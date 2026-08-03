Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function ConvertFrom-NrCommandLineArguments {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$CommandLine)
    $arguments=New-Object 'System.Collections.Generic.List[string]'
    foreach ($match in [regex]::Matches($CommandLine,'(?:[^\s"]|"[^"]*")+')) {
        $value=$match.Value.Trim()
        if (-not $value) { continue }
        $value=[regex]::Replace($value,'="([^"]*)"$','=$1')
        if ($value.Length -ge 2 -and $value[0] -eq '"' -and $value[$value.Length-1] -eq '"') {
            $value=$value.Substring(1,$value.Length-2)
        }
        $arguments.Add($value)
    }
    return $arguments.ToArray()
}

function Get-NrPerServiceMappingEntries {
    param([Parameter(Mandatory)]$Mapping)
    $entries=New-Object 'System.Collections.Generic.List[object]'
    if ($Mapping -is [hashtable]) {
        foreach ($entry in $Mapping.GetEnumerator()) { $entries.Add([pscustomobject]@{ serviceId=[string]$entry.Key; strategy=[string]$entry.Value }) }
    } else {
        foreach ($property in @($Mapping.PSObject.Properties)) { $entries.Add([pscustomobject]@{ serviceId=[string]$property.Name; strategy=[string]$property.Value }) }
    }
    return @($entries.ToArray() | Where-Object { $_.serviceId -and $_.strategy } | Sort-Object serviceId)
}

function Get-NrWorkerStrategyCandidates {
    param(
        [Parameter(Mandatory)][string]$SelectedName,
        [Parameter(Mandatory)][System.IO.FileInfo[]]$Strategies,
        [int]$Maximum=3
    )
    $lookup=@{}
    foreach ($strategy in $Strategies) {
        $lookup[$strategy.Name.ToLowerInvariant()]=$strategy
        $lookup[$strategy.BaseName.ToLowerInvariant()]=$strategy
    }
    $selectedKey=$SelectedName.ToLowerInvariant()
    if (-not $lookup.ContainsKey($selectedKey)) { throw "Selected per-service strategy does not exist: $SelectedName" }
    $ordered=New-Object 'System.Collections.Generic.List[System.IO.FileInfo]'
    $seen=@{}
    $addCandidate={
        param([System.IO.FileInfo]$Candidate)
        if (-not $Candidate) { return }
        $key=$Candidate.FullName.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { return }
        $seen[$key]=$true
        $ordered.Add($Candidate)
    }.GetNewClosure()
    & $addCandidate $lookup[$selectedKey]

    $run=Get-NrLatestLabRun
    if ($run -and $run.results) {
        foreach ($result in @($run.results | Sort-Object score -Descending)) {
            $name=[string]$result.strategy
            if (-not $name) { continue }
            $key=$name.ToLowerInvariant()
            if ($lookup.ContainsKey($key)) { & $addCandidate $lookup[$key] }
            elseif ($lookup.ContainsKey(($name+'.bat').ToLowerInvariant())) { & $addCandidate $lookup[($name+'.bat').ToLowerInvariant()] }
            if ($ordered.Count -ge $Maximum) { break }
        }
    }
    foreach ($strategy in $Strategies) {
        if ($ordered.Count -ge $Maximum) { break }
        & $addCandidate $strategy
    }
    return @($ordered.ToArray() | Select-Object -First ([Math]::Max(1,$Maximum)))
}

function Get-NrServiceProbeUri {
    param([Parameter(Mandatory)]$Definition)
    foreach ($target in @($Definition.testTargets)) {
        $value=$null
        if ($target.PSObject.Properties['url']) { $value=[string]$target.url }
        elseif ($target.PSObject.Properties['value']) { $value=[string]$target.value }
        if ($value -match '^https?://') { return $value }
    }
    foreach ($domain in @($Definition.domains)) {
        if ([string]$domain) { return 'https://'+[string]$domain+'/' }
    }
    throw "Service '$($Definition.id)' has no HTTP or HTTPS probe target."
}

function Assert-NrServiceFilterFiles {
    param([Parameter(Mandatory)][string]$ServiceId)
    $hostList=Join-Path $script:NrRoot ('lists\list-service-'+$ServiceId+'.txt')
    $ipset=Join-Path $script:NrRoot ('lists\ipset-service-'+$ServiceId+'.txt')
    if (-not (Test-Path -LiteralPath $hostList -PathType Leaf)) { throw "Service hostlist is missing: $hostList" }
    if (-not (Test-Path -LiteralPath $ipset -PathType Leaf)) { throw "Service ipset is missing: $ipset" }
    $hostEntries=@(Get-Content -LiteralPath $hostList -Encoding UTF8 | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') })
    $ipEntries=@(Get-Content -LiteralPath $ipset -Encoding UTF8 | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') })
    if ($hostEntries.Count -eq 0 -and $ipEntries.Count -eq 0) { throw "Service '$ServiceId' has no hostlist or ipset entries." }
    return [pscustomobject]@{ hostList=[IO.Path]::GetFullPath($hostList); ipset=[IO.Path]::GetFullPath($ipset); hostEntries=$hostEntries.Count; ipEntries=$ipEntries.Count }
}

function New-NrServiceWorkerConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Mapping,
        [System.IO.FileInfo[]]$Strategies=@(Get-NrStrategies),
        [object[]]$Definitions=@(Get-NrServiceDefinitions),
        [int]$MaximumStrategiesPerService=3
    )
    $entries=Get-NrPerServiceMappingEntries -Mapping $Mapping
    if ($entries.Count -eq 0) { throw 'Per-service strategy mapping is empty.' }
    $definitionMap=@{}
    foreach ($definition in $Definitions) { $definitionMap[[string]$definition.id]=$definition }
    $winws=Join-Path $script:NrRoot 'bin\winws.exe'
    if (-not (Test-Path -LiteralPath $winws -PathType Leaf)) { throw "winws.exe is missing: $winws" }

    $services=New-Object 'System.Collections.Generic.List[object]'
    foreach ($entry in $entries) {
        $serviceId=ConvertTo-NrWorkerId ([string]$entry.serviceId)
        if (-not $definitionMap.ContainsKey($serviceId)) { throw "Unknown Service Matrix id in per-service mapping: $serviceId" }
        $filterFiles=Assert-NrServiceFilterFiles -ServiceId $serviceId
        $candidates=Get-NrWorkerStrategyCandidates -SelectedName ([string]$entry.strategy) -Strategies $Strategies -Maximum $MaximumStrategiesPerService
        $strategyPlans=New-Object 'System.Collections.Generic.List[object]'
        foreach ($candidate in $candidates) {
            $rawCommand=Get-NrStrategyCommand -Path $candidate.FullName
            if ([string]::IsNullOrWhiteSpace($rawCommand)) { throw "winws command is missing in strategy: $($candidate.Name)" }
            $scoped=ConvertTo-NrServiceScopedCommand -Command $rawCommand -ServiceId $serviceId
            $arguments=ConvertFrom-NrCommandLineArguments -CommandLine $scoped
            if ($arguments.Count -eq 0) { throw "Scoped strategy produced no arguments: $($candidate.Name)" }
            $hostToken='--hostlist='+$filterFiles.hostList
            $ipsetToken='--ipset='+$filterFiles.ipset
            if ($arguments -notcontains $hostToken -or $arguments -notcontains $ipsetToken) {
                throw "Scoped strategy '$($candidate.Name)' does not contain isolated filter files for '$serviceId'."
            }
            foreach ($argument in $arguments) {
                if ($argument -match '--hostlist=.*list-general' -or $argument -match '--ipset=.*ipset-all') {
                    throw "Scoped strategy '$($candidate.Name)' still references a global include list."
                }
            }
            $strategyPlans.Add([ordered]@{
                name=$candidate.Name
                executable=[IO.Path]::GetFullPath($winws)
                arguments=[string[]]$arguments
                sourceFile=$candidate.Name
            })
        }
        $services.Add([ordered]@{
            id=$serviceId
            enabled=$true
            filterTokens=@('hostlist:'+$filterFiles.hostList.ToLowerInvariant(),'ipset:'+$filterFiles.ipset.ToLowerInvariant())
            filterFiles=[ordered]@{ hostlist=$filterFiles.hostList; ipset=$filterFiles.ipset; hostEntries=$filterFiles.hostEntries; ipEntries=$filterFiles.ipEntries }
            probe=[ordered]@{ uri=Get-NrServiceProbeUri -Definition $definitionMap[$serviceId]; timeoutSeconds=8 }
            strategies=$strategyPlans.ToArray()
        })
    }
    $configuration=[ordered]@{
        schemaVersion=1
        generatedUtc=[DateTime]::UtcNow.ToString('o')
        generator='NexRoute 0.6.0'
        services=$services.ToArray()
    }
    $plans=New-Object 'System.Collections.Generic.List[object]'
    foreach ($service in $configuration.services) {
        $first=$service.strategies[0]
        $plans.Add([pscustomobject]@{ serviceId=$service.id; filterTokens=[string[]]$service.filterTokens; strategy=$first.name; executable=$first.executable; arguments=[string[]]$first.arguments })
    }
    Assert-NrWorkerFilterIsolation -Plans $plans.ToArray() | Out-Null
    return [pscustomobject]$configuration
}

function Save-NrServiceWorkerConfiguration {
    param([Parameter(Mandatory)]$Configuration)
    $path=Join-Path $script:NrService 'service-workers.json'
    [IO.File]::WriteAllText($path,($Configuration | ConvertTo-Json -Depth 30)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
    return $path
}

function Get-NrWorkerSupervisorPidPath {
    return Join-Path (Get-NrWorkerRuntimeDirectory -Root $script:NrRoot) 'supervisor.pid'
}

function Stop-NrPerServiceWorkerRuntime {
    $pidPath=Get-NrWorkerSupervisorPidPath
    if (Test-Path -LiteralPath $pidPath -PathType Leaf) {
        try {
            $supervisorPid=[int](Get-Content -LiteralPath $pidPath -Raw).Trim()
            if ($supervisorPid -gt 0) { Stop-Process -Id $supervisorPid -Force -ErrorAction SilentlyContinue }
        } catch { }
        Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
    }
    Stop-NrWorkerSet -Root $script:NrRoot
}

function Register-NrWorkerRuntimeTask {
    param([Parameter(Mandatory)][string]$ConfigurationPath)
    if ($env:OS -ne 'Windows_NT') { return $null }
    $hostPath=Join-Path $script:NrService 'nexroute-worker-host.ps1'
    $powerShell=(Get-Command powershell.exe -ErrorAction Stop).Source
    $arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$hostPath+'" -Mode Supervise -Root "'+$script:NrRoot+'" -ConfigPath "'+$ConfigurationPath+'" -IntervalSeconds 20 -FailureThreshold 3'
    $action=New-ScheduledTaskAction -Execute $powerShell -Argument $arguments -WorkingDirectory $script:NrRoot
    $trigger=New-ScheduledTaskTrigger -AtLogOn
    $settings=New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
    Register-ScheduledTask -TaskName 'NexRoute Worker Runtime' -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest -Force | Out-Null
    return 'NexRoute Worker Runtime'
}

function Start-NrPerServiceWorkerRuntime {
    param([Parameter(Mandatory)][string]$ConfigurationPath)
    $hostPath=Join-Path $script:NrService 'nexroute-worker-host.ps1'
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $hostPath -Mode Start -Root $script:NrRoot -ConfigPath $ConfigurationPath | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Worker host Start returned exit code $LASTEXITCODE." }
    $arguments=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$hostPath,'-Mode','Supervise','-Root',$script:NrRoot,'-ConfigPath',$ConfigurationPath,'-IntervalSeconds','20','-FailureThreshold','3')
    $process=Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WorkingDirectory $script:NrRoot -WindowStyle Hidden -PassThru
    [IO.File]::WriteAllText((Get-NrWorkerSupervisorPidPath),[string]$process.Id,[Text.Encoding]::ASCII)
    Register-NrWorkerRuntimeTask -ConfigurationPath $ConfigurationPath | Out-Null
    return $process.Id
}

function Apply-NrPerServiceStrategies {
    $mapping=$script:NrState.perServiceStrategies
    if ($null -eq $mapping -or (Get-NrPerServiceMappingEntries -Mapping $mapping).Count -eq 0) {
        throw 'Select at least one service strategy before applying the worker runtime.'
    }
    $configuration=New-NrServiceWorkerConfiguration -Mapping $mapping
    $configurationPath=Save-NrServiceWorkerConfiguration -Configuration $configuration
    Stop-NrStrategyRuntime
    Stop-NrPerServiceWorkerRuntime
    foreach ($existing in @(Get-Service -Name 'NexRoute_*' -ErrorAction SilentlyContinue)) {
        try { Stop-Service -Name $existing.Name -Force -ErrorAction SilentlyContinue } catch { }
        try { & sc.exe delete $existing.Name | Out-Null } catch { }
    }
    $supervisorPid=Start-NrPerServiceWorkerRuntime -ConfigurationPath $configurationPath
    foreach ($service in $configuration.services) {
        Save-NrStrategyHistory -Action 'per-service-worker-start' -Strategy ([string]$service.strategies[0].name) -Details @{ service=[string]$service.id; supervisorPid=$supervisorPid; fallbackCount=@($service.strategies).Count-1 }
    }
    Send-NrNotification -Title 'NexRoute' -Message ('Started '+@($configuration.services).Count+' isolated service workers.') -Level Info
    return [pscustomobject]@{ configurationPath=$configurationPath; serviceCount=@($configuration.services).Count; supervisorPid=$supervisorPid }
}
