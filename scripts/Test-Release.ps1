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
$baseTest = Join-Path $PSScriptRoot 'Test-Package.ps1'
$result = @(& $baseTest -ArtifactsDirectory $ArtifactsDirectory -ExtractDirectory $ExtractDirectory -SkipRuntime:$SkipRuntime) | Select-Object -Last 1
$root = $result.ExtractPath

$required = @(
    '.service/nexroute-services-core.ps1',
    '.service/services-runtime.cmd',
    '.service/ip-source-status.json',
    '.service/i18n/nexroute-pages-core.ps1',
    '.service/i18n/nexroute-pages-network.ps1',
    '.service/i18n/nexroute-services-state.ps1',
    '.service/i18n/nexroute-services-network.ps1',
    '.service/i18n/nexroute-services-runtime.ps1',
    '.service/i18n/nexroute-services-diagnostics.ps1'
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

$serviceBat = Get-Content -LiteralPath (Join-Path $root 'service.bat') -Raw
foreach ($token in @('NEXROUTE_REFRESH_MATRIX_V3',':nexroute_game_filter',':nexroute_update_watch','-Mode GameFilter','-Mode UpdateWatch','NEXROUTE_EXPAND_RUNTIME_ARGS')) {
    if ($serviceBat -notmatch [regex]::Escape($token)) { throw "service.bat is missing release token: $token" }
}

$strategyFiles = @(Get-ChildItem -LiteralPath $root -Filter '*.bat' -File | Where-Object { $_.Name -notin @('service.bat','nexroute.bat') })
if ($strategyFiles.Count -ne 21) { throw "Expected 21 patched real strategies, got $($strategyFiles.Count)" }
foreach ($strategy in $strategyFiles) {
    $content = Get-Content -LiteralPath $strategy.FullName -Raw
    foreach ($token in @('NEXROUTE_SERVICE_FILTERS_V3','services-runtime.cmd','%NEXROUTE_SERVICE_TCP_ARGS%','%NEXROUTE_SERVICE_UDP_ARGS%')) {
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
if ($general -notmatch '(?m)^youtube\.com$') { throw 'Enabled YouTube domain is absent from the managed general block.' }
if ($exclude -match '(?m)^youtube\.com$') { throw 'Enabled YouTube domain leaked into the disabled block.' }

$testLab = Get-Content -LiteralPath (Join-Path $root 'utils/test zapret.ps1') -Raw
if ($testLab -notmatch 'NEXROUTE_DYNAMIC_TARGETS_V3') { throw 'Strategy Lab does not load enabled Service Matrix targets.' }
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
Write-Host "Patched real strategies: $($strategyFiles.Count)" -ForegroundColor Green
Write-Host "Generated icon bytes: $iconSize" -ForegroundColor Green

[pscustomobject]@{
    Archive = $result.Archive
    Checksum = $result.Checksum
    ExtractPath = $root
    Sha256 = $result.Sha256
    StrategyCount = $strategyFiles.Count
    ServiceCount = $services.Count
    IconBytes = $iconSize
}
