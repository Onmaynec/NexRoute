[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ExtractDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw 'Windows launcher smoke tests require Windows.'
}

$sourceRoot = (Resolve-Path -LiteralPath $ExtractDirectory).Path
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'NexRoute 0.6.3 Strategy Refresh Тест {0}' -f [guid]::NewGuid().ToString('N')
)
$results = New-Object 'System.Collections.Generic.List[object]'

try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    foreach ($item in @(Get-ChildItem -LiteralPath $sourceRoot -Force -ErrorAction Stop)) {
        Copy-Item -LiteralPath $item.FullName -Destination $testRoot -Recurse -Force
    }

    Remove-Item -LiteralPath (Join-Path $testRoot 'utils\check_updates.enabled') -Force -ErrorAction SilentlyContinue

    $updaterCore = Join-Path $testRoot '.service\nexroute-updater.ps1'
    $updaterEntry = Join-Path $testRoot '.service\nexroute-updater-entry.ps1'
    foreach ($requiredUpdater in @($updaterCore,$updaterEntry)) {
        if (-not (Test-Path -LiteralPath $requiredUpdater -PathType Leaf)) {
            throw "Updater module is missing from the extracted package: $requiredUpdater"
        }
    }

    $updaterOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $updaterEntry -Mode Status -Root $testRoot -Json 2>&1
    $updaterExitCode = $LASTEXITCODE
    $updaterText = (($updaterOutput | ForEach-Object { [string]$_ }) -join [Environment]::NewLine)
    if ($updaterExitCode -ne 0) {
        throw "Updater entry status smoke failed with exit code $updaterExitCode.`n$updaterText"
    }
    if ($updaterText -match '(?i)GetFullPath|Illegal characters in path|Недопустимые знаки|MethodInvocationException|ArgumentException') {
        throw "Updater entry reproduced a runtime crash.`n$updaterText"
    }
    try {
        $updaterStatus = @($updaterOutput | Select-Object -Last 20 | ForEach-Object {
            try { [string]$_ | ConvertFrom-Json } catch { $null }
        } | Where-Object { $null -ne $_ } | Select-Object -Last 1)
        if ($updaterStatus.Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$updaterStatus[0].CurrentVersion)) {
            throw 'Updater entry returned no valid status JSON.'
        }
    } catch {
        throw "Updater entry status output is invalid.`n$updaterText`n$($_.Exception.Message)"
    }

    $previousFixture = [Environment]::GetEnvironmentVariable('NEXROUTE_LATEST_RELEASE_FIXTURE')
    try {
        $env:NEXROUTE_LATEST_RELEASE_FIXTURE = 'https://github.com/Onmaynec/NexRoute/releases/tag/v0.6.3'
        $fallbackOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $updaterEntry -Mode Check -Root $testRoot -Json -NonInteractive 2>&1
        $fallbackExitCode = $LASTEXITCODE
        $fallbackText = (($fallbackOutput | ForEach-Object { [string]$_ }) -join [Environment]::NewLine)
        if ($fallbackExitCode -ne 0) {
            throw "API-free updater fallback smoke failed with exit code $fallbackExitCode.`n$fallbackText"
        }
        if ($fallbackText -match '(?i)API rate limit exceeded|api\.github\.com|403 Forbidden|429 Too Many Requests') {
            throw "Updater fallback unexpectedly reached the GitHub API.`n$fallbackText"
        }
        $fallbackStatus = @($fallbackOutput | Select-Object -Last 20 | ForEach-Object {
            try { [string]$_ | ConvertFrom-Json } catch { $null }
        } | Where-Object { $null -ne $_ } | Select-Object -Last 1)
        if ($fallbackStatus.Count -ne 1 -or [string]$fallbackStatus[0].LatestVersion -ne '0.6.3') {
            throw "Updater fallback returned no deterministic 0.6.3 release result.`n$fallbackText"
        }
    } finally {
        if ($null -eq $previousFixture) {
            Remove-Item Env:NEXROUTE_LATEST_RELEASE_FIXTURE -ErrorAction SilentlyContinue
        } else {
            $env:NEXROUTE_LATEST_RELEASE_FIXTURE = $previousFixture
        }
    }

    $diagnosticSmokePath = Join-Path $testRoot '.service\nexroute-first-run-smoke.ps1'
    $diagnosticSmokeSource = @'
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Root)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$service=Join-Path $Root '.service'
$next=Join-Path $service 'next'
foreach ($module in @(
    'nexroute-common.ps1',
    'nexroute-strategies.ps1',
    'nexroute-network.ps1',
    'nexroute-diagnostics.ps1',
    'nexroute-management.ps1',
    'nexroute-update.ps1'
)) {
    . (Join-Path $next $module)
}
Initialize-NrEnvironment -RootPath $Root
$report=Get-NrDiagnosticReport
function Test-ReportMember {
    param($Object,[string]$Name)
    if ($Object -is [System.Collections.IDictionary]) { return $Object.Contains($Name) }
    return ($null -ne $Object.PSObject.Properties[$Name])
}
foreach ($name in @('administrator','runtime','network','conflicts')) {
    if (-not (Test-ReportMember -Object $report -Name $name)) { throw "First-run diagnostic member is missing: $name" }
}
if (-not (Test-ReportMember -Object $report.runtime -Name 'zapret')) { throw 'First-run runtime.zapret member is missing.' }
foreach ($conflict in @($report.conflicts)) {
    if (-not (Test-ReportMember -Object $conflict -Name 'detected')) { throw 'First-run conflict.detected member is missing.' }
}
[pscustomobject]@{
    diagnosticCompatibility='passed'
    administrator=[bool]$report.administrator
    service=[bool]$report.runtime.zapret
    network=[string]$report.network
    conflictCount=@($report.conflicts).Count
} | ConvertTo-Json -Compress
'@
    [IO.File]::WriteAllText($diagnosticSmokePath,$diagnosticSmokeSource,(New-Object Text.UTF8Encoding($false)))
    try {
        $diagnosticOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $diagnosticSmokePath -Root $testRoot 2>&1
        $diagnosticExitCode = $LASTEXITCODE
        $diagnosticText = (($diagnosticOutput | ForEach-Object { [string]$_ }) -join [Environment]::NewLine)
        if ($diagnosticExitCode -ne 0) {
            throw "First-run diagnostic compatibility smoke failed with exit code $diagnosticExitCode.`n$diagnosticText"
        }
        if ($diagnosticText -match '(?i)PropertyNotFound|property .+ cannot be found|Не удается найти свойство') {
            throw "First-run diagnostic compatibility reproduced the property crash.`n$diagnosticText"
        }
        $diagnosticStatus = @($diagnosticOutput | Select-Object -Last 20 | ForEach-Object {
            try { [string]$_ | ConvertFrom-Json } catch { $null }
        } | Where-Object { $null -ne $_ } | Select-Object -Last 1)
        if ($diagnosticStatus.Count -ne 1 -or [string]$diagnosticStatus[0].diagnosticCompatibility -ne 'passed') {
            throw "First-run diagnostic compatibility returned no valid result.`n$diagnosticText"
        }
    } finally {
        Remove-Item -LiteralPath $diagnosticSmokePath -Force -ErrorAction SilentlyContinue
    }

    foreach ($fixture in @(
        [pscustomobject]@{ Name = 'service.bat'; Arguments = '--status' },
        [pscustomobject]@{ Name = 'nexroute.bat'; Arguments = '--status' },
        [pscustomobject]@{ Name = 'nexroute-update.cmd'; Arguments = '--status' }
    )) {
        $launcher = Join-Path $testRoot $fixture.Name
        if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) {
            throw "Launcher is missing from the extracted package: $($fixture.Name)"
        }

        $commandLine = 'call "{0}" {1}' -f $launcher, $fixture.Arguments
        $output = & $env:ComSpec /d /s /c $commandLine 2>&1
        $exitCode = $LASTEXITCODE
        $text = (($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine)

        if ($exitCode -ne 0) {
            throw "Launcher $($fixture.Name) failed with exit code $exitCode.`n$text"
        }
        if ($text -match '(?i)GetFullPath|Illegal characters in path|Недопустимые знаки|MethodInvocationException|ArgumentException|ParameterAlreadyBound|PropertyNotFound') {
            throw "Launcher $($fixture.Name) reproduced the Windows runtime crash.`n$text"
        }

        $results.Add([pscustomobject]@{
            launcher = $fixture.Name
            exitCode = $exitCode
            outputLength = $text.Length
        })
    }

    return [pscustomobject]@{
        status = 'passed'
        testRoot = $testRoot
        updaterEntryExitCode = $updaterExitCode
        updaterVersion = [string]$updaterStatus[0].CurrentVersion
        updaterFallbackExitCode = $fallbackExitCode
        updaterFallbackVersion = [string]$fallbackStatus[0].LatestVersion
        diagnosticCompatibility = [string]$diagnosticStatus[0].diagnosticCompatibility
        launcherCount = $results.Count
        launchers = $results.ToArray()
    }
} finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
