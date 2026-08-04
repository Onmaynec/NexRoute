Describe 'NexRoute 0.6.0 notification broker' {
    BeforeAll {
        $root=Split-Path -Parent $PSScriptRoot
        function Send-NrNotification { param($Title,$Message,$Level) return 'legacy' }
        . (Join-Path $root 'overlay/.service/next/nexroute-notifications.ps1')
    }

    It 'encodes Russian notification content as UTF-8 Base64 for the native process' {
        $title='NexRoute обновлён'
        $message='Стратегия переключена автоматически'
        $title64=ConvertTo-NrNotificationBase64 -Value $title
        $message64=ConvertTo-NrNotificationBase64 -Value $message
        [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($title64)) | Should -Be $title
        [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($message64)) | Should -Be $message
    }

    It 'creates bounded escaped ToastGeneric XML without control characters' {
        $payload=New-NrToastPayload -Title 'NexRoute <ready>' -Message "A&B`u{0001}" -Level Warning -TimeoutMilliseconds 99999 -AppId 'NexRoute.Tests'
        $payload.appId | Should -Be 'NexRoute.Tests'
        $payload.level | Should -Be 'warning'
        $payload.timeoutMilliseconds | Should -Be 15000
        $payload.xml | Should -Match 'ToastGeneric'
        $payload.xml | Should -Match 'NexRoute &lt;ready&gt;'
        $payload.xml | Should -Match 'A&amp;B'
        $payload.xml | Should -Not -Match ([char]1)
    }

    It 'uses the Windows toast path first and records confirmed delivery' {
        $fixture=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-notification-toast-'+[guid]::NewGuid().ToString('N'))
        $script:toastPayload=$null
        $script:nativeCalls=0
        try {
            New-Item -ItemType Directory -Path $fixture -Force | Out-Null
            $result=Send-NrNotification -Root $fixture -Title 'Маршрут готов' -Message 'Защищённый сервис доступен' -Level Info -ToastRunner {
                param($payload)
                $script:toastPayload=$payload
                [pscustomobject]@{ delivered=$true; setting='Enabled' }
            } -Runner {
                $script:nativeCalls++
                [pscustomobject]@{ exitCode=0; processId=777 }
            }

            $result.channel | Should -Be 'windows-toast'
            $result.attempts | Should -Be @('windows-toast')
            $result.error | Should -BeNullOrEmpty
            $script:nativeCalls | Should -Be 0
            $script:toastPayload.xml | Should -Match 'Маршрут готов'
            $script:toastPayload.timeoutMilliseconds | Should -Be 5000
            $history=Get-Content -LiteralPath $result.historyPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $history.channel | Should -Be 'windows-toast'
            @($history.attempts) | Should -Be @('windows-toast')
        } finally { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'falls back to the native balloon when toast is disabled' {
        $fixture=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-notification-native-'+[guid]::NewGuid().ToString('N'))
        $script:capturedArguments=$null
        try {
            New-Item -ItemType Directory -Path (Join-Path $fixture '.service/native') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $fixture '.service/native/NexRoute.Notifier.exe') -Value 'fixture' -Encoding ASCII
            $oldOs=$env:OS
            $env:OS='Windows_NT'
            try {
                $result=Send-NrNotification -Root $fixture -Title 'Обновление' -Message 'Готово' -Level Warning -TimeoutMilliseconds 99999 -DisableToast -Runner {
                    param($executable,$arguments)
                    $script:capturedArguments=[string[]]$arguments
                    [pscustomobject]@{ exitCode=0; processId=777 }
                }
            } finally { $env:OS=$oldOs }

            $result.channel | Should -Be 'native-balloon'
            $result.attempts | Should -Be @('windows-toast','native-balloon')
            $result.error | Should -Match 'disabled by NexRoute configuration'
            Test-Path -LiteralPath $result.historyPath -PathType Leaf | Should -BeTrue
            $script:capturedArguments | Should -Contain '--title64'
            $script:capturedArguments | Should -Contain '--message64'
            $script:capturedArguments | Should -Contain '--level'
            $script:capturedArguments | Should -Contain 'warning'
            $script:capturedArguments | Should -Contain '--timeout'
            $script:capturedArguments | Should -Contain '15000'
            $titleIndex=[Array]::IndexOf($script:capturedArguments,'--title64')
            $messageIndex=[Array]::IndexOf($script:capturedArguments,'--message64')
            [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($script:capturedArguments[$titleIndex+1])) | Should -Be 'Обновление'
            [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($script:capturedArguments[$messageIndex+1])) | Should -Be 'Готово'
            $history=Get-Content -LiteralPath $result.historyPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $history.channel | Should -Be 'native-balloon'
            @($history.attempts) | Should -Be @('windows-toast','native-balloon')
            $history.level | Should -Be 'Warning'
            $history.processId | Should -BeGreaterThan 0
        } finally { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'uses the final fallback and retains both toast and native failure reasons' {
        $fixture=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-notification-fallback-'+[guid]::NewGuid().ToString('N'))
        $script:fallbackCalls=0
        try {
            New-Item -ItemType Directory -Path $fixture -Force | Out-Null
            $result=Send-NrNotification -Root $fixture -Title 'NexRoute' -Message 'Service stopped' -Level Error -DisableToast -Fallback {
                param($title,$message,$level)
                $script:fallbackCalls++
                $title | Should -Be 'NexRoute'
                $message | Should -Be 'Service stopped'
                $level | Should -Be 'Error'
            }
            $result.channel | Should -Be 'injected-fallback'
            $result.attempts | Should -Be @('windows-toast','native-balloon','injected-fallback')
            $result.error | Should -Match 'Toast notifications are disabled'
            $result.error | Should -Match 'Native notifier is unavailable'
            $script:fallbackCalls | Should -Be 1
            $history=Get-Content -LiteralPath $result.historyPath -Raw | ConvertFrom-Json
            $history.channel | Should -Be 'injected-fallback'
            @($history.attempts) | Should -Be @('windows-toast','native-balloon','injected-fallback')
            $history.error | Should -Match 'Native notifier is unavailable'
        } finally { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'fails over when Windows reports toast delivery disabled' {
        $fixture=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-notification-setting-'+[guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path $fixture -Force | Out-Null
            $result=Send-NrNotification -Root $fixture -Title 'NexRoute' -Message 'Policy test' -Level Info -ToastRunner {
                param($payload)
                [pscustomobject]@{ delivered=$false; setting='DisabledByGroupPolicy' }
            } -Fallback { param($title,$message,$level) }
            $result.channel | Should -Be 'injected-fallback'
            $result.error | Should -Match 'DisabledByGroupPolicy'
        } finally { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'writes one atomic history document per notification without exposing temporary files' {
        $fixture=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-notification-history-'+[guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path $fixture -Force | Out-Null
            1..3 | ForEach-Object {
                Write-NrNotificationHistory -Root $fixture -Title ('Title '+$_) -Message ('Message '+$_) -Level Info -Channel console -Attempts @('console') | Out-Null
            }
            $historyDirectory=Join-Path $fixture '.service/notifications/history'
            @(Get-ChildItem -LiteralPath $historyDirectory -Filter '*.json' -File) | Should -HaveCount 3
            @(Get-ChildItem -LiteralPath $historyDirectory -Filter '*.tmp' -File -ErrorAction SilentlyContinue) | Should -HaveCount 0
        } finally { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'keeps the native notifier independent as the deterministic WinRT fallback' {
        $repositoryRoot=Split-Path -Parent $PSScriptRoot
        $source=Get-Content -LiteralPath (Join-Path $repositoryRoot 'native/NexRoute.Notifier/Program.cs') -Raw -Encoding UTF8
        foreach ($token in @('NotifyIcon','ShowBalloonTip','--self-test','--title64','--message64','Encoding.UTF8','ToolTipIcon.Error','ToolTipIcon.Warning')) {
            $source | Should -Match ([regex]::Escape($token))
        }
        $source | Should -Not -Match 'Windows\.UI\.Notifications|ToastNotificationManager|WinRT'
    }

    It 'implements Windows toast capability checks before using the native fallback' {
        $repositoryRoot=Split-Path -Parent $PSScriptRoot
        $broker=Get-Content -LiteralPath (Join-Path $repositoryRoot 'overlay/.service/next/nexroute-notifications.ps1') -Raw -Encoding UTF8
        foreach ($token in @('ToastNotificationManager','ToastGeneric','CreateToastNotifier','notifier.Setting','NEXROUTE_DISABLE_TOAST','windows-toast','native-balloon','DisabledByGroupPolicy')) {
            $broker | Should -Match ([regex]::Escape($token))
        }
        $broker.IndexOf('$attempts.Add(''windows-toast'')') | Should -BeLessThan $broker.IndexOf('$attempts.Add(''native-balloon'')')
    }

    It 'loads the broker after the legacy notification function' {
        $repositoryRoot=Split-Path -Parent $PSScriptRoot
        $loader=Get-Content -LiteralPath (Join-Path $repositoryRoot 'overlay/.service/next/nexroute-runtime-extensions.ps1') -Raw -Encoding UTF8
        $loader | Should -Match ([regex]::Escape('nexroute-notifications.ps1'))
        $loader.IndexOf('nexroute-notifications.ps1') | Should -BeGreaterThan $loader.IndexOf('nexroute-dot-snapshot-v2.ps1')
    }

    It 'requires the native notifier and its self-test in online and offline packages' {
        $repositoryRoot=Split-Path -Parent $PSScriptRoot
        $builder=Get-Content -LiteralPath (Join-Path $repositoryRoot 'scripts/Build-Package.ps1') -Raw -Encoding UTF8
        $releaseTest=Get-Content -LiteralPath (Join-Path $repositoryRoot 'scripts/Test-Release.ps1') -Raw -Encoding UTF8
        foreach ($token in @('NexRoute.Notifier.exe','NativeNotifierIncluded=$true','NativeNotifierSha256','notifierExecutable')) {
            $builder | Should -Match ([regex]::Escape($token))
        }
        foreach ($token in @('NexRoute.Notifier.exe','Native notifier self-test failed','NativeNotifierExitCode','NativeNotifierSha256')) {
            $releaseTest | Should -Match ([regex]::Escape($token))
        }
    }
}
