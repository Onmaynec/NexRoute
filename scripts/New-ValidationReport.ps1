[CmdletBinding()]
param(
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version,
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
    [bool]$PortableAttestationVerifierIncluded = $false,
    [bool]$DotResolverIncluded = $false,
    [ValidateSet('passed','experimental','unsupported','failed')]
    [string]$Ipv6RuntimeStatus = 'experimental',
    [switch]$NoMain
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-NrValidationText {
    [CmdletBinding()]
    param(
        [AllowNull()][AllowEmptyString()][object]$Value,
        [string]$Fallback = 'unknown'
    )
    if ($null -eq $Value) { return $Fallback }
    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) { return $Fallback }
    return $text.Trim()
}

function Test-NrValidationWindows {
    [CmdletBinding()]
    param()
    try {
        return [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
            [Runtime.InteropServices.OSPlatform]::Windows
        )
    } catch {
        return $env:OS -eq 'Windows_NT'
    }
}

function Get-NrValidationEnvironment {
    [CmdletBinding()]
    param()

    $isWindows = Test-NrValidationWindows
    $isAdministrator = $false
    if ($isWindows) {
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
    if ($isWindows) {
        try { $windowsBuild = [Environment]::OSVersion.Version.Build } catch { }
    }

    return [pscustomobject][ordered]@{
        isWindows = $isWindows
        isAdministrator = $isAdministrator
        osDescription = Get-NrValidationText -Value $osDescription
        osArchitecture = Get-NrValidationText -Value $osArchitecture
        processArchitecture = Get-NrValidationText -Value $processArchitecture
        windowsBuild = $windowsBuild
        powershellVersion = $PSVersionTable.PSVersion.ToString()
        powershellEdition = Get-NrValidationText -Value $PSVersionTable.PSEdition
        runnerName = Get-NrValidationText -Value $env:RUNNER_NAME
        runnerEnvironment = Get-NrValidationText -Value $env:RUNNER_ENVIRONMENT
    }
}

function New-NrValidationCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Id,
        [Parameter(Mandatory=$true)][string]$Category,
        [Parameter(Mandatory=$true)]
        [ValidateSet('passed','experimental','unsupported','failed')]
        [string]$Status,
        [Parameter(Mandatory=$true)][bool]$Required,
        [Parameter(Mandatory=$true)][string]$Summary,
        [AllowNull()][string]$Evidence,
        [AllowNull()][string]$Limitation
    )

    return [pscustomobject][ordered]@{
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
        [Parameter(Mandatory=$true)]
        [ValidatePattern('^\d+\.\d+\.\d+$')]
        [string]$Version,
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
        [bool]$PortableAttestationVerifierIncluded,
        [bool]$DotResolverIncluded,
        [ValidateSet('passed','experimental','unsupported','failed')]
        [string]$Ipv6RuntimeStatus = 'experimental'
    )

    $environment = Get-NrValidationEnvironment
    $checks = @()

    $packageHashValid = $PackageSha256 -match '^[0-9a-fA-F]{64}$'
    $checks += New-NrValidationCheck -Id 'package.sha256' -Category 'release' `
        -Status $(if ($packageHashValid) { 'passed' } else { 'failed' }) -Required $true `
        -Summary 'The release package has a verified SHA-256 digest.' `
        -Evidence $(if ($packageHashValid) { $PackageSha256.ToLowerInvariant() } else { 'Missing or invalid package digest.' }) `
        -Limitation $(if ($packageHashValid) { $null } else { 'The release must not be published without a verified package digest.' })

    $upstreamHashValid = $UpstreamSha256 -match '^[0-9a-fA-F]{64}$'
    $checks += New-NrValidationCheck -Id 'upstream.pin' -Category 'supply-chain' `
        -Status $(if ($upstreamHashValid) { 'passed' } else { 'failed' }) -Required $true `
        -Summary 'The pinned upstream archive identity is recorded.' `
        -Evidence $(if ($upstreamHashValid) { $UpstreamSha256.ToLowerInvariant() } else { 'Missing or invalid upstream digest.' }) `
        -Limitation $(if ($upstreamHashValid) { $null } else { 'The source archive cannot be reproduced or verified.' })

    $patchesValid = $PatchTargetCount -eq 23
    $checks += New-NrValidationCheck -Id 'patches.contract' -Category 'supply-chain' `
        -Status $(if ($patchesValid) { 'passed' } else { 'failed' }) -Required $true `
        -Summary 'All tracked upstream patch targets were applied.' `
        -Evidence "$PatchTargetCount tracked patch target(s)." `
        -Limitation $(if ($patchesValid) { $null } else { 'Expected exactly 23 tracked patch targets.' })

    $catalogsValid = $StrategyCount -gt 0 -and $ServiceCount -gt 0
    $checks += New-NrValidationCheck -Id 'package.catalogs' -Category 'package' `
        -Status $(if ($catalogsValid) { 'passed' } else { 'failed' }) -Required $true `
        -Summary 'The verified package contains strategy and service catalogs.' `
        -Evidence "$StrategyCount strategies; $ServiceCount services." `
        -Limitation $(if ($catalogsValid) { $null } else { 'The package catalogs are empty or were not verified.' })

    $trayValid = $NativeTrayIncluded -and $NativeTrayExitCode -eq 0
    $checks += New-NrValidationCheck -Id 'native-tray.self-test' -Category 'desktop' `
        -Status $(if ($trayValid) { 'passed' } else { 'failed' }) -Required $true `
        -Summary 'The compiled native tray controller passed its deterministic self-test.' `
        -Evidence "included=$NativeTrayIncluded; exitCode=$NativeTrayExitCode" `
        -Limitation $(if ($trayValid) { $null } else { 'The native tray binary is missing or its self-test failed.' })

    $dashboardHashValid = $NativeDashboardSha256 -match '^[0-9a-fA-F]{64}$'
    $dashboardValid = $NativeDashboardIncluded -and $NativeDashboardExitCode -eq 0 -and $dashboardHashValid
    $checks += New-NrValidationCheck -Id 'native-dashboard.self-test' -Category 'desktop' `
        -Status $(if ($dashboardValid) { 'passed' } else { 'failed' }) -Required $true `
        -Summary 'The compiled native dashboard loaded Strategy Lab history and passed its deterministic self-test.' `
        -Evidence "included=$NativeDashboardIncluded; exitCode=$NativeDashboardExitCode; sha256=$(Get-NrValidationText -Value $NativeDashboardSha256)" `
        -Limitation $(if ($dashboardValid) { $null } else { 'The native dashboard is missing, has no verified digest or failed to read its history fixture.' })

    $checks += New-NrValidationCheck -Id 'attestation.portable-verifier' -Category 'supply-chain' `
        -Status $(if ($PortableAttestationVerifierIncluded) { 'passed' } else { 'failed' }) -Required $true `
        -Summary 'The package includes the pinned portable attestation verifier.' `
        -Evidence "included=$PortableAttestationVerifierIncluded" `
        -Limitation $(if ($PortableAttestationVerifierIncluded) { $null } else { 'Release provenance cannot be verified without an external installation.' })

    $checks += New-NrValidationCheck -Id 'dns.dot-resolver' -Category 'networking' `
        -Status $(if ($DotResolverIncluded) { 'passed' } else { 'failed' }) -Required $true `
        -Summary 'The package includes the pinned transactional DNS-over-TLS resolver.' `
        -Evidence "included=$DotResolverIncluded" `
        -Limitation $(if ($DotResolverIncluded) { $null } else { 'DNS-over-TLS must not be advertised without the bundled resolver.' })

    $checks += New-NrValidationCheck -Id 'windows.runner' -Category 'environment' `
        -Status $(if ($environment.isWindows) { 'passed' } else { 'unsupported' }) -Required $false `
        -Summary 'The validation report records the Windows execution environment.' `
        -Evidence $environment.osDescription `
        -Limitation $(if ($environment.isWindows) { $null } else { 'Windows-only integration behavior was not exercised on this runner.' })

    $checks += New-NrValidationCheck -Id 'native-tray.interactive' -Category 'desktop' `
        -Status 'experimental' -Required $false `
        -Summary 'Interactive tray rendering, startup registration and crash recovery require a signed-in Windows desktop session.' `
        -Evidence 'Automated binary self-test passed; no interactive desktop session is available in hosted CI.' `
        -Limitation 'Validate on Windows 10 and Windows 11 with Explorer and notifications enabled and disabled.'

    $checks += New-NrValidationCheck -Id 'native-dashboard.interactive' -Category 'desktop' `
        -Status 'experimental' -Required $false `
        -Summary 'Dashboard theme switching, accent colors, chart zoom and mouse interaction require a signed-in Windows desktop session.' `
        -Evidence 'The dashboard self-test loaded real Strategy Lab fixture data and verified the compiled assembly.' `
        -Limitation 'Validate light/dark themes, accents and chart interaction on Windows 10 and Windows 11.'

    $dohAvailable = $false
    if ($environment.isWindows) {
        $dohAvailable = $null -ne (Get-Command Set-DnsClientDohServerAddress -ErrorAction SilentlyContinue)
    }
    $checks += New-NrValidationCheck -Id 'dns.doh-platform' -Category 'networking' `
        -Status $(if ($dohAvailable) { 'experimental' } else { 'unsupported' }) -Required $false `
        -Summary 'Windows encrypted DNS capability is reported without claiming a live resolver path.' `
        -Evidence "Set-DnsClientDohServerAddress available=$dohAvailable" `
        -Limitation $(if ($dohAvailable) { 'A live adapter and resolver verification is still required.' } else { 'This Windows environment does not expose the required DoH cmdlet.' })

    $checks += New-NrValidationCheck -Id 'network.adapter-events' -Category 'networking' `
        -Status $(if ($environment.isWindows) { 'experimental' } else { 'unsupported' }) -Required $false `
        -Summary 'Adapter arrival, removal and profile migration require physical or virtual adapter events.' `
        -Evidence 'Synthetic event and restart reconciliation tests are part of the automated suite.' `
        -Limitation 'Validate with Ethernet, Wi-Fi and public/private profile transitions on Windows.'

    $checks += New-NrValidationCheck -Id 'runtime.ipv4-live' -Category 'runtime' `
        -Status 'experimental' -Required $false `
        -Summary 'IPv4 worker plans are behavior-tested, but a live ISP DPI path is environment-dependent.' `
        -Evidence 'Synthetic worker and package smoke tests passed.' `
        -Limitation 'No hosted CI runner can prove bypass behavior for a specific ISP.'

    $checks += New-NrValidationCheck -Id 'runtime.ipv6-live' -Category 'runtime' `
        -Status $Ipv6RuntimeStatus -Required $false `
        -Summary 'IPv6 worker support is reported separately from CIDR parsing and AAAA resolution.' `
        -Evidence 'IPv4-only, IPv6-only and dual-stack synthetic worker tests are part of the automated suite.' `
        -Limitation $(if ($Ipv6RuntimeStatus -eq 'passed') { $null } else { 'Validate against an IPv6-capable Windows host and network before claiming full IPv6 bypass.' })

    $requiredFailures = @($checks | Where-Object { $_.required -and $_.status -eq 'failed' })
    $limitations = @($checks | Where-Object { $_.status -in @('experimental','unsupported','failed') } | ForEach-Object {
        [pscustomobject][ordered]@{
            id = $_.id
            status = $_.status
            limitation = $_.limitation
        }
    })
    $overallStatus = if ($requiredFailures.Count -gt 0) {
        'failed'
    } elseif ($limitations.Count -gt 0) {
        'passed-with-limitations'
    } else {
        'passed'
    }

    return [pscustomobject][ordered]@{
        schemaVersion = 1
        product = 'NexRoute'
        version = $Version
        overallStatus = $overallStatus
        generatedAtUtc = [DateTime]::UtcNow.ToString('o')
        provenance = [pscustomobject][ordered]@{
            repository = Get-NrValidationText -Value $env:GITHUB_REPOSITORY -Fallback 'Onmaynec/NexRoute'
            commit = Get-NrValidationText -Value $env:GITHUB_SHA
            workflow = Get-NrValidationText -Value $env:GITHUB_WORKFLOW
            runId = Get-NrValidationText -Value $env:GITHUB_RUN_ID
            runAttempt = Get-NrValidationText -Value $env:GITHUB_RUN_ATTEMPT
        }
        environment = $environment
        release = [pscustomobject][ordered]@{
            packageSha256 = Get-NrValidationText -Value $PackageSha256
            upstreamSha256 = Get-NrValidationText -Value $UpstreamSha256
            patchTargetCount = $PatchTargetCount
            strategyCount = $StrategyCount
            serviceCount = $ServiceCount
            nativeDashboardSha256 = Get-NrValidationText -Value $NativeDashboardSha256
        }
        checks = [object[]]$checks
        limitations = [object[]]$limitations
    }
}

function ConvertTo-NrValidationMarkdown {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][object]$Report)

    $lines = @(
        "# NexRoute $($Report.version) validation report",
        '',
        "- Overall status: **$($Report.overallStatus)**",
        "- Generated (UTC): $($Report.generatedAtUtc)",
        "- Repository: $($Report.provenance.repository)",
        "- Commit: $($Report.provenance.commit)",
        "- Workflow run: $($Report.provenance.runId) (attempt $($Report.provenance.runAttempt))",
        "- OS: $($Report.environment.osDescription)",
        "- PowerShell: $($Report.environment.powershellVersion)",
        '',
        '## Checks',
        '',
        '| Check | Status | Required | Evidence | Limitation |',
        '|---|---|---:|---|---|'
    )

    foreach ($check in @($Report.checks)) {
        $summary = (Get-NrValidationText -Value $check.summary).Replace('|','\|').Replace("`r",' ').Replace("`n",' ')
        $evidence = (Get-NrValidationText -Value $check.evidence -Fallback '-').Replace('|','\|').Replace("`r",' ').Replace("`n",' ')
        $limitation = (Get-NrValidationText -Value $check.limitation -Fallback '-').Replace('|','\|').Replace("`r",' ').Replace("`n",' ')
        $lines += "| $($check.id) — $summary | **$($check.status)** | $($check.required) | $evidence | $limitation |"
    }

    $lines += @(
        '',
        '## Release identities',
        '',
        "- Package SHA-256: $($Report.release.packageSha256)",
        "- Upstream SHA-256: $($Report.release.upstreamSha256)",
        "- Patch targets: $($Report.release.patchTargetCount)",
        "- Strategies: $($Report.release.strategyCount)",
        "- Services: $($Report.release.serviceCount)",
        "- Native dashboard SHA-256: $($Report.release.nativeDashboardSha256)",
        '',
        'This report is generated by the release workflow and is included in the same GitHub artifact attestation as the release package. Experimental and unsupported rows are explicit limitations, not successful hardware validation.'
    )

    return ($lines -join [Environment]::NewLine) + [Environment]::NewLine
}

function Write-NrValidationUtf8File {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Content
    )

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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$Report,
        [Parameter(Mandatory=$true)][string]$OutputDirectory
    )

    $jsonPath = Join-Path $OutputDirectory "NexRoute-$($Report.version)-validation.json"
    $markdownPath = Join-Path $OutputDirectory "NexRoute-$($Report.version)-validation.md"
    Write-NrValidationUtf8File -Path $jsonPath -Content (($Report | ConvertTo-Json -Depth 10) + [Environment]::NewLine)
    Write-NrValidationUtf8File -Path $markdownPath -Content (ConvertTo-NrValidationMarkdown -Report $Report)

    return [pscustomobject][ordered]@{
        OverallStatus = $Report.overallStatus
        JsonPath = (Resolve-Path -LiteralPath $jsonPath).Path
        MarkdownPath = (Resolve-Path -LiteralPath $markdownPath).Path
        JsonSha256 = (Get-FileHash -LiteralPath $jsonPath -Algorithm SHA256).Hash.ToLowerInvariant()
        MarkdownSha256 = (Get-FileHash -LiteralPath $markdownPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

if (-not $NoMain) {
    if ([string]::IsNullOrWhiteSpace($Version)) { throw 'Version is required.' }

    $report = New-NrValidationReportDocument `
        -Version $Version `
        -PackageSha256 $PackageSha256 `
        -UpstreamSha256 $UpstreamSha256 `
        -PatchTargetCount $PatchTargetCount `
        -StrategyCount $StrategyCount `
        -ServiceCount $ServiceCount `
        -NativeTrayIncluded $NativeTrayIncluded `
        -NativeTrayExitCode $NativeTrayExitCode `
        -NativeDashboardIncluded $NativeDashboardIncluded `
        -NativeDashboardExitCode $NativeDashboardExitCode `
        -NativeDashboardSha256 $NativeDashboardSha256 `
        -PortableAttestationVerifierIncluded $PortableAttestationVerifierIncluded `
        -DotResolverIncluded $DotResolverIncluded `
        -Ipv6RuntimeStatus $Ipv6RuntimeStatus

    $result = Write-NrValidationReport -Report $report -OutputDirectory $OutputDirectory
    if ($result.OverallStatus -eq 'failed') {
        throw "NexRoute validation report contains failed required checks: $($result.JsonPath)"
    }
    $result
}
