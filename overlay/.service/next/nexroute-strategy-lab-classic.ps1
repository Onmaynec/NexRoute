Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-NrLabProgress065 {
    param(
        [string]$Label,
        [int]$Current,
        [int]$Total,
        [ConsoleColor]$Color = [ConsoleColor]::Red
    )
    $totalSafe = [Math]::Max(1,$Total)
    $percent = [Math]::Min(100,[Math]::Max(0,[int][Math]::Round(($Current/[double]$totalSafe)*100)))
    $barWidth = 34
    $filled = [Math]::Min($barWidth,[int][Math]::Floor($barWidth*($percent/100.0)))
    $bar = ('#' * $filled) + ('-' * ($barWidth-$filled))
    Write-Host ('  {0,-28} [{1}] {2,3}%' -f $Label,$bar,$percent) -ForegroundColor $Color
}

function Write-NrLabCheck065 {
    param(
        [ValidateSet('OK','WARN','FAIL','SKIP','INFO')][string]$State,
        [string]$Label,
        [string]$Details = ''
    )
    $color = switch ($State) {
        'OK' { [ConsoleColor]::Green }
        'WARN' { [ConsoleColor]::Yellow }
        'FAIL' { [ConsoleColor]::Red }
        'SKIP' { [ConsoleColor]::DarkGray }
        default { [ConsoleColor]::Gray }
    }
    $suffix = if ([string]::IsNullOrWhiteSpace($Details)) { '' } else { '  ' + $Details }
    Write-Host ('  [{0,-4}] {1}{2}' -f $State,$Label,$suffix) -ForegroundColor $color
}

function Get-NrLabControlTargets065 {
    $targets = New-Object 'System.Collections.Generic.List[object]'
    foreach ($target in @(Get-NrProbeTargets)) { $targets.Add($target) }
    if (@($targets | Where-Object { $_.name -eq 'CloudflareWeb' }).Count -eq 0) {
        $targets.Add([pscustomobject]@{
            name='CloudflareWeb'
            uri='https://www.cloudflare.com/cdn-cgi/trace'
            host='www.cloudflare.com'
            kind='control'
        })
    }
    return @($targets | Group-Object uri | ForEach-Object { $_.Group[0] })
}

function Test-NrLabDns065 {
    param([Parameter(Mandatory)][string]$HostName)
    $watch=[Diagnostics.Stopwatch]::StartNew()
    try {
        $records=@(Resolve-DnsName -Name $HostName -Type A -DnsOnly -ErrorAction Stop | Where-Object { $_.IPAddress })
        $watch.Stop()
        return [pscustomobject]@{
            ok=($records.Count -gt 0)
            host=$HostName
            elapsedMs=[math]::Round($watch.Elapsed.TotalMilliseconds,2)
            addresses=@($records | ForEach-Object { [string]$_.IPAddress } | Select-Object -Unique)
            error=$null
        }
    } catch {
        $watch.Stop()
        return [pscustomobject]@{
            ok=$false
            host=$HostName
            elapsedMs=[math]::Round($watch.Elapsed.TotalMilliseconds,2)
            addresses=@()
            error=$_.Exception.Message
        }
    }
}

function Test-NrLabDpiFreeze065 {
    param([int]$TimeoutSeconds=15)
    $curl=Get-Command curl.exe -ErrorAction SilentlyContinue
    if (-not $curl) {
        return [pscustomobject]@{ supported=$false; ok=$null; status='curl-missing'; bytes=0L; seconds=0.0; httpCode=0; likelyFreeze=$false }
    }

    $format='NR|%{http_code}|%{size_download}|%{time_total}'
    $uri='https://speed.cloudflare.com/__down?bytes=65536'
    $output=''
    $exitCode=0
    try {
        $output = & $curl.Source -L -sS --range '0-32767' --max-time $TimeoutSeconds -o NUL -w $format $uri 2>&1 | Out-String
        $exitCode=$LASTEXITCODE
    } catch {
        $output=$_.Exception.Message
        $exitCode=1
    }

    $match=[regex]::Match($output,'NR\|(?<code>\d{3})\|(?<bytes>\d+)\|(?<time>[0-9.]+)')
    if (-not $match.Success) {
        return [pscustomobject]@{ supported=$true; ok=$false; status='probe-error'; bytes=0L; seconds=0.0; httpCode=0; likelyFreeze=$false; error=$output.Trim() }
    }

    $bytes=[long]$match.Groups['bytes'].Value
    $seconds=[double]$match.Groups['time'].Value
    $code=[int]$match.Groups['code'].Value
    $likelyFreeze=($exitCode -ne 0 -and $bytes -ge 16384 -and $bytes -le 20480)
    $ok=($exitCode -eq 0 -and $code -ge 200 -and $code -lt 500 -and $bytes -ge 24576)
    $status=if ($likelyFreeze) { 'likely-16-20kb-freeze' } elseif ($ok) { 'clear' } else { 'failed' }
    return [pscustomobject]@{ supported=$true; ok=$ok; status=$status; bytes=$bytes; seconds=$seconds; httpCode=$code; likelyFreeze=$likelyFreeze; exitCode=$exitCode }
}

function Get-NrLabPreflight065 {
    $checks=New-Object 'System.Collections.Generic.List[object]'
    $checks.Add([pscustomobject]@{ id='admin'; required=$true; ok=[bool](Test-NrAdministrator); details='Administrator privileges' })
    $checks.Add([pscustomobject]@{ id='winws'; required=$true; ok=(Test-Path -LiteralPath (Join-Path $script:NrRoot 'bin\winws.exe') -PathType Leaf); details='bin\\winws.exe' })
    $checks.Add([pscustomobject]@{ id='windivert'; required=$true; ok=(Test-Path -LiteralPath (Join-Path $script:NrRoot 'bin\WinDivert64.sys') -PathType Leaf); details='bin\\WinDivert64.sys' })
    $checks.Add([pscustomobject]@{ id='curl'; required=$false; ok=[bool](Get-Command curl.exe -ErrorAction SilentlyContinue); details='curl.exe / DPI range probe' })
    $strategyCount=@(Get-NrStrategies).Count
    $checks.Add([pscustomobject]@{ id='strategies'; required=$true; ok=($strategyCount -gt 0); details=($strategyCount.ToString() + ' strategy files') })

    $control=$null
    try { $control=Measure-NrHttpEndpoint -Name 'Control' -Uri 'https://api.github.com' -TimeoutSec 8 } catch { }
    $checks.Add([pscustomobject]@{
        id='network'
        required=$true
        ok=($null -ne $control -and [bool]$control.ok)
        details=$(if ($control -and $control.ok) { ('GitHub control / ' + [math]::Round([double]$control.latencyMs,0) + ' ms') } else { 'GitHub control failed' })
    })
    return $checks.ToArray()
}

function Show-NrLabPreflight065 {
    Write-NrHeader -Title (T 'strategyLab')
    Write-NrPanel -Title (T 'labPreflight')
    $checks=@(Get-NrLabPreflight065)
    foreach ($check in $checks) {
        $state=if ($check.ok) { 'OK' } elseif ($check.required) { 'FAIL' } else { 'WARN' }
        Write-NrLabCheck065 -State $state -Label ([string]$check.id).ToUpperInvariant() -Details ([string]$check.details)
    }
    $requiredFailures=@($checks | Where-Object { $_.required -and -not $_.ok })
    if ($requiredFailures.Count -gt 0) {
        Write-Host ''
        Write-NrLabCheck065 -State 'FAIL' -Label 'PREFLIGHT' -Details 'Required checks failed. Strategy testing was not started.'
        Wait-NrKey
        return $false
    }
    Write-Host ''
    Write-NrLabCheck065 -State 'OK' -Label 'PREFLIGHT' -Details 'Ready to test strategies.'
    Start-Sleep -Milliseconds 450
    return $true
}

function New-NrLabObservation065 {
    param(
        [int]$Round,
        [string]$Target,
        [string]$Protocol,
        [bool]$Critical,
        [bool]$Control,
        $Success,
        $LatencyMs,
        $PacketLossPercent,
        $JitterMs,
        $ThroughputMbps,
        [string]$Details=''
    )
    return [pscustomobject]@{
        round=$Round
        target=$Target
        protocol=$Protocol
        critical=$Critical
        control=$Control
        success=$Success
        latencyMs=$LatencyMs
        packetLossPercent=$PacketLossPercent
        jitterMs=$JitterMs
        throughputMbps=$ThroughputMbps
        details=$Details
    }
}

function Test-NrLabCriticalTarget065 {
    param($Target)
    $name=[string]$Target.name
    $kind=[string]$Target.kind
    if ($kind -eq 'control') { return $false }
    return ($kind -eq 'service' -or $name -match '^(YouTube|Discord)$')
}

function Invoke-NrStrategyProbe065 {
    param(
        [Parameter(Mandatory)][System.IO.FileInfo]$Strategy,
        [ValidateRange(2,5)][int]$RepeatCount=3,
        [int]$StrategyIndex=1,
        [int]$StrategyTotal=1
    )

    $startedAt=[DateTime]::UtcNow
    $observations=New-Object 'System.Collections.Generic.List[object]'
    $details=New-Object 'System.Collections.Generic.List[object]'
    $started=$false
    $pass=0; $fail=0; $warn=0

    Write-NrHeader -Title (T 'strategyLab')
    Write-NrPanel -Title ('CONFIG {0}/{1} // {2}' -f $StrategyIndex,$StrategyTotal,$Strategy.BaseName)
    Write-NrLabCheck065 -State 'INFO' -Label 'START' -Details 'Stopping previous runtime and launching this strategy...'

    try {
        $started=[bool](Start-NrTemporaryStrategy -Strategy $Strategy)
        if ($started) {
            $pass++
            Write-NrLabCheck065 -State 'OK' -Label 'WINWS' -Details 'Process is running.'
        } else {
            $fail++
            Write-NrLabCheck065 -State 'FAIL' -Label 'WINWS' -Details 'Strategy did not start winws.exe.'
            return [pscustomobject]@{
                strategy=$Strategy.Name; started=$false; observations=@(); diagnostics=@(); passedChecks=$pass; failedChecks=$fail; warningChecks=$warn;
                elapsedMs=[math]::Round(([DateTime]::UtcNow-$startedAt).TotalMilliseconds,0); probeError='strategy did not start'
            }
        }

        $targets=@(Get-NrLabControlTargets065)
        for($round=1;$round -le $RepeatCount;$round++) {
            Write-Host ''
            Write-NrPanel -Title (('{0} {1}/{2}' -f (T 'labRound'),$round,$RepeatCount))
            Write-NrLabProgress065 -Label ('Strategy ' + $Strategy.BaseName) -Current (($round-1)*$targets.Count) -Total ($RepeatCount*$targets.Count)

            $pings=New-Object 'System.Collections.Generic.List[object]'
            foreach($pingTarget in @('1.1.1.1','8.8.8.8','discord.com','api.telegram.org')) {
                try { $pings.Add((Measure-NrPingMetrics -Target $pingTarget -Count 3)) } catch { }
            }
            $loss=Get-NrOptionalAverage064 -Values @($pings | ForEach-Object { Get-NrObservationProperty064 -Observation $_ -Name 'packetLossPercent' })
            $jitter=Get-NrOptionalAverage064 -Values @($pings | ForEach-Object { Get-NrObservationProperty064 -Observation $_ -Name 'jitterMs' })
            $pingOk=($null -ne $loss -and [double]$loss -lt 50)
            $observations.Add((New-NrLabObservation065 -Round $round -Target 'NetworkPing' -Protocol 'ICMP' -Critical $false -Control $false -Success $pingOk -LatencyMs $null -PacketLossPercent $loss -JitterMs $jitter -ThroughputMbps $null -Details '1.1.1.1 / 8.8.8.8 / Discord / Telegram'))
            if ($pingOk) { $pass++; Write-NrLabCheck065 -State 'OK' -Label 'PING' -Details ('loss={0:N1}% jitter={1:N1}ms' -f $loss,$jitter) }
            else { $warn++; Write-NrLabCheck065 -State 'WARN' -Label 'PING' -Details ('loss={0} jitter={1}' -f $loss,$jitter) }

            $targetIndex=0
            foreach($target in $targets) {
                $targetIndex++
                $name=[string]$target.name
                $host=[string]$target.host
                $critical=[bool](Test-NrLabCriticalTarget065 -Target $target)
                $control=([string]$target.kind -eq 'control')

                $dns=Test-NrLabDns065 -HostName $host
                $observations.Add((New-NrLabObservation065 -Round $round -Target $name -Protocol 'DNS' -Critical $false -Control $false -Success ([bool]$dns.ok) -LatencyMs $dns.elapsedMs -PacketLossPercent $loss -JitterMs $jitter -ThroughputMbps $null -Details ($dns.addresses -join ',')))
                if ($dns.ok) { $pass++; Write-NrLabCheck065 -State 'OK' -Label ('DNS ' + $name) -Details ('{0:N0} ms / {1}' -f $dns.elapsedMs,(@($dns.addresses) -join ', ')) }
                else { $fail++; Write-NrLabCheck065 -State 'FAIL' -Label ('DNS ' + $name) -Details ([string]$dns.error) }

                $tls=$null
                try { $tls=Test-NrTlsTransportReadiness -HostName $host -Port 443 -TimeoutSeconds 8 } catch { }
                $tlsOk=($null -ne $tls -and [bool]$tls.ok)
                $tlsLatency=if ($tls -and $tls.PSObject.Properties['elapsedMs']) { [double]$tls.elapsedMs } else { $null }
                $observations.Add((New-NrLabObservation065 -Round $round -Target $name -Protocol 'TLS' -Critical $critical -Control $false -Success $tlsOk -LatencyMs $tlsLatency -PacketLossPercent $loss -JitterMs $jitter -ThroughputMbps $null -Details $(if($tls){[string]$tls.protocol}else{''})))
                if ($tlsOk) { $pass++; Write-NrLabCheck065 -State 'OK' -Label ('TLS ' + $name) -Details ('{0:N0} ms / {1}' -f $tlsLatency,[string]$tls.protocol) }
                else { $fail++; Write-NrLabCheck065 -State 'FAIL' -Label ('TLS ' + $name) -Details 'Handshake failed.' }

                $http=$null
                try { $http=Measure-NrHttpEndpoint -Name $name -Uri ([string]$target.uri) -TimeoutSec 12 } catch { }
                $httpOk=($null -ne $http -and [bool]$http.ok)
                $httpLatency=if ($http) { [double]$http.latencyMs } else { $null }
                $throughput=if ($http -and [double]$http.megabitsPerSecond -gt 0) { [double]$http.megabitsPerSecond } else { $null }
                $observations.Add((New-NrLabObservation065 -Round $round -Target $name -Protocol 'HTTPS' -Critical $critical -Control $control -Success $httpOk -LatencyMs $httpLatency -PacketLossPercent $loss -JitterMs $jitter -ThroughputMbps $throughput -Details $(if($http){'HTTP '+[string]$http.statusCode}else{'no response'})))
                if ($httpOk) { $pass++; Write-NrLabCheck065 -State 'OK' -Label ('HTTP ' + $name) -Details ('code={0}  {1:N0} ms' -f $http.statusCode,$httpLatency) }
                else { $fail++; Write-NrLabCheck065 -State 'FAIL' -Label ('HTTP ' + $name) -Details $(if($http){[string]$http.error}else{'No response'}) }

                Write-NrLabProgress065 -Label ('Round ' + $round) -Current ((($round-1)*$targets.Count)+$targetIndex) -Total ($RepeatCount*$targets.Count) -Color DarkRed
            }
        }

        Write-Host ''
        Write-NrPanel -Title 'DEEP CHECKS'

        $stream=$null
        try { $stream=Invoke-NrSafeStreamingProbe } catch { }
        if ($stream -and $stream.ok) {
            $pass++
            Write-NrLabCheck065 -State 'OK' -Label (T 'labThroughput') -Details ('{0:N2} Mbps / {1:N0} KB' -f $stream.megabitsPerSecond,([double]$stream.receivedBytes/1KB))
            $observations.Add((New-NrLabObservation065 -Round 0 -Target 'CloudflareSpeed' -Protocol 'STREAM' -Critical $false -Control $false -Success $true -LatencyMs $stream.elapsedMs -PacketLossPercent $null -JitterMs $null -ThroughputMbps $stream.megabitsPerSecond -Details ([string]$stream.uri)))
        } else {
            $warn++
            Write-NrLabCheck065 -State 'WARN' -Label (T 'labThroughput') -Details 'Streaming measurement unavailable.'
        }

        $media=$null
        try { $media=Invoke-NrSafeYoutubePlaybackProbe } catch { }
        if ($media -and [string]$media.status -eq 'not-configured') {
            $warn++
            Write-NrLabCheck065 -State 'SKIP' -Label (T 'labMedia') -Details 'HLS URI is not configured; HTTP/TLS YouTube checks are still included.'
        } elseif ($media -and $media.ok) {
            $pass++
            Write-NrLabCheck065 -State 'OK' -Label (T 'labMedia') -Details ('segment={0:N0} KB' -f ([double]$media.segmentBytes/1KB))
            $observations.Add((New-NrLabObservation065 -Round 0 -Target 'YouTubeMedia' -Protocol 'HLS' -Critical $true -Control $false -Success $true -LatencyMs $media.elapsedMs -PacketLossPercent $null -JitterMs $null -ThroughputMbps $null -Details 'media segment ready'))
        } else {
            $warn++
            Write-NrLabCheck065 -State 'WARN' -Label (T 'labMedia') -Details 'Media probe did not confirm playback readiness.'
            if ($media) { $observations.Add((New-NrLabObservation065 -Round 0 -Target 'YouTubeMedia' -Protocol 'HLS' -Critical $true -Control $false -Success $false -LatencyMs $null -PacketLossPercent $null -JitterMs $null -ThroughputMbps $null -Details ([string]$media.status))) }
        }

        $dpi=Test-NrLabDpiFreeze065
        if (-not $dpi.supported) {
            $warn++
            Write-NrLabCheck065 -State 'SKIP' -Label (T 'labDpiFreeze') -Details 'curl.exe is not available.'
        } elseif ($dpi.likelyFreeze) {
            $fail++
            Write-NrLabCheck065 -State 'FAIL' -Label (T 'labDpiFreeze') -Details ('possible 16-20 KB freeze / {0} bytes' -f $dpi.bytes)
            $observations.Add((New-NrLabObservation065 -Round 0 -Target 'DpiRange' -Protocol 'DPI' -Critical $false -Control $false -Success $false -LatencyMs ($dpi.seconds*1000) -PacketLossPercent $null -JitterMs $null -ThroughputMbps $null -Details $dpi.status))
        } elseif ($dpi.ok) {
            $pass++
            Write-NrLabCheck065 -State 'OK' -Label (T 'labDpiFreeze') -Details ('range completed / {0} bytes / {1:N2}s' -f $dpi.bytes,$dpi.seconds)
            $observations.Add((New-NrLabObservation065 -Round 0 -Target 'DpiRange' -Protocol 'DPI' -Critical $false -Control $false -Success $true -LatencyMs ($dpi.seconds*1000) -PacketLossPercent $null -JitterMs $null -ThroughputMbps $null -Details $dpi.status))
        } else {
            $warn++
            Write-NrLabCheck065 -State 'WARN' -Label (T 'labDpiFreeze') -Details ('probe failed without 16-20 KB signature / bytes=' + $dpi.bytes)
        }

        $details.Add([pscustomobject]@{ throughput=$stream; media=$media; dpi=$dpi })
    } finally {
        Stop-NrStrategyRuntime
    }

    $elapsed=[math]::Round(([DateTime]::UtcNow-$startedAt).TotalMilliseconds,0)
    Write-Host ''
    Write-NrPanel -Title 'CONFIG SUMMARY'
    Write-NrLabCheck065 -State $(if($fail -eq 0){'OK'}else{'WARN'}) -Label $Strategy.BaseName -Details ('passed={0} failed={1} warnings={2} elapsed={3:N1}s' -f $pass,$fail,$warn,($elapsed/1000))

    return [pscustomobject]@{
        strategy=$Strategy.Name
        started=$started
        observations=$observations.ToArray()
        diagnostics=$details.ToArray()
        passedChecks=$pass
        failedChecks=$fail
        warningChecks=$warn
        elapsedMs=$elapsed
    }
}

function Save-NrStrategyLabRun065 {
    param([object[]]$Ranked,[int]$RepeatCount)
    $dir=Join-Path $script:NrHistoryDir 'strategy-lab'
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $stamp=[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
    $document=[ordered]@{
        schemaVersion=4
        rankingSchemaVersion=1
        interface='classic-0.2.2'
        rankingModel='critical-services-stability-v1'
        createdUtc=[DateTime]::UtcNow.ToString('o')
        network=Get-NrActiveNetworkKey
        repeatCount=$RepeatCount
        minimumObservations=6
        probes=@('runtime','dns','tls','https','icmp','stream','hls','dpi-range')
        controlPolicy='HTTP control targets must pass repeated measurements; extra probes remain visible in diagnostics'
        scoringWeights=[ordered]@{criticalAvailability=0.60;secondaryAvailability=0.10;stability=0.20;optionalTelemetry=0.10}
        missingMetricPolicy='exclude-and-renormalize'
        results=$Ranked
    }
    $jsonPath=Join-Path $dir ($stamp+'.json')
    $csvPath=Join-Path $dir ($stamp+'.csv')
    [IO.File]::WriteAllText($jsonPath,($document | ConvertTo-Json -Depth 35)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
    $Ranked | Select-Object rank,strategy,rankingState,score,criticalAvailabilityPercent,secondaryAvailabilityPercent,controlAvailabilityPercent,availabilityPercent,stabilityPercent,telemetryScorePercent,observationCount,controlObservationCount,averageHttpLatencyMs,averagePacketLossPercent,averageJitterMs,peakDownloadMbps,recommendationReason,inconclusiveReason | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
    return [pscustomobject]@{ json=$jsonPath; csv=$csvPath }
}

function Show-NrStrategyLabResults065 {
    param([object[]]$Ranked)
    Write-NrHeader -Title (T 'strategyLab')
    Write-NrPanel -Title 'RESULTS'

    foreach($result in @($Ranked | Sort-Object rank)) {
        if ($result.rankingState -eq 'eligible') {
            $color=if ([int]$result.rank -eq 1) { [ConsoleColor]::Green } else { [ConsoleColor]::Gray }
            Write-Host ('  {0,2}. {1,-30} SCORE {2,6:N2}  CRIT {3,6:N1}%  STAB {4,6:N1}%  OBS {5,3}' -f $result.rank,$result.strategy,$result.score,$result.criticalAvailabilityPercent,$result.stabilityPercent,$result.observationCount) -ForegroundColor $color
            $rates=@($result.protocolPassRates | Sort-Object protocol | ForEach-Object { '{0}:{1:N0}%' -f $_.protocol,$_.passRatePercent })
            if ($rates.Count -gt 0) { Write-Host ('      ' + ($rates -join '  ')) -ForegroundColor DarkGray }
        } else {
            Write-Host ('  {0,2}. {1,-30} INCONCLUSIVE' -f $result.rank,$result.strategy) -ForegroundColor Yellow
            Write-Host ('      ' + [string]$result.inconclusiveReason) -ForegroundColor DarkGray
        }
    }

    $winner=@($Ranked | Where-Object { $_.rankingState -eq 'eligible' } | Sort-Object rank | Select-Object -First 1)
    if ($winner.Count -gt 0) {
        Write-Host ''
        Write-NrPanel -Title 'RECOMMENDATION'
        Write-NrLabCheck065 -State 'OK' -Label $winner[0].strategy -Details ('score=' + $winner[0].score)
        if (-not [string]::IsNullOrWhiteSpace([string]$winner[0].recommendationReason)) {
            Write-Host ('  WHY: ' + $winner[0].recommendationReason) -ForegroundColor Yellow
        }
        $script:NrState.lastWorkingStrategy=[string]$winner[0].strategy
        Save-NrState
        Send-NrNotification -Title 'NexRoute Strategy Lab' -Message ('Best: '+$winner[0].strategy+' / '+$winner[0].score) -Level Info
    } else {
        Write-Host ''
        Write-NrLabCheck065 -State 'WARN' -Label 'RECOMMENDATION' -Details 'No strategy had enough clean repeated evidence.'
    }
}

function Invoke-NrStrategyLab {
    $strategies=@(Get-NrStrategies)
    if ($strategies.Count -eq 0) { Show-NrMessage -Title (T 'strategyLab') -Message (T 'noStrategies') -Color Red; return }

    $items=@(
        New-NrMenuItem -Id 'all' -Label (T 'labRunAll') -Section (T 'strategyLab')
        New-NrMenuItem -Id 'selected' -Label (T 'labRunSelected') -Section (T 'strategyLab')
        New-NrMenuItem -Id 'history' -Label (T 'labCompare') -Section (T 'strategyLab')
        New-NrMenuItem -Id 'best' -Label (T 'bestInstall') -Section (T 'strategyLab')
        New-NrMenuItem -Id 'back' -Label (T 'back') -Section ''
    )
    $mode=Invoke-NrMenu -Title (T 'strategyLab') -Items $items -AllowEscape
    if (-not $mode -or $mode -eq 'back') { return }
    if ($mode -eq 'history') { Show-NrLabHistory; return }
    if ($mode -eq 'best') { Install-NrBestStrategy; return }

    if (-not (Show-NrLabPreflight065)) { return }

    $chosen=@()
    if ($mode -eq 'all') {
        $chosen=$strategies
    } else {
        $selectItems=@($strategies | ForEach-Object { [pscustomobject]@{ Id=$_.Name; Label=$_.BaseName; Status='' } })
        $selected=Invoke-NrMultiSelect -Title (T 'strategyLab') -Items $selectItems
        if ($null -eq $selected -or $selected.Count -eq 0) { return }
        $chosen=@($strategies | Where-Object { $selected -contains $_.Name })
    }

    $original=Get-NrInstalledStrategy
    $candidates=New-Object 'System.Collections.Generic.List[object]'
    $repeatCount=3
    try {
        for($i=0;$i -lt $chosen.Count;$i++) {
            try {
                $candidates.Add((Invoke-NrStrategyProbe065 -Strategy $chosen[$i] -RepeatCount $repeatCount -StrategyIndex ($i+1) -StrategyTotal $chosen.Count))
            } catch {
                $candidates.Add([pscustomobject]@{ strategy=$chosen[$i].Name; started=$false; observations=@(); diagnostics=@(); passedChecks=0; failedChecks=1; warningChecks=0; probeError=$_.Exception.Message })
                Write-NrLog -Level ERROR -Message 'Strategy Lab 0.6.5 probe failed' -Data @{ strategy=$chosen[$i].Name; error=$_.Exception.Message }
            }
        }
    } finally {
        Stop-NrStrategyRuntime
        if ($original -and $original -ne 'none') {
            $restore=$strategies | Where-Object { $_.BaseName -eq $original -or $_.Name -eq ($original + '.bat') } | Select-Object -First 1
            if ($restore) {
                try {
                    Install-NrStrategy -Strategy $restore -Silent
                    Write-NrLog -Level INFO -Message 'Strategy Lab restored original strategy' -Data @{ strategy=$restore.Name }
                } catch {
                    Write-NrLog -Level WARN -Message 'Strategy Lab could not restore original strategy' -Data @{ strategy=$restore.Name; error=$_.Exception.Message }
                }
            }
        }
    }

    $ranked=@(Get-NrStrategyRanking064 -Candidates $candidates.ToArray())
    $paths=Save-NrStrategyLabRun065 -Ranked $ranked -RepeatCount $repeatCount
    Show-NrStrategyLabResults065 -Ranked $ranked
    Write-Host ''
    Write-Host ('  JSON: ' + $paths.json) -ForegroundColor DarkGray
    Write-Host ('  CSV : ' + $paths.csv) -ForegroundColor DarkGray
    Wait-NrKey
}
