Set-StrictMode -Version Latest

function Get-NrOptionalAverage064 {
    param($Values)
    $numeric = @($Values | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ })
    if ($numeric.Count -eq 0) { return $null }
    return [math]::Round([double](($numeric | Measure-Object -Average).Average), 3)
}

function Get-NrOptionalMaximum064 {
    param($Values)
    $numeric = @($Values | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ })
    if ($numeric.Count -eq 0) { return $null }
    return [math]::Round([double](($numeric | Measure-Object -Maximum).Maximum), 3)
}

function Get-NrObservationProperty064 {
    param($Observation, [Parameter(Mandatory)][string]$Name)
    if ($null -eq $Observation) { return $null }
    $property = $Observation.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    if ($Observation -is [System.Collections.IDictionary] -and $Observation.Contains($Name)) { return $Observation[$Name] }
    return $null
}

function Expand-NrObservations064 {
    param($Value)
    $result = New-Object 'System.Collections.Generic.List[object]'
    foreach ($item in @($Value)) {
        if ($item -is [System.Array]) {
            foreach ($nested in $item) { if ($null -ne $nested) { $result.Add($nested) } }
        } elseif ($null -ne $item) {
            $result.Add($item)
        }
    }
    return $result.ToArray()
}

function Get-NrPassRate064 {
    param([object[]]$Observations)
    $known = @($Observations | Where-Object { $null -ne (Get-NrObservationProperty064 -Observation $_ -Name 'success') })
    if ($known.Count -eq 0) { return $null }
    $passed = @($known | Where-Object { [bool](Get-NrObservationProperty064 -Observation $_ -Name 'success') }).Count
    return [math]::Round(($passed / [double]$known.Count) * 100, 3)
}

function Get-NrStrategyRanking064 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Candidates,
        [ValidateRange(1,1000)][int]$MinimumObservations = 6,
        [ValidateRange(2,10)][int]$MinimumObservationsPerCriticalTarget = 2,
        [ValidateRange(2,10)][int]$MinimumControlObservations = 2
    )

    $evaluated = New-Object 'System.Collections.Generic.List[object]'
    foreach ($candidate in @($Candidates)) {
        $strategy = [string](Get-NrObservationProperty064 -Observation $candidate -Name 'strategy')
        if ([string]::IsNullOrWhiteSpace($strategy)) { throw 'Strategy ranking candidate is missing strategy id.' }
        $startedValue = Get-NrObservationProperty064 -Observation $candidate -Name 'started'
        $started = if ($null -eq $startedValue) { $true } else { [bool]$startedValue }
        $observations = @(Expand-NrObservations064 -Value (Get-NrObservationProperty064 -Observation $candidate -Name 'observations'))
        $known = @($observations | Where-Object { $null -ne (Get-NrObservationProperty064 -Observation $_ -Name 'success') })
        $controls = @($known | Where-Object { [bool](Get-NrObservationProperty064 -Observation $_ -Name 'control') })
        $critical = @($known | Where-Object { [bool](Get-NrObservationProperty064 -Observation $_ -Name 'critical') -and -not [bool](Get-NrObservationProperty064 -Observation $_ -Name 'control') })
        $secondary = @($known | Where-Object { -not [bool](Get-NrObservationProperty064 -Observation $_ -Name 'critical') -and -not [bool](Get-NrObservationProperty064 -Observation $_ -Name 'control') })
        $scoredObservations = @($critical + $secondary)

        $targetPassRates = New-Object 'System.Collections.Generic.List[object]'
        foreach ($targetName in @($known | ForEach-Object { [string](Get-NrObservationProperty064 -Observation $_ -Name 'target') } | Sort-Object -Unique)) {
            $targetObservations = @($known | Where-Object { [string](Get-NrObservationProperty064 -Observation $_ -Name 'target') -eq $targetName })
            $targetPassed = @($targetObservations | Where-Object { [bool](Get-NrObservationProperty064 -Observation $_ -Name 'success') }).Count
            $targetPassRates.Add([pscustomobject]@{
                target = $targetName
                protocol = [string](Get-NrObservationProperty064 -Observation $targetObservations[0] -Name 'protocol')
                critical = [bool](Get-NrObservationProperty064 -Observation $targetObservations[0] -Name 'critical')
                control = [bool](Get-NrObservationProperty064 -Observation $targetObservations[0] -Name 'control')
                measured = $targetObservations.Count
                passed = $targetPassed
                passRatePercent = [math]::Round(($targetPassed / [double]$targetObservations.Count) * 100, 3)
            })
        }

        $protocolPassRates = New-Object 'System.Collections.Generic.List[object]'
        foreach ($protocolName in @($known | ForEach-Object { $value=[string](Get-NrObservationProperty064 -Observation $_ -Name 'protocol'); if ([string]::IsNullOrWhiteSpace($value)) { 'unknown' } else { $value } } | Sort-Object -Unique)) {
            $protocolObservations = @($known | Where-Object { $value=[string](Get-NrObservationProperty064 -Observation $_ -Name 'protocol'); if ([string]::IsNullOrWhiteSpace($value)) { $value='unknown' }; $value -eq $protocolName })
            $protocolPassed = @($protocolObservations | Where-Object { [bool](Get-NrObservationProperty064 -Observation $_ -Name 'success') }).Count
            $protocolPassRates.Add([pscustomobject]@{ protocol=$protocolName; measured=$protocolObservations.Count; passed=$protocolPassed; passRatePercent=[math]::Round(($protocolPassed/[double]$protocolObservations.Count)*100,3) })
        }

        $criticalTargets = @($targetPassRates | Where-Object { $_.critical -and -not $_.control })
        $controlTargets = @($targetPassRates | Where-Object { $_.control })
        $criticalCoverageOk = $criticalTargets.Count -gt 0 -and @($criticalTargets | Where-Object { $_.measured -lt $MinimumObservationsPerCriticalTarget }).Count -eq 0
        $controlCoverageOk = $controlTargets.Count -gt 0 -and @($controlTargets | Where-Object { $_.measured -lt $MinimumControlObservations }).Count -eq 0
        $controlHealthy = $controlTargets.Count -gt 0 -and @($controlTargets | Where-Object { $_.passed -ne $_.measured }).Count -eq 0

        $criticalAvailability = Get-NrPassRate064 -Observations $critical
        $secondaryAvailability = Get-NrPassRate064 -Observations $secondary
        $controlAvailability = Get-NrPassRate064 -Observations $controls
        $availability = Get-NrPassRate064 -Observations $scoredObservations

        $targetStability = New-Object 'System.Collections.Generic.List[double]'
        foreach ($target in @($targetPassRates | Where-Object { -not $_.control })) {
            if ([int]$target.measured -lt 2) { continue }
            $p = [double]$target.passed / [double]$target.measured
            $targetStability.Add([math]::Max(0,1-(4*$p*(1-$p)))*100)
        }
        $stability = if ($targetStability.Count -gt 0) { [math]::Round([double](($targetStability|Measure-Object -Average).Average),3) } else { $null }

        $latency = Get-NrOptionalAverage064 -Values @($scoredObservations | Where-Object { [bool](Get-NrObservationProperty064 -Observation $_ -Name 'success') } | ForEach-Object { Get-NrObservationProperty064 -Observation $_ -Name 'latencyMs' })
        $loss = Get-NrOptionalAverage064 -Values @($scoredObservations | ForEach-Object { Get-NrObservationProperty064 -Observation $_ -Name 'packetLossPercent' })
        $jitter = Get-NrOptionalAverage064 -Values @($scoredObservations | ForEach-Object { Get-NrObservationProperty064 -Observation $_ -Name 'jitterMs' })
        $download = Get-NrOptionalMaximum064 -Values @($scoredObservations | ForEach-Object { Get-NrObservationProperty064 -Observation $_ -Name 'throughputMbps' })
        $telemetryParts = New-Object 'System.Collections.Generic.List[double]'
        if ($null -ne $latency) { $telemetryParts.Add([math]::Max(0,[math]::Min(100,100-([double]$latency/10)))) }
        if ($null -ne $loss) { $telemetryParts.Add([math]::Max(0,[math]::Min(100,100-[double]$loss))) }
        if ($null -ne $jitter) { $telemetryParts.Add([math]::Max(0,[math]::Min(100,100-([double]$jitter/2.5)))) }
        if ($null -ne $download) { $telemetryParts.Add([math]::Max(0,[math]::Min(100,([double]$download/25)*100))) }
        $telemetry = if ($telemetryParts.Count -gt 0) { [math]::Round([double](($telemetryParts|Measure-Object -Average).Average),3) } else { $null }

        $inconclusiveReasons = New-Object 'System.Collections.Generic.List[string]'
        if (-not $started) { $inconclusiveReasons.Add('strategy did not start') }
        if ($scoredObservations.Count -lt $MinimumObservations) { $inconclusiveReasons.Add("only $($scoredObservations.Count) measured non-control observations; need $MinimumObservations") }
        if ($criticalTargets.Count -eq 0) { $inconclusiveReasons.Add('no critical-service observations') }
        elseif (-not $criticalCoverageOk) { $inconclusiveReasons.Add("at least one critical target has fewer than $MinimumObservationsPerCriticalTarget measured observations") }
        if ($controlTargets.Count -eq 0) { $inconclusiveReasons.Add('no control observations') }
        elseif (-not $controlCoverageOk) { $inconclusiveReasons.Add("control target has fewer than $MinimumControlObservations measured observations") }
        elseif (-not $controlHealthy) { $inconclusiveReasons.Add('control target failed; strategy result cannot be distinguished from general connectivity failure') }
        $eligible = $inconclusiveReasons.Count -eq 0

        $score=$null
        if ($eligible) {
            $weighted=0.0; $weight=0.0
            if ($null -ne $criticalAvailability) { $weighted += [double]$criticalAvailability*0.60; $weight += 0.60 }
            if ($null -ne $secondaryAvailability) { $weighted += [double]$secondaryAvailability*0.10; $weight += 0.10 }
            if ($null -ne $stability) { $weighted += [double]$stability*0.20; $weight += 0.20 }
            if ($null -ne $telemetry) { $weighted += [double]$telemetry*0.10; $weight += 0.10 }
            if ($weight -gt 0) { $score=[math]::Round($weighted/$weight,3) }
        }

        $youtube=@($known|Where-Object { [string](Get-NrObservationProperty064 -Observation $_ -Name 'target') -eq 'YouTube' })
        $discord=@($known|Where-Object { [string](Get-NrObservationProperty064 -Observation $_ -Name 'target') -eq 'Discord' })
        $telegram=@($known|Where-Object { [string](Get-NrObservationProperty064 -Observation $_ -Name 'target') -eq 'Telegram' })
        $youtubeReady=$youtube.Count -ge 2 -and (@($youtube|Where-Object { [bool](Get-NrObservationProperty064 -Observation $_ -Name 'success') }).Count/[double]$youtube.Count) -ge (2.0/3.0)
        $discordReady=$discord.Count -ge 2 -and (@($discord|Where-Object { [bool](Get-NrObservationProperty064 -Observation $_ -Name 'success') }).Count/[double]$discord.Count) -ge (2.0/3.0)
        $telegramReady=$telegram.Count -ge 2 -and (@($telegram|Where-Object { [bool](Get-NrObservationProperty064 -Observation $_ -Name 'success') }).Count/[double]$telegram.Count) -ge (2.0/3.0)

        $evaluated.Add([pscustomobject]@{
            strategy=$strategy; started=$started; rankingSchemaVersion=1; rankingState=$(if($eligible){'eligible'}else{'inconclusive'}); score=$score
            criticalAvailabilityPercent=$criticalAvailability; secondaryAvailabilityPercent=$secondaryAvailability; controlAvailabilityPercent=$controlAvailability; availabilityPercent=$availability
            stabilityPercent=$stability; telemetryScorePercent=$telemetry; observationCount=$scoredObservations.Count; controlObservationCount=$controls.Count
            minimumObservationCount=$MinimumObservations; criticalTargetCount=$criticalTargets.Count; controlTargetCount=$controlTargets.Count
            averageHttpLatencyMs=$latency; averagePacketLossPercent=$loss; averageJitterMs=$jitter; peakDownloadMbps=$download
            youtubeVideoReady=[bool]$youtubeReady; discordVoiceReady=[bool]$discordReady; telegramVoiceReady=[bool]$telegramReady
            targetPassRates=@($targetPassRates.ToArray()); protocolPassRates=@($protocolPassRates.ToArray())
            inconclusiveReason=$(if($eligible){$null}else{$inconclusiveReasons -join '; '}); recommendationReason=$null; observations=@($observations)
            probeError=Get-NrObservationProperty064 -Observation $candidate -Name 'probeError'
        })
    }

    $eligibleRanked=@($evaluated|Where-Object {$_.rankingState -eq 'eligible'}|Sort-Object @{Expression={[double]$_.score};Descending=$true},@{Expression={[double]$_.criticalAvailabilityPercent};Descending=$true},@{Expression={if($null-eq$_.stabilityPercent){-1}else{[double]$_.stabilityPercent}};Descending=$true},@{Expression={[string]$_.strategy};Descending=$false})
    $inconclusiveRanked=@($evaluated|Where-Object {$_.rankingState -ne 'eligible'}|Sort-Object strategy)
    $ranked=@($eligibleRanked+$inconclusiveRanked)
    for($index=0;$index-lt$ranked.Count;$index++){ $ranked[$index]|Add-Member -NotePropertyName rank -NotePropertyValue ($index+1) -Force }

    if($eligibleRanked.Count -gt 0){
        $winner=$eligibleRanked[0]
        $criticalEvidence=@($winner.targetPassRates|Where-Object {$_.critical -and -not $_.control}|ForEach-Object {'{0} {1}/{2}' -f $_.target,$_.passed,$_.measured}) -join ', '
        $controlEvidence=@($winner.targetPassRates|Where-Object {$_.control}|ForEach-Object {'{0} {1}/{2}' -f $_.target,$_.passed,$_.measured}) -join ', '
        $evidenceText="Evidence: critical [$criticalEvidence]; controls [$controlEvidence]; repeated HTTPS observations."
        if($eligibleRanked.Count -gt 1){
            $runnerUp=$eligibleRanked[1]
            $criticalDelta=[math]::Round([double]$winner.criticalAvailabilityPercent-[double]$runnerUp.criticalAvailabilityPercent,1)
            $stabilityDelta=if($null-ne$winner.stabilityPercent -and $null-ne$runnerUp.stabilityPercent){[math]::Round([double]$winner.stabilityPercent-[double]$runnerUp.stabilityPercent,1)}else{$null}
            $scoreDelta=[math]::Round([double]$winner.score-[double]$runnerUp.score,2)
            if($scoreDelta-eq0 -and $criticalDelta-eq0 -and (($null-eq$stabilityDelta)-or$stabilityDelta-eq0)){$winner.recommendationReason="$evidenceText Tied normalized measurements; deterministic strategy-id tie-break selected '$($winner.strategy)' before '$($runnerUp.strategy)'."}
            else{$stabilityText=if($null-eq$stabilityDelta){'stability n/a'}else{"stability delta $stabilityDelta pp"};$winner.recommendationReason="$evidenceText Selected over '$($runnerUp.strategy)': critical-service availability delta $criticalDelta pp; $stabilityText; normalized score delta $scoreDelta."}
        }else{$winner.recommendationReason="$evidenceText Only candidate with sufficient repeated critical-service observations and healthy controls."}
    }
    return @($ranked)
}

function Test-NrControlProbeTarget064 { param($Target) return ([string](Get-NrObservationProperty064 -Observation $Target -Name 'kind') -eq 'control') }
function Test-NrCriticalProbeTarget064 { param($Target) if(Test-NrControlProbeTarget064 -Target $Target){return $false};$kind=[string](Get-NrObservationProperty064 -Observation $Target -Name 'kind');$name=[string](Get-NrObservationProperty064 -Observation $Target -Name 'name');return($kind-eq'service'-or$name-match'^(YouTube|Discord)$') }

function Invoke-NrStrategyProbe {
    param([Parameter(Mandatory)][System.IO.FileInfo]$Strategy,[ValidateRange(2,10)][int]$RepeatCount=3)
    $started=$false;$observations=New-Object 'System.Collections.Generic.List[object]'
    try{
        $started=[bool](Start-NrTemporaryStrategy -Strategy $Strategy);$targets=@(Get-NrProbeTargets)
        for($round=1;$round-le$RepeatCount;$round++){
            $pings=New-Object 'System.Collections.Generic.List[object]'
            foreach($pingTarget in @('1.1.1.1','8.8.8.8','discord.com','api.telegram.org')){try{$pings.Add((Measure-NrPingMetrics -Target $pingTarget -Count 4))}catch{}}
            $loss=Get-NrOptionalAverage064 -Values @($pings|ForEach-Object {Get-NrObservationProperty064 -Observation $_ -Name 'packetLossPercent'});$jitter=Get-NrOptionalAverage064 -Values @($pings|ForEach-Object {Get-NrObservationProperty064 -Observation $_ -Name 'jitterMs'})
            foreach($target in $targets){
                $measurement=$null;try{$measurement=Measure-NrHttpEndpoint -Name $target.name -Uri $target.uri}catch{}
                $critical=[bool](Test-NrCriticalProbeTarget064 -Target $target);$control=[bool](Test-NrControlProbeTarget064 -Target $target)
                if($null-eq$measurement){$observations.Add([pscustomobject]@{round=$round;target=[string]$target.name;protocol='HTTPS';critical=$critical;control=$control;success=$null;latencyMs=$null;packetLossPercent=$loss;jitterMs=$jitter;throughputMbps=$null});continue}
                $ok=[bool](Get-NrObservationProperty064 -Observation $measurement -Name 'ok');$latencyValue=Get-NrObservationProperty064 -Observation $measurement -Name 'latencyMs';$throughputValue=Get-NrObservationProperty064 -Observation $measurement -Name 'megabitsPerSecond';$throughput=if($null-ne$throughputValue -and [double]$throughputValue-gt0){[double]$throughputValue}else{$null}
                $observations.Add([pscustomobject]@{round=$round;target=[string]$target.name;protocol='HTTPS';critical=$critical;control=$control;success=$ok;latencyMs=$(if($ok -and $null-ne$latencyValue){[double]$latencyValue}else{$null});packetLossPercent=$loss;jitterMs=$jitter;throughputMbps=$throughput})
            }
        }
    }finally{Stop-NrStrategyRuntime}
    return [pscustomobject]@{strategy=$Strategy.Name;started=$started;observations=$observations.ToArray()}
}

function Get-NrStrategyScoreMap {$map=@{};$run=Get-NrLatestLabRun;if(-not$run -or -not$run.results){return $map};foreach($result in @($run.results)){$scoreProperty=$result.PSObject.Properties['score'];if(-not$scoreProperty -or $null-eq$scoreProperty.Value){continue};$map[[string]$result.strategy]=[double]$scoreProperty.Value};return $map}

function Invoke-NrStrategyLab {
    $strategies=@(Get-NrStrategies);if($strategies.Count-eq0){Show-NrMessage -Title (T 'strategyLab') -Message (T 'noStrategies') -Color Red;return}
    $items=@($strategies|ForEach-Object{[pscustomobject]@{Id=$_.Name;Label=$_.BaseName;Status=''}});$selected=Invoke-NrMultiSelect -Title (T 'strategyLab') -Items $items;if($null-eq$selected -or $selected.Count-eq0){return};$chosen=@($strategies|Where-Object{$selected-contains$_.Name});$original=Get-NrInstalledStrategy;$candidates=New-Object 'System.Collections.Generic.List[object]'
    try{for($i=0;$i-lt$chosen.Count;$i++){Write-NrHeader -Title (T 'strategyLab');Write-Host ('  [{0}/{1}] {2}' -f ($i+1),$chosen.Count,$chosen[$i].BaseName) -ForegroundColor Cyan;Write-Host '  3 repeated HTTPS rounds / critical services / controls / stability / optional telemetry' -ForegroundColor DarkGray;try{$candidates.Add((Invoke-NrStrategyProbe -Strategy $chosen[$i] -RepeatCount 3))}catch{$candidates.Add([pscustomobject]@{strategy=$chosen[$i].Name;started=$false;observations=@();probeError=$_.Exception.Message});Write-NrLog -Level ERROR -Message 'Strategy Lab probe failed' -Data @{strategy=$chosen[$i].Name;error=$_.Exception.Message}}}}
    finally{Stop-NrStrategyRuntime;if($original -and $original-ne'none'){$restore=$strategies|Where-Object{$_.BaseName-eq$original -or $_.Name-eq($original+'.bat')}|Select-Object -First 1;if($restore){try{Install-NrStrategy -Strategy $restore -Silent}catch{}}}}
    $ranked=@(Get-NrStrategyRanking064 -Candidates $candidates.ToArray());$dir=Join-Path $script:NrHistoryDir 'strategy-lab';if(-not(Test-Path -LiteralPath $dir -PathType Container)){New-Item -ItemType Directory -Path $dir -Force|Out-Null};$stamp=[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
    $document=[ordered]@{schemaVersion=3;rankingSchemaVersion=1;rankingModel='critical-services-stability-v1';createdUtc=[DateTime]::UtcNow.ToString('o');network=Get-NrActiveNetworkKey;repeatCount=3;minimumObservations=6;controlPolicy='control target must have repeated measurements and all measured control observations must pass';scoringWeights=[ordered]@{criticalAvailability=0.60;secondaryAvailability=0.10;stability=0.20;optionalTelemetry=0.10};missingMetricPolicy='exclude-and-renormalize; never coerce missing latency/loss/jitter/throughput to zero';tieBreak='score desc, critical availability desc, stability desc, strategy id asc';results=$ranked}
    $jsonPath=Join-Path $dir ($stamp+'.json');[IO.File]::WriteAllText($jsonPath,($document|ConvertTo-Json -Depth 30)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false));$ranked|Select-Object rank,strategy,rankingState,score,criticalAvailabilityPercent,secondaryAvailabilityPercent,controlAvailabilityPercent,availabilityPercent,stabilityPercent,telemetryScorePercent,observationCount,controlObservationCount,averageHttpLatencyMs,averagePacketLossPercent,averageJitterMs,peakDownloadMbps,recommendationReason,inconclusiveReason|Export-Csv -LiteralPath (Join-Path $dir ($stamp+'.csv')) -NoTypeInformation -Encoding UTF8
    Write-NrHeader -Title (T 'strategyLab');foreach($result in $ranked){if($result.rankingState-eq'eligible'){Write-Host ('  {0,2}. {1,-32} SCORE {2,6:N2}  CRIT {3,6:N1}%  STAB {4,6:N1}%' -f $result.rank,$result.strategy,$result.score,$result.criticalAvailabilityPercent,$result.stabilityPercent) -ForegroundColor $(if($result.rank-eq1){[ConsoleColor]::Green}else{[ConsoleColor]::Gray})}else{Write-Host ('  {0,2}. {1,-32} INCONCLUSIVE  {2}' -f $result.rank,$result.strategy,$result.inconclusiveReason) -ForegroundColor Yellow}}
    $winner=@($ranked|Where-Object{$_.rankingState-eq'eligible'}|Select-Object -First 1);if($winner.Count-gt0){if(-not[string]::IsNullOrWhiteSpace([string]$winner[0].recommendationReason)){Write-Host ('  WHY: '+$winner[0].recommendationReason) -ForegroundColor DarkCyan};$script:NrState.lastWorkingStrategy=[string]$winner[0].strategy;Save-NrState;Send-NrNotification -Title 'NexRoute Strategy Lab' -Message ('Best: '+$winner[0].strategy+' / '+$winner[0].score) -Level Info};Wait-NrKey
}

function Install-NrBestStrategy {$run=Get-NrLatestLabRun;if(-not$run -or -not$run.results -or @($run.results).Count-eq0){Show-NrMessage -Title (T 'autoBest') -Message (T 'noResults') -Color Yellow;return};$results=@($run.results);$isNew=$null-ne$run.PSObject.Properties['rankingSchemaVersion'];if($isNew){$best=@($results|Where-Object{$_.rankingState-eq'eligible' -and $null-ne$_.score}|Sort-Object rank|Select-Object -First 1)}else{$best=@($results|Where-Object{$null-ne$_.score -and [double]$_.score-gt0}|Sort-Object score -Descending|Select-Object -First 1)};if($best.Count-eq0){Show-NrMessage -Title (T 'autoBest') -Message (T 'noResults') -Color Yellow;return};$strategy=Get-NrStrategies|Where-Object{$_.Name-eq[string]$best[0].strategy}|Select-Object -First 1;if(-not$strategy){throw 'The recommended strategy file is missing.'};Install-NrStrategy -Strategy $strategy;$why=if($best[0].PSObject.Properties['recommendationReason'] -and $best[0].recommendationReason){' / '+[string]$best[0].recommendationReason}else{''};Show-NrMessage -Title (T 'autoBest') -Message ($strategy.BaseName+' / score '+$best[0].score+$why) -Color Green}

function Show-NrLabHistory {$dir=Join-Path $script:NrHistoryDir 'strategy-lab';$files=@(Get-ChildItem -LiteralPath $dir -Filter '*.json' -File -ErrorAction SilentlyContinue|Sort-Object LastWriteTimeUtc -Descending);if($files.Count-eq0){Show-NrMessage -Title (T 'labCompare') -Message (T 'noResults') -Color Yellow;return};$items=@($files|ForEach-Object{New-NrMenuItem -Id $_.FullName -Label $_.BaseName -Section (T 'history') -Status $_.LastWriteTime.ToString('g')});$choice=Invoke-NrMenu -Title (T 'labCompare') -Items $items -AllowEscape;if(-not$choice){return};$run=Get-Content -LiteralPath $choice -Raw -Encoding UTF8|ConvertFrom-Json;Write-NrHeader -Title (T 'labCompare');if($run.PSObject.Properties['rankingSchemaVersion']){foreach($result in @($run.results|Sort-Object rank)){if($result.rankingState-eq'eligible'){Write-Host ('  {0,-34} score={1,6:N2} critical={2,6:N1}% stability={3,6:N1}% observations={4}' -f $result.strategy,$result.score,$result.criticalAvailabilityPercent,$result.stabilityPercent,$result.observationCount) -ForegroundColor Gray;if($result.rank-eq1 -and $result.recommendationReason){Write-Host ('    WHY: '+$result.recommendationReason) -ForegroundColor DarkCyan}}else{Write-Host ('  {0,-34} INCONCLUSIVE: {1}' -f $result.strategy,$result.inconclusiveReason) -ForegroundColor Yellow}}}else{foreach($result in @($run.results|Sort-Object score -Descending)){Write-Host ('  {0,-38} score={1,6:N2} up={2,6:N1}% ping={3,7:N1}ms jitter={4,6:N1} loss={5,5:N1}%' -f $result.strategy,$result.score,$result.availabilityPercent,$result.averageHttpLatencyMs,$result.averageJitterMs,$result.averagePacketLossPercent) -ForegroundColor Gray}};Wait-NrKey}
