Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Get-NrDnsAdapterSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Adapters,
        [scriptblock]$AddressReader
    )
    $rows=New-Object 'System.Collections.Generic.List[object]'
    foreach ($adapter in $Adapters) {
        $index=[int]$adapter.ifIndex
        $addresses=New-Object 'System.Collections.Generic.List[string]'
        foreach ($family in @('IPv4','IPv6')) {
            try {
                if ($AddressReader) { $entries=@(& $AddressReader $index $family) }
                else { $entries=@(Get-DnsClientServerAddress -InterfaceIndex $index -AddressFamily $family -ErrorAction Stop) }
                foreach ($entry in $entries) {
                    foreach ($address in @($entry.ServerAddresses)) {
                        $value=([string]$address).Trim()
                        if ($value -and -not $addresses.Contains($value)) { $addresses.Add($value) }
                    }
                }
            } catch { }
        }
        $rows.Add([pscustomobject]@{
            interfaceIndex=$index
            interfaceAlias=[string]$adapter.Name
            serverAddresses=[string[]]$addresses.ToArray()
        })
    }
    return $rows.ToArray()
}

function Restore-NrDnsAdapterSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Snapshot,
        [scriptblock]$AddressSetter,
        [scriptblock]$CacheFlusher
    )
    foreach ($entry in $Snapshot) {
        $addresses=[string[]]@($entry.serverAddresses | Where-Object { $_ })
        if ($AddressSetter) {
            & $AddressSetter ([int]$entry.interfaceIndex) $addresses ($addresses.Count -eq 0)
        } elseif ($addresses.Count -gt 0) {
            Set-DnsClientServerAddress -InterfaceIndex ([int]$entry.interfaceIndex) -ServerAddresses $addresses -ErrorAction Stop
        } else {
            Set-DnsClientServerAddress -InterfaceIndex ([int]$entry.interfaceIndex) -ResetServerAddresses -ErrorAction Stop
        }
    }
    if ($CacheFlusher) { & $CacheFlusher }
    else { Clear-DnsClientCache -ErrorAction SilentlyContinue }
}
