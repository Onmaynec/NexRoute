# Internal NexRoute Service Matrix module. Dot-sourced by nexroute-services.ps1.

function Restart-InstalledStrategy {
    $service = Get-Service -Name 'zapret' -ErrorAction SilentlyContinue
    if (-not $service) { return [pscustomobject]@{ Installed = $false; Restarted = $false; Message = 'zapret service is not installed.' } }
    $strategy = $null
    try { $strategy = [string](Get-ItemPropertyValue -Path 'HKLM:\System\CurrentControlSet\Services\zapret' -Name 'zapret-discord-youtube' -ErrorAction Stop) } catch { }
    if ([string]::IsNullOrWhiteSpace($strategy)) {
        Restart-Service -Name 'zapret' -Force -ErrorAction Stop
        return [pscustomobject]@{ Installed = $true; Restarted = $true; Message = 'zapret service restarted.' }
    }
    $strategyFile = if ($strategy.EndsWith('.bat', [StringComparison]::OrdinalIgnoreCase)) { $strategy } else { "$strategy.bat" }
    $serviceBat = Join-Path $Root 'service.bat'
    if (-not (Test-Path -LiteralPath $serviceBat -PathType Leaf)) { throw 'service.bat was not found for matrix refresh.' }
    $argumentLine = '/d /c ""{0}" refresh_matrix "{1}""' -f $serviceBat, $strategyFile
    $process = Start-Process -FilePath $env:ComSpec -ArgumentList $argumentLine -WorkingDirectory $Root -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "Installed strategy refresh failed with exit code $($process.ExitCode)." }
    return [pscustomobject]@{ Installed = $true; Restarted = $true; Message = "zapret service reinstalled from $strategyFile." }
}

function Get-FileSha256Safe {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() } catch { return $null }
}

function Export-NexRouteDiagnostics {
    param([Parameter(Mandatory)][array]$Definitions, [Parameter(Mandatory)]$State)
    $version = if (Test-Path -LiteralPath $versionPath -PathType Leaf) { (Get-Content -LiteralPath $versionPath -Raw).Trim() } else { 'unknown' }
    $enabledIds = [string[]]@($Definitions | Where-Object { [bool]$State[$_.id] } | ForEach-Object { [string]$_.id })
    $sourceStatuses = [object[]]@()
    if (Test-Path -LiteralPath $sourceStatusPath -PathType Leaf) {
        $loadedStatuses = Read-JsonFile -Path $sourceStatusPath
        if ($null -ne $loadedStatuses) { $sourceStatuses = [object[]]@($loadedStatuses) }
    }
    $zapret = $null
    if (Get-Command Get-Service -ErrorAction SilentlyContinue) {
        try { $zapret = Get-Service -Name 'zapret' -ErrorAction SilentlyContinue } catch { }
    }

    $report = [ordered]@{
        generatedAtUtc = [DateTime]::UtcNow.ToString('o')
        privacy = 'No domain-list contents, IP values, usernames, or paths outside the NexRoute root are included.'
        nexRouteVersion = $version
        serviceSchemaVersion = 2
        stateSchemaVersion = $stateSchemaVersion
        enabledServiceCount = $enabledIds.Count
        enabledServiceIds = $enabledIds
        sourceStatuses = $sourceStatuses
        runtime = [ordered]@{
            serviceRuntimeSha256 = Get-FileSha256Safe -Path $runtimePath
            enabledDomainCount = if (Test-Path -LiteralPath $enabledListPath) { @(Get-Content -LiteralPath $enabledListPath).Count } else { 0 }
            serviceIpCount = if (Test-Path -LiteralPath $serviceIpsetPath) { @(Get-Content -LiteralPath $serviceIpsetPath).Count } else { 0 }
        }
        environment = [ordered]@{
            osVersion = [Environment]::OSVersion.VersionString
            is64BitOperatingSystem = [Environment]::Is64BitOperatingSystem
            powerShellVersion = $PSVersionTable.PSVersion.ToString()
            zapretInstalled = ($null -ne $zapret)
            zapretStatus = if ($zapret) { [string]$zapret.Status } else { 'NotInstalled' }
        }
    }

    if ([string]::IsNullOrWhiteSpace($DiagnosticsPath)) {
        $DiagnosticsPath = Join-Path $Root ("NexRoute-Diagnostics-{0}.json" -f [DateTime]::Now.ToString('yyyyMMdd-HHmmss'))
    }
    $fullPath = [System.IO.Path]::GetFullPath($DiagnosticsPath)
    Write-JsonFile -Path $fullPath -Value $report -Depth 10
    return [pscustomobject]@{ Path = $fullPath; Enabled = $enabledIds.Count; SourceStatuses = $sourceStatuses.Count }
}

function Assert-ServiceDefinitions {
    param([Parameter(Mandatory)][array]$Definitions)
    $ids = @($Definitions | ForEach-Object { [string]$_.id })
    if (($ids | Sort-Object -Unique).Count -ne $ids.Count) { throw 'services.json contains duplicate ids.' }

    foreach ($service in $Definitions) {
        if (-not $service.id -or -not $service.nameEn -or -not $service.nameRu -or -not $service.descriptionEn -or -not $service.descriptionRu) {
            throw 'A service definition is missing identity or localized description fields.'
        }
        if (([string]$service.id) -notmatch '^[a-z0-9][a-z0-9_-]*$') { throw "Service '$($service.id)' has an invalid id." }
        if (@($service.domains).Count -eq 0) { throw "Service '$($service.id)' has no domains." }
        if (@($service.testTargets).Count -lt 2) { throw "Service '$($service.id)' must define at least two real test targets." }
        if (@($service.tcpPorts).Count -eq 0 -and @($service.udpPorts).Count -eq 0) { throw "Service '$($service.id)' has no network ports." }

        $portsToValidate = @($service.tcpPorts) + @($service.udpPorts)
        foreach ($port in $portsToValidate) {
            if (-not (ConvertTo-ValidatedPort -Value ([string]$port))) { throw "Service '$($service.id)' has invalid port '$port'." }
        }
        foreach ($cidrValue in @($service.ipCidrs)) {
            if (-not (ConvertTo-ValidatedIpCidr -Value ([string]$cidrValue))) { throw "Service '$($service.id)' has invalid IPv4/IPv6 CIDR '$cidrValue'." }
        }
        foreach ($domainValue in @($service.domains)) {
            $domain = ([string]$domainValue).Trim()
            if ($domain -notmatch '^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$') { throw "Service '$($service.id)' has invalid domain '$domain'." }
        }
    }
}
