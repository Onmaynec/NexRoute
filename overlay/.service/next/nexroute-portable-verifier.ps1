Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Read-NrPortableToolsManifest {
    [CmdletBinding()]
    param([string]$Path)
    if (-not $Path) {
        if (-not $script:NrService) { throw 'NexRoute service directory is not initialized.' }
        $Path=Join-Path $script:NrService 'portable-tools.json'
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Portable tools manifest is missing: $Path" }
    $manifest=Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$manifest.schemaVersion -ne 1) { throw 'Portable tools manifest schemaVersion must be 1.' }
    $tool=$manifest.tools.githubCli
    if (-not $tool) { throw 'Portable tools manifest has no githubCli definition.' }
    if ([string]$tool.repository -ne 'cli/cli') { throw 'Portable GitHub CLI repository must be cli/cli.' }
    if ([string]$tool.assetUrl -notmatch '^https://github\.com/cli/cli/releases/download/v[0-9]+\.[0-9]+\.[0-9]+/') { throw 'Portable GitHub CLI asset URL is not an official immutable release URL.' }
    if ([string]$tool.sha256 -notmatch '^[0-9a-fA-F]{64}$') { throw 'Portable GitHub CLI SHA-256 is invalid.' }
    if ([long]$tool.minimumBytes -lt 1000000) { throw 'Portable GitHub CLI minimumBytes is unsafe.' }
    if ([string]::IsNullOrWhiteSpace([string]$tool.executableRelativePath)) { throw 'Portable GitHub CLI executable path is missing.' }
    return $tool
}

function Test-NrPortableToolArchive {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Tool)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Portable verifier archive is missing: $Path" }
    $file=Get-Item -LiteralPath $Path
    if ($file.Length -lt [long]$Tool.minimumBytes) { throw "Portable verifier archive is unexpectedly small: $($file.Length) bytes." }
    $actual=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    $expected=([string]$Tool.sha256).ToLowerInvariant()
    if ($actual -ne $expected) { throw "Portable verifier SHA-256 mismatch: expected $expected, got $actual" }
    return [pscustomobject]@{ path=$file.FullName; size=$file.Length; sha256=$actual }
}

function Expand-NrPortableToolArchive {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ArchivePath,[Parameter(Mandatory)][string]$Destination)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $destinationRoot=[IO.Path]::GetFullPath($Destination)
    if (Test-Path -LiteralPath $destinationRoot) { Remove-Item -LiteralPath $destinationRoot -Recurse -Force }
    New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
    $prefix=$destinationRoot.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
    $archive=[IO.Compression.ZipFile]::OpenRead([IO.Path]::GetFullPath($ArchivePath))
    try {
        foreach ($entry in $archive.Entries) {
            $relative=([string]$entry.FullName).Replace('\','/')
            if ([string]::IsNullOrWhiteSpace($relative)) { continue }
            if ($relative.StartsWith('/') -or $relative -match '^[A-Za-z]:' -or @($relative.Split('/') | Where-Object { $_ -eq '..' }).Count -gt 0) {
                throw "Unsafe portable verifier archive entry: $relative"
            }
            $target=[IO.Path]::GetFullPath((Join-Path $destinationRoot $relative))
            if (-not $target.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -and $target -ne $destinationRoot) {
                throw "Portable verifier archive entry escapes its destination: $relative"
            }
            if ([string]::IsNullOrEmpty($entry.Name)) {
                New-Item -ItemType Directory -Path $target -Force | Out-Null
                continue
            }
            $parent=Split-Path -Parent $target
            if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$target,$true)
        }
    } finally { $archive.Dispose() }
    return $destinationRoot
}

function Test-NrPortableGithubCliCache {
    param([Parameter(Mandatory)][string]$CacheDirectory,[Parameter(Mandatory)]$Tool,[switch]$SkipVersionProbe)
    $receiptPath=Join-Path $CacheDirectory 'verified-tool.json'
    $executable=Join-Path $CacheDirectory ([string]$Tool.executableRelativePath)
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf) -or -not (Test-Path -LiteralPath $executable -PathType Leaf)) { return $null }
    try {
        $receipt=Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([int]$receipt.schemaVersion -ne 1 -or [string]$receipt.version -ne [string]$Tool.version -or [string]$receipt.archiveSha256 -ne ([string]$Tool.sha256).ToLowerInvariant()) { return $null }
        $actualExecutableSha=(Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualExecutableSha -ne [string]$receipt.executableSha256) { return $null }
        if (-not $SkipVersionProbe -and $env:OS -eq 'Windows_NT') {
            $versionOutput=@(& $executable --version 2>&1) -join "`n"
            if ($LASTEXITCODE -ne 0 -or $versionOutput -notmatch ('gh version\s+'+[regex]::Escape([string]$Tool.version)+'(?:\s|$)')) { return $null }
        }
        return [pscustomobject]@{ executable=[IO.Path]::GetFullPath($executable); receipt=$receiptPath; executableSha256=$actualExecutableSha; cached=$true }
    } catch { return $null }
}

function Get-NrPortableGithubCli {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$ManifestPath,
        [string]$ArchivePath,
        [switch]$SkipVersionProbe
    )
    $rootPath=[IO.Path]::GetFullPath($Root)
    if (-not $ManifestPath) { $ManifestPath=Join-Path $rootPath '.service/portable-tools.json' }
    $tool=Read-NrPortableToolsManifest -Path $ManifestPath
    $cacheDirectory=Join-Path $rootPath ('.service/tools/github-cli/'+[string]$Tool.version)
    $cached=Test-NrPortableGithubCliCache -CacheDirectory $cacheDirectory -Tool $tool -SkipVersionProbe:$SkipVersionProbe
    if ($cached) { return $cached }

    $toolsRoot=Split-Path -Parent $cacheDirectory
    if (-not (Test-Path -LiteralPath $toolsRoot -PathType Container)) { New-Item -ItemType Directory -Path $toolsRoot -Force | Out-Null }
    $downloadDirectory=Join-Path $rootPath '.service/tools/downloads'
    if (-not (Test-Path -LiteralPath $downloadDirectory -PathType Container)) { New-Item -ItemType Directory -Path $downloadDirectory -Force | Out-Null }
    $temporaryArchive=Join-Path $downloadDirectory (([string]$tool.assetName)+'.tmp-'+[guid]::NewGuid().ToString('N'))
    $staging=$cacheDirectory+'.staging-'+[guid]::NewGuid().ToString('N')
    try {
        if ($ArchivePath) {
            Copy-Item -LiteralPath $ArchivePath -Destination $temporaryArchive -Force
        } else {
            Invoke-WebRequest -Uri ([string]$tool.assetUrl) -OutFile $temporaryArchive -UseBasicParsing -TimeoutSec 180 -Headers @{
                Accept='application/octet-stream'
                'User-Agent'='NexRoute-Portable-Attestation-Verifier/0.6.0'
            }
        }
        $archive=Test-NrPortableToolArchive -Path $temporaryArchive -Tool $tool
        Expand-NrPortableToolArchive -ArchivePath $temporaryArchive -Destination $staging | Out-Null
        $executable=Join-Path $staging ([string]$tool.executableRelativePath)
        if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) { throw "Portable verifier executable is missing after extraction: $($tool.executableRelativePath)" }
        if (-not $SkipVersionProbe -and $env:OS -eq 'Windows_NT') {
            $versionOutput=@(& $executable --version 2>&1) -join "`n"
            if ($LASTEXITCODE -ne 0 -or $versionOutput -notmatch ('gh version\s+'+[regex]::Escape([string]$tool.version)+'(?:\s|$)')) {
                throw "Portable GitHub CLI version probe failed. Expected $($tool.version)."
            }
        }
        $executableSha=(Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash.ToLowerInvariant()
        $receipt=[ordered]@{
            schemaVersion=1
            verifiedUtc=[DateTime]::UtcNow.ToString('o')
            version=[string]$tool.version
            repository=[string]$tool.repository
            assetName=[string]$tool.assetName
            archiveSha256=[string]$archive.sha256
            executableRelativePath=[string]$tool.executableRelativePath
            executableSha256=$executableSha
        }
        [IO.File]::WriteAllText((Join-Path $staging 'verified-tool.json'),($receipt | ConvertTo-Json -Depth 8)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
        if (Test-Path -LiteralPath $cacheDirectory) { Remove-Item -LiteralPath $cacheDirectory -Recurse -Force }
        Move-Item -LiteralPath $staging -Destination $cacheDirectory -Force
        $verified=Test-NrPortableGithubCliCache -CacheDirectory $cacheDirectory -Tool $tool -SkipVersionProbe:$SkipVersionProbe
        if (-not $verified) { throw 'Portable GitHub CLI cache verification failed after installation.' }
        $verified.cached=$false
        return $verified
    } finally {
        Remove-Item -LiteralPath $temporaryArchive -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-NrGithubAttestationVerify {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$VerifierPath,
        [Parameter(Mandatory)][string]$SubjectPath,
        [string]$Repository='Onmaynec/NexRoute',
        [scriptblock]$Runner
    )
    if (-not (Test-Path -LiteralPath $SubjectPath -PathType Leaf)) { throw "Attestation subject is missing: $SubjectPath" }
    $arguments=[string[]]@('attestation','verify',[IO.Path]::GetFullPath($SubjectPath),'--repo',$Repository,'--signer-repo',$Repository)
    if ($Runner) {
        $result=& $Runner $VerifierPath $arguments
        $exitCode=if ($null -ne $result -and $result.PSObject.Properties['exitCode']) { [int]$result.exitCode } else { 0 }
        $output=if ($null -ne $result -and $result.PSObject.Properties['output']) { [string]$result.output } else { '' }
    } else {
        $output=@(& $VerifierPath @arguments 2>&1) -join [Environment]::NewLine
        $exitCode=$LASTEXITCODE
    }
    if ($exitCode -ne 0) { throw "GitHub attestation verification failed for '$SubjectPath': $output" }
    return [pscustomobject]@{ verified=$true; subject=[IO.Path]::GetFullPath($SubjectPath); repository=$Repository; verifier=[IO.Path]::GetFullPath($VerifierPath); output=$output }
}
