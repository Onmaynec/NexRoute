Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-NrWorkerId {
    param([Parameter(Mandatory)][string]$ServiceId)
    $id = ($ServiceId.Trim().ToLowerInvariant() -replace '[^a-z0-9._-]','-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($id)) { throw 'Service worker id is empty.' }
    return $id
}

function Get-NrWorkerRuntimeDirectory {
    param([Parameter(Mandatory)][string]$Root)
    $path = Join-Path $Root '.service/workers'
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
    return $path
}

function Get-NrWorkerStatePath {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$ServiceId)
    return Join-Path (Get-NrWorkerRuntimeDirectory -Root $Root) ((ConvertTo-NrWorkerId $ServiceId) + '.json')
}

function Write-NrWorkerState {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][hashtable]$State)
    $path = Get-NrWorkerStatePath -Root $Root -ServiceId ([string]$State.serviceId)
    $temporary = $path + '.tmp-' + [guid]::NewGuid().ToString('N')
    [IO.File]::WriteAllText($temporary,($State | ConvertTo-Json -Depth 12),(New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temporary -Destination $path -Force
    return $path
}

function Read-NrWorkerState {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$ServiceId)
    $path = Get-NrWorkerStatePath -Root $Root -ServiceId $ServiceId
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try { return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { throw "Worker state is invalid: $path" }
}

function Get-NrWorkerStates {
    param([Parameter(Mandatory)][string]$Root)
    $states = New-Object 'System.Collections.Generic.List[object]'
    foreach ($file in @(Get-ChildItem -LiteralPath (Get-NrWorkerRuntimeDirectory -Root $Root) -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        try { $states.Add((Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json)) } catch { }
    }
    return $states.ToArray()
}

function Test-NrWorkerProcess {
    param([Parameter(Mandatory)][object]$State)
    try {
        $process = Get-Process -Id ([int]$State.pid) -ErrorAction Stop
        return -not $process.HasExited
    } catch { return $false }
}

function New-NrWorkerStartInfo {
    param([Parameter(Mandatory)][string]$Executable,[Parameter(Mandatory)][string[]]$Arguments,[Parameter(Mandatory)][string]$WorkingDirectory)
    if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) { throw "Worker executable does not exist: $Executable" }
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $Executable
    $info.WorkingDirectory = $WorkingDirectory
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $false
    $info.RedirectStandardError = $false
    foreach ($argument in $Arguments) { [void]$info.ArgumentList.Add([string]$argument) }
    return $info
}

function Start-NrServiceWorker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ServiceId,
        [Parameter(Mandatory)][string]$Strategy,
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][string[]]$Arguments,
        [string[]]$FilterTokens = @(),
        [int]$Generation = 1
    )
    $workerId = ConvertTo-NrWorkerId $ServiceId
    $runtime = Get-NrWorkerRuntimeDirectory -Root $Root
    $logs = Join-Path $runtime 'logs'
    New-Item -ItemType Directory -Path $logs -Force | Out-Null
    $stdout = Join-Path $logs ($workerId + '.stdout.log')
    $stderr = Join-Path $logs ($workerId + '.stderr.log')

    $existing = Read-NrWorkerState -Root $Root -ServiceId $ServiceId
    if ($existing -and (Test-NrWorkerProcess -State $existing)) { throw "Worker for '$ServiceId' is already running with PID $($existing.pid)." }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = New-NrWorkerStartInfo -Executable $Executable -Arguments $Arguments -WorkingDirectory $Root
    if (-not $process.Start()) { throw "Failed to start worker for '$ServiceId'." }

    $metadata = "{0} START service={1} strategy={2} pid={3} generation={4}{5}" -f [DateTime]::UtcNow.ToString('o'),$ServiceId,$Strategy,$process.Id,$Generation,[Environment]::NewLine
    [IO.File]::WriteAllText($stdout,$metadata,(New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText($stderr,'',(New-Object Text.UTF8Encoding($false)))

    $state = [ordered]@{
        schemaVersion=1; workerId=$workerId; serviceId=$ServiceId; strategy=$Strategy; executable=$Executable
        arguments=@($Arguments); filterTokens=@($FilterTokens); pid=$process.Id; generation=$Generation
        startedUtc=[DateTime]::UtcNow.ToString('o'); lastHealthyUtc=$null; consecutiveFailures=0; status='running'
        stdout=$stdout; stderr=$stderr
    }
    Write-NrWorkerState -Root $Root -State $state | Out-Null
    return [pscustomobject]$state
}

function Stop-NrServiceWorker {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$ServiceId,[int]$TimeoutSeconds=5)
    $state = Read-NrWorkerState -Root $Root -ServiceId $ServiceId
    if (-not $state) { return $false }
    try {
        $process = Get-Process -Id ([int]$state.pid) -ErrorAction Stop
        if (-not $process.HasExited) {
            [void]$process.CloseMainWindow()
            if (-not $process.WaitForExit($TimeoutSeconds * 1000)) { $process.Kill($true) }
            $process.WaitForExit()
        }
    } catch { }
    $newState = @{}
    foreach ($property in $state.PSObject.Properties) { $newState[$property.Name] = $property.Value }
    $newState.status='stopped'; $newState.stoppedUtc=[DateTime]::UtcNow.ToString('o')
    Write-NrWorkerState -Root $Root -State $newState | Out-Null
    return $true
}

function Assert-NrWorkerFilterIsolation {
    param([Parameter(Mandatory)][object[]]$Plans)
    $owners=@{}
    foreach ($plan in $Plans) {
        foreach ($token in @($plan.filterTokens)) {
            $normalized=([string]$token).Trim().ToLowerInvariant()
            if (-not $normalized) { continue }
            if ($owners.ContainsKey($normalized)) { throw "Worker filter collision '$normalized' between '$($owners[$normalized])' and '$($plan.serviceId)'." }
            $owners[$normalized]=[string]$plan.serviceId
        }
    }
    return $true
}

function Start-NrWorkerSet {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][object[]]$Plans)
    Assert-NrWorkerFilterIsolation -Plans $Plans | Out-Null
    $started=New-Object 'System.Collections.Generic.List[object]'
    try {
        foreach ($plan in $Plans) {
            $started.Add((Start-NrServiceWorker -Root $Root -ServiceId $plan.serviceId -Strategy $plan.strategy -Executable $plan.executable -Arguments ([string[]]$plan.arguments) -FilterTokens ([string[]]$plan.filterTokens)))
        }
        return $started.ToArray()
    } catch {
        foreach ($worker in $started) { Stop-NrServiceWorker -Root $Root -ServiceId $worker.serviceId | Out-Null }
        throw
    }
}

function Invoke-NrWorkerSupervisorCycle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][scriptblock]$Probe,
        [Parameter(Mandatory)][scriptblock]$ResolveReplacement,
        [int]$FailureThreshold=3
    )
    if ($FailureThreshold -lt 1) { throw 'FailureThreshold must be at least 1.' }
    $events=New-Object 'System.Collections.Generic.List[object]'
    foreach ($state in @(Get-NrWorkerStates -Root $Root | Where-Object { $_.status -eq 'running' })) {
        $processAlive=Test-NrWorkerProcess -State $state
        $probeResult=$false
        if ($processAlive) { try { $probeResult=[bool](& $Probe $state) } catch { $probeResult=$false } }
        $mutable=@{}
        foreach ($property in $state.PSObject.Properties) { $mutable[$property.Name]=$property.Value }
        if ($processAlive -and $probeResult) {
            $mutable.consecutiveFailures=0; $mutable.lastHealthyUtc=[DateTime]::UtcNow.ToString('o')
            Write-NrWorkerState -Root $Root -State $mutable | Out-Null
            $events.Add([pscustomobject]@{ serviceId=$state.serviceId; action='healthy'; pid=$state.pid; strategy=$state.strategy })
            continue
        }
        $mutable.consecutiveFailures=[int]$mutable.consecutiveFailures+1
        Write-NrWorkerState -Root $Root -State $mutable | Out-Null
        if ([int]$mutable.consecutiveFailures -lt $FailureThreshold) {
            $events.Add([pscustomobject]@{ serviceId=$state.serviceId; action='failure-recorded'; pid=$state.pid; strategy=$state.strategy })
            continue
        }
        Stop-NrServiceWorker -Root $Root -ServiceId ([string]$state.serviceId) | Out-Null
        $replacement=& $ResolveReplacement $state
        if (-not $replacement) {
            $events.Add([pscustomobject]@{ serviceId=$state.serviceId; action='stopped-no-replacement'; pid=$state.pid; strategy=$state.strategy })
            continue
        }
        $next=Start-NrServiceWorker -Root $Root -ServiceId ([string]$state.serviceId) -Strategy ([string]$replacement.strategy) -Executable ([string]$replacement.executable) -Arguments ([string[]]$replacement.arguments) -FilterTokens ([string[]]$replacement.filterTokens) -Generation ([int]$state.generation+1)
        $events.Add([pscustomobject]@{ serviceId=$state.serviceId; action='failover'; oldPid=$state.pid; newPid=$next.pid; oldStrategy=$state.strategy; newStrategy=$next.strategy; generation=$next.generation })
    }
    return $events.ToArray()
}

function Stop-NrWorkerSet {
    param([Parameter(Mandatory)][string]$Root)
    foreach ($state in @(Get-NrWorkerStates -Root $Root)) { Stop-NrServiceWorker -Root $Root -ServiceId ([string]$state.serviceId) | Out-Null }
}
