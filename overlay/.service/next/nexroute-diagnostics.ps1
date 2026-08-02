Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-NrConflictReport {
    $items=New-Object 'System.Collections.Generic.List[object]'
    try {
        foreach ($vpn in @(Get-VpnConnection -AllUserConnection -ErrorAction SilentlyContinue)) {
            $items.Add([pscustomobject]@{ type='VPN'; name=$vpn.Name; status=$vpn.ConnectionStatus; severity='warning'; detail='Windows VPN connection' })
        }
    } catch { }
    try {
        foreach ($service in @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)vpn|wireguard|openvpn|tailscale|zerotier|adguard|checkpoint|tracsrv|smartbyte|killer' -or $_.DisplayName -match '(?i)vpn|wireguard|openvpn|tailscale|zerotier|adguard|check point|smartbyte|killer' })) {
            $severity=if ($service.Status -eq 'Running') { 'warning' } else { 'info' }
            $items.Add([pscustomobject]@{ type='SERVICE'; name=$service.DisplayName; status=[string]$service.Status; severity=$severity; detail=$service.Name })
        }
    } catch { }
    try {
        $av=@(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction SilentlyContinue)
        foreach ($product in $av) {
            $items.Add([pscustomobject]@{ type='ANTIVIRUS'; name=$product.displayName; status=('0x{0:X}' -f [int]$product.productState); severity='info'; detail=$product.pathToSignedProductExe })
        }
    } catch { }
    try {
        foreach ($profile in @(Get-NetFirewallProfile -ErrorAction SilentlyContinue)) {
            $items.Add([pscustomobject]@{ type='FIREWALL'; name=$profile.Name; status=$(if ($profile.Enabled) { 'Enabled' } else { 'Disabled' }); severity=$(if ($profile.Enabled) { 'info' } else { 'warning' }); detail=('DefaultInbound=' + $profile.DefaultInboundAction) })
        }
    } catch { }
    try {
        foreach ($service in @(Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)windivert' })) {
            if ($service.Name -notin @('WinDivert','WinDivert14')) {
                $items.Add([pscustomobject]@{ type='WINDIVERT'; name=$service.Name; status=[string]$service.Status; severity='warning'; detail='Additional WinDivert service' })
            }
        }
        $systemDrivers=Join-Path $env:SystemRoot 'System32\drivers'
        foreach ($file in @(Get-ChildItem -LiteralPath $systemDrivers -Filter '*WinDivert*.sys' -File -ErrorAction SilentlyContinue)) {
            $items.Add([pscustomobject]@{ type='WINDIVERT'; name=$file.Name; status='Driver file'; severity='info'; detail=$file.FullName })
        }
    } catch { }
    return $items.ToArray()
}

function Get-NrUserListIntegrity {
    $paths=@(
        'lists/list-general-user.txt','lists/list-exclude-user.txt','lists/ipset-services-user.txt','lists/ipset-exclude-user.txt','lists/ipset-all.txt'
    )
    $results=New-Object 'System.Collections.Generic.List[object]'
    $hashPath=Join-Path $script:NrService 'user-list-integrity.json'
    $previous=$null
    if (Test-Path -LiteralPath $hashPath) { try { $previous=Get-Content -LiteralPath $hashPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { } }
    $current=[ordered]@{ schemaVersion=1; updatedUtc=[DateTime]::UtcNow.ToString('o'); files=[ordered]@{} }
    foreach ($relative in $paths) {
        $path=Join-Path $script:NrRoot $relative
        $exists=Test-Path -LiteralPath $path -PathType Leaf
        $hash=$null; $lineCount=0; $valid=$true; $message=$null
        if ($exists) {
            try {
                $hash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
                $lines=@(Get-Content -LiteralPath $path -Encoding UTF8)
                $lineCount=$lines.Count
                if ($relative -match 'ipset') {
                    foreach ($line in $lines) {
                        $candidate=($line -split '[#;]',2)[0].Trim()
                        if (-not $candidate) { continue }
                        $addressText=($candidate -split '/',2)[0]
                        $ip=$null
                        if (-not [Net.IPAddress]::TryParse($addressText,[ref]$ip)) { $valid=$false; $message='Invalid IP/CIDR: ' + $candidate; break }
                    }
                } else {
                    foreach ($line in $lines) {
                        $candidate=($line -split '[#;]',2)[0].Trim()
                        if (-not $candidate) { continue }
                        if ($candidate -notmatch '^(\^?)([A-Za-z0-9_-]+\.)+[A-Za-z0-9_-]+$') { $valid=$false; $message='Invalid domain: ' + $candidate; break }
                    }
                }
            } catch { $valid=$false; $message=$_.Exception.Message }
        } else { $valid=$false; $message='Missing file' }
        $changed=$false
        if ($previous) {
            try { $property=$previous.files.PSObject.Properties[$relative]; if ($property -and [string]$property.Value.sha256 -ne $hash) { $changed=$true } } catch { }
        }
        $current.files[$relative]=[ordered]@{ sha256=$hash; lineCount=$lineCount; valid=$valid }
        $results.Add([pscustomobject]@{ path=$relative; exists=$exists; sha256=$hash; lineCount=$lineCount; valid=$valid; changed=$changed; message=$message })
    }
    [System.IO.File]::WriteAllText($hashPath,($current | ConvertTo-Json -Depth 10)+[Environment]::NewLine,(New-Object Text.UTF8Encoding($false)))
    return $results.ToArray()
}

function Get-NrDiagnosticReport {
    $versionPath=Join-Path $script:NrService 'version.txt'
    $version=if (Test-Path -LiteralPath $versionPath) { (Get-Content -LiteralPath $versionPath -Raw -Encoding UTF8).Trim() } else { $null }
    $os=$null
    try { $os=Get-CimInstance Win32_OperatingSystem -ErrorAction Stop } catch { }
    $adapters=@()
    try {
        $adapters=@(Get-NetAdapter -ErrorAction Stop | ForEach-Object {
            $addresses=@(Get-NetIPAddress -InterfaceIndex $_.ifIndex -ErrorAction SilentlyContinue | Where-Object { $_.AddressState -eq 'Preferred' } | ForEach-Object { $_.IPAddress })
            [pscustomobject]@{ name=$_.Name; status=[string]$_.Status; mediaType=[string]$_.MediaType; linkSpeed=[string]$_.LinkSpeed; addresses=$addresses }
        })
    } catch { }
    $dns=@()
    try { $dns=@(Get-DnsClientServerAddress -ErrorAction Stop | Where-Object { $_.ServerAddresses.Count -gt 0 } | ForEach-Object { [pscustomobject]@{ adapter=$_.InterfaceAlias; family=[string]$_.AddressFamily; servers=@($_.ServerAddresses) } }) } catch { }
    $monitor=$null
    if (Test-Path -LiteralPath $script:NrMonitorState) { try { $monitor=Get-Content -LiteralPath $script:NrMonitorState -Raw -Encoding UTF8 | ConvertFrom-Json } catch { } }
    return [ordered]@{
        schemaVersion=3
        createdUtc=[DateTime]::UtcNow.ToString('o')
        nexroute=[ordered]@{
            version=$version; installedStrategy=Get-NrInstalledStrategy; serviceRunning=Test-NrServiceRunning -Name zapret;
            winDivertRunning=(Test-NrServiceRunning -Name WinDivert -or Test-NrServiceRunning -Name WinDivert14);
            winwsRunning=[bool](Get-Process -Name winws -ErrorAction SilentlyContinue); serviceProfiles=Get-NrServiceSummary;
            safeMode=[bool]$script:NrState.safeMode; monitorEnabled=[bool]$script:NrState.monitorEnabled;
            autoSwitchEnabled=[bool]$script:NrState.autoSwitchEnabled; networkKey=Get-NrActiveNetworkKey;
            dnsProvider=[string]$script:NrState.dnsProvider; dnsEncryption=[string]$script:NrState.dnsEncryption;
            lastDownloadedSha256=[string]$script:NrState.lastDownloadedSha256; lastAttestationStatus=[string]$script:NrState.lastAttestationStatus
        }
        windows=[ordered]@{
            caption=if ($os) { $os.Caption } else { [Environment]::OSVersion.VersionString }
            version=if ($os) { $os.Version } else { [Environment]::OSVersion.Version.ToString() }
            build=if ($os) { $os.BuildNumber } else { $null }
            architecture=$env:PROCESSOR_ARCHITECTURE
            powershell=$PSVersionTable.PSVersion.ToString()
            elevated=Test-NrAdministrator
        }
        adapters=$adapters
        dns=$dns
        conflicts=Get-NrConflictReport
        userLists=Get-NrUserListIntegrity
        monitor=$monitor
    }
}

function Show-NrSystemStatus {
    $report=Get-NrDiagnosticReport
    Write-NrHeader -Title (T 'systemStatus')
    $rows=@(
        @((T 'statusVersion'),$report.nexroute.version),
        @((T 'statusStrategy'),$report.nexroute.installedStrategy),
        @((T 'statusZapret'),$(if ($report.nexroute.serviceRunning) { T 'running' } else { T 'stopped' })),
        @((T 'statusWinDivert'),$(if ($report.nexroute.winDivertRunning) { T 'running' } else { T 'stopped' })),
        @((T 'statusEngine'),$(if ($report.nexroute.winwsRunning) { T 'running' } else { T 'stopped' })),
        @((T 'statusProfiles'),$report.nexroute.serviceProfiles),
        @((T 'statusMonitor'),$(if ($report.nexroute.monitorEnabled) { T 'enabled' } else { T 'disabled' })),
        @((T 'statusNetwork'),$report.nexroute.networkKey),
        @((T 'dnsProvider'),($report.nexroute.dnsProvider + ' / ' + $report.nexroute.dnsEncryption)),
        @((T 'sha'),$report.nexroute.lastDownloadedSha256)
    )
    foreach ($row in $rows) {
        $value=[string]$row[1]
        Write-Host ('  {0,-34}: {1}' -f $row[0],$value) -ForegroundColor $(Get-NrStatusColor -Status $value)
    }
    Write-Host ''
    Write-Host ('  Conflicts detected: ' + @($report.conflicts | Where-Object { $_.severity -eq 'warning' }).Count) -ForegroundColor Yellow
    Wait-NrKey
}

function Show-NrAvailabilityPanel {
    Write-NrHeader -Title (T 'availability')
    if (-not (Test-Path -LiteralPath $script:NrMonitorState -PathType Leaf)) {
        Write-Host ('  ' + (T 'noResults')) -ForegroundColor Yellow
        Wait-NrKey
        return
    }
    try {
        $state=Get-Content -LiteralPath $script:NrMonitorState -Raw -Encoding UTF8 | ConvertFrom-Json
        Write-Host ('  Updated: ' + $state.updatedUtc) -ForegroundColor DarkGray
        Write-Host ('  Strategy: ' + $state.strategy) -ForegroundColor Cyan
        Write-Host ''
        foreach ($service in @($state.services)) {
            Write-Host ('  {0,-28} {1,-12} latency={2,7:N1} ms failures={3}' -f $service.name,$(if ($service.ok) { 'AVAILABLE' } else { 'FAILED' }),$service.latencyMs,$service.consecutiveFailures) -ForegroundColor $(if ($service.ok) { [ConsoleColor]::Green } else { [ConsoleColor]::Red })
        }
    } catch { Write-Host ('  ' + $_.Exception.Message) -ForegroundColor Red }
    Wait-NrKey
}

function Show-NrConflicts {
    $items=@(Get-NrConflictReport)
    Write-NrHeader -Title (T 'conflicts')
    if ($items.Count -eq 0) { Write-Host '  No conflicts detected.' -ForegroundColor Green }
    foreach ($item in $items) {
        $color=if ($item.severity -eq 'warning') { [ConsoleColor]::Yellow } else { [ConsoleColor]::Gray }
        Write-Host ('  [{0,-9}] {1,-34} {2,-12} {3}' -f $item.type,$item.name,$item.status,$item.detail) -ForegroundColor $color
    }
    Wait-NrKey
}

function Repair-NrService {
    Write-NrHeader -Title (T 'repairService')
    $strategy=Get-NrInstalledStrategy
    try {
        if (Test-NrServiceRunning -Name zapret) {
            Restart-Service -Name zapret -Force -ErrorAction Stop
            Show-NrMessage -Title (T 'repairService') -Message (T 'restarted') -Color Green
            return
        }
        $file=Get-NrStrategies | Where-Object { $_.BaseName -eq $strategy -or $_.Name -eq ($strategy + '.bat') } | Select-Object -First 1
        if (-not $file) {
            $run=Get-NrLatestLabRun
            if ($run) {
                $best=@($run.results | Sort-Object score -Descending | Select-Object -First 1)
                if ($best.Count -gt 0) { $file=Get-NrStrategies | Where-Object { $_.Name -eq [string]$best[0].strategy } | Select-Object -First 1 }
            }
        }
        if (-not $file) { $file=Get-NrStrategies | Select-Object -First 1 }
        if (-not $file) { throw 'No strategy file is available for repair.' }
        Install-NrStrategy -Strategy $file -Silent
        Show-NrMessage -Title (T 'repairService') -Message (T 'operationComplete') -Color Green
    } catch { Show-NrMessage -Title (T 'operationFailed') -Message $_.Exception.Message -Color Red }
}

function Show-NrIntegrity {
    $results=@(Get-NrUserListIntegrity)
    Write-NrHeader -Title (T 'integrity')
    foreach ($result in $results) {
        Write-Host ('  {0,-42} {1,-8} lines={2,6} changed={3}' -f $result.path,$(if ($result.valid) { 'VALID' } else { 'INVALID' }),$result.lineCount,$result.changed) -ForegroundColor $(if ($result.valid) { [ConsoleColor]::Green } else { [ConsoleColor]::Red })
        if ($result.message) { Write-Host ('    ' + $result.message) -ForegroundColor Yellow }
    }
    Wait-NrKey
}

function Export-NrDiagnosticZip {
    $stamp=[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
    $temp=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-diagnostics-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temp -Force | Out-Null
    try {
        $report=Get-NrDiagnosticReport
        [IO.File]::WriteAllText((Join-Path $temp 'diagnostics.json'),($report | ConvertTo-Json -Depth 20)+[Environment]::NewLine,(New-Object Text.UTF8Encoding($false)))
        $log=Join-Path $script:NrLogDir 'nexroute.jsonl'
        if (Test-Path -LiteralPath $log) { Copy-Item -LiteralPath $log -Destination (Join-Path $temp 'nexroute.jsonl') -Force }
        $monitor=Join-Path $script:NrService 'monitor-state.json'
        if (Test-Path -LiteralPath $monitor) { Copy-Item -LiteralPath $monitor -Destination (Join-Path $temp 'monitor-state.json') -Force }
        $destination=Join-Path ([Environment]::GetFolderPath('Desktop')) ('NexRoute-diagnostics-' + $stamp + '.zip')
        if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Force }
        Compress-Archive -Path (Join-Path $temp '*') -DestinationPath $destination -CompressionLevel Optimal
        Show-NrMessage -Title (T 'diagnosticZip') -Message $destination -Color Green
    } finally { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
}

function Copy-NrDiagnosticReport {
    $json=(Get-NrDiagnosticReport | ConvertTo-Json -Depth 20)
    try { Set-Clipboard -Value $json -ErrorAction Stop; Show-NrMessage -Title (T 'copyReport') -Message (T 'operationComplete') -Color Green }
    catch { Show-NrMessage -Title (T 'copyReport') -Message $_.Exception.Message -Color Red }
}

function Get-NrLogEntries {
    $path=Join-Path $script:NrLogDir 'nexroute.jsonl'
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    $entries=New-Object 'System.Collections.Generic.List[object]'
    foreach ($line in @(Get-Content -LiteralPath $path -Encoding UTF8 -Tail 1000)) {
        try { $entries.Add(($line | ConvertFrom-Json)) } catch { }
    }
    return $entries.ToArray()
}

function Show-NrLogs {
    param([string]$Level,[string]$Query)
    $entries=@(Get-NrLogEntries)
    if ($Level) { $entries=@($entries | Where-Object { [string]$_.level -eq $Level }) }
    if ($Query) { $entries=@($entries | Where-Object { ([string]$_.message).IndexOf($Query,[StringComparison]::OrdinalIgnoreCase) -ge 0 -or (($_ | ConvertTo-Json -Compress).IndexOf($Query,[StringComparison]::OrdinalIgnoreCase) -ge 0) }) }
    Write-NrHeader -Title (T 'logViewer')
    foreach ($entry in @($entries | Select-Object -Last 80)) {
        $color=switch ([string]$entry.level) { 'ERROR' { [ConsoleColor]::Red } 'WARNING' { [ConsoleColor]::Yellow } default { [ConsoleColor]::Gray } }
        Write-Host ('  {0} [{1,-7}] {2}' -f ([string]$entry.timestampUtc),([string]$entry.level),([string]$entry.message)) -ForegroundColor $color
    }
    if ($entries.Count -eq 0) { Write-Host ('  ' + (T 'noResults')) -ForegroundColor Yellow }
    Wait-NrKey
}

function Show-NrLogMenu {
    while ($true) {
        $items=@(
            New-NrMenuItem -Id 'all' -Label (T 'logViewer') -Section (T 'logs')
            New-NrMenuItem -Id 'error' -Label 'ERROR' -Section (T 'logs')
            New-NrMenuItem -Id 'warning' -Label 'WARNING' -Section (T 'logs')
            New-NrMenuItem -Id 'search' -Label (T 'logSearch') -Section (T 'logs')
            New-NrMenuItem -Id 'copy' -Label (T 'copyReport') -Section (T 'logs')
            New-NrMenuItem -Id 'zip' -Label (T 'diagnosticZip') -Section (T 'logs')
            New-NrMenuItem -Id 'back' -Label (T 'back') -Section (T 'logs')
        )
        $choice=Invoke-NrMenu -Title (T 'logs') -Items $items -AllowEscape
        if (-not $choice -or $choice -eq 'back') { return }
        switch ($choice) {
            'all' { Show-NrLogs }
            'error' { Show-NrLogs -Level 'ERROR' }
            'warning' { Show-NrLogs -Level 'WARNING' }
            'search' { Write-NrHeader -Title (T 'logSearch'); $query=Read-Host ('  ' + (T 'inputPrompt')); if ($query) { Show-NrLogs -Query $query } }
            'copy' { Copy-NrDiagnosticReport }
            'zip' { Export-NrDiagnosticZip }
        }
    }
}

function Show-NrErrorCatalog {
    $errors=@(
        [pscustomobject]@{ code='NR-UPDATE-001'; title='Update download failed'; solution='Check GitHub access, DNS and system time, then retry.' },
        [pscustomobject]@{ code='NR-SHA-002'; title='SHA-256 mismatch'; solution='Delete the downloaded package. NexRoute will never install it.' },
        [pscustomobject]@{ code='NR-WD-003'; title='WinDivert conflict'; solution='Stop other DPI tools, VPN filters and duplicate WinDivert services.' },
        [pscustomobject]@{ code='NR-DNS-004'; title='DNS resolution failed'; solution='Open Network and DNS, run diagnostics, then select a secure resolver.' },
        [pscustomobject]@{ code='NR-LAB-005'; title='Strategy Lab cannot start winws'; solution='Run NexRoute as administrator and check antivirus quarantine.' },
        [pscustomobject]@{ code='NR-SVC-006'; title='zapret service stopped'; solution='Use Repair damaged service or install another strategy.' },
        [pscustomobject]@{ code='NR-CFG-007'; title='Invalid custom configuration'; solution='Use Validate configuration and review the winws command preview.' },
        [pscustomobject]@{ code='NR-IPV6-008'; title='IPv6 path unavailable'; solution='Verify the adapter has a global IPv6 address and AAAA DNS works.' }
    )
    $items=@($errors | ForEach-Object { New-NrMenuItem -Id $_.code -Label ($_.code + ' — ' + $_.title) -Section (T 'help') })
    $choice=Invoke-NrMenu -Title (T 'help') -Items $items -AllowEscape
    if (-not $choice) { return }
    $item=$errors | Where-Object { $_.code -eq $choice } | Select-Object -First 1
    Write-NrHeader -Title $item.code
    Write-Host ('  ' + $item.title) -ForegroundColor Red
    Write-Host ''
    Write-Host ('  ' + $item.solution) -ForegroundColor Gray
    Write-Host ''
    Write-Host '  Documentation: https://onmaynec.github.io/NexRoute/docs/diagnostics/' -ForegroundColor Cyan
    Wait-NrKey
}

function Show-NrDiagnosticsMenu {
    while ($true) {
        $items=@(
            New-NrMenuItem -Id 'status' -Label (T 'systemStatus') -Section (T 'diagnosticCore')
            New-NrMenuItem -Id 'availability' -Label (T 'availability') -Section (T 'diagnosticCore')
            New-NrMenuItem -Id 'conflicts' -Label (T 'conflicts') -Section (T 'diagnosticCore')
            New-NrMenuItem -Id 'repair' -Label (T 'repairService') -Section (T 'diagnosticCore')
            New-NrMenuItem -Id 'integrity' -Label (T 'integrity') -Section (T 'diagnosticCore')
            New-NrMenuItem -Id 'logs' -Label (T 'logs') -Section (T 'diagnosticCore')
            New-NrMenuItem -Id 'help' -Label (T 'help') -Section (T 'diagnosticCore')
            New-NrMenuItem -Id 'back' -Label (T 'back') -Section (T 'diagnosticCore')
        )
        $choice=Invoke-NrMenu -Title (T 'diagnosticCore') -Items $items -AllowEscape
        if (-not $choice -or $choice -eq 'back') { return }
        switch ($choice) {
            'status' { Show-NrSystemStatus }
            'availability' { Show-NrAvailabilityPanel }
            'conflicts' { Show-NrConflicts }
            'repair' { Repair-NrService }
            'integrity' { Show-NrIntegrity }
            'logs' { Show-NrLogMenu }
            'help' { Show-NrErrorCatalog }
        }
    }
}
