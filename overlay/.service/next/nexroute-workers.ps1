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
        try { $states.Add((Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json)) }
        catch { throw "Worker state cannot be read: $($file.Name)" }
    }
    return $states.ToArray()
}

function Get-NrWorkerProcessIdentity {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State)
    $pidValue=0
    try { $pidValue=[int]$State.pid } catch { }
    if ($pidValue -le 0) { return [pscustomobject]@{ status='exited'; pid=$pidValue; reason='invalid-pid' } }
    $process=$null
    try {
        $process=Get-Process -Id $pidValue -ErrorAction Stop
    } catch {
        # No process with this PID: the child has already exited.
        if ($_.FullyQualifiedErrorId -like '*NoProcessFound*' -or
            $_.FullyQualifiedErrorId -like '*ProcessNotFound*' -or
            $_.Exception -is [ArgumentException]) {
            return [pscustomobject]@{status='exited';pid=$pidValue;reason='not-found'}
        }
        return [pscustomobject]@{status='unverified';pid=$pidValue;reason='process-lookup-failed'}
    }
    try {
        if ($process.HasExited) { return [pscustomobject]@{status='exited';pid=$pidValue;reason='exited'} }
        $storedStart=$null
        $storedText=''
        if ($State.PSObject.Properties['processStartedUtc']) { $storedText=[string]$State.processStartedUtc }
        if ([string]::IsNullOrWhiteSpace($storedText) -or
            -not [DateTime]::TryParse($storedText,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$storedStart)) {
            return [pscustomobject]@{status='unverified';pid=$pidValue;reason='missing-process-identity'}
        }
        $actualStart=$process.StartTime.ToUniversalTime()
        $distance=[Math]::Abs(($actualStart-$storedStart.ToUniversalTime()).TotalMilliseconds)
        if ($distance -gt 1000) {
            return [pscustomobject]@{status='mismatch';pid=$pidValue;reason='start-time-mismatch'}
        }
        $expected=[IO.Path]::GetFullPath([string]$State.executable)
        $actual=$process.Path
        if ([string]::IsNullOrWhiteSpace($actual)) {
            return [pscustomobject]@{status='unverified';pid=$pidValue;reason='executable-unavailable'}
        }
        if (-not [string]::Equals([IO.Path]::GetFullPath($actual),$expected,[StringComparison]::OrdinalIgnoreCase)) {
            return [pscustomobject]@{status='mismatch';pid=$pidValue;reason='executable-mismatch'}
        }
        return [pscustomobject]@{status='verified';pid=$pidValue;reason='start-time-and-executable-match'}
    } catch {
        return [pscustomobject]@{status='unverified';pid=$pidValue;reason='identity-inspection-failed'}
    } finally { if ($process) { $process.Dispose() } }
}

function Test-NrWorkerProcess {
    param([Parameter(Mandatory)][object]$State)
    return (Get-NrWorkerProcessIdentity -State $State).status -eq 'verified'
}

function ConvertTo-NrWorkerArgument072 {
    param([AllowEmptyString()][string]$Value)
    if ($Value.IndexOfAny([char[]]@([char]0,[char]10,[char]13)) -ge 0) {
        throw 'Worker argument contains unsupported control characters.'
    }
    if ($Value -notmatch '[\s"]' -and $Value.Length -gt 0) { return $Value }
    $result='"'
    $slashes=0
    foreach ($char in $Value.ToCharArray()) {
        if ($char -eq [char]92) { $slashes++; continue }
        if ($char -eq [char]34) {
            $result+=('\' * ($slashes*2+1))+'"'
            $slashes=0
            continue
        }
        $result+=('\' * $slashes)+$char
        $slashes=0
    }
    return $result+('\' * ($slashes*2))+'"'
}

function New-NrWorkerStartInfo {
    param([Parameter(Mandatory)][string]$Executable,[Parameter(Mandatory)][string[]]$Arguments,[Parameter(Mandatory)][string]$WorkingDirectory)
    if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) { throw "Worker executable does not exist: $Executable" }
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = [IO.Path]::GetFullPath($Executable)
    $info.WorkingDirectory = $WorkingDirectory
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $false
    $info.RedirectStandardError = $false
    # ArgumentList is unavailable on Windows PowerShell 5.1 / .NET Framework.
    # Use one quoting algorithm on both hosts for deterministic launch behavior.
    $info.Arguments=(@($Arguments | ForEach-Object { ConvertTo-NrWorkerArgument072 -Value ([string]$_) }) -join ' ')
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
        [int]$Generation = 1,
        [int]$ConsecutiveFailovers = 0,
        [string]$CooldownUntilUtc = ''
    )
    $workerId = ConvertTo-NrWorkerId $ServiceId
    $runtime = Get-NrWorkerRuntimeDirectory -Root $Root
    $logs = Join-Path $runtime 'logs'
    New-Item -ItemType Directory -Path $logs -Force | Out-Null
    $stdout = Join-Path $logs ($workerId + '.stdout.log')
    $stderr = Join-Path $logs ($workerId + '.stderr.log')

    $existing = Read-NrWorkerState -Root $Root -ServiceId $ServiceId
    if ($existing -and [string]$existing.status -ne 'stopped') {
        $identity=Get-NrWorkerProcessIdentity -State $existing
        if ($identity.status -ne 'exited') {
            throw "Worker for '$ServiceId' already owns PID $($existing.pid) (identity: $($identity.status)); refusing to launch a duplicate."
        }
    }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = New-NrWorkerStartInfo -Executable $Executable -Arguments $Arguments -WorkingDirectory $Root
    if (-not $process.Start()) { throw "Failed to start worker for '$ServiceId'." }
    try { $processStartUtc=$process.StartTime.ToUniversalTime().ToString('o') }
    catch {
        try { $process.Kill() } catch { }
        throw "Cannot establish worker process identity for '$ServiceId'."
    }

    $metadata = "{0} START service={1} strategy={2} pid={3} generation={4}{5}" -f [DateTime]::UtcNow.ToString('o'),$ServiceId,$Strategy,$process.Id,$Generation,[Environment]::NewLine
    [IO.File]::WriteAllText($stdout,$metadata,(New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText($stderr,'',(New-Object Text.UTF8Encoding($false)))

    $state = [ordered]@{
        schemaVersion=1; workerId=$workerId; serviceId=$ServiceId; strategy=$Strategy; executable=$Executable
        arguments=@($Arguments); filterTokens=@($FilterTokens); pid=$process.Id; generation=$Generation
        startedUtc=[DateTime]::UtcNow.ToString('o'); processStartedUtc=$processStartUtc
        lastHealthyUtc=$null; consecutiveFailures=0; healthyCycles=0
        consecutiveFailovers=$ConsecutiveFailovers; cooldownUntilUtc=$CooldownUntilUtc
        status='running'
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
    if ([string]$state.status -eq 'stopped') { return $true }
    $identity=Get-NrWorkerProcessIdentity -State $state
    if ($identity.status -in @('unverified','mismatch')) {
        # Fail closed. A PID is not an ownership token: never terminate a
        # process whose start time and executable do not match our record.
        $unsafe=@{}
        foreach($property in $state.PSObject.Properties){$unsafe[$property.Name]=$property.Value}
        $unsafe.status='identity-unverified'
        $unsafe.lastErrorCode='NR-WORKER-IDENTITY'
        Write-NrWorkerState -Root $Root -State $unsafe | Out-Null
        return $false
    }
    if ($identity.status -eq 'verified') {
        $process=$null
        try {
            $process=Get-Process -Id ([int]$state.pid) -ErrorAction Stop
            if (-not $process.HasExited) {
                # Verify again just before terminating. No broad Stop-Process by name.
                if ((Get-NrWorkerProcessIdentity -State $state).status -ne 'verified') { return $false }
                [void]$process.CloseMainWindow()
                if (-not $process.WaitForExit(([Math]::Max(1,$TimeoutSeconds))*1000)) {
                    $process.Kill()
                }
                $process.WaitForExit()
            }
        } finally { if($process){$process.Dispose()} }
    }
    $newState = @{}
    foreach ($property in $state.PSObject.Properties) { $newState[$property.Name] = $property.Value }
    $newState.status='stopped'; $newState.stoppedUtc=[DateTime]::UtcNow.ToString('o')
    Write-NrWorkerState -Root $Root -State $newState | Out-Null
    return $true
}

function Assert-NrWorkerFilterIsolation {
    param([Parameter(Mandatory)][object[]]$Plans)
    $owners=@{}
    $services=@{}
    foreach ($plan in $Plans) {
        $serviceId=ConvertTo-NrWorkerId ([string]$plan.serviceId)
        if ($services.ContainsKey($serviceId)) {
            throw "Duplicate normalized worker service id: $serviceId"
        }
        $services[$serviceId]=$true
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
        foreach ($worker in $started) { try { Stop-NrServiceWorker -Root $Root -ServiceId $worker.serviceId | Out-Null } catch { } }
        throw
    }
}

function Get-NrWorkerStateValue072 {
    param($State,[Parameter(Mandatory)][string]$Name,$Default=$null)
    if ($null -eq $State) { return $Default }
    if ($State -is [System.Collections.IDictionary]) {
        if ($State.Contains($Name)) { return $State[$Name] }
        return $Default
    }
    $property=$State.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $Default
}

function Get-NrWorkerCooldown072 {
    param($State)
    $text=[string](Get-NrWorkerStateValue072 $State 'cooldownUntilUtc' '')
    if (-not $text) { return $false }
    $until=[datetime]::MinValue
    if (-not [DateTime]::TryParse($text,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$until)) { return $false }
    return [DateTime]::UtcNow -lt $until.ToUniversalTime()
}

function Invoke-NrWorkerSupervisorCycle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][scriptblock]$Probe,
        [Parameter(Mandatory)][scriptblock]$ResolveReplacement,
        [ValidateRange(1,100)][int]$FailureThreshold=3,
        [ValidateRange(0,3600)][int]$CooldownSeconds=30,
        [ValidateRange(0,3600)][int]$MaximumCooldownSeconds=300
    )
    $events=New-Object 'System.Collections.Generic.List[object]'
    foreach ($state in @(Get-NrWorkerStates -Root $Root | Where-Object { $_.status -eq 'running' })) {
        $identity=Get-NrWorkerProcessIdentity -State $state
        $mutable=@{}
        foreach ($property in $state.PSObject.Properties) { $mutable[$property.Name]=$property.Value }
        if ($identity.status -notin @('verified','exited')) {
            $mutable.status='identity-unverified'
            $mutable.lastErrorCode='NR-WORKER-IDENTITY'
            Write-NrWorkerState -Root $Root -State $mutable | Out-Null
            $events.Add([pscustomobject]@{serviceId=$state.serviceId;action='identity-unverified';pid=$state.pid;reason=$identity.reason})
            continue
        }
        $passed=$false
        if ($identity.status -eq 'verified') {
            try { $passed=[bool](& $Probe $state) } catch { $passed=$false }
        }
        if ($identity.status -eq 'verified' -and $passed) {
            $mutable.consecutiveFailures=0
            $mutable.healthyCycles=[int](Get-NrWorkerStateValue072 $state 'healthyCycles' 0)+1
            $mutable.lastHealthyUtc=[DateTime]::UtcNow.ToString('o')
            $mutable.lastErrorCode=$null
            if ($mutable.healthyCycles -ge 3) { $mutable.consecutiveFailovers=0; $mutable.cooldownUntilUtc='' }
            Write-NrWorkerState -Root $Root -State $mutable | Out-Null
            $events.Add([pscustomobject]@{serviceId=$state.serviceId;action='healthy';pid=$state.pid;strategy=$state.strategy})
            continue
        }
        $mutable.healthyCycles=0
        $mutable.consecutiveFailures=[int](Get-NrWorkerStateValue072 $state 'consecutiveFailures' 0)+1
        $mutable.lastErrorCode=$(if($identity.status -eq 'exited'){'NR-WORKER-EXITED'}else{'NR-WORKER-PROBE'})
        Write-NrWorkerState -Root $Root -State $mutable | Out-Null
        if ($mutable.consecutiveFailures -lt $FailureThreshold) {
            $events.Add([pscustomobject]@{serviceId=$state.serviceId;action='failure-recorded';pid=$state.pid;strategy=$state.strategy})
            continue
        }
        if (Get-NrWorkerCooldown072 -State $mutable) {
            $events.Add([pscustomobject]@{serviceId=$state.serviceId;action='cooldown';pid=$state.pid;strategy=$state.strategy})
            continue
        }
        if (-not (Stop-NrServiceWorker -Root $Root -ServiceId ([string]$state.serviceId))) {
            $events.Add([pscustomobject]@{serviceId=$state.serviceId;action='identity-unverified';pid=$state.pid;reason='stop-refused'})
            continue
        }
        try {
            $replacement=& $ResolveReplacement $state
            if (-not $replacement) {
                $halted=Read-NrWorkerState -Root $Root -ServiceId ([string]$state.serviceId)
                $failed=@{}
                foreach ($property in $halted.PSObject.Properties) { $failed[$property.Name]=$property.Value }
                $failed.status='failed'; $failed.lastErrorCode='NR-WORKER-NO-FALLBACK'
                Write-NrWorkerState -Root $Root -State $failed | Out-Null
                $events.Add([pscustomobject]@{serviceId=$state.serviceId;action='stopped-no-replacement';pid=$state.pid;strategy=$state.strategy})
                continue
            }
            $count=[int](Get-NrWorkerStateValue072 $state 'consecutiveFailovers' 0)+1
            $factor=[Math]::Pow(2,[Math]::Min(4,[Math]::Max(0,$count-1)))
            $seconds=[int][Math]::Min($MaximumCooldownSeconds,$CooldownSeconds*$factor)
            $cooldown=if($seconds -gt 0){[DateTime]::UtcNow.AddSeconds($seconds).ToString('o')}else{''}
            $args=@{Root=$Root;ServiceId=[string]$state.serviceId;Strategy=[string]$replacement.strategy;Executable=[string]$replacement.executable;Arguments=[string[]]$replacement.arguments;FilterTokens=[string[]]$replacement.filterTokens;Generation=([int]$state.generation+1);ConsecutiveFailovers=$count;CooldownUntilUtc=$cooldown}
            $next=Start-NrServiceWorker @args
            $events.Add([pscustomobject]@{serviceId=$state.serviceId;action='failover';oldPid=$state.pid;newPid=$next.pid;oldStrategy=$state.strategy;newStrategy=$next.strategy;generation=$next.generation;cooldownSeconds=$seconds})
        } catch {
            # A failed restart must not take down healthy services.
            $halted=Read-NrWorkerState -Root $Root -ServiceId ([string]$state.serviceId)
            if ($halted -and [string]$halted.status -eq 'stopped') {
                $failed=@{}
                foreach ($property in $halted.PSObject.Properties) { $failed[$property.Name]=$property.Value }
                $failed.status='failed'; $failed.lastErrorCode='NR-WORKER-RESTART'
                Write-NrWorkerState -Root $Root -State $failed | Out-Null
            }
            $events.Add([pscustomobject]@{serviceId=$state.serviceId;action='restart-failed';pid=$state.pid;errorCode='NR-WORKER-RESTART'})
        }
    }
    return $events.ToArray()
}

function Stop-NrWorkerSet {
    param([Parameter(Mandatory)][string]$Root)
    foreach ($state in @(Get-NrWorkerStates -Root $Root | Where-Object { $_.status -ne 'stopped' })) {
        if (-not (Stop-NrServiceWorker -Root $Root -ServiceId ([string]$state.serviceId))) {
            throw "Worker '$($state.serviceId)' could not be stopped safely: process identity is unverified."
        }
    }
}
