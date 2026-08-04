Describe 'NexRoute 0.6.0 native Windows tray controller' {
    BeforeAll {
        $root=Split-Path -Parent $PSScriptRoot
        $source=Get-Content -LiteralPath (Join-Path $root 'native/NexRoute.Tray/Program.cs') -Raw -Encoding UTF8
        $dashboardSource=Get-Content -LiteralPath (Join-Path $root 'native/NexRoute.Dashboard/Program.cs') -Raw -Encoding UTF8
        $builder=Get-Content -LiteralPath (Join-Path $root 'scripts/Build-NativeTray.ps1') -Raw -Encoding UTF8
        $installer=Get-Content -LiteralPath (Join-Path $root 'overlay/.service/next/nexroute-tray-install.ps1') -Raw -Encoding UTF8
        $launcher=Get-Content -LiteralPath (Join-Path $root 'overlay/nexroute-tray.cmd') -Raw -Encoding UTF8
        $installerLauncher=Get-Content -LiteralPath (Join-Path $root 'overlay/nexroute-tray-install.cmd') -Raw -Encoding UTF8
        $packageBuilder=Get-Content -LiteralPath (Join-Path $root 'scripts/Build-Package.ps1') -Raw -Encoding UTF8
        $packageTest=Get-Content -LiteralPath (Join-Path $root 'scripts/Test-Package.ps1') -Raw -Encoding UTF8
    }

    It 'implements a native single-instance NotifyIcon controller with live service actions' {
        foreach ($token in @(
            'NotifyIcon','ContextMenuStrip','ServiceController','BuildMutexName','Enable NexRoute','Disable NexRoute','Restart NexRoute',
            'Open Dashboard','Open Validation Report','OpenValidationReport','NexRoute.Validation.exe',
            'Open Control Center','Check Update','Open Logs','Ctrl+Alt+N','RegisterHotKey','UnregisterHotKey','ShowBalloonTip'
        )) {
            $source | Should -Match ([regex]::Escape($token))
        }
        $source | Should -Match '--self-test'
        $source | Should -Match 'Service state changed'
        $source | Should -Match 'Verb = "runas"'
    }

    It 'requires the dashboard and validation viewer in its deterministic self-test' {
        $source | Should -Match ([regex]::Escape('Path.Combine(".service", "native", "NexRoute.Dashboard.exe")'))
        $source | Should -Match ([regex]::Escape('Path.Combine(".service", "native", "NexRoute.Validation.exe")'))
    }

    It 'compiles repository sources directly without NuGet network access or source rewriting' {
        $builder | Should -Match 'Microsoft\.NET/Framework64/v4\.0\.30319/csc\.exe'
        $builder | Should -Match '/target:winexe'
        $builder | Should -Match 'System\.Windows\.Forms\.dll'
        $builder | Should -Match 'System\.ServiceProcess\.dll'
        $builder | Should -Match "AssemblyName\]::GetAssemblyName"
        $builder | Should -Not -Match 'nuget|dotnet restore|Invoke-WebRequest|Download'
        $builder | Should -Not -Match 'Convert-NrMutableUiFields|MutableUiFields|Expected readonly UI field declaration'
        foreach ($field in @('metricSelector','strategySelector','themeSelector','accentSelector','chart','grid','resetZoomButton')) {
            $dashboardSource | Should -Match ("private\s+(?:ComboBox|Chart|DataGridView|Button)\s+"+[regex]::Escape($field)+"\s*;")
            $dashboardSource | Should -Not -Match ("private\s+readonly\s+[^;]+\s+"+[regex]::Escape($field)+"\s*;")
        }
    }

    It 'installs one interactive highest-privilege logon task and manages its lifecycle' {
        foreach ($token in @(
            "ValidateSet('Install','Uninstall','Start','Stop','Status')",'NexRoute Native Tray','Register-ScheduledTask',
            'New-ScheduledTaskTrigger -AtLogOn','LogonType Interactive','RunLevel Highest','MultipleInstances IgnoreNew',
            'RestartCount 3','Get-NrTrayProcesses','Stop-NrTrayProcesses','Start-NrNativeTray','Unregister-ScheduledTask'
        )) {
            $installer | Should -Match ([regex]::Escape($token))
        }
        $installerLauncher | Should -Match 'nexroute-tray-install\.ps1'
        $installerLauncher | Should -Match 'if not defined MODE set "MODE=Install"'
    }

    It 'uses the native executable first and preserves the PowerShell fallback' {
        $launcher | Should -Match '\.service\\native\\NexRoute\.Tray\.exe'
        $launcher | Should -Match 'if exist "%NATIVE%"'
        $launcher | Should -Match 'nexroute-tray\.ps1'
        $launcher.IndexOf('NexRoute.Tray.exe') | Should -BeLessThan $launcher.IndexOf('nexroute-tray.ps1')
    }

    It 'requires compilation and native self-test for both online and offline packages' {
        $packageBuilder | Should -Match 'Build-NativeTray\.ps1'
        $packageBuilder | Should -Match '\.service/native/NexRoute\.Tray\.exe'
        $packageBuilder | Should -Match 'NativeTrayIncluded=\$true'
        $packageTest | Should -Match 'NexRoute\.Tray\.exe'
        $packageTest | Should -Match '--self-test'
        $packageTest | Should -Match 'Native tray self-test failed'
        $packageTest | Should -Match "AssemblyName\]::GetAssemblyName"
    }
}
