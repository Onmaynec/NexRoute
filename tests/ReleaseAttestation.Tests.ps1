Describe 'Release artifact attestations' {
    BeforeAll {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $workflowPath = Join-Path $repoRoot '.github/workflows/release.yml'
        $workflow = Get-Content -LiteralPath $workflowPath -Raw -Encoding UTF8
    }

    It 'grants the OIDC and attestation permissions required by actions/attest' {
        $workflow | Should -Match '(?m)^  id-token: write$'
        $workflow | Should -Match '(?m)^  attestations: write$'
        $workflow | Should -Match '(?m)^  artifact-metadata: write$'
    }

    It 'uses the current official attestation action' {
        $workflow | Should -Match 'uses: actions/attest@v4'
    }

    It 'attests both the release archive and its checksum file' {
        $workflow | Should -Match 'artifacts/\$\{\{ steps\.version\.outputs\.archive \}\}'
        $workflow | Should -Match 'artifacts/\$\{\{ steps\.version\.outputs\.archive \}\}\.sha256'
    }

    It 'verifies provenance before publishing the GitHub Release' {
        $attestIndex = $workflow.IndexOf('- name: Generate signed build provenance')
        $verifyIndex = $workflow.IndexOf('- name: Verify signed build provenance')
        $publishIndex = $workflow.IndexOf('- name: Publish GitHub Release')

        $attestIndex | Should -BeGreaterThan -1
        $verifyIndex | Should -BeGreaterThan $attestIndex
        $publishIndex | Should -BeGreaterThan $verifyIndex
        $workflow | Should -Match 'gh attestation verify'
    }
}
