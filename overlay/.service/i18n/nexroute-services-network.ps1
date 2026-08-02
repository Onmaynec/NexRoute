# Internal NexRoute Service Matrix module. Dot-sourced by nexroute-services.ps1.

function Get-EndpointHost {
    param($Target)
    if ($null -eq $Target -or -not $Target.url) { return $null }
    try { return ([Uri][string]$Target.url).DnsSafeHost } catch { return $null }
}

function ConvertTo-ValidatedIpCidr {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $parts = $Value.Trim().Split('/')
    if ($parts.Count -ne 2) { return $null }

    $address = $null
    if (-not [System.Net.IPAddress]::TryParse($parts[0], [ref]$address)) { return $null }
    $prefix = 0
    if (-not [int]::TryParse($parts[1], [ref]$prefix)) { return $null }
    $maximum = if ($address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) { 32 } elseif ($address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6) { 128 } else { return $null }
    if ($prefix -lt 0 -or $prefix -gt $maximum) { return $null }
    return ('{0}/{1}' -f $address.IPAddressToString, $prefix)
}

# Compatibility alias retained for older modules and repository contracts.
function ConvertTo-ValidatedIpv4Cidr {
    param([string]$Value)
    $cidr = ConvertTo-ValidatedIpCidr -Value $Value
    if (-not $cidr) { return $null }
    $address = $null
    if (-not [System.Net.IPAddress]::TryParse(($cidr -split '/',2)[0], [ref]$address)) { return $null }
    if ($address.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) { return $null }
    return $cidr
}

function ConvertTo-ValidatedPort {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $text = $Value.Trim()
    if ($text -match '^(\d{1,5})$') {
        $port = [int]$matches[1]
        if ($port -ge 1 -and $port -le 65535) { return [string]$port }
        return $null
    }
    if ($text -match '^(\d{1,5})-(\d{1,5})$') {
        $start = [int]$matches[1]
        $end = [int]$matches[2]
        if ($start -ge 1 -and $end -le 65535 -and $start -le $end) { return ('{0}-{1}' -f $start, $end) }
    }
    return $null
}

function Get-PortText {
    param([string[]]$Ports, [string]$Fallback = '65535')
    $values = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($port in @($Ports)) {
        $validated = ConvertTo-ValidatedPort -Value ([string]$port)
        if ($validated) { [void]$values.Add($validated) }
    }
    $result = @($values | Sort-Object)
    if ($result.Count -eq 0) { return $Fallback }
    return ($result -join ',')
}

function Get-ResolvedIpEntries {
    param([Parameter(Mandatory)][string[]]$Hosts)
    $entries = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($hostName in @($Hosts | Where-Object { $_ } | Sort-Object -Unique)) {
        try {
            $addresses = @()
            if (Get-Command Resolve-DnsName -ErrorAction SilentlyContinue) {
                $addresses = @(
                    Resolve-DnsName -Name $hostName -Type A -DnsOnly -ErrorAction SilentlyContinue
                    Resolve-DnsName -Name $hostName -Type AAAA -DnsOnly -ErrorAction SilentlyContinue
                ) | Where-Object { $_.IPAddress } | ForEach-Object { $_.IPAddress }
            }
            else {
                $addresses = @([System.Net.Dns]::GetHostAddresses($hostName) | ForEach-Object { $_.IPAddressToString })
            }
            foreach ($addressText in $addresses) {
                $address = $null
                if (-not [System.Net.IPAddress]::TryParse([string]$addressText, [ref]$address)) { continue }
                $prefix = if ($address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) { 32 } else { 128 }
                $cidr = ConvertTo-ValidatedIpCidr -Value ("$addressText/$prefix")
                if ($cidr) { [void]$entries.Add($cidr) }
            }
        }
        catch { }
    }
    return [string[]]@($entries | ForEach-Object { $_ })
}

function Get-ResolvedIpv4Entries {
    param([Parameter(Mandatory)][string[]]$Hosts)
    return [string[]]@(Get-ResolvedIpEntries -Hosts $Hosts | Where-Object {
        $address = $null
        [System.Net.IPAddress]::TryParse(($_ -split '/',2)[0], [ref]$address) -and $address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork
    })
}

function Get-StringHash {
    param([Parameter(Mandatory)][string]$Value)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
        return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '')
    }
    finally { $sha.Dispose() }
}

function Get-CachedSourceEntries {
    param([Parameter(Mandatory)][string]$Source)
    $key = Get-StringHash -Value $Source
    $dataPath = Join-Path $cacheDirectory ($key + '.txt')
    $metaPath = Join-Path $cacheDirectory ($key + '.json')
    if (-not (Test-Path -LiteralPath $dataPath -PathType Leaf) -or -not (Test-Path -LiteralPath $metaPath -PathType Leaf)) {
        return [pscustomobject]@{ Entries = [string[]]@(); Usable = $false; AgeDays = $null; DataPath = $dataPath; MetaPath = $metaPath }
    }

    try {
        $meta = Read-JsonFile -Path $metaPath
        $fetchedAt = [DateTime]::Parse([string]$meta.fetchedAtUtc).ToUniversalTime()
        $ageDays = ([DateTime]::UtcNow - $fetchedAt).TotalDays
        $entries = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($line in @(Get-Content -LiteralPath $dataPath -Encoding UTF8)) {
            $cidr = ConvertTo-ValidatedIpCidr -Value $line
            if ($cidr) { [void]$entries.Add($cidr) }
        }
        $entryArray = [string[]]@($entries | ForEach-Object { $_ })
        return [pscustomobject]@{
            Entries = $entryArray
            Usable = ($ageDays -le $sourceCacheMaxAgeDays -and $entryArray.Count -gt 0)
            AgeDays = [math]::Round($ageDays, 2)
            DataPath = $dataPath
            MetaPath = $metaPath
        }
    }
    catch {
        return [pscustomobject]@{ Entries = [string[]]@(); Usable = $false; AgeDays = $null; DataPath = $dataPath; MetaPath = $metaPath }
    }
}

function Save-SourceCache {
    param([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string[]]$Entries)
    if (-not (Test-Path -LiteralPath $cacheDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $cacheDirectory -Force | Out-Null
    }
    $key = Get-StringHash -Value $Source
    $dataPath = Join-Path $cacheDirectory ($key + '.txt')
    $metaPath = Join-Path $cacheDirectory ($key + '.json')
    $values = @($Entries | Sort-Object -Unique)
    Write-Utf8NoBom -Path $dataPath -Content (($values -join "`r`n") + "`r`n")
    $contentHash = Get-StringHash -Value ($values -join "`n")
    Write-JsonFile -Path $metaPath -Value ([ordered]@{
        source = $Source
        fetchedAtUtc = [DateTime]::UtcNow.ToString('o')
        sha256 = $contentHash
        count = $values.Count
    }) -Depth 4
}

function Get-RemoteIpEntries {
    param([string[]]$Sources)
    $entries = New-Object 'System.Collections.Generic.HashSet[string]'
    $statuses = New-Object 'System.Collections.Generic.List[object]'

    foreach ($sourceValue in @($Sources | Where-Object { $_ } | Sort-Object -Unique)) {
        $source = [string]$sourceValue
        $cache = Get-CachedSourceEntries -Source $source
        $sourceEntries = [string[]]@()
        $status = 'failed'
        $message = $null

        try {
            $response = Invoke-WebRequest -Uri $source -UseBasicParsing -TimeoutSec 8
            $validated = New-Object 'System.Collections.Generic.HashSet[string]'
            foreach ($line in @([string]$response.Content -split "`r?`n")) {
                $candidate = ($line -split '[#;]', 2)[0].Trim()
                $cidr = ConvertTo-ValidatedIpCidr -Value $candidate
                if ($cidr) { [void]$validated.Add($cidr) }
            }
            $sourceEntries = [string[]]@($validated | ForEach-Object { $_ })
            if ($sourceEntries.Count -eq 0) { throw 'The source returned no valid IPv4 or IPv6 CIDR entries.' }
            Save-SourceCache -Source $source -Entries $sourceEntries
            $status = 'fresh'
        }
        catch {
            $message = $_.Exception.Message
            if ($cache.Usable) {
                $sourceEntries = [string[]]$cache.Entries
                $status = 'cache'
                Write-Warning "Using cached service IP source '$source' ($($cache.AgeDays) days old): $message"
            }
            else {
                Write-Warning "Unable to refresh service IP source '$source': $message"
            }
        }

        foreach ($entry in $sourceEntries) { [void]$entries.Add($entry) }
        $statuses.Add([pscustomobject]@{
            source = $source
            status = $status
            count = $sourceEntries.Count
            cacheAgeDays = $cache.AgeDays
            message = $message
        })
    }

    return [pscustomobject]@{
        Entries = [string[]]@($entries | ForEach-Object { $_ })
        Statuses = [object[]]$statuses.ToArray()
    }
}
