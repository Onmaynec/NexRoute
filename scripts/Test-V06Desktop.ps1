[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ExtractDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($ExtractDirectory)
if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw "Extracted package directory is missing: $root" }

$trayPath=Join-Path $root '.service/native/NexRoute.Tray.exe'
$dashboardPath=Join-Path $root '.service/native/NexRoute.Dashboard.exe'
foreach ($path in @($trayPath,$dashboardPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Native desktop executable is missing: $path" }
}
$trayAssembly=[Reflection.AssemblyName]::GetAssemblyName($trayPath)
$dashboardAssembly=[Reflection.AssemblyName]::GetAssemblyName($dashboardPath)
if ([string]$trayAssembly.Name -ne 'NexRoute.Tray') { throw "Unexpected tray assembly: $($trayAssembly.Name)" }
if ([string]$dashboardAssembly.Name -ne 'NexRoute.Dashboard') { throw "Unexpected dashboard assembly: $($dashboardAssembly.Name)" }

$historyDirectory=Join-Path $root '.service/history/strategy-lab'
New-Item -ItemType Directory -Path $historyDirectory -Force | Out-Null
$fixturePath=Join-Path $historyDirectory '20990101-000000-dashboard-fixture.json'
$fixture=[ordered]@{
    schemaVersion=3
    createdUtc='2099-01-01T00:00:00.0000000Z'
    network='dashboard-ci'
    measurementContract=[ordered]@{ download='streaming'; youtube='hls-segment'; realtime='transport-readiness' }
    results=@(
        [ordered]@{
            strategy='dashboard-fixture'
            score=91.25
            measuredDownloadMbps=125.5
            averageJitterMs=3.2
            averagePacketLossPercent=0.0
            averageHttpLatencyMs=24.6
            availabilityPercent=100.0
            youtubePlaybackReady=$true
            discordRealtimeTransportReady=$true
            telegramRealtimeTransportReady=$true
        }
    )
}
[IO.File]::WriteAllText($fixturePath,($fixture | ConvertTo-Json -Depth 12)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))

$outputPath=Join-Path $env:TEMP ('nexroute-dashboard-selftest-'+[guid]::NewGuid().ToString('N')+'.json')
$errorPath=$outputPath+'.err'
try {
    $process=Start-Process -FilePath $dashboardPath -ArgumentList @('--self-test','--root',$root) -WorkingDirectory $root -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $outputPath -RedirectStandardError $errorPath
    if ($process.ExitCode -ne 0) {
        $errorText=if (Test-Path -LiteralPath $errorPath) { Get-Content -LiteralPath $errorPath -Raw -ErrorAction SilentlyContinue } else { '' }
        throw "Native dashboard self-test failed with exit code $($process.ExitCode): $errorText"
    }
    $raw=Get-Content -LiteralPath $outputPath -Raw -Encoding UTF8
    $report=$raw | ConvertFrom-Json
    if (-not [bool]$report.ok) { throw "Native dashboard self-test returned ok=false: $raw" }
    if ([int]$report.runCount -lt 1) { throw "Native dashboard did not read Strategy Lab history: $raw" }
    if ([int]$report.resultCount -lt 1) { throw "Native dashboard did not parse Strategy Lab results: $raw" }
    if ([string]$report.version -notmatch '^\d+\.\d+\.\d+') { throw "Native dashboard did not read package version: $raw" }
} finally {
    Remove-Item -LiteralPath $fixturePath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $outputPath,$errorPath -Force -ErrorAction SilentlyContinue
}

$traySource=Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'native/NexRoute.Tray/Program.cs') -Raw -Encoding UTF8
foreach ($token in @('Open Dashboard','NexRoute.Dashboard.exe','notifyIcon.DoubleClick','--root')) {
    if ($traySource -notmatch [regex]::Escape($token)) { throw "Tray source does not expose dashboard token: $token" }
}
$dashboardSource=Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'native/NexRoute.Dashboard/Program.cs') -Raw -Encoding UTF8
foreach ($token in @('System.Windows.Forms.DataVisualization.Charting','ScaleView.Zoomable','ChartMouseWheel','Light','Dark','AccentNames','strategy-lab','ui-settings.json')) {
    if ($dashboardSource -notmatch [regex]::Escape($token)) { throw "Dashboard source does not expose required UI behavior: $token" }
}

[pscustomobject]@{
    TrayAssembly=[string]$trayAssembly.Name
    TraySha256=(Get-FileHash -LiteralPath $trayPath -Algorithm SHA256).Hash.ToLowerInvariant()
    DashboardAssembly=[string]$dashboardAssembly.Name
    DashboardSha256=(Get-FileHash -LiteralPath $dashboardPath -Algorithm SHA256).Hash.ToLowerInvariant()
    DashboardSelfTestExitCode=0
    FixtureRunCount=[int]$report.runCount
    FixtureResultCount=[int]$report.resultCount
}
