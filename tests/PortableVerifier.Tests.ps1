Describe 'NexRoute 0.6.0 portable attestation verifier' {
    BeforeAll {
        $root=Split-Path -Parent $PSScriptRoot
        . (Join-Path $root 'overlay/.service/next/nexroute-portable-verifier.ps1')
        Add-Type -AssemblyName System.IO.Compression.FileSystem

        function New-NrPortableVerifierFixture {
            param([string]$Path,[switch]$UnsafeEntry)
            $source=Join-Path $Path 'source'
            New-Item -ItemType Directory -Path (Join-Path $source 'bin') -Force | Out-Null
            [IO.File]::WriteAllBytes((Join-Path $source 'bin/gh.exe'),[Text.Encoding]::UTF8.GetBytes('fixture-gh-executable'))
            $padding=New-Object byte[] 1100000
            for ($index=0;$index -lt $padding.Length;$index++) { $padding[$index]=[byte]($index % 251) }
            [IO.File]::WriteAllBytes((Join-Path $source 'bin/padding.dat'),$padding)
            $archive=Join-Path $Path 'gh_fixture.zip'
            if ($UnsafeEntry) {
                $stream=[IO.File]::Open($archive,[IO.FileMode]::Create)
                $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$false)
                try {
                    $entry=$zip.CreateEntry('../escape.exe')
                    $writer=[IO.StreamWriter]::new($entry.Open())
                    try { $writer.Write('escape') } finally { $writer.Dispose() }
                } finally { $zip.Dispose(); $stream.Dispose() }
            } else {
                [IO.Compression.ZipFile]::CreateFromDirectory($source,$archive,[IO.Compression.CompressionLevel]::NoCompression,$false)
            }
            return $archive
        }

        function New-NrPortableVerifierManifest {
            param([string]$Path,[string]$ArchivePath,[string]$ExpectedSha)
            $manifest=[ordered]@{
                schemaVersion=1
                tools=[ordered]@{
                    githubCli=[ordered]@{
                        version='2.97.0'; tag='v2.97.0'; repository='cli/cli'; assetName='gh_fixture.zip';
                        assetUrl='https://github.com/cli/cli/releases/download/v2.97.0/gh_2.97.0_windows_amd64.zip';
                        sha256=$ExpectedSha; minimumBytes=1000000; executableRelativePath='bin/gh.exe'; purpose='fixture'
                    }
                }
            }
            $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding UTF8
            return $Path
        }
    }

    It 'pins the official immutable GitHub CLI 2.97.0 archive and digest' {
        $repositoryRoot=Split-Path -Parent $PSScriptRoot
        $manifestPath=Join-Path $repositoryRoot 'overlay/.service/portable-tools.json'
        $tool=Read-NrPortableToolsManifest -Path $manifestPath
        $tool.version | Should -Be '2.97.0'
        $tool.assetName | Should -Be 'gh_2.97.0_windows_amd64.zip'
        $tool.sha256 | Should -Be '35d7fe05c4dd1411ffda1e73dfc7c6f44b75c936ca51fa6595c657fdc0350cec'
        $tool.assetUrl | Should -Be 'https://github.com/cli/cli/releases/download/v2.97.0/gh_2.97.0_windows_amd64.zip'
    }

    It 'installs a verified archive into an integrity-checked cache' {
        $fixture=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-portable-verifier-'+[guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path (Join-Path $fixture '.service') -Force | Out-Null
            $archive=New-NrPortableVerifierFixture -Path $fixture
            $sha=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
            $manifest=New-NrPortableVerifierManifest -Path (Join-Path $fixture '.service/portable-tools.json') -ArchivePath $archive -ExpectedSha $sha
            $first=Get-NrPortableGithubCli -Root $fixture -ManifestPath $manifest -ArchivePath $archive -SkipVersionProbe
            $first.cached | Should -BeFalse
            Test-Path -LiteralPath $first.executable -PathType Leaf | Should -BeTrue
            Test-Path -LiteralPath $first.receipt -PathType Leaf | Should -BeTrue
            $receipt=Get-Content -LiteralPath $first.receipt -Raw | ConvertFrom-Json
            $receipt.archiveSha256 | Should -Be $sha
            $receipt.executableSha256 | Should -Be (Get-FileHash -LiteralPath $first.executable -Algorithm SHA256).Hash.ToLowerInvariant()

            $second=Get-NrPortableGithubCli -Root $fixture -ManifestPath $manifest -ArchivePath $archive -SkipVersionProbe
            $second.cached | Should -BeTrue
            $second.executable | Should -Be $first.executable
        } finally { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'rejects a portable verifier archive with the wrong digest' {
        $fixture=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-portable-verifier-bad-'+[guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path (Join-Path $fixture '.service') -Force | Out-Null
            $archive=New-NrPortableVerifierFixture -Path $fixture
            $manifest=New-NrPortableVerifierManifest -Path (Join-Path $fixture '.service/portable-tools.json') -ArchivePath $archive -ExpectedSha ('0'*64)
            { Get-NrPortableGithubCli -Root $fixture -ManifestPath $manifest -ArchivePath $archive -SkipVersionProbe } | Should -Throw '*SHA-256 mismatch*'
        } finally { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'rejects ZIP path traversal before writing outside the cache' {
        $fixture=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-portable-verifier-traversal-'+[guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path $fixture -Force | Out-Null
            $archive=New-NrPortableVerifierFixture -Path $fixture -UnsafeEntry
            { Expand-NrPortableToolArchive -ArchivePath $archive -Destination (Join-Path $fixture 'extract') } | Should -Throw '*Unsafe portable verifier archive entry*'
            Test-Path -LiteralPath (Join-Path $fixture 'escape.exe') | Should -BeFalse
        } finally { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'reinstalls the verifier when the cached executable is modified' {
        $fixture=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-portable-verifier-tamper-'+[guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path (Join-Path $fixture '.service') -Force | Out-Null
            $archive=New-NrPortableVerifierFixture -Path $fixture
            $sha=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
            $manifest=New-NrPortableVerifierManifest -Path (Join-Path $fixture '.service/portable-tools.json') -ArchivePath $archive -ExpectedSha $sha
            $first=Get-NrPortableGithubCli -Root $fixture -ManifestPath $manifest -ArchivePath $archive -SkipVersionProbe
            Set-Content -LiteralPath $first.executable -Value 'tampered' -Encoding ASCII
            $second=Get-NrPortableGithubCli -Root $fixture -ManifestPath $manifest -ArchivePath $archive -SkipVersionProbe
            $second.cached | Should -BeFalse
            (Get-Content -LiteralPath $second.executable -Raw) | Should -Match 'fixture-gh-executable'
        } finally { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'invokes cryptographic verification with repository and signer identity constraints' {
        $fixture=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-portable-verifier-runner-'+[guid]::NewGuid().ToString('N'))
        $script:capturedArguments=$null
        try {
            New-Item -ItemType Directory -Path $fixture -Force | Out-Null
            $subject=Join-Path $fixture 'NexRoute.zip'
            Set-Content -LiteralPath $subject -Value 'artifact' -Encoding ASCII
            $verifier=Join-Path $fixture 'gh.exe'
            Set-Content -LiteralPath $verifier -Value 'fixture' -Encoding ASCII
            $result=Invoke-NrGithubAttestationVerify -VerifierPath $verifier -SubjectPath $subject -Repository 'Onmaynec/NexRoute' -Runner {
                param($executable,$arguments)
                $script:capturedArguments=[string[]]$arguments
                [pscustomobject]@{ exitCode=0; output='verified' }
            }
            $result.verified | Should -BeTrue
            $script:capturedArguments | Should -Contain 'attestation'
            $script:capturedArguments | Should -Contain 'verify'
            $script:capturedArguments | Should -Contain '--repo'
            $script:capturedArguments | Should -Contain '--signer-repo'
            @($script:capturedArguments | Where-Object { $_ -eq 'Onmaynec/NexRoute' }).Count | Should -Be 2
        } finally { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
