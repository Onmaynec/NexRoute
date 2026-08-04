Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-NexRoute063Sha256 {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-NexRoute063StrategyCatalog {
    return @(
        [pscustomobject]@{ File='general.bat'; Profile='nr063-01-auto-sniext-ts'; Family='auto-multisplit-sniext-ts'; SniPrimary='www.google.com'; SniSecondary='ya.ru'; SeqOvl=679; Repeats=8; QuicRepeats=11; DiscordRepeats=6; Cutoff=4 },
        [pscustomobject]@{ File='general (ALT).bat'; Profile='nr063-02-static-fakedsplit-ts'; Family='static-fakedsplit-ts'; SniPrimary='www.google.com'; SniSecondary='ya.ru'; SeqOvl=0; Repeats=8; QuicRepeats=11; DiscordRepeats=6; Cutoff=4 },
        [pscustomobject]@{ File='general (ALT2).bat'; Profile='nr063-03-auto-multidisorder-ts'; Family='auto-multidisorder-ts'; SniPrimary='www.google.com'; SniSecondary='ya.ru'; SeqOvl=0; Repeats=11; QuicRepeats=11; DiscordRepeats=5; Cutoff=4 },
        [pscustomobject]@{ File='general (ALT3).bat'; Profile='nr063-04-auto-hostfakesplit-ts'; Family='auto-hostfakesplit-ts'; SniPrimary='www.google.com'; SniSecondary='ya.ru'; SeqOvl=0; Repeats=8; QuicRepeats=11; DiscordRepeats=5; Cutoff=4 },
        [pscustomobject]@{ File='general (ALT4).bat'; Profile='nr063-05-static-multisplit-badseq'; Family='static-multisplit-badseq'; SniPrimary='www.google.com'; SniSecondary='ya.ru'; SeqOvl=681; Repeats=8; QuicRepeats=10; DiscordRepeats=6; Cutoff=3 },
        [pscustomobject]@{ File='general (ALT5).bat'; Profile='nr063-06-syndata-multidisorder'; Family='syndata-multidisorder'; SniPrimary='www.google.com'; SniSecondary='ya.ru'; SeqOvl=0; Repeats=0; QuicRepeats=11; DiscordRepeats=6; Cutoff=4 },
        [pscustomobject]@{ File='general (ALT6).bat'; Profile='nr063-07-static-multisplit-ts-681'; Family='static-multisplit-ts'; SniPrimary='www.google.com'; SniSecondary='ya.ru'; SeqOvl=681; Repeats=8; QuicRepeats=11; DiscordRepeats=4; Cutoff=4 },
        [pscustomobject]@{ File='general (ALT7).bat'; Profile='nr063-08-auto-sniext-ts-ya'; Family='auto-multisplit-sniext-ts'; SniPrimary='ya.ru'; SniSecondary='www.google.com'; SeqOvl=679; Repeats=8; QuicRepeats=10; DiscordRepeats=4; Cutoff=4 },
        [pscustomobject]@{ File='general (ALT8).bat'; Profile='nr063-09-auto-fake-badseq'; Family='auto-fake-badseq'; SniPrimary='www.google.com'; SniSecondary='ya.ru'; SeqOvl=0; Repeats=8; QuicRepeats=9; DiscordRepeats=5; Cutoff=3 },
        [pscustomobject]@{ File='general (ALT9).bat'; Profile='nr063-10-auto-fakedsplit-badseq'; Family='auto-fakedsplit-badseq'; SniPrimary='www.google.com'; SniSecondary='ya.ru'; SeqOvl=0; Repeats=8; QuicRepeats=11; DiscordRepeats=4; Cutoff=4 },
        [pscustomobject]@{ File='general (ALT10).bat'; Profile='nr063-11-auto-multisplit-ts-652'; Family='auto-multisplit-ts'; SniPrimary='www.google.com'; SniSecondary='ya.ru'; SeqOvl=652; Repeats=8; QuicRepeats=11; DiscordRepeats=4; Cutoff=3 },
        [pscustomobject]@{ File='general (ALT11).bat'; Profile='nr063-12-hostfakesplit-only-ts'; Family='hostfakesplit-only-ts'; SniPrimary='www.google.com'; SniSecondary='ya.ru'; SeqOvl=0; Repeats=0; QuicRepeats=10; DiscordRepeats=5; Cutoff=4 },
        [pscustomobject]@{ File='general (ALT12).bat'; Profile='nr063-13-static-stun2-hybrid'; Family='static-stun2-hybrid'; SniPrimary='www.google.com'; SniSecondary='ya.ru'; SeqOvl=664; Repeats=8; QuicRepeats=11; DiscordRepeats=4; Cutoff=4 },
        [pscustomobject]@{ File='general (EXP).bat'; Profile='nr063-14-exp-auto-stun2'; Family='exp-auto-stun2'; SniPrimary='www.google.com'; SniSecondary='ya.ru'; SeqOvl=480; Repeats=8; QuicRepeats=12; DiscordRepeats=4; Cutoff=4 },
        [pscustomobject]@{ File='general (FAKE TLS AUTO).bat'; Profile='nr063-15-auto-multidisorder-badseq'; Family='auto-multidisorder-badseq'; SniPrimary='www.google.com'; SniSecondary='ya.ru'; SeqOvl=0; Repeats=11; QuicRepeats=11; DiscordRepeats=6; Cutoff=4 },
        [pscustomobject]@{ File='general (FAKE TLS AUTO ALT).bat'; Profile='nr063-16-auto-fakedsplit-ts'; Family='auto-fakedsplit-ts'; SniPrimary='www.google.com'; SniSecondary='ya.ru'; SeqOvl=0; Repeats=8; QuicRepeats=11; DiscordRepeats=6; Cutoff=4 },
        [pscustomobject]@{ File='general (FAKE TLS AUTO ALT2).bat'; Profile='nr063-17-auto-hostfakesplit-altorder'; Family='auto-hostfakesplit-altorder'; SniPrimary='www.google.com'; SniSecondary='ya.ru'; SeqOvl=0; Repeats=8; QuicRepeats=11; DiscordRepeats=5; Cutoff=4 },
        [pscustomobject]@{ File='general (FAKE TLS AUTO ALT3).bat'; Profile='nr063-18-auto-multisplit-ts-681'; Family='auto-multisplit-ts'; SniPrimary='www.google.com'; SniSecondary='ya.ru'; SeqOvl=681; Repeats=8; QuicRepeats=12; DiscordRepeats=4; Cutoff=3 },
        [pscustomobject]@{ File='general (SIMPLE FAKE).bat'; Profile='nr063-19-simple-static-fake-ts'; Family='static-fake-ts'; SniPrimary='www.google.com'; SniSecondary='ya.ru'; SeqOvl=0; Repeats=8; QuicRepeats=10; DiscordRepeats=6; Cutoff=3 },
        [pscustomobject]@{ File='general (SIMPLE FAKE ALT).bat'; Profile='nr063-20-simple-auto-fake-ts'; Family='auto-fake-ts'; SniPrimary='www.google.com'; SniSecondary='ya.ru'; SeqOvl=0; Repeats=8; QuicRepeats=10; DiscordRepeats=5; Cutoff=3 },
        [pscustomobject]@{ File='general (SIMPLE FAKE ALT2).bat'; Profile='nr063-21-auto-multisplit-badseq'; Family='auto-multisplit-badseq'; SniPrimary='ya.ru'; SniSecondary='www.google.com'; SeqOvl=568; Repeats=8; QuicRepeats=11; DiscordRepeats=4; Cutoff=4 }
    )
}

function Get-NexRoute063TcpArguments {
    param(
        [Parameter(Mandatory)]$Spec,
        [Parameter(Mandatory)][ValidateSet('Discord','YouTube','General','Fallback','Game')][string]$Scope
    )

    $sni = if ($Scope -in @('Discord','YouTube')) { [string]$Spec.SniPrimary } else { [string]$Spec.SniSecondary }
    $repeats = [int]$Spec.Repeats
    $seqOvl = [int]$Spec.SeqOvl

    switch ([string]$Spec.Family) {
        'auto-multisplit-sniext-ts' {
            return ('--dpi-desync=fake,multisplit --dpi-desync-split-seqovl={0} --dpi-desync-split-pos=2,sniext+1 --dpi-desync-fooling=ts --dpi-desync-repeats={1} --dpi-desync-split-seqovl-pattern="%BIN%tls_clienthello_www_google_com.bin" --dpi-desync-fake-tls=^! --dpi-desync-fake-tls-mod=rnd,dupsid,sni={2}' -f $seqOvl,$repeats,$sni)
        }
        'static-fakedsplit-ts' {
            return ('--dpi-desync=fake,fakedsplit --dpi-desync-repeats={0} --dpi-desync-fooling=ts --dpi-desync-fakedsplit-pattern=0x00 --dpi-desync-fake-tls="%BIN%stun.bin" --dpi-desync-fake-tls="%BIN%tls_clienthello_www_google_com.bin"' -f $repeats)
        }
        'auto-multidisorder-ts' {
            return ('--dpi-desync=fake,multidisorder --dpi-desync-split-pos=1,midsld --dpi-desync-repeats={0} --dpi-desync-fooling=ts --dpi-desync-fake-tls=0x00000000 --dpi-desync-fake-tls=^! --dpi-desync-fake-tls-mod=rnd,dupsid,sni={1}' -f $repeats,$sni)
        }
        'auto-hostfakesplit-ts' {
            return ('--dpi-desync=fake,hostfakesplit --dpi-desync-repeats={0} --dpi-desync-fooling=ts --dpi-desync-fake-tls=^! --dpi-desync-fake-tls-mod=rnd,dupsid,sni={1} --dpi-desync-hostfakesplit-mod=host={1}' -f $repeats,$sni)
        }
        'static-multisplit-badseq' {
            return ('--dpi-desync=fake,multisplit --dpi-desync-split-seqovl={0} --dpi-desync-split-pos=1 --dpi-desync-repeats={1} --dpi-desync-fooling=badseq --dpi-desync-badseq-increment=1000 --dpi-desync-split-seqovl-pattern="%BIN%tls_clienthello_www_google_com.bin" --dpi-desync-fake-tls="%BIN%tls_clienthello_www_google_com.bin"' -f $seqOvl,$repeats)
        }
        'syndata-multidisorder' {
            return '--filter-l3=ipv4 --dpi-desync=syndata,multidisorder'
        }
        'static-multisplit-ts' {
            return ('--dpi-desync=fake,multisplit --dpi-desync-split-seqovl={0} --dpi-desync-split-pos=1 --dpi-desync-fooling=ts --dpi-desync-repeats={1} --dpi-desync-split-seqovl-pattern="%BIN%tls_clienthello_www_google_com.bin" --dpi-desync-fake-tls="%BIN%stun.bin" --dpi-desync-fake-tls="%BIN%tls_clienthello_www_google_com.bin"' -f $seqOvl,$repeats)
        }
        'auto-fake-badseq' {
            return ('--dpi-desync=fake --dpi-desync-repeats={0} --dpi-desync-fooling=badseq --dpi-desync-badseq-increment=2 --dpi-desync-fake-tls=^! --dpi-desync-fake-tls-mod=rnd,dupsid,sni={1}' -f $repeats,$sni)
        }
        'auto-fakedsplit-badseq' {
            return ('--dpi-desync=fake,fakedsplit --dpi-desync-repeats={0} --dpi-desync-fooling=badseq --dpi-desync-badseq-increment=1000 --dpi-desync-fakedsplit-pattern=0x00 --dpi-desync-fake-tls=^! --dpi-desync-fake-tls-mod=rnd,dupsid,sni={1}' -f $repeats,$sni)
        }
        'auto-multisplit-ts' {
            return ('--dpi-desync=fake,multisplit --dpi-desync-split-seqovl={0} --dpi-desync-split-pos=1 --dpi-desync-fooling=ts --dpi-desync-repeats={1} --dpi-desync-split-seqovl-pattern="%BIN%tls_clienthello_www_google_com.bin" --dpi-desync-fake-tls-mod=rnd,dupsid,sni={2}' -f $seqOvl,$repeats,$sni)
        }
        'hostfakesplit-only-ts' {
            return ('--dpi-desync=hostfakesplit --dpi-desync-fooling=ts --dpi-desync-hostfakesplit-mod=host={0}' -f $sni)
        }
        'static-stun2-hybrid' {
            return ('--dpi-desync=fake,multisplit --dpi-desync-split-seqovl={0} --dpi-desync-split-pos=1 --dpi-desync-fooling=ts --dpi-desync-repeats={1} --dpi-desync-split-seqovl-pattern="%BIN%tls_clienthello_max_ru.bin" --dpi-desync-fake-tls="%BIN%stun.bin" --dpi-desync-fake-tls="%BIN%tls_clienthello_max_ru.bin"' -f $seqOvl,$repeats)
        }
        'exp-auto-stun2' {
            return ('--dpi-desync=fake,multisplit --dpi-desync-split-seqovl={0} --dpi-desync-split-pos=1 --dpi-desync-fooling=ts --dpi-desync-repeats={1} --dpi-desync-split-seqovl-pattern="%BIN%stun2.bin" --dpi-desync-fake-tls="%BIN%tls_clienthello_max_ru.bin" --dpi-desync-fake-tls-mod=rnd,dupsid,sni={2}' -f $seqOvl,$repeats,$sni)
        }
        'auto-multidisorder-badseq' {
            return ('--dpi-desync=fake,multidisorder --dpi-desync-split-pos=1,midsld --dpi-desync-repeats={0} --dpi-desync-fooling=badseq --dpi-desync-badseq-increment=1000 --dpi-desync-fake-tls=0x00000000 --dpi-desync-fake-tls=^! --dpi-desync-fake-tls-mod=rnd,dupsid,sni={1}' -f $repeats,$sni)
        }
        'auto-fakedsplit-ts' {
            return ('--dpi-desync=fake,fakedsplit --dpi-desync-repeats={0} --dpi-desync-fooling=ts --dpi-desync-fakedsplit-pattern=0x00 --dpi-desync-fake-tls=0x00000000 --dpi-desync-fake-tls=^! --dpi-desync-fake-tls-mod=rnd,dupsid,sni={1}' -f $repeats,$sni)
        }
        'auto-hostfakesplit-altorder' {
            return ('--dpi-desync=fake,hostfakesplit --dpi-desync-repeats={0} --dpi-desync-fooling=ts --dpi-desync-fake-tls=^! --dpi-desync-fake-tls-mod=rnd,dupsid,sni={1} --dpi-desync-hostfakesplit-mod=host={1},altorder=1' -f $repeats,$sni)
        }
        'static-fake-ts' {
            return ('--dpi-desync=fake --dpi-desync-repeats={0} --dpi-desync-fooling=ts --dpi-desync-fake-tls="%BIN%stun.bin" --dpi-desync-fake-tls="%BIN%tls_clienthello_www_google_com.bin"' -f $repeats)
        }
        'auto-fake-ts' {
            return ('--dpi-desync=fake --dpi-desync-repeats={0} --dpi-desync-fooling=ts --dpi-desync-fake-tls=0x00000000 --dpi-desync-fake-tls=^! --dpi-desync-fake-tls-mod=rnd,dupsid,sni={1}' -f $repeats,$sni)
        }
        'auto-multisplit-badseq' {
            return ('--dpi-desync=fake,multisplit --dpi-desync-split-seqovl={0} --dpi-desync-split-pos=1 --dpi-desync-repeats={1} --dpi-desync-fooling=badseq --dpi-desync-badseq-increment=1000 --dpi-desync-split-seqovl-pattern="%BIN%tls_clienthello_www_google_com.bin" --dpi-desync-fake-tls=^! --dpi-desync-fake-tls-mod=rnd,dupsid,sni={2}' -f $seqOvl,$repeats,$sni)
        }
        default { throw "Unsupported NexRoute 0.6.3 strategy family: $($Spec.Family)" }
    }
}

function Write-NexRoute063HostList {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string[]]$Domains
    )
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $content = ($Domains | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ } | Sort-Object -Unique) -join "`r`n"
    [System.IO.File]::WriteAllText($Path, ($content + "`r`n"), [System.Text.Encoding]::ASCII)
}

function New-NexRoute063StrategyCommand {
    param([Parameter(Mandatory)]$Spec)

    $discordArgs = Get-NexRoute063TcpArguments -Spec $Spec -Scope Discord
    $youtubeArgs = Get-NexRoute063TcpArguments -Spec $Spec -Scope YouTube
    $generalArgs = Get-NexRoute063TcpArguments -Spec $Spec -Scope General
    $fallbackArgs = Get-NexRoute063TcpArguments -Spec $Spec -Scope Fallback
    $gameArgs = Get-NexRoute063TcpArguments -Spec $Spec -Scope Game
    $gameArgs += (' --dpi-desync-any-protocol=1 --dpi-desync-cutoff=n{0}' -f [int]$Spec.Cutoff)
    $httpFakeSuffix = if ([string]$Spec.Family -in @('syndata-multidisorder','hostfakesplit-only-ts')) { '' } else { ' --dpi-desync-fake-http="%BIN%tls_clienthello_max_ru.bin"' }

    $lines = @(
        'start "zapret: %~n0" /min "%BIN%winws.exe" --wf-tcp=80,443,2053,2083,2087,2096,8443,%GameFilterTCP% --wf-udp=443,19294-19344,50000-50100,%GameFilterUDP% ^',
        ('--filter-l7=quic --hostlist="%LISTS%list-nexroute-youtube-critical.txt" --hostlist="%LISTS%list-google.txt" --hostlist="%LISTS%list-general.txt" --hostlist="%LISTS%list-general-user.txt" --hostlist-exclude="%LISTS%list-exclude.txt" --hostlist-exclude="%LISTS%list-exclude-user.txt" --ipset-exclude="%LISTS%ipset-exclude.txt" --ipset-exclude="%LISTS%ipset-exclude-user.txt" --dpi-desync=fake --dpi-desync-repeats={0} --dpi-desync-fake-quic="%BIN%quic_initial_www_google_com.bin" --new ^' -f [int]$Spec.QuicRepeats),
        ('--filter-udp=19294-19344,50000-50100 --filter-l7=discord,stun,unknown --dpi-desync=fake --dpi-desync-fake-discord="%BIN%stun.bin" --dpi-desync-fake-discord="%BIN%ACTIVE_DISCORD_UDP.bin" --dpi-desync-fake-stun="%BIN%ACTIVE_DISCORD_UDP.bin" --dpi-desync-fake-unknown-udp="%BIN%quic_initial_www_google_com.bin" --dpi-desync-fake-unknown-udp="%BIN%ACTIVE_DISCORD_UDP.bin" --dpi-desync-repeats={0} --new ^' -f [int]$Spec.DiscordRepeats),
        ('--filter-tcp=443,2053,2083,2087,2096,8443 --hostlist="%LISTS%list-nexroute-discord-critical.txt" --hostlist-domains=discord.media {0} --new ^' -f $discordArgs),
        ('--filter-tcp=443 --hostlist="%LISTS%list-nexroute-youtube-critical.txt" --hostlist="%LISTS%list-google.txt" --ip-id=zero {0} --new ^' -f $youtubeArgs),
        ('--filter-tcp=80,443 --hostlist="%LISTS%list-nexroute-discord-critical.txt" --hostlist="%LISTS%list-general.txt" --hostlist="%LISTS%list-general-user.txt" --hostlist-exclude="%LISTS%list-exclude.txt" --hostlist-exclude="%LISTS%list-exclude-user.txt" --ipset-exclude="%LISTS%ipset-exclude.txt" --ipset-exclude="%LISTS%ipset-exclude-user.txt" {0}{1} --new ^' -f $generalArgs,$httpFakeSuffix),
        ('--filter-udp=443 --ipset="%LISTS%ipset-all.txt" --hostlist-exclude="%LISTS%list-exclude.txt" --hostlist-exclude="%LISTS%list-exclude-user.txt" --ipset-exclude="%LISTS%ipset-exclude.txt" --ipset-exclude="%LISTS%ipset-exclude-user.txt" --dpi-desync=fake --dpi-desync-repeats={0} --dpi-desync-fake-quic="%BIN%quic_initial_www_google_com.bin" --new ^' -f [int]$Spec.QuicRepeats),
        ('--filter-tcp=80,443,8443 --ipset="%LISTS%ipset-all.txt" --hostlist-exclude="%LISTS%list-exclude.txt" --hostlist-exclude="%LISTS%list-exclude-user.txt" --ipset-exclude="%LISTS%ipset-exclude.txt" --ipset-exclude="%LISTS%ipset-exclude-user.txt" {0}{1} --new ^' -f $fallbackArgs,$httpFakeSuffix),
        ('--filter-tcp=%GameFilterTCP% --ipset="%LISTS%ipset-all.txt" --ipset-exclude="%LISTS%ipset-exclude.txt" --ipset-exclude="%LISTS%ipset-exclude-user.txt" {0}{1} --new ^' -f $gameArgs,$httpFakeSuffix),
        ('--filter-udp=%GameFilterUDP% --ipset="%LISTS%ipset-all.txt" --ipset-exclude="%LISTS%ipset-exclude.txt" --ipset-exclude="%LISTS%ipset-exclude-user.txt" --dpi-desync=fake --dpi-desync-repeats=10 --dpi-desync-any-protocol=1 --dpi-desync-fake-unknown-udp="%BIN%quic_initial_4pda.to.bin" --dpi-desync-fake-unknown-udp="%BIN%ACTIVE_GAME_UDP.bin" --dpi-desync-cutoff=n{0} ^' -f [int]$Spec.Cutoff),
        '%NEXROUTE_SERVICE_TCP_ARGS% ^',
        '%NEXROUTE_SERVICE_UDP_ARGS%'
    )
    return $lines
}

function Set-NexRoute063StrategyFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Spec
    )

    $lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) { [void]$lines.Add($line) }
    $startIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '(?i)^\s*start\s+.+winws\.exe') { $startIndex = $i; break }
    }
    if ($startIndex -lt 0) { throw "Strategy has no winws command: $Path" }

    $endIndex = $startIndex
    while ($endIndex -lt ($lines.Count - 1) -and $lines[$endIndex].TrimEnd().EndsWith('^')) { $endIndex++ }
    if ($endIndex -le $startIndex) { throw "Strategy winws command is not multiline: $Path" }

    for ($i = $endIndex; $i -ge $startIndex; $i--) { $lines.RemoveAt($i) }
    $replacement = @(New-NexRoute063StrategyCommand -Spec $Spec)
    for ($i = 0; $i -lt $replacement.Count; $i++) { $lines.Insert($startIndex + $i, $replacement[$i]) }

    $marker = ('rem NEXROUTE_STRATEGY_REFRESH_063 {0}' -f $Spec.Profile)
    $markerIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -like 'rem NEXROUTE_STRATEGY_REFRESH_063*') { $markerIndex = $i; break }
    }
    if ($markerIndex -ge 0) { $lines[$markerIndex] = $marker }
    else {
        $insertIndex = [Math]::Min(2, $lines.Count)
        $lines.Insert($insertIndex, $marker)
    }

    [System.IO.File]::WriteAllLines($Path, $lines, [System.Text.Encoding]::ASCII)
}

function Assert-NexRoute063Payloads {
    param([Parameter(Mandatory)][string]$Root)
    foreach ($relativePath in @(
        'bin/winws.exe',
        'bin/quic_initial_www_google_com.bin',
        'bin/quic_initial_4pda.to.bin',
        'bin/ACTIVE_DISCORD_UDP.bin',
        'bin/ACTIVE_GAME_UDP.bin',
        'bin/stun.bin',
        'bin/stun2.bin',
        'bin/tls_clienthello_www_google_com.bin',
        'bin/tls_clienthello_max_ru.bin'
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $Root $relativePath) -PathType Leaf)) {
            throw "NexRoute 0.6.3 strategy refresh requires payload: $relativePath"
        }
    }
}

function Update-NexRoute063PatchReport {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$RefreshReport
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Patch report was not found: $Path" }
    $patchReport = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($item in @($RefreshReport.strategies)) {
        $target = ([string]$item.file).Replace('\','/')
        $entry = @($patchReport.patches | Where-Object { ([string]$_.target).Replace('\','/') -eq $target }) | Select-Object -First 1
        if (-not $entry) { throw "Patch report has no strategy target: $target" }
        $entry.afterSha256 = [string]$item.afterSha256
        $entry.operations = [int]$entry.operations + 1
        if ($entry.PSObject.Properties.Name -contains 'refreshProfile') { $entry.refreshProfile = [string]$item.profile }
        else { $entry | Add-Member -NotePropertyName refreshProfile -NotePropertyValue ([string]$item.profile) }
    }
    $patchReport.summary.operationCount = [int]$patchReport.summary.operationCount + @($RefreshReport.strategies).Count
    $refreshMetadata = [ordered]@{
        schemaVersion = 1
        strategyCount = @($RefreshReport.strategies).Count
        criticalListCount = @($RefreshReport.lists).Count
        report = '.service/strategy-refresh-report.json'
    }
    if ($patchReport.PSObject.Properties.Name -contains 'strategyRefresh') { $patchReport.strategyRefresh = $refreshMetadata }
    else { $patchReport | Add-Member -NotePropertyName strategyRefresh -NotePropertyValue $refreshMetadata }
    $json = $patchReport | ConvertTo-Json -Depth 12
    [System.IO.File]::WriteAllText($Path, ($json + "`r`n"), [System.Text.UTF8Encoding]::new($false))
    return [int]$patchReport.summary.operationCount
}

function Invoke-NexRoute063StrategyRefresh {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$PatchReportPath
    )

    $rootPath = [System.IO.Path]::GetFullPath($Root)
    Assert-NexRoute063Payloads -Root $rootPath
    $catalog = @(Get-NexRoute063StrategyCatalog)
    if ($catalog.Count -ne 21) { throw "Expected 21 NexRoute 0.6.3 strategy profiles, got $($catalog.Count)." }
    if (@($catalog.Profile | Sort-Object -Unique).Count -ne 21) { throw 'NexRoute 0.6.3 strategy profile IDs must be unique.' }

    $listsRoot = Join-Path $rootPath 'lists'
    $discordListPath = Join-Path $listsRoot 'list-nexroute-discord-critical.txt'
    $youtubeListPath = Join-Path $listsRoot 'list-nexroute-youtube-critical.txt'
    Write-NexRoute063HostList -Path $discordListPath -Domains @(
        'gateway.discord.gg','cdn.discordapp.com','updates.discord.com','discord.com','discord.gg',
        'discordapp.com','discordapp.net','discord.media','discordcdn.com','stable.dl2.discordapp.net'
    )
    Write-NexRoute063HostList -Path $youtubeListPath -Domains @(
        'www.youtube.com','youtu.be','i.ytimg.com','redirector.googlevideo.com','youtube.com',
        'youtube-nocookie.com','ytimg.com','googlevideo.com','youtubei.googleapis.com',
        'youtube.googleapis.com','ggpht.com','yt3.ggpht.com'
    )

    $strategyReports = New-Object 'System.Collections.Generic.List[object]'
    foreach ($spec in $catalog) {
        $path = Join-Path $rootPath ([string]$spec.File)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing strategy file: $($spec.File)" }
        $before = Get-NexRoute063Sha256 -Path $path
        Set-NexRoute063StrategyFile -Path $path -Spec $spec
        $after = Get-NexRoute063Sha256 -Path $path
        if ($before -eq $after) { throw "Strategy refresh did not change: $($spec.File)" }
        $strategyReports.Add([pscustomobject]@{
            file = ([string]$spec.File).Replace('\','/')
            profile = [string]$spec.Profile
            family = [string]$spec.Family
            beforeSha256 = $before
            afterSha256 = $after
        })
    }

    $versionPath = Join-Path $rootPath '.service/version.txt'
    $version = if (Test-Path -LiteralPath $versionPath -PathType Leaf) { (Get-Content -LiteralPath $versionPath -Raw -Encoding UTF8).Trim() } else { '0.6.3-candidate' }
    $report = [ordered]@{
        schemaVersion = 1
        nexRouteVersion = $version
        targetProvider = 'Informatsionnye Kommunikatsii / wired / Sibay, Russia'
        strategyCount = $strategyReports.Count
        strategySet = 'NexRoute 0.6.3 RKN refresh'
        criticalTargets = @('DiscordGateway','DiscordCDN','DiscordUpdates','YouTubeWeb','YouTubeShort','YouTubeImage','YouTubeVideoRedirect')
        lists = @(
            [ordered]@{ file='lists/list-nexroute-discord-critical.txt'; sha256=(Get-NexRoute063Sha256 -Path $discordListPath) },
            [ordered]@{ file='lists/list-nexroute-youtube-critical.txt'; sha256=(Get-NexRoute063Sha256 -Path $youtubeListPath) }
        )
        strategies = @($strategyReports.ToArray())
    }
    $reportPath = Join-Path $rootPath '.service/strategy-refresh-report.json'
    $reportJson = $report | ConvertTo-Json -Depth 12
    [System.IO.File]::WriteAllText($reportPath, ($reportJson + "`r`n"), [System.Text.UTF8Encoding]::new($false))
    $operationCount = Update-NexRoute063PatchReport -Path $PatchReportPath -RefreshReport $report

    return [pscustomobject]@{
        StrategyCount = $strategyReports.Count
        PatchOperationCount = $operationCount
        Report = $reportPath
        DiscordList = $discordListPath
        YouTubeList = $youtubeListPath
    }
}
