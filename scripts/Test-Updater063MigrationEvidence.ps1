[CmdletBinding()]
param(
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

if ($env:OS -ne 'Windows_NT') {
    throw 'The NexRoute 0.6.2 -> 0.6.3 migration evidence gate must run on Windows.'
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$updater = Join-Path $repositoryRoot 'overlay/.service/nexroute-updater.ps1'
if (-not (Test-Path -LiteralPath $updater -PathType Leaf)) { throw "Updater under test is missing: $updater" }

function Copy-NrTree064 {
    param([Parameter(Mandatory)][string]$Source,[Parameter(Mandatory)][string]$Destination)
    if (-not (Test-Path -LiteralPath $Destination -PathType Container)) { New-Item -ItemType Directory -Path $Destination -Force | Out-Null }
    foreach ($item in @(Get-ChildItem -LiteralPath $Source -Force -ErrorAction Stop)) {
        $target = Join-Path $Destination $item.Name
        if ($item.PSIsContainer) { Copy-NrTree064 -Source $item.FullName -Destination $target }
        else { Copy-Item -LiteralPath $item.FullName -Destination $target -Force }
    }
}

function Receive-NrReleaseAsset064 {
    param([Parameter(Mandatory)][string]$Version,[Parameter(Mandatory)][string]$Directory)
    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    $archiveName = "NexRoute-$Version-win-x64.zip"
    $archive = Join-Path $Directory $archiveName
    $checksum = "$archive.sha256"
    $base = "https://github.com/Onmaynec/NexRoute/releases/download/v$Version"
    Invoke-WebRequest -Uri "$base/$archiveName" -OutFile $archive -UseBasicParsing -TimeoutSec 120 -Headers @{ 'User-Agent'='NexRoute-Migration-Evidence/0.6.4'; 'Cache-Control'='no-cache' }
    Invoke-WebRequest -Uri "$base/$archiveName.sha256" -OutFile $checksum -UseBasicParsing -TimeoutSec 60 -Headers @{ 'User-Agent'='NexRoute-Migration-Evidence/0.6.4'; 'Cache-Control'='no-cache' }

    $line = (Get-Content -LiteralPath $checksum -Encoding ASCII | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1).Trim()
    $match = [regex]::Match($line, '^(?<sha>[0-9a-fA-F]{64})\s+\*?(?<name>NexRoute-\d+\.\d+\.\d+-win-x64\.zip)$')
    if (-not $match.Success -or $match.Groups['name'].Value -ne $archiveName) { throw "Published checksum format is invalid for $archiveName." }
    $expected = $match.Groups['sha'].Value.ToLowerInvariant()
    $actual = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) { throw "Published $archiveName SHA-256 mismatch." }
    return [pscustomobject]@{ Archive=$archive; ArchiveName=$archiveName; Sha256=$actual; Directory=$Directory }
}

function Find-NrPackageRoot064 {
    param([Parameter(Mandatory)][string]$ExtractDirectory,[Parameter(Mandatory)][string]$Version)
    $candidates = @()
    if ((Test-Path -LiteralPath (Join-Path $ExtractDirectory '.service/version.txt') -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $ExtractDirectory 'nexroute.bat') -PathType Leaf)) {
        $candidates += $ExtractDirectory
    }
    $candidates += @(Get-ChildItem -LiteralPath $ExtractDirectory -Filter version.txt -File -Recurse -ErrorAction Stop | Where-Object { $_.Directory.Name -eq '.service' } | ForEach-Object { Split-Path -Parent $_.Directory.FullName } | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'nexroute.bat') -PathType Leaf } | Select-Object -Unique)
    $matches = @($candidates | Where-Object { (Get-Content -LiteralPath (Join-Path $_ '.service/version.txt') -Raw -Encoding UTF8).Trim() -eq $Version } | Select-Object -Unique)
    if ($matches.Count -ne 1) { throw "Expected exactly one NexRoute $Version package root, got $($matches.Count)." }
    return [IO.Path]::GetFullPath($matches[0])
}

function New-NrInstalledCopy064 {
    param([Parameter(Mandatory)][string]$Archive,[Parameter(Mandatory)][string]$Version,[Parameter(Mandatory)][string]$Path)
    $extract = "$Path-extract"
    New-Item -ItemType Directory -Path $extract -Force | Out-Null
    Expand-Archive -LiteralPath $Archive -DestinationPath $extract -Force
    $source = Find-NrPackageRoot064 -ExtractDirectory $extract -Version $Version
    Copy-NrTree064 -Source $source -Destination $Path
    Remove-Item -LiteralPath $extract -Recurse -Force -ErrorAction SilentlyContinue

    New-Item -ItemType Directory -Path (Join-Path $Path '.service/history') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $Path '.service/language.txt'),"RU`r`n",[Text.Encoding]::ASCII)
    [IO.File]::WriteAllText((Join-Path $Path '.service/custom-services.json'),'{"services":[{"id":"migration-evidence"}]}' + [Environment]::NewLine,[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $Path '.service/history/strategy-switches.jsonl'),'{"strategy":"migration-evidence"}' + [Environment]::NewLine,[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $Path 'lists/list-general-user.txt'),"migration-evidence.example`r`n",[Text.UTF8Encoding]::new($false))
    return $Path
}

function Get-NrPreservedHashes064 {
    param([Parameter(Mandatory)][string]$Root)
    $result = [ordered]@{}
    foreach ($relative in @('.service/language.txt','.service/custom-services.json','.service/history/strategy-switches.jsonl','lists/list-general-user.txt')) {
        $path = Join-Path $Root $relative
        $result[$relative] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    return $result
}

function Assert-NrPreserved064 {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)]$Expected)
    foreach ($relative in $Expected.Keys) {
        $actual = (Get-FileHash -LiteralPath (Join-Path $Root $relative) -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne [string]$Expected[$relative]) { throw "Preserved state changed for $relative." }
    }
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('NexRoute migration Тест 0.6.2 '+[guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $source62 = Receive-NrReleaseAsset064 -Version '0.6.2' -Directory (Join-Path $work 'release-0.6.2')
    $source63 = Receive-NrReleaseAsset064 -Version '0.6.3' -Directory (Join-Path $work 'release-0.6.3')

    $metadataPath = Join-Path $work 'release-0.6.3.json'
    $base63 = 'https://github.com/Onmaynec/NexRoute/releases/download/v0.6.3'
    [ordered]@{
        tag_name='v0.6.3'; draft=$false; prerelease=$false; published_at=$null; html_url='https://github.com/Onmaynec/NexRoute/releases/tag/v0.6.3';
        assets=@(
            [ordered]@{ name=$source63.ArchiveName; browser_download_url="$base63/$($source63.ArchiveName)" },
            [ordered]@{ name="$($source63.ArchiveName).sha256"; browser_download_url="$base63/$($source63.ArchiveName).sha256" }
        )
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $metadataPath -Encoding UTF8

    $installed = Join-Path $work 'Installed NexRoute Кириллица'
    New-NrInstalledCopy064 -Archive $source62.Archive -Version '0.6.2' -Path $installed | Out-Null
    $before = Get-NrPreservedHashes064 -Root $installed
    if ((Get-Content -LiteralPath (Join-Path $installed '.service/version.txt') -Raw -Encoding UTF8).Trim() -ne '0.6.2') { throw 'Real v0.6.2 install fixture has an unexpected version.' }

    $installOutput = & $updater -Mode Install -Root $installed -ReleaseMetadataPath $metadataPath -AssetDirectory $source63.Directory -Json
    $install = ($installOutput | Select-Object -Last 1) | ConvertFrom-Json
    if ([string]$install.Status -ne 'updated' -or [string]$install.CurrentVersion -ne '0.6.3') { throw 'Real 0.6.2 -> 0.6.3 migration did not finish as updated.' }
    if ([string]$install.PackageSha256 -ne [string]$source63.Sha256) { throw 'Migration package SHA-256 differs from published v0.6.3 asset.' }
    Assert-NrPreserved064 -Root $installed -Expected $before

    $secondOutput = & $updater -Mode Install -Root $installed -ReleaseMetadataPath $metadataPath -AssetDirectory $source63.Directory -Json
    $second = ($secondOutput | Select-Object -Last 1) | ConvertFrom-Json
    if ([string]$second.Status -ne 'current' -or [bool]$second.Updated) { throw 'Second migration run was not idempotent.' }
    Assert-NrPreserved064 -Root $installed -Expected $before

    $rollbackRoot = Join-Path $work 'Rollback NexRoute Кириллица'
    New-NrInstalledCopy064 -Archive $source62.Archive -Version '0.6.2' -Path $rollbackRoot | Out-Null
    $rollbackBefore = Get-NrPreservedHashes064 -Root $rollbackRoot
    $oldFailure = $env:NEXROUTE_UPDATE_FORCE_HEALTH_FAILURE
    $env:NEXROUTE_UPDATE_FORCE_HEALTH_FAILURE = '1'
    $forcedFailureObserved = $false
    try {
        try {
            & $updater -Mode Install -Root $rollbackRoot -ReleaseMetadataPath $metadataPath -AssetDirectory $source63.Directory -Json | Out-Null
        } catch {
            if ($_.Exception.Message -notmatch 'post-update health check') { throw }
            $forcedFailureObserved = $true
        }
    } finally {
        $env:NEXROUTE_UPDATE_FORCE_HEALTH_FAILURE = $oldFailure
    }
    if (-not $forcedFailureObserved) { throw 'Forced post-update health-check failure did not fail the transaction.' }
    if ((Get-Content -LiteralPath (Join-Path $rollbackRoot '.service/version.txt') -Raw -Encoding UTF8).Trim() -ne '0.6.2') { throw 'Forced health-check failure did not restore v0.6.2.' }
    Assert-NrPreserved064 -Root $rollbackRoot -Expected $rollbackBefore

    $evidence = [ordered]@{
        schemaVersion = 1
        product = 'NexRoute'
        gate = 'real-updater-migration-0.6.2-to-0.6.3'
        status = 'passed'
        updaterUnderTest = 'current-source-tree'
        fromVersion = '0.6.2'
        toVersion = '0.6.3'
        fromPackageSha256 = [string]$source62.Sha256
        toPackageSha256 = [string]$source63.Sha256
        installStatus = [string]$install.Status
        secondRunStatus = [string]$second.Status
        forcedHealthFailureRollback = $forcedFailureObserved
        rollbackVersion = '0.6.2'
        preservedState = @($before.Keys)
        pathHasSpaces = $true
        pathHasNonAscii = $true
        absolutePathPublished = $false
    }

    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
        $parent = Split-Path -Parent $OutputPath
        if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        [IO.File]::WriteAllText($OutputPath,(($evidence | ConvertTo-Json -Depth 10 -Compress)+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
    }
    [pscustomobject]$evidence
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
