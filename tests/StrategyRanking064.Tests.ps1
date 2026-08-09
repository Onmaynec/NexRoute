Describe 'NexRoute 0.6.4 Strategy Lab ranking' {
    BeforeAll {
        $script:root = Split-Path -Parent $PSScriptRoot
        . (Join-Path $script:root 'overlay/.service/next/nexroute-strategy-ranking.ps1')

        function New-Observation {
            param(
                [string]$Target,
                [bool]$Critical,
                $Success,
                $Latency = 50,
                $Loss = 1,
                $Jitter = 5,
                $Throughput = 10
            )
            [pscustomobject]@{
                target = $Target
                critical = $Critical
                success = $Success
                latencyMs = $Latency
                packetLossPercent = $Loss
                jitterMs = $Jitter
                throughputMbps = $Throughput
            }
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
            (New-Observation GitHub $false $false), (New-Observation GitHub $false $false), (New-Observation GitHub $false $false)
        )
        $b = New-Candidate 'secondary-first.bat' @(
            (New-Observation Discord $true $true), (New-Observation Discord $true $true), (New-Observation Discord $true $false),
            (New-Observation YouTube $true $true), (New-Observation YouTube $true $true), (New-Observation YouTube $true $false),
            (New-Observation GitHub $false $true), (New-Observation GitHub $false $true), (New-Observation GitHub $false $true)
        )

        $ranked = @(Get-NrStrategyRanking064 -Candidates @($b,$a))
        $ranked[0].strategy | Should -Be 'critical-first.bat'
        $ranked[0].criticalAvailabilityPercent | Should -Be 100
        $ranked[0].recommendationReason | Should -Match 'critical-service availability delta'
    }

    It 'uses repeated observations to reward stability when availability is otherwise tied' {
        $stable = New-Candidate 'stable.bat' @(
            (New-Observation Discord $true $true), (New-Observation Discord $true $true), (New-Observation Discord $true $true),
            (New-Observation YouTube $true $false), (New-Observation YouTube $true $false), (New-Observation YouTube $true $false)
        )
        $flappy = New-Candidate 'flappy.bat' @(
            (New-Observation Discord $true $true), (New-Observation Discord $true $false), (New-Observation Discord $true $true),
            (New-Observation YouTube $true $false), (New-Observation YouTube $true $true), (New-Observation YouTube $true $false)
        )

        $ranked = @(Get-NrStrategyRanking064 -Candidates @($flappy,$stable))
        $ranked[0].strategy | Should -Be 'stable.bat'
        $ranked[0].criticalAvailabilityPercent | Should -Be 50
        $ranked[1].criticalAvailabilityPercent | Should -Be 50
        $ranked[0].stabilityPercent | Should -BeGreaterThan $ranked[1].stabilityPercent
    }

    It 'does not coerce missing optional telemetry to zero' {
        $missingTelemetry = New-Candidate 'missing-telemetry.bat' @(
            (New-Observation Discord $true $true $null $null $null $null),
            (New-Observation Discord $true $true $null $null $null $null),
            (New-Observation Discord $true $true $null $null $null $null),
            (New-Observation YouTube $true $true $null $null $null $null),
            (New-Observation YouTube $true $true $null $null $null $null),
            (New-Observation YouTube $true $true $null $null $null $null)
        )

        $ranked = @(Get-NrStrategyRanking064 -Candidates @($missingTelemetry))
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
            (New-Observation GitHub $false $true)
        )

        $ranked = @(Get-NrStrategyRanking064 -Candidates @($candidate) -MinimumObservations 6)
        $ranked[0].rankingState | Should -Be 'inconclusive'
        $ranked[0].score | Should -BeNullOrEmpty
        $ranked[0].inconclusiveReason | Should -Match 'measured observations'
    }

    It 'uses strategy id as a deterministic final tie-break and explains it' {
        $observations = @(
            (New-Observation Discord $true $true), (New-Observation Discord $true $true), (New-Observation Discord $true $true),
            (New-Observation YouTube $true $true), (New-Observation YouTube $true $true), (New-Observation YouTube $true $true)
        )
        $z = New-Candidate 'zeta.bat' $observations
        $a = New-Candidate 'alpha.bat' $observations

        $ranked = @(Get-NrStrategyRanking064 -Candidates @($z,$a))
        $ranked[0].strategy | Should -Be 'alpha.bat'
        $ranked[0].recommendationReason | Should -Match 'deterministic strategy-id tie-break'
    }

    It 'puts eligible candidates ahead of inconclusive candidates even when the latter appears first' {
        $short = New-Candidate 'aaa-inconclusive.bat' @((New-Observation Discord $true $true))
        $eligible = New-Candidate 'zzz-eligible.bat' @(
            (New-Observation Discord $true $true), (New-Observation Discord $true $true), (New-Observation Discord $true $true),
            (New-Observation YouTube $true $true), (New-Observation YouTube $true $true), (New-Observation YouTube $true $true)
        )

        $ranked = @(Get-NrStrategyRanking064 -Candidates @($short,$eligible))
        $ranked[0].strategy | Should -Be 'zzz-eligible.bat'
        $ranked[0].rankingState | Should -Be 'eligible'
        $ranked[1].rankingState | Should -Be 'inconclusive'
    }
}
