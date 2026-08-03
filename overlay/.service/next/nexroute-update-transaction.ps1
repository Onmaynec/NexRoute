Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Test-NrPostUpdateHealthPolicy {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Results,[int]$MinimumServiceCount=1)
    $internet=@($Results | Where-Object { [string]$_.name -eq 'Internet' } | Select-Object -First 1)
    $services=@($Results | Where-Object { [string]$_.name -in @('YouTube','Discord','Telegram') })
    $healthyServices=@($services | Where-Object { [bool]$_.ok }).Count
    $internetHealthy=($internet.Count -eq 1 -and [bool]$internet[0].ok)
    $passed=($internetHealthy -and $healthyServices -ge [Math]::Max(1,$MinimumServiceCount))
    return [pscustomobject]@{
        passed=$passed
        internetHealthy=$internetHealthy
        healthyServiceCount=$healthyServices
        totalServiceCount=$services.Count
        minimumServiceCount=[Math]::Max(1,$MinimumServiceCount)
    }
}

function Write-NrUpdateHandoffRecord {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$FromVersion,
        [Parameter(Mandatory)][string]$ToVersion,
        [Parameter(Mandatory)][ValidateSet('verifying','committed','rolled-back')][string]$Status,
        [object]$HealthPolicy,
        [object]$ControlNodeSmoke,
        [string]$Message
    )
    $directory=Join-Path $Root '.service'
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $path=Join-Path $directory 'update-handoff.json'
    $record=[ordered]@{
        schemaVersion=1
        timestampUtc=[DateTime]::UtcNow.ToString('o')
        fromVersion=$FromVersion
        toVersion=$ToVersion
        status=$Status
        sourceProcessId=$PID
        healthPolicy=$HealthPolicy
        controlNodeSmoke=$ControlNodeSmoke
        message=$Message
    }
    [IO.File]::WriteAllText($path,($record | ConvertTo-Json -Depth 12)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
    return $path
}

function Test-NrUpdatedControlNode {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root,[int]$TimeoutSeconds=25)
    $serviceBatch=Join-Path $Root 'service.bat'
    if (-not (Test-Path -LiteralPath $serviceBatch -PathType Leaf)) {
        return [pscustomobject]@{ passed=$false; exitCode=-1; elapsedMs=0; message='service.bat is missing after update.' }
    }
    if ($env:OS -ne 'Windows_NT') {
        return [pscustomobject]@{ passed=$true; exitCode=0; elapsedMs=0; message='Windows control-node smoke is deferred to the Windows package runner.' }
    }
    $stdout=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-handoff-'+[guid]::NewGuid().ToString('N')+'.out.log')
    $stderr=$stdout+'.err'
    $watch=[Diagnostics.Stopwatch]::StartNew()
    try {
        $process=Start-Process -FilePath $env:ComSpec -ArgumentList @('/d','/c','"'+$serviceBatch+'" --status') -WorkingDirectory $Root -PassThru -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        if (-not $process.WaitForExit([Math]::Max(5,$TimeoutSeconds)*1000)) {
            try { $process.Kill() } catch { }
            $watch.Stop()
            return [pscustomobject]@{ passed=$false; exitCode=-2; elapsedMs=[Math]::Round($watch.Elapsed.TotalMilliseconds,2); message='Updated control node timed out.' }
        }
        $watch.Stop()
        $message=''
        if (Test-Path -LiteralPath $stderr) { $message=(Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue).Trim() }
        if (-not $message -and (Test-Path -LiteralPath $stdout)) { $message=(Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue).Trim() }
        return [pscustomobject]@{ passed=($process.ExitCode -eq 0); exitCode=$process.ExitCode; elapsedMs=[Math]::Round($watch.Elapsed.TotalMilliseconds,2); message=$message }
    } catch {
        $watch.Stop()
        return [pscustomobject]@{ passed=$false; exitCode=-3; elapsedMs=[Math]::Round($watch.Elapsed.TotalMilliseconds,2); message=$_.Exception.Message }
    } finally {
        Remove-Item -LiteralPath $stdout,$stderr -Force -ErrorAction SilentlyContinue
    }
}
