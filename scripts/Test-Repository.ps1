[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$errors = New-Object 'System.Collections.Generic.List[string]'
$expectedVersion = '0.2.3'

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

Write-Host "NexRoute $expectedVersion repository validation" -ForegroundColor Cyan
Write-Host '====================================' -ForegroundColor Cyan

$required = @(
    'README.md','CHANGELOG.md','LICENSE','THIRD_PARTY_NOTICES.md','.service/version.txt',
    'overlay/nexroute.bat','overlay/.service/nexroute-ui.ps1','overlay/.service/nexroute-services.ps1',
    'overlay/.service/nexroute-services-entry.ps1','overlay/.service/services.json',
    'overlay/.service/New-NexRouteIcon.ps1','overlay/.service/i18n/ru.json','overlay/.service/i18n/en.json',
    'overlay/.service/i18n/nexroute-theme.ps1','overlay/.service/i18n/nexroute-pages.ps1',
    'overlay/.service/i18n/nexroute-pages-core.ps1','overlay/.service/i18n/nexroute-pages-network.ps1',
    'overlay/.service/i18n/nexroute-services-ui.ps1',
    'overlay/.service/i18n/nexroute-services-state.ps1',
    'overlay/.service/i18n/nexroute-services-network.ps1',
    'overlay/.service/i18n/nexroute-services-runtime.ps1',
    'overlay/.service/i18n/nexroute-services-diagnostics.ps1',
    'scripts/Build-NexRoute.ps1','scripts/Build-Release.ps1',
    'scripts/Test-Repository.ps1','scripts/Test-Package.ps1','scripts/Test-Release.ps1',
    'tests/ServiceMatrix.Tests.ps1',
    '.github/workflows/validate.yml','.github/workflows/release.yml',
    '.github/release-notes/v0.2.3.md','docs/SERVICES.md'
)
foreach ($relativePath in $required) {
    Assert-True (Test-Path -LiteralPath (Join-Path $root $relativePath) -PathType Leaf) "Required file exists: $relativePath"
}

$version = (Get-Content -LiteralPath (Join-Path $root '.service/version.txt') -Raw).Trim()
Assert-True ($version -eq $expectedVersion) "Repository version is $expectedVersion"

$readme = Get-Content -LiteralPath (Join-Path $root 'README.md') -Raw
Assert-True ($readme -match [regex]::Escape($expectedVersion)) "README mentions $expectedVersion"
Assert-True ($readme -match '21') 'README documents all 21 real Flowseal strategies'
Assert-True ($readme -match 'Diagnostics|Диагност') 'README documents diagnostics export'
Assert-True ($readme -match '14') 'README documents the IP source cache TTL'

$powerShellFiles = @(Get-ChildItem -LiteralPath $root -Filter '*.ps1' -File -Recurse -Force | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' })
foreach ($file in $powerShellFiles) {
    Test-PowerShellFile ($file.FullName.Substring($root.Length).TrimStart('\','/'))
}

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

$controllerPath = Join-Path $root 'overlay/.service/nexroute-services.ps1'
$controllerFiles = @(
    $controllerPath,
    (Join-Path $root 'overlay/.service/i18n/nexroute-services-state.ps1'),
    (Join-Path $root 'overlay/.service/i18n/nexroute-services-network.ps1'),
    (Join-Path $root 'overlay/.service/i18n/nexroute-services-runtime.ps1'),
    (Join-Path $root 'overlay/.service/i18n/nexroute-services-diagnostics.ps1')
)
$controller = (($controllerFiles | ForEach-Object { Get-Content -LiteralPath $_ -Raw }) -join [Environment]::NewLine)
foreach ($token in @(
    'Diagnostics','services-state.v1.backup.json','services-state.invalid.backup.json',
    'ConvertTo-ValidatedIpv4Cidr','ConvertTo-ValidatedPort','sourceCacheMaxAgeDays = 14',
    'list-service-{0}.txt','ipset-service-{0}.txt','allDomains','enabledDomains.Contains',
    'AllowEmptyCollection'
)) {
    Assert-True ($controller -match [regex]::Escape($token)) "Service controller modules contain $token"
}

try {
    $validationOutput = & $controllerPath -Mode Validate -Root (Join-Path $root 'overlay') | Select-Object -Last 1
    Assert-True ($validationOutput -match 'strict ports/CIDR') 'Controller performs strict Service Matrix validation'
}
catch {
    Assert-True $false "Controller validation succeeds: $($_.Exception.Message)"
}

$entry = Get-Content -LiteralPath (Join-Path $root 'overlay/.service/nexroute-services-entry.ps1') -Raw
Assert-True ($entry -match 'nexroute-services-core\.ps1') 'Package entry delegates to the copied controller core'
Assert-True ($entry -match 'DiagnosticsPath') 'Package entry forwards diagnostics output path'

$buildWrapper = Get-Content -LiteralPath (Join-Path $root 'scripts/Build-Release.ps1') -Raw
foreach ($token in @('Expected 21 real strategy BAT files','NEXROUTE_SERVICE_FILTERS_V3','NEXROUTE_DYNAMIC_TARGETS_V3','NEXROUTE_REFRESH_MATRIX_V3','State schema: 2')) {
    Assert-True ($buildWrapper -match [regex]::Escape($token)) "Generic release builder contains $token"
}

$releaseTest = Get-Content -LiteralPath (Join-Path $root 'scripts/Test-Release.ps1') -Raw
foreach ($token in @('list-service-youtube.txt','ipset-service-youtube.txt','Diagnostics','Expected 15 services')) {
    Assert-True ($releaseTest -match [regex]::Escape($token)) "Generic release test contains $token"
}

$pesterTests = Get-Content -LiteralPath (Join-Path $root 'tests/ServiceMatrix.Tests.ps1') -Raw
foreach ($token in @('shared domain only when all owners are disabled','backs up and replaces corrupt state','is idempotent','privacy-safe diagnostics')) {
    Assert-True ($pesterTests -match [regex]::Escape($token)) "Pester suite covers $token"
}

$networkPages = Get-Content -LiteralPath (Join-Path $root 'overlay/.service/i18n/nexroute-pages-network.ps1') -Raw
Assert-True ($networkPages -match 'NEXROUTE-HOSTS-BEGIN') 'SYNC HOSTS uses a managed block'
Assert-True ($networkPages -match '\[string\]\$localText =') 'SYNC HOSTS is null-safe'
Assert-True ($networkPages -match 'ipconfig\.exe /flushdns') 'SYNC HOSTS flushes DNS'

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
Write-Host "`nAll NexRoute $expectedVersion repository checks passed." -ForegroundColor Green
