Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$extensionModules=@(
    'nexroute-update-transaction.ps1',
    'nexroute-portable-verifier.ps1',
    'nexroute-attestation-v2.ps1',
    'nexroute-dot-bootstrap.ps1',
    'nexroute-dot.ps1',
    'nexroute-dot-snapshot-v2.ps1',
    'nexroute-media.ps1',
    'nexroute-strategy-lab-v2.ps1',
    'nexroute-workers.ps1',
    'nexroute-worker-plans.ps1'
)
foreach ($extension in $extensionModules) {
    $extensionPath=Join-Path $PSScriptRoot $extension
    if (-not (Test-Path -LiteralPath $extensionPath -PathType Leaf)) { throw "NexRoute runtime extension is missing: $extension" }
    . $extensionPath
}
