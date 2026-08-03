Describe 'NexRoute 0.6.0 portable release attestation flow' {
    BeforeAll {
        $root=Split-Path -Parent $PSScriptRoot
        . (Join-Path $root 'overlay/.service/next/nexroute-portable-verifier.ps1')
        . (Join-Path $root 'overlay/.service/next/nexroute-attestation-v2.ps1')

        function New-NrAttestationReleaseFixture {
            param([string]$Path,[switch]$BadChecksum,[switch]$Prerelease,[switch]$MissingChecksum)
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
            $archiveName='NexRoute-0.6.0-win-x64.zip'
            $checksumName="$archiveName.sha256"
            $archivePath=Join-Path $Path $archiveName
            [IO.File]::WriteAllBytes($archivePath,[Text.Encoding]::UTF8.GetBytes('nexroute-release-fixture'))
            $sha=(Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
            $writtenSha=if ($BadChecksum) { '0'*64 } else { $sha }
            if (-not $MissingChecksum) { Set-Content -LiteralPath (Join-Path $Path $checksumName) -Value "$writtenSha  $archiveName" -Encoding ASCII }
            $assets=@([pscustomobject]@{ name=$archiveName; browser_download_url='https://github.com/Onmaynec/NexRoute/releases/download/v0.6.0/'+$archiveName })
            if (-not $MissingChecksum) { $assets += [pscustomobject]@{ name=$checksumName; browser_download_url='https://github.com/Onmaynec/NexRoute/releases/download/v0.6.0/'+$checksumName } }
            return [pscustomobject]@{
                release=[pscustomobject]@{ tag_name='v0.6.0'; draft=$false; prerelease=[bool]$Prerelease; assets=$assets }
                archiveName=$archiveName
                checksumName=$checksumName
                sha=$sha
            }
        }
    }

    It 'verifies checksum and both attested subjects using the portable verifier' {
        $fixture=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-attestation-v2-'+[guid]::NewGuid().ToString('N'))
        $script:verifiedSubjects=New-Object 'System.Collections.Generic.List[string]'
        try {
            $release=New-NrAttestationReleaseFixture -Path $fixture
            $result=Invoke-NrReleaseAttestationVerification -Root $fixture -Release $release.release -AssetDirectory $fixture `
                -VerifierResolver { param($rootPath,$portableArchive) [pscustomobject]@{ executable=(Join-Path $rootPath '.service/tools/github-cli/2.97.0/bin/gh.exe'); cached=$true } } `
                -SubjectVerifier {
                    param($verifier,$subject,$repository)
                    $repository | Should -Be 'Onmaynec/NexRoute'
                    $verifier | Should -Match 'gh\.exe$'
                    $script:verifiedSubjects.Add((Split-Path $subject -Leaf))
                    [pscustomobject]@{ verified=$true; subject=$subject; repository=$repository; verifier=$verifier }
                }
            $result.verified | Should -BeTrue
            $result.version | Should -Be '0.6.0'
            $result.sha256 | Should -Be $release.sha
            $result.verifierCached | Should -BeTrue
            $script:verifiedSubjects.ToArray() | Should -Be @($release.archiveName,$release.checksumName)
            @($result.subjects) | Should -HaveCount 2
        } finally { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'rejects a release archive before attestation when the checksum does not match' {
        $fixture=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-attestation-bad-sha-'+[guid]::NewGuid().ToString('N'))
        $script:subjectVerifierCalls=0
        try {
            $release=New-NrAttestationReleaseFixture -Path $fixture -BadChecksum
            {
                Invoke-NrReleaseAttestationVerification -Root $fixture -Release $release.release -AssetDirectory $fixture `
                    -VerifierResolver { param($rootPath,$portableArchive) [pscustomobject]@{ executable='gh.exe' } } `
                    -SubjectVerifier { param($verifier,$subject,$repository) $script:subjectVerifierCalls++; [pscustomobject]@{ verified=$true } }
            } | Should -Throw '*SHA-256 mismatch*'
            $script:subjectVerifierCalls | Should -Be 0
        } finally { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'rejects prereleases and missing checksum assets' {
        $fixture=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-attestation-invalid-release-'+[guid]::NewGuid().ToString('N'))
        try {
            $prerelease=New-NrAttestationReleaseFixture -Path (Join-Path $fixture 'pre') -Prerelease
            { Invoke-NrReleaseAttestationVerification -Root $fixture -Release $prerelease.release -AssetDirectory (Join-Path $fixture 'pre') } | Should -Throw '*not a stable release*'
            $missing=New-NrAttestationReleaseFixture -Path (Join-Path $fixture 'missing') -MissingChecksum
            { Invoke-NrReleaseAttestationVerification -Root $fixture -Release $missing.release -AssetDirectory (Join-Path $fixture 'missing') } | Should -Throw '*exactly one checksum asset*'
        } finally { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'rejects mutable or foreign release asset URLs' {
        $fixture=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-attestation-foreign-url-'+[guid]::NewGuid().ToString('N'))
        try {
            $release=New-NrAttestationReleaseFixture -Path $fixture
            $release.release.assets[0].browser_download_url='https://example.com/NexRoute-0.6.0-win-x64.zip'
            { Get-NrReleaseAttestationAssets -Release $release.release } | Should -Throw '*not an immutable NexRoute release URL*'
        } finally { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'fails when either archive or checksum attestation is not confirmed' {
        $fixture=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-attestation-subject-failure-'+[guid]::NewGuid().ToString('N'))
        $script:verificationIndex=0
        try {
            $release=New-NrAttestationReleaseFixture -Path $fixture
            {
                Invoke-NrReleaseAttestationVerification -Root $fixture -Release $release.release -AssetDirectory $fixture `
                    -VerifierResolver { param($rootPath,$portableArchive) [pscustomobject]@{ executable='gh.exe' } } `
                    -SubjectVerifier {
                        param($verifier,$subject,$repository)
                        $script:verificationIndex++
                        [pscustomobject]@{ verified=($script:verificationIndex -eq 1); subject=$subject }
                    }
            } | Should -Throw '*did not confirm subject*'
            $script:verificationIndex | Should -Be 2
        } finally { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
