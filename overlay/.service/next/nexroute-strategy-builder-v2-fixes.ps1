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
