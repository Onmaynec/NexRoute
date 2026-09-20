[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ReceiptPath,

    [string]$SourceLogPath,

    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$CandidateSha256
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# PrivacyReview is intentionally a generator-side publication review. This validator
# enforces the same boundary by rejecting unknown or extra receipt fields fail-closed.
$requiredTargets = @(
    'DiscordGateway',
    'DiscordCDN',
    'DiscordUpdates',
    'YouTubeWeb',
    'YouTubeShort',
    'YouTubeImage',
    'YouTubeVideoRedirect'
)
$requiredControls = @('GoogleMain', 'CloudflareWeb')
$knownStatuses = @('OK','ERROR','TIMEOUT','UNSUPPORTED','INCONCLUSIVE')
$allowedTopLevel = @(
    'schemaVersion','product','nexRouteVersion','gate','status','candidateSha256','sourceLogSha256',
    'strategy','requiredTargets','requiredControls','targets','controls','parsedStrategyCount','trustModel',
    'canonicalPayloadSha256'
)
$allowedResultFields = @('target','http','tls12','tls13')

function Get-NrSha256Text {
    param([Parameter(Mandatory)][string]$Text)
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Assert-NrExactProperties {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string[]]$Allowed,
        [Parameter(Mandatory)][string]$Context
    )
    $names = @($Object.PSObject.Properties.Name)
    $unknown = @($names | Where-Object { $Allowed -notcontains $_ })
    $missing = @($Allowed | Where-Object { $names -notcontains $_ })
    if ($unknown.Count -gt 0) { throw "$Context contains unknown field(s): $($unknown -join ', ')" }
    if ($missing.Count -gt 0) { throw "$Context is missing required field(s): $($missing -join ', ')" }
}

function New-NrCanonicalPayload {
    param([Parameter(Mandatory)]$Receipt)
    $targets = @(
        foreach ($item in @($Receipt.targets)) {
            [ordered]@{
                target = [string]$item.target
                http = [string]$item.http
                tls12 = [string]$item.tls12
                tls13 = [string]$item.tls13
            }
        }
    )
    $controls = @(
        foreach ($item in @($Receipt.controls)) {
            [ordered]@{
                target = [string]$item.target
                http = [string]$item.http
                tls12 = [string]$item.tls12
                tls13 = [string]$item.tls13
            }
        }
    )
    return [ordered]@{
        schemaVersion = [int]$Receipt.schemaVersion
        product = [string]$Receipt.product
        nexRouteVersion = [string]$Receipt.nexRouteVersion
        gate = [string]$Receipt.gate
        status = [string]$Receipt.status
        candidateSha256 = ([string]$Receipt.candidateSha256).ToLowerInvariant()
        sourceLogSha256 = ([string]$Receipt.sourceLogSha256).ToLowerInvariant()
        strategy = [string]$Receipt.strategy
        requiredTargets = @($Receipt.requiredTargets | ForEach-Object { [string]$_ })
        requiredControls = @($Receipt.requiredControls | ForEach-Object { [string]$_ })
        targets = @($targets)
        controls = @($controls)
        parsedStrategyCount = [int]$Receipt.parsedStrategyCount
        trustModel = [string]$Receipt.trustModel
    }
}

if (-not (Test-Path -LiteralPath $ReceiptPath -PathType Leaf)) {
    throw "Field-evidence receipt is missing: $ReceiptPath"
}

$receipt = Get-Content -LiteralPath $ReceiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-NrExactProperties -Object $receipt -Allowed $allowedTopLevel -Context 'Field-evidence receipt'

if ([int]$receipt.schemaVersion -ne 1) { throw "Unsupported field-evidence schemaVersion: $($receipt.schemaVersion)" }
if ([string]$receipt.product -ne 'NexRoute') { throw "Unexpected field-evidence product: $($receipt.product)" }
if ([string]$receipt.nexRouteVersion -notmatch '^\d+\.\d+\.\d+$') { throw 'Field-evidence nexRouteVersion is invalid.' }
if ([string]$receipt.gate -ne 'critical-service-field-evidence') { throw "Unknown field-evidence gate: $($receipt.gate)" }
if ([string]$receipt.status -ne 'passed') { throw "Field-evidence status must be passed, got: $($receipt.status)" }
if ([string]$receipt.candidateSha256 -notmatch '^[0-9a-f]{64}$') { throw 'Field-evidence candidateSha256 is invalid.' }
if ([string]$receipt.sourceLogSha256 -notmatch '^[0-9a-f]{64}$') { throw 'Field-evidence sourceLogSha256 is invalid.' }
if ([string]$receipt.canonicalPayloadSha256 -notmatch '^[0-9a-f]{64}$') { throw 'Field-evidence canonicalPayloadSha256 is invalid.' }
if ([string]::IsNullOrWhiteSpace([string]$receipt.strategy)) { throw 'Field-evidence strategy is empty.' }
if ([System.IO.Path]::GetFileName([string]$receipt.strategy) -ne [string]$receipt.strategy) { throw 'Field-evidence strategy must be a file name without a path.' }
if ([int]$receipt.parsedStrategyCount -lt 1) { throw 'Field-evidence parsedStrategyCount must be positive.' }

$storedRequiredTargets = @($receipt.requiredTargets | ForEach-Object { [string]$_ })
$storedRequiredControls = @($receipt.requiredControls | ForEach-Object { [string]$_ })
if (($storedRequiredTargets -join '|') -ne ($requiredTargets -join '|')) { throw 'Field-evidence requiredTargets do not match the canonical target set.' }
if (($storedRequiredControls -join '|') -ne ($requiredControls -join '|')) { throw 'Field-evidence requiredControls do not match the canonical control set.' }

function Assert-NrResultArray {
    param(
        [Parameter(Mandatory)]$Values,
        [Parameter(Mandatory)][string[]]$ExpectedTargets,
        [Parameter(Mandatory)][string]$Context
    )
    $items = @($Values)
    if ($items.Count -ne $ExpectedTargets.Count) { throw "$Context count is invalid." }
    for ($index = 0; $index -lt $ExpectedTargets.Count; $index++) {
        $item = $items[$index]
        Assert-NrExactProperties -Object $item -Allowed $allowedResultFields -Context "$Context[$index]"
        if ([string]$item.target -ne $ExpectedTargets[$index]) { throw "$Context target order or name is invalid at index $index." }
        foreach ($field in @('http','tls12','tls13')) {
            $value = [string]$item.$field
            if ($knownStatuses -notcontains $value) { throw "$Context contains unknown status '$value' for $($item.target)." }
            if ($value -ne 'OK') { throw "$Context contains a non-passing status '$value' for $($item.target)." }
        }
    }
}

Assert-NrResultArray -Values $receipt.targets -ExpectedTargets $requiredTargets -Context 'targets'
Assert-NrResultArray -Values $receipt.controls -ExpectedTargets $requiredControls -Context 'controls'

if (-not [string]::IsNullOrWhiteSpace($CandidateSha256) -and
    ([string]$receipt.candidateSha256).ToLowerInvariant() -ne $CandidateSha256.ToLowerInvariant()) {
    throw 'Field-evidence candidate SHA-256 does not match the expected candidate.'
}

if (-not [string]::IsNullOrWhiteSpace($SourceLogPath)) {
    if (-not (Test-Path -LiteralPath $SourceLogPath -PathType Leaf)) { throw "Source log is missing: $SourceLogPath" }
    $sourceSha = (Get-FileHash -LiteralPath $SourceLogPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($sourceSha -ne ([string]$receipt.sourceLogSha256).ToLowerInvariant()) {
        throw 'Field-evidence source-log SHA-256 does not match the supplied source log.'
    }
}

$payload = New-NrCanonicalPayload -Receipt $receipt
$canonicalJson = $payload | ConvertTo-Json -Depth 20 -Compress
$computedPayloadSha = Get-NrSha256Text -Text $canonicalJson
if ($computedPayloadSha -ne ([string]$receipt.canonicalPayloadSha256).ToLowerInvariant()) {
    throw 'Field-evidence canonical payload hash mismatch; the receipt was modified or is non-canonical.'
}

[pscustomobject]@{
    status = 'valid'
    schemaVersion = 1
    product = 'NexRoute'
    nexRouteVersion = [string]$receipt.nexRouteVersion
    strategy = [string]$receipt.strategy
    candidateSha256 = [string]$receipt.candidateSha256
    sourceLogSha256 = [string]$receipt.sourceLogSha256
    canonicalPayloadSha256 = [string]$receipt.canonicalPayloadSha256
    trustModel = [string]$receipt.trustModel
}
