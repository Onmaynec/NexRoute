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

function Get-NrVersionFromReleaseLocator {
    [CmdletBinding()]
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    foreach ($pattern in @(
        '(?i)https://github\.com/Onmaynec/NexRoute/releases/tag/v?(?<version>\d+\.\d+\.\d+)',
        '(?i)/Onmaynec/NexRoute/releases/tag/v?(?<version>\d+\.\d+\.\d+)',
        '(?i)/releases/tag/v?(?<version>\d+\.\d+\.\d+)'
    )) {
        if ($Text -match $pattern) { return [string]$Matches.version }
    }
    return $null
}

function Resolve-NrPublicLatestReleaseVersion {
    [CmdletBinding()]
    param()

    $fixture=[Environment]::GetEnvironmentVariable('NEXROUTE_LATEST_RELEASE_FIXTURE')
    if (-not [string]::IsNullOrWhiteSpace($fixture)) {
        $fixtureText=$fixture
        if (Test-Path -LiteralPath $fixture -PathType Leaf) {
            $fixtureText=[string](Get-Content -LiteralPath $fixture -Raw -Encoding UTF8)
        }
        $fixtureVersion=Get-NrVersionFromReleaseLocator -Text $fixtureText
        if (-not $fixtureVersion) { throw 'NEXROUTE_LATEST_RELEASE_FIXTURE does not contain a stable NexRoute release URL.' }
        return $fixtureVersion
    }

    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch { }

    $latestUri='https://github.com/Onmaynec/NexRoute/releases/latest'
    $errors=New-Object 'System.Collections.Generic.List[string]'

    try {
        $response=Invoke-WebRequest -Uri $latestUri -UseBasicParsing -MaximumRedirection 10 -TimeoutSec 20 -Headers @{
            'User-Agent'='NexRoute-Updater-Fallback/0.6.2'
            'Cache-Control'='no-cache'
        }
        $candidates=New-Object 'System.Collections.Generic.List[string]'
        try { $candidates.Add([string]$response.BaseResponse.ResponseUri.AbsoluteUri) } catch { }
        try { $candidates.Add([string]$response.BaseResponse.RequestMessage.RequestUri.AbsoluteUri) } catch { }
        try { $candidates.Add([string]$response.Headers.Location) } catch { }
        try { $candidates.Add([string]$response.Content) } catch { }
        foreach ($candidate in $candidates) {
            $version=Get-NrVersionFromReleaseLocator -Text $candidate
            if ($version) { return $version }
        }
        $errors.Add('Invoke-WebRequest returned no stable release tag.')
    } catch {
        $errors.Add('Invoke-WebRequest: '+$_.Exception.Message)
    }

    $webResponse=$null
    $reader=$null
    try {
        $request=[Net.HttpWebRequest]::Create($latestUri)
        $request.Method='GET'
        $request.AllowAutoRedirect=$true
        $request.UserAgent='NexRoute-Updater-Fallback/0.6.2'
        $request.Timeout=20000
        $request.ReadWriteTimeout=20000
        $webResponse=$request.GetResponse()
        $version=Get-NrVersionFromReleaseLocator -Text ([string]$webResponse.ResponseUri.AbsoluteUri)
        if ($version) { return $version }
        $reader=New-Object IO.StreamReader($webResponse.GetResponseStream())
        $version=Get-NrVersionFromReleaseLocator -Text $reader.ReadToEnd()
        if ($version) { return $version }
        $errors.Add('HttpWebRequest returned no stable release tag.')
    } catch {
        $errors.Add('HttpWebRequest: '+$_.Exception.Message)
    } finally {
        if ($reader) { $reader.Dispose() }
        if ($webResponse) { $webResponse.Close() }
    }

    $curl=Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        $tempFile=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-latest-'+[guid]::NewGuid().ToString('N')+'.html')
        try {
            $curlOutput=& $curl.Source '--silent' '--show-error' '--location' '--max-time' '20' '--output' $tempFile '--write-out' '%{url_effective}' $latestUri 2>&1
            $curlCode=$LASTEXITCODE
            $locator=(($curlOutput | ForEach-Object { [string]$_ }) -join [Environment]::NewLine)
            if (Test-Path -LiteralPath $tempFile -PathType Leaf) {
                $locator += [Environment]::NewLine + [string](Get-Content -LiteralPath $tempFile -Raw -Encoding UTF8)
            }
            $version=Get-NrVersionFromReleaseLocator -Text $locator
            if ($curlCode -eq 0 -and $version) { return $version }
            $errors.Add("curl.exe returned exit code $curlCode without a stable release tag.")
        } catch {
            $errors.Add('curl.exe: '+$_.Exception.Message)
        } finally {
            Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
        }
    }

    $details=($errors | Select-Object -First 3) -join ' | '
    throw "Unable to resolve the latest stable NexRoute release without the GitHub API. $details"
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
        (New-Object Text.UTF8Encoding($false))
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
    if (-not $effectiveMetadata -and $needsRelease) {
        $latestVersion=Resolve-NrPublicLatestReleaseVersion
        $temporaryMetadata=New-NrFallbackReleaseMetadata -Version $latestVersion
        $effectiveMetadata=$temporaryMetadata
    }

    $result=Invoke-NrUpdaterCore -MetadataPath $effectiveMetadata
    foreach ($line in @($result.output)) { Write-Output $line }
    exit ([int]$result.exitCode)
} finally {
    if ($temporaryMetadata) {
        Remove-Item -LiteralPath $temporaryMetadata -Force -ErrorAction SilentlyContinue
    }
}
