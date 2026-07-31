[CmdletBinding()]
param(
    [ValidateSet('Apply', 'Summary', 'Reset', 'Validate', 'TestTargets', 'Restart', 'Diagnostics')]
    [string]$Mode = 'Apply',
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [string]$DiagnosticsPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$serviceDirectory = $PSScriptRoot
$definitionPath = Join-Path $serviceDirectory 'services.json'
$statePath = Join-Path $serviceDirectory 'services-state.json'
$runtimePath = Join-Path $serviceDirectory 'services-runtime.cmd'
$sourceStatusPath = Join-Path $serviceDirectory 'ip-source-status.json'
$cacheDirectory = Join-Path $serviceDirectory 'cache\ip-sources'
$listsDirectory = Join-Path $Root 'lists'
$generalUserPath = Join-Path $listsDirectory 'list-general-user.txt'
$excludeUserPath = Join-Path $listsDirectory 'list-exclude-user.txt'
$enabledListPath = Join-Path $listsDirectory 'list-services-enabled.txt'
$serviceIpsetPath = Join-Path $listsDirectory 'ipset-services-user.txt'
$versionPath = Join-Path $serviceDirectory 'version.txt'
$stateSchemaVersion = 2
$sourceCacheMaxAgeDays = 14

$generalBegin = '# NEXROUTE-SERVICES-BEGIN'
$generalEnd = '# NEXROUTE-SERVICES-END'
$excludeBegin = '# NEXROUTE-DISABLED-SERVICES-BEGIN'
$excludeEnd = '# NEXROUTE-DISABLED-SERVICES-END'

$moduleDirectory = Join-Path $serviceDirectory 'i18n'
foreach ($moduleName in @(
    'nexroute-services-state.ps1',
    'nexroute-services-network.ps1',
    'nexroute-services-runtime.ps1',
    'nexroute-services-diagnostics.ps1'
)) {
    $modulePath = Join-Path $moduleDirectory $moduleName
    if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) { throw "NexRoute Service Matrix module is missing: $modulePath" }
    . $modulePath
}

$definitions = Get-ServiceDefinitions

switch ($Mode) {
    'Validate' {
        Assert-ServiceDefinitions -Definitions $definitions
        Write-Output "Validated $($definitions.Count) service definitions (schema v2, strict ports/CIDR)."
    }
    'Reset' {
        $state = New-DefaultState -Definitions $definitions
        Save-ServiceState -State $state
        (Apply-ServiceMatrix -Definitions $definitions -State $state) | ConvertTo-Json -Depth 6 -Compress
    }
    'Summary' {
        $stateResult = Get-ServiceStateResult -Definitions $definitions
        $enabled = @($definitions | Where-Object { [bool]$stateResult.State[$_.id] })
        [pscustomobject]@{
            Total = $definitions.Count
            Enabled = $enabled.Count
            EnabledIds = @($enabled | ForEach-Object { $_.id })
            TestTargets = @($enabled | ForEach-Object { @($_.testTargets).Count } | Measure-Object -Sum).Sum
            StateSchemaVersion = $stateSchemaVersion
            NeedsMigration = [bool]$stateResult.Migrated
            InvalidState = [bool]$stateResult.Invalid
        } | ConvertTo-Json -Depth 5 -Compress
    }
    'TestTargets' {
        $stateResult = Get-ServiceStateResult -Definitions $definitions
        $targets = New-Object 'System.Collections.Generic.List[object]'
        foreach ($service in $definitions) {
            if (-not [bool]$stateResult.State[$service.id]) { continue }
            foreach ($target in @($service.testTargets)) {
                if (-not $target.url) { continue }
                $targets.Add([pscustomobject]@{
                    NameEn = ('{0} / {1}' -f $service.nameEn, $target.name)
                    NameRu = ('{0} / {1}' -f $service.nameRu, $target.role)
                    Value = [string]$target.url
                    ServiceId = [string]$service.id
                    Role = [string]$target.role
                })
            }
        }
        @($targets) | ConvertTo-Json -Depth 5 -Compress
    }
    'Restart' {
        Restart-InstalledStrategy | ConvertTo-Json -Compress
    }
    'Diagnostics' {
        $stateResult = Get-ServiceStateResult -Definitions $definitions
        Export-NexRouteDiagnostics -Definitions $definitions -State $stateResult.State | ConvertTo-Json -Compress
    }
    default {
        Assert-ServiceDefinitions -Definitions $definitions
        $stateResult = Get-ServiceStateResult -Definitions $definitions
        if ($stateResult.Migrated) { Backup-ServiceState -FileName 'services-state.v1.backup.json' }
        if ($stateResult.Invalid) { Backup-ServiceState -FileName 'services-state.invalid.backup.json' }
        if (-not $stateResult.Exists -or $stateResult.Migrated -or $stateResult.Invalid) { Save-ServiceState -State $stateResult.State }
        (Apply-ServiceMatrix -Definitions $definitions -State $stateResult.State) | ConvertTo-Json -Depth 6 -Compress
    }
}
