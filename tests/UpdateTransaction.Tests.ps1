Describe 'NexRoute 0.6.0 update transaction policy' {
    BeforeAll {
        $root=Split-Path -Parent $PSScriptRoot
        . (Join-Path $root 'overlay/.service/next/nexroute-update-transaction.ps1')
    }

    It 'accepts a healthy Internet connection and at least one working protected service' {
        $policy=Test-NrPostUpdateHealthPolicy -Results @(
            [pscustomobject]@{ name='Internet'; ok=$true }
            [pscustomobject]@{ name='YouTube'; ok=$false }
            [pscustomobject]@{ name='Discord'; ok=$true }
            [pscustomobject]@{ name='Telegram'; ok=$false }
        )
        $policy.passed | Should -BeTrue
        $policy.internetHealthy | Should -BeTrue
        $policy.healthyServiceCount | Should -Be 1
    }

    It 'rejects an update when general Internet access is lost' {
        $policy=Test-NrPostUpdateHealthPolicy -Results @(
            [pscustomobject]@{ name='Internet'; ok=$false }
            [pscustomobject]@{ name='YouTube'; ok=$true }
            [pscustomobject]@{ name='Discord'; ok=$true }
        )
        $policy.passed | Should -BeFalse
    }

    It 'rejects an update when all protected service probes fail' {
        $policy=Test-NrPostUpdateHealthPolicy -Results @(
            [pscustomobject]@{ name='Internet'; ok=$true }
            [pscustomobject]@{ name='YouTube'; ok=$false }
            [pscustomobject]@{ name='Discord'; ok=$false }
            [pscustomobject]@{ name='Telegram'; ok=$false }
        )
        $policy.passed | Should -BeFalse
    }

    It 'writes a machine-readable committed handoff record' {
        $fixture=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-handoff-test-'+[guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path $fixture -Force | Out-Null
            $health=[pscustomobject]@{ passed=$true; internetHealthy=$true; healthyServiceCount=2 }
            $smoke=[pscustomobject]@{ passed=$true; exitCode=0; elapsedMs=120 }
            $path=Write-NrUpdateHandoffRecord -Root $fixture -FromVersion '0.5.0' -ToVersion '0.6.0' -Status committed -HealthPolicy $health -ControlNodeSmoke $smoke -Message 'ready'
            $record=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            $record.schemaVersion | Should -Be 1
            $record.fromVersion | Should -Be '0.5.0'
            $record.toVersion | Should -Be '0.6.0'
            $record.status | Should -Be 'committed'
            $record.healthPolicy.passed | Should -BeTrue
            $record.controlNodeSmoke.exitCode | Should -Be 0
        } finally {
            Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'does not report a missing control node as a successful handoff' {
        $fixture=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-handoff-missing-'+[guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path $fixture -Force | Out-Null
            $result=Test-NrUpdatedControlNode -Root $fixture
            $result.passed | Should -BeFalse
            $result.exitCode | Should -Be -1
        } finally {
            Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
