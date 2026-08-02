[CmdletBinding()]
param(
    [string]$Root,
    [switch]$Update,
    [switch]$Status,
    [switch]$Lab
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$next=Join-Path $PSScriptRoot 'next'
foreach ($module in @(
    'nexroute-common.ps1',
    'nexroute-strategies.ps1',
    'nexroute-network.ps1',
    'nexroute-diagnostics.ps1',
    'nexroute-management.ps1',
    'nexroute-update.ps1'
)) {
    $path=Join-Path $next $module
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "NexRoute module is missing: $module" }
    . $path
}
Initialize-NrEnvironment -RootPath $Root

function Get-NrGameFilterStatus {
    $path=Join-Path $script:NrRoot 'utils\game_filter.enabled'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return (T 'disabled') }
    try {
        $mode=(Get-Content -LiteralPath $path -Raw -Encoding ASCII).Trim().ToUpperInvariant()
        if ($mode) { return $mode }
    } catch { }
    return (T 'enabled')
}

function Get-NrIpSetMode {
    $path=Join-Path $script:NrRoot 'lists\ipset-all.txt'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return (T 'none') }
    $lines=@(Get-Content -LiteralPath $path -ErrorAction SilentlyContinue | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($lines.Count -eq 0) { return 'ANY' }
    if ($lines -contains '203.0.113.113/32') { return (T 'none') }
    return 'LOADED'
}

function Restart-NrCurrentStrategy {
    $controller=Join-Path $script:NrService 'nexroute-services.ps1'
    if (Test-Path -LiteralPath $controller) {
        try { & $controller -Mode Restart -Root $script:NrRoot | Out-Null; return } catch { }
    }
    $strategy=Get-NrInstalledStrategy
    $file=Get-NrStrategies | Where-Object { $_.Name -eq $strategy -or $_.BaseName -eq $strategy } | Select-Object -First 1
    if ($file) { Install-NrStrategy -Path $file.FullName -Reason 'configuration-refresh' | Out-Null }
}

function Show-NrGameFilterMenu {
    $current=Get-NrGameFilterStatus
    $items=@(
        New-NrMenuItem -Id 'disabled' -Label 'Disabled' -Section (T 'gameFilter') -Status $(if ($current -eq (T 'disabled')) { T 'current' } else { '' })
        New-NrMenuItem -Id 'all' -Label 'TCP + UDP' -Section (T 'gameFilter') -Status $(if ($current -eq 'ALL') { T 'current' } else { '' })
        New-NrMenuItem -Id 'tcp' -Label 'TCP only' -Section (T 'gameFilter') -Status $(if ($current -eq 'TCP') { T 'current' } else { '' })
        New-NrMenuItem -Id 'udp' -Label 'UDP only' -Section (T 'gameFilter') -Status $(if ($current -eq 'UDP') { T 'current' } else { '' })
        New-NrMenuItem -Id 'back' -Label (T 'back') -Section (T 'gameFilter')
    )
    $choice=Invoke-NrMenu -Title (T 'gameFilter') -Items $items -AllowEscape
    if (-not $choice -or $choice -eq 'back') { return }
    $path=Join-Path $script:NrRoot 'utils\game_filter.enabled'
    if ($choice -eq 'disabled') { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
    else {
        $parent=Split-Path -Parent $path
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        [IO.File]::WriteAllText($path,$choice+[Environment]::NewLine,[Text.Encoding]::ASCII)
    }
    try { Restart-NrCurrentStrategy } catch { }
    Show-NrMessage -Title (T 'gameFilter') -Message (T 'operationComplete') -Color Green
}

function Show-NrIpSetMenu {
    $current=Get-NrIpSetMode
    $items=@(
        New-NrMenuItem -Id 'loaded' -Label 'Loaded IPSET' -Section (T 'ipsetFilter') -Status $(if ($current -eq 'LOADED') { T 'current' } else { '' })
        New-NrMenuItem -Id 'any' -Label 'Any address' -Section (T 'ipsetFilter') -Status $(if ($current -eq 'ANY') { T 'current' } else { '' })
        New-NrMenuItem -Id 'none' -Label 'Disabled IPSET' -Section (T 'ipsetFilter') -Status $(if ($current -eq (T 'none')) { T 'current' } else { '' })
        New-NrMenuItem -Id 'back' -Label (T 'back') -Section (T 'ipsetFilter')
    )
    $choice=Invoke-NrMenu -Title (T 'ipsetFilter') -Items $items -AllowEscape
    if (-not $choice -or $choice -eq 'back') { return }
    $path=Join-Path $script:NrRoot 'lists\ipset-all.txt'
    $backup=$path+'.backup'
    try {
        switch ($choice) {
            'loaded' {
                if (Test-Path -LiteralPath $backup -PathType Leaf) { Copy-Item -LiteralPath $backup -Destination $path -Force }
                elseif (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-NrIpSetMode) -ne 'LOADED') { throw 'No downloaded IPSET is available. Run Update IPSET first.' }
            }
            'any' {
                if ((Get-NrIpSetMode) -eq 'LOADED') { Copy-Item -LiteralPath $path -Destination $backup -Force }
                [IO.File]::WriteAllText($path,'',[Text.Encoding]::ASCII)
            }
            'none' {
                if ((Get-NrIpSetMode) -eq 'LOADED') { Copy-Item -LiteralPath $path -Destination $backup -Force }
                [IO.File]::WriteAllText($path,"203.0.113.113/32`r`n",[Text.Encoding]::ASCII)
            }
        }
        Restart-NrCurrentStrategy
        Show-NrMessage -Title (T 'ipsetFilter') -Message (T 'operationComplete') -Color Green
    } catch { Show-NrMessage -Title (T 'operationFailed') -Message $_.Exception.Message -Color Red }
}

function Show-NrPayloadVault {
    $bin=Join-Path $script:NrRoot 'bin'
    $files=@(Get-ChildItem -LiteralPath $bin -Filter '*.bin' -File -ErrorAction SilentlyContinue | Where-Object { $_.BaseName -notlike 'ACTIVE_*' } | Sort-Object BaseName)
    if ($files.Count -eq 0) { Show-NrMessage -Title (T 'payloadVault') -Message (T 'noResults') -Color Yellow; return }
    $targetItems=@(
        New-NrMenuItem -Id 'discord' -Label 'Discord UDP payload' -Section (T 'payloadVault')
        New-NrMenuItem -Id 'game' -Label 'Game UDP payload' -Section (T 'payloadVault')
        New-NrMenuItem -Id 'back' -Label (T 'back') -Section (T 'payloadVault')
    )
    $target=Invoke-NrMenu -Title (T 'payloadVault') -Items $targetItems -AllowEscape
    if (-not $target -or $target -eq 'back') { return }
    $fileItems=@($files | ForEach-Object { New-NrMenuItem -Id $_.FullName -Label $_.BaseName -Section (T 'payloadVault') })
    $source=Invoke-NrMenu -Title (T 'payloadVault') -Items $fileItems -AllowEscape
    if (-not $source) { return }
    $destination=Join-Path $bin $(if ($target -eq 'discord') { 'ACTIVE_DISCORD_UDP.bin' } else { 'ACTIVE_GAME_UDP.bin' })
    Copy-Item -LiteralPath $source -Destination $destination -Force
    try { Restart-NrCurrentStrategy } catch { }
    Show-NrMessage -Title (T 'payloadVault') -Message (T 'operationComplete') -Color Green
}

function Invoke-NrLegacyUiMode {
    param([ValidateSet('SyncIpSet','SyncHosts','Services')][string]$Mode)
    $ui=Join-Path $script:NrService 'nexroute-ui.ps1'
    if (-not (Test-Path -LiteralPath $ui)) { throw 'Legacy UI module is missing.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ui -Mode $Mode -Root $script:NrRoot -LanguageFile (Join-Path $script:NrService 'language.txt')
}

function Show-NrStrategyTools {
    while ($true) {
        $items=@(
            New-NrMenuItem -Id 'lab' -Label (T 'labRun') -Section (T 'strategyLab')
            New-NrMenuItem -Id 'best' -Label (T 'bestInstall') -Section (T 'strategyLab')
            New-NrMenuItem -Id 'compare' -Label (T 'labCompare') -Section (T 'strategyLab')
            New-NrMenuItem -Id 'favorites' -Label (T 'favorites') -Section (T 'strategyLab')
            New-NrMenuItem -Id 'last' -Label (T 'lastWorking') -Section (T 'strategyLab')
            New-NrMenuItem -Id 'perService' -Label (T 'perService') -Section (T 'strategyLab')
            New-NrMenuItem -Id 'preview' -Label (T 'previewCommand') -Section (T 'strategyLab')
            New-NrMenuItem -Id 'back' -Label (T 'back') -Section (T 'strategyLab')
        )
        $choice=Invoke-NrMenu -Title (T 'strategyLab') -Items $items -AllowEscape
        if (-not $choice -or $choice -eq 'back') { return }
        switch ($choice) {
            'lab' { Invoke-NrStrategyLab }
            'best' { Install-NrBestStrategy }
            'compare' { Show-NrLabHistory }
            'favorites' { Toggle-NrFavoriteStrategy }
            'last' { Restore-NrLastWorkingStrategy }
            'perService' { Show-NrPerServiceMapping }
            'preview' { Show-NrStrategyPreview }
        }
    }
}

function Show-NrAdvancedToolkit {
    while ($true) {
        $items=@(
            New-NrMenuItem -Id 'lab' -Label (T 'strategyLab') -Section (T 'advancedToolkit')
            New-NrMenuItem -Id 'network' -Label (T 'networkDns') -Section (T 'advancedToolkit')
            New-NrMenuItem -Id 'backups' -Label (T 'backups') -Section (T 'advancedToolkit')
            New-NrMenuItem -Id 'configuration' -Label (T 'configuration') -Section (T 'advancedToolkit')
            New-NrMenuItem -Id 'statistics' -Label (T 'statistics') -Section (T 'advancedToolkit')
            New-NrMenuItem -Id 'settings' -Label (T 'settings') -Section (T 'advancedToolkit')
            New-NrMenuItem -Id 'updates' -Label (T 'checkUpdate') -Section (T 'advancedToolkit')
            New-NrMenuItem -Id 'back' -Label (T 'back') -Section (T 'advancedToolkit')
        )
        $choice=Invoke-NrMenu -Title (T 'advancedToolkit') -Items $items -AllowEscape
        if (-not $choice -or $choice -eq 'back') { return }
        switch ($choice) {
            'lab' { Show-NrStrategyTools }
            'network' { Show-NrNetworkMenu }
            'backups' { Show-NrBackupManager }
            'configuration' { Show-NrConfigurationManager }
            'statistics' { Show-NrStatisticsMenu }
            'settings' { Show-NrSettings }
            'updates' { Show-NrUpdateTools }
        }
    }
}

function Invoke-NrFirstRun {
    if ([bool]$script:NrState.firstRunComplete) { return }
    Write-NrHeader -Title (T 'firstRun')
    Write-Host '  Windows / PowerShell / administrator / service / DNS / IPv6 / conflicts' -ForegroundColor Cyan
    $report=Get-NrDiagnosticReport
    Write-Host ('  Administrator: ' + [string]$report.administrator) -ForegroundColor $(if ($report.administrator) { [ConsoleColor]::Green } else { [ConsoleColor]::Red })
    Write-Host ('  Service: ' + [string]$report.runtime.zapret) -ForegroundColor Gray
    Write-Host ('  Network: ' + [string]$report.network) -ForegroundColor Gray
    Write-Host ('  Conflicts: ' + @($report.conflicts | Where-Object { $_.detected }).Count) -ForegroundColor Yellow
    $script:NrState.firstRunComplete=$true
    Save-NrState
    Wait-NrKey
}

function Get-NrMainItems {
    $items=New-Object 'System.Collections.Generic.List[object]'
    $items.Add((New-NrMenuItem -Id 'install' -Label (T 'installConfig') -Section (T 'serviceControl') -HotKey 'I'))
    $items.Add((New-NrMenuItem -Id 'delete' -Label (T 'deleteConfig') -Section (T 'serviceControl') -HotKey 'D'))
    $items.Add((New-NrMenuItem -Id 'status' -Label (T 'systemStatus') -Section (T 'serviceControl') -Status $(if (Test-NrServiceRunning zapret) { T 'running' } else { T 'stopped' }) -HotKey 'S'))
    $items.Add((New-NrMenuItem -Id 'game' -Label (T 'gameFilter') -Section (T 'filterMatrix') -Status (Get-NrGameFilterStatus)))
    $items.Add((New-NrMenuItem -Id 'ipset' -Label (T 'ipsetFilter') -Section (T 'filterMatrix') -Status (Get-NrIpSetMode)))
    $items.Add((New-NrMenuItem -Id 'autoupdate' -Label (T 'autoUpdate') -Section (T 'filterMatrix') -Status $(if (Get-NrAutoUpdateEnabled) { T 'enabled' } else { T 'disabled' })))
    $items.Add((New-NrMenuItem -Id 'payload' -Label (T 'payloadVault') -Section (T 'filterMatrix')))
    $items.Add((New-NrMenuItem -Id 'syncipset' -Label (T 'updateIpset') -Section (T 'dataChannels')))
    $items.Add((New-NrMenuItem -Id 'synchosts' -Label (T 'updateHosts') -Section (T 'dataChannels')))
    $items.Add((New-NrMenuItem -Id 'update' -Label (T 'checkUpdate') -Section (T 'dataChannels') -HotKey 'U'))
    $items.Add((New-NrMenuItem -Id 'services' -Label (T 'serviceMatrix') -Section (T 'serviceBypass') -Status (Get-NrServiceSummary)))
    $items.Add((New-NrMenuItem -Id 'diagnostics' -Label (T 'diagnosticCore') -Section (T 'systemToolkit') -HotKey 'L'))
    $items.Add((New-NrMenuItem -Id 'lab' -Label (T 'checkingConfig') -Section (T 'systemToolkit') -HotKey 'T'))
    $items.Add((New-NrMenuItem -Id 'language' -Label (T 'switchLanguage') -Section (T 'systemToolkit') -Status $script:NrLanguage))
    if ([string]$script:NrState.mode -eq 'advanced') { $items.Add((New-NrMenuItem -Id 'advanced' -Label (T 'advancedToolkit') -Section (T 'systemToolkit') -Status (T 'advanced'))) }
    $items.Add((New-NrMenuItem -Id 'exit' -Label (T 'exit') -Section ''))
    return $items.ToArray()
}

function Start-NrConsole {
    Invoke-NrFirstRun
    while ($true) {
        $choice=Invoke-NrMenu -Title '' -Items (Get-NrMainItems)
        switch ($choice) {
            'install' { Show-NrInstallStrategy }
            'delete' { Remove-NrServices }
            'status' { Show-NrSystemStatus }
            'game' { Show-NrGameFilterMenu }
            'ipset' { Show-NrIpSetMenu }
            'autoupdate' { $enabled=-not (Get-NrAutoUpdateEnabled); Set-NrAutoUpdateEnabled -Enabled $enabled }
            'payload' { Show-NrPayloadVault }
            'syncipset' { try { Invoke-NrLegacyUiMode -Mode SyncIpSet } catch { Show-NrMessage -Title (T 'operationFailed') -Message $_.Exception.Message -Color Red } }
            'synchosts' { try { Invoke-NrLegacyUiMode -Mode SyncHosts } catch { Show-NrMessage -Title (T 'operationFailed') -Message $_.Exception.Message -Color Red } }
            'update' { Invoke-NrCheckUpdate }
            'services' { try { Invoke-NrLegacyUiMode -Mode Services } catch { Show-NrMessage -Title (T 'operationFailed') -Message $_.Exception.Message -Color Red } }
            'diagnostics' { Show-NrDiagnosticsMenu }
            'lab' { Show-NrStrategyTools }
            'language' {
                $script:NrLanguage=if ($script:NrLanguage -eq 'RU') { 'EN' } else { 'RU' }
                $script:NrState.language=$script:NrLanguage; $script:NrText=$script:NrTranslations[$script:NrLanguage]
                [IO.File]::WriteAllText((Join-Path $script:NrService 'language.txt'),$script:NrLanguage+[Environment]::NewLine,[Text.Encoding]::ASCII)
                Save-NrState
            }
            'advanced' { Show-NrAdvancedToolkit }
            'exit' { return }
        }
    }
}

if ($Update) { Invoke-NrCheckUpdate; exit 0 }
if ($Status) { Show-NrSystemStatus; exit 0 }
if ($Lab) { Show-NrStrategyTools; exit 0 }
Start-NrConsole
