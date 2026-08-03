Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-NrStrategyLabSpeedTarget {
    $bytes=8388608L
    if ($script:NrState -and $script:NrState.PSObject.Properties['speedTestBytes']) {
        try { $bytes=[long]$script:NrState.speedTestBytes } catch { }
    }
    if ($bytes -lt 1048576L) { $bytes=1048576L }
    if ($bytes -gt 67108864L) { $bytes=67108864L }

    $uriText=[string]$env:NEXROUTE_SPEEDTEST_URI
    if ([string]::IsNullOrWhiteSpace($uriText) -and $script:NrState -and $script:NrState.PSObject.Properties['speedTestUri']) {
        $uriText=[string]$script:NrState.speedTestUri
    }
    if ([string]::IsNullOrWhiteSpace($uriText)) {
        $uriText='https://speed.cloudflare.com/__down?bytes=' + $bytes
    }
    return [pscustomobject]@{ uri=[Uri]$uriText; bytes=$bytes }
}

function Get-NrStrategyLabHlsManifestUri {
    $value=[string]$env:NEXROUTE_YOUTUBE_HLS_URI
    if ([string]::IsNullOrWhiteSpace($value) -and $script:NrState -and $script:NrState.PSObject.Properties['youtubeHlsManifestUri']) {
        $value=[string]$script:NrState.youtubeHlsManifestUri
    }
    if ([string]::IsNullOrWhiteSpace($value)) { return $null }
    try { return [Uri]$value } catch { return $null }
}

function Invoke-NrSafeStreamingProbe {
    $target=Get-NrStrategyLabSpeedTarget
    try {
        return Measure-NrStreamingDownload -Uri $target.uri -TargetBytes $target.bytes -TimeoutSeconds 35
    } catch {
        return [pscustomobject]@{
            uri=$target.uri.AbsoluteUri; ok=$false; requestedBytes=$target.bytes; receivedBytes=0L;
            elapsedMs=0; megabitsPerSecond=0; statusCode=0; error=$_.Exception.Message
        }
    }
}

function Invoke-NrSafeYoutubePlaybackProbe {
    $manifest=Get-NrStrategyLabHlsManifestUri
    if (-not $manifest) {
        return [pscustomobject]@{ ok=$false; status='not-configured'; mode='hls'; manifestUri=$null; segmentBytes=0L }
    }
    try {
        $result=Test-NrHlsPlaybackReadiness -ManifestUri $manifest -TimeoutSeconds 25 -MinimumSegmentBytes 32768
        return [pscustomobject]@{
            ok=[bool]$result.ok; status=$(if ($result.ok) { 'ready' } else { 'segment-too-small' }); mode='hls';
            manifestUri=$result.manifestUri; mediaPlaylistUri=$result.mediaPlaylistUri; segmentUri=$result.segmentUri;
            segmentBytes=[long]$result.segmentBytes; elapsedMs=[double]$result.elapsedMs; usedMasterPlaylist=[bool]$result.usedMasterPlaylist
        }
    } catch {
        return [pscustomobject]@{ ok=$false; status='failed'; mode='hls'; manifestUri=$manifest.AbsoluteUri; segmentBytes=0L; error=$_.Exception.Message }
    }
}

function Invoke-NrSafeTlsProbe {
    param([Parameter(Mandatory)][string]$HostName)
    try { return Test-NrTlsTransportReadiness -HostName $HostName -Port 443 -TimeoutSeconds 10 }
    catch { return [pscustomobject]@{ ok=$false; host=$HostName; port=443; elapsedMs=0; protocol=$null; error=$_.Exception.Message } }
}

function Get-NrStrategyScoreV2 {
    param(
        [double]$Availability,
        [double]$HttpLatency,
        [double]$PacketLoss,
        [double]$Jitter,
        [double]$DownloadMbps,
        [bool]$PlaybackReady,
        [bool]$PlaybackConfigured,
        [bool]$DiscordTransportReady,
        [bool]$TelegramTransportReady
    )
    $score=0.0
    $score += [Math]::Min(55.0,[Math]::Max(0.0,$Availability*0.55))
    $score += [Math]::Max(0.0,15.0-($HttpLatency/150.0))
    $score += [Math]::Max(0.0,10.0-($PacketLoss/2.0))
    $score += [Math]::Max(0.0,8.0-($Jitter/15.0))
    $score += [Math]::Min(8.0,[Math]::Max(0.0,$DownloadMbps/10.0))
    if ($PlaybackConfigured -and $PlaybackReady) { $score += 2.0 }
    if ($DiscordTransportReady) { $score += 1.0 }
    if ($TelegramTransportReady) { $score += 1.0 }
    return [Math]::Round([Math]::Min(100.0,[Math]::Max(0.0,$score)),2)
}

function Invoke-NrStrategyProbe {
    param([Parameter(Mandatory)][System.IO.FileInfo]$Strategy)
    $started=Start-NrTemporaryStrategy -Strategy $Strategy
    try {
        $targets=Get-NrProbeTargets
        $http=New-Object 'System.Collections.Generic.List[object]'
        foreach ($target in $targets) { $http.Add((Measure-NrHttpEndpoint -Name $target.name -Uri $target.uri)) }

        $pings=New-Object 'System.Collections.Generic.List[object]'
        foreach ($target in @('1.1.1.1','8.8.8.8','discord.com','api.telegram.org')) {
            $pings.Add((Measure-NrPingMetrics -Target $target -Count 4))
        }

        $throughput=Invoke-NrSafeStreamingProbe
        $youtubePlayback=Invoke-NrSafeYoutubePlaybackProbe
        $discordTls=Invoke-NrSafeTlsProbe -HostName 'discord.com'
        $telegramTls=Invoke-NrSafeTlsProbe -HostName 'api.telegram.org'

        $okCount=@($http | Where-Object { $_.ok }).Count
        $availability=if ($http.Count -gt 0) { [Math]::Round(($okCount/[double]$http.Count)*100.0,2) } else { 0.0 }
        $latencies=@($http | Where-Object { $_.ok } | ForEach-Object { [double]$_.latencyMs })
        $httpLatency=if ($latencies.Count -gt 0) { [double](($latencies | Measure-Object -Average).Average) } else { 5000.0 }
        $loss=if ($pings.Count -gt 0) { [double](($pings | Measure-Object -Property packetLossPercent -Average).Average) } else { 100.0 }
        $jitter=if ($pings.Count -gt 0) { [double](($pings | Measure-Object -Property jitterMs -Average).Average) } else { 9999.0 }
        $download=if ($throughput.ok) { [double]$throughput.megabitsPerSecond } else { 0.0 }

        $discordHttp=@($http | Where-Object { $_.name -eq 'Discord' } | Select-Object -First 1)
        $telegramHttp=@($http | Where-Object { $_.name -eq 'Telegram' } | Select-Object -First 1)
        $discordReady=[bool]($discordTls.ok -and $discordHttp.Count -gt 0 -and $discordHttp[0].ok -and $loss -lt 10 -and $jitter -lt 100)
        $telegramReady=[bool]($telegramTls.ok -and $telegramHttp.Count -gt 0 -and $telegramHttp[0].ok -and $loss -lt 10 -and $jitter -lt 100)
        $playbackConfigured=([string]$youtubePlayback.status -ne 'not-configured')
        $score=Get-NrStrategyScoreV2 -Availability $availability -HttpLatency $httpLatency -PacketLoss $loss -Jitter $jitter -DownloadMbps $download -PlaybackReady ([bool]$youtubePlayback.ok) -PlaybackConfigured $playbackConfigured -DiscordTransportReady $discordReady -TelegramTransportReady $telegramReady

        return [pscustomobject]@{
            schemaVersion=3
            strategy=$Strategy.Name
            started=$started
            score=$score
            availabilityPercent=$availability
            averageHttpLatencyMs=[Math]::Round($httpLatency,2)
            averagePacketLossPercent=[Math]::Round($loss,2)
            averageJitterMs=[Math]::Round($jitter,2)
            measuredDownloadMbps=[Math]::Round($download,3)
            throughputReceivedBytes=[long]$throughput.receivedBytes
            throughputRequestedBytes=[long]$throughput.requestedBytes
            throughputOk=[bool]$throughput.ok
            youtubePlaybackReady=[bool]$youtubePlayback.ok
            youtubePlaybackProbeStatus=[string]$youtubePlayback.status
            youtubePlaybackMode=[string]$youtubePlayback.mode
            youtubeSegmentBytes=[long]$youtubePlayback.segmentBytes
            discordRealtimeTransportReady=$discordReady
            telegramRealtimeTransportReady=$telegramReady
            http=$http.ToArray()
            ping=$pings.ToArray()
            throughput=$throughput
            youtubePlayback=$youtubePlayback
            discordTransport=$discordTls
            telegramTransport=$telegramTls
        }
    } finally {
        Stop-NrStrategyRuntime
    }
}

function Invoke-NrStrategyLab {
    $strategies=@(Get-NrStrategies)
    if ($strategies.Count -eq 0) { Show-NrMessage -Title (T 'strategyLab') -Message (T 'noStrategies') -Color Red; return }
    $items=@($strategies | ForEach-Object { [pscustomobject]@{ Id=$_.Name; Label=$_.BaseName; Status='' } })
    $selected=Invoke-NrMultiSelect -Title (T 'strategyLab') -Items $items
    if ($null -eq $selected -or $selected.Count -eq 0) { return }
    $chosen=@($strategies | Where-Object { $selected -contains $_.Name })
    $original=Get-NrInstalledStrategy
    $results=New-Object 'System.Collections.Generic.List[object]'
    try {
        for ($index=0;$index -lt $chosen.Count;$index++) {
            Write-NrHeader -Title (T 'strategyLab')
            Write-Host ('  [{0}/{1}] {2}' -f ($index+1),$chosen.Count,$chosen[$index].BaseName) -ForegroundColor Cyan
            Write-Host '  HTTP / packet loss / jitter / streamed download / media segment / TLS transport' -ForegroundColor DarkGray
            try { $results.Add((Invoke-NrStrategyProbe -Strategy $chosen[$index])) }
            catch {
                $results.Add([pscustomobject]@{ schemaVersion=3; strategy=$chosen[$index].Name; started=$false; score=0; availabilityPercent=0; error=$_.Exception.Message })
                Write-NrLog -Level ERROR -Message 'Strategy Lab v2 probe failed' -Data @{ strategy=$chosen[$index].Name; error=$_.Exception.Message }
            }
        }
    } finally {
        Stop-NrStrategyRuntime
        if ($original -and $original -ne 'none') {
            $restore=$strategies | Where-Object { $_.BaseName -eq $original -or $_.Name -eq ($original + '.bat') } | Select-Object -First 1
            if ($restore) { try { Install-NrStrategy -Strategy $restore -Silent } catch { } }
        }
    }

    $sorted=@($results | Sort-Object score -Descending)
    $directory=Join-Path $script:NrHistoryDir 'strategy-lab'
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $stamp=[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
    $document=[ordered]@{ schemaVersion=3; createdUtc=[DateTime]::UtcNow.ToString('o'); network=Get-NrActiveNetworkKey; results=$sorted }
    [IO.File]::WriteAllText((Join-Path $directory ($stamp+'.json')),($document | ConvertTo-Json -Depth 24)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
    $sorted | Select-Object strategy,score,availabilityPercent,averageHttpLatencyMs,averagePacketLossPercent,averageJitterMs,measuredDownloadMbps,throughputReceivedBytes,youtubePlaybackReady,youtubePlaybackProbeStatus,discordRealtimeTransportReady,telegramRealtimeTransportReady | Export-Csv -LiteralPath (Join-Path $directory ($stamp+'.csv')) -NoTypeInformation -Encoding UTF8

    Write-NrHeader -Title (T 'strategyLab')
    $rank=1
    foreach ($result in $sorted) {
        Write-Host ('  {0,2}. {1,-32} SCORE {2,6:N2}  DOWN {3,7:N2} Mbps  MEDIA {4}' -f $rank,$result.strategy,$result.score,$result.measuredDownloadMbps,$result.youtubePlaybackProbeStatus) -ForegroundColor $(if ($rank -eq 1) { [ConsoleColor]::Green } else { [ConsoleColor]::Gray })
        $rank++
    }
    if ($sorted.Count -gt 0) {
        $script:NrState.lastWorkingStrategy=[string]$sorted[0].strategy
        Save-NrState
        Send-NrNotification -Title 'NexRoute Strategy Lab' -Message ('Best: '+$sorted[0].strategy+' / '+$sorted[0].score) -Level Info
    }
    Wait-NrKey
}

function Show-NrLabHistory {
    $directory=Join-Path $script:NrHistoryDir 'strategy-lab'
    $files=@(Get-ChildItem -LiteralPath $directory -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending)
    if ($files.Count -eq 0) { Show-NrMessage -Title (T 'labCompare') -Message (T 'noResults') -Color Yellow; return }
    $items=@($files | ForEach-Object { New-NrMenuItem -Id $_.FullName -Label $_.BaseName -Section (T 'history') -Status $_.LastWriteTime.ToString('g') })
    $choice=Invoke-NrMenu -Title (T 'labCompare') -Items $items -AllowEscape
    if (-not $choice) { return }
    $run=Get-Content -LiteralPath $choice -Raw -Encoding UTF8 | ConvertFrom-Json
    Write-NrHeader -Title (T 'labCompare')
    foreach ($result in @($run.results | Sort-Object score -Descending)) {
        $download=if ($result.PSObject.Properties['measuredDownloadMbps']) { [double]$result.measuredDownloadMbps } elseif ($result.PSObject.Properties['peakDownloadMbps']) { [double]$result.peakDownloadMbps } else { 0.0 }
        Write-Host ('  {0,-32} score={1,6:N2} down={2,7:N2}Mbps jitter={3,6:N1} loss={4,5:N1}%' -f $result.strategy,$result.score,$download,$result.averageJitterMs,$result.averagePacketLossPercent) -ForegroundColor Gray
    }
    Wait-NrKey
}
