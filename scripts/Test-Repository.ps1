[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$errors = New-Object 'System.Collections.Generic.List[string]'
$expectedVersion = '0.3.0'
$bootstrapUnlocked = $env:NEXROUTE_BOOTSTRAP_UPSTREAM -eq '1'

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
    'README.md','CHANGELOG.md','LICENSE','THIRD_PARTY_NOTICES.md','.service/version.txt','.service/upstream-manifest.json',
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
    'scripts/Build-NexRoute.ps1','scripts/Build-Release.ps1','scripts/NexRoute.Upstream.psm1',
    'scripts/Test-Repository.ps1','scripts/Test-Package.ps1','scripts/Test-Release.ps1',
    'tests/ServiceMatrix.Tests.ps1','tests/UpstreamContract.Tests.ps1',
    '.github/workflows/validate.yml','.github/workflows/release.yml',
    '.github/release-notes/v0.3.0.md','docs/SERVICES.md','docs/UPSTREAM.md','docs/RELEASES.md'
)
foreach ($relativePath in $required) {
    Assert-True (Test-Path -LiteralPath (Join-Path $root $relativePath) -PathType Leaf) "Required file exists: $relativePath"
}

$version = (Get-Content -LiteralPath (Join-Path $root '.service/version.txt') -Raw).Trim()
Assert-True ($version -eq $expectedVersion) "Repository version is $expectedVersion"

$readme = Get-Content -LiteralPath (Join-Path $root 'README.md') -Raw
Assert-True ($readme -match [regex]::Escape($expectedVersion)) "README mentions $expectedVersion"
Assert-True ($readme -match '21') 'README documents all 21 real Flowseal strategies'
Assert-True ($readme -match 'upstream-lock\.json') 'README documents the upstream lock'
Assert-True ($readme -match 'patch-report\.json') 'README documents patch provenance'
Assert-True ($readme -match 'offline|офлайн') 'README documents offline rebuilds'

$powerShellFiles = @(Get-ChildItem -LiteralPath $root -File -Recurse -Force -Include '*.ps1','*.psm1' | Where-Object {
    $_.FullName -notmatch '[\\/]\.git[\\/]'
})
foreach ($file in $powerShellFiles) {
    Test-PowerShellFile ($file.FullName.Substring($root.Length).TrimStart('\','/'))
}

$upstreamModulePath = Join-Path $root 'scripts/NexRoute.Upstream.psm1'
try {
    Import-Module $upstreamModulePath -Force
    $manifest = Read-NexRouteUpstreamManifest -Path (Join-Path $root '.service/upstream-manifest.json')
    Assert-True ($manifest.schemaVersion -eq 1) 'Upstream manifest uses schema version 1'
    Assert-True ($manifest.repository -eq 'Flowseal/zapret-discord-youtube') 'Upstream manifest pins the Flowseal repository'
    Assert-True ($manifest.tag -eq '1.10.0') 'Upstream manifest pins Flowseal 1.10.0'
    Assert-True ($manifest.requiredPaths.Count -ge 8) 'Upstream manifest declares required archive paths'
    Assert-True (($manifest.expectedSha256 -match '^[0-9a-f]{64}$') -or $bootstrapUnlocked) 'Upstream manifest contains a locked SHA-256'
}
catch {
    Assert-True $false "Upstream manifest validates: $($_.Exception.Message)"
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

$upstreamModule = Get-Content -LiteralPath $upstreamModulePath -Raw
foreach ($token in @('expectedSha256','Test-NexRouteUpstreamArchive','Resolve-NexRouteUpstreamArchive','New-NexRouteProxyRelease','Unsafe upstream required path')) {
    Assert-True ($upstreamModule -match [regex]::Escape($token)) "Upstream module contains $token"
}

$buildWrapper = Get-Content -LiteralPath (Join-Path $root 'scripts/Build-Release.ps1') -Raw
foreach ($token in @(
    'NEXROUTE_SERVICE_FILTERS_V4','NEXROUTE_DYNAMIC_TARGETS_V4','NEXROUTE_REFRESH_MATRIX_V4',
    'upstream-lock.json','patch-report.json','Expected 23 tracked patch targets','UpstreamCachePath',
    'Building Flowseal','verified archive'
)) {
    Assert-True ($buildWrapper -match [regex]::Escape($token)) "Release builder contains $token"
}

$releaseTest = Get-Content -LiteralPath (Join-Path $root 'scripts/Test-Release.ps1') -Raw
foreach ($token in @('upstream-lock.json','patch-report.json','Expected 23 tracked patch targets','NEXROUTE_SERVICE_FILTERS_V4','NEXROUTE_DYNAMIC_TARGETS_V4')) {
    Assert-True ($releaseTest -match [regex]::Escape($token)) "Generic release test contains $token"
}

$serviceMatrixTests = Get-Content -LiteralPath (Join-Path $root 'tests/ServiceMatrix.Tests.ps1') -Raw
foreach ($token in @('shared domain only when all owners are disabled','backs up and replaces corrupt state','is idempotent','privacy-safe diagnostics')) {
    Assert-True ($serviceMatrixTests -match [regex]::Escape($token)) "Service Matrix Pester suite covers $token"
}

$upstreamTests = Get-Content -LiteralPath (Join-Path $root 'tests/UpstreamContract.Tests.ps1') -Raw
foreach ($token in @('path traversal','locked digest','offline archive','SHA-256 differs','missing a required upstream file','local release proxy')) {
    Assert-True ($upstreamTests -match [regex]::Escape($token)) "Upstream Pester suite covers $token"
}

$validateWorkflow = Get-Content -LiteralPath (Join-Path $root '.github/workflows/validate.yml') -Raw
foreach ($token in @('UpstreamContract.Tests.ps1','UpstreamCachePath','UpstreamArchive','offline','0.3.0')) {
    Assert-True ($validateWorkflow -match [regex]::Escape($token)) "Validation workflow contains $token"
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
