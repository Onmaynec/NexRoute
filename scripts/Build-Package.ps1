[CmdletBinding()]
param(
    [Parameter()][ValidatePattern('^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$')][string]$Version,
    [Parameter()][string]$UpstreamVersion,
    [Parameter()][string]$OutputDirectory,
    [Parameter()][string]$UpstreamArchive,
    [Parameter()][string]$UpstreamCachePath,
    [switch]$AllowUnlockedUpstream
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$baseBuilder = Join-Path $PSScriptRoot 'Build-Release.ps1'
if (-not $Version) {
    $Version = (Get-Content -LiteralPath (Join-Path $repositoryRoot '.service/version.txt') -Raw -Encoding UTF8).Trim()
}
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $repositoryRoot 'artifacts'
}
$outputPath = [System.IO.Path]::GetFullPath($OutputDirectory)
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('nexroute-package-{0}' -f [guid]::NewGuid().ToString('N'))
$packageRoot = Join-Path $tempRoot 'package'

function Copy-NexRoutePackageFile {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw "Required updater source file was not found: $Source"
    }
    $parent = Split-Path -Parent $Destination
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

try {
    if (-not (Test-Path -LiteralPath $baseBuilder -PathType Leaf)) {
        throw "Base release builder was not found: $baseBuilder"
    }

    $buildParameters = @{
        Version = $Version
        OutputDirectory = $outputPath
    }
    if ($UpstreamVersion) { $buildParameters.UpstreamVersion = $UpstreamVersion }
    if ($UpstreamArchive) { $buildParameters.UpstreamArchive = $UpstreamArchive }
    if ($UpstreamCachePath) { $buildParameters.UpstreamCachePath = $UpstreamCachePath }
    if ($AllowUnlockedUpstream) { $buildParameters.AllowUnlockedUpstream = $true }

    $baseResult = @(& $baseBuilder @buildParameters) | Select-Object -Last 1
    if (-not $baseResult) { throw 'Base release builder returned no result.' }

    $zipPath = [string]$baseResult.Archive
    $checksumPath = [string]$baseResult.Checksum
    if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) {
        throw "Base release archive was not found: $zipPath"
    }

    New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
    Expand-Archive -LiteralPath $zipPath -DestinationPath $packageRoot -Force

    $serviceDirectory = Join-Path $packageRoot '.service'
    $i18nDirectory = Join-Path $serviceDirectory 'i18n'
    if (-not (Test-Path -LiteralPath $serviceDirectory -PathType Container)) {
        throw 'Expanded package has no .service directory.'
    }
    if (-not (Test-Path -LiteralPath $i18nDirectory -PathType Container)) {
        throw 'Expanded package has no .service/i18n directory.'
    }

    $testLabDestination = Join-Path $packageRoot 'utils/test zapret.ps1'
    if (-not (Test-Path -LiteralPath $testLabDestination -PathType Leaf)) {
        throw 'Expanded package is missing utils/test zapret.ps1.'
    }

    # Windows PowerShell 5.1 interprets UTF-8 without BOM as the active ANSI code page.
    # Strategy Lab contains Cyrillic strings, so the final packaged copy must carry a BOM.
    $testLabText = [System.IO.File]::ReadAllText($testLabDestination, [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText(
        $testLabDestination,
        $testLabText,
        (New-Object System.Text.UTF8Encoding($true))
    )

    $updaterDestination = Join-Path $serviceDirectory 'nexroute-updater.ps1'
    Copy-NexRoutePackageFile `
        -Source (Join-Path $repositoryRoot 'overlay/.service/nexroute-updater.ps1') `
        -Destination $updaterDestination

    # Windows PowerShell 5.1 interprets UTF-8 without BOM as the active ANSI code page.
    # The updater contains RU strings, so the packaged copy must carry an explicit BOM.
    $updaterText = [System.IO.File]::ReadAllText($updaterDestination, [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText(
        $updaterDestination,
        $updaterText,
        (New-Object System.Text.UTF8Encoding($true))
    )

    Copy-NexRoutePackageFile `
        -Source (Join-Path $repositoryRoot 'overlay/.service/i18n/nexroute-pages.ps1') `
        -Destination (Join-Path $i18nDirectory 'nexroute-pages.ps1')
    Copy-NexRoutePackageFile `
        -Source (Join-Path $repositoryRoot 'overlay/.service/i18n/nexroute-pages-update.ps1') `
        -Destination (Join-Path $i18nDirectory 'nexroute-pages-update.ps1')
    Copy-NexRoutePackageFile `
        -Source (Join-Path $repositoryRoot 'overlay/nexroute-update.cmd') `
        -Destination (Join-Path $packageRoot 'nexroute-update.cmd')

    foreach ($relativePath in @(
        'utils/test zapret.ps1',
        '.service/nexroute-updater.ps1',
        '.service/i18n/nexroute-pages-update.ps1',
        'nexroute-update.cmd'
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $packageRoot $relativePath) -PathType Leaf)) {
            throw "Package finalization failed. Missing: $relativePath"
        }
    }

    Remove-Item -LiteralPath $zipPath -Force
    if ($checksumPath -and (Test-Path -LiteralPath $checksumPath)) {
        Remove-Item -LiteralPath $checksumPath -Force
    }

    Compress-Archive -Path (Join-Path $packageRoot '*') -DestinationPath $zipPath -CompressionLevel Optimal
    $hash = Get-FileHash -LiteralPath $zipPath -Algorithm SHA256
    $archiveName = Split-Path $zipPath -Leaf
    if (-not $checksumPath) { $checksumPath = "$zipPath.sha256" }
    Set-Content `
        -LiteralPath $checksumPath `
        -Value ("{0}  {1}" -f $hash.Hash.ToLowerInvariant(), $archiveName) `
        -Encoding ASCII

    [pscustomobject]@{
        Version = [string]$baseResult.Version
        UpstreamVersion = [string]$baseResult.UpstreamVersion
        UpstreamAsset = [string]$baseResult.UpstreamAsset
        UpstreamSha256 = [string]$baseResult.UpstreamSha256
        UpstreamResolution = [string]$baseResult.UpstreamResolution
        PatchTargetCount = [int]$baseResult.PatchTargetCount
        PatchOperationCount = [int]$baseResult.PatchOperationCount
        StrategyCount = [int]$baseResult.StrategyCount
        ServiceCount = [int]$baseResult.ServiceCount
        UpdaterIncluded = $true
        Archive = $zipPath
        Checksum = $checksumPath
        Sha256 = $hash.Hash.ToLowerInvariant()
    }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
