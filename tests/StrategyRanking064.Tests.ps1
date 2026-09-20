Describe 'NexRoute 0.6.4 Strategy Lab ranking' {
    BeforeAll {
        $script:root = Split-Path -Parent $PSScriptRoot
        . (Join-Path $script:root 'overlay/.service/next/nexroute-strategy-ranking.ps1')

        function New-Observation {
            param(
                [string]$Target,
                [bool]$Critical,
                $Success,
                [bool]$Control = $false,
                $Latency = 50,
                $Loss = 1,
                $Jitter = 5,
                $Throughput = 10,
                [string]$Protocol = 'HTTPS'
            )
            [pscustomobject]@{
                target = $Target
                protocol = $Protocol
                critical = $Critical
                control = $Control
                success = $Success
                latencyMs = $Latency
                packetLossPercent = $Loss
                jitterMs = $Jitter
                throughputMbps = $Throughput
            }
        }

        function New-HealthyControl {
            @(
                (New-Observation GitHub $false $true $true),
                (New-Observation GitHub $false $true $true),
                (New-Observation GitHub $false $true $true)
            )
        }

        function New-Candidate {
            param([string]$Strategy, [object[]]$Observations, [bool]$Started = $true)
            [pscustomobject]@{ strategy = $Strategy; started = $Started; observations = @($Observations) }
        }
    }

    It 'weights repeated critical-service success above secondary checks' {
        $a = New-Candidate 'critical-first.bat' @(
            (New-Observation Discord $true $true), (New-Observation Discord $true $true), (New-Observation Discord $true $true),
            (New-Observation YouTube $true $true), (New-Observation YouTube $true $true), (New-Observation YouTube $true $true),
            (New-Observation Telegram $false $false), (New-Observation Telegram $false $false), (New-Observation Telegram $false $false),
            (New-HealthyControl)
        )
        $b = New-Candidate 'secondary-first.bat' @(
            (New-Observation Discord $true $true), (New-Observation Discord $true $true), (New-Observation Discord $true $false),
            (New-Observation YouTube $true $true), (New-Observation YouTube $true $true), (New-Observation YouTube $true $false),
            (New-Observation Telegram $false $true), (New-Observation Telegram $false $true), (New-Observation Telegram $false $true),
            (New-HealthyControl)
        )

        $ranked = @(Get-NrStrategyRanking064 -Candidates @($b,$a))
        $ranked[0].strategy | Should -Be 'critical-first.bat'
        $ranked[0].criticalAvailabilityPercent | Should -Be 100
        $ranked[0].controlAvailabilityPercent | Should -Be 100
        $ranked[0].recommendationReason | Should -Match 'critical-service availability delta'
        $ranked[0].recommendationReason | Should -Match 'Discord 3/3'
        $ranked[0].recommendationReason | Should -Match 'GitHub 3/3'
    }

    It 'penalizes a 2-of-3 flapping critical endpoint versus a stable endpoint set' {
        $stable = New-Candidate 'stable.bat' @(
            (New-Observation Discord $true $true), (New-Observation Discord $true $true), (New-Observation Discord $true $true),
            (New-Observation YouTube $true $false), (New-Observation YouTube $true $false), (New-Observation YouTube $true $false),
            (New-HealthyControl)
        )
        $flappy = New-Candidate 'flappy-2of3.bat' @(
            (New-Observation Discord $true $true), (New-Observation Discord $true $false), (New-Observation Discord $true $true),
            (New-Observation YouTube $true $false), (New-Observation YouTube $true $true), (New-Observation YouTube $true $false),
            (New-HealthyControl)
        )

        $ranked = @(Get-NrStrategyRanking064 -Candidates @($flappy,$stable))
        $ranked[0].strategy | Should -Be 'stable.bat'
        $ranked[0].criticalAvailabilityPercent | Should -Be 50
        $ranked[1].criticalAvailabilityPercent | Should -Be 50
        $ranked[0].stabilityPercent | Should -BeGreaterThan $ranked[1].stabilityPercent
    }

    It 'penalizes a 1-of-3 flapping endpoint and exposes endpoint pass rates' {
        $candidate = New-Candidate 'flappy-1of3.bat' @(
            (New-Observation Discord $true $true), (New-Observation Discord $true $false), (New-Observation Discord $true $false),
            (New-Observation YouTube $true $true), (New-Observation YouTube $true $true), (New-Observation YouTube $true $true),
            (New-HealthyControl)
        )
        $ranked = @(Get-NrStrategyRanking064 -Candidates @($candidate))
        $discord = @($ranked[0].targetPassRates | Where-Object { $_.target -eq 'Discord' })[0]
        $discord.passed | Should -Be 1
        $discord.measured | Should -Be 3
        $discord.passRatePercent | Should -Be 33.333
        $ranked[0].stabilityPercent | Should -BeLessThan 100
    }

    It 'does not coerce missing optional telemetry to zero' {
        $candidate = New-Candidate 'missing-telemetry.bat' @(
            (New-Observation Discord $true $true $false $null $null $null $null),
            (New-Observation Discord $true $true $false $null $null $null $null),
            (New-Observation Discord $true $true $false $null $null $null $null),
            (New-Observation YouTube $true $true $false $null $null $null $null),
            (New-Observation YouTube $true $true $false $null $null $null $null),
            (New-Observation YouTube $true $true $false $null $null $null $null),
            (New-HealthyControl)
        )

        $ranked = @(Get-NrStrategyRanking064 -Candidates @($candidate))
        $ranked[0].rankingState | Should -Be 'eligible'
        $ranked[0].telemetryScorePercent | Should -BeNullOrEmpty
        $ranked[0].averageHttpLatencyMs | Should -BeNullOrEmpty
        $ranked[0].peakDownloadMbps | Should -BeNullOrEmpty
        $ranked[0].score | Should -Be 100
    }

    It 'marks insufficient critical observations inconclusive instead of assigning a synthetic zero score' {
        $candidate = New-Candidate 'too-short.bat' @(
            (New-Observation Discord $true $true),
            (New-Observation YouTube $true $true),
            (New-Observation Telegram $false $true),
            (New-HealthyControl)
        )

        $ranked = @(Get-NrStrategyRanking064 -Candidates @($candidate) -MinimumObservations 6)
        $ranked[0].rankingState | Should -Be 'inconclusive'
        $ranked[0].score | Should -BeNullOrEmpty
        $ranked[0].inconclusiveReason | Should -Match 'measured non-control observations'
    }

    It 'marks a control failure inconclusive instead of ranking a possibly offline network' {
        $candidate = New-Candidate 'control-failed.bat' @(
            (New-Observation Discord $true $true), (New-Observation Discord $true $true), (New-Observation Discord $true $true),
            (New-Observation YouTube $true $true), (New-Observation YouTube $true $true), (New-Observation YouTube $true $true),
            (New-Observation GitHub $false $true $true), (New-Observation GitHub $false $false $true), (New-Observation GitHub $false $true $true)
        )
        $ranked = @(Get-NrStrategyRanking064 -Candidates @($candidate))
        $ranked[0].rankingState | Should -Be 'inconclusive'
        $ranked[0].score | Should -BeNullOrEmpty
        $ranked[0].inconclusiveReason | Should -Match 'control target failed'
    }

    It 'uses strategy id as a deterministic final tie-break and explains it' {
        $observations = @(
            (New-Observation Discord $true $true), (New-Observation Discord $true $true), (New-Observation Discord $true $true),
            (New-Observation YouTube $true $true), (New-Observation YouTube $true $true), (New-Observation YouTube $true $true),
            (New-HealthyControl)
        )
        $ranked = @(Get-NrStrategyRanking064 -Candidates @((New-Candidate 'zeta.bat' $observations),(New-Candidate 'alpha.bat' $observations)))
        $ranked[0].strategy | Should -Be 'alpha.bat'
        $ranked[0].recommendationReason | Should -Match 'deterministic strategy-id tie-break'
    }

    It 'keeps disabled or unmeasured services out of the target denominator' {
        $candidate = New-Candidate 'enabled-only.bat' @(
            (New-Observation Discord $true $true), (New-Observation Discord $true $true), (New-Observation Discord $true $true),
            (New-Observation YouTube $true $true), (New-Observation YouTube $true $true), (New-Observation YouTube $true $true),
            (New-HealthyControl)
        )
        $ranked = @(Get-NrStrategyRanking064 -Candidates @($candidate))
        @($ranked[0].targetPassRates.target) | Should -Not -Contain 'DisabledGameService'
        $ranked[0].criticalTargetCount | Should -Be 2
    }

    It 'stores pass rates by protocol for the measured probe contract' {
        $candidate = New-Candidate 'protocol.bat' @(
            (New-Observation Discord $true $true), (New-Observation Discord $true $true), (New-Observation Discord $true $true),
            (New-Observation YouTube $true $true), (New-Observation YouTube $true $true), (New-Observation YouTube $true $true),
            (New-HealthyControl)
        )
        $ranked = @(Get-NrStrategyRanking064 -Candidates @($candidate))
        $https = @($ranked[0].protocolPassRates | Where-Object { $_.protocol -eq 'HTTPS' })[0]
        $https.measured | Should -Be 9
        $https.passed | Should -Be 9
        $https.passRatePercent | Should -Be 100
    }

    It 'puts eligible candidates ahead of inconclusive candidates even when the latter appears first' {
        $short = New-Candidate 'aaa-inconclusive.bat' @((New-Observation Discord $true $true),(New-HealthyControl))
        $eligible = New-Candidate 'zzz-eligible.bat' @(
            (New-Observation Discord $true $true), (New-Observation Discord $true $true), (New-Observation Discord $true $true),
            (New-Observation YouTube $true $true), (New-Observation YouTube $true $true), (New-Observation YouTube $true $true),
            (New-HealthyControl)
        )
        $ranked = @(Get-NrStrategyRanking064 -Candidates @($short,$eligible))
        $ranked[0].strategy | Should -Be 'zzz-eligible.bat'
        $ranked[0].rankingState | Should -Be 'eligible'
        $ranked[1].rankingState | Should -Be 'inconclusive'
    }
}
