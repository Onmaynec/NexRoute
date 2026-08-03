Describe 'NexRoute 0.6.0 atomic DNS snapshot restoration' {
    BeforeAll {
        $root=Split-Path -Parent $PSScriptRoot
        . (Join-Path $root 'overlay/.service/next/nexroute-dot-snapshot-v2.ps1')
    }

    It 'combines IPv4 and IPv6 DNS servers into one adapter snapshot' {
        $snapshot=Get-NrDnsAdapterSnapshot -Adapters @([pscustomobject]@{ ifIndex=12; Name='Ethernet' }) -AddressReader {
            param($index,$family)
            if ($family -eq 'IPv4') { return [pscustomobject]@{ ServerAddresses=@('1.1.1.1','1.0.0.1') } }
            return [pscustomobject]@{ ServerAddresses=@('2606:4700:4700::1111','2606:4700:4700::1001','1.1.1.1') }
        }
        @($snapshot) | Should -HaveCount 1
        $snapshot[0].interfaceIndex | Should -Be 12
        @($snapshot[0].serverAddresses) | Should -Be @('1.1.1.1','1.0.0.1','2606:4700:4700::1111','2606:4700:4700::1001')
    }

    It 'restores IPv4 and IPv6 addresses with one atomic setter call per adapter' {
        $script:calls=New-Object 'System.Collections.Generic.List[object]'
        $script:flushes=0
        Restore-NrDnsAdapterSnapshot -Snapshot @(
            [pscustomobject]@{ interfaceIndex=12; interfaceAlias='Ethernet'; serverAddresses=@('1.1.1.1','2606:4700:4700::1111') }
            [pscustomobject]@{ interfaceIndex=13; interfaceAlias='Wi-Fi'; serverAddresses=@() }
        ) -AddressSetter {
            param($index,$addresses,$reset)
            $script:calls.Add([pscustomobject]@{ index=$index; addresses=[string[]]$addresses; reset=[bool]$reset })
        } -CacheFlusher { $script:flushes++ }

        $script:calls.Count | Should -Be 2
        $script:calls[0].index | Should -Be 12
        $script:calls[0].addresses | Should -Be @('1.1.1.1','2606:4700:4700::1111')
        $script:calls[0].reset | Should -BeFalse
        $script:calls[1].index | Should -Be 13
        $script:calls[1].reset | Should -BeTrue
        $script:flushes | Should -Be 1
    }
}
