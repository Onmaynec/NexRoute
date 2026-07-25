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
    param([Parameter(Mandatory)][string]$RelativePath)
    $path = Join-Path $root $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return }
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -ne 0) {
        foreach ($parseError in $parseErrors) {
            Write-Host ("       {0}:{1} {2}" -f $parseError.Extent.StartLineNumber, $parseError.Extent.StartColumnNumber, $parseError.Message) -ForegroundColor Yellow
        }
    }
    Assert-True -Condition ($parseErrors.Count -eq 0) -Message "$RelativePath parses without PowerShell syntax errors"
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
    'overlay/.service/nexroute-services.ps1',
    'overlay/.service/New-NexRouteIcon.ps1',
    'overlay/.service/services.json',
    'overlay/.service/i18n/ru.json',
    'overlay/.service/i18n/en.json',
    'assets/nexroute-mark.svg',
    'scripts/Build-NexRoute.ps1',
    '.github/workflows/validate.yml',
    '.github/workflows/release.yml',
    'docs/README_EN.md',
    'docs/ARCHITECTURE.md',
    'docs/COMPATIBILITY.md',
    'docs/RELEASES.md',
    'docs/SERVICES.md',
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
    Assert-True -Condition ($readme -match 'Service Bypass Matrix|Матрица обхода сервисов') -Message 'README documents the service matrix'
}

$license = Get-Content -LiteralPath (Join-Path $root 'LICENSE') -Raw
Assert-True -Condition ($license -match 'MIT License') -Message 'Project license is MIT'
Assert-True -Condition ($license -match 'Copyright \(c\) 2026 Onmaynec') -Message 'License attribution belongs to Onmaynec'

$powerShellFiles = @(
    'scripts/Build-NexRoute.ps1',
    'scripts/Test-Repository.ps1',
    'overlay/.service/nexroute-ui.ps1',
    'overlay/.service/nexroute-services.ps1',
    'overlay/.service/New-NexRouteIcon.ps1'
)
foreach ($relativePath in $powerShellFiles) {
    Test-PowerShellFile -RelativePath $relativePath
}

$uiPath = Join-Path $root 'overlay/.service/nexroute-ui.ps1'
if (Test-Path -LiteralPath $uiPath) {
    $ui = Get-Content -LiteralPath $uiPath -Raw
    $nonAscii = @($ui.ToCharArray() | Where-Object { [int]$_ -gt 127 })
    Assert-True -Condition ($nonAscii.Count -eq 0) -Message 'Terminal renderer source is ASCII-safe'
    foreach ($mode in @('Menu', 'Status', 'StrategyPicker', 'PayloadManager', 'IpSetSwitch', 'SyncIpSet', 'SyncHosts', 'TestsIntro', 'TestHeader', 'Services')) {
        Assert-True -Condition ($ui -match [regex]::Escape("'$mode'")) -Message "Terminal renderer implements $mode mode"
    }
    Assert-True -Condition ($ui -match 'Console\]::ReadKey') -Message 'Service matrix supports keyboard navigation'
}

$servicesPath = Join-Path $root 'overlay/.service/services.json'
if (Test-Path -LiteralPath $servicesPath) {
    try {
        $servicesDocument = Get-Content -LiteralPath $servicesPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $services = @($servicesDocument.services)
        Assert-True -Condition ($services.Count -eq 15) -Message 'Service matrix contains exactly 15 requested services'
        $ids = @($services | ForEach-Object { $_.id })
        Assert-True -Condition (($ids | Sort-Object -Unique).Count -eq $ids.Count) -Message 'Service ids are unique'
        $expectedIds = @('youtube', 'discord', 'chatgpt', 'facetime', 'snapchat', 'viber', 'signal', 'x', 'instagram', 'facebook', 'telegram', 'linkedin', 'tiktok', 'whatsapp', 'casebattle')
        foreach ($id in $expectedIds) {
            Assert-True -Condition ($ids -contains $id) -Message "Service matrix contains: $id"
        }
        foreach ($service in $services) {
            Assert-True -Condition (@($service.domains).Count -gt 0) -Message "Service '$($service.id)' has domain entries"
        }
    }
    catch {
        Assert-True -Condition $false -Message ("services.json is valid: " + $_.Exception.Message)
    }
}

$buildScriptPath = Join-Path $root 'scripts/Build-NexRoute.ps1'
if (Test-Path -LiteralPath $buildScriptPath) {
    $buildScript = Get-Content -LiteralPath $buildScriptPath -Raw
    Assert-True -Condition ($buildScript -match "UpstreamVersion = '1\.10\.0'") -Message 'Flowseal baseline is pinned to 1.10.0'
    Assert-True -Condition ($buildScript -match 'releases/tags/\$UpstreamVersion') -Message 'Builder resolves an immutable upstream release tag'
    Assert-True -Condition ($buildScript -match 'Get-FileHash.+SHA256') -Message 'Release builder generates SHA-256'
    Assert-True -Condition ($buildScript -match 'nexroute-services\.ps1') -Message 'Builder installs the service matrix controller'
    Assert-True -Condition ($buildScript -match 'New-NexRouteIcon\.ps1') -Message 'Builder generates the custom Windows icon'
    Assert-True -Condition ($buildScript -match 'Mode Status') -Message 'Builder patches the styled status screen'
    Assert-True -Condition ($buildScript -match 'Mode StrategyPicker') -Message 'Builder patches the styled strategy selector'
    Assert-True -Condition ($buildScript -match 'Mode PayloadManager') -Message 'Builder patches the styled payload manager'
    Assert-True -Condition ($buildScript -match 'Mode SyncIpSet') -Message 'Builder patches animated IPSet sync'
    Assert-True -Condition ($buildScript -match 'Mode SyncHosts') -Message 'Builder patches animated hosts sync'
}

$forbiddenExtensions = @('.exe', '.dll', '.sys', '.bin', '.zip', '.rar', '.7z', '.ico', '.lnk')
$forbiddenFiles = @(Get-ChildItem -LiteralPath $root -File -Recurse -Force | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' -and $forbiddenExtensions -contains $_.Extension.ToLowerInvariant() })
Assert-True -Condition ($forbiddenFiles.Count -eq 0) -Message 'Git source tree contains no generated binaries or archives'
if ($forbiddenFiles.Count -gt 0) {
    foreach ($file in $forbiddenFiles) { Write-Host "       $($file.FullName)" -ForegroundColor Yellow }
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
