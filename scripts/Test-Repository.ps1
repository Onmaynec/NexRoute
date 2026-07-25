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

function Test-PowerShellFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$DisplayName
    )

    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        foreach ($parseError in $parseErrors) {
            Write-Host ("       {0}:{1} {2}" -f $parseError.Extent.StartLineNumber, $parseError.Extent.StartColumnNumber, $parseError.Message) -ForegroundColor Yellow
        }
    }
    Assert-True -Condition ($parseErrors.Count -eq 0) -Message "$DisplayName parses without PowerShell syntax errors"
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
    'overlay/.service/nexroute-ui.ps1',
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
    Assert-True -Condition ($readme -match 'Flowseal 1\.10\.0') -Message 'README documents the pinned Flowseal baseline'
}

$licensePath = Join-Path $root 'LICENSE'
if (Test-Path -LiteralPath $licensePath) {
    $license = Get-Content -LiteralPath $licensePath -Raw
    Assert-True -Condition ($license -match 'MIT License') -Message 'Project license is MIT'
    Assert-True -Condition ($license -match 'Copyright \(c\) 2026 Onmaynec') -Message 'License attribution belongs to Onmaynec'
}

$buildScriptPath = Join-Path $root 'scripts/Build-NexRoute.ps1'
if (Test-Path -LiteralPath $buildScriptPath) {
    Test-PowerShellFile -Path $buildScriptPath -DisplayName 'Build-NexRoute.ps1'

    $buildScript = Get-Content -LiteralPath $buildScriptPath -Raw
    Assert-True -Condition ($buildScript -match "UpstreamVersion = '1\.10\.0'") -Message 'Flowseal baseline is pinned to 1.10.0'
    Assert-True -Condition ($buildScript -match 'releases/tags/\$UpstreamVersion') -Message 'Builder resolves an immutable upstream release tag'
    Assert-True -Condition ($buildScript -match 'Get-FileHash.+SHA256') -Message 'Release builder generates SHA-256'
    Assert-True -Condition ($buildScript -match 'overlay/\.service/nexroute-ui\.ps1') -Message 'Builder installs the terminal UI renderer'
    Assert-True -Condition ($buildScript -match 'NEXROUTE_PROFILE_BOOT') -Message 'Builder injects profile boot animation hooks'
    Assert-True -Condition ($buildScript -match '-Mode Action') -Message 'Builder wires action animations into service.bat'
    Assert-True -Condition ($buildScript -notmatch '[\u0400-\u04FF]') -Message 'Generated BAT overlay source contains no direct Cyrillic literals'
}

$uiScriptPath = Join-Path $root 'overlay/.service/nexroute-ui.ps1'
if (Test-Path -LiteralPath $uiScriptPath) {
    Test-PowerShellFile -Path $uiScriptPath -DisplayName 'nexroute-ui.ps1'

    $uiScript = Get-Content -LiteralPath $uiScriptPath -Raw
    $nonAsciiCharacters = @($uiScript.ToCharArray() | Where-Object { [int]$_ -gt 127 })
    Assert-True -Condition ($nonAsciiCharacters.Count -eq 0) -Message 'Terminal UI source is ASCII-safe for Windows PowerShell 5.1'
    Assert-True -Condition ($uiScript -match 'FromBase64String') -Message 'Russian translations are decoded explicitly as UTF-8'
    Assert-True -Condition ($uiScript -match 'NEXROUTE CONTROL NODE') -Message 'Terminal UI contains branded control-node header'
    Assert-True -Condition ($uiScript -match 'Write-ProgressLine') -Message 'Terminal UI implements animated progress bars'
    Assert-True -Condition ($uiScript -match "'Launch'") -Message 'Terminal UI implements strategy launch mode'
}

$testScriptPath = Join-Path $root 'scripts/Test-Repository.ps1'
Test-PowerShellFile -Path $testScriptPath -DisplayName 'Test-Repository.ps1'

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

$workflowDirectory = Join-Path $root '.github/workflows'
$workflowFiles = @(Get-ChildItem -LiteralPath $workflowDirectory -Filter '*.yml' -File -ErrorAction SilentlyContinue)
Assert-True -Condition ($workflowFiles.Count -ge 2) -Message 'Validation and release workflows are present'

foreach ($workflowFile in $workflowFiles) {
    $workflowContent = Get-Content -LiteralPath $workflowFile.FullName -Raw
    Assert-True -Condition ($workflowContent -match '(?m)^name:\s+\S') -Message "Workflow has a name: $($workflowFile.Name)"
    Assert-True -Condition ($workflowContent -match '(?m)^on:\s*$') -Message "Workflow defines triggers: $($workflowFile.Name)"
    Assert-True -Condition ($workflowContent -match '(?m)^jobs:\s*$') -Message "Workflow defines jobs: $($workflowFile.Name)"
}

if ($errors.Count -gt 0) {
    Write-Host "`nValidation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host "`nAll NexRoute repository checks passed." -ForegroundColor Green
