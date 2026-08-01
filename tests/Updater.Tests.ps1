$repositoryRoot = Split-Path -Parent $PSScriptRoot
$updaterPath = Join-Path $repositoryRoot 'overlay/.service/nexroute-updater.ps1'

function New-UpdaterInstalledRoot {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Version = '0.3.0',
        [switch]$AutoEnabled
    )

    New-Item -ItemType Directory -Path (
        Join-Path $Path '.service'
    ), (
        Join-Path $Path 'utils'
    ), (
        Join-Path $Path 'lists'
    ) -Force | Out-Null

    Set-Content -LiteralPath (Join-Path $Path '.service/version.txt') -Value $Version -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $Path '.service/language.txt') -Value 'RU' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $Path '.service/services-state.json') -Value '{"schemaVersion":2,"services":{"youtube":true}}' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $Path 'lists/list-general-user.txt') -Value 'user-preserved.example' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $Path 'nexroute.bat') -Value '@echo off' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $Path 'service.bat') -Value '@echo off' -Encoding ASCII

    if ($AutoEnabled) {
        Set-Content -LiteralPath (Join-Path $Path 'utils/check_updates.enabled') -Value 'ENABLED' -Encoding ASCII
    }
}

function New-UpdaterReleaseFixture {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Version = '0.3.1',
        [switch]$InvalidChecksum,
        [switch]$Prerelease
    )

    $assets = Join-Path $Path 'assets'
    $payload = Join-Path $Path 'payload'
    New-Item -ItemType Directory -Path $assets, (
        Join-Path $payload '.service/i18n'
    ), (
        Join-Path $payload 'bin'
    ) -Force | Out-Null

    Set-Content -LiteralPath (Join-Path $payload '.service/version.txt') -Value $Version -Encoding UTF8
    Copy-Item -LiteralPath $updaterPath -Destination (Join-Path $payload '.service/nexroute-updater.ps1') -Force
    Set-Content -LiteralPath (Join-Path $payload '.service/i18n/nexroute-pages-update.ps1') -Value 'function Invoke-NexRouteUpdateWatch { }' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $payload '.service/upstream-lock.json') -Value '{"schemaVersion":1,"sha256":"6b7c5a66cfd055b8e361f8b5fb00f00b167260f21b1c03d589f6008417fb94a2"}' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $payload '.service/patch-report.json') -Value '{"schemaVersion":1,"summary":{"targetCount":23}}' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $payload 'nexroute.bat') -Value '@echo off' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $payload 'nexroute-update.cmd') -Value '@echo off' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $payload 'service.bat') -Value '@echo off' -Encoding ASCII

    1..21 | ForEach-Object {
        Set-Content -LiteralPath (Join-Path $payload ('strategy-{0:d2}.bat' -f $_)) -Value '@echo off' -Encoding ASCII
    }

    $padding = New-Object byte[] 180000
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($padding) } finally { $rng.Dispose() }
    [System.IO.File]::WriteAllBytes((Join-Path $payload 'bin/padding.dat'), $padding)

    $archiveName = "NexRoute-$Version-win-x64.zip"
    $archivePath = Join-Path $assets $archiveName
    Compress-Archive -Path (Join-Path $payload '*') -DestinationPath $archivePath -CompressionLevel NoCompression
    $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $checksumHash = if ($InvalidChecksum) { '0' * 64 } else { $actualHash }
    Set-Content -LiteralPath (Join-Path $assets "$archiveName.sha256") -Value "$checksumHash  $archiveName" -Encoding ASCII

    $metadataPath = Join-Path $Path 'release.json'
    [ordered]@{
        tag_name = "v$Version"
        draft = $false
        prerelease = [bool]$Prerelease
        published_at = '2026-08-01T00:00:00Z'
        html_url = "https://github.com/Onmaynec/NexRoute/releases/tag/v$Version"
        assets = @(
            [ordered]@{
                name = $archiveName
                browser_download_url = "https://github.com/Onmaynec/NexRoute/releases/download/v$Version/$archiveName"
            },
            [ordered]@{
                name = "$archiveName.sha256"
                browser_download_url = "https://github.com/Onmaynec/NexRoute/releases/download/v$Version/$archiveName.sha256"
            }
        )
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $metadataPath -Encoding UTF8

    return [pscustomobject]@{
        AssetDirectory = $assets
        MetadataPath = $metadataPath
        ArchivePath = $archivePath
        ArchiveSha256 = $actualHash
    }
}

Describe 'NexRoute secure updater' {
    BeforeEach {
        $script:testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('nexroute-updater-test-{0}' -f [guid]::NewGuid().ToString('N'))
        $script:installedRoot = Join-Path $script:testRoot 'NexRoute'
        New-Item -ItemType Directory -Path $script:testRoot -Force | Out-Null
        New-UpdaterInstalledRoot -Path $script:installedRoot -AutoEnabled
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:testRoot) {
            Remove-Item -LiteralPath $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'reports a newer stable release from local metadata' {
        $fixture = New-UpdaterReleaseFixture -Path (Join-Path $script:testRoot 'release')
        $json = & $updaterPath `
            -Mode Check `
            -Root $script:installedRoot `
            -ReleaseMetadataPath $fixture.MetadataPath `
            -AssetDirectory $fixture.AssetDirectory `
            -Json
        $result = ($json | Select-Object -Last 1) | ConvertFrom-Json

        $result.Status | Should -Be 'available'
        $result.CurrentVersion | Should -Be '0.3.0'
        $result.LatestVersion | Should -Be '0.3.1'
        Test-Path -LiteralPath (Join-Path $script:installedRoot '.service/update-state.json') | Should -BeTrue
    }

    It 'installs a verified release and preserves user state' {
        $fixture = New-UpdaterReleaseFixture -Path (Join-Path $script:testRoot 'release')
        $json = & $updaterPath `
            -Mode Install `
            -Root $script:installedRoot `
            -ReleaseMetadataPath $fixture.MetadataPath `
            -AssetDirectory $fixture.AssetDirectory `
            -Json
        $result = ($json | Select-Object -Last 1) | ConvertFrom-Json

        $result.Status | Should -Be 'updated'
        $result.PackageSha256 | Should -Be $fixture.ArchiveSha256
        (Get-Content -LiteralPath (Join-Path $script:installedRoot '.service/version.txt') -Raw).Trim() | Should -Be '0.3.1'
        (Get-Content -LiteralPath (Join-Path $script:installedRoot '.service/language.txt') -Raw).Trim() | Should -Be 'RU'
        (Get-Content -LiteralPath (Join-Path $script:installedRoot 'lists/list-general-user.txt') -Raw).Trim() | Should -Be 'user-preserved.example'
        Test-Path -LiteralPath $result.BackupPath -PathType Container | Should -BeTrue
    }

    It 'rolls back to the previous verified backup' {
        $fixture = New-UpdaterReleaseFixture -Path (Join-Path $script:testRoot 'release')
        & $updaterPath `
            -Mode Install `
            -Root $script:installedRoot `
            -ReleaseMetadataPath $fixture.MetadataPath `
            -AssetDirectory $fixture.AssetDirectory `
            -Json | Out-Null

        $json = & $updaterPath -Mode Rollback -Root $script:installedRoot -Json
        $result = ($json | Select-Object -Last 1) | ConvertFrom-Json

        $result.Status | Should -Be 'rolled-back'
        (Get-Content -LiteralPath (Join-Path $script:installedRoot '.service/version.txt') -Raw).Trim() | Should -Be '0.3.0'
        (Get-Content -LiteralPath (Join-Path $script:installedRoot 'lists/list-general-user.txt') -Raw).Trim() | Should -Be 'user-preserved.example'
    }

    It 'rejects a release archive with a mismatched checksum' {
        $fixture = New-UpdaterReleaseFixture -Path (Join-Path $script:testRoot 'release') -InvalidChecksum
        {
            & $updaterPath `
                -Mode Install `
                -Root $script:installedRoot `
                -ReleaseMetadataPath $fixture.MetadataPath `
                -AssetDirectory $fixture.AssetDirectory
        } | Should -Throw '*SHA-256 mismatch*'
        (Get-Content -LiteralPath (Join-Path $script:installedRoot '.service/version.txt') -Raw).Trim() | Should -Be '0.3.0'
    }

    It 'rejects prerelease metadata in the stable channel' {
        $fixture = New-UpdaterReleaseFixture -Path (Join-Path $script:testRoot 'release') -Prerelease
        {
            & $updaterPath `
                -Mode Check `
                -Root $script:installedRoot `
                -ReleaseMetadataPath $fixture.MetadataPath `
                -AssetDirectory $fixture.AssetDirectory
        } | Should -Throw '*Prerelease builds are not accepted*'
    }

    It 'does not contact release metadata when automatic updates are disabled' {
        Remove-Item -LiteralPath (Join-Path $script:installedRoot 'utils/check_updates.enabled') -Force
        $json = & $updaterPath `
            -Mode Auto `
            -Root $script:installedRoot `
            -ReleaseMetadataPath (Join-Path $script:testRoot 'missing.json') `
            -Json
        $result = ($json | Select-Object -Last 1) | ConvertFrom-Json
        $result.Status | Should -Be 'disabled'
    }

    It 'honors the automatic update cooldown' {
        [ordered]@{
            schemaVersion = 1
            nextCheckUtc = [DateTime]::UtcNow.AddHours(3).ToString('o')
            lastStatus = 'current'
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $script:installedRoot '.service/update-state.json') -Encoding UTF8

        $json = & $updaterPath `
            -Mode Auto `
            -Root $script:installedRoot `
            -ReleaseMetadataPath (Join-Path $script:testRoot 'missing.json') `
            -Json
        $result = ($json | Select-Object -Last 1) | ConvertFrom-Json
        $result.Status | Should -Be 'cooldown'
    }

    It 'wires the launcher to the automatic updater' {
        $launcher = Get-Content -LiteralPath (Join-Path $repositoryRoot 'overlay/nexroute.bat') -Raw
        $pages = Get-Content -LiteralPath (Join-Path $repositoryRoot 'overlay/.service/i18n/nexroute-pages.ps1') -Raw
        $launcher | Should -Match 'nexroute-updater\.ps1'
        $launcher | Should -Match '-Mode Auto'
        $pages | Should -Match 'nexroute-pages-update\.ps1'
    }
}
