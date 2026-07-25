[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$errors = New-Object 'System.Collections.Generic.List[string]'

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

Write-Host 'NexRoute 0.2.2 repository validation' -ForegroundColor Cyan
Write-Host '====================================' -ForegroundColor Cyan

$required = @(
    'README.md','CHANGELOG.md','LICENSE','THIRD_PARTY_NOTICES.md','.service/version.txt',
    'overlay/nexroute.bat','overlay/.service/nexroute-ui.ps1','overlay/.service/nexroute-services.ps1',
    'overlay/.service/nexroute-services-entry.ps1','overlay/.service/services.json',
    'overlay/.service/New-NexRouteIcon.ps1','overlay/.service/i18n/ru.json','overlay/.service/i18n/en.json',
    'overlay/.service/i18n/nexroute-theme.ps1','overlay/.service/i18n/nexroute-pages.ps1',
    'overlay/.service/i18n/nexroute-pages-core.ps1','overlay/.service/i18n/nexroute-pages-network.ps1',
    'overlay/.service/i18n/nexroute-services-ui.ps1',
    'scripts/Build-NexRoute.ps1','scripts/Build-NexRoute-0.2.2.ps1',
    'scripts/Test-Repository.ps1','scripts/Test-Package.ps1','scripts/Test-Package-0.2.2.ps1',
    '.github/workflows/validate.yml','.github/workflows/publish-v0.2.2.yml',
    '.github/release-notes/v0.2.2.md','docs/SERVICES.md'
)
foreach ($relativePath in $required) {
    Assert-True (Test-Path -LiteralPath (Join-Path $root $relativePath) -PathType Leaf) "Required file exists: $relativePath"
}

$version = (Get-Content -LiteralPath (Join-Path $root '.service/version.txt') -Raw).Trim()
Assert-True ($version -eq '0.2.2') 'Repository version is 0.2.2'

$readme = Get-Content -LiteralPath (Join-Path $root 'README.md') -Raw
Assert-True ($readme -match '0\.2\.2') 'README mentions 0.2.2'
Assert-True ($readme -match '21') 'README documents all 21 real Flowseal strategies'
Assert-True ($readme -match 'Strategy Lab|Лаборатор') 'README documents Strategy Lab integration'

$powerShellFiles = @(
    'scripts/Build-NexRoute.ps1','scripts/Build-NexRoute-0.2.2.ps1',
    'scripts/Test-Repository.ps1','scripts/Test-Package.ps1','scripts/Test-Package-0.2.2.ps1',
    'overlay/.service/nexroute-ui.ps1','overlay/.service/nexroute-services.ps1',
    'overlay/.service/nexroute-services-entry.ps1','overlay/.service/New-NexRouteIcon.ps1',
    'overlay/.service/i18n/nexroute-theme.ps1','overlay/.service/i18n/nexroute-pages.ps1',
    'overlay/.service/i18n/nexroute-pages-core.ps1','overlay/.service/i18n/nexroute-pages-network.ps1',
    'overlay/.service/i18n/nexroute-services-ui.ps1'
)
foreach ($relativePath in $powerShellFiles) { Test-PowerShellFile $relativePath }

$dispatcher = Get-Content -LiteralPath (Join-Path $root 'overlay/.service/nexroute-ui.ps1') -Raw
foreach ($token in @('GameFilter','UpdateWatch','Repair-NexRouteEmbeddedArguments')) {
    Assert-True ($dispatcher -match [regex]::Escape($token)) "Dispatcher contains $token"
}

$pagesLoader = Get-Content -LiteralPath (Join-Path $root 'overlay/.service/i18n/nexroute-pages.ps1') -Raw
Assert-True ($pagesLoader -match 'nexroute-pages-core\.ps1') 'Page loader imports the core page module'
Assert-True ($pagesLoader -match 'nexroute-pages-network\.ps1') 'Page loader imports the network page module'

$servicesDocument = Get-Content -LiteralPath (Join-Path $root 'overlay/.service/services.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$services = @($servicesDocument.services)
Assert-True ($servicesDocument.schemaVersion -eq 2) 'Service Matrix uses schema version 2'
Assert-True ($services.Count -eq 15) 'Service Matrix contains 15 profiles'
$ids = @($services | ForEach-Object { $_.id })
Assert-True (($ids | Sort-Object -Unique).Count -eq $ids.Count) 'Service ids are unique'
foreach ($service in $services) {
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$service.descriptionEn)) "Service $($service.id) has an English description"
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$service.descriptionRu)) "Service $($service.id) has a Russian description"
    Assert-True (@($service.testTargets).Count -ge 2) "Service $($service.id) has real critical endpoints"
    Assert-True (@($service.tcpPorts).Count -gt 0 -or @($service.udpPorts).Count -gt 0) "Service $($service.id) has transport coverage"
}

$controller = Get-Content -LiteralPath (Join-Path $root 'overlay/.service/nexroute-services.ps1') -Raw
foreach ($token in @('TestTargets','Restart-InstalledStrategy','ipset-services-user.txt','services-runtime.cmd')) {
    Assert-True ($controller -match [regex]::Escape($token)) "Service controller contains $token"
}

$entry = Get-Content -LiteralPath (Join-Path $root 'overlay/.service/nexroute-services-entry.ps1') -Raw
Assert-True ($entry -match 'NEXROUTE_SERVICE_TCP_ARGS') 'Runtime entry generates TCP service filters'
Assert-True ($entry -match 'NEXROUTE_SERVICE_UDP_ARGS') 'Runtime entry generates UDP service filters'
Assert-True ($entry -match '--hostlist=') 'Runtime entry generates domain filters'
Assert-True ($entry -match '--ipset=') 'Runtime entry generates IP filters'

$networkPages = Get-Content -LiteralPath (Join-Path $root 'overlay/.service/i18n/nexroute-pages-network.ps1') -Raw
Assert-True ($networkPages -match 'NEXROUTE-HOSTS-BEGIN') 'SYNC HOSTS uses a managed block'
Assert-True ($networkPages -match '\[string\]\$localText =') 'SYNC HOSTS is null-safe'
Assert-True ($networkPages -match 'ipconfig\.exe /flushdns') 'SYNC HOSTS flushes DNS'

$buildWrapper = Get-Content -LiteralPath (Join-Path $root 'scripts/Build-NexRoute-0.2.2.ps1') -Raw
foreach ($token in @('Expected 21 real strategy BAT files','NEXROUTE_SERVICE_FILTERS_V2','NEXROUTE_DYNAMIC_TARGETS_V2','NEXROUTE_REFRESH_MATRIX_V2','nexroute.bat')) {
    Assert-True ($buildWrapper -match [regex]::Escape($token)) "0.2.2 builder contains $token"
}

$iconScript = Get-Content -LiteralPath (Join-Path $root 'overlay/.service/New-NexRouteIcon.ps1') -Raw
foreach ($token in @('New-NexRouteArtwork','New-RoundedRectanglePath','N E X R O U T E','Write-NexRouteIco','@(16, 20, 24, 32, 40, 48, 64, 128, 256)')) {
    Assert-True ($iconScript -match [regex]::Escape($token)) "Icon generator contains $token"
}

$forbiddenExtensions = @('.exe','.dll','.sys','.bin','.zip','.rar','.7z','.ico','.lnk')
$forbidden = @(Get-ChildItem -LiteralPath $root -File -Recurse -Force | Where-Object {
    $_.FullName -notmatch '[\\/]\.git[\\/]' -and $forbiddenExtensions -contains $_.Extension.ToLowerInvariant()
})
Assert-True ($forbidden.Count -eq 0) 'Git source tree contains no generated executables, drivers, archives, ICOs or shortcuts'

if ($errors.Count -gt 0) {
    Write-Host "`nValidation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}
Write-Host "`nAll NexRoute 0.2.2 repository checks passed." -ForegroundColor Green
