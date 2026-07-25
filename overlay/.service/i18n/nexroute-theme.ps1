Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

try {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    $OutputEncoding = [Console]::OutputEncoding
}
catch {
}

$script:ServiceDirectory = Split-Path -Parent $PSScriptRoot
$rootCandidate = if ([string]::IsNullOrWhiteSpace($Root)) { Split-Path -Parent $script:ServiceDirectory } else { $Root }
$rootCandidate = $rootCandidate.Trim().Trim('"').Trim("'")
while ($rootCandidate.Length -gt 3 -and ($rootCandidate.EndsWith('\') -or $rootCandidate.EndsWith('/'))) {
    $rootCandidate = $rootCandidate.Substring(0, $rootCandidate.Length - 1)
}
try {
    $script:Root = [System.IO.Path]::GetFullPath($rootCandidate)
}
catch {
    $script:Root = Split-Path -Parent $script:ServiceDirectory
}

$script:LanguageFile = if ([string]::IsNullOrWhiteSpace($LanguageFile)) {
    Join-Path $script:ServiceDirectory 'language.txt'
}
else {
    $LanguageFile
}

function Get-NexRouteLanguage {
    $language = 'RU'
    if (Test-Path -LiteralPath $script:LanguageFile -PathType Leaf) {
        try {
            $candidate = (Get-Content -LiteralPath $script:LanguageFile -Raw -Encoding ASCII).Trim().ToUpperInvariant()
            if ($candidate -in @('RU', 'EN')) { $language = $candidate }
        }
        catch {
        }
    }
    return $language
}

function Get-NexRouteText {
    param([Parameter(Mandatory)][string]$Language)

    $path = Join-Path $script:ServiceDirectory ("i18n\{0}.json" -f $Language.ToLowerInvariant())
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $path = Join-Path $script:ServiceDirectory 'i18n\en.json'
    }
    return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

$script:Language = Get-NexRouteLanguage
$script:Text = Get-NexRouteText -Language $script:Language
$script:Width = 104
try {
    $script:Width = [Math]::Min([Math]::Max([Console]::WindowWidth - 2, 92), 116)
}
catch {
}

function Get-NexRouteEnvironmentValue {
    param([string]$Name, [string]$Fallback)
    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) { return $Fallback }
    return $value
}

function Test-NexRouteAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function Test-NexRouteServiceRunning {
    param([string]$Name)
    try { return ((Get-Service -Name $Name -ErrorAction Stop).Status -eq 'Running') }
    catch { return $false }
}

function Format-NexRouteText {
    param([AllowNull()][string]$Value, [int]$Length)
    if ($Length -lt 1) { return '' }
    if ($null -eq $Value) { $Value = '' }
    if ($Value.Length -gt $Length) {
        if ($Length -le 3) { return $Value.Substring(0, $Length) }
        return $Value.Substring(0, $Length - 3) + '...'
    }
    return $Value.PadRight($Length)
}

function Get-NexRouteStateColor {
    param([string]$State)
    $value = if ($State) { ($State -replace '[\[\]]', '').Trim().ToLowerInvariant() } else { '' }
    if ($value -match 'running|ready|enabled|loaded|on|found|success|baseline|stable') { return [ConsoleColor]::Green }
    if ($value -match 'warning|experimental|advanced|any|standard|web') { return [ConsoleColor]::Yellow }
    if ($value -match 'missing|stopped|disabled|none|off|error|failed') { return [ConsoleColor]::Red }
    return [ConsoleColor]::Yellow
}

function Write-NexRouteRule {
    param([char]$Fill = '-', [ConsoleColor]$Color = [ConsoleColor]::DarkCyan)
    Write-Host ('+' + ($Fill.ToString() * ($script:Width - 2)) + '+') -ForegroundColor $Color
}

function Write-NexRouteCentered {
    param([string]$Value, [ConsoleColor]$Color = [ConsoleColor]::White)
    $padding = [Math]::Max(0, [int](($script:Width - $Value.Length) / 2))
    Write-Host ((' ' * $padding) + $Value) -ForegroundColor $Color
}

function Write-NexRouteLogo {
    $logo = @(
        ' _   _  _____ __  __ ____   ___  _   _ _____ _____ ',
        '| \ | || ____|\ \/ /|  _ \ / _ \| | | |_   _| ____|',
        '|  \| ||  _|   \  / | |_) | | | | | | | | | |  _|  ',
        '| |\  || |___  /  \ |  _ <| |_| | |_| | | | | |___ ',
        '|_| \_||_____|/_/\_\|_| \_\\___/ \___/  |_| |_____|'
    )
    $colors = @('Cyan', 'DarkCyan', 'Cyan', 'Magenta', 'Cyan')
    for ($index = 0; $index -lt $logo.Count; $index++) {
        Write-NexRouteCentered -Value $logo[$index] -Color $colors[$index]
    }
    Write-NexRouteCentered -Value $script:Text.tagline -Color DarkGray
}

function Write-NexRouteHeader {
    param([string]$Title)

    Clear-Host
    try { $Host.UI.RawUI.WindowTitle = "NexRoute // $Title" } catch {}
    Write-NexRouteLogo

    $version = Get-NexRouteEnvironmentValue -Name 'NEXROUTE_VERSION' -Fallback '0.2.1'
    $baseline = Get-NexRouteEnvironmentValue -Name 'NEXROUTE_BASELINE' -Fallback '1.10.0'
    $strategy = Get-NexRouteEnvironmentValue -Name 'NEXROUTE_STRATEGY' -Fallback 'none'
    $strategy = ($strategy -replace '^(Current\s+)?Strategy\s*:\s*', '').Trim()
    $privilege = if (Test-NexRouteAdministrator) { $script:Text.elevated } else { $script:Text.standard }

    Write-NexRouteRule -Fill '=' -Color Cyan
    Write-NexRouteCentered -Value (" NEXROUTE CONTROL NODE  v$version  //  FLOWSEAL $baseline ") -Color White
    Write-NexRouteRule -Fill '=' -Color Cyan

    $right = "$($script:Text.engine): $($script:Text.ready)   $($script:Text.language): $($script:Language)   $($script:Text.privilege): $privilege  "
    $leftLength = [Math]::Max(12, $script:Width - 3 - $right.Length)
    $left = Format-NexRouteText -Value ("  $($script:Text.profile): $strategy") -Length $leftLength
    $spaces = [Math]::Max(1, $script:Width - 2 - $left.Length - $right.Length)

    Write-Host '|' -NoNewline -ForegroundColor DarkCyan
    Write-Host $left -NoNewline -ForegroundColor Gray
    Write-Host (' ' * $spaces) -NoNewline
    Write-Host $right -NoNewline -ForegroundColor DarkGray
    Write-Host '|' -ForegroundColor DarkCyan
    Write-NexRouteRule -Color DarkCyan

    if ($Title -and $Title -notmatch '^CONTROL NODE') {
        Write-NexRoutePanel -Title $Title
    }
}

function Write-NexRoutePanel {
    param([string]$Title)
    $label = "[ $Title ]"
    $remaining = [Math]::Max(0, $script:Width - 4 - $label.Length)
    Write-Host ('+--' + $label + ('-' * $remaining) + '+') -ForegroundColor DarkCyan
}

function Write-NexRouteOption {
    param([int]$Number, [string]$Label, [string]$Status = '')

    $numberText = '[{0:00}]' -f $Number
    $statusText = if ($Status) { '[' + (($Status -replace '[\[\]]', '').Trim().ToUpperInvariant()) + ']' } else { '' }
    $titleText = ' ' + $Label
    $padding = [Math]::Max(1, $script:Width - 4 - $numberText.Length - $titleText.Length - $statusText.Length)

    Write-Host '|' -NoNewline -ForegroundColor DarkCyan
    Write-Host (' ' + $numberText) -NoNewline -ForegroundColor Cyan
    Write-Host $titleText -NoNewline -ForegroundColor White
    Write-Host (' ' * $padding) -NoNewline
    if ($statusText) { Write-Host $statusText -NoNewline -ForegroundColor (Get-NexRouteStateColor -State $Status) }
    Write-Host ' |' -ForegroundColor DarkCyan
}

function Write-NexRouteKeyValue {
    param([string]$Key, [string]$Value, [ConsoleColor]$ValueColor = [ConsoleColor]::White)

    $keyWidth = [Math]::Min(30, [Math]::Max(18, [int]($script:Width * 0.28)))
    Write-Host '|' -NoNewline -ForegroundColor DarkCyan
    Write-Host ('  ' + (Format-NexRouteText -Value $Key -Length $keyWidth)) -NoNewline -ForegroundColor DarkGray
    Write-Host ' : ' -NoNewline -ForegroundColor DarkCyan
    Write-Host (Format-NexRouteText -Value $Value -Length ($script:Width - $keyWidth - 8)) -NoNewline -ForegroundColor $ValueColor
    Write-Host '|' -ForegroundColor DarkCyan
}

function Write-NexRouteProgress {
    param([string]$Label, [int]$Percent, [ConsoleColor]$Color = [ConsoleColor]::Cyan)

    $barWidth = [Math]::Min(42, [Math]::Max(20, $script:Width - 46))
    $filled = [int][Math]::Floor($barWidth * ($Percent / 100.0))
    $bar = ('#' * $filled) + ('-' * ($barWidth - $filled))
    $line = '  {0,-34} [{1}] {2,3}%' -f (Format-NexRouteText -Value $Label -Length 34), $bar, $Percent
    $rendered = Format-NexRouteText -Value $line -Length ($script:Width - 1)

    try {
        [Console]::Write("`r")
        $old = [Console]::ForegroundColor
        [Console]::ForegroundColor = $Color
        [Console]::Write($rendered)
        [Console]::ForegroundColor = $old
        if ($Percent -ge 100) { [Console]::WriteLine() }
    }
    catch { Write-Host $line -ForegroundColor $Color }
}

function Invoke-NexRouteAnimation {
    param([string]$Label, [int]$Duration = 160, [ConsoleColor]$Color = [ConsoleColor]::Cyan)
    foreach ($percent in @(0, 20, 40, 60, 80, 100)) {
        Write-NexRouteProgress -Label $Label -Percent $percent -Color $Color
        Start-Sleep -Milliseconds ([Math]::Max(5, [int]($Duration / 6)))
    }
}

function Write-NexRouteResult {
    param([bool]$Success, [string]$Message)
    Write-Host ''
    Write-NexRouteRule -Color DarkCyan
    if ($Success) { Write-NexRouteCentered -Value ("[ OK ] $Message") -Color Green }
    else { Write-NexRouteCentered -Value ("[ ERROR ] $Message") -Color Red }
    Write-NexRouteRule -Color DarkCyan
}

function Wait-NexRouteKey {
    if ($NonInteractive) { return }
    Write-Host ''
    Write-NexRouteCentered -Value $script:Text.pressKey -Color DarkGray
    try { [void][Console]::ReadKey($true) } catch { Read-Host | Out-Null }
}

function Get-NexRouteServiceSummary {
    $controller = Join-Path $script:ServiceDirectory 'nexroute-services.ps1'
    if (-not (Test-Path -LiteralPath $controller -PathType Leaf)) { return '0/0' }
    try {
        $json = & $controller -Mode Summary -Root $script:Root | Select-Object -Last 1
        $summary = $json | ConvertFrom-Json
        return ("{0}/{1}" -f $summary.Enabled, $summary.Total)
    }
    catch { return '0/0' }
}
