[CmdletBinding()]
param(
    [string]$ArtifactsDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts'),
    [string]$ExtractDirectory,
    [switch]$SkipRuntime
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$baseTest = Join-Path $PSScriptRoot 'Test-Package.ps1'
$result = @(& $baseTest -ArtifactsDirectory $ArtifactsDirectory -ExtractDirectory $ExtractDirectory -SkipRuntime:$SkipRuntime) | Select-Object -Last 1
$root = $result.ExtractPath

$required = @(
    '.service/nexroute-services-core.ps1',
    '.service/services-runtime.cmd',
    '.service/i18n/nexroute-pages-core.ps1',
    '.service/i18n/nexroute-pages-network.ps1'
)
$required += 0..9 | ForEach-Object { 'assets/nexroute-icon-parts/{0:00}.b64' -f $_ }
foreach ($relativePath in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relativePath) -PathType Leaf)) {
        throw "NexRoute 0.2.2 package is missing $relativePath"
    }
}

$version = (Get-Content -LiteralPath (Join-Path $root '.service/version.txt') -Raw).Trim()
if ($version -ne '0.2.2') { throw "Expected package version 0.2.2, got $version" }

$language = (Get-Content -LiteralPath (Join-Path $root '.service/language.txt') -Raw -Encoding ASCII).Trim().ToUpperInvariant()
if ($language -ne 'EN') { throw "Default package language must be EN, got $language" }

$serviceBat = Get-Content -LiteralPath (Join-Path $root 'service.bat') -Raw
foreach ($token in @('NEXROUTE_REFRESH_MATRIX_V2',':nexroute_game_filter',':nexroute_update_watch','-Mode GameFilter','-Mode UpdateWatch','NEXROUTE_EXPAND_RUNTIME_ARGS')) {
    if ($serviceBat -notmatch [regex]::Escape($token)) { throw "service.bat is missing 0.2.2 token: $token" }
}

$strategyFiles = @(Get-ChildItem -LiteralPath $root -Filter '*.bat' -File | Where-Object { $_.Name -notin @('service.bat','nexroute.bat') })
if ($strategyFiles.Count -ne 22) { throw "Expected 22 patched strategies, got $($strategyFiles.Count)" }
foreach ($strategy in $strategyFiles) {
    $content = Get-Content -LiteralPath $strategy.FullName -Raw
    foreach ($token in @('NEXROUTE_SERVICE_FILTERS_V2','services-runtime.cmd','%NEXROUTE_SERVICE_TCP_ARGS%','%NEXROUTE_SERVICE_UDP_ARGS%')) {
        if ($content -notmatch [regex]::Escape($token)) { throw "$($strategy.Name) is missing $token" }
    }
}

$runtime = Get-Content -LiteralPath (Join-Path $root '.service/services-runtime.cmd') -Raw
foreach ($token in @('NEXROUTE_SERVICE_TCP_ARGS','NEXROUTE_SERVICE_UDP_ARGS','--hostlist=','--ipset=')) {
    if ($runtime -notmatch [regex]::Escape($token)) { throw "Service runtime is missing $token" }
}

$testLab = Get-Content -LiteralPath (Join-Path $root 'utils/test zapret.ps1') -Raw
if ($testLab -notmatch 'NEXROUTE_DYNAMIC_TARGETS_V2') { throw 'Strategy Lab does not load enabled Service Matrix targets.' }
if ($testLab -notmatch '-Mode TestTargets') { throw 'Strategy Lab is not connected to real Service Matrix endpoints.' }

$iconPath = Join-Path $root '.service/nexroute.ico'
$iconSize = (Get-Item -LiteralPath $iconPath).Length
if ($iconSize -lt 20KB) { throw "Generated multi-resolution icon is unexpectedly small: $iconSize bytes" }

$iconParts = @(Get-ChildItem -LiteralPath (Join-Path $root 'assets/nexroute-icon-parts') -Filter '*.b64' -File | Sort-Object Name)
$iconBase64 = ($iconParts | ForEach-Object { (Get-Content -LiteralPath $_.FullName -Raw -Encoding ASCII).Trim() }) -join ''
$iconSourceBytes = [Convert]::FromBase64String($iconBase64)
if ($iconSourceBytes.Length -lt 5KB) { throw 'Decoded icon source is unexpectedly small.' }

$services = @((Get-Content -LiteralPath (Join-Path $root '.service/services.json') -Raw -Encoding UTF8 | ConvertFrom-Json).services)
foreach ($service in $services) {
    if (@($service.testTargets).Count -lt 2) { throw "Service '$($service.id)' has insufficient test targets." }
    if (@($service.tcpPorts).Count -eq 0 -and @($service.udpPorts).Count -eq 0) { throw "Service '$($service.id)' has no TCP/UDP coverage." }
}

if (-not $SkipRuntime) {
    $uiPath = Join-Path $root '.service/nexroute-ui.ps1'
    $languagePath = Join-Path $root '.service/language.txt'
    Set-Content -LiteralPath $languagePath -Value 'EN' -Encoding ASCII
    foreach ($mode in @('GameFilter','UpdateWatch')) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $uiPath -Mode $mode -LanguageFile $languagePath -NonInteractive
        if ($LASTEXITCODE -ne 0) { throw "$mode renderer failed in non-interactive mode." }
    }
}

Write-Host 'NexRoute 0.2.2 extended package checks passed.' -ForegroundColor Green
Write-Host "Patched strategies: $($strategyFiles.Count)" -ForegroundColor Green
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
