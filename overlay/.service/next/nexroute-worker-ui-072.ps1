Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Read-NrWorkerUiConfiguration072 {
    $path=Join-Path $script:NrService 'service-workers.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try { return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop }
    catch { throw 'Service worker configuration is invalid; review it locally before restarting workers.' }
}

function Invoke-NrWorkerUiAction072 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('StartService','StopService','RestartService')][string]$Action,
        [Parameter(Mandatory)][string]$ServiceId)
    $hostPath=Join-Path $script:NrService 'nexroute-worker-host.ps1'
    $configPath=Join-Path $script:NrService 'service-workers.json'
    if (-not (Test-Path -LiteralPath $hostPath -PathType Leaf)) { throw 'Worker host module is missing.' }
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { throw 'Service worker configuration is missing.' }
    $raw=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $hostPath -Mode $Action -ServiceId $ServiceId -Root $script:NrRoot -ConfigPath $configPath -Json 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Worker host rejected $Action for '$ServiceId'. Review local worker logs." }
    $payload=(@($raw | ForEach-Object { [string]$_ }) -join [Environment]::NewLine).Trim()
    if (-not $payload.StartsWith('{')) { throw 'Worker host returned no operation receipt.' }
    return ($payload | ConvertFrom-Json)
}

function Show-NrWorkerManager072 {
    while ($true) {
        $configuration=$null
        try { $configuration=Read-NrWorkerUiConfiguration072 }
        catch {
            Write-NrHeader -Title (T 'workerManager')
            Write-NrLabCheck065 -State WARN -Label 'CONFIG' -Details 'Invalid service-workers.json; nothing will be started.'
            Wait-NrKey
            return
        }
        $report=Get-NrWorkerRuntimeReport072 -Root $script:NrRoot -Configuration $configuration
        Write-NrHeader -Title (T 'workerManager')
        Write-NrPanel -Title ('WORKERS // {0} running / {1} unhealthy' -f $report.running,$report.unhealthy)
        foreach ($worker in @($report.workers | Sort-Object serviceId)) {
            $color=if($worker.processState -eq 'verified' -and $worker.consecutiveFailures -eq 0){[ConsoleColor]::Green}
                elseif($worker.status -eq 'stopped'){[ConsoleColor]::DarkGray}
                else{[ConsoleColor]::Yellow}
            Write-Host ('  {0,-16} {1,-13} PID {2,7}  GEN {3,2}  {4}' -f $worker.serviceId,$worker.processState,$worker.pid,$worker.generation,$worker.strategy) -ForegroundColor $color
            if ($worker.consecutiveFailures -gt 0 -or $worker.cooldownActive -or $worker.lastErrorCode) {
                Write-Host ('      failures={0} cooldown={1} code={2}' -f $worker.consecutiveFailures,$worker.cooldownActive,$worker.lastErrorCode) -ForegroundColor DarkGray
            }
        }
        if (@($report.workers).Count -eq 0) {
            Write-NrLabCheck065 -State INFO -Label 'WORKERS' -Details 'No service worker state found. Apply a service strategy first.'
        }
        if ($report.scopes) {
            Write-Host ('  Filter overlaps: {0}; coverage: {1}' -f $report.scopes.overlapPairs,$report.scopes.coverage) -ForegroundColor $(if($report.scopes.overlapPairs -gt 0 -or $report.scopes.coverage -eq 'partial'){'Yellow'}else{'Gray'})
            foreach($warning in @($report.scopes.warnings | Select-Object -First 12)) {
                Write-Host ('      {0} + {1}: domains={2}, CIDRs={3}' -f $warning.serviceA,$warning.serviceB,$warning.overlappingDomains,$warning.overlappingCidrs) -ForegroundColor Yellow
            }
        }
        $items=@(
            New-NrMenuItem -Id 'restart' -Label (T 'workerRestart') -Section (T 'workerManager')
            New-NrMenuItem -Id 'stop' -Label (T 'workerStop') -Section (T 'workerManager')
            New-NrMenuItem -Id 'start' -Label (T 'workerStart') -Section (T 'workerManager')
            New-NrMenuItem -Id 'back' -Label (T 'back') -Section ''
        )
        $mode=Invoke-NrMenu -Title (T 'workerManager') -Items $items -AllowEscape
        if (-not $mode -or $mode -eq 'back') { return }
        if (-not $configuration) { Show-NrMessage -Title (T 'operationFailed') -Message 'No worker configuration exists.' -Color Yellow; continue }
        $services=@($configuration.services | Where-Object { $null -eq $_.enabled -or [bool]$_.enabled } | Sort-Object id)
        if ($services.Count -eq 0) { Show-NrMessage -Title (T 'operationFailed') -Message 'No enabled service worker profiles.' -Color Yellow; continue }
        $selected=Invoke-NrMenu -Title (T 'workerManager') -Items @($services | ForEach-Object { New-NrMenuItem -Id ([string]$_.id) -Label ([string]$_.id) -Section (T 'workerManager') }) -AllowEscape
        if (-not $selected) { continue }
        $action=switch($mode){'restart'{'RestartService'}'stop'{'StopService'}'start'{'StartService'}}
        try {
            $receipt=Invoke-NrWorkerUiAction072 -Action $action -ServiceId $selected
            Show-NrMessage -Title (T 'workerManager') -Message ('Service '+$receipt.serviceId+': '+$receipt.action) -Color Green
        } catch {
            Show-NrMessage -Title (T 'operationFailed') -Message $_.Exception.Message -Color Red
        }
    }
}
