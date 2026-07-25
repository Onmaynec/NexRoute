[CmdletBinding()]
param(
    [Parameter()]
    [string]$ArtifactsDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts'),

    [Parameter()]
    [string]$ExtractDirectory,

    [switch]$SkipRuntime
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Check {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ("[PACKAGE] {0}" -f $Message) -ForegroundColor Cyan
}

$artifactsPath = [System.IO.Path]::GetFullPath($ArtifactsDirectory)
$zip = Get-ChildItem -LiteralPath $artifactsPath -Filter 'NexRoute-*-win-x64.zip' -File |
    Sort-Object -Property LastWriteTimeUtc -Descending |
    Select-Object -First 1
$checksum = if ($zip) {
    Get-Item -LiteralPath ($zip.FullName + '.sha256') -ErrorAction SilentlyContinue
}
else {
    $null
}

if (-not $zip -or -not $checksum) {
    throw 'Build output is incomplete: ZIP or SHA-256 file is missing.'
}
if ($zip.Length -lt 1MB) {
    throw 'Release archive is unexpectedly small.'
}

Write-Check 'Verifying SHA-256'
$expectedHash = ((Get-Content -LiteralPath $checksum.FullName -Raw) -split '\s+')[0].Trim().ToLowerInvariant()
$actualHash = (Get-FileHash -LiteralPath $zip.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
if ($expectedHash -ne $actualHash) {
    throw "SHA-256 mismatch: expected $expectedHash, got $actualHash"
}

if (-not $ExtractDirectory) {
    $ExtractDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("nexroute-package-test-{0}" -f [guid]::NewGuid().ToString('N'))
}
$extractPath = [System.IO.Path]::GetFullPath($ExtractDirectory)
if (Test-Path -LiteralPath $extractPath) {
    Remove-Item -LiteralPath $extractPath -Recurse -Force
}
New-Item -ItemType Directory -Path $extractPath -Force | Out-Null

Write-Check 'Expanding release archive'
Expand-Archive -LiteralPath $zip.FullName -DestinationPath $extractPath -Force

$required = @(
    'service.bat',
    'nexroute.bat',
    'NexRoute.lnk',
    'general.bat',
    'bin/winws.exe',
    'bin/WinDivert.dll',
    'bin/WinDivert64.sys',
    '.service/nexroute.ico',
    '.service/nexroute-ui.ps1',
    '.service/nexroute-services.ps1',
    '.service/services.json',
    '.service/services-state.json',
    '.service/i18n/ru.json',
    '.service/i18n/en.json',
    '.service/language.txt',
    '.service/version.txt',
    'assets/nexroute-mark.svg',
    'docs/SERVICES.md',
    'NEXROUTE_BUILD_INFO.txt'
)

Write-Check 'Checking required package files'
foreach ($relativePath in $required) {
    $candidate = Join-Path $extractPath $relativePath
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw "Built package is missing $relativePath"
    }
}

Write-Check 'Inspecting service.bat UI routing'
$servicePath = Join-Path $extractPath 'service.bat'
$service = Get-Content -LiteralPath $servicePath -Raw
foreach ($token in @(
    '-Mode Status',
    '-Mode StrategyPicker',
    '-Mode PayloadManager',
    '-Mode IpSetSwitch',
    '-Mode SyncIpSet',
    '-Mode SyncHosts',
    '-Mode TestsIntro',
    '-Mode Services'
)) {
    if ($service -notmatch [regex]::Escape($token)) {
        throw "service.bat is missing UI route: $token"
    }
}
if ($service -match '[\u0400-\u04FF]') {
    throw 'service.bat contains direct Cyrillic literals and may break in CMD.'
}

Write-Check 'Parsing package PowerShell runtime'
$uiPath = Join-Path $extractPath '.service/nexroute-ui.ps1'
$serviceControllerPath = Join-Path $extractPath '.service/nexroute-services.ps1'
foreach ($scriptPath in @($uiPath, $serviceControllerPath)) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -ne 0) {
        foreach ($parseError in $parseErrors) {
            Write-Host ("{0}:{1} {2}" -f $parseError.Extent.StartLineNumber, $parseError.Extent.StartColumnNumber, $parseError.Message) -ForegroundColor Red
        }
        throw "PowerShell parse errors in $scriptPath"
    }
}

$ui = Get-Content -LiteralPath $uiPath -Raw
if (@($ui.ToCharArray() | Where-Object { [int]$_ -gt 127 }).Count -ne 0) {
    throw 'nexroute-ui.ps1 source is not ASCII-safe.'
}

Write-Check 'Validating 15 service definitions'
$servicesPath = Join-Path $extractPath '.service/services.json'
$services = @((Get-Content -LiteralPath $servicesPath -Raw -Encoding UTF8 | ConvertFrom-Json).services)
if ($services.Count -ne 15) {
    throw "Expected 15 services, got $($services.Count)."
}

& $serviceControllerPath -Mode Validate -Root $extractPath
& $serviceControllerPath -Mode Apply -Root $extractPath

Write-Check 'Inspecting managed domain blocks'
$generalUserPath = Join-Path $extractPath 'lists/list-general-user.txt'
$excludeUserPath = Join-Path $extractPath 'lists/list-exclude-user.txt'
$generalUser = Get-Content -LiteralPath $generalUserPath -Raw
$excludeUser = Get-Content -LiteralPath $excludeUserPath -Raw
if ($generalUser -notmatch 'NEXROUTE-SERVICES-BEGIN') {
    throw 'Managed enabled-service block was not created.'
}
if ($excludeUser -notmatch 'NEXROUTE-DISABLED-SERVICES-BEGIN') {
    throw 'Managed disabled-service block was not created.'
}
if ($generalUser -notmatch 'youtube\.com' -or $generalUser -notmatch 'discord\.com') {
    throw 'Default baseline services are not enabled.'
}
if ($excludeUser -notmatch 'chatgpt\.com' -or $excludeUser -notmatch 'casebattle\.net') {
    throw 'Disabled service domains are not excluded.'
}

Write-Check 'Inspecting strategy launch hooks'
$strategyFiles = @(
    Get-ChildItem -LiteralPath $extractPath -Filter '*.bat' -File |
        Where-Object { $_.Name -notin @('service.bat', 'nexroute.bat') }
)
if ($strategyFiles.Count -eq 0) {
    throw 'No strategy launchers were found.'
}
foreach ($strategyFile in $strategyFiles) {
    $content = Get-Content -LiteralPath $strategyFile.FullName -Raw
    if ($content -notmatch 'NEXROUTE_PROFILE_BOOT') {
        throw "No animated boot hook: $($strategyFile.Name)"
    }
    if ($content -notmatch 'nexroute-services\.ps1') {
        throw "No service matrix apply hook: $($strategyFile.Name)"
    }
}

$testScript = Get-Content -LiteralPath (Join-Path $extractPath 'utils/test zapret.ps1') -Raw
if ($testScript -notmatch 'NEXROUTE_TEST_HEADER') {
    throw 'Test laboratory header was not injected.'
}

if (-not $SkipRuntime) {
    Write-Check 'Executing RU/EN pages in Windows PowerShell 5.1'
    $languagePath = Join-Path $extractPath '.service/language.txt'
    foreach ($language in @('RU', 'EN')) {
        Set-Content -LiteralPath $languagePath -Value $language -Encoding ascii
        $calls = @(
            @('-Mode', 'Menu', '-NonInteractive'),
            @('-Mode', 'Action', '-ActionId', 'deploy', '-NonInteractive'),
            @('-Mode', 'Launch', '-Profile', 'general (ALT)', '-NonInteractive'),
            @('-Mode', 'Status', '-NonInteractive'),
            @('-Mode', 'StrategyPicker', '-NonInteractive'),
            @('-Mode', 'PayloadManager', '-NonInteractive'),
            @('-Mode', 'Services', '-NonInteractive'),
            @('-Mode', 'TestsIntro', '-NonInteractive'),
            @('-Mode', 'TestHeader', '-NonInteractive')
        )

        foreach ($arguments in $calls) {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $uiPath -Root $extractPath -LanguageFile $languagePath @arguments
            if ($LASTEXITCODE -ne 0) {
                throw "$language renderer failed: $($arguments -join ' ')"
            }
        }
    }
}

Write-Check 'Package verification completed'
[pscustomobject]@{
    Archive = $zip.FullName
    ExtractPath = $extractPath
    Sha256 = $actualHash
    StrategyCount = $strategyFiles.Count
    ServiceCount = $services.Count
    RuntimeTested = -not [bool]$SkipRuntime
}
