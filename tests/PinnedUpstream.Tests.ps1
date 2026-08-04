Describe 'NexRoute 0.6.0 pinned upstream resolver' {
    BeforeAll {
        $script:repositoryRoot=Split-Path -Parent $PSScriptRoot
        $script:resolver=Join-Path $script:repositoryRoot 'scripts/Resolve-PinnedUpstream.ps1'
    }

    It 'pins one exact immutable upstream asset and digest in the production manifest' {
        $manifest=Get-Content -LiteralPath (Join-Path $script:repositoryRoot '.service/upstream-manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $manifest.repository | Should -Be 'Flowseal/zapret-discord-youtube'
        $manifest.tag | Should -Be '1.10.0'
        $manifest.assetName | Should -Be 'zapret-discord-youtube-1.10.0.zip'
        $manifest.assetName | Should -Match $manifest.assetPattern
        $manifest.expectedSha256 | Should -Be '6b7c5a66cfd055b8e361f8b5fb00f00b167260f21b1c03d589f6008417fb94a2'
    }

    It 'uses an already verified cache without contacting GitHub API or release metadata' {
        $fixture=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-pinned-upstream-'+[guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path $fixture -Force | Out-Null
            $archive=Join-Path $fixture 'fixture.zip'
            [IO.File]::WriteAllBytes($archive,[Text.Encoding]::UTF8.GetBytes('verified-upstream-fixture'))
            $sha=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
            $manifestPath=Join-Path $fixture 'manifest.json'
            [ordered]@{
                schemaVersion=1
                repository='Flowseal/zapret-discord-youtube'
                tag='1.10.0'
                assetName='zapret-discord-youtube-1.10.0.zip'
                assetPattern='^zapret-discord-youtube-1\.10\.0\.zip$'
                minimumBytes=1
                expectedSha256=$sha
                requiredPaths=@('service.bat')
            } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

            $result=& $script:resolver -ManifestPath $manifestPath -OutputPath $archive
            $result.cached | Should -BeTrue
            $result.sha256 | Should -Be $sha
            $result.path | Should -Be ([IO.Path]::GetFullPath($archive))
            $result.url | Should -Be 'https://github.com/Flowseal/zapret-discord-youtube/releases/download/1.10.0/zapret-discord-youtube-1.10.0.zip'
        } finally { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'rejects unsafe or ambiguous asset names before attempting a download' {
        $fixture=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-pinned-upstream-invalid-'+[guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path $fixture -Force | Out-Null
            foreach ($assetName in @('../release.zip','folder/release.zip','release.exe')) {
                $manifestPath=Join-Path $fixture (([guid]::NewGuid().ToString('N'))+'.json')
                [ordered]@{
                    schemaVersion=1
                    repository='Flowseal/zapret-discord-youtube'
                    tag='1.10.0'
                    assetName=$assetName
                    assetPattern='.*'
                    minimumBytes=1
                    expectedSha256=('0'*64)
                    requiredPaths=@('service.bat')
                } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
                { & $script:resolver -ManifestPath $manifestPath -OutputPath (Join-Path $fixture 'output.zip') } | Should -Throw '*assetName*'
            }
        } finally { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'contains no GitHub Releases API dependency' {
        $source=Get-Content -LiteralPath $script:resolver -Raw -Encoding UTF8
        $source | Should -Match 'releases/download'
        $source | Should -Match 'Get-FileHash'
        $source | Should -Not -Match 'api\.github\.com|Invoke-RestMethod|releases/tags'
    }
}
