Describe 'NexRoute 0.6.0 address-family probes' {
    BeforeAll {
        $repositoryRoot=Split-Path -Parent $PSScriptRoot
        . (Join-Path $repositoryRoot 'overlay/.service/next/nexroute-family-probe.ps1')
    }

    It 'filters DNS results to the requested address family' {
        $resolver={ param($hostName) @([Net.IPAddress]::Parse('127.0.0.1'),[Net.IPAddress]::Parse('::1'),[Net.IPAddress]::Parse('192.0.2.10'),[Net.IPAddress]::Parse('2001:db8::10')) }
        $ipv4=@(Resolve-NrProbeAddresses -HostName 'fixture.invalid' -Family ipv4 -Resolver $resolver)
        $ipv6=@(Resolve-NrProbeAddresses -HostName 'fixture.invalid' -Family ipv6 -Resolver $resolver)
        $ipv4 | Should -HaveCount 2
        @($ipv4 | ForEach-Object IPAddressToString) | Should -Contain '127.0.0.1'
        @($ipv4 | ForEach-Object IPAddressToString) | Should -Contain '192.0.2.10'
        $ipv6 | Should -HaveCount 2
        @($ipv6 | ForEach-Object IPAddressToString) | Should -Contain '::1'
        @($ipv6 | ForEach-Object IPAddressToString) | Should -Contain '2001:db8::10'
    }

    It 'does not reinterpret a literal address as the other family' {
        @(Resolve-NrProbeAddresses -HostName '127.0.0.1' -Family ipv6) | Should -HaveCount 0
        @(Resolve-NrProbeAddresses -HostName '::1' -Family ipv4) | Should -HaveCount 0
        @(Resolve-NrProbeAddresses -HostName '127.0.0.1' -Family ipv4) | Should -HaveCount 1
        @(Resolve-NrProbeAddresses -HostName '::1' -Family ipv6) | Should -HaveCount 1
    }

    It 'connects a TCP probe only to the selected IPv6 address' {
        $script:connectedAddress=$null
        $script:connectedFamily=$null
        $resolver={ param($hostName) @([Net.IPAddress]::Parse('127.0.0.1'),[Net.IPAddress]::Parse('::1')) }
        $connector={
            param($address,$port,$timeout)
            $script:connectedAddress=$address.IPAddressToString
            $script:connectedFamily=$address.AddressFamily
            $client=[pscustomobject]@{ Connected=$true }
            $client | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
            return $client
        }
        $result=Invoke-NrAddressFamilyProbe -Uri ([Uri]'tcp://fixture.invalid:443') -Family ipv6 -Resolver $resolver -Connector $connector
        $result.ok | Should -BeTrue
        $result.family | Should -Be 'ipv6'
        $result.address | Should -Be '::1'
        $script:connectedAddress | Should -Be '::1'
        $script:connectedFamily | Should -Be ([Net.Sockets.AddressFamily]::InterNetworkV6)
    }

    It 'parses an HTTP response through the selected IPv4 connection' {
        $script:probeStream=[IO.MemoryStream]::new([Text.Encoding]::ASCII.GetBytes("HTTP/1.1 204 No Content`r`nContent-Length: 0`r`n`r`n"))
        $script:connectedAddress=$null
        try {
            $resolver={ param($hostName) @([Net.IPAddress]::Parse('::1'),[Net.IPAddress]::Parse('127.0.0.1')) }
            $connector={
                param($address,$port,$timeout)
                $script:connectedAddress=$address.IPAddressToString
                $client=[pscustomobject]@{ Connected=$true }
                $client | Add-Member -MemberType ScriptMethod -Name GetStream -Value { return $script:probeStream }
                $client | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }
                return $client
            }
            $result=Invoke-NrAddressFamilyProbe -Uri ([Uri]'http://fixture.invalid/generate_204') -Family ipv4 -Resolver $resolver -Connector $connector
            $result.ok | Should -BeTrue
            $result.statusCode | Should -Be 204
            $result.address | Should -Be '127.0.0.1'
            $script:connectedAddress | Should -Be '127.0.0.1'
        } finally { $script:probeStream.Dispose() }
    }

    It 'fails closed when DNS has no address in the requested family' {
        $resolver={ param($hostName) @([Net.IPAddress]::Parse('127.0.0.1')) }
        $result=Invoke-NrAddressFamilyProbe -Uri ([Uri]'tcp://fixture.invalid:443') -Family ipv6 -Resolver $resolver
        $result.ok | Should -BeFalse
        $result.reason | Should -Match 'No ipv6 address'
        $result.address | Should -BeNullOrEmpty
    }

    It 'accepts schema v2 in the product worker host and delegates family probes' {
        $repositoryRoot=Split-Path -Parent $PSScriptRoot
        $source=Get-Content -LiteralPath (Join-Path $repositoryRoot 'overlay/.service/nexroute-worker-host.ps1') -Raw -Encoding UTF8
        foreach ($token in @("schemaVersion -notin @(1,2)",'nexroute-family-probe.ps1','Test-NrAddressFamilyProbe','addressFamily','strategy family')) {
            $source | Should -Match ([regex]::Escape($token))
        }
    }

    It 'loads family probe source in the Windows package tree' {
        $repositoryRoot=Split-Path -Parent $PSScriptRoot
        Test-Path -LiteralPath (Join-Path $repositoryRoot 'overlay/.service/next/nexroute-family-probe.ps1') -PathType Leaf | Should -BeTrue
        $packageBuilder=Get-Content -LiteralPath (Join-Path $repositoryRoot 'scripts/Build-Package.ps1') -Raw -Encoding UTF8
        $packageBuilder | Should -Match ([regex]::Escape("Copy-NexRoutePackageDirectory -Source (Join-Path `$repositoryRoot 'overlay/.service/next')"))
    }
}
