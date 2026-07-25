[CmdletBinding()]
param(
    [ValidateSet('Apply', 'Summary', 'Reset', 'Validate')]
    [string]$Mode = 'Apply',

    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$serviceDirectory = $PSScriptRoot
$definitionPath = Join-Path $serviceDirectory 'services.json'
$statePath = Join-Path $serviceDirectory 'services-state.json'
$listsDirectory = Join-Path $Root 'lists'
$generalUserPath = Join-Path $listsDirectory 'list-general-user.txt'
$excludeUserPath = Join-Path $listsDirectory 'list-exclude-user.txt'

$generalBegin = '# NEXROUTE-SERVICES-BEGIN'
$generalEnd = '# NEXROUTE-SERVICES-END'
$excludeBegin = '# NEXROUTE-DISABLED-SERVICES-BEGIN'
$excludeEnd = '# NEXROUTE-DISABLED-SERVICES-END'

function Read-JsonFile {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required JSON file was not found: $Path"
    }

    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    return $raw | ConvertFrom-Json
}

function Get-ServiceDefinitions {
    $document = Read-JsonFile -Path $definitionPath
    if (-not $document.services -or @($document.services).Count -eq 0) {
        throw 'services.json does not contain service definitions.'
    }
    return @($document.services)
}

function New-DefaultState {
    param([Parameter(Mandatory)][array]$Definitions)

    $state = [ordered]@{}
    foreach ($service in $Definitions) {
        $state[$service.id] = [bool]$service.defaultEnabled
    }
    return $state
}

function Get-ServiceState {
    param([Parameter(Mandatory)][array]$Definitions)

    $state = New-DefaultState -Definitions $Definitions
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        return $state
    }

    try {
        $saved = Read-JsonFile -Path $statePath
        foreach ($service in $Definitions) {
            $property = $saved.PSObject.Properties[$service.id]
            if ($null -ne $property) {
                $state[$service.id] = [bool]$property.Value
            }
        }
    }
    catch {
        Write-Warning "Ignoring invalid service state: $($_.Exception.Message)"
    }

    return $state
}

function Save-ServiceState {
    param([Parameter(Mandatory)]$State)

    $json = $State | ConvertTo-Json -Depth 4
    [System.IO.File]::WriteAllText($statePath, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
}

function Ensure-ListFile {
    param([Parameter(Mandatory)][string]$Path)

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        [System.IO.File]::WriteAllText($Path, "# User-managed domains`r`n", [System.Text.UTF8Encoding]::new($false))
    }
}

function Set-ManagedBlock {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$BeginMarker,
        [Parameter(Mandatory)][string]$EndMarker,
        [Parameter(Mandatory)][string[]]$Values
    )

    Ensure-ListFile -Path $Path
    $sourceLines = @(Get-Content -LiteralPath $Path -Encoding UTF8)
    $output = [System.Collections.Generic.List[string]]::new()
    $insideManagedBlock = $false

    foreach ($line in $sourceLines) {
        if ($line.Trim() -eq $BeginMarker) {
            $insideManagedBlock = $true
            continue
        }
        if ($line.Trim() -eq $EndMarker) {
            $insideManagedBlock = $false
            continue
        }
        if (-not $insideManagedBlock) {
            $output.Add($line)
        }
    }

    while ($output.Count -gt 0 -and [string]::IsNullOrWhiteSpace($output[$output.Count - 1])) {
        $output.RemoveAt($output.Count - 1)
    }

    $output.Add('')
    $output.Add($BeginMarker)
    foreach ($value in @($Values | Where-Object { $_ } | Sort-Object -Unique)) {
        $output.Add($value.ToLowerInvariant())
    }
    $output.Add($EndMarker)
    $output.Add('')

    [System.IO.File]::WriteAllLines($Path, $output, [System.Text.UTF8Encoding]::new($false))
}

function Apply-ServiceMatrix {
    param(
        [Parameter(Mandatory)][array]$Definitions,
        [Parameter(Mandatory)]$State
    )

    $enabledDomains = [System.Collections.Generic.List[string]]::new()
    $disabledDomains = [System.Collections.Generic.List[string]]::new()

    foreach ($service in $Definitions) {
        $isEnabled = [bool]$State[$service.id]
        foreach ($domain in @($service.domains)) {
            if ([string]::IsNullOrWhiteSpace($domain)) { continue }
            if ($isEnabled) {
                $enabledDomains.Add($domain)
            }
            else {
                $disabledDomains.Add($domain)
            }
        }
    }

    Set-ManagedBlock -Path $generalUserPath -BeginMarker $generalBegin -EndMarker $generalEnd -Values $enabledDomains.ToArray()
    Set-ManagedBlock -Path $excludeUserPath -BeginMarker $excludeBegin -EndMarker $excludeEnd -Values $disabledDomains.ToArray()
}

$definitions = Get-ServiceDefinitions

switch ($Mode) {
    'Validate' {
        $ids = @($definitions | ForEach-Object { $_.id })
        if (($ids | Sort-Object -Unique).Count -ne $ids.Count) {
            throw 'services.json contains duplicate ids.'
        }
        foreach ($service in $definitions) {
            if (-not $service.id -or -not $service.nameEn -or -not $service.nameRu) {
                throw 'A service definition is missing id/name fields.'
            }
            if (@($service.domains).Count -eq 0) {
                throw "Service '$($service.id)' has no domains."
            }
        }
        Write-Output "Validated $($definitions.Count) service definitions."
    }

    'Reset' {
        $state = New-DefaultState -Definitions $definitions
        Save-ServiceState -State $state
        Apply-ServiceMatrix -Definitions $definitions -State $state
        Write-Output 'Service matrix reset to defaults.'
    }

    'Summary' {
        $state = Get-ServiceState -Definitions $definitions
        $enabled = @($definitions | Where-Object { [bool]$state[$_.id] })
        [pscustomobject]@{
            Total = $definitions.Count
            Enabled = $enabled.Count
            EnabledIds = @($enabled | ForEach-Object { $_.id })
        } | ConvertTo-Json -Compress
    }

    default {
        $state = Get-ServiceState -Definitions $definitions
        if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
            Save-ServiceState -State $state
        }
        Apply-ServiceMatrix -Definitions $definitions -State $state
    }
}
