# Safe, allowlisted diagnostics shared by the Diagnostics UI, ZIP and clipboard.
# No raw network identity, adapter IP, VPN name, logs or user-list contents leave the machine.
Set-StrictMode -Version Latest

function Get-NrDiagnosticField071 {
    param($Object,[Parameter(Mandatory)][string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $null
    }
    $property=$Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $null
}

function Get-NrLabHealth071 {
    $run=$null
    try {
        if (Get-Command Get-NrLatestLabRun -ErrorAction SilentlyContinue) {
            $run=Get-NrLatestLabRun
        }
    } catch { return [pscustomobject]@{ status='unreadable'; eligible=0; inconclusive=0; scoringModel='unknown' } }

    if (-not $run) {
        return [pscustomobject]@{ status='not-run'; eligible=0; inconclusive=0; scoringModel='unknown' }
    }
    $results=Get-NrDiagnosticField071 -Object $run -Name 'results'
    if ($null -eq $results -or $results -isnot [array]) {
        return [pscustomobject]@{ status='unreadable'; eligible=0; inconclusive=0; scoringModel='unknown' }
    }
    $eligible=@($results | Where-Object {
        (Get-NrDiagnosticField071 -Object $_ -Name 'rankingState') -eq 'eligible'
    }).Count
    $inconclusive=@($results | Where-Object {
        (Get-NrDiagnosticField071 -Object $_ -Name 'rankingState') -eq 'inconclusive'
    }).Count
    $model=[string](Get-NrDiagnosticField071 -Object $run -Name 'measurementModel')
    if ($model -notin @('https-primary-071','critical-services-stability-v1')) { $model='legacy-or-unknown' }
    return [pscustomobject]@{
        status='available'
        eligible=[int]$eligible
        inconclusive=[int]$inconclusive
        scoringModel=$model
    }
}

function Get-NrDiagnosticFindings071 {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Report)
    $nx=Get-NrDiagnosticField071 $Report 'nexroute'
    $win=Get-NrDiagnosticField071 $Report 'windows'
    $findings=New-Object 'System.Collections.Generic.List[object]'
    if (-not [bool](Get-NrDiagnosticField071 $win 'elevated')) {
        $findings.Add([pscustomobject]@{ code='NR-ADMIN-001'; severity='warning'; message='NexRoute is not elevated.'; nextStep='Run the control node as administrator before installing a service.' })
    }
    $winws=[bool](Get-NrDiagnosticField071 $nx 'winwsRunning')
    $driver=[bool](Get-NrDiagnosticField071 $nx 'winDivertRunning')
    if ($winws -and -not $driver) {
        $findings.Add([pscustomobject]@{ code='NR-WD-003'; severity='warning'; message='winws is active, but WinDivert service was not detected.'; nextStep='Check WinDivert status, then inspect logs locally.' })
    }
    if (-not $winws -and -not [bool](Get-NrDiagnosticField071 $nx 'serviceRunning')) {
        $findings.Add([pscustomobject]@{ code='NR-RUN-002'; severity='info'; message='No running DPI engine was detected.'; nextStep='This is expected when bypass is disabled; otherwise check installation.' })
    }
    $lists=@(Get-NrDiagnosticField071 $Report 'userLists' | Where-Object { $null -ne $_ })
    if (@($lists | Where-Object { -not [bool](Get-NrDiagnosticField071 $_ 'valid') }).Count -gt 0) {
        $findings.Add([pscustomobject]@{ code='NR-LIST-004'; severity='warning'; message='At least one configured user list is missing or invalid.'; nextStep='Open Diagnostics / List integrity and correct the local file.' })
    }
    $conflicts=@(Get-NrDiagnosticField071 $Report 'conflicts' | Where-Object { $null -ne $_ })
    if (@($conflicts | Where-Object { (Get-NrDiagnosticField071 $_ 'severity') -eq 'warning' }).Count -gt 0) {
        $findings.Add([pscustomobject]@{ code='NR-FILTER-005'; severity='info'; message='Potential additional network filters were detected.'; nextStep='Review Conflicts. Detection alone does not prove a software conflict.' })
    }
    if ($findings.Count -eq 0) {
        $findings.Add([pscustomobject]@{ code='NR-DIAG-000'; severity='info'; message='No issues were identified by the available local checks.'; nextStep='This does not prove ISP-specific connectivity or bypass.' })
    }
    return @($findings.ToArray())
}

function ConvertTo-NrSafeDiagnosticReport071 {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Report,$LabHealth)
    if (-not $LabHealth) { $LabHealth=Get-NrLabHealth071 }
    $nx=Get-NrDiagnosticField071 $Report 'nexroute'
    $win=Get-NrDiagnosticField071 $Report 'windows'
    $list=@(Get-NrDiagnosticField071 $Report 'userLists' | Where-Object { $null -ne $_ })
    $conflicts=@(Get-NrDiagnosticField071 $Report 'conflicts' | Where-Object { $null -ne $_ })
    $adapters=@(Get-NrDiagnosticField071 $Report 'adapters' | Where-Object { $null -ne $_ })
    $dns=@(Get-NrDiagnosticField071 $Report 'dns' | Where-Object { $null -ne $_ })
    $warnings=@($conflicts | Where-Object { (Get-NrDiagnosticField071 $_ 'severity') -eq 'warning' })
    $status=if (@(Get-NrDiagnosticFindings071 -Report $Report | Where-Object { $_.severity -eq 'warning' }).Count -gt 0) { 'attention' } else { 'informational' }
    $version=[string](Get-NrDiagnosticField071 $nx 'version')
    if ($version -notmatch '^[0-9]{1,3}[.][0-9]{1,3}[.][0-9]{1,3}$') { $version='unknown' }

    # No free-form source fields. All names, addresses, credentials, paths,
    # DNS servers, SSIDs, source URIs and raw diagnostic messages are excluded.
    return [ordered]@{
        schemaVersion=4
        exportType='privacy-minimised'
        privacy=[ordered]@{
            rawLogsIncluded=$false
            rawNetworkIdentifiersIncluded=$false
            rawUserListsIncluded=$false
            rawProbeUrlsIncluded=$false
        }
        createdUtc=[DateTime]::UtcNow.ToString('o')
        nexroute=[ordered]@{
            version=$version
            engineRunning=[bool](Get-NrDiagnosticField071 $nx 'winwsRunning')
            driverRunning=[bool](Get-NrDiagnosticField071 $nx 'winDivertRunning')
            serviceRunning=[bool](Get-NrDiagnosticField071 $nx 'serviceRunning')
            safeMode=[bool](Get-NrDiagnosticField071 $nx 'safeMode')
            monitorEnabled=[bool](Get-NrDiagnosticField071 $nx 'monitorEnabled')
        }
        environment=[ordered]@{
            elevated=[bool](Get-NrDiagnosticField071 $win 'elevated')
            # OS version/build are safe identifiers; do not export computer names.
            osVersion=$(if([string](Get-NrDiagnosticField071 $win 'version') -match '^[0-9.]{1,24}$'){[string](Get-NrDiagnosticField071 $win 'version')}else{'unknown'})
            powershellVersion=$(if([string](Get-NrDiagnosticField071 $win 'powershell') -match '^[0-9.]{1,24}$'){[string](Get-NrDiagnosticField071 $win 'powershell')}else{'unknown'})
        }
        networkCounts=[ordered]@{ adapters=$adapters.Count; dnsConfigs=$dns.Count; potentialFilterWarnings=$warnings.Count }
        listIntegrity=[ordered]@{
            inspected=$list.Count
            invalid=@($list | Where-Object { -not [bool](Get-NrDiagnosticField071 $_ 'valid') }).Count
            changed=@($list | Where-Object { [bool](Get-NrDiagnosticField071 $_ 'changed') }).Count
        }
        strategyLab=[ordered]@{
            status=[string](Get-NrDiagnosticField071 $LabHealth 'status')
            eligible=[int](Get-NrDiagnosticField071 $LabHealth 'eligible')
            inconclusive=[int](Get-NrDiagnosticField071 $LabHealth 'inconclusive')
            scoringModel=[string](Get-NrDiagnosticField071 $LabHealth 'scoringModel')
        }
        overallStatus=$status
        findings=@(Get-NrDiagnosticFindings071 -Report $Report)
    }
}

function Show-NrDiagnosticHealth071 {
    $source=Get-NrDiagnosticReport
    $report=ConvertTo-NrSafeDiagnosticReport071 -Report $source
    Write-NrHeader -Title 'DIAGNOSTICS / HEALTH'
    Write-Host ('  Status: ' + $report.overallStatus) -ForegroundColor $(if($report.overallStatus -eq 'attention'){'Yellow'}else{'Green'})
    Write-Host ('  Strategy Lab: {0} / eligible={1} / inconclusive={2}' -f $report.strategyLab.status,$report.strategyLab.eligible,$report.strategyLab.inconclusive) -ForegroundColor Gray
    Write-Host ('  Network inventory: {0} adapters / {1} DNS configurations' -f $report.networkCounts.adapters,$report.networkCounts.dnsConfigs) -ForegroundColor DarkGray
    Write-Host ''
    foreach ($finding in @($report.findings)) {
        Write-Host ('  [{0}] {1}' -f $finding.code,$finding.message) -ForegroundColor $(if($finding.severity -eq 'warning'){'Yellow'}else{'Gray'})
        Write-Host ('      ' + $finding.nextStep) -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host '  This report cannot verify real ISP bypass or voice call quality.' -ForegroundColor Yellow
    Wait-NrKey
}
