$repositoryRoot = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $repositoryRoot 'scripts/NexRoute.Upstream.psm1'
Import-Module $modulePath -Force

Describe 'NexRoute upstream contract' {
    BeforeAll {
        function New-TestManifestFile {
            param(
                [string]$ExpectedSha256 = '',
                [string[]]$RequiredPaths = @('service.bat','general.bat','bin/winws.exe')
            )
            $manifestPath = Join-Path $script:testRoot 'manifest.json'
            [ordered]@{
                schemaVersion = 1
                repository = 'Example/Upstream'
                tag = '1.2.3'
                assetPattern = '^example-1\.2\.3\.zip$'
                minimumBytes = 1
                expectedSha256 = $ExpectedSha256
                requiredPaths = $RequiredPaths
            } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
            return $manifestPath
        }

        function New-TestArchive {
            param([switch]$OmitBinary)
            $payload = Join-Path $script:testRoot 'payload'
            $bin = Join-Path $payload 'bin'
            New-Item -ItemType Directory -Path $bin -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $payload 'service.bat') -Value '@echo off' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $payload 'general.bat') -Value '@echo off' -Encoding ASCII
            if (-not $OmitBinary) {
                Set-Content -LiteralPath (Join-Path $bin 'winws.exe') -Value 'fixture' -Encoding ASCII
            }
            $archive = Join-Path $script:testRoot 'example-1.2.3.zip'
            Compress-Archive -Path (Join-Path $payload '*') -DestinationPath $archive -CompressionLevel Fastest
            return $archive
        }
    }

    BeforeEach {
        $script:testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('nexroute-upstream-test-{0}' -f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:testRoot -Force | Out-Null
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:testRoot) {
            Remove-Item -LiteralPath $script:testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'loads a valid declarative manifest' {
        $manifest = Read-NexRouteUpstreamManifest -Path (New-TestManifestFile)
        $manifest.schemaVersion | Should -Be 1
        $manifest.repository | Should -Be 'Example/Upstream'
        $manifest.requiredPaths.Count | Should -Be 3
    }

    It 'rejects path traversal in required paths' {
        $path = New-TestManifestFile -RequiredPaths @('service.bat','../secret.txt')
        { Read-NexRouteUpstreamManifest -Path $path } | Should -Throw '*Unsafe upstream required path*'
    }

    It 'rejects duplicate required paths' {
        $path = New-TestManifestFile -RequiredPaths @('service.bat','service.bat')
        { Read-NexRouteUpstreamManifest -Path $path } | Should -Throw
    }

    It 'requires a locked digest unless bootstrap mode is explicit' {
        $manifest = Read-NexRouteUpstreamManifest -Path (New-TestManifestFile)
        $archive = New-TestArchive
        { Resolve-NexRouteUpstreamArchive -Manifest $manifest -WorkingDirectory (Join-Path $script:testRoot 'resolve') -ArchivePath $archive } |
            Should -Throw '*manifest is unlocked*'
    }

    It 'resolves and verifies an offline archive using the locked digest' {
        $archive = New-TestArchive
        $sha = Get-NexRouteSha256 -Path $archive
        $manifest = Read-NexRouteUpstreamManifest -Path (New-TestManifestFile -ExpectedSha256 $sha)
        $resolved = Resolve-NexRouteUpstreamArchive `
            -Manifest $manifest `
            -WorkingDirectory (Join-Path $script:testRoot 'resolve') `
            -ArchivePath $archive

        $resolved.ResolutionMode | Should -Be 'offline'
        $resolved.Lock.sha256 | Should -Be $sha
        $resolved.Lock.assetName | Should -Be 'example-1.2.3.zip'
        $resolved.Lock.strategyCount | Should -Be 1
    }

    It 'rejects an archive whose SHA-256 differs from the lock' {
        $archive = New-TestArchive
        $manifest = Read-NexRouteUpstreamManifest -Path (New-TestManifestFile -ExpectedSha256 ('0' * 64))
        { Resolve-NexRouteUpstreamArchive -Manifest $manifest -WorkingDirectory (Join-Path $script:testRoot 'resolve') -ArchivePath $archive } |
            Should -Throw '*SHA-256 mismatch*'
    }

    It 'rejects an archive missing a required upstream file' {
        $archive = New-TestArchive -OmitBinary
        $sha = Get-NexRouteSha256 -Path $archive
        $manifest = Read-NexRouteUpstreamManifest -Path (New-TestManifestFile -ExpectedSha256 $sha)
        { Resolve-NexRouteUpstreamArchive -Manifest $manifest -WorkingDirectory (Join-Path $script:testRoot 'resolve') -ArchivePath $archive } |
            Should -Throw '*Missing: bin/winws.exe*'
    }

    It 'creates a local release proxy with the verified asset identity' {
        $archive = New-TestArchive
        $sha = Get-NexRouteSha256 -Path $archive
        $manifest = Read-NexRouteUpstreamManifest -Path (New-TestManifestFile -ExpectedSha256 $sha)
        $resolved = Resolve-NexRouteUpstreamArchive `
            -Manifest $manifest `
            -WorkingDirectory (Join-Path $script:testRoot 'resolve') `
            -ArchivePath $archive
        $proxy = New-NexRouteProxyRelease -ResolvedUpstream $resolved -ProxyAssetUrl 'https://nexroute.invalid/upstream.zip'

        @($proxy.assets).Count | Should -Be 1
        $proxy.assets[0].digest | Should -Be "sha256:$sha"
        $proxy.assets[0].browser_download_url | Should -Be 'https://nexroute.invalid/upstream.zip'
    }
}
