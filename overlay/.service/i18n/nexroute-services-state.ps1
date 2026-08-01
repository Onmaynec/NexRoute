# Internal NexRoute Service Matrix module. Dot-sourced by nexroute-services.ps1.

function Write-Utf8NoBom {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Content)
    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

function Write-JsonFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][AllowEmptyCollection()]$Value, [int]$Depth = 8)
    Write-Utf8NoBom -Path $Path -Content (($Value | ConvertTo-Json -Depth $Depth) + [Environment]::NewLine)
}

function Read-JsonFile {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required JSON file was not found: $Path"
    }
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Get-ServiceDefinitions {
    $document = Read-JsonFile -Path $definitionPath
    if ([int]$document.schemaVersion -ne 2) { throw "Unsupported services.json schema: $($document.schemaVersion)" }
    if (-not $document.services -or @($document.services).Count -eq 0) {
        throw 'services.json does not contain service definitions.'
    }
    return @($document.services)
}

function New-DefaultState {
    param([Parameter(Mandatory)][array]$Definitions)
    $state = [ordered]@{}
    foreach ($service in $Definitions) { $state[$service.id] = [bool]$service.defaultEnabled }
    return $state
}

function Backup-ServiceState {
    param([Parameter(Mandatory)][string]$FileName)
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { return }
    $backupPath = Join-Path $serviceDirectory $FileName
    if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
        Copy-Item -LiteralPath $statePath -Destination $backupPath -Force
    }
}

function Get-ServiceStateResult {
    param([Parameter(Mandatory)][array]$Definitions)

    $state = New-DefaultState -Definitions $Definitions
    $migrated = $false
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        return [pscustomobject]@{ State = $state; Migrated = $false; Invalid = $false; Exists = $false }
    }

    $invalid = $false
    try {
        $saved = Read-JsonFile -Path $statePath
        $savedServices = $null
        if ($saved.PSObject.Properties['services']) {
            $savedServices = $saved.services
        }
        else {
            $savedServices = $saved
            $migrated = $true
        }

        foreach ($service in $Definitions) {
            $property = $savedServices.PSObject.Properties[$service.id]
            if ($null -ne $property) { $state[$service.id] = [bool]$property.Value }
        }
    }
    catch {
        $invalid = $true
        Write-Warning "Ignoring invalid service state: $($_.Exception.Message)"
    }

    return [pscustomobject]@{ State = $state; Migrated = $migrated; Invalid = $invalid; Exists = $true }
}

function Save-ServiceState {
    param([Parameter(Mandatory)]$State)
    $document = [ordered]@{
        schemaVersion = $stateSchemaVersion
        updatedAtUtc = [DateTime]::UtcNow.ToString('o')
        services = $State
    }
    Write-JsonFile -Path $statePath -Value $document -Depth 6
}

function Ensure-ListFile {
    param([Parameter(Mandatory)][string]$Path)
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Write-Utf8NoBom -Path $Path -Content "# User-managed entries`r`n"
    }
}

function Set-ManagedBlock {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$BeginMarker,
        [Parameter(Mandatory)][string]$EndMarker,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Values
    )

    Ensure-ListFile -Path $Path
    $sourceLines = @(Get-Content -LiteralPath $Path -Encoding UTF8)
    $output = New-Object 'System.Collections.Generic.List[string]'
    $inside = $false
    foreach ($line in $sourceLines) {
        if ($line.Trim() -eq $BeginMarker) { $inside = $true; continue }
        if ($line.Trim() -eq $EndMarker) { $inside = $false; continue }
        if (-not $inside) { $output.Add($line) }
    }

    while ($output.Count -gt 0 -and [string]::IsNullOrWhiteSpace($output[$output.Count - 1])) {
        $output.RemoveAt($output.Count - 1)
    }

    $output.Add('')
    $output.Add($BeginMarker)
    foreach ($value in @($Values | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)) {
        $output.Add(([string]$value).ToLowerInvariant())
    }
    $output.Add($EndMarker)
    $output.Add('')
    Write-Utf8NoBom -Path $Path -Content (($output.ToArray() -join "`r`n") + "`r`n")
}
