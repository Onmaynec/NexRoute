Describe 'NexRoute 0.6.0 network profiles v2' {
    BeforeAll {
        $repositoryRoot=Split-Path -Parent $PSScriptRoot
        . (Join-Path $repositoryRoot 'overlay/.service/next/nexroute-network-profiles-v2.ps1')
    }

    It 'uses the interface GUID as a stable identity when the interface index changes' {
        $first=[pscustomobject]@{ InterfaceGuid='{11111111-2222-3333-4444-555555555555}'; ifIndex=7; Name='Ethernet' }
        $second=[pscustomobject]@{ InterfaceGuid='{11111111-2222-3333-4444-555555555555}'; ifIndex=42; Name='Ethernet renamed' }
        ConvertTo-NrStableAdapterId -Adapter $first | Should -Be 'guid:11111111-2222-3333-4444-555555555555'
        ConvertTo-NrStableAdapterId -Adapter $second | Should -Be 'guid:11111111-2222-3333-4444-555555555555'
    }

    It 'builds Ethernet and WiFi snapshots with Windows network categories' {
        $adapters=@(
            [pscustomobject]@{ InterfaceGuid='{aaaaaaaa-0000-0000-0000-000000000001}'; ifIndex=10; Name='Intel Ethernet'; Status='Up'; NdisPhysicalMedium='802.3'; MediaType='802.3'; InterfaceDescription='Intel Ethernet'; MacAddress='00-11-22-33-44-55' },
            [pscustomobject]@{ InterfaceGuid='{aaaaaaaa-0000-0000-0000-000000000002}'; ifIndex=20; Name='Wi-Fi'; Status='Up'; NdisPhysicalMedium='802.11'; MediaType='802.11'; InterfaceDescription='Wireless Adapter'; MacAddress='66-77-88-99-AA-BB' },
            [pscustomobject]@{ InterfaceGuid='{aaaaaaaa-0000-0000-0000-000000000003}'; ifIndex=30; Name='Offline'; Status='Disconnected'; NdisPhysicalMedium='802.3'; MediaType='802.3'; InterfaceDescription='Offline'; MacAddress='00-00-00-00-00-00' }
        )
        $profiles=@(
            [pscustomobject]@{ InterfaceIndex=10; NetworkCategory='Private'; Name='Home LAN' },
            [pscustomobject]@{ InterfaceIndex=20; NetworkCategory='Public'; Name='Cafe WiFi' }
        )
        $snapshot=@(Get-NrNetworkAdapterSnapshot -AdapterProvider { $adapters } -ProfileProvider { $profiles })
        $snapshot | Should -HaveCount 2
        ($snapshot | Where-Object interfaceIndex -eq 10).mediaType | Should -Be 'Ethernet'
        ($snapshot | Where-Object interfaceIndex -eq 10).networkCategory | Should -Be 'Private'
        ($snapshot | Where-Object interfaceIndex -eq 20).mediaType | Should -Be 'WiFi'
        ($snapshot | Where-Object interfaceIndex -eq 20).networkCategory | Should -Be 'Public'
    }

    It 'prefers stable-adapter and category matches over media fallbacks' {
        $adapter=[pscustomobject]@{ stableId='guid:adapter-1'; mediaType='Ethernet'; networkCategory='Public' }
        $profiles=@(
            [pscustomobject]@{ id='media-any'; stableAdapterId=''; mediaType='Ethernet'; networkCategory='Any'; enabled=$true },
            [pscustomobject]@{ id='media-public'; stableAdapterId=''; mediaType='Ethernet'; networkCategory='Public'; enabled=$true },
            [pscustomobject]@{ id='stable-any'; stableAdapterId='guid:adapter-1'; mediaType='Ethernet'; networkCategory='Any'; enabled=$true },
            [pscustomobject]@{ id='stable-public'; stableAdapterId='guid:adapter-1'; mediaType='Ethernet'; networkCategory='Public'; enabled=$true }
        )
        (Find-NrMatchingNetworkProfile -Adapter $adapter -Profiles $profiles).id | Should -Be 'stable-public'
    }

    It 'applies profiles once, survives restart, migrates category and records removal' {
        $fixture=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-network-profiles-'+[guid]::NewGuid().ToString('N'))
        $script:profileApplyCalls=New-Object 'System.Collections.Generic.List[string]'
        try {
            New-Item -ItemType Directory -Path $fixture -Force | Out-Null
            foreach ($profile in @(
                [pscustomobject][ordered]@{ id='ethernet-private'; stableAdapterId='guid:ethernet'; mediaType='Ethernet'; networkCategory='Private'; strategy='general'; dnsProvider='cloudflare'; dnsEncryption='doh'; servicePlan='home'; enabled=$true },
                [pscustomobject][ordered]@{ id='ethernet-public'; stableAdapterId='guid:ethernet'; mediaType='Ethernet'; networkCategory='Public'; strategy='general ALT'; dnsProvider='quad9'; dnsEncryption='dot'; servicePlan='public'; enabled=$true },
                [pscustomobject][ordered]@{ id='wifi-any'; stableAdapterId=''; mediaType='WiFi'; networkCategory='Any'; strategy='general'; dnsProvider='system'; dnsEncryption='system'; servicePlan='mobile'; enabled=$true }
            )) { Set-NrNetworkProfileDefinition -Root $fixture -Profile $profile | Out-Null }

            $ethernetPrivate=[pscustomobject]@{ stableId='guid:ethernet'; interfaceIndex=10; name='Ethernet'; mediaType='Ethernet'; networkCategory='Private'; networkName='Home'; status='Up' }
            $wifi=[pscustomobject]@{ stableId='guid:wifi'; interfaceIndex=20; name='Wi-Fi'; mediaType='WiFi'; networkCategory='Public'; networkName='Cafe'; status='Up' }
            $apply={ param($profile,$adapter,$root) $script:profileApplyCalls.Add($adapter.stableId+'='+$profile.id); return $true }

            $first=Invoke-NrNetworkProfileReconcile -Root $fixture -Snapshot @($ethernetPrivate,$wifi) -ApplyProfile $apply
            $first.applied | Should -Be 2
            $first.arrived | Should -Be 2
            $first.failed | Should -Be 0
            $script:profileApplyCalls | Should -HaveCount 2

            # Simulate a new process reading persisted state. The same snapshot must
            # not execute any configuration command again.
            $second=Invoke-NrNetworkProfileReconcile -Root $fixture -Snapshot @($ethernetPrivate,$wifi) -ApplyProfile $apply
            $second.applied | Should -Be 0
            $second.skipped | Should -Be 2
            $script:profileApplyCalls | Should -HaveCount 2

            $ethernetPublic=[pscustomobject]@{ stableId='guid:ethernet'; interfaceIndex=10; name='Ethernet'; mediaType='Ethernet'; networkCategory='Public'; networkName='Office guest'; status='Up' }
            $third=Invoke-NrNetworkProfileReconcile -Root $fixture -Snapshot @($ethernetPublic,$wifi) -ApplyProfile $apply
            $third.applied | Should -Be 1
            $third.skipped | Should -Be 1
            $script:profileApplyCalls[-1] | Should -Be 'guid:ethernet=ethernet-public'

            $fourth=Invoke-NrNetworkProfileReconcile -Root $fixture -Snapshot @($wifi) -ApplyProfile $apply
            $fourth.removed | Should -Be 1
            $fourth.skipped | Should -Be 1

            $state=Read-NrNetworkProfilesState -Root $fixture
            $state.schemaVersion | Should -Be 2
            @($state.previousActiveIds) | Should -Contain 'guid:wifi'
            @($state.previousActiveIds) | Should -Not -Contain 'guid:ethernet'
            $state.lastSnapshotFingerprint | Should -Match '^[0-9a-f]{64}$'

            $historyDirectory=Join-Path $fixture '.service/history/network-profiles'
            $history=@(Get-ChildItem -LiteralPath $historyDirectory -Filter '*.json' -File | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json })
            @($history | Where-Object action -eq 'applied').Count | Should -Be 3
            @($history | Where-Object action -eq 'unchanged').Count | Should -BeGreaterOrEqual 3
            @($history | Where-Object action -eq 'removed').Count | Should -Be 1
        } finally { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'backs up corrupt state instead of silently accepting it' {
        $fixture=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-network-corrupt-'+[guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path (Join-Path $fixture '.service') -Force | Out-Null
            $path=Get-NrNetworkProfilesStatePath -Root $fixture
            Set-Content -LiteralPath $path -Value '{broken' -Encoding UTF8
            $state=Read-NrNetworkProfilesState -Root $fixture
            $state.schemaVersion | Should -Be 2
            @(Get-ChildItem -LiteralPath (Split-Path -Parent $path) -Filter 'network-profiles-v2.json.invalid-*.json' -File) | Should -HaveCount 1
        } finally { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'uses Windows adapter events and startup reconciliation in the watcher' {
        $repositoryRoot=Split-Path -Parent $PSScriptRoot
        $source=Get-Content -LiteralPath (Join-Path $repositoryRoot 'overlay/.service/next/nexroute-network-profiles-v2.ps1') -Raw -Encoding UTF8
        foreach ($token in @('Register-CimIndicationEvent','__InstanceCreationEvent','__InstanceDeletionEvent','__InstanceModificationEvent','MSFT_NetAdapter','Invoke-NrNetworkProfileReconcile','Wait-Event','Unregister-Event')) {
            $source | Should -Match ([regex]::Escape($token))
        }
        $loader=Get-Content -LiteralPath (Join-Path $repositoryRoot 'overlay/.service/next/nexroute-runtime-extensions.ps1') -Raw -Encoding UTF8
        $loader | Should -Match ([regex]::Escape('nexroute-network-profiles-v2.ps1'))
    }
}
