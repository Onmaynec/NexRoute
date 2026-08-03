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

    It 'launches the native notifier with bounded arguments and records delivery history' {
        $fixture=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-notification-native-'+[guid]::NewGuid().ToString('N'))
        $script:capturedArguments=$null
        try {
            New-Item -ItemType Directory -Path (Join-Path $fixture '.service/native') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $fixture '.service/native/NexRoute.Notifier.exe') -Value 'fixture' -Encoding ASCII
            $oldOs=$env:OS
            $env:OS='Windows_NT'
            try {
                $result=Send-NrNotification -Root $fixture -Title 'Обновление' -Message 'Готово' -Level Warning -TimeoutMilliseconds 99999 -Runner {
                    param($executable,$arguments)
                    $script:capturedArguments=[string[]]$arguments
                    [pscustomobject]@{ exitCode=0; processId=777 }
                }
            } finally { $env:OS=$oldOs }

            $result.channel | Should -Be 'native-balloon'
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
            $history.level | Should -Be 'Warning'
            $history.processId | Should -BeGreaterThan 0
        } finally { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'uses a fallback and retains the native failure reason when the executable is unavailable' {
        $fixture=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-notification-fallback-'+[guid]::NewGuid().ToString('N'))
        $script:fallbackCalls=0
        try {
            New-Item -ItemType Directory -Path $fixture -Force | Out-Null
            $result=Send-NrNotification -Root $fixture -Title 'NexRoute' -Message 'Service stopped' -Level Error -Fallback {
                param($title,$message,$level)
                $script:fallbackCalls++
                $title | Should -Be 'NexRoute'
                $message | Should -Be 'Service stopped'
                $level | Should -Be 'Error'
            }
            $result.channel | Should -Be 'injected-fallback'
            $result.error | Should -Match 'Native notifier is unavailable'
            $script:fallbackCalls | Should -Be 1
            $history=Get-Content -LiteralPath $result.historyPath -Raw | ConvertFrom-Json
            $history.channel | Should -Be 'injected-fallback'
            $history.error | Should -Match 'Native notifier is unavailable'
        } finally { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'writes one atomic history document per notification without exposing temporary files' {
        $fixture=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-notification-history-'+[guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path $fixture -Force | Out-Null
            1..3 | ForEach-Object {
                Write-NrNotificationHistory -Root $fixture -Title ('Title '+$_) -Message ('Message '+$_) -Level Info -Channel console | Out-Null
            }
            $historyDirectory=Join-Path $fixture '.service/notifications/history'
            @(Get-ChildItem -LiteralPath $historyDirectory -Filter '*.json' -File) | Should -HaveCount 3
            @(Get-ChildItem -LiteralPath $historyDirectory -Filter '*.tmp' -File -ErrorAction SilentlyContinue) | Should -HaveCount 0
        } finally { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'defines a native notifier that is independent of the WinRT toast API' {
        $repositoryRoot=Split-Path -Parent $PSScriptRoot
        $source=Get-Content -LiteralPath (Join-Path $repositoryRoot 'native/NexRoute.Notifier/Program.cs') -Raw -Encoding UTF8
        foreach ($token in @('NotifyIcon','ShowBalloonTip','--self-test','--title64','--message64','Encoding.UTF8','ToolTipIcon.Error','ToolTipIcon.Warning')) {
            $source | Should -Match ([regex]::Escape($token))
        }
        $source | Should -Not -Match 'Windows\.UI\.Notifications|ToastNotificationManager|WinRT'
    }
}
