Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Get-NrLatestStableReleaseForAttestation {
    [CmdletBinding()]
    param([string]$MetadataPath)
    if ($MetadataPath) {
        if (-not (Test-Path -LiteralPath $MetadataPath -PathType Leaf)) { throw "Release metadata is missing: $MetadataPath" }
        $release=Get-Content -LiteralPath $MetadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } else {
        $release=Invoke-RestMethod -Uri 'https://api.github.com/repos/Onmaynec/NexRoute/releases/latest' -Headers @{
            Accept='application/vnd.github+json'
            'User-Agent'='NexRoute-Attestation/0.6.0'
            'X-GitHub-Api-Version'='2022-11-28'
        } -TimeoutSec 30
    }
    if (-not $release) { throw 'GitHub returned no release metadata.' }
    if ([bool]$release.draft -or [bool]$release.prerelease) { throw 'Latest release is not a stable release.' }
    $tag=[string]$release.tag_name
    if ($tag -notmatch '^v\d+\.\d+\.\d+$') { throw "Release tag is invalid: $tag" }
    return $release
}

function Get-NrReleaseAttestationAssets {
    param([Parameter(Mandatory)]$Release)
    $version=([string]$Release.tag_name).TrimStart('v')
    $archiveName="NexRoute-$version-win-x64.zip"
    $checksumName="$archiveName.sha256"
    $archive=@($Release.assets | Where-Object { [string]$_.name -eq $archiveName })
    $checksum=@($Release.assets | Where-Object { [string]$_.name -eq $checksumName })
    if ($archive.Count -ne 1) { throw "Release must contain exactly one archive asset named $archiveName." }
    if ($checksum.Count -ne 1) { throw "Release must contain exactly one checksum asset named $checksumName." }
    foreach ($asset in @($archive[0],$checksum[0])) {
        $uri=[string]$asset.browser_download_url
        if ($uri -notmatch ('^https://github\.com/Onmaynec/NexRoute/releases/download/'+[regex]::Escape([string]$Release.tag_name)+'/')) {
            throw "Release asset URL is not an immutable NexRoute release URL: $uri"
        }
    }
    return [pscustomobject]@{ version=$version; archiveName=$archiveName; checksumName=$checksumName; archive=$archive[0]; checksum=$checksum[0] }
}

function Test-NrReleaseChecksumFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ArchivePath,[Parameter(Mandatory)][string]$ChecksumPath)
    if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) { throw "Release archive is missing: $ArchivePath" }
    if (-not (Test-Path -LiteralPath $ChecksumPath -PathType Leaf)) { throw "Release checksum file is missing: $ChecksumPath" }
    $line=(Get-Content -LiteralPath $ChecksumPath -Raw -Encoding ASCII).Trim()
    if ($line -notmatch '^([0-9a-fA-F]{64})\s+\*?(.+)$') { throw 'Release checksum file has an invalid format.' }
    $expected=$matches[1].ToLowerInvariant()
    $listedName=$matches[2].Trim()
    $archiveName=Split-Path $ArchivePath -Leaf
    if ($listedName -ne $archiveName) { throw "Release checksum names '$listedName' instead of '$archiveName'." }
    $actual=(Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) { throw "Release archive SHA-256 mismatch: expected $expected, got $actual" }
    return [pscustomobject]@{ verified=$true; sha256=$actual; archiveName=$archiveName }
}

function Invoke-NrReleaseAttestationVerification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [object]$Release,
        [string]$MetadataPath,
        [string]$AssetDirectory,
        [string]$PortableArchivePath,
        [scriptblock]$Downloader,
        [scriptblock]$VerifierResolver,
        [scriptblock]$SubjectVerifier
    )
    $rootPath=[IO.Path]::GetFullPath($Root)
    if (-not $Release) { $Release=Get-NrLatestStableReleaseForAttestation -MetadataPath $MetadataPath }
    else {
        if ([bool]$Release.draft -or [bool]$Release.prerelease) { throw 'Latest release is not a stable release.' }
        if ([string]$Release.tag_name -notmatch '^v\d+\.\d+\.\d+$') { throw "Release tag is invalid: $($Release.tag_name)" }
    }
    $assets=Get-NrReleaseAttestationAssets -Release $Release
    $temporary=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-attestation-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temporary -Force | Out-Null
    try {
        $archivePath=Join-Path $temporary $assets.archiveName
        $checksumPath=Join-Path $temporary $assets.checksumName
        foreach ($pair in @(
            [pscustomobject]@{ asset=$assets.archive; destination=$archivePath }
            [pscustomobject]@{ asset=$assets.checksum; destination=$checksumPath }
        )) {
            if ($AssetDirectory) {
                $source=Join-Path $AssetDirectory ([string]$pair.asset.name)
                if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Release fixture asset is missing: $source" }
                Copy-Item -LiteralPath $source -Destination $pair.destination -Force
            } elseif ($Downloader) {
                & $Downloader $pair.asset $pair.destination
            } else {
                Invoke-WebRequest -Uri ([string]$pair.asset.browser_download_url) -OutFile $pair.destination -UseBasicParsing -TimeoutSec 180 -Headers @{
                    Accept='application/octet-stream'
                    'User-Agent'='NexRoute-Attestation/0.6.0'
                }
            }
            if (-not (Test-Path -LiteralPath $pair.destination -PathType Leaf)) { throw "Release asset download produced no file: $($pair.asset.name)" }
        }

        $checksum=Test-NrReleaseChecksumFile -ArchivePath $archivePath -ChecksumPath $checksumPath
        if ($VerifierResolver) { $portable=& $VerifierResolver $rootPath $PortableArchivePath }
        else { $portable=Get-NrPortableGithubCli -Root $rootPath -ArchivePath $PortableArchivePath }
        if (-not $portable -or [string]::IsNullOrWhiteSpace([string]$portable.executable)) { throw 'Portable attestation verifier resolver returned no executable.' }
        $verifiedSubjects=New-Object 'System.Collections.Generic.List[object]'
        foreach ($subject in @($archivePath,$checksumPath)) {
            if ($SubjectVerifier) { $verification=& $SubjectVerifier ([string]$portable.executable) $subject 'Onmaynec/NexRoute' }
            else { $verification=Invoke-NrGithubAttestationVerify -VerifierPath ([string]$portable.executable) -SubjectPath $subject -Repository 'Onmaynec/NexRoute' }
            if (-not $verification -or -not [bool]$verification.verified) { throw "Attestation verifier did not confirm subject: $(Split-Path $subject -Leaf)" }
            $verifiedSubjects.Add($verification)
        }
        return [pscustomobject]@{
            verified=$true
            version=$assets.version
            archiveName=$assets.archiveName
            checksumName=$assets.checksumName
            sha256=$checksum.sha256
            verifier=[string]$portable.executable
            verifierCached=$(if ($portable.PSObject.Properties['cached']) { [bool]$portable.cached } else { $false })
            subjects=$verifiedSubjects.ToArray()
        }
    } finally {
        Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-NrAttestationVerification {
    Write-NrHeader -Title (T 'attestation')
    try {
        Write-Host '  Resolving pinned portable verifier and release provenance...' -ForegroundColor Cyan
        $result=Invoke-NrReleaseAttestationVerification -Root $script:NrRoot
        $script:NrState.lastAttestationStatus='verified'
        Save-NrState
        Show-NrMessage -Title (T 'attestation') -Message ("Verified release v{0}, SHA-256 {1}, archive and checksum attestations." -f $result.version,$result.sha256) -Color Green
    } catch {
        $script:NrState.lastAttestationStatus='failed'
        Save-NrState
        Write-NrLog -Level ERROR -Message 'Portable release attestation verification failed' -Data @{ error=$_.Exception.Message }
        Show-NrMessage -Title (T 'operationFailed') -Message $_.Exception.Message -Color Red
    }
}
