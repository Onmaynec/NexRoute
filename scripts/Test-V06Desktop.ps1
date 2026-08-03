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
$validationPath=Join-Path $root '.service/native/NexRoute.Validation.exe'
foreach ($path in @($trayPath,$dashboardPath,$validationPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Native desktop executable is missing: $path" }
}
$trayAssembly=[Reflection.AssemblyName]::GetAssemblyName($trayPath)
$dashboardAssembly=[Reflection.AssemblyName]::GetAssemblyName($dashboardPath)
$validationAssembly=[Reflection.AssemblyName]::GetAssemblyName($validationPath)
if ([string]$trayAssembly.Name -ne 'NexRoute.Tray') { throw "Unexpected tray assembly: $($trayAssembly.Name)" }
if ([string]$dashboardAssembly.Name -ne 'NexRoute.Dashboard') { throw "Unexpected dashboard assembly: $($dashboardAssembly.Name)" }
if ([string]$validationAssembly.Name -ne 'NexRoute.Validation') { throw "Unexpected validation assembly: $($validationAssembly.Name)" }

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

function Invoke-NrValidationViewerSelfTest {
    param([Parameter(Mandatory)][string]$Executable,[Parameter(Mandatory)][string]$PackageRoot)
    $stdout=Join-Path $env:TEMP ('nexroute-validation-selftest-'+[guid]::NewGuid().ToString('N')+'.json')
    $stderr=$stdout+'.err'
    try {
        $process=Start-Process -FilePath $Executable -ArgumentList @('--self-test','--root',$PackageRoot) -WorkingDirectory $PackageRoot -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $errorText=if (Test-Path -LiteralPath $stderr) { Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue } else { '' }
        if ($process.ExitCode -ne 0) { throw "Validation viewer self-test failed with exit code $($process.ExitCode): $errorText" }
        $raw=Get-Content -LiteralPath $stdout -Raw -Encoding UTF8
        $result=$raw | ConvertFrom-Json
        if (-not [bool]$result.ok -or -not [bool]$result.reportFound -or -not [bool]$result.schemaValid) {
            throw "Validation viewer returned an invalid self-test document: $raw"
        }
        return $result
    } finally {
        Remove-Item -LiteralPath $stdout,$stderr -Force -ErrorAction SilentlyContinue
    }
}

$packageVersion=(Get-Content -LiteralPath (Join-Path $root '.service/version.txt') -Raw -Encoding UTF8).Trim()
$validationReportPath=Join-Path $root '.service/release-validation.json'
$validationReceiptPath=$validationReportPath+'.attestation-receipt.json'
$validationFixture=[ordered]@{
    schemaVersion=1
    product='NexRoute'
    version=$packageVersion
    overallStatus='passed-with-limitations'
    checks=@(
        [ordered]@{ id='package.sha256'; category='release'; status='passed'; required=$true; summary='Package digest verified.'; evidence=('a'*64); limitation=$null },
        [ordered]@{ id='native-dashboard.interactive'; category='desktop'; status='experimental'; required=$false; summary='Interactive dashboard session is not automated.'; evidence='Self-test passed.'; limitation='Validate on a signed-in Windows desktop.' },
        [ordered]@{ id='runtime.ipv6-live'; category='runtime'; status='unsupported'; required=$false; summary='Live IPv6 bypass is not proven.'; evidence='Synthetic workers passed.'; limitation='Requires an IPv6-capable network.' }
    )
    limitations=@(
        [ordered]@{ id='native-dashboard.interactive'; status='experimental'; limitation='Validate on a signed-in Windows desktop.' },
        [ordered]@{ id='runtime.ipv6-live'; status='unsupported'; limitation='Requires an IPv6-capable network.' }
    )
}
[IO.File]::WriteAllText($validationReportPath,($validationFixture | ConvertTo-Json -Depth 12)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
try {
    $unverifiedValidation=Invoke-NrValidationViewerSelfTest -Executable $validationPath -PackageRoot $root
    if ([string]$unverifiedValidation.trustState -ne 'attestation-not-verified') { throw "Expected an unverified report trust state, got $($unverifiedValidation.trustState)." }
    if ([int]$unverifiedValidation.checkCount -ne 3 -or [int]$unverifiedValidation.limitationCount -ne 2) {
        throw "Validation viewer did not preserve report checks and limitations: $($unverifiedValidation | ConvertTo-Json -Compress)"
    }
    if ([int]$unverifiedValidation.failedRequiredCount -ne 0) { throw 'Validation viewer reported a failed required check for the valid fixture.' }

    $receipt=[ordered]@{
        schemaVersion=1
        verified=$true
        reportSha256=(Get-FileHash -LiteralPath $validationReportPath -Algorithm SHA256).Hash.ToLowerInvariant()
        verifiedAtUtc=[DateTime]::UtcNow.ToString('o')
        verifier='desktop-ci-fixture'
    }
    [IO.File]::WriteAllText($validationReceiptPath,($receipt | ConvertTo-Json -Depth 5)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
    $verifiedValidation=Invoke-NrValidationViewerSelfTest -Executable $validationPath -PackageRoot $root
    if ([string]$verifiedValidation.trustState -ne 'attestation-receipt-matched') { throw "Validation viewer did not accept the matching local receipt: $($verifiedValidation.trustState)." }
} finally {
    Remove-Item -LiteralPath $validationReportPath,$validationReceiptPath -Force -ErrorAction SilentlyContinue
}

$traySource=Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'native/NexRoute.Tray/Program.cs') -Raw -Encoding UTF8
foreach ($token in @('Open Dashboard','NexRoute.Dashboard.exe','notifyIcon.DoubleClick','--root')) {
    if ($traySource -notmatch [regex]::Escape($token)) { throw "Tray source does not expose dashboard token: $token" }
}
$dashboardSource=Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'native/NexRoute.Dashboard/Program.cs') -Raw -Encoding UTF8
foreach ($token in @('System.Windows.Forms.DataVisualization.Charting','ScaleView.Zoomable','ChartMouseWheel','Light','Dark','AccentNames','strategy-lab','ui-settings.json')) {
    if ($dashboardSource -notmatch [regex]::Escape($token)) { throw "Dashboard source does not expose required UI behavior: $token" }
}
$validationSource=Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'native/NexRoute.Validation/Program.cs') -Raw -Encoding UTF8
foreach ($token in @('NexRoute Validation Viewer','passed-with-limitations','experimental','unsupported','attestation-receipt-matched','release-validation.json')) {
    if ($validationSource -notmatch [regex]::Escape($token)) { throw "Validation viewer source does not expose required claim-safety behavior: $token" }
}

[pscustomobject]@{
    TrayAssembly=[string]$trayAssembly.Name
    TraySha256=(Get-FileHash -LiteralPath $trayPath -Algorithm SHA256).Hash.ToLowerInvariant()
    DashboardAssembly=[string]$dashboardAssembly.Name
    DashboardSha256=(Get-FileHash -LiteralPath $dashboardPath -Algorithm SHA256).Hash.ToLowerInvariant()
    DashboardSelfTestExitCode=0
    FixtureRunCount=[int]$report.runCount
    FixtureResultCount=[int]$report.resultCount
    ValidationAssembly=[string]$validationAssembly.Name
    ValidationSha256=(Get-FileHash -LiteralPath $validationPath -Algorithm SHA256).Hash.ToLowerInvariant()
    ValidationSelfTestExitCode=0
    ValidationTrustState=[string]$verifiedValidation.trustState
    ValidationCheckCount=[int]$verifiedValidation.checkCount
    ValidationLimitationCount=[int]$verifiedValidation.limitationCount
}
