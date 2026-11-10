Describe 'NexRoute 0.7.2 worker ownership, cooldown and scope diagnostics' {
    BeforeAll {
        $script:root=Split-Path -Parent $PSScriptRoot
        . (Join-Path $script:root 'overlay/.service/next/nexroute-workers.ps1')
        . (Join-Path $script:root 'overlay/.service/next/nexroute-worker-scopes-072.ps1')
        $script:pwsh=(Get-Process -Id $PID).Path
    }
    BeforeEach {
        $script:fixture=Join-Path ([IO.Path]::GetTempPath()) ('NexRoute 072 worker fixture '+[guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $script:fixture '.service'),(Join-Path $script:fixture 'lists') -Force | Out-Null
        $script:workerScript=Join-Path $script:fixture 'test worker.ps1'
        @'
while ($true) { Start-Sleep -Milliseconds 200 }
'@ | Set-Content -LiteralPath $script:workerScript -Encoding UTF8
        $script:started=New-Object 'System.Collections.Generic.List[int]'
    }
    AfterEach {
        foreach($id in @($script:started)) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue }
        Remove-Item -LiteralPath $script:fixture -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'records process identity and stops only the process it started' {
        $w=Start-NrServiceWorker -Root $script:fixture -ServiceId youtube -Strategy first -Executable $script:pwsh -Arguments @('-NoProfile','-File',$script:workerScript) -FilterTokens @('hostlist:youtube')
        $script:started.Add([int]$w.pid)
        $w.processStartedUtc | Should -Match '^[0-9]{4}-'
        (Get-NrWorkerProcessIdentity -State (Read-NrWorkerState -Root $script:fixture -ServiceId youtube)).status | Should -Be 'verified'
        (Stop-NrServiceWorker -Root $script:fixture -ServiceId youtube) | Should -BeTrue
        (Read-NrWorkerState -Root $script:fixture -ServiceId youtube).status | Should -Be 'stopped'
    }

    It 'refuses a reused or stale PID rather than killing another process' {
        $w=Start-NrServiceWorker -Root $script:fixture -ServiceId discord -Strategy initial -Executable $script:pwsh -Arguments @('-NoProfile','-File',$script:workerScript) -FilterTokens @('hostlist:discord')
        $script:started.Add([int]$w.pid)
        $state=Read-NrWorkerState -Root $script:fixture -ServiceId discord
        $state.processStartedUtc='2000-01-01T00:00:00.0000000Z'
        $modified=@{}
        foreach($p in $state.PSObject.Properties){$modified[$p.Name]=$p.Value}
        Write-NrWorkerState -Root $script:fixture -State $modified | Out-Null
        (Get-NrWorkerProcessIdentity -State $state).status | Should -Be 'mismatch'
        (Stop-NrServiceWorker -Root $script:fixture -ServiceId discord) | Should -BeFalse
        (Read-NrWorkerState -Root $script:fixture -ServiceId discord).status | Should -Be 'identity-unverified'
        (Get-Process -Id $w.pid -ErrorAction Stop).HasExited | Should -BeFalse
    }

    It 'prevents duplicate normalized IDs and filter collisions' {
        $plans=@([pscustomobject]@{serviceId='service@';filterTokens=@('hostlist:a')},
            [pscustomobject]@{serviceId='service!';filterTokens=@('hostlist:b')})
        { Assert-NrWorkerFilterIsolation -Plans $plans } | Should -Throw '*Duplicate normalized*'
        $plans[1].serviceId='other'
        $plans[1].filterTokens=@('hostlist:a')
        { Assert-NrWorkerFilterIsolation -Plans $plans } | Should -Throw '*collision*'
    }

    It 'backs off repeat failovers and avoids restarting on every check' {
        $w=Start-NrServiceWorker -Root $script:fixture -ServiceId discord -Strategy primary -Executable $script:pwsh -Arguments @('-NoProfile','-File',$script:workerScript) -FilterTokens @('hostlist:discord')
        $script:started.Add([int]$w.pid)
        $probe={param($state) $false}
        $fallback={
            param($state)
            [pscustomobject]@{strategy='secondary';executable=$script:pwsh;arguments=@('-NoProfile','-File',$script:workerScript);filterTokens=@('hostlist:discord')}
        }
        $events=@(Invoke-NrWorkerSupervisorCycle -Root $script:fixture -Probe $probe -ResolveReplacement $fallback -FailureThreshold 1 -CooldownSeconds 120)
        @($events | Where-Object action -eq 'failover').Count | Should -Be 1
        $new=Read-NrWorkerState -Root $script:fixture -ServiceId discord
        $script:started.Add([int]$new.pid)
        $new.generation | Should -Be 2
        (Get-NrWorkerCooldown072 -State $new) | Should -BeTrue
        $events2=@(Invoke-NrWorkerSupervisorCycle -Root $script:fixture -Probe $probe -ResolveReplacement $fallback -FailureThreshold 1 -CooldownSeconds 120)
        @($events2 | Where-Object action -eq 'cooldown').Count | Should -Be 1
        (Read-NrWorkerState -Root $script:fixture -ServiceId discord).pid | Should -Be $new.pid
    }

    It 'marks the service failed if there is no fallback rather than looping' {
        $w=Start-NrServiceWorker -Root $script:fixture -ServiceId telegram -Strategy only -Executable $script:pwsh -Arguments @('-NoProfile','-File',$script:workerScript) -FilterTokens @('hostlist:telegram')
        $script:started.Add([int]$w.pid)
        $events=@(Invoke-NrWorkerSupervisorCycle -Root $script:fixture -Probe {param($state) $false} -ResolveReplacement {param($state) $null} -FailureThreshold 1)
        @($events | Where-Object action -eq 'stopped-no-replacement').Count | Should -Be 1
        $state=Read-NrWorkerState -Root $script:fixture -ServiceId telegram
        $state.status | Should -Be 'failed'
        $state.lastErrorCode | Should -Be 'NR-WORKER-NO-FALLBACK'
        @(Invoke-NrWorkerSupervisorCycle -Root $script:fixture -Probe {param($state) $false} -ResolveReplacement {param($state) $null} -FailureThreshold 1).Count | Should -Be 0
    }

    It 'finds shared host and IPv4/IPv6 subnet overlaps without exporting identifiers' {
        $aHost=Join-Path $script:fixture 'lists/a-host.txt';$bHost=Join-Path $script:fixture 'lists/b-host.txt'
        $aIp=Join-Path $script:fixture 'lists/a-ip.txt';$bIp=Join-Path $script:fixture 'lists/b-ip.txt'
        'youtube.com','private.example' | Set-Content -LiteralPath $aHost -Encoding UTF8
        'm.youtube.com','safe.example' | Set-Content -LiteralPath $bHost -Encoding UTF8
        '192.0.2.0/24','2001:db8::/32' | Set-Content -LiteralPath $aIp -Encoding UTF8
        '192.0.2.128/25','2001:db8:5::/48' | Set-Content -LiteralPath $bIp -Encoding UTF8
        $config=[pscustomobject]@{services=@(
            [pscustomobject]@{id='youtube';enabled=$true;filterFiles=[pscustomobject]@{hostlist=$aHost;ipset=$aIp}}
            [pscustomobject]@{id='discord';enabled=$true;filterFiles=[pscustomobject]@{hostlist=$bHost;ipset=$bIp}}
        )}
        $report=Get-NrWorkerScopeReport072 -Configuration $config
        $report.coverage | Should -Be 'complete'
        $report.overlapPairs | Should -Be 1
        $report.warnings[0].overlappingDomains | Should -Be 1
        $report.warnings[0].overlappingCidrs | Should -Be 2
        (ConvertTo-Json -InputObject $report -Depth 6) | Should -Not -Match 'youtube.com|192.0.2|2001:db8|private.example'
    }

    It 'shows partial coverage rather than claiming complete isolation' {
        $host=Join-Path $script:fixture 'lists/host.txt'
        $ip=Join-Path $script:fixture 'lists/ip.txt'
        'one.example','two.example','three.example' | Set-Content -LiteralPath $host -Encoding UTF8
        '192.0.2.1/32' | Set-Content -LiteralPath $ip -Encoding UTF8
        $config=[pscustomobject]@{services=@([pscustomobject]@{id='youtube';enabled=$true;filterFiles=[pscustomobject]@{hostlist=$host;ipset=$ip}})}
        $report=Get-NrWorkerScopeReport072 -Configuration $config -MaxEntriesPerService 2
        $report.coverage | Should -Be 'partial'
        $report.incompleteServices | Should -Contain 'youtube'
    }

    It 'quotes 5.1-compatible process arguments safely' {
        (ConvertTo-NrWorkerArgument072 -Value 'simple') | Should -Be 'simple'
        (ConvertTo-NrWorkerArgument072 -Value 'C:\Nex Route\') | Should -Be '"C:\Nex Route\\"'
        (ConvertTo-NrWorkerArgument072 -Value '') | Should -Be '""'
        { ConvertTo-NrWorkerArgument072 -Value ("bad"+[char]10+"argument") } | Should -Throw '*control characters*'
    }

    It 'returns an empty runtime report without any worker state' {
        $r=Get-NrWorkerRuntimeReport072 -Root $script:fixture
        $r.total | Should -Be 0
        $r.unhealthy | Should -Be 0
    }
}
