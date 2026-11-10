[CmdletBinding()]
param(
    [ValidateSet('Start','Stop','Status','Inspect','StartService','StopService','RestartService','Once','Supervise')][string]$Mode='Status',
    [string]$Root,
    [string]$ConfigPath,
    [string]$ServiceId,
    [int]$IntervalSeconds=20,
    [int]$FailureThreshold=3,
    [ValidateRange(0,3600)][int]$CooldownSeconds=30,
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if (-not $Root) { $Root=Split-Path -Parent $PSScriptRoot }
$Root=[IO.Path]::GetFullPath($Root)
. (Join-Path $PSScriptRoot 'next/nexroute-workers.ps1')
. (Join-Path $PSScriptRoot 'next/nexroute-worker-scopes-072.ps1')
. (Join-Path $PSScriptRoot 'next/nexroute-family-probe.ps1')
if (-not $ConfigPath) { $ConfigPath=Join-Path $PSScriptRoot 'service-workers.json' }

function Get-NrHostPropertyValue {
    param($Object,[Parameter(Mandatory)][string]$Name,$Default=$null)
    if ($null -eq $Object) { return $Default }
    $property=$Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $Default
}

function Read-NrWorkerConfiguration {
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { throw "Worker configuration is missing: $ConfigPath" }
    $document=Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $schemaVersion=[int](Get-NrHostPropertyValue -Object $document -Name 'schemaVersion' -Default 0)
    if ($schemaVersion -notin @(1,2)) { throw 'Worker configuration schemaVersion must be 1 or 2.' }
    $services=@($document.services)
    if ($services.Count -eq 0) { throw 'Worker configuration contains no services.' }
    $ids=@{}
    foreach ($service in $services) {
        $id=ConvertTo-NrWorkerId ([string]$service.id)
        if ($ids.ContainsKey($id)) { throw "Duplicate worker service id: $id" }
        $ids[$id]=$true
        if (-not $service.strategies -or @($service.strategies).Count -eq 0) { throw "Service '$id' has no strategies." }
        if (-not $service.probe -or [string]::IsNullOrWhiteSpace([string]$service.probe.uri)) { throw "Service '$id' has no probe URI." }
        if (@($service.filterTokens).Count -eq 0) { throw "Worker '$id' has no scoped filter tokens." }
        $probeFamily=[string](Get-NrHostPropertyValue -Object $service.probe -Name 'addressFamily' -Default '')
        if ($probeFamily -and $probeFamily -notin @('ipv4','ipv6')) { throw "Service '$id' has an unsupported probe address family: $probeFamily" }
        foreach ($strategy in @($service.strategies)) {
            if ([string]::IsNullOrWhiteSpace([string]$strategy.name)) { throw "Service '$id' contains an unnamed strategy." }
            if ([string]::IsNullOrWhiteSpace([string]$strategy.executable)) { throw "Strategy '$($strategy.name)' has no executable." }
            if ($null -eq $strategy.arguments) { throw "Strategy '$($strategy.name)' has no argument array." }
            $strategyFamily=[string](Get-NrHostPropertyValue -Object $strategy -Name 'addressFamily' -Default '')
            if ($probeFamily -and $strategyFamily -and $probeFamily -ne $strategyFamily) {
                throw "Service '$id' probe family '$probeFamily' differs from strategy family '$strategyFamily'."
            }
            # Only strictly scoped winws plans may run: accepting a broad
            # user-edited worker config would silently intercept other services.
            if ([IO.Path]::GetFileName([string]$strategy.executable) -ieq 'winws.exe') {
                if (-not $service.filterFiles) { throw "Worker '$id' has no scoped filter file metadata." }
                $hostPath=[string]$service.filterFiles.hostlist
                $ipsetPath=[string]$service.filterFiles.ipset
                if (-not (Test-Path -LiteralPath $hostPath -PathType Leaf) -or -not (Test-Path -LiteralPath $ipsetPath -PathType Leaf)) {
                    throw "Worker '$id' has missing filter file(s)."
                }
                $arguments=@([string[]]$strategy.arguments)
                if ($arguments -notcontains ('--hostlist='+$hostPath) -or $arguments -notcontains ('--ipset='+$ipsetPath)) {
                    throw "Worker '$id' command is missing its service-scoped include filters."
                }
                foreach ($argument in $arguments) {
                    if ($argument -match '^--(hostlist|ipset)=' -and $argument -notin @('--hostlist='+$hostPath,'--ipset='+$ipsetPath)) {
                        throw "Worker '$id' contains a non-service-scoped include list."
                    }
                }
            }
        }
    }
    $initial=@(Get-NrInitialWorkerPlans -Configuration $document)
    Assert-NrWorkerFilterIsolation -Plans $initial | Out-Null
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
        addressFamily=[string](Get-NrHostPropertyValue -Object $strategy -Name 'addressFamily' -Default (Get-NrHostPropertyValue -Object $Service -Name 'addressFamily' -Default ''))
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
    $timeoutValue=Get-NrHostPropertyValue -Object $Service.probe -Name 'timeoutSeconds' -Default 8
    $timeout=if ($timeoutValue) { [int]$timeoutValue } else { 8 }
    $family=([string](Get-NrHostPropertyValue -Object $Service.probe -Name 'addressFamily' -Default '')).ToLowerInvariant()
    try {
        if ($family -in @('ipv4','ipv6')) {
            return Test-NrAddressFamilyProbe -Uri $uri -Family $family -TimeoutSeconds $timeout
        }
        if ($uri.Scheme -in @('http','https')) {
            $response=Invoke-WebRequest -Uri $uri.AbsoluteUri -UseBasicParsing -TimeoutSec $timeout -Headers @{ 'User-Agent'='NexRoute-WorkerHost/0.6.0'; 'Cache-Control'='no-cache' }
            return [int]$response.StatusCode -ge 200 -and [int]$response.StatusCode -lt 400
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
    $probeFunction=${function:Test-NrServiceProbe}
    $replacementFunction=${function:Resolve-NrWorkerReplacement}
    $probe={
        param($state)
        $service=@($Configuration.services | Where-Object { [string]$_.id -eq [string]$state.serviceId } | Select-Object -First 1)
        if ($service.Count -eq 0) { return $false }
        return [bool](& $probeFunction -Service $service[0])
    }.GetNewClosure()
    $replacement={ param($state) & $replacementFunction -State $state -Configuration $Configuration }.GetNewClosure()
    return @(Invoke-NrWorkerSupervisorCycle -Root $Root -Probe $probe -ResolveReplacement $replacement -FailureThreshold $FailureThreshold -CooldownSeconds $CooldownSeconds)
}

function Invoke-NrHostOperationLock072 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][scriptblock]$Action)
    $sha=[Security.Cryptography.SHA256]::Create()
    try { $hash=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Root.ToLowerInvariant()))).Replace('-','') }
    finally { $sha.Dispose() }
    $mutex=[Threading.Mutex]::new($false,('Global\NexRoute.WorkerOperation.'+$hash.Substring(0,24)))
    $owns=$false
    try {
        try { $owns=$mutex.WaitOne(10000) }
        catch [Threading.AbandonedMutexException] { $owns=$true }
        if (-not $owns) { throw 'Worker management is already busy; retry after the active operation finishes.' }
        return & $Action
    } finally {
        if ($owns) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

function Get-NrHostService072 {
    param([Parameter(Mandatory)]$Configuration,[Parameter(Mandatory)][string]$Id)
    $wanted=ConvertTo-NrWorkerId $Id
    $matches=@($Configuration.services | Where-Object {
        (ConvertTo-NrWorkerId ([string]$_.id)) -eq $wanted -and ($null -eq $_.enabled -or [bool]$_.enabled)
    })
    if ($matches.Count -ne 1) { throw "Enabled service '$wanted' was not found in the worker configuration." }
    return $matches[0]
}

function Invoke-NrSingleWorkerOperation072 {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Configuration,[Parameter(Mandatory)][string]$Action,[Parameter(Mandatory)][string]$Id)
    $service=Get-NrHostService072 -Configuration $Configuration -Id $Id
    $name=ConvertTo-NrWorkerId $Id
    $previous=Read-NrWorkerState -Root $Root -ServiceId $name
    if ($Action -eq 'StopService') {
        $stopped=Stop-NrServiceWorker -Root $Root -ServiceId $name
        if (-not $stopped) { throw "Worker '$name' could not be stopped: its process identity is unverified or state is missing." }
        return [pscustomobject]@{serviceId=$name;action='stopped';processState='not-running'}
    }

    $index=0
    if ($previous) {
        for($i=0;$i -lt @($service.strategies).Count;$i++) {
            if ([string]$service.strategies[$i].name -eq [string]$previous.strategy) { $index=$i; break }
        }
    }
    $plan=New-NrWorkerPlanFromService -Service $service -StrategyIndex $index
    $otherPlans=@(Get-NrWorkerStates -Root $Root | Where-Object { $_.serviceId -ne $name -and $_.status -eq 'running' } |
        ForEach-Object { [pscustomobject]@{serviceId=$_.serviceId;filterTokens=@($_.filterTokens)} })
    Assert-NrWorkerFilterIsolation -Plans @($otherPlans + @([pscustomobject]@{serviceId=$name;filterTokens=$plan.filterTokens})) | Out-Null

    if ($Action -eq 'RestartService' -and $previous -and [string]$previous.status -ne 'stopped') {
        if (-not (Stop-NrServiceWorker -Root $Root -ServiceId $name)) {
            throw "Worker '$name' cannot be restarted: process identity is unverified."
        }
    }
    $generation=if($previous){[int]$previous.generation+1}else{1}
    $next=Start-NrServiceWorker -Root $Root -ServiceId $name -Strategy $plan.strategy -Executable $plan.executable -Arguments ([string[]]$plan.arguments) -FilterTokens ([string[]]$plan.filterTokens) -Generation $generation
    return [pscustomobject]@{serviceId=$name;action=$(if($Action -eq 'RestartService'){'restarted'}else{'started'});pid=$next.pid;generation=$next.generation;strategy=$next.strategy}
}

$configuration=$null
if ($Mode -in @('Start','StartService','StopService','RestartService','Once','Supervise')) {
    $configuration=Read-NrWorkerConfiguration
} elseif ($Mode -eq 'Inspect' -and (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    $configuration=Read-NrWorkerConfiguration
}

switch ($Mode) {
    'Start' {
        $scope=Get-NrWorkerScopeReport072 -Configuration $configuration
        if (-not $Json -and $scope.overlapPairs -gt 0) {
            Write-Warning ("Service Matrix: {0} overlapping filter pairs detected. Inspect scopes before interpreting probes." -f $scope.overlapPairs)
        }
        if (-not $Json -and $scope.coverage -eq 'partial') {
            Write-Warning 'Service Matrix scope inspection is partial; do not assume full filter isolation.'
        }
        $plans=Get-NrInitialWorkerPlans -Configuration $configuration
        $result=@(Invoke-NrHostOperationLock072 -Action { Start-NrWorkerSet -Root $Root -Plans $plans })
    }
    'Stop' {
        Invoke-NrHostOperationLock072 -Action { Stop-NrWorkerSet -Root $Root } | Out-Null
        $result=@()
    }
    'StartService' {
        if (-not $ServiceId) { throw 'StartService requires -ServiceId.' }
        $result=Invoke-NrHostOperationLock072 -Action { Invoke-NrSingleWorkerOperation072 -Configuration $configuration -Action 'StartService' -Id $ServiceId }
    }
    'StopService' {
        if (-not $ServiceId) { throw 'StopService requires -ServiceId.' }
        $result=Invoke-NrHostOperationLock072 -Action { Invoke-NrSingleWorkerOperation072 -Configuration $configuration -Action 'StopService' -Id $ServiceId }
    }
    'RestartService' {
        if (-not $ServiceId) { throw 'RestartService requires -ServiceId.' }
        $result=Invoke-NrHostOperationLock072 -Action { Invoke-NrSingleWorkerOperation072 -Configuration $configuration -Action 'RestartService' -Id $ServiceId }
    }
    'Status' { $result=@(Get-NrWorkerStates -Root $Root) }
    'Inspect' { $result=Get-NrWorkerRuntimeReport072 -Root $Root -Configuration $configuration }
    'Once' { $result=@(Invoke-NrHostOperationLock072 -Action { Invoke-NrHostCycle -Configuration $configuration }) }
    'Supervise' {
        # One supervisor per installation, including a second AtLogOn task
        # or an accidentally started extra terminal.
        $sha=[Security.Cryptography.SHA256]::Create()
        try {
            $hash=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Root.ToLowerInvariant()))).Replace('-','')
        } finally { $sha.Dispose() }
        $mutexName='Global\NexRoute.WorkerHost.'+$hash.Substring(0,24)
        $mutex=[Threading.Mutex]::new($false,$mutexName)
        $owns=$false
        try {
            try { $owns=$mutex.WaitOne(0) }
            catch [Threading.AbandonedMutexException] { $owns=$true }
            if (-not $owns) { Write-Warning 'NexRoute worker supervisor is already active for this installation.'; return }
            while ($true) {
                $events=@(Invoke-NrHostOperationLock072 -Action { Invoke-NrHostCycle -Configuration $configuration })
                foreach ($event in $events) {
                    if ($event.action -eq 'failover') {
                        Write-Host ("Failover {0}: {1} -> {2} (PID {3}; cooldown {4}s)" -f $event.serviceId,$event.oldStrategy,$event.newStrategy,$event.newPid,$event.cooldownSeconds) -ForegroundColor Yellow
                    } elseif ($event.action -in @('identity-unverified','restart-failed','stopped-no-replacement')) {
                        Write-Warning ("Worker {0}: {1} (requires review)" -f $event.serviceId,$event.action)
                    }
                }
                Start-Sleep -Seconds ([Math]::Min([Math]::Max($IntervalSeconds,5),3600))
            }
        } finally {
            if ($owns) { $mutex.ReleaseMutex() }
            $mutex.Dispose()
        }
    }
}
if ($Mode -ne 'Supervise') {
    if ($Json) { ConvertTo-Json -InputObject $result -Depth 12 }
    elseif ($Mode -eq 'Inspect') {
        Write-Host ("Workers: {0} total, {1} verified running, {2} unhealthy" -f $result.total,$result.running,$result.unhealthy)
        $result.workers | Format-Table serviceId,strategy,pid,generation,status,processState,consecutiveFailures,cooldownActive -AutoSize
        if ($result.scopes) {
            Write-Host ("Filter overlaps: {0}; inspection coverage: {1}" -f $result.scopes.overlapPairs,$result.scopes.coverage)
            $result.scopes.warnings | Format-Table serviceA,serviceB,overlappingDomains,overlappingCidrs -AutoSize
        }
    } else { $result | Format-Table serviceId,strategy,pid,generation,status,addressFamily -AutoSize }
}
