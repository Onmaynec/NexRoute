[CmdletBinding()]
param(
    [ValidateSet('Menu', 'Action', 'Launch', 'Status', 'StrategyPicker', 'PayloadManager', 'IpSetSwitch', 'SyncIpSet', 'SyncHosts', 'TestsIntro', 'TestHeader', 'Services', 'Screen')]
    [string]$Mode = 'Menu',

    [string]$ChoiceFile,
    [string]$LanguageFile,
    [string]$ActionId,
    [string]$Profile,
    [string]$ScreenId,
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $OutputEncoding = [Console]::OutputEncoding
}
catch {
}

$script:Width = 100
try {
    $script:Width = [Math]::Min(118, [Math]::Max(88, [Console]::WindowWidth - 2))
}
catch {
}

$script:ServiceDirectory = $PSScriptRoot
$script:Root = [System.IO.Path]::GetFullPath($Root)
$script:LanguageFile = if ($LanguageFile) { $LanguageFile } else { Join-Path $script:ServiceDirectory 'language.txt' }

function Get-Language {
    $language = 'RU'
    if (Test-Path -LiteralPath $script:LanguageFile -PathType Leaf) {
        try {
            $candidate = (Get-Content -LiteralPath $script:LanguageFile -Raw -Encoding ASCII).Trim().ToUpperInvariant()
            if ($candidate -in @('RU', 'EN')) {
                $language = $candidate
            }
        }
        catch {
        }
    }
    return $language
}

function Get-TextTable {
    param([Parameter(Mandatory)][string]$Language)

    $path = Join-Path $script:ServiceDirectory ("i18n\{0}.json" -f $Language.ToLowerInvariant())
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $path = Join-Path $script:ServiceDirectory 'i18n\en.json'
    }
    return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

$script:Language = Get-Language
$script:Text = Get-TextTable -Language $script:Language

function Fit-Text {
    param(
        [AllowNull()][string]$Value,
        [int]$Length
    )

    if ($Length -lt 1) { return '' }
    if ($null -eq $Value) { $Value = '' }
    if ($Value.Length -gt $Length) {
        if ($Length -le 3) { return $Value.Substring(0, $Length) }
        return $Value.Substring(0, $Length - 3) + '...'
    }
    return $Value.PadRight($Length)
}

function Write-Rule {
    param(
        [char]$Fill = '-',
        [ConsoleColor]$Color = [ConsoleColor]::DarkCyan
    )
    Write-Host ($Fill.ToString() * $script:Width) -ForegroundColor $Color
}

function Write-Centered {
    param(
        [string]$Value,
        [ConsoleColor]$Color = [ConsoleColor]::White
    )
    $padding = [Math]::Max(0, [int](($script:Width - $Value.Length) / 2))
    Write-Host ((' ' * $padding) + $Value) -ForegroundColor $Color
}

function Write-Logo {
    $logo = @(
        ' _   _ _______  ______   ___  _   _ _____ _____ ',
        '| \ | | ____\ \/ /  _ \ / _ \| | | |_   _| ____|',
        '|  \| |  _|  \  /| |_) | | | | | | | | | |  _|  ',
        '| |\  | |___ /  \|  _ <| |_| | |_| | | | | |___ ',
        '|_| \_|_____/_/\_\_| \_\\___/ \___/  |_| |_____|'
    )
    foreach ($line in $logo) {
        Write-Centered -Value $line -Color Cyan
    }
}

function Write-Header {
    param([string]$Title)

    Clear-Host
    try { $Host.UI.RawUI.WindowTitle = "NexRoute // $Title" } catch {}
    Write-Rule -Fill '=' -Color Cyan
    Write-Logo
    Write-Centered -Value ('// ' + $script:Text.tagline + ' //') -Color DarkCyan
    Write-Rule -Fill '=' -Color Cyan
    if ($Title) {
        Write-Centered -Value ("[ $Title ]") -Color White
        Write-Rule -Color DarkCyan
    }
}

function Write-PanelTitle {
    param([string]$Title)
    Write-Host ''
    Write-Host ('  +-- ' + $Title + ' ') -NoNewline -ForegroundColor Cyan
    $remaining = $script:Width - $Title.Length - 8
    if ($remaining -gt 0) { Write-Host ('-' * $remaining) -ForegroundColor DarkCyan } else { Write-Host '' }
}

function Get-StateColor {
    param([string]$State)
    $value = if ($State) { $State.ToLowerInvariant() } else { '' }
    if ($value -match 'running|ready|enabled|loaded|on|found|success|baseline|stable') { return [ConsoleColor]::Green }
    if ($value -match 'warning|experimental|advanced|any|standard|web') { return [ConsoleColor]::Yellow }
    if ($value -match 'missing|stopped|disabled|none|off|error|failed') { return [ConsoleColor]::Red }
    return [ConsoleColor]::Cyan
}

function Write-Option {
    param(
        [int]$Number,
        [string]$Label,
        [string]$Status
    )

    $numberText = '[{0:00}]' -f $Number
    Write-Host '  | ' -NoNewline -ForegroundColor DarkCyan
    Write-Host $numberText -NoNewline -ForegroundColor Cyan
    Write-Host '  ' -NoNewline
    $statusWidth = if ($Status) { [Math]::Min(22, [Math]::Max(10, $Status.Length + 2)) } else { 0 }
    $labelWidth = $script:Width - 12 - $statusWidth
    Write-Host (Fit-Text -Value $Label -Length $labelWidth) -NoNewline -ForegroundColor White
    if ($Status) {
        Write-Host ('[' + (Fit-Text -Value $Status -Length ($statusWidth - 2)).TrimEnd() + ']') -NoNewline -ForegroundColor (Get-StateColor -State $Status)
    }
    Write-Host ' |' -ForegroundColor DarkCyan
}

function Write-KeyValue {
    param(
        [string]$Key,
        [string]$Value,
        [ConsoleColor]$ValueColor = [ConsoleColor]::White
    )
    $keyWidth = 30
    Write-Host '  | ' -NoNewline -ForegroundColor DarkCyan
    Write-Host (Fit-Text -Value $Key -Length $keyWidth) -NoNewline -ForegroundColor DarkGray
    Write-Host ' : ' -NoNewline -ForegroundColor DarkCyan
    Write-Host (Fit-Text -Value $Value -Length ($script:Width - $keyWidth - 9)) -NoNewline -ForegroundColor $ValueColor
    Write-Host ' |' -ForegroundColor DarkCyan
}

function Write-Progress {
    param(
        [string]$Label,
        [int]$Percent,
        [ConsoleColor]$Color = [ConsoleColor]::Cyan
    )

    $barWidth = [Math]::Min(46, [Math]::Max(24, $script:Width - 48))
    $filled = [int][Math]::Floor($barWidth * ($Percent / 100.0))
    $bar = ('#' * $filled) + ('.' * ($barWidth - $filled))
    $line = ('  {0,-30} [{1}] {2,3}%' -f (Fit-Text -Value $Label -Length 30), $bar, $Percent)
    try {
        [Console]::Write("`r")
        $old = [Console]::ForegroundColor
        [Console]::ForegroundColor = $Color
        $formatted = Fit-Text -Value $line -Length ($script:Width - 1)
        [Console]::Write($formatted)
        [Console]::ForegroundColor = $old
        if ($Percent -ge 100) { [Console]::WriteLine() }
    }
    catch {
        Write-Host $line -ForegroundColor $Color
    }
}

function Animate-Step {
    param(
        [string]$Label,
        [int]$Duration = 180,
        [ConsoleColor]$Color = [ConsoleColor]::Cyan
    )
    foreach ($percent in @(0, 12, 25, 44, 67, 84, 100)) {
        Write-Progress -Label $Label -Percent $percent -Color $Color
        Start-Sleep -Milliseconds ([Math]::Max(12, [int]($Duration / 7)))
    }
}

function Write-Result {
    param(
        [bool]$Success,
        [string]$Message
    )
    Write-Host ''
    Write-Rule -Color DarkCyan
    if ($Success) {
        Write-Centered -Value ('[ OK ] ' + $Message) -Color Green
    }
    else {
        Write-Centered -Value ('[ ERROR ] ' + $Message) -Color Red
    }
    Write-Rule -Color DarkCyan
}

function Wait-Key {
    if ($NonInteractive) { return }
    Write-Host ''
    Write-Centered -Value $script:Text.pressKey -Color DarkGray
    try { [void][Console]::ReadKey($true) } catch { Read-Host | Out-Null }
}

function Get-AdminState {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Get-ServiceRunning {
    param([string]$Name)
    try {
        return ((Get-Service -Name $Name -ErrorAction Stop).Status -eq 'Running')
    }
    catch {
        return $false
    }
}

function Get-ServiceSummary {
    $controller = Join-Path $script:ServiceDirectory 'nexroute-services.ps1'
    if (-not (Test-Path -LiteralPath $controller -PathType Leaf)) { return '0/0' }
    try {
        $json = & $controller -Mode Summary -Root $script:Root | Select-Object -Last 1
        $summary = $json | ConvertFrom-Json
        return ("{0}/{1}" -f $summary.Enabled, $summary.Total)
    }
    catch {
        return '0/0'
    }
}

function Show-Menu {
    $version = if ($env:NEXROUTE_VERSION) { $env:NEXROUTE_VERSION } else { '0.2.0' }
    $baseline = if ($env:NEXROUTE_BASELINE) { $env:NEXROUTE_BASELINE } else { '1.10.0' }
    $strategy = if ($env:NEXROUTE_STRATEGY) { $env:NEXROUTE_STRATEGY } else { 'none' }
    $game = if ($env:NEXROUTE_GAME_STATUS) { $env:NEXROUTE_GAME_STATUS } else { 'disabled' }
    $ipset = if ($env:NEXROUTE_IPSET_STATUS) { $env:NEXROUTE_IPSET_STATUS } else { 'none' }
    $updates = if ($env:NEXROUTE_UPDATE_STATUS) { $env:NEXROUTE_UPDATE_STATUS } else { 'disabled' }
    $admin = if (Get-AdminState) { $script:Text.elevated } else { $script:Text.standard }
    $serviceSummary = Get-ServiceSummary

    if ($env:NEXROUTE_UI_ANIMATE -eq '1') {
        Write-Header -Title 'BOOT SEQUENCE'
        Animate-Step -Label $script:Text.boot1 -Duration 170
        Animate-Step -Label $script:Text.boot2 -Duration 150
        Animate-Step -Label $script:Text.boot3 -Duration 160
        Animate-Step -Label $script:Text.boot4 -Duration 180
        Animate-Step -Label $script:Text.boot5 -Duration 120 -Color Green
        Start-Sleep -Milliseconds 180
    }

    while ($true) {
        Write-Header -Title ("CONTROL NODE v$version")
        Write-KeyValue -Key $script:Text.profile -Value $strategy -ValueColor Cyan
        Write-KeyValue -Key 'Flowseal baseline' -Value $baseline -ValueColor DarkCyan
        Write-KeyValue -Key $script:Text.language -Value $script:Language -ValueColor Yellow
        Write-KeyValue -Key $script:Text.privilege -Value $admin -ValueColor (Get-StateColor -State $admin)

        Write-PanelTitle -Title $script:Text.mainService
        Write-Option -Number 1 -Label $script:Text.menu1
        Write-Option -Number 2 -Label $script:Text.menu2
        Write-Option -Number 3 -Label $script:Text.menu3

        Write-PanelTitle -Title $script:Text.mainFilters
        Write-Option -Number 4 -Label $script:Text.menu4 -Status $game
        Write-Option -Number 5 -Label $script:Text.menu5 -Status $ipset
        Write-Option -Number 6 -Label $script:Text.menu6 -Status $updates
        Write-Option -Number 7 -Label $script:Text.menu7

        Write-PanelTitle -Title $script:Text.mainData
        Write-Option -Number 8 -Label $script:Text.menu8
        Write-Option -Number 9 -Label $script:Text.menu9
        Write-Option -Number 10 -Label $script:Text.menu10

        Write-PanelTitle -Title $script:Text.mainOther
        Write-Option -Number 14 -Label $script:Text.menu14 -Status $serviceSummary

        Write-PanelTitle -Title $script:Text.mainTools
        Write-Option -Number 11 -Label $script:Text.menu11
        Write-Option -Number 12 -Label $script:Text.menu12
        Write-Option -Number 13 -Label $script:Text.menu13 -Status $script:Language
        Write-Option -Number 0 -Label $script:Text.menu0
        Write-Rule -Fill '=' -Color Cyan

        if ($NonInteractive) { return }
        Write-Host ''
        Write-Host ('  > ' + $script:Text.prompt + ': ') -NoNewline -ForegroundColor Cyan
        $choice = (Read-Host).Trim()
        $number = 0
        if ([int]::TryParse($choice, [ref]$number) -and $number -ge 0 -and $number -le 14) {
            if ($ChoiceFile) {
                [System.IO.File]::WriteAllText($ChoiceFile, $number.ToString(), [System.Text.Encoding]::ASCII)
            }
            return
        }
        Write-Host ('  [!] ' + $script:Text.invalid) -ForegroundColor Red
        Start-Sleep -Milliseconds 650
    }
}

function Show-Action {
    $label = if ($ActionId) { $ActionId.ToUpperInvariant() } else { 'SYSTEM OPERATION' }
    Write-Header -Title $script:Text.actionTitle
    Write-KeyValue -Key 'OPERATION' -Value $label -ValueColor Cyan
    Animate-Step -Label 'Validating request' -Duration 120
    Animate-Step -Label 'Locking configuration state' -Duration 150
    Animate-Step -Label 'Preparing system module' -Duration 170
    Animate-Step -Label $script:Text.actionComplete -Duration 120 -Color Green
}

function Show-Launch {
    $profileName = if ($Profile) { $Profile } else { 'general' }
    Write-Header -Title $script:Text.launchTitle
    Write-KeyValue -Key $script:Text.profile -Value $profileName -ValueColor Cyan
    Animate-Step -Label $script:Text.launchRead -Duration 130

    $enginePath = Join-Path $script:Root 'bin\winws.exe'
    $driverPath = Join-Path $script:Root 'bin\WinDivert64.sys'
    $engineOk = Test-Path -LiteralPath $enginePath -PathType Leaf
    $driverOk = Test-Path -LiteralPath $driverPath -PathType Leaf

    $engineColor = if ($engineOk) { [ConsoleColor]::Green } else { [ConsoleColor]::Red }
    $driverColor = if ($driverOk) { [ConsoleColor]::Green } else { [ConsoleColor]::Red }
    Animate-Step -Label $script:Text.launchEngine -Duration 120 -Color $engineColor
    Animate-Step -Label $script:Text.launchDriver -Duration 120 -Color $driverColor
    Animate-Step -Label $script:Text.launchLists -Duration 140
    Animate-Step -Label $script:Text.launchCommand -Duration 150
    Animate-Step -Label $script:Text.launchTransfer -Duration 120 -Color Green

    if (-not $engineOk -or -not $driverOk) {
        Write-Result -Success $false -Message 'Required engine components are missing.'
        exit 2
    }
}

function Show-Status {
    Write-Header -Title $script:Text.statusTitle

    $strategy = 'none'
    try {
        $value = Get-ItemPropertyValue -Path 'HKLM:\System\CurrentControlSet\Services\zapret' -Name 'zapret-discord-youtube' -ErrorAction Stop
        if ($value) { $strategy = [string]$value }
    }
    catch {
    }

    $zapretState = if (Get-ServiceRunning -Name 'zapret') { $script:Text.running } else { $script:Text.stopped }
    $windivertState = if (Get-ServiceRunning -Name 'WinDivert') { $script:Text.running } else { $script:Text.stopped }
    $engineState = if (Get-Process -Name 'winws' -ErrorAction SilentlyContinue) { $script:Text.running } else { $script:Text.stopped }
    $driverState = if (Test-Path -LiteralPath (Join-Path $script:Root 'bin\WinDivert64.sys')) { $script:Text.ready } else { $script:Text.missing }

    Write-PanelTitle -Title 'SERVICE TELEMETRY'
    Write-KeyValue -Key $script:Text.statusStrategy -Value $strategy -ValueColor Cyan
    Write-KeyValue -Key $script:Text.statusZapret -Value $zapretState -ValueColor (Get-StateColor -State $zapretState)
    Write-KeyValue -Key $script:Text.statusWinDivert -Value $windivertState -ValueColor (Get-StateColor -State $windivertState)
    Write-KeyValue -Key $script:Text.statusEngine -Value $engineState -ValueColor (Get-StateColor -State $engineState)
    Write-KeyValue -Key 'WinDivert64.sys' -Value $driverState -ValueColor (Get-StateColor -State $driverState)
    Write-KeyValue -Key $script:Text.statusDomains -Value (Get-ServiceSummary) -ValueColor Yellow
    Write-Rule -Fill '=' -Color Cyan
    Wait-Key
}

function Get-StrategyCategory {
    param([string]$Name)
    $upper = $Name.ToUpperInvariant()
    if ($upper -match 'EXP') { return $script:Text.strategyExperimental }
    if ($upper -match 'ALT|FAKE') { return $script:Text.strategyAdvanced }
    return $script:Text.strategyStable
}

function Show-StrategyPicker {
    $files = @(Get-ChildItem -LiteralPath $script:Root -Filter '*.bat' -File | Where-Object { $_.Name -notin @('service.bat', 'nexroute.bat') } | Sort-Object Name)
    Write-Header -Title $script:Text.strategyTitle
    Write-Centered -Value $script:Text.strategyHint -Color DarkGray
    Write-PanelTitle -Title 'AVAILABLE PROFILES'

    for ($index = 0; $index -lt $files.Count; $index++) {
        Write-Option -Number ($index + 1) -Label $files[$index].BaseName -Status (Get-StrategyCategory -Name $files[$index].Name)
    }
    Write-Option -Number 0 -Label $script:Text.strategyExit
    Write-Rule -Fill '=' -Color Cyan

    if ($NonInteractive) { return }
    while ($true) {
        Write-Host ''
        Write-Host ('  > ' + $script:Text.strategyPrompt + " [0-$($files.Count)]: ") -NoNewline -ForegroundColor Cyan
        $raw = (Read-Host).Trim()
        $choice = 0
        if ([int]::TryParse($raw, [ref]$choice) -and $choice -ge 0 -and $choice -le $files.Count) {
            $value = if ($choice -eq 0) { '0' } else { $files[$choice - 1].Name }
            if ($ChoiceFile) { [System.IO.File]::WriteAllText($ChoiceFile, $value, [System.Text.UTF8Encoding]::new($false)) }
            return
        }
        Write-Host ('  [!] ' + $script:Text.invalid) -ForegroundColor Red
    }
}

function Get-FileHashSafe {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Show-PayloadManager {
    $binPath = Join-Path $script:Root 'bin'
    if (-not (Test-Path -LiteralPath $binPath -PathType Container)) {
        Write-Header -Title $script:Text.payloadTitle
        Write-Result -Success $false -Message 'bin directory was not found.'
        Wait-Key
        return
    }

    while ($true) {
        $files = @(Get-ChildItem -LiteralPath $binPath -Filter '*.bin' -File | Where-Object { $_.BaseName -notlike 'ACTIVE_*' } | Sort-Object BaseName)
        $discordActive = Join-Path $binPath 'ACTIVE_DISCORD_UDP.bin'
        $gameActive = Join-Path $binPath 'ACTIVE_GAME_UDP.bin'
        $discordHash = Get-FileHashSafe -Path $discordActive
        $gameHash = Get-FileHashSafe -Path $gameActive
        $discordName = $script:Text.missing
        $gameName = $script:Text.missing

        foreach ($file in $files) {
            $hash = Get-FileHashSafe -Path $file.FullName
            if ($discordHash -and $hash -eq $discordHash) { $discordName = $file.BaseName }
            if ($gameHash -and $hash -eq $gameHash) { $gameName = $file.BaseName }
        }

        Write-Header -Title $script:Text.payloadTitle
        Write-PanelTitle -Title $script:Text.payloadTypes
        Write-Option -Number 1 -Label $script:Text.payloadDiscord -Status $discordName
        Write-Option -Number 2 -Label $script:Text.payloadGame -Status $gameName
        Write-PanelTitle -Title $script:Text.payloadFiles
        for ($index = 0; $index -lt $files.Count; $index++) {
            Write-Option -Number ($index + 1) -Label $files[$index].BaseName
        }
        Write-Rule -Fill '=' -Color Cyan

        if ($NonInteractive) { return }
        Write-Host ''
        Write-Host ('  > ' + $script:Text.payloadPrompt + ': ') -NoNewline -ForegroundColor Cyan
        $choice = (Read-Host).Trim()
        if ($choice -eq '0' -or [string]::IsNullOrWhiteSpace($choice)) { return }

        $parts = @($choice -split '\s+' | Where-Object { $_ })
        if ($parts.Count -ne 2) {
            Write-Host ('  [!] ' + $script:Text.invalid) -ForegroundColor Red
            Start-Sleep -Milliseconds 700
            continue
        }

        $type = 0
        $fileNumber = 0
        if (-not [int]::TryParse($parts[0], [ref]$type) -or -not [int]::TryParse($parts[1], [ref]$fileNumber) -or $type -notin @(1, 2) -or $fileNumber -lt 1 -or $fileNumber -gt $files.Count) {
            Write-Host ('  [!] ' + $script:Text.invalid) -ForegroundColor Red
            Start-Sleep -Milliseconds 700
            continue
        }

        $destination = if ($type -eq 1) { $discordActive } else { $gameActive }
        try {
            Animate-Step -Label 'Unlocking payload vault' -Duration 120
            Animate-Step -Label 'Verifying selected payload' -Duration 140
            Copy-Item -LiteralPath $files[$fileNumber - 1].FullName -Destination $destination -Force
            Animate-Step -Label 'Committing active payload' -Duration 130 -Color Green
            Write-Result -Success $true -Message $script:Text.payloadSuccess
        }
        catch {
            Write-Result -Success $false -Message ($script:Text.payloadFailure + ': ' + $_.Exception.Message)
        }
        Wait-Key
    }
}

function Get-IpsetMode {
    $listPath = Join-Path $script:Root 'lists\ipset-all.txt'
    if (-not (Test-Path -LiteralPath $listPath -PathType Leaf)) { return 'none' }
    $lines = @(Get-Content -LiteralPath $listPath -ErrorAction SilentlyContinue)
    if ($lines.Count -eq 0 -or ($lines.Count -eq 1 -and [string]::IsNullOrWhiteSpace($lines[0]))) { return 'any' }
    if ($lines -contains '203.0.113.113/32') { return 'none' }
    return 'loaded'
}

function Invoke-IpsetSwitch {
    $listPath = Join-Path $script:Root 'lists\ipset-all.txt'
    $backupPath = $listPath + '.backup'
    $current = Get-IpsetMode
    $target = if ($current -eq 'loaded') { 'none' } elseif ($current -eq 'none') { 'any' } else { 'loaded' }
    $title = if ($target -eq 'loaded') { $script:Text.transitionLoaded } elseif ($target -eq 'any') { $script:Text.transitionAny } else { $script:Text.transitionNone }

    Write-Header -Title $title
    Animate-Step -Label 'Snapshot current routing state' -Duration 130
    Animate-Step -Label $script:Text.transitionApply -Duration 190

    try {
        if ($target -eq 'none') {
            if (Test-Path -LiteralPath $backupPath) { Remove-Item -LiteralPath $backupPath -Force }
            Copy-Item -LiteralPath $listPath -Destination $backupPath -Force
            [System.IO.File]::WriteAllText($listPath, "203.0.113.113/32`r`n", [System.Text.Encoding]::ASCII)
        }
        elseif ($target -eq 'any') {
            [System.IO.File]::WriteAllText($listPath, '', [System.Text.Encoding]::ASCII)
        }
        else {
            if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) { throw 'No loaded IPSet backup is available. Run SYNC IPSET first.' }
            Move-Item -LiteralPath $backupPath -Destination $listPath -Force
        }
        Animate-Step -Label 'Verify routing state' -Duration 120 -Color Green
        Write-Result -Success $true -Message ("IPSet mode: $target")
    }
    catch {
        Write-Result -Success $false -Message $_.Exception.Message
    }
    Wait-Key
}

function Invoke-SyncIpSet {
    $listPath = Join-Path $script:Root 'lists\ipset-all.txt'
    $backupPath = $listPath + '.backup'
    $tempPath = Join-Path $env:TEMP ("nexroute-ipset-{0}.txt" -f [guid]::NewGuid().ToString('N'))
    $url = 'https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/refs/heads/main/.service/ipset-service.txt'

    Write-Header -Title $script:Text.syncIpSetTitle
    try {
        Animate-Step -Label $script:Text.syncResolve -Duration 130
        Animate-Step -Label $script:Text.syncDownload -Duration 160
        Invoke-WebRequest -Uri $url -OutFile $tempPath -UseBasicParsing -TimeoutSec 20
        Animate-Step -Label $script:Text.syncValidate -Duration 140
        $lines = @(Get-Content -LiteralPath $tempPath -ErrorAction Stop | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($lines.Count -lt 10) { throw 'Downloaded IPSet contains too few entries.' }
        Animate-Step -Label $script:Text.syncBackup -Duration 120
        if (Test-Path -LiteralPath $listPath -PathType Leaf) { Copy-Item -LiteralPath $listPath -Destination $backupPath -Force }
        Animate-Step -Label $script:Text.syncCommit -Duration 160
        Move-Item -LiteralPath $tempPath -Destination $listPath -Force
        Write-Result -Success $true -Message ("$($script:Text.syncDone): $($lines.Count) entries")
    }
    catch {
        if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue }
        Write-Result -Success $false -Message ($script:Text.syncFailed + ': ' + $_.Exception.Message)
    }
    Wait-Key
}

function Invoke-SyncHosts {
    $hostsPath = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
    $tempPath = Join-Path $env:TEMP ("nexroute-hosts-{0}.txt" -f [guid]::NewGuid().ToString('N'))
    $url = 'https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/refs/heads/main/.service/hosts'

    Write-Header -Title $script:Text.syncHostsTitle
    try {
        Animate-Step -Label $script:Text.syncResolve -Duration 130
        Animate-Step -Label $script:Text.syncDownload -Duration 160
        $cacheBuster = [DateTime]::UtcNow.Ticks
        Invoke-WebRequest -Uri ($url + '?t=' + $cacheBuster) -OutFile $tempPath -UseBasicParsing -TimeoutSec 20
        Animate-Step -Label $script:Text.syncValidate -Duration 140
        $remoteLines = @(Get-Content -LiteralPath $tempPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($remoteLines.Count -eq 0) { throw 'Downloaded hosts dataset is empty.' }
        $localText = if (Test-Path -LiteralPath $hostsPath) { Get-Content -LiteralPath $hostsPath -Raw -ErrorAction SilentlyContinue } else { '' }
        $isCurrent = $localText.Contains($remoteLines[0]) -and $localText.Contains($remoteLines[$remoteLines.Count - 1])
        if ($isCurrent) {
            Animate-Step -Label $script:Text.syncCommit -Duration 110 -Color Green
            Write-Result -Success $true -Message $script:Text.syncNoChange
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
        else {
            Animate-Step -Label $script:Text.syncBackup -Duration 120
            Animate-Step -Label 'Opening merge workspace' -Duration 120 -Color Yellow
            Write-Result -Success $true -Message 'Remote hosts dataset downloaded. Complete the merge in Notepad.'
            if (-not $NonInteractive) {
                Start-Process notepad.exe -ArgumentList ('"' + $tempPath + '"')
                Start-Process explorer.exe -ArgumentList ('/select,"' + $hostsPath + '"')
            }
        }
    }
    catch {
        if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue }
        Write-Result -Success $false -Message ($script:Text.syncFailed + ': ' + $_.Exception.Message)
    }
    Wait-Key
}

function Get-ServiceDefinitions {
    $path = Join-Path $script:ServiceDirectory 'services.json'
    return @((Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json).services)
}

function Get-ServiceStateTable {
    param([array]$Definitions)
    $table = [ordered]@{}
    foreach ($item in $Definitions) { $table[$item.id] = [bool]$item.defaultEnabled }
    $statePath = Join-Path $script:ServiceDirectory 'services-state.json'
    if (Test-Path -LiteralPath $statePath -PathType Leaf) {
        try {
            $saved = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($item in $Definitions) {
                $property = $saved.PSObject.Properties[$item.id]
                if ($null -ne $property) { $table[$item.id] = [bool]$property.Value }
            }
        }
        catch {
        }
    }
    return $table
}

function Save-ServiceStateTable {
    param($Table)
    $path = Join-Path $script:ServiceDirectory 'services-state.json'
    $json = $Table | ConvertTo-Json -Depth 4
    [System.IO.File]::WriteAllText($path, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    & (Join-Path $script:ServiceDirectory 'nexroute-services.ps1') -Mode Apply -Root $script:Root | Out-Null
}

function Show-Services {
    $definitions = Get-ServiceDefinitions
    $state = Get-ServiceStateTable -Definitions $definitions
    $selected = 0

    while ($true) {
        Write-Header -Title $script:Text.servicesTitle
        $enabledCount = @($definitions | Where-Object { [bool]$state[$_.id] }).Count
        Write-KeyValue -Key $script:Text.servicesActive -Value ("$enabledCount/$($definitions.Count)") -ValueColor Yellow
        Write-PanelTitle -Title $script:Text.servicesTitle

        for ($index = 0; $index -lt $definitions.Count; $index++) {
            $item = $definitions[$index]
            $active = [bool]$state[$item.id]
            $name = if ($script:Language -eq 'RU') { $item.nameRu } else { $item.nameEn }
            $scopeText = if ($item.scope -eq 'experimental') { $script:Text.experimental } elseif ($item.scope -eq 'baseline') { $script:Text.baseline } else { $script:Text.web }
            $prefix = if ($index -eq $selected) { '>' } else { ' ' }
            $status = if ($active) { $script:Text.enabled } else { $script:Text.disabled }
            $selectorColor = if ($index -eq $selected) { [ConsoleColor]::Cyan } else { [ConsoleColor]::DarkGray }
            Write-Host ('  ' + $prefix + ' ') -NoNewline -ForegroundColor $selectorColor
            Write-Host ('[{0:00}] ' -f ($index + 1)) -NoNewline -ForegroundColor Cyan
            Write-Host (Fit-Text -Value $name -Length 28) -NoNewline -ForegroundColor White
            Write-Host (Fit-Text -Value $scopeText -Length 16) -NoNewline -ForegroundColor (Get-StateColor -State $scopeText)
            Write-Host ('[' + (Fit-Text -Value $status -Length 8).TrimEnd() + ']') -ForegroundColor (Get-StateColor -State $status)
        }

        Write-Rule -Color DarkCyan
        Write-Centered -Value $script:Text.servicesWarning -Color Yellow
        Write-Centered -Value $script:Text.servicesHelp -Color DarkGray
        Write-Rule -Fill '=' -Color Cyan

        if ($NonInteractive) { return }
        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            'UpArrow' { $selected = if ($selected -le 0) { $definitions.Count - 1 } else { $selected - 1 } }
            'DownArrow' { $selected = if ($selected -ge $definitions.Count - 1) { 0 } else { $selected + 1 } }
            'Spacebar' { $id = $definitions[$selected].id; $state[$id] = -not [bool]$state[$id] }
            'A' { foreach ($item in $definitions) { $state[$item.id] = $true } }
            'N' { foreach ($item in $definitions) { $state[$item.id] = $false } }
            'Enter' {
                Save-ServiceStateTable -Table $state
                Write-Result -Success $true -Message $script:Text.servicesSaved
                Start-Sleep -Milliseconds 850
                return
            }
            'Escape' {
                Write-Result -Success $true -Message $script:Text.servicesCancelled
                Start-Sleep -Milliseconds 500
                return
            }
        }
    }
}

function Show-TestsIntro {
    Write-Header -Title $script:Text.testsTitle
    Animate-Step -Label $script:Text.testsStart -Duration 170
    Animate-Step -Label 'Checking PowerShell runtime' -Duration 130
    Animate-Step -Label 'Loading DPI test suite' -Duration 170
    Animate-Step -Label $script:Text.testsWindow -Duration 120 -Color Green
    Wait-Key
}

function Show-TestHeader {
    Write-Header -Title $script:Text.testHeader
    Write-KeyValue -Key 'SESSION' -Value ([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss')) -ValueColor Cyan
    $privilegeText = if (Get-AdminState) { $script:Text.elevated } else { $script:Text.standard }
    Write-KeyValue -Key $script:Text.privilege -Value $privilegeText -ValueColor Yellow
    Write-Rule -Color DarkCyan
}

switch ($Mode) {
    'Menu' { Show-Menu }
    'Action' { Show-Action }
    'Launch' { Show-Launch }
    'Status' { Show-Status }
    'StrategyPicker' { Show-StrategyPicker }
    'PayloadManager' { Show-PayloadManager }
    'IpSetSwitch' { Invoke-IpsetSwitch }
    'SyncIpSet' { Invoke-SyncIpSet }
    'SyncHosts' { Invoke-SyncHosts }
    'TestsIntro' { Show-TestsIntro }
    'TestHeader' { Show-TestHeader }
    'Services' { Show-Services }
    'Screen' {
        $title = if ($ScreenId) { $ScreenId.ToUpperInvariant() } else { 'SYSTEM SCREEN' }
        Write-Header -Title $title
    }
}
