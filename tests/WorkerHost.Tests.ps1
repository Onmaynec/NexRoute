Describe 'NexRoute 0.6.0 product worker host' {
    BeforeAll {
        $repoRoot=Split-Path -Parent $PSScriptRoot
        $hostScript=Join-Path $repoRoot 'overlay/.service/nexroute-worker-host.ps1'
        $workersModule=Join-Path $repoRoot 'overlay/.service/next/nexroute-workers.ps1'
        . $workersModule
        $pwshPath=(Get-Process -Id $PID).Path
    }

    BeforeEach {
        $root=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-host-test-'+[guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $root '.service') -Force | Out-Null
        $workerScript=Join-Path $root 'worker.ps1'
        @'
param([string]$Name)
while ($true) { Start-Sleep -Milliseconds 100 }
'@ | Set-Content -LiteralPath $workerScript -Encoding UTF8
        $config=Join-Path $root 'workers.json'
        [ordered]@{
            schemaVersion=1
            services=@(
                [ordered]@{
                    id='discord'; enabled=$true; filterTokens=@('hostlist:discord')
                    probe=[ordered]@{ uri='tcp://127.0.0.1:9'; timeoutSeconds=1 }
                    strategies=@(
                        [ordered]@{ name='discord-primary'; executable=$pwshPath; arguments=@('-NoProfile','-File',$workerScript,'-Name','primary') }
                        [ordered]@{ name='discord-secondary'; executable=$pwshPath; arguments=@('-NoProfile','-File',$workerScript,'-Name','secondary') }
                    )
                }
            )
        } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $config -Encoding UTF8
    }

    AfterEach {
        try { Stop-NrWorkerSet -Root $root } catch { }
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'executes Start Status failover and Stop through the packaged host entrypoint' {
        & $hostScript -Mode Start -Root $root -ConfigPath $config | Out-Null
        $primary=Read-NrWorkerState -Root $root -ServiceId 'discord'
        $primary.strategy | Should -Be 'discord-primary'
        Test-NrWorkerProcess -State $primary | Should -BeTrue

        $statusJson=& $hostScript -Mode Status -Root $root -ConfigPath $config -Json
        $status=@($statusJson | ConvertFrom-Json)
        $status.Count | Should -Be 1
        $status[0].pid | Should -Be $primary.pid

        $eventsJson=& $hostScript -Mode Once -Root $root -ConfigPath $config -FailureThreshold 1 -Json
        $events=@($eventsJson | ConvertFrom-Json)
        @($events | Where-Object action -eq 'failover').Count | Should -Be 1
        $secondary=Read-NrWorkerState -Root $root -ServiceId 'discord'
        $secondary.strategy | Should -Be 'discord-secondary'
        $secondary.pid | Should -Not -Be $primary.pid
        $secondary.generation | Should -Be 2
        Test-NrWorkerProcess -State $secondary | Should -BeTrue

        & $hostScript -Mode Stop -Root $root -ConfigPath $config | Out-Null
        $stopped=Read-NrWorkerState -Root $root -ServiceId 'discord'
        $stopped.status | Should -Be 'stopped'
        Test-NrWorkerProcess -State $stopped | Should -BeFalse
    }
}
