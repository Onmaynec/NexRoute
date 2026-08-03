Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function ConvertTo-NrProbeAddressFamily {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('ipv4','ipv6')][string]$Family)
    if ($Family -eq 'ipv6') { return [Net.Sockets.AddressFamily]::InterNetworkV6 }
    return [Net.Sockets.AddressFamily]::InterNetwork
}

function Resolve-NrProbeAddresses {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$HostName,
        [Parameter(Mandatory)][ValidateSet('ipv4','ipv6')][string]$Family,
        [scriptblock]$Resolver
    )
    $targetFamily=ConvertTo-NrProbeAddressFamily -Family $Family
    $literal=$null
    if ([Net.IPAddress]::TryParse($HostName,[ref]$literal)) {
        if ($literal.AddressFamily -ne $targetFamily) { return [Net.IPAddress[]]@() }
        return [Net.IPAddress[]]@($literal)
    }
    $addresses=if ($Resolver) { @(& $Resolver $HostName) } else { @([Net.Dns]::GetHostAddresses($HostName)) }
    return [Net.IPAddress[]]@($addresses | Where-Object { $_ -and $_.AddressFamily -eq $targetFamily } | Sort-Object IPAddressToString -Unique)
}

function Connect-NrFamilyTcpClient {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][Net.IPAddress]$Address,
        [Parameter(Mandatory)][ValidateRange(1,65535)][int]$Port,
        [ValidateRange(1,120)][int]$TimeoutSeconds=8,
        [scriptblock]$Connector
    )
    if ($Connector) { return & $Connector $Address $Port $TimeoutSeconds }
    $client=[Net.Sockets.TcpClient]::new($Address.AddressFamily)
    try {
        $client.ReceiveTimeout=$TimeoutSeconds*1000
        $client.SendTimeout=$TimeoutSeconds*1000
        $task=$client.ConnectAsync($Address,$Port)
        if (-not $task.Wait($TimeoutSeconds*1000)) {
            $client.Dispose()
            throw "TCP connect timed out after $TimeoutSeconds second(s)."
        }
        if ($task.IsFaulted) { throw $task.Exception.GetBaseException() }
        if (-not $client.Connected) { throw 'TCP connection did not reach the connected state.' }
        return $client
    } catch {
        if ($client) { $client.Dispose() }
        throw
    }
}

function Set-NrStreamTimeouts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][IO.Stream]$Stream,
        [ValidateRange(1,120)][int]$TimeoutSeconds=8,
        [switch]$Read,
        [switch]$Write
    )
    if (-not $Stream.CanTimeout) { return }
    if ($Read) { $Stream.ReadTimeout=$TimeoutSeconds*1000 }
    if ($Write) { $Stream.WriteTimeout=$TimeoutSeconds*1000 }
}

function Read-NrHttpStatusLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][IO.Stream]$Stream,
        [ValidateRange(1,120)][int]$TimeoutSeconds=8
    )
    Set-NrStreamTimeouts -Stream $Stream -TimeoutSeconds $TimeoutSeconds -Read
    $bytes=New-Object 'System.Collections.Generic.List[byte]'
    while ($bytes.Count -lt 4096) {
        $value=$Stream.ReadByte()
        if ($value -lt 0) { break }
        $bytes.Add([byte]$value)
        if ($bytes.Count -ge 2 -and $bytes[$bytes.Count-2] -eq 13 -and $bytes[$bytes.Count-1] -eq 10) { break }
    }
    if ($bytes.Count -eq 0) { throw 'HTTP probe returned no status line.' }
    return [Text.Encoding]::ASCII.GetString($bytes.ToArray()).TrimEnd("`r","`n")
}

function Invoke-NrAddressFamilyProbe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][Uri]$Uri,
        [Parameter(Mandatory)][ValidateSet('ipv4','ipv6')][string]$Family,
        [ValidateRange(1,120)][int]$TimeoutSeconds=8,
        [scriptblock]$Resolver,
        [scriptblock]$Connector,
        [scriptblock]$TlsFactory
    )
    $started=[Diagnostics.Stopwatch]::StartNew()
    $addresses=@()
    try {
        $addresses=@(Resolve-NrProbeAddresses -HostName $Uri.DnsSafeHost -Family $Family -Resolver $Resolver)
        if ($addresses.Count -eq 0) {
            return [pscustomobject][ordered]@{
                ok=$false; family=$Family; scheme=$Uri.Scheme; host=$Uri.DnsSafeHost; address=$null
                port=$Uri.Port; statusCode=$null; elapsedMs=[Math]::Round($started.Elapsed.TotalMilliseconds,2)
                reason="No $Family address is available for $($Uri.DnsSafeHost)."
            }
        }
        $lastError=$null
        foreach ($address in $addresses) {
            $client=$null
            $stream=$null
            try {
                $port=if ($Uri.Port -gt 0) { $Uri.Port } elseif ($Uri.Scheme -eq 'https') { 443 } elseif ($Uri.Scheme -eq 'http') { 80 } else { throw 'Probe URI has no port.' }
                $client=Connect-NrFamilyTcpClient -Address $address -Port $port -TimeoutSeconds $TimeoutSeconds -Connector $Connector
                if ($Uri.Scheme -eq 'tcp') {
                    return [pscustomobject][ordered]@{
                        ok=$true; family=$Family; scheme='tcp'; host=$Uri.DnsSafeHost; address=$address.IPAddressToString
                        port=$port; statusCode=$null; elapsedMs=[Math]::Round($started.Elapsed.TotalMilliseconds,2); reason=$null
                    }
                }
                if ($Uri.Scheme -notin @('http','https')) { throw "Unsupported probe scheme: $($Uri.Scheme)" }
                $stream=$client.GetStream()
                if ($Uri.Scheme -eq 'https') {
                    if ($TlsFactory) { $stream=& $TlsFactory $stream $Uri.DnsSafeHost $TimeoutSeconds }
                    else {
                        $ssl=[Net.Security.SslStream]::new($stream,$false)
                        Set-NrStreamTimeouts -Stream $ssl -TimeoutSeconds $TimeoutSeconds -Read -Write
                        $ssl.AuthenticateAsClient($Uri.DnsSafeHost)
                        $stream=$ssl
                    }
                }
                $path=if ([string]::IsNullOrWhiteSpace($Uri.PathAndQuery)) { '/' } else { $Uri.PathAndQuery }
                $request="GET $path HTTP/1.1`r`nHost: $($Uri.DnsSafeHost)`r`nUser-Agent: NexRoute-WorkerHost/0.6.0`r`nAccept: */*`r`nCache-Control: no-cache`r`nConnection: close`r`n`r`n"
                $requestBytes=[Text.Encoding]::ASCII.GetBytes($request)
                Set-NrStreamTimeouts -Stream $stream -TimeoutSeconds $TimeoutSeconds -Write
                $stream.Write($requestBytes,0,$requestBytes.Length)
                $stream.Flush()
                $statusLine=Read-NrHttpStatusLine -Stream $stream -TimeoutSeconds $TimeoutSeconds
                if ($statusLine -notmatch '^HTTP/\d(?:\.\d)?\s+(?<code>\d{3})(?:\s|$)') { throw "Invalid HTTP status line: $statusLine" }
                $statusCode=[int]$Matches['code']
                return [pscustomobject][ordered]@{
                    ok=($statusCode -ge 200 -and $statusCode -lt 500); family=$Family; scheme=$Uri.Scheme
                    host=$Uri.DnsSafeHost; address=$address.IPAddressToString; port=$port; statusCode=$statusCode
                    elapsedMs=[Math]::Round($started.Elapsed.TotalMilliseconds,2); reason=if ($statusCode -ge 200 -and $statusCode -lt 500) { $null } else { "HTTP status $statusCode" }
                }
            } catch {
                $lastError=$_.Exception.Message
            } finally {
                if ($stream) { try { $stream.Dispose() } catch { } }
                if ($client) { try { $client.Dispose() } catch { } }
            }
        }
        return [pscustomobject][ordered]@{
            ok=$false; family=$Family; scheme=$Uri.Scheme; host=$Uri.DnsSafeHost
            address=($addresses | Select-Object -Last 1).IPAddressToString; port=$Uri.Port; statusCode=$null
            elapsedMs=[Math]::Round($started.Elapsed.TotalMilliseconds,2); reason=$lastError
        }
    } catch {
        return [pscustomobject][ordered]@{
            ok=$false; family=$Family; scheme=$Uri.Scheme; host=$Uri.DnsSafeHost; address=$null
            port=$Uri.Port; statusCode=$null; elapsedMs=[Math]::Round($started.Elapsed.TotalMilliseconds,2); reason=$_.Exception.Message
        }
    } finally {
        $started.Stop()
    }
}

function Test-NrAddressFamilyProbe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][Uri]$Uri,
        [Parameter(Mandatory)][ValidateSet('ipv4','ipv6')][string]$Family,
        [ValidateRange(1,120)][int]$TimeoutSeconds=8,
        [scriptblock]$Resolver,
        [scriptblock]$Connector,
        [scriptblock]$TlsFactory
    )
    $result=Invoke-NrAddressFamilyProbe -Uri $Uri -Family $Family -TimeoutSeconds $TimeoutSeconds -Resolver $Resolver -Connector $Connector -TlsFactory $TlsFactory
    return [bool]$result.ok
}
