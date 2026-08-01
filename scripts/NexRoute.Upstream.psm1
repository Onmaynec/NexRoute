Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-NexRouteJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Value
    )

    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $json = $Value | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText(
        $Path,
        $json + [Environment]::NewLine,
        (New-Object System.Text.UTF8Encoding($false))
    )
}

function Get-NexRouteSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "File not found for SHA-256: $Path"
    }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-NexRouteSafeRelativePath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $normalized = $Path.Replace('\', '/')
    if ($normalized.StartsWith('/')) { return $false }
    if ($normalized -match '^[A-Za-z]:') { return $false }
    if ($normalized -match '(^|/)\.\.(/|$)') { return $false }
    return -not [System.IO.Path]::IsPathRooted($Path)
}

function Read-NexRouteUpstreamManifest {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Upstream manifest was not found: $Path"
    }

    try {
        $manifest = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        throw "Unable to parse upstream manifest '$Path': $($_.Exception.Message)"
    }

    if ([int]$manifest.schemaVersion -ne 1) {
        throw "Unsupported upstream manifest schema: $($manifest.schemaVersion)"
    }
    if ([string]$manifest.repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') {
        throw 'Upstream repository must use owner/name format.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$manifest.tag)) {
        throw 'Upstream manifest tag is required.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$manifest.assetPattern)) {
        throw 'Upstream manifest assetPattern is required.'
    }
    try { [void][regex]::new([string]$manifest.assetPattern) }
    catch { throw "Invalid upstream assetPattern: $($_.Exception.Message)" }

    if ([long]$manifest.minimumBytes -lt 1) {
        throw 'Upstream minimumBytes must be greater than zero.'
    }

    $expectedSha256 = ([string]$manifest.expectedSha256).Trim().ToLowerInvariant()
    if ($expectedSha256 -and $expectedSha256 -notmatch '^[0-9a-f]{64}$') {
        throw 'Upstream expectedSha256 must be empty or contain 64 hexadecimal characters.'
    }

    $requiredPaths = @($manifest.requiredPaths | ForEach-Object { [string]$_ })
    if ($requiredPaths.Count -eq 0) {
        throw 'Upstream manifest must define requiredPaths.'
    }
    foreach ($relativePath in $requiredPaths) {
        if (-not (Test-NexRouteSafeRelativePath -Path $relativePath)) {
            throw "Unsafe upstream required path: $relativePath"
        }
    }
    if (($requiredPaths | Sort-Object -Unique).Count -ne $requiredPaths.Count) {
        throw 'Upstream requiredPaths contains duplicates.'
    }

    return [pscustomobject]@{
        schemaVersion = 1
        repository = [string]$manifest.repository
        tag = [string]$manifest.tag
        assetPattern = [string]$manifest.assetPattern
        minimumBytes = [long]$manifest.minimumBytes
        expectedSha256 = $expectedSha256
        requiredPaths = $requiredPaths
    }
}

function Test-NexRouteUpstreamArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ArchivePath,
        [Parameter(Mandatory)][string[]]$RequiredPaths,
        [Parameter(Mandatory)][string]$WorkingDirectory
    )

    if (Test-Path -LiteralPath $WorkingDirectory) {
        Remove-Item -LiteralPath $WorkingDirectory -Recurse -Force
    }
    New-Item -ItemType Directory -Path $WorkingDirectory -Force | Out-Null

    try {
        Expand-Archive -LiteralPath $ArchivePath -DestinationPath $WorkingDirectory -Force
    }
    catch {
        throw "Unable to expand upstream archive: $($_.Exception.Message)"
    }

    $serviceFiles = @(Get-ChildItem -LiteralPath $WorkingDirectory -Filter 'service.bat' -File -Recurse | Where-Object {
        Test-Path -LiteralPath (Join-Path $_.Directory.FullName 'general.bat') -PathType Leaf
    })
    if ($serviceFiles.Count -ne 1) {
        throw "Expected exactly one upstream distribution root, got $($serviceFiles.Count)."
    }

    $root = $serviceFiles[0].Directory.FullName
    foreach ($relativePath in $RequiredPaths) {
        $candidate = Join-Path $root $relativePath
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            throw "The upstream archive is incomplete. Missing: $relativePath"
        }
    }

    $strategies = @(Get-ChildItem -LiteralPath $root -Filter '*.bat' -File | Where-Object {
        $_.Name -notin @('service.bat', 'nexroute.bat')
    })

    return [pscustomobject]@{
        Root = $root
        StrategyCount = $strategies.Count
        RequiredPathCount = $RequiredPaths.Count
    }
}

function Resolve-NexRouteUpstreamArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [string]$ArchivePath,
        [switch]$AllowUnlocked
    )

    if (Test-Path -LiteralPath $WorkingDirectory) {
        Remove-Item -LiteralPath $WorkingDirectory -Recurse -Force
    }
    New-Item -ItemType Directory -Path $WorkingDirectory -Force | Out-Null

    $headers = @{
        Accept = 'application/vnd.github+json'
        'User-Agent' = 'NexRoute-Upstream-Resolver'
        'X-GitHub-Api-Version' = '2022-11-28'
    }
    $releaseApiUrl = "https://api.github.com/repos/$($Manifest.repository)/releases/tags/$($Manifest.tag)"
    $resolvedArchive = Join-Path $WorkingDirectory 'upstream.zip'
    $assetName = $null
    $assetId = $null
    $assetSizeFromApi = $null
    $apiDigest = $null
    $resolutionMode = $null

    if ($ArchivePath) {
        if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
            throw "Offline upstream archive was not found: $ArchivePath"
        }
        Copy-Item -LiteralPath $ArchivePath -Destination $resolvedArchive -Force
        $assetName = Split-Path -Leaf $ArchivePath
        if ($assetName -notmatch [string]$Manifest.assetPattern) {
            throw "Offline upstream archive name does not match assetPattern: $assetName"
        }
        $resolutionMode = 'offline'
    }
    else {
        $release = Microsoft.PowerShell.Utility\Invoke-RestMethod -Uri $releaseApiUrl -Headers $headers -Method Get
        $assets = @($release.assets | Where-Object {
            $_.browser_download_url -and ([string]$_.name -match [string]$Manifest.assetPattern)
        })
        if ($assets.Count -ne 1) {
            throw "Expected exactly one upstream release asset, got $($assets.Count)."
        }
        $asset = $assets[0]
        $assetName = [string]$asset.name
        $assetId = $asset.id
        $assetSizeFromApi = $asset.size
        $apiDigest = ([string]$asset.digest).Trim().ToLowerInvariant()
        Microsoft.PowerShell.Utility\Invoke-WebRequest `
            -Uri ([string]$asset.browser_download_url) `
            -Headers $headers `
            -OutFile $resolvedArchive `
            -UseBasicParsing
        $resolutionMode = 'online'
    }

    $archiveInfo = Get-Item -LiteralPath $resolvedArchive
    if ($archiveInfo.Length -lt [long]$Manifest.minimumBytes) {
        throw "Upstream archive is unexpectedly small: $($archiveInfo.Length) bytes."
    }

    $sha256 = Get-NexRouteSha256 -Path $resolvedArchive
    if (-not $Manifest.expectedSha256 -and -not $AllowUnlocked) {
        throw 'Upstream manifest is unlocked. Set expectedSha256 before release builds.'
    }
    if ($Manifest.expectedSha256 -and $sha256 -ne [string]$Manifest.expectedSha256) {
        throw "Upstream SHA-256 mismatch. Expected $($Manifest.expectedSha256), got $sha256."
    }
    if ($apiDigest -match '^sha256:([0-9a-f]{64})$' -and $sha256 -ne $Matches[1]) {
        throw "GitHub asset digest mismatch. API reports $apiDigest, downloaded $sha256."
    }
    if ($assetSizeFromApi -and [long]$assetSizeFromApi -ne $archiveInfo.Length) {
        throw "GitHub asset size mismatch. API reports $assetSizeFromApi, downloaded $($archiveInfo.Length)."
    }

    $validation = Test-NexRouteUpstreamArchive `
        -ArchivePath $resolvedArchive `
        -RequiredPaths $Manifest.requiredPaths `
        -WorkingDirectory (Join-Path $WorkingDirectory 'validation')

    $lock = [ordered]@{
        schemaVersion = 1
        repository = [string]$Manifest.repository
        tag = [string]$Manifest.tag
        assetName = [string]$assetName
        assetSize = [long]$archiveInfo.Length
        sha256 = $sha256
        requiredPaths = @($Manifest.requiredPaths)
        strategyCount = [int]$validation.StrategyCount
    }

    return [pscustomobject]@{
        ArchivePath = $resolvedArchive
        ReleaseApiUrl = $releaseApiUrl
        ResolutionMode = $resolutionMode
        AssetId = $assetId
        ApiDigest = $apiDigest
        Lock = $lock
    }
}

function New-NexRouteProxyRelease {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$ResolvedUpstream,
        [Parameter(Mandatory)][string]$ProxyAssetUrl
    )

    return [pscustomobject]@{
        assets = @(
            [pscustomobject]@{
                id = $ResolvedUpstream.AssetId
                name = [string]$ResolvedUpstream.Lock.assetName
                size = [long]$ResolvedUpstream.Lock.assetSize
                digest = ('sha256:{0}' -f $ResolvedUpstream.Lock.sha256)
                browser_download_url = $ProxyAssetUrl
            }
        )
    }
}

Export-ModuleMember -Function @(
    'Write-NexRouteJson',
    'Get-NexRouteSha256',
    'Test-NexRouteSafeRelativePath',
    'Read-NexRouteUpstreamManifest',
    'Test-NexRouteUpstreamArchive',
    'Resolve-NexRouteUpstreamArchive',
    'New-NexRouteProxyRelease'
)
