[CmdletBinding()]
param(
    [string]$ArtifactsDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts'),
    [string]$ExtractDirectory,
    [switch]$SkipRuntime
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$expectedVersion = (Get-Content -LiteralPath (Join-Path $repositoryRoot '.service/version.txt') -Raw).Trim()
$sourceManifest = Get-Content -LiteralPath (Join-Path $repositoryRoot '.service/upstream-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$baseTest = Join-Path $PSScriptRoot 'Test-Package.ps1'
$result = @(& $baseTest -ArtifactsDirectory $ArtifactsDirectory -ExtractDirectory $ExtractDirectory -SkipRuntime:$SkipRuntime) | Select-Object -Last 1
$root = $result.ExtractPath

$required = @(
    '.service/nexroute-services-core.ps1',
    '.service/services-runtime.cmd',
    '.service/ip-source-status.json',
    '.service/upstream-manifest.json',
    '.service/upstream-lock.json',
    '.service/patch-report.json',
    '.service/nexroute-updater.ps1',
    '.service/i18n/nexroute-pages-update.ps1',
    'nexroute-update.cmd',
    '.service/i18n/nexroute-pages-core.ps1',
    '.service/i18n/nexroute-pages-network.ps1',
    '.service/i18n/nexroute-services-state.ps1',
    '.service/i18n/nexroute-services-network.ps1',
    '.service/i18n/nexroute-services-runtime.ps1',
    '.service/i18n/nexroute-services-diagnostics.ps1',
    '.service/native/NexRoute.Notifier.exe',
    '.service/next/nexroute-notifications.ps1'
)
foreach ($relativePath in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relativePath) -PathType Leaf)) {
        throw "NexRoute $expectedVersion package is missing $relativePath"
    }
}

$version = (Get-Content -LiteralPath (Join-Path $root '.service/version.txt') -Raw).Trim()
if ($version -ne $expectedVersion) { throw "Expected package version $expectedVersion, got $version" }

$language = (Get-Content -LiteralPath (Join-Path $root '.service/language.txt') -Raw -Encoding ASCII).Trim().ToUpperInvariant()
if ($language -ne 'EN') { throw "Default package language must be EN, got $language" }

$packageManifest = Get-Content -LiteralPath (Join-Path $root '.service/upstream-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$upstreamLock = Get-Content -LiteralPath (Join-Path $root '.service/upstream-lock.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if ([int]$packageManifest.schemaVersion -ne 1) { throw 'Package upstream manifest schema must be 1.' }
if ([int]$upstreamLock.schemaVersion -ne 1) { throw 'Package upstream lock schema must be 1.' }
if ($upstreamLock.repository -ne $sourceManifest.repository) { throw 'Upstream lock repository differs from the source manifest.' }
if ($upstreamLock.tag -ne $sourceManifest.tag) { throw 'Upstream lock tag differs from the source manifest.' }
if ([string]$upstreamLock.assetName -notmatch [string]$sourceManifest.assetPattern) { throw 'Upstream lock asset does not match the declared pattern.' }
if ([string]$upstreamLock.sha256 -notmatch '^[0-9a-f]{64}$') { throw 'Upstream lock does not contain a valid SHA-256.' }
if ([long]$upstreamLock.assetSize -lt [long]$sourceManifest.minimumBytes) { throw 'Upstream lock asset size is below the manifest minimum.' }
if ([int]$upstreamLock.strategyCount -ne 21) { throw "Expected upstream lock to report 21 strategies, got $($upstreamLock.strategyCount)." }
if ($sourceManifest.expectedSha256 -and $upstreamLock.sha256 -ne ([string]$sourceManifest.expectedSha256).ToLowerInvariant()) {
    throw 'Upstream lock SHA-256 differs from the committed source lock.'
}

$patchReport = Get-Content -LiteralPath (Join-Path $root '.service/patch-report.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$patches = @($patchReport.patches)
if ([int]$patchReport.schemaVersion -ne 1) { throw 'Patch report schema must be 1.' }
if ($patchReport.nexRouteVersion -ne $expectedVersion) { throw 'Patch report contains the wrong NexRoute version.' }
if ($patchReport.upstreamSha256 -ne $upstreamLock.sha256) { throw 'Patch report and upstream lock use different archive hashes.' }
if ([int]$patchReport.summary.targetCount -ne 23 -or $patches.Count -ne 23) {
    throw "Expected 23 tracked patch targets, got $($patches.Count)."
}
if ([int]$patchReport.summary.strategyTargets -ne 21) { throw 'Patch report does not declare 21 strategy targets.' }
if ([int]$patchReport.summary.infrastructureTargets -ne 2) { throw 'Patch report does not declare two infrastructure targets.' }
if (($patches.id | Sort-Object -Unique).Count -ne $patches.Count) { throw 'Patch report contains duplicate IDs.' }
if (@($patches | Where-Object { $_.id -like 'strategy.*' }).Count -ne 21) { throw 'Patch report does not contain 21 strategy records.' }
foreach ($patch in $patches) {
    if ([string]::IsNullOrWhiteSpace([string]$patch.id)) { throw 'Patch report contains an empty ID.' }
    if ([string]::IsNullOrWhiteSpace([string]$patch.target)) { throw "Patch '$($patch.id)' has no target." }
    if ([int]$patch.operations -lt 1) { throw "Patch '$($patch.id)' reports no operations." }
    if ([string]$patch.beforeSha256 -notmatch '^[0-9a-f]{64}$') { throw "Patch '$($patch.id)' has an invalid before hash." }
    if ([string]$patch.afterSha256 -notmatch '^[0-9a-f]{64}$') { throw "Patch '$($patch.id)' has an invalid after hash." }
    if ($patch.beforeSha256 -eq $patch.afterSha256) { throw "Patch '$($patch.id)' did not change its target." }
}

$legacyServiceBat = Get-Content -LiteralPath (Join-Path $root '.service/legacy-service.bat') -Raw
foreach ($token in @('NEXROUTE_REFRESH_MATRIX_V4',':nexroute_game_filter',':nexroute_update_watch','-Mode GameFilter','-Mode UpdateWatch','NEXROUTE_EXPAND_RUNTIME_ARGS')) {
    if ($legacyServiceBat -notmatch [regex]::Escape($token)) { throw "legacy-service.bat is missing release token: $token" }
}

$arrowLauncher = Get-Content -LiteralPath (Join-Path $root 'service.bat') -Raw
foreach ($token in @('nexroute-console.ps1','-Root','%~dp0')) {
    if ($arrowLauncher -notmatch [regex]::Escape($token)) { throw "service.bat is missing arrow launcher token: $token" }
}

$launcher = Get-Content -LiteralPath (Join-Path $root 'nexroute.bat') -Raw
foreach ($token in @('nexroute-updater.ps1','check_updates.enabled','-Mode Auto')) {
    if ($launcher -notmatch [regex]::Escape($token)) { throw "nexroute.bat is missing updater token: $token" }
}
$updater = Get-Content -LiteralPath (Join-Path $root '.service/nexroute-updater.ps1') -Raw
foreach ($token in @('releases/latest','NexRoute-backups','SHA-256 mismatch','rolled-back')) {
    if ($updater -notmatch [regex]::Escape($token)) { throw "Updater is missing package token: $token" }
}
$updatePage = Get-Content -LiteralPath (Join-Path $root '.service/i18n/nexroute-pages-update.ps1') -Raw
if ($updatePage -notmatch '-Mode Menu') { throw 'Update Center UI is not connected to the updater menu.' }

$runtimeExtensions = Get-Content -LiteralPath (Join-Path $root '.service/next/nexroute-runtime-extensions.ps1') -Raw
if ($runtimeExtensions -notmatch [regex]::Escape('nexroute-notifications.ps1')) { throw 'Runtime loader does not load the notification broker.' }
$notificationBroker = Get-Content -LiteralPath (Join-Path $root '.service/next/nexroute-notifications.ps1') -Raw
foreach ($token in @('NexRoute.Notifier.exe','ConvertTo-NrNotificationBase64','Write-NrNotificationHistory','native-balloon','powershell-fallback')) {
    if ($notificationBroker -notmatch [regex]::Escape($token)) { throw "Notification broker is missing package token: $token" }
}
$nativeNotifierPath = Join-Path $root '.service/native/NexRoute.Notifier.exe'
$nativeNotifierFile = Get-Item -LiteralPath $nativeNotifierPath
if ($nativeNotifierFile.Length -lt 4096) { throw "Native notifier executable is unexpectedly small: $($nativeNotifierFile.Length) bytes." }
$nativeNotifierAssembly = [Reflection.AssemblyName]::GetAssemblyName($nativeNotifierPath)
if ([string]$nativeNotifierAssembly.Name -ne 'NexRoute.Notifier') { throw "Unexpected native notifier assembly name: $($nativeNotifierAssembly.Name)" }
$nativeNotifierSelfTest = Start-Process -FilePath $nativeNotifierPath -ArgumentList @('--self-test') -WorkingDirectory $root -WindowStyle Hidden -Wait -PassThru
if ($nativeNotifierSelfTest.ExitCode -ne 0) { throw "Native notifier self-test failed with exit code $($nativeNotifierSelfTest.ExitCode)." }

$strategyFiles = @(Get-ChildItem -LiteralPath $root -Filter '*.bat' -File | Where-Object { $_.Name -notin @('service.bat','nexroute.bat') })
if ($strategyFiles.Count -ne 21) { throw "Expected 21 patched real strategies, got $($strategyFiles.Count)" }
foreach ($strategy in $strategyFiles) {
    $content = Get-Content -LiteralPath $strategy.FullName -Raw
    foreach ($token in @('NEXROUTE_SERVICE_FILTERS_V4','services-runtime.cmd','%NEXROUTE_SERVICE_TCP_ARGS%','%NEXROUTE_SERVICE_UDP_ARGS%')) {
        if ($content -notmatch [regex]::Escape($token)) { throw "$($strategy.Name) is missing $token" }
    }
}

$runtime = Get-Content -LiteralPath (Join-Path $root '.service/services-runtime.cmd') -Raw -Encoding ASCII
foreach ($token in @('NEXROUTE_SERVICE_TCP_ARGS','NEXROUTE_SERVICE_UDP_ARGS','list-service-youtube.txt','list-service-discord.txt','ipset-service-youtube.txt','--hostlist=','--ipset=')) {
    if ($runtime -notmatch [regex]::Escape($token)) { throw "Service runtime is missing $token" }
}
if ($runtime -match 'list-service-chatgpt\.txt') { throw 'Disabled ChatGPT service leaked into the default runtime.' }

$general = Get-Content -LiteralPath (Join-Path $root 'lists/list-general-user.txt') -Raw -Encoding UTF8
$exclude = Get-Content -LiteralPath (Join-Path $root 'lists/list-exclude-user.txt') -Raw -Encoding UTF8
if ($general -notmatch '(?m)^youtube\.com\r?$') { throw 'Enabled YouTube domain is absent from the managed general block.' }
if ($exclude -match '(?m)^youtube\.com\r?$') { throw 'Enabled YouTube domain leaked into the disabled block.' }

$testLab = Get-Content -LiteralPath (Join-Path $root 'utils/test zapret.ps1') -Raw
if ($testLab -notmatch 'NEXROUTE_DYNAMIC_TARGETS_V4') { throw 'Strategy Lab does not load enabled Service Matrix targets.' }
if ($testLab -notmatch '-Mode TestTargets') { throw 'Strategy Lab is not connected to real Service Matrix endpoints.' }
if ($testLab -notmatch '\$_.Name -ne "nexroute\.bat"') { throw 'Strategy Lab still counts nexroute.bat as a strategy.' }

$iconPath = Join-Path $root '.service/nexroute.ico'
$iconSize = (Get-Item -LiteralPath $iconPath).Length
if ($iconSize -lt 20KB) { throw "Generated multi-resolution icon is unexpectedly small: $iconSize bytes" }

$servicesDocument = Get-Content -LiteralPath (Join-Path $root '.service/services.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$services = @($servicesDocument.services)
if ($servicesDocument.schemaVersion -ne 2) { throw 'Service Matrix schema must remain version 2.' }
if ($services.Count -ne 15) { throw "Expected 15 services, got $($services.Count)." }
foreach ($service in $services) {
    if (@($service.testTargets).Count -lt 2) { throw "Service '$($service.id)' has insufficient test targets." }
    if (@($service.tcpPorts).Count -eq 0 -and @($service.udpPorts).Count -eq 0) { throw "Service '$($service.id)' has no TCP/UDP coverage." }
}

$controller = Join-Path $root '.service/nexroute-services.ps1'
$diagnosticsPath = Join-Path $root 'NexRoute-Diagnostics-CI.json'
& $controller -Mode Diagnostics -Root $root -DiagnosticsPath $diagnosticsPath | Out-Null
if (-not (Test-Path -LiteralPath $diagnosticsPath -PathType Leaf)) { throw 'Diagnostics report was not created.' }
$diagnostics = Get-Content -LiteralPath $diagnosticsPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($diagnostics.nexRouteVersion -ne $expectedVersion) { throw 'Diagnostics report contains the wrong version.' }
if (-not $diagnostics.privacy) { throw 'Diagnostics report does not declare its privacy boundary.' }

if (-not $SkipRuntime) {
    $uiPath = Join-Path $root '.service/nexroute-ui.ps1'
    $languagePath = Join-Path $root '.service/language.txt'
    Set-Content -LiteralPath $languagePath -Value 'EN' -Encoding ASCII
    foreach ($mode in @('GameFilter','UpdateWatch')) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $uiPath -Mode $mode -LanguageFile $languagePath -NonInteractive
        if ($LASTEXITCODE -ne 0) { throw "$mode renderer failed in non-interactive mode." }
    }
}

Write-Host "NexRoute $expectedVersion extended package checks passed." -ForegroundColor Green
Write-Host "Upstream SHA-256: $($upstreamLock.sha256)" -ForegroundColor Green
Write-Host "Tracked patch targets: $($patches.Count)" -ForegroundColor Green
Write-Host "Patched real strategies: $($strategyFiles.Count)" -ForegroundColor Green
Write-Host "Native notifier: self-test passed, assembly $($nativeNotifierAssembly.Name), $($nativeNotifierFile.Length) bytes" -ForegroundColor Green
Write-Host "Generated icon bytes: $iconSize" -ForegroundColor Green

[pscustomobject]@{
    Archive = $result.Archive
    Checksum = $result.Checksum
    ExtractPath = $root
    Sha256 = $result.Sha256
    UpstreamSha256 = [string]$upstreamLock.sha256
    PatchTargetCount = $patches.Count
    PatchOperationCount = [int]$patchReport.summary.operationCount
    StrategyCount = $strategyFiles.Count
    ServiceCount = $services.Count
    IconBytes = $iconSize
    ControlNodeExitCode = [int]$result.ControlNodeExitCode
    NativeTrayExitCode = [int]$result.NativeTrayExitCode
    NativeTraySha256 = [string]$result.NativeTraySha256
    NativeNotifierExitCode = [int]$nativeNotifierSelfTest.ExitCode
    NativeNotifierSha256 = (Get-FileHash -LiteralPath $nativeNotifierPath -Algorithm SHA256).Hash.ToLowerInvariant()
}
