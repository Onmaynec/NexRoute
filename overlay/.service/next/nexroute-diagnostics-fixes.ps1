Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-NrDiagnosticReport {
    $versionPath = Join-Path $script:NrService 'version.txt'
    $version = if (Test-Path -LiteralPath $versionPath -PathType Leaf) {
        ([string](Get-Content -LiteralPath $versionPath -Raw -Encoding UTF8)).Trim()
    } else {
        $null
    }

    $os = $null
    try { $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop } catch { }

    $adapters = @()
    try {
        $adapters = @(Get-NetAdapter -ErrorAction Stop | ForEach-Object {
            $addresses = @(Get-NetIPAddress -InterfaceIndex $_.ifIndex -ErrorAction SilentlyContinue |
                Where-Object { $_.AddressState -eq 'Preferred' } |
                ForEach-Object { $_.IPAddress })
            [pscustomobject]@{
                name = $_.Name
                status = [string]$_.Status
                mediaType = [string]$_.MediaType
                linkSpeed = [string]$_.LinkSpeed
                addresses = $addresses
            }
        })
    } catch { }

    $dns = @()
    try {
        $dns = @(Get-DnsClientServerAddress -ErrorAction Stop |
            Where-Object { $_.ServerAddresses.Count -gt 0 } |
            ForEach-Object {
                [pscustomobject]@{
                    adapter = $_.InterfaceAlias
                    family = [string]$_.AddressFamily
                    servers = @($_.ServerAddresses)
                }
            })
    } catch { }

    $monitor = $null
    if (Test-Path -LiteralPath $script:NrMonitorState -PathType Leaf) {
        try { $monitor = Get-Content -LiteralPath $script:NrMonitorState -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
    }

    $serviceRunning = Test-NrServiceRunning -Name 'zapret'
    $winDivertRunning = ((Test-NrServiceRunning -Name 'WinDivert') -or (Test-NrServiceRunning -Name 'WinDivert14'))
    $winwsRunning = [bool](Get-Process -Name 'winws' -ErrorAction SilentlyContinue)

    return [ordered]@{
        schemaVersion = 3
        createdUtc = [DateTime]::UtcNow.ToString('o')
        nexroute = [ordered]@{
            version = $version
            installedStrategy = Get-NrInstalledStrategy
            serviceRunning = $serviceRunning
            winDivertRunning = $winDivertRunning
            winwsRunning = $winwsRunning
            serviceProfiles = Get-NrServiceSummary
            safeMode = [bool]$script:NrState.safeMode
            monitorEnabled = [bool]$script:NrState.monitorEnabled
            autoSwitchEnabled = [bool]$script:NrState.autoSwitchEnabled
            networkKey = Get-NrActiveNetworkKey
            dnsProvider = [string]$script:NrState.dnsProvider
            dnsEncryption = [string]$script:NrState.dnsEncryption
            lastDownloadedSha256 = [string]$script:NrState.lastDownloadedSha256
            lastAttestationStatus = [string]$script:NrState.lastAttestationStatus
        }
        windows = [ordered]@{
            caption = if ($os) { $os.Caption } else { [Environment]::OSVersion.VersionString }
            version = if ($os) { $os.Version } else { [Environment]::OSVersion.Version.ToString() }
            build = if ($os) { $os.BuildNumber } else { $null }
            architecture = $env:PROCESSOR_ARCHITECTURE
            powershell = $PSVersionTable.PSVersion.ToString()
            elevated = Test-NrAdministrator
        }
        adapters = $adapters
        dns = $dns
        conflicts = Get-NrConflictReport
        userLists = Get-NrUserListIntegrity
        monitor = $monitor
    }
}

function Show-NrSystemStatus {
    [CmdletBinding()]
    param([switch]$NoWait)

    $report = Get-NrDiagnosticReport
    Write-NrHeader -Title (T 'systemStatus')
    $rows = @(
        @((T 'statusVersion'), $report.nexroute.version),
        @((T 'statusStrategy'), $report.nexroute.installedStrategy),
        @((T 'statusZapret'), $(if ($report.nexroute.serviceRunning) { T 'running' } else { T 'stopped' })),
        @((T 'statusWinDivert'), $(if ($report.nexroute.winDivertRunning) { T 'running' } else { T 'stopped' })),
        @((T 'statusEngine'), $(if ($report.nexroute.winwsRunning) { T 'running' } else { T 'stopped' })),
        @((T 'statusProfiles'), $report.nexroute.serviceProfiles),
        @((T 'statusMonitor'), $(if ($report.nexroute.monitorEnabled) { T 'enabled' } else { T 'disabled' })),
        @((T 'statusNetwork'), $report.nexroute.networkKey),
        @((T 'dnsProvider'), ($report.nexroute.dnsProvider + ' / ' + $report.nexroute.dnsEncryption)),
        @((T 'sha'), $report.nexroute.lastDownloadedSha256)
    )

    foreach ($row in $rows) {
        $value = [string]$row[1]
        Write-Host ('  {0,-34}: {1}' -f $row[0], $value) -ForegroundColor (Get-NrStatusColor -Status $value)
    }
    Write-Host ''
    Write-Host ('  Conflicts detected: ' + @($report.conflicts | Where-Object { $_.severity -eq 'warning' }).Count) -ForegroundColor Yellow

    $redirected = $false
    try { $redirected = [Console]::IsInputRedirected -or [Console]::IsOutputRedirected } catch { $redirected = $true }
    if (-not $NoWait -and -not $redirected -and [Environment]::UserInteractive) {
        Wait-NrKey
    }

    return $report
}
