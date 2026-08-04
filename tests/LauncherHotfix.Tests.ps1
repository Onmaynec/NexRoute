Describe 'NexRoute 0.6.1 Windows launcher hotfix' {
    BeforeAll {
        $root = Split-Path -Parent $PSScriptRoot
        $script:service = Get-Content -LiteralPath (Join-Path $root 'overlay/service.bat') -Raw
        $script:main = Get-Content -LiteralPath (Join-Path $root 'overlay/nexroute.bat') -Raw
        $script:update = Get-Content -LiteralPath (Join-Path $root 'overlay/nexroute-update.cmd') -Raw
        $script:smoke = Get-Content -LiteralPath (Join-Path $root 'scripts/Test-WindowsLaunchers.ps1') -Raw
        $script:desktopGate = Get-Content -LiteralPath (Join-Path $root 'scripts/Test-V06Desktop.ps1') -Raw
        $script:builder = Get-Content -LiteralPath (Join-Path $root 'scripts/Build-Package.ps1') -Raw
        $script:diagnosticFix = Get-Content -LiteralPath (Join-Path $root 'overlay/.service/next/nexroute-diagnostics-fixes.ps1') -Raw
        $script:updateTransaction = Get-Content -LiteralPath (Join-Path $root 'overlay/.service/next/nexroute-update-transaction.ps1') -Raw
        $script:updaterEntry = Get-Content -LiteralPath (Join-Path $root 'overlay/.service/nexroute-updater-entry.ps1') -Raw
        $script:extensions = Get-Content -LiteralPath (Join-Path $root 'overlay/.service/next/nexroute-runtime-extensions.ps1') -Raw
        $script:canonicalRoot = 'for %%I in ("%~dp0.") do set "NEXROUTE_ROOT=%%~fI"'
    }

    It 'canonicalizes the root without passing a quoted trailing backslash' {
        foreach ($launcher in @($script:service,$script:main,$script:update)) {
            $launcher | Should -Match ([regex]::Escape($script:canonicalRoot))
            $launcher | Should -Not -Match ([regex]::Escape('set "NEXROUTE_ROOT=%~dp0"'))
        }
    }

    It 'preserves child exit codes across setlocal boundaries' {
        foreach ($launcher in @($script:service,$script:main,$script:update)) {
            $launcher | Should -Match ([regex]::Escape('set "NEXROUTE_EXIT_CODE=%ERRORLEVEL%"'))
            $launcher | Should -Match ([regex]::Escape('endlocal & exit /b %NEXROUTE_EXIT_CODE%'))
        }
    }

    It 'keeps automatic checks non-fatal and exposes a network-free updater smoke path' {
        $script:main | Should -Match ([regex]::Escape('-WarningAction SilentlyContinue'))
        $script:main | Should -Match ([regex]::Escape('if "%~1"==""'))
        $script:main | Should -Match ([regex]::Escape('nexroute-updater-entry.ps1'))
        $script:update | Should -Match ([regex]::Escape('"--status"'))
        $script:update | Should -Match ([regex]::Escape('service.bat" --status'))
    }

    It 'executes every public launcher from a Cyrillic path in the Windows package gate' {
        foreach ($token in @(
            'NexRoute 0.6.1 Hot Fix Тест',
            'service.bat',
            'nexroute.bat',
            'nexroute-update.cmd',
            'GetFullPath',
            'Illegal characters in path',
            'Недопустимые знаки',
            'MethodInvocationException',
            'ArgumentException'
        )) {
            $script:smoke | Should -Match ([regex]::Escape($token))
        }
        $script:smoke | Should -Match ([regex]::Escape("`$env:OS -ne 'Windows_NT'"))
        $script:smoke | Should -Match ([regex]::Escape('& $env:ComSpec /d /s /c'))
    }

    It 'accepts a representative path with spaces and Cyrillic characters' {
        $candidate = 'C:\Users\Тест Пользователь\Downloads\NexRoute-0.6.1-win-x64'
        { [System.IO.Path]::GetFullPath($candidate) } | Should -Not -Throw
    }

    It 'fixes diagnostic status and makes successful empty redirected logs null-safe' {
        $script:extensions | Should -Match ([regex]::Escape("'nexroute-diagnostics-fixes.ps1'"))
        $script:diagnosticFix | Should -Match ([regex]::Escape("`$winDivertRunning = ((Test-NrServiceRunning -Name 'WinDivert') -or (Test-NrServiceRunning -Name 'WinDivert14'))"))
        $script:diagnosticFix | Should -Not -Match 'Test-NrServiceRunning\s+-Name\s+WinDivert\s+-or\s+Test-NrServiceRunning\s+-Name'
        $script:diagnosticFix | Should -Match ([regex]::Escape('[Console]::IsInputRedirected'))
        $script:diagnosticFix | Should -Match ([regex]::Escape('[Console]::IsOutputRedirected'))
        $script:diagnosticFix | Should -Match ([regex]::Escape('if (-not $NoWait -and -not $redirected'))
        $script:updateTransaction | Should -Match ([regex]::Escape('function Read-NrRedirectedText'))
        $script:updateTransaction | Should -Match ([regex]::Escape('$raw=Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue'))
        $script:updateTransaction | Should -Match ([regex]::Escape('if ($null -eq $raw) { return '''' }'))
        $script:updateTransaction | Should -Match ([regex]::Escape('return ([string]$raw).Trim()'))
        $script:updateTransaction | Should -Match ([regex]::Escape('$process.Refresh()'))
        $script:updateTransaction | Should -Match ([regex]::Escape('$errorText=Read-NrRedirectedText -Path $stderr'))
        $script:updateTransaction | Should -Match ([regex]::Escape('$outputText=Read-NrRedirectedText -Path $stdout'))
    }

    It 'falls back from GitHub API errors without bypassing secure updater verification' {
        $script:diagnosticFix | Should -Match ([regex]::Escape('nexroute-updater-entry.ps1'))
        $script:updaterEntry | Should -Match ([regex]::Escape('https://github.com/Onmaynec/NexRoute/releases/latest'))
        $script:updaterEntry | Should -Match ([regex]::Escape('/releases/tag/v?(?<version>\d+\.\d+\.\d+)'))
        foreach ($token in @(
            'NexRoute-$Version-win-x64.zip',
            'NexRoute-$Version-validation.json',
            'NexRoute-$Version-validation.md',
            'nexroute-updater.ps1',
            '-ReleaseMetadataPath',
            'output=@($output)',
            'exitCode=[int]$LASTEXITCODE',
            'exit ([int]$result.exitCode)'
        )) {
            $script:updaterEntry | Should -Match ([regex]::Escape($token))
        }
        $script:updaterEntry | Should -Match ([regex]::Escape('The core updater keeps its existing error handling.'))
    }

    It 'copies and requires the resilient updater entry in every finalized package' {
        ($script:builder | Select-String -Pattern "'nexroute-updater-entry\.ps1'" -AllMatches).Matches.Count | Should -BeGreaterOrEqual 1
        $script:builder | Should -Match ([regex]::Escape("'.service/nexroute-updater-entry.ps1'"))
        $script:builder | Should -Match ([regex]::Escape('UpdaterEntryIncluded=$true'))
        $script:smoke | Should -Match ([regex]::Escape('$updaterEntry = Join-Path $testRoot ''.service\nexroute-updater-entry.ps1'''))
    }

    It 'makes the launcher contract part of the mandatory release desktop gate' {
        $script:desktopGate | Should -Match ([regex]::Escape('$launcherSmokePath=Join-Path $PSScriptRoot ''Test-WindowsLaunchers.ps1'''))
        $script:desktopGate | Should -Match ([regex]::Escape('$launcherResult=& $launcherSmokePath -ExtractDirectory $root'))
        $script:desktopGate | Should -Match ([regex]::Escape('LauncherContractExitCode=0'))
        $script:desktopGate | Should -Match ([regex]::Escape('UpdaterEntryExitCode=[int]$launcherResult.updaterEntryExitCode'))
        $script:desktopGate | Should -Match ([regex]::Escape('UpdaterVersion=[string]$launcherResult.updaterVersion'))
    }
}
