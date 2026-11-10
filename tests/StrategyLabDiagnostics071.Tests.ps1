Describe 'NexRoute 0.7.1 Strategy Lab and diagnostics' {
    BeforeAll {
        $script:root = Split-Path -Parent $PSScriptRoot
        . (Join-Path $script:root 'overlay/.service/next/nexroute-strategy-ranking.ps1')
        . (Join-Path $script:root 'overlay/.service/next/nexroute-strategy-lab-classic.ps1')
        . (Join-Path $script:root 'overlay/.service/next/nexroute-diagnostics-071.ps1')

        function New-Nr071Observation {
            param([string]$Target,[string]$Protocol,[bool]$Critical,[bool]$Control,
                [bool]$Success,[bool]$DiagnosticOnly=$false)
            [pscustomobject]@{
                target=$Target; protocol=$Protocol; critical=$Critical
                control=$Control; success=$Success; diagnosticOnly=$DiagnosticOnly
                latencyMs=$null; packetLossPercent=$null; jitterMs=$null; throughputMbps=$null
            }
        }

        function New-Nr071SafeReport {
            [pscustomobject]@{
                nexroute=[pscustomobject]@{
                    version='0.7.1'; installedStrategy='PRIVATE_USER_SSID';
                    networkKey='PRIVATE_USER_SSID'; winwsRunning=$true
                    winDivertRunning=$false; serviceRunning=$false
                    safeMode=$false; monitorEnabled=$true
                }
                windows=[pscustomobject]@{
                    elevated=$false; version='10.0.19045'; powershell='5.1.19041.1'
                    caption='PRIVATE_USER_USERNAME'
                }
                adapters=@([pscustomobject]@{name='PRIVATE_ADAPTER'; addresses=@('192.168.100.123')})
                dns=@([pscustomobject]@{adapter='PRIVATE_ADAPTER'; servers=@('10.5.6.7')})
                conflicts=@([pscustomobject]@{
                    type='VPN'; name='PRIVATE_VPN'; status='Running'; severity='warning'
                    detail='C:\Users\PRIVATE_USER_USERNAME\vpn.exe'
                })
                userLists=@([pscustomobject]@{
                    path='C:\Users\PRIVATE_USER_USERNAME\list.txt'; valid=$false
                    changed=$true; message='PRIVATE_LIST_SECRET'
                })
                monitor=[pscustomobject]@{endpoint='https://host.invalid/?token=PRIVATE_TOKEN'}
            }
        }
    }

    It 'scores HTTPS only and cannot turn DNS/TLS success into HTTP availability' {
        $observations=@()
        foreach ($round in 1..3) {
            foreach ($target in @('Discord','YouTube')) {
                $observations+=New-Nr071Observation $target 'DNS' $false $false $true $true
                $observations+=New-Nr071Observation $target 'TLS' $true $false $true $true
                $observations+=New-Nr071Observation $target 'HTTPS' $true $false $false
            }
            $observations+=New-Nr071Observation 'GitHub' 'HTTPS' $false $true $true
        }
        $ranked=@(Get-NrStrategyRanking064 -Candidates @([pscustomobject]@{strategy='test.bat';started=$true;observations=$observations}))
        $ranked[0].rankingState | Should -Be 'eligible'
        $ranked[0].criticalAvailabilityPercent | Should -Be 0
        $ranked[0].availabilityPercent | Should -Be 0
        $ranked[0].diagnosticObservationCount | Should -Be 12
        $ranked[0].observationCount | Should -Be 6
        $ranked[0].score | Should -BeLessThan 50
        $ranked[0].discordVoiceReady | Should -BeFalse
        $ranked[0].telegramVoiceReady | Should -BeFalse
        $ranked[0].youtubeVideoReady | Should -BeFalse
        $ranked[0].voiceEvidence | Should -Be 'not-measured'
    }

    It 'does not produce a recommendation from diagnostic-only successes' {
        $observations=@()
        foreach ($round in 1..3) {
            $observations+=New-Nr071Observation 'Discord' 'DNS' $true $false $true $true
            $observations+=New-Nr071Observation 'YouTube' 'TLS' $true $false $true $true
            $observations+=New-Nr071Observation 'GitHub' 'HTTPS' $false $true $true
        }
        $ranked=@(Get-NrStrategyRanking064 -Candidates @([pscustomobject]@{strategy='dns-only.bat';started=$true;observations=$observations}))
        $ranked[0].rankingState | Should -Be 'inconclusive'
        $ranked[0].score | Should -BeNullOrEmpty
        $ranked[0].inconclusiveReason | Should -Match 'no critical-service observations'
    }

    It 'confirms HLS readiness only when a real segment observation succeeds' {
        $observations=@()
        foreach ($round in 1..3) {
            $observations+=New-Nr071Observation 'Discord' 'HTTPS' $true $false $true
            $observations+=New-Nr071Observation 'YouTube' 'HTTPS' $true $false $true
            $observations+=New-Nr071Observation 'GitHub' 'HTTPS' $false $true $true
        }
        $observations+=New-Nr071Observation 'YouTubeMedia' 'HLS' $true $false $true $true
        $ranked=@(Get-NrStrategyRanking064 -Candidates @([pscustomobject]@{strategy='hls.bat';started=$true;observations=$observations}))
        $ranked[0].rankingState | Should -Be 'eligible'
        $ranked[0].youtubeVideoReady | Should -BeTrue
        $ranked[0].mediaEvidence | Should -Be 'hls-segment'
    }

    It 'rejects HTTP 404 and partial transfers as a successful DPI-range check' {
        $ok=ConvertTo-NrDpiProbe071 -Output 'NR|206|32768|1.250' -ExitCode 0
        $ok.ok | Should -BeTrue
        $ok.status | Should -Be 'range-completed'
        (ConvertTo-NrDpiProbe071 -Output 'NR|404|32768|1.250' -ExitCode 0).ok | Should -BeFalse
        (ConvertTo-NrDpiProbe071 -Output 'NR|200|16384|1.250' -ExitCode 0).ok | Should -BeFalse
        $stall=ConvertTo-NrDpiProbe071 -Output 'NR|206|18432|15.000' -ExitCode 28
        $stall.ok | Should -BeFalse
        $stall.likelyFreeze | Should -BeTrue
        $stall.status | Should -Be 'possible-16-20kb-stall'
        (ConvertTo-NrDpiProbe071 -Output 'curl error with credential PRIVATE_TOKEN' -ExitCode 1).status | Should -Be 'probe-error'
    }

    It 'exports only allowlisted fields without adapter, DNS, user, VPN or URL identities' {
        $report=New-Nr071SafeReport
        $health=[pscustomobject]@{status='available';eligible=1;inconclusive=2;scoringModel='https-primary-071'}
        $safe=ConvertTo-NrSafeDiagnosticReport071 -Report $report -LabHealth $health
        $json=ConvertTo-Json -InputObject $safe -Depth 20
        $safe.schemaVersion | Should -Be 4
        $safe.exportType | Should -Be 'privacy-minimised'
        $safe.networkCounts.adapters | Should -Be 1
        $safe.listIntegrity.invalid | Should -Be 1
        $safe.strategyLab.inconclusive | Should -Be 2
        $safe.privacy.rawLogsIncluded | Should -BeFalse
        $safe.overallStatus | Should -Be 'attention'
        foreach ($token in @('PRIVATE_','192.168.100.123','10.5.6.7','C:\Users','token=','networkKey','addresses','servers','"monitor":','installedStrategy')) {
            $json | Should -Not -Match ([regex]::Escape($token))
        }
        @($safe.findings.code) | Should -Contain 'NR-ADMIN-001'
        @($safe.findings.code) | Should -Contain 'NR-WD-003'
        @($safe.findings.code) | Should -Contain 'NR-LIST-004'
        @($safe.findings.code) | Should -Contain 'NR-FILTER-005'
        $report.nexroute.installedStrategy | Should -Be 'PRIVATE_USER_SSID'
    }

    It 'treats absent optional observations and a healthy runtime as informational' {
        $source=New-Nr071SafeReport
        $source.windows.elevated=$true
        $source.nexroute.winDivertRunning=$true
        $source.conflicts=@()
        $source.userLists=@([pscustomobject]@{valid=$true;changed=$false})
        $safe=ConvertTo-NrSafeDiagnosticReport071 -Report $source -LabHealth ([pscustomobject]@{status='not-run';eligible=0;inconclusive=0;scoringModel='unknown'})
        $safe.overallStatus | Should -Be 'informational'
        @($safe.findings.code) | Should -Contain 'NR-DIAG-000'
        $safe.strategyLab.status | Should -Be 'not-run'
    }

    It 'requires real TLS certificate validation and safe diagnostic exports' {
        $media=Get-Content -LiteralPath (Join-Path $script:root 'overlay/.service/next/nexroute-media.ps1') -Raw -Encoding UTF8
        $diag=Get-Content -LiteralPath (Join-Path $script:root 'overlay/.service/next/nexroute-diagnostics.ps1') -Raw -Encoding UTF8
        $lab=Get-Content -LiteralPath (Join-Path $script:root 'overlay/.service/next/nexroute-strategy-lab-classic.ps1') -Raw -Encoding UTF8
        $media | Should -Not -Match ([regex]::Escape('({ $true })'))
        $media | Should -Match ([regex]::Escape('SslStream]::new($client.GetStream(),$false)'))
        $diag | Should -Match 'ConvertTo-NrSafeDiagnosticReport071'
        $diag | Should -Not -Match 'Copy-Item -LiteralPath \$log'
        $diag | Should -Not -Match 'Copy-Item -LiteralPath \$monitor'
        $lab | Should -Match "network='redacted'"
        $lab | Should -Match 'DiagnosticOnly'
    }
}
