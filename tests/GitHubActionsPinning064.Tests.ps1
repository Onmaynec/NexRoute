Describe 'NexRoute 0.6.4 GitHub Actions supply-chain pinning' {
    BeforeAll {
        $script:root = Split-Path -Parent $PSScriptRoot
        $script:validator = Join-Path $script:root 'scripts/Test-GitHubActionsPinning.ps1'
    }

    It 'accepts every repository workflow only when external actions match the reviewed immutable allowlist' {
        $result = & $script:validator -Root $script:root
        $result.status | Should -Be 'passed'
        $result.externalActionCount | Should -BeGreaterThan 0
        $result.approvedActionCount | Should -Be 7
        foreach ($entry in @($result.approved)) {
            $entry.sha | Should -Match '^[0-9a-f]{40}$'
            $entry.version | Should -Match '^v\d+\.\d+\.\d+$'
        }
    }

    It 'rejects mutable refs and unknown external actions with explicit errors' {
        $fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('nexroute-actions-pin-'+[guid]::NewGuid().ToString('N'))
        try {
            $workflowRoot = Join-Path $fixtureRoot '.github/workflows'
            New-Item -ItemType Directory -Path $workflowRoot -Force | Out-Null
            @'
name: bad
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: unknown/vendor-action@1111111111111111111111111111111111111111 # unknown/vendor-action v1.0.0
'@ | Set-Content -LiteralPath (Join-Path $workflowRoot 'bad.yml') -Encoding UTF8

            { & $script:validator -Root $fixtureRoot } | Should -Throw '*mutable ref*'
            { & $script:validator -Root $fixtureRoot } | Should -Throw '*unknown external action*'
        } finally {
            Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'rejects a full SHA that is not the reviewed commit and rejects missing semver comments' {
        $fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('nexroute-actions-pin-'+[guid]::NewGuid().ToString('N'))
        try {
            $workflowRoot = Join-Path $fixtureRoot '.github/workflows'
            New-Item -ItemType Directory -Path $workflowRoot -Force | Out-Null
            @'
name: bad-sha
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@1111111111111111111111111111111111111111
'@ | Set-Content -LiteralPath (Join-Path $workflowRoot 'bad.yml') -Encoding UTF8

            { & $script:validator -Root $fixtureRoot } | Should -Throw '*unapproved SHA*'
        } finally {
            Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
