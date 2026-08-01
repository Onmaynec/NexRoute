[CmdletBinding()]
param(
    [ValidateSet('Apply', 'Summary', 'Reset', 'Validate', 'TestTargets', 'Restart', 'Diagnostics')]
    [string]$Mode = 'Apply',
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [string]$DiagnosticsPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$corePath = Join-Path $PSScriptRoot 'nexroute-services-core.ps1'
if (-not (Test-Path -LiteralPath $corePath -PathType Leaf)) {
    throw "NexRoute service-matrix core is missing: $corePath"
}

$arguments = @{
    Mode = $Mode
    Root = $Root
}
if (-not [string]::IsNullOrWhiteSpace($DiagnosticsPath)) {
    $arguments.DiagnosticsPath = $DiagnosticsPath
}

& $corePath @arguments
exit 0
