Describe 'NexRoute 0.6.3 live Strategy Lab release evidence' {
    BeforeAll {
        $script:root = Split-Path -Parent $PSScriptRoot
        $script:validator = Join-Path $script:root 'scripts/Test-StrategyLab063Evidence.ps1'
        $script:candidateSha = '6103d6f96f052693af890f3b446f82624ac1c73845d6f8795a458182726f85fa'

        function New-StrategyLab063Log {
            param(
                [Parameter(Mandatory)][string]$Path,
                [switch]$Passing
            )

            $criticalStatus = if ($Passing) { 'OK' } else { 'ERROR' }
            $lines = @(
                'NEXROUTE STRATEGY LAB SESSION',
                '[1/21] general (ALT).bat',
                "  DiscordGateway           HTTP:$criticalStatus TLS1.2:$criticalStatus TLS1.3:$criticalStatus | Ping: 35 ms",
                "  DiscordCDN               HTTP:$criticalStatus TLS1.2:$criticalStatus TLS1.3:$criticalStatus | Ping: 28 ms",
                "  DiscordUpdates           HTTP:$criticalStatus TLS1.2:$criticalStatus TLS1.3:$criticalStatus | Ping: 28 ms",
                "  YouTubeWeb               HTTP:$criticalStatus TLS1.2:$criticalStatus TLS1.3:$criticalStatus | Ping: 43 ms",
                "  YouTubeShort             HTTP:$criticalStatus TLS1.2:$criticalStatus TLS1.3:$criticalStatus | Ping: 45 ms",
                "  YouTubeImage             HTTP:$criticalStatus TLS1.2:$criticalStatus TLS1.3:$criticalStatus | Ping: 46 ms",
                "  YouTubeVideoRedirect     HTTP:$criticalStatus TLS1.2:$criticalStatus TLS1.3:$criticalStatus | Ping: 43 ms",
                '  GoogleMain               HTTP:OK TLS1.2:OK TLS1.3:OK | Ping: 47 ms',
                '  CloudflareWeb            HTTP:OK TLS1.2:OK TLS1.3:OK | Ping: 27 ms',
                '[2/21] general (ALT2).bat',
                '  DiscordGateway           HTTP:ERROR TLS1.2:ERROR TLS1.3:ERROR | Ping: 35 ms'
            )
            [System.IO.File]::WriteAllLines($Path, $lines, [System.Text.UTF8Encoding]::new($false))
        }
    }

    BeforeEach {
        $script:fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('nexroute-063-live-evidence-{0}' -f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:fixtureRoot -Force | Out-Null
    }

    AfterEach {
        Remove-Item -LiteralPath $script:fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'accepts one real config only when all seven critical targets pass HTTP and both TLS versions' {
        $log = Join-Path $script:fixtureRoot 'strategy-lab.txt'
        $evidencePath = Join-Path $script:fixtureRoot 'evidence.json'
        New-StrategyLab063Log -Path $log -Passing

        $result = & $script:validator `
            -Path $log `
            -CandidateSha256 $script:candidateSha `
            -OutputPath $evidencePath

        $result.status | Should -Be 'passed'
        $result.nexRouteVersion | Should -Be '0.6.3'
        $result.strategy | Should -Be 'general (ALT).bat'
        @($result.requiredTargets).Count | Should -Be 7
        @($result.targets).Count | Should -Be 7
        $result.candidateSha256 | Should -Be $script:candidateSha
        $result.sourceLogSha256 | Should -Match '^[0-9a-f]{64}$'
        Test-Path -LiteralPath $evidencePath -PathType Leaf | Should -BeTrue

        $stored = Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $stored.status | Should -Be 'passed'
        $stored.strategy | Should -Be 'general (ALT).bat'
        @($stored.targets | Where-Object { $_.http -eq 'OK' -and $_.tls12 -eq 'OK' -and $_.tls13 -eq 'OK' }).Count | Should -Be 7
    }

    It 'rejects the previously observed failure shape even when control sites are healthy' {
        $log = Join-Path $script:fixtureRoot 'failed-strategy-lab.txt'
        New-StrategyLab063Log -Path $log

        { & $script:validator -Path $log -CandidateSha256 $script:candidateSha } |
            Should -Throw '*no strategy passed HTTP, TLS 1.2 and TLS 1.3 for all seven critical Discord/YouTube targets*'
    }

    It 'rejects incomplete logs that omit one critical target' {
        $log = Join-Path $script:fixtureRoot 'incomplete-strategy-lab.txt'
        $lines = @(
            '[1/21] general.bat',
            'DiscordGateway HTTP:OK TLS1.2:OK TLS1.3:OK | Ping: 30 ms',
            'DiscordCDN HTTP:OK TLS1.2:OK TLS1.3:OK | Ping: 30 ms',
            'DiscordUpdates HTTP:OK TLS1.2:OK TLS1.3:OK | Ping: 30 ms',
            'YouTubeWeb HTTP:OK TLS1.2:OK TLS1.3:OK | Ping: 30 ms',
            'YouTubeShort HTTP:OK TLS1.2:OK TLS1.3:OK | Ping: 30 ms',
            'YouTubeImage HTTP:OK TLS1.2:OK TLS1.3:OK | Ping: 30 ms'
        )
        [System.IO.File]::WriteAllLines($log, $lines, [System.Text.UTF8Encoding]::new($false))

        { & $script:validator -Path $log -CandidateSha256 $script:candidateSha } |
            Should -Throw '*YouTubeVideoRedirect*'
    }

    It 'requires a real file and a SHA-256-shaped candidate digest' {
        { & $script:validator -Path (Join-Path $script:fixtureRoot 'missing.txt') -CandidateSha256 $script:candidateSha } |
            Should -Throw '*evidence log is missing*'
        { & $script:validator -Path (Join-Path $script:fixtureRoot 'missing.txt') -CandidateSha256 'bad' } |
            Should -Throw
    }
}
