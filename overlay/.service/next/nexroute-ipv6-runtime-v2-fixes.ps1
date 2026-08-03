Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function ConvertTo-NrFamilyStrategyArguments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][ValidateSet('ipv4','ipv6')][string]$Family,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$OriginalIpset,
        [string]$FamilyIpset,
        [bool]$HasFamilyIpset
    )
    $originalFull=[IO.Path]::GetFullPath($OriginalIpset.Trim('"'))
    if ($HasFamilyIpset) {
        if ([string]::IsNullOrWhiteSpace($FamilyIpset)) { throw "The generated $Family ipset path is empty." }
        $FamilyIpset=[IO.Path]::GetFullPath($FamilyIpset.Trim('"'))
    }
    $result=New-Object 'System.Collections.Generic.List[string]'
    $result.Add('--filter-l3='+$Family)
    foreach ($argumentValue in @($Arguments)) {
        $argument=[string]$argumentValue
        if ($argument -eq '--new') {
            $result.Add('--new')
            $result.Add('--filter-l3='+$Family)
            continue
        }
        if ($argument -match '^--filter-l3=') { continue }
        if ($argument.StartsWith('--ipset=',[StringComparison]::OrdinalIgnoreCase)) {
            $existing=$argument.Substring('--ipset='.Length).Trim('"')
            if ([string]::IsNullOrWhiteSpace($existing)) { throw 'Malformed winws argument: --ipset has no path.' }
            $existingFull=[IO.Path]::GetFullPath($existing)
            if ($existingFull.Equals($originalFull,[StringComparison]::OrdinalIgnoreCase)) {
                if ($HasFamilyIpset) { $result.Add('--ipset='+$FamilyIpset) }
                continue
            }
        }
        $result.Add($argument)
    }
    return [string[]]$result.ToArray()
}
