Describe 'NexRoute 0.6.5 classic Strategy Lab' {
    BeforeAll {
        $root=Split-Path -Parent $PSScriptRoot
        $script:lab=Get-Content -LiteralPath (Join-Path $root 'overlay/.service/next/nexroute-strategy-lab-classic.ps1') -Raw -Encoding UTF8
        $script:loader=Get-Content -LiteralPath (Join-Path $root 'overlay/.service/next/nexroute-runtime-extensions.ps1') -Raw -Encoding UTF8
        $script:common=Get-Content -LiteralPath (Join-Path $root 'overlay/.service/next/nexroute-common.ps1') -Raw -Encoding UTF8
        $script:console=Get-Content -LiteralPath (Join-Path $root 'overlay/.service/nexroute-console.ps1') -Raw -Encoding UTF8
    }

    It 'loads the classic lab after Strategy Lab v2 so the 0.6.5 UI wins' {
        $script:loader | Should -Match ([regex]::Escape('nexroute-strategy-lab-classic.ps1'))
        $script:loader.IndexOf('nexroute-strategy-lab-classic.ps1') | Should -BeGreaterThan $script:loader.IndexOf('nexroute-strategy-lab-v2.ps1')
        $script:loader.IndexOf('nexroute-strategy-lab-classic.ps1') | Should -BeLessThan $script:loader.IndexOf('nexroute-workers.ps1')
    }

    It 'contains the expanded per-config probe set and repeated observations' {
        foreach ($token in @(
            'Show-NrLabPreflight065',
            'Test-NrLabDns065',
            'Test-NrTlsTransportReadiness',
            'Measure-NrHttpEndpoint',
            'Measure-NrPingMetrics',
            'Invoke-NrSafeStreamingProbe',
            'Invoke-NrSafeYoutubePlaybackProbe',
            'Test-NrLabDpiFreeze065',
            "-Protocol 'DNS'",
            "-Protocol 'TLS'",
            "-Protocol 'HTTPS'",
            "-Protocol 'ICMP'",
            "-Protocol 'STREAM'",
            "-Protocol 'HLS'",
            "-Protocol 'DPI'",
            'RepeatCount=3',
            'CloudflareWeb'
        )) { $script:lab | Should -Match ([regex]::Escape($token)) }
    }

    It 'shows live OK WARN FAIL progress and detailed config summaries' {
        foreach ($token in @('Write-NrLabProgress065','Write-NrLabCheck065',"'OK'","'WARN'","'FAIL'","'SKIP'",'passedChecks','failedChecks','warningChecks','elapsedMs','CONFIG SUMMARY','RECOMMENDATION')) {
            $script:lab | Should -Match ([regex]::Escape($token))
        }
    }

    It 'supports all configs or selected configs and restores the original strategy' {
        foreach ($token in @('labRunAll','labRunSelected','Invoke-NrMultiSelect','Get-NrInstalledStrategy','Install-NrStrategy -Strategy $restore -Silent','Strategy Lab restored original strategy')) {
            ($script:lab + $script:common) | Should -Match ([regex]::Escape($token))
        }
        $script:console | Should -Match ([regex]::Escape("'lab' { Invoke-NrStrategyLab }"))
    }

    It 'keeps explainable ranking and stores schema 4 JSON plus CSV history' {
        foreach ($token in @('Get-NrStrategyRanking064','rankingModel','critical-services-stability-v1','schemaVersion=4',"interface='classic-0.2.2'",'ConvertTo-Json -Depth 35','Export-Csv','inconclusiveReason','recommendationReason')) {
            $script:lab | Should -Match ([regex]::Escape($token))
        }
    }

    It 'uses the requested black red green warning visual contract' {
        foreach ($token in @('BackgroundColor = [ConsoleColor]::Black',"accent = 'Red'",'[ConsoleColor]::Green','[ConsoleColor]::Yellow','[ConsoleColor]::Red','███╗░░██╗███████╗')) {
            $script:common | Should -Match ([regex]::Escape($token))
        }
    }
}
