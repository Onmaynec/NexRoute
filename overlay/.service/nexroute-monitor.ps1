[CmdletBinding()]
param([string]$Root)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$next=Join-Path $PSScriptRoot 'next'
. (Join-Path $next 'nexroute-common.ps1')
. (Join-Path $next 'nexroute-strategies.ps1')
. (Join-Path $next 'nexroute-network.ps1')
Initialize-NrEnvironment -RootPath $Root

$seed=[Text.Encoding]::UTF8.GetBytes($script:NrRoot.ToLowerInvariant())
$sha=[Security.Cryptography.SHA256]::Create()
try { $hash=([BitConverter]::ToString($sha.ComputeHash($seed))).Replace('-','').Substring(0,20) } finally { $sha.Dispose() }
$mutex=New-Object Threading.Mutex($false,"NexRouteMonitor-$hash")
if (-not $mutex.WaitOne(0)) { exit 0 }

function Save-NrMonitorState {
    param([object]$Value)
    [IO.File]::WriteAllText($script:NrMonitorState,($Value | ConvertTo-Json -Depth 15)+[Environment]::NewLine,(New-Object Text.UTF8Encoding($false)))
}

function Get-NrMonitorTargets {
    $definitions=Get-NrServiceDefinitions
    $controller=Join-Path $script:NrService 'nexroute-services.ps1'
    $enabled=@{}
    if (Test-Path -LiteralPath $controller) {
        try {
            $summary=(& $controller -Mode Summary -Root $script:NrRoot | Select-Object -Last 1) | ConvertFrom-Json
            foreach ($id in @($summary.EnabledIds)) { $enabled[[string]$id]=$true }
        } catch { }
    }
    $targets=New-Object 'System.Collections.Generic.List[object]'
    foreach ($service in $definitions) {
        if ($enabled.Count -gt 0 -and -not $enabled.ContainsKey([string]$service.id)) { continue }
        $target=@($service.testTargets | Where-Object { $_.url } | Select-Object -First 1)
        if ($target.Count -eq 0) { continue }
        $name=if ($script:NrLanguage -eq 'RU') { [string]$service.nameRu } else { [string]$service.nameEn }
        $targets.Add([pscustomobject]@{ id=[string]$service.id; name=$name; uri=[string]$target[0].url })
    }
    return $targets.ToArray()
}

function Test-NrMonitorTarget {
    param([object]$Target)
    $watch=[Diagnostics.Stopwatch]::StartNew(); $ok=$false; $error=$null
    try {
        $response=Invoke-WebRequest -Uri $Target.uri -UseBasicParsing -TimeoutSec 8 -Headers @{ 'User-Agent'='NexRoute-Monitor/0.5.0'; 'Cache-Control'='no-cache' }
        $ok=[int]$response.StatusCode -ge 200 -and [int]$response.StatusCode -lt 500
    } catch { $error=$_.Exception.Message }
    $watch.Stop()
    return [pscustomobject]@{ serviceId=$Target.id; name=$Target.name; uri=$Target.uri; ok=$ok; latencyMs=[math]::Round($watch.Elapsed.TotalMilliseconds,2); error=$error }
}

function Get-NrRestartCount {
    $path=Join-Path $script:NrHistoryDir 'restarts.jsonl'
    if (-not (Test-Path -LiteralPath $path)) { return 0 }
    $cutoff=[DateTime]::UtcNow.AddHours(-1)
    $count=0
    foreach ($line in @(Get-Content -LiteralPath $path -Tail 100 -Encoding UTF8)) {
        try { $entry=$line | ConvertFrom-Json; if ([DateTime]::Parse([string]$entry.timestampUtc).ToUniversalTime() -ge $cutoff) { $count++ } } catch { }
    }
    return $count
}

function Restart-NrMonitoredService {
    if ((Get-NrRestartCount) -ge [int]$script:NrState.restartLimitPerHour) {
        Write-NrLog -Level ERROR -Message 'Restart limit reached' -Data @{ limit=$script:NrState.restartLimitPerHour }
        return $false
    }
    try {
        $strategy=Get-NrInstalledStrategy
        if ($strategy -and $strategy -ne 'none') {
            $candidate=Get-NrStrategies | Where-Object { $_.Name -eq $strategy -or $_.BaseName -eq $strategy } | Select-Object -First 1
            if ($candidate) { Install-NrStrategy -Path $candidate.FullName -Reason 'health-monitor-repair' | Out-Null }
            else { Start-Service -Name zapret -ErrorAction Stop }
        } else { Start-Service -Name zapret -ErrorAction Stop }
        $entry=[ordered]@{ timestampUtc=[DateTime]::UtcNow.ToString('o'); action='restart'; strategy=$strategy }
        Add-Content -LiteralPath (Join-Path $script:NrHistoryDir 'restarts.jsonl') -Value ($entry | ConvertTo-Json -Compress) -Encoding UTF8
        Send-NrNotification -Title 'NexRoute' -Message 'The network service was restored automatically.' -Level Warning
        return $true
    } catch { Write-NrLog -Level ERROR -Message 'Automatic service repair failed' -Data @{ error=$_.Exception.Message }; return $false }
}

function Invoke-NrAutomaticFailover {
    param([int]$Failures)
    if (-not [bool]$script:NrState.autoSwitchEnabled -or [bool]$script:NrState.safeMode) { return }
    if ($Failures -lt [int]$script:NrState.failureThreshold) { return }
    $latest=Get-NrLatestLabRun
    if (-not $latest) { return }
    $current=Get-NrInstalledStrategy
    $candidate=@($latest.results | Where-Object { $_.strategy -ne $current } | Sort-Object score -Descending | Select-Object -First 1)
    if ($candidate.Count -eq 0) { return }
    $file=Get-NrStrategies | Where-Object { $_.BaseName -eq [string]$candidate[0].strategy -or $_.Name -eq [string]$candidate[0].strategy } | Select-Object -First 1
    if (-not $file) { return }
    try {
        Install-NrStrategy -Path $file.FullName -Reason 'automatic-failover' | Out-Null
        Send-NrNotification -Title 'NexRoute' -Message ('Automatic failover selected ' + $file.BaseName) -Level Warning
    } catch { Write-NrLog -Level ERROR -Message 'Automatic failover failed' -Data @{ error=$_.Exception.Message } }
}

$failures=@{}
try {
    while ($true) {
        $script:NrState=Read-NrState
        if (-not [bool]$script:NrState.monitorEnabled) { break }
        $network=Get-NrActiveNetworkKey
        if ([string]$script:NrState.currentNetworkKey -ne $network) {
            $script:NrState.currentNetworkKey=$network; Save-NrState
            try { Apply-NrNetworkProfile -Key $network } catch { }
            Write-NrLog -Message 'Active network changed' -Data @{ network=$network }
        }
        if (-not (Test-NrServiceRunning -Name 'zapret')) { [void](Restart-NrMonitoredService) }
        $rows=New-Object 'System.Collections.Generic.List[object]'
        $totalFailures=0
        foreach ($target in @(Get-NrMonitorTargets)) {
            $probe=Test-NrMonitorTarget -Target $target
            $id=[string]$probe.serviceId
            if ($probe.ok) { $failures[$id]=0 } else { $failures[$id]=1+[int]$(if ($failures.ContainsKey($id)) { $failures[$id] } else { 0 }) }
            if (-not $probe.ok) { $totalFailures++ }
            $row=[ordered]@{ timestampUtc=[DateTime]::UtcNow.ToString('o'); serviceId=$id; name=$probe.name; ok=$probe.ok; latencyMs=$probe.latencyMs; consecutiveFailures=[int]$failures[$id]; strategy=Get-NrInstalledStrategy; network=$network; error=$probe.error }
            $rows.Add([pscustomobject]$row)
            if ([bool]$script:NrState.statisticsEnabled) { Add-Content -LiteralPath (Join-Path $script:NrHistoryDir 'availability.jsonl') -Value ($row | ConvertTo-Json -Compress) -Encoding UTF8 }
        }
        $state=[ordered]@{ timestampUtc=[DateTime]::UtcNow.ToString('o'); running=Test-NrServiceRunning -Name zapret; strategy=Get-NrInstalledStrategy; network=$network; services=$rows.ToArray(); failedServices=$totalFailures }
        Save-NrMonitorState -Value $state
        Invoke-NrAutomaticFailover -Failures $totalFailures
        Start-Sleep -Seconds ([Math]::Min([Math]::Max([int]$script:NrState.probeIntervalSeconds,15),3600))
    }
} finally {
    try { $mutex.ReleaseMutex() } catch { }
    $mutex.Dispose()
}
