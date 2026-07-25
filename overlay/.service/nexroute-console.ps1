[CmdletBinding()]
param(
    [ValidateSet('Menu','Action','Launch')][string]$Mode = 'Menu',
    [string]$ChoiceFile,
    [string]$LanguageFile,
    [string]$ActionId,
    [string]$Profile
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
$width = 92
function Rule([char]$Fill = '=') { Write-Host ($Fill * $width) -ForegroundColor DarkCyan }
function Pad([string]$Value, [int]$Length) {
    if ($Value.Length -gt $Length) { return $Value.Substring(0, [Math]::Max(0, $Length - 3)) + '...' }
    return $Value + (' ' * ($Length - $Value.Length))
}
function Progress([string]$Label, [ConsoleColor]$Color = [ConsoleColor]::Cyan, [int]$Delay = 22) {
    for ($p = 0; $p -le 100; $p += 10) {
        $filled = [int]($p / 5)
        Write-Host ("`r  {0,-34} [{1}] {2,3}%" -f $Label, (('#' * $filled) + ('-' * (20-$filled))), $p) -NoNewline -ForegroundColor $Color
        Start-Sleep -Milliseconds $Delay
    }
    Write-Host
}
function State([string]$Name, [string]$Value) {
    Write-Host ('  ' + (Pad $Name 24)) -NoNewline -ForegroundColor DarkGray
    $color = if ($Value -match 'enabled|running|ready|elevated') { [ConsoleColor]::Green } elseif ($Value -match 'disabled|none|stopped') { [ConsoleColor]::DarkGray } else { [ConsoleColor]::Yellow }
    Write-Host ('[' + $Value + ']') -ForegroundColor $color
}
function Item([string]$Number, [string]$Title, [string]$Hint = '') {
    Write-Host ('  [' + $Number + '] ') -NoNewline -ForegroundColor Cyan
    Write-Host (Pad $Title 34) -NoNewline -ForegroundColor White
    if ($Hint) { Write-Host $Hint -ForegroundColor DarkGray } else { Write-Host }
}
function Header([string]$Title) {
    Clear-Host
    Rule
    Write-Host '  NX' -NoNewline -ForegroundColor Magenta
    Write-Host ' // NEXROUTE PACKET ORCHESTRATOR' -ForegroundColor Cyan
    Write-Host ('  ' + $Title) -ForegroundColor White
    Rule '-'
}
if ($Mode -eq 'Action') {
    Header 'OPERATION BUS'
    $labels = @{ deploy='Deploying selected strategy'; remove='Purging runtime services'; status='Reading runtime telemetry'; game='Switching game filter'; ipset='Switching IPSet mode'; updatecheck='Updating release watch'; payload='Opening payload vault'; syncipset='Synchronizing IPSet channels'; synchosts='Synchronizing hosts mappings'; releases='Querying release channel'; diagnostics='Starting diagnostic core'; tests='Starting strategy laboratory'; services='Opening service bypass matrix' }
    $label = if ($labels.ContainsKey($ActionId)) { $labels[$ActionId] } else { 'Executing system operation' }
    Progress $label Cyan 28
    Write-Host '  Control transferred to system module.' -ForegroundColor Green
    Start-Sleep -Milliseconds 220
    exit 0
}
if ($Mode -eq 'Launch') {
    Header 'PROFILE BOOT'
    Write-Host ('  Profile: ' + $Profile) -ForegroundColor White
    Progress 'Loading packet profile' Cyan 20
    Progress 'Checking winws engine' Green 20
    Progress 'Mounting WinDivert route' Magenta 20
    Write-Host '  Strategy command stream ready.' -ForegroundColor Green
    Start-Sleep -Milliseconds 180
    exit 0
}
Header ('CONTROL NODE v' + $env:NEXROUTE_VERSION)
if ($env:NEXROUTE_UI_ANIMATE -eq '1') {
    Progress 'Initializing terminal matrix' Cyan 18
    Progress 'Loading service telemetry' Magenta 18
    Progress 'Mounting profile index' Green 18
    Clear-Host
    Header ('CONTROL NODE v' + $env:NEXROUTE_VERSION)
}
Write-Host '  RUNTIME' -ForegroundColor Yellow
State 'Strategy' $env:NEXROUTE_STRATEGY
State 'Game filter' $env:NEXROUTE_GAME_STATUS
State 'IPSet' $env:NEXROUTE_IPSET_STATUS
State 'Update watch' $env:NEXROUTE_UPDATE_STATUS
Rule '-'
Write-Host '  SERVICE CONTROL' -ForegroundColor Yellow
Item '01' 'DEPLOY PROFILE' 'install selected strategy as service'
Item '02' 'PURGE SERVICES' 'remove NexRoute and WinDivert services'
Item '03' 'RUNTIME TELEMETRY' 'service, driver and process status'
Rule '-'
Write-Host '  FILTER MATRIX' -ForegroundColor Yellow
Item '04' 'GAME FILTER'
Item '05' 'IPSET FILTER'
Item '06' 'UPDATE WATCH'
Item '07' 'PAYLOAD VAULT'
Rule '-'
Write-Host '  DATA CHANNELS' -ForegroundColor Yellow
Item '08' 'SYNC IPSET'
Item '09' 'SYNC HOSTS'
Item '10' 'RELEASE CHANNEL'
Rule '-'
Write-Host '  SYSTEM TOOLKIT' -ForegroundColor Yellow
Item '11' 'DIAGNOSTIC CORE'
Item '12' 'STRATEGY LAB'
Item '13' 'SWITCH LANGUAGE'
Rule '-'
Write-Host '  OTHER SERVICE BYPASS' -ForegroundColor Yellow
Item '14' 'SERVICE MATRIX' 'YouTube, Discord, ChatGPT, social and messenger profiles'
Rule '-'
Item '00' 'DISCONNECT / EXIT'
Rule
$choice = (Read-Host '  Enter command [0-14]').Trim()
if ($choice -match '^\d$') { $choice = [int]$choice }
if ($choice -match '^0\d$') { $choice = [int]$choice }
if ($choice -notmatch '^(?:[0-9]|1[0-4])$') { $choice = '0' }
if ($ChoiceFile) { [System.IO.File]::WriteAllText($ChoiceFile, [string]$choice, [System.Text.Encoding]::ASCII) }
