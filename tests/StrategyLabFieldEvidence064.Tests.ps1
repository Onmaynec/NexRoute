Describe 'NexRoute 0.6.4 privacy-safe field evidence' {
    BeforeAll {
        $script:root = Split-Path -Parent $PSScriptRoot
        $script:generator = Join-Path $script:root 'scripts/New-StrategyLabFieldEvidence.ps1'
        $script:validator = Join-Path $script:root 'scripts/Test-StrategyLabFieldEvidence.ps1'
        $script:candidateSha = '6103d6f96f052693af890f3b446f82624ac1c73845d6f8795a458182726f85fa'

        function New-Nr064FieldLog {
            param(
                [Parameter(Mandatory)][string]$Path,
                [string]$CriticalStatus = 'OK',
                [string]$ControlStatus = 'OK',
                [switch]$UnknownTarget,
                [switch]$UnknownStatus
            )
            $firstStatus = if ($UnknownStatus) { 'MAYBE' } else { $CriticalStatus }
            $lines = @(
                'NEXROUTE STRATEGY LAB SESSION',
                '[1/21] general (ALT).bat',
                "  DiscordGateway           HTTP:$firstStatus TLS1.2:$CriticalStatus TLS1.3:$CriticalStatus | Ping: 35 ms",
                "  DiscordCDN               HTTP:$CriticalStatus TLS1.2:$CriticalStatus TLS1.3:$CriticalStatus | Ping: 28 ms",
                "  DiscordUpdates           HTTP:$CriticalStatus TLS1.2:$CriticalStatus TLS1.3:$CriticalStatus | Ping: 28 ms",
                "  YouTubeWeb               HTTP:$CriticalStatus TLS1.2:$CriticalStatus TLS1.3:$CriticalStatus | Ping: 43 ms",
                "  YouTubeShort             HTTP:$CriticalStatus TLS1.2:$CriticalStatus TLS1.3:$CriticalStatus | Ping: 45 ms",
                "  YouTubeImage             HTTP:$CriticalStatus TLS1.2:$CriticalStatus TLS1.3:$CriticalStatus | Ping: 46 ms",
                "  YouTubeVideoRedirect     HTTP:$CriticalStatus TLS1.2:$CriticalStatus TLS1.3:$CriticalStatus | Ping: 43 ms",
                "  GoogleMain               HTTP:$ControlStatus TLS1.2:$ControlStatus TLS1.3:$ControlStatus | Ping: 47 ms",
                "  CloudflareWeb            HTTP:$ControlStatus TLS1.2:$ControlStatus TLS1.3:$ControlStatus | Ping: 27 ms"
            )
            if ($UnknownTarget) { $lines += '  MysteryTarget             HTTP:OK TLS1.2:OK TLS1.3:OK | Ping: 10 ms' }
            $lines += @(
                '[2/21] general (ALT2).bat',
                '  DiscordGateway           HTTP:ERROR TLS1.2:ERROR TLS1.3:ERROR | Ping: 35 ms'
            )
            [System.IO.File]::WriteAllLines($Path, $lines, [System.Text.UTF8Encoding]::new($false))
        }
    }

    BeforeEach {
        $script:fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('nexroute-064-field-evidence-{0}' -f [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:fixtureRoot -Force | Out-Null
    }

    AfterEach { Remove-Item -LiteralPath $script:fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue }

    It 'generates byte-identical receipts for the same source log and candidate' {
        $log = Join-Path $script:fixtureRoot 'strategy-lab.txt'
        $first = Join-Path $script:fixtureRoot 'evidence-a.json'
        $second = Join-Path $script:fixtureRoot 'evidence-b.json'
        New-Nr064FieldLog -Path $log
        & $script:generator -Path $log -CandidateSha256 $script:candidateSha -OutputPath $first | Out-Null
        Start-Sleep -Milliseconds 30
        & $script:generator -Path $log -CandidateSha256 $script:candidateSha -OutputPath $second | Out-Null

        [Convert]::ToBase64String([IO.File]::ReadAllBytes($first)) | Should -Be ([Convert]::ToBase64String([IO.File]::ReadAllBytes($second)))
        $receipt = Get-Content -LiteralPath $first -Raw -Encoding UTF8 | ConvertFrom-Json
        $receipt.nexRouteVersion | Should -Be '0.6.4'
        $receipt.status | Should -Be 'passed'
        $receipt.strategy | Should -Be 'general (ALT).bat'
        $receipt.candidateSha256 | Should -Be $script:candidateSha
        $receipt.sourceLogSha256 | Should -Match '^[0-9a-f]{64}$'
        $receipt.canonicalPayloadSha256 | Should -Match '^[0-9a-f]{64}$'
        @($receipt.targets).Count | Should -Be 7
        @($receipt.controls).Count | Should -Be 2
    }

    It 'publishes a minimised receipt without user or network identity fields' {
        $log = Join-Path $script:fixtureRoot 'strategy-lab.txt'
        $receiptPath = Join-Path $script:fixtureRoot 'evidence.json'
        New-Nr064FieldLog -Path $log
        $review = & $script:generator -Path $log -CandidateSha256 $script:candidateSha -OutputPath $receiptPath -PrivacyReview
        $text = Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8

        $review.status | Should -Be 'privacy-review'
        @($review.excludedCategories) | Should -Contain 'provider'
        @($review.excludedCategories) | Should -Contain 'location'
        @($review.excludedCategories) | Should -Contain 'absolute-local-path'
        @($review.excludedCategories) | Should -Contain 'wall-clock-verification-time'
        $review.sourceLogPublished | Should -BeFalse
        $text | Should -Not -Match [regex]::Escape($script:fixtureRoot)
        $text | Should -Not -Match 'provider|location|verifiedUtc|username|ssid|macAddress'
    }

    It 'validates an untampered receipt against both candidate and source-log hashes' {
        $log = Join-Path $script:fixtureRoot 'strategy-lab.txt'
        $receiptPath = Join-Path $script:fixtureRoot 'evidence.json'
        New-Nr064FieldLog -Path $log
        & $script:generator -Path $log -CandidateSha256 $script:candidateSha -OutputPath $receiptPath | Out-Null
        $result = & $script:validator -ReceiptPath $receiptPath -SourceLogPath $log -CandidateSha256 $script:candidateSha
        $result.status | Should -Be 'valid'
        $result.canonicalPayloadSha256 | Should -Match '^[0-9a-f]{64}$'
    }

    It 'fails closed when a receipt is modified after generation' {
        $log = Join-Path $script:fixtureRoot 'strategy-lab.txt'
        $receiptPath = Join-Path $script:fixtureRoot 'evidence.json'
        New-Nr064FieldLog -Path $log
        & $script:generator -Path $log -CandidateSha256 $script:candidateSha -OutputPath $receiptPath | Out-Null
        $receipt = Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $receipt.strategy = 'tampered.bat'
        [IO.File]::WriteAllText($receiptPath, (($receipt | ConvertTo-Json -Depth 20 -Compress) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
        { & $script:validator -ReceiptPath $receiptPath } | Should -Throw '*canonical payload hash mismatch*'
    }

    It 'fails closed when the source log changes after receipt generation' {
        $log = Join-Path $script:fixtureRoot 'strategy-lab.txt'
        $receiptPath = Join-Path $script:fixtureRoot 'evidence.json'
        New-Nr064FieldLog -Path $log
        & $script:generator -Path $log -CandidateSha256 $script:candidateSha -OutputPath $receiptPath | Out-Null
        Add-Content -LiteralPath $log -Value 'tampered after receipt generation' -Encoding UTF8
        { & $script:validator -ReceiptPath $receiptPath -SourceLogPath $log } | Should -Throw '*source-log SHA-256 does not match*'
    }

    It 'fails closed on an incomplete critical target set' {
        $log = Join-Path $script:fixtureRoot 'incomplete.txt'
        New-Nr064FieldLog -Path $log
        $lines = @(Get-Content -LiteralPath $log -Encoding UTF8 | Where-Object { $_ -notmatch '^\s*YouTubeVideoRedirect\s+' })
        [IO.File]::WriteAllLines($log,$lines,[Text.UTF8Encoding]::new($false))
        { & $script:generator -Path $log -CandidateSha256 $script:candidateSha } | Should -Throw '*no single strategy passed*'
    }

    It 'fails when required targets are split across different strategies' {
        $log = Join-Path $script:fixtureRoot 'split.txt'
        $lines = @(
            '[1/2] first-half.bat',
            '  DiscordGateway           HTTP:OK TLS1.2:OK TLS1.3:OK',
            '  DiscordCDN               HTTP:OK TLS1.2:OK TLS1.3:OK',
            '  DiscordUpdates           HTTP:OK TLS1.2:OK TLS1.3:OK',
            '  GoogleMain               HTTP:OK TLS1.2:OK TLS1.3:OK',
            '  CloudflareWeb            HTTP:OK TLS1.2:OK TLS1.3:OK',
            '[2/2] second-half.bat',
            '  YouTubeWeb               HTTP:OK TLS1.2:OK TLS1.3:OK',
            '  YouTubeShort             HTTP:OK TLS1.2:OK TLS1.3:OK',
            '  YouTubeImage             HTTP:OK TLS1.2:OK TLS1.3:OK',
            '  YouTubeVideoRedirect     HTTP:OK TLS1.2:OK TLS1.3:OK',
            '  GoogleMain               HTTP:OK TLS1.2:OK TLS1.3:OK',
            '  CloudflareWeb            HTTP:OK TLS1.2:OK TLS1.3:OK'
        )
        [IO.File]::WriteAllLines($log,$lines,[Text.UTF8Encoding]::new($false))
        { & $script:generator -Path $log -CandidateSha256 $script:candidateSha } | Should -Throw '*no single strategy passed*'
    }

    It 'fails closed on unknown source targets and statuses' {
        $unknownTarget = Join-Path $script:fixtureRoot 'unknown-target.txt'
        $unknownStatus = Join-Path $script:fixtureRoot 'unknown-status.txt'
        New-Nr064FieldLog -Path $unknownTarget -UnknownTarget
        New-Nr064FieldLog -Path $unknownStatus -UnknownStatus
        { & $script:generator -Path $unknownTarget -CandidateSha256 $script:candidateSha } | Should -Throw '*unknown target*'
        { & $script:generator -Path $unknownStatus -CandidateSha256 $script:candidateSha } | Should -Throw '*unknown status*'
    }

    It 'rejects critical or control failures instead of producing a partial success receipt' {
        $critical = Join-Path $script:fixtureRoot 'critical-fail.txt'
        $control = Join-Path $script:fixtureRoot 'control-fail.txt'
        New-Nr064FieldLog -Path $critical -CriticalStatus 'ERROR'
        New-Nr064FieldLog -Path $control -ControlStatus 'ERROR'
        { & $script:generator -Path $critical -CandidateSha256 $script:candidateSha } | Should -Throw '*no single strategy passed*'
        { & $script:generator -Path $control -CandidateSha256 $script:candidateSha } | Should -Throw '*healthy GoogleMain and CloudflareWeb controls*'
    }

    It 'fails closed on unknown receipt schema and extra privacy fields' {
        $log = Join-Path $script:fixtureRoot 'strategy-lab.txt'
        $receiptPath = Join-Path $script:fixtureRoot 'evidence.json'
        New-Nr064FieldLog -Path $log
        & $script:generator -Path $log -CandidateSha256 $script:candidateSha -OutputPath $receiptPath | Out-Null
        $receipt = Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $receipt.schemaVersion = 99
        $receipt | Add-Member -NotePropertyName provider -NotePropertyValue 'must-not-be-published'
        [IO.File]::WriteAllText($receiptPath, (($receipt | ConvertTo-Json -Depth 20 -Compress) + [Environment]::NewLine), [Text.UTF8Encoding]::new($false))
        { & $script:validator -ReceiptPath $receiptPath } | Should -Throw '*unknown field*'
    }
}
