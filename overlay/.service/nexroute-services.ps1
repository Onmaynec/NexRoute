[CmdletBinding()]
param(
    [ValidateSet('Apply', 'Summary', 'Reset', 'Validate', 'TestTargets', 'Restart', 'Diagnostics')]
    [string]$Mode = 'Apply',
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [string]$DiagnosticsPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$serviceDirectory = $PSScriptRoot
$definitionPath = Join-Path $serviceDirectory 'services.json'
$statePath = Join-Path $serviceDirectory 'services-state.json'
$runtimePath = Join-Path $serviceDirectory 'services-runtime.cmd'
$sourceStatusPath = Join-Path $serviceDirectory 'ip-source-status.json'
$cacheDirectory = Join-Path $serviceDirectory 'cache\ip-sources'
$listsDirectory = Join-Path $Root 'lists'
$generalUserPath = Join-Path $listsDirectory 'list-general-user.txt'
$excludeUserPath = Join-Path $listsDirectory 'list-exclude-user.txt'
$enabledListPath = Join-Path $listsDirectory 'list-services-enabled.txt'
$serviceIpsetPath = Join-Path $listsDirectory 'ipset-services-user.txt'
$versionPath = Join-Path $serviceDirectory 'version.txt'
$stateSchemaVersion = 2
$sourceCacheMaxAgeDays = 14

$generalBegin = '# NEXROUTE-SERVICES-BEGIN'
$generalEnd = '# NEXROUTE-SERVICES-END'
$excludeBegin = '# NEXROUTE-DISABLED-SERVICES-BEGIN'
$excludeEnd = '# NEXROUTE-DISABLED-SERVICES-END'

function Write-Utf8NoBom {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Content)
    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

function Write-JsonFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Value, [int]$Depth = 8)
    Write-Utf8NoBom -Path $Path -Content (($Value | ConvertTo-Json -Depth $Depth) + [Environment]::NewLine)
}

function Read-JsonFile {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required JSON file was not found: $Path"
    }
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Get-ServiceDefinitions {
    $document = Read-JsonFile -Path $definitionPath
    if ([int]$document.schemaVersion -ne 2) { throw "Unsupported services.json schema: $($document.schemaVersion)" }
    if (-not $document.services -or @($document.services).Count -eq 0) {
        throw 'services.json does not contain service definitions.'
    }
    return @($document.services)
}

function New-DefaultState {
    param([Parameter(Mandatory)][array]$Definitions)
    $state = [ordered]@{}
    foreach ($service in $Definitions) { $state[$service.id] = [bool]$service.defaultEnabled }
    return $state
}

function Backup-ServiceState {
    param([Parameter(Mandatory)][string]$FileName)
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { return }
    $backupPath = Join-Path $serviceDirectory $FileName
    if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
        Copy-Item -LiteralPath $statePath -Destination $backupPath -Force
    }
}

function Get-ServiceStateResult {
    param([Parameter(Mandatory)][array]$Definitions)

    $state = New-DefaultState -Definitions $Definitions
    $migrated = $false
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        return [pscustomobject]@{ State = $state; Migrated = $false; Invalid = $false; Exists = $false }
    }

    $invalid = $false
    try {
        $saved = Read-JsonFile -Path $statePath
        $savedServices = $null
        if ($saved.PSObject.Properties['services']) {
            $savedServices = $saved.services
        }
        else {
            $savedServices = $saved
            $migrated = $true
        }

        foreach ($service in $Definitions) {
            $property = $savedServices.PSObject.Properties[$service.id]
            if ($null -ne $property) { $state[$service.id] = [bool]$property.Value }
        }
    }
    catch {
        $invalid = $true
        Write-Warning "Ignoring invalid service state: $($_.Exception.Message)"
    }

    return [pscustomobject]@{ State = $state; Migrated = $migrated; Invalid = $invalid; Exists = $true }
}

function Save-ServiceState {
    param([Parameter(Mandatory)]$State)
    $document = [ordered]@{
        schemaVersion = $stateSchemaVersion
        updatedAtUtc = [DateTime]::UtcNow.ToString('o')
        services = $State
    }
    Write-JsonFile -Path $statePath -Value $document -Depth 6
}

function Ensure-ListFile {
    param([Parameter(Mandatory)][string]$Path)
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Write-Utf8NoBom -Path $Path -Content "# User-managed entries`r`n"
    }
}

function Set-ManagedBlock {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$BeginMarker,
        [Parameter(Mandatory)][string]$EndMarker,
        [Parameter(Mandatory)][string[]]$Values
    )

    Ensure-ListFile -Path $Path
    $sourceLines = @(Get-Content -LiteralPath $Path -Encoding UTF8)
    $output = New-Object 'System.Collections.Generic.List[string]'
    $inside = $false
    foreach ($line in $sourceLines) {
        if ($line.Trim() -eq $BeginMarker) { $inside = $true; continue }
        if ($line.Trim() -eq $EndMarker) { $inside = $false; continue }
        if (-not $inside) { $output.Add($line) }
    }

    while ($output.Count -gt 0 -and [string]::IsNullOrWhiteSpace($output[$output.Count - 1])) {
        $output.RemoveAt($output.Count - 1)
    }

    $output.Add('')
    $output.Add($BeginMarker)
    foreach ($value in @($Values | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)) {
        $output.Add(([string]$value).ToLowerInvariant())
    }
    $output.Add($EndMarker)
    $output.Add('')
    Write-Utf8NoBom -Path $Path -Content (($output.ToArray() -join "`r`n") + "`r`n")
}

function Get-EndpointHost {
    param($Target)
    if ($null -eq $Target -or -not $Target.url) { return $null }
    try { return ([Uri][string]$Target.url).DnsSafeHost } catch { return $null }
}

function ConvertTo-ValidatedIpv4Cidr {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $parts = $Value.Trim().Split('/')
    if ($parts.Count -ne 2) { return $null }

    $address = $null
    if (-not [System.Net.IPAddress]::TryParse($parts[0], [ref]$address)) { return $null }
    if ($address.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) { return $null }

    $prefix = 0
    if (-not [int]::TryParse($parts[1], [ref]$prefix)) { return $null }
    if ($prefix -lt 0 -or $prefix -gt 32) { return $null }
    return ('{0}/{1}' -f $address.IPAddressToString, $prefix)
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

function Get-ResolvedIpv4Entries {
    param([Parameter(Mandatory)][string[]]$Hosts)
    $entries = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($hostName in @($Hosts | Where-Object { $_ } | Sort-Object -Unique)) {
        try {
            $addresses = @()
            if (Get-Command Resolve-DnsName -ErrorAction SilentlyContinue) {
                $addresses = @(Resolve-DnsName -Name $hostName -Type A -DnsOnly -ErrorAction Stop | Where-Object { $_.IPAddress } | ForEach-Object { $_.IPAddress })
            }
            else {
                $addresses = @([System.Net.Dns]::GetHostAddresses($hostName) | Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork } | ForEach-Object { $_.IPAddressToString })
            }
            foreach ($address in $addresses) {
                $cidr = ConvertTo-ValidatedIpv4Cidr -Value ("$address/32")
                if ($cidr) { [void]$entries.Add($cidr) }
            }
        }
        catch { }
    }
    return @($entries)
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
        return [pscustomobject]@{ Entries = @(); Usable = $false; AgeDays = $null; DataPath = $dataPath; MetaPath = $metaPath }
    }

    try {
        $meta = Read-JsonFile -Path $metaPath
        $fetchedAt = [DateTime]::Parse([string]$meta.fetchedAtUtc).ToUniversalTime()
        $ageDays = ([DateTime]::UtcNow - $fetchedAt).TotalDays
        $entries = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($line in @(Get-Content -LiteralPath $dataPath -Encoding UTF8)) {
            $cidr = ConvertTo-ValidatedIpv4Cidr -Value $line
            if ($cidr) { [void]$entries.Add($cidr) }
        }
        return [pscustomobject]@{
            Entries = @($entries)
            Usable = ($ageDays -le $sourceCacheMaxAgeDays -and $entries.Count -gt 0)
            AgeDays = [math]::Round($ageDays, 2)
            DataPath = $dataPath
            MetaPath = $metaPath
        }
    }
    catch {
        return [pscustomobject]@{ Entries = @(); Usable = $false; AgeDays = $null; DataPath = $dataPath; MetaPath = $metaPath }
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
        $sourceEntries = @()
        $status = 'failed'
        $message = $null

        try {
            $response = Invoke-WebRequest -Uri $source -UseBasicParsing -TimeoutSec 8
            $validated = New-Object 'System.Collections.Generic.HashSet[string]'
            foreach ($line in @([string]$response.Content -split "`r?`n")) {
                $candidate = ($line -split '[#;]', 2)[0].Trim()
                $cidr = ConvertTo-ValidatedIpv4Cidr -Value $candidate
                if ($cidr) { [void]$validated.Add($cidr) }
            }
            $sourceEntries = @($validated)
            if ($sourceEntries.Count -eq 0) { throw 'The source returned no valid IPv4 CIDR entries.' }
            Save-SourceCache -Source $source -Entries $sourceEntries
            $status = 'fresh'
        }
        catch {
            $message = $_.Exception.Message
            if ($cache.Usable) {
                $sourceEntries = @($cache.Entries)
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

    return [pscustomobject]@{ Entries = @($entries); Statuses = @($statuses) }
}

function Get-SafeServiceId {
    param([Parameter(Mandatory)][string]$Value)
    $safe = $Value.ToLowerInvariant() -replace '[^a-z0-9_-]', '-'
    if ([string]::IsNullOrWhiteSpace($safe)) { throw "Invalid service id: $Value" }
    return $safe
}

function Write-ServiceRuntime {
    param([Parameter(Mandatory)][array]$RuntimeServices)

    $bin = Join-Path $Root 'bin'
    $tlsPattern = Join-Path $bin 'tls_clienthello_4pda_to.bin'
    $quicPattern = Join-Path $bin 'quic_initial_www_google_com.bin'
    $tcpBlocks = New-Object 'System.Collections.Generic.List[string]'
    $udpBlocks = New-Object 'System.Collections.Generic.List[string]'
    $allTcpPorts = New-Object 'System.Collections.Generic.List[string]'
    $allUdpPorts = New-Object 'System.Collections.Generic.List[string]'

    foreach ($item in $RuntimeServices) {
        $tcpText = Get-PortText -Ports @($item.TcpPorts) -Fallback ''
        $udpText = Get-PortText -Ports @($item.UdpPorts) -Fallback ''
        foreach ($port in @($item.TcpPorts)) { if ($port) { $allTcpPorts.Add([string]$port) } }
        foreach ($port in @($item.UdpPorts)) { if ($port) { $allUdpPorts.Add([string]$port) } }

        if ($tcpText) {
            if ([bool]$item.HasDomains) {
                $tcpBlocks.Add(('--filter-tcp={0} --hostlist="{1}" --dpi-desync=multisplit --dpi-desync-split-seqovl=568 --dpi-desync-split-pos=1 --dpi-desync-split-seqovl-pattern="{2}" --new' -f $tcpText, $item.HostList, $tlsPattern))
            }
            if ([bool]$item.HasIps) {
                $tcpBlocks.Add(('--filter-tcp={0} --ipset="{1}" --dpi-desync=multisplit --dpi-desync-split-seqovl=568 --dpi-desync-split-pos=1 --dpi-desync-split-seqovl-pattern="{2}" --new' -f $tcpText, $item.IpSet, $tlsPattern))
            }
        }

        if ($udpText) {
            if ([bool]$item.HasDomains) {
                $udpBlocks.Add(('--filter-udp={0} --hostlist="{1}" --dpi-desync=fake --dpi-desync-repeats=8 --dpi-desync-fake-quic="{2}" --new' -f $udpText, $item.HostList, $quicPattern))
            }
            if ([bool]$item.HasIps) {
                $udpBlocks.Add(('--filter-udp={0} --ipset="{1}" --dpi-desync=fake --dpi-desync-repeats=8 --dpi-desync-fake-quic="{2}" --new' -f $udpText, $item.IpSet, $quicPattern))
            }
        }
    }

    $tcpArgs = if ($tcpBlocks.Count -gt 0) { $tcpBlocks.ToArray() -join ' ' } else { '--filter-tcp=65535 --hostlist="' + $enabledListPath + '" --new' }
    $udpArgs = if ($udpBlocks.Count -gt 0) { $udpBlocks.ToArray() -join ' ' } else { '--filter-udp=65535 --hostlist="' + $enabledListPath + '" --new' }
    $lines = @(
        '@echo off',
        'rem Generated by NexRoute 0.2.3 Service Matrix. Do not edit.',
        ('set "NEXROUTE_ENABLED_SERVICE_COUNT={0}"' -f $RuntimeServices.Count),
        ('set "NEXROUTE_EXTRA_TCP_PORTS={0}"' -f (Get-PortText -Ports $allTcpPorts.ToArray())),
        ('set "NEXROUTE_EXTRA_UDP_PORTS={0}"' -f (Get-PortText -Ports $allUdpPorts.ToArray())),
        ('set "NEXROUTE_SERVICE_TCP_ARGS={0}"' -f $tcpArgs),
        ('set "NEXROUTE_SERVICE_UDP_ARGS={0}"' -f $udpArgs)
    )
    [System.IO.File]::WriteAllLines($runtimePath, $lines, [System.Text.Encoding]::ASCII)
}

function Remove-StaleServiceLists {
    param([Parameter(Mandatory)][string[]]$KeepPaths)
    if (-not (Test-Path -LiteralPath $listsDirectory -PathType Container)) { return }
    foreach ($file in @(Get-ChildItem -LiteralPath $listsDirectory -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(list|ipset)-service-[a-z0-9_-]+\.txt$' })) {
        if ($KeepPaths -notcontains $file.FullName) { Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue }
    }
}

function Apply-ServiceMatrix {
    param([Parameter(Mandatory)][array]$Definitions, [Parameter(Mandatory)]$State)

    $enabledDomains = New-Object 'System.Collections.Generic.HashSet[string]'
    $allDomains = New-Object 'System.Collections.Generic.HashSet[string]'
    $enabledIds = New-Object 'System.Collections.Generic.List[string]'
    $runtimeServices = New-Object 'System.Collections.Generic.List[object]'
    $allIps = New-Object 'System.Collections.Generic.HashSet[string]'
    $allSourceStatuses = New-Object 'System.Collections.Generic.List[object]'
    $keepPaths = New-Object 'System.Collections.Generic.List[string]'

    foreach ($service in $Definitions) {
        foreach ($domainValue in @($service.domains)) {
            if ([string]::IsNullOrWhiteSpace([string]$domainValue)) { continue }
            $domain = ([string]$domainValue).Trim().ToLowerInvariant()
            [void]$allDomains.Add($domain)
            if ([bool]$State[$service.id]) { [void]$enabledDomains.Add($domain) }
        }
    }

    $disabledDomains = @($allDomains | Where-Object { -not $enabledDomains.Contains($_) } | Sort-Object)
    Set-ManagedBlock -Path $generalUserPath -BeginMarker $generalBegin -EndMarker $generalEnd -Values @($enabledDomains)
    Set-ManagedBlock -Path $excludeUserPath -BeginMarker $excludeBegin -EndMarker $excludeEnd -Values $disabledDomains

    $enabledValues = @($enabledDomains | Sort-Object)
    if ($enabledValues.Count -eq 0) { $enabledValues = @('nexroute.invalid') }
    Write-Utf8NoBom -Path $enabledListPath -Content (($enabledValues -join "`r`n") + "`r`n")

    foreach ($service in $Definitions) {
        if (-not [bool]$State[$service.id]) { continue }
        $id = Get-SafeServiceId -Value ([string]$service.id)
        $enabledIds.Add($id)

        $serviceDomains = @($service.domains | Where-Object { $_ } | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } | Sort-Object -Unique)
        $hostListPath = Join-Path $listsDirectory ("list-service-{0}.txt" -f $id)
        $ipsetPath = Join-Path $listsDirectory ("ipset-service-{0}.txt" -f $id)
        $keepPaths.Add($hostListPath)
        $keepPaths.Add($ipsetPath)
        $hostValues = if ($serviceDomains.Count -gt 0) { $serviceDomains } else { @('nexroute.invalid') }
        Write-Utf8NoBom -Path $hostListPath -Content (($hostValues -join "`r`n") + "`r`n")

        $ips = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($entryValue in @($service.ipCidrs)) {
            $entry = ConvertTo-ValidatedIpv4Cidr -Value ([string]$entryValue)
            if ($entry) { [void]$ips.Add($entry) }
        }

        $remote = Get-RemoteIpEntries -Sources @($service.ipSources)
        foreach ($entry in @($remote.Entries)) { [void]$ips.Add($entry) }
        foreach ($status in @($remote.Statuses)) {
            $allSourceStatuses.Add([pscustomobject]@{
                serviceId = $id
                source = $status.source
                status = $status.status
                count = $status.count
                cacheAgeDays = $status.cacheAgeDays
                message = $status.message
            })
        }

        $resolveHosts = New-Object 'System.Collections.Generic.List[string]'
        foreach ($hostName in @($service.resolveHosts)) { if ($hostName) { $resolveHosts.Add([string]$hostName) } }
        foreach ($target in @($service.testTargets)) {
            $hostName = Get-EndpointHost -Target $target
            if ($hostName) { $resolveHosts.Add($hostName) }
        }
        foreach ($entry in @(Get-ResolvedIpv4Entries -Hosts $resolveHosts.ToArray())) { [void]$ips.Add($entry) }

        $ipValues = @($ips | Sort-Object)
        $hasIps = $ipValues.Count -gt 0
        if (-not $hasIps) { $ipValues = @('203.0.113.113/32') }
        Write-Utf8NoBom -Path $ipsetPath -Content (($ipValues -join "`r`n") + "`r`n")
        foreach ($entry in @($ips)) { [void]$allIps.Add($entry) }

        $runtimeServices.Add([pscustomobject]@{
            Id = $id
            HostList = $hostListPath
            IpSet = $ipsetPath
            HasDomains = ($serviceDomains.Count -gt 0)
            HasIps = $hasIps
            TcpPorts = @($service.tcpPorts)
            UdpPorts = @($service.udpPorts)
        })
    }

    Remove-StaleServiceLists -KeepPaths $keepPaths.ToArray()
    $globalIps = @($allIps | Sort-Object)
    if ($globalIps.Count -eq 0) { $globalIps = @('203.0.113.113/32') }
    Write-Utf8NoBom -Path $serviceIpsetPath -Content (($globalIps -join "`r`n") + "`r`n")
    Write-JsonFile -Path $sourceStatusPath -Value @($allSourceStatuses) -Depth 6
    Write-ServiceRuntime -RuntimeServices $runtimeServices.ToArray()

    return [pscustomobject]@{
        Enabled = $enabledIds.Count
        EnabledIds = $enabledIds.ToArray()
        Domains = $enabledDomains.Count
        DisabledDomains = $disabledDomains.Count
        ResolvedIps = $globalIps.Count
        RuntimeGroups = $runtimeServices.Count
        SourceStatuses = $allSourceStatuses.Count
    }
}

function Restart-InstalledStrategy {
    $service = Get-Service -Name 'zapret' -ErrorAction SilentlyContinue
    if (-not $service) { return [pscustomobject]@{ Installed = $false; Restarted = $false; Message = 'zapret service is not installed.' } }
    $strategy = $null
    try { $strategy = [string](Get-ItemPropertyValue -Path 'HKLM:\System\CurrentControlSet\Services\zapret' -Name 'zapret-discord-youtube' -ErrorAction Stop) } catch { }
    if ([string]::IsNullOrWhiteSpace($strategy)) {
        Restart-Service -Name 'zapret' -Force -ErrorAction Stop
        return [pscustomobject]@{ Installed = $true; Restarted = $true; Message = 'zapret service restarted.' }
    }
    $strategyFile = if ($strategy.EndsWith('.bat', [StringComparison]::OrdinalIgnoreCase)) { $strategy } else { "$strategy.bat" }
    $serviceBat = Join-Path $Root 'service.bat'
    if (-not (Test-Path -LiteralPath $serviceBat -PathType Leaf)) { throw 'service.bat was not found for matrix refresh.' }
    $argumentLine = '/d /c ""{0}" refresh_matrix "{1}""' -f $serviceBat, $strategyFile
    $process = Start-Process -FilePath $env:ComSpec -ArgumentList $argumentLine -WorkingDirectory $Root -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "Installed strategy refresh failed with exit code $($process.ExitCode)." }
    return [pscustomobject]@{ Installed = $true; Restarted = $true; Message = "zapret service reinstalled from $strategyFile." }
}

function Get-FileSha256Safe {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() } catch { return $null }
}

function Export-NexRouteDiagnostics {
    param([Parameter(Mandatory)][array]$Definitions, [Parameter(Mandatory)]$State)
    $version = if (Test-Path -LiteralPath $versionPath -PathType Leaf) { (Get-Content -LiteralPath $versionPath -Raw).Trim() } else { 'unknown' }
    $enabledIds = @($Definitions | Where-Object { [bool]$State[$_.id] } | ForEach-Object { [string]$_.id })
    $sourceStatuses = if (Test-Path -LiteralPath $sourceStatusPath -PathType Leaf) { @(Read-JsonFile -Path $sourceStatusPath) } else { @() }
    $zapret = $null
    if (Get-Command Get-Service -ErrorAction SilentlyContinue) {
        try { $zapret = Get-Service -Name 'zapret' -ErrorAction SilentlyContinue } catch { }
    }

    $report = [ordered]@{
        generatedAtUtc = [DateTime]::UtcNow.ToString('o')
        privacy = 'No domain-list contents, IP values, usernames, or paths outside the NexRoute root are included.'
        nexRouteVersion = $version
        serviceSchemaVersion = 2
        stateSchemaVersion = $stateSchemaVersion
        enabledServiceCount = $enabledIds.Count
        enabledServiceIds = $enabledIds
        sourceStatuses = $sourceStatuses
        runtime = [ordered]@{
            serviceRuntimeSha256 = Get-FileSha256Safe -Path $runtimePath
            enabledDomainCount = if (Test-Path -LiteralPath $enabledListPath) { @(Get-Content -LiteralPath $enabledListPath).Count } else { 0 }
            serviceIpCount = if (Test-Path -LiteralPath $serviceIpsetPath) { @(Get-Content -LiteralPath $serviceIpsetPath).Count } else { 0 }
        }
        environment = [ordered]@{
            osVersion = [Environment]::OSVersion.VersionString
            is64BitOperatingSystem = [Environment]::Is64BitOperatingSystem
            powerShellVersion = $PSVersionTable.PSVersion.ToString()
            zapretInstalled = ($null -ne $zapret)
            zapretStatus = if ($zapret) { [string]$zapret.Status } else { 'NotInstalled' }
        }
    }

    if ([string]::IsNullOrWhiteSpace($DiagnosticsPath)) {
        $DiagnosticsPath = Join-Path $Root ("NexRoute-Diagnostics-{0}.json" -f [DateTime]::Now.ToString('yyyyMMdd-HHmmss'))
    }
    $fullPath = [System.IO.Path]::GetFullPath($DiagnosticsPath)
    Write-JsonFile -Path $fullPath -Value $report -Depth 10
    return [pscustomobject]@{ Path = $fullPath; Enabled = $enabledIds.Count; SourceStatuses = $sourceStatuses.Count }
}

function Assert-ServiceDefinitions {
    param([Parameter(Mandatory)][array]$Definitions)
    $ids = @($Definitions | ForEach-Object { [string]$_.id })
    if (($ids | Sort-Object -Unique).Count -ne $ids.Count) { throw 'services.json contains duplicate ids.' }

    foreach ($service in $Definitions) {
        if (-not $service.id -or -not $service.nameEn -or -not $service.nameRu -or -not $service.descriptionEn -or -not $service.descriptionRu) {
            throw 'A service definition is missing identity or localized description fields.'
        }
        if (([string]$service.id) -notmatch '^[a-z0-9][a-z0-9_-]*$') { throw "Service '$($service.id)' has an invalid id." }
        if (@($service.domains).Count -eq 0) { throw "Service '$($service.id)' has no domains." }
        if (@($service.testTargets).Count -lt 2) { throw "Service '$($service.id)' must define at least two real test targets." }
        if (@($service.tcpPorts).Count -eq 0 -and @($service.udpPorts).Count -eq 0) { throw "Service '$($service.id)' has no network ports." }

        $portsToValidate = @($service.tcpPorts) + @($service.udpPorts)
        foreach ($port in $portsToValidate) {
            if (-not (ConvertTo-ValidatedPort -Value ([string]$port))) { throw "Service '$($service.id)' has invalid port '$port'." }
        }
        foreach ($cidrValue in @($service.ipCidrs)) {
            if (-not (ConvertTo-ValidatedIpv4Cidr -Value ([string]$cidrValue))) { throw "Service '$($service.id)' has invalid IPv4 CIDR '$cidrValue'." }
        }
        foreach ($domainValue in @($service.domains)) {
            $domain = ([string]$domainValue).Trim()
            if ($domain -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$') { throw "Service '$($service.id)' has invalid domain '$domain'." }
        }
    }
}

$definitions = Get-ServiceDefinitions

switch ($Mode) {
    'Validate' {
        Assert-ServiceDefinitions -Definitions $definitions
        Write-Output "Validated $($definitions.Count) service definitions (schema v2, strict ports/CIDR)."
    }
    'Reset' {
        $state = New-DefaultState -Definitions $definitions
        Save-ServiceState -State $state
        (Apply-ServiceMatrix -Definitions $definitions -State $state) | ConvertTo-Json -Depth 6 -Compress
    }
    'Summary' {
        $stateResult = Get-ServiceStateResult -Definitions $definitions
        $enabled = @($definitions | Where-Object { [bool]$stateResult.State[$_.id] })
        [pscustomobject]@{
            Total = $definitions.Count
            Enabled = $enabled.Count
            EnabledIds = @($enabled | ForEach-Object { $_.id })
            TestTargets = @($enabled | ForEach-Object { @($_.testTargets).Count } | Measure-Object -Sum).Sum
            StateSchemaVersion = $stateSchemaVersion
            NeedsMigration = [bool]$stateResult.Migrated
            InvalidState = [bool]$stateResult.Invalid
        } | ConvertTo-Json -Depth 5 -Compress
    }
    'TestTargets' {
        $stateResult = Get-ServiceStateResult -Definitions $definitions
        $targets = New-Object 'System.Collections.Generic.List[object]'
        foreach ($service in $definitions) {
            if (-not [bool]$stateResult.State[$service.id]) { continue }
            foreach ($target in @($service.testTargets)) {
                if (-not $target.url) { continue }
                $targets.Add([pscustomobject]@{
                    NameEn = ('{0} / {1}' -f $service.nameEn, $target.name)
                    NameRu = ('{0} / {1}' -f $service.nameRu, $target.role)
                    Value = [string]$target.url
                    ServiceId = [string]$service.id
                    Role = [string]$target.role
                })
            }
        }
        @($targets) | ConvertTo-Json -Depth 5 -Compress
    }
    'Restart' {
        Restart-InstalledStrategy | ConvertTo-Json -Compress
    }
    'Diagnostics' {
        $stateResult = Get-ServiceStateResult -Definitions $definitions
        Export-NexRouteDiagnostics -Definitions $definitions -State $stateResult.State | ConvertTo-Json -Compress
    }
    default {
        Assert-ServiceDefinitions -Definitions $definitions
        $stateResult = Get-ServiceStateResult -Definitions $definitions
        if ($stateResult.Migrated) { Backup-ServiceState -FileName 'services-state.v1.backup.json' }
        if ($stateResult.Invalid) { Backup-ServiceState -FileName 'services-state.invalid.backup.json' }
        if (-not $stateResult.Exists -or $stateResult.Migrated -or $stateResult.Invalid) { Save-ServiceState -State $stateResult.State }
        (Apply-ServiceMatrix -Definitions $definitions -State $stateResult.State) | ConvertTo-Json -Depth 6 -Compress
    }
}
