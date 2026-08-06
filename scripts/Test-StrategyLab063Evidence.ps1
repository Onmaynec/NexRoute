[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path,

    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{64}$')]
    [string]$CandidateSha256,

    [string]$OutputPath,

    [string]$Provider = 'Informatsionnye Kommunikatsii',

    [string]$Location = 'Sibay, Russia'
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

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Strategy Lab evidence log is missing: $Path"
}

$resolvedPath = (Resolve-Path -LiteralPath $Path).Path
$sourceSha256 = (Get-FileHash -LiteralPath $resolvedPath -Algorithm SHA256).Hash.ToLowerInvariant()
$lines = Get-Content -LiteralPath $resolvedPath -Encoding UTF8

$strategyPattern = '^\s*\[(?<index>\d+)\/(?<total>\d+)\]\s+(?<strategy>.+?\.bat)\s*$'
$targetPattern = '^\s*(?<target>DiscordGateway|DiscordCDN|DiscordUpdates|YouTubeWeb|YouTubeShort|YouTubeImage|YouTubeVideoRedirect)\s+HTTP:(?<http>[A-Z0-9_-]+)\s+TLS1\.2:(?<tls12>[A-Z0-9_.-]+)\s+TLS1\.3:(?<tls13>[A-Z0-9_.-]+)\s+\|\s+Ping:\s*(?<ping>\d+)\s*ms\s*$'
$controlPattern = '^\s*(?<target>GoogleMain|GoogleGstatic|CloudflareWeb|CloudflareCDN)\s+HTTP:(?<http>[A-Z0-9_-]+)\s+TLS1\.2:(?<tls12>[A-Z0-9_.-]+)\s+TLS1\.3:(?<tls13>[A-Z0-9_.-]+)\s+\|\s+Ping:\s*(?<ping>\d+)\s*ms\s*$'

$strategies = New-Object 'System.Collections.Generic.List[object]'
$current = $null

function Complete-CurrentStrategy {
    if ($null -eq $script:current) { return }
    $script:strategies.Add([pscustomobject]@{
        index = [int]$script:current.index
        total = [int]$script:current.total
        strategy = [string]$script:current.strategy
        targets = @($script:current.targets.Values)
        controls = @($script:current.controls.Values)
    })
    $script:current = $null
}

foreach ($line in $lines) {
    $strategyMatch = [regex]::Match([string]$line, $strategyPattern)
    if ($strategyMatch.Success) {
        Complete-CurrentStrategy
        $current = [pscustomobject]@{
            index = [int]$strategyMatch.Groups['index'].Value
            total = [int]$strategyMatch.Groups['total'].Value
            strategy = [string]$strategyMatch.Groups['strategy'].Value.Trim()
            targets = @{}
            controls = @{}
        }
        continue
    }

    if ($null -eq $current) { continue }

    $targetMatch = [regex]::Match([string]$line, $targetPattern)
    if ($targetMatch.Success) {
        $targetName = [string]$targetMatch.Groups['target'].Value
        $current.targets[$targetName] = [pscustomobject]@{
            target = $targetName
            http = [string]$targetMatch.Groups['http'].Value
            tls12 = [string]$targetMatch.Groups['tls12'].Value
            tls13 = [string]$targetMatch.Groups['tls13'].Value
            pingMs = [int]$targetMatch.Groups['ping'].Value
        }
        continue
    }

    $controlMatch = [regex]::Match([string]$line, $controlPattern)
    if ($controlMatch.Success) {
        $targetName = [string]$controlMatch.Groups['target'].Value
        $current.controls[$targetName] = [pscustomobject]@{
            target = $targetName
            http = [string]$controlMatch.Groups['http'].Value
            tls12 = [string]$controlMatch.Groups['tls12'].Value
            tls13 = [string]$controlMatch.Groups['tls13'].Value
            pingMs = [int]$controlMatch.Groups['ping'].Value
        }
    }
}
Complete-CurrentStrategy

if ($strategies.Count -eq 0) {
    throw 'The evidence log contains no recognizable Strategy Lab config blocks.'
}

$evaluations = New-Object 'System.Collections.Generic.List[object]'
foreach ($strategy in $strategies) {
    $targetMap = @{}
    foreach ($target in @($strategy.targets)) { $targetMap[[string]$target.target] = $target }

    $missing = @($requiredTargets | Where-Object { -not $targetMap.ContainsKey($_) })
    $failed = New-Object 'System.Collections.Generic.List[string]'
    foreach ($targetName in $requiredTargets) {
        if (-not $targetMap.ContainsKey($targetName)) { continue }
        $result = $targetMap[$targetName]
        if ([string]$result.http -ne 'OK' -or [string]$result.tls12 -ne 'OK' -or [string]$result.tls13 -ne 'OK') {
            $failed.Add($targetName)
        }
    }

    $evaluations.Add([pscustomobject]@{
        strategy = [string]$strategy.strategy
        complete = ($missing.Count -eq 0)
        passed = ($missing.Count -eq 0 -and $failed.Count -eq 0)
        missingTargets = $missing
        failedTargets = @($failed.ToArray())
        targets = @($strategy.targets)
        controls = @($strategy.controls)
    })
}

$winner = @($evaluations | Where-Object { $_.passed } | Select-Object -First 1)
if ($winner.Count -ne 1) {
    $best = @($evaluations | Sort-Object @{ Expression = { @($_.failedTargets).Count + @($_.missingTargets).Count } }, strategy | Select-Object -First 1)
    $detail = if ($best.Count -eq 1) {
        $problems = @(@($best[0].missingTargets) + @($best[0].failedTargets) | Sort-Object -Unique)
        " Closest strategy '$($best[0].strategy)' still fails or misses: $($problems -join ', ')."
    } else { '' }
    throw "NexRoute 0.6.3 live release gate failed: no strategy passed HTTP, TLS 1.2 and TLS 1.3 for all seven critical Discord/YouTube targets.$detail"
}

$winningStrategy = $winner[0]
$evidence = [ordered]@{
    schemaVersion = 1
    nexRouteVersion = '0.6.3'
    gate = 'sibay-critical-targets'
    status = 'passed'
    provider = $Provider
    location = $Location
    candidateSha256 = $CandidateSha256.ToLowerInvariant()
    sourceLogSha256 = $sourceSha256
    verifiedUtc = [DateTime]::UtcNow.ToString('o')
    strategy = [string]$winningStrategy.strategy
    requiredTargets = $requiredTargets
    targets = @($winningStrategy.targets)
    controls = @($winningStrategy.controls)
    parsedStrategyCount = $strategies.Count
}

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $parent = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $json = $evidence | ConvertTo-Json -Depth 12
    [System.IO.File]::WriteAllText(
        $OutputPath,
        ($json + [Environment]::NewLine),
        [System.Text.UTF8Encoding]::new($false)
    )
}

[pscustomobject]$evidence
