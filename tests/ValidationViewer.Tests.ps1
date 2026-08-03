BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $sourcePath = Join-Path $repoRoot 'native/NexRoute.Validation/Program.cs'
    $builderPath = Join-Path $repoRoot 'scripts/Build-NativeTray.ps1'
    $packagePath = Join-Path $repoRoot 'scripts/Build-Package.ps1'
    $desktopTestPath = Join-Path $repoRoot 'scripts/Test-V06Desktop.ps1'
    $launcherPath = Join-Path $repoRoot 'overlay/nexroute-validation.cmd'

    $source = Get-Content -LiteralPath $sourcePath -Raw -Encoding UTF8
    $builder = Get-Content -LiteralPath $builderPath -Raw -Encoding UTF8
    $package = Get-Content -LiteralPath $packagePath -Raw -Encoding UTF8
    $desktopTest = Get-Content -LiteralPath $desktopTestPath -Raw -Encoding UTF8
    $launcher = Get-Content -LiteralPath $launcherPath -Raw -Encoding UTF8
}

Describe 'Native validation viewer contract' {
    It 'keeps imported JSON informational until a matching attestation receipt exists' {
        foreach ($token in @(
            'attestation-not-verified',
            'attestation-receipt-matched',
            'attestation-receipt-mismatch',
            'schema-valid but its GitHub artifact attestation has not been verified locally'
        )) {
            $source | Should -Match ([regex]::Escape($token))
        }
    }

    It 'rejects version mismatches, duplicate checks and inconsistent overall status' {
        foreach ($token in @(
            'does not match package version',
            'Duplicate validation check id',
            'AllowedOverallStatuses',
            'passed-with-limitations',
            'is inconsistent with checks; expected',
            'AllowedStatuses'
        )) {
            $source | Should -Match ([regex]::Escape($token))
        }
    }

    It 'is compiled and included in online and offline package builds' {
        $builder | Should -Match ([regex]::Escape("ValidationSourcePath"))
        $builder | Should -Match ([regex]::Escape("NexRoute.Validation"))
        $builder | Should -Match ([regex]::Escape("validationExecutable"))
        $package | Should -Match ([regex]::Escape("native/NexRoute.Validation/Program.cs"))
        $package | Should -Match ([regex]::Escape(".service/native/NexRoute.Validation.exe"))
        $package | Should -Match ([regex]::Escape("nexroute-validation.cmd"))
    }

    It 'has a Windows self-test for unverified and digest-matched receipt states' {
        foreach ($token in @(
            'attestation-not-verified',
            'attestation-receipt-matched',
            '.attestation-receipt.json',
            'ValidationSelfTestExitCode'
        )) {
            $desktopTest | Should -Match ([regex]::Escape($token))
        }
        $launcher | Should -Match ([regex]::Escape('NexRoute.Validation.exe'))
        $launcher | Should -Match ([regex]::Escape('--root'))
    }
}
