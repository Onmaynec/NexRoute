Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Get-NrAddressFamilyRoot {
    param([string]$Root)
    if ($Root) { return [IO.Path]::GetFullPath($Root).TrimEnd('\','/') }
    if (Get-Variable -Name NrRoot -Scope Script -ErrorAction SilentlyContinue) { return [IO.Path]::GetFullPath([string]$script:NrRoot).TrimEnd('\','/') }
    return [IO.Path]::GetFullPath((Get-Location).Path).TrimEnd('\','/')
}

function Get-NrWinwsAddressFamilyCapability {
    [CmdletBinding()]
    param(
        [string]$WinwsPath,
        [string]$HelpText,
        [scriptblock]$Runner,
        [string]$Root
    )
    $rootPath=Get-NrAddressFamilyRoot -Root $Root
    if (-not $WinwsPath) { $WinwsPath=Join-Path $rootPath 'bin/winws.exe' }
    $resolvedPath=[IO.Path]::GetFullPath($WinwsPath)
    $errorMessage=$null
    if ($null -eq $HelpText) {
        if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
            return [pscustomobject][ordered]@{
                state='unsupported'; executable=$resolvedPath; helpSha256=$null
                supportsFilterL3=$false; supportsIpv4=$false; supportsIpv6=$false
                reason='winws.exe is missing.'; observedHelp=$null
            }
        }
        try {
            $output=if ($Runner) { @(& $Runner $resolvedPath @('--help')) } else { @(& $resolvedPath --help 2>&1) }
            $HelpText=($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
        } catch {
            $errorMessage=$_.Exception.Message
            $HelpText=''
        }
    }
    $normalized=[string]$HelpText
    $supportsFilterL3=$normalized -match '(?i)--filter-l3(?:=|\s)'
    $supportsIpv4=$supportsFilterL3 -and $normalized -match '(?i)(?:^|[^a-z0-9])ipv4(?:[^a-z0-9]|$)'
    $supportsIpv6=$supportsFilterL3 -and $normalized -match '(?i)(?:^|[^a-z0-9])ipv6(?:[^a-z0-9]|$)'
    $sha=$null
    if ($normalized.Length -gt 0) {
        $algorithm=[Security.Cryptography.SHA256]::Create()
        try { $sha=[BitConverter]::ToString($algorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes($normalized))).Replace('-','').ToLowerInvariant() }
        finally { $algorithm.Dispose() }
    }
    $state=if ($supportsIpv4 -and $supportsIpv6) { 'supported' } elseif ($supportsIpv4) { 'ipv4-only' } else { 'unsupported' }
    $reason=if ($state -eq 'supported') { $null } elseif ($errorMessage) { $errorMessage } elseif (-not $supportsFilterL3) { 'Pinned winws help does not advertise --filter-l3.' } elseif (-not $supportsIpv6) { 'Pinned winws help does not advertise the ipv6 layer-3 selector.' } else { 'Address-family capability is incomplete.' }
    return [pscustomobject][ordered]@{
        state=$state; executable=$resolvedPath; helpSha256=$sha
        supportsFilterL3=$supportsFilterL3; supportsIpv4=$supportsIpv4; supportsIpv6=$supportsIpv6
        reason=$reason; observedHelp=$normalized
    }
}

function Get-NrIpSetEntryFamily {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Entry)
    $value=$Entry.Trim()
    if (-not $value -or $value.StartsWith('#')) { return $null }
    $addressText=($value -split '/',2)[0].Trim()
    $address=$null
    if (-not [Net.IPAddress]::TryParse($addressText,[ref]$address)) { return 'invalid' }
    if ($address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork) { return 'ipv4' }
    if ($address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetworkV6) { return 'ipv6' }
    return 'invalid'
}

function Read-NrIpSetAddressFamilies {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Service ipset is missing: $Path" }
    $ipv4=New-Object 'System.Collections.Generic.List[string]'
    $ipv6=New-Object 'System.Collections.Generic.List[string]'
    $invalid=New-Object 'System.Collections.Generic.List[string]'
    foreach ($line in @(Get-Content -LiteralPath $Path -Encoding UTF8)) {
        $entry=([string]$line).Trim()
        if (-not $entry -or $entry.StartsWith('#')) { continue }
        switch (Get-NrIpSetEntryFamily -Entry $entry) {
            'ipv4' { if (-not $ipv4.Contains($entry)) { $ipv4.Add($entry) } }
            'ipv6' { if (-not $ipv6.Contains($entry)) { $ipv6.Add($entry) } }
            default { $invalid.Add($entry) }
        }
    }
    return [pscustomobject][ordered]@{
        source=[IO.Path]::GetFullPath($Path)
        ipv4=[string[]]$ipv4.ToArray()
        ipv6=[string[]]$ipv6.ToArray()
        invalid=[string[]]$invalid.ToArray()
    }
}

function Write-NrFamilyIpset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$ServiceId,
        [Parameter(Mandatory)][ValidateSet('ipv4','ipv6')][string]$Family,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Entries
    )
    $directory=Join-Path (Get-NrAddressFamilyRoot -Root $Root) '.service/runtime/ipsets'
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $safeId=ConvertTo-NrWorkerId $ServiceId
    $path=Join-Path $directory ('ipset-service-'+$safeId+'-'+$Family+'.txt')
    $temporary=$path+'.tmp-'+[guid]::NewGuid().ToString('N')
    $header='# NexRoute 0.6.0 generated '+$Family+' service ipset. Do not edit.'
    $content=@($header)+@($Entries | Sort-Object -Unique)
    [IO.File]::WriteAllLines($temporary,[string[]]$content,[Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $path -Force
    return [IO.Path]::GetFullPath($path)
}

function Resolve-NrAddressFamilyMode {
    [CmdletBinding()]
    param(
        [ValidateSet('Auto','IPv4','IPv6','DualStack')][string]$Mode='Auto',
        [Parameter(Mandatory)]$Capability,
        [bool]$HasIpv6Data
    )
    if ($Mode -eq 'Auto') {
        if ([bool]$Capability.supportsIpv6 -and $HasIpv6Data) { return 'DualStack' }
        return 'IPv4'
    }
    return $Mode
}

function ConvertTo-NrFamilyStrategyArguments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][ValidateSet('ipv4','ipv6')][string]$Family,
        [Parameter(Mandatory)][string]$OriginalIpset,
        [string]$FamilyIpset,
        [bool]$HasFamilyIpset
    )
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
            $existing=$argument.Substring('--ipset='.Length)
            if ([IO.Path]::GetFullPath($existing) -eq [IO.Path]::GetFullPath($OriginalIpset)) {
                if ($HasFamilyIpset) { $result.Add('--ipset='+$FamilyIpset) }
                continue
            }
        }
        $result.Add($argument)
    }
    return [string[]]$result.ToArray()
}

function New-NrAddressFamilyWorkerConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$BaseConfiguration,
        [ValidateSet('Auto','IPv4','IPv6','DualStack')][string]$Mode='Auto',
        [string]$Root,
        $Capability
    )
    $rootPath=Get-NrAddressFamilyRoot -Root $Root
    if (-not $Capability) { $Capability=Get-NrWinwsAddressFamilyCapability -Root $rootPath }
    $familyData=@{}
    $hasIpv6=$false
    foreach ($service in @($BaseConfiguration.services)) {
        $source=[string]$service.filterFiles.ipset
        $families=Read-NrIpSetAddressFamilies -Path $source
        $familyData[[string]$service.id]=$families
        if (@($families.ipv6).Count -gt 0) { $hasIpv6=$true }
    }
    $resolvedMode=Resolve-NrAddressFamilyMode -Mode $Mode -Capability $Capability -HasIpv6Data $hasIpv6
    $requestedFamilies=switch ($resolvedMode) {
        'IPv4' { @('ipv4') }
        'IPv6' { @('ipv6') }
        'DualStack' { @('ipv4','ipv6') }
        default { throw "Unsupported address-family mode: $resolvedMode" }
    }
    $services=New-Object 'System.Collections.Generic.List[object]'
    $limitations=New-Object 'System.Collections.Generic.List[object]'
    foreach ($service in @($BaseConfiguration.services)) {
        $sourceFamilyData=$familyData[[string]$service.id]
        foreach ($family in $requestedFamilies) {
            $capabilityOk=if ($family -eq 'ipv6') { [bool]$Capability.supportsIpv6 } else { [bool]$Capability.supportsIpv4 }
            if (-not $capabilityOk) {
                $limitations.Add([pscustomobject]@{ serviceId=[string]$service.id; family=$family; code='upstream-capability-missing'; message=[string]$Capability.reason })
                continue
            }
            $entries=[string[]]@(if ($family -eq 'ipv6') { $sourceFamilyData.ipv6 } else { $sourceFamilyData.ipv4 })
            $hostEntries=[int]$service.filterFiles.hostEntries
            if ($hostEntries -eq 0 -and $entries.Count -eq 0) {
                $limitations.Add([pscustomobject]@{ serviceId=[string]$service.id; family=$family; code='no-family-targets'; message='The service has no hostname or address targets for this family.' })
                continue
            }
            $familyIpset=Write-NrFamilyIpset -Root $rootPath -ServiceId ([string]$service.id) -Family $family -Entries $entries
            $strategies=New-Object 'System.Collections.Generic.List[object]'
            foreach ($strategy in @($service.strategies)) {
                $arguments=ConvertTo-NrFamilyStrategyArguments -Arguments ([string[]]$strategy.arguments) -Family $family -OriginalIpset ([string]$service.filterFiles.ipset) -FamilyIpset $familyIpset -HasFamilyIpset ($entries.Count -gt 0)
                if ($arguments -notcontains ('--filter-l3='+$family)) { throw "Generated '$family' strategy has no layer-3 filter." }
                foreach ($argument in $arguments) {
                    if ($argument -match '^--ipset=' -and $argument -notmatch [regex]::Escape($familyIpset)) {
                        throw "Generated '$family' strategy still references an unsplit service ipset."
                    }
                }
                $strategies.Add([ordered]@{
                    name=[string]$strategy.name
                    executable=[string]$strategy.executable
                    arguments=[string[]]$arguments
                    sourceFile=[string]$strategy.sourceFile
                    addressFamily=$family
                })
            }
            $workerId=(ConvertTo-NrWorkerId ([string]$service.id))+'-'+$family
            $scopeTokens=New-Object 'System.Collections.Generic.List[string]'
            $scopeTokens.Add('scope:'+$family+'|hostlist:'+([string]$service.filterFiles.hostlist).ToLowerInvariant())
            if ($entries.Count -gt 0) { $scopeTokens.Add('scope:'+$family+'|ipset:'+([string]$familyIpset).ToLowerInvariant()) }
            $services.Add([ordered]@{
                id=$workerId
                baseServiceId=[string]$service.id
                addressFamily=$family
                enabled=$true
                filterTokens=[string[]]$scopeTokens.ToArray()
                filterFiles=[ordered]@{
                    hostlist=[string]$service.filterFiles.hostlist
                    ipset=$familyIpset
                    hostEntries=$hostEntries
                    ipEntries=$entries.Count
                    sourceIpset=[string]$service.filterFiles.ipset
                }
                probe=[ordered]@{
                    uri=[string]$service.probe.uri
                    timeoutSeconds=[int]$service.probe.timeoutSeconds
                    addressFamily=$family
                }
                strategies=[object[]]$strategies.ToArray()
            })
        }
    }
    $plans=New-Object 'System.Collections.Generic.List[object]'
    foreach ($service in $services) {
        $strategy=$service.strategies[0]
        $plans.Add([pscustomobject]@{
            serviceId=[string]$service.id
            filterTokens=[string[]]$service.filterTokens
            strategy=[string]$strategy.name
            executable=[string]$strategy.executable
            arguments=[string[]]$strategy.arguments
        })
    }
    if ($plans.Count -gt 0) { Assert-NrWorkerFilterIsolation -Plans ([object[]]$plans.ToArray()) | Out-Null }
    $state=if ($services.Count -eq 0) { 'unsupported' } elseif ($limitations.Count -gt 0) { 'partial' } else { 'supported' }
    return [pscustomobject][ordered]@{
        schemaVersion=2
        generatedUtc=[DateTime]::UtcNow.ToString('o')
        generator='NexRoute 0.6.0 address-family runtime'
        requestedMode=$Mode
        resolvedMode=$resolvedMode
        state=$state
        capability=$Capability
        limitations=[object[]]$limitations.ToArray()
        services=[object[]]$services.ToArray()
    }
}

function Write-NrAddressFamilyCapabilityReport {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Configuration,[string]$Root)
    $rootPath=Get-NrAddressFamilyRoot -Root $Root
    $path=Join-Path $rootPath '.service/ipv6-capability.json'
    $temporary=$path+'.tmp-'+[guid]::NewGuid().ToString('N')
    [IO.File]::WriteAllText($temporary,($Configuration | ConvertTo-Json -Depth 30)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $path -Force
    return $path
}

function Get-NrConfiguredAddressFamilyMode {
    if (Get-Variable -Name NrState -Scope Script -ErrorAction SilentlyContinue) {
        $property=$script:NrState.PSObject.Properties['addressFamilyMode']
        if ($property -and [string]$property.Value -in @('Auto','IPv4','IPv6','DualStack')) { return [string]$property.Value }
    }
    return 'Auto'
}

function Show-NrIpv6RuntimeStatus {
    [CmdletBinding()]
    param([string]$Root)
    $capability=Get-NrWinwsAddressFamilyCapability -Root (Get-NrAddressFamilyRoot -Root $Root)
    $message=if ($capability.state -eq 'supported') {
        'Pinned winws advertises IPv4 and IPv6 layer-3 filters. Dual-stack workers are available.'
    } else {
        'IPv6 bypass is unsupported by the current pinned runtime: '+[string]$capability.reason
    }
    if (Get-Command Show-NrMessage -ErrorAction SilentlyContinue) {
        Show-NrMessage -Title 'IPv6 Runtime' -Message $message -Color $(if ($capability.state -eq 'supported') { 'Green' } else { 'Yellow' })
    }
    return $capability
}

if (-not (Get-Variable -Name NrApplyPerServiceStrategiesV1 -Scope Script -ErrorAction SilentlyContinue)) {
    $script:NrApplyPerServiceStrategiesV1=${function:Apply-NrPerServiceStrategies}
}

function Apply-NrPerServiceStrategies {
    [CmdletBinding()]
    param()
    $mapping=$script:NrState.perServiceStrategies
    if ($null -eq $mapping -or (Get-NrPerServiceMappingEntries -Mapping $mapping).Count -eq 0) {
        throw 'Select at least one service strategy before applying the worker runtime.'
    }
    $baseConfiguration=New-NrServiceWorkerConfiguration -Mapping $mapping
    $mode=Get-NrConfiguredAddressFamilyMode
    $configuration=New-NrAddressFamilyWorkerConfiguration -BaseConfiguration $baseConfiguration -Mode $mode -Root $script:NrRoot
    $reportPath=Write-NrAddressFamilyCapabilityReport -Configuration $configuration -Root $script:NrRoot
    if ($configuration.state -eq 'unsupported' -or @($configuration.services).Count -eq 0) {
        $reasons=@($configuration.limitations | ForEach-Object { $_.serviceId+':'+$_.family+' '+$_.message }) -join '; '
        throw "Address-family worker runtime is unsupported. $reasons Report: $reportPath"
    }
    $configurationPath=Save-NrServiceWorkerConfiguration -Configuration $configuration
    Stop-NrStrategyRuntime
    Stop-NrPerServiceWorkerRuntime
    foreach ($existing in @(Get-Service -Name 'NexRoute_*' -ErrorAction SilentlyContinue)) {
        try { Stop-Service -Name $existing.Name -Force -ErrorAction SilentlyContinue } catch { }
        try { & sc.exe delete $existing.Name | Out-Null } catch { }
    }
    $supervisorPid=Start-NrPerServiceWorkerRuntime -ConfigurationPath $configurationPath
    foreach ($service in $configuration.services) {
        Save-NrStrategyHistory -Action 'per-service-family-worker-start' -Strategy ([string]$service.strategies[0].name) -Details @{
            service=[string]$service.baseServiceId
            worker=[string]$service.id
            addressFamily=[string]$service.addressFamily
            supervisorPid=$supervisorPid
            fallbackCount=(@($service.strategies).Count-1)
        }
    }
    Send-NrNotification -Title 'NexRoute' -Message ('Started '+@($configuration.services).Count+' isolated '+$configuration.resolvedMode+' workers.') -Level Info
    return [pscustomobject]@{
        configurationPath=$configurationPath
        capabilityReport=$reportPath
        state=$configuration.state
        resolvedMode=$configuration.resolvedMode
        serviceCount=@($configuration.services).Count
        supervisorPid=$supervisorPid
    }
}
