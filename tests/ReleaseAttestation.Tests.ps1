Describe 'NexRoute 0.6.0 release artifact attestations' {
    BeforeAll {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $workflowPath = Join-Path $repoRoot '.github/workflows/release.yml'
        $workflow = Get-Content -LiteralPath $workflowPath -Raw -Encoding UTF8
    }

    It 'grants the OIDC and attestation permissions required by actions attest' {
        $workflow | Should -Match '(?m)^  id-token: write\r?$'
        $workflow | Should -Match '(?m)^  attestations: write\r?$'
        $workflow | Should -Match '(?m)^  artifact-metadata: write\r?$'
    }

    It 'uses the current official attestation action' {
        $workflow | Should -Match 'uses: actions/attest@v4'
    }

    It 'attests the package checksum and both validation report formats together' {
        foreach ($subject in @(
            'artifacts/${{ steps.version.outputs.archive }}',
            'artifacts/${{ steps.version.outputs.archive }}.sha256',
            'artifacts/NexRoute-${{ steps.version.outputs.version }}-validation.json',
            'artifacts/NexRoute-${{ steps.version.outputs.version }}-validation.md'
        )) {
            $workflow | Should -Match ([regex]::Escape($subject))
        }
        $attestBlock = $workflow.Substring(
            $workflow.IndexOf('- name: Generate signed build provenance'),
            $workflow.IndexOf('- name: Verify signed build provenance') - $workflow.IndexOf('- name: Generate signed build provenance')
        )
        ([regex]::Matches($attestBlock,'(?m)^\s{12}artifacts/')).Count | Should -Be 4
    }

    It 'verifies every subject before publishing the GitHub Release' {
        $attestIndex = $workflow.IndexOf('- name: Generate signed build provenance')
        $verifyIndex = $workflow.IndexOf('- name: Verify signed build provenance')
        $publishIndex = $workflow.IndexOf('- name: Publish GitHub Release')

        $attestIndex | Should -BeGreaterThan -1
        $verifyIndex | Should -BeGreaterThan $attestIndex
        $publishIndex | Should -BeGreaterThan $verifyIndex
        $verifyBlock = $workflow.Substring($verifyIndex,$publishIndex-$verifyIndex)
        foreach ($subject in @(
            './artifacts/${{ steps.version.outputs.archive }}',
            './artifacts/${{ steps.version.outputs.archive }}.sha256',
            './artifacts/NexRoute-${{ steps.version.outputs.version }}-validation.json',
            './artifacts/NexRoute-${{ steps.version.outputs.version }}-validation.md'
        )) {
            $verifyBlock | Should -Match ([regex]::Escape($subject))
        }
        $verifyBlock | Should -Match 'gh attestation verify'
    }
}
