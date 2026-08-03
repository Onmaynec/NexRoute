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
