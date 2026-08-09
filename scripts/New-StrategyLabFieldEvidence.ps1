[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path,

    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$CandidateSha256,

    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version = '0.6.4',

    [string]$OutputPath,

    [switch]$PrivacyReview
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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
$knownTargets = @($requiredTargets + @('GoogleMain','GoogleGstatic','CloudflareWeb','CloudflareCDN'))
$knownStatuses = @('OK','ERROR','TIMEOUT','UNSUPPORTED','INCONCLUSIVE')

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

function ConvertTo-NrCanonicalJson {
    param([Parameter(Mandatory)]$Value)
    return ($Value | ConvertTo-Json -Depth 20 -Compress)
}

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Strategy Lab field log is missing: $Path"
}

$resolvedPath = (Resolve-Path -LiteralPath $Path).Path
$sourceSha256 = (Get-FileHash -LiteralPath $resolvedPath -Algorithm SHA256).Hash.ToLowerInvariant()
$lines = @(Get-Content -LiteralPath $resolvedPath -Encoding UTF8)

$strategyPattern = '^\s*\[(?<index>\d+)\/(?<total>\d+)\]\s+(?<strategy>.+?\.bat)\s*$'
$resultPattern = '^\s*(?<target>[A-Za-z][A-Za-z0-9_-]*)\s+HTTP:(?<http>[A-Z0-9_.-]+)\s+TLS1\.2:(?<tls12>[A-Z0-9_.-]+)\s+TLS1\.3:(?<tls13>[A-Z0-9_.-]+)(?:\s+\|\s+Ping:\s*(?<ping>\d+)\s*ms)?\s*$'

$strategies = New-Object 'System.Collections.Generic.List[object]'
$current = $null

function Complete-NrFieldStrategy {
    if ($null -eq $script:current) { return }
    $script:strategies.Add([pscustomobject]@{
        index = [int]$script:current.index
        total = [int]$script:current.total
        strategy = [string]$script:current.strategy
        results = $script:current.results
    })
    $script:current = $null
}

foreach ($line in $lines) {
    $strategyMatch = [regex]::Match([string]$line, $strategyPattern)
    if ($strategyMatch.Success) {
        Complete-NrFieldStrategy
        $strategyName = [string]$strategyMatch.Groups['strategy'].Value.Trim()
        if ([System.IO.Path]::GetFileName($strategyName) -ne $strategyName) {
            throw "Strategy Lab evidence contains a strategy path instead of a file name: $strategyName"
        }
        $current = [pscustomobject]@{
            index = [int]$strategyMatch.Groups['index'].Value
            total = [int]$strategyMatch.Groups['total'].Value
            strategy = $strategyName
            results = @{}
        }
        continue
    }

    $resultMatch = [regex]::Match([string]$line, $resultPattern)
    if (-not $resultMatch.Success) { continue }
    if ($null -eq $current) {
        throw 'Strategy Lab evidence contains target results before a strategy header.'
    }

    $targetName = [string]$resultMatch.Groups['target'].Value
    if ($knownTargets -notcontains $targetName) {
        throw "Strategy Lab evidence contains an unknown target: $targetName"
    }
    if ($current.results.ContainsKey($targetName)) {
        throw "Strategy Lab evidence contains a duplicate target result for $targetName in $($current.strategy)."
    }

    $http = [string]$resultMatch.Groups['http'].Value
    $tls12 = [string]$resultMatch.Groups['tls12'].Value
    $tls13 = [string]$resultMatch.Groups['tls13'].Value
    foreach ($status in @($http,$tls12,$tls13)) {
        if ($knownStatuses -notcontains $status) {
            throw "Strategy Lab evidence contains an unknown status '$status' for $targetName."
        }
    }

    $current.results[$targetName] = [pscustomobject]@{
        target = $targetName
        http = $http
        tls12 = $tls12
        tls13 = $tls13
    }
}
Complete-NrFieldStrategy

if ($strategies.Count -eq 0) {
    throw 'The field log contains no recognizable Strategy Lab strategy blocks.'
}

$winner = $null
foreach ($strategy in $strategies) {
    $missingTargets = @($requiredTargets | Where-Object { -not $strategy.results.ContainsKey($_) })
    $missingControls = @($requiredControls | Where-Object { -not $strategy.results.ContainsKey($_) })
    if ($missingTargets.Count -gt 0 -or $missingControls.Count -gt 0) { continue }

    $allPassed = $true
    foreach ($name in @($requiredTargets + $requiredControls)) {
        $result = $strategy.results[$name]
        if ([string]$result.http -ne 'OK' -or [string]$result.tls12 -ne 'OK' -or [string]$result.tls13 -ne 'OK') {
            $allPassed = $false
            break
        }
    }
    if ($allPassed) {
        $winner = $strategy
        break
    }
}

if ($null -eq $winner) {
    throw 'NexRoute field evidence gate failed: no single strategy passed HTTP, TLS 1.2 and TLS 1.3 for every required critical target with healthy GoogleMain and CloudflareWeb controls.'
}

$targetReceipts = @(
    foreach ($name in $requiredTargets) {
        $result = $winner.results[$name]
        [ordered]@{
            target = $name
            http = [string]$result.http
            tls12 = [string]$result.tls12
            tls13 = [string]$result.tls13
        }
    }
)
$controlReceipts = @(
    foreach ($name in $requiredControls) {
        $result = $winner.results[$name]
        [ordered]@{
            target = $name
            http = [string]$result.http
            tls12 = [string]$result.tls12
            tls13 = [string]$result.tls13
        }
    }
)

$payload = [ordered]@{
    schemaVersion = 1
    product = 'NexRoute'
    nexRouteVersion = $Version
    gate = 'critical-service-field-evidence'
    status = 'passed'
    candidateSha256 = $CandidateSha256.ToLowerInvariant()
    sourceLogSha256 = $sourceSha256
    strategy = [string]$winner.strategy
    requiredTargets = @($requiredTargets)
    requiredControls = @($requiredControls)
    targets = @($targetReceipts)
    controls = @($controlReceipts)
    parsedStrategyCount = [int]$strategies.Count
    trustModel = 'Receipt proves deterministic parsing of the source-log hash; it does not independently prove network origin or operator identity.'
}
$payloadJson = ConvertTo-NrCanonicalJson -Value $payload
$receipt = [ordered]@{}
foreach ($key in $payload.Keys) { $receipt[$key] = $payload[$key] }
$receipt.canonicalPayloadSha256 = Get-NrSha256Text -Text $payloadJson

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $parent = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $json = ConvertTo-NrCanonicalJson -Value $receipt
    [System.IO.File]::WriteAllText(
        $OutputPath,
        ($json + [Environment]::NewLine),
        [System.Text.UTF8Encoding]::new($false)
    )
}

if ($PrivacyReview) {
    [pscustomobject]@{
        status = 'privacy-review'
        includedFields = @($receipt.Keys)
        excludedCategories = @(
            'username',
            'absolute-local-path',
            'ip-address',
            'mac-address',
            'ssid',
            'provider',
            'location',
            'arbitrary-user-list-content',
            'wall-clock-verification-time'
        )
        sourceLogPublished = $false
        receipt = [pscustomobject]$receipt
    }
} else {
    [pscustomobject]$receipt
}
