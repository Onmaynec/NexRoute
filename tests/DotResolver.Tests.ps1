Describe 'NexRoute 0.6.0 transactional DNS-over-TLS resolver' {
    BeforeAll {
        $root=Split-Path -Parent $PSScriptRoot
        . (Join-Path $root 'overlay/.service/next/nexroute-portable-verifier.ps1')
        function Set-NrDnsProvider { param($Provider,$Adapters,$Encryption) return 'legacy' }
        . (Join-Path $root 'overlay/.service/next/nexroute-dot.ps1')
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $script:provider=[pscustomobject]@{
            id='cloudflare'; dot='cloudflare-dns.com:853';
            ipv4=@('1.1.1.1','1.0.0.1'); ipv6=@('2606:4700:4700::1111','2606:4700:4700::1001')
        }

        function New-NrDnsProxyFixture {
            param([string]$Path)
            $source=Join-Path $Path 'source/dnsproxy-windows-amd64-v0.81.4'
            New-Item -ItemType Directory -Path $source -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $source 'dnsproxy.exe') -Value 'fixture-dnsproxy-executable' -Encoding ASCII
            $padding=New-Object byte[] 1100000
            for ($index=0;$index -lt $padding.Length;$index++) { $padding[$index]=[byte]($index % 239) }
            [IO.File]::WriteAllBytes((Join-Path $source 'padding.dat'),$padding)
            $archive=Join-Path $Path 'dnsproxy-fixture.zip'
            [IO.Compression.ZipFile]::CreateFromDirectory((Join-Path $Path 'source'),$archive,[IO.Compression.CompressionLevel]::NoCompression,$false)
            return $archive
        }

        function New-NrDnsProxyManifest {
            param([string]$Path,[string]$ArchivePath,[string]$Sha)
            [ordered]@{
                schemaVersion=1
                tools=[ordered]@{
                    dnsproxy=[ordered]@{
                        version='0.81.4'; tag='v0.81.4'; repository='AdguardTeam/dnsproxy';
                        assetName='dnsproxy-windows-amd64-v0.81.4.zip';
                        assetUrl='https://github.com/AdguardTeam/dnsproxy/releases/download/v0.81.4/dnsproxy-windows-amd64-v0.81.4.zip';
                        sha256=$Sha; minimumBytes=1000000; executableFileName='dnsproxy.exe'; purpose='fixture'
                    }
                }
            } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding UTF8
            return $Path
        }
    }

    It 'pins the official dnsproxy v0.81.4 Windows asset and GitHub digest' {
        $repositoryRoot=Split-Path -Parent $PSScriptRoot
        $manifest=Join-Path $repositoryRoot 'overlay/.service/portable-tools.json'
        $tool=Read-NrDnsProxyToolDefinition -ManifestPath $manifest
        $tool.version | Should -Be '0.81.4'
        $tool.assetName | Should -Be 'dnsproxy-windows-amd64-v0.81.4.zip'
        $tool.sha256 | Should -Be '2ca72d0e3a7a888b8643578236a9dd3c2d0cf501b24150521418abcdfe522ae2'
        $tool.assetUrl | Should -Be 'https://github.com/AdguardTeam/dnsproxy/releases/download/v0.81.4/dnsproxy-windows-amd64-v0.81.4.zip'
    }

    It 'installs a verified resolver archive into an integrity-checked cache' {
        $fixture=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-dot-cache-'+[guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path (Join-Path $fixture '.service') -Force | Out-Null
            $archive=New-NrDnsProxyFixture -Path $fixture
            $sha=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
            $manifest=New-NrDnsProxyManifest -Path (Join-Path $fixture '.service/portable-tools.json') -ArchivePath $archive -Sha $sha
            $first=Get-NrDnsProxyBinary -Root $fixture -ManifestPath $manifest -ArchivePath $archive -SkipVersionProbe
            $first.cached | Should -BeFalse
            Test-Path -LiteralPath $first.executable -PathType Leaf | Should -BeTrue
            $first.executable | Should -Match '[\\/]bin[\\/]dnsproxy\.exe$'
            $receipt=Get-Content -LiteralPath $first.receipt -Raw | ConvertFrom-Json
            $receipt.archiveSha256 | Should -Be $sha
            $receipt.executableSha256 | Should -Be (Get-FileHash -LiteralPath $first.executable -Algorithm SHA256).Hash.ToLowerInvariant()

            $second=Get-NrDnsProxyBinary -Root $fixture -ManifestPath $manifest -ArchivePath $archive -SkipVersionProbe
            $second.cached | Should -BeTrue
            Set-Content -LiteralPath $second.executable -Value 'tampered' -Encoding ASCII
            $third=Get-NrDnsProxyBinary -Root $fixture -ManifestPath $manifest -ArchivePath $archive -SkipVersionProbe
            $third.cached | Should -BeFalse
            (Get-Content -LiteralPath $third.executable -Raw) | Should -Match 'fixture-dnsproxy-executable'
        } finally { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'builds a loopback resolver command with a TLS upstream and bootstrap DNS' {
        $arguments=New-NrDnsProxyArguments -Provider $script:provider -LogPath 'C:\NexRoute\dnsproxy.log'
        $arguments | Should -Contain '-l'
        $arguments | Should -Contain '127.0.0.1'
        $arguments | Should -Contain '::1'
        $arguments | Should -Contain '-p'
        $arguments | Should -Contain '53'
        $arguments | Should -Contain '-u'
        $arguments | Should -Contain 'tls://cloudflare-dns.com:853'
        $arguments | Should -Contain '1.1.1.1:53'
        $arguments | Should -Contain '1.0.0.1:53'
        $arguments | Should -Contain '--cache'
        $arguments | Should -Not -Contain '--insecure'
    }

    It 'commits only after direct and system DNS probes pass' {
        $fixture=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-dot-commit-'+[guid]::NewGuid().ToString('N'))
        $script:events=New-Object 'System.Collections.Generic.List[string]'
        try {
            New-Item -ItemType Directory -Path $fixture -Force | Out-Null
            $result=Invoke-NrDotTransaction -Root $fixture -Provider $script:provider -Adapters @([pscustomobject]@{ ifIndex=7; Name='Ethernet' }) -Executable 'dnsproxy.exe' -Arguments @('-u','tls://cloudflare-dns.com:853') `
                -SnapshotReader { param($adapters) $script:events.Add('snapshot'); @([pscustomobject]@{ interfaceIndex=7; interfaceAlias='Ethernet'; addressFamily='IPv4'; serverAddresses=@('192.0.2.53') }) } `
                -RuntimeStarter { param($rootPath,$executable,$arguments) $script:events.Add('start'); [pscustomobject]@{ pid=4242 } } `
                -LoopbackSetter { param($adapters) $script:events.Add('loopback') } `
                -Probe { param($mode) $script:events.Add('probe-'+$mode); [pscustomobject]@{ ok=$true; mode=$mode } } `
                -SnapshotRestorer { param($snapshot) $script:events.Add('restore') } `
                -RuntimeStopper { param($rootPath) $script:events.Add('stop') }

            $result.committed | Should -BeTrue
            $result.status | Should -Be 'committed'
            $script:events.ToArray() | Should -Be @('snapshot','start','probe-direct','loopback','probe-system')
            Test-Path -LiteralPath $result.snapshotPath -PathType Leaf | Should -BeTrue
            $record=Get-Content -LiteralPath (Join-Path $fixture '.service/dot/transaction.json') -Raw | ConvertFrom-Json
            $record.status | Should -Be 'committed'
            $record.upstream | Should -Be 'tls://cloudflare-dns.com:853'
        } finally { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'restores previous DNS and stops the resolver when the direct probe fails' {
        $fixture=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-dot-direct-fail-'+[guid]::NewGuid().ToString('N'))
        $script:events=New-Object 'System.Collections.Generic.List[string]'
        try {
            New-Item -ItemType Directory -Path $fixture -Force | Out-Null
            $result=Invoke-NrDotTransaction -Root $fixture -Provider $script:provider -Adapters @([pscustomobject]@{ ifIndex=8; Name='Wi-Fi' }) -Executable 'dnsproxy.exe' -Arguments @() `
                -SnapshotReader { param($adapters) @([pscustomobject]@{ interfaceIndex=8; interfaceAlias='Wi-Fi'; addressFamily='IPv4'; serverAddresses=@('198.51.100.53') }) } `
                -RuntimeStarter { param($rootPath,$executable,$arguments) $script:events.Add('start'); [pscustomobject]@{ pid=5000 } } `
                -LoopbackSetter { param($adapters) $script:events.Add('loopback') } `
                -Probe { param($mode) $script:events.Add('probe-'+$mode); [pscustomobject]@{ ok=$false; mode=$mode } } `
                -SnapshotRestorer { param($snapshot) $script:events.Add('restore') } `
                -RuntimeStopper { param($rootPath) $script:events.Add('stop') }

            $result.committed | Should -BeFalse
            $result.status | Should -Be 'rolled-back'
            $script:events.ToArray() | Should -Be @('start','probe-direct','restore','stop')
            $result.message | Should -Match 'Previous DNS settings were restored'
            $record=Get-Content -LiteralPath (Join-Path $fixture '.service/dot/transaction.json') -Raw | ConvertFrom-Json
            $record.status | Should -Be 'rolled-back'
        } finally { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'restores previous DNS when loopback works but the system resolver fails' {
        $fixture=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-dot-system-fail-'+[guid]::NewGuid().ToString('N'))
        $script:events=New-Object 'System.Collections.Generic.List[string]'
        try {
            New-Item -ItemType Directory -Path $fixture -Force | Out-Null
            $result=Invoke-NrDotTransaction -Root $fixture -Provider $script:provider -Adapters @([pscustomobject]@{ ifIndex=9; Name='Ethernet' }) -Executable 'dnsproxy.exe' -Arguments @() `
                -SnapshotReader { param($adapters) @([pscustomobject]@{ interfaceIndex=9; interfaceAlias='Ethernet'; addressFamily='IPv4'; serverAddresses=@('203.0.113.53') }) } `
                -RuntimeStarter { param($rootPath,$executable,$arguments) [pscustomobject]@{ pid=6000 } } `
                -LoopbackSetter { param($adapters) $script:events.Add('loopback') } `
                -Probe { param($mode) $script:events.Add('probe-'+$mode); [pscustomobject]@{ ok=($mode -eq 'direct'); mode=$mode } } `
                -SnapshotRestorer { param($snapshot) $script:events.Add('restore') } `
                -RuntimeStopper { param($rootPath) $script:events.Add('stop') }

            $result.status | Should -Be 'rolled-back'
            $script:events.ToArray() | Should -Be @('probe-direct','loopback','probe-system','restore','stop')
        } finally { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
