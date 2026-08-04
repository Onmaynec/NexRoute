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

function Read-NrRedirectedText {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    $raw=[string](Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue)
    return $raw.Trim()
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
        if ($null -eq $process) {
            $watch.Stop()
            return [pscustomobject]@{ passed=$false; exitCode=-4; elapsedMs=[Math]::Round($watch.Elapsed.TotalMilliseconds,2); message='Control-node process was not created.' }
        }
        if (-not $process.WaitForExit([Math]::Max(5,$TimeoutSeconds)*1000)) {
            try { $process.Kill() } catch { }
            $watch.Stop()
            return [pscustomobject]@{ passed=$false; exitCode=-2; elapsedMs=[Math]::Round($watch.Elapsed.TotalMilliseconds,2); message='Updated control node timed out.' }
        }
        $process.Refresh()
        $watch.Stop()
        $errorText=Read-NrRedirectedText -Path $stderr
        $outputText=Read-NrRedirectedText -Path $stdout
        $message=if ($errorText) { $errorText } else { $outputText }
        return [pscustomobject]@{ passed=($process.ExitCode -eq 0); exitCode=$process.ExitCode; elapsedMs=[Math]::Round($watch.Elapsed.TotalMilliseconds,2); message=$message }
    } catch {
        $watch.Stop()
        $details=$_.Exception.Message
        if ($_.ScriptStackTrace) { $details += [Environment]::NewLine + $_.ScriptStackTrace }
        return [pscustomobject]@{ passed=$false; exitCode=-3; elapsedMs=[Math]::Round($watch.Elapsed.TotalMilliseconds,2); message=$details }
    } finally {
        Remove-Item -LiteralPath $stdout,$stderr -Force -ErrorAction SilentlyContinue
    }
}

function Complete-NrUpdateTransaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$FromVersion,
        [Parameter(Mandatory)][string]$ToVersion,
        [Parameter(Mandatory)][object[]]$HealthResults,
        [int]$MinimumServiceCount=1,
        [scriptblock]$ControlNodeProbe,
        [Parameter(Mandatory)][scriptblock]$Rollback,
        [scriptblock]$Launch
    )
    $policy=Test-NrPostUpdateHealthPolicy -Results $HealthResults -MinimumServiceCount $MinimumServiceCount
    if ($ControlNodeProbe) { $smoke=& $ControlNodeProbe $Root }
    else { $smoke=Test-NrUpdatedControlNode -Root $Root }
    if ($null -eq $smoke) { $smoke=[pscustomobject]@{ passed=$false; exitCode=-4; elapsedMs=0; message='Control-node probe returned no result.' } }

    $verificationMessage='Post-update verification is running.'
    Write-NrUpdateHandoffRecord -Root $Root -FromVersion $FromVersion -ToVersion $ToVersion -Status verifying -HealthPolicy $policy -ControlNodeSmoke $smoke -Message $verificationMessage | Out-Null

    if (-not [bool]$policy.passed -or -not [bool]$smoke.passed) {
        $reason=if (-not [bool]$policy.passed) {
            'Post-update network health policy failed.'
        } else {
            'Updated control node failed its smoke test.'
        }
        $rollbackResult=$null
        try {
            $rollbackResult=& $Rollback $Root $FromVersion $ToVersion
        } catch {
            $failureMessage=$reason+' Automatic rollback also failed: '+$_.Exception.Message
            Write-NrUpdateHandoffRecord -Root $Root -FromVersion $FromVersion -ToVersion $ToVersion -Status rolled-back -HealthPolicy $policy -ControlNodeSmoke $smoke -Message $failureMessage | Out-Null
            throw $failureMessage
        }
        $message=$reason+' The previous NexRoute version was restored.'
        Write-NrUpdateHandoffRecord -Root $Root -FromVersion $FromVersion -ToVersion $ToVersion -Status rolled-back -HealthPolicy $policy -ControlNodeSmoke $smoke -Message $message | Out-Null
        if ($Launch) { & $Launch $Root $FromVersion 'rolled-back' | Out-Null }
        return [pscustomobject]@{
            status='rolled-back'
            committed=$false
            fromVersion=$FromVersion
            toVersion=$ToVersion
            healthPolicy=$policy
            controlNodeSmoke=$smoke
            rollbackResult=$rollbackResult
            message=$message
        }
    }

    $message='Update verification passed and the new version was committed.'
    Write-NrUpdateHandoffRecord -Root $Root -FromVersion $FromVersion -ToVersion $ToVersion -Status committed -HealthPolicy $policy -ControlNodeSmoke $smoke -Message $message | Out-Null
    if ($Launch) { & $Launch $Root $ToVersion 'committed' | Out-Null }
    return [pscustomobject]@{
        status='committed'
        committed=$true
        fromVersion=$FromVersion
        toVersion=$ToVersion
        healthPolicy=$policy
        controlNodeSmoke=$smoke
        rollbackResult=$null
        message=$message
    }
}
