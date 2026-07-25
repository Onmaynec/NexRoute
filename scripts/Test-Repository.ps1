[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$errors = [System.Collections.Generic.List[string]]::new()

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if ($Condition) { Write-Host "[ OK ] $Message" -ForegroundColor Green }
    else { $script:errors.Add($Message); Write-Host "[FAIL] $Message" -ForegroundColor Red }
}

function Test-PowerShellFile {
    param([string]$RelativePath)
    $path = Join-Path $root $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return }
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
    foreach ($parseError in $parseErrors) {
        Write-Host ("       {0}:{1} {2}" -f $parseError.Extent.StartLineNumber, $parseError.Extent.StartColumnNumber, $parseError.Message) -ForegroundColor Yellow
    }
    Assert-True ($parseErrors.Count -eq 0) "$RelativePath parses without PowerShell syntax errors"
}

Write-Host 'NexRoute 0.2.1 repository validation' -ForegroundColor Cyan
Write-Host '====================================' -ForegroundColor Cyan

$required = @(
    'README.md','CHANGELOG.md','LICENSE','THIRD_PARTY_NOTICES.md','.service/version.txt',
    'overlay/nexroute.bat','overlay/.service/nexroute-ui.ps1','overlay/.service/nexroute-services.ps1',
    'overlay/.service/services.json','overlay/.service/New-NexRouteIcon.ps1',
    'overlay/.service/i18n/ru.json','overlay/.service/i18n/en.json',
    'overlay/.service/i18n/nexroute-theme.ps1','overlay/.service/i18n/nexroute-pages.ps1',
    'overlay/.service/i18n/nexroute-services-ui.ps1','scripts/Build-NexRoute.ps1',
    'scripts/Test-Repository.ps1','scripts/Test-Package.ps1','.github/workflows/validate.yml',
    '.github/workflows/release.yml','.github/workflows/publish-v0.2.1.yml',
    '.github/release-notes/v0.2.1.md','docs/SERVICES.md'
)
foreach ($relativePath in $required) {
    Assert-True (Test-Path -LiteralPath (Join-Path $root $relativePath) -PathType Leaf) "Required file exists: $relativePath"
}

$version = (Get-Content -LiteralPath (Join-Path $root '.service/version.txt') -Raw).Trim()
Assert-True ($version -eq '0.2.1') 'Repository version is 0.2.1'
$readme = Get-Content -LiteralPath (Join-Path $root 'README.md') -Raw
Assert-True ($readme -match '0\.2\.1') 'README mentions 0.2.1'
Assert-True ($readme -match '0\.1\.1') 'README documents restored 0.1.1 design'

foreach ($relativePath in @(
    'scripts/Build-NexRoute.ps1','scripts/Test-Repository.ps1','scripts/Test-Package.ps1',
    'overlay/.service/nexroute-ui.ps1','overlay/.service/nexroute-services.ps1',
    'overlay/.service/New-NexRouteIcon.ps1','overlay/.service/i18n/nexroute-theme.ps1',
    'overlay/.service/i18n/nexroute-pages.ps1','overlay/.service/i18n/nexroute-services-ui.ps1'
)) { Test-PowerShellFile $relativePath }

$dispatcher = Get-Content -LiteralPath (Join-Path $root 'overlay/.service/nexroute-ui.ps1') -Raw
Assert-True ($dispatcher -match 'Repair-NexRouteEmbeddedArguments') 'Dispatcher recovers arguments swallowed by the trailing-backslash quote bug'
Assert-True ($dispatcher -match 'Repair-NexRouteBatchLaunchers') 'Dispatcher permanently repairs generated BAT launchers'
Assert-True ($dispatcher -match 'nexroute-theme\.ps1') 'Dispatcher loads classic theme module'

$theme = Get-Content -LiteralPath (Join-Path $root 'overlay/.service/i18n/nexroute-theme.ps1') -Raw
Assert-True ($theme -match [regex]::Escape('| \ | || ____|\ \/ /|  _ \ / _ \| | | |_   _| ____|')) 'Theme contains the 0.1.1 NexRoute logo layout'
Assert-True ($theme -match 'NEXROUTE CONTROL NODE') 'Theme contains the 0.1.1 control-node header'

foreach ($relativePath in @(
    'overlay/.service/nexroute-ui.ps1','overlay/.service/i18n/nexroute-theme.ps1',
    'overlay/.service/i18n/nexroute-pages.ps1','overlay/.service/i18n/nexroute-services-ui.ps1'
)) {
    $content = Get-Content -LiteralPath (Join-Path $root $relativePath) -Raw
    Assert-True (@($content.ToCharArray() | Where-Object { [int]$_ -gt 127 }).Count -eq 0) "$relativePath is ASCII-safe"
}

$services = @((Get-Content -LiteralPath (Join-Path $root 'overlay/.service/services.json') -Raw -Encoding UTF8 | ConvertFrom-Json).services)
Assert-True ($services.Count -eq 15) 'Service matrix contains 15 profiles'
$ids = @($services | ForEach-Object { $_.id })
Assert-True (($ids | Sort-Object -Unique).Count -eq $ids.Count) 'Service ids are unique'
foreach ($id in @('youtube','discord','chatgpt','facetime','snapchat','viber','signal','x','instagram','facebook','telegram','linkedin','tiktok','whatsapp','casebattle')) {
    Assert-True ($ids -contains $id) "Service matrix contains $id"
}

$builder = Get-Content -LiteralPath (Join-Path $root 'scripts/Build-NexRoute.ps1') -Raw
Assert-True ($builder -match "UpstreamVersion = '1\.10\.0'") 'Flowseal baseline remains pinned to 1.10.0'
Assert-True ($builder -match 'overlay/\.service/i18n') 'Builder copies the complete UI module directory'
Assert-True ($builder -match 'Get-FileHash.+SHA256') 'Builder creates SHA-256 checksums'

$forbiddenExtensions = @('.exe','.dll','.sys','.bin','.zip','.rar','.7z','.ico','.lnk')
$forbidden = @(Get-ChildItem -LiteralPath $root -File -Recurse -Force | Where-Object {
    $_.FullName -notmatch '[\\/]\.git[\\/]' -and $forbiddenExtensions -contains $_.Extension.ToLowerInvariant()
})
Assert-True ($forbidden.Count -eq 0) 'Git source tree contains no generated binaries or archives'

if ($errors.Count -gt 0) {
    Write-Host "`nValidation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}
Write-Host "`nAll NexRoute 0.2.1 repository checks passed." -ForegroundColor Green
