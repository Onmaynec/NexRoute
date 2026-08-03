Describe 'NexRoute 0.6.0 signed validation report' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent $PSScriptRoot
        $scriptPath = Join-Path $repositoryRoot 'scripts/New-ValidationReport.ps1'
        . $scriptPath -NoMain
        $script:validDigest = ('a' * 64)
    }

    It 'writes machine-readable and human-readable reports with release provenance' {
        $output = Join-Path $TestDrive 'report'
        $report = New-NrValidationReportDocument `
            -Version '0.6.0' `
            -PackageSha256 $script:validDigest `
            -UpstreamSha256 ('b' * 64) `
            -PatchTargetCount 23 `
            -StrategyCount 21 `
            -ServiceCount 15 `
            -NativeTrayIncluded $true `
            -NativeTrayExitCode 0 `
            -NativeDashboardIncluded $true `
            -NativeDashboardExitCode 0 `
            -NativeDashboardSha256 ('c' * 64) `
            -NativeValidationIncluded $true `
            -NativeValidationExitCode 0 `
            -NativeValidationSha256 ('d' * 64) `
            -PortableAttestationVerifierIncluded $true `
            -DotResolverIncluded $true `
            -Ipv6RuntimeStatus experimental

        $result = Write-NrValidationReport -Report $report -OutputDirectory $output
        $result.OverallStatus | Should -Be 'passed-with-limitations'
        Test-Path -LiteralPath $result.JsonPath -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $result.MarkdownPath -PathType Leaf | Should -BeTrue
        $result.JsonSha256 | Should -Match '^[0-9a-f]{64}$'
        $result.MarkdownSha256 | Should -Match '^[0-9a-f]{64}$'

        $json = Get-Content -LiteralPath $result.JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $json.schemaVersion | Should -Be 1
        $json.product | Should -Be 'NexRoute'
        $json.version | Should -Be '0.6.0'
        $json.release.patchTargetCount | Should -Be 23
        @($json.checks | Where-Object id -eq 'native-tray.self-test').status | Should -Be 'passed'
        @($json.checks | Where-Object id -eq 'native-dashboard.self-test').status | Should -Be 'passed'
        @($json.checks | Where-Object id -eq 'native-validation.self-test').status | Should -Be 'passed'
        $json.release.nativeDashboardSha256 | Should -Be ('c' * 64)
        $json.release.nativeValidationSha256 | Should -Be ('d' * 64)

        $markdown = Get-Content -LiteralPath $result.MarkdownPath -Raw -Encoding UTF8
        $markdown | Should -Match 'passed-with-limitations'
        $markdown | Should -Match 'Native validation viewer SHA-256'
        $markdown | Should -Match 'Experimental and unsupported rows are explicit limitations'
    }

    It 'never converts unavailable hardware validation into a false success' {
        $report = New-NrValidationReportDocument `
            -Version '0.6.0' `
            -PackageSha256 $script:validDigest `
            -UpstreamSha256 ('b' * 64) `
            -PatchTargetCount 23 `
            -StrategyCount 21 `
            -ServiceCount 15 `
            -NativeTrayIncluded $true `
            -NativeTrayExitCode 0 `
            -NativeDashboardIncluded $true `
            -NativeDashboardExitCode 0 `
            -NativeDashboardSha256 ('c' * 64) `
            -NativeValidationIncluded $true `
            -NativeValidationExitCode 0 `
            -NativeValidationSha256 ('d' * 64) `
            -PortableAttestationVerifierIncluded $true `
            -DotResolverIncluded $true `
            -Ipv6RuntimeStatus unsupported

        @($report.checks | Where-Object id -eq 'native-tray.interactive').status | Should -Be 'experimental'
        @($report.checks | Where-Object id -eq 'native-dashboard.interactive').status | Should -Be 'experimental'
        @($report.checks | Where-Object id -eq 'runtime.ipv4-live').status | Should -Be 'experimental'
        @($report.checks | Where-Object id -eq 'runtime.ipv6-live').status | Should -Be 'unsupported'
        @($report.checks | Where-Object id -eq 'native-validation.self-test').status | Should -Be 'passed'
        $report.overallStatus | Should -Be 'passed-with-limitations'
    }

    It 'fails the release gate when required package evidence is missing' {
        $report = New-NrValidationReportDocument `
            -Version '0.6.0' `
            -PackageSha256 'invalid' `
            -UpstreamSha256 ('b' * 64) `
            -PatchTargetCount 22 `
            -StrategyCount 0 `
            -ServiceCount 0 `
            -NativeTrayIncluded $false `
            -NativeTrayExitCode 1 `
            -NativeDashboardIncluded $false `
            -NativeDashboardExitCode 1 `
            -NativeDashboardSha256 'invalid' `
            -NativeValidationIncluded $false `
            -NativeValidationExitCode 1 `
            -NativeValidationSha256 'invalid' `
            -PortableAttestationVerifierIncluded $false `
            -DotResolverIncluded $false

        $report.overallStatus | Should -Be 'failed'
        @($report.checks | Where-Object { $_.required -and $_.status -eq 'failed' }).Count | Should -BeGreaterThan 0
        @($report.checks | Where-Object id -eq 'native-validation.self-test').status | Should -Be 'failed'
    }

    It 'attests verifies uploads and publishes both validation report formats' {
        $repositoryRoot = Split-Path -Parent $PSScriptRoot
        $workflow = Get-Content -LiteralPath (Join-Path $repositoryRoot '.github/workflows/release.yml') -Raw -Encoding UTF8
        foreach ($token in @(
            'Generate hardware and OS validation report',
            'New-ValidationReport.ps1',
            'Test-V06Desktop.ps1',
            'NEXROUTE_DASHBOARD_SELF_TEST_EXIT_CODE',
            'NEXROUTE_VALIDATION_VIEWER_SELF_TEST_EXIT_CODE',
            'NexRoute-${{ steps.version.outputs.version }}-validation.json',
            'NexRoute-${{ steps.version.outputs.version }}-validation.md',
            'actions/attest@v4',
            'gh attestation verify'
        )) {
            $workflow | Should -Match ([regex]::Escape($token))
        }

        $jsonAsset = [regex]::Escape('"./artifacts/NexRoute-${{ steps.version.outputs.version }}-validation.json"')
        $markdownAsset = [regex]::Escape('"./artifacts/NexRoute-${{ steps.version.outputs.version }}-validation.md"')
        $workflow | Should -Match $jsonAsset
        $workflow | Should -Match $markdownAsset
    }
}
