Describe 'NexRoute 0.6.4 updater post-update health rollback' {
    BeforeAll {
        $script:repositoryRoot = Split-Path -Parent $PSScriptRoot
        $script:updaterPath = Join-Path $script:repositoryRoot 'overlay/.service/nexroute-updater.ps1'

        function New-Nr064InstalledRoot {
            param([string]$Path,[string]$Version)
            New-Item -ItemType Directory -Path (Join-Path $Path '.service/history'),(Join-Path $Path '.service/logs'),(Join-Path $Path '.service/profiles'),(Join-Path $Path 'utils'),(Join-Path $Path 'lists') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $Path '.service/version.txt') -Value $Version -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $Path '.service/language.txt') -Value 'RU' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $Path '.service/services-state.json') -Value '{"schemaVersion":2,"services":{"youtube":true,"discord":true}}' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $Path '.service/next-state.json') -Value '{"theme":"dark","accent":"cyan","mode":"advanced"}' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $Path '.service/custom-services.json') -Value '{"services":[{"id":"custom-health-test"}]}' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $Path '.service/history/strategy-switches.jsonl') -Value '{"strategy":"working-health"}' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $Path 'lists/list-general-user.txt') -Value 'health-preserved.example' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $Path 'utils/check_updates.enabled') -Value 'ENABLED' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $Path 'nexroute.bat') -Value '@echo off' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $Path 'service.bat') -Value '@echo off' -Encoding ASCII
        }

        function New-Nr064Release {
            param([string]$Path,[string]$Version='0.6.4')
            $assets = Join-Path $Path 'assets'
            $payload = Join-Path $Path 'payload'
            New-Item -ItemType Directory -Path $assets,(Join-Path $payload '.service/i18n'),(Join-Path $payload 'bin') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $payload '.service/version.txt') -Value $Version -Encoding UTF8
            Copy-Item -LiteralPath $script:updaterPath -Destination (Join-Path $payload '.service/nexroute-updater.ps1') -Force
            Set-Content -LiteralPath (Join-Path $payload '.service/i18n/nexroute-pages-update.ps1') -Value 'function Invoke-NexRouteUpdateWatch { }' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $payload '.service/upstream-lock.json') -Value '{"schemaVersion":1,"sha256":"244314ae1c24538a0d751601da8e0c925c843371eec4456eb15f14c4fd6b7058"}' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $payload '.service/patch-report.json') -Value '{"schemaVersion":1,"summary":{"targetCount":24}}' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $payload 'nexroute.bat') -Value '@echo off' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $payload 'nexroute-update.cmd') -Value '@echo off' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $payload 'service.bat') -Value '@echo off' -Encoding ASCII
            1..22 | ForEach-Object { Set-Content -LiteralPath (Join-Path $payload ('strategy-{0:d2}.bat' -f $_)) -Value '@echo off' -Encoding ASCII }
            $padding = New-Object byte[] 180000
            $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
            try { $rng.GetBytes($padding) } finally { $rng.Dispose() }
            [IO.File]::WriteAllBytes((Join-Path $payload 'bin/padding.dat'),$padding)

            $archiveName = "NexRoute-$Version-win-x64.zip"
            $archivePath = Join-Path $assets $archiveName
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [IO.Compression.ZipFile]::CreateFromDirectory($payload,$archivePath,[IO.Compression.CompressionLevel]::NoCompression,$false)
            $sha = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
            Set-Content -LiteralPath (Join-Path $assets "$archiveName.sha256") -Value "$sha  $archiveName" -Encoding ASCII
            $metadata = Join-Path $Path 'release.json'
            [ordered]@{
                tag_name="v$Version"; draft=$false; prerelease=$false; published_at='2026-08-09T00:00:00Z'; html_url="https://github.com/Onmaynec/NexRoute/releases/tag/v$Version";
                assets=@(
                    [ordered]@{ name=$archiveName; browser_download_url="https://github.com/Onmaynec/NexRoute/releases/download/v$Version/$archiveName" },
                    [ordered]@{ name="$archiveName.sha256"; browser_download_url="https://github.com/Onmaynec/NexRoute/releases/download/v$Version/$archiveName.sha256" }
                )
            } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $metadata -Encoding UTF8
            return [pscustomobject]@{ Assets=$assets; Metadata=$metadata; Sha=$sha }
        }
    }

    It 'rolls back byte-preserved user state when the post-update health check fails' {
        $testRoot = Join-Path ([IO.Path]::GetTempPath()) ('NexRoute health rollback Тест '+[guid]::NewGuid().ToString('N'))
        $installed = Join-Path $testRoot 'NexRoute Installed'
        try {
            New-Nr064InstalledRoot -Path $installed -Version '0.6.3'
            $fixture = New-Nr064Release -Path (Join-Path $testRoot 'release')
            $before = @{}
            foreach ($relative in @('.service/language.txt','.service/next-state.json','.service/custom-services.json','.service/history/strategy-switches.jsonl','lists/list-general-user.txt')) {
                $before[$relative] = (Get-FileHash -LiteralPath (Join-Path $installed $relative) -Algorithm SHA256).Hash
            }

            $old = $env:NEXROUTE_UPDATE_FORCE_HEALTH_FAILURE
            $env:NEXROUTE_UPDATE_FORCE_HEALTH_FAILURE = '1'
            try {
                { & $script:updaterPath -Mode Install -Root $installed -ReleaseMetadataPath $fixture.Metadata -AssetDirectory $fixture.Assets -Json } | Should -Throw '*post-update health check*'
            } finally {
                $env:NEXROUTE_UPDATE_FORCE_HEALTH_FAILURE = $old
            }

            (Get-Content -LiteralPath (Join-Path $installed '.service/version.txt') -Raw).Trim() | Should -Be '0.6.3'
            foreach ($relative in $before.Keys) {
                (Get-FileHash -LiteralPath (Join-Path $installed $relative) -Algorithm SHA256).Hash | Should -Be $before[$relative]
            }
        } finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'updates successfully and a second install is an idempotent current result' {
        $testRoot = Join-Path ([IO.Path]::GetTempPath()) ('NexRoute idempotent Тест '+[guid]::NewGuid().ToString('N'))
        $installed = Join-Path $testRoot 'NexRoute Installed'
        try {
            New-Nr064InstalledRoot -Path $installed -Version '0.6.3'
            $fixture = New-Nr064Release -Path (Join-Path $testRoot 'release')

            $firstOutput = & $script:updaterPath -Mode Install -Root $installed -ReleaseMetadataPath $fixture.Metadata -AssetDirectory $fixture.Assets -Json
            $first = ($firstOutput | Select-Object -Last 1) | ConvertFrom-Json
            $first.Status | Should -Be 'updated'
            $first.CurrentVersion | Should -Be '0.6.4'
            $first.PackageSha256 | Should -Be $fixture.Sha
            (Get-Content -LiteralPath (Join-Path $installed '.service/custom-services.json') -Raw) | Should -Match 'custom-health-test'

            $secondOutput = & $script:updaterPath -Mode Install -Root $installed -ReleaseMetadataPath $fixture.Metadata -AssetDirectory $fixture.Assets -Json
            $second = ($secondOutput | Select-Object -Last 1) | ConvertFrom-Json
            $second.Status | Should -Be 'current'
            $second.CurrentVersion | Should -Be '0.6.4'
            $second.Updated | Should -BeFalse
        } finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
