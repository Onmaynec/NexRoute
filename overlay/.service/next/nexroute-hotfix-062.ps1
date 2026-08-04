Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Preserve the canonical diagnostic implementation and expose the compatibility
# fields consumed by the first-run console introduced before schemaVersion 3.
$script:NrDiagnosticReport062Core = ${function:Get-NrDiagnosticReport}

function Get-NrDiagnosticReport {
    $report = & $script:NrDiagnosticReport062Core
    if ($null -eq $report) {
        throw 'NexRoute diagnostic report returned no data.'
    }

    $nexroute = $report.nexroute
    $windows = $report.windows
    $networkKey = [string]$nexroute.networkKey
    $serviceRunning = [bool]$nexroute.serviceRunning
    $winDivertRunning = [bool]$nexroute.winDivertRunning
    $winwsRunning = [bool]$nexroute.winwsRunning
    $administrator = [bool]$windows.elevated

    if ($report -is [System.Collections.IDictionary]) {
        $report['administrator'] = $administrator
        $report['runtime'] = [ordered]@{
            zapret = $serviceRunning
            winDivert = $winDivertRunning
            winws = $winwsRunning
        }
        $report['network'] = $networkKey
    } else {
        $report | Add-Member -NotePropertyName administrator -NotePropertyValue $administrator -Force
        $report | Add-Member -NotePropertyName runtime -NotePropertyValue ([pscustomobject]@{
            zapret = $serviceRunning
            winDivert = $winDivertRunning
            winws = $winwsRunning
        }) -Force
        $report | Add-Member -NotePropertyName network -NotePropertyValue $networkKey -Force
    }

    $compatibleConflicts = New-Object 'System.Collections.Generic.List[object]'
    foreach ($conflict in @($report.conflicts)) {
        if ($null -eq $conflict) { continue }
        $detected = ([string]$conflict.severity -eq 'warning')
        if ($conflict -is [System.Collections.IDictionary]) {
            $conflict['detected'] = $detected
        } else {
            $conflict | Add-Member -NotePropertyName detected -NotePropertyValue $detected -Force
        }
        $compatibleConflicts.Add($conflict)
    }

    if ($report -is [System.Collections.IDictionary]) {
        $report['conflicts'] = $compatibleConflicts.ToArray()
    } else {
        $report.conflicts = $compatibleConflicts.ToArray()
    }

    return $report
}
