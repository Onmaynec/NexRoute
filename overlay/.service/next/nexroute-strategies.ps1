Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-NrStrategies {
    $files = @(Get-ChildItem -LiteralPath $script:NrRoot -Filter '*.bat' -File -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -notin @('service.bat','nexroute.bat') -and $_.Name -notlike 'nexroute-*'
    } | Sort-Object Name)
    return $files
}

function Get-NrFavorites {
    return [string[]]@($script:NrState.favorites)
}

function Save-NrStrategyHistory {
    param([string]$Action,[string]$Strategy,[hashtable]$Details)
    $entry = [ordered]@{
        timestampUtc = [DateTime]::UtcNow.ToString('o')
        action = $Action
        strategy = $Strategy
        network = Get-NrActiveNetworkKey
    }
    if ($Details) { $entry.details = $Details }
    Add-Content -LiteralPath (Join-Path $script:NrHistoryDir 'strategy-switches.jsonl') -Value ($entry | ConvertTo-Json -Depth 10 -Compress) -Encoding UTF8
    Write-NrLog -Level INFO -Message ('Strategy history: ' + $Action) -Data @{ strategy=$Strategy }
}

function Get-NrLatestLabRun {
    $dir = Join-Path $script:NrHistoryDir 'strategy-lab'
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return $null }
    $file = Get-ChildItem -LiteralPath $dir -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if (-not $file) { return $null }
    try { return Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $null }
}

function Get-NrStrategyScoreMap {
    $map = @{}
    $run = Get-NrLatestLabRun
    if ($run -and $run.results) {
        foreach ($result in @($run.results)) { $map[[string]$result.strategy] = [double]$result.score }
    }
    return $map
}

function Install-NrStrategy {
    param([Parameter(Mandatory)][System.IO.FileInfo]$Strategy,[switch]$Silent)
    if (-not (Test-Path -LiteralPath $Strategy.FullName -PathType Leaf)) { throw 'Strategy file was not found.' }
    $previous = Get-NrInstalledStrategy
    if ($previous -and $previous -ne 'none') { $script:NrState.lastWorkingStrategy = $previous }
    Save-NrState
    $exitCode = Invoke-NrLegacy -Arguments @('refresh_matrix',$Strategy.FullName) -Hidden:$Silent
    if ($exitCode -ne 0) { throw "Strategy installation returned exit code $exitCode." }
    Save-NrStrategyHistory -Action 'install' -Strategy $Strategy.BaseName -Details @{ previous=$previous }
    Send-NrNotification -Title 'NexRoute' -Message ((T 'installDone') + ' ' + $Strategy.BaseName) -Level Info
}

function Show-NrInstallStrategy {
    $strategies = @(Get-NrStrategies)
    if ($strategies.Count -eq 0) { Show-NrMessage -Title (T 'installConfig') -Message (T 'noStrategies') -Color Red; return }
    $scores = Get-NrStrategyScoreMap
    $favorites = Get-NrFavorites
    $items = New-Object 'System.Collections.Generic.List[object]'
    $items.Add((New-NrMenuItem -Id '__auto' -Label (T 'autoBest') -Section (T 'selectStrategy') -Status 'AUTO'))
    foreach ($strategy in $strategies) {
        $statusParts = New-Object 'System.Collections.Generic.List[string]'
        if ($favorites -contains $strategy.Name) { $statusParts.Add('FAVORITE') }
        if ($scores.ContainsKey($strategy.Name)) { $statusParts.Add(('SCORE {0:N1}' -f $scores[$strategy.Name])) }
        $items.Add((New-NrMenuItem -Id $strategy.Name -Label $strategy.BaseName -Section (T 'selectStrategy') -Status ($statusParts -join ' / ')))
    }
    $items.Add((New-NrMenuItem -Id '__back' -Label (T 'back') -Section (T 'selectStrategy')))
    $choice = Invoke-NrMenu -Title (T 'installConfig') -Items $items.ToArray() -AllowEscape
    if (-not $choice -or $choice -eq '__back') { return }
    if ($choice -eq '__auto') { Install-NrBestStrategy; return }
    $selected = $strategies | Where-Object { $_.Name -eq $choice } | Select-Object -First 1
    if ($selected) {
        Show-NrMessage -Title (T 'installConfig') -Message ($selected.BaseName + '...') -Color Cyan -NoWait
        try { Install-NrStrategy -Strategy $selected; Show-NrMessage -Title (T 'installConfig') -Message (T 'installDone') -Color Green }
        catch { Show-NrMessage -Title (T 'operationFailed') -Message $_.Exception.Message -Color Red }
    }
}

function Remove-NrServices {
    if (-not (Confirm-NrY -Message (T 'purgeConfirm'))) { return }
    foreach ($name in @('zapret','WinDivert','WinDivert14')) {
        try { Stop-Service -Name $name -Force -ErrorAction SilentlyContinue } catch { }
        try { & sc.exe delete $name | Out-Null } catch { }
    }
    foreach ($service in @(Get-Service -Name 'NexRoute_*' -ErrorAction SilentlyContinue)) {
        try { Stop-Service -Name $service.Name -Force -ErrorAction SilentlyContinue } catch { }
        try { & sc.exe delete $service.Name | Out-Null } catch { }
    }
    try { Get-Process -Name winws -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue } catch { }
    Save-NrStrategyHistory -Action 'purge' -Strategy (Get-NrInstalledStrategy) -Details @{}
    Send-NrNotification -Title 'NexRoute' -Message (T 'purgeDone') -Level Info
    Show-NrMessage -Title (T 'deleteConfig') -Message (T 'purgeDone') -Color Green
}

function Get-NrStrategyCommand {
    param([Parameter(Mandatory)][string]$Path)
    $lines = @(Get-Content -LiteralPath $Path -Encoding UTF8)
    $joined = New-Object System.Text.StringBuilder
    $capture = $false
    foreach ($raw in $lines) {
        $line = $raw.Trim()
        if (-not $capture -and $line -match '(?i)winws\.exe') { $capture = $true }
        if (-not $capture) { continue }
        [void]$joined.Append(' ' + ($line -replace '\^\s*$',''))
    }
    $text = $joined.ToString().Trim()
    $match = [regex]::Match($text,'(?is)winws\.exe"?\s+(?<args>.*)$')
    if (-not $match.Success) { return $null }
    $args = $match.Groups['args'].Value
    $bin = (Join-Path $script:NrRoot 'bin') + '\'
    $lists = (Join-Path $script:NrRoot 'lists') + '\'
    $args = $args.Replace('%BIN%',$bin).Replace('%LISTS%',$lists)
    $args = $args.Replace('%GameFilter%','1024-65535').Replace('%GameFilterTCP%','1024-65535').Replace('%GameFilterUDP%','1024-65535')
    $runtimePath = Join-Path $script:NrService 'services-runtime.cmd'
    $tcp = ''; $udp = ''
    if (Test-Path -LiteralPath $runtimePath) {
        foreach ($line in @(Get-Content -LiteralPath $runtimePath -Encoding ASCII)) {
            if ($line -match '^set "NEXROUTE_SERVICE_TCP_ARGS=(.*)"$') { $tcp=$Matches[1] }
            if ($line -match '^set "NEXROUTE_SERVICE_UDP_ARGS=(.*)"$') { $udp=$Matches[1] }
        }
    }
    $args = $args.Replace('%NEXROUTE_SERVICE_TCP_ARGS%',$tcp).Replace('%NEXROUTE_SERVICE_UDP_ARGS%',$udp)
    return ($args -replace '\s+',' ').Trim()
}

function Test-NrStrategyConfiguration {
    param([Parameter(Mandatory)][string]$Path)
    $errors = New-Object 'System.Collections.Generic.List[string]'
    $warnings = New-Object 'System.Collections.Generic.List[string]'
    $command = Get-NrStrategyCommand -Path $Path
    if ([string]::IsNullOrWhiteSpace($command)) { $errors.Add('winws.exe command was not found.') }
    else {
        if ($command -notmatch '--filter-(tcp|udp)=') { $errors.Add('No TCP or UDP filter is defined.') }
        if ($command -notmatch '--dpi-desync=') { $errors.Add('No DPI desynchronization mode is defined.') }
        if (($command.ToCharArray() | Where-Object { $_ -eq '"' }).Count % 2 -ne 0) { $errors.Add('Unbalanced quotation marks.') }
        if ($command -match '(?i)\.\.[\\/]') { $warnings.Add('The command contains a parent-directory path.') }
        if ($command -match '(?i)--wf-(tcp|udp)=\*') { $warnings.Add('The command captures every port.') }
        foreach ($pathMatch in [regex]::Matches($command,'"(?<path>[A-Za-z]:\\[^"\r\n]+)"')) {
            $candidate=$pathMatch.Groups['path'].Value
            if ($candidate -match '\.(txt|bin|exe|sys)$' -and -not (Test-Path -LiteralPath $candidate)) { $errors.Add('Missing referenced file: ' + $candidate) }
        }
    }
    return [pscustomobject]@{ Valid=($errors.Count -eq 0); Errors=$errors.ToArray(); Warnings=$warnings.ToArray(); Command=$command }
}

function Show-NrStrategyPreview {
    $strategies=@(Get-NrStrategies)
    if ($strategies.Count -eq 0) { return }
    $items=@($strategies | ForEach-Object { New-NrMenuItem -Id $_.Name -Label $_.BaseName -Section (T 'selectStrategy') })
    $choice=Invoke-NrMenu -Title (T 'previewCommand') -Items $items -AllowEscape
    if (-not $choice) { return }
    $strategy=$strategies | Where-Object { $_.Name -eq $choice } | Select-Object -First 1
    $result=Test-NrStrategyConfiguration -Path $strategy.FullName
    Write-NrHeader -Title (T 'previewCommand')
    Write-Host ('  ' + $strategy.BaseName) -ForegroundColor Cyan
    Write-Host ''
    Write-Host $result.Command -ForegroundColor Gray
    Write-Host ''
    if ($result.Valid) { Write-Host '  [OK] Configuration syntax is valid.' -ForegroundColor Green }
    foreach ($error in @($result.Errors)) { Write-Host ('  [ERROR] ' + $error) -ForegroundColor Red }
    foreach ($warning in @($result.Warnings)) { Write-Host ('  [WARN] ' + $warning) -ForegroundColor Yellow }
    Wait-NrKey
}

function Toggle-NrFavoriteStrategy {
    $strategies=@(Get-NrStrategies)
    if ($strategies.Count -eq 0) { return }
    $favorites=Get-NrFavorites
    $items=@($strategies | ForEach-Object { New-NrMenuItem -Id $_.Name -Label $_.BaseName -Section (T 'favorites') -Status $(if ($favorites -contains $_.Name) { 'FAVORITE' } else { '' }) })
    $choice=Invoke-NrMenu -Title (T 'favorites') -Items $items -AllowEscape
    if (-not $choice) { return }
    $list=New-Object 'System.Collections.Generic.List[string]'
    foreach ($name in $favorites) { if ($name -ne $choice) { $list.Add($name) } }
    if ($favorites -notcontains $choice) { $list.Add($choice) }
    $script:NrState.favorites=$list.ToArray()
    Save-NrState
}

function Measure-NrPingMetrics {
    param([string]$Target,[int]$Count=5)
    $times=New-Object 'System.Collections.Generic.List[double]'
    try {
        $responses=@(Test-Connection -ComputerName $Target -Count $Count -ErrorAction SilentlyContinue)
        foreach ($response in $responses) {
            $property=$response.PSObject.Properties['ResponseTime']
            if ($property) { $times.Add([double]$property.Value) }
        }
    } catch { }
    $received=$times.Count
    $loss=[math]::Round((($Count-$received)/[double]$Count)*100,2)
    $avg=if ($received -gt 0) { [math]::Round((($times | Measure-Object -Average).Average),2) } else { 9999 }
    $jitter=0.0
    if ($received -gt 1) {
        $diff=New-Object 'System.Collections.Generic.List[double]'
        for ($i=1;$i -lt $times.Count;$i++) { $diff.Add([math]::Abs($times[$i]-$times[$i-1])) }
        $jitter=[math]::Round((($diff | Measure-Object -Average).Average),2)
    }
    return [pscustomobject]@{ target=$Target; averageMs=$avg; jitterMs=$jitter; packetLossPercent=$loss; received=$received; sent=$Count }
}

function Measure-NrHttpEndpoint {
    param([string]$Name,[string]$Uri,[int]$TimeoutSec=12)
    $watch=[Diagnostics.Stopwatch]::StartNew()
    try {
        $response=Invoke-WebRequest -Uri $Uri -UseBasicParsing -TimeoutSec $TimeoutSec -Headers @{ 'User-Agent'='NexRoute-Strategy-Lab/0.5.0'; 'Cache-Control'='no-cache' }
        $watch.Stop()
        $bytes=0
        if ($response.Content) { $bytes=[Text.Encoding]::UTF8.GetByteCount([string]$response.Content) }
        $seconds=[Math]::Max($watch.Elapsed.TotalSeconds,0.001)
        $mbps=[math]::Round((($bytes*8)/$seconds/1000000),3)
        return [pscustomobject]@{ name=$Name; uri=$Uri; ok=$true; statusCode=[int]$response.StatusCode; latencyMs=[math]::Round($watch.Elapsed.TotalMilliseconds,2); bytes=$bytes; megabitsPerSecond=$mbps; error=$null }
    } catch {
        $watch.Stop()
        return [pscustomobject]@{ name=$Name; uri=$Uri; ok=$false; statusCode=0; latencyMs=[math]::Round($watch.Elapsed.TotalMilliseconds,2); bytes=0; megabitsPerSecond=0; error=$_.Exception.Message }
    }
}

function Get-NrProbeTargets {
    $targets=New-Object 'System.Collections.Generic.List[object]'
    $targets.Add([pscustomobject]@{ name='YouTube'; uri='https://www.youtube.com/generate_204'; host='www.youtube.com'; kind='video' })
    $targets.Add([pscustomobject]@{ name='Discord'; uri='https://discord.com/api/v9/gateway'; host='discord.com'; kind='voice' })
    $targets.Add([pscustomobject]@{ name='Telegram'; uri='https://api.telegram.org'; host='api.telegram.org'; kind='voice' })
    $targets.Add([pscustomobject]@{ name='GitHub'; uri='https://api.github.com'; host='api.github.com'; kind='control' })
    $controller=Join-Path $script:NrService 'nexroute-services.ps1'
    if (Test-Path -LiteralPath $controller) {
        try {
            $json=& $controller -Mode TestTargets -Root $script:NrRoot | Select-Object -Last 1
            foreach ($target in @($json | ConvertFrom-Json)) {
                if ($target.Value) {
                    $uri=[Uri][string]$target.Value
                    $targets.Add([pscustomobject]@{ name=[string]$target.NameEn; uri=[string]$target.Value; host=$uri.DnsSafeHost; kind='service' })
                }
            }
        } catch { }
    }
    return @($targets | Group-Object uri | ForEach-Object { $_.Group[0] })
}

function Stop-NrStrategyRuntime {
    try { Stop-Service -Name zapret -Force -ErrorAction SilentlyContinue } catch { }
    try { Get-Process -Name winws -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue } catch { }
    Start-Sleep -Milliseconds 400
}

function Start-NrTemporaryStrategy {
    param([Parameter(Mandatory)][System.IO.FileInfo]$Strategy)
    Stop-NrStrategyRuntime
    $old=$env:NO_UPDATE_CHECK
    $env:NO_UPDATE_CHECK='1'
    try {
        $command='"' + $Strategy.FullName + '"'
        Start-Process -FilePath $env:ComSpec -ArgumentList @('/d','/c',$command) -WindowStyle Hidden | Out-Null
        Start-Sleep -Seconds 3
        return [bool](Get-Process -Name winws -ErrorAction SilentlyContinue)
    } finally { $env:NO_UPDATE_CHECK=$old }
}

function Invoke-NrStrategyProbe {
    param([Parameter(Mandatory)][System.IO.FileInfo]$Strategy)
    $started=Start-NrTemporaryStrategy -Strategy $Strategy
    $targets=Get-NrProbeTargets
    $http=New-Object 'System.Collections.Generic.List[object]'
    foreach ($target in $targets) { $http.Add((Measure-NrHttpEndpoint -Name $target.name -Uri $target.uri)) }
    $pingTargets=@('1.1.1.1','8.8.8.8','discord.com','api.telegram.org')
    $pings=New-Object 'System.Collections.Generic.List[object]'
    foreach ($target in $pingTargets) { $pings.Add((Measure-NrPingMetrics -Target $target -Count 4)) }
    Stop-NrStrategyRuntime
    $okCount=@($http | Where-Object { $_.ok }).Count
    $availability=if ($http.Count -gt 0) { [math]::Round(($okCount/[double]$http.Count)*100,2) } else { 0 }
    $latencies=@($http | Where-Object { $_.ok } | ForEach-Object { [double]$_.latencyMs })
    $httpLatency=if ($latencies.Count -gt 0) { [double](($latencies | Measure-Object -Average).Average) } else { 5000 }
    $loss=[double](($pings | Measure-Object -Property packetLossPercent -Average).Average)
    $jitter=[double](($pings | Measure-Object -Property jitterMs -Average).Average)
    $download=[double](($http | Measure-Object -Property megabitsPerSecond -Maximum).Maximum)
    $score=($availability*0.65) + ([math]::Max(0,20-($httpLatency/100))) + ([math]::Max(0,8-($loss/4))) + ([math]::Max(0,5-($jitter/20))) + ([math]::Min(2,$download/5))
    $youtube=@($http | Where-Object { $_.name -eq 'YouTube' })[0]
    $discord=@($http | Where-Object { $_.name -eq 'Discord' })[0]
    $telegram=@($http | Where-Object { $_.name -eq 'Telegram' })[0]
    return [pscustomobject]@{
        strategy=$Strategy.Name; started=$started; score=[math]::Round($score,2); availabilityPercent=$availability;
        averageHttpLatencyMs=[math]::Round($httpLatency,2); averagePacketLossPercent=[math]::Round($loss,2); averageJitterMs=[math]::Round($jitter,2);
        peakDownloadMbps=[math]::Round($download,3); youtubeVideoReady=[bool]($youtube -and $youtube.ok);
        discordVoiceReady=[bool]($discord -and $discord.ok -and $loss -lt 10 -and $jitter -lt 100);
        telegramVoiceReady=[bool]($telegram -and $telegram.ok -and $loss -lt 10 -and $jitter -lt 100);
        http=$http.ToArray(); ping=$pings.ToArray()
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
        for ($i=0;$i -lt $chosen.Count;$i++) {
            Write-NrHeader -Title (T 'strategyLab')
            Write-Host ('  [{0}/{1}] {2}' -f ($i+1),$chosen.Count,$chosen[$i].BaseName) -ForegroundColor Cyan
            Write-Host ('  ' + (T 'speed') + ' / ' + (T 'jitter') + ' / ' + (T 'packetLoss')) -ForegroundColor DarkGray
            try { $results.Add((Invoke-NrStrategyProbe -Strategy $chosen[$i])) }
            catch {
                $results.Add([pscustomobject]@{ strategy=$chosen[$i].Name; started=$false; score=0; availabilityPercent=0; error=$_.Exception.Message })
                Write-NrLog -Level ERROR -Message 'Strategy Lab probe failed' -Data @{ strategy=$chosen[$i].Name; error=$_.Exception.Message }
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
    $dir=Join-Path $script:NrHistoryDir 'strategy-lab'
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $stamp=[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
    $document=[ordered]@{ schemaVersion=2; createdUtc=[DateTime]::UtcNow.ToString('o'); network=Get-NrActiveNetworkKey; results=$sorted }
    $jsonPath=Join-Path $dir ($stamp + '.json')
    [System.IO.File]::WriteAllText($jsonPath,($document | ConvertTo-Json -Depth 20)+[Environment]::NewLine,(New-Object System.Text.UTF8Encoding($false)))
    $sorted | Select-Object strategy,score,availabilityPercent,averageHttpLatencyMs,averagePacketLossPercent,averageJitterMs,peakDownloadMbps,youtubeVideoReady,discordVoiceReady,telegramVoiceReady | Export-Csv -LiteralPath (Join-Path $dir ($stamp + '.csv')) -NoTypeInformation -Encoding UTF8
    Write-NrHeader -Title (T 'strategyLab')
    $rank=1
    foreach ($result in $sorted) {
        Write-Host ('  {0,2}. {1,-36} SCORE {2,6:N2}  UP {3,6:N1}%' -f $rank,$result.strategy,$result.score,$result.availabilityPercent) -ForegroundColor $(if ($rank -eq 1) { [ConsoleColor]::Green } else { [ConsoleColor]::Gray })
        $rank++
    }
    if ($sorted.Count -gt 0) {
        $script:NrState.lastWorkingStrategy=[string]$sorted[0].strategy
        Save-NrState
        Send-NrNotification -Title 'NexRoute Strategy Lab' -Message ('Best: ' + $sorted[0].strategy + ' / ' + $sorted[0].score) -Level Info
    }
    Wait-NrKey
}

function Install-NrBestStrategy {
    $run=Get-NrLatestLabRun
    if (-not $run -or -not $run.results -or @($run.results).Count -eq 0) {
        Show-NrMessage -Title (T 'autoBest') -Message (T 'noResults') -Color Yellow
        return
    }
    $best=@($run.results | Sort-Object score -Descending | Where-Object { $_.score -gt 0 } | Select-Object -First 1)
    if ($best.Count -eq 0) { Show-NrMessage -Title (T 'autoBest') -Message (T 'noResults') -Color Yellow; return }
    $strategy=Get-NrStrategies | Where-Object { $_.Name -eq [string]$best[0].strategy } | Select-Object -First 1
    if (-not $strategy) { throw 'The recommended strategy file is missing.' }
    Install-NrStrategy -Strategy $strategy
    Show-NrMessage -Title (T 'autoBest') -Message ($strategy.BaseName + ' / score ' + $best[0].score) -Color Green
}

function Show-NrLabHistory {
    $dir=Join-Path $script:NrHistoryDir 'strategy-lab'
    $files=@(Get-ChildItem -LiteralPath $dir -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending)
    if ($files.Count -eq 0) { Show-NrMessage -Title (T 'labCompare') -Message (T 'noResults') -Color Yellow; return }
    $items=@($files | ForEach-Object { New-NrMenuItem -Id $_.FullName -Label $_.BaseName -Section (T 'history') -Status $_.LastWriteTime.ToString('g') })
    $choice=Invoke-NrMenu -Title (T 'labCompare') -Items $items -AllowEscape
    if (-not $choice) { return }
    $run=Get-Content -LiteralPath $choice -Raw -Encoding UTF8 | ConvertFrom-Json
    Write-NrHeader -Title (T 'labCompare')
    foreach ($result in @($run.results | Sort-Object score -Descending)) {
        Write-Host ('  {0,-38} score={1,6:N2} up={2,6:N1}% ping={3,7:N1}ms jitter={4,6:N1} loss={5,5:N1}%' -f $result.strategy,$result.score,$result.availabilityPercent,$result.averageHttpLatencyMs,$result.averageJitterMs,$result.averagePacketLossPercent) -ForegroundColor Gray
    }
    Wait-NrKey
}

function Restore-NrLastWorkingStrategy {
    $name=[string]$script:NrState.lastWorkingStrategy
    if ([string]::IsNullOrWhiteSpace($name)) { Show-NrMessage -Title (T 'lastWorking') -Message (T 'noResults') -Color Yellow; return }
    $strategy=Get-NrStrategies | Where-Object { $_.Name -eq $name -or $_.BaseName -eq $name } | Select-Object -First 1
    if (-not $strategy) { Show-NrMessage -Title (T 'lastWorking') -Message 'Strategy file is missing.' -Color Red; return }
    Install-NrStrategy -Strategy $strategy
    Show-NrMessage -Title (T 'lastWorking') -Message $strategy.BaseName -Color Green
}

function Get-NrServiceDefinitions {
    $path=Join-Path $script:NrService 'services.json'
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    try { return @((Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json).services) } catch { return @() }
}

function ConvertTo-NrServiceScopedCommand {
    param([string]$Command,[string]$ServiceId)
    $hostList=Join-Path $script:NrRoot ('lists\list-service-' + $ServiceId + '.txt')
    $ipset=Join-Path $script:NrRoot ('lists\ipset-service-' + $ServiceId + '.txt')
    $tokens=@([regex]::Matches($Command,'"[^"]*"|\S+') | ForEach-Object { $_.Value })
    $global=New-Object 'System.Collections.Generic.List[string]'
    $blocks=New-Object 'System.Collections.Generic.List[object]'
    $current=New-Object 'System.Collections.Generic.List[string]'
    $inProfiles=$false
    foreach ($token in $tokens) {
        if ($token -eq '--new') {
            $inProfiles=$true
            if ($current.Count -gt 0) { $blocks.Add($current.ToArray()); $current=New-Object 'System.Collections.Generic.List[string]' }
            continue
        }
        if (-not $inProfiles -and $token -notmatch '^--filter-') { $global.Add($token); continue }
        $inProfiles=$true
        $current.Add($token)
    }
    if ($current.Count -gt 0) { $blocks.Add($current.ToArray()) }
    $scoped=New-Object 'System.Collections.Generic.List[string]'
    foreach ($block in $blocks) {
        $clean=New-Object 'System.Collections.Generic.List[string]'
        foreach ($token in $block) {
            if ($token -match '^--(hostlist|hostlist-domains|ipset)=' -and $token -notmatch '^--(hostlist-exclude|ipset-exclude)=') { continue }
            $clean.Add($token)
        }
        if (($clean -join ' ') -match '--filter-(tcp|udp)=') {
            $clean.Add('--hostlist="' + $hostList + '"')
            $clean.Add('--ipset="' + $ipset + '"')
            $scoped.Add(($clean -join ' ') + ' --new')
        }
    }
    return (($global -join ' ') + ' ' + ($scoped -join ' ')).Trim()
}

function Apply-NrPerServiceStrategies {
    $map=$script:NrState.perServiceStrategies
    if ($null -eq $map) { return }
    $properties=@($map.PSObject.Properties)
    if ($properties.Count -eq 0 -and $map -is [hashtable]) { $properties=@($map.GetEnumerator() | ForEach-Object { [pscustomobject]@{ Name=$_.Key; Value=$_.Value } }) }
    if ($properties.Count -eq 0) { return }
    Stop-NrStrategyRuntime
    foreach ($existing in @(Get-Service -Name 'NexRoute_*' -ErrorAction SilentlyContinue)) {
        try { Stop-Service -Name $existing.Name -Force -ErrorAction SilentlyContinue } catch { }
        & sc.exe delete $existing.Name | Out-Null
    }
    $strategies=Get-NrStrategies
    foreach ($property in $properties) {
        $serviceId=[string]$property.Name
        $strategyName=[string]$property.Value
        $strategy=$strategies | Where-Object { $_.Name -eq $strategyName } | Select-Object -First 1
        if (-not $strategy) { continue }
        $command=Get-NrStrategyCommand -Path $strategy.FullName
        if (-not $command) { continue }
        $scoped=ConvertTo-NrServiceScopedCommand -Command $command -ServiceId $serviceId
        $serviceName=('NexRoute_' + ($serviceId -replace '[^A-Za-z0-9_]','_'))
        $bin=Join-Path $script:NrRoot 'bin\winws.exe'
        $binPath='"' + $bin + '" ' + $scoped
        & sc.exe create $serviceName binPath= $binPath DisplayName= ('NexRoute ' + $serviceId) start= auto | Out-Null
        & sc.exe description $serviceName ('NexRoute per-service strategy: ' + $strategy.BaseName) | Out-Null
        & sc.exe start $serviceName | Out-Null
        Save-NrStrategyHistory -Action 'per-service-install' -Strategy $strategy.BaseName -Details @{ service=$serviceId }
    }
}

function Show-NrPerServiceMapping {
    $definitions=Get-NrServiceDefinitions
    $strategies=@(Get-NrStrategies)
    if ($definitions.Count -eq 0 -or $strategies.Count -eq 0) { return }
    while ($true) {
        $items=New-Object 'System.Collections.Generic.List[object]'
        foreach ($service in $definitions) {
            $name=if ($script:NrLanguage -eq 'RU') { [string]$service.nameRu } else { [string]$service.nameEn }
            $status=''
            try { $property=$script:NrState.perServiceStrategies.PSObject.Properties[[string]$service.id]; if ($property) { $status=[string]$property.Value } } catch { }
            $items.Add((New-NrMenuItem -Id ([string]$service.id) -Label $name -Section (T 'perService') -Status $status))
        }
        $items.Add((New-NrMenuItem -Id '__apply' -Label (T 'save') -Section (T 'perService') -Status 'APPLY'))
        $items.Add((New-NrMenuItem -Id '__back' -Label (T 'back') -Section (T 'perService')))
        $choice=Invoke-NrMenu -Title (T 'perService') -Items $items.ToArray() -AllowEscape
        if (-not $choice -or $choice -eq '__back') { return }
        if ($choice -eq '__apply') {
            try { Apply-NrPerServiceStrategies; Show-NrMessage -Title (T 'perService') -Message (T 'operationComplete') -Color Green }
            catch { Show-NrMessage -Title (T 'operationFailed') -Message $_.Exception.Message -Color Red }
            return
        }
        $strategyItems=@($strategies | ForEach-Object { New-NrMenuItem -Id $_.Name -Label $_.BaseName -Section (T 'selectStrategy') })
        $strategyChoice=Invoke-NrMenu -Title (T 'perService') -Items $strategyItems -AllowEscape
        if ($strategyChoice) {
            $table=[ordered]@{}
            try { foreach ($property in @($script:NrState.perServiceStrategies.PSObject.Properties)) { $table[$property.Name]=$property.Value } } catch { }
            $table[$choice]=$strategyChoice
            $script:NrState.perServiceStrategies=[pscustomobject]$table
            Save-NrState
        }
    }
}

function Show-NrCustomStrategyBuilder {
    $strategies=@(Get-NrStrategies)
    if ($strategies.Count -eq 0) { return }
    $items=@($strategies | ForEach-Object { New-NrMenuItem -Id $_.FullName -Label $_.BaseName -Section (T 'customStrategy') })
    $choice=Invoke-NrMenu -Title (T 'customStrategy') -Items $items -AllowEscape
    if (-not $choice) { return }
    $source=Get-Item -LiteralPath $choice
    $target=Join-Path $script:NrRoot ('custom-' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss') + '.bat')
    Copy-Item -LiteralPath $source.FullName -Destination $target -Force
    Open-NrTextFile -Path $target
    $validation=Test-NrStrategyConfiguration -Path $target
    if ($validation.Valid) { Show-NrMessage -Title (T 'validateConfig') -Message $target -Color Green }
    else { Show-NrMessage -Title (T 'validateConfig') -Message (($validation.Errors -join [Environment]::NewLine)) -Color Red }
}
