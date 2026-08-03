Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-NrAbsoluteUri {
    param([Parameter(Mandatory)][Uri]$BaseUri,[Parameter(Mandatory)][string]$Reference)
    $candidate=$Reference.Trim()
    if ([string]::IsNullOrWhiteSpace($candidate)) { throw 'URI reference is empty.' }
    $absolute=$null
    if ([Uri]::TryCreate($candidate,[UriKind]::Absolute,[ref]$absolute)) { return $absolute }
    return [Uri]::new($BaseUri,$candidate)
}

function Get-NrHlsReferences {
    param([Parameter(Mandatory)][string]$Playlist)
    $references=New-Object 'System.Collections.Generic.List[string]'
    foreach ($raw in ($Playlist -split "`r?`n")) {
        $line=$raw.Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }
        $references.Add($line)
    }
    return $references.ToArray()
}

function Get-NrHlsVariantReference {
    param([Parameter(Mandatory)][string]$Playlist)
    $lines=@($Playlist -split "`r?`n")
    for ($index=0;$index -lt $lines.Count;$index++) {
        if ($lines[$index].Trim() -notmatch '^#EXT-X-STREAM-INF:') { continue }
        for ($next=$index+1;$next -lt $lines.Count;$next++) {
            $candidate=$lines[$next].Trim()
            if (-not $candidate) { continue }
            if ($candidate.StartsWith('#')) { break }
            return $candidate
        }
    }
    return $null
}

function New-NrHttpClient {
    param([int]$TimeoutSeconds=30)
    $handler=[Net.Http.HttpClientHandler]::new()
    $handler.AutomaticDecompression=[Net.DecompressionMethods]::GZip -bor [Net.DecompressionMethods]::Deflate
    $client=[Net.Http.HttpClient]::new($handler,$true)
    $client.Timeout=[TimeSpan]::FromSeconds([Math]::Max(1,$TimeoutSeconds))
    $client.DefaultRequestHeaders.UserAgent.ParseAdd('NexRoute-Media-Probe/0.6.0')
    $client.DefaultRequestHeaders.CacheControl=[Net.Http.Headers.CacheControlHeaderValue]::new()
    $client.DefaultRequestHeaders.CacheControl.NoCache=$true
    return $client
}

function Measure-NrStreamingDownload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][Uri]$Uri,
        [long]$TargetBytes=8388608,
        [int]$TimeoutSeconds=30,
        [int]$BufferBytes=65536
    )
    if ($TargetBytes -lt 1048576) { throw 'TargetBytes must be at least 1 MiB.' }
    if ($BufferBytes -lt 4096) { throw 'BufferBytes must be at least 4096.' }
    $client=New-NrHttpClient -TimeoutSeconds $TimeoutSeconds
    $response=$null; $stream=$null
    $watch=[Diagnostics.Stopwatch]::StartNew()
    $readTotal=[long]0
    try {
        $response=$client.GetAsync($Uri,[Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        $response.EnsureSuccessStatusCode() | Out-Null
        $stream=$response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $buffer=New-Object byte[] $BufferBytes
        while ($readTotal -lt $TargetBytes) {
            $remaining=[int][Math]::Min([long]$buffer.Length,$TargetBytes-$readTotal)
            $read=$stream.Read($buffer,0,$remaining)
            if ($read -le 0) { break }
            $readTotal += $read
        }
        $watch.Stop()
        $seconds=[Math]::Max($watch.Elapsed.TotalSeconds,0.001)
        $mbps=[Math]::Round((($readTotal*8.0)/$seconds/1000000.0),3)
        return [pscustomobject]@{
            uri=$Uri.AbsoluteUri
            ok=($readTotal -ge $TargetBytes)
            requestedBytes=$TargetBytes
            receivedBytes=$readTotal
            elapsedMs=[Math]::Round($watch.Elapsed.TotalMilliseconds,2)
            megabitsPerSecond=$mbps
            statusCode=[int]$response.StatusCode
        }
    } finally {
        if ($stream) { $stream.Dispose() }
        if ($response) { $response.Dispose() }
        $client.Dispose()
    }
}

function Test-NrHlsPlaybackReadiness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][Uri]$ManifestUri,
        [int]$TimeoutSeconds=20,
        [long]$MinimumSegmentBytes=1024
    )
    $client=New-NrHttpClient -TimeoutSeconds $TimeoutSeconds
    $watch=[Diagnostics.Stopwatch]::StartNew()
    try {
        $master=$client.GetStringAsync($ManifestUri).GetAwaiter().GetResult()
        if ($master -notmatch '^\s*#EXTM3U') { throw 'The response is not an HLS playlist.' }
        $mediaUri=$ManifestUri
        $variant=Get-NrHlsVariantReference -Playlist $master
        $media=$master
        if ($variant) {
            $mediaUri=Resolve-NrAbsoluteUri -BaseUri $ManifestUri -Reference $variant
            $media=$client.GetStringAsync($mediaUri).GetAwaiter().GetResult()
            if ($media -notmatch '^\s*#EXTM3U') { throw 'The HLS variant is not a playlist.' }
        }
        $references=@(Get-NrHlsReferences -Playlist $media)
        if ($references.Count -eq 0) { throw 'The HLS media playlist contains no segments.' }
        $segmentUri=Resolve-NrAbsoluteUri -BaseUri $mediaUri -Reference $references[0]
        $segmentResponse=$client.GetAsync($segmentUri,[Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        try {
            $segmentResponse.EnsureSuccessStatusCode() | Out-Null
            $bytes=$segmentResponse.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
        } finally { $segmentResponse.Dispose() }
        $watch.Stop()
        return [pscustomobject]@{
            ok=($bytes.Length -ge $MinimumSegmentBytes)
            manifestUri=$ManifestUri.AbsoluteUri
            mediaPlaylistUri=$mediaUri.AbsoluteUri
            segmentUri=$segmentUri.AbsoluteUri
            segmentBytes=$bytes.Length
            elapsedMs=[Math]::Round($watch.Elapsed.TotalMilliseconds,2)
            usedMasterPlaylist=[bool]$variant
        }
    } finally { $client.Dispose() }
}

function Test-NrTlsTransportReadiness {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$HostName,[int]$Port=443,[int]$TimeoutSeconds=10)
    $client=[Net.Sockets.TcpClient]::new()
    $watch=[Diagnostics.Stopwatch]::StartNew()
    try {
        $connect=$client.ConnectAsync($HostName,$Port)
        if (-not $connect.Wait($TimeoutSeconds*1000)) { throw 'TCP connection timed out.' }
        $ssl=[Net.Security.SslStream]::new($client.GetStream(),$false,({ $true }))
        try {
            $auth=$ssl.AuthenticateAsClientAsync($HostName)
            if (-not $auth.Wait($TimeoutSeconds*1000)) { throw 'TLS handshake timed out.' }
            $watch.Stop()
            return [pscustomobject]@{ ok=$ssl.IsAuthenticated; host=$HostName; port=$Port; elapsedMs=[Math]::Round($watch.Elapsed.TotalMilliseconds,2); protocol=[string]$ssl.SslProtocol }
        } finally { $ssl.Dispose() }
    } catch {
        $watch.Stop()
        return [pscustomobject]@{ ok=$false; host=$HostName; port=$Port; elapsedMs=[Math]::Round($watch.Elapsed.TotalMilliseconds,2); protocol=$null; error=$_.Exception.Message }
    } finally { $client.Dispose() }
}
