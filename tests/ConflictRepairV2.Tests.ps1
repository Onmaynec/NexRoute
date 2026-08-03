Describe 'NexRoute 0.6.0 evidence-based conflict repair wizard' {
    BeforeAll {
        $repositoryRoot=Split-Path -Parent $PSScriptRoot
        . (Join-Path $repositoryRoot 'overlay/.service/next/nexroute-repair-v2.ps1')
    }

    It 'distinguishes recognized security products from unknown products without claiming compatibility' {
        $products=@(
            [pscustomobject]@{ displayName='Microsoft Defender Antivirus'; productState=397568; pathToSignedProductExe='C:\Program Files\Windows Defender\MsMpEng.exe' },
            [pscustomobject]@{ displayName='Mystery Shield 9000'; productState=1; pathToSignedProductExe='C:\Mystery\shield.exe' }
        )
        $findings=@(Get-NrEvidenceConflictReport -ServiceProvider { @() } -AdapterProvider { @() } -RouteProvider { @() } -FirewallRuleProvider { @() } -AntivirusProvider { $products } -DriverProvider { @() })
        $findings | Should -HaveCount 2
        ($findings | Where-Object product -eq 'Microsoft Defender Antivirus').compatibility | Should -Be 'recognized-unverified'
        ($findings | Where-Object product -eq 'Microsoft Defender Antivirus').repairAction | Should -Be 'defender-path-exclusion'
        ($findings | Where-Object product -eq 'Mystery Shield 9000').compatibility | Should -Be 'UNKNOWN'
        ($findings | Where-Object product -eq 'Mystery Shield 9000').repairAction | Should -BeNullOrEmpty
        @($findings | Where-Object compatibility -match '(?i)compatible').Count | Should -Be 0
    }

    It 'reports VPN default-route, blocking firewall and parallel WinDivert evidence separately' {
        $adapters=@([pscustomobject]@{ ifIndex=44; Name='WireGuard Tunnel'; InterfaceDescription='WireGuard'; MediaType='Tunnel' })
        $routes=@([pscustomobject]@{ DestinationPrefix='0.0.0.0/0'; InterfaceIndex=44; RouteMetric=5 })
        $rules=@([pscustomobject]@{ Name='BlockWinws'; DisplayName='Block winws'; Action='Block'; Enabled='True'; Program='C:\NexRoute\bin\winws.exe'; Service=''; Description='Security policy' })
        $services=@(
            [pscustomobject]@{ Name='WinDivert'; DisplayName='WinDivert'; State='Running'; StartMode='Auto'; PathName='C:\NexRoute\WinDivert64.sys' },
            [pscustomobject]@{ Name='WinDivert14'; DisplayName='Other WinDivert'; State='Running'; StartMode='Auto'; PathName='C:\Other\WinDivert64.sys' }
        )
        $findings=@(Get-NrEvidenceConflictReport -ServiceProvider { $services } -AdapterProvider { $adapters } -RouteProvider { $routes } -FirewallRuleProvider { $rules } -AntivirusProvider { @() } -DriverProvider { @() })
        @($findings | Where-Object category -eq 'VPN') | Should -HaveCount 1
        @($findings | Where-Object category -eq 'FIREWALL') | Should -HaveCount 1
        @($findings | Where-Object category -eq 'WINDIVERT') | Should -HaveCount 2
        ($findings | Where-Object category -eq 'VPN').evidence | Should -Contain 'InterfaceIndex=44'
        ($findings | Where-Object category -eq 'FIREWALL').reversible | Should -BeTrue
        @($findings | Where-Object category -eq 'WINDIVERT' | ForEach-Object { $_.evidence -join ';' }) -join '|' | Should -Match 'RunningWinDivertServices=2'
    }

    It 'writes the backup before apply and commits only after verification' {
        $fixture=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-repair-commit-'+[guid]::NewGuid().ToString('N'))
        $script:order=New-Object 'System.Collections.Generic.List[string]'
        try {
            New-Item -ItemType Directory -Path $fixture -Force | Out-Null
            $result=Invoke-NrRepairTransaction -Root $fixture -Action 'fixture' -Target 'target' `
                -Snapshot { $script:order.Add('snapshot'); [pscustomobject]@{ value='before' } } `
                -Apply { param($snapshot) (Test-Path -LiteralPath (Join-Path $fixture '.service/backups/repairs') -PathType Container) | Should -BeTrue; $script:order.Add('apply') } `
                -Verify { param($snapshot) $script:order.Add('verify'); [pscustomobject]@{ ok=$true; detail='confirmed' } } `
                -Rollback { param($snapshot) $script:order.Add('rollback') }
            $result.success | Should -BeTrue
            $result.state | Should -Be 'committed'
            $result.rolledBack | Should -BeFalse
            $script:order -join ',' | Should -Be 'snapshot,apply,verify'
            Test-Path -LiteralPath $result.backupPath -PathType Leaf | Should -BeTrue
            $transaction=Get-Content -LiteralPath $result.transactionPath -Raw | ConvertFrom-Json
            $transaction.state | Should -Be 'committed'
            $transaction.verification.detail | Should -Be 'confirmed'
        } finally { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'rolls back the exact snapshot when verification fails' {
        $fixture=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-repair-rollback-'+[guid]::NewGuid().ToString('N'))
        $script:restored=$null
        try {
            New-Item -ItemType Directory -Path $fixture -Force | Out-Null
            $result=Invoke-NrRepairTransaction -Root $fixture -Action 'fixture-fail' -Target 'target' `
                -Snapshot { [pscustomobject]@{ value='original'; metric=17 } } `
                -Apply { param($snapshot) } `
                -Verify { param($snapshot) $false } `
                -Rollback { param($snapshot) $script:restored=$snapshot }
            $result.success | Should -BeFalse
            $result.state | Should -Be 'rolled-back'
            $result.rolledBack | Should -BeTrue
            $script:restored.value | Should -Be 'original'
            $script:restored.metric | Should -Be 17
            (Get-Content -LiteralPath $result.transactionPath -Raw | ConvertFrom-Json).state | Should -Be 'rolled-back'
        } finally { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'restores a firewall blocking rule after a failed repair verification' {
        $fixture=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-firewall-repair-'+[guid]::NewGuid().ToString('N'))
        $script:ruleEnabled=$true
        try {
            $result=Invoke-NrFirewallRuleRepair -Root $fixture -RuleName 'BlockWinws' `
                -GetRule { [pscustomobject]@{ Name='BlockWinws'; Enabled=$script:ruleEnabled } } `
                -DisableRule { param($snapshot) $script:ruleEnabled=$false } `
                -EnableRule { param($snapshot) $script:ruleEnabled=[bool]$snapshot.Enabled } `
                -VerifyRule { param($snapshot) $false }
            $result.state | Should -Be 'rolled-back'
            $script:ruleEnabled | Should -BeTrue
        } finally { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'restores VPN metrics for every address family after failure' {
        $fixture=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-vpn-repair-'+[guid]::NewGuid().ToString('N'))
        $script:metrics=@{ IPv4=10; IPv6=20 }
        try {
            $result=Invoke-NrVpnMetricRepair -Root $fixture -InterfaceIndex 44 -TemporaryMetric 5000 `
                -GetMetric { @([pscustomobject]@{ InterfaceIndex=44; AddressFamily='IPv4'; InterfaceMetric=10 },[pscustomobject]@{ InterfaceIndex=44; AddressFamily='IPv6'; InterfaceMetric=20 }) } `
                -SetMetric { param($snapshot,$metric) foreach ($entry in @($snapshot)) { $script:metrics[[string]$entry.AddressFamily]=[int]$metric } } `
                -VerifyMetric { param($snapshot,$metric) $false }
            $result.state | Should -Be 'rolled-back'
            $script:metrics.IPv4 | Should -Be 10
            $script:metrics.IPv6 | Should -Be 20
        } finally { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'restores WinDivert service status and startup mode after failure' {
        $fixture=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-windivert-repair-'+[guid]::NewGuid().ToString('N'))
        $script:serviceState=[ordered]@{ State='Running'; StartMode='Auto' }
        try {
            $result=Invoke-NrWinDivertServiceRepair -Root $fixture -ServiceName 'WinDivert14' `
                -GetServiceState { [pscustomobject]@{ Name='WinDivert14'; State=$script:serviceState.State; StartMode=$script:serviceState.StartMode } } `
                -StopServiceAction { param($snapshot) $script:serviceState.State='Stopped'; $script:serviceState.StartMode='Manual' } `
                -RestoreServiceAction { param($snapshot) $script:serviceState.State=[string]$snapshot.State; $script:serviceState.StartMode=[string]$snapshot.StartMode } `
                -VerifyService { param($snapshot) $false }
            $result.state | Should -Be 'rolled-back'
            $script:serviceState.State | Should -Be 'Running'
            $script:serviceState.StartMode | Should -Be 'Auto'
        } finally { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'restores dual-stack DNS addresses after a failed reset' {
        $fixture=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-dns-repair-'+[guid]::NewGuid().ToString('N'))
        $script:dns=@('1.1.1.1','2606:4700:4700::1111')
        try {
            $result=Invoke-NrDnsResetRepair -Root $fixture -InterfaceAlias 'Ethernet' `
                -GetDnsState { @([pscustomobject]@{ AddressFamily='IPv4'; ServerAddresses=@('1.1.1.1') },[pscustomobject]@{ AddressFamily='IPv6'; ServerAddresses=@('2606:4700:4700::1111') }) } `
                -ResetDns { param($snapshot) $script:dns=@() } `
                -RestoreDns { param($snapshot) $script:dns=@($snapshot | ForEach-Object { @($_.ServerAddresses) }) } `
                -VerifyDns { param($snapshot) $false }
            $result.state | Should -Be 'rolled-back'
            $script:dns | Should -Contain '1.1.1.1'
            $script:dns | Should -Contain '2606:4700:4700::1111'
        } finally { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'removes only the Defender exclusion created by the transaction during rollback' {
        $fixture=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-defender-repair-'+[guid]::NewGuid().ToString('N'))
        $install=Join-Path $fixture 'NexRoute'
        $script:exclusions=@('C:\Existing')
        try {
            New-Item -ItemType Directory -Path $install -Force | Out-Null
            $result=Invoke-NrDefenderExclusionRepair -Root $fixture -InstallRoot $install `
                -GetExclusions { @($script:exclusions) } `
                -AddExclusion { param($snapshot) $script:exclusions+=([IO.Path]::GetFullPath($install).TrimEnd([char[]]@('\','/'))) } `
                -RemoveExclusion { param($snapshot) $created=[IO.Path]::GetFullPath($install).TrimEnd([char[]]@('\','/')); $script:exclusions=@($script:exclusions | Where-Object { $_ -ne $created }) } `
                -VerifyExclusion { param($snapshot) $false }
            $result.state | Should -Be 'rolled-back'
            $script:exclusions | Should -Contain 'C:\Existing'
            $script:exclusions | Should -Not -Contain ([IO.Path]::GetFullPath($install).TrimEnd([char[]]@('\','/')))
        } finally { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'loads the repair wizard after diagnostics and network overrides' {
        $repositoryRoot=Split-Path -Parent $PSScriptRoot
        $loader=Get-Content -LiteralPath (Join-Path $repositoryRoot 'overlay/.service/next/nexroute-runtime-extensions.ps1') -Raw -Encoding UTF8
        $loader | Should -Match ([regex]::Escape('nexroute-repair-v2.ps1'))
        $loader.IndexOf('nexroute-repair-v2.ps1') | Should -BeGreaterThan $loader.IndexOf('nexroute-network-profiles-v2-fixes.ps1')
        $source=Get-Content -LiteralPath (Join-Path $repositoryRoot 'overlay/.service/next/nexroute-repair-v2.ps1') -Raw -Encoding UTF8
        foreach ($token in @('Show-NrRepairWizard','Invoke-NrRepairTransaction','New-NrRepairBackup','rolled-back','rollback-failed','UNKNOWN','defender-path-exclusion')) {
            $source | Should -Match ([regex]::Escape($token))
        }
    }
}
