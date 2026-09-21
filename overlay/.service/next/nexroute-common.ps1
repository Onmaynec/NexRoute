Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-NrDefaultLanguage {
    try {
        $culture = [System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName
        if ($culture -eq 'ru') { return 'RU' }
    } catch { }
    return 'EN'
}

$script:NrTranslations = @{
    EN = @{
        appTitle='NEXROUTE CONTROL NODE'; tagline='NETWORK ROUTE CONTROL SYSTEM';
        serviceControl='SERVICE CONTROL'; filterMatrix='FILTER MATRIX'; dataChannels='DATA CHANNELS';
        serviceBypass='SERVICE BYPASS'; systemToolkit='SYSTEM TOOLKIT'; advancedToolkit='ADVANCED TOOLKIT';
        installConfig='Installing Config'; deleteConfig='Deleting Config'; systemStatus='System Status';
        gameFilter='Game Traffic Filter'; ipsetFilter='Filter IPSET'; autoUpdate='Auto-Check Update'; payloadVault='Fake Payload VAULT';
        updateIpset='Update IPSET'; updateHosts='Update HOSTS'; checkUpdate='Check Update'; serviceMatrix='Bypassing Services / SERVICE MATRIX';
        diagnosticCore='Diagnostic Core'; checkingConfig='STRATEGY LAB'; switchLanguage='Switch Language'; exit='Disconnect / Exit';
        strategyLab='Strategy Lab'; autoBest='Automatically choose best strategy'; installSelected='Install selected strategy';
        favorites='Favorite strategies'; history='Strategy history'; availability='Service availability';
        networkDns='Network and DNS'; backups='Backup manager'; configuration='Configuration manager';
        logs='Logs and reports'; settings='Interface and mode'; monitor='Continuous monitor'; statistics='Local statistics';
        safeMode='Safe mode'; tray='System tray'; help='Error catalog and help'; back='Back'; cancel='Cancel';
        enabled='ENABLED'; disabled='DISABLED'; running='RUNNING'; stopped='STOPPED'; none='NONE'; current='CURRENT';
        pressKey='Press any key to continue'; arrows='ARROWS: move  ENTER: select  ESC: back';
        confirmUpdate='Install the downloaded update? Press Y to confirm or any other key to cancel.';
        updateChecking='Checking the stable release channel'; updateCurrent='NexRoute is already up to date.';
        updateAvailable='A new NexRoute release is available.'; updateInstalling='Downloading, verifying and installing the update';
        updateDone='Update installed. Restarting NexRoute...'; updateCancelled='Update cancelled.';
        selectStrategy='SELECT A STRATEGY'; selectItems='SPACE: select  ENTER: continue  ESC: cancel';
        noResults='No results are available yet.'; operationFailed='Operation failed'; operationComplete='Operation completed';
        beginner='BEGINNER'; advanced='ADVANCED'; dark='DARK'; light='LIGHT';
        save='Save'; edit='Edit'; export='Export'; import='Import'; reset='Reset'; repair='Repair';
        dnsDiagnostics='DNS diagnostics'; dnsProvider='Choose DNS provider'; doh='DNS-over-HTTPS'; dot='DNS-over-TLS';
        adapters='Network adapters'; networkProfiles='Network profiles'; provider='Internet provider';
        conflicts='VPN / antivirus / firewall conflicts'; resetNetwork='Reset Windows network stack';
        repairService='Repair damaged service'; integrity='User-list integrity'; diagnosticZip='Create diagnostic ZIP';
        copyReport='Copy diagnostic report'; logViewer='View logs'; logSearch='Search logs';
        labRun='Run Strategy Lab'; labCompare='Compare previous Strategy Lab runs'; labRecommend='Show recommendation';
        bestInstall='Install best measured strategy'; autoSwitch='Automatic strategy failover'; perService='Per-service strategy mapping';
        customProfiles='Custom service profiles'; customStrategy='Custom strategy builder'; previewCommand='Preview winws command';
        validateConfig='Validate configuration'; favoriteToggle='Toggle favorite'; lastWorking='Return to last working strategy';
        speed='Download speed'; jitter='Jitter'; packetLoss='Packet loss'; youtube='YouTube video readiness';
        discordVoice='Discord voice readiness'; telegramVoice='Telegram voice readiness';
        exportStats='Export statistics'; charts='Stability charts'; hotkeys='Hotkeys'; accent='Accent color'; labPreflight='Preflight'; labRunAll='Test all strategies'; labRunSelected='Test selected strategies'; labRound='Round'; labChecks='Checks'; labPassed='Passed'; labFailed='Failed'; labWarnings='Warnings'; labElapsed='Elapsed'; labControl='Control'; labResult='Result'; labDpiFreeze='DPI freeze'; labDns='DNS'; labTls='TLS'; labHttp='HTTP'; labThroughput='Throughput'; labMedia='Media';
        firstRun='First-run diagnostics'; ipv6='IPv6 support'; attestation='Verify GitHub attestation'; sha='Downloaded SHA-256';
        trayEnable='Enable tray controller'; trayDisable='Disable tray controller'; monitorEnable='Enable health monitor'; monitorDisable='Disable health monitor';
        theme='Theme'; interfaceMode='Interface mode'; language='Language';
        inputPrompt='Enter text and press Enter'; notAvailable='NOT AVAILABLE'; experimental='EXPERIMENTAL';
        statusStrategy='Installed strategy'; statusZapret='zapret service'; statusWinDivert='WinDivert driver'; statusEngine='winws process';
        statusProfiles='Enabled service profiles'; statusMonitor='Health monitor'; statusNetwork='Active network'; statusVersion='Version';
        purgeConfirm='Delete NexRoute and WinDivert services? Press Y to confirm.';
        purgeDone='NexRoute and WinDivert services were removed.';
        installDone='Strategy installed as a Windows service.';
        autoCheckOn='Automatic update checks enabled.'; autoCheckOff='Automatic update checks disabled.';
        restarted='Service restarted.'; noStrategies='No strategy files were found.';
    }
    RU = @{
        appTitle='ЦЕНТР УПРАВЛЕНИЯ NEXROUTE'; tagline='СИСТЕМА УПРАВЛЕНИЯ СЕТЕВЫМИ МАРШРУТАМИ';
        serviceControl='УПРАВЛЕНИЕ СЛУЖБОЙ'; filterMatrix='МАТРИЦА ФИЛЬТРОВ'; dataChannels='КАНАЛЫ ДАННЫХ';
        serviceBypass='ОБХОД СЕРВИСОВ'; systemToolkit='СИСТЕМНЫЕ ИНСТРУМЕНТЫ'; advancedToolkit='РАСШИРЕННЫЕ ИНСТРУМЕНТЫ';
        installConfig='Установка конфигурации'; deleteConfig='Удаление конфигурации'; systemStatus='Состояние системы';
        gameFilter='Фильтр игрового трафика'; ipsetFilter='Фильтр IPSET'; autoUpdate='Автопроверка обновлений'; payloadVault='Хранилище Fake Payload';
        updateIpset='Обновить IPSET'; updateHosts='Обновить HOSTS'; checkUpdate='Проверить обновление'; serviceMatrix='Обход сервисов / МАТРИЦА СЕРВИСОВ';
        diagnosticCore='Диагностический центр'; checkingConfig='Лаборатория стратегий'; switchLanguage='Сменить язык'; exit='Отключиться / Выход';
        strategyLab='Лаборатория стратегий'; autoBest='Автоматически выбрать лучшую стратегию'; installSelected='Установить выбранную стратегию';
        favorites='Избранные стратегии'; history='История стратегий'; availability='Доступность сервисов';
        networkDns='Сеть и DNS'; backups='Менеджер резервных копий'; configuration='Управление конфигурацией';
        logs='Логи и отчёты'; settings='Интерфейс и режим'; monitor='Непрерывный мониторинг'; statistics='Локальная статистика';
        safeMode='Безопасный режим'; tray='Системный трей'; help='Каталог ошибок и помощь'; back='Назад'; cancel='Отмена';
        enabled='ВКЛЮЧЕНО'; disabled='ВЫКЛЮЧЕНО'; running='РАБОТАЕТ'; stopped='ОСТАНОВЛЕНО'; none='НЕТ'; current='ТЕКУЩАЯ';
        pressKey='Нажмите любую клавишу, чтобы продолжить'; arrows='СТРЕЛКИ: выбор  ENTER: открыть  ESC: назад';
        confirmUpdate='Установить загруженное обновление? Нажмите Y для подтверждения или любую другую клавишу для отмены.';
        updateChecking='Проверка стабильного канала обновлений'; updateCurrent='Установлена актуальная версия NexRoute.';
        updateAvailable='Доступна новая версия NexRoute.'; updateInstalling='Загрузка, проверка и установка обновления';
        updateDone='Обновление установлено. Перезапуск NexRoute...'; updateCancelled='Обновление отменено.';
        selectStrategy='ВЫБОР СТРАТЕГИИ'; selectItems='ПРОБЕЛ: выбрать  ENTER: продолжить  ESC: отмена';
        noResults='Результаты пока отсутствуют.'; operationFailed='Ошибка операции'; operationComplete='Операция завершена';
        beginner='ДЛЯ НАЧИНАЮЩИХ'; advanced='РАСШИРЕННЫЙ'; dark='ТЁМНАЯ'; light='СВЕТЛАЯ';
        save='Сохранить'; edit='Изменить'; export='Экспорт'; import='Импорт'; reset='Сброс'; repair='Восстановить';
        dnsDiagnostics='Диагностика DNS'; dnsProvider='Выбрать DNS-провайдера'; doh='DNS-over-HTTPS'; dot='DNS-over-TLS';
        adapters='Сетевые адаптеры'; networkProfiles='Сетевые профили'; provider='Интернет-провайдер';
        conflicts='Конфликты VPN / антивируса / файрвола'; resetNetwork='Сброс сетевого стека Windows';
        repairService='Восстановление повреждённой службы'; integrity='Целостность пользовательских списков'; diagnosticZip='Создать диагностический ZIP';
        copyReport='Копировать диагностический отчёт'; logViewer='Просмотр логов'; logSearch='Поиск по логам';
        labRun='Запустить лабораторию стратегий'; labCompare='Сравнить предыдущие запуски'; labRecommend='Показать рекомендацию';
        bestInstall='Установить лучшую измеренную стратегию'; autoSwitch='Автопереключение стратегии'; perService='Стратегии по отдельным сервисам';
        customProfiles='Пользовательские профили сервисов'; customStrategy='Конструктор пользовательских стратегий'; previewCommand='Предпросмотр команды winws';
        validateConfig='Проверить конфигурацию'; favoriteToggle='Добавить или убрать из избранного'; lastWorking='Вернуться к последней рабочей стратегии';
        speed='Скорость загрузки'; jitter='Джиттер'; packetLoss='Потеря пакетов'; youtube='Готовность видеопотока YouTube';
        discordVoice='Готовность голосовой связи Discord'; telegramVoice='Готовность голосовой связи Telegram';
        exportStats='Экспорт статистики'; charts='Графики стабильности'; hotkeys='Горячие клавиши'; accent='Акцентный цвет'; labPreflight='Предварительная проверка'; labRunAll='Проверить все стратегии'; labRunSelected='Проверить выбранные стратегии'; labRound='Раунд'; labChecks='Проверки'; labPassed='Пройдено'; labFailed='Ошибок'; labWarnings='Предупреждений'; labElapsed='Время'; labControl='Контроль'; labResult='Результат'; labDpiFreeze='DPI-зависание'; labDns='DNS'; labTls='TLS'; labHttp='HTTP'; labThroughput='Скорость'; labMedia='Медиа';
        firstRun='Диагностика первого запуска'; ipv6='Поддержка IPv6'; attestation='Проверить GitHub attestation'; sha='SHA-256 обновления';
        trayEnable='Включить управление из трея'; trayDisable='Отключить управление из трея'; monitorEnable='Включить мониторинг'; monitorDisable='Отключить мониторинг';
        theme='Тема'; interfaceMode='Режим интерфейса'; language='Язык';
        inputPrompt='Введите текст и нажмите Enter'; notAvailable='НЕДОСТУПНО'; experimental='ЭКСПЕРИМЕНТАЛЬНО';
        statusStrategy='Установленная стратегия'; statusZapret='Служба zapret'; statusWinDivert='Драйвер WinDivert'; statusEngine='Процесс winws';
        statusProfiles='Включённые сервисы'; statusMonitor='Мониторинг'; statusNetwork='Активная сеть'; statusVersion='Версия';
        purgeConfirm='Удалить службы NexRoute и WinDivert? Нажмите Y для подтверждения.';
        purgeDone='Службы NexRoute и WinDivert удалены.';
        installDone='Стратегия установлена как служба Windows.';
        autoCheckOn='Автоматическая проверка обновлений включена.'; autoCheckOff='Автоматическая проверка обновлений отключена.';
        restarted='Служба перезапущена.'; noStrategies='Файлы стратегий не найдены.';
    }
}

function Get-NrRoot {
    param([string]$Candidate)
    if ([string]::IsNullOrWhiteSpace($Candidate)) { $Candidate = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
    return [System.IO.Path]::GetFullPath($Candidate).TrimEnd('\','/')
}


function Initialize-NrEnvironment {
    param([string]$RootPath)
    $script:NrRoot = Get-NrRoot -Candidate $RootPath
    $script:NrService = Join-Path $script:NrRoot '.service'
    $script:NrStatePath = Join-Path $script:NrService 'next-state.json'
    $script:NrLogDir = Join-Path $script:NrService 'logs'
    $script:NrHistoryDir = Join-Path $script:NrService 'history'
    $script:NrConfigDir = Join-Path $script:NrService 'profiles'
    $script:NrMonitorState = Join-Path $script:NrService 'monitor-state.json'
    foreach ($path in @($script:NrLogDir,$script:NrHistoryDir,$script:NrConfigDir)) {
        if (-not (Test-Path -LiteralPath $path -PathType Container)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
    }

    $script:NrState = Read-NrState
    $storedSchema = 0
    try { $storedSchema = [int]$script:NrState.schemaVersion } catch { }
    if ($storedSchema -lt 4) {
        $script:NrState.schemaVersion = 4
        $script:NrState.theme = 'dark'
        $script:NrState.accent = 'Red'
        try { Save-NrState } catch { }
    }

    $script:NrLanguage = [string]$script:NrState.language
    if ($script:NrLanguage -notin @('RU','EN')) { $script:NrLanguage = Get-NrDefaultLanguage }
    $script:NrText = $script:NrTranslations[$script:NrLanguage]

    try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }
    try {
        [Console]::BackgroundColor = [ConsoleColor]::Black
        [Console]::ForegroundColor = [ConsoleColor]::Gray
        Clear-Host
    } catch { }

    try {
        $versionPath = Join-Path $script:NrService 'version.txt'
        $version = if (Test-Path -LiteralPath $versionPath -PathType Leaf) { (Get-Content -LiteralPath $versionPath -Raw -Encoding UTF8).Trim() } else { '0.6.5' }
        [Console]::Title = "NexRoute $version"
    } catch { }
}


function New-NrDefaultState {
    $lang = Get-NrDefaultLanguage
    return [ordered]@{
        schemaVersion = 4
        language = $lang
        mode = 'beginner'
        theme = 'dark'
        accent = 'Red'
        firstRunComplete = $false
        monitorEnabled = $false
        autoSwitchEnabled = $false
        trayEnabled = $false
        safeMode = $false
        restartLimitPerHour = 3
        failureThreshold = 3
        probeIntervalSeconds = 60
        favorites = @()
        lastWorkingStrategy = $null
        perServiceStrategies = [ordered]@{}
        networkProfiles = [ordered]@{}
        currentNetworkKey = $null
        dnsProvider = 'system'
        dnsEncryption = 'system'
        lastDownloadedSha256 = $null
        lastAttestationStatus = 'not-checked'
        statisticsEnabled = $true
    }
}

function Read-NrState {
    $default = New-NrDefaultState
    if (-not (Test-Path -LiteralPath $script:NrStatePath -PathType Leaf)) { return $default }
    try {
        $stored = Get-Content -LiteralPath $script:NrStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($key in @($default.Keys)) {
            $property = $stored.PSObject.Properties[$key]
            if ($property -and $null -ne $property.Value) { $default[$key] = $property.Value }
        }
    } catch { }
    return $default
}

function Save-NrState {
    $json = $script:NrState | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($script:NrStatePath, $json + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
}

function T {
    param([Parameter(Mandatory)][string]$Key)
    if ($script:NrText.ContainsKey($Key)) { return [string]$script:NrText[$Key] }
    return $Key
}

function Write-NrLog {
    param([string]$Level='INFO',[string]$Message,[hashtable]$Data)
    $entry = [ordered]@{ timestampUtc=[DateTime]::UtcNow.ToString('o'); level=$Level.ToUpperInvariant(); message=$Message }
    if ($Data) { $entry.data = $Data }
    $line = $entry | ConvertTo-Json -Depth 10 -Compress
    Add-Content -LiteralPath (Join-Path $script:NrLogDir 'nexroute.jsonl') -Value $line -Encoding UTF8
}


function Get-NrAccentColor {
    $name = [string]$script:NrState.accent
    if ([string]::IsNullOrWhiteSpace($name) -or $name -eq 'Cyan') { return [ConsoleColor]::Red }
    try { return [ConsoleColor]::$name } catch { return [ConsoleColor]::Red }
}


function Get-NrWidth {
    try { return [Math]::Min([Math]::Max([Console]::WindowWidth - 2, 100), 124) } catch { return 112 }
}

function Format-NrText {
    param([AllowNull()][string]$Value,[int]$Length)
    if ($null -eq $Value) { $Value = '' }
    if ($Length -lt 1) { return '' }
    if ($Value.Length -gt $Length) {
        if ($Length -le 3) { return $Value.Substring(0,$Length) }
        return $Value.Substring(0,$Length-3) + '...'
    }
    return $Value.PadRight($Length)
}


function Write-NrRule {
    param([char]$Fill='-',[ConsoleColor]$Color=[ConsoleColor]::DarkRed)
    $width = Get-NrWidth
    Write-Host ('+' + ($Fill.ToString() * ($width-2)) + '+') -ForegroundColor $Color
}


function Write-NrPanel {
    param([string]$Title)
    if ([string]::IsNullOrWhiteSpace($Title)) { return }
    $width = Get-NrWidth
    $label = '[ ' + $Title + ' ]'
    $remaining = [Math]::Max(0,$width-4-$label.Length)
    Write-Host ('+--' + $label + ('-' * $remaining) + '+') -ForegroundColor DarkRed
}


function Write-NrHeader {
    param([string]$Title)
    Clear-Host

    $versionPath = Join-Path $script:NrService 'version.txt'
    $version = if (Test-Path -LiteralPath $versionPath -PathType Leaf) { (Get-Content -LiteralPath $versionPath -Raw -Encoding UTF8).Trim() } else { '0.6.5' }
    $baseline = '1.10.3'
    $manifestPath = Join-Path $script:NrService 'upstream-manifest.json'
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        try { $baseline = [string]((Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json).tag) } catch { }
    }

    $logo = @(
        '███╗░░██╗███████╗██╗░░██╗██████╗░░█████╗░██╗░░░██╗████████╗███████╗',
        '████╗░██║██╔════╝╚██╗██╔╝██╔══██╗██╔══██╗██║░░░██║╚══██╔══╝██╔════╝',
        '██╔██╗██║█████╗░░░╚███╔╝░██████╔╝██║░░██║██║░░░██║░░░██║░░░█████╗░░',
        '██║╚████║██╔══╝░░░██╔██╗░██╔══██╗██║░░██║██║░░░██║░░░██║░░░██╔══╝░░',
        '██║░╚███║███████╗██╔╝╚██╗██║░░██║╚█████╔╝╚██████╔╝░░░██║░░░███████╗',
        '╚═╝░░╚══╝╚══════╝╚═╝░░╚═╝╚═╝░░╚═╝░╚════╝░░╚═════╝░░░░╚═╝░░░╚══════╝'
    )
    $width = Get-NrWidth
    foreach ($line in $logo) {
        $pad = [Math]::Max(0,[int](($width-$line.Length)/2))
        Write-Host ((' ' * $pad) + $line) -ForegroundColor Red
    }

    $tagline = T 'tagline'
    $tagPad = [Math]::Max(0,[int](($width-$tagline.Length)/2))
    Write-Host ((' ' * $tagPad) + $tagline) -ForegroundColor DarkGray

    Write-NrRule -Fill '=' -Color Red
    $headline = " NEXROUTE CONTROL NODE  v$version  //  FLOWSEAL $baseline "
    $headlinePad = [Math]::Max(0,[int](($width-$headline.Length)/2))
    Write-Host ((' ' * $headlinePad) + $headline) -ForegroundColor White
    Write-NrRule -Fill '=' -Color Red

    $strategy = 'none'
    try { $strategy = Get-NrInstalledStrategy } catch { }
    $engineState = if (Test-NrServiceRunning -Name 'zapret') { T 'running' } else { T 'stopped' }
    $privilege = if (Test-NrAdministrator) { 'ADMIN' } else { 'USER' }
    $left = "  PROFILE: $strategy"
    $right = "ENGINE: $engineState   LANG: $script:NrLanguage   $privilege  "
    $space = [Math]::Max(1,$width-2-$left.Length-$right.Length)
    Write-Host '|' -NoNewline -ForegroundColor DarkRed
    Write-Host $left -NoNewline -ForegroundColor Gray
    Write-Host (' ' * $space) -NoNewline
    Write-Host $right -NoNewline -ForegroundColor (Get-NrStatusColor -Status $engineState)
    Write-Host '|' -ForegroundColor DarkRed
    Write-NrRule -Color DarkRed

    if (-not [string]::IsNullOrWhiteSpace($Title)) { Write-NrPanel -Title $Title }
}


function Get-NrStatusColor {
    param([string]$Status)
    if ([string]::IsNullOrWhiteSpace($Status)) { return [ConsoleColor]::Gray }
    $value = $Status.ToLowerInvariant()
    if ($value -match 'enabled|running|ready|ok|current|success|stable|включ|работ|готов|успех|текущ') { return [ConsoleColor]::Green }
    if ($value -match 'disabled|stopped|error|failed|none|missing|выключ|останов|ошиб|нет|не найден') { return [ConsoleColor]::Red }
    return [ConsoleColor]::Yellow
}


function Write-NrMenuRow {
    param([object]$Item,[int]$Number,[switch]$ExitRow)
    $width = Get-NrWidth
    $numberText = if ($ExitRow) { '[00]' } else { '[{0:00}]' -f $Number }
    $status = ''
    if ($Item.PSObject.Properties['Status'] -and -not [string]::IsNullOrWhiteSpace([string]$Item.Status)) {
        $status = '[' + (([string]$Item.Status -replace '[\[\]]','').ToUpperInvariant()) + ']'
    }
    $label = [string]$Item.Label
    $contentWidth = $width - 4
    $pad = [Math]::Max(1,$contentWidth-$numberText.Length-2-$label.Length-$status.Length)

    Write-Host '|' -NoNewline -ForegroundColor DarkRed
    Write-Host (' ' + $numberText) -NoNewline -ForegroundColor Red
    Write-Host (' ' + $label) -NoNewline -ForegroundColor $(if ($ExitRow) { [ConsoleColor]::DarkGray } else { [ConsoleColor]::White })
    Write-Host (' ' * $pad) -NoNewline
    if ($status) { Write-Host $status -NoNewline -ForegroundColor (Get-NrStatusColor -Status $status) }
    Write-Host ' |' -ForegroundColor DarkRed
}

function New-NrMenuItem {
    param([string]$Id,[string]$Label,[string]$Section,[string]$Status='',[string]$HotKey='')
    return [pscustomobject]@{ Id=$Id; Label=$Label; Section=$Section; Status=$Status; HotKey=$HotKey }
}


function Invoke-NrMenu {
    param([string]$Title,[Parameter(Mandatory)][object[]]$Items,[int]$InitialIndex=0,[switch]$AllowEscape)
    if ($Items.Count -eq 0) { return $null }

    $regular = @($Items | Where-Object { [string]$_.Id -notin @('exit','back','__back') })
    $exitItem = @($Items | Where-Object { [string]$_.Id -in @('exit','back','__back') } | Select-Object -First 1)

    while ($true) {
        Write-NrHeader -Title $Title
        $lastSection = $null
        for ($i=0; $i -lt $regular.Count; $i++) {
            $section = [string]$regular[$i].Section
            if ($section -ne $lastSection) { Write-NrPanel -Title $section; $lastSection=$section }
            Write-NrMenuRow -Item $regular[$i] -Number ($i+1)
        }
        if ($exitItem.Count -gt 0 -or $AllowEscape) {
            Write-NrRule -Color DarkRed
            $item = if ($exitItem.Count -gt 0) { $exitItem[0] } else { [pscustomobject]@{ Label=(T 'back'); Status='' } }
            Write-NrMenuRow -Item $item -Number 0 -ExitRow
        }
        Write-NrRule -Fill '=' -Color Red
        Write-Host ''
        Write-Host '  > ' -NoNewline -ForegroundColor Red
        $raw = (Read-Host).Trim()

        if ($raw -eq '0') {
            if ($exitItem.Count -gt 0) { return [string]$exitItem[0].Id }
            if ($AllowEscape) { return $null }
        }

        $number = 0
        if ([int]::TryParse($raw,[ref]$number) -and $number -ge 1 -and $number -le $regular.Count) {
            return [string]$regular[$number-1].Id
        }

        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            foreach ($item in $regular) {
                if (-not [string]::IsNullOrWhiteSpace([string]$item.HotKey) -and $raw.ToUpperInvariant() -eq ([string]$item.HotKey).ToUpperInvariant()) {
                    return [string]$item.Id
                }
            }
        }

        Write-Host ''
        Write-Host '  [ERROR] Invalid menu number.' -ForegroundColor Red
        Start-Sleep -Milliseconds 650
    }
}


function Invoke-NrMultiSelect {
    param([string]$Title,[Parameter(Mandatory)][object[]]$Items,[string[]]$SelectedIds=@())
    $selected = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($id in $SelectedIds) { [void]$selected.Add($id) }

    while ($true) {
        Write-NrHeader -Title $Title
        Write-NrPanel -Title (T 'selectItems')
        for ($i=0; $i -lt $Items.Count; $i++) {
            $mark = if ($selected.Contains([string]$Items[$i].Id)) { '[X]' } else { '[ ]' }
            $row = [pscustomobject]@{ Label=($mark + ' ' + [string]$Items[$i].Label); Status=[string]$Items[$i].Status }
            Write-NrMenuRow -Item $row -Number ($i+1)
        }
        Write-NrRule -Fill '=' -Color Red
        Write-Host '  A = all   N = none   ENTER = continue   0 = cancel' -ForegroundColor DarkGray
        Write-Host '  Numbers: 1,3,5-8' -ForegroundColor DarkGray
        Write-Host ''
        Write-Host '  > ' -NoNewline -ForegroundColor Red
        $raw = (Read-Host).Trim()

        if ([string]::IsNullOrWhiteSpace($raw)) { return [string[]]@($selected) }
        if ($raw -eq '0') { return $null }
        if ($raw.ToUpperInvariant() -eq 'A') {
            $selected.Clear()
            foreach ($item in $Items) { [void]$selected.Add([string]$item.Id) }
            continue
        }
        if ($raw.ToUpperInvariant() -eq 'N') {
            $selected.Clear()
            continue
        }

        $valid = $true
        $numbers = New-Object 'System.Collections.Generic.HashSet[int]'
        foreach ($token in @($raw -split '[,\s]+')) {
            if ([string]::IsNullOrWhiteSpace($token)) { continue }
            if ($token -match '^(\d+)-(\d+)$') {
                $from=[int]$Matches[1]; $to=[int]$Matches[2]
                if ($from -gt $to) { $tmp=$from; $from=$to; $to=$tmp }
                if ($from -lt 1 -or $to -gt $Items.Count) { $valid=$false; break }
                for ($n=$from;$n -le $to;$n++) { [void]$numbers.Add($n) }
            } else {
                $n=0
                if (-not [int]::TryParse($token,[ref]$n) -or $n -lt 1 -or $n -gt $Items.Count) { $valid=$false; break }
                [void]$numbers.Add($n)
            }
        }
        if (-not $valid -or $numbers.Count -eq 0) {
            Write-Host '  [ERROR] Use numbers, ranges, A, N or 0.' -ForegroundColor Red
            Start-Sleep -Milliseconds 650
            continue
        }
        foreach ($n in $numbers) {
            $id=[string]$Items[$n-1].Id
            if ($selected.Contains($id)) { [void]$selected.Remove($id) } else { [void]$selected.Add($id) }
        }
    }
}


function Confirm-NrY {
    param([string]$Message)
    Write-Host ''
    Write-Host ('  [!] ' + $Message) -ForegroundColor Yellow
    Write-Host '  > Y/N: ' -NoNewline -ForegroundColor Red
    $raw=(Read-Host).Trim()
    return ($raw -match '^(?i:y|yes|д|да)$')
}


function Wait-NrKey {
    Write-Host ''
    Write-Host ('  ' + (T 'pressKey')) -ForegroundColor DarkGray
    try { [void][Console]::ReadKey($true) } catch { Read-Host | Out-Null }
}


function Show-NrMessage {
    param([string]$Title,[string]$Message,[ConsoleColor]$Color=[ConsoleColor]::White,[switch]$NoWait)
    Write-NrHeader -Title $Title
    Write-Host ''
    Write-NrRule -Color DarkRed
    Write-Host ('  ' + $Message) -ForegroundColor $Color
    Write-NrRule -Color DarkRed
    if (-not $NoWait) { Wait-NrKey }
}

function Test-NrAdministrator {
    try {
        $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
        $principal=New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Get-NrInstalledStrategy {
    try {
        $value=Get-ItemPropertyValue -Path 'HKLM:\System\CurrentControlSet\Services\zapret' -Name 'zapret-discord-youtube' -ErrorAction Stop
        if ($value) { return [string]$value }
    } catch { }
    return 'none'
}

function Test-NrServiceRunning {
    param([string]$Name)
    try { return ((Get-Service -Name $Name -ErrorAction Stop).Status -eq 'Running') } catch { return $false }
}

function Get-NrServiceSummary {
    $controller=Join-Path $script:NrService 'nexroute-services.ps1'
    if (-not (Test-Path -LiteralPath $controller)) { return '0/0' }
    try {
        $json=& $controller -Mode Summary -Root $script:NrRoot | Select-Object -Last 1
        $data=$json | ConvertFrom-Json
        return ('{0}/{1}' -f $data.Enabled,$data.Total)
    } catch { return '0/15' }
}

function Invoke-NrLegacy {
    param([Parameter(Mandatory)][string[]]$Arguments,[switch]$Hidden)
    $legacy=Join-Path $script:NrService 'legacy-service.bat'
    if (-not (Test-Path -LiteralPath $legacy -PathType Leaf)) { throw 'Legacy service engine is missing.' }
    $parts=New-Object 'System.Collections.Generic.List[string]'
    $parts.Add('"' + $legacy + '"')
    foreach ($argument in $Arguments) { $parts.Add('"' + ([string]$argument).Replace('"','""') + '"') }
    $command=$parts -join ' '
    Write-NrLog -Level INFO -Message 'Legacy command' -Data @{ command=$command }
    if ($Hidden) {
        $process=Start-Process -FilePath $env:ComSpec -ArgumentList @('/d','/c',$command) -WindowStyle Hidden -Wait -PassThru
        return $process.ExitCode
    }
    & $env:ComSpec /d /c $command
    return $LASTEXITCODE
}

function Send-NrNotification {
    param([string]$Title,[string]$Message,[ValidateSet('Info','Warning','Error')][string]$Level='Info')
    Write-NrLog -Level $Level -Message $Message -Data @{ title=$Title }
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $notify=New-Object System.Windows.Forms.NotifyIcon
        $notify.Icon=[System.Drawing.SystemIcons]::Information
        $notify.BalloonTipTitle=$Title
        $notify.BalloonTipText=$Message
        $notify.Visible=$true
        $icon=[System.Windows.Forms.ToolTipIcon]::$Level
        $notify.ShowBalloonTip(5000,$Title,$Message,$icon)
        Start-Sleep -Milliseconds 800
        $notify.Dispose()
    } catch {
        try { (New-Object -ComObject WScript.Shell).Popup($Message,5,$Title,64) | Out-Null } catch { }
    }
}

function Open-NrTextFile {
    param([Parameter(Mandatory)][string]$Path)
    $parent=Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { [System.IO.File]::WriteAllText($Path,"# NexRoute`r`n",(New-Object System.Text.UTF8Encoding($false))) }
    Start-Process notepad.exe -ArgumentList ('"' + $Path + '"') -Wait
}

function Get-NrActiveNetworkKey {
    try {
        $profile=Get-NetConnectionProfile -ErrorAction Stop | Where-Object { $_.IPv4Connectivity -ne 'Disconnected' -or $_.IPv6Connectivity -ne 'Disconnected' } | Sort-Object InterfaceIndex | Select-Object -First 1
        if ($profile) {
            $name=if ([string]::IsNullOrWhiteSpace([string]$profile.Name)) { 'network' } else { [string]$profile.Name }
            return ('{0}|{1}|{2}' -f $profile.InterfaceAlias,$name,$profile.NetworkCategory)
        }
    } catch { }
    return 'unknown'
}
