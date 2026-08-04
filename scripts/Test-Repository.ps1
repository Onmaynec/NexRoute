[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$errors=New-Object 'System.Collections.Generic.List[string]'
$expectedVersion='0.6.2'
$bootstrapUnlocked=$env:NEXROUTE_BOOTSTRAP_UPSTREAM -eq '1'

function Assert-True {
    param([bool]$Condition,[string]$Message)
    if ($Condition) { Write-Host "[ OK ] $Message" -ForegroundColor Green }
    else { $script:errors.Add($Message); Write-Host "[FAIL] $Message" -ForegroundColor Red }
}

function Read-Text {
    param([Parameter(Mandatory)][string]$RelativePath)
    return Get-Content -LiteralPath (Join-Path $root $RelativePath) -Raw -Encoding UTF8
}

function Test-PowerShellFile {
    param([Parameter(Mandatory)][string]$Path)
    $tokens=$null
    $parseErrors=$null
    [void][Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) {
        Write-Host ("       {0}:{1} {2}" -f $parseError.Extent.StartLineNumber,$parseError.Extent.StartColumnNumber,$parseError.Message) -ForegroundColor Yellow
    }
    $relative=$Path.Substring($root.Length).TrimStart('\','/')
    Assert-True (@($parseErrors).Count -eq 0) "$relative parses without PowerShell syntax errors"
}

Write-Host "NexRoute $expectedVersion repository validation" -ForegroundColor Cyan
Write-Host '====================================' -ForegroundColor Cyan

$required=@(
    'README.md','CHANGELOG.md','LICENSE','THIRD_PARTY_NOTICES.md',
    '.service/version.txt','.service/upstream-manifest.json',
    'overlay/service.bat','overlay/nexroute.bat','overlay/nexroute-update.cmd','overlay/nexroute-tray.cmd','overlay/nexroute-validation.cmd',
    'overlay/.service/nexroute-console.ps1','overlay/.service/nexroute-updater.ps1','overlay/.service/nexroute-updater-entry.ps1',
    'overlay/.service/nexroute-services.ps1','overlay/.service/nexroute-services-entry.ps1','overlay/.service/services.json',
    'overlay/.service/next/nexroute-common.ps1','overlay/.service/next/nexroute-strategies.ps1','overlay/.service/next/nexroute-network.ps1',
    'overlay/.service/next/nexroute-diagnostics.ps1','overlay/.service/next/nexroute-diagnostics-fixes.ps1',
    'overlay/.service/next/nexroute-management.ps1','overlay/.service/next/nexroute-update.ps1',
    'overlay/.service/next/nexroute-runtime-extensions.ps1','overlay/.service/next/nexroute-hotfix-062.ps1',
    'overlay/.service/next/nexroute-notifications.ps1','overlay/.service/next/nexroute-attestation-v2.ps1',
    'native/NexRoute.Tray/Program.cs','native/NexRoute.Notifier/Program.cs','native/NexRoute.Dashboard/Program.cs','native/NexRoute.Validation/Program.cs',
    'scripts/Build-NativeTray.ps1','scripts/Build-NexRoute.ps1','scripts/Build-Package.ps1','scripts/Build-Release.ps1',
    'scripts/New-ValidationReport.ps1','scripts/NexRoute.Upstream.psm1','scripts/Resolve-PinnedUpstream.ps1',
    'scripts/Test-Package.ps1','scripts/Test-Release.ps1','scripts/Test-V06Desktop.ps1','scripts/Test-WindowsLaunchers.ps1',
    'tests/ServiceMatrix.Tests.ps1','tests/UpstreamContract.Tests.ps1','tests/Updater.Tests.ps1','tests/UpdaterMigration.Tests.ps1',
    'tests/ReleaseAttestation.Tests.ps1','tests/ReleaseCoherence.Tests.ps1','tests/NextInterface.Tests.ps1',
    'tests/Notifications.Tests.ps1','tests/NativeTray.Tests.ps1','tests/ValidationReport.Tests.ps1','tests/ValidationViewer.Tests.ps1',
    'tests/LauncherHotfix.Tests.ps1','tests/Hotfix062.Tests.ps1',
    '.github/workflows/validate.yml','.github/workflows/release.yml','.github/workflows/pages.yml',
    '.github/release-notes/v0.6.0.md','.github/release-notes/v0.6.1.md','.github/release-notes/v0.6.2.md',
    'docs/RELEASE_0.6.0_ACCEPTANCE.md','docs/SERVICES.md','docs/UPSTREAM.md','docs/RELEASES.md','docs/UPDATES.md','docs/ATTESTATIONS.md','docs/WEBSITE.md',
    'website/package.json','website/package-lock.json','website/tsconfig.json','website/next.config.ts','website/postcss.config.mjs','website/.env.example',
    'website/app/layout.tsx','website/app/page.tsx','website/app/features/page.tsx','website/app/download/page.tsx',
    'website/app/docs/page.tsx','website/app/docs/[slug]/page.tsx','website/app/security/page.tsx','website/app/faq/page.tsx','website/app/changelog/page.tsx',
    'website/components/layout/site-header.tsx','website/components/layout/site-footer.tsx','website/components/product/demos.tsx',
    'website/components/docs/docs-shell.tsx','website/components/docs/doc-article.tsx','website/components/ui/code-block.tsx',
    'website/content/docs.ts','website/content/faq.ts','website/content/site.ts','website/lib/github.ts','website/lib/metadata.ts'
)
foreach ($relative in $required) {
    Assert-True (Test-Path -LiteralPath (Join-Path $root $relative) -PathType Leaf) "Required file exists: $relative"
}

$version=(Read-Text '.service/version.txt').Trim()
Assert-True ($version -eq $expectedVersion) "Repository version is $expectedVersion"

$readme=Read-Text 'README.md'
$changelog=Read-Text 'CHANGELOG.md'
$releaseNotes=Read-Text '.github/release-notes/v0.6.2.md'
$websitePackage=Read-Text 'website/package.json' | ConvertFrom-Json
$websiteLock=Read-Text 'website/package-lock.json' | ConvertFrom-Json
Assert-True ($readme -match [regex]::Escape("NexRoute $expectedVersion")) "README mentions $expectedVersion"
Assert-True ($changelog -match [regex]::Escape('## [0.6.2] - 2026-08-04')) 'CHANGELOG contains the 0.6.2 entry'
Assert-True ($releaseNotes -match [regex]::Escape('# NexRoute 0.6.2 — Hot Bug Fix')) 'Release notes describe 0.6.2'
Assert-True ([string]$websitePackage.version -eq $expectedVersion) 'Website package version matches repository version'
Assert-True ([string]$websiteLock.version -eq $expectedVersion) 'Website lockfile version matches repository version'
Assert-True ([string]$websiteLock.packages.''.version -eq $expectedVersion) 'Website root lock package version matches repository version'
foreach ($token in @('21','upstream-lock.json','patch-report.json','offline','nexroute-update.cmd','update-state.json','gh attestation verify','nexroute-validation.cmd','NexRoute 0.6.2 Hot Fix')) {
    Assert-True ($readme -match [regex]::Escape($token)) "README documents $token"
}
foreach ($asset in @(
    'NexRoute-0.6.2-win-x64.zip','NexRoute-0.6.2-win-x64.zip.sha256',
    'NexRoute-0.6.2-validation.json','NexRoute-0.6.2-validation.md'
)) {
    Assert-True ($readme -match [regex]::Escape($asset)) "README documents release asset $asset"
    Assert-True ($releaseNotes -match [regex]::Escape($asset)) "Release notes document release asset $asset"
}

$powerShellFiles=@(Get-ChildItem -LiteralPath $root -File -Recurse -Force -Include '*.ps1','*.psm1' | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' })
foreach ($file in $powerShellFiles) { Test-PowerShellFile -Path $file.FullName }

try {
    Import-Module (Join-Path $root 'scripts/NexRoute.Upstream.psm1') -Force
    $manifest=Read-NexRouteUpstreamManifest -Path (Join-Path $root '.service/upstream-manifest.json')
    Assert-True ($manifest.schemaVersion -eq 1) 'Upstream manifest uses schema version 1'
    Assert-True ($manifest.repository -eq 'Flowseal/zapret-discord-youtube') 'Upstream manifest pins the Flowseal repository'
    Assert-True ($manifest.tag -eq '1.10.0') 'Upstream manifest pins Flowseal 1.10.0'
    Assert-True ($manifest.requiredPaths.Count -ge 8) 'Upstream manifest declares required archive paths'
    Assert-True (($manifest.expectedSha256 -match '^[0-9a-f]{64}$') -or $bootstrapUnlocked) 'Upstream manifest contains a locked SHA-256'
} catch {
    Assert-True $false "Upstream manifest validates: $($_.Exception.Message)"
}

$servicesDocument=Read-Text 'overlay/.service/services.json' | ConvertFrom-Json
$services=@($servicesDocument.services)
Assert-True ($servicesDocument.schemaVersion -eq 2) 'Service Matrix uses schema version 2'
Assert-True ($services.Count -eq 15) 'Service Matrix contains 15 profiles'
Assert-True ((@($services.id | Sort-Object -Unique)).Count -eq $services.Count) 'Service ids are unique'
foreach ($service in $services) {
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$service.descriptionEn)) "Service $($service.id) has an English description"
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$service.descriptionRu)) "Service $($service.id) has a Russian description"
    Assert-True (@($service.testTargets).Count -ge 2) "Service $($service.id) has real critical endpoints"
    Assert-True (@($service.tcpPorts).Count -gt 0 -or @($service.udpPorts).Count -gt 0) "Service $($service.id) has transport coverage"
}

$build=(Read-Text 'scripts/Build-Release.ps1')+(Read-Text 'scripts/Build-Package.ps1')
foreach ($token in @('NEXROUTE_SERVICE_FILTERS_V4','NEXROUTE_DYNAMIC_TARGETS_V4','NEXROUTE_REFRESH_MATRIX_V4','upstream-lock.json','patch-report.json','Expected 23 tracked patch targets','UpstreamCachePath','UpstreamArchive','verified archive','UpdaterEntryIncluded')) {
    Assert-True ($build -match [regex]::Escape($token)) "Release builders contain $token"
}
$packageTest=Read-Text 'scripts/Test-Package.ps1'
foreach ($token in @('utils/test zapret.ps1','UTF-8 with BOM','powershell.exe','Strategy Lab does not parse in Windows PowerShell 5.1')) {
    Assert-True ($packageTest -match [regex]::Escape($token)) "Package validation contains $token"
}

$mainLauncher=Read-Text 'overlay/nexroute.bat'
$serviceLauncher=Read-Text 'overlay/service.bat'
$updateLauncher=Read-Text 'overlay/nexroute-update.cmd'
foreach ($launcher in @($mainLauncher,$serviceLauncher,$updateLauncher)) {
    Assert-True ($launcher -match 'for %%I in \("%~dp0\."\) do set "NEXROUTE_ROOT=%%~fI"') 'Launcher canonicalizes the package root without a trailing slash'
    Assert-True ($launcher -notmatch 'set "NEXROUTE_ROOT=%~dp0"') 'Launcher rejects raw trailing-slash root quoting'
    Assert-True ($launcher -match 'endlocal & exit /b %NEXROUTE_EXIT_CODE%') 'Launcher preserves the real child exit code'
}
Assert-True ($mainLauncher -match 'nexroute-updater-entry\.ps1') 'Main launcher uses the updater entry wrapper'
Assert-True ($mainLauncher -match '-Mode Auto') 'Main launcher performs automatic update checks'
Assert-True ($updateLauncher -match '"--status"') 'Manual updater launcher exposes deterministic status mode'

$hotfix=Read-Text 'overlay/.service/next/nexroute-hotfix-062.ps1'
$runtimeLoader=Read-Text 'overlay/.service/next/nexroute-runtime-extensions.ps1'
$updaterEntry=Read-Text 'overlay/.service/nexroute-updater-entry.ps1'
$diagnosticFixes=Read-Text 'overlay/.service/next/nexroute-diagnostics-fixes.ps1'
$launcherSmoke=Read-Text 'scripts/Test-WindowsLaunchers.ps1'
Assert-True ($runtimeLoader.IndexOf("'nexroute-hotfix-062.ps1'",[StringComparison]::Ordinal) -gt $runtimeLoader.IndexOf("'nexroute-diagnostics-fixes.ps1'",[StringComparison]::Ordinal)) '0.6.2 hotfix loads after diagnostic fixes'
foreach ($token in @("['administrator']","['runtime']","['network']",'detected','[Console]::Title = "NexRoute $version"')) {
    Assert-True ($hotfix -match [regex]::Escape($token)) "First-run compatibility layer contains $token"
}
Assert-True ($diagnosticFixes -match [regex]::Escape("Join-Path `$script:NrService 'nexroute-updater-entry.ps1'")) 'Interactive updater routes through the updater entry wrapper'
foreach ($token in @('NEXROUTE_LATEST_RELEASE_FIXTURE','Invoke-WebRequest','HttpWebRequest','curl.exe','New-NrFallbackReleaseMetadata','without the GitHub API')) {
    Assert-True ($updaterEntry -match [regex]::Escape($token)) "Updater entry contains $token"
}
Assert-True ($updaterEntry -notmatch 'api\.github\.com') 'Updater entry never uses api.github.com'
Assert-True ($updaterEntry -notmatch 'effectiveMetadata\s*=\s*\$null') 'Updater entry does not silently fall back to API metadata'
foreach ($token in @('NexRoute 0.6.2 Hot Fix Тест','diagnosticCompatibility','NEXROUTE_LATEST_RELEASE_FIXTURE','updaterFallbackVersion','service.bat','nexroute.bat','nexroute-update.cmd','PropertyNotFound')) {
    Assert-True ($launcherSmoke -match [regex]::Escape($token)) "Windows package smoke contains $token"
}

$validateWorkflow=Read-Text '.github/workflows/validate.yml'
$releaseWorkflow=Read-Text '.github/workflows/release.yml'
$pagesWorkflow=Read-Text '.github/workflows/pages.yml'
foreach ($token in @('Validate NexRoute 0.6.2 sources','Build and test NexRoute 0.6.2','NexRoute-0.6.2-smoke','Test-WindowsLaunchers.ps1','diagnosticCompatibility','updaterFallbackVersion','UpstreamArchive','offline','npm run typecheck','npm run build','actions/checkout@v6','actions/setup-node@v6','actions/upload-artifact@v7','NotificationToastChannel','NotificationFallbackChannel')) {
    Assert-True ($validateWorkflow -match [regex]::Escape($token)) "Validation workflow contains $token"
}
Assert-True ($validateWorkflow -notmatch 'NexRoute-0\.6\.[01]-smoke|Expected 0\.6\.[01]|Build and test NexRoute 0\.6\.[01]') 'Validation workflow contains no stale 0.6.0/0.6.1 package contract'
foreach ($token in @('id-token: write','attestations: write','artifact-metadata: write','actions/attest@v4','gh attestation verify','actions/checkout@v6','actions/upload-artifact@v7','NotificationToastChannel','NotificationFallbackChannel','gh release create')) {
    Assert-True ($releaseWorkflow -match [regex]::Escape($token)) "Release workflow contains $token"
}
foreach ($workflow in @($validateWorkflow,$releaseWorkflow,$pagesWorkflow)) {
    Assert-True ($workflow -notmatch 'actions/checkout@v4|actions/setup-node@v4|actions/upload-artifact@v4|actions/upload-pages-artifact@v4') 'Workflow contains no deprecated Node 20 action majors'
}
Assert-True ($pagesWorkflow -match 'actions/upload-pages-artifact@v5') 'Pages workflow uses upload-pages-artifact v5'

$attestationTests=Read-Text 'tests/ReleaseAttestation.Tests.ps1'
foreach ($token in @('actions/attest@v4','gh attestation verify','release archive and its checksum file','before publishing the GitHub Release')) {
    Assert-True ($attestationTests -match [regex]::Escape($token)) "Release attestation suite covers $token"
}

$websiteText=((Get-ChildItem -LiteralPath (Join-Path $root 'website') -File -Recurse -Force | Where-Object { $_.FullName -notmatch '[\\/](node_modules|\.next|\.vercel)[\\/]' -and $_.Extension -in @('.ts','.tsx','.css','.md','.json','.mjs') } | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue }) -join [Environment]::NewLine)
foreach ($token in @('Onmaynec/NexRoute','Service Matrix','Strategy Lab','gh attestation verify','prefers-reduced-motion','NEXT_PUBLIC_SITE_URL','getLatestStableRelease','SoftwareApplication','FAQAccordion','ServiceMatrixDemo','StrategyLabDemo','AnimatedRouteGraph')) {
    Assert-True ($websiteText -match [regex]::Escape($token)) "Website source contains $token"
}
Assert-True ($websiteText -notmatch '(?i)lorem ipsum|add implementation here|миллион пользователей|лучший в мире|100% результат|полная анонимность') 'Website contains no placeholders or unsupported marketing claims'

$forbiddenExtensions=@('.exe','.dll','.sys','.bin','.zip','.rar','.7z','.ico','.lnk')
$forbidden=@(Get-ChildItem -LiteralPath $root -File -Recurse -Force | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' -and $forbiddenExtensions -contains $_.Extension.ToLowerInvariant() })
Assert-True ($forbidden.Count -eq 0) 'Git source tree contains no generated executables, drivers, archives, ICOs or shortcuts'

if ($errors.Count -gt 0) {
    Write-Host "`nValidation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}
Write-Host "`nAll NexRoute $expectedVersion repository checks passed." -ForegroundColor Green
