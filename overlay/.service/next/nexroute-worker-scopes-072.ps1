Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

# Local, read-only scope analysis. No domain/IP value is included in a report:
# only service IDs and overlap counts. Sharing ports is not a collision by itself.

function Get-NrWorkerScopeEntries072 {
    [CmdletBinding()]
    param([string]$Path,[ValidateRange(1,10000)][int]$Limit=256)
    $result=New-Object 'System.Collections.Generic.List[string]'
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{available=$false;truncated=$false;entries=@()}
    }
    $count=0
    foreach($line in @(Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction Stop)) {
        $entry=([string]$line -split '[#;]',2)[0].Trim().ToLowerInvariant()
        if (-not $entry -or $entry -in @('nexroute.invalid','203.0.113.113/32')) { continue }
        $count++
        if ($result.Count -lt $Limit) { $result.Add($entry.TrimStart('^')) }
    }
    return [pscustomobject]@{available=$true;truncated=($count -gt $Limit);entries=@($result.ToArray() | Sort-Object -Unique)}
}

function ConvertTo-NrWorkerCidr072 {
    param([Parameter(Mandatory)][string]$Text)
    $split=$Text.Trim().Split('/')
    if ($split.Count -gt 2) { return $null }
    $ip=$null
    if (-not [Net.IPAddress]::TryParse($split[0],[ref]$ip)) { return $null }
    $bits=$ip.GetAddressBytes().Length*8
    $prefix=$bits
    if ($split.Count -eq 2) {
        if (-not [int]::TryParse($split[1],[ref]$prefix) -or $prefix -lt 0 -or $prefix -gt $bits) { return $null }
    }
    return [pscustomobject]@{address=$ip;bytes=@($ip.GetAddressBytes());bits=$bits;prefix=$prefix}
}

function Test-NrWorkerCidrOverlap072 {
    param([Parameter(Mandatory)][string]$Left,[Parameter(Mandatory)][string]$Right)
    $a=ConvertTo-NrWorkerCidr072 -Text $Left
    $b=ConvertTo-NrWorkerCidr072 -Text $Right
    if (-not $a -or -not $b -or $a.bits -ne $b.bits) { return $false }
    $bits=[Math]::Min($a.prefix,$b.prefix)
    for($i=0;$i -lt $a.bytes.Count -and $bits -gt 0;$i++) {
        $n=[Math]::Min($bits,8)
        $mask=(255 -shl (8-$n)) -band 255
        if (($a.bytes[$i] -band $mask) -ne ($b.bytes[$i] -band $mask)) { return $false }
        $bits-=$n
    }
    return $true
}

function Test-NrWorkerDomainOverlap072 {
    param([string]$Left,[string]$Right)
    $a=$Left.Trim().TrimEnd('.').TrimStart('^').ToLowerInvariant()
    $b=$Right.Trim().TrimEnd('.').TrimStart('^').ToLowerInvariant()
    if (-not $a -or -not $b) { return $false }
    return ($a -eq $b -or $a.EndsWith('.'+$b,[StringComparison]::Ordinal) -or $b.EndsWith('.'+$a,[StringComparison]::Ordinal))
}

function Get-NrWorkerScopeReport072 {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Configuration,[ValidateRange(1,10000)][int]$MaxEntriesPerService=256)
    $services=@($Configuration.services | Where-Object { $null -eq $_.enabled -or [bool]$_.enabled })
    $indexed=New-Object 'System.Collections.Generic.List[object]'
    $incomplete=New-Object 'System.Collections.Generic.List[string]'
    foreach($service in $services) {
        $id=ConvertTo-NrWorkerId ([string]$service.id)
        $paths=Get-NrWorkerStateValue072 -State $service -Name 'filterFiles'
        $hostPath='';$ipPath=''
        if ($paths) {
            if ($paths -is [System.Collections.IDictionary]) {
                $hostPath=[string]$paths['hostlist'];$ipPath=[string]$paths['ipset']
            } else {
                $hostPath=[string]$paths.hostlist;$ipPath=[string]$paths.ipset
            }
        }
        $hostList=Get-NrWorkerScopeEntries072 -Path $hostPath -Limit $MaxEntriesPerService
        $ipList=Get-NrWorkerScopeEntries072 -Path $ipPath -Limit $MaxEntriesPerService
        if (-not $hostList.available -or -not $ipList.available -or $hostList.truncated -or $ipList.truncated) { $incomplete.Add($id) }
        $indexed.Add([pscustomobject]@{id=$id;hosts=@($hostList.entries);ips=@($ipList.entries)})
    }

    $warnings=New-Object 'System.Collections.Generic.List[object]'
    for($i=0;$i -lt $indexed.Count;$i++) {
        for($j=$i+1;$j -lt $indexed.Count;$j++) {
            $a=$indexed[$i];$b=$indexed[$j];$domains=0;$cidrs=0
            foreach($left in $a.hosts) {
                foreach($right in $b.hosts) {
                    if (Test-NrWorkerDomainOverlap072 -Left $left -Right $right) { $domains++; break }
                }
            }
            foreach($left in $a.ips) {
                foreach($right in $b.ips) {
                    if (Test-NrWorkerCidrOverlap072 -Left $left -Right $right) { $cidrs++; break }
                }
            }
            if ($domains -gt 0 -or $cidrs -gt 0) {
                $warnings.Add([pscustomobject]@{
                    serviceA=$a.id;serviceB=$b.id;overlappingDomains=$domains;overlappingCidrs=$cidrs
                    action='Review local hostlist/ipset ownership; overlapping scopes may compete.'
                })
            }
        }
    }
    return [pscustomobject]@{
        schemaVersion=1
        servicesAnalyzed=$services.Count
        overlapPairs=$warnings.Count
        warnings=@($warnings.ToArray())
        incompleteServices=@($incomplete.ToArray())
        coverage=$(if($incomplete.Count -gt 0){'partial'}else{'complete'})
        maxEntriesPerService=$MaxEntriesPerService
    }
}

function Get-NrWorkerRuntimeReport072 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root,$Configuration)
    $workers=New-Object 'System.Collections.Generic.List[object]'
    foreach($state in @(Get-NrWorkerStates -Root $Root)) {
        $identity=if([string]$state.status -eq 'stopped') {
            [pscustomobject]@{status='not-running';reason='stopped'}
        } else { Get-NrWorkerProcessIdentity -State $state }
        $code=[string](Get-NrWorkerStateValue072 $state 'lastErrorCode' '')
        if ($code -notin @('','NR-WORKER-IDENTITY','NR-WORKER-EXITED','NR-WORKER-PROBE','NR-WORKER-RESTART','NR-WORKER-NO-FALLBACK')) { $code='NR-WORKER-OTHER' }
        $workers.Add([pscustomobject]@{
            serviceId=[string]$state.serviceId
            strategy=[string]$state.strategy
            pid=[int]$state.pid
            generation=[int]$state.generation
            status=[string]$state.status
            processState=[string]$identity.status
            processReason=[string]$identity.reason
            consecutiveFailures=[int](Get-NrWorkerStateValue072 $state 'consecutiveFailures' 0)
            consecutiveFailovers=[int](Get-NrWorkerStateValue072 $state 'consecutiveFailovers' 0)
            cooldownActive=[bool](Get-NrWorkerCooldown072 -State $state)
            lastErrorCode=$code
        })
    }
    $scope=$null
    if ($Configuration) { $scope=Get-NrWorkerScopeReport072 -Configuration $Configuration }
    $running=@($workers | Where-Object { $_.status -eq 'running' -and $_.processState -eq 'verified' }).Count
    $unhealthy=@($workers | Where-Object { $_.status -ne 'stopped' -and ($_.status -ne 'running' -or $_.processState -ne 'verified' -or $_.consecutiveFailures -gt 0) }).Count
    return [pscustomobject]@{
        schemaVersion=1
        total=$workers.Count
        running=$running
        unhealthy=$unhealthy
        stopped=@($workers | Where-Object status -eq 'stopped').Count
        workers=@($workers.ToArray())
        scopes=$scope
    }
}
