[CmdletBinding()]
param(
    [ValidateSet('Menu', 'Action', 'Launch')]
    [string]$Mode = 'Menu',
    [string]$ChoiceFile,
    [string]$LanguageFile,
    [string]$ActionId,
    [string]$Profile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $OutputEncoding = [Console]::OutputEncoding
}
catch {
}

function Convert-Utf8 {
    param([Parameter(Mandatory)][string]$Value)
    $bytes = [Convert]::FromBase64String($Value)
    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

$ru = @{
    tagline = Convert-Utf8 '0KPQn9Cg0JDQktCb0JXQndCY0JUg0JzQkNCg0KjQoNCj0KLQkNCc0JggLy8g0JrQntCd0KLQoNCe0JvQrCDQotCg0JDQpNCY0JrQkA=='
    profile = Convert-Utf8 '0J/QoNCe0KTQmNCb0Kw='
    engine = Convert-Utf8 '0JTQktCY0JbQntCa'
    language = Convert-Utf8 '0K/Ql9Cr0Jo='
    privilege = Convert-Utf8 '0J/QoNCQ0JLQkA=='
    ready = Convert-Utf8 '0JPQntCi0J7Qkg=='
    admin = Convert-Utf8 '0JDQlNCc0JjQnQ=='
    user = Convert-Utf8 '0J7QkdCr0KfQndCr0JU='
    service_panel = Convert-Utf8 '0KPQn9Cg0JDQktCb0JXQndCY0JUg0KHQm9Cj0JbQkdCe0Jk='
    filters_panel = Convert-Utf8 '0JzQkNCi0KDQmNCm0JAg0KTQmNCb0KzQotCg0J7Qkg=='
    data_panel = Convert-Utf8 '0JrQkNCd0JDQm9CrINCU0JDQndCd0KvQpQ=='
    tools_panel = Convert-Utf8 '0KHQmNCh0KLQldCc0J3Qq9CVINCY0J3QodCi0KDQo9Cc0JXQndCi0Ks='
    opt1 = Convert-Utf8 '0KDQkNCX0JLQldCg0J3Qo9Ci0Kwg0J/QoNCe0KTQmNCb0Kw='
    opt2 = Convert-Utf8 '0KPQlNCQ0JvQmNCi0Kwg0KHQm9Cj0JbQkdCr'
    opt3 = Convert-Utf8 '0KHQntCh0KLQntCv0J3QmNCVINCh0JjQodCi0JXQnNCr'
    opt4 = Convert-Utf8 '0JjQk9Cg0J7QktCe0Jkg0KTQmNCb0KzQotCg'
    opt5 = Convert-Utf8 'SVBTRVQt0KTQmNCb0KzQotCg'
    opt6 = Convert-Utf8 '0JrQntCd0KLQoNCe0JvQrCDQntCR0J3QntCS0JvQldCd0JjQmQ=='
    opt7 = Convert-Utf8 '0KXQoNCQ0J3QmNCb0JjQqdCVIFBBWUxPQUQ='
    opt8 = Convert-Utf8 '0J7QkdCd0J7QktCY0KLQrCBJUFNFVA=='
    opt9 = Convert-Utf8 '0J7QkdCd0J7QktCY0KLQrCBIT1NUUw=='
    opt10 = Convert-Utf8 '0JrQkNCd0JDQmyDQoNCV0JvQmNCX0J7Qkg=='
    opt11 = Convert-Utf8 '0K/QlNCg0J4g0JTQmNCQ0JPQndCe0KHQotCY0JrQmA=='
    opt12 = Convert-Utf8 '0JvQkNCR0J7QoNCQ0KLQntCg0JjQryDQodCi0KDQkNCi0JXQk9CY0Jk='
    opt13 = Convert-Utf8 '0KHQnNCV0J3QmNCi0Kwg0K/Ql9Cr0Jo='
    opt0 = Convert-Utf8 '0J7QotCa0JvQrtCn0JjQotCs0KHQryAvINCS0KvQpdCe0JQ='
    prompt = Convert-Utf8 '0JLQstC10LTQuNGC0LUg0LrQvtC80LDQvdC00YMgWzAtMTNd'
    invalid = Convert-Utf8 '0J3QtdC40LfQstC10YHRgtC90LDRjyDQutC+0LzQsNC90LTQsC4g0JTQvtC/0YPRgdGC0LjQvNGLINC30L3QsNGH0LXQvdC40Y8gMC0xMy4='
    boot_title = Convert-Utf8 '0JjQndCY0KbQmNCQ0JvQmNCX0JDQptCY0K8gQ09OVFJPTCBOT0RF'
    boot1 = Convert-Utf8 '0JjQvdC40YbQuNCw0LvQuNC30LDRhtC40Y8g0YLQtdGA0LzQuNC90LDQu9Cw'
    boot2 = Convert-Utf8 '0JfQsNCz0YDRg9C30LrQsCDRhtCy0LXRgtC+0LLQvtC5INC80LDRgtGA0LjRhtGL'
    boot3 = Convert-Utf8 '0KfRgtC10L3QuNC1INGB0L7RgdGC0L7Rj9C90LjRjyDRgdC70YPQttCx'
    boot4 = Convert-Utf8 '0J/QvtC00LrQu9GO0YfQtdC90LjQtSDQuNC90LTQtdC60YHQsCDQv9GA0L7RhNC40LvQtdC5'
    boot5 = Convert-Utf8 '0JrQvtC90YLRgNC+0LvRjNC90YvQuSDRg9C30LXQuyDQs9C+0YLQvtCy'
    action_title = Convert-Utf8 '0JLQq9Cf0J7Qm9Cd0JXQndCY0JUg0J7Qn9CV0KDQkNCm0JjQmA=='
    complete = Convert-Utf8 '0KPQn9Cg0JDQktCb0JXQndCY0JUg0J/QldCg0JXQlNCQ0J3QniDQodCY0KHQotCV0JzQndCe0JzQoyDQnNCe0JTQo9Cb0K4='
    launch_title = Convert-Utf8 '0JfQkNCf0KPQodCaINCf0KDQntCk0JjQm9Cv'
    launch1 = Convert-Utf8 '0KfRgtC10L3QuNC1INC/0YDQvtGE0LjQu9GPINGB0YLRgNCw0YLQtdCz0LjQuA=='
    launch2 = Convert-Utf8 '0J/RgNC+0LLQtdGA0LrQsCDQtNCy0LjQttC60LAgd2lud3M='
    launch3 = Convert-Utf8 '0J/RgNC+0LLQtdGA0LrQsCDQtNGA0LDQudCy0LXRgNCwIFdpbkRpdmVydA=='
    launch4 = Convert-Utf8 '0J/QvtC00LPQvtGC0L7QstC60LAg0LrQvtC80LDQvdC00L3QvtC5INGB0YLRgNC+0LrQuA=='
    launch5 = Convert-Utf8 '0J/QtdGA0LXQtNCw0YfQsCDRg9C/0YDQsNCy0LvQtdC90LjRjyDRgdGC0YDQsNGC0LXQs9C40Lg='
    found = Convert-Utf8 '0J3QkNCZ0JTQldCd'
    missing = Convert-Utf8 '0J3QlSDQndCQ0JnQlNCV0J0='
    action_deploy = Convert-Utf8 '0KPRgdGC0LDQvdC+0LLQutCwINCy0YvQsdGA0LDQvdC90L7QuSDRgdGC0YDQsNGC0LXQs9C40Lgg0LrQsNC6INGB0LvRg9C20LHRiw=='
    action_remove = Convert-Utf8 '0J7RgdGC0LDQvdC+0LLQutCwINC4INGD0LTQsNC70LXQvdC40LUg0YHQu9GD0LbQsQ=='
    action_status = Convert-Utf8 '0KfRgtC10L3QuNC1INGB0L7RgdGC0L7Rj9C90LjRjyDRgdC70YPQttCx0Ysg0Lgg0LTQstC40LbQutCw'
    action_game = Convert-Utf8 '0J/QtdGA0LXQutC70Y7Rh9C10L3QuNC1INC40LPRgNC+0LLQvtCz0L4g0YTQuNC70YzRgtGA0LA='
    action_ipset = Convert-Utf8 '0J/QtdGA0LXQutC70Y7Rh9C10L3QuNC1INGA0LXQttC40LzQsCBJUFNldA=='
    action_updatecheck = Convert-Utf8 '0J/QtdGA0LXQutC70Y7Rh9C10L3QuNC1INC/0YDQvtCy0LXRgNC60Lgg0L7QsdC90L7QstC70LXQvdC40Lk='
    action_payload = Convert-Utf8 '0JLRi9Cx0L7RgCDQsNC60YLQuNCy0L3QvtCz0L4gZmFrZS1wYXlsb2Fk'
    action_syncipset = Convert-Utf8 '0J7QsdC90L7QstC70LXQvdC40LUg0LTQuNCw0L/QsNC30L7QvdC+0LIgSVBTZXQ='
    action_synchosts = Convert-Utf8 '0J7QsdC90L7QstC70LXQvdC40LUg0YHQuNGB0YLQtdC80L3QvtCz0L4gaG9zdHM='
    action_releases = Convert-Utf8 '0J/RgNC+0LLQtdGA0LrQsCDQutCw0L3QsNC70LAg0YDQtdC70LjQt9C+0LIgTmV4Um91dGU='
    action_diagnostics = Convert-Utf8 '0JfQsNC/0YPRgdC6INGB0LjRgdGC0LXQvNC90L7QuSDQtNC40LDQs9C90L7RgdGC0LjQutC4'
    action_tests = Convert-Utf8 '0JfQsNC/0YPRgdC6INGC0LXRgdGC0L7QsiDRgdGC0YDQsNGC0LXQs9C40Lkg0LggRFBJ'
}

$en = @{
    tagline = 'ROUTE CONTROL // TRAFFIC ORCHESTRATOR'
    profile = 'PROFILE'
    engine = 'ENGINE'
    language = 'LANGUAGE'
    privilege = 'PRIVILEGE'
    ready = 'READY'
    admin = 'ADMIN'
    user = 'STANDARD'
    service_panel = 'SERVICE CONTROL'
    filters_panel = 'FILTER MATRIX'
    data_panel = 'DATA CHANNELS'
    tools_panel = 'SYSTEM TOOLKIT'
    opt1 = 'DEPLOY PROFILE'
    opt2 = 'PURGE SERVICES'
    opt3 = 'SYSTEM STATUS'
    opt4 = 'GAME FILTER'
    opt5 = 'IPSET FILTER'
    opt6 = 'UPDATE WATCH'
    opt7 = 'PAYLOAD VAULT'
    opt8 = 'SYNC IPSET'
    opt9 = 'SYNC HOSTS'
    opt10 = 'RELEASE CHANNEL'
    opt11 = 'DIAGNOSTIC CORE'
    opt12 = 'STRATEGY LAB'
    opt13 = 'SWITCH LANGUAGE'
    opt0 = 'DISCONNECT / EXIT'
    prompt = 'Enter command [0-13]'
    invalid = 'Unknown command. Accepted values: 0-13.'
    boot_title = 'INITIALIZING CONTROL NODE'
    boot1 = 'Initializing terminal'
    boot2 = 'Loading color matrix'
    boot3 = 'Reading service state'
    boot4 = 'Mounting profile index'
    boot5 = 'Control node ready'
    action_title = 'EXECUTING OPERATION'
    complete = 'CONTROL HANDED TO SYSTEM MODULE'
    launch_title = 'PROFILE BOOT'
    launch1 = 'Reading strategy profile'
    launch2 = 'Checking winws engine'
    launch3 = 'Checking WinDivert driver'
    launch4 = 'Preparing command line'
    launch5 = 'Transferring control to strategy'
    found = 'FOUND'
    missing = 'MISSING'
    action_deploy = 'Install selected strategy as Windows service'
    action_remove = 'Stop and remove NexRoute / WinDivert services'
    action_status = 'Read service and engine state'
    action_game = 'Toggle expanded game traffic filter'
    action_ipset = 'Switch IPSet routing mode'
    action_updatecheck = 'Toggle release checks'
    action_payload = 'Select active fake payload set'
    action_syncipset = 'Refresh IPSet ranges'
    action_synchosts = 'Refresh system hosts mappings'
    action_releases = 'Check NexRoute release channel'
    action_diagnostics = 'Run system conflict diagnostics'
    action_tests = 'Run strategy and DPI test suite'
}

function Get-Language {
    param([string]$Path)
    $result = 'RU'
    if ($Path -and (Test-Path -LiteralPath $Path -PathType Leaf)) {
        try {
            $candidate = (Get-Content -LiteralPath $Path -Raw).Trim().ToUpperInvariant()
            if ($candidate -in @('RU', 'EN')) {
                $result = $candidate
            }
        }
        catch {
        }
    }
    return $result
}

$language = Get-Language -Path $LanguageFile
if ($language -eq 'EN') {
    $text = $en
}
else {
    $text = $ru
}

try {
    $script:Width = [Math]::Min([Math]::Max([Console]::WindowWidth - 2, 88), 116)
}
catch {
    $script:Width = 100
}

function Fit-Text {
    param(
        [AllowEmptyString()][string]$Value,
        [int]$Length
    )
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
    $body = $Fill.ToString() * ($script:Width - 2)
    Write-Host ('+' + $body + '+') -ForegroundColor $Color
}

function Write-Centered {
    param(
        [string]$Value,
        [ConsoleColor]$Color = [ConsoleColor]::Cyan
    )
    $padding = [Math]::Max(0, [int](($script:Width - $Value.Length) / 2))
    Write-Host ((' ' * $padding) + $Value) -ForegroundColor $Color
}

function Write-Logo {
    $logo = @(
        ' _   _  _____ __  __ ____   ___  _   _ _____ _____ ',
        '| \ | || ____|\ \/ /|  _ \ / _ \| | | |_   _| ____|',
        '|  \| ||  _|   \  / | |_) | | | | | | | | | |  _|  ',
        '| |\  || |___  /  \ |  _ <| |_| | |_| | | | | |___ ',
        '|_| \_||_____|/_/\_\|_| \_\\___/ \___/  |_| |_____|'
    )
    $colors = @('Cyan', 'DarkCyan', 'Cyan', 'Magenta', 'Cyan')
    for ($index = 0; $index -lt $logo.Count; $index++) {
        Write-Centered -Value $logo[$index] -Color $colors[$index]
    }
    Write-Centered -Value $text.tagline -Color DarkGray
}

function Normalize-State {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return 'UNKNOWN' }
    return ($Value -replace '[\[\]]', '').Trim().ToUpperInvariant()
}

function Get-StateColor {
    param([string]$State)
    $normalized = Normalize-State -Value $State
    if ($normalized -match 'ENABLED|RUNNING|READY|ACTIVE|ON|OK|FOUND') { return 'Green' }
    if ($normalized -match 'DISABLED|STOPPED|OFF|ERROR|FAILED|MISSING') { return 'Red' }
    return 'Yellow'
}

function Test-IsAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Get-EnvironmentValue {
    param([string]$Name, [string]$Fallback)
    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) { return $Fallback }
    return $value
}

function Write-Header {
    $version = Get-EnvironmentValue -Name 'NEXROUTE_VERSION' -Fallback '0.0.0'
    $baseline = Get-EnvironmentValue -Name 'NEXROUTE_BASELINE' -Fallback 'unknown'
    $strategy = Get-EnvironmentValue -Name 'NEXROUTE_STRATEGY' -Fallback 'not selected'
    $strategy = ($strategy -replace '^(Current\s+)?Strategy\s*:\s*', '').Trim()
    if (Test-IsAdministrator) { $privilege = $text.admin } else { $privilege = $text.user }

    Write-Rule -Fill '=' -Color Cyan
    $title = " NEXROUTE CONTROL NODE  v$version  //  FLOWSEAL $baseline "
    Write-Centered -Value $title -Color White
    Write-Rule -Fill '=' -Color Cyan

    $right = "$($text.engine): $($text.ready)   $($text.language): $language   $($text.privilege): $privilege  "
    $leftLength = [Math]::Max(12, $script:Width - 3 - $right.Length)
    $leftValue = "  $($text.profile): $strategy"
    $left = Fit-Text -Value $leftValue -Length $leftLength
    $spaces = [Math]::Max(1, $script:Width - 2 - $left.Length - $right.Length)
    Write-Host '|' -NoNewline -ForegroundColor DarkCyan
    Write-Host $left -NoNewline -ForegroundColor Gray
    Write-Host (' ' * $spaces) -NoNewline
    Write-Host $right -NoNewline -ForegroundColor DarkGray
    Write-Host '|' -ForegroundColor DarkCyan
    Write-Rule -Color DarkCyan
}

function Write-PanelHeader {
    param([string]$Title)
    $label = "[ $Title ]"
    $remaining = [Math]::Max(0, $script:Width - 4 - $label.Length)
    Write-Host ('+--' + $label + ('-' * $remaining) + '+') -ForegroundColor DarkCyan
}

function Write-MenuItem {
    param([int]$Number, [string]$Title, [string]$Status = '')
    $numberText = '[{0:00}]' -f $Number
    $statusText = ''
    $normalized = ''
    if (-not [string]::IsNullOrWhiteSpace($Status)) {
        $normalized = Normalize-State -Value $Status
        $statusText = "[$normalized]"
    }
    $titleText = " $Title"
    $padding = [Math]::Max(1, $script:Width - 4 - $numberText.Length - $titleText.Length - $statusText.Length)
    Write-Host '|' -NoNewline -ForegroundColor DarkCyan
    Write-Host (' ' + $numberText) -NoNewline -ForegroundColor Cyan
    Write-Host $titleText -NoNewline -ForegroundColor White
    Write-Host (' ' * $padding) -NoNewline
    if ($statusText) {
        $stateColor = Get-StateColor -State $normalized
        Write-Host $statusText -NoNewline -ForegroundColor $stateColor
    }
    Write-Host ' |' -ForegroundColor DarkCyan
}

function Write-Footer {
    Write-Rule -Color DarkCyan
    Write-Host '|' -NoNewline -ForegroundColor DarkCyan
    Write-Host ' [00] ' -NoNewline -ForegroundColor Cyan
    $exitText = Fit-Text -Value $text.opt0 -Length ($script:Width - 10)
    Write-Host $exitText -NoNewline -ForegroundColor DarkGray
    Write-Host '|' -ForegroundColor DarkCyan
    Write-Rule -Fill '=' -Color Cyan
}

function Write-ProgressLine {
    param([string]$Label, [int]$Percent, [ConsoleColor]$Color = [ConsoleColor]::Cyan)
    $barWidth = [Math]::Min(42, [Math]::Max(20, $script:Width - 46))
    $filled = [int][Math]::Floor($barWidth * ($Percent / 100.0))
    $bar = ('#' * $filled) + ('-' * ($barWidth - $filled))
    $shortLabel = Fit-Text -Value $Label -Length 34
    $line = '  {0,-34} [{1}] {2,3}%' -f $shortLabel, $bar, $Percent
    $renderedLine = Fit-Text -Value $line -Length ($script:Width - 1)
    [Console]::Write("`r")
    $previousColor = [Console]::ForegroundColor
    [Console]::ForegroundColor = $Color
    [Console]::Write($renderedLine)
    [Console]::ForegroundColor = $previousColor
    if ($Percent -ge 100) { [Console]::WriteLine() }
}

function Animate-Step {
    param([string]$Label, [int]$Duration = 160, [ConsoleColor]$Color = [ConsoleColor]::Cyan)
    for ($percent = 0; $percent -le 100; $percent += 20) {
        Write-ProgressLine -Label $Label -Percent $percent -Color $Color
        $delay = [Math]::Max(5, [int]($Duration / 6))
        Start-Sleep -Milliseconds $delay
    }
}

function Show-Boot {
    try { [Console]::CursorVisible = $false } catch {}
    Clear-Host
    Write-Logo
    Write-Rule -Fill '=' -Color Cyan
    Write-Centered -Value $text.boot_title -Color Magenta
    Write-Rule -Fill '=' -Color Cyan
    Write-Host
    foreach ($step in @($text.boot1, $text.boot2, $text.boot3, $text.boot4)) {
        Animate-Step -Label $step -Duration 120 -Color Cyan
    }
    Write-Host
    Write-Centered -Value ("[ $($text.boot5) ]") -Color Green
    Start-Sleep -Milliseconds 260
    try { [Console]::CursorVisible = $true } catch {}
}

function Render-Menu {
    Clear-Host
    Write-Logo
    Write-Header
    Write-PanelHeader -Title $text.service_panel
    Write-MenuItem -Number 1 -Title $text.opt1
    Write-MenuItem -Number 2 -Title $text.opt2
    Write-MenuItem -Number 3 -Title $text.opt3
    Write-PanelHeader -Title $text.filters_panel
    Write-MenuItem -Number 4 -Title $text.opt4 -Status (Get-EnvironmentValue -Name 'NEXROUTE_GAME_STATUS' -Fallback 'UNKNOWN')
    Write-MenuItem -Number 5 -Title $text.opt5 -Status (Get-EnvironmentValue -Name 'NEXROUTE_IPSET_STATUS' -Fallback 'UNKNOWN')
    Write-MenuItem -Number 6 -Title $text.opt6 -Status (Get-EnvironmentValue -Name 'NEXROUTE_UPDATE_STATUS' -Fallback 'UNKNOWN')
    Write-MenuItem -Number 7 -Title $text.opt7
    Write-PanelHeader -Title $text.data_panel
    Write-MenuItem -Number 8 -Title $text.opt8
    Write-MenuItem -Number 9 -Title $text.opt9
    Write-MenuItem -Number 10 -Title $text.opt10
    Write-PanelHeader -Title $text.tools_panel
    Write-MenuItem -Number 11 -Title $text.opt11
    Write-MenuItem -Number 12 -Title $text.opt12
    if ($language -eq 'RU') { $targetLanguage = 'EN' } else { $targetLanguage = 'RU' }
    Write-MenuItem -Number 13 -Title $text.opt13 -Status $targetLanguage
    Write-Footer
}

function Get-ActionLabel {
    param([string]$Id)
    $map = @{
        deploy = 'action_deploy'; remove = 'action_remove'; status = 'action_status'; game = 'action_game'
        ipset = 'action_ipset'; updatecheck = 'action_updatecheck'; payload = 'action_payload'
        syncipset = 'action_syncipset'; synchosts = 'action_synchosts'; releases = 'action_releases'
        diagnostics = 'action_diagnostics'; tests = 'action_tests'
    }
    if ($map.ContainsKey($Id)) { return $text[$map[$Id]] }
    return $Id
}

function Show-Action {
    param([string]$Id)
    Clear-Host
    try { [Console]::CursorVisible = $false } catch {}
    Write-Logo
    Write-Rule -Fill '=' -Color Cyan
    Write-Centered -Value $text.action_title -Color Magenta
    Write-Rule -Fill '=' -Color Cyan
    Write-Host
    $label = Get-ActionLabel -Id $Id
    Animate-Step -Label $label -Duration 360 -Color Magenta
    Write-Host
    Write-Centered -Value ("[ $($text.complete) ]") -Color Green
    Start-Sleep -Milliseconds 320
    try { [Console]::CursorVisible = $true } catch {}
}

function Show-Launch {
    param([string]$Name)
    Clear-Host
    try { [Console]::CursorVisible = $false } catch {}
    Write-Logo
    Write-Rule -Fill '=' -Color Cyan
    Write-Centered -Value ("$($text.launch_title) // $Name") -Color Magenta
    Write-Rule -Fill '=' -Color Cyan
    Write-Host
    $root = Split-Path -Parent $PSScriptRoot
    Animate-Step -Label $text.launch1 -Duration 130 -Color Cyan
    $engineFound = Test-Path -LiteralPath (Join-Path $root 'bin\winws.exe') -PathType Leaf
    if ($engineFound) { $engineState = $text.found; $engineColor = 'Green' } else { $engineState = $text.missing; $engineColor = 'Red' }
    Animate-Step -Label ("$($text.launch2) : $engineState") -Duration 130 -Color $engineColor
    $driverFound = Test-Path -LiteralPath (Join-Path $root 'bin\WinDivert64.sys') -PathType Leaf
    if ($driverFound) { $driverState = $text.found; $driverColor = 'Green' } else { $driverState = $text.missing; $driverColor = 'Red' }
    Animate-Step -Label ("$($text.launch3) : $driverState") -Duration 130 -Color $driverColor
    Animate-Step -Label $text.launch4 -Duration 130 -Color Cyan
    Animate-Step -Label $text.launch5 -Duration 180 -Color Magenta
    Write-Host
    Start-Sleep -Milliseconds 180
    try { [Console]::CursorVisible = $true } catch {}
}

try { [Console]::Title = 'NexRoute // Control Node' } catch {}

switch ($Mode) {
    'Menu' {
        if ((Get-EnvironmentValue -Name 'NEXROUTE_UI_ANIMATE' -Fallback '0') -eq '1') { Show-Boot }
        while ($true) {
            Render-Menu
            Write-Host
            Write-Host ('  > ' + $text.prompt + ': ') -NoNewline -ForegroundColor Cyan
            $choice = (Read-Host).Trim()
            if ($choice -match '^(?:[0-9]|1[0-3])$') {
                if (-not $ChoiceFile) { throw 'ChoiceFile is required in Menu mode.' }
                Set-Content -LiteralPath $ChoiceFile -Value $choice -Encoding ascii
                break
            }
            Write-Host
            Write-Centered -Value $text.invalid -Color Red
            Start-Sleep -Milliseconds 850
        }
    }
    'Action' { Show-Action -Id $ActionId }
    'Launch' {
        if ($Profile) { $profileName = $Profile } else { $profileName = 'unknown' }
        Show-Launch -Name $profileName
    }
}
