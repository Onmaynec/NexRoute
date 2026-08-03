Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Get-NrStrategyBuilderRoot {
    param([string]$Root)
    if ($Root) { return [IO.Path]::GetFullPath($Root).TrimEnd('\','/') }
    if (Get-Variable -Name NrRoot -Scope Script -ErrorAction SilentlyContinue) { return [IO.Path]::GetFullPath([string]$script:NrRoot).TrimEnd('\','/') }
    return [IO.Path]::GetFullPath((Get-Location).Path).TrimEnd('\','/')
}

function Get-NrStrategyBuilderAllowedModes {
    return [string[]]@(
        'fake','multisplit','multidisorder','fakedsplit','fakeddisorder','hostfakesplit',
        'split2','disorder2','syndata','synack','destopt','hopbyhop','ipfrag1','ipfrag2'
    )
}

function Get-NrStrategyBuilderAllowedFooling {
    return [string[]]@('none','md5sig','badseq','badsum','datanoack','ts','hopbyhop','destopt')
}

function Get-NrStrategyBuilderAllowedPayloadKinds {
    return [string[]]@('quic','tls','unknown-udp','unknown-tcp')
}

function New-NrStrategyDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [object[]]$Sections=@(),
        [bool]$AllowBroadCapture=$false
    )
    return [pscustomobject][ordered]@{
        schemaVersion=2
        name=$Name
        allowBroadCapture=$AllowBroadCapture
        sections=[object[]]@($Sections)
    }
}

function New-NrStrategySection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('tcp','udp')][string]$Protocol,
        [Parameter(Mandatory)][string[]]$Ports,
        [string]$Hostlist,
        [string]$Ipset,
        [Parameter(Mandatory)][string[]]$DesyncModes,
        [ValidateRange(1,20)][int]$Repeats=1,
        [string[]]$Fooling=@(),
        [string[]]$SplitPositions=@(),
        [object[]]$FakePayloads=@()
    )
    return [pscustomobject][ordered]@{
        protocol=$Protocol.ToLowerInvariant()
        ports=[string[]]@($Ports)
        hostlist=$Hostlist
        ipset=$Ipset
        desyncModes=[string[]]@($DesyncModes)
        repeats=$Repeats
        fooling=[string[]]@($Fooling)
        splitPositions=[string[]]@($SplitPositions)
        fakePayloads=[object[]]@($FakePayloads)
    }
}

function New-NrFakePayloadDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('quic','tls','unknown-udp','unknown-tcp')][string]$Kind,
        [Parameter(Mandatory)][string]$Path
    )
    return [pscustomobject][ordered]@{ kind=$Kind.ToLowerInvariant(); path=$Path }
}

function Test-NrBuilderSafeName {
    param([string]$Name)
    return (-not [string]::IsNullOrWhiteSpace($Name) -and $Name.Length -le 64 -and $Name -match '^[A-Za-z0-9][A-Za-z0-9._ -]*$' -and $Name -notmatch '[. ]$')
}

function Resolve-NrStrategyBuilderPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][ValidateSet('lists','bin')][string]$ExpectedDirectory,
        [Parameter(Mandatory)][string[]]$AllowedExtensions,
        [switch]$AllowMissing
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Path is empty.' }
    if ($Path -match '[\x00-\x1F<>|?*"`r`n]' -or $Path -match '(^|[\\/])\.\.([\\/]|$)') { throw "Unsafe path: $Path" }
    if ([IO.Path]::IsPathRooted($Path)) { throw "Only relative strategy paths are accepted: $Path" }
    $normalized=$Path.Replace('/',[IO.Path]::DirectorySeparatorChar).Replace('\',[IO.Path]::DirectorySeparatorChar).TrimStart([IO.Path]::DirectorySeparatorChar)
    $rootPath=Get-NrStrategyBuilderRoot -Root $Root
    $full=[IO.Path]::GetFullPath((Join-Path $rootPath $normalized))
    $rootPrefix=$rootPath.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($rootPrefix,[StringComparison]::OrdinalIgnoreCase)) { throw "Path escapes the NexRoute root: $Path" }
    $expectedPrefix=[IO.Path]::GetFullPath((Join-Path $rootPath $ExpectedDirectory)).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($expectedPrefix,[StringComparison]::OrdinalIgnoreCase)) { throw "Path must be inside '$ExpectedDirectory': $Path" }
    $extension=[IO.Path]::GetExtension($full).ToLowerInvariant()
    if ($extension -notin @($AllowedExtensions | ForEach-Object { $_.ToLowerInvariant() })) { throw "Unsupported file extension '$extension': $Path" }
    if (-not $AllowMissing -and -not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Referenced file does not exist: $Path" }
    $relative=$full.Substring($rootPrefix.Length).Replace([IO.Path]::DirectorySeparatorChar,'/')
    return [pscustomobject]@{ relative=$relative; full=$full }
}

function ConvertTo-NrBuilderPortRanges {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Ports)
    $ranges=New-Object 'System.Collections.Generic.List[object]'
    foreach ($portValue in @($Ports)) {
        $candidate=([string]$portValue).Trim()
        if ($candidate -notmatch '^(?<start>\d{1,5})(?:-(?<end>\d{1,5}))?$') { throw "Invalid port or port range: $candidate" }
        $start=[int]$Matches.start
        $end=if ($Matches.end) { [int]$Matches.end } else { $start }
        if ($start -lt 1 -or $start -gt 65535 -or $end -lt 1 -or $end -gt 65535 -or $end -lt $start) { throw "Invalid port bounds: $candidate" }
        $ranges.Add([pscustomobject]@{ start=$start; end=$end; text=if ($start -eq $end) { [string]$start } else { "$start-$end" } })
    }
    if ($ranges.Count -eq 0) { throw 'At least one TCP or UDP port is required.' }
    $ordered=@($ranges.ToArray() | Sort-Object start,end)
    for ($index=1; $index -lt $ordered.Count; $index++) {
        if ([int]$ordered[$index].start -le [int]$ordered[$index-1].end) { throw 'Port ranges overlap or repeat.' }
    }
    return [object[]]$ordered
}

function Test-NrBuilderSplitPosition {
    param([string]$Value)
    return ([string]$Value -match '^(?:\d{1,5}|host(?:[+-]\d{1,3})?|midsld(?:[+-]\d{1,3})?|sniext(?:[+-]\d{1,3})?|method(?:[+-]\d{1,3})?|endhost(?:[+-]\d{1,3})?)$')
}

function ConvertTo-NrNormalizedStrategyDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Definition,
        [Parameter(Mandatory)][string]$Root,
        [switch]$AllowMissingFiles
    )
    if ([int]$Definition.schemaVersion -ne 2) { throw 'Strategy definition schemaVersion must be 2.' }
    $name=[string]$Definition.name
    if (-not (Test-NrBuilderSafeName -Name $name)) { throw 'Strategy name must start with an alphanumeric character and may contain letters, digits, spaces, dot, underscore or dash.' }
    $sections=@($Definition.sections)
    if ($sections.Count -lt 1 -or $sections.Count -gt 16) { throw 'A strategy requires between 1 and 16 sections.' }
    $allowedModes=Get-NrStrategyBuilderAllowedModes
    $allowedFooling=Get-NrStrategyBuilderAllowedFooling
    $allowedPayloads=Get-NrStrategyBuilderAllowedPayloadKinds
    $normalizedSections=New-Object 'System.Collections.Generic.List[object]'
    $scopeKeys=@{}
    foreach ($section in $sections) {
        $protocol=([string]$section.protocol).ToLowerInvariant()
        if ($protocol -notin @('tcp','udp')) { throw "Unsupported protocol: $protocol" }
        $ranges=ConvertTo-NrBuilderPortRanges -Ports ([string[]]@($section.ports))
        $covered=0L
        foreach ($range in $ranges) { $covered+=([long]$range.end-[long]$range.start+1L) }
        if (-not [bool]$Definition.allowBroadCapture -and ($covered -gt 20000 -or ($ranges.Count -eq 1 -and $ranges[0].start -eq 1 -and $ranges[0].end -eq 65535))) {
            throw "Broad $protocol capture is blocked. Narrow the ports or explicitly enable allowBroadCapture."
        }
        $hostlist=$null; $ipset=$null
        if (-not [string]::IsNullOrWhiteSpace([string]$section.hostlist)) {
            $hostlist=Resolve-NrStrategyBuilderPath -Path ([string]$section.hostlist) -Root $Root -ExpectedDirectory lists -AllowedExtensions @('.txt') -AllowMissing:$AllowMissingFiles
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$section.ipset)) {
            $ipset=Resolve-NrStrategyBuilderPath -Path ([string]$section.ipset) -Root $Root -ExpectedDirectory lists -AllowedExtensions @('.txt') -AllowMissing:$AllowMissingFiles
        }
        if (-not $hostlist -and -not $ipset) { throw "Section '$protocol' must have a hostlist or ipset to prevent an unscoped capture." }
        $modes=[string[]]@($section.desyncModes | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } | Where-Object { $_ } | Select-Object -Unique)
        if ($modes.Count -lt 1 -or $modes.Count -gt 4) { throw 'Each section requires between one and four desynchronization modes.' }
        foreach ($mode in $modes) { if ($mode -notin $allowedModes) { throw "Unsupported desynchronization mode: $mode" } }
        if ($modes -contains 'synack' -and $protocol -ne 'tcp') { throw 'synack is valid only for TCP sections.' }
        if (($modes -contains 'ipfrag1') -and ($modes -contains 'ipfrag2')) { throw 'ipfrag1 and ipfrag2 cannot be enabled in the same section.' }
        $repeats=if ($section.PSObject.Properties['repeats']) { [int]$section.repeats } else { 1 }
        if ($repeats -lt 1 -or $repeats -gt 20) { throw 'Desynchronization repeats must be between 1 and 20.' }
        $fooling=[string[]]@($section.fooling | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } | Where-Object { $_ -and $_ -ne 'none' } | Select-Object -Unique)
        foreach ($item in $fooling) {
            if ($item -notin $allowedFooling) { throw "Unsupported fooling mode: $item" }
            if ($protocol -eq 'udp' -and $item -in @('md5sig','datanoack','ts')) { throw "$item is not valid for UDP sections." }
        }
        $splitPositions=[string[]]@($section.splitPositions | ForEach-Object { ([string]$_).Trim().ToLowerInvariant() } | Where-Object { $_ } | Select-Object -Unique)
        foreach ($position in $splitPositions) { if (-not (Test-NrBuilderSplitPosition -Value $position)) { throw "Unsafe or unsupported split position: $position" } }
        if ($splitPositions.Count -gt 8) { throw 'No more than eight split positions are allowed.' }
        $payloads=New-Object 'System.Collections.Generic.List[object]'
        foreach ($payload in @($section.fakePayloads)) {
            $kind=([string]$payload.kind).ToLowerInvariant()
            if ($kind -notin $allowedPayloads) { throw "Unsupported fake payload kind: $kind" }
            if ($modes -notcontains 'fake') { throw 'Fake payload files require the fake desynchronization mode.' }
            if ($protocol -eq 'tcp' -and $kind -in @('quic','unknown-udp')) { throw "$kind payload is not valid for TCP sections." }
            if ($protocol -eq 'udp' -and $kind -in @('tls','unknown-tcp')) { throw "$kind payload is not valid for UDP sections." }
            $resolved=Resolve-NrStrategyBuilderPath -Path ([string]$payload.path) -Root $Root -ExpectedDirectory bin -AllowedExtensions @('.bin') -AllowMissing:$AllowMissingFiles
            $payloads.Add([pscustomobject][ordered]@{ kind=$kind; path=$resolved.relative; fullPath=$resolved.full })
        }
        $scopeKey=($protocol+'|'+($ranges.text -join ',')+'|'+$(if ($hostlist) { $hostlist.relative } else { '' })+'|'+$(if ($ipset) { $ipset.relative } else { '' })).ToLowerInvariant()
        if ($scopeKeys.ContainsKey($scopeKey)) { throw 'Duplicate filter scope detected. Merge or remove the repeated section.' }
        $scopeKeys[$scopeKey]=$true
        $normalizedSections.Add([pscustomobject][ordered]@{
            protocol=$protocol
            ports=[string[]]@($ranges.text)
            hostlist=if ($hostlist) { $hostlist.relative } else { $null }
            hostlistFull=if ($hostlist) { $hostlist.full } else { $null }
            ipset=if ($ipset) { $ipset.relative } else { $null }
            ipsetFull=if ($ipset) { $ipset.full } else { $null }
            desyncModes=$modes
            repeats=$repeats
            fooling=$fooling
            splitPositions=$splitPositions
            fakePayloads=[object[]]$payloads.ToArray()
        })
    }
    return [pscustomobject][ordered]@{
        schemaVersion=2
        name=$name.Trim()
        allowBroadCapture=[bool]$Definition.allowBroadCapture
        sections=[object[]]$normalizedSections.ToArray()
    }
}

function Test-NrStrategyDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Definition,
        [string]$Root,
        [switch]$AllowMissingFiles
    )
    try {
        $normalized=ConvertTo-NrNormalizedStrategyDefinition -Definition $Definition -Root (Get-NrStrategyBuilderRoot -Root $Root) -AllowMissingFiles:$AllowMissingFiles
        return [pscustomobject]@{ Valid=$true; Errors=[string[]]@(); Warnings=[string[]]@(); Normalized=$normalized }
    } catch {
        return [pscustomobject]@{ Valid=$false; Errors=[string[]]@($_.Exception.Message); Warnings=[string[]]@(); Normalized=$null }
    }
}

function ConvertTo-NrStrategyBuilderTokens {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Definition,
        [string]$Root,
        [switch]$AllowMissingFiles
    )
    $rootPath=Get-NrStrategyBuilderRoot -Root $Root
    $normalized=ConvertTo-NrNormalizedStrategyDefinition -Definition $Definition -Root $rootPath -AllowMissingFiles:$AllowMissingFiles
    $tokens=New-Object 'System.Collections.Generic.List[string]'
    for ($index=0; $index -lt $normalized.sections.Count; $index++) {
        if ($index -gt 0) { $tokens.Add('--new') }
        $section=$normalized.sections[$index]
        $tokens.Add('--filter-'+$section.protocol+'='+($section.ports -join ','))
        if ($section.hostlistFull) { $tokens.Add('--hostlist='+[string]$section.hostlistFull) }
        if ($section.ipsetFull) { $tokens.Add('--ipset='+[string]$section.ipsetFull) }
        $tokens.Add('--dpi-desync='+($section.desyncModes -join ','))
        if ([int]$section.repeats -ne 1) { $tokens.Add('--dpi-desync-repeats='+[int]$section.repeats) }
        if (@($section.fooling).Count -gt 0) { $tokens.Add('--dpi-desync-fooling='+($section.fooling -join ',')) }
        if (@($section.splitPositions).Count -gt 0) { $tokens.Add('--dpi-desync-split-pos='+($section.splitPositions -join ',')) }
        foreach ($payload in @($section.fakePayloads)) {
            $flag=switch ([string]$payload.kind) {
                'quic' { '--dpi-desync-fake-quic=' }
                'tls' { '--dpi-desync-fake-tls=' }
                'unknown-udp' { '--dpi-desync-fake-unknown-udp=' }
                'unknown-tcp' { '--dpi-desync-fake-unknown-tcp=' }
                default { throw "Unsupported payload kind: $($payload.kind)" }
            }
            $tokens.Add($flag+[string]$payload.fullPath)
        }
    }
    return [string[]]$tokens.ToArray()
}

function ConvertTo-NrWindowsArgument {
    param([AllowEmptyString()][string]$Value)
    if ($null -eq $Value) { return '""' }
    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') { return $Value }
    $builder=New-Object Text.StringBuilder
    [void]$builder.Append('"')
    $backslashes=0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') { $backslashes++; continue }
        if ($character -eq '"') {
            [void]$builder.Append(('\' * ($backslashes*2+1)))
            [void]$builder.Append('"')
            $backslashes=0
            continue
        }
        if ($backslashes -gt 0) { [void]$builder.Append(('\' * $backslashes)); $backslashes=0 }
        [void]$builder.Append($character)
    }
    if ($backslashes -gt 0) { [void]$builder.Append(('\' * ($backslashes*2))) }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function ConvertFrom-NrWindowsCommandLine {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$CommandLine)
    $arguments=New-Object 'System.Collections.Generic.List[string]'
    $length=$CommandLine.Length
    $index=0
    while ($index -lt $length) {
        while ($index -lt $length -and [char]::IsWhiteSpace($CommandLine[$index])) { $index++ }
        if ($index -ge $length) { break }
        $builder=New-Object Text.StringBuilder
        $inQuotes=$false
        while ($index -lt $length) {
            $character=$CommandLine[$index]
            if (-not $inQuotes -and [char]::IsWhiteSpace($character)) { break }
            if ($character -eq '\') {
                $slashCount=0
                while ($index -lt $length -and $CommandLine[$index] -eq '\') { $slashCount++; $index++ }
                if ($index -lt $length -and $CommandLine[$index] -eq '"') {
                    [void]$builder.Append(('\' * [Math]::Floor($slashCount/2)))
                    if (($slashCount % 2) -eq 0) { $inQuotes=-not $inQuotes }
                    else { [void]$builder.Append('"') }
                    $index++
                } else { [void]$builder.Append(('\' * $slashCount)) }
                continue
            }
            if ($character -eq '"') { $inQuotes=-not $inQuotes; $index++; continue }
            [void]$builder.Append($character)
            $index++
        }
        if ($inQuotes) { throw 'Unbalanced quotation mark in command line.' }
        $arguments.Add($builder.ToString())
        while ($index -lt $length -and [char]::IsWhiteSpace($CommandLine[$index])) { $index++ }
    }
    return [string[]]$arguments.ToArray()
}

function New-NrStrategyWorkerCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Definition,
        [string]$Root,
        [switch]$AllowMissingFiles
    )
    $rootPath=Get-NrStrategyBuilderRoot -Root $Root
    $executable=[IO.Path]::GetFullPath((Join-Path $rootPath 'bin/winws.exe'))
    if (-not $AllowMissingFiles -and -not (Test-Path -LiteralPath $executable -PathType Leaf)) { throw "winws.exe is missing: $executable" }
    $arguments=ConvertTo-NrStrategyBuilderTokens -Definition $Definition -Root $rootPath -AllowMissingFiles:$AllowMissingFiles
    $preview=((ConvertTo-NrWindowsArgument -Value $executable)+$(if ($arguments.Count -gt 0) { ' '+(@($arguments | ForEach-Object { ConvertTo-NrWindowsArgument -Value $_ }) -join ' ') } else { '' }))
    $canonical=[ordered]@{ executable=$executable; arguments=[string[]]$arguments } | ConvertTo-Json -Compress -Depth 8
    $sha=[Security.Cryptography.SHA256]::Create()
    try { $hash=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($canonical))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
    return [pscustomobject][ordered]@{ executable=$executable; arguments=[string[]]$arguments; preview=$preview; commandHash=$hash }
}

function ConvertTo-NrBuilderRelativePath {
    param([Parameter(Mandatory)][string]$FullPath,[Parameter(Mandatory)][string]$Root)
    $rootPath=Get-NrStrategyBuilderRoot -Root $Root
    $rootPrefix=$rootPath.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    $resolved=[IO.Path]::GetFullPath($FullPath)
    if (-not $resolved.StartsWith($rootPrefix,[StringComparison]::OrdinalIgnoreCase)) { throw "Token path is outside NexRoute root: $FullPath" }
    return $resolved.Substring($rootPrefix.Length).Replace([IO.Path]::DirectorySeparatorChar,'/')
}

function ConvertFrom-NrStrategyBuilderTokens {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Tokens,
        [Parameter(Mandatory)][string]$Name,
        [string]$Root,
        [bool]$AllowBroadCapture=$false,
        [switch]$AllowMissingFiles
    )
    $rootPath=Get-NrStrategyBuilderRoot -Root $Root
    $sections=New-Object 'System.Collections.Generic.List[object]'
    $current=$null
    $finish={
        if ($null -eq $current) { return }
        if (-not $current.protocol) { throw 'Section is missing a filter token.' }
        $sections.Add((New-NrStrategySection -Protocol $current.protocol -Ports ([string[]]$current.ports) -Hostlist $current.hostlist -Ipset $current.ipset -DesyncModes ([string[]]$current.desyncModes) -Repeats ([int]$current.repeats) -Fooling ([string[]]$current.fooling) -SplitPositions ([string[]]$current.splitPositions) -FakePayloads ([object[]]$current.fakePayloads)))
    }.GetNewClosure()
    foreach ($token in $Tokens) {
        if ($token -eq '--new') { & $finish; $current=$null; continue }
        if ($null -eq $current) {
            $current=[ordered]@{ protocol=$null; ports=@(); hostlist=$null; ipset=$null; desyncModes=@(); repeats=1; fooling=@(); splitPositions=@(); fakePayloads=@() }
        }
        if ($token -match '^--filter-(tcp|udp)=(.+)$') { $current.protocol=$Matches[1]; $current.ports=[string[]]@($Matches[2] -split ','); continue }
        if ($token -match '^--hostlist=(.+)$') { $current.hostlist=ConvertTo-NrBuilderRelativePath -FullPath $Matches[1] -Root $rootPath; continue }
        if ($token -match '^--ipset=(.+)$') { $current.ipset=ConvertTo-NrBuilderRelativePath -FullPath $Matches[1] -Root $rootPath; continue }
        if ($token -match '^--dpi-desync=(.+)$') { $current.desyncModes=[string[]]@($Matches[1] -split ','); continue }
        if ($token -match '^--dpi-desync-repeats=(\d+)$') { $current.repeats=[int]$Matches[1]; continue }
        if ($token -match '^--dpi-desync-fooling=(.+)$') { $current.fooling=[string[]]@($Matches[1] -split ','); continue }
        if ($token -match '^--dpi-desync-split-pos=(.+)$') { $current.splitPositions=[string[]]@($Matches[1] -split ','); continue }
        $payloadKind=$null; $payloadPath=$null
        if ($token -match '^--dpi-desync-fake-quic=(.+)$') { $payloadKind='quic'; $payloadPath=$Matches[1] }
        elseif ($token -match '^--dpi-desync-fake-tls=(.+)$') { $payloadKind='tls'; $payloadPath=$Matches[1] }
        elseif ($token -match '^--dpi-desync-fake-unknown-udp=(.+)$') { $payloadKind='unknown-udp'; $payloadPath=$Matches[1] }
        elseif ($token -match '^--dpi-desync-fake-unknown-tcp=(.+)$') { $payloadKind='unknown-tcp'; $payloadPath=$Matches[1] }
        if ($payloadKind) {
            $relative=ConvertTo-NrBuilderRelativePath -FullPath $payloadPath -Root $rootPath
            $current.fakePayloads=[object[]]@($current.fakePayloads + @(New-NrFakePayloadDefinition -Kind $payloadKind -Path $relative))
            continue
        }
        throw "Unsupported strategy token: $token"
    }
    & $finish
    $definition=New-NrStrategyDefinition -Name $Name -Sections ([object[]]$sections.ToArray()) -AllowBroadCapture $AllowBroadCapture
    return (ConvertTo-NrNormalizedStrategyDefinition -Definition $definition -Root $rootPath -AllowMissingFiles:$AllowMissingFiles)
}

function ConvertTo-NrPortableBuilderToken {
    param([Parameter(Mandatory)][string]$Token,[Parameter(Mandatory)][string]$Root)
    $rootPath=Get-NrStrategyBuilderRoot -Root $Root
    $lists=[IO.Path]::GetFullPath((Join-Path $rootPath 'lists')).TrimEnd('\','/')
    $bin=[IO.Path]::GetFullPath((Join-Path $rootPath 'bin')).TrimEnd('\','/')
    $value=$Token
    if ($value.IndexOf($lists,[StringComparison]::OrdinalIgnoreCase) -ge 0) { $value=$value.Replace($lists,'%LISTS%') }
    if ($value.IndexOf($bin,[StringComparison]::OrdinalIgnoreCase) -ge 0) { $value=$value.Replace($bin,'%BIN%') }
    return $value
}

function Save-NrCustomStrategy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Definition,
        [string]$Root
    )
    $rootPath=Get-NrStrategyBuilderRoot -Root $Root
    $normalized=ConvertTo-NrNormalizedStrategyDefinition -Definition $Definition -Root $rootPath
    $command=New-NrStrategyWorkerCommand -Definition $normalized -Root $rootPath
    $safeName=($normalized.name -replace '[^A-Za-z0-9._-]','-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($safeName)) { throw 'Strategy name does not produce a safe file name.' }
    $definitionDirectory=Join-Path $rootPath '.service/custom-strategies'
    New-Item -ItemType Directory -Path $definitionDirectory -Force | Out-Null
    $definitionPath=Join-Path $definitionDirectory ($safeName+'.json')
    $batchPath=Join-Path $rootPath ('custom-'+$safeName+'.bat')
    $definitionDocument=[ordered]@{
        schemaVersion=2
        savedUtc=[DateTime]::UtcNow.ToString('o')
        definition=$normalized
        commandHash=$command.commandHash
    }
    $temporaryDefinition=$definitionPath+'.tmp-'+[guid]::NewGuid().ToString('N')
    [IO.File]::WriteAllText($temporaryDefinition,($definitionDocument | ConvertTo-Json -Depth 30)+[Environment]::NewLine,(New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temporaryDefinition -Destination $definitionPath -Force
    $portableTokens=[string[]]@($command.arguments | ForEach-Object { ConvertTo-NrPortableBuilderToken -Token $_ -Root $rootPath })
    $portableLine=@($portableTokens | ForEach-Object { ConvertTo-NrWindowsArgument -Value $_ }) -join ' '
    $batch=@(
        '@echo off',
        'setlocal',
        'set "BIN=%~dp0bin"',
        'set "LISTS=%~dp0lists"',
        '"%BIN%\winws.exe" '+$portableLine,
        'exit /b %errorlevel%'
    ) -join "`r`n"
    $temporaryBatch=$batchPath+'.tmp-'+[guid]::NewGuid().ToString('N')
    [IO.File]::WriteAllText($temporaryBatch,$batch+"`r`n",(New-Object Text.UTF8Encoding($true)))
    Move-Item -LiteralPath $temporaryBatch -Destination $batchPath -Force
    return [pscustomobject][ordered]@{ definitionPath=$definitionPath; batchPath=$batchPath; command=$command; portableArguments=$portableTokens }
}

function Import-NrCustomStrategyDefinition {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path,[string]$Root)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Strategy definition file was not found: $Path" }
    $document=Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$document.schemaVersion -ne 2 -or -not $document.definition) { throw 'Unsupported custom strategy document.' }
    return ConvertTo-NrNormalizedStrategyDefinition -Definition $document.definition -Root (Get-NrStrategyBuilderRoot -Root $Root)
}

function Select-NrBuilderSingleValue {
    param([Parameter(Mandatory)][string]$Title,[Parameter(Mandatory)][string[]]$Values)
    if (-not (Get-Command Invoke-NrMenu -ErrorAction SilentlyContinue)) { return $Values[0] }
    $items=@($Values | ForEach-Object { New-NrMenuItem -Id $_ -Label $_ -Section $Title })
    return Invoke-NrMenu -Title $Title -Items $items -AllowEscape
}

function Select-NrBuilderMultipleValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string[]]$Values,
        [string[]]$Selected=@()
    )
    if (-not [Environment]::UserInteractive -or [Console]::IsInputRedirected) { return [string[]]$Selected }
    $index=0
    $set=@{}
    foreach ($item in $Selected) { $set[[string]$item]=$true }
    while ($true) {
        try { Clear-Host } catch { }
        Write-Host $Title -ForegroundColor Cyan
        Write-Host '  ARROWS: move  SPACE: toggle  ENTER: continue  ESC: cancel' -ForegroundColor DarkGray
        Write-Host ''
        for ($itemIndex=0; $itemIndex -lt $Values.Count; $itemIndex++) {
            $value=$Values[$itemIndex]
            $cursor=if ($itemIndex -eq $index) { '>' } else { ' ' }
            $mark=if ($set.ContainsKey($value)) { '[+]' } else { '[ ]' }
            Write-Host ('{0}{1} {2}' -f $cursor,$mark,$value) -ForegroundColor $(if ($itemIndex -eq $index) { [ConsoleColor]::Cyan } elseif ($set.ContainsKey($value)) { [ConsoleColor]::Green } else { [ConsoleColor]::Gray })
        }
        $key=[Console]::ReadKey($true)
        switch ($key.Key) {
            'UpArrow' { $index=($index-1+$Values.Count)%$Values.Count }
            'DownArrow' { $index=($index+1)%$Values.Count }
            'Spacebar' { $value=$Values[$index]; if ($set.ContainsKey($value)) { $set.Remove($value) } else { $set[$value]=$true } }
            'Enter' { return [string[]]@($Values | Where-Object { $set.ContainsKey($_) }) }
            'Escape' { return $null }
        }
    }
}

function Read-NrStrategyBuilderSection {
    [CmdletBinding()]
    param([string]$Root)
    $rootPath=Get-NrStrategyBuilderRoot -Root $Root
    $protocol=Select-NrBuilderSingleValue -Title 'Protocol' -Values @('tcp','udp')
    if (-not $protocol) { return $null }
    $ports=Read-Host 'Ports or ranges separated by comma (example: 80,443)'
    $listFiles=@(Get-ChildItem -LiteralPath (Join-Path $rootPath 'lists') -Filter '*.txt' -File -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($listFiles.Count -eq 0) { throw 'No list files are available for a scoped strategy.' }
    $scopeType=Select-NrBuilderSingleValue -Title 'Filter scope' -Values @('hostlist','ipset','both')
    if (-not $scopeType) { return $null }
    $hostlist=$null; $ipset=$null
    if ($scopeType -in @('hostlist','both')) {
        $selection=Select-NrBuilderSingleValue -Title 'HOSTLIST' -Values ([string[]]@($listFiles.Name))
        if (-not $selection) { return $null }
        $hostlist='lists/'+$selection
    }
    if ($scopeType -in @('ipset','both')) {
        $selection=Select-NrBuilderSingleValue -Title 'IPSET' -Values ([string[]]@($listFiles.Name))
        if (-not $selection) { return $null }
        $ipset='lists/'+$selection
    }
    $modes=Select-NrBuilderMultipleValues -Title 'DPI desynchronization modes' -Values (Get-NrStrategyBuilderAllowedModes)
    if ($null -eq $modes -or $modes.Count -eq 0) { return $null }
    $repeatsText=Read-Host 'Repeats (1-20, default 1)'
    $repeats=if ([string]::IsNullOrWhiteSpace($repeatsText)) { 1 } else { [int]$repeatsText }
    $fooling=Select-NrBuilderMultipleValues -Title 'Fooling modes' -Values ([string[]]@((Get-NrStrategyBuilderAllowedFooling) | Where-Object { $_ -ne 'none' }))
    if ($null -eq $fooling) { return $null }
    $positionsText=Read-Host 'Split positions separated by comma (optional)'
    $positions=if ([string]::IsNullOrWhiteSpace($positionsText)) { @() } else { [string[]]@($positionsText -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
    $payloads=@()
    if ($modes -contains 'fake') {
        $payloadFiles=@(Get-ChildItem -LiteralPath (Join-Path $rootPath 'bin') -Filter '*.bin' -File -ErrorAction SilentlyContinue | Sort-Object Name)
        if ($payloadFiles.Count -gt 0) {
            $usePayload=Select-NrBuilderSingleValue -Title 'Fake payload' -Values @('none','quic','tls','unknown-udp','unknown-tcp')
            if ($usePayload -and $usePayload -ne 'none') {
                $payloadName=Select-NrBuilderSingleValue -Title 'Payload file' -Values ([string[]]@($payloadFiles.Name))
                if ($payloadName) { $payloads=@(New-NrFakePayloadDefinition -Kind $usePayload -Path ('bin/'+$payloadName)) }
            }
        }
    }
    return New-NrStrategySection -Protocol $protocol -Ports ([string[]]@($ports -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) -Hostlist $hostlist -Ipset $ipset -DesyncModes $modes -Repeats $repeats -Fooling $fooling -SplitPositions $positions -FakePayloads $payloads
}

function Show-NrStrategyBuilder {
    [CmdletBinding()]
    param([string]$Root)
    $rootPath=Get-NrStrategyBuilderRoot -Root $Root
    $name=Read-Host 'Strategy name'
    $sections=New-Object 'System.Collections.Generic.List[object]'
    while ($true) {
        $section=Read-NrStrategyBuilderSection -Root $rootPath
        if ($section) { $sections.Add($section) }
        if ($sections.Count -eq 0) { return $null }
        $next=Select-NrBuilderSingleValue -Title 'Strategy sections' -Values @('Save strategy','Add another section','Cancel')
        if ($next -eq 'Add another section') { continue }
        if ($next -ne 'Save strategy') { return $null }
        break
    }
    $definition=New-NrStrategyDefinition -Name $name -Sections ([object[]]$sections.ToArray())
    $validation=Test-NrStrategyDefinition -Definition $definition -Root $rootPath
    if (-not $validation.Valid) {
        if (Get-Command Show-NrMessage -ErrorAction SilentlyContinue) { Show-NrMessage -Title 'Strategy Builder' -Message ($validation.Errors -join [Environment]::NewLine) -Color Red }
        return $validation
    }
    $command=New-NrStrategyWorkerCommand -Definition $validation.Normalized -Root $rootPath
    if (Get-Command Write-NrHeader -ErrorAction SilentlyContinue) { Write-NrHeader -Title 'Strategy Builder / Preview' }
    Write-Host $command.preview -ForegroundColor Gray
    if (Get-Command Confirm-NrY -ErrorAction SilentlyContinue) {
        if (-not (Confirm-NrY -Message 'Save this validated strategy? Press Y to confirm.')) { return $null }
    }
    $saved=Save-NrCustomStrategy -Definition $validation.Normalized -Root $rootPath
    if (Get-Command Show-NrMessage -ErrorAction SilentlyContinue) { Show-NrMessage -Title 'Strategy Builder' -Message ('Saved: '+$saved.batchPath) -Color Green }
    return $saved
}
