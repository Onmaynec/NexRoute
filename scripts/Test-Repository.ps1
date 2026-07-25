[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$errors = [System.Collections.Generic.List[string]]::new()

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )

    if (-not $Condition) {
        $script:errors.Add($Message)
        Write-Host "[FAIL] $Message" -ForegroundColor Red
    }
    else {
        Write-Host "[ OK ] $Message" -ForegroundColor Green
    }
}

Write-Host 'NexRoute repository validation' -ForegroundColor Cyan
Write-Host '================================' -ForegroundColor Cyan

$requiredFiles = @(
    'README.md',
    'LICENSE',
    'THIRD_PARTY_NOTICES.md',
    'CONTRIBUTING.md',
    'SECURITY.md',
    '.service/version.txt',
    'overlay/nexroute.bat',
    'scripts/Build-NexRoute.ps1',
    '.github/workflows/validate.yml',
    '.github/workflows/release.yml',
    'docs/README_EN.md',
    'docs/ARCHITECTURE.md',
    'docs/COMPATIBILITY.md',
    'docs/RELEASES.md',
    'docs/UPSTREAM.md'
)

foreach ($relativePath in $requiredFiles) {
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $root $relativePath) -PathType Leaf) -Message "Required file exists: $relativePath"
}

$versionPath = Join-Path $root '.service/version.txt'
if (Test-Path -LiteralPath $versionPath) {
    $version = (Get-Content -LiteralPath $versionPath -Raw).Trim()
    Assert-True -Condition ($version -match '^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$') -Message "Version is valid semantic version: $version"

    $readme = Get-Content -LiteralPath (Join-Path $root 'README.md') -Raw
    Assert-True -Condition ($readme -match [regex]::Escape($version)) -Message 'README mentions the current version'
}

$buildScriptPath = Join-Path $root 'scripts/Build-NexRoute.ps1'
if (Test-Path -LiteralPath $buildScriptPath) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($buildScriptPath, [ref]$tokens, [ref]$parseErrors)
    Assert-True -Condition ($parseErrors.Count -eq 0) -Message 'Build-NexRoute.ps1 parses without PowerShell syntax errors'

    $buildScript = Get-Content -LiteralPath $buildScriptPath -Raw
    Assert-True -Condition ($buildScript -match "UpstreamVersion = '1\.10\.0'") -Message 'Flowseal baseline is pinned to 1.10.0'
    Assert-True -Condition ($buildScript -match 'Get-FileHash.+SHA256') -Message 'Release builder generates SHA-256'
}

$forbiddenExtensions = @('.exe', '.dll', '.sys', '.bin', '.zip', '.rar', '.7z')
$forbiddenFiles = @(
    Get-ChildItem -LiteralPath $root -File -Recurse -Force |
        Where-Object {
            $_.FullName -notmatch '[\\/]\.git[\\/]' -and
            $forbiddenExtensions -contains $_.Extension.ToLowerInvariant()
        }
)
Assert-True -Condition ($forbiddenFiles.Count -eq 0) -Message 'Git source tree contains no binaries or archives'

if ($forbiddenFiles.Count -gt 0) {
    foreach ($file in $forbiddenFiles) {
        Write-Host "       $($file.FullName)" -ForegroundColor Yellow
    }
}

$workflowFiles = Get-ChildItem -LiteralPath (Join-Path $root '.github/workflows') -Filter '*.yml' -File -ErrorAction SilentlyContinue
Assert-True -Condition ($workflowFiles.Count -ge 2) -Message 'Validation and release workflows are present'

if ($errors.Count -gt 0) {
    Write-Host "`nValidation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host '`nAll NexRoute repository checks passed.' -ForegroundColor Green
