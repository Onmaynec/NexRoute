[CmdletBinding()]
param(
    [ValidateSet('Auto', 'Check', 'Install', 'Menu', 'Rollback', 'Status')]
    [string]$Mode = 'Menu',
    [string]$Root,
    [string]$ReleaseMetadataPath,
    [string]$AssetDirectory,
    [ValidateRange(1, 168)]
    [int]$CheckIntervalHours = 24,
    [switch]$Force,
    [switch]$Json,
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}
$Root = [System.IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
$serviceDirectory = Join-Path $Root '.service'
$versionPath = Join-Path $serviceDirectory 'version.txt'
$statePath = Join-Path $serviceDirectory 'update-state.json'
$autoFlagPath = Join-Path $Root 'utils\check_updates.enabled'
$languagePath = Join-Path $serviceDirectory 'language.txt'
$backupRoot = Join-Path (Split-Path -Parent $Root) 'NexRoute-backups'
$repository = 'Onmaynec/NexRoute'
$releaseApi = "https://api.github.com/repos/$repository/releases/latest"
$workingRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('nexroute-update-{0}' -f [guid]::NewGuid().ToString('N'))
$mutex = $null
$mutexAcquired = $false

function Get-NexRoutePropertyValue {
    param($InputObject, [Parameter(Mandatory)][string]$Name)
    if ($null -eq $InputObject) { return $null }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function Write-NexRouteUtf8Json {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)]$Value)
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $jsonText = $Value | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText(
        $Path,
        $jsonText + [Environment]::NewLine,
        (New-Object System.Text.UTF8Encoding($false))
    )
}

function Get-NexRouteCurrentVersion {
    if (-not (Test-Path -LiteralPath $versionPath -PathType Leaf)) {
        throw "NexRoute version file was not found: $versionPath"
    }
    $value = (Get-Content -LiteralPath $versionPath -Raw -Encoding UTF8).Trim()
    if ($value -notmatch '^\d+\.\d+\.\d+$') {
        throw "Invalid installed NexRoute version: $value"
    }
    return $value
}

function ConvertTo-NexRouteVersion {
    param([Parameter(Mandatory)][string]$Value)
    $normalized = $Value.Trim()
    if ($normalized.StartsWith('v', [System.StringComparison]::OrdinalIgnoreCase)) {
        $normalized = $normalized.Substring(1)
    }
    if ($normalized -notmatch '^\d+\.\d+\.\d+$') {
        throw "Invalid semantic version: $Value"
    }
    return [version]$normalized
}

function Get-NexRouteLanguage {
    if (Test-Path -LiteralPath $languagePath -PathType Leaf) {
        try {
            $value = (Get-Content -LiteralPath $languagePath -Raw -Encoding ASCII).Trim().ToUpperInvariant()
            if ($value -eq 'RU') { return 'RU' }
        } catch { }
    }
    return 'EN'
}

function New-NexRouteUpdateState {
    return [ordered]@{
        schemaVersion = 1
        repository = $repository
        currentVersion = $null
        latestVersion = $null
        autoEnabled = $false
        lastCheckUtc = $null
        nextCheckUtc = $null
        lastStatus = 'never-checked'
        lastMessage = $null
        lastUpdateUtc = $null
        lastBackupPath = $null
        lastPackageSha256 = $null
    }
}

function Read-NexRouteUpdateState {
    $state = New-NexRouteUpdateState
    if (Test-Path -LiteralPath $statePath -PathType Leaf) {
        try {
            $stored = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($key in @($state.Keys)) {
                $value = Get-NexRoutePropertyValue -InputObject $stored -Name $key
                if ($null -ne $value) { $state[$key] = $value }
            }
        } catch {
            $state.lastStatus = 'state-recovered'
            $state.lastMessage = $_.Exception.Message
        }
    }
    $state.currentVersion = Get-NexRouteCurrentVersion
    $state.autoEnabled = Test-Path -LiteralPath $autoFlagPath -PathType Leaf
    return $state
}

function Save-NexRouteUpdateState {
    param([Parameter(Mandatory)]$State)
    $State.currentVersion = Get-NexRouteCurrentVersion
    $State.autoEnabled = Test-Path -LiteralPath $autoFlagPath -PathType Leaf
    Write-NexRouteUtf8Json -Path $statePath -Value $State
}

function Get-NexRouteLatestRelease {
    if ($ReleaseMetadataPath) {
        if (-not (Test-Path -LiteralPath $ReleaseMetadataPath -PathType Leaf)) {
            throw "Release metadata file was not found: $ReleaseMetadataPath"
        }
        $release = Get-Content -LiteralPath $ReleaseMetadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } else {
        $headers = @{
            Accept = 'application/vnd.github+json'
            'User-Agent' = 'NexRoute-Secure-Updater'
            'X-GitHub-Api-Version' = '2022-11-28'
        }
        $release = Invoke-RestMethod -Uri $releaseApi -Headers $headers -Method Get -TimeoutSec 20
    }

    if ([bool](Get-NexRoutePropertyValue -InputObject $release -Name 'draft')) {
        throw 'The latest GitHub release is a draft.'
    }
    if ([bool](Get-NexRoutePropertyValue -InputObject $release -Name 'prerelease')) {
        throw 'Prerelease builds are not accepted by the stable updater.'
    }

    $tag = [string](Get-NexRoutePropertyValue -InputObject $release -Name 'tag_name')
    if ($tag -notmatch '^v?(\d+\.\d+\.\d+)$') {
        throw "Latest release tag is not a stable semantic version: $tag"
    }
    $latestVersion = $Matches[1]
    $archiveName = "NexRoute-$latestVersion-win-x64.zip"
    $checksumName = "$archiveName.sha256"
    $assetsValue = Get-NexRoutePropertyValue -InputObject $release -Name 'assets'
    $assets = @($assetsValue)
    $archiveAssets = @($assets | Where-Object { [string](Get-NexRoutePropertyValue -InputObject $_ -Name 'name') -eq $archiveName })
    $checksumAssets = @($assets | Where-Object { [string](Get-NexRoutePropertyValue -InputObject $_ -Name 'name') -eq $checksumName })
    if ($archiveAssets.Count -ne 1) {
        throw "Expected exactly one release archive named $archiveName, got $($archiveAssets.Count)."
    }
    if ($checksumAssets.Count -ne 1) {
        throw "Expected exactly one checksum asset named $checksumName, got $($checksumAssets.Count)."
    }

    if (-not $AssetDirectory) {
        foreach ($asset in @($archiveAssets[0], $checksumAssets[0])) {
            $downloadUrl = [string](Get-NexRoutePropertyValue -InputObject $asset -Name 'browser_download_url')
            if ($downloadUrl -notmatch '^https://github\.com/Onmaynec/NexRoute/releases/download/') {
                throw "Release asset URL is outside the trusted NexRoute release path: $downloadUrl"
            }
        }
    }

    return [pscustomobject]@{
        Version = $latestVersion
        Tag = $tag
        ArchiveName = $archiveName
        ChecksumName = $checksumName
        ArchiveAsset = $archiveAssets[0]
        ChecksumAsset = $checksumAssets[0]
        PublishedAt = [string](Get-NexRoutePropertyValue -InputObject $release -Name 'published_at')
        HtmlUrl = [string](Get-NexRoutePropertyValue -InputObject $release -Name 'html_url')
    }
}

function Receive-NexRouteReleaseAsset {
    param(
        [Parameter(Mandatory)]$Asset,
        [Parameter(Mandatory)][string]$Destination
    )
    $name = [string](Get-NexRoutePropertyValue -InputObject $Asset -Name 'name')
    if ($AssetDirectory) {
        $source = Join-Path $AssetDirectory $name
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "Local release asset was not found: $source"
        }
        Copy-Item -LiteralPath $source -Destination $Destination -Force
        return
    }

    $headers = @{
        Accept = 'application/octet-stream'
        'User-Agent' = 'NexRoute-Secure-Updater'
    }
    $url = [string](Get-NexRoutePropertyValue -InputObject $Asset -Name 'browser_download_url')
    Invoke-WebRequest -Uri $url -Headers $headers -OutFile $Destination -UseBasicParsing -TimeoutSec 60
}

function Get-NexRoutePackageRoot {
    param(
        [Parameter(Mandatory)][string]$ExtractDirectory,
        [Parameter(Mandatory)][string]$ExpectedVersion
    )

    $candidates = New-Object 'System.Collections.Generic.List[string]'
    $directVersion = Join-Path $ExtractDirectory '.service\version.txt'
    if ((Test-Path -LiteralPath $directVersion -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $ExtractDirectory 'nexroute.bat') -PathType Leaf)) {
        [void]$candidates.Add([System.IO.Path]::GetFullPath($ExtractDirectory))
    }

    $versionFiles = @(Get-ChildItem -LiteralPath $ExtractDirectory -Filter 'version.txt' -File -Recurse -ErrorAction Stop | Where-Object {
        $_.Directory.Name -eq '.service'
    })
    foreach ($file in $versionFiles) {
        $candidate = Split-Path -Parent $file.Directory.FullName
        if (Test-Path -LiteralPath (Join-Path $candidate 'nexroute.bat') -PathType Leaf) {
            $fullCandidate = [System.IO.Path]::GetFullPath($candidate)
            if (-not $candidates.Contains($fullCandidate)) { [void]$candidates.Add($fullCandidate) }
        }
    }

    if ($candidates.Count -ne 1) {
        throw "Expected exactly one NexRoute package root, got $($candidates.Count)."
    }

    $packageRoot = $candidates[0]
    $required = @(
        'nexroute.bat',
        'nexroute-update.cmd',
        'service.bat',
        '.service/version.txt',
        '.service/nexroute-updater.ps1',
        '.service/upstream-lock.json',
        '.service/patch-report.json',
        '.service/i18n/nexroute-pages-update.ps1'
    )
    foreach ($relativePath in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $packageRoot $relativePath) -PathType Leaf)) {
            throw "Downloaded package is incomplete. Missing: $relativePath"
        }
    }

    $packageVersion = (Get-Content -LiteralPath (Join-Path $packageRoot '.service/version.txt') -Raw -Encoding UTF8).Trim()
    if ($packageVersion -ne $ExpectedVersion) {
        throw "Downloaded package version $packageVersion differs from release version $ExpectedVersion."
    }

    $strategies = @(Get-ChildItem -LiteralPath $packageRoot -Filter '*.bat' -File | Where-Object {
        $_.Name -notin @('service.bat', 'nexroute.bat', 'nexroute-update.cmd')
    })
    if ($strategies.Count -ne 21) {
        throw "Downloaded package contains $($strategies.Count) strategies instead of 21."
    }

    $patchReport = Get-Content -LiteralPath (Join-Path $packageRoot '.service/patch-report.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $targetCount = [int](Get-NexRoutePropertyValue -InputObject (Get-NexRoutePropertyValue -InputObject $patchReport -Name 'summary') -Name 'targetCount')
    if ($targetCount -ne 23) {
        throw "Downloaded package patch report contains $targetCount targets instead of 23."
    }

    return $packageRoot
}

function Get-NexRouteVerifiedPackage {
    param([Parameter(Mandatory)]$Release)

    $downloadDirectory = Join-Path $workingRoot 'download'
    $extractDirectory = Join-Path $workingRoot 'extract'
    New-Item -ItemType Directory -Path $downloadDirectory, $extractDirectory -Force | Out-Null

    $archivePath = Join-Path $downloadDirectory $Release.ArchiveName
    $checksumPath = Join-Path $downloadDirectory $Release.ChecksumName
    Receive-NexRouteReleaseAsset -Asset $Release.ArchiveAsset -Destination $archivePath
    Receive-NexRouteReleaseAsset -Asset $Release.ChecksumAsset -Destination $checksumPath

    if ((Get-Item -LiteralPath $archivePath).Length -lt 100KB) {
        throw 'Downloaded NexRoute archive is unexpectedly small.'
    }

    $checksumLines = @(Get-Content -LiteralPath $checksumPath -Encoding ASCII | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_)
    })
    if ($checksumLines.Count -ne 1) {
        throw 'Checksum asset must contain exactly one non-empty line.'
    }
    $checksumMatch = [regex]::Match(
        $checksumLines[0].Trim(),
        '^(?<hash>[0-9a-fA-F]{64})\s+\*?(?<name>NexRoute-\d+\.\d+\.\d+-win-x64\.zip)$'
    )
    if (-not $checksumMatch.Success) {
        throw 'Checksum asset has an invalid format.'
    }
    if ($checksumMatch.Groups['name'].Value -ne $Release.ArchiveName) {
        throw 'Checksum asset references a different archive.'
    }

    $expectedSha256 = $checksumMatch.Groups['hash'].Value.ToLowerInvariant()
    $actualSha256 = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualSha256 -ne $expectedSha256) {
        throw "NexRoute package SHA-256 mismatch. Expected $expectedSha256, got $actualSha256."
    }

    Expand-Archive -LiteralPath $archivePath -DestinationPath $extractDirectory -Force
    $packageRoot = Get-NexRoutePackageRoot -ExtractDirectory $extractDirectory -ExpectedVersion $Release.Version

    return [pscustomobject]@{
        Root = $packageRoot
        Archive = $archivePath
        Sha256 = $actualSha256
        Version = $Release.Version
    }
}

function Copy-NexRouteDirectoryContents {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )
    if (-not (Test-Path -LiteralPath $Destination -PathType Container)) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    }
    foreach ($item in @(Get-ChildItem -LiteralPath $Source -Force -ErrorAction Stop)) {
        $target = Join-Path $Destination $item.Name
        if ($item.PSIsContainer) {
            if (-not (Test-Path -LiteralPath $target -PathType Container)) {
                New-Item -ItemType Directory -Path $target -Force | Out-Null
            }
            Copy-NexRouteDirectoryContents -Source $item.FullName -Destination $target
        } else {
            Copy-Item -LiteralPath $item.FullName -Destination $target -Force
        }
    }
}

function Copy-NexRoutePreservedState {
    param([Parameter(Mandatory)][string]$Destination)
    $preserved = @(
        '.service/language.txt',
        '.service/services-state.json',
        '.service/update-state.json',
        '.service/ip-source-cache',
        '.service/backups',
        'utils/check_updates.enabled',
        'utils/game_filter.enabled',
        'lists/list-general-user.txt',
        'lists/list-exclude-user.txt',
        'lists/ipset-services-user.txt',
        'lists/ipset-exclude-user.txt',
        'lists/ipset-all.txt'
    )
    foreach ($relativePath in $preserved) {
        $source = Join-Path $Root $relativePath
        if (-not (Test-Path -LiteralPath $source)) { continue }
        $target = Join-Path $Destination $relativePath
        $targetParent = Split-Path -Parent $target
        if (-not (Test-Path -LiteralPath $targetParent -PathType Container)) {
            New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
        }
        if (Test-Path -LiteralPath $source -PathType Container) {
            if (-not (Test-Path -LiteralPath $target -PathType Container)) {
                New-Item -ItemType Directory -Path $target -Force | Out-Null
            }
            Copy-NexRouteDirectoryContents -Source $source -Destination $target
        } else {
            Copy-Item -LiteralPath $source -Destination $target -Force
        }
    }
}

function Restore-NexRoutePreservedState {
    param([Parameter(Mandatory)][string]$Source)
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) { return }
    Copy-NexRouteDirectoryContents -Source $Source -Destination $Root
}

function Stop-NexRouteRuntime {
    $wasRunning = $false
    if ($env:OS -eq 'Windows_NT') {
        try {
            $service = Get-Service -Name 'zapret' -ErrorAction Stop
            $wasRunning = $service.Status -eq 'Running'
            if ($service.Status -ne 'Stopped') {
                Stop-Service -Name 'zapret' -Force -ErrorAction Stop
                $service.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(10))
            }
        } catch { }
        try { Get-Process -Name 'winws' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue } catch { }
    }
    return $wasRunning
}

function Start-NexRouteRuntime {
    param([bool]$WasRunning)
    if (-not $WasRunning -or $env:OS -ne 'Windows_NT') { return $null }
    $controller = Join-Path $Root '.service\nexroute-services.ps1'
    if (Test-Path -LiteralPath $controller -PathType Leaf) {
        try {
            return (& $controller -Mode Restart -Root $Root | Select-Object -Last 1)
        } catch {
            return $_.Exception.Message
        }
    }
    return 'Service controller was not found after the update.'
}

function New-NexRouteBackup {
    param(
        [Parameter(Mandatory)][string]$FromVersion,
        [Parameter(Mandatory)][string]$ToVersion,
        [string]$Prefix = 'update'
    )
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $name = '{0}-{1}-to-{2}-{3}' -f $Prefix, $FromVersion, $ToVersion, [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
    $path = Join-Path $backupRoot $name
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    Copy-NexRouteDirectoryContents -Source $Root -Destination $path
    return $path
}

function Limit-NexRouteBackups {
    if (-not (Test-Path -LiteralPath $backupRoot -PathType Container)) { return }
    $backups = @(Get-ChildItem -LiteralPath $backupRoot -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending)
    foreach ($backup in @($backups | Select-Object -Skip 4)) {
        Remove-Item -LiteralPath $backup.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Install-NexRouteVerifiedPackage {
    param(
        [Parameter(Mandatory)]$VerifiedPackage,
        [Parameter(Mandatory)]$Release,
        [Parameter(Mandatory)]$State
    )

    $currentVersion = Get-NexRouteCurrentVersion
    $currentSemantic = ConvertTo-NexRouteVersion -Value $currentVersion
    $targetSemantic = ConvertTo-NexRouteVersion -Value $Release.Version
    if (-not $Force -and $targetSemantic -le $currentSemantic) {
        return [pscustomobject]@{
            Status = 'current'
            CurrentVersion = $currentVersion
            LatestVersion = $Release.Version
            Updated = $false
            BackupPath = $null
            PackageSha256 = $VerifiedPackage.Sha256
            Message = 'NexRoute is already current.'
        }
    }

    $preserveDirectory = Join-Path $workingRoot 'preserved'
    New-Item -ItemType Directory -Path $preserveDirectory -Force | Out-Null
    Copy-NexRoutePreservedState -Destination $preserveDirectory
    $backupPath = New-NexRouteBackup -FromVersion $currentVersion -ToVersion $Release.Version
    $wasRunning = Stop-NexRouteRuntime

    try {
        Copy-NexRouteDirectoryContents -Source $VerifiedPackage.Root -Destination $Root
        Restore-NexRoutePreservedState -Source $preserveDirectory

        $installedVersion = Get-NexRouteCurrentVersion
        if ($installedVersion -ne $Release.Version) {
            throw "Installed version validation failed. Expected $($Release.Version), got $installedVersion."
        }

        $restartMessage = Start-NexRouteRuntime -WasRunning $wasRunning
        $State.latestVersion = $Release.Version
        $State.lastStatus = 'updated'
        $State.lastMessage = if ($restartMessage) { [string]$restartMessage } else { 'Update installed successfully.' }
        $State.lastUpdateUtc = [DateTime]::UtcNow.ToString('o')
        $State.lastBackupPath = $backupPath
        $State.lastPackageSha256 = $VerifiedPackage.Sha256
        Save-NexRouteUpdateState -State $State
        Limit-NexRouteBackups

        return [pscustomobject]@{
            Status = 'updated'
            CurrentVersion = $installedVersion
            LatestVersion = $Release.Version
            Updated = $true
            BackupPath = $backupPath
            PackageSha256 = $VerifiedPackage.Sha256
            Message = $State.lastMessage
        }
    } catch {
        try {
            Copy-NexRouteDirectoryContents -Source $backupPath -Destination $Root
            Restore-NexRoutePreservedState -Source $preserveDirectory
            [void](Start-NexRouteRuntime -WasRunning $wasRunning)
        } catch { }
        throw "Update failed and the previous package was restored: $($_.Exception.Message)"
    }
}

function Invoke-NexRouteCheck {
    param([Parameter(Mandatory)]$State)
    $currentVersion = Get-NexRouteCurrentVersion
    $release = Get-NexRouteLatestRelease
    $available = (ConvertTo-NexRouteVersion -Value $release.Version) -gt (ConvertTo-NexRouteVersion -Value $currentVersion)
    $now = [DateTime]::UtcNow
    $State.latestVersion = $release.Version
    $State.lastCheckUtc = $now.ToString('o')
    $State.nextCheckUtc = $now.AddHours($CheckIntervalHours).ToString('o')
    $State.lastStatus = if ($available) { 'available' } else { 'current' }
    $State.lastMessage = if ($available) { "NexRoute $($release.Version) is available." } else { 'NexRoute is already current.' }
    Save-NexRouteUpdateState -State $State

    return [pscustomobject]@{
        Status = $State.lastStatus
        CurrentVersion = $currentVersion
        LatestVersion = $release.Version
        UpdateAvailable = $available
        Release = $release
        Message = $State.lastMessage
    }
}

function Test-NexRouteCheckDue {
    param([Parameter(Mandatory)]$State)
    if ($Force) { return $true }
    if ([string]::IsNullOrWhiteSpace([string]$State.nextCheckUtc)) { return $true }
    $next = [DateTime]::MinValue
    if (-not [DateTime]::TryParse([string]$State.nextCheckUtc, [ref]$next)) { return $true }
    return [DateTime]::UtcNow -ge $next.ToUniversalTime()
}

function Invoke-NexRouteInstallLatest {
    param([Parameter(Mandatory)]$State)
    $check = Invoke-NexRouteCheck -State $State
    if (-not $check.UpdateAvailable -and -not $Force) {
        return [pscustomobject]@{
            Status = 'current'
            CurrentVersion = $check.CurrentVersion
            LatestVersion = $check.LatestVersion
            Updated = $false
            BackupPath = $null
            PackageSha256 = $null
            Message = $check.Message
        }
    }
    $verified = Get-NexRouteVerifiedPackage -Release $check.Release
    return Install-NexRouteVerifiedPackage -VerifiedPackage $verified -Release $check.Release -State $State
}

function Invoke-NexRouteRollback {
    param([Parameter(Mandatory)]$State)
    if (-not (Test-Path -LiteralPath $backupRoot -PathType Container)) {
        throw 'No NexRoute update backups are available.'
    }
    $backup = @(Get-ChildItem -LiteralPath $backupRoot -Directory -ErrorAction Stop |
        Where-Object { $_.Name -like 'update-*' } |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1)
    if ($backup.Count -ne 1) {
        throw 'No NexRoute update backups are available.'
    }

    $backupVersionPath = Join-Path $backup[0].FullName '.service\version.txt'
    if (-not (Test-Path -LiteralPath $backupVersionPath -PathType Leaf)) {
        throw 'The latest update backup is incomplete.'
    }
    $backupVersion = (Get-Content -LiteralPath $backupVersionPath -Raw -Encoding UTF8).Trim()
    [void](ConvertTo-NexRouteVersion -Value $backupVersion)
    $currentVersion = Get-NexRouteCurrentVersion
    $wasRunning = Stop-NexRouteRuntime
    $safetyPath = New-NexRouteBackup -FromVersion $currentVersion -ToVersion $backupVersion -Prefix 'rollback-safety'

    try {
        Copy-NexRouteDirectoryContents -Source $backup[0].FullName -Destination $Root
        $restoredVersion = Get-NexRouteCurrentVersion
        if ($restoredVersion -ne $backupVersion) {
            throw "Rollback validation failed. Expected $backupVersion, got $restoredVersion."
        }
        $restartMessage = Start-NexRouteRuntime -WasRunning $wasRunning
        $restoredState = Read-NexRouteUpdateState
        $restoredState.lastStatus = 'rolled-back'
        $restoredState.lastMessage = if ($restartMessage) { [string]$restartMessage } else { "Rolled back to NexRoute $backupVersion." }
        $restoredState.lastUpdateUtc = [DateTime]::UtcNow.ToString('o')
        $restoredState.lastBackupPath = $safetyPath
        Save-NexRouteUpdateState -State $restoredState
        Limit-NexRouteBackups
        return [pscustomobject]@{
            Status = 'rolled-back'
            CurrentVersion = $restoredVersion
            LatestVersion = $State.latestVersion
            Updated = $true
            BackupPath = $safetyPath
            PackageSha256 = $null
            Message = $restoredState.lastMessage
        }
    } catch {
        try {
            Copy-NexRouteDirectoryContents -Source $safetyPath -Destination $Root
            [void](Start-NexRouteRuntime -WasRunning $wasRunning)
        } catch { }
        throw "Rollback failed and the current package was restored: $($_.Exception.Message)"
    }
}

function Invoke-NexRouteMenu {
    param([Parameter(Mandatory)]$State)
    $language = Get-NexRouteLanguage
    while ($true) {
        $currentVersion = Get-NexRouteCurrentVersion
        $enabled = Test-Path -LiteralPath $autoFlagPath -PathType Leaf
        Clear-Host
        Write-Host '============================================================' -ForegroundColor Cyan
        Write-Host '  NEXROUTE SECURE UPDATE CENTER' -ForegroundColor Cyan
        Write-Host '============================================================' -ForegroundColor Cyan
        if ($language -eq 'RU') {
            Write-Host ("  Текущая версия : {0}" -f $currentVersion)
            Write-Host ("  Автообновление : {0}" -f $(if ($enabled) { 'ВКЛЮЧЕНО' } else { 'ВЫКЛЮЧЕНО' }))
            Write-Host ''
            Write-Host '  [1] Включить/выключить автообновление'
            Write-Host '  [2] Проверить и установить обновление сейчас'
            Write-Host '  [3] Откатиться к последней резервной копии'
            Write-Host '  [0] Назад'
            Write-Host ''
            $choice = (Read-Host '  Выберите действие').Trim()
        } else {
            Write-Host ("  Current version : {0}" -f $currentVersion)
            Write-Host ("  Auto update     : {0}" -f $(if ($enabled) { 'ENABLED' } else { 'DISABLED' }))
            Write-Host ''
            Write-Host '  [1] Toggle automatic updates'
            Write-Host '  [2] Check and install the latest version now'
            Write-Host '  [3] Roll back to the latest backup'
            Write-Host '  [0] Back'
            Write-Host ''
            $choice = (Read-Host '  Select action').Trim()
        }

        if ($choice -eq '0') {
            return [pscustomobject]@{
                Status = 'menu-exit'
                CurrentVersion = Get-NexRouteCurrentVersion
                LatestVersion = $State.latestVersion
                Updated = $false
                Message = 'Update menu closed.'
            }
        }
        if ($choice -eq '1') {
            if ($enabled) {
                Remove-Item -LiteralPath $autoFlagPath -Force -ErrorAction SilentlyContinue
            } else {
                $flagParent = Split-Path -Parent $autoFlagPath
                New-Item -ItemType Directory -Path $flagParent -Force | Out-Null
                [System.IO.File]::WriteAllText($autoFlagPath, "ENABLED`r`n", [System.Text.Encoding]::ASCII)
            }
            $State.autoEnabled = -not $enabled
            $State.nextCheckUtc = $null
            $State.lastStatus = if ($State.autoEnabled) { 'auto-enabled' } else { 'auto-disabled' }
            $State.lastMessage = $State.lastStatus
            Save-NexRouteUpdateState -State $State
            continue
        }

        try {
            if ($choice -eq '2') {
                $result = Invoke-NexRouteInstallLatest -State $State
            } elseif ($choice -eq '3') {
                $result = Invoke-NexRouteRollback -State $State
            } else {
                continue
            }
            Write-Host ''
            Write-Host $result.Message -ForegroundColor Green
        } catch {
            Write-Host ''
            Write-Host $_.Exception.Message -ForegroundColor Red
        }
        if ($language -eq 'RU') { [void](Read-Host 'Нажмите Enter') }
        else { [void](Read-Host 'Press Enter') }
    }
}

function Write-NexRouteResult {
    param([Parameter(Mandatory)]$Result)
    if ($Json) {
        $Result | ConvertTo-Json -Depth 12 -Compress
    } else {
        $Result
    }
}

try {
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        throw "NexRoute root directory was not found: $Root"
    }
    if (-not (Test-Path -LiteralPath $serviceDirectory -PathType Container)) {
        throw "NexRoute service directory was not found: $serviceDirectory"
    }

    $state = Read-NexRouteUpdateState
    $mutexSeed = [System.Text.Encoding]::UTF8.GetBytes($Root.ToLowerInvariant())
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $mutexHash = ([BitConverter]::ToString($sha.ComputeHash($mutexSeed))).Replace('-', '').Substring(0, 24) }
    finally { $sha.Dispose() }
    $mutex = New-Object System.Threading.Mutex($false, "NexRouteUpdater-$mutexHash")
    $mutexAcquired = $mutex.WaitOne(0)
    if (-not $mutexAcquired) {
        throw 'Another NexRoute update operation is already running.'
    }

    New-Item -ItemType Directory -Path $workingRoot -Force | Out-Null

    switch ($Mode) {
        'Status' {
            $result = [pscustomobject]@{
                Status = [string]$state.lastStatus
                CurrentVersion = Get-NexRouteCurrentVersion
                LatestVersion = $state.latestVersion
                AutoEnabled = Test-Path -LiteralPath $autoFlagPath -PathType Leaf
                LastCheckUtc = $state.lastCheckUtc
                NextCheckUtc = $state.nextCheckUtc
                LastBackupPath = $state.lastBackupPath
                Message = $state.lastMessage
            }
        }
        'Check' {
            $result = Invoke-NexRouteCheck -State $state
        }
        'Install' {
            $result = Invoke-NexRouteInstallLatest -State $state
        }
        'Rollback' {
            $result = Invoke-NexRouteRollback -State $state
        }
        'Menu' {
            if ($NonInteractive) {
                $result = [pscustomobject]@{
                    Status = [string]$state.lastStatus
                    CurrentVersion = Get-NexRouteCurrentVersion
                    LatestVersion = $state.latestVersion
                    AutoEnabled = Test-Path -LiteralPath $autoFlagPath -PathType Leaf
                    Message = $state.lastMessage
                }
            } else {
                $result = Invoke-NexRouteMenu -State $state
            }
        }
        'Auto' {
            if (-not (Test-Path -LiteralPath $autoFlagPath -PathType Leaf)) {
                $result = [pscustomobject]@{
                    Status = 'disabled'
                    CurrentVersion = Get-NexRouteCurrentVersion
                    LatestVersion = $state.latestVersion
                    Updated = $false
                    Message = 'Automatic updates are disabled.'
                }
            } elseif (-not (Test-NexRouteCheckDue -State $state)) {
                $result = [pscustomobject]@{
                    Status = 'cooldown'
                    CurrentVersion = Get-NexRouteCurrentVersion
                    LatestVersion = $state.latestVersion
                    Updated = $false
                    Message = 'Automatic update check is not due yet.'
                }
            } else {
                $result = Invoke-NexRouteInstallLatest -State $state
                if ($result.Updated) {
                    Write-Host ("[NexRoute] Updated to {0}. Backup: {1}" -f $result.CurrentVersion, $result.BackupPath) -ForegroundColor Green
                }
            }
        }
    }

    Write-NexRouteResult -Result $result
} catch {
    try {
        $failureState = Read-NexRouteUpdateState
        $failureState.lastStatus = 'error'
        $failureState.lastMessage = $_.Exception.Message
        $failureState.lastCheckUtc = [DateTime]::UtcNow.ToString('o')
        Save-NexRouteUpdateState -State $failureState
    } catch { }

    if ($Mode -eq 'Auto') {
        Write-Warning ("NexRoute automatic update skipped: {0}" -f $_.Exception.Message)
        Write-NexRouteResult -Result ([pscustomobject]@{
            Status = 'error'
            CurrentVersion = $(try { Get-NexRouteCurrentVersion } catch { $null })
            LatestVersion = $null
            Updated = $false
            Message = $_.Exception.Message
        })
    } else {
        throw
    }
} finally {
    if ($mutexAcquired -and $mutex) {
        try { $mutex.ReleaseMutex() } catch { }
    }
    if ($mutex) { $mutex.Dispose() }
    if (Test-Path -LiteralPath $workingRoot) {
        Remove-Item -LiteralPath $workingRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
