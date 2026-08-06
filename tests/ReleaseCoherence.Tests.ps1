Describe 'NexRoute 0.6.3 release coherence' {
    BeforeAll {
        $root=Split-Path -Parent $PSScriptRoot
        $script:version=(Get-Content -LiteralPath (Join-Path $root '.service/version.txt') -Raw -Encoding UTF8).Trim()
        $script:releaseNotes=Get-Content -LiteralPath (Join-Path $root '.github/release-notes/v0.6.3.md') -Raw -Encoding UTF8
        $script:acceptance=Get-Content -LiteralPath (Join-Path $root 'docs/RELEASE_0.6.3_ACCEPTANCE.md') -Raw -Encoding UTF8
        $script:websitePackage=Get-Content -LiteralPath (Join-Path $root 'website/package.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $script:websiteLock=Get-Content -LiteralPath (Join-Path $root 'website/package-lock.json') -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable
        $script:validateWorkflow=Get-Content -LiteralPath (Join-Path $root '.github/workflows/validate.yml') -Raw -Encoding UTF8
        $script:releaseWorkflow=Get-Content -LiteralPath (Join-Path $root '.github/workflows/release.yml') -Raw -Encoding UTF8
        $script:pagesWorkflow=Get-Content -LiteralPath (Join-Path $root '.github/workflows/pages.yml') -Raw -Encoding UTF8
        $script:launcherSmoke=Get-Content -LiteralPath (Join-Path $root 'scripts/Test-WindowsLaunchers.ps1') -Raw -Encoding UTF8
        $script:updaterEntry=Get-Content -LiteralPath (Join-Path $root 'overlay/.service/nexroute-updater-entry.ps1') -Raw -Encoding UTF8
        $script:refresh=Get-Content -LiteralPath (Join-Path $root 'overlay/.service/next/nexroute-strategy-refresh.ps1') -Raw -Encoding UTF8
        $script:evidence=Get-Content -LiteralPath (Join-Path $root 'scripts/Test-StrategyLab063Evidence.ps1') -Raw -Encoding UTF8
    }

    It 'uses 0.6.3 as the canonical package and website version' {
        $script:version | Should -Be '0.6.3'
        [string]$script:websitePackage.version | Should -Be $script:version
        [string]$script:websiteLock['version'] | Should -Be $script:version
        [string]$script:websiteLock['packages']['']['version'] | Should -Be $script:version
        $script:releaseNotes | Should -Match ([regex]::Escape('# NexRoute 0.6.3 — Discord and YouTube strategy refresh'))
        $script:acceptance | Should -Match ([regex]::Escape('NexRoute 0.6.3 release acceptance'))
    }

    It 'uses 0.6.3 package names and job labels in the validation workflow' {
        foreach ($token in @(
            'Validate NexRoute 0.6.3 sources',
            'Build and test NexRoute 0.6.3',
            "if (`$version -ne '0.6.3')",
            'NexRoute-0.6.3-smoke',
            'artifacts/NexRoute-0.6.3-win-x64.zip',
            'artifacts/NexRoute-0.6.3-win-x64.zip.sha256'
        )) {
            $script:validateWorkflow | Should -Match ([regex]::Escape($token))
        }
    }

    It 'executes the launcher and first-run compatibility contract for online and offline packages' {
        ($script:validateWorkflow | Select-String -Pattern 'Test-WindowsLaunchers\.ps1' -AllMatches).Matches.Count | Should -Be 2
        foreach ($token in @(
            'NexRoute 0.6.3 Strategy Refresh Тест',
            'service.bat',
            'nexroute.bat',
            'nexroute-update.cmd',
            'diagnosticCompatibility',
            'NEXROUTE_LATEST_RELEASE_FIXTURE',
            'updaterFallbackVersion',
            'PropertyNotFound'
        )) {
            $script:launcherSmoke | Should -Match ([regex]::Escape($token))
        }
        ($script:validateWorkflow | Select-String -Pattern "diagnosticCompatibility -ne 'passed'" -AllMatches).Matches.Count | Should -Be 2
        ($script:validateWorkflow | Select-String -Pattern "updaterFallbackVersion -ne '0.6.3'" -AllMatches).Matches.Count | Should -Be 2
    }

    It 'keeps stable update discovery independent from the GitHub Releases API' {
        foreach ($token in @('Invoke-WebRequest','HttpWebRequest','curl.exe','NEXROUTE_LATEST_RELEASE_FIXTURE')) {
            $script:updaterEntry | Should -Match ([regex]::Escape($token))
        }
        $script:updaterEntry | Should -Not -Match 'api\.github\.com'
    }

    It 'keeps the 21-profile refresh and live evidence gate in the stable source tree' {
        foreach ($token in @('nr063-01','nr063-21','multisplit','multidisorder','fakedsplit','hostfakesplit','syndata')) {
            $script:refresh | Should -Match ([regex]::Escape($token))
        }
        foreach ($target in @('DiscordGateway','DiscordCDN','DiscordUpdates','YouTubeWeb','YouTubeShort','YouTubeImage','YouTubeVideoRedirect','GoogleMain','CloudflareWeb')) {
            $script:evidence | Should -Match ([regex]::Escape($target))
        }
    }

    It 'uses current action majors across validate release and Pages workflows' {
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

    It 'documents the four-subject 0.6.3 release trust flow' {
        foreach ($token in @(
            'NexRoute-0.6.3-win-x64.zip',
            'NexRoute-0.6.3-win-x64.zip.sha256',
            'NexRoute-0.6.3-validation.json',
            'NexRoute-0.6.3-validation.md'
        )) {
            $script:releaseNotes | Should -Match ([regex]::Escape($token))
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
