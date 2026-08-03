Describe 'NexRoute 0.6.0 portable release attestation flow' {
    BeforeAll {
        $root=Split-Path -Parent $PSScriptRoot
        . (Join-Path $root 'overlay/.service/next/nexroute-portable-verifier.ps1')
        . (Join-Path $root 'overlay/.service/next/nexroute-attestation-v2.ps1')

        function New-NrAttestationReleaseFixture {
            param(
                [string]$Path,
                [switch]$BadChecksum,
                [switch]$Prerelease,
                [switch]$MissingChecksum,
                [switch]$MissingValidationJson,
                [switch]$BadValidation
            )
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
            $archiveName='NexRoute-0.6.0-win-x64.zip'
            $checksumName="$archiveName.sha256"
            $validationJsonName='NexRoute-0.6.0-validation.json'
            $validationMarkdownName='NexRoute-0.6.0-validation.md'
            $archivePath=Join-Path $Path $archiveName
            [IO.File]::WriteAllBytes($archivePath,[Text.Encoding]::UTF8.GetBytes('nexroute-release-fixture'))
            $sha=(Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
            $writtenSha=if ($BadChecksum) { '0'*64 } else { $sha }
            if (-not $MissingChecksum) { Set-Content -LiteralPath (Join-Path $Path $checksumName) -Value "$writtenSha  $archiveName" -Encoding ASCII }

            if (-not $MissingValidationJson) {
                $validation=[ordered]@{
                    schemaVersion=$(if ($BadValidation) { 99 } else { 1 })
                    product='NexRoute'
                    version='0.6.0'
                    overallStatus='passed-with-limitations'
                    checks=@(
                        [ordered]@{ id='package.sha256'; category='release'; status='passed'; required=$true; summary='Package verified.'; evidence=$sha; limitation=$null },
                        [ordered]@{ id='runtime.ipv6-live'; category='runtime'; status='experimental'; required=$false; summary='Live IPv6 remains environment dependent.'; evidence='Synthetic tests passed.'; limitation='Validate on an IPv6-capable host.' }
                    )
                    limitations=@([ordered]@{ id='runtime.ipv6-live'; status='experimental'; limitation='Validate on an IPv6-capable host.' })
                }
                [IO.File]::WriteAllText((Join-Path $Path $validationJsonName),($validation | ConvertTo-Json -Depth 10)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
            }
            [IO.File]::WriteAllText((Join-Path $Path $validationMarkdownName),'# NexRoute 0.6.0 validation report'+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))

            $assets=@([pscustomobject]@{ name=$archiveName; browser_download_url='https://github.com/Onmaynec/NexRoute/releases/download/v0.6.0/'+$archiveName })
            if (-not $MissingChecksum) { $assets += [pscustomobject]@{ name=$checksumName; browser_download_url='https://github.com/Onmaynec/NexRoute/releases/download/v0.6.0/'+$checksumName } }
            if (-not $MissingValidationJson) { $assets += [pscustomobject]@{ name=$validationJsonName; browser_download_url='https://github.com/Onmaynec/NexRoute/releases/download/v0.6.0/'+$validationJsonName } }
            $assets += [pscustomobject]@{ name=$validationMarkdownName; browser_download_url='https://github.com/Onmaynec/NexRoute/releases/download/v0.6.0/'+$validationMarkdownName }
            return [pscustomobject]@{
                release=[pscustomobject]@{ tag_name='v0.6.0'; draft=$false; prerelease=[bool]$Prerelease; assets=$assets }
                archiveName=$archiveName
                checksumName=$checksumName
                validationJsonName=$validationJsonName
                validationMarkdownName=$validationMarkdownName
                sha=$sha
            }
        }
    }

    It 'verifies all four attested subjects and installs a viewer receipt' {
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
            $script:verifiedSubjects.ToArray() | Should -Be @(
                $release.archiveName,
                $release.checksumName,
                $release.validationJsonName,
                $release.validationMarkdownName
            )
            @($result.subjects) | Should -HaveCount 4
            $result.validation.overallStatus | Should -Be 'passed-with-limitations'
            $result.validation.checkCount | Should -Be 2
            $result.validation.limitationCount | Should -Be 1
            Test-Path -LiteralPath $result.validation.reportPath -PathType Leaf | Should -BeTrue
            Test-Path -LiteralPath $result.validation.markdownPath -PathType Leaf | Should -BeTrue
            Test-Path -LiteralPath $result.validation.receiptPath -PathType Leaf | Should -BeTrue
            $receipt=Get-Content -LiteralPath $result.validation.receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $receipt.schemaVersion | Should -Be 1
            $receipt.verified | Should -BeTrue
            $receipt.reportSha256 | Should -Be ((Get-FileHash -LiteralPath $result.validation.reportPath -Algorithm SHA256).Hash.ToLowerInvariant())
            $receipt.releaseVersion | Should -Be '0.6.0'
            @($receipt.subjects) | Should -HaveCount 4
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

    It 'rejects prereleases and missing required assets' {
        $fixture=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-attestation-invalid-release-'+[guid]::NewGuid().ToString('N'))
        try {
            $prerelease=New-NrAttestationReleaseFixture -Path (Join-Path $fixture 'pre') -Prerelease
            { Invoke-NrReleaseAttestationVerification -Root $fixture -Release $prerelease.release -AssetDirectory (Join-Path $fixture 'pre') } | Should -Throw '*not a stable release*'
            $missing=New-NrAttestationReleaseFixture -Path (Join-Path $fixture 'missing') -MissingChecksum
            { Invoke-NrReleaseAttestationVerification -Root $fixture -Release $missing.release -AssetDirectory (Join-Path $fixture 'missing') } | Should -Throw '*exactly one checksum asset*'
            $missingValidation=New-NrAttestationReleaseFixture -Path (Join-Path $fixture 'missing-validation') -MissingValidationJson
            { Invoke-NrReleaseAttestationVerification -Root $fixture -Release $missingValidation.release -AssetDirectory (Join-Path $fixture 'missing-validation') } | Should -Throw '*exactly one validation JSON asset*'
        } finally { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'rejects mutable or foreign release asset URLs' {
        $fixture=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-attestation-foreign-url-'+[guid]::NewGuid().ToString('N'))
        try {
            $release=New-NrAttestationReleaseFixture -Path $fixture
            $release.release.assets[2].browser_download_url='https://example.com/NexRoute-0.6.0-validation.json'
            { Get-NrReleaseAttestationAssets -Release $release.release } | Should -Throw '*not an immutable NexRoute release URL*'
        } finally { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'fails when any of the four subject attestations is not confirmed' {
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
                        [pscustomobject]@{ verified=($script:verificationIndex -ne 3); subject=$subject }
                    }
            } | Should -Throw '*did not confirm subject*'
            $script:verificationIndex | Should -Be 3
            Test-Path -LiteralPath (Join-Path $fixture '.service/release-validation.json') | Should -BeFalse
        } finally { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'rejects an attested but invalid validation schema before installing a receipt' {
        $fixture=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-attestation-invalid-validation-'+[guid]::NewGuid().ToString('N'))
        $script:subjectVerifierCalls=0
        try {
            $release=New-NrAttestationReleaseFixture -Path $fixture -BadValidation
            {
                Invoke-NrReleaseAttestationVerification -Root $fixture -Release $release.release -AssetDirectory $fixture `
                    -VerifierResolver { param($rootPath,$portableArchive) [pscustomobject]@{ executable='gh.exe' } } `
                    -SubjectVerifier { param($verifier,$subject,$repository) $script:subjectVerifierCalls++; [pscustomobject]@{ verified=$true; subject=$subject } }
            } | Should -Throw '*schemaVersion must be 1*'
            $script:subjectVerifierCalls | Should -Be 4
            Test-Path -LiteralPath (Join-Path $fixture '.service/release-validation.json') | Should -BeFalse
            Test-Path -LiteralPath (Join-Path $fixture '.service/release-validation.json.attestation-receipt.json') | Should -BeFalse
        } finally { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
    }
}