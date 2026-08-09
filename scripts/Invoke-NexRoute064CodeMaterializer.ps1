[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot

function Read-NrText([string]$RelativePath) { [IO.File]::ReadAllText((Join-Path $root $RelativePath),[Text.Encoding]::UTF8) }
function Write-NrText([string]$RelativePath,[string]$Text) { [IO.File]::WriteAllText((Join-Path $root $RelativePath),$Text,[Text.UTF8Encoding]::new($false)) }
function Replace-NrRequired([string]$RelativePath,[string]$Old,[string]$New) {
    $text=Read-NrText $RelativePath
    if (-not $text.Contains($Old)) { throw "Required 0.6.4 integration token was not found in $RelativePath.`n$Old" }
    Write-NrText $RelativePath ($text.Replace($Old,$New))
}

# Strategy Lab override.
$console='overlay/.service/nexroute-console.ps1'
if (-not (Read-NrText $console).Contains("'nexroute-strategy-ranking.ps1'")) {
    Replace-NrRequired $console "    'nexroute-strategies.ps1',`n    'nexroute-network.ps1'," "    'nexroute-strategies.ps1',`n    'nexroute-strategy-ranking.ps1',`n    'nexroute-network.ps1',"
}

# Transactional post-update health gate.
$updater='overlay/.service/nexroute-updater.ps1'
if (-not (Read-NrText $updater).Contains('function Test-NexRoutePostUpdateHealth')) {
    $health=@'
function Test-NexRoutePostUpdateHealth {
    param(
        [Parameter(Mandatory)][string]$ExpectedVersion,
        [bool]$WasRunning = $false
    )

    if ([Environment]::GetEnvironmentVariable('NEXROUTE_UPDATE_FORCE_HEALTH_FAILURE') -eq '1') {
        throw 'NexRoute post-update health check was forced to fail for rollback validation.'
    }

    foreach ($relativePath in @(
        '.service/version.txt',
        '.service/nexroute-updater.ps1',
        '.service/upstream-lock.json',
        '.service/patch-report.json',
        'nexroute.bat',
        'nexroute-update.cmd',
        'service.bat'
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $Root $relativePath) -PathType Leaf)) {
            throw "NexRoute post-update health check failed: required file is missing: $relativePath"
        }
    }

    $installedVersion = Get-NexRouteCurrentVersion
    if ($installedVersion -ne $ExpectedVersion) {
        throw "NexRoute post-update health check failed: expected version $ExpectedVersion, got $installedVersion."
    }

    $patchReport = Get-Content -LiteralPath (Join-Path $Root '.service/patch-report.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $summary = Get-NexRoutePropertyValue -InputObject $patchReport -Name 'summary'
    $targetCount = [int](Get-NexRoutePropertyValue -InputObject $summary -Name 'targetCount')
    if ($targetCount -ne 23) {
        throw "NexRoute post-update health check failed: patch report contains $targetCount targets instead of 23."
    }

    if ($WasRunning -and $env:OS -eq 'Windows_NT') {
        $runtimeHealthy = $false
        try {
            $service = Get-Service -Name 'zapret' -ErrorAction Stop
            $runtimeHealthy = $service.Status -eq 'Running'
        } catch { }
        if (-not $runtimeHealthy) {
            try { $runtimeHealthy = $null -ne (Get-Process -Name 'winws' -ErrorAction SilentlyContinue | Select-Object -First 1) } catch { }
        }
        if (-not $runtimeHealthy) {
            throw 'NexRoute post-update health check failed: runtime was active before the update but did not return to a healthy running state.'
        }
    }
    return $true
}

'@
    Replace-NrRequired $updater 'function Install-NexRouteVerifiedPackage {' ($health+'function Install-NexRouteVerifiedPackage {')
}
if (-not (Read-NrText $updater).Contains('Test-NexRoutePostUpdateHealth -ExpectedVersion $Release.Version')) {
    Replace-NrRequired $updater "        `$restartMessage = Start-NexRouteRuntime -WasRunning `$wasRunning`n        `$State.latestVersion = `$Release.Version" "        `$restartMessage = Start-NexRouteRuntime -WasRunning `$wasRunning`n        [void](Test-NexRoutePostUpdateHealth -ExpectedVersion `$Release.Version -WasRunning `$wasRunning)`n        `$State.latestVersion = `$Release.Version"
}

# Dashboard consumes schema-3 ranking fields and explains winner/inconclusive states.
$dashboard='native/NexRoute.Dashboard/Program.cs'
if (-not (Read-NrText $dashboard).Contains('AddGridColumn("RankingState"')) {
    Replace-NrRequired $dashboard '            AddGridColumn("Score", "Score", 70, "N2");' @'
            AddGridColumn("Score", "Score", 70, "N2");
            AddGridColumn("RankingState", "State", 85);
            AddGridColumn("CriticalAvailabilityPercent", "Critical %", 85, "N1");
            AddGridColumn("StabilityPercent", "Stability %", 85, "N1");
            AddGridColumn("ObservationCount", "Samples", 70);
            AddGridColumn("RecommendationReason", "Why winner", 220);
'@
}
if (-not (Read-NrText $dashboard).Contains('best.RecommendationReason')) {
    Replace-NrRequired $dashboard @'
                StrategyPoint best = points.OrderByDescending(delegate(StrategyPoint point) { return point.Score; }).FirstOrDefault();
                bestValue.Text = best == null ? "—" : best.Strategy + " · " + best.Score.ToString("N2", CultureInfo.InvariantCulture);
'@ @'
                StrategyPoint best = points.Where(delegate(StrategyPoint point) { return !string.Equals(point.RankingState, "inconclusive", StringComparison.OrdinalIgnoreCase); }).OrderByDescending(delegate(StrategyPoint point) { return point.Score; }).FirstOrDefault();
                bestValue.Text = best == null ? "—" : best.Strategy + " · " + best.Score.ToString("N2", CultureInfo.InvariantCulture);
                toolTip.SetToolTip(bestValue, best == null || string.IsNullOrWhiteSpace(best.RecommendationReason) ? string.Empty : best.RecommendationReason);
'@
}
if (-not (Read-NrText $dashboard).Contains('points = points.Where(delegate(StrategyPoint point) { return !string.Equals(point.RankingState, "inconclusive"')) {
    Replace-NrRequired $dashboard @'
            if (!string.Equals(selected, "All strategies", StringComparison.OrdinalIgnoreCase))
            {
                points = points.Where(delegate(StrategyPoint point) { return string.Equals(point.Strategy, selected, StringComparison.OrdinalIgnoreCase); }).ToList();
            }
            chart.Series.Clear();
'@ @'
            if (!string.Equals(selected, "All strategies", StringComparison.OrdinalIgnoreCase))
            {
                points = points.Where(delegate(StrategyPoint point) { return string.Equals(point.Strategy, selected, StringComparison.OrdinalIgnoreCase); }).ToList();
            }
            if (string.Equals(metric, "Score", StringComparison.OrdinalIgnoreCase))
            {
                points = points.Where(delegate(StrategyPoint point) { return !string.Equals(point.RankingState, "inconclusive", StringComparison.OrdinalIgnoreCase); }).ToList();
            }
            chart.Series.Clear();
'@
}
if (-not (Read-NrText $dashboard).Contains('string rankingText')) {
    Replace-NrRequired $dashboard @'
            e.Text = model.Strategy + Environment.NewLine +
                     model.CreatedUtc.ToLocalTime().ToString("g") + Environment.NewLine +
                     "Score " + model.Score.ToString("N2") + " · " + model.DownloadMbps.ToString("N2") + " Mbps" + Environment.NewLine +
                     "Jitter " + model.JitterMs.ToString("N1") + " ms · Loss " + model.PacketLossPercent.ToString("N1") + "%";
'@ @'
            string rankingText = string.Equals(model.RankingState, "inconclusive", StringComparison.OrdinalIgnoreCase)
                ? "INCONCLUSIVE: " + (model.InconclusiveReason ?? "insufficient evidence")
                : "Score " + model.Score.ToString("N2") + " · critical " + model.CriticalAvailabilityPercent.ToString("N1") + "% · stability " + model.StabilityPercent.ToString("N1") + "%";
            string why = string.IsNullOrWhiteSpace(model.RecommendationReason) ? string.Empty : Environment.NewLine + "WHY: " + model.RecommendationReason;
            e.Text = model.Strategy + Environment.NewLine +
                     model.CreatedUtc.ToLocalTime().ToString("g") + Environment.NewLine +
                     rankingText + Environment.NewLine +
                     model.DownloadMbps.ToString("N2") + " Mbps · Jitter " + model.JitterMs.ToString("N1") + " ms · Loss " + model.PacketLossPercent.ToString("N1") + "%" + why;
'@
}
if (-not (Read-NrText $dashboard).Contains('RankingState = ConvertEx.String')) {
    Replace-NrRequired $dashboard @'
                                Strategy = ConvertEx.String(result, "strategy", "unknown"),
                                Score = ConvertEx.Double(result, "score", 0),
                                DownloadMbps = ConvertEx.Double(result, "measuredDownloadMbps", ConvertEx.Double(result, "peakDownloadMbps", 0)),
'@ @'
                                Strategy = ConvertEx.String(result, "strategy", "unknown"),
                                Score = ConvertEx.Double(result, "score", 0),
                                RankingState = ConvertEx.String(result, "rankingState", "legacy"),
                                CriticalAvailabilityPercent = ConvertEx.Double(result, "criticalAvailabilityPercent", ConvertEx.Double(result, "availabilityPercent", 0)),
                                StabilityPercent = ConvertEx.Double(result, "stabilityPercent", 0),
                                ObservationCount = ConvertEx.Int(result, "observationCount", 0),
                                RecommendationReason = ConvertEx.String(result, "recommendationReason", null),
                                InconclusiveReason = ConvertEx.String(result, "inconclusiveReason", null),
                                DownloadMbps = ConvertEx.Double(result, "measuredDownloadMbps", ConvertEx.Double(result, "peakDownloadMbps", 0)),
'@
    Replace-NrRequired $dashboard @'
                                YoutubeReady = ConvertEx.Bool(result, "youtubePlaybackReady", false),
                                DiscordReady = ConvertEx.Bool(result, "discordRealtimeTransportReady", false),
                                TelegramReady = ConvertEx.Bool(result, "telegramRealtimeTransportReady", false)
'@ @'
                                YoutubeReady = ConvertEx.Bool(result, "youtubePlaybackReady", ConvertEx.Bool(result, "youtubeVideoReady", false)),
                                DiscordReady = ConvertEx.Bool(result, "discordRealtimeTransportReady", ConvertEx.Bool(result, "discordVoiceReady", false)),
                                TelegramReady = ConvertEx.Bool(result, "telegramRealtimeTransportReady", ConvertEx.Bool(result, "telegramVoiceReady", false))
'@
    Replace-NrRequired $dashboard @'
        public double Score { get; set; }
        public double DownloadMbps { get; set; }
'@ @'
        public double Score { get; set; }
        public string RankingState { get; set; }
        public double CriticalAvailabilityPercent { get; set; }
        public double StabilityPercent { get; set; }
        public int ObservationCount { get; set; }
        public string RecommendationReason { get; set; }
        public string InconclusiveReason { get; set; }
        public double DownloadMbps { get; set; }
'@
}

# Repository contract additions only; workflow files are intentionally handled by the GitHub connector.
$repoTest='scripts/Test-Repository.ps1'
if (-not (Read-NrText $repoTest).Contains("'overlay/.service/next/nexroute-strategy-ranking.ps1'")) {
    Replace-NrRequired $repoTest "    'overlay/.service/next/nexroute-hotfix-062.ps1','overlay/.service/next/nexroute-update.ps1'," "    'overlay/.service/next/nexroute-hotfix-062.ps1','overlay/.service/next/nexroute-strategy-ranking.ps1','overlay/.service/next/nexroute-update.ps1',"
}
if (-not (Read-NrText $repoTest).Contains("'scripts/Test-Updater063MigrationEvidence.ps1'")) {
    Replace-NrRequired $repoTest "    'scripts/Test-StrategyLab063Evidence.ps1','scripts/New-StrategyLabFieldEvidence.ps1','scripts/Test-StrategyLabFieldEvidence.ps1','scripts/Test-GitHubActionsPinning.ps1'," "    'scripts/Test-StrategyLab063Evidence.ps1','scripts/New-StrategyLabFieldEvidence.ps1','scripts/Test-StrategyLabFieldEvidence.ps1','scripts/Test-GitHubActionsPinning.ps1','scripts/Test-Updater063MigrationEvidence.ps1',"
}
if (-not (Read-NrText $repoTest).Contains("'tests/StrategyRanking064.Tests.ps1'")) {
    Replace-NrRequired $repoTest "    'tests/StrategyRefresh063.Tests.ps1','tests/StrategyLab063Evidence.Tests.ps1','tests/StrategyLabFieldEvidence064.Tests.ps1','tests/GitHubActionsPinning064.Tests.ps1'," "    'tests/StrategyRefresh063.Tests.ps1','tests/StrategyLab063Evidence.Tests.ps1','tests/StrategyLabFieldEvidence064.Tests.ps1','tests/StrategyRanking064.Tests.ps1','tests/UpdaterHealthRollback064.Tests.ps1','tests/GitHubActionsPinning064.Tests.ps1',"
}
if (-not (Read-NrText $repoTest).Contains('$ranking064=Read-Text')) {
    Replace-NrRequired $repoTest "`$fieldEvidenceValidator=Read-Text 'scripts/Test-StrategyLabFieldEvidence.ps1'`n" @'
$fieldEvidenceValidator=Read-Text 'scripts/Test-StrategyLabFieldEvidence.ps1'
$ranking064=Read-Text 'overlay/.service/next/nexroute-strategy-ranking.ps1'
$console064=Read-Text 'overlay/.service/nexroute-console.ps1'
$updater064=Read-Text 'overlay/.service/nexroute-updater.ps1'
$migration064=Read-Text 'scripts/Test-Updater063MigrationEvidence.ps1'
$dashboard064=Read-Text 'native/NexRoute.Dashboard/Program.cs'
'@
    Replace-NrRequired $repoTest "Assert-True (`$fieldEvidence -notmatch 'verifiedUtc|provider\\s`*=|location\\s`*=') '0.6.4 field-evidence receipt has no nondeterministic time/provider/location fields'`n" @'
Assert-True ($fieldEvidence -notmatch 'verifiedUtc|provider\s*=|location\s*=') '0.6.4 field-evidence receipt has no nondeterministic time/provider/location fields'
foreach ($token in @('criticalAvailabilityPercent','stabilityPercent','minimumObservationCount','inconclusiveReason','recommendationReason','missingMetricPolicy','tieBreak')) {
    Assert-True ($ranking064 -match [regex]::Escape($token)) "0.6.4 Strategy Lab ranking contains $token"
}
Assert-True ($console064 -match [regex]::Escape('nexroute-strategy-ranking.ps1')) 'Console loads the 0.6.4 Strategy Lab ranking override'
foreach ($token in @('Test-NexRoutePostUpdateHealth','NEXROUTE_UPDATE_FORCE_HEALTH_FAILURE','post-update health check')) {
    Assert-True ($updater064 -match [regex]::Escape($token)) "Updater health transaction contains $token"
}
foreach ($token in @('v0.6.2','v0.6.3','pathHasSpaces','pathHasNonAscii','absolutePathPublished')) {
    Assert-True ($migration064 -match [regex]::Escape($token)) "Real migration evidence gate contains $token"
}
foreach ($token in @('RankingState','RecommendationReason','InconclusiveReason','CriticalAvailabilityPercent','StabilityPercent')) {
    Assert-True ($dashboard064 -match [regex]::Escape($token)) "Dashboard exposes ranking field $token"
}
'@
}

# Remove both temporary code materializers; workflow cleanup is done through the connector after this commit lands.
foreach ($relative in @('scripts/Invoke-NexRoute064CodeMaterializer.ps1','scripts/Invoke-NexRoute064Materializer.ps1')) {
    $path=Join-Path $root $relative
    if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force }
}
