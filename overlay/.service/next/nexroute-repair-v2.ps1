Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Get-NrRepairRoot {
    param([string]$Root)
    if ($Root) { return [IO.Path]::GetFullPath($Root) }
    if (Get-Variable -Name NrRoot -Scope Script -ErrorAction SilentlyContinue) { return [IO.Path]::GetFullPath([string]$script:NrRoot) }
    return [IO.Path]::GetFullPath((Get-Location).Path)
}

function Get-NrSafeProperty {
    param($Object,[Parameter(Mandatory)][string]$Name,$Default=$null)
    if ($null -eq $Object) { return $Default }
    $property=$Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $Default
}

function Write-NrAtomicJson {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Value,[int]$Depth=20)
    $directory=Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $temporary=$Path+'.tmp-'+[guid]::NewGuid().ToString('N')
    [IO.File]::WriteAllText($temporary,($Value | ConvertTo-Json -Depth $Depth)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function New-NrRepairBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Action,
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)]$Snapshot,
        [string]$Root
    )
    $rootPath=Get-NrRepairRoot -Root $Root
    $directory=Join-Path $rootPath ('.service/backups/repairs/'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fffffff')+'-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $backup=[ordered]@{
        schemaVersion=1
        createdUtc=[DateTime]::UtcNow.ToString('o')
        action=$Action
        target=$Target
        snapshot=$Snapshot
    }
    $backupPath=Join-Path $directory 'backup.json'
    Write-NrAtomicJson -Path $backupPath -Value $backup
    return [pscustomobject]@{ directory=$directory; backupPath=$backupPath; snapshot=$Snapshot }
}

function Write-NrRepairTransaction {
    param([Parameter(Mandatory)]$Backup,[Parameter(Mandatory)][string]$State,[string]$ErrorMessage,[object]$Verification)
    $record=[ordered]@{
        schemaVersion=1
        updatedUtc=[DateTime]::UtcNow.ToString('o')
        state=$State
        backupPath=[string]$Backup.backupPath
        verification=$Verification
        error=$ErrorMessage
    }
    $path=Join-Path ([string]$Backup.directory) 'transaction.json'
    Write-NrAtomicJson -Path $path -Value $record
    return $path
}

function Invoke-NrRepairTransaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Action,
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][scriptblock]$Snapshot,
        [Parameter(Mandatory)][scriptblock]$Apply,
        [Parameter(Mandatory)][scriptblock]$Verify,
        [Parameter(Mandatory)][scriptblock]$Rollback,
        [string]$Root
    )
    $snapshotData=& $Snapshot
    $backup=New-NrRepairBackup -Action $Action -Target $Target -Snapshot $snapshotData -Root $Root
    $transactionPath=Write-NrRepairTransaction -Backup $backup -State 'prepared' -ErrorMessage $null -Verification $null
    try {
        & $Apply $snapshotData
        $verification=& $Verify $snapshotData
        $verified=if ($verification -is [bool]) { [bool]$verification } elseif ($verification -and $verification.PSObject.Properties['ok']) { [bool]$verification.ok } else { $false }
        if (-not $verified) { throw 'Repair verification failed.' }
        $transactionPath=Write-NrRepairTransaction -Backup $backup -State 'committed' -ErrorMessage $null -Verification $verification
        return [pscustomobject]@{ success=$true; state='committed'; rolledBack=$false; backupPath=$backup.backupPath; transactionPath=$transactionPath; verification=$verification; error=$null }
    } catch {
        $originalError=$_.Exception.Message
        $rollbackError=$null
        try { & $Rollback $snapshotData }
        catch { $rollbackError=$_.Exception.Message }
        $state=if ($rollbackError) { 'rollback-failed' } else { 'rolled-back' }
        $errorText=if ($rollbackError) { $originalError+' Rollback failed: '+$rollbackError } else { $originalError }
        $transactionPath=Write-NrRepairTransaction -Backup $backup -State $state -ErrorMessage $errorText -Verification $null
        return [pscustomobject]@{ success=$false; state=$state; rolledBack=(-not $rollbackError); backupPath=$backup.backupPath; transactionPath=$transactionPath; verification=$null; error=$errorText }
    }
}

function Get-NrKnownSecurityProduct {
    param([string]$Name)
    $normalized=([string]$Name).ToLowerInvariant()
    $catalog=@(
        [pscustomobject]@{ pattern='microsoft defender|windows defender'; vendor='Microsoft'; product='Microsoft Defender Antivirus'; action='defender-path-exclusion' },
        [pscustomobject]@{ pattern='kaspersky'; vendor='Kaspersky'; product='Kaspersky'; action='manual-vendor-exclusion' },
        [pscustomobject]@{ pattern='eset|nod32'; vendor='ESET'; product='ESET'; action='manual-vendor-exclusion' },
        [pscustomobject]@{ pattern='avast'; vendor='Avast'; product='Avast'; action='manual-vendor-exclusion' },
        [pscustomobject]@{ pattern='avg'; vendor='AVG'; product='AVG'; action='manual-vendor-exclusion' },
        [pscustomobject]@{ pattern='bitdefender'; vendor='Bitdefender'; product='Bitdefender'; action='manual-vendor-exclusion' },
        [pscustomobject]@{ pattern='malwarebytes'; vendor='Malwarebytes'; product='Malwarebytes'; action='manual-vendor-exclusion' },
        [pscustomobject]@{ pattern='norton|symantec'; vendor='Norton'; product='Norton/Symantec'; action='manual-vendor-exclusion' },
        [pscustomobject]@{ pattern='mcafee'; vendor='McAfee'; product='McAfee'; action='manual-vendor-exclusion' }
    )
    return $catalog | Where-Object { $normalized -match $_.pattern } | Select-Object -First 1
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
    $services=try { if ($ServiceProvider) { @(& $ServiceProvider) } else { @(Get-CimInstance Win32_Service -ErrorAction Stop) } } catch { @() }
    $adapters=try { if ($AdapterProvider) { @(& $AdapterProvider) } else { @(Get-NetAdapter -ErrorAction Stop) } } catch { @() }
    $routes=try { if ($RouteProvider) { @(& $RouteProvider) } else { @(Get-NetRoute -ErrorAction Stop) } } catch { @() }
    $firewallRules=try { if ($FirewallRuleProvider) { @(& $FirewallRuleProvider) } else { @(Get-NetFirewallRule -ErrorAction Stop) } } catch { @() }
    $antivirus=try { if ($AntivirusProvider) { @(& $AntivirusProvider) } else { @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction Stop) } } catch { @() }
    $drivers=try { if ($DriverProvider) { @(& $DriverProvider) } else { @(Get-ChildItem -LiteralPath (Join-Path $env:SystemRoot 'System32/drivers') -Filter '*WinDivert*.sys' -File -ErrorAction Stop) } } catch { @() }

    $findings=New-Object 'System.Collections.Generic.List[object]'
    $adapterByIndex=@{}
    foreach ($adapter in $adapters) {
        $index=Get-NrSafeProperty -Object $adapter -Name 'ifIndex' -Default (Get-NrSafeProperty -Object $adapter -Name 'InterfaceIndex' -Default 0)
        $adapterByIndex[[int]$index]=$adapter
    }

    foreach ($route in $routes) {
        $destination=[string](Get-NrSafeProperty -Object $route -Name 'DestinationPrefix')
        if ($destination -notin @('0.0.0.0/0','::/0')) { continue }
        $index=[int](Get-NrSafeProperty -Object $route -Name 'InterfaceIndex' -Default 0)
        $adapter=$adapterByIndex[$index]
        $adapterText=((@(
            Get-NrSafeProperty -Object $adapter -Name 'Name'
            Get-NrSafeProperty -Object $adapter -Name 'InterfaceDescription'
            Get-NrSafeProperty -Object $adapter -Name 'MediaType'
        ) | ForEach-Object { [string]$_ }) -join ' ')
        if ($adapterText -match '(?i)vpn|wireguard|openvpn|tailscale|zerotier|tunnel|tap|tun') {
            $findings.Add([pscustomobject][ordered]@{
                id='vpn-default-route-'+$index+'-'+($destination -replace '[^a-zA-Z0-9]','-')
                category='VPN'; severity='warning'; confidence='high'; status='active-route'; product=$adapterText.Trim(); compatibility='unverified'
                evidence=@("DestinationPrefix=$destination","InterfaceIndex=$index",'RouteMetric='+(Get-NrSafeProperty -Object $route -Name 'RouteMetric' -Default 'unknown'))
                repairAction='increase-vpn-interface-metric'; reversible=$true
            })
        }
    }

    foreach ($rule in $firewallRules) {
        $action=[string](Get-NrSafeProperty -Object $rule -Name 'Action')
        $enabled=[string](Get-NrSafeProperty -Object $rule -Name 'Enabled')
        $text=((@(
            Get-NrSafeProperty -Object $rule -Name 'DisplayName'
            Get-NrSafeProperty -Object $rule -Name 'Name'
            Get-NrSafeProperty -Object $rule -Name 'Program'
            Get-NrSafeProperty -Object $rule -Name 'Service'
            Get-NrSafeProperty -Object $rule -Name 'Description'
        ) | ForEach-Object { [string]$_ }) -join ' ')
        if ($action -match '(?i)block' -and $enabled -notmatch '(?i)false|no' -and $text -match '(?i)nexroute|winws|windivert') {
            $findings.Add([pscustomobject][ordered]@{
                id='firewall-block-'+([string](Get-NrSafeProperty -Object $rule -Name 'Name' -Default ([guid]::NewGuid().ToString('N'))))
                category='FIREWALL'; severity='error'; confidence='high'; status='blocking-rule'; product=[string](Get-NrSafeProperty -Object $rule -Name 'DisplayName' -Default 'Windows Firewall'); compatibility='blocked'
                evidence=@('Action='+$action,'Enabled='+$enabled,'Rule='+$text.Trim())
                repairAction='disable-specific-block-rule'; reversible=$true
            })
        }
    }

    $winDivertServices=@($services | Where-Object {
        ([string](Get-NrSafeProperty -Object $_ -Name 'Name') -match '(?i)windivert') -or
        ([string](Get-NrSafeProperty -Object $_ -Name 'DisplayName') -match '(?i)windivert')
    })
    $runningWinDivert=@($winDivertServices | Where-Object { [string](Get-NrSafeProperty -Object $_ -Name 'State' -Default (Get-NrSafeProperty -Object $_ -Name 'Status')) -match '(?i)running' })
    if ($runningWinDivert.Count -gt 1) {
        foreach ($service in $runningWinDivert) {
            $name=[string](Get-NrSafeProperty -Object $service -Name 'Name')
            $findings.Add([pscustomobject][ordered]@{
                id='windivert-service-'+$name; category='WINDIVERT'; severity='warning'; confidence='high'; status='parallel-service'; product=$name; compatibility='conflict-likely'
                evidence=@('State=Running','Path='+(Get-NrSafeProperty -Object $service -Name 'PathName' -Default 'unknown'),'RunningWinDivertServices='+$runningWinDivert.Count)
                repairAction='stop-extra-windivert-service'; reversible=$true
            })
        }
    }
    foreach ($driver in $drivers) {
        $findings.Add([pscustomobject][ordered]@{
            id='windivert-driver-'+([string](Get-NrSafeProperty -Object $driver -Name 'Name' -Default 'unknown')); category='WINDIVERT'; severity='info'; confidence='high'; status='driver-present'; product=[string](Get-NrSafeProperty -Object $driver -Name 'Name' -Default 'WinDivert driver'); compatibility='unverified'
            evidence=@('Path='+(Get-NrSafeProperty -Object $driver -Name 'FullName' -Default 'unknown'),'Length='+(Get-NrSafeProperty -Object $driver -Name 'Length' -Default 'unknown'))
            repairAction=$null; reversible=$false
        })
    }

    foreach ($product in $antivirus) {
        $name=[string](Get-NrSafeProperty -Object $product -Name 'displayName' -Default (Get-NrSafeProperty -Object $product -Name 'DisplayName' -Default 'Unknown security product'))
        $known=Get-NrKnownSecurityProduct -Name $name
        $state=Get-NrSafeProperty -Object $product -Name 'productState' -Default 'unknown'
        $path=Get-NrSafeProperty -Object $product -Name 'pathToSignedProductExe' -Default (Get-NrSafeProperty -Object $product -Name 'PathToSignedProductExe' -Default 'unknown')
        $findings.Add([pscustomobject][ordered]@{
            id='security-product-'+(($name -replace '[^a-zA-Z0-9.-]','-').ToLowerInvariant())
            category='ANTIVIRUS'; severity='info'; confidence='high'; status='detected'; product=$name
            compatibility=if ($known) { 'recognized-unverified' } else { 'UNKNOWN' }
            evidence=@('ProductState='+$state,'SignedProductPath='+$path)
            repairAction=if ($known) { [string]$known.action } else { $null }
            reversible=if ($known -and $known.action -eq 'defender-path-exclusion') { $true } else { $false }
        })
    }

    return [object[]]$findings.ToArray()
}

function Invoke-NrFirewallRuleRepair {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RuleName,
        [string]$Root,
        [scriptblock]$GetRule,
        [scriptblock]$DisableRule,
        [scriptblock]$EnableRule,
        [scriptblock]$VerifyRule
    )
    if (-not $GetRule) { $GetRule={ Get-NetFirewallRule -Name $RuleName -ErrorAction Stop } }
    if (-not $DisableRule) { $DisableRule={ param($snapshot) Disable-NetFirewallRule -Name $RuleName -ErrorAction Stop | Out-Null } }
    if (-not $EnableRule) { $EnableRule={ param($snapshot) if ([string]$snapshot.Enabled -match '(?i)true|yes') { Enable-NetFirewallRule -Name $RuleName -ErrorAction Stop | Out-Null } } }
    if (-not $VerifyRule) { $VerifyRule={ param($snapshot) $rule=Get-NetFirewallRule -Name $RuleName -ErrorAction Stop; return ([string]$rule.Enabled -match '(?i)false|no') } }
    return Invoke-NrRepairTransaction -Action 'firewall-disable-block-rule' -Target $RuleName -Root $Root -Snapshot $GetRule -Apply $DisableRule -Verify $VerifyRule -Rollback $EnableRule
}

function Invoke-NrVpnMetricRepair {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$InterfaceIndex,
        [int]$TemporaryMetric=5000,
        [string]$Root,
        [scriptblock]$GetMetric,
        [scriptblock]$SetMetric,
        [scriptblock]$VerifyMetric
    )
    if (-not $GetMetric) { $GetMetric={ Get-NetIPInterface -InterfaceIndex $InterfaceIndex -ErrorAction Stop | Select-Object InterfaceIndex,AddressFamily,InterfaceMetric,AutomaticMetric } }
    if (-not $SetMetric) { $SetMetric={ param($snapshot,$metric) foreach ($entry in @($snapshot)) { Set-NetIPInterface -InterfaceIndex $InterfaceIndex -AddressFamily $entry.AddressFamily -AutomaticMetric Disabled -InterfaceMetric $metric -ErrorAction Stop } } }
    if (-not $VerifyMetric) { $VerifyMetric={ param($snapshot,$metric) $current=@(Get-NetIPInterface -InterfaceIndex $InterfaceIndex -ErrorAction Stop); return (@($current | Where-Object { [int]$_.InterfaceMetric -ne $metric }).Count -eq 0) } }
    $apply={ param($snapshot) & $SetMetric $snapshot $TemporaryMetric }
    $verify={ param($snapshot) & $VerifyMetric $snapshot $TemporaryMetric }
    $rollback={ param($snapshot) foreach ($entry in @($snapshot)) { if ($SetMetric) { & $SetMetric @($entry) ([int]$entry.InterfaceMetric) } } }
    return Invoke-NrRepairTransaction -Action 'vpn-interface-metric' -Target ([string]$InterfaceIndex) -Root $Root -Snapshot $GetMetric -Apply $apply -Verify $verify -Rollback $rollback
}

function Invoke-NrWinDivertServiceRepair {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ServiceName,
        [string]$Root,
        [scriptblock]$GetServiceState,
        [scriptblock]$StopServiceAction,
        [scriptblock]$RestoreServiceAction,
        [scriptblock]$VerifyService
    )
    if (-not $GetServiceState) { $GetServiceState={ $service=Get-CimInstance Win32_Service -Filter ("Name='"+$ServiceName.Replace("'","''")+"'") -ErrorAction Stop; [pscustomobject]@{ Name=$service.Name; State=$service.State; StartMode=$service.StartMode } } }
    if (-not $StopServiceAction) { $StopServiceAction={ param($snapshot) Stop-Service -Name $ServiceName -Force -ErrorAction Stop; Set-Service -Name $ServiceName -StartupType Manual -ErrorAction Stop } }
    if (-not $RestoreServiceAction) { $RestoreServiceAction={ param($snapshot) $startup=switch -Regex ([string]$snapshot.StartMode) { '^Auto' {'Automatic'} '^Disabled' {'Disabled'} default {'Manual'} }; Set-Service -Name $ServiceName -StartupType $startup -ErrorAction Stop; if ([string]$snapshot.State -match '(?i)running') { Start-Service -Name $ServiceName -ErrorAction Stop } } }
    if (-not $VerifyService) { $VerifyService={ param($snapshot) return ((Get-Service -Name $ServiceName -ErrorAction Stop).Status -ne 'Running') } }
    return Invoke-NrRepairTransaction -Action 'windivert-stop-extra-service' -Target $ServiceName -Root $Root -Snapshot $GetServiceState -Apply $StopServiceAction -Verify $VerifyService -Rollback $RestoreServiceAction
}

function Invoke-NrDnsResetRepair {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$InterfaceAlias,
        [string]$Root,
        [scriptblock]$GetDnsState,
        [scriptblock]$ResetDns,
        [scriptblock]$RestoreDns,
        [scriptblock]$VerifyDns
    )
    if (-not $GetDnsState) { $GetDnsState={ @(Get-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ErrorAction Stop | ForEach-Object { [pscustomobject]@{ AddressFamily=[string]$_.AddressFamily; ServerAddresses=@($_.ServerAddresses) } }) } }
    if (-not $ResetDns) { $ResetDns={ param($snapshot) Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ResetServerAddresses -ErrorAction Stop; Clear-DnsClientCache -ErrorAction SilentlyContinue } }
    if (-not $RestoreDns) { $RestoreDns={ param($snapshot) $addresses=@($snapshot | ForEach-Object { @($_.ServerAddresses) } | Where-Object { $_ }); if ($addresses.Count -gt 0) { Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ServerAddresses $addresses -ErrorAction Stop } else { Set-DnsClientServerAddress -InterfaceAlias $InterfaceAlias -ResetServerAddresses -ErrorAction Stop } } }
    if (-not $VerifyDns) { $VerifyDns={ param($snapshot) try { Resolve-DnsName -Name 'github.com' -DnsOnly -ErrorAction Stop | Out-Null; return $true } catch { return $false } } }
    return Invoke-NrRepairTransaction -Action 'dns-reset' -Target $InterfaceAlias -Root $Root -Snapshot $GetDnsState -Apply $ResetDns -Verify $VerifyDns -Rollback $RestoreDns
}

function Invoke-NrDefenderExclusionRepair {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$InstallRoot,
        [string]$Root,
        [scriptblock]$GetExclusions,
        [scriptblock]$AddExclusion,
        [scriptblock]$RemoveExclusion,
        [scriptblock]$VerifyExclusion
    )
    $normalized=[IO.Path]::GetFullPath($InstallRoot).TrimEnd('\','/')
    if (-not $GetExclusions) { $GetExclusions={ @((Get-MpPreference -ErrorAction Stop).ExclusionPath) } }
    if (-not $AddExclusion) { $AddExclusion={ param($snapshot) if ($normalized -notin @($snapshot)) { Add-MpPreference -ExclusionPath $normalized -ErrorAction Stop } } }
    if (-not $RemoveExclusion) { $RemoveExclusion={ param($snapshot) if ($normalized -notin @($snapshot)) { Remove-MpPreference -ExclusionPath $normalized -ErrorAction Stop } } }
    if (-not $VerifyExclusion) { $VerifyExclusion={ param($snapshot) return ($normalized -in @((Get-MpPreference -ErrorAction Stop).ExclusionPath)) } }
    return Invoke-NrRepairTransaction -Action 'defender-path-exclusion' -Target $normalized -Root $Root -Snapshot $GetExclusions -Apply $AddExclusion -Verify $VerifyExclusion -Rollback $RemoveExclusion
}

function Show-NrRepairWizard {
    [CmdletBinding()]
    param([string]$Root)
    $rootPath=Get-NrRepairRoot -Root $Root
    $findings=@(Get-NrEvidenceConflictReport)
    if (-not (Get-Command Invoke-NrMenu -ErrorAction SilentlyContinue)) { return $findings }
    $items=@($findings | ForEach-Object {
        [pscustomobject]@{
            Id=[string]$_.id
            Label=('[{0}] {1}' -f $_.category,$_.product)
            Section='CONFLICT & REPAIR'
            Status=([string]$_.compatibility).ToUpperInvariant()
        }
    })
    if ($items.Count -eq 0) {
        if (Get-Command Show-NrMessage -ErrorAction SilentlyContinue) { Show-NrMessage -Title 'Conflict & Repair' -Message 'No evidence-based conflicts were detected.' -Color Green }
        return @()
    }
    $selection=Invoke-NrMenu -Title 'Conflict & Repair' -Items $items -AllowEscape
    if (-not $selection) { return $findings }
    $finding=$findings | Where-Object id -eq $selection | Select-Object -First 1
    if (-not $finding.reversible -or [string]::IsNullOrWhiteSpace([string]$finding.repairAction)) {
        if (Get-Command Show-NrMessage -ErrorAction SilentlyContinue) { Show-NrMessage -Title 'Conflict & Repair' -Message ('No automatic reversible repair is available. Evidence: '+(@($finding.evidence) -join '; ')) -Color Yellow }
        return $finding
    }
    if (Get-Command Confirm-NrY -ErrorAction SilentlyContinue) {
        if (-not (Confirm-NrY -Message ('Apply reversible repair '+$finding.repairAction+'? Press Y to confirm.'))) { return $finding }
    }
    switch ([string]$finding.repairAction) {
        'disable-specific-block-rule' { return Invoke-NrFirewallRuleRepair -RuleName (($finding.id -replace '^firewall-block-','')) -Root $rootPath }
        'increase-vpn-interface-metric' {
            $index=[int](($finding.evidence | Where-Object { $_ -like 'InterfaceIndex=*' } | Select-Object -First 1) -replace '^InterfaceIndex=','')
            return Invoke-NrVpnMetricRepair -InterfaceIndex $index -Root $rootPath
        }
        'stop-extra-windivert-service' { return Invoke-NrWinDivertServiceRepair -ServiceName ([string]$finding.product) -Root $rootPath }
        'defender-path-exclusion' { return Invoke-NrDefenderExclusionRepair -InstallRoot $rootPath -Root $rootPath }
        default { return $finding }
    }
}
