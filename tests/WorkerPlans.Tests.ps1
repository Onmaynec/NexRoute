Describe 'NexRoute 0.6.0 real per-service winws plans' {
    BeforeAll {
        $repositoryRoot=Split-Path -Parent $PSScriptRoot
        . (Join-Path $repositoryRoot 'overlay/.service/next/nexroute-workers.ps1')
        . (Join-Path $repositoryRoot 'overlay/.service/next/nexroute-strategies.ps1')
        . (Join-Path $repositoryRoot 'overlay/.service/next/nexroute-worker-plans.ps1')

        $script:fixture=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-worker-plans-'+[guid]::NewGuid().ToString('N'))
        $script:NrRoot=$script:fixture
        $script:NrService=Join-Path $script:fixture '.service'
        $script:NrHistoryDir=Join-Path $script:NrService 'history'
        New-Item -ItemType Directory -Path (Join-Path $script:fixture 'bin'),(Join-Path $script:fixture 'lists'),(Join-Path $script:NrHistoryDir 'strategy-lab') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:fixture 'bin/winws.exe') -Value 'fixture' -Encoding ASCII
        foreach ($serviceId in @('youtube','discord')) {
            Set-Content -LiteralPath (Join-Path $script:fixture ('lists/list-service-'+$serviceId+'.txt')) -Value ($serviceId+'.example') -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $script:fixture ('lists/ipset-service-'+$serviceId+'.txt')) -Value $(if ($serviceId -eq 'youtube') { '2001:db8:1::/48' } else { '203.0.113.0/24' }) -Encoding UTF8
        }
        Set-Content -LiteralPath (Join-Path $script:fixture 'lists/list-general.txt') -Value 'global.example' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $script:fixture 'lists/ipset-all.txt') -Value '0.0.0.0/0' -Encoding UTF8

        $batchTemplate=@'
@echo off
set "BIN=%~dp0bin"
set "LISTS=%~dp0lists"
start "zapret" /min "%BIN%winws.exe" --wf-tcp=80,443 --wf-udp=443 ^
--filter-tcp=80,443 --hostlist="%LISTS%list-general.txt" --ipset="%LISTS%ipset-all.txt" --dpi-desync=fake,multisplit --new ^
--filter-udp=443 --hostlist="%LISTS%list-general.txt" --ipset="%LISTS%ipset-all.txt" --dpi-desync=fake --dpi-desync-repeats=6
'@
        foreach ($name in @('strategy-a.bat','strategy-b.bat','strategy-c.bat')) {
            Set-Content -LiteralPath (Join-Path $script:fixture $name) -Value $batchTemplate -Encoding UTF8
        }
        [ordered]@{
            schemaVersion=3
            results=@(
                [ordered]@{ strategy='strategy-c.bat'; score=97.5 }
                [ordered]@{ strategy='strategy-b.bat'; score=88.0 }
                [ordered]@{ strategy='strategy-a.bat'; score=70.0 }
            )
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $script:NrHistoryDir 'strategy-lab/20260803-000000.json') -Encoding UTF8

        $script:definitions=@(
            [pscustomobject]@{ id='youtube'; domains=@('youtube.com'); testTargets=@([pscustomobject]@{ url='https://www.youtube.com/generate_204' }) }
            [pscustomobject]@{ id='discord'; domains=@('discord.com'); testTargets=@([pscustomobject]@{ url='https://discord.com/api/v9/gateway' }) }
        )
    }

    AfterAll {
        Remove-Item -LiteralPath $script:fixture -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'tokenizes quoted winws arguments without splitting paths containing spaces' {
        $arguments=ConvertFrom-NrCommandLineArguments -CommandLine '--wf-tcp=80,443 --hostlist="C:\Nex Route\lists\youtube.txt" --dpi-desync=fake'
        $arguments | Should -HaveCount 3
        $arguments[1] | Should -Be '--hostlist=C:\Nex Route\lists\youtube.txt'
    }

    It 'creates distinct workers whose arguments contain only their own hostlist and ipset' {
        $mapping=[pscustomobject]@{ youtube='strategy-a.bat'; discord='strategy-b.bat' }
        $strategies=@(Get-ChildItem -LiteralPath $script:fixture -Filter 'strategy-*.bat' -File | Sort-Object Name)
        $configuration=New-NrServiceWorkerConfiguration -Mapping $mapping -Strategies $strategies -Definitions $script:definitions -MaximumStrategiesPerService 3

        $configuration.schemaVersion | Should -Be 1
        @($configuration.services) | Should -HaveCount 2
        $youtube=@($configuration.services | Where-Object id -eq 'youtube')[0]
        $discord=@($configuration.services | Where-Object id -eq 'discord')[0]
        @($youtube.strategies) | Should -HaveCount 3
        @($discord.strategies) | Should -HaveCount 3
        $youtube.strategies[0].name | Should -Be 'strategy-a.bat'
        $discord.strategies[0].name | Should -Be 'strategy-b.bat'
        $youtube.strategies[1].name | Should -Be 'strategy-c.bat'
        $discord.strategies[1].name | Should -Be 'strategy-c.bat'

        foreach ($strategy in @($youtube.strategies)) {
            $joined=@($strategy.arguments) -join ' '
            $joined | Should -Match 'list-service-youtube\.txt'
            $joined | Should -Match 'ipset-service-youtube\.txt'
            $joined | Should -Not -Match 'list-general\.txt'
            $joined | Should -Not -Match 'ipset-all\.txt'
            $strategy.executable | Should -Be (Join-Path $script:fixture 'bin/winws.exe')
        }
        foreach ($strategy in @($discord.strategies)) {
            $joined=@($strategy.arguments) -join ' '
            $joined | Should -Match 'list-service-discord\.txt'
            $joined | Should -Match 'ipset-service-discord\.txt'
            $joined | Should -Not -Match 'list-general\.txt'
            $joined | Should -Not -Match 'ipset-all\.txt'
        }
        $youtube.filterTokens[0] | Should -Not -Be $discord.filterTokens[0]
        $youtube.probe.uri | Should -Be 'https://www.youtube.com/generate_204'
        $discord.probe.uri | Should -Be 'https://discord.com/api/v9/gateway'
    }

    It 'writes a product-host compatible service-workers.json document' {
        $mapping=[pscustomobject]@{ youtube='strategy-a.bat'; discord='strategy-b.bat' }
        $strategies=@(Get-ChildItem -LiteralPath $script:fixture -Filter 'strategy-*.bat' -File | Sort-Object Name)
        $configuration=New-NrServiceWorkerConfiguration -Mapping $mapping -Strategies $strategies -Definitions $script:definitions
        $path=Save-NrServiceWorkerConfiguration -Configuration $configuration
        $saved=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $saved.schemaVersion | Should -Be 1
        @($saved.services) | Should -HaveCount 2
        foreach ($service in @($saved.services)) {
            $service.enabled | Should -BeTrue
            @($service.filterTokens).Count | Should -Be 2
            @($service.strategies).Count | Should -BeGreaterOrEqual 2
            $service.strategies[0].arguments | Should -Not -BeNullOrEmpty
            $service.probe.uri | Should -Match '^https://'
        }
    }

    It 'rejects unknown services and empty filter files instead of launching broad capture workers' {
        $strategies=@(Get-ChildItem -LiteralPath $script:fixture -Filter 'strategy-*.bat' -File | Sort-Object Name)
        { New-NrServiceWorkerConfiguration -Mapping ([pscustomobject]@{ unknown='strategy-a.bat' }) -Strategies $strategies -Definitions $script:definitions } | Should -Throw '*Unknown Service Matrix id*'
        Set-Content -LiteralPath (Join-Path $script:fixture 'lists/list-service-youtube.txt') -Value '# empty' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $script:fixture 'lists/ipset-service-youtube.txt') -Value '# empty' -Encoding UTF8
        try {
            { New-NrServiceWorkerConfiguration -Mapping ([pscustomobject]@{ youtube='strategy-a.bat' }) -Strategies $strategies -Definitions $script:definitions } | Should -Throw '*has no hostlist or ipset entries*'
        } finally {
            Set-Content -LiteralPath (Join-Path $script:fixture 'lists/list-service-youtube.txt') -Value 'youtube.example' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $script:fixture 'lists/ipset-service-youtube.txt') -Value '2001:db8:1::/48' -Encoding UTF8
        }
    }
}
