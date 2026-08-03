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
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repositoryRoot 'artifacts' }
$outputPath = [System.IO.Path]::GetFullPath($OutputDirectory)
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('nexroute-package-{0}' -f [guid]::NewGuid().ToString('N'))
$packageRoot = Join-Path $tempRoot 'package'

function Copy-NexRoutePackageFile {
    param([Parameter(Mandatory)][string]$Source,[Parameter(Mandatory)][string]$Destination)
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { throw "Required package source file was not found: $Source" }
    $parent = Split-Path -Parent $Destination
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

function Copy-NexRoutePackageDirectory {
    param([Parameter(Mandatory)][string]$Source,[Parameter(Mandatory)][string]$Destination)
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) { throw "Required package source directory was not found: $Source" }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    foreach ($item in @(Get-ChildItem -LiteralPath $Source -Force)) {
        $target=Join-Path $Destination $item.Name
        if ($item.PSIsContainer) { Copy-NexRoutePackageDirectory -Source $item.FullName -Destination $target }
        else { Copy-NexRoutePackageFile -Source $item.FullName -Destination $target }
    }
}

function Set-NexRoutePowerShellBom {
    param([Parameter(Mandatory)][string]$Path)
    $text=[System.IO.File]::ReadAllText($Path,[System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText($Path,$text,(New-Object System.Text.UTF8Encoding($true)))
}

try {
    if (-not (Test-Path -LiteralPath $baseBuilder -PathType Leaf)) { throw "Base release builder was not found: $baseBuilder" }
    $buildParameters=@{ Version=$Version; OutputDirectory=$outputPath }
    if ($UpstreamVersion) { $buildParameters.UpstreamVersion=$UpstreamVersion }
    if ($UpstreamArchive) { $buildParameters.UpstreamArchive=$UpstreamArchive }
    if ($UpstreamCachePath) { $buildParameters.UpstreamCachePath=$UpstreamCachePath }
    if ($AllowUnlockedUpstream) { $buildParameters.AllowUnlockedUpstream=$true }

    $baseResult=@(& $baseBuilder @buildParameters) | Select-Object -Last 1
    if (-not $baseResult) { throw 'Base release builder returned no result.' }
    $zipPath=[string]$baseResult.Archive
    $checksumPath=[string]$baseResult.Checksum
    if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) { throw "Base release archive was not found: $zipPath" }

    New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null
    Expand-Archive -LiteralPath $zipPath -DestinationPath $packageRoot -Force
    $serviceDirectory=Join-Path $packageRoot '.service'
    $i18nDirectory=Join-Path $serviceDirectory 'i18n'
    if (-not (Test-Path -LiteralPath $serviceDirectory -PathType Container)) { throw 'Expanded package has no .service directory.' }
    if (-not (Test-Path -LiteralPath $i18nDirectory -PathType Container)) { throw 'Expanded package has no .service/i18n directory.' }

    # Preserve the proven Flowseal/NexRoute batch engine behind the new arrow-key interface.
    Copy-Item -LiteralPath (Join-Path $packageRoot 'service.bat') -Destination (Join-Path $serviceDirectory 'legacy-service.bat') -Force
    Copy-NexRoutePackageFile -Source (Join-Path $repositoryRoot 'overlay/service.bat') -Destination (Join-Path $packageRoot 'service.bat')
    Copy-NexRoutePackageFile -Source (Join-Path $repositoryRoot 'overlay/nexroute-update.cmd') -Destination (Join-Path $packageRoot 'nexroute-update.cmd')
    Copy-NexRoutePackageFile -Source (Join-Path $repositoryRoot 'overlay/nexroute-tray.cmd') -Destination (Join-Path $packageRoot 'nexroute-tray.cmd')

    foreach ($name in @('nexroute-console.ps1','nexroute-monitor.ps1','nexroute-tray.ps1','nexroute-updater.ps1','nexroute-worker-host.ps1')) {
        Copy-NexRoutePackageFile -Source (Join-Path $repositoryRoot ('overlay/.service/' + $name)) -Destination (Join-Path $serviceDirectory $name)
    }
    Copy-NexRoutePackageDirectory -Source (Join-Path $repositoryRoot 'overlay/.service/next') -Destination (Join-Path $serviceDirectory 'next')

    foreach ($name in @('nexroute-services-state.ps1','nexroute-services-network.ps1','nexroute-services-runtime.ps1','nexroute-services-diagnostics.ps1')) {
        Copy-NexRoutePackageFile -Source (Join-Path $repositoryRoot ('overlay/.service/i18n/' + $name)) -Destination (Join-Path $i18nDirectory $name)
    }

    # Windows PowerShell 5.1 treats UTF-8 without BOM as the active ANSI code page.
    # Finalize every localized PowerShell module with BOM.
    foreach ($scriptFile in @(Get-ChildItem -LiteralPath $serviceDirectory -Filter '*.ps1' -File -Recurse)) { Set-NexRoutePowerShellBom -Path $scriptFile.FullName }

    $testLabDestination=Join-Path $packageRoot 'utils/test zapret.ps1'
    if (-not (Test-Path -LiteralPath $testLabDestination -PathType Leaf)) { throw 'Expanded package is missing utils/test zapret.ps1.' }
    Set-NexRoutePowerShellBom -Path $testLabDestination

    $required=@(
        'service.bat','nexroute.bat','nexroute-update.cmd','nexroute-tray.cmd',
        '.service/legacy-service.bat','.service/nexroute-console.ps1','.service/nexroute-monitor.ps1','.service/nexroute-tray.ps1',
        '.service/nexroute-updater.ps1','.service/nexroute-worker-host.ps1','.service/next/nexroute-common.ps1','.service/next/nexroute-strategies.ps1',
        '.service/next/nexroute-network.ps1','.service/next/nexroute-diagnostics.ps1','.service/next/nexroute-management.ps1',
        '.service/next/nexroute-update.ps1','.service/next/nexroute-workers.ps1','.service/next/nexroute-worker-plans.ps1',
        '.service/next/nexroute-runtime-extensions.ps1','.service/next/nexroute-media.ps1','.service/next/nexroute-strategy-lab-v2.ps1',
        '.service/next/nexroute-update-transaction.ps1','utils/test zapret.ps1'
    )
    foreach ($relativePath in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $packageRoot $relativePath) -PathType Leaf)) { throw "Package finalization failed. Missing: $relativePath" }
    }

    Remove-Item -LiteralPath $zipPath -Force
    if ($checksumPath -and (Test-Path -LiteralPath $checksumPath)) { Remove-Item -LiteralPath $checksumPath -Force }
    Compress-Archive -Path (Join-Path $packageRoot '*') -DestinationPath $zipPath -CompressionLevel Optimal
    $hash=Get-FileHash -LiteralPath $zipPath -Algorithm SHA256
    $archiveName=Split-Path $zipPath -Leaf
    if (-not $checksumPath) { $checksumPath="$zipPath.sha256" }
    Set-Content -LiteralPath $checksumPath -Value ("{0}  {1}" -f $hash.Hash.ToLowerInvariant(),$archiveName) -Encoding ASCII

    [pscustomobject]@{
        Version=[string]$baseResult.Version
        UpstreamVersion=[string]$baseResult.UpstreamVersion
        UpstreamAsset=[string]$baseResult.UpstreamAsset
        UpstreamSha256=[string]$baseResult.UpstreamSha256
        UpstreamResolution=[string]$baseResult.UpstreamResolution
        PatchTargetCount=[int]$baseResult.PatchTargetCount
        PatchOperationCount=[int]$baseResult.PatchOperationCount
        StrategyCount=[int]$baseResult.StrategyCount
        ServiceCount=[int]$baseResult.ServiceCount
        UpdaterIncluded=$true
        NextInterfaceIncluded=$true
        WorkerRuntimeIncluded=$true
        Archive=$zipPath
        Checksum=$checksumPath
        Sha256=$hash.Hash.ToLowerInvariant()
    }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
