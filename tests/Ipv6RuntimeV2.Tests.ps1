Describe 'NexRoute 0.6.0 IPv4 IPv6 dual-stack runtime' {
    BeforeAll {
        $repositoryRoot=Split-Path -Parent $PSScriptRoot
        . (Join-Path $repositoryRoot 'overlay/.service/next/nexroute-workers.ps1')
        function Apply-NrPerServiceStrategies { }
        . (Join-Path $repositoryRoot 'overlay/.service/next/nexroute-ipv6-runtime-v2.ps1')
        $script:ipv6Fixture=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-ipv6-'+[guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $script:ipv6Fixture 'bin') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:ipv6Fixture 'lists') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:ipv6Fixture '.service') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:ipv6Fixture 'bin/winws.exe') -Value 'fixture' -Encoding ASCII
        $script:hostlist=Join-Path $script:ipv6Fixture 'lists/list-service-youtube.txt'
        $script:ipset=Join-Path $script:ipv6Fixture 'lists/ipset-service-youtube.txt'
        Set-Content -LiteralPath $script:hostlist -Value "youtube.com`ngooglevideo.com" -Encoding UTF8
        Set-Content -LiteralPath $script:ipset -Value @(
            '# mixed service ipset',
            '142.250.0.0/15',
            '8.8.8.8',
            '2a00:1450::/32',
            '2001:4860:4860::8888',
            'invalid-address'
        ) -Encoding UTF8
        $script:winws=Join-Path $script:ipv6Fixture 'bin/winws.exe'
        $script:baseConfiguration=[pscustomobject][ordered]@{
            schemaVersion=1
            services=@(
                [pscustomobject][ordered]@{
                    id='youtube'
                    enabled=$true
                    filterTokens=@('hostlist:youtube','ipset:youtube')
                    filterFiles=[pscustomobject]@{ hostlist=$script:hostlist; ipset=$script:ipset; hostEntries=2; ipEntries=5 }
                    probe=[pscustomobject]@{ uri='https://www.youtube.com/generate_204'; timeoutSeconds=5 }
                    strategies=@(
                        [pscustomobject][ordered]@{
                            name='general.bat'; executable=$script:winws; sourceFile='general.bat'
                            arguments=@(
                                '--filter-tcp=80,443',
                                '--hostlist='+$script:hostlist,
                                '--ipset='+$script:ipset,
                                '--dpi-desync=fake,multisplit',
                                '--new',
                                '--filter-udp=443',
                                '--hostlist='+$script:hostlist,
                                '--ipset='+$script:ipset,
                                '--dpi-desync=fake'
                            )
                        }
                    )
                }
            )
        }
        $script:supportedCapability=Get-NrWinwsAddressFamilyCapability -Root $script:ipv6Fixture -HelpText @'
winws 1.10.0
--filter-l3=ipv4|ipv6
--filter-tcp=<ports>
--filter-udp=<ports>
--ipset=<file>
--hostlist=<file>
'@
    }

    AfterAll {
        Stop-NrWorkerSet -Root $script:ipv6Fixture -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $script:ipv6Fixture -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'requires the pinned runtime help to advertise both layer-3 families' {
        $script:supportedCapability.state | Should -Be 'supported'
        $script:supportedCapability.supportsFilterL3 | Should -BeTrue
        $script:supportedCapability.supportsIpv4 | Should -BeTrue
        $script:supportedCapability.supportsIpv6 | Should -BeTrue
        $script:supportedCapability.helpSha256 | Should -Match '^[0-9a-f]{64}$'

        $unsupported=Get-NrWinwsAddressFamilyCapability -Root $script:ipv6Fixture -HelpText "winws`n--filter-tcp=<ports>"
        $unsupported.state | Should -Be 'unsupported'
        $unsupported.supportsIpv6 | Should -BeFalse
        $unsupported.reason | Should -Match 'filter-l3'
    }

    It 'classifies and separates IPv4 and IPv6 CIDR and literal addresses' {
        Get-NrIpSetEntryFamily -Entry '142.250.0.0/15' | Should -Be 'ipv4'
        Get-NrIpSetEntryFamily -Entry '8.8.8.8' | Should -Be 'ipv4'
        Get-NrIpSetEntryFamily -Entry '2a00:1450::/32' | Should -Be 'ipv6'
        Get-NrIpSetEntryFamily -Entry '2001:4860:4860::8888' | Should -Be 'ipv6'
        Get-NrIpSetEntryFamily -Entry 'not-an-address' | Should -Be 'invalid'
        $families=Read-NrIpSetAddressFamilies -Path $script:ipset
        $families.ipv4 | Should -HaveCount 2
        $families.ipv6 | Should -HaveCount 2
        $families.invalid | Should -Contain 'invalid-address'
    }

    It 'builds an IPv4-only plan and injects the filter in every winws profile' {
        $configuration=New-NrAddressFamilyWorkerConfiguration -BaseConfiguration $script:baseConfiguration -Mode IPv4 -Root $script:ipv6Fixture -Capability $script:supportedCapability
        $configuration.state | Should -Be 'supported'
        $configuration.resolvedMode | Should -Be 'IPv4'
        $configuration.services | Should -HaveCount 1
        $service=$configuration.services[0]
        $service.id | Should -Be 'youtube-ipv4'
        $service.addressFamily | Should -Be 'ipv4'
        $service.probe.addressFamily | Should -Be 'ipv4'
        @($service.strategies[0].arguments | Where-Object { $_ -eq '--filter-l3=ipv4' }) | Should -HaveCount 2
        @($service.strategies[0].arguments | Where-Object { $_ -eq '--filter-l3=ipv6' }) | Should -HaveCount 0
        $familyLines=@(Get-Content -LiteralPath $service.filterFiles.ipset | Where-Object { $_ -and -not $_.StartsWith('#') })
        $familyLines | Should -Contain '142.250.0.0/15'
        $familyLines | Should -Contain '8.8.8.8'
        $familyLines | Should -Not -Contain '2a00:1450::/32'
        @($service.strategies[0].arguments | Where-Object { $_ -eq ('--ipset='+$script:ipset) }) | Should -HaveCount 0
    }

    It 'builds an IPv6-only plan with only IPv6 targets' {
        $configuration=New-NrAddressFamilyWorkerConfiguration -BaseConfiguration $script:baseConfiguration -Mode IPv6 -Root $script:ipv6Fixture -Capability $script:supportedCapability
        $configuration.state | Should -Be 'supported'
        $configuration.services | Should -HaveCount 1
        $service=$configuration.services[0]
        $service.id | Should -Be 'youtube-ipv6'
        @($service.strategies[0].arguments | Where-Object { $_ -eq '--filter-l3=ipv6' }) | Should -HaveCount 2
        $familyLines=@(Get-Content -LiteralPath $service.filterFiles.ipset | Where-Object { $_ -and -not $_.StartsWith('#') })
        $familyLines | Should -Contain '2a00:1450::/32'
        $familyLines | Should -Contain '2001:4860:4860::8888'
        $familyLines | Should -Not -Contain '142.250.0.0/15'
    }

    It 'builds non-overlapping dual-stack worker scopes' {
        $configuration=New-NrAddressFamilyWorkerConfiguration -BaseConfiguration $script:baseConfiguration -Mode DualStack -Root $script:ipv6Fixture -Capability $script:supportedCapability
        $configuration.state | Should -Be 'supported'
        $configuration.services | Should -HaveCount 2
        @($configuration.services.id) | Should -Contain 'youtube-ipv4'
        @($configuration.services.id) | Should -Contain 'youtube-ipv6'
        $plans=@($configuration.services | ForEach-Object {
            [pscustomobject]@{
                serviceId=$_.id
                filterTokens=[string[]]$_.filterTokens
                strategy=$_.strategies[0].name
                executable=$_.strategies[0].executable
                arguments=[string[]]$_.strategies[0].arguments
            }
        })
        { Assert-NrWorkerFilterIsolation -Plans $plans } | Should -Not -Throw
        @($plans[0].filterTokens | Where-Object { $_ -like 'scope:ipv4*' }).Count | Should -BeGreaterThan 0
        @($plans[1].filterTokens | Where-Object { $_ -like 'scope:ipv6*' }).Count | Should -BeGreaterThan 0
    }

    It 'fails closed and records limitations when IPv6 is not advertised' {
        $unsupported=Get-NrWinwsAddressFamilyCapability -Root $script:ipv6Fixture -HelpText "winws`n--filter-l3=ipv4"
        $configuration=New-NrAddressFamilyWorkerConfiguration -BaseConfiguration $script:baseConfiguration -Mode IPv6 -Root $script:ipv6Fixture -Capability $unsupported
        $configuration.state | Should -Be 'unsupported'
        $configuration.services | Should -HaveCount 0
        $configuration.limitations | Should -HaveCount 1
        $configuration.limitations[0].code | Should -Be 'upstream-capability-missing'
        $configuration.limitations[0].message | Should -Not -BeNullOrEmpty
    }

    It 'launches real IPv4-only, IPv6-only and dual-stack synthetic workers with unique PIDs' {
        $engine=(Get-Process -Id $PID).Path
        $workerScript=Join-Path $script:ipv6Fixture 'family-worker.ps1'
        Set-Content -LiteralPath $workerScript -Value @'
param([string]$Family,[string]$Service)
Write-Output ("READY family={0} service={1}" -f $Family,$Service)
Start-Sleep -Seconds 30
'@ -Encoding UTF8
        foreach ($mode in @('IPv4','IPv6','DualStack')) {
            Stop-NrWorkerSet -Root $script:ipv6Fixture
            $configuration=New-NrAddressFamilyWorkerConfiguration -BaseConfiguration $script:baseConfiguration -Mode $mode -Root $script:ipv6Fixture -Capability $script:supportedCapability
            $plans=@($configuration.services | ForEach-Object {
                [pscustomobject]@{
                    serviceId=$_.id
                    strategy='synthetic-'+$_.addressFamily
                    executable=$engine
                    arguments=@('-NoProfile','-File',$workerScript,'-Family',[string]$_.addressFamily,'-Service',[string]$_.baseServiceId)
                    filterTokens=[string[]]$_.filterTokens
                }
            })
            $started=@(Start-NrWorkerSet -Root $script:ipv6Fixture -Plans $plans)
            $expected=if ($mode -eq 'DualStack') { 2 } else { 1 }
            $started | Should -HaveCount $expected
            @($started.pid | Sort-Object -Unique) | Should -HaveCount $expected
            foreach ($state in $started) {
                Test-NrWorkerProcess -State $state | Should -BeTrue
                [string[]]$state.arguments | Should -Contain '-Family'
                Test-Path -LiteralPath $state.stdout -PathType Leaf | Should -BeTrue
            }
            Stop-NrWorkerSet -Root $script:ipv6Fixture
        }
    }

    It 'loads the family gate after worker plans and exposes an honest status command' {
        $repositoryRoot=Split-Path -Parent $PSScriptRoot
        $loader=Get-Content -LiteralPath (Join-Path $repositoryRoot 'overlay/.service/next/nexroute-runtime-extensions.ps1') -Raw -Encoding UTF8
        $loader | Should -Match ([regex]::Escape('nexroute-ipv6-runtime-v2.ps1'))
        $loader.IndexOf('nexroute-ipv6-runtime-v2.ps1') | Should -BeGreaterThan $loader.IndexOf('nexroute-worker-plans.ps1')
        $source=Get-Content -LiteralPath (Join-Path $repositoryRoot 'overlay/.service/next/nexroute-ipv6-runtime-v2.ps1') -Raw -Encoding UTF8
        foreach ($token in @('--filter-l3=','ipv4','ipv6','DualStack','upstream-capability-missing','Show-NrIpv6RuntimeStatus','ipv6-capability.json')) {
            $source | Should -Match ([regex]::Escape($token))
        }
    }
}
