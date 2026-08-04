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
    $validationJsonName="NexRoute-$version-validation.json"
    $validationMarkdownName="NexRoute-$version-validation.md"
    $archive=@($Release.assets | Where-Object { [string]$_.name -eq $archiveName })
    $checksum=@($Release.assets | Where-Object { [string]$_.name -eq $checksumName })
    $validationJson=@($Release.assets | Where-Object { [string]$_.name -eq $validationJsonName })
    $validationMarkdown=@($Release.assets | Where-Object { [string]$_.name -eq $validationMarkdownName })
    if ($archive.Count -ne 1) { throw "Release must contain exactly one archive asset named $archiveName." }
    if ($checksum.Count -ne 1) { throw "Release must contain exactly one checksum asset named $checksumName." }
    if ($validationJson.Count -ne 1) { throw "Release must contain exactly one validation JSON asset named $validationJsonName." }
    if ($validationMarkdown.Count -ne 1) { throw "Release must contain exactly one validation Markdown asset named $validationMarkdownName." }
    foreach ($asset in @($archive[0],$checksum[0],$validationJson[0],$validationMarkdown[0])) {
        $uri=[string]$asset.browser_download_url
        if ($uri -notmatch ('^https://github\.com/Onmaynec/NexRoute/releases/download/'+[regex]::Escape([string]$Release.tag_name)+'/')) {
            throw "Release asset URL is not an immutable NexRoute release URL: $uri"
        }
    }
    return [pscustomobject]@{
        version=$version
        archiveName=$archiveName
        checksumName=$checksumName
        validationJsonName=$validationJsonName
        validationMarkdownName=$validationMarkdownName
        archive=$archive[0]
        checksum=$checksum[0]
        validationJson=$validationJson[0]
        validationMarkdown=$validationMarkdown[0]
    }
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

function Test-NrSignedValidationReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$JsonPath,
        [Parameter(Mandatory)][string]$ExpectedVersion
    )
    if (-not (Test-Path -LiteralPath $JsonPath -PathType Leaf)) { throw "Signed validation report is missing: $JsonPath" }
    $report=Get-Content -LiteralPath $JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$report.schemaVersion -ne 1) { throw 'Signed validation report schemaVersion must be 1.' }
    if ([string]$report.product -ne 'NexRoute') { throw 'Signed validation report product is not NexRoute.' }
    if ([string]$report.version -ne $ExpectedVersion) { throw "Signed validation report version '$($report.version)' does not match release '$ExpectedVersion'." }
    if ([string]$report.overallStatus -notin @('passed','passed-with-limitations')) { throw "Signed validation report is not releasable: $($report.overallStatus)" }
    $checks=@($report.checks)
    if ($checks.Count -lt 1) { throw 'Signed validation report contains no checks.' }
    $ids=@($checks | ForEach-Object { [string]$_.id })
    if (@($ids | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) { throw 'Signed validation report contains a check without an id.' }
    if (@($ids | Sort-Object -Unique).Count -ne $ids.Count) { throw 'Signed validation report contains duplicate check ids.' }
    $failedRequired=@($checks | Where-Object { [bool]$_.required -and [string]$_.status -eq 'failed' })
    if ($failedRequired.Count -gt 0) { throw "Signed validation report contains $($failedRequired.Count) failed required check(s)." }
    foreach ($check in $checks) {
        if ([string]$check.status -notin @('passed','experimental','unsupported','failed')) {
            throw "Signed validation report contains unsupported status '$($check.status)' for '$($check.id)'."
        }
    }
    return [pscustomobject]@{
        valid=$true
        version=[string]$report.version
        overallStatus=[string]$report.overallStatus
        checkCount=$checks.Count
        limitationCount=@($checks | Where-Object { [string]$_.status -in @('experimental','unsupported','failed') }).Count
        sha256=(Get-FileHash -LiteralPath $JsonPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

function Write-NrAttestationUtf8File {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$Content)
    $directory=Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $temporary="$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temporary,$Content,[Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporary -Destination $Path -Force
    } finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
}

function Install-NrSignedValidationReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$JsonPath,
        [Parameter(Mandatory)][string]$MarkdownPath,
        [Parameter(Mandatory)][object]$Validation,
        [Parameter(Mandatory)][string]$Verifier,
        [Parameter(Mandatory)][object[]]$VerifiedSubjects,
        [Parameter(Mandatory)][string]$SourceAssetName
    )
    $serviceDirectory=Join-Path ([IO.Path]::GetFullPath($Root)) '.service'
    New-Item -ItemType Directory -Path $serviceDirectory -Force | Out-Null
    $installedJson=Join-Path $serviceDirectory 'release-validation.json'
    $installedMarkdown=Join-Path $serviceDirectory 'release-validation.md'
    $receiptPath=$installedJson+'.attestation-receipt.json'
    Write-NrAttestationUtf8File -Path $installedJson -Content (Get-Content -LiteralPath $JsonPath -Raw -Encoding UTF8)
    Write-NrAttestationUtf8File -Path $installedMarkdown -Content (Get-Content -LiteralPath $MarkdownPath -Raw -Encoding UTF8)
    $receipt=[ordered]@{
        schemaVersion=1
        verified=$true
        reportSha256=[string]$Validation.sha256
        verifiedAtUtc=[DateTime]::UtcNow.ToString('o')
        verifier=$Verifier
        repository='Onmaynec/NexRoute'
        releaseVersion=[string]$Validation.version
        sourceAssetName=$SourceAssetName
        subjects=@($VerifiedSubjects | ForEach-Object {
            if ($_.PSObject.Properties['subject']) { Split-Path ([string]$_.subject) -Leaf }
            else { 'verified-subject' }
        })
    }
    Write-NrAttestationUtf8File -Path $receiptPath -Content (($receipt | ConvertTo-Json -Depth 8)+[Environment]::NewLine)
    return [pscustomobject]@{
        reportPath=$installedJson
        markdownPath=$installedMarkdown
        receiptPath=$receiptPath
        reportSha256=[string]$Validation.sha256
        overallStatus=[string]$Validation.overallStatus
        checkCount=[int]$Validation.checkCount
        limitationCount=[int]$Validation.limitationCount
    }
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
        $validationJsonPath=Join-Path $temporary $assets.validationJsonName
        $validationMarkdownPath=Join-Path $temporary $assets.validationMarkdownName
        foreach ($pair in @(
            [pscustomobject]@{ asset=$assets.archive; destination=$archivePath }
            [pscustomobject]@{ asset=$assets.checksum; destination=$checksumPath }
            [pscustomobject]@{ asset=$assets.validationJson; destination=$validationJsonPath }
            [pscustomobject]@{ asset=$assets.validationMarkdown; destination=$validationMarkdownPath }
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
        foreach ($subject in @($archivePath,$checksumPath,$validationJsonPath,$validationMarkdownPath)) {
            if ($SubjectVerifier) { $verification=& $SubjectVerifier ([string]$portable.executable) $subject 'Onmaynec/NexRoute' }
            else { $verification=Invoke-NrGithubAttestationVerify -VerifierPath ([string]$portable.executable) -SubjectPath $subject -Repository 'Onmaynec/NexRoute' }
            if (-not $verification -or -not [bool]$verification.verified) { throw "Attestation verifier did not confirm subject: $(Split-Path $subject -Leaf)" }
            $verifiedSubjects.Add($verification)
        }
        $validation=Test-NrSignedValidationReport -JsonPath $validationJsonPath -ExpectedVersion $assets.version
        $installed=Install-NrSignedValidationReport -Root $rootPath -JsonPath $validationJsonPath -MarkdownPath $validationMarkdownPath `
            -Validation $validation -Verifier ([string]$portable.executable) -VerifiedSubjects $verifiedSubjects.ToArray() `
            -SourceAssetName $assets.validationJsonName
        return [pscustomobject]@{
            verified=$true
            version=$assets.version
            archiveName=$assets.archiveName
            checksumName=$assets.checksumName
            validationJsonName=$assets.validationJsonName
            validationMarkdownName=$assets.validationMarkdownName
            sha256=$checksum.sha256
            verifier=[string]$portable.executable
            verifierCached=$(if ($portable.PSObject.Properties['cached']) { [bool]$portable.cached } else { $false })
            subjects=$verifiedSubjects.ToArray()
            validation=$installed
        }
    } finally {
        Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-NrAttestationVerification {
    Write-NrHeader -Title (T 'attestation')
    try {
        Write-Host '  Resolving pinned portable verifier and signed release evidence...' -ForegroundColor Cyan
        $result=Invoke-NrReleaseAttestationVerification -Root $script:NrRoot
        $script:NrState.lastAttestationStatus='verified'
        Save-NrState
        Show-NrMessage -Title (T 'attestation') -Message ("Verified release v{0}, SHA-256 {1}, four attested assets and {2} validation checks. The Validation Viewer receipt is ready." -f $result.version,$result.sha256,$result.validation.checkCount) -Color Green
    } catch {
        $script:NrState.lastAttestationStatus='failed'
        Save-NrState
        Write-NrLog -Level ERROR -Message 'Portable release attestation verification failed' -Data @{ error=$_.Exception.Message }
        Show-NrMessage -Title (T 'operationFailed') -Message $_.Exception.Message -Color Red
    }
}