Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Get-NrObjectPropertyValue {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Name
    )
    $property=$Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function Get-NrAdapterMediaType {
    param([Parameter(Mandatory)]$Adapter)
    $values=@(
        Get-NrObjectPropertyValue -Object $Adapter -Name 'NdisPhysicalMedium'
        Get-NrObjectPropertyValue -Object $Adapter -Name 'MediaType'
        Get-NrObjectPropertyValue -Object $Adapter -Name 'InterfaceDescription'
        Get-NrObjectPropertyValue -Object $Adapter -Name 'Name'
    )
    $text=(@($values | ForEach-Object { [string]$_ }) -join ' ').ToLowerInvariant()
    if ($text -match 'wireless|wi-?fi|802\.11|wlan') { return 'WiFi' }
    if ($text -match 'ethernet|802\.3') { return 'Ethernet' }
    if ($text -match 'tunnel|vpn|wireguard|tap|tun') { return 'Tunnel' }
    return 'Other'
}

function Set-NrNetworkProfileDefinition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Profile,
        [string]$Root
    )
    if ([string]::IsNullOrWhiteSpace([string]$Profile.id)) {
        throw 'Network profile id is required.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$Profile.stableAdapterId) -and
        [string]::IsNullOrWhiteSpace([string]$Profile.mediaType)) {
        throw 'Profile requires stableAdapterId or mediaType.'
    }

    $state=Read-NrNetworkProfilesState -Root $Root
    $existingProfiles=@($state.profiles)
    $profiles=@($existingProfiles | Where-Object { [string]$_.id -ne [string]$Profile.id })
    $state.profiles=[object[]]@($profiles + @($Profile))
    Write-NrNetworkProfilesState -State $state -Root $Root | Out-Null
    return $Profile
}
