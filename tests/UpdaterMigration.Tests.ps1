Describe 'NexRoute 0.6.1 updater migration transactions' {
    BeforeAll {
        $script:repositoryRoot=Split-Path -Parent $PSScriptRoot
        $script:updaterPath=Join-Path $script:repositoryRoot 'overlay/.service/nexroute-updater.ps1'

        function New-NrMigrationInstalledRoot {
            param([string]$Path,[string]$Version)
            New-Item -ItemType Directory -Path (Join-Path $Path '.service/history'),(Join-Path $Path '.service/logs'),(Join-Path $Path '.service/profiles'),(Join-Path $Path 'utils'),(Join-Path $Path 'lists') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $Path '.service/version.txt') -Value $Version -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $Path '.service/language.txt') -Value 'RU' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $Path '.service/services-state.json') -Value '{"schemaVersion":2,"services":{"youtube":true,"discord":true}}' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $Path '.service/next-state.json') -Value '{"theme":"light","accent":"cyan","mode":"advanced"}' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $Path '.service/custom-services.json') -Value '{"services":[{"id":"custom-test"}]}' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $Path '.service/history/strategy-switches.jsonl') -Value '{"strategy":"working-a"}' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $Path '.service/profiles/home.json') -Value '{"strategy":"working-a"}' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $Path 'lists/list-general-user.txt') -Value 'user-preserved.example' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $Path 'lists/ipset-services-user.txt') -Value '2001:db8::/32' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $Path 'utils/check_updates.enabled') -Value 'ENABLED' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $Path 'nexroute.bat') -Value '@echo off' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $Path 'service.bat') -Value '@echo off' -Encoding ASCII
        }

        function New-NrMigrationRelease {
            param([string]$Path)
            $version='0.6.1'
            $assets=Join-Path $Path 'assets'
            $payload=Join-Path $Path 'payload'
            New-Item -ItemType Directory -Path $assets,(Join-Path $payload '.service/i18n'),(Join-Path $payload '.service/next'),(Join-Path $payload 'bin') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $payload '.service/version.txt') -Value $version -Encoding UTF8
            Copy-Item -LiteralPath $script:updaterPath -Destination (Join-Path $payload '.service/nexroute-updater.ps1') -Force
            Set-Content -LiteralPath (Join-Path $payload '.service/i18n/nexroute-pages-update.ps1') -Value 'function Invoke-NexRouteUpdateWatch { }' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $payload '.service/upstream-lock.json') -Value '{"schemaVersion":1,"sha256":"6b7c5a66cfd055b8e361f8b5fb00f00b167260f21b1c03d589f6008417fb94a2"}' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $payload '.service/patch-report.json') -Value '{"schemaVersion":1,"summary":{"targetCount":23}}' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $payload 'nexroute.bat') -Value '@echo off' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $payload 'nexroute-update.cmd') -Value '@echo off' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $payload 'service.bat') -Value '@echo off' -Encoding ASCII
            1..21 | ForEach-Object { Set-Content -LiteralPath (Join-Path $payload ('strategy-{0:d2}.bat' -f $_)) -Value '@echo off' -Encoding ASCII }
            $padding=New-Object byte[] 180000
            $rng=[Security.Cryptography.RandomNumberGenerator]::Create()
            try { $rng.GetBytes($padding) } finally { $rng.Dispose() }
            [IO.File]::WriteAllBytes((Join-Path $payload 'bin/padding.dat'),$padding)

            $archiveName="NexRoute-$version-win-x64.zip"
            $archivePath=Join-Path $assets $archiveName
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [IO.Compression.ZipFile]::CreateFromDirectory($payload,$archivePath,[IO.Compression.CompressionLevel]::NoCompression,$false)
            $sha=(Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
            Set-Content -LiteralPath (Join-Path $assets "$archiveName.sha256") -Value "$sha  $archiveName" -Encoding ASCII
            $metadata=Join-Path $Path 'release.json'
            [ordered]@{
                tag_name='v0.6.1'; draft=$false; prerelease=$false; published_at='2026-08-04T00:00:00Z'; html_url='https://github.com/Onmaynec/NexRoute/releases/tag/v0.6.1';
                assets=@(
                    [ordered]@{ name=$archiveName; browser_download_url="https://github.com/Onmaynec/NexRoute/releases/download/v0.6.1/$archiveName" },
                    [ordered]@{ name="$archiveName.sha256"; browser_download_url="https://github.com/Onmaynec/NexRoute/releases/download/v0.6.1/$archiveName.sha256" }
                )
            } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $metadata -Encoding UTF8
            return [pscustomobject]@{ Assets=$assets; Metadata=$metadata; Sha=$sha }
        }
    }

    It 'migrates <_> to 0.6.1 and restores the exact prior version on rollback' -ForEach @('0.4.1','0.5.0','0.6.0') {
        $fromVersion=$_
        $testRoot=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-migration-'+[guid]::NewGuid().ToString('N'))
        $installed=Join-Path $testRoot 'NexRoute'
        try {
            New-NrMigrationInstalledRoot -Path $installed -Version $fromVersion
            $fixture=New-NrMigrationRelease -Path (Join-Path $testRoot 'release')
            $output=& $script:updaterPath -Mode Install -Root $installed -ReleaseMetadataPath $fixture.Metadata -AssetDirectory $fixture.Assets -Json
            $result=($output | Select-Object -Last 1) | ConvertFrom-Json

            $result.Status | Should -Be 'updated'
            $result.CurrentVersion | Should -Be '0.6.1'
            $result.PackageSha256 | Should -Be $fixture.Sha
            Test-Path -LiteralPath $result.BackupPath -PathType Container | Should -BeTrue
            (Get-Content -LiteralPath (Join-Path $installed '.service/language.txt') -Raw).Trim() | Should -Be 'RU'
            (Get-Content -LiteralPath (Join-Path $installed 'lists/list-general-user.txt') -Raw).Trim() | Should -Be 'user-preserved.example'
            (Get-Content -LiteralPath (Join-Path $installed 'lists/ipset-services-user.txt') -Raw).Trim() | Should -Be '2001:db8::/32'
            (Get-Content -LiteralPath (Join-Path $installed '.service/next-state.json') -Raw) | Should -Match 'advanced'
            (Get-Content -LiteralPath (Join-Path $installed '.service/history/strategy-switches.jsonl') -Raw) | Should -Match 'working-a'

            $rollbackOutput=& $script:updaterPath -Mode Rollback -Root $installed -Json
            $rollback=($rollbackOutput | Select-Object -Last 1) | ConvertFrom-Json
            $rollback.Status | Should -Be 'rolled-back'
            (Get-Content -LiteralPath (Join-Path $installed '.service/version.txt') -Raw).Trim() | Should -Be $fromVersion
            (Get-Content -LiteralPath (Join-Path $installed 'lists/list-general-user.txt') -Raw).Trim() | Should -Be 'user-preserved.example'
            (Get-Content -LiteralPath (Join-Path $installed '.service/custom-services.json') -Raw) | Should -Match 'custom-test'
        } finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
