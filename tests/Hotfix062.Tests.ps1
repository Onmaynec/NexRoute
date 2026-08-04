Describe 'NexRoute 0.6.2 first-run and updater hotfix' {
    BeforeAll {
        $root=Split-Path -Parent $PSScriptRoot
        $script:hotfixPath=Join-Path $root 'overlay/.service/next/nexroute-hotfix-062.ps1'
        $script:hotfix=Get-Content -LiteralPath $script:hotfixPath -Raw -Encoding UTF8
        $script:loader=Get-Content -LiteralPath (Join-Path $root 'overlay/.service/next/nexroute-runtime-extensions.ps1') -Raw -Encoding UTF8
        $script:console=Get-Content -LiteralPath (Join-Path $root 'overlay/.service/nexroute-console.ps1') -Raw -Encoding UTF8
        $script:diagnosticFixes=Get-Content -LiteralPath (Join-Path $root 'overlay/.service/next/nexroute-diagnostics-fixes.ps1') -Raw -Encoding UTF8
        $script:updaterEntry=Get-Content -LiteralPath (Join-Path $root 'overlay/.service/nexroute-updater-entry.ps1') -Raw -Encoding UTF8
        $script:launcherSmoke=Get-Content -LiteralPath (Join-Path $root 'scripts/Test-WindowsLaunchers.ps1') -Raw -Encoding UTF8
    }

    It 'loads the 0.6.2 compatibility layer after diagnostic fixes' {
        $fixIndex=$script:loader.IndexOf("'nexroute-diagnostics-fixes.ps1'",[StringComparison]::Ordinal)
        $hotfixIndex=$script:loader.IndexOf("'nexroute-hotfix-062.ps1'",[StringComparison]::Ordinal)
        $fixIndex | Should -BeGreaterThanOrEqual 0
        $hotfixIndex | Should -BeGreaterThan $fixIndex
    }

    It 'adapts schemaVersion 3 diagnostics for the first-run console contract' {
        $module=New-Module -ArgumentList $script:hotfixPath -ScriptBlock {
            param($path)
            function Initialize-NrEnvironment { param([string]$RootPath) }
            function Get-NrDiagnosticReport {
                return [ordered]@{
                    schemaVersion=3
                    nexroute=[ordered]@{
                        serviceRunning=$true
                        winDivertRunning=$false
                        winwsRunning=$true
                        networkKey='wifi-public'
                    }
                    windows=[ordered]@{ elevated=$true }
                    conflicts=@(
                        [pscustomobject]@{ severity='warning'; name='vpn' },
                        [pscustomobject]@{ severity='info'; name='firewall' }
                    )
                }
            }
            . $path
            Export-ModuleMember -Function Get-NrDiagnosticReport
        }
        try {
            $report=& $module { Get-NrDiagnosticReport }
            $report.administrator | Should -BeTrue
            $report.runtime.zapret | Should -BeTrue
            $report.runtime.winDivert | Should -BeFalse
            $report.runtime.winws | Should -BeTrue
            $report.network | Should -Be 'wifi-public'
            @($report.conflicts | Where-Object { $_.detected }).Count | Should -Be 1
        } finally {
            Remove-Module $module -Force -ErrorAction SilentlyContinue
        }
    }

    It 'covers every legacy property read by Invoke-NrFirstRun' {
        foreach ($token in @('$report.administrator','$report.runtime.zapret','$report.network','$_.detected')) {
            $script:console | Should -Match ([regex]::Escape($token))
        }
        foreach ($token in @("['administrator']","['runtime']","['network']",'detected')) {
            $script:hotfix | Should -Match ([regex]::Escape($token))
        }
    }

    It 'updates the console title from the packaged version instead of the 0.5.0 constant' {
        $script:hotfix | Should -Match ([regex]::Escape("Join-Path `$script:NrService 'version.txt'"))
        $script:hotfix | Should -Match ([regex]::Escape('[Console]::Title = "NexRoute $version"'))
    }

    It 'routes interactive update checks through the secure updater entry wrapper' {
        $script:diagnosticFixes | Should -Match ([regex]::Escape("Join-Path `$script:NrService 'nexroute-updater-entry.ps1'"))
        $script:diagnosticFixes | Should -Not -Match "Get-NrUpdaterPath[\s\S]*Join-Path \$script:NrService 'nexroute-updater\.ps1'"
    }

    It 'resolves stable releases without falling back to the rate-limited GitHub API' {
        foreach ($token in @(
            'NEXROUTE_LATEST_RELEASE_FIXTURE',
            'Invoke-WebRequest',
            'HttpWebRequest',
            'curl.exe',
            'New-NrFallbackReleaseMetadata',
            'Unable to resolve the latest stable NexRoute release without the GitHub API'
        )) {
            $script:updaterEntry | Should -Match ([regex]::Escape($token))
        }
        $script:updaterEntry | Should -Not -Match 'api\.github\.com'
        $script:updaterEntry | Should -Not -Match 'effectiveMetadata\s*=\s*\$null'
    }

    It 'requires package smoke evidence for first-run diagnostics and API-free update checks' {
        foreach ($token in @(
            'NEXROUTE_LATEST_RELEASE_FIXTURE',
            'diagnosticCompatibility',
            'administrator',
            'runtime',
            'nexroute-update.cmd'
        )) {
            $script:launcherSmoke | Should -Match ([regex]::Escape($token))
        }
    }
}
