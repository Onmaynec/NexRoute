[CmdletBinding()]
param(
    [string]$ArtifactsDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts'),
    [string]$ExtractDirectory,
    [switch]$SkipRuntime
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$artifactsPath = [System.IO.Path]::GetFullPath($ArtifactsDirectory)
$zip = Get-ChildItem -LiteralPath $artifactsPath -Filter 'NexRoute-*-win-x64.zip' -File | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
$checksum = if ($zip) { Get-Item -LiteralPath ($zip.FullName + '.sha256') -ErrorAction SilentlyContinue } else { $null }
if (-not $zip -or -not $checksum) { throw 'Build output is incomplete.' }
if ($zip.Length -lt 1MB) { throw 'Release archive is unexpectedly small.' }

$expectedHash = ((Get-Content -LiteralPath $checksum.FullName -Raw) -split '\s+')[0].Trim().ToLowerInvariant()
$actualHash = (Get-FileHash -LiteralPath $zip.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
if ($expectedHash -ne $actualHash) { throw "SHA-256 mismatch: expected $expectedHash, got $actualHash" }

if (-not $ExtractDirectory) { $ExtractDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("nexroute-package-test-{0}" -f [guid]::NewGuid().ToString('N')) }
$extractPath = [System.IO.Path]::GetFullPath($ExtractDirectory)
if (Test-Path -LiteralPath $extractPath) { Remove-Item -LiteralPath $extractPath -Recurse -Force }
New-Item -ItemType Directory -Path $extractPath -Force | Out-Null
Expand-Archive -LiteralPath $zip.FullName -DestinationPath $extractPath -Force

$required = @(
    'service.bat','nexroute.bat','NexRoute.lnk','general.bat','bin/winws.exe',
    'bin/WinDivert.dll','bin/WinDivert64.sys','.service/nexroute.ico',
    '.service/nexroute-ui.ps1','.service/nexroute-services.ps1','.service/services.json',
    '.service/services-state.json','.service/i18n/ru.json','.service/i18n/en.json',
    '.service/i18n/nexroute-theme.ps1','.service/i18n/nexroute-pages.ps1',
    '.service/i18n/nexroute-services-ui.ps1','.service/language.txt','.service/version.txt',
    'assets/nexroute-mark.svg','docs/SERVICES.md','NEXROUTE_BUILD_INFO.txt'
)
foreach ($relativePath in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $extractPath $relativePath) -PathType Leaf)) { throw "Built package is missing $relativePath" }
}

$allBatchFiles = @(Get-ChildItem -LiteralPath $extractPath -Filter '*.bat' -File)
foreach ($batchFile in $allBatchFiles) {
    $batchContent = Get-Content -LiteralPath $batchFile.FullName -Raw
    if ($batchContent -match '-Root\s+"%~dp0"') {
        throw "Published archive contains an unsafe Root argument: $($batchFile.Name)"
    }
}

$servicePath = Join-Path $extractPath 'service.bat'
$service = Get-Content -LiteralPath $servicePath -Raw
if ($service -notmatch 'if "!menu_choice!"=="14" goto nexroute_services_matrix') { throw 'service.bat is missing option 14.' }
foreach ($token in @('-Mode Menu','-Mode Action','-Mode Status','-Mode StrategyPicker','-Mode PayloadManager','-Mode IpSetSwitch','-Mode SyncIpSet','-Mode SyncHosts','-Mode TestsIntro','-Mode Services')) {
    if ($service -notmatch [regex]::Escape($token)) { throw "service.bat is missing $token" }
}

$uiPath = Join-Path $extractPath '.service/nexroute-ui.ps1'
$themePath = Join-Path $extractPath '.service/i18n/nexroute-theme.ps1'
$theme = Get-Content -LiteralPath $themePath -Raw
if ($theme -notmatch [regex]::Escape('| \ | || ____|\ \/ /|  _ \ / _ \| | | |_   _| ____|')) { throw 'Classic 0.1.1 logo layout is missing.' }

$servicesPath = Join-Path $extractPath '.service/services.json'
$controllerPath = Join-Path $extractPath '.service/nexroute-services.ps1'
$services = @((Get-Content -LiteralPath $servicesPath -Raw -Encoding UTF8 | ConvertFrom-Json).services)
if ($services.Count -ne 15) { throw "Expected 15 services, got $($services.Count)." }
& $controllerPath -Mode Validate -Root $extractPath
& $controllerPath -Mode Apply -Root $extractPath

$strategyFiles = @($allBatchFiles | Where-Object { $_.Name -notin @('service.bat','nexroute.bat') })
if ($strategyFiles.Count -eq 0) { throw 'No strategy files were found.' }
foreach ($strategyFile in $strategyFiles) {
    $content = Get-Content -LiteralPath $strategyFile.FullName -Raw
    if ($content -notmatch 'NEXROUTE_PROFILE_BOOT') { throw "Missing launch hook: $($strategyFile.Name)" }
    if ($content -notmatch 'nexroute-services\.ps1') { throw "Missing service matrix hook: $($strategyFile.Name)" }
}

if (-not $SkipRuntime) {
    $languagePath = Join-Path $extractPath '.service/language.txt'
    Set-Content -LiteralPath $languagePath -Value 'RU' -Encoding ascii

    # Regression guard for already-downloaded 0.2.0 packages: the dispatcher must
    # still recover a command line where the trailing slash swallowed arguments.
    $malformed = $extractPath + '\" -ActionId "deploy" -LanguageFile "' + $languagePath + '"'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $uiPath -Mode Action -Root $malformed -NonInteractive
    if ($LASTEXITCODE -ne 0) { throw 'Renderer failed to recover the malformed Root argument shown in user reports.' }

    foreach ($language in @('RU','EN')) {
        Set-Content -LiteralPath $languagePath -Value $language -Encoding ascii
        $calls = @(
            @('-Mode','Menu','-NonInteractive'),
            @('-Mode','Action','-ActionId','deploy','-NonInteractive'),
            @('-Mode','Launch','-Profile','general (ALT)','-NonInteractive'),
            @('-Mode','Status','-NonInteractive'),
            @('-Mode','StrategyPicker','-NonInteractive'),
            @('-Mode','PayloadManager','-NonInteractive'),
            @('-Mode','Services','-NonInteractive'),
            @('-Mode','TestsIntro','-NonInteractive'),
            @('-Mode','TestHeader','-NonInteractive'),
            @('-Mode','Screen','-ScreenId','diagnostics','-NonInteractive')
        )
        foreach ($arguments in $calls) {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $uiPath -LanguageFile $languagePath @arguments
            if ($LASTEXITCODE -ne 0) { throw "$language renderer failed: $($arguments -join ' ')" }
        }
    }
}

Write-Host "Verified package: $($zip.Name)" -ForegroundColor Green
Write-Host "Strategies: $($strategyFiles.Count)" -ForegroundColor Green
Write-Host "Services: $($services.Count)" -ForegroundColor Green
Write-Host "SHA-256: $actualHash" -ForegroundColor Green

[pscustomobject]@{
    Archive = $zip.FullName
    Checksum = $checksum.FullName
    ExtractPath = $extractPath
    Sha256 = $actualHash
    StrategyCount = $strategyFiles.Count
    ServiceCount = $services.Count
}
