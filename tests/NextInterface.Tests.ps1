Describe 'NexRoute 0.5.0 arrow-key control node' {
    BeforeAll {
        $root=Split-Path -Parent $PSScriptRoot
        $common=Get-Content -LiteralPath (Join-Path $root 'overlay/.service/next/nexroute-common.ps1') -Raw
        $console=Get-Content -LiteralPath (Join-Path $root 'overlay/.service/nexroute-console.ps1') -Raw
        $update=Get-Content -LiteralPath (Join-Path $root 'overlay/.service/next/nexroute-update.ps1') -Raw
        $monitor=Get-Content -LiteralPath (Join-Path $root 'overlay/.service/nexroute-monitor.ps1') -Raw
        $network=Get-Content -LiteralPath (Join-Path $root 'overlay/.service/next/nexroute-network.ps1') -Raw
        $management=Get-Content -LiteralPath (Join-Path $root 'overlay/.service/next/nexroute-management.ps1') -Raw
        $strategy=Get-Content -LiteralPath (Join-Path $root 'overlay/.service/next/nexroute-strategies.ps1') -Raw
        $serviceNetwork=Get-Content -LiteralPath (Join-Path $root 'overlay/.service/i18n/nexroute-services-network.ps1') -Raw
        $serviceState=Get-Content -LiteralPath (Join-Path $root 'overlay/.service/i18n/nexroute-services-state.ps1') -Raw
    }

    It 'renders [+] actions and reads arrow keys instead of numeric menu input' {
        $common | Should -Match ([regex]::Escape("'>[+]'"))
        $common | Should -Match "'UpArrow'"
        $common | Should -Match "'DownArrow'"
        $common | Should -Match "'Enter'"
        $console | Should -Not -Match '\[10\]\s+RELEASE CHANNEL'
        $console | Should -Not -Match 'TryParse\(.+menu'
    }

    It 'contains the fully renamed English and Russian main menu' {
        foreach ($token in @('Installing Config','Deleting Config','System Status','Game Traffic Filter','Filter IPSET','Auto-Check Update','Fake Payload VAULT','Update IPSET','Update HOSTS','Check Update','Bypassing Services / SERVICE MATRIX','Diagnostic Core','Checking Config','Switch Language','Disconnect / Exit','Установка конфигурации','Проверить обновление','Сменить язык')) {
            $common | Should -Match ([regex]::Escape($token))
        }
    }

    It 'requires Y confirmation and performs an install-and-restart update flow' {
        $update | Should -Match 'Confirm-NrY'
        $update | Should -Match "-Mode Install"
        $update | Should -Match 'PackageSha256'
        $update | Should -Match 'Invoke-NrPostUpdateHealthCheck'
        $update | Should -Match 'Start-Process.+nexroute\.bat'
        $update | Should -Match 'gh.+attestation verify'
    }

    It 'implements strategy scoring history recommendations and failover' {
        foreach ($token in @('Invoke-NrStrategyLab','score','jitterMs','packetLossPercent','megabitsPerSecond','Install-NrBestStrategy','Show-NrLabHistory','Apply-NrPerServiceStrategies','automatic-failover')) {
            ($strategy + $monitor) | Should -Match ([regex]::Escape($token))
        }
    }

    It 'implements monitoring tray notifications logs backups and statistics' {
        foreach ($token in @('monitor-state.json','availability.jsonl','restartLimitPerHour','Send-NrNotification','NexRoute Tray Controller','New-NrManualBackup','Restore-NrBackup','Export-NrConfiguration','Export-NrStatistics','nexroute.jsonl')) {
            ($common + $monitor + $management) | Should -Match ([regex]::Escape($token))
        }
    }

    It 'implements DNS encryption network profiles and full IPv6 CIDR handling' {
        foreach ($token in @('DNS-over-HTTPS','DNS-over-TLS','netsh','networkProfiles','Test-NrIpv6Readiness','ConvertTo-ValidatedIpCidr','InterNetworkV6','Resolve-DnsName -Name $hostName -Type AAAA')) {
            ($common + $network + $serviceNetwork) | Should -Match ([regex]::Escape($token))
        }
    }

    It 'merges custom service profiles without replacing built-in definitions' {
        $serviceState | Should -Match 'custom-services\.json'
        $serviceState | Should -Match 'Duplicate service id across built-in and custom profiles'
    }
}
