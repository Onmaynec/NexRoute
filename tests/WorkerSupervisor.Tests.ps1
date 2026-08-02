Describe 'NexRoute 0.6.0 independent service workers' {
    BeforeAll {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        . (Join-Path $repoRoot 'overlay/.service/next/nexroute-workers.ps1')
        $pwshPath = (Get-Process -Id $PID).Path
        if (-not $pwshPath) { throw 'Unable to resolve the current PowerShell executable.' }
    }

    BeforeEach {
        $testRoot = Join-Path ([IO.Path]::GetTempPath()) ('nexroute-worker-test-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $testRoot '.service') -Force | Out-Null
        $workerScript = Join-Path $testRoot 'fake-worker.ps1'
        @'
param([string]$Service,[string]$Strategy,[int]$LifetimeSeconds=60)
Write-Output ("READY service={0} strategy={1} pid={2}" -f $Service,$Strategy,$PID)
$deadline=[DateTime]::UtcNow.AddSeconds($LifetimeSeconds)
while ([DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
'@ | Set-Content -LiteralPath $workerScript -Encoding UTF8
    }

    AfterEach {
        try { Stop-NrWorkerSet -Root $testRoot } catch { }
        Start-Sleep -Milliseconds 100
        Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'runs isolated YouTube Discord and Telegram workers with distinct PIDs logs and arguments' {
        $plans = @(
            [pscustomobject]@{ serviceId='youtube'; strategy='general-alt'; executable=$pwshPath; arguments=@('-NoProfile','-File',$workerScript,'-Service','youtube','-Strategy','general-alt'); filterTokens=@('hostlist:youtube') }
            [pscustomobject]@{ serviceId='discord'; strategy='discord-udp'; executable=$pwshPath; arguments=@('-NoProfile','-File',$workerScript,'-Service','discord','-Strategy','discord-udp'); filterTokens=@('hostlist:discord') }
            [pscustomobject]@{ serviceId='telegram'; strategy='telegram-tcp'; executable=$pwshPath; arguments=@('-NoProfile','-File',$workerScript,'-Service','telegram','-Strategy','telegram-tcp'); filterTokens=@('hostlist:telegram') }
        )

        $workers = @(Start-NrWorkerSet -Root $testRoot -Plans $plans)
        $workers.Count | Should -Be 3
        @($workers.pid | Sort-Object -Unique).Count | Should -Be 3

        foreach ($worker in $workers) {
            (Get-Process -Id ([int]$worker.pid) -ErrorAction Stop).HasExited | Should -BeFalse
            $state = Read-NrWorkerState -Root $testRoot -ServiceId $worker.serviceId
            $state.strategy | Should -Be $worker.strategy
            $state.arguments -join ' ' | Should -Match ([regex]::Escape('-Service ' + $worker.serviceId))
            $state.stdout | Should -Match ([regex]::Escape('.service' + [IO.Path]::DirectorySeparatorChar + 'workers'))
        }

        { Assert-NrWorkerFilterIsolation -Plans @($plans[0],[pscustomobject]@{ serviceId='duplicate'; filterTokens=@('hostlist:youtube') }) } | Should -Throw '*collision*'
    }

    It 'fails over only the killed service and preserves healthy worker PIDs' {
        $plans = @(
            [pscustomobject]@{ serviceId='youtube'; strategy='youtube-a'; executable=$pwshPath; arguments=@('-NoProfile','-File',$workerScript,'-Service','youtube','-Strategy','youtube-a'); filterTokens=@('hostlist:youtube') }
            [pscustomobject]@{ serviceId='discord'; strategy='discord-a'; executable=$pwshPath; arguments=@('-NoProfile','-File',$workerScript,'-Service','discord','-Strategy','discord-a'); filterTokens=@('hostlist:discord') }
            [pscustomobject]@{ serviceId='telegram'; strategy='telegram-a'; executable=$pwshPath; arguments=@('-NoProfile','-File',$workerScript,'-Service','telegram','-Strategy','telegram-a'); filterTokens=@('hostlist:telegram') }
        )
        $workers = @(Start-NrWorkerSet -Root $testRoot -Plans $plans)
        $before = @{}
        foreach ($worker in $workers) { $before[$worker.serviceId] = [int]$worker.pid }

        Stop-Process -Id $before.discord -Force
        for ($i=0; $i -lt 30; $i++) {
            if (-not (Get-Process -Id $before.discord -ErrorAction SilentlyContinue)) { break }
            Start-Sleep -Milliseconds 100
        }

        $probe = { param($state) return (Test-NrWorkerProcess -State $state) }
        $replacement = {
            param($state)
            if ([string]$state.serviceId -ne 'discord') { return $null }
            return [pscustomobject]@{
                strategy='discord-b'
                executable=$pwshPath
                arguments=@('-NoProfile','-File',$workerScript,'-Service','discord','-Strategy','discord-b')
                filterTokens=@('hostlist:discord')
            }
        }
        $events = @(Invoke-NrWorkerSupervisorCycle -Root $testRoot -Probe $probe -ResolveReplacement $replacement -FailureThreshold 1)
        $failover = @($events | Where-Object { $_.action -eq 'failover' })
        $failover.Count | Should -Be 1
        $failover[0].serviceId | Should -Be 'discord'
        $failover[0].oldPid | Should -Be $before.discord
        $failover[0].newPid | Should -Not -Be $before.discord
        $failover[0].newStrategy | Should -Be 'discord-b'
        $failover[0].generation | Should -Be 2

        (Read-NrWorkerState -Root $testRoot -ServiceId 'youtube').pid | Should -Be $before.youtube
        (Read-NrWorkerState -Root $testRoot -ServiceId 'telegram').pid | Should -Be $before.telegram
        (Read-NrWorkerState -Root $testRoot -ServiceId 'discord').strategy | Should -Be 'discord-b'
        Test-NrWorkerProcess -State (Read-NrWorkerState -Root $testRoot -ServiceId 'discord') | Should -BeTrue
    }
}
