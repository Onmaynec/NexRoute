Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Copy-NrDirectoryContents {
    param([Parameter(Mandatory)][string]$Source,[Parameter(Mandatory)][string]$Destination)
    if (-not (Test-Path -LiteralPath $Destination -PathType Container)) { New-Item -ItemType Directory -Path $Destination -Force | Out-Null }
    foreach ($item in @(Get-ChildItem -LiteralPath $Source -Force -ErrorAction Stop)) {
        $target=Join-Path $Destination $item.Name
        if ($item.PSIsContainer) { Copy-NrDirectoryContents -Source $item.FullName -Destination $target }
        else { Copy-Item -LiteralPath $item.FullName -Destination $target -Force }
    }
}

function Get-NrBackupRoot {
    return Join-Path (Split-Path -Parent $script:NrRoot) 'NexRoute-backups'
}

function New-NrManualBackup {
    $root=Get-NrBackupRoot
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $versionPath=Join-Path $script:NrService 'version.txt'
    $version=if (Test-Path -LiteralPath $versionPath) { (Get-Content -LiteralPath $versionPath -Raw -Encoding UTF8).Trim() } else { 'unknown' }
    $destination=Join-Path $root ('manual-' + $version + '-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    Copy-NrDirectoryContents -Source $script:NrRoot -Destination $destination
    Write-NrLog -Level INFO -Message 'Manual backup created' -Data @{ path=$destination; version=$version }
    Show-NrMessage -Title (T 'backups') -Message $destination -Color Green
}

function Get-NrBackups {
    $root=Get-NrBackupRoot
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { return @() }
    $items=New-Object 'System.Collections.Generic.List[object]'
    foreach ($directory in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending)) {
        $version='unknown'
        $versionPath=Join-Path $directory.FullName '.service\version.txt'
        if (Test-Path -LiteralPath $versionPath) { try { $version=(Get-Content -LiteralPath $versionPath -Raw -Encoding UTF8).Trim() } catch { } }
        $items.Add([pscustomobject]@{ Name=$directory.Name; FullName=$directory.FullName; Version=$version; Date=$directory.LastWriteTime; SizeBytes=(Get-ChildItem -LiteralPath $directory.FullName -File -Recurse -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum })
    }
    return $items.ToArray()
}

function Restore-NrBackup {
    param([Parameter(Mandatory)]$Backup)
    if (-not (Confirm-NrY -Message ('Restore NexRoute ' + $Backup.Version + ' from ' + $Backup.Name + '? Press Y to confirm.'))) { return }
    $safetyRoot=Get-NrBackupRoot
    $safety=Join-Path $safetyRoot ('restore-safety-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Path $safety -Force | Out-Null
    Copy-NrDirectoryContents -Source $script:NrRoot -Destination $safety
    Stop-NrStrategyRuntime
    try {
        Copy-NrDirectoryContents -Source $Backup.FullName -Destination $script:NrRoot
        $newVersion=(Get-Content -LiteralPath (Join-Path $script:NrRoot '.service\version.txt') -Raw -Encoding UTF8).Trim()
        if ($newVersion -ne $Backup.Version) { throw 'Restored version validation failed.' }
        Write-NrLog -Level INFO -Message 'Backup restored' -Data @{ backup=$Backup.FullName; safety=$safety }
        Send-NrNotification -Title 'NexRoute' -Message ('Restored version ' + $newVersion) -Level Info
        Start-Process -FilePath (Join-Path $script:NrRoot 'nexroute.bat') -WorkingDirectory $script:NrRoot
        exit 0
    } catch {
        Copy-NrDirectoryContents -Source $safety -Destination $script:NrRoot
        throw
    }
}

function Show-NrBackupManager {
    while ($true) {
        $items=New-Object 'System.Collections.Generic.List[object]'
        $items.Add((New-NrMenuItem -Id '__create' -Label 'Create manual backup' -Section (T 'backups')))
        foreach ($backup in @(Get-NrBackups)) {
            $items.Add((New-NrMenuItem -Id $backup.FullName -Label $backup.Name -Section (T 'backups') -Status ($backup.Version + ' / ' + $backup.Date.ToString('g'))))
        }
        $items.Add((New-NrMenuItem -Id '__back' -Label (T 'back') -Section (T 'backups')))
        $choice=Invoke-NrMenu -Title (T 'backups') -Items $items.ToArray() -AllowEscape
        if (-not $choice -or $choice -eq '__back') { return }
        if ($choice -eq '__create') { New-NrManualBackup; continue }
        $backup=Get-NrBackups | Where-Object { $_.FullName -eq $choice } | Select-Object -First 1
        if ($backup) { Restore-NrBackup -Backup $backup }
    }
}

function Get-NrConfigPaths {
    return @(
        '.service/next-state.json','.service/services-state.json','.service/custom-services.json','.service/user-list-integrity.json',
        'utils/check_updates.enabled','utils/game_filter.enabled','lists/list-general-user.txt','lists/list-exclude-user.txt',
        'lists/ipset-services-user.txt','lists/ipset-exclude-user.txt','lists/ipset-all.txt'
    )
}

function Export-NrConfiguration {
    $stamp=[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
    $temp=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-config-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temp -Force | Out-Null
    try {
        foreach ($relative in Get-NrConfigPaths) {
            $source=Join-Path $script:NrRoot $relative
            if (-not (Test-Path -LiteralPath $source)) { continue }
            $target=Join-Path $temp $relative
            $parent=Split-Path -Parent $target
            if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            Copy-Item -LiteralPath $source -Destination $target -Force -Recurse
        }
        $manifest=[ordered]@{ schemaVersion=1; exportedUtc=[DateTime]::UtcNow.ToString('o'); version=(Get-Content -LiteralPath (Join-Path $script:NrService 'version.txt') -Raw -Encoding UTF8).Trim(); files=Get-NrConfigPaths }
        [IO.File]::WriteAllText((Join-Path $temp 'NEXROUTE_CONFIG.json'),($manifest | ConvertTo-Json -Depth 10)+[Environment]::NewLine,(New-Object Text.UTF8Encoding($false)))
        $destination=Join-Path ([Environment]::GetFolderPath('Desktop')) ('NexRoute-config-' + $stamp + '.zip')
        Compress-Archive -Path (Join-Path $temp '*') -DestinationPath $destination -CompressionLevel Optimal -Force
        Show-NrMessage -Title (T 'export') -Message $destination -Color Green
    } finally { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
}

function Select-NrZipFile {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $dialog=New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Filter='ZIP archives (*.zip)|*.zip'
        $dialog.Title='NexRoute configuration import'
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dialog.FileName }
    } catch { }
    Write-NrHeader -Title (T 'import')
    return Read-Host ('  ' + (T 'inputPrompt'))
}

function Import-NrConfiguration {
    $archive=Select-NrZipFile
    if ([string]::IsNullOrWhiteSpace($archive) -or -not (Test-Path -LiteralPath $archive -PathType Leaf)) { return }
    $temp=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-import-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temp -Force | Out-Null
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip=[IO.Compression.ZipFile]::OpenRead($archive)
        try {
            foreach ($entry in $zip.Entries) {
                if ($entry.FullName -match '(^|[\\/])\.\.([\\/]|$)' -or [IO.Path]::IsPathRooted($entry.FullName)) { throw 'Unsafe path in configuration archive: ' + $entry.FullName }
            }
        } finally { $zip.Dispose() }
        Expand-Archive -LiteralPath $archive -DestinationPath $temp -Force
        $manifestPath=Join-Path $temp 'NEXROUTE_CONFIG.json'
        if (-not (Test-Path -LiteralPath $manifestPath)) { throw 'NEXROUTE_CONFIG.json is missing.' }
        foreach ($relative in Get-NrConfigPaths) {
            $source=Join-Path $temp $relative
            if (-not (Test-Path -LiteralPath $source)) { continue }
            $target=Join-Path $script:NrRoot $relative
            $parent=Split-Path -Parent $target
            if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            Copy-Item -LiteralPath $source -Destination $target -Force -Recurse
        }
        $script:NrState=Read-NrState
        $script:NrLanguage=[string]$script:NrState.language
        $script:NrText=$script:NrTranslations[$script:NrLanguage]
        $controller=Join-Path $script:NrService 'nexroute-services.ps1'
        if (Test-Path -LiteralPath $controller) { & $controller -Mode Apply -Root $script:NrRoot | Out-Null }
        Show-NrMessage -Title (T 'import') -Message (T 'operationComplete') -Color Green
    } catch { Show-NrMessage -Title (T 'operationFailed') -Message $_.Exception.Message -Color Red }
    finally { Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue }
}

function Ensure-NrCustomServicesFile {
    $path=Join-Path $script:NrService 'custom-services.json'
    if (-not (Test-Path -LiteralPath $path)) {
        $template=[ordered]@{
            schemaVersion=1
            services=@(
                [ordered]@{
                    id='custom-example'; nameEn='Custom Example'; nameRu='Пользовательский пример'; descriptionEn='User-managed service profile'; descriptionRu='Пользовательский профиль сервиса';
                    defaultEnabled=$false; domains=@('example.com'); testTargets=@([ordered]@{ name='HTTPS'; role='HTTPS'; url='https://example.com' });
                    tcpPorts=@('443'); udpPorts=@(); resolveHosts=@('example.com'); ipCidrs=@(); ipSources=@()
                }
            )
        }
        [IO.File]::WriteAllText($path,($template | ConvertTo-Json -Depth 20)+[Environment]::NewLine,(New-Object Text.UTF8Encoding($false)))
    }
    return $path
}

function Validate-NrCustomServices {
    $path=Ensure-NrCustomServicesFile
    $document=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    $ids=New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($service in @($document.services)) {
        if ([string]::IsNullOrWhiteSpace([string]$service.id) -or [string]$service.id -notmatch '^[a-z0-9][a-z0-9_-]{1,39}$') { throw 'Invalid custom service id.' }
        if (-not $ids.Add([string]$service.id)) { throw 'Duplicate custom service id: ' + $service.id }
        if (@($service.domains).Count -eq 0 -and @($service.ipCidrs).Count -eq 0) { throw 'Custom service requires domains or IP CIDRs: ' + $service.id }
        foreach ($port in @($service.tcpPorts)+@($service.udpPorts)) {
            if ([string]$port -notmatch '^\d{1,5}(-\d{1,5})?$') { throw 'Invalid port in custom service ' + $service.id + ': ' + $port }
        }
        foreach ($cidr in @($service.ipCidrs)) {
            $parts=[string]$cidr -split '/',2
            $address=$null; $prefix=0
            if ($parts.Count -ne 2 -or -not [Net.IPAddress]::TryParse($parts[0],[ref]$address) -or -not [int]::TryParse($parts[1],[ref]$prefix)) { throw 'Invalid CIDR: ' + $cidr }
            $max=if ($address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork) { 32 } else { 128 }
            if ($prefix -lt 0 -or $prefix -gt $max) { throw 'Invalid CIDR prefix: ' + $cidr }
        }
    }
    return @($document.services).Count
}

function Show-NrCustomProfileManager {
    while ($true) {
        $items=@(
            New-NrMenuItem -Id 'editProfiles' -Label (T 'customProfiles') -Section (T 'configuration')
            New-NrMenuItem -Id 'domains' -Label 'Edit user domains' -Section (T 'configuration')
            New-NrMenuItem -Id 'ips' -Label 'Edit IP / IPv6 ranges' -Section (T 'configuration')
            New-NrMenuItem -Id 'ports' -Label 'Edit TCP / UDP ports' -Section (T 'configuration')
            New-NrMenuItem -Id 'validate' -Label (T 'validateConfig') -Section (T 'configuration')
            New-NrMenuItem -Id 'apply' -Label (T 'save') -Section (T 'configuration') -Status 'APPLY'
            New-NrMenuItem -Id 'back' -Label (T 'back') -Section (T 'configuration')
        )
        $choice=Invoke-NrMenu -Title (T 'customProfiles') -Items $items -AllowEscape
        if (-not $choice -or $choice -eq 'back') { return }
        switch ($choice) {
            'editProfiles' { Open-NrTextFile -Path (Ensure-NrCustomServicesFile) }
            'domains' { Open-NrTextFile -Path (Join-Path $script:NrRoot 'lists\list-general-user.txt') }
            'ips' { Open-NrTextFile -Path (Join-Path $script:NrRoot 'lists\ipset-services-user.txt') }
            'ports' { Open-NrTextFile -Path (Ensure-NrCustomServicesFile) }
            'validate' { try { $count=Validate-NrCustomServices; Show-NrMessage -Title (T 'validateConfig') -Message ('Custom profiles: ' + $count) -Color Green } catch { Show-NrMessage -Title (T 'operationFailed') -Message $_.Exception.Message -Color Red } }
            'apply' {
                try {
                    [void](Validate-NrCustomServices)
                    $controller=Join-Path $script:NrService 'nexroute-services.ps1'
                    & $controller -Mode Apply -Root $script:NrRoot | Out-Null
                    Show-NrMessage -Title (T 'customProfiles') -Message (T 'operationComplete') -Color Green
                } catch { Show-NrMessage -Title (T 'operationFailed') -Message $_.Exception.Message -Color Red }
            }
        }
    }
}

function Show-NrConfigurationManager {
    while ($true) {
        $items=@(
            New-NrMenuItem -Id 'export' -Label (T 'export') -Section (T 'configuration')
            New-NrMenuItem -Id 'import' -Label (T 'import') -Section (T 'configuration')
            New-NrMenuItem -Id 'profiles' -Label (T 'customProfiles') -Section (T 'configuration')
            New-NrMenuItem -Id 'strategy' -Label (T 'customStrategy') -Section (T 'configuration')
            New-NrMenuItem -Id 'preview' -Label (T 'previewCommand') -Section (T 'configuration')
            New-NrMenuItem -Id 'back' -Label (T 'back') -Section (T 'configuration')
        )
        $choice=Invoke-NrMenu -Title (T 'configuration') -Items $items -AllowEscape
        if (-not $choice -or $choice -eq 'back') { return }
        switch ($choice) {
            'export' { Export-NrConfiguration }
            'import' { Import-NrConfiguration }
            'profiles' { Show-NrCustomProfileManager }
            'strategy' { Show-NrCustomStrategyBuilder }
            'preview' { Show-NrStrategyPreview }
        }
    }
}

function Get-NrAvailabilityHistory {
    $path=Join-Path $script:NrHistoryDir 'availability.jsonl'
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    $items=New-Object 'System.Collections.Generic.List[object]'
    foreach ($line in @(Get-Content -LiteralPath $path -Encoding UTF8 -Tail 5000)) { try { $items.Add(($line | ConvertFrom-Json)) } catch { } }
    return $items.ToArray()
}

function Get-NrSparkline {
    param([double[]]$Values,[int]$Width=50)
    if ($Values.Count -eq 0) { return '' }
    $chars=@(' ','_','.','-','=','+','*','#','@')
    $sample=@($Values | Select-Object -Last $Width)
    $min=[double](($sample | Measure-Object -Minimum).Minimum); $max=[double](($sample | Measure-Object -Maximum).Maximum)
    $range=[Math]::Max(0.001,$max-$min)
    $builder=New-Object Text.StringBuilder
    foreach ($value in $sample) {
        $index=[int][Math]::Round((($value-$min)/$range)*($chars.Count-1))
        [void]$builder.Append($chars[[Math]::Min([Math]::Max($index,0),$chars.Count-1)])
    }
    return $builder.ToString()
}

function Show-NrStatistics {
    $history=@(Get-NrAvailabilityHistory)
    Write-NrHeader -Title (T 'statistics')
    if ($history.Count -eq 0) { Write-Host ('  ' + (T 'noResults')) -ForegroundColor Yellow; Wait-NrKey; return }
    $groups=$history | Group-Object serviceId
    foreach ($group in $groups) {
        $uptime=@($group.Group | ForEach-Object { if ($_.ok) { 100.0 } else { 0.0 } })
        $latency=@($group.Group | ForEach-Object { [double]$_.latencyMs })
        $up=[math]::Round((($uptime | Measure-Object -Average).Average),2)
        $avg=[math]::Round((($latency | Measure-Object -Average).Average),2)
        Write-Host ('  {0,-24} uptime={1,6:N1}% avg={2,8:N1}ms  {3}' -f $group.Name,$up,$avg,(Get-NrSparkline -Values $uptime -Width 36)) -ForegroundColor $(if ($up -ge 95) { [ConsoleColor]::Green } elseif ($up -ge 80) { [ConsoleColor]::Yellow } else { [ConsoleColor]::Red })
    }
    Wait-NrKey
}

function Export-NrStatistics {
    $history=@(Get-NrAvailabilityHistory)
    if ($history.Count -eq 0) { Show-NrMessage -Title (T 'exportStats') -Message (T 'noResults') -Color Yellow; return }
    $stamp=[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
    $desktop=[Environment]::GetFolderPath('Desktop')
    $json=Join-Path $desktop ('NexRoute-statistics-' + $stamp + '.json')
    $csv=Join-Path $desktop ('NexRoute-statistics-' + $stamp + '.csv')
    [IO.File]::WriteAllText($json,($history | ConvertTo-Json -Depth 15)+[Environment]::NewLine,(New-Object Text.UTF8Encoding($false)))
    $history | Select-Object timestampUtc,serviceId,name,ok,latencyMs,consecutiveFailures,strategy,network | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
    Show-NrMessage -Title (T 'exportStats') -Message ($json + [Environment]::NewLine + $csv) -Color Green
}

function Set-NrBackgroundFeature {
    param([ValidateSet('monitor','tray')][string]$Feature,[bool]$Enabled)
    $scriptName=if ($Feature -eq 'monitor') { 'nexroute-monitor.ps1' } else { 'nexroute-tray.ps1' }
    $taskName=if ($Feature -eq 'monitor') { 'NexRoute Health Monitor' } else { 'NexRoute Tray Controller' }
    $scriptPath=Join-Path $script:NrService $scriptName
    if ($Enabled) {
        $taskCommand='powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $scriptPath + '" -Root "' + $script:NrRoot + '"'
        & schtasks.exe /Create /TN $taskName /SC ONLOGON /RL HIGHEST /TR $taskCommand /F | Out-Null
        Start-Process powershell.exe -ArgumentList @('-NoProfile','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',$scriptPath,'-Root',$script:NrRoot) -WindowStyle Hidden | Out-Null
    } else {
        & schtasks.exe /Delete /TN $taskName /F 2>$null | Out-Null
        $pattern=[regex]::Escape($scriptName)
        try {
            Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" | Where-Object { $_.CommandLine -match $pattern } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        } catch { }
    }
    if ($Feature -eq 'monitor') { $script:NrState.monitorEnabled=$Enabled } else { $script:NrState.trayEnabled=$Enabled }
    Save-NrState
}

function Show-NrSettings {
    while ($true) {
        $items=@(
            New-NrMenuItem -Id 'mode' -Label (T 'interfaceMode') -Section (T 'settings') -Status ([string]$script:NrState.mode)
            New-NrMenuItem -Id 'theme' -Label (T 'theme') -Section (T 'settings') -Status ([string]$script:NrState.theme)
            New-NrMenuItem -Id 'accent' -Label (T 'accent') -Section (T 'settings') -Status ([string]$script:NrState.accent)
            New-NrMenuItem -Id 'language' -Label (T 'language') -Section (T 'settings') -Status $script:NrLanguage
            New-NrMenuItem -Id 'safe' -Label (T 'safeMode') -Section (T 'settings') -Status $(if ($script:NrState.safeMode) { T 'enabled' } else { T 'disabled' })
            New-NrMenuItem -Id 'monitor' -Label (T 'monitor') -Section (T 'settings') -Status $(if ($script:NrState.monitorEnabled) { T 'enabled' } else { T 'disabled' })
            New-NrMenuItem -Id 'autoswitch' -Label (T 'autoSwitch') -Section (T 'settings') -Status $(if ($script:NrState.autoSwitchEnabled) { T 'enabled' } else { T 'disabled' })
            New-NrMenuItem -Id 'tray' -Label (T 'tray') -Section (T 'settings') -Status $(if ($script:NrState.trayEnabled) { T 'enabled' } else { T 'disabled' })
            New-NrMenuItem -Id 'hotkeys' -Label (T 'hotkeys') -Section (T 'settings') -Status 'F1/F2/U/L'
            New-NrMenuItem -Id 'back' -Label (T 'back') -Section (T 'settings')
        )
        $choice=Invoke-NrMenu -Title (T 'settings') -Items $items -AllowEscape
        if (-not $choice -or $choice -eq 'back') { return }
        switch ($choice) {
            'mode' { $script:NrState.mode=if ([string]$script:NrState.mode -eq 'beginner') { 'advanced' } else { 'beginner' }; Save-NrState }
            'theme' { $script:NrState.theme=if ([string]$script:NrState.theme -eq 'dark') { 'light' } else { 'dark' }; Save-NrState }
            'accent' {
                $colors=@('Cyan','Green','Magenta','Yellow','Blue','White')
                $colorItems=@($colors | ForEach-Object { New-NrMenuItem -Id $_ -Label $_ -Section (T 'accent') })
                $selected=Invoke-NrMenu -Title (T 'accent') -Items $colorItems -AllowEscape
                if ($selected) { $script:NrState.accent=$selected; Save-NrState }
            }
            'language' {
                $script:NrLanguage=if ($script:NrLanguage -eq 'RU') { 'EN' } else { 'RU' }
                $script:NrState.language=$script:NrLanguage; $script:NrText=$script:NrTranslations[$script:NrLanguage]
                [IO.File]::WriteAllText((Join-Path $script:NrService 'language.txt'),$script:NrLanguage+[Environment]::NewLine,[Text.Encoding]::ASCII)
                Save-NrState
            }
            'safe' { $script:NrState.safeMode=-not [bool]$script:NrState.safeMode; Save-NrState }
            'monitor' { Set-NrBackgroundFeature -Feature monitor -Enabled (-not [bool]$script:NrState.monitorEnabled) }
            'autoswitch' { $script:NrState.autoSwitchEnabled=-not [bool]$script:NrState.autoSwitchEnabled; Save-NrState }
            'tray' { Set-NrBackgroundFeature -Feature tray -Enabled (-not [bool]$script:NrState.trayEnabled) }
            'hotkeys' { Show-NrMessage -Title (T 'hotkeys') -Message 'F1: status   F2: Strategy Lab   U: Check Update   L: logs   ESC: back' -Color Cyan }
        }
    }
}

function Show-NrStatisticsMenu {
    $items=@(
        New-NrMenuItem -Id 'charts' -Label (T 'charts') -Section (T 'statistics')
        New-NrMenuItem -Id 'export' -Label (T 'exportStats') -Section (T 'statistics')
        New-NrMenuItem -Id 'back' -Label (T 'back') -Section (T 'statistics')
    )
    $choice=Invoke-NrMenu -Title (T 'statistics') -Items $items -AllowEscape
    if ($choice -eq 'charts') { Show-NrStatistics }
    elseif ($choice -eq 'export') { Export-NrStatistics }
}
