Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function ConvertTo-NrBuilderPortRanges {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Ports)
    $ranges=New-Object 'System.Collections.Generic.List[object]'
    foreach ($portValue in @($Ports)) {
        $candidate=([string]$portValue).Trim()
        if ($candidate -notmatch '^(?<start>\d{1,5})(?:-(?<end>\d{1,5}))?$') {
            throw "Invalid port or port range: $candidate"
        }
        $start=[int]$Matches['start']
        $hasEnd=$Matches.ContainsKey('end') -and -not [string]::IsNullOrWhiteSpace([string]$Matches['end'])
        $end=if ($hasEnd) { [int]$Matches['end'] } else { $start }
        if ($start -lt 1 -or $start -gt 65535 -or $end -lt 1 -or $end -gt 65535 -or $end -lt $start) {
            throw "Invalid port bounds: $candidate"
        }
        $text=if ($start -eq $end) { [string]$start } else { "$start-$end" }
        $ranges.Add([pscustomobject]@{ start=$start; end=$end; text=$text })
    }
    if ($ranges.Count -eq 0) { throw 'At least one TCP or UDP port is required.' }
    $ordered=[object[]]@($ranges.ToArray() | Sort-Object start,end)
    for ($index=1; $index -lt $ordered.Count; $index++) {
        if ([int]$ordered[$index].start -le [int]$ordered[$index-1].end) {
            throw 'Port ranges overlap or repeat.'
        }
    }
    return $ordered
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
    $hasControlCharacter=$false
    foreach ($character in $Path.ToCharArray()) {
        if ([char]::IsControl($character)) { $hasControlCharacter=$true; break }
    }
    if ($hasControlCharacter -or $Path -match '[<>|?*"]' -or $Path -match '(^|[\\/])\.\.([\\/]|$)') {
        throw "Unsafe path: $Path"
    }
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

function Add-NrParsedStrategyBuilderSection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.Generic.List[object]]$Sections,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Current
    )
    if ([string]::IsNullOrWhiteSpace([string]$Current['protocol'])) {
        throw 'Section is missing a filter token.'
    }
    if (@($Current['desyncModes']).Count -eq 0) {
        throw 'Section is missing a desynchronization mode.'
    }
    $section=New-NrStrategySection `
        -Protocol ([string]$Current['protocol']) `
        -Ports ([string[]]@($Current['ports'])) `
        -Hostlist ([string]$Current['hostlist']) `
        -Ipset ([string]$Current['ipset']) `
        -DesyncModes ([string[]]@($Current['desyncModes'])) `
        -Repeats ([int]$Current['repeats']) `
        -Fooling ([string[]]@($Current['fooling'])) `
        -SplitPositions ([string[]]@($Current['splitPositions'])) `
        -FakePayloads ([object[]]@($Current['fakePayloads']))
    $Sections.Add($section)
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

    foreach ($tokenValue in @($Tokens)) {
        $token=[string]$tokenValue
        if ($token -eq '--new') {
            if ($null -eq $current) { throw 'Empty strategy section before --new.' }
            Add-NrParsedStrategyBuilderSection -Sections $sections -Current $current
            $current=$null
            continue
        }
        if ($null -eq $current) {
            $current=[ordered]@{
                protocol=$null
                ports=[string[]]@()
                hostlist=$null
                ipset=$null
                desyncModes=[string[]]@()
                repeats=1
                fooling=[string[]]@()
                splitPositions=[string[]]@()
                fakePayloads=[object[]]@()
            }
        }
        if ($token -match '^--filter-(tcp|udp)=(.+)$') {
            if ($current['protocol']) { throw 'A section contains more than one filter token.' }
            $current['protocol']=$Matches[1]
            $current['ports']=[string[]]@($Matches[2] -split ',')
            continue
        }
        if ($token -match '^--hostlist=(.+)$') {
            if ($current['hostlist']) { throw 'A section contains more than one hostlist token.' }
            $current['hostlist']=ConvertTo-NrBuilderRelativePath -FullPath $Matches[1] -Root $rootPath
            continue
        }
        if ($token -match '^--ipset=(.+)$') {
            if ($current['ipset']) { throw 'A section contains more than one ipset token.' }
            $current['ipset']=ConvertTo-NrBuilderRelativePath -FullPath $Matches[1] -Root $rootPath
            continue
        }
        if ($token -match '^--dpi-desync=(.+)$') {
            if (@($current['desyncModes']).Count -gt 0) { throw 'A section contains more than one desynchronization token.' }
            $current['desyncModes']=[string[]]@($Matches[1] -split ',')
            continue
        }
        if ($token -match '^--dpi-desync-repeats=(\d+)$') {
            $current['repeats']=[int]$Matches[1]
            continue
        }
        if ($token -match '^--dpi-desync-fooling=(.+)$') {
            $current['fooling']=[string[]]@($Matches[1] -split ',')
            continue
        }
        if ($token -match '^--dpi-desync-split-pos=(.+)$') {
            $current['splitPositions']=[string[]]@($Matches[1] -split ',')
            continue
        }

        $payloadKind=$null
        $payloadPath=$null
        if ($token -match '^--dpi-desync-fake-quic=(.+)$') { $payloadKind='quic'; $payloadPath=$Matches[1] }
        elseif ($token -match '^--dpi-desync-fake-tls=(.+)$') { $payloadKind='tls'; $payloadPath=$Matches[1] }
        elseif ($token -match '^--dpi-desync-fake-unknown-udp=(.+)$') { $payloadKind='unknown-udp'; $payloadPath=$Matches[1] }
        elseif ($token -match '^--dpi-desync-fake-unknown-tcp=(.+)$') { $payloadKind='unknown-tcp'; $payloadPath=$Matches[1] }
        if ($payloadKind) {
            $relative=ConvertTo-NrBuilderRelativePath -FullPath $payloadPath -Root $rootPath
            $payload=New-NrFakePayloadDefinition -Kind $payloadKind -Path $relative
            $current['fakePayloads']=[object[]]@(@($current['fakePayloads']) + @($payload))
            continue
        }
        throw "Unsupported strategy token: $token"
    }

    if ($null -ne $current) {
        Add-NrParsedStrategyBuilderSection -Sections $sections -Current $current
    }
    if ($sections.Count -eq 0) { throw 'A strategy requires at least one parsed section.' }

    $definition=New-NrStrategyDefinition -Name $Name -Sections ([object[]]$sections.ToArray()) -AllowBroadCapture $AllowBroadCapture
    return ConvertTo-NrNormalizedStrategyDefinition -Definition $definition -Root $rootPath -AllowMissingFiles:$AllowMissingFiles
}
