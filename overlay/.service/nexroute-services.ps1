[CmdletBinding()]
param(
    [ValidateSet('Apply', 'Summary', 'Reset', 'Validate', 'TestTargets', 'Restart')]
    [string]$Mode = 'Apply',
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$serviceDirectory = $PSScriptRoot
$definitionPath = Join-Path $serviceDirectory 'services.json'
$statePath = Join-Path $serviceDirectory 'services-state.json'
$runtimePath = Join-Path $serviceDirectory 'services-runtime.cmd'
$listsDirectory = Join-Path $Root 'lists'
$generalUserPath = Join-Path $listsDirectory 'list-general-user.txt'
$excludeUserPath = Join-Path $listsDirectory 'list-exclude-user.txt'
$enabledListPath = Join-Path $listsDirectory 'list-services-enabled.txt'
$serviceIpsetPath = Join-Path $listsDirectory 'ipset-services-user.txt'

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

function Read-JsonFile {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required JSON file was not found: $Path"
    }
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Get-ServiceDefinitions {
    $document = Read-JsonFile -Path $definitionPath
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

function Get-ServiceState {
    param([Parameter(Mandatory)][array]$Definitions)
    $state = New-DefaultState -Definitions $Definitions
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { return $state }
    try {
        $saved = Read-JsonFile -Path $statePath
        foreach ($service in $Definitions) {
            $property = $saved.PSObject.Properties[$service.id]
            if ($null -ne $property) { $state[$service.id] = [bool]$property.Value }
        }
    }
    catch { Write-Warning "Ignoring invalid service state: $($_.Exception.Message)" }
    return $state
}

function Save-ServiceState {
    param([Parameter(Mandatory)]$State)
    Write-Utf8NoBom -Path $statePath -Content (($State | ConvertTo-Json -Depth 6) + [Environment]::NewLine)
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
        $output.Add($value.ToLowerInvariant())
    }
    $output.Add($EndMarker)
    $output.Add('')
    Write-Utf8NoBom -Path $Path -Content (($output.ToArray() -join "`r`n") + "`r`n")
}

function Get-EndpointHost {
    param($Target)
    if ($null -eq $Target -or -not $Target.url) { return $null }
    try { return ([Uri]$Target.url).DnsSafeHost } catch { return $null }
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
            foreach ($address in $addresses) { [void]$entries.Add("$address/32") }
        }
        catch { }
    }
    return @($entries)
}

function Get-RemoteIpEntries {
    param([array]$Sources)
    $entries = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($source in @($Sources | Where-Object { $_ })) {
        try {
            $response = Invoke-WebRequest -Uri ([string]$source) -UseBasicParsing -TimeoutSec 8 -Headers @{ 'Cache-Control' = 'no-cache' }
            foreach ($line in @($response.Content -split "`r?`n")) {
                $value = $line.Trim()
                if ($value -match '^\d{1,3}(?:\.\d{1,3}){3}/\d{1,2}$') { [void]$entries.Add($value) }
            }
        }
        catch { Write-Warning "Unable to refresh service IP source '$source': $($_.Exception.Message)" }
    }
    return @($entries)
}

function Get-PortText {
    param([string[]]$Ports, [string]$Fallback)
    $values = @($Ports | Where-Object { $_ } | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ -match '^\d+(?:-\d+)?$' } | Sort-Object -Unique)
    if ($values.Count -eq 0) { return $Fallback }
    return ($values -join ',')
}

function Write-ServiceRuntime {
    param(
        [Parameter(Mandatory)][string[]]$TcpPorts,
        [Parameter(Mandatory)][string[]]$UdpPorts,
        [Parameter(Mandatory)][bool]$HasEnabledServices
    )
    $tcpText = Get-PortText -Ports $TcpPorts -Fallback '65535'
    $udpText = Get-PortText -Ports $UdpPorts -Fallback '65535'
    $hostList = $enabledListPath
    $ipset = $serviceIpsetPath
    $bin = Join-Path $Root 'bin'
    if (-not $HasEnabledServices) {
        $tcpText = '65535'
        $udpText = '65535'
    }
    $tcpArgs = '--filter-tcp={0} --hostlist="{1}" --ipset="{2}" --dpi-desync=multisplit --dpi-desync-split-seqovl=568 --dpi-desync-split-pos=1 --dpi-desync-split-seqovl-pattern="{3}" --new' -f $tcpText, $hostList, $ipset, (Join-Path $bin 'tls_clienthello_4pda_to.bin')
    $udpArgs = '--filter-udp={0} --hostlist="{1}" --ipset="{2}" --dpi-desync=fake --dpi-desync-repeats=8 --dpi-desync-fake-quic="{3}" --new' -f $udpText, $hostList, $ipset, (Join-Path $bin 'quic_initial_www_google_com.bin')
    $lines = @(
        '@echo off',
        'rem Generated by NexRoute Service Matrix. Do not edit.',
        ('set "NEXROUTE_EXTRA_TCP_PORTS={0}"' -f $tcpText),
        ('set "NEXROUTE_EXTRA_UDP_PORTS={0}"' -f $udpText),
        ('set "NEXROUTE_SERVICE_TCP_ARGS={0}"' -f $tcpArgs),
        ('set "NEXROUTE_SERVICE_UDP_ARGS={0}"' -f $udpArgs)
    )
    [System.IO.File]::WriteAllLines($runtimePath, $lines, [System.Text.Encoding]::ASCII)
}

function Apply-ServiceMatrix {
    param([Parameter(Mandatory)][array]$Definitions, [Parameter(Mandatory)]$State)
    $enabledDomains = New-Object 'System.Collections.Generic.List[string]'
    $disabledDomains = New-Object 'System.Collections.Generic.List[string]'
    $resolveHosts = New-Object 'System.Collections.Generic.List[string]'
    $staticIps = New-Object 'System.Collections.Generic.List[string]'
    $ipSources = New-Object 'System.Collections.Generic.List[string]'
    $tcpPorts = New-Object 'System.Collections.Generic.List[string]'
    $udpPorts = New-Object 'System.Collections.Generic.List[string]'
    $enabledIds = New-Object 'System.Collections.Generic.List[string]'

    foreach ($service in $Definitions) {
        $enabled = [bool]$State[$service.id]
        foreach ($domain in @($service.domains)) {
            if ([string]::IsNullOrWhiteSpace([string]$domain)) { continue }
            if ($enabled) { $enabledDomains.Add([string]$domain) } else { $disabledDomains.Add([string]$domain) }
        }
        if (-not $enabled) { continue }
        $enabledIds.Add([string]$service.id)
        foreach ($port in @($service.tcpPorts)) { if ($port) { $tcpPorts.Add([string]$port) } }
        foreach ($port in @($service.udpPorts)) { if ($port) { $udpPorts.Add([string]$port) } }
        foreach ($hostName in @($service.resolveHosts)) { if ($hostName) { $resolveHosts.Add([string]$hostName) } }
        foreach ($target in @($service.testTargets)) { $hostName = Get-EndpointHost -Target $target; if ($hostName) { $resolveHosts.Add($hostName) } }
        foreach ($entry in @($service.ipCidrs)) { if ($entry) { $staticIps.Add([string]$entry) } }
        foreach ($source in @($service.ipSources)) { if ($source) { $ipSources.Add([string]$source) } }
    }

    Set-ManagedBlock -Path $generalUserPath -BeginMarker $generalBegin -EndMarker $generalEnd -Values $enabledDomains.ToArray()
    Set-ManagedBlock -Path $excludeUserPath -BeginMarker $excludeBegin -EndMarker $excludeEnd -Values $disabledDomains.ToArray()
    $enabledValues = @($enabledDomains.ToArray() | Sort-Object -Unique)
    if ($enabledValues.Count -eq 0) { $enabledValues = @('nexroute.invalid') }
    Write-Utf8NoBom -Path $enabledListPath -Content (($enabledValues -join "`r`n") + "`r`n")

    $ipValues = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($entry in @($staticIps.ToArray())) { if ($entry -match '^\d{1,3}(?:\.\d{1,3}){3}/\d{1,2}$') { [void]$ipValues.Add($entry) } }
    foreach ($entry in @(Get-RemoteIpEntries -Sources $ipSources.ToArray())) { [void]$ipValues.Add($entry) }
    foreach ($entry in @(Get-ResolvedIpv4Entries -Hosts $resolveHosts.ToArray())) { [void]$ipValues.Add($entry) }
    $ipList = @($ipValues | Sort-Object)
    if ($ipList.Count -eq 0) { $ipList = @('203.0.113.113/32') }
    Write-Utf8NoBom -Path $serviceIpsetPath -Content (($ipList -join "`r`n") + "`r`n")

    Write-ServiceRuntime -TcpPorts $tcpPorts.ToArray() -UdpPorts $udpPorts.ToArray() -HasEnabledServices ($enabledIds.Count -gt 0)
    return [pscustomobject]@{
        Enabled = $enabledIds.Count
        Domains = $enabledDomains.Count
        ResolvedIps = $ipList.Count
        TcpPorts = Get-PortText -Ports $tcpPorts.ToArray() -Fallback '65535'
        UdpPorts = Get-PortText -Ports $udpPorts.ToArray() -Fallback '65535'
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

$definitions = Get-ServiceDefinitions

switch ($Mode) {
    'Validate' {
        $ids = @($definitions | ForEach-Object { $_.id })
        if (($ids | Sort-Object -Unique).Count -ne $ids.Count) { throw 'services.json contains duplicate ids.' }
        foreach ($service in $definitions) {
            if (-not $service.id -or -not $service.nameEn -or -not $service.nameRu -or -not $service.descriptionEn -or -not $service.descriptionRu) {
                throw 'A service definition is missing identity or localized description fields.'
            }
            if (@($service.domains).Count -eq 0) { throw "Service '$($service.id)' has no domains." }
            if (@($service.testTargets).Count -lt 2) { throw "Service '$($service.id)' must define at least two real test targets." }
            if (@($service.tcpPorts).Count -eq 0 -and @($service.udpPorts).Count -eq 0) { throw "Service '$($service.id)' has no network ports." }
        }
        Write-Output "Validated $($definitions.Count) service definitions (schema v2)."
    }
    'Reset' {
        $state = New-DefaultState -Definitions $definitions
        Save-ServiceState -State $state
        $result = Apply-ServiceMatrix -Definitions $definitions -State $state
        $result | ConvertTo-Json -Compress
    }
    'Summary' {
        $state = Get-ServiceState -Definitions $definitions
        $enabled = @($definitions | Where-Object { [bool]$state[$_.id] })
        [pscustomobject]@{
            Total = $definitions.Count
            Enabled = $enabled.Count
            EnabledIds = @($enabled | ForEach-Object { $_.id })
            TestTargets = @($enabled | ForEach-Object { @($_.testTargets).Count } | Measure-Object -Sum).Sum
        } | ConvertTo-Json -Compress
    }
    'TestTargets' {
        $state = Get-ServiceState -Definitions $definitions
        $targets = New-Object 'System.Collections.Generic.List[object]'
        foreach ($service in $definitions) {
            if (-not [bool]$state[$service.id]) { continue }
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
    'Restart' { Restart-InstalledStrategy | ConvertTo-Json -Compress }
    default {
        $state = Get-ServiceState -Definitions $definitions
        if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { Save-ServiceState -State $state }
        (Apply-ServiceMatrix -Definitions $definitions -State $state) | ConvertTo-Json -Compress
    }
}
