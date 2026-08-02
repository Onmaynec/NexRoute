[CmdletBinding()]
param(
    [ValidateSet('Start','Stop','Status','Once','Supervise')][string]$Mode='Status',
    [string]$Root,
    [string]$ConfigPath,
    [int]$IntervalSeconds=20,
    [int]$FailureThreshold=3,
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if (-not $Root) { $Root=Split-Path -Parent $PSScriptRoot }
$Root=[IO.Path]::GetFullPath($Root)
. (Join-Path $PSScriptRoot 'next/nexroute-workers.ps1')
if (-not $ConfigPath) { $ConfigPath=Join-Path $PSScriptRoot 'service-workers.json' }

function Read-NrWorkerConfiguration {
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { throw "Worker configuration is missing: $ConfigPath" }
    $document=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$document.schemaVersion -ne 1) { throw 'Worker configuration schemaVersion must be 1.' }
    $services=@($document.services)
    if ($services.Count -eq 0) { throw 'Worker configuration contains no services.' }
    $ids=@{}
    foreach ($service in $services) {
        $id=ConvertTo-NrWorkerId ([string]$service.id)
        if ($ids.ContainsKey($id)) { throw "Duplicate worker service id: $id" }
        $ids[$id]=$true
        if (-not $service.strategies -or @($service.strategies).Count -eq 0) { throw "Service '$id' has no strategies." }
        if (-not $service.probe -or [string]::IsNullOrWhiteSpace([string]$service.probe.uri)) { throw "Service '$id' has no probe URI." }
        foreach ($strategy in @($service.strategies)) {
            if ([string]::IsNullOrWhiteSpace([string]$strategy.name)) { throw "Service '$id' contains an unnamed strategy." }
            if ([string]::IsNullOrWhiteSpace([string]$strategy.executable)) { throw "Strategy '$($strategy.name)' has no executable." }
            if ($null -eq $strategy.arguments) { throw "Strategy '$($strategy.name)' has no argument array." }
        }
    }
    return $document
}

function Resolve-NrWorkerExecutable {
    param([Parameter(Mandatory)][string]$Path)
    if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
    return [IO.Path]::GetFullPath((Join-Path $Root $Path))
}

function New-NrWorkerPlanFromService {
    param([Parameter(Mandatory)][object]$Service,[int]$StrategyIndex=0)
    $strategies=@($Service.strategies)
    if ($StrategyIndex -lt 0 -or $StrategyIndex -ge $strategies.Count) { throw "Invalid strategy index for '$($Service.id)'." }
    $strategy=$strategies[$StrategyIndex]
    return [pscustomobject]@{
        serviceId=[string]$Service.id
        strategy=[string]$strategy.name
        executable=Resolve-NrWorkerExecutable ([string]$strategy.executable)
        arguments=[string[]]@($strategy.arguments)
        filterTokens=[string[]]@($Service.filterTokens)
        strategyIndex=$StrategyIndex
    }
}

function Get-NrInitialWorkerPlans {
    param([Parameter(Mandatory)][object]$Configuration)
    $plans=New-Object 'System.Collections.Generic.List[object]'
    foreach ($service in @($Configuration.services | Where-Object { $null -eq $_.enabled -or [bool]$_.enabled })) {
        $plans.Add((New-NrWorkerPlanFromService -Service $service -StrategyIndex 0))
    }
    return $plans.ToArray()
}

function Test-NrServiceProbe {
    param([Parameter(Mandatory)][object]$Service)
    $uri=[Uri][string]$Service.probe.uri
    $timeout=if ($Service.probe.timeoutSeconds) { [int]$Service.probe.timeoutSeconds } else { 8 }
    try {
        if ($uri.Scheme -in @('http','https')) {
            $response=Invoke-WebRequest -Uri $uri.AbsoluteUri -UseBasicParsing -TimeoutSec $timeout -Headers @{ 'User-Agent'='NexRoute-WorkerHost/0.6.0'; 'Cache-Control'='no-cache' }
            return [int]$response.StatusCode -ge 200 -and [int]$response.StatusCode -lt 500
        }
        if ($uri.Scheme -eq 'tcp') {
            $client=[Net.Sockets.TcpClient]::new()
            try {
                $task=$client.ConnectAsync($uri.Host,$uri.Port)
                if (-not $task.Wait($timeout*1000)) { return $false }
                return $client.Connected
            } finally { $client.Dispose() }
        }
        throw "Unsupported probe scheme: $($uri.Scheme)"
    } catch { return $false }
}

function Resolve-NrWorkerReplacement {
    param([Parameter(Mandatory)][object]$State,[Parameter(Mandatory)][object]$Configuration)
    $service=@($Configuration.services | Where-Object { [string]$_.id -eq [string]$State.serviceId } | Select-Object -First 1)
    if ($service.Count -eq 0) { return $null }
    $strategies=@($service[0].strategies)
    $current=-1
    for ($index=0;$index -lt $strategies.Count;$index++) { if ([string]$strategies[$index].name -eq [string]$State.strategy) { $current=$index; break } }
    if ($strategies.Count -lt 2) { return $null }
    $next=($current+1) % $strategies.Count
    return New-NrWorkerPlanFromService -Service $service[0] -StrategyIndex $next
}

function Invoke-NrHostCycle {
    param([Parameter(Mandatory)][object]$Configuration)
    $probe={
        param($state)
        $service=@($Configuration.services | Where-Object { [string]$_.id -eq [string]$state.serviceId } | Select-Object -First 1)
        if ($service.Count -eq 0) { return $false }
        return Test-NrServiceProbe -Service $service[0]
    }.GetNewClosure()
    $replacement={ param($state) Resolve-NrWorkerReplacement -State $state -Configuration $Configuration }.GetNewClosure()
    return @(Invoke-NrWorkerSupervisorCycle -Root $Root -Probe $probe -ResolveReplacement $replacement -FailureThreshold $FailureThreshold)
}

$configuration=Read-NrWorkerConfiguration
switch ($Mode) {
    'Start' {
        $plans=Get-NrInitialWorkerPlans -Configuration $configuration
        $result=@(Start-NrWorkerSet -Root $Root -Plans $plans)
    }
    'Stop' {
        Stop-NrWorkerSet -Root $Root
        $result=@()
    }
    'Status' { $result=@(Get-NrWorkerStates -Root $Root) }
    'Once' { $result=@(Invoke-NrHostCycle -Configuration $configuration) }
    'Supervise' {
        while ($true) {
            $events=@(Invoke-NrHostCycle -Configuration $configuration)
            foreach ($event in $events) {
                if ($event.action -eq 'failover') { Write-Host ("Failover {0}: {1} -> {2} (PID {3})" -f $event.serviceId,$event.oldStrategy,$event.newStrategy,$event.newPid) -ForegroundColor Yellow }
            }
            Start-Sleep -Seconds ([Math]::Min([Math]::Max($IntervalSeconds,5),3600))
        }
    }
}
if ($Mode -ne 'Supervise') {
    if ($Json) { $result | ConvertTo-Json -Depth 12 }
    else { $result | Format-Table serviceId,strategy,pid,generation,status -AutoSize }
}
