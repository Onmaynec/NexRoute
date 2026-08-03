Describe 'NexRoute 0.6.0 release coherence' {
    BeforeAll {
        $root=Split-Path -Parent $PSScriptRoot
        $script:version=(Get-Content -LiteralPath (Join-Path $root '.service/version.txt') -Raw -Encoding UTF8).Trim()
        $script:readme=Get-Content -LiteralPath (Join-Path $root 'README.md') -Raw -Encoding UTF8
        $script:changelog=Get-Content -LiteralPath (Join-Path $root 'CHANGELOG.md') -Raw -Encoding UTF8
        $script:releaseNotes=Get-Content -LiteralPath (Join-Path $root '.github/release-notes/v0.6.0.md') -Raw -Encoding UTF8
        $script:websitePackage=Get-Content -LiteralPath (Join-Path $root 'website/package.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $script:validateWorkflow=Get-Content -LiteralPath (Join-Path $root '.github/workflows/validate.yml') -Raw -Encoding UTF8
        $script:releaseWorkflow=Get-Content -LiteralPath (Join-Path $root '.github/workflows/release.yml') -Raw -Encoding UTF8
        $script:pagesWorkflow=Get-Content -LiteralPath (Join-Path $root '.github/workflows/pages.yml') -Raw -Encoding UTF8
    }

    It 'uses 0.6.0 as the canonical package and website version' {
        $script:version | Should -Be '0.6.0'
        [string]$script:websitePackage.version | Should -Be $script:version
        $script:readme | Should -Match ([regex]::Escape('NexRoute 0.6.0'))
        $script:changelog | Should -Match ([regex]::Escape('## [0.6.0] - 2026-08-03'))
        $script:releaseNotes | Should -Match ([regex]::Escape('# NexRoute 0.6.0'))
    }

    It 'uses 0.6.0 package names and job labels in the validation workflow' {
        foreach ($token in @(
            'Validate NexRoute 0.6.0 sources',
            'Build and test NexRoute 0.6.0',
            "if (`$version -ne '0.6.0')",
            'NexRoute-0.6.0-smoke',
            'artifacts/NexRoute-0.6.0-win-x64.zip',
            'artifacts/NexRoute-0.6.0-win-x64.zip.sha256'
        )) {
            $script:validateWorkflow | Should -Match ([regex]::Escape($token))
        }
        $script:validateWorkflow | Should -Not -Match 'NexRoute-0\.5\.0-win-x64|Expected 0\.5\.0|Validate NexRoute 0\.5\.0|Build and test NexRoute 0\.5\.0'
    }

    It 'uses Node 24 action majors across validate release and Pages workflows' {
        foreach ($workflow in @($script:validateWorkflow,$script:releaseWorkflow,$script:pagesWorkflow)) {
            $workflow | Should -Match 'uses: actions/checkout@v6'
            $workflow | Should -Not -Match 'uses: actions/checkout@v4'
        }
        $script:validateWorkflow | Should -Match 'uses: actions/setup-node@v6'
        $script:validateWorkflow | Should -Match 'uses: actions/upload-artifact@v7'
        $script:releaseWorkflow | Should -Match 'uses: actions/upload-artifact@v7'
        $script:pagesWorkflow | Should -Match 'uses: actions/setup-node@v6'
        $script:pagesWorkflow | Should -Match 'uses: actions/upload-pages-artifact@v5'
        ($script:validateWorkflow+$script:releaseWorkflow+$script:pagesWorkflow) | Should -Not -Match 'actions/setup-node@v4|actions/upload-artifact@v4|actions/upload-pages-artifact@v4'
    }

    It 'documents and verifies the four-subject release trust flow' {
        foreach ($token in @(
            'NexRoute-0.6.0-win-x64.zip',
            'NexRoute-0.6.0-win-x64.zip.sha256',
            'NexRoute-0.6.0-validation.json',
            'NexRoute-0.6.0-validation.md',
            'nexroute-validation.cmd',
            'attestation-not-verified',
            'attestation-receipt-matched'
        )) {
            $script:readme | Should -Match ([regex]::Escape($token))
        }
        foreach ($token in @(
            'NotificationToastChannel',
            'NotificationFallbackChannel',
            'actions/attest@v4',
            'gh attestation verify',
            'NexRoute-${{ steps.version.outputs.version }}-validation.json',
            'NexRoute-${{ steps.version.outputs.version }}-validation.md'
        )) {
            $script:releaseWorkflow | Should -Match ([regex]::Escape($token))
        }
    }
}
