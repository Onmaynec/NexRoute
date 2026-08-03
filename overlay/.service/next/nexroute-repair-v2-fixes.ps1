Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

if (-not (Get-Variable -Name NrEvidenceConflictReportV2Base -Scope Script -ErrorAction SilentlyContinue)) {
    $script:NrEvidenceConflictReportV2Base=${function:Get-NrEvidenceConflictReport}
}

function ConvertTo-NrNormalizedEvidence {
    [CmdletBinding()]
    param([object[]]$Evidence)
    $normalized=New-Object 'System.Collections.Generic.List[string]'
    $items=@($Evidence)
    for ($index=0; $index -lt $items.Count; $index++) {
        $value=[string]$items[$index]
        if ($value.EndsWith('=') -and ($index+1) -lt $items.Count) {
            $value+=[string]$items[$index+1]
            $index++
        }
        if (-not [string]::IsNullOrWhiteSpace($value)) { $normalized.Add($value) }
    }
    return [string[]]$normalized.ToArray()
}

function Get-NrEvidenceConflictReport {
    [CmdletBinding()]
    param(
        [scriptblock]$ServiceProvider,
        [scriptblock]$AdapterProvider,
        [scriptblock]$RouteProvider,
        [scriptblock]$FirewallRuleProvider,
        [scriptblock]$AntivirusProvider,
        [scriptblock]$DriverProvider
    )
    $parameters=@{}
    foreach ($entry in $PSBoundParameters.GetEnumerator()) { $parameters[$entry.Key]=$entry.Value }
    $findings=@(& $script:NrEvidenceConflictReportV2Base @parameters)
    foreach ($finding in $findings) {
        $finding.evidence=[string[]](ConvertTo-NrNormalizedEvidence -Evidence @($finding.evidence))
    }
    return [object[]]$findings
}
