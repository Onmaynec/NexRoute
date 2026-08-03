Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertFrom-NrLastJsonLine {
    param([object[]]$Output)
    foreach ($line in @($Output | Select-Object -Last 20 | Select-Object -Reverse)) {
        try { return ([string]$line | ConvertFrom-Json) } catch { }
    }
    throw 'NexRoute updater returned no valid JSON result.'
}

function Get-NrUpdaterPath {
    $path=Join-Path $script:NrService 'nexroute-updater.ps1'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Secure updater module is missing.' }
    return $path
}

function Get-NrAutoUpdateEnabled {
    return Test-Path -LiteralPath (Join-Path $script:NrRoot 'utils\check_updates.enabled') -PathType Leaf
}

function Set-NrAutoUpdateEnabled {
    param([bool]$Enabled)
    $path=Join-Path $script:NrRoot 'utils\check_updates.enabled'
    if ($Enabled) {
        $parent=Split-Path -Parent $path
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        [IO.File]::WriteAllText($path,"ENABLED`r`n",[Text.Encoding]::ASCII)
    } else {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
    Write-NrLog -Message 'Automatic update checks changed' -Data @{ enabled=$Enabled }
}

function Invoke-NrUpdaterJson {
    param([ValidateSet('Check','Install','Status','Rollback')][string]$Mode,[switch]$Force)
    $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Get-NrUpdaterPath),'-Mode',$Mode,'-Root',$script:NrRoot,'-Json')
    if ($Force) { $arguments += '-Force' }
    $output=& powershell.exe @arguments 2>&1
    $code=$LASTEXITCODE
    if ($code -ne 0) { throw (($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine) }
    return ConvertFrom-NrLastJsonLine -Output $output
}

function Invoke-NrPostUpdateHealthCheck {
    $results=New-Object 'System.Collections.Generic.List[object]'
    foreach ($target in @(
        [pscustomobject]@{ Name='Internet'; Uri='https://www.msftconnecttest.com/connecttest.txt' }
        [pscustomobject]@{ Name='YouTube'; Uri='https://www.youtube.com/generate_204' }
        [pscustomobject]@{ Name='Discord'; Uri='https://discord.com/api/v9/gateway' }
        [pscustomobject]@{ Name='Telegram'; Uri='https://api.telegram.org' }
    )) {
        $watch=[Diagnostics.Stopwatch]::StartNew()
        $ok=$false; $message=$null
        try {
            $response=Invoke-WebRequest -Uri $target.Uri -UseBasicParsing -TimeoutSec 10 -Headers @{ 'User-Agent'='NexRoute-Post-Update/0.6.0' }
            $ok=[int]$response.StatusCode -ge 200 -and [int]$response.StatusCode -lt 500
        } catch { $message=$_.Exception.Message }
        $watch.Stop()
        $results.Add([pscustomobject]@{ name=$target.Name; ok=$ok; latencyMs=[math]::Round($watch.Elapsed.TotalMilliseconds,2); message=$message })
    }
    return $results.ToArray()
}

function Invoke-NrCheckUpdate {
    Write-NrHeader -Title (T 'checkUpdate')
    Write-Host ('  ' + (T 'updateChecking') + '...') -ForegroundColor Cyan
    try {
        $check=Invoke-NrUpdaterJson -Mode Check
        if (-not [bool]$check.UpdateAvailable) {
            Show-NrMessage -Title (T 'checkUpdate') -Message ((T 'updateCurrent') + ' ' + [string]$check.CurrentVersion) -Color Green
            return
        }

        Write-NrHeader -Title (T 'checkUpdate')
        Write-Host ('  ' + (T 'updateAvailable')) -ForegroundColor Green
        Write-Host ('  Current: ' + [string]$check.CurrentVersion) -ForegroundColor Gray
        Write-Host ('  Latest : ' + [string]$check.LatestVersion) -ForegroundColor Cyan
        Write-Host ''
        if (-not (Confirm-NrY -Message (T 'confirmUpdate'))) {
            Show-NrMessage -Title (T 'checkUpdate') -Message (T 'updateCancelled') -Color Yellow
            return
        }

        Write-NrHeader -Title (T 'checkUpdate')
        Write-Host ('  ' + (T 'updateInstalling') + '...') -ForegroundColor Cyan
        $result=Invoke-NrUpdaterJson -Mode Install
        if ($result.PackageSha256) {
            $script:NrState.lastDownloadedSha256=[string]$result.PackageSha256
            Save-NrState
        }
        if (-not [bool]$result.Updated -and [string]$result.Status -ne 'updated') {
            Show-NrMessage -Title (T 'checkUpdate') -Message ([string]$result.Message) -Color Yellow
            return
        }

        $health=Invoke-NrPostUpdateHealthCheck
        $healthy=@($health | Where-Object { $_.ok }).Count
        Write-NrLog -Message 'Update installed and post-update probes completed' -Data @{ version=$result.CurrentVersion; sha256=$result.PackageSha256; healthy=$healthy; total=$health.Count }
        Send-NrNotification -Title 'NexRoute' -Message ((T 'updateDone') + ' ' + [string]$result.CurrentVersion) -Level Info
        Write-NrHeader -Title (T 'checkUpdate')
        Write-Host ('  ' + (T 'updateDone')) -ForegroundColor Green
        Write-Host ('  SHA-256: ' + [string]$result.PackageSha256) -ForegroundColor Cyan
        Write-Host ('  Post-update checks: {0}/{1}' -f $healthy,$health.Count) -ForegroundColor $(if ($healthy -eq $health.Count) { [ConsoleColor]::Green } else { [ConsoleColor]::Yellow })
        Start-Sleep -Seconds 2
        Start-Process -FilePath (Join-Path $script:NrRoot 'nexroute.bat') -WorkingDirectory $script:NrRoot | Out-Null
        exit 0
    } catch {
        Write-NrLog -Level ERROR -Message 'Update failed' -Data @{ error=$_.Exception.Message }
        Show-NrMessage -Title (T 'operationFailed') -Message $_.Exception.Message -Color Red
    }
}

function Invoke-NrAttestationVerification {
    Write-NrHeader -Title (T 'attestation')
    $gh=Get-Command gh.exe -ErrorAction SilentlyContinue
    if (-not $gh) { $gh=Get-Command gh -ErrorAction SilentlyContinue }
    if (-not $gh) {
        $script:NrState.lastAttestationStatus='gh-cli-missing'; Save-NrState
        Show-NrMessage -Title (T 'attestation') -Message 'GitHub CLI is required for local Sigstore attestation verification.' -Color Yellow
        return
    }
    $temp=Join-Path ([IO.Path]::GetTempPath()) ('nexroute-attestation-' + [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $temp -Force | Out-Null
        $release=Invoke-RestMethod -Uri 'https://api.github.com/repos/Onmaynec/NexRoute/releases/latest' -Headers @{ 'User-Agent'='NexRoute-Attestation/0.6.0'; Accept='application/vnd.github+json' } -TimeoutSec 20
        if ($release.draft -or $release.prerelease) { throw 'Latest release is not a stable release.' }
        $version=([string]$release.tag_name).TrimStart('v')
        $archive="NexRoute-$version-win-x64.zip"
        foreach ($name in @($archive,"$archive.sha256")) {
            $asset=@($release.assets | Where-Object { $_.name -eq $name })
            if ($asset.Count -ne 1) { throw "Release asset is missing: $name" }
            Invoke-WebRequest -Uri $asset[0].browser_download_url -OutFile (Join-Path $temp $name) -UseBasicParsing -TimeoutSec 90 -Headers @{ 'User-Agent'='NexRoute-Attestation/0.6.0' }
        }
        & $gh.Source attestation verify (Join-Path $temp $archive) --repo Onmaynec/NexRoute
        if ($LASTEXITCODE -ne 0) { throw 'Archive attestation verification failed.' }
        & $gh.Source attestation verify (Join-Path $temp "$archive.sha256") --repo Onmaynec/NexRoute
        if ($LASTEXITCODE -ne 0) { throw 'Checksum attestation verification failed.' }
        $script:NrState.lastAttestationStatus='verified'; Save-NrState
        Show-NrMessage -Title (T 'attestation') -Message ('Verified release v' + $version + ' and both build provenance attestations.') -Color Green
    } catch {
        $script:NrState.lastAttestationStatus='failed'; Save-NrState
        Show-NrMessage -Title (T 'operationFailed') -Message $_.Exception.Message -Color Red
    } finally {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Show-NrUpdateTools {
    while ($true) {
        $items=@(
            New-NrMenuItem -Id 'check' -Label (T 'checkUpdate') -Section (T 'checkUpdate')
            New-NrMenuItem -Id 'auto' -Label (T 'autoUpdate') -Section (T 'checkUpdate') -Status $(if (Get-NrAutoUpdateEnabled) { T 'enabled' } else { T 'disabled' })
            New-NrMenuItem -Id 'attestation' -Label (T 'attestation') -Section (T 'checkUpdate') -Status ([string]$script:NrState.lastAttestationStatus)
            New-NrMenuItem -Id 'sha' -Label (T 'sha') -Section (T 'checkUpdate') -Status ([string]$script:NrState.lastDownloadedSha256)
            New-NrMenuItem -Id 'back' -Label (T 'back') -Section (T 'checkUpdate')
        )
        $choice=Invoke-NrMenu -Title (T 'checkUpdate') -Items $items -AllowEscape
        if (-not $choice -or $choice -eq 'back') { return }
        switch ($choice) {
            'check' { Invoke-NrCheckUpdate }
            'auto' {
                $enabled=-not (Get-NrAutoUpdateEnabled)
                Set-NrAutoUpdateEnabled -Enabled $enabled
                Show-NrMessage -Title (T 'autoUpdate') -Message $(if ($enabled) { T 'autoCheckOn' } else { T 'autoCheckOff' }) -Color Green
            }
            'attestation' { Invoke-NrAttestationVerification }
            'sha' { Show-NrMessage -Title (T 'sha') -Message $(if ($script:NrState.lastDownloadedSha256) { [string]$script:NrState.lastDownloadedSha256 } else { T 'noResults' }) -Color Cyan }
        }
    }
}

# Loaded last by nexroute-console.ps1. These extensions intentionally override
# the legacy Strategy Lab functions after all compatibility modules are present.
foreach ($extension in @('nexroute-media.ps1','nexroute-strategy-lab-v2.ps1')) {
    $extensionPath=Join-Path $PSScriptRoot $extension
    if (-not (Test-Path -LiteralPath $extensionPath -PathType Leaf)) { throw "NexRoute runtime extension is missing: $extension" }
    . $extensionPath
}
