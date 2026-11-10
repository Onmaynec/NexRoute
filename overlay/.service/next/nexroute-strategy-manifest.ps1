# Canonical reader for the versioned, checked-in strategy catalog.
# Runtime consumers may inspect strategy-manifest.json directly; no script evaluation is needed.
Set-StrictMode -Version Latest

$script:NrStrategyManifestPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'strategy-manifest.json'

function Assert-NrManifestFields {
    param([Parameter(Mandatory)]$Value,[Parameter(Mandatory)][string[]]$Fields,[Parameter(Mandatory)][string]$Context)
    if ($null -eq $Value -or $Value -is [string] -or $Value -is [array]) {
        throw "Invalid strategy manifest object: $Context"
    }
    $names = @($Value.PSObject.Properties | ForEach-Object { $_.Name })
    foreach ($field in $Fields) {
        if ($names -notcontains $field) { throw "Strategy manifest $Context is missing field: $field" }
    }
    foreach ($name in $names) {
        if ($Fields -notcontains $name) { throw "Unknown strategy manifest field: $Context.$name" }
    }
}

function Assert-NrManifestStringList {
    param([Parameter(Mandatory)]$Value,[Parameter(Mandatory)][string]$Context)
    if ($Value -isnot [array]) { throw "Strategy manifest $Context must be an array." }
    $seen = @{}
    foreach ($entry in $Value) {
        if ($entry -isnot [string] -or [string]::IsNullOrWhiteSpace($entry)) {
            throw "Strategy manifest $Context contains an empty or non-string entry."
        }
        if ($seen.ContainsKey($entry)) { throw "Strategy manifest $Context contains duplicate entry: $entry" }
        $seen[$entry] = $true
    }
}

function Assert-NrManifestSameList {
    param([object[]]$Actual,[object[]]$Expected,[string]$Context)
    if (($Actual -join [char]31) -cne ($Expected -join [char]31)) {
        throw "Strategy manifest $Context differs from the validated winws template."
    }
}

function Get-NrManifestSha256 {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-NrManifestProfileSha256 {
    param([Parameter(Mandatory)]$Profile)
    $json = ConvertTo-Json -InputObject $Profile -Depth 18 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$json)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Read-NrStrategyManifest {
    [CmdletBinding()]
    param(
        [string]$Path = $script:NrStrategyManifestPath,
        [string]$PayloadRoot
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Strategy manifest is missing: $Path"
    }
    $manifest = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-NrManifestFields $manifest @('schemaVersion','strategySetVersion','sourceCatalogVersion','upstreamVersion','profiles') 'root'
    if ($manifest.schemaVersion -isnot [int] -or [int]$manifest.schemaVersion -ne 1) { throw 'Unsupported strategy manifest schemaVersion.' }
    if ([string]$manifest.strategySetVersion -ne '0.7.0' -or [string]$manifest.sourceCatalogVersion -ne '0.6.3') {
        throw 'Unsupported strategy manifest catalog version.'
    }
    if ([string]$manifest.upstreamVersion -ne '1.10.3') { throw 'Strategy manifest requires Flowseal 1.10.3.' }
    if ($manifest.profiles -isnot [array] -or @($manifest.profiles).Count -ne 21) {
        throw 'Strategy manifest must define exactly 21 specialized profiles.'
    }

    $expectedPayloads = @(
        'bin/ACTIVE_DISCORD_UDP.bin','bin/ACTIVE_GAME_UDP.bin',
        'bin/quic_initial_4pda_to.bin','bin/quic_initial_www_google_com.bin',
        'bin/stun.bin','bin/stun2.bin',
        'bin/tls_clienthello_max_ru.bin','bin/tls_clienthello_www_google_com.bin'
    )
    $expectedLists = @(
        'lists/ipset-all.txt','lists/ipset-exclude-user.txt','lists/ipset-exclude.txt',
        'lists/list-exclude-user.txt','lists/list-exclude.txt','lists/list-general-user.txt',
        'lists/list-general.txt','lists/list-google.txt',
        'lists/list-nexroute-discord-critical.txt','lists/list-nexroute-youtube-critical.txt'
    )
    $tcpScopes = [ordered]@{
        discord='443,2053,2083,2087,2096,8443'; youtube='443'; general='80,443'
        fallback='80,443,8443'; game='%GameFilterTCP%'
    }
    $udpScopes = [ordered]@{
        quic='443'; discord='19294-19344,50000-50100'
        fallback='443'; game='%GameFilterUDP%'
    }

    $knownFamilies = @(
        'auto-multisplit-sniext-ts',
        'static-fakedsplit-ts',
        'auto-multidisorder-ts',
        'auto-hostfakesplit-ts',
        'static-multisplit-badseq',
        'syndata-multidisorder',
        'static-multisplit-ts',
        'auto-fake-badseq',
        'auto-fakedsplit-badseq',
        'auto-multisplit-ts',
        'hostfakesplit-only-ts',
        'static-stun2-hybrid',
        'exp-auto-stun2',
        'auto-multidisorder-badseq',
        'auto-fakedsplit-ts',
        'auto-hostfakesplit-altorder',
        'static-fake-ts',
        'auto-fake-ts',
        'auto-multisplit-badseq'
    )
    $ids = @{}
    $files = @{}
    $result = New-Object 'System.Collections.Generic.List[object]'
    foreach ($profile in $manifest.profiles) {
        Assert-NrManifestFields $profile @(
            'id','displayName','file','family','tcp','udp','sni','parameters',
            'fakePayloads','requiredLists','compatibility','provenance'
        ) 'profile'
        if ([string]$profile.id -cnotmatch '^nr063-[0-9]{2}-[a-z0-9-]+$') { throw "Unsafe strategy profile id: $($profile.id)" }
        if ([string]$profile.displayName -cnotmatch '^[a-zA-Z0-9 ()_-]{1,80}$') { throw "Unsafe profile displayName: $($profile.id)" }
        if ([string]$profile.file -cnotmatch '^general(?: \([A-Z0-9 ]+\))?\.bat$') { throw "Unsafe strategy file path: $($profile.file)" }
        if ($ids.ContainsKey([string]$profile.id) -or $files.ContainsKey([string]$profile.file)) {
            throw "Duplicate strategy profile id or file: $($profile.id)"
        }
        $ids[[string]$profile.id] = $true
        $files[[string]$profile.file] = $true
        if ([string]$profile.family -cnotmatch '^[a-z0-9-]{1,64}        Assert-NrManifestFields $profile.tcp @('scopes','modes','fooling','splitPositions') 'profile.tcp'
        Assert-NrManifestFields $profile.udp @('scopes','modes') 'profile.udp'
        Assert-NrManifestFields $profile.tcp.scopes @('discord','youtube','general','fallback','game') 'profile.tcp.scopes'
        Assert-NrManifestFields $profile.udp.scopes @('quic','discord','fallback','game') 'profile.udp.scopes'
        foreach ($name in $tcpScopes.Keys) {
            if ([string]$profile.tcp.scopes.$name -cne $tcpScopes[$name]) { throw "Unsafe TCP capture scope: $($profile.id) / $name" }
        }
        foreach ($name in $udpScopes.Keys) {
            if ([string]$profile.udp.scopes.$name -cne $udpScopes[$name]) { throw "Unsafe UDP capture scope: $($profile.id) / $name" }
        }
        foreach ($key in @('modes','fooling','splitPositions')) {
            Assert-NrManifestStringList $profile.tcp.$key "profile.tcp.$key"
        }
        Assert-NrManifestStringList $profile.udp.modes 'profile.udp.modes'
        Assert-NrManifestSameList @($profile.udp.modes) @('fake') 'profile.udp.modes'
        foreach ($mode in @($profile.tcp.modes)) {
            if ($mode -notin @('fake','multisplit','multidisorder','fakedsplit','hostfakesplit','syndata')) {
                throw "Unsupported TCP desync mode: $mode"
            }
        }
        foreach ($mode in @($profile.tcp.fooling)) {
            if ($mode -notin @('ts','badseq')) { throw "Unsupported TCP fooling mode: $mode" }
        }
        foreach ($position in @($profile.tcp.splitPositions)) {
            if ($position -cnotmatch '^(?:[0-9]{1,5}|sniext\+[0-9]{1,4}|midsld)$') {
                throw "Unsupported TCP split position: $position"
            }
        }

        Assert-NrManifestFields $profile.sni @('primary','secondary') 'profile.sni'
        foreach ($name in @('primary','secondary')) {
            if ([string]$profile.sni.$name -cnotmatch '^(?:[a-z0-9-]{1,63}\.)+[a-z0-9-]{2,63}$') {
                throw "Unsafe SNI in strategy manifest: $($profile.id) / $name"
            }
        }
        Assert-NrManifestFields $profile.parameters @(
            'seqOvl','repeats','quicRepeats','discordRepeats','cutoff'
        ) 'profile.parameters'
        $limits = @{
            seqOvl=@(0,4096); repeats=@(0,20); quicRepeats=@(1,20)
            discordRepeats=@(1,20); cutoff=@(1,32)
        }
        foreach ($name in $limits.Keys) {
            $number = $profile.parameters.$name
            if (($number -isnot [int] -and $number -isnot [long]) -or
                [long]$number -lt $limits[$name][0] -or [long]$number -gt $limits[$name][1]) {
                throw "Invalid strategy numeric parameter: $($profile.id) / $name"
            }
        }

        Assert-NrManifestStringList $profile.fakePayloads 'profile.fakePayloads'
        Assert-NrManifestStringList $profile.requiredLists 'profile.requiredLists'
        foreach ($pathRef in @($profile.fakePayloads)) {
            if ($pathRef -cnotmatch '^bin/[A-Za-z0-9_]+\.bin$') { throw "Unsafe fake payload path: $pathRef" }
        }
        foreach ($pathRef in @($profile.requiredLists)) {
            if ($pathRef -cnotmatch '^lists/[A-Za-z0-9._-]+\.txt$') { throw "Unsafe list path: $pathRef" }
        }
        Assert-NrManifestSameList @($profile.fakePayloads) $expectedPayloads 'profile.fakePayloads'
        Assert-NrManifestSameList @($profile.requiredLists) $expectedLists 'profile.requiredLists'
        if ($PayloadRoot) {
            foreach ($pathRef in @($profile.fakePayloads)) {
                $full = Join-Path $PayloadRoot ($pathRef.Replace('/',[IO.Path]::DirectorySeparatorChar))
                if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
                    throw "Strategy manifest references missing payload: $pathRef"
                }
            }
        }

        Assert-NrManifestFields $profile.compatibility @('flowseal','windows','addressFamily') 'profile.compatibility'
        if ([string]$profile.compatibility.flowseal -cne '1.10.3' -or
            [string]$profile.compatibility.windows -cne '10/11-x64' -or
            [string]$profile.compatibility.addressFamily -cne $(if ($profile.family -eq 'syndata-multidisorder') {'ipv4'} else {'upstream-dependent'})) {
            throw "Inconsistent strategy compatibility metadata: $($profile.id)"
        }
        Assert-NrManifestFields $profile.provenance @('sourceVersion','source') 'profile.provenance'
        if ([string]$profile.provenance.sourceVersion -cne '0.6.3' -or
            [string]$profile.provenance.source -cne 'Get-NexRoute063StrategyCatalog') {
            throw "Invalid strategy provenance: $($profile.id)"
        }

        # Keep the old generator as a byte-compatible renderer, but only feed it
        # objects validated by the single canonical manifest parser.
        $spec = [pscustomobject][ordered]@{
            File=[string]$profile.file; Profile=[string]$profile.id; Family=[string]$profile.family
            SniPrimary=[string]$profile.sni.primary; SniSecondary=[string]$profile.sni.secondary
            SeqOvl=[int]$profile.parameters.seqOvl; Repeats=[int]$profile.parameters.repeats
            QuicRepeats=[int]$profile.parameters.quicRepeats
            DiscordRepeats=[int]$profile.parameters.discordRepeats
            Cutoff=[int]$profile.parameters.cutoff
        }
        # The same normalized model is used in CLI/worker projections.
        # During a build, also assert exact parity with the winws family renderer.
        if (Get-Command 'Get-NexRoute063TcpArguments' -ErrorAction SilentlyContinue) {
            $tcp = Get-NexRoute063TcpArguments -Spec $spec -Scope Discord
            $modes = @()
            $fooling = @()
            $splitPositions = @()
            if ($tcp -match '--dpi-desync=([a-z,]+)') { $modes = @($Matches[1].Split(',')) }
            if ($tcp -match '--dpi-desync-fooling=([a-z,]+)') { $fooling = @($Matches[1].Split(',')) }
            if ($tcp -match '--dpi-desync-split-pos=([a-z0-9+,]+)') { $splitPositions = @($Matches[1].Split(',')) }
            Assert-NrManifestSameList @($profile.tcp.modes) $modes 'profile.tcp.modes'
            Assert-NrManifestSameList @($profile.tcp.fooling) $fooling 'profile.tcp.fooling'
            Assert-NrManifestSameList @($profile.tcp.splitPositions) $splitPositions 'profile.tcp.splitPositions'
        }
        $result.Add($spec)
    }
    return [pscustomobject][ordered]@{
        SchemaVersion=1
        StrategySetVersion=[string]$manifest.strategySetVersion
        SourceCatalogVersion=[string]$manifest.sourceCatalogVersion
        UpstreamVersion=[string]$manifest.upstreamVersion
        Path=[IO.Path]::GetFullPath($Path)
        Sha256=(Get-NrManifestSha256 -Path $Path)
        Profiles=@($manifest.profiles)
        Catalog=@($result.ToArray())
    }
}

function Get-NrStrategyManifestProjection {
    [CmdletBinding()]
    param([string]$Path = $script:NrStrategyManifestPath)
    $manifest = Read-NrStrategyManifest -Path $Path
    # A read-only projection for the UI, Strategy Builder and worker selection.
    return @($manifest.Profiles | ForEach-Object {
        [pscustomobject][ordered]@{
            id=[string]$_.id
            displayName=[string]$_.displayName
            file=[string]$_.file
            family=[string]$_.family
            modes=@($_.tcp.modes)
            fooling=@($_.tcp.fooling)
            splitPositions=@($_.tcp.splitPositions)
            tcpScopes=$_.tcp.scopes
            udpScopes=$_.udp.scopes
            compatibleFlowseal=[string]$_.compatibility.flowseal
        }
    })
}
 -or
            [string]$profile.family -notin $knownFamilies) {
            throw "Unsupported strategy family: $($profile.family)"
        }

        Assert-NrManifestFields $profile.tcp @('scopes','modes','fooling','splitPositions') 'profile.tcp'
        Assert-NrManifestFields $profile.udp @('scopes','modes') 'profile.udp'
        Assert-NrManifestFields $profile.tcp.scopes @('discord','youtube','general','fallback','game') 'profile.tcp.scopes'
        Assert-NrManifestFields $profile.udp.scopes @('quic','discord','fallback','game') 'profile.udp.scopes'
        foreach ($name in $tcpScopes.Keys) {
            if ([string]$profile.tcp.scopes.$name -cne $tcpScopes[$name]) { throw "Unsafe TCP capture scope: $($profile.id) / $name" }
        }
        foreach ($name in $udpScopes.Keys) {
            if ([string]$profile.udp.scopes.$name -cne $udpScopes[$name]) { throw "Unsafe UDP capture scope: $($profile.id) / $name" }
        }
        foreach ($key in @('modes','fooling','splitPositions')) {
            Assert-NrManifestStringList $profile.tcp.$key "profile.tcp.$key"
        }
        Assert-NrManifestStringList $profile.udp.modes 'profile.udp.modes'
        Assert-NrManifestSameList @($profile.udp.modes) @('fake') 'profile.udp.modes'
        foreach ($mode in @($profile.tcp.modes)) {
            if ($mode -notin @('fake','multisplit','multidisorder','fakedsplit','hostfakesplit','syndata')) {
                throw "Unsupported TCP desync mode: $mode"
            }
        }
        foreach ($mode in @($profile.tcp.fooling)) {
            if ($mode -notin @('ts','badseq')) { throw "Unsupported TCP fooling mode: $mode" }
        }
        foreach ($position in @($profile.tcp.splitPositions)) {
            if ($position -cnotmatch '^(?:[0-9]{1,5}|sniext\+[0-9]{1,4}|midsld)$') {
                throw "Unsupported TCP split position: $position"
            }
        }

        Assert-NrManifestFields $profile.sni @('primary','secondary') 'profile.sni'
        foreach ($name in @('primary','secondary')) {
            if ([string]$profile.sni.$name -cnotmatch '^(?:[a-z0-9-]{1,63}\.)+[a-z0-9-]{2,63}$') {
                throw "Unsafe SNI in strategy manifest: $($profile.id) / $name"
            }
        }
        Assert-NrManifestFields $profile.parameters @(
            'seqOvl','repeats','quicRepeats','discordRepeats','cutoff'
        ) 'profile.parameters'
        $limits = @{
            seqOvl=@(0,4096); repeats=@(0,20); quicRepeats=@(1,20)
            discordRepeats=@(1,20); cutoff=@(1,32)
        }
        foreach ($name in $limits.Keys) {
            $number = $profile.parameters.$name
            if (($number -isnot [int] -and $number -isnot [long]) -or
                [long]$number -lt $limits[$name][0] -or [long]$number -gt $limits[$name][1]) {
                throw "Invalid strategy numeric parameter: $($profile.id) / $name"
            }
        }

        Assert-NrManifestStringList $profile.fakePayloads 'profile.fakePayloads'
        Assert-NrManifestStringList $profile.requiredLists 'profile.requiredLists'
        foreach ($pathRef in @($profile.fakePayloads)) {
            if ($pathRef -cnotmatch '^bin/[A-Za-z0-9_]+\.bin$') { throw "Unsafe fake payload path: $pathRef" }
        }
        foreach ($pathRef in @($profile.requiredLists)) {
            if ($pathRef -cnotmatch '^lists/[A-Za-z0-9._-]+\.txt$') { throw "Unsafe list path: $pathRef" }
        }
        Assert-NrManifestSameList @($profile.fakePayloads) $expectedPayloads 'profile.fakePayloads'
        Assert-NrManifestSameList @($profile.requiredLists) $expectedLists 'profile.requiredLists'
        if ($PayloadRoot) {
            foreach ($pathRef in @($profile.fakePayloads)) {
                $full = Join-Path $PayloadRoot ($pathRef.Replace('/',[IO.Path]::DirectorySeparatorChar))
                if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
                    throw "Strategy manifest references missing payload: $pathRef"
                }
            }
        }

        Assert-NrManifestFields $profile.compatibility @('flowseal','windows','addressFamily') 'profile.compatibility'
        if ([string]$profile.compatibility.flowseal -cne '1.10.3' -or
            [string]$profile.compatibility.windows -cne '10/11-x64' -or
            [string]$profile.compatibility.addressFamily -cne $(if ($profile.family -eq 'syndata-multidisorder') {'ipv4'} else {'upstream-dependent'})) {
            throw "Inconsistent strategy compatibility metadata: $($profile.id)"
        }
        Assert-NrManifestFields $profile.provenance @('sourceVersion','source') 'profile.provenance'
        if ([string]$profile.provenance.sourceVersion -cne '0.6.3' -or
            [string]$profile.provenance.source -cne 'Get-NexRoute063StrategyCatalog') {
            throw "Invalid strategy provenance: $($profile.id)"
        }

        # Keep the old generator as a byte-compatible renderer, but only feed it
        # objects validated by the single canonical manifest parser.
        $spec = [pscustomobject][ordered]@{
            File=[string]$profile.file; Profile=[string]$profile.id; Family=[string]$profile.family
            SniPrimary=[string]$profile.sni.primary; SniSecondary=[string]$profile.sni.secondary
            SeqOvl=[int]$profile.parameters.seqOvl; Repeats=[int]$profile.parameters.repeats
            QuicRepeats=[int]$profile.parameters.quicRepeats
            DiscordRepeats=[int]$profile.parameters.discordRepeats
            Cutoff=[int]$profile.parameters.cutoff
        }
        $tcp = Get-NexRoute063TcpArguments -Spec $spec -Scope Discord
        $modes = @()
        $fooling = @()
        $splitPositions = @()
        if ($tcp -match '--dpi-desync=([a-z,]+)') { $modes = @($Matches[1].Split(',')) }
        if ($tcp -match '--dpi-desync-fooling=([a-z,]+)') { $fooling = @($Matches[1].Split(',')) }
        if ($tcp -match '--dpi-desync-split-pos=([a-z0-9+,]+)') { $splitPositions = @($Matches[1].Split(',')) }
        Assert-NrManifestSameList @($profile.tcp.modes) $modes 'profile.tcp.modes'
        Assert-NrManifestSameList @($profile.tcp.fooling) $fooling 'profile.tcp.fooling'
        Assert-NrManifestSameList @($profile.tcp.splitPositions) $splitPositions 'profile.tcp.splitPositions'
        $result.Add($spec)
    }
    return [pscustomobject][ordered]@{
        SchemaVersion=1
        StrategySetVersion=[string]$manifest.strategySetVersion
        SourceCatalogVersion=[string]$manifest.sourceCatalogVersion
        UpstreamVersion=[string]$manifest.upstreamVersion
        Path=[IO.Path]::GetFullPath($Path)
        Sha256=(Get-NrManifestSha256 -Path $Path)
        Profiles=@($manifest.profiles)
        Catalog=@($result.ToArray())
    }
}

function Get-NrStrategyManifestProjection {
    [CmdletBinding()]
    param([string]$Path = $script:NrStrategyManifestPath)
    $manifest = Read-NrStrategyManifest -Path $Path
    # A read-only projection for the UI, Strategy Builder and worker selection.
    return @($manifest.Profiles | ForEach-Object {
        [pscustomobject][ordered]@{
            id=[string]$_.id
            displayName=[string]$_.displayName
            file=[string]$_.file
            family=[string]$_.family
            modes=@($_.tcp.modes)
            fooling=@($_.tcp.fooling)
            splitPositions=@($_.tcp.splitPositions)
            tcpScopes=$_.tcp.scopes
            udpScopes=$_.udp.scopes
            compatibleFlowseal=[string]$_.compatibility.flowseal
        }
    })
}

function Get-NrManifestStrategyByName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name,[string]$Path = $script:NrStrategyManifestPath)
    $key = $Name.Trim()
    foreach ($profile in @(Get-NrStrategyManifestProjection -Path $Path)) {
        if ($profile.id -ieq $key -or $profile.file -ieq $key -or
            [IO.Path]::GetFileNameWithoutExtension([string]$profile.file) -ieq $key) {
            return $profile
        }
    }
    return $null
}
 -or
            [string]$profile.family -notin $knownFamilies) {
            throw "Unsupported strategy family: $($profile.family)"
        }

        Assert-NrManifestFields $profile.tcp @('scopes','modes','fooling','splitPositions') 'profile.tcp'
        Assert-NrManifestFields $profile.udp @('scopes','modes') 'profile.udp'
        Assert-NrManifestFields $profile.tcp.scopes @('discord','youtube','general','fallback','game') 'profile.tcp.scopes'
        Assert-NrManifestFields $profile.udp.scopes @('quic','discord','fallback','game') 'profile.udp.scopes'
        foreach ($name in $tcpScopes.Keys) {
            if ([string]$profile.tcp.scopes.$name -cne $tcpScopes[$name]) { throw "Unsafe TCP capture scope: $($profile.id) / $name" }
        }
        foreach ($name in $udpScopes.Keys) {
            if ([string]$profile.udp.scopes.$name -cne $udpScopes[$name]) { throw "Unsafe UDP capture scope: $($profile.id) / $name" }
        }
        foreach ($key in @('modes','fooling','splitPositions')) {
            Assert-NrManifestStringList $profile.tcp.$key "profile.tcp.$key"
        }
        Assert-NrManifestStringList $profile.udp.modes 'profile.udp.modes'
        Assert-NrManifestSameList @($profile.udp.modes) @('fake') 'profile.udp.modes'
        foreach ($mode in @($profile.tcp.modes)) {
            if ($mode -notin @('fake','multisplit','multidisorder','fakedsplit','hostfakesplit','syndata')) {
                throw "Unsupported TCP desync mode: $mode"
            }
        }
        foreach ($mode in @($profile.tcp.fooling)) {
            if ($mode -notin @('ts','badseq')) { throw "Unsupported TCP fooling mode: $mode" }
        }
        foreach ($position in @($profile.tcp.splitPositions)) {
            if ($position -cnotmatch '^(?:[0-9]{1,5}|sniext\+[0-9]{1,4}|midsld)$') {
                throw "Unsupported TCP split position: $position"
            }
        }

        Assert-NrManifestFields $profile.sni @('primary','secondary') 'profile.sni'
        foreach ($name in @('primary','secondary')) {
            if ([string]$profile.sni.$name -cnotmatch '^(?:[a-z0-9-]{1,63}\.)+[a-z0-9-]{2,63}$') {
                throw "Unsafe SNI in strategy manifest: $($profile.id) / $name"
            }
        }
        Assert-NrManifestFields $profile.parameters @(
            'seqOvl','repeats','quicRepeats','discordRepeats','cutoff'
        ) 'profile.parameters'
        $limits = @{
            seqOvl=@(0,4096); repeats=@(0,20); quicRepeats=@(1,20)
            discordRepeats=@(1,20); cutoff=@(1,32)
        }
        foreach ($name in $limits.Keys) {
            $number = $profile.parameters.$name
            if (($number -isnot [int] -and $number -isnot [long]) -or
                [long]$number -lt $limits[$name][0] -or [long]$number -gt $limits[$name][1]) {
                throw "Invalid strategy numeric parameter: $($profile.id) / $name"
            }
        }

        Assert-NrManifestStringList $profile.fakePayloads 'profile.fakePayloads'
        Assert-NrManifestStringList $profile.requiredLists 'profile.requiredLists'
        foreach ($pathRef in @($profile.fakePayloads)) {
            if ($pathRef -cnotmatch '^bin/[A-Za-z0-9_]+\.bin$') { throw "Unsafe fake payload path: $pathRef" }
        }
        foreach ($pathRef in @($profile.requiredLists)) {
            if ($pathRef -cnotmatch '^lists/[A-Za-z0-9._-]+\.txt$') { throw "Unsafe list path: $pathRef" }
        }
        Assert-NrManifestSameList @($profile.fakePayloads) $expectedPayloads 'profile.fakePayloads'
        Assert-NrManifestSameList @($profile.requiredLists) $expectedLists 'profile.requiredLists'
        if ($PayloadRoot) {
            foreach ($pathRef in @($profile.fakePayloads)) {
                $full = Join-Path $PayloadRoot ($pathRef.Replace('/',[IO.Path]::DirectorySeparatorChar))
                if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
                    throw "Strategy manifest references missing payload: $pathRef"
                }
            }
        }

        Assert-NrManifestFields $profile.compatibility @('flowseal','windows','addressFamily') 'profile.compatibility'
        if ([string]$profile.compatibility.flowseal -cne '1.10.3' -or
            [string]$profile.compatibility.windows -cne '10/11-x64' -or
            [string]$profile.compatibility.addressFamily -cne $(if ($profile.family -eq 'syndata-multidisorder') {'ipv4'} else {'upstream-dependent'})) {
            throw "Inconsistent strategy compatibility metadata: $($profile.id)"
        }
        Assert-NrManifestFields $profile.provenance @('sourceVersion','source') 'profile.provenance'
        if ([string]$profile.provenance.sourceVersion -cne '0.6.3' -or
            [string]$profile.provenance.source -cne 'Get-NexRoute063StrategyCatalog') {
            throw "Invalid strategy provenance: $($profile.id)"
        }

        # Keep the old generator as a byte-compatible renderer, but only feed it
        # objects validated by the single canonical manifest parser.
        $spec = [pscustomobject][ordered]@{
            File=[string]$profile.file; Profile=[string]$profile.id; Family=[string]$profile.family
            SniPrimary=[string]$profile.sni.primary; SniSecondary=[string]$profile.sni.secondary
            SeqOvl=[int]$profile.parameters.seqOvl; Repeats=[int]$profile.parameters.repeats
            QuicRepeats=[int]$profile.parameters.quicRepeats
            DiscordRepeats=[int]$profile.parameters.discordRepeats
            Cutoff=[int]$profile.parameters.cutoff
        }
        # The same normalized model is used in CLI/worker projections.
        # During a build, also assert exact parity with the winws family renderer.
        if (Get-Command 'Get-NexRoute063TcpArguments' -ErrorAction SilentlyContinue) {
            $tcp = Get-NexRoute063TcpArguments -Spec $spec -Scope Discord
            $modes = @()
            $fooling = @()
            $splitPositions = @()
            if ($tcp -match '--dpi-desync=([a-z,]+)') { $modes = @($Matches[1].Split(',')) }
            if ($tcp -match '--dpi-desync-fooling=([a-z,]+)') { $fooling = @($Matches[1].Split(',')) }
            if ($tcp -match '--dpi-desync-split-pos=([a-z0-9+,]+)') { $splitPositions = @($Matches[1].Split(',')) }
            Assert-NrManifestSameList @($profile.tcp.modes) $modes 'profile.tcp.modes'
            Assert-NrManifestSameList @($profile.tcp.fooling) $fooling 'profile.tcp.fooling'
            Assert-NrManifestSameList @($profile.tcp.splitPositions) $splitPositions 'profile.tcp.splitPositions'
        }
        $result.Add($spec)
    }
    return [pscustomobject][ordered]@{
        SchemaVersion=1
        StrategySetVersion=[string]$manifest.strategySetVersion
        SourceCatalogVersion=[string]$manifest.sourceCatalogVersion
        UpstreamVersion=[string]$manifest.upstreamVersion
        Path=[IO.Path]::GetFullPath($Path)
        Sha256=(Get-NrManifestSha256 -Path $Path)
        Profiles=@($manifest.profiles)
        Catalog=@($result.ToArray())
    }
}

function Get-NrStrategyManifestProjection {
    [CmdletBinding()]
    param([string]$Path = $script:NrStrategyManifestPath)
    $manifest = Read-NrStrategyManifest -Path $Path
    # A read-only projection for the UI, Strategy Builder and worker selection.
    return @($manifest.Profiles | ForEach-Object {
        [pscustomobject][ordered]@{
            id=[string]$_.id
            displayName=[string]$_.displayName
            file=[string]$_.file
            family=[string]$_.family
            modes=@($_.tcp.modes)
            fooling=@($_.tcp.fooling)
            splitPositions=@($_.tcp.splitPositions)
            tcpScopes=$_.tcp.scopes
            udpScopes=$_.udp.scopes
            compatibleFlowseal=[string]$_.compatibility.flowseal
        }
    })
}
 -or
            [string]$profile.family -notin $knownFamilies) {
            throw "Unsupported strategy family: $($profile.family)"
        }

        Assert-NrManifestFields $profile.tcp @('scopes','modes','fooling','splitPositions') 'profile.tcp'
        Assert-NrManifestFields $profile.udp @('scopes','modes') 'profile.udp'
        Assert-NrManifestFields $profile.tcp.scopes @('discord','youtube','general','fallback','game') 'profile.tcp.scopes'
        Assert-NrManifestFields $profile.udp.scopes @('quic','discord','fallback','game') 'profile.udp.scopes'
        foreach ($name in $tcpScopes.Keys) {
            if ([string]$profile.tcp.scopes.$name -cne $tcpScopes[$name]) { throw "Unsafe TCP capture scope: $($profile.id) / $name" }
        }
        foreach ($name in $udpScopes.Keys) {
            if ([string]$profile.udp.scopes.$name -cne $udpScopes[$name]) { throw "Unsafe UDP capture scope: $($profile.id) / $name" }
        }
        foreach ($key in @('modes','fooling','splitPositions')) {
            Assert-NrManifestStringList $profile.tcp.$key "profile.tcp.$key"
        }
        Assert-NrManifestStringList $profile.udp.modes 'profile.udp.modes'
        Assert-NrManifestSameList @($profile.udp.modes) @('fake') 'profile.udp.modes'
        foreach ($mode in @($profile.tcp.modes)) {
            if ($mode -notin @('fake','multisplit','multidisorder','fakedsplit','hostfakesplit','syndata')) {
                throw "Unsupported TCP desync mode: $mode"
            }
        }
        foreach ($mode in @($profile.tcp.fooling)) {
            if ($mode -notin @('ts','badseq')) { throw "Unsupported TCP fooling mode: $mode" }
        }
        foreach ($position in @($profile.tcp.splitPositions)) {
            if ($position -cnotmatch '^(?:[0-9]{1,5}|sniext\+[0-9]{1,4}|midsld)$') {
                throw "Unsupported TCP split position: $position"
            }
        }

        Assert-NrManifestFields $profile.sni @('primary','secondary') 'profile.sni'
        foreach ($name in @('primary','secondary')) {
            if ([string]$profile.sni.$name -cnotmatch '^(?:[a-z0-9-]{1,63}\.)+[a-z0-9-]{2,63}$') {
                throw "Unsafe SNI in strategy manifest: $($profile.id) / $name"
            }
        }
        Assert-NrManifestFields $profile.parameters @(
            'seqOvl','repeats','quicRepeats','discordRepeats','cutoff'
        ) 'profile.parameters'
        $limits = @{
            seqOvl=@(0,4096); repeats=@(0,20); quicRepeats=@(1,20)
            discordRepeats=@(1,20); cutoff=@(1,32)
        }
        foreach ($name in $limits.Keys) {
            $number = $profile.parameters.$name
            if (($number -isnot [int] -and $number -isnot [long]) -or
                [long]$number -lt $limits[$name][0] -or [long]$number -gt $limits[$name][1]) {
                throw "Invalid strategy numeric parameter: $($profile.id) / $name"
            }
        }

        Assert-NrManifestStringList $profile.fakePayloads 'profile.fakePayloads'
        Assert-NrManifestStringList $profile.requiredLists 'profile.requiredLists'
        foreach ($pathRef in @($profile.fakePayloads)) {
            if ($pathRef -cnotmatch '^bin/[A-Za-z0-9_]+\.bin$') { throw "Unsafe fake payload path: $pathRef" }
        }
        foreach ($pathRef in @($profile.requiredLists)) {
            if ($pathRef -cnotmatch '^lists/[A-Za-z0-9._-]+\.txt$') { throw "Unsafe list path: $pathRef" }
        }
        Assert-NrManifestSameList @($profile.fakePayloads) $expectedPayloads 'profile.fakePayloads'
        Assert-NrManifestSameList @($profile.requiredLists) $expectedLists 'profile.requiredLists'
        if ($PayloadRoot) {
            foreach ($pathRef in @($profile.fakePayloads)) {
                $full = Join-Path $PayloadRoot ($pathRef.Replace('/',[IO.Path]::DirectorySeparatorChar))
                if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
                    throw "Strategy manifest references missing payload: $pathRef"
                }
            }
        }

        Assert-NrManifestFields $profile.compatibility @('flowseal','windows','addressFamily') 'profile.compatibility'
        if ([string]$profile.compatibility.flowseal -cne '1.10.3' -or
            [string]$profile.compatibility.windows -cne '10/11-x64' -or
            [string]$profile.compatibility.addressFamily -cne $(if ($profile.family -eq 'syndata-multidisorder') {'ipv4'} else {'upstream-dependent'})) {
            throw "Inconsistent strategy compatibility metadata: $($profile.id)"
        }
        Assert-NrManifestFields $profile.provenance @('sourceVersion','source') 'profile.provenance'
        if ([string]$profile.provenance.sourceVersion -cne '0.6.3' -or
            [string]$profile.provenance.source -cne 'Get-NexRoute063StrategyCatalog') {
            throw "Invalid strategy provenance: $($profile.id)"
        }

        # Keep the old generator as a byte-compatible renderer, but only feed it
        # objects validated by the single canonical manifest parser.
        $spec = [pscustomobject][ordered]@{
            File=[string]$profile.file; Profile=[string]$profile.id; Family=[string]$profile.family
            SniPrimary=[string]$profile.sni.primary; SniSecondary=[string]$profile.sni.secondary
            SeqOvl=[int]$profile.parameters.seqOvl; Repeats=[int]$profile.parameters.repeats
            QuicRepeats=[int]$profile.parameters.quicRepeats
            DiscordRepeats=[int]$profile.parameters.discordRepeats
            Cutoff=[int]$profile.parameters.cutoff
        }
        $tcp = Get-NexRoute063TcpArguments -Spec $spec -Scope Discord
        $modes = @()
        $fooling = @()
        $splitPositions = @()
        if ($tcp -match '--dpi-desync=([a-z,]+)') { $modes = @($Matches[1].Split(',')) }
        if ($tcp -match '--dpi-desync-fooling=([a-z,]+)') { $fooling = @($Matches[1].Split(',')) }
        if ($tcp -match '--dpi-desync-split-pos=([a-z0-9+,]+)') { $splitPositions = @($Matches[1].Split(',')) }
        Assert-NrManifestSameList @($profile.tcp.modes) $modes 'profile.tcp.modes'
        Assert-NrManifestSameList @($profile.tcp.fooling) $fooling 'profile.tcp.fooling'
        Assert-NrManifestSameList @($profile.tcp.splitPositions) $splitPositions 'profile.tcp.splitPositions'
        $result.Add($spec)
    }
    return [pscustomobject][ordered]@{
        SchemaVersion=1
        StrategySetVersion=[string]$manifest.strategySetVersion
        SourceCatalogVersion=[string]$manifest.sourceCatalogVersion
        UpstreamVersion=[string]$manifest.upstreamVersion
        Path=[IO.Path]::GetFullPath($Path)
        Sha256=(Get-NrManifestSha256 -Path $Path)
        Profiles=@($manifest.profiles)
        Catalog=@($result.ToArray())
    }
}

function Get-NrStrategyManifestProjection {
    [CmdletBinding()]
    param([string]$Path = $script:NrStrategyManifestPath)
    $manifest = Read-NrStrategyManifest -Path $Path
    # A read-only projection for the UI, Strategy Builder and worker selection.
    return @($manifest.Profiles | ForEach-Object {
        [pscustomobject][ordered]@{
            id=[string]$_.id
            displayName=[string]$_.displayName
            file=[string]$_.file
            family=[string]$_.family
            modes=@($_.tcp.modes)
            fooling=@($_.tcp.fooling)
            splitPositions=@($_.tcp.splitPositions)
            tcpScopes=$_.tcp.scopes
            udpScopes=$_.udp.scopes
            compatibleFlowseal=[string]$_.compatibility.flowseal
        }
    })
}

function Get-NrManifestStrategyByName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name,[string]$Path = $script:NrStrategyManifestPath)
    $key = $Name.Trim()
    foreach ($profile in @(Get-NrStrategyManifestProjection -Path $Path)) {
        if ($profile.id -ieq $key -or $profile.file -ieq $key -or
            [IO.Path]::GetFileNameWithoutExtension([string]$profile.file) -ieq $key) {
            return $profile
        }
    }
    return $null
}
