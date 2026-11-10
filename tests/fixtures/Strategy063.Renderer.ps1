# Immutable 0.6.3 renderer used only by StrategyManifest070 regression tests.
# This reference must not change when the production strategy generator is modified.
function Get-NrLegacy063TcpArguments {
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


function New-NrLegacy063StrategyCommand {
    param([Parameter(Mandatory)]$Spec)

    $discordArgs = Get-NrLegacy063TcpArguments -Spec $Spec -Scope Discord
    $youtubeArgs = Get-NrLegacy063TcpArguments -Spec $Spec -Scope YouTube
    $generalArgs = Get-NrLegacy063TcpArguments -Spec $Spec -Scope General
    $fallbackArgs = Get-NrLegacy063TcpArguments -Spec $Spec -Scope Fallback
    $gameArgs = Get-NrLegacy063TcpArguments -Spec $Spec -Scope Game
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
        ('--filter-udp=%GameFilterUDP% --ipset="%LISTS%ipset-all.txt" --ipset-exclude="%LISTS%ipset-exclude.txt" --ipset-exclude="%LISTS%ipset-exclude-user.txt" --dpi-desync=fake --dpi-desync-repeats=10 --dpi-desync-any-protocol=1 --dpi-desync-fake-unknown-udp="%BIN%quic_initial_4pda_to.bin" --dpi-desync-fake-unknown-udp="%BIN%ACTIVE_GAME_UDP.bin" --dpi-desync-cutoff=n{0} ^' -f [int]$Spec.Cutoff),
        '%NEXROUTE_SERVICE_TCP_ARGS% ^',
        '%NEXROUTE_SERVICE_UDP_ARGS%'
    )
    return $lines
}


function Set-NrLegacy063StrategyFile {
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
    $replacement = @(New-NrLegacy063StrategyCommand -Spec $Spec)
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

