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
function U([string]$Value) { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Value)) }
function Get-Language {
    if ($LanguageFile -and (Test-Path $LanguageFile)) {
        $value=(Get-Content $LanguageFile -Raw).Trim().ToUpperInvariant()
        if ($value -in @('RU','EN')) { return $value }
    }
    return 'RU'
}
$ru=@{
 control=(U '0KbQldCd0KLQoCDQo9Cf0KDQkNCS0JvQldCd0JjQrw=='); runtime=(U '0KHQntCh0KLQntCv0J3QmNCV'); strategy=(U '0KHRgtGA0LDRgtC10LPQuNGP'); game=(U '0JjQs9GA0L7QstC+0Lkg0YTQuNC70YzRgtGA'); ipset=(U 'SVBTZXQt0YTQuNC70YzRgtGA'); update=(U '0J/RgNC+0LLQtdGA0LrQsCDQvtCx0L3QvtCy0LvQtdC90LjQuQ=='); service=(U '0KPQn9Cg0JDQktCb0JXQndCY0JUg0KHQm9Cj0JbQkdCe0Jk='); deploy=(U '0KPQodCi0JDQndCe0JLQmNCi0Kwg0J/QoNCe0KTQmNCb0Kw='); purge=(U '0KPQlNCQ0JvQmNCi0Kwg0KHQm9Cj0JbQkdCr'); telemetry=(U '0KHQntCh0KLQntCv0J3QmNCVINCh0JjQodCi0JXQnNCr'); filters=(U '0JzQkNCi0KDQmNCm0JAg0KTQmNCb0KzQotCg0J7Qkg=='); gamef=(U '0JjQk9Cg0J7QktCe0Jkg0KTQmNCb0KzQotCg'); ipsetf=(U 'SVBTRVQt0KTQmNCb0KzQotCg'); updatew=(U '0JrQntCd0KLQoNCe0JvQrCDQntCR0J3QntCS0JvQldCd0JjQmQ=='); payload=(U '0KXQoNCQ0J3QmNCb0JjQqdCVIFBBWUxPQUQ='); data=(U '0JrQkNCd0JDQm9CrINCU0JDQndCd0KvQpQ=='); syncip=(U '0KHQmNCd0KXQoNCe0J3QmNCX0JDQptCY0K8gSVBTRVQ='); synchost=(U '0KHQmNCd0KXQoNCe0J3QmNCX0JDQptCY0K8gSE9TVFM='); release=(U '0JrQkNCd0JDQmyDQoNCV0JvQmNCX0J7Qkg=='); tools=(U '0KHQmNCh0KLQldCc0J3Qq9CVINCY0J3QodCi0KDQo9Cc0JXQndCi0Ks='); diag=(U '0JTQmNCQ0JPQndCe0KHQotCY0JrQkA=='); lab=(U '0JvQkNCR0J7QoNCQ0KLQntCg0JjQryDQodCi0KDQkNCi0JXQk9CY0Jk='); lang=(U '0J/QldCg0JXQmtCb0K7Qp9CY0KLQrCDQr9CX0KvQmg=='); other=(U '0J7QkdCl0J7QlCDQlNCg0KPQk9CY0KUg0KHQldCg0JLQmNCh0J7Qkg=='); matrix=(U '0JzQkNCi0KDQmNCm0JAg0KHQldCg0JLQmNCh0J7Qkg=='); exit=(U '0JLQq9Cl0J7QlA=='); prompt=(U '0JLQstC10LTQuNGC0LUg0LrQvtC80LDQvdC00YMgWzAtMTRd'); action=(U '0JLQq9Cf0J7Qm9Cd0JXQndCY0JUg0J7Qn9CV0KDQkNCm0JjQmA==')
}
$en=@{ control='CONTROL NODE'; runtime='RUNTIME'; strategy='Strategy'; game='Game filter'; ipset='IPSet'; update='Update watch'; service='SERVICE CONTROL'; deploy='DEPLOY PROFILE'; purge='PURGE SERVICES'; telemetry='RUNTIME TELEMETRY'; filters='FILTER MATRIX'; gamef='GAME FILTER'; ipsetf='IPSET FILTER'; updatew='UPDATE WATCH'; payload='PAYLOAD VAULT'; data='DATA CHANNELS'; syncip='SYNC IPSET'; synchost='SYNC HOSTS'; release='RELEASE CHANNEL'; tools='SYSTEM TOOLKIT'; diag='DIAGNOSTIC CORE'; lab='STRATEGY LAB'; lang='SWITCH LANGUAGE'; other='OTHER SERVICE BYPASS'; matrix='SERVICE MATRIX'; exit='DISCONNECT / EXIT'; prompt='Enter command [0-14]'; action='OPERATION BUS' }
$text=if ((Get-Language) -eq 'EN') { $en } else { $ru }
$width=92
function Rule([char]$Fill='=') { Write-Host ($Fill*$width) -ForegroundColor DarkCyan }
function Pad([string]$Value,[int]$Length) { if ($Value.Length -gt $Length) { return $Value.Substring(0,[Math]::Max(0,$Length-3))+'...' }; $Value+(' '*($Length-$Value.Length)) }
function Progress([string]$Label,[ConsoleColor]$Color=[ConsoleColor]::Cyan,[int]$Delay=22) {
    for($p=0;$p -le 100;$p+=10){$filled=[int]($p/5);Write-Host ("`r  {0,-34} [{1}] {2,3}%" -f $Label,(('#'*$filled)+('-'*(20-$filled))),$p) -NoNewline -ForegroundColor $Color;Start-Sleep -Milliseconds $Delay};Write-Host
}
function State([string]$Name,[string]$Value){Write-Host ('  '+(Pad $Name 24)) -NoNewline -ForegroundColor DarkGray;$color=if($Value -match 'enabled|running|ready|elevated'){[ConsoleColor]::Green}elseif($Value -match 'disabled|none|stopped'){[ConsoleColor]::DarkGray}else{[ConsoleColor]::Yellow};Write-Host ('['+$Value+']') -ForegroundColor $color}
function Item([string]$Number,[string]$Title,[string]$Hint=''){Write-Host ('  ['+$Number+'] ') -NoNewline -ForegroundColor Cyan;Write-Host (Pad $Title 34) -NoNewline -ForegroundColor White;if($Hint){Write-Host $Hint -ForegroundColor DarkGray}else{Write-Host}}
function Header([string]$Title){Clear-Host;Rule;Write-Host '  NX' -NoNewline -ForegroundColor Magenta;Write-Host ' // NEXROUTE PACKET ORCHESTRATOR' -ForegroundColor Cyan;Write-Host ('  '+$Title) -ForegroundColor White;Rule '-'}
if($Mode -eq 'Action'){Header $text.action;$labels=@{deploy='Deploying selected strategy';remove='Purging runtime services';status='Reading runtime telemetry';game='Switching game filter';ipset='Switching IPSet mode';updatecheck='Updating release watch';payload='Opening payload vault';syncipset='Synchronizing IPSet channels';synchosts='Synchronizing hosts mappings';releases='Querying release channel';diagnostics='Starting diagnostic core';tests='Starting strategy laboratory';services='Opening service bypass matrix'};$label=if($labels.ContainsKey($ActionId)){$labels[$ActionId]}else{'Executing system operation'};Progress $label Cyan 28;Write-Host '  Control transferred to system module.' -ForegroundColor Green;Start-Sleep -Milliseconds 220;exit 0}
if($Mode -eq 'Launch'){Header 'PROFILE BOOT';Write-Host ('  Profile: '+$Profile) -ForegroundColor White;Progress 'Loading packet profile' Cyan 20;Progress 'Checking winws engine' Green 20;Progress 'Mounting WinDivert route' Magenta 20;Write-Host '  Strategy command stream ready.' -ForegroundColor Green;Start-Sleep -Milliseconds 180;exit 0}
Header ($text.control+' v'+$env:NEXROUTE_VERSION)
if($env:NEXROUTE_UI_ANIMATE -eq '1'){Progress 'Initializing terminal matrix' Cyan 18;Progress 'Loading service telemetry' Magenta 18;Progress 'Mounting profile index' Green 18;Clear-Host;Header ($text.control+' v'+$env:NEXROUTE_VERSION)}
Write-Host ('  '+$text.runtime) -ForegroundColor Yellow
State $text.strategy $env:NEXROUTE_STRATEGY;State $text.game $env:NEXROUTE_GAME_STATUS;State $text.ipset $env:NEXROUTE_IPSET_STATUS;State $text.update $env:NEXROUTE_UPDATE_STATUS
Rule '-';Write-Host ('  '+$text.service) -ForegroundColor Yellow;Item '01' $text.deploy;Item '02' $text.purge;Item '03' $text.telemetry
Rule '-';Write-Host ('  '+$text.filters) -ForegroundColor Yellow;Item '04' $text.gamef;Item '05' $text.ipsetf;Item '06' $text.updatew;Item '07' $text.payload
Rule '-';Write-Host ('  '+$text.data) -ForegroundColor Yellow;Item '08' $text.syncip;Item '09' $text.synchost;Item '10' $text.release
Rule '-';Write-Host ('  '+$text.tools) -ForegroundColor Yellow;Item '11' $text.diag;Item '12' $text.lab;Item '13' $text.lang
Rule '-';Write-Host ('  '+$text.other) -ForegroundColor Yellow;Item '14' $text.matrix 'YouTube, Discord, ChatGPT, social and messenger profiles'
Rule '-';Item '00' $text.exit;Rule
$choice=(Read-Host ('  '+$text.prompt)).Trim();if($choice -match '^\d$'){$choice=[int]$choice};if($choice -match '^0\d$'){$choice=[int]$choice};if($choice -notmatch '^(?:[0-9]|1[0-4])$'){$choice='0'};if($ChoiceFile){[IO.File]::WriteAllText($ChoiceFile,[string]$choice,[Text.Encoding]::ASCII)}
