$repositoryRoot = Split-Path -Parent $PSScriptRoot
$refreshBuildPath = Join-Path $repositoryRoot 'overlay/.service/next/nexroute-strategy-refresh-build.ps1'
. $refreshBuildPath

Describe 'NexRoute 0.6.3 strategy refresh' {
    BeforeAll {
        $script:requiredPayloads = @(
            'bin/winws.exe',
            'bin/quic_initial_www_google_com.bin',
            'bin/quic_initial_4pda.to.bin',
            'bin/ACTIVE_DISCORD_UDP.bin',
            'bin/ACTIVE_GAME_UDP.bin',
            'bin/stun.bin',
            'bin/stun2.bin',
            'bin/tls_clienthello_www_google_com.bin',
            'bin/tls_clienthello_max_ru.bin'
        )

        function New-NexRoute063Fixture {
            param([switch]$OmitStun2)

            $root = Join-Path ([System.IO.Path]::GetTempPath()) ('nexroute-063-refresh-{0}' -f [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $root -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $root 'bin'), (Join-Path $root 'lists'), (Join-Path $root '.service') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $root '.service/version.txt') -Value '0.6.3' -Encoding ASCII

            foreach ($relativePath in $script:requiredPayloads) {
                if ($OmitStun2 -and $relativePath -eq 'bin/stun2.bin') { continue }
                $path = Join-Path $root $relativePath
                [System.IO.File]::WriteAllBytes($path, [byte[]](1,2,3,4))
            }

            $template = @(
                '@echo off',
                'rem NEXROUTE_PROFILE_BOOT',
                'start "zapret: %~n0" /min "%~dp0bin\winws.exe" --wf-tcp=80,443 --wf-udp=443 ^',
                '--filter-tcp=443 --dpi-desync=fake --new ^',
                '%NEXROUTE_SERVICE_TCP_ARGS% ^',
                '%NEXROUTE_SERVICE_UDP_ARGS%'
            )
            foreach ($spec in @(Get-NexRoute063StrategyCatalog)) {
                [System.IO.File]::WriteAllLines(
                    (Join-Path $root ([string]$spec.File)),
                    $template,
                    [System.Text.Encoding]::ASCII
                )
            }

            return $root
        }
    }

    BeforeEach {
        $script:fixtureRoot = $null
    }

    AfterEach {
        if ($script:fixtureRoot -and (Test-Path -LiteralPath $script:fixtureRoot)) {
            Remove-Item -LiteralPath $script:fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'creates 21 distinct strategies for the seven failed Discord and YouTube targets' {
        $script:fixtureRoot = New-NexRoute063Fixture
        $result = Invoke-NexRoute063StrategyRefreshBuild -Root $script:fixtureRoot

        $result.StrategyCount | Should -Be 21
        Test-Path -LiteralPath $result.Report -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $result.DiscordList -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $result.YouTubeList -PathType Leaf | Should -BeTrue

        $profiles = New-Object 'System.Collections.Generic.List[string]'
        foreach ($spec in @(Get-NexRoute063StrategyCatalog)) {
            $path = Join-Path $script:fixtureRoot ([string]$spec.File)
            $content = Get-Content -LiteralPath $path -Raw -Encoding ASCII
            $content | Should -Match 'NEXROUTE_STRATEGY_REFRESH_063'
            $content | Should -Match 'list-nexroute-discord-critical\.txt'
            $content | Should -Match 'list-nexroute-youtube-critical\.txt'
            $content | Should -Match '--filter-l7=quic'
            $content | Should -Match '--filter-l7=discord,stun,unknown'
            $content | Should -Not -Match '%NEXROUTE_SERVICE_TCP_ARGS%'
            $content | Should -Not -Match '%NEXROUTE_SERVICE_UDP_ARGS%'

            $marker = [regex]::Match($content, 'NEXROUTE_STRATEGY_REFRESH_063\s+(?<profile>\S+)')
            $marker.Success | Should -BeTrue
            $profiles.Add($marker.Groups['profile'].Value)
        }

        @($profiles | Sort-Object -Unique).Count | Should -Be 21
    }

    It 'writes exact critical host coverage and a hash-verifiable refresh report' {
        $script:fixtureRoot = New-NexRoute063Fixture
        $result = Invoke-NexRoute063StrategyRefreshBuild -Root $script:fixtureRoot

        $discordHosts = @(Get-Content -LiteralPath $result.DiscordList -Encoding ASCII)
        $youtubeHosts = @(Get-Content -LiteralPath $result.YouTubeList -Encoding ASCII)
        foreach ($hostName in @('gateway.discord.gg','cdn.discordapp.com','updates.discord.com')) {
            $discordHosts | Should -Contain $hostName
        }
        foreach ($hostName in @('www.youtube.com','youtu.be','i.ytimg.com','redirector.googlevideo.com')) {
            $youtubeHosts | Should -Contain $hostName
        }

        $report = Get-Content -LiteralPath $result.Report -Raw -Encoding UTF8 | ConvertFrom-Json
        $report.schemaVersion | Should -Be 1
        $report.nexRouteVersion | Should -Be '0.6.3'
        $report.sourceVersion | Should -Be '0.6.3'
        $report.strategyCount | Should -Be 21
        @($report.criticalTargets).Count | Should -Be 7
        @($report.strategies).Count | Should -Be 21
        @($report.strategies.profile | Sort-Object -Unique).Count | Should -Be 21

        foreach ($entry in @($report.strategies)) {
            $path = Join-Path $script:fixtureRoot ([string]$entry.file)
            (Get-NexRoute063Sha256 -Path $path) | Should -Be ([string]$entry.afterSha256)
            ([string]$entry.beforeSha256) | Should -Not -Be ([string]$entry.afterSha256)
        }
    }

    It 'fails closed when a required payload is absent' {
        $script:fixtureRoot = New-NexRoute063Fixture -OmitStun2
        { Invoke-NexRoute063StrategyRefreshBuild -Root $script:fixtureRoot } |
            Should -Throw '*requires payload: bin/stun2.bin*'
    }

    It 'guards build integration and leaves Service Matrix tail insertion to the tracked patch' {
        $entryPath = Join-Path $repositoryRoot 'overlay/.service/nexroute-services-entry.ps1'
        $entry = Get-Content -LiteralPath $entryPath -Raw -Encoding UTF8
        $buildReleasePath = Join-Path $repositoryRoot 'scripts/Build-Release.ps1'
        $buildRelease = Get-Content -LiteralPath $buildReleasePath -Raw -Encoding UTF8

        $entry | Should -Match '\$Mode -eq ''Apply'''
        $entry | Should -Match 'Get-PSCallStack'
        $entry | Should -Match 'Build-Release\.ps1'
        $entry | Should -Match 'nexroute-strategy-refresh-build\.ps1'
        $entry | Should -Match 'Invoke-NexRoute063StrategyRefreshBuild'
        $buildRelease | Should -Match '%NEXROUTE_SERVICE_TCP_ARGS%'
        $buildRelease | Should -Match '%NEXROUTE_SERVICE_UDP_ARGS%'
    }
}
