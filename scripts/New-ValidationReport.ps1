[CmdletBinding()]
param(
    [ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version,
    [string]$OutputDirectory = (Join-Path (Get-Location) 'artifacts'),
    [string]$PackageSha256,
    [string]$UpstreamSha256,
    [int]$PatchTargetCount = 0,
    [int]$StrategyCount = 0,
    [int]$ServiceCount = 0,
    [bool]$NativeTrayIncluded = $false,
    [int]$NativeTrayExitCode = -1,
    [bool]$NativeDashboardIncluded = $false,
    [int]$NativeDashboardExitCode = -1,
    [string]$NativeDashboardSha256,
    [bool]$NativeValidationIncluded = $false,
    [int]$NativeValidationExitCode = -1,
    [string]$NativeValidationSha256,
    [int]$NotificationContractExitCode = -1,
    [string]$NotificationContractEvidence,
    [bool]$PortableAttestationVerifierIncluded = $false,
    [bool]$DotResolverIncluded = $false,
    [ValidateSet('passed','experimental','unsupported','failed')]
    [string]$Ipv6RuntimeStatus = 'experimental',
    [switch]$NoMain
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-NrValidationText {
    param([AllowNull()][AllowEmptyString()][object]$Value,[string]$Fallback = 'unknown')
    if ($null -eq $Value) { return $Fallback }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $Fallback }
    return $text.Trim()
}

function Test-NrValidationWindows {
    try {
        return [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
            [Runtime.InteropServices.OSPlatform]::Windows
        )
    } catch {
        return $env:OS -eq 'Windows_NT'
    }
}

function Get-NrValidationEnvironment {
    $runningOnWindows = Test-NrValidationWindows
    $isAdministrator = $false
    if ($runningOnWindows) {
        try {
            $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
            $principal = New-Object Security.Principal.WindowsPrincipal($identity)
            $isAdministrator = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        } catch { }
    }

    $osDescription = 'unknown'
    $osArchitecture = if ([Environment]::Is64BitOperatingSystem) { 'X64' } else { 'X86' }
    $processArchitecture = if ([Environment]::Is64BitProcess) { 'X64' } else { 'X86' }
    try {
        $osDescription = [Runtime.InteropServices.RuntimeInformation]::OSDescription
        $osArchitecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
        $processArchitecture = [Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
    } catch { }

    $windowsBuild = $null
    if ($runningOnWindows) {
        try { $windowsBuild = [Environment]::OSVersion.Version.Build } catch { }
    }

    [pscustomobject][ordered]@{
        isWindows = $runningOnWindows
        isAdministrator = $isAdministrator
        osDescription = Get-NrValidationText $osDescription
        osArchitecture = Get-NrValidationText $osArchitecture
        processArchitecture = Get-NrValidationText $processArchitecture
        windowsBuild = $windowsBuild
        powershellVersion = $PSVersionTable.PSVersion.ToString()
        powershellEdition = Get-NrValidationText $PSVersionTable.PSEdition
        runnerName = Get-NrValidationText $env:RUNNER_NAME
        runnerEnvironment = Get-NrValidationText $env:RUNNER_ENVIRONMENT
    }
}

function Invoke-NrNotificationContractSelfTest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version,
        [Parameter(Mandatory=$true)][string]$ArtifactsDirectory
    )

    if (-not (Test-NrValidationWindows)) {
        throw 'The packaged notification contract requires a Windows runner.'
    }

    $artifactRoot = [IO.Path]::GetFullPath($ArtifactsDirectory)
    $archivePath = Join-Path $artifactRoot "NexRoute-$Version-win-x64.zip"
    if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
        throw "Release archive is missing for notification validation: $archivePath"
    }

    $extractRoot = Join-Path ([IO.Path]::GetTempPath()) ('nexroute-notification-contract-' + [guid]::NewGuid().ToString('N'))
    try {
        Expand-Archive -LiteralPath $archivePath -DestinationPath $extractRoot -Force
        $brokers = @(Get-ChildItem -LiteralPath $extractRoot -Filter 'nexroute-notifications.ps1' -File -Recurse | Where-Object {
            $_.FullName.Replace('/','\') -match '\\.service\\next\\nexroute-notifications\.ps1$'
        })
        if ($brokers.Count -ne 1) {
            throw "Expected one packaged notification broker, found $($brokers.Count)."
        }

        $brokerPath = $brokers[0].FullName
        $packageRoot = $brokers[0].Directory.Parent.Parent.FullName
        $notifierPath = Join-Path $packageRoot '.service/native/NexRoute.Notifier.exe'
        if (-not (Test-Path -LiteralPath $notifierPath -PathType Leaf)) {
            throw "Packaged native notifier is missing: $notifierPath"
        }
        $notifierAssembly = [Reflection.AssemblyName]::GetAssemblyName($notifierPath)
        if ([string]$notifierAssembly.Name -ne 'NexRoute.Notifier') {
            throw "Unexpected packaged notifier assembly: $($notifierAssembly.Name)"
        }

        . $brokerPath
        $toastResult = Send-NrNotification -Root $packageRoot -Title 'NexRoute notification contract' `
            -Message 'Toast delivery fixture' -Level Info -ToastRunner {
                param($payload)
                if ([string]$payload.level -ne 'info' -or [int]$payload.timeoutMilliseconds -ne 5000) {
                    throw 'Toast payload normalization failed.'
                }
                if ([string]$payload.xml -notmatch 'ToastGeneric') { throw 'Toast payload is not ToastGeneric XML.' }
                [pscustomobject]@{ delivered=$true; setting='Enabled' }
            } -Runner { throw 'Native fallback must not run after confirmed toast delivery.' }
        if ([string]$toastResult.channel -ne 'windows-toast') {
            throw "Expected windows-toast, got $($toastResult.channel)."
        }
        if ((@($toastResult.attempts) -join ',') -ne 'windows-toast') {
            throw "Unexpected toast attempt order: $(@($toastResult.attempts) -join ',')."
        }

        $fallbackResult = Send-NrNotification -Root $packageRoot -Title 'NexRoute notification contract' `
            -Message 'Policy fallback fixture' -Level Warning -ToastRunner {
                [pscustomobject]@{ delivered=$false; setting='DisabledByGroupPolicy' }
            } -Runner {
                param($executable,$arguments)
                if ([IO.Path]::GetFullPath($executable) -ne [IO.Path]::GetFullPath($notifierPath)) {
                    throw 'Fallback used an unexpected notifier executable.'
                }
                if ($arguments -notcontains '--title64' -or $arguments -notcontains '--message64') {
                    throw 'Fallback notifier arguments are incomplete.'
                }
                [pscustomobject]@{ exitCode=0; processId=4242 }
            }
        if ([string]$fallbackResult.channel -ne 'native-balloon') {
            throw "Expected native-balloon fallback, got $($fallbackResult.channel)."
        }
        if ((@($fallbackResult.attempts) -join ',') -ne 'windows-toast,native-balloon') {
            throw "Unexpected fallback attempt order: $(@($fallbackResult.attempts) -join ',')."
        }
        if ([string]$fallbackResult.error -notmatch 'DisabledByGroupPolicy') {
            throw 'The policy-disabled reason was not preserved in notification history.'
        }

        [pscustomobject][ordered]@{
            ExitCode = 0
            Evidence = 'toast=windows-toast; policyFallback=native-balloon; attempts=windows-toast,native-balloon; setting=DisabledByGroupPolicy'
            ToastChannel = [string]$toastResult.channel
            FallbackChannel = [string]$fallbackResult.channel
        }
    } finally {
        Remove-Item -LiteralPath $extractRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function New-NrValidationCheck {
    param(
        [Parameter(Mandatory=$true)][string]$Id,
        [Parameter(Mandatory=$true)][string]$Category,
        [Parameter(Mandatory=$true)]
        [ValidateSet('passed','experimental','unsupported','failed')][string]$Status,
        [Parameter(Mandatory=$true)][bool]$Required,
        [Parameter(Mandatory=$true)][string]$Summary,
        [AllowNull()][string]$Evidence,
        [AllowNull()][string]$Limitation
    )
    [pscustomobject][ordered]@{
        id = $Id
        category = $Category
        status = $Status
        required = $Required
        summary = $Summary
        evidence = $Evidence
        limitation = $Limitation
    }
}

function New-NrValidationReportDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][ValidatePattern('^\d+\.\d+\.\d+$')][string]$Version,
        [string]$PackageSha256,
        [string]$UpstreamSha256,
        [int]$PatchTargetCount,
        [int]$StrategyCount,
        [int]$ServiceCount,
        [bool]$NativeTrayIncluded,
        [int]$NativeTrayExitCode,
        [bool]$NativeDashboardIncluded,
        [int]$NativeDashboardExitCode,
        [string]$NativeDashboardSha256,
        [bool]$NativeValidationIncluded,
        [int]$NativeValidationExitCode,
        [string]$NativeValidationSha256,
        [int]$NotificationContractExitCode = -1,
        [string]$NotificationContractEvidence,
        [bool]$PortableAttestationVerifierIncluded,
        [bool]$DotResolverIncluded,
        [ValidateSet('passed','experimental','unsupported','failed')]
        [string]$Ipv6RuntimeStatus = 'experimental'
    )

    $environment = Get-NrValidationEnvironment
    $checks = @()
    $add = {
        param($Id,$Category,$Status,$Required,$Summary,$Evidence,$Limitation)
        New-NrValidationCheck -Id $Id -Category $Category -Status $Status -Required $Required `
            -Summary $Summary -Evidence $Evidence -Limitation $Limitation
    }

    $packageOk = $PackageSha256 -match '^[0-9a-fA-F]{64}$'
    $checks += & $add 'package.sha256' 'release' $(if ($packageOk) {'passed'} else {'failed'}) $true `
        'The release package has a verified SHA-256 digest.' `
        $(if ($packageOk) {$PackageSha256.ToLowerInvariant()} else {'Missing or invalid package digest.'}) `
        $(if ($packageOk) {$null} else {'The release must not be published without a verified package digest.'})

    $upstreamOk = $UpstreamSha256 -match '^[0-9a-fA-F]{64}$'
    $checks += & $add 'upstream.pin' 'supply-chain' $(if ($upstreamOk) {'passed'} else {'failed'}) $true `
        'The pinned upstream archive identity is recorded.' `
        $(if ($upstreamOk) {$UpstreamSha256.ToLowerInvariant()} else {'Missing or invalid upstream digest.'}) `
        $(if ($upstreamOk) {$null} else {'The source archive cannot be reproduced or verified.'})

    $patchesOk = $PatchTargetCount -eq 23
    $checks += & $add 'patches.contract' 'supply-chain' $(if ($patchesOk) {'passed'} else {'failed'}) $true `
        'All tracked upstream patch targets were applied.' "$PatchTargetCount tracked patch target(s)." `
        $(if ($patchesOk) {$null} else {'Expected exactly 23 tracked patch targets.'})

    $catalogsOk = $StrategyCount -gt 0 -and $ServiceCount -gt 0
    $checks += & $add 'package.catalogs' 'package' $(if ($catalogsOk) {'passed'} else {'failed'}) $true `
        'The verified package contains strategy and service catalogs.' "$StrategyCount strategies; $ServiceCount services." `
        $(if ($catalogsOk) {$null} else {'The package catalogs are empty or were not verified.'})

    $trayOk = $NativeTrayIncluded -and $NativeTrayExitCode -eq 0
    $checks += & $add 'native-tray.self-test' 'desktop' $(if ($trayOk) {'passed'} else {'failed'}) $true `
        'The compiled native tray controller passed its deterministic self-test.' `
        "included=$NativeTrayIncluded; exitCode=$NativeTrayExitCode" `
        $(if ($trayOk) {$null} else {'The native tray binary is missing or its self-test failed.'})

    $dashboardHashOk = $NativeDashboardSha256 -match '^[0-9a-fA-F]{64}$'
    $dashboardOk = $NativeDashboardIncluded -and $NativeDashboardExitCode -eq 0 -and $dashboardHashOk
    $checks += & $add 'native-dashboard.self-test' 'desktop' $(if ($dashboardOk) {'passed'} else {'failed'}) $true `
        'The compiled native dashboard loaded Strategy Lab history and passed its deterministic self-test.' `
        "included=$NativeDashboardIncluded; exitCode=$NativeDashboardExitCode; sha256=$(Get-NrValidationText $NativeDashboardSha256)" `
        $(if ($dashboardOk) {$null} else {'The native dashboard is missing, has no verified digest or failed to read its history fixture.'})

    $validationHashOk = $NativeValidationSha256 -match '^[0-9a-fA-F]{64}$'
    $validationOk = $NativeValidationIncluded -and $NativeValidationExitCode -eq 0 -and $validationHashOk
    $checks += & $add 'native-validation.self-test' 'desktop' $(if ($validationOk) {'passed'} else {'failed'}) $true `
        'The native Validation Viewer parsed claim statuses and distinguished unverified JSON from a digest-matched local attestation receipt.' `
        "included=$NativeValidationIncluded; exitCode=$NativeValidationExitCode; sha256=$(Get-NrValidationText $NativeValidationSha256)" `
        $(if ($validationOk) {$null} else {'The release must not publish without a working UI that exposes experimental and unsupported capability claims.'})

    $notificationOk = $NotificationContractExitCode -eq 0
    $checks += & $add 'notifications.delivery-contract' 'desktop' $(if ($notificationOk) {'passed'} else {'failed'}) $true `
        'The extracted release package proved ToastGeneric delivery and deterministic native fallback for a policy-disabled toast channel.' `
        $(if ($notificationOk) {Get-NrValidationText $NotificationContractEvidence 'toast=windows-toast; policyFallback=native-balloon'} else {Get-NrValidationText $NotificationContractEvidence "exitCode=$NotificationContractExitCode"}) `
        $(if ($notificationOk) {$null} else {'The release must not publish when notification delivery can silently disappear or skip its native fallback.'})

    $checks += & $add 'attestation.portable-verifier' 'supply-chain' `
        $(if ($PortableAttestationVerifierIncluded) {'passed'} else {'failed'}) $true `
        'The package includes the pinned portable attestation verifier.' `
        "included=$PortableAttestationVerifierIncluded" `
        $(if ($PortableAttestationVerifierIncluded) {$null} else {'Release provenance cannot be verified without an external installation.'})

    $checks += & $add 'dns.dot-resolver' 'networking' $(if ($DotResolverIncluded) {'passed'} else {'failed'}) $true `
        'The package includes the pinned transactional DNS-over-TLS resolver.' "included=$DotResolverIncluded" `
        $(if ($DotResolverIncluded) {$null} else {'DNS-over-TLS must not be advertised without the bundled resolver.'})

    $checks += & $add 'windows.runner' 'environment' $(if ($environment.isWindows) {'passed'} else {'unsupported'}) $false `
        'The validation report records the Windows execution environment.' $environment.osDescription `
        $(if ($environment.isWindows) {$null} else {'Windows-only integration behavior was not exercised on this runner.'})

    $checks += & $add 'native-tray.interactive' 'desktop' 'experimental' $false `
        'Interactive tray rendering, startup registration and crash recovery require a signed-in Windows desktop session.' `
        'Automated binary self-test passed; no interactive desktop session is available in hosted CI.' `
        'Validate on Windows 10 and Windows 11 with Explorer and notifications enabled and disabled.'

    $checks += & $add 'notifications.interactive' 'desktop' 'experimental' $false `
        'Actual toast and balloon rendering still require a signed-in Windows desktop session and user notification settings.' `
        'The packaged broker proved payload construction, policy detection, attempt ordering and native fallback without claiming visible delivery.' `
        'Validate visible toast and balloon rendering on Windows 10 and Windows 11 with notifications enabled, user-disabled and policy-disabled.'

    $checks += & $add 'native-dashboard.interactive' 'desktop' 'experimental' $false `
        'Dashboard theme switching, accent colors, chart zoom and mouse interaction require a signed-in Windows desktop session.' `
        'The dashboard self-test loaded real Strategy Lab fixture data and verified the compiled assembly.' `
        'Validate light/dark themes, accents and chart interaction on Windows 10 and Windows 11.'

    $dohAvailable = $false
    if ($environment.isWindows) {
        $dohAvailable = $null -ne (Get-Command Set-DnsClientDohServerAddress -ErrorAction SilentlyContinue)
    }
    $checks += & $add 'dns.doh-platform' 'networking' $(if ($dohAvailable) {'experimental'} else {'unsupported'}) $false `
        'Windows encrypted DNS capability is reported without claiming a live resolver path.' `
        "Set-DnsClientDohServerAddress available=$dohAvailable" `
        $(if ($dohAvailable) {'A live adapter and resolver verification is still required.'} else {'This Windows environment does not expose the required DoH cmdlet.'})

    $checks += & $add 'network.adapter-events' 'networking' `
        $(if ($environment.isWindows) {'experimental'} else {'unsupported'}) $false `
        'Adapter arrival, removal and profile migration require physical or virtual adapter events.' `
        'Synthetic event and restart reconciliation tests are part of the automated suite.' `
        'Validate with Ethernet, Wi-Fi and public/private profile transitions on Windows.'

    $checks += & $add 'runtime.ipv4-live' 'runtime' 'experimental' $false `
        'IPv4 worker plans are behavior-tested, but a live ISP DPI path is environment-dependent.' `
        'Synthetic worker and package smoke tests passed.' `
        'No hosted CI runner can prove bypass behavior for a specific ISP.'

    $checks += & $add 'runtime.ipv6-live' 'runtime' $Ipv6RuntimeStatus $false `
        'IPv6 worker support is reported separately from CIDR parsing and AAAA resolution.' `
        'IPv4-only, IPv6-only and dual-stack synthetic worker tests are part of the automated suite.' `
        $(if ($Ipv6RuntimeStatus -eq 'passed') {$null} else {'Validate against an IPv6-capable Windows host and network before claiming full IPv6 bypass.'})

    $failedRequired = @($checks | Where-Object { $_.required -and $_.status -eq 'failed' })
    $limitations = @($checks | Where-Object { $_.status -in @('experimental','unsupported','failed') } | ForEach-Object {
        [pscustomobject][ordered]@{ id = $_.id; status = $_.status; limitation = $_.limitation }
    })
    $overall = if ($failedRequired.Count -gt 0) {'failed'} elseif ($limitations.Count -gt 0) {'passed-with-limitations'} else {'passed'}

    [pscustomobject][ordered]@{
        schemaVersion = 1
        product = 'NexRoute'
        version = $Version
        overallStatus = $overall
        generatedAtUtc = [DateTime]::UtcNow.ToString('o')
        provenance = [pscustomobject][ordered]@{
            repository = Get-NrValidationText $env:GITHUB_REPOSITORY 'Onmaynec/NexRoute'
            commit = Get-NrValidationText $env:GITHUB_SHA
            workflow = Get-NrValidationText $env:GITHUB_WORKFLOW
            runId = Get-NrValidationText $env:GITHUB_RUN_ID
            runAttempt = Get-NrValidationText $env:GITHUB_RUN_ATTEMPT
        }
        environment = $environment
        release = [pscustomobject][ordered]@{
            packageSha256 = Get-NrValidationText $PackageSha256
            upstreamSha256 = Get-NrValidationText $UpstreamSha256
            patchTargetCount = $PatchTargetCount
            strategyCount = $StrategyCount
            serviceCount = $ServiceCount
            nativeDashboardSha256 = Get-NrValidationText $NativeDashboardSha256
            nativeValidationSha256 = Get-NrValidationText $NativeValidationSha256
        }
        checks = [object[]]$checks
        limitations = [object[]]$limitations
    }
}

function ConvertTo-NrValidationMarkdown {
    param([Parameter(Mandatory=$true)][object]$Report)
    $lines = @(
        "# NexRoute $($Report.version) validation report",'',
        "- Overall status: **$($Report.overallStatus)**",
        "- Generated (UTC): $($Report.generatedAtUtc)",
        "- Repository: $($Report.provenance.repository)",
        "- Commit: $($Report.provenance.commit)",
        "- Workflow run: $($Report.provenance.runId) (attempt $($Report.provenance.runAttempt))",
        "- OS: $($Report.environment.osDescription)",
        "- PowerShell: $($Report.environment.powershellVersion)",'','## Checks','',
        '| Check | Status | Required | Evidence | Limitation |','|---|---|---:|---|---|'
    )
    foreach ($check in @($Report.checks)) {
        $summary = (Get-NrValidationText $check.summary).Replace('|','\|').Replace("`r",' ').Replace("`n",' ')
        $evidence = (Get-NrValidationText $check.evidence '-').Replace('|','\|').Replace("`r",' ').Replace("`n",' ')
        $limitation = (Get-NrValidationText $check.limitation '-').Replace('|','\|').Replace("`r",' ').Replace("`n",' ')
        $lines += "| $($check.id) — $summary | **$($check.status)** | $($check.required) | $evidence | $limitation |"
    }
    $lines += @(
        '','## Release identities','',
        "- Package SHA-256: $($Report.release.packageSha256)",
        "- Upstream SHA-256: $($Report.release.upstreamSha256)",
        "- Patch targets: $($Report.release.patchTargetCount)",
        "- Strategies: $($Report.release.strategyCount)",
        "- Services: $($Report.release.serviceCount)",
        "- Native dashboard SHA-256: $($Report.release.nativeDashboardSha256)",
        "- Native validation viewer SHA-256: $($Report.release.nativeValidationSha256)",'',
        'This report is generated by the release workflow and is included in the same GitHub artifact attestation as the release package. Experimental and unsupported rows are explicit limitations, not successful hardware validation.'
    )
    ($lines -join [Environment]::NewLine) + [Environment]::NewLine
}

function Write-NrValidationUtf8File {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$Content)
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $temporaryPath = "$Path.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temporaryPath,$Content,(New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Write-NrValidationReport {
    param([Parameter(Mandatory=$true)][object]$Report,[Parameter(Mandatory=$true)][string]$OutputDirectory)
    $jsonPath = Join-Path $OutputDirectory "NexRoute-$($Report.version)-validation.json"
    $markdownPath = Join-Path $OutputDirectory "NexRoute-$($Report.version)-validation.md"
    Write-NrValidationUtf8File $jsonPath (($Report | ConvertTo-Json -Depth 10) + [Environment]::NewLine)
    Write-NrValidationUtf8File $markdownPath (ConvertTo-NrValidationMarkdown $Report)
    [pscustomobject][ordered]@{
        OverallStatus = $Report.overallStatus
        JsonPath = (Resolve-Path -LiteralPath $jsonPath).Path
        MarkdownPath = (Resolve-Path -LiteralPath $markdownPath).Path
        JsonSha256 = (Get-FileHash -LiteralPath $jsonPath -Algorithm SHA256).Hash.ToLowerInvariant()
        MarkdownSha256 = (Get-FileHash -LiteralPath $markdownPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

if (-not $NoMain) {
    if ([string]::IsNullOrWhiteSpace($Version)) { throw 'Version is required.' }
    if ($NotificationContractExitCode -lt 0) {
        try {
            $notificationContract = Invoke-NrNotificationContractSelfTest -Version $Version -ArtifactsDirectory $OutputDirectory
            $NotificationContractExitCode = [int]$notificationContract.ExitCode
            $NotificationContractEvidence = [string]$notificationContract.Evidence
        } catch {
            $NotificationContractExitCode = 1
            $NotificationContractEvidence = $_.Exception.Message
        }
    }
    $report = New-NrValidationReportDocument -Version $Version -PackageSha256 $PackageSha256 `
        -UpstreamSha256 $UpstreamSha256 -PatchTargetCount $PatchTargetCount -StrategyCount $StrategyCount `
        -ServiceCount $ServiceCount -NativeTrayIncluded $NativeTrayIncluded -NativeTrayExitCode $NativeTrayExitCode `
        -NativeDashboardIncluded $NativeDashboardIncluded -NativeDashboardExitCode $NativeDashboardExitCode `
        -NativeDashboardSha256 $NativeDashboardSha256 `
        -NativeValidationIncluded $NativeValidationIncluded -NativeValidationExitCode $NativeValidationExitCode `
        -NativeValidationSha256 $NativeValidationSha256 `
        -NotificationContractExitCode $NotificationContractExitCode `
        -NotificationContractEvidence $NotificationContractEvidence `
        -PortableAttestationVerifierIncluded $PortableAttestationVerifierIncluded `
        -DotResolverIncluded $DotResolverIncluded -Ipv6RuntimeStatus $Ipv6RuntimeStatus
    $result = Write-NrValidationReport $report $OutputDirectory
    if ($result.OverallStatus -eq 'failed') {
        throw "NexRoute validation report contains failed required checks: $($result.JsonPath)"
    }
    $result
}
