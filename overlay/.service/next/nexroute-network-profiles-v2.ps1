Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Get-NrNetworkProfilesRoot {
    param([string]$Root)
    if ($Root) { return [IO.Path]::GetFullPath($Root) }
    if (Get-Variable -Name NrRoot -Scope Script -ErrorAction SilentlyContinue) { return [IO.Path]::GetFullPath([string]$script:NrRoot) }
    return [IO.Path]::GetFullPath((Get-Location).Path)
}

function Get-NrNetworkProfilesStatePath {
    param([string]$Root)
    return Join-Path (Get-NrNetworkProfilesRoot -Root $Root) '.service/network-profiles-v2.json'
}

function New-NrNetworkProfilesState {
    [pscustomobject][ordered]@{
        schemaVersion=2
        profiles=@()
        lastApplied=[pscustomobject]@{}
        previousActiveIds=@()
        lastSnapshotFingerprint=$null
        updatedUtc=[DateTime]::UtcNow.ToString('o')
    }
}

function Read-NrNetworkProfilesState {
    [CmdletBinding()]
    param([string]$Root)
    $path=Get-NrNetworkProfilesStatePath -Root $Root
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return New-NrNetworkProfilesState }
    try {
        $state=Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([int]$state.schemaVersion -ne 2) { throw 'Unsupported network profile state schema.' }
        if (-not $state.PSObject.Properties['profiles']) { $state | Add-Member -NotePropertyName profiles -NotePropertyValue @() }
        if (-not $state.PSObject.Properties['lastApplied']) { $state | Add-Member -NotePropertyName lastApplied -NotePropertyValue ([pscustomobject]@{}) }
        if (-not $state.PSObject.Properties['previousActiveIds']) { $state | Add-Member -NotePropertyName previousActiveIds -NotePropertyValue @() }
        return $state
    } catch {
        $backup=$path+'.invalid-'+[DateTime]::UtcNow.ToString('yyyyMMddHHmmss')+'.json'
        Move-Item -LiteralPath $path -Destination $backup -Force -ErrorAction SilentlyContinue
        return New-NrNetworkProfilesState
    }
}

function Write-NrNetworkProfilesState {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$State,[string]$Root)
    $path=Get-NrNetworkProfilesStatePath -Root $Root
    $directory=Split-Path -Parent $path
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $State.updatedUtc=[DateTime]::UtcNow.ToString('o')
    $temporary=$path+'.tmp-'+[guid]::NewGuid().ToString('N')
    [IO.File]::WriteAllText($temporary,($State | ConvertTo-Json -Depth 20)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $path -Force
    return $path
}

function ConvertTo-NrStableAdapterId {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Adapter)
    foreach ($name in @('InterfaceGuid','Guid')) {
        $property=$Adapter.PSObject.Properties[$name]
        if ($property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            return ('guid:'+[string]$property.Value).ToLowerInvariant().Replace('{','').Replace('}','')
        }
    }
    foreach ($name in @('PnPDeviceID','MacAddress','PermanentAddress')) {
        $property=$Adapter.PSObject.Properties[$name]
        if ($property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            $bytes=[Text.Encoding]::UTF8.GetBytes(([string]$property.Value).Trim().ToLowerInvariant())
            $sha=[Security.Cryptography.SHA256]::Create()
            try { return ('hash:'+([BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','').ToLowerInvariant())) }
            finally { $sha.Dispose() }
        }
    }
    $indexProperty=$Adapter.PSObject.Properties['ifIndex']
    if (-not $indexProperty) { $indexProperty=$Adapter.PSObject.Properties['InterfaceIndex'] }
    if ($indexProperty) { return 'index:'+([string]$indexProperty.Value) }
    throw 'Adapter has no stable identity fields.'
}

function Get-NrAdapterMediaType {
    param([Parameter(Mandatory)]$Adapter)
    $text=((@(
        $Adapter.PSObject.Properties['NdisPhysicalMedium'].Value,
        $Adapter.PSObject.Properties['MediaType'].Value,
        $Adapter.PSObject.Properties['InterfaceDescription'].Value,
        $Adapter.PSObject.Properties['Name'].Value
    ) | ForEach-Object { [string]$_ }) -join ' ').ToLowerInvariant()
    if ($text -match 'wireless|wi-?fi|802\.11|wlan') { return 'WiFi' }
    if ($text -match 'ethernet|802\.3') { return 'Ethernet' }
    if ($text -match 'tunnel|vpn|wireguard|tap|tun') { return 'Tunnel' }
    return 'Other'
}

function Get-NrNetworkAdapterSnapshot {
    [CmdletBinding()]
    param([scriptblock]$AdapterProvider,[scriptblock]$ProfileProvider)
    $adapters=if ($AdapterProvider) { @(& $AdapterProvider) } else { @(Get-NetAdapter -ErrorAction Stop) }
    $profiles=if ($ProfileProvider) { @(& $ProfileProvider) } else { @(Get-NetConnectionProfile -ErrorAction SilentlyContinue) }
    $result=New-Object 'System.Collections.Generic.List[object]'
    foreach ($adapter in $adapters) {
        $status=[string]$adapter.Status
        if ($status -ne 'Up') { continue }
        $ifIndex=if ($adapter.PSObject.Properties['ifIndex']) { [int]$adapter.ifIndex } elseif ($adapter.PSObject.Properties['InterfaceIndex']) { [int]$adapter.InterfaceIndex } else { 0 }
        $profile=$profiles | Where-Object { [int]$_.InterfaceIndex -eq $ifIndex } | Select-Object -First 1
        $category=if ($profile -and $profile.PSObject.Properties['NetworkCategory']) { [string]$profile.NetworkCategory } else { 'Unknown' }
        $name=if ($adapter.PSObject.Properties['Name']) { [string]$adapter.Name } else { 'Adapter '+$ifIndex }
        $result.Add([pscustomobject][ordered]@{
            stableId=ConvertTo-NrStableAdapterId -Adapter $adapter
            interfaceIndex=$ifIndex
            name=$name
            mediaType=Get-NrAdapterMediaType -Adapter $adapter
            networkCategory=$category
            networkName=if ($profile -and $profile.PSObject.Properties['Name']) { [string]$profile.Name } else { $null }
            status='Up'
        })
    }
    return @($result | Sort-Object stableId)
}

function Get-NrNetworkSnapshotFingerprint {
    param([Parameter(Mandatory)][object[]]$Snapshot)
    $canonical=@($Snapshot | Sort-Object stableId | ForEach-Object {
        '{0}|{1}|{2}|{3}' -f $_.stableId,$_.mediaType,$_.networkCategory,$_.networkName
    }) -join "`n"
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($canonical))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-NrNetworkProfileHash {
    param([Parameter(Mandatory)]$Profile)
    $canonical=[ordered]@{
        id=[string]$Profile.id
        strategy=[string]$Profile.strategy
        dnsProvider=[string]$Profile.dnsProvider
        dnsEncryption=[string]$Profile.dnsEncryption
        servicePlan=[string]$Profile.servicePlan
    } | ConvertTo-Json -Compress
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($canonical))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Find-NrMatchingNetworkProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Adapter,[Parameter(Mandatory)][object[]]$Profiles)
    $enabled=@($Profiles | Where-Object { -not $_.PSObject.Properties['enabled'] -or [bool]$_.enabled })
    $ranked=foreach ($profile in $enabled) {
        $stable=[string]$profile.stableAdapterId
        $media=[string]$profile.mediaType
        $category=[string]$profile.networkCategory
        $score=-1
        if ($stable -eq [string]$Adapter.stableId -and $category -eq [string]$Adapter.networkCategory) { $score=400 }
        elseif ($stable -eq [string]$Adapter.stableId -and ($category -eq 'Any' -or [string]::IsNullOrWhiteSpace($category))) { $score=300 }
        elseif ($media -eq [string]$Adapter.mediaType -and $category -eq [string]$Adapter.networkCategory) { $score=200 }
        elseif ($media -eq [string]$Adapter.mediaType -and ($category -eq 'Any' -or [string]::IsNullOrWhiteSpace($category))) { $score=100 }
        if ($score -ge 0) { [pscustomobject]@{ profile=$profile; score=$score; id=[string]$profile.id } }
    }
    return ($ranked | Sort-Object @{Expression='score';Descending=$true},id | Select-Object -First 1).profile
}

function Write-NrNetworkProfileHistory {
    param([string]$Root,[string]$Action,$Adapter,$Profile,[string]$Message,[string]$ErrorMessage)
    $directory=Join-Path (Get-NrNetworkProfilesRoot -Root $Root) '.service/history/network-profiles'
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $path=Join-Path $directory ([DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fffffff')+'-'+[guid]::NewGuid().ToString('N')+'.json')
    $record=[ordered]@{
        schemaVersion=1
        timestampUtc=[DateTime]::UtcNow.ToString('o')
        action=$Action
        adapter=$Adapter
        profileId=if ($Profile) { [string]$Profile.id } else { $null }
        message=$Message
        error=$ErrorMessage
    }
    [IO.File]::WriteAllText($path,($record | ConvertTo-Json -Depth 12)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
    return $path
}

function Invoke-NrDefaultNetworkProfileApply {
    param($Profile,$Adapter,[string]$Root)
    if (-not [string]::IsNullOrWhiteSpace([string]$Profile.strategy) -and (Get-Command Get-NrStrategies -ErrorAction SilentlyContinue)) {
        $strategy=Get-NrStrategies | Where-Object { $_.BaseName -eq [string]$Profile.strategy -or $_.Name -eq [string]$Profile.strategy } | Select-Object -First 1
        if (-not $strategy) { throw "Configured strategy was not found: $($Profile.strategy)" }
        Install-NrStrategy -Strategy $strategy -Silent
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Profile.dnsProvider) -and (Get-Command Get-NrDnsProviders -ErrorAction SilentlyContinue)) {
        $provider=Get-NrDnsProviders | Where-Object { $_.id -eq [string]$Profile.dnsProvider } | Select-Object -First 1
        if (-not $provider) { throw "Configured DNS provider was not found: $($Profile.dnsProvider)" }
        $realAdapter=Get-NetAdapter -InterfaceIndex ([int]$Adapter.interfaceIndex) -ErrorAction Stop
        Set-NrDnsProvider -Provider $provider -Adapters @($realAdapter) -Encryption ([string]$Profile.dnsEncryption)
    }
    return $true
}

function Invoke-NrNetworkProfileReconcile {
    [CmdletBinding()]
    param(
        [string]$Root,
        [object[]]$Snapshot,
        [scriptblock]$ApplyProfile,
        [scriptblock]$AdapterProvider,
        [scriptblock]$ProfileProvider
    )
    $rootPath=Get-NrNetworkProfilesRoot -Root $Root
    $state=Read-NrNetworkProfilesState -Root $rootPath
    if ($null -eq $Snapshot) { $Snapshot=@(Get-NrNetworkAdapterSnapshot -AdapterProvider $AdapterProvider -ProfileProvider $ProfileProvider) }
    $Snapshot=@($Snapshot | Sort-Object stableId)
    $activeIds=@($Snapshot | ForEach-Object { [string]$_.stableId })
    $previousIds=@($state.previousActiveIds | ForEach-Object { [string]$_ })
    $arrived=@($activeIds | Where-Object { $_ -notin $previousIds })
    $removed=@($previousIds | Where-Object { $_ -notin $activeIds })
    foreach ($id in $removed) { Write-NrNetworkProfileHistory -Root $rootPath -Action 'removed' -Adapter ([pscustomobject]@{ stableId=$id }) -Profile $null -Message 'Adapter removed' | Out-Null }
    foreach ($id in $arrived) { Write-NrNetworkProfileHistory -Root $rootPath -Action 'arrived' -Adapter ($Snapshot | Where-Object stableId -eq $id | Select-Object -First 1) -Profile $null -Message 'Adapter arrived' | Out-Null }

    $applied=0; $skipped=0; $failed=0; $unmatched=0
    $lastApplied=[ordered]@{}
    foreach ($property in @($state.lastApplied.PSObject.Properties)) { $lastApplied[$property.Name]=$property.Value }
    foreach ($adapter in $Snapshot) {
        $profile=Find-NrMatchingNetworkProfile -Adapter $adapter -Profiles @($state.profiles)
        if (-not $profile) {
            $unmatched++
            Write-NrNetworkProfileHistory -Root $rootPath -Action 'no-profile' -Adapter $adapter -Profile $null -Message 'No matching profile' | Out-Null
            continue
        }
        $key=([string]$adapter.stableId)+'|'+([string]$adapter.networkCategory)
        $profileHash=Get-NrNetworkProfileHash -Profile $profile
        $previous=$lastApplied[$key]
        if ($previous -and [string]$previous.profileHash -eq $profileHash) {
            $skipped++
            Write-NrNetworkProfileHistory -Root $rootPath -Action 'unchanged' -Adapter $adapter -Profile $profile -Message 'Profile already applied' | Out-Null
            continue
        }
        try {
            if ($ApplyProfile) { $ok=& $ApplyProfile $profile $adapter $rootPath }
            else { $ok=Invoke-NrDefaultNetworkProfileApply -Profile $profile -Adapter $adapter -Root $rootPath }
            if ($false -eq $ok) { throw 'Profile apply callback returned false.' }
            $lastApplied[$key]=[pscustomobject][ordered]@{ profileId=[string]$profile.id; profileHash=$profileHash; appliedUtc=[DateTime]::UtcNow.ToString('o') }
            $applied++
            Write-NrNetworkProfileHistory -Root $rootPath -Action 'applied' -Adapter $adapter -Profile $profile -Message 'Profile applied' | Out-Null
        } catch {
            $failed++
            Write-NrNetworkProfileHistory -Root $rootPath -Action 'failed' -Adapter $adapter -Profile $profile -Message 'Profile apply failed' -ErrorMessage $_.Exception.Message | Out-Null
        }
    }
    $state.lastApplied=[pscustomobject]$lastApplied
    $state.previousActiveIds=@($activeIds)
    $state.lastSnapshotFingerprint=Get-NrNetworkSnapshotFingerprint -Snapshot $Snapshot
    Write-NrNetworkProfilesState -State $state -Root $rootPath | Out-Null
    return [pscustomobject]@{ applied=$applied; skipped=$skipped; failed=$failed; unmatched=$unmatched; arrived=$arrived.Count; removed=$removed.Count; fingerprint=$state.lastSnapshotFingerprint }
}

function Set-NrNetworkProfileDefinition {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Profile,[string]$Root)
    if ([string]::IsNullOrWhiteSpace([string]$Profile.id)) { throw 'Network profile id is required.' }
    if ([string]::IsNullOrWhiteSpace([string]$Profile.stableAdapterId) -and [string]::IsNullOrWhiteSpace([string]$Profile.mediaType)) { throw 'Profile requires stableAdapterId or mediaType.' }
    $state=Read-NrNetworkProfilesState -Root $Root
    $profiles=New-Object 'System.Collections.Generic.List[object]'
    foreach ($existing in @($state.profiles)) { if ([string]$existing.id -ne [string]$Profile.id) { $profiles.Add($existing) } }
    $profiles.Add($Profile)
    $state.profiles=@($profiles)
    Write-NrNetworkProfilesState -State $state -Root $Root | Out-Null
    return $Profile
}

function Save-NrCurrentNetworkProfile {
    [CmdletBinding()]
    param([string]$Root)
    $rootPath=Get-NrNetworkProfilesRoot -Root $Root
    $snapshot=@(Get-NrNetworkAdapterSnapshot)
    $strategy=if (Get-Command Get-NrInstalledStrategy -ErrorAction SilentlyContinue) { [string](Get-NrInstalledStrategy) } else { $null }
    foreach ($adapter in $snapshot) {
        $profile=[pscustomobject][ordered]@{
            id='adapter-'+(($adapter.stableId -replace '[^a-zA-Z0-9.-]','-'))+'-'+$adapter.networkCategory.ToLowerInvariant()
            stableAdapterId=[string]$adapter.stableId
            mediaType=[string]$adapter.mediaType
            networkCategory=[string]$adapter.networkCategory
            strategy=$strategy
            dnsProvider=if (Get-Variable -Name NrState -Scope Script -ErrorAction SilentlyContinue) { [string]$script:NrState.dnsProvider } else { 'system' }
            dnsEncryption=if (Get-Variable -Name NrState -Scope Script -ErrorAction SilentlyContinue) { [string]$script:NrState.dnsEncryption } else { 'system' }
            servicePlan=$null
            enabled=$true
        }
        Set-NrNetworkProfileDefinition -Profile $profile -Root $rootPath | Out-Null
    }
    return @($snapshot)
}

function Apply-NrNetworkProfile {
    [CmdletBinding()]
    param([string]$Root)
    $result=Invoke-NrNetworkProfileReconcile -Root $Root
    return ($result.failed -eq 0 -and ($result.applied -gt 0 -or $result.skipped -gt 0))
}

function Start-NrNetworkProfileWatcher {
    [CmdletBinding()]
    param([string]$Root,[int]$DebounceSeconds=2,[int]$PollTimeoutSeconds=30,[string]$StopFile)
    if ($env:OS -ne 'Windows_NT') { throw 'Network profile watcher requires Windows.' }
    $rootPath=Get-NrNetworkProfilesRoot -Root $Root
    if (-not $StopFile) { $StopFile=Join-Path $rootPath '.service/network-profile-watcher.stop' }
    Remove-Item -LiteralPath $StopFile -Force -ErrorAction SilentlyContinue
    $sourcePrefix='NexRoute.NetworkProfile.'+[guid]::NewGuid().ToString('N')
    $subscriptions=New-Object 'System.Collections.Generic.List[string]'
    try {
        foreach ($eventClass in @('__InstanceCreationEvent','__InstanceDeletionEvent','__InstanceModificationEvent')) {
            $identifier=$sourcePrefix+'.'+$eventClass
            $query="SELECT * FROM $eventClass WITHIN 3 WHERE TargetInstance ISA 'MSFT_NetAdapter'"
            Register-CimIndicationEvent -Namespace 'root/StandardCimv2' -Query $query -SourceIdentifier $identifier | Out-Null
            $subscriptions.Add($identifier)
        }
        Invoke-NrNetworkProfileReconcile -Root $rootPath | Out-Null
        while (-not (Test-Path -LiteralPath $StopFile -PathType Leaf)) {
            $event=Wait-Event -Timeout $PollTimeoutSeconds
            if ($event -and [string]$event.SourceIdentifier -like ($sourcePrefix+'*')) {
                Remove-Event -EventIdentifier $event.EventIdentifier -ErrorAction SilentlyContinue
                Start-Sleep -Seconds ([Math]::Max(0,$DebounceSeconds))
                Invoke-NrNetworkProfileReconcile -Root $rootPath | Out-Null
            }
        }
    } finally {
        foreach ($identifier in $subscriptions) { Unregister-Event -SourceIdentifier $identifier -Force -ErrorAction SilentlyContinue }
        Get-Event | Where-Object { [string]$_.SourceIdentifier -like ($sourcePrefix+'*') } | Remove-Event -ErrorAction SilentlyContinue
    }
}
