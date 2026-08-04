[CmdletBinding()]
param(
    [ValidateSet('Auto','Check','Install','Menu','Rollback','Status')]
    [string]$Mode='Menu',
    [string]$Root,
    [string]$ReleaseMetadataPath,
    [string]$AssetDirectory,
    [ValidateRange(1,168)]
    [int]$CheckIntervalHours=24,
    [switch]$Force,
    [switch]$Json,
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root=Split-Path -Parent $PSScriptRoot
}
$Root=[IO.Path]::GetFullPath($Root).TrimEnd('\','/')
$coreUpdater=Join-Path $PSScriptRoot 'nexroute-updater.ps1'
if (-not (Test-Path -LiteralPath $coreUpdater -PathType Leaf)) {
    throw "NexRoute updater core is missing: $coreUpdater"
}

function Resolve-NrPublicLatestReleaseVersion {
    [CmdletBinding()]
    param()

    Add-Type -AssemblyName System.Net.Http
    $handler=[System.Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect=$true
    $client=[System.Net.Http.HttpClient]::new($handler)
    try {
        $client.Timeout=[TimeSpan]::FromSeconds(20)
        $client.DefaultRequestHeaders.UserAgent.ParseAdd('NexRoute-Updater-Fallback/0.6.1')
        $response=$client.GetAsync(
            'https://github.com/Onmaynec/NexRoute/releases/latest',
            [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead
        ).GetAwaiter().GetResult()
        try {
            $response.EnsureSuccessStatusCode()
            $finalUri=[string]$response.RequestMessage.RequestUri.AbsoluteUri
        } finally {
            $response.Dispose()
        }
    } finally {
        $client.Dispose()
        $handler.Dispose()
    }

    if ($finalUri -notmatch '/releases/tag/v?(?<version>\d+\.\d+\.\d+)/?(?:\?.*)?$') {
        throw "GitHub latest-release redirect returned an unexpected URL: $finalUri"
    }
    return $Matches.version
}

function New-NrFallbackReleaseMetadata {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Version)

    if ($Version -notmatch '^\d+\.\d+\.\d+$') {
        throw "Invalid fallback release version: $Version"
    }
    $tag="v$Version"
    $archive="NexRoute-$Version-win-x64.zip"
    $checksum="$archive.sha256"
    $validationJson="NexRoute-$Version-validation.json"
    $validationMarkdown="NexRoute-$Version-validation.md"
    $base="https://github.com/Onmaynec/NexRoute/releases/download/$tag"
    $metadata=[ordered]@{
        tag_name=$tag
        draft=$false
        prerelease=$false
        published_at=$null
        html_url="https://github.com/Onmaynec/NexRoute/releases/tag/$tag"
        assets=@(
            [ordered]@{ name=$archive; browser_download_url="$base/$archive" },
            [ordered]@{ name=$checksum; browser_download_url="$base/$checksum" },
            [ordered]@{ name=$validationJson; browser_download_url="$base/$validationJson" },
            [ordered]@{ name=$validationMarkdown; browser_download_url="$base/$validationMarkdown" }
        )
    }
    $path=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-release-fallback-'+[guid]::NewGuid().ToString('N')+'.json')
    [IO.File]::WriteAllText(
        $path,
        ($metadata | ConvertTo-Json -Depth 8)+[Environment]::NewLine,
        [Text.UTF8Encoding]::new($false)
    )
    return $path
}

function Invoke-NrUpdaterCore {
    [CmdletBinding()]
    param([string]$MetadataPath)

    $arguments=@(
        '-NoProfile','-ExecutionPolicy','Bypass','-File',$coreUpdater,
        '-Mode',$Mode,
        '-Root',$Root,
        '-CheckIntervalHours',[string]$CheckIntervalHours
    )
    if ($MetadataPath) { $arguments+=@('-ReleaseMetadataPath',$MetadataPath) }
    if ($AssetDirectory) { $arguments+=@('-AssetDirectory',$AssetDirectory) }
    if ($Force) { $arguments+='-Force' }
    if ($Json) { $arguments+='-Json' }
    if ($NonInteractive) { $arguments+='-NonInteractive' }

    $output=& powershell.exe @arguments 2>&1
    return [pscustomobject]@{
        exitCode=[int]$LASTEXITCODE
        output=@($output)
    }
}

$temporaryMetadata=$null
try {
    $effectiveMetadata=$ReleaseMetadataPath
    $needsRelease=($Mode -in @('Auto','Check','Install','Menu'))
    if (-not $effectiveMetadata -and -not $AssetDirectory -and $needsRelease) {
        try {
            $latestVersion=Resolve-NrPublicLatestReleaseVersion
            $temporaryMetadata=New-NrFallbackReleaseMetadata -Version $latestVersion
            $effectiveMetadata=$temporaryMetadata
        } catch {
            # Preserve the original API path when the public redirect itself is
            # unavailable. The core updater keeps its existing error handling.
            $effectiveMetadata=$null
        }
    }

    $result=Invoke-NrUpdaterCore -MetadataPath $effectiveMetadata
    foreach ($line in @($result.output)) { Write-Output $line }
    exit ([int]$result.exitCode)
} finally {
    if ($temporaryMetadata) {
        Remove-Item -LiteralPath $temporaryMetadata -Force -ErrorAction SilentlyContinue
    }
}
