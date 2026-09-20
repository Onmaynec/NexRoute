[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$errors=New-Object 'System.Collections.Generic.List[string]'
$expectedVersion='0.6.5'

function Assert-True {
    param([bool]$Condition,[string]$Message)
    if ($Condition) { Write-Host "[ OK ] $Message" -ForegroundColor Green }
    else { $script:errors.Add($Message); Write-Host "[FAIL] $Message" -ForegroundColor Red }
}
function Read-Text {
    param([string]$RelativePath)
    Get-Content -LiteralPath (Join-Path $root $RelativePath) -Raw -Encoding UTF8
}

Write-Host "NexRoute $expectedVersion repository validation" -ForegroundColor Cyan
Write-Host '====================================' -ForegroundColor Cyan

$required=@(
    'README.md','CHANGELOG.md','LICENSE','THIRD_PARTY_NOTICES.md','.service/version.txt','.service/upstream-manifest.json',
    'overlay/service.bat','overlay/nexroute.bat','overlay/nexroute-update.cmd','overlay/nexroute-validation.cmd',
    'overlay/.service/nexroute-console.ps1','overlay/.service/nexroute-updater.ps1','overlay/.service/nexroute-updater-entry.ps1',
    'overlay/.service/nexroute-services.ps1','overlay/.service/nexroute-services-entry.ps1','overlay/.service/services.json',
    'overlay/.service/next/nexroute-common.ps1','overlay/.service/next/nexroute-diagnostics.ps1',
    'overlay/.service/next/nexroute-diagnostics-fixes.ps1','overlay/.service/next/nexroute-runtime-extensions.ps1',
    'overlay/.service/next/nexroute-hotfix-062.ps1','overlay/.service/next/nexroute-strategy-ranking.ps1','overlay/.service/next/nexroute-strategy-lab-classic.ps1','overlay/.service/next/nexroute-update.ps1',
    'overlay/.service/next/nexroute-notifications.ps1','overlay/.service/next/nexroute-attestation-v2.ps1',
    'overlay/.service/next/nexroute-strategy-refresh.ps1','overlay/.service/next/nexroute-strategy-refresh-build.ps1',
    'native/NexRoute.Tray/Program.cs','native/NexRoute.Notifier/Program.cs','native/NexRoute.Dashboard/Program.cs','native/NexRoute.Validation/Program.cs',
    'scripts/Build-Package.ps1','scripts/Build-Release.ps1','scripts/New-ValidationReport.ps1','scripts/NexRoute.Upstream.psm1',
    'scripts/Test-Package.ps1','scripts/Test-Release.ps1','scripts/Test-V06Desktop.ps1','scripts/Test-WindowsLaunchers.ps1',
    'scripts/Test-StrategyLab063Evidence.ps1','scripts/New-StrategyLabFieldEvidence.ps1','scripts/Test-StrategyLabFieldEvidence.ps1',
    'scripts/Test-GitHubActionsPinning.ps1','scripts/Test-Updater063MigrationEvidence.ps1',
    'tests/ServiceMatrix.Tests.ps1','tests/UpstreamContract.Tests.ps1','tests/Updater.Tests.ps1','tests/UpdaterMigration.Tests.ps1',
    'tests/ReleaseAttestation.Tests.ps1','tests/ReleaseCoherence.Tests.ps1','tests/LauncherHotfix.Tests.ps1','tests/Hotfix062.Tests.ps1',
    'tests/StrategyRefresh063.Tests.ps1','tests/StrategyLab063Evidence.Tests.ps1','tests/StrategyLabFieldEvidence064.Tests.ps1',
    'tests/StrategyRanking064.Tests.ps1','tests/StrategyLab065.Tests.ps1','tests/UpdaterHealthRollback064.Tests.ps1','tests/GitHubActionsPinning064.Tests.ps1',
    '.github/workflows/validate.yml','.github/workflows/release.yml','.github/workflows/pages.yml',
    '.github/release-notes/v0.6.0.md','.github/release-notes/v0.6.1.md','.github/release-notes/v0.6.2.md','.github/release-notes/v0.6.3.md','.github/release-notes/v0.6.4.md','.github/release-notes/v0.6.5.md',
    'docs/RELEASE_0.6.0_ACCEPTANCE.md','docs/RELEASE_0.6.3_ACCEPTANCE.md','docs/RELEASE_0.6.4_ACCEPTANCE.md','docs/RELEASE_0.6.5_ACCEPTANCE.md','docs/UPDATES.md','docs/ATTESTATIONS.md','docs/RELEASES.md','docs/FIELD_EVIDENCE.md','docs/STRATEGY_LAB_RANKING.md','docs/GITHUB_ACTIONS_PINNING.md',
    'website/package.json','website/package-lock.json','website/tsconfig.json','website/next.config.ts','website/postcss.config.mjs',
    'website/app/layout.tsx','website/app/page.tsx','website/app/download/page.tsx','website/app/docs/[slug]/page.tsx',
    'website/components/layout/site-header.tsx','website/components/product/demos.tsx','website/content/docs.ts','website/lib/github.ts'
)
foreach ($relative in $required) { Assert-True (Test-Path -LiteralPath (Join-Path $root $relative) -PathType Leaf) "Required file exists: $relative" }

$version=(Read-Text '.service/version.txt').Trim()
$releaseNotes=Read-Text '.github/release-notes/v0.6.5.md'
$acceptance=Read-Text 'docs/RELEASE_0.6.5_ACCEPTANCE.md'
$websitePackage=Read-Text 'website/package.json' | ConvertFrom-Json
$websiteLock=Read-Text 'website/package-lock.json' | ConvertFrom-Json -AsHashtable
Assert-True ($version -eq $expectedVersion) "Repository version is $expectedVersion"
Assert-True ([string]$websitePackage.version -eq $expectedVersion) 'Website package version matches repository version'
Assert-True ([string]$websiteLock['version'] -eq $expectedVersion) 'Website lockfile version matches repository version'
Assert-True ([string]$websiteLock['packages']['']['version'] -eq $expectedVersion) 'Website root lock package version matches repository version'
Assert-True ($releaseNotes -match [regex]::Escape('# NexRoute 0.6.5 — возвращение классического интерфейса и новый Strategy Lab')) 'Release notes describe 0.6.5'
Assert-True ($acceptance -match [regex]::Escape('NexRoute 0.6.5 — критерии готовности релиза')) '0.6.5 acceptance document exists'
foreach ($asset in @('NexRoute-0.6.5-win-x64.zip','NexRoute-0.6.5-win-x64.zip.sha256','NexRoute-0.6.5-validation.json','NexRoute-0.6.5-validation.md')) {
    Assert-True ($releaseNotes -match [regex]::Escape($asset)) "Release notes document $asset"
}

$powerShellFiles=@(Get-ChildItem -LiteralPath $root -File -Recurse -Force -Include '*.ps1','*.psm1' | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' })
foreach ($file in $powerShellFiles) {
    $tokens=$null; $parseErrors=$null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$parseErrors)
    $relative=$file.FullName.Substring($root.Length).TrimStart([char[]]'\/')
    Assert-True (@($parseErrors).Count -eq 0) "$relative parses without PowerShell syntax errors"
    foreach ($parseError in @($parseErrors)) { Write-Host ("       {0}:{1} {2}" -f $parseError.Extent.StartLineNumber,$parseError.Extent.StartColumnNumber,$parseError.Message) -ForegroundColor Yellow }
}

try {
    Import-Module (Join-Path $root 'scripts/NexRoute.Upstream.psm1') -Force
    $manifest=Read-NexRouteUpstreamManifest -Path (Join-Path $root '.service/upstream-manifest.json')
    Assert-True ($manifest.schemaVersion -eq 1) 'Upstream manifest uses schema version 1'
    Assert-True ($manifest.repository -eq 'Flowseal/zapret-discord-youtube') 'Upstream manifest pins Flowseal'
    Assert-True ($manifest.tag -eq '1.10.3') 'Upstream manifest pins Flowseal 1.10.3'
    Assert-True ($manifest.expectedSha256 -match '^[0-9a-f]{64}$') 'Upstream manifest contains a locked SHA-256'
} catch { Assert-True $false "Upstream manifest validates: $($_.Exception.Message)" }

$services=Read-Text 'overlay/.service/services.json' | ConvertFrom-Json
Assert-True ($services.schemaVersion -eq 2) 'Service Matrix uses schema version 2'
Assert-True (@($services.services).Count -eq 15) 'Service Matrix contains 15 profiles'
Assert-True ((@($services.services.id | Sort-Object -Unique)).Count -eq 15) 'Service ids are unique'

$mainLauncher=Read-Text 'overlay/nexroute.bat'
$serviceLauncher=Read-Text 'overlay/service.bat'
$updateLauncher=Read-Text 'overlay/nexroute-update.cmd'
foreach ($launcher in @($mainLauncher,$serviceLauncher,$updateLauncher)) {
    Assert-True ($launcher -match 'for %%I in \("%~dp0\."\) do set "NEXROUTE_ROOT=%%~fI"') 'Launcher canonicalizes the package root'
    Assert-True ($launcher -notmatch 'set "NEXROUTE_ROOT=%~dp0"') 'Launcher rejects raw trailing-slash quoting'
    Assert-True ($launcher -match 'endlocal & exit /b %NEXROUTE_EXIT_CODE%') 'Launcher preserves child exit code'
}
Assert-True ($mainLauncher -match 'nexroute-updater-entry\.ps1') 'Main launcher uses updater entry'
Assert-True ($updateLauncher -match '"--status"') 'Manual updater exposes status smoke mode'

$updaterEntry=Read-Text 'overlay/.service/nexroute-updater-entry.ps1'
foreach ($token in @('NEXROUTE_LATEST_RELEASE_FIXTURE','Invoke-WebRequest','HttpWebRequest','curl.exe','New-NrFallbackReleaseMetadata','without the GitHub API')) {
    Assert-True ($updaterEntry -match [regex]::Escape($token)) "Updater entry contains $token"
}
Assert-True ($updaterEntry -notmatch 'api\.github\.com') 'Updater entry never uses api.github.com'

$refresh=Read-Text 'overlay/.service/next/nexroute-strategy-refresh.ps1'
$refreshBuild=Read-Text 'overlay/.service/next/nexroute-strategy-refresh-build.ps1'
$serviceEntry=Read-Text 'overlay/.service/nexroute-services-entry.ps1'
$evidence=Read-Text 'scripts/Test-StrategyLab063Evidence.ps1'
$fieldEvidence=Read-Text 'scripts/New-StrategyLabFieldEvidence.ps1'
$fieldEvidenceValidator=Read-Text 'scripts/Test-StrategyLabFieldEvidence.ps1'
$ranking064=Read-Text 'overlay/.service/next/nexroute-strategy-ranking.ps1'
$console064=Read-Text 'overlay/.service/nexroute-console.ps1'
$updater064=Read-Text 'overlay/.service/nexroute-updater.ps1'
$migration064=Read-Text 'scripts/Test-Updater063MigrationEvidence.ps1'
$dashboard064=Read-Text 'native/NexRoute.Dashboard/Program.cs'
foreach ($token in @('Get-NexRoute063StrategyCatalog','nr063-01','nr063-21','multisplit','multidisorder','fakedsplit','hostfakesplit','syndata')) {
    Assert-True ($refresh -match [regex]::Escape($token)) "0.6.3 refresh contains $token"
}
foreach ($token in @('strategy-refresh-report.json','list-nexroute-discord-critical.txt','list-nexroute-youtube-critical.txt','StrategyCount')) {
    Assert-True ($refreshBuild -match [regex]::Escape($token)) "0.6.3 build refresh contains $token"
}
Assert-True ($serviceEntry -match 'Invoke-NexRoute063StrategyRefreshBuild') '0.6.3 refresh is integrated into release build entry'
foreach ($target in @('DiscordGateway','DiscordCDN','DiscordUpdates','YouTubeWeb','YouTubeShort','YouTubeImage','YouTubeVideoRedirect','GoogleMain','CloudflareWeb')) {
    Assert-True ($evidence -match [regex]::Escape($target)) "0.6.3 evidence validator covers $target"
    Assert-True ($fieldEvidence -match [regex]::Escape($target)) "0.6.4 privacy-safe evidence covers $target"
}
foreach ($token in @('canonicalPayloadSha256','sourceLogSha256','candidateSha256','PrivacyReview','trustModel')) {
    Assert-True ($fieldEvidence -match [regex]::Escape($token)) "0.6.4 field-evidence generator contains $token"
    Assert-True ($fieldEvidenceValidator -match [regex]::Escape($token)) "0.6.4 field-evidence validator contains $token"
}
Assert-True ($fieldEvidence -notmatch 'verifiedUtc|provider\s*=|location\s*=') '0.6.4 field-evidence receipt has no nondeterministic time/provider/location fields'

foreach ($token in @('criticalAvailabilityPercent','stabilityPercent','minimumObservationCount','inconclusiveReason','recommendationReason','missingMetricPolicy','tieBreak')) {
    Assert-True ($ranking064 -match [regex]::Escape($token)) "0.6.4 Strategy Lab ranking contains $token"
}
Assert-True ($console064 -match [regex]::Escape('nexroute-strategy-ranking.ps1')) 'Console loads the 0.6.4 Strategy Lab ranking override'
foreach ($token in @('Test-NexRoutePostUpdateHealth','NEXROUTE_UPDATE_FORCE_HEALTH_FAILURE','post-update health check')) {
    Assert-True ($updater064 -match [regex]::Escape($token)) "Updater health transaction contains $token"
}
foreach ($token in @('v0.6.2','v0.6.3','pathHasSpaces','pathHasNonAscii','absolutePathPublished')) {
    Assert-True ($migration064 -match [regex]::Escape($token)) "Real migration evidence gate contains $token"
}
foreach ($token in @('RankingState','RecommendationReason','InconclusiveReason','CriticalAvailabilityPercent','StabilityPercent')) {
    Assert-True ($dashboard064 -match [regex]::Escape($token)) "Dashboard exposes ranking field $token"
}

$classic065=Read-Text 'overlay/.service/next/nexroute-strategy-lab-classic.ps1'
$common065=Read-Text 'overlay/.service/next/nexroute-common.ps1'
$loader065=Read-Text 'overlay/.service/next/nexroute-runtime-extensions.ps1'
foreach ($token in @('███╗░░██╗███████╗',"accent = 'Red'",'Read-Host',"'[00]'")) {
    Assert-True ($common065 -match [regex]::Escape($token)) "0.6.5 classic interface contains $token"
}
foreach ($token in @('Test-NrLabDns065','Test-NrLabDpiFreeze065','Show-NrLabPreflight065','Invoke-NrStrategyProbe065','schemaVersion=4')) {
    Assert-True ($classic065 -match [regex]::Escape($token)) "0.6.5 Strategy Lab contains $token"
}
Assert-True ($loader065.IndexOf('nexroute-strategy-lab-classic.ps1') -gt $loader065.IndexOf('nexroute-strategy-lab-v2.ps1')) '0.6.5 Strategy Lab override loads after v2'

$build=(Read-Text 'scripts/Build-Release.ps1')+(Read-Text 'scripts/Build-Package.ps1')
foreach ($token in @('upstream-lock.json','patch-report.json','Expected 24 tracked patch targets','UpstreamCachePath','UpstreamArchive','UpdaterEntryIncluded')) {
    Assert-True ($build -match [regex]::Escape($token)) "Build contract contains $token"
}

$validate=Read-Text '.github/workflows/validate.yml'
$release=Read-Text '.github/workflows/release.yml'
$pages=Read-Text '.github/workflows/pages.yml'
foreach ($token in @('NexRoute 0.6.5','Test-WindowsLaunchers.ps1','diagnosticCompatibility','updaterFallbackVersion','UpstreamArchive','npm run typecheck','npm run build','actions/checkout v6.1.0','actions/setup-node v6.5.0','actions/upload-artifact v7.0.1')) {
    Assert-True ($validate -match [regex]::Escape($token)) "Validation workflow contains $token"
}
foreach ($token in @('id-token: write','attestations: write','artifact-metadata: write','actions/attest v4.2.2','gh attestation verify','actions/checkout v6.1.0','actions/upload-artifact v7.0.1','gh release create')) {
    Assert-True ($release -match [regex]::Escape($token)) "Release workflow contains $token"
}
foreach ($token in @('actions/configure-pages v5.0.0','actions/upload-pages-artifact v5.0.0','actions/deploy-pages v4.0.5')) {
    Assert-True ($pages -match [regex]::Escape($token)) "Pages workflow contains $token"
}
try {
    $pinResult=& (Join-Path $root 'scripts/Test-GitHubActionsPinning.ps1') -Root $root
    Assert-True ($pinResult.status -eq 'passed') 'Every external GitHub Action is allowlisted and pinned to the reviewed full commit SHA'
} catch { Assert-True $false "GitHub Actions pinning contract validates: $($_.Exception.Message)" }

$websiteText=((Get-ChildItem -LiteralPath (Join-Path $root 'website') -File -Recurse -Force | Where-Object { $_.FullName -notmatch '[\\/](node_modules|\.next|\.vercel)[\\/]' -and $_.Extension -in @('.ts','.tsx','.css','.md','.json','.mjs') } | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue }) -join [Environment]::NewLine)
foreach ($token in @('Onmaynec/NexRoute','Service Matrix','Strategy Lab','gh attestation verify','prefers-reduced-motion','NEXT_PUBLIC_SITE_URL','getLatestStableRelease','SoftwareApplication')) {
    Assert-True ($websiteText -match [regex]::Escape($token)) "Website contains $token"
}
Assert-True ($websiteText -notmatch '(?i)lorem ipsum|add implementation here|миллион пользователей|лучший в мире|100% результат|полная анонимность') 'Website has no placeholders or unsupported claims'

$forbidden=@(Get-ChildItem -LiteralPath $root -File -Recurse -Force | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' -and $_.Extension.ToLowerInvariant() -in @('.exe','.dll','.sys','.bin','.zip','.rar','.7z','.ico','.lnk') })
Assert-True ($forbidden.Count -eq 0) 'Git source tree contains no generated binaries or archives'

if ($errors.Count -gt 0) { Write-Host "`nValidation failed with $($errors.Count) error(s)." -ForegroundColor Red; exit 1 }
Write-Host "`nAll NexRoute $expectedVersion repository checks passed." -ForegroundColor Green
