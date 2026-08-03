Describe 'NexRoute 0.6.0 safe Strategy Builder v2' {
    BeforeAll {
        $repositoryRoot=Split-Path -Parent $PSScriptRoot
        . (Join-Path $repositoryRoot 'overlay/.service/next/nexroute-strategy-builder-v2.ps1')
        $script:builderFixture=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-builder-'+[guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $script:builderFixture 'bin') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:builderFixture 'lists') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:builderFixture '.service') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $script:builderFixture 'bin/winws.exe') -Value 'fixture' -Encoding ASCII
        [IO.File]::WriteAllBytes((Join-Path $script:builderFixture 'bin/tls payload.bin'),[byte[]](1..32))
        [IO.File]::WriteAllBytes((Join-Path $script:builderFixture 'bin/quic payload.bin'),[byte[]](33..64))
        Set-Content -LiteralPath (Join-Path $script:builderFixture 'lists/video hosts.txt') -Value "youtube.com`ngooglevideo.com" -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $script:builderFixture 'lists/video ipset.txt') -Value "142.250.0.0/15`n2a00:1450::/32" -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $script:builderFixture 'lists/chat hosts.txt') -Value "discord.com`ndiscord.gg" -Encoding UTF8
    }

    AfterAll {
        Remove-Item -LiteralPath $script:builderFixture -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'builds typed TCP and UDP sections into deterministic winws tokens' {
        $definition=New-NrStrategyDefinition -Name 'Video and Voice' -Sections @(
            (New-NrStrategySection -Protocol tcp -Ports @('80','443') -Hostlist 'lists/video hosts.txt' -DesyncModes @('fake','multisplit') -Repeats 6 -Fooling @('badseq','md5sig') -SplitPositions @('1','host+1') -FakePayloads @(
                (New-NrFakePayloadDefinition -Kind tls -Path 'bin/tls payload.bin')
            )),
            (New-NrStrategySection -Protocol udp -Ports @('443','50000-50100') -Ipset 'lists/video ipset.txt' -DesyncModes @('fake','ipfrag2') -Repeats 3 -Fooling @('badsum') -FakePayloads @(
                (New-NrFakePayloadDefinition -Kind quic -Path 'bin/quic payload.bin')
            ))
        )
        $result=Test-NrStrategyDefinition -Definition $definition -Root $script:builderFixture
        $result.Valid | Should -BeTrue
        $tokens=[string[]](ConvertTo-NrStrategyBuilderTokens -Definition $definition -Root $script:builderFixture)
        $tokens[0] | Should -Be '--filter-tcp=80,443'
        $tokens | Should -Contain ('--hostlist='+(Join-Path $script:builderFixture 'lists/video hosts.txt'))
        $tokens | Should -Contain '--dpi-desync=fake,multisplit'
        $tokens | Should -Contain '--dpi-desync-repeats=6'
        $tokens | Should -Contain '--dpi-desync-fooling=badseq,md5sig'
        $tokens | Should -Contain '--dpi-desync-split-pos=1,host+1'
        $tokens | Should -Contain ('--dpi-desync-fake-tls='+(Join-Path $script:builderFixture 'bin/tls payload.bin'))
        $tokens | Should -Contain '--new'
        $tokens | Should -Contain '--filter-udp=443,50000-50100'
        $tokens | Should -Contain ('--dpi-desync-fake-quic='+(Join-Path $script:builderFixture 'bin/quic payload.bin'))
    }

    It 'blocks unscoped, broad, traversal and protocol-incompatible definitions' {
        $cases=@(
            (New-NrStrategyDefinition -Name 'No scope' -Sections @(
                (New-NrStrategySection -Protocol tcp -Ports @('443') -DesyncModes @('fake'))
            )),
            (New-NrStrategyDefinition -Name 'Broad' -Sections @(
                (New-NrStrategySection -Protocol tcp -Ports @('1-65535') -Hostlist 'lists/video hosts.txt' -DesyncModes @('fake'))
            )),
            (New-NrStrategyDefinition -Name 'Traversal' -Sections @(
                (New-NrStrategySection -Protocol tcp -Ports @('443') -Hostlist '../outside.txt' -DesyncModes @('fake'))
            )),
            (New-NrStrategyDefinition -Name 'UDP TLS fake' -Sections @(
                (New-NrStrategySection -Protocol udp -Ports @('443') -Ipset 'lists/video ipset.txt' -DesyncModes @('fake') -FakePayloads @(
                    (New-NrFakePayloadDefinition -Kind tls -Path 'bin/tls payload.bin')
                ))
            )),
            (New-NrStrategyDefinition -Name 'TCP QUIC fake' -Sections @(
                (New-NrStrategySection -Protocol tcp -Ports @('443') -Hostlist 'lists/video hosts.txt' -DesyncModes @('fake') -FakePayloads @(
                    (New-NrFakePayloadDefinition -Kind quic -Path 'bin/quic payload.bin')
                ))
            )),
            (New-NrStrategyDefinition -Name 'UDP md5sig' -Sections @(
                (New-NrStrategySection -Protocol udp -Ports @('443') -Ipset 'lists/video ipset.txt' -DesyncModes @('fake') -Fooling @('md5sig'))
            ))
        )
        foreach ($definition in $cases) {
            $result=Test-NrStrategyDefinition -Definition $definition -Root $script:builderFixture
            $result.Valid | Should -BeFalse
            @($result.Errors) | Should -HaveCount 1
        }
    }

    It 'allows an explicitly acknowledged broad capture but still requires a scope' {
        $definition=New-NrStrategyDefinition -Name 'Explicit broad' -AllowBroadCapture $true -Sections @(
            (New-NrStrategySection -Protocol tcp -Ports @('1-65535') -Hostlist 'lists/video hosts.txt' -DesyncModes @('multisplit'))
        )
        (Test-NrStrategyDefinition -Definition $definition -Root $script:builderFixture).Valid | Should -BeTrue
    }

    It 'round-trips Windows arguments containing spaces, quotes and trailing slashes' {
        $arguments=@(
            'plain',
            'path with spaces',
            '--hostlist=C:\Program Files\NexRoute\lists\video hosts.txt',
            'embedded"quote',
            'C:\trailing slash\',
            ''
        )
        $commandLine=@($arguments | ForEach-Object { ConvertTo-NrWindowsArgument -Value $_ }) -join ' '
        $parsed=[string[]](ConvertFrom-NrWindowsCommandLine -CommandLine $commandLine)
        $parsed | Should -HaveCount $arguments.Count
        for ($index=0; $index -lt $arguments.Count; $index++) { $parsed[$index] | Should -Be $arguments[$index] }
    }

    It 'round-trips a validated definition through tokens without changing the worker command' {
        $definition=New-NrStrategyDefinition -Name 'Round Trip' -Sections @(
            (New-NrStrategySection -Protocol tcp -Ports @('80','443') -Hostlist 'lists/video hosts.txt' -Ipset 'lists/video ipset.txt' -DesyncModes @('fake','multisplit') -Repeats 4 -Fooling @('badseq') -SplitPositions @('midsld','host+1') -FakePayloads @(
                (New-NrFakePayloadDefinition -Kind tls -Path 'bin/tls payload.bin')
            )),
            (New-NrStrategySection -Protocol udp -Ports @('443') -Ipset 'lists/video ipset.txt' -DesyncModes @('fake') -Repeats 2 -FakePayloads @(
                (New-NrFakePayloadDefinition -Kind quic -Path 'bin/quic payload.bin')
            ))
        )
        $first=[string[]](ConvertTo-NrStrategyBuilderTokens -Definition $definition -Root $script:builderFixture)
        $parsed=ConvertFrom-NrStrategyBuilderTokens -Tokens $first -Name 'Round Trip' -Root $script:builderFixture
        $second=[string[]](ConvertTo-NrStrategyBuilderTokens -Definition $parsed -Root $script:builderFixture)
        $second | Should -HaveCount $first.Count
        for ($index=0; $index -lt $first.Count; $index++) { $second[$index] | Should -Be $first[$index] }
    }

    It 'uses the exact same argv array for preview and the worker command object' {
        $definition=New-NrStrategyDefinition -Name 'Preview Exact' -Sections @(
            (New-NrStrategySection -Protocol tcp -Ports @('443') -Hostlist 'lists/video hosts.txt' -DesyncModes @('fake','multisplit') -FakePayloads @(
                (New-NrFakePayloadDefinition -Kind tls -Path 'bin/tls payload.bin')
            ))
        )
        $command=New-NrStrategyWorkerCommand -Definition $definition -Root $script:builderFixture
        $parsed=[string[]](ConvertFrom-NrWindowsCommandLine -CommandLine $command.preview)
        $parsed[0] | Should -Be $command.executable
        $parsed.Count | Should -Be ($command.arguments.Count+1)
        for ($index=0; $index -lt $command.arguments.Count; $index++) { $parsed[$index+1] | Should -Be $command.arguments[$index] }
        $command.commandHash | Should -Match '^[0-9a-f]{64}$'
    }

    It 'saves an atomic JSON definition and a portable BAT using the same tokens' {
        $definition=New-NrStrategyDefinition -Name 'Portable Custom' -Sections @(
            (New-NrStrategySection -Protocol tcp -Ports @('443') -Hostlist 'lists/video hosts.txt' -DesyncModes @('fake','multisplit') -Repeats 5 -FakePayloads @(
                (New-NrFakePayloadDefinition -Kind tls -Path 'bin/tls payload.bin')
            ))
        )
        $saved=Save-NrCustomStrategy -Definition $definition -Root $script:builderFixture
        Test-Path -LiteralPath $saved.definitionPath -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $saved.batchPath -PathType Leaf | Should -BeTrue
        @(Get-ChildItem -LiteralPath (Split-Path -Parent $saved.definitionPath) -Filter '*.tmp-*' -File -ErrorAction SilentlyContinue) | Should -HaveCount 0
        $batch=Get-Content -LiteralPath $saved.batchPath -Raw -Encoding UTF8
        $batch | Should -Match ([regex]::Escape('%BIN%\winws.exe'))
        $batch | Should -Match ([regex]::Escape('%LISTS%'))
        $batch | Should -Not -Match ([regex]::Escape($script:builderFixture))
        $document=Get-Content -LiteralPath $saved.definitionPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $document.commandHash | Should -Be $saved.command.commandHash
        $imported=Import-NrCustomStrategyDefinition -Path $saved.definitionPath -Root $script:builderFixture
        $imported.name | Should -Be 'Portable Custom'
        [string[]]$saved.portableArguments | Should -Contain '--dpi-desync-repeats=5'
    }

    It 'rejects duplicate scopes, overlapping ports and unsafe names' {
        $duplicate=New-NrStrategyDefinition -Name 'Duplicate' -Sections @(
            (New-NrStrategySection -Protocol tcp -Ports @('443') -Hostlist 'lists/video hosts.txt' -DesyncModes @('fake')),
            (New-NrStrategySection -Protocol tcp -Ports @('443') -Hostlist 'lists/video hosts.txt' -DesyncModes @('multisplit'))
        )
        (Test-NrStrategyDefinition -Definition $duplicate -Root $script:builderFixture).Valid | Should -BeFalse
        $overlap=New-NrStrategyDefinition -Name 'Overlap' -Sections @(
            (New-NrStrategySection -Protocol tcp -Ports @('80-100','90-110') -Hostlist 'lists/video hosts.txt' -DesyncModes @('fake'))
        )
        (Test-NrStrategyDefinition -Definition $overlap -Root $script:builderFixture).Valid | Should -BeFalse
        $unsafe=New-NrStrategyDefinition -Name 'bad & del *' -Sections @(
            (New-NrStrategySection -Protocol tcp -Ports @('443') -Hostlist 'lists/video hosts.txt' -DesyncModes @('fake'))
        )
        (Test-NrStrategyDefinition -Definition $unsafe -Root $script:builderFixture).Valid | Should -BeFalse
    }

    It 'loads the visual arrow-key builder before Strategy Lab and worker plans' {
        $repositoryRoot=Split-Path -Parent $PSScriptRoot
        $loader=Get-Content -LiteralPath (Join-Path $repositoryRoot 'overlay/.service/next/nexroute-runtime-extensions.ps1') -Raw -Encoding UTF8
        $loader | Should -Match ([regex]::Escape('nexroute-strategy-builder-v2.ps1'))
        $loader.IndexOf('nexroute-strategy-builder-v2.ps1') | Should -BeGreaterThan $loader.IndexOf('nexroute-repair-v2-fixes.ps1')
        $loader.IndexOf('nexroute-strategy-builder-v2.ps1') | Should -BeLessThan $loader.IndexOf('nexroute-strategy-lab-v2.ps1')
        $source=Get-Content -LiteralPath (Join-Path $repositoryRoot 'overlay/.service/next/nexroute-strategy-builder-v2.ps1') -Raw -Encoding UTF8
        foreach ($token in @('Show-NrStrategyBuilder','Select-NrBuilderMultipleValues','UpArrow','DownArrow','Spacebar','New-NrStrategyWorkerCommand','ConvertFrom-NrStrategyBuilderTokens','Save-NrCustomStrategy')) {
            $source | Should -Match ([regex]::Escape($token))
        }
    }
}
