Describe 'NexRoute 0.6.0 Strategy Lab v2 integration' {
    BeforeAll {
        $root=Split-Path -Parent $PSScriptRoot
        . (Join-Path $root 'overlay/.service/next/nexroute-media.ps1')
        . (Join-Path $root 'overlay/.service/next/nexroute-strategy-lab-v2.ps1')
        $script:NrState=[pscustomobject]@{ speedTestBytes=8388608; speedTestUri='https://speed.example.test/download'; youtubeHlsManifestUri='https://video.example.test/master.m3u8' }
        $script:fakeStrategy=[IO.FileInfo](Join-Path ([IO.Path]::GetTempPath()) 'strategy-a.bat')

        function Start-NrTemporaryStrategy { param($Strategy) return $true }
        function Stop-NrStrategyRuntime { }
        function Get-NrProbeTargets {
            return @(
                [pscustomobject]@{ name='YouTube'; uri='https://www.youtube.com/generate_204' }
                [pscustomobject]@{ name='Discord'; uri='https://discord.com/api/v9/gateway' }
                [pscustomobject]@{ name='Telegram'; uri='https://api.telegram.org' }
            )
        }
        function Measure-NrHttpEndpoint {
            param($Name,$Uri)
            return [pscustomobject]@{ name=$Name; uri=$Uri; ok=$true; latencyMs=50; megabitsPerSecond=9999 }
        }
        function Measure-NrPingMetrics {
            param($Target,$Count)
            return [pscustomobject]@{ target=$Target; averageMs=35; jitterMs=4; packetLossPercent=0; received=$Count; sent=$Count }
        }
    }

    It 'uses streamed bytes for bandwidth instead of HTTP response size' {
        Mock Measure-NrStreamingDownload {
            [pscustomobject]@{ uri='https://speed.example.test/download'; ok=$true; requestedBytes=8388608L; receivedBytes=8388608L; elapsedMs=1600; megabitsPerSecond=41.943; statusCode=200 }
        }
        Mock Test-NrHlsPlaybackReadiness {
            [pscustomobject]@{ ok=$true; manifestUri='https://video.example.test/master.m3u8'; mediaPlaylistUri='https://video.example.test/media.m3u8'; segmentUri='https://video.example.test/seg.ts'; segmentBytes=65536L; elapsedMs=400; usedMasterPlaylist=$true }
        }
        Mock Test-NrTlsTransportReadiness {
            param($HostName,$Port,$TimeoutSeconds)
            [pscustomobject]@{ ok=$true; host=$HostName; port=$Port; elapsedMs=20; protocol='Tls13' }
        }

        $result=Invoke-NrStrategyProbe -Strategy $script:fakeStrategy
        $result.schemaVersion | Should -Be 3
        $result.measuredDownloadMbps | Should -Be 41.943
        $result.throughputReceivedBytes | Should -Be 8388608
        $result.measuredDownloadMbps | Should -Not -Be 9999
        $result.youtubePlaybackReady | Should -BeTrue
        $result.youtubeSegmentBytes | Should -Be 65536
        $result.discordRealtimeTransportReady | Should -BeTrue
        $result.telegramRealtimeTransportReady | Should -BeTrue
        $result.PSObject.Properties.Name | Should -Not -Contain 'discordVoiceReady'
        $result.PSObject.Properties.Name | Should -Not -Contain 'telegramVoiceReady'
        Assert-MockCalled Measure-NrStreamingDownload -Times 1 -Exactly
        Assert-MockCalled Test-NrHlsPlaybackReadiness -Times 1 -Exactly
    }

    It 'does not claim YouTube playback when no media manifest is configured' {
        $old=$script:NrState.youtubeHlsManifestUri
        $oldEnv=$env:NEXROUTE_YOUTUBE_HLS_URI
        try {
            $script:NrState.youtubeHlsManifestUri=''
            $env:NEXROUTE_YOUTUBE_HLS_URI=$null
            Mock Measure-NrStreamingDownload {
                [pscustomobject]@{ uri='https://speed.example.test/download'; ok=$true; requestedBytes=8388608L; receivedBytes=8388608L; elapsedMs=2000; megabitsPerSecond=33.554; statusCode=200 }
            }
            Mock Test-NrHlsPlaybackReadiness { throw 'HLS probe must not run without a configured manifest.' }
            Mock Test-NrTlsTransportReadiness { param($HostName,$Port,$TimeoutSeconds) [pscustomobject]@{ ok=$true; host=$HostName; port=$Port; elapsedMs=20; protocol='Tls13' } }
            $result=Invoke-NrStrategyProbe -Strategy $script:fakeStrategy
            $result.youtubePlaybackReady | Should -BeFalse
            $result.youtubePlaybackProbeStatus | Should -Be 'not-configured'
            Assert-MockCalled Test-NrHlsPlaybackReadiness -Times 0 -Exactly
        } finally {
            $script:NrState.youtubeHlsManifestUri=$old
            $env:NEXROUTE_YOUTUBE_HLS_URI=$oldEnv
        }
    }
}
