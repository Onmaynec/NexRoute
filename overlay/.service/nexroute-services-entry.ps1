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

# Build-Release invokes this packaged entry point after the original Flowseal
# archive has been expanded but before the normal NexRoute strategy hooks are
# tracked. Apply the 0.6.3 refresh only in that build call stack. Runtime Apply
# calls made by users must never rewrite installed strategy BAT files.
if ($Mode -eq 'Apply') {
    $buildFrame = @(
        Get-PSCallStack | Where-Object {
            -not [string]::IsNullOrWhiteSpace([string]$_.ScriptName) -and
            [System.IO.Path]::GetFileName([string]$_.ScriptName) -eq 'Build-Release.ps1'
        }
    ) | Select-Object -First 1

    if ($buildFrame) {
        $scriptsDirectory = Split-Path -Parent ([string]$buildFrame.ScriptName)
        $repositoryRoot = Split-Path -Parent $scriptsDirectory
        $refreshPath = Join-Path $repositoryRoot 'overlay/.service/next/nexroute-strategy-refresh-build.ps1'
        if (-not (Test-Path -LiteralPath $refreshPath -PathType Leaf)) {
            throw "NexRoute 0.6.3 build refresh is missing: $refreshPath"
        }

        . $refreshPath
        $refreshResult = Invoke-NexRoute063StrategyRefreshBuild -Root $Root
        if ([int]$refreshResult.StrategyCount -ne 21) {
            throw "NexRoute 0.6.3 strategy refresh produced $($refreshResult.StrategyCount) profiles instead of 21."
        }
    }
}

exit 0
