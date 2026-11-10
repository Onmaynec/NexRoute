Describe 'NexRoute active documentation coherence' {
    BeforeAll {
        $root = Split-Path -Parent $PSScriptRoot
        function Read-NrCurrentDoc {
            param([string]$Path)
            Get-Content -LiteralPath (Join-Path $root $Path) -Raw -Encoding UTF8
        }
        $script:version = (Read-NrCurrentDoc '.service/version.txt').Trim()
        $script:manifest = Read-NrCurrentDoc '.service/upstream-manifest.json' | ConvertFrom-Json
        $script:readme = Read-NrCurrentDoc 'README.md'
        $script:english = Read-NrCurrentDoc 'docs/README_EN.md'
        $script:architecture = Read-NrCurrentDoc 'docs/ARCHITECTURE.md'
        $script:compatibility = Read-NrCurrentDoc 'docs/COMPATIBILITY.md'
        $script:services = Read-NrCurrentDoc 'docs/SERVICES.md'
        $script:updates = Read-NrCurrentDoc 'docs/UPDATES.md'
        $script:releases = Read-NrCurrentDoc 'docs/RELEASES.md'
        $script:site = Read-NrCurrentDoc 'website/content/site.ts'
        $script:siteDocs = Read-NrCurrentDoc 'website/content/docs.ts'
        $script:releaseNotes = Read-NrCurrentDoc '.github/release-notes/v0.7.0.md'
        $script:acceptance = Read-NrCurrentDoc 'docs/RELEASE_0.7.0_ACCEPTANCE.md'
        $script:package = Read-NrCurrentDoc 'website/package.json' | ConvertFrom-Json
        $script:lock = Read-NrCurrentDoc 'website/package-lock.json' | ConvertFrom-Json -AsHashtable
    }

    It 'keeps the current product version synchronized' {
        $script:version | Should -Be '0.7.0'
        [string]$script:package.version | Should -Be $script:version
        [string]$script:lock['version'] | Should -Be $script:version
        [string]$script:lock['packages']['']['version'] | Should -Be $script:version
        $script:readme | Should -Match ('version-' + $script:version + '-')
        $script:readme | Should -Match ('NexRoute ' + $script:version + ' — Strategy Manifest')
        $script:english | Should -Match ('version-' + $script:version + '-')
        $script:architecture | Should -Match ('Архитектура NexRoute ' + $script:version)
        $script:compatibility | Should -Match ('Совместимость NexRoute ' + $script:version)
        $script:releases | Should -Match ('Сборка и публикация NexRoute ' + $script:version)
        $script:siteDocs | Should -Match ('NexRoute ' + $script:version)
    }

    It 'documents only the pinned upstream in current instructions' {
        $script:manifest.tag | Should -Be '1.10.3'
        foreach ($document in @($script:readme,$script:english,$script:architecture,$script:releases,$script:services,$script:siteDocs)) {
            $document | Should -Match '1\.10\.3'
            $document | Should -Not -Match '1\.10\.0'
        }
    }

    It 'agrees on upstream strategy counts and tracked patches' {
        $script:readme | Should -Match '22 стратегии, 24 patch-targets'
        $script:architecture | Should -Match '22 upstream strategy launchers'
        $script:architecture | Should -Match '24 tracked patch targets'
        $script:releases | Should -Match '22 upstream Flowseal strategies'
        $script:releases | Should -Match '24 tracked patch targets'
        $script:services | Should -Match '22 upstream-стратегии'
        $script:updates | Should -Match '22 upstream-стратегий'
        $script:updates | Should -Match '24 patch records'
        $script:site | Should -Match '22.*upstream-стратегии'
        $script:site | Should -Match '24 tracked patch targets'
    }

    It 'uses the current archive and version for all build examples' {
        foreach ($document in @($script:readme,$script:releases,$script:siteDocs)) {
            $document | Should -Match '\-Version 0\.7\.0'
            $document | Should -Match 'zapret-discord-youtube-1\.10\.3\.zip'
            $document | Should -Not -Match '\-Version 0\.6\.0'
        }
        $script:releases | Should -Not -Match 'zapret-discord-youtube-1\.10\.0'
    }

    It 'documents the current four-asset release contract' {
        foreach ($asset in @('NexRoute-0.7.0-win-x64.zip','NexRoute-0.7.0-win-x64.zip.sha256','NexRoute-0.7.0-validation.json','NexRoute-0.7.0-validation.md')) {
            $script:readme | Should -Match ([regex]::Escape($asset))
            $script:releaseNotes | Should -Match ([regex]::Escape($asset))
            $script:releases | Should -Match ([regex]::Escape($asset))
        }
        $script:acceptance | Should -Match 'NexRoute 0\.7\.0'
        $script:updates | Should -Match '0\.6\.6 -> 0\.7\.0'
    }

    It 'retains historical 0.6.5 release evidence without silently closing manual checks' {
        $historic = Read-NrCurrentDoc 'docs/RELEASE_0.6.5_ACCEPTANCE.md'
        $historic | Should -Match 'Архивный checklist'
        $historic | Should -Match 'actions/runs/35577265434'
        $historic | Should -Match '\- \[ \] '
        (Read-NrCurrentDoc '.github/release-notes/v0.6.5.md') | Should -Match 'NexRoute 0\.6\.5'
    }
}
