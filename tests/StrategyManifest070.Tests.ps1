Describe 'NexRoute 0.7.0 Strategy Manifest' {
    BeforeAll {
        $script:root = Split-Path -Parent $PSScriptRoot
        . (Join-Path $script:root 'overlay/.service/next/nexroute-strategy-refresh.ps1')
        . (Join-Path $script:root 'tests/fixtures/Strategy063.Renderer.ps1')
        $script:path = Join-Path $script:root 'overlay/.service/strategy-manifest.json'
        $script:golden = Get-Content -LiteralPath (Join-Path $script:root 'tests/fixtures/Strategy063.Catalog.json') -Raw -Encoding UTF8 | ConvertFrom-Json

        function New-NrManifestTestCopy {
            param([Parameter(Mandatory)][scriptblock]$Change)
            $target = Join-Path ([IO.Path]::GetTempPath()) ('nr-manifest-'+[guid]::NewGuid().ToString('N')+'.json')
            $doc = Get-Content -LiteralPath $script:path -Raw -Encoding UTF8 | ConvertFrom-Json
            & $Change $doc
            $doc | ConvertTo-Json -Depth 25 | Set-Content -LiteralPath $target -Encoding UTF8
            return $target
        }

        function New-NrGoldenSpec {
            param($Entry)
            return [pscustomobject][ordered]@{
                File=$Entry.File; Profile=$Entry.Profile; Family=$Entry.Family
                SniPrimary=$Entry.SniPrimary; SniSecondary=$Entry.SniSecondary
                SeqOvl=$Entry.SeqOvl; Repeats=$Entry.Repeats
                QuicRepeats=$Entry.QuicRepeats; DiscordRepeats=$Entry.DiscordRepeats
                Cutoff=$Entry.Cutoff
            }
        }
    }

    It 'preserves all 21 historical profiles and numeric parameters' {
        $manifest = Read-NrStrategyManifest -Path $script:path
        $manifest.StrategySetVersion | Should -Be '0.7.0'
        $manifest.UpstreamVersion | Should -Be '1.10.3'
        $manifest.Sha256 | Should -Match '^[0-9a-f]{64}$'
        $catalog = @($manifest.Catalog)
        $catalog.Count | Should -Be 21
        for ($i = 0; $i -lt 21; $i++) {
            $expected = $script:golden.profiles[$i]
            foreach ($field in @('File','Profile','Family','SniPrimary','SniSecondary','SeqOvl','Repeats','QuicRepeats','DiscordRepeats','Cutoff')) {
                $catalog[$i].$field | Should -Be $expected.$field
            }
        }
    }

    It 'produces byte-identical strategy BAT commands with the frozen v0.6.3 generator' {
        $catalog = @(Get-NexRoute063StrategyCatalog)
        $dir = Join-Path ([IO.Path]::GetTempPath()) ('nr-manifest-bat-'+[guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $template = @(
            '@echo off','rem NEXROUTE_PROFILE_BOOT',
            'start "zapret: %~n0" /min "%~dp0bin\winws.exe" --wf-tcp=80,443 --wf-udp=443 ^',
            '--filter-tcp=443 --dpi-desync=fake --new ^',
            '%NEXROUTE_SERVICE_TCP_ARGS% ^','%NEXROUTE_SERVICE_UDP_ARGS%'
        )
        try {
            for ($i = 0; $i -lt 21; $i++) {
                $old = New-NrGoldenSpec -Entry $script:golden.profiles[$i]
                $current = $catalog[$i]
                ((@(New-NexRoute063StrategyCommand -Spec $current)) -join [char]10) |
                    Should -BeExactly ((@(New-NrLegacy063StrategyCommand -Spec $old)) -join [char]10)
                $legacyPath = Join-Path $dir ('legacy-'+$i+'.bat')
                $currentPath = Join-Path $dir ('current-'+$i+'.bat')
                [IO.File]::WriteAllLines($legacyPath,$template,[Text.Encoding]::ASCII)
                [IO.File]::WriteAllLines($currentPath,$template,[Text.Encoding]::ASCII)
                Set-NrLegacy063StrategyFile -Path $legacyPath -Spec $old
                Set-NexRoute063StrategyFile -Path $currentPath -Spec $current
                ([Convert]::ToBase64String([IO.File]::ReadAllBytes($currentPath))) |
                    Should -BeExactly ([Convert]::ToBase64String([IO.File]::ReadAllBytes($legacyPath)))
            }
        } finally {
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'provides deterministic manifest and per-profile SHA-256 and a safe UI projection' {
        $a = Read-NrStrategyManifest -Path $script:path
        $b = Read-NrStrategyManifest -Path $script:path
        $a.Sha256 | Should -Be $b.Sha256
        for ($i = 0; $i -lt 21; $i++) {
            (Get-NrManifestProfileSha256 -Profile $a.Profiles[$i]) |
                Should -Be (Get-NrManifestProfileSha256 -Profile $b.Profiles[$i])
        }
        $profile = Get-NrManifestStrategyByName -Name $a.Profiles[0].id -Path $script:path
        $profile.file | Should -Be $a.Profiles[0].file
        $profile.family | Should -Be $a.Profiles[0].family
    }

    It 'fails closed on unknown fields, invalid modes and semantic drift' {
        $file = New-NrManifestTestCopy { param($m) $m.profiles[0] | Add-Member -NotePropertyName 'command' -NotePropertyValue 'bad' }
        try { { Read-NrStrategyManifest -Path $file } | Should -Throw '*Unknown strategy manifest field*' }
        finally { Remove-Item -LiteralPath $file -Force }
        $file = New-NrManifestTestCopy { param($m) $m.profiles[0].tcp.modes = @('unsafe-mode') }
        try { { Read-NrStrategyManifest -Path $file } | Should -Throw '*Unsupported TCP desync mode*' }
        finally { Remove-Item -LiteralPath $file -Force }
        $file = New-NrManifestTestCopy { param($m) $m.profiles[0].tcp.modes = @('fake') }
        try { { Read-NrStrategyManifest -Path $file } | Should -Throw '*differs from the validated winws template*' }
        finally { Remove-Item -LiteralPath $file -Force }
    }

    It 'rejects payload traversal, unsafe file names and broad capture scopes' {
        $file = New-NrManifestTestCopy { param($m) $m.profiles[0].fakePayloads[0] = 'bin/../evil.bin' }
        try { { Read-NrStrategyManifest -Path $file } | Should -Throw '*Unsafe fake payload path*' }
        finally { Remove-Item -LiteralPath $file -Force }
        $file = New-NrManifestTestCopy { param($m) $m.profiles[0].file = '../general.bat' }
        try { { Read-NrStrategyManifest -Path $file } | Should -Throw '*Unsafe strategy file path*' }
        finally { Remove-Item -LiteralPath $file -Force }
        $file = New-NrManifestTestCopy { param($m) $m.profiles[0].udp.scopes.quic = '1-65535' }
        try { { Read-NrStrategyManifest -Path $file } | Should -Throw '*Unsafe UDP capture scope*' }
        finally { Remove-Item -LiteralPath $file -Force }
    }

    It 'fails on missing payloads, duplicate profiles and unknown schemaVersion' {
        $dir = Join-Path ([IO.Path]::GetTempPath()) ('nr-empty-bin-'+[guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $dir | Out-Null
        try { { Read-NrStrategyManifest -Path $script:path -PayloadRoot $dir } | Should -Throw '*references missing payload*' }
        finally { Remove-Item -LiteralPath $dir -Recurse -Force }
        $file = New-NrManifestTestCopy { param($m) $m.profiles[1].id = $m.profiles[0].id }
        try { { Read-NrStrategyManifest -Path $file } | Should -Throw '*Duplicate strategy profile*' }
        finally { Remove-Item -LiteralPath $file -Force }
        $file = New-NrManifestTestCopy { param($m) $m.schemaVersion = 2 }
        try { { Read-NrStrategyManifest -Path $file } | Should -Throw '*Unsupported strategy manifest schemaVersion*' }
        finally { Remove-Item -LiteralPath $file -Force }
    }
}
