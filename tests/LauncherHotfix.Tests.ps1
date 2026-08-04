Describe 'NexRoute 0.6.1 Windows launcher hotfix' {
    BeforeAll {
        $root = Split-Path -Parent $PSScriptRoot
        $script:service = Get-Content -LiteralPath (Join-Path $root 'overlay/service.bat') -Raw
        $script:main = Get-Content -LiteralPath (Join-Path $root 'overlay/nexroute.bat') -Raw
        $script:update = Get-Content -LiteralPath (Join-Path $root 'overlay/nexroute-update.cmd') -Raw
        $script:smoke = Get-Content -LiteralPath (Join-Path $root 'scripts/Test-WindowsLaunchers.ps1') -Raw
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

    It 'accepts a representative Windows path with spaces and Cyrillic characters' {
        $candidate = 'C:\Users\Тест Пользователь\Downloads\NexRoute-0.6.1-win-x64'
        { [System.IO.Path]::GetFullPath($candidate) } | Should -Not -Throw
        [System.IO.Path]::GetFullPath($candidate) | Should -Be $candidate
    }
}
