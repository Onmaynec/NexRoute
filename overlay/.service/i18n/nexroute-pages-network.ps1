function Get-NexRouteIpsetMode {
    $listPath = Join-Path $script:Root 'lists\ipset-all.txt'
    if (-not (Test-Path -LiteralPath $listPath -PathType Leaf)) { return 'none' }
    $lines = @(Get-Content -LiteralPath $listPath -ErrorAction SilentlyContinue)
    if ($lines.Count -eq 0 -or ($lines.Count -eq 1 -and [string]::IsNullOrWhiteSpace($lines[0]))) { return 'any' }
    if ($lines -contains '203.0.113.113/32') { return 'none' }
    return 'loaded'
}

function Invoke-NexRouteIpsetSwitch {
    $listPath = Join-Path $script:Root 'lists\ipset-all.txt'
    $backupPath = $listPath + '.backup'
    $current = Get-NexRouteIpsetMode
    $target = if ($current -eq 'loaded') { 'none' } elseif ($current -eq 'none') { 'any' } else { 'loaded' }
    $title = if ($target -eq 'loaded') { $script:Text.transitionLoaded } elseif ($target -eq 'any') { $script:Text.transitionAny } else { $script:Text.transitionNone }
    Write-NexRouteHeader -Title $title
    Invoke-NexRouteAnimation -Label 'Snapshot current routing state' -Duration 160
    Invoke-NexRouteAnimation -Label $script:Text.transitionApply -Duration 210
    try {
        if ($target -eq 'none') {
            if (Test-Path -LiteralPath $backupPath) { Remove-Item -LiteralPath $backupPath -Force }
            if (Test-Path -LiteralPath $listPath) { Copy-Item -LiteralPath $listPath -Destination $backupPath -Force }
            [System.IO.File]::WriteAllText($listPath, "203.0.113.113/32`r`n", [System.Text.Encoding]::ASCII)
        } elseif ($target -eq 'any') {
            [System.IO.File]::WriteAllText($listPath, '', [System.Text.Encoding]::ASCII)
        } else {
            if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) { throw 'No loaded IPSet backup is available. Run SYNC IPSET first.' }
            Move-Item -LiteralPath $backupPath -Destination $listPath -Force
        }
        Write-NexRouteResult -Success $true -Message ("IPSet mode: $target")
    } catch { Write-NexRouteResult -Success $false -Message $_.Exception.Message }
    Wait-NexRouteKey
}

function Invoke-NexRouteSyncIpSet {
    $listPath = Join-Path $script:Root 'lists\ipset-all.txt'
    $backupPath = $listPath + '.backup'
    $tempPath = Join-Path $env:TEMP ("nexroute-ipset-{0}.txt" -f [guid]::NewGuid().ToString('N'))
    $url = 'https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/refs/heads/main/.service/ipset-service.txt'
    Write-NexRouteHeader -Title $script:Text.syncIpSetTitle
    try {
        Invoke-NexRouteAnimation -Label $script:Text.syncResolve -Duration 150
        Invoke-NexRouteAnimation -Label $script:Text.syncDownload -Duration 190
        Invoke-WebRequest -Uri $url -OutFile $tempPath -UseBasicParsing -TimeoutSec 20
        Invoke-NexRouteAnimation -Label $script:Text.syncValidate -Duration 170
        $lines = @(Get-Content -LiteralPath $tempPath -ErrorAction Stop | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($lines.Count -lt 10) { throw 'Downloaded IPSet contains too few entries.' }
        Invoke-NexRouteAnimation -Label $script:Text.syncBackup -Duration 150
        if (Test-Path -LiteralPath $listPath -PathType Leaf) { Copy-Item -LiteralPath $listPath -Destination $backupPath -Force }
        Invoke-NexRouteAnimation -Label $script:Text.syncCommit -Duration 190
        Move-Item -LiteralPath $tempPath -Destination $listPath -Force
        Write-NexRouteResult -Success $true -Message ("$($script:Text.syncDone): $($lines.Count) entries")
    } catch {
        if (Test-Path -LiteralPath $tempPath) { Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue }
        Write-NexRouteResult -Success $false -Message ($script:Text.syncFailed + ': ' + $_.Exception.Message)
    }
    Wait-NexRouteKey
}

function Remove-NexRouteManagedHostsBlock {
    param([string[]]$Lines, [string]$BeginMarker, [string]$EndMarker)
    $result = New-Object 'System.Collections.Generic.List[string]'
    $inside = $false
    foreach ($line in @($Lines)) {
        if ($line.Trim() -eq $BeginMarker) { $inside = $true; continue }
        if ($line.Trim() -eq $EndMarker) { $inside = $false; continue }
        if (-not $inside) { $result.Add($line) }
    }
    while ($result.Count -gt 0 -and [string]::IsNullOrWhiteSpace($result[$result.Count - 1])) { $result.RemoveAt($result.Count - 1) }
    return @($result)
}

function Invoke-NexRouteSyncHosts {
    $hostsPath = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
    $hostsDirectory = Split-Path -Parent $hostsPath
    $downloadPath = Join-Path $env:TEMP ("nexroute-hosts-download-{0}.txt" -f [guid]::NewGuid().ToString('N'))
    $commitPath = Join-Path $hostsDirectory ("hosts.nexroute-{0}.tmp" -f [guid]::NewGuid().ToString('N'))
    $backupDirectory = Join-Path $script:ServiceDirectory 'backups'
    $backupPath = Join-Path $backupDirectory ("hosts-{0}.bak" -f [DateTime]::Now.ToString('yyyyMMdd-HHmmss'))
    $url = 'https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/refs/heads/main/.service/hosts'
    $beginMarker = '# NEXROUTE-HOSTS-BEGIN'
    $endMarker = '# NEXROUTE-HOSTS-END'

    Write-NexRouteHeader -Title $script:Text.syncHostsTitle
    try {
        if (-not (Test-NexRouteAdministrator)) { throw 'Administrator privileges are required to update the system hosts file.' }
        Invoke-NexRouteAnimation -Label $script:Text.syncResolve -Duration 160
        Invoke-NexRouteAnimation -Label $script:Text.syncDownload -Duration 210
        Invoke-WebRequest -Uri ($url + '?t=' + [DateTime]::UtcNow.Ticks) -OutFile $downloadPath -UseBasicParsing -TimeoutSec 20 -Headers @{ 'Cache-Control' = 'no-cache' }
        Invoke-NexRouteAnimation -Label $script:Text.syncValidate -Duration 190
        $remoteLines = @(Get-Content -LiteralPath $downloadPath -Encoding UTF8 -ErrorAction Stop | ForEach-Object { $_.TrimEnd() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($remoteLines.Count -lt 2) { throw 'Downloaded hosts dataset is empty or incomplete.' }
        $invalid = @($remoteLines | Where-Object { $_ -notmatch '^\s*(#|\d{1,3}(?:\.\d{1,3}){3}\s+\S+)' })
        if ($invalid.Count -gt 0) { throw 'Downloaded hosts dataset contains invalid lines.' }

        [string]$localText = ''
        if (Test-Path -LiteralPath $hostsPath -PathType Leaf) {
            $raw = Get-Content -LiteralPath $hostsPath -Raw -ErrorAction SilentlyContinue
            if ($null -ne $raw) { $localText = [string]$raw }
        }
        $localLines = if ($localText.Length -gt 0) { @($localText -split "`r?`n") } else { @() }
        $preserved = @(Remove-NexRouteManagedHostsBlock -Lines $localLines -BeginMarker $beginMarker -EndMarker $endMarker)
        $merged = New-Object 'System.Collections.Generic.List[string]'
        foreach ($line in $preserved) { $merged.Add($line) }
        if ($merged.Count -gt 0) { $merged.Add('') }
        $merged.Add($beginMarker)
        foreach ($line in $remoteLines) { $merged.Add($line) }
        $merged.Add($endMarker)
        $merged.Add('')
        $newText = ($merged.ToArray() -join "`r`n") + "`r`n"
        $oldNormalized = ($localText -replace "`r?`n", "`n").TrimEnd()
        $newNormalized = ($newText -replace "`r?`n", "`n").TrimEnd()
        if ($oldNormalized -eq $newNormalized) {
            Invoke-NexRouteAnimation -Label $script:Text.syncCommit -Duration 140 -Color Green
            Write-NexRouteResult -Success $true -Message $script:Text.syncNoChange
            return
        }

        Invoke-NexRouteAnimation -Label $script:Text.syncBackup -Duration 180
        New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
        if (Test-Path -LiteralPath $hostsPath -PathType Leaf) { Copy-Item -LiteralPath $hostsPath -Destination $backupPath -Force }
        Invoke-NexRouteAnimation -Label $script:Text.syncMerge -Duration 200
        [System.IO.File]::WriteAllText($commitPath, $newText, (New-Object System.Text.UTF8Encoding($false)))
        Invoke-NexRouteAnimation -Label $script:Text.syncCommit -Duration 210
        Move-Item -LiteralPath $commitPath -Destination $hostsPath -Force
        Invoke-NexRouteAnimation -Label $script:Text.syncFlushDns -Duration 170
        & ipconfig.exe /flushdns | Out-Null
        Write-NexRouteKeyValue -Key $script:Text.syncHostsManaged -Value $remoteLines.Count.ToString() -ValueColor Green
        Write-NexRouteKeyValue -Key $script:Text.syncHostsBackup -Value $backupPath -ValueColor Cyan
        Write-NexRouteResult -Success $true -Message $script:Text.syncDone
    } catch {
        if (Test-Path -LiteralPath $commitPath) { Remove-Item -LiteralPath $commitPath -Force -ErrorAction SilentlyContinue }
        Write-NexRouteResult -Success $false -Message ($script:Text.syncFailed + ': ' + $_.Exception.Message)
    } finally {
        if (Test-Path -LiteralPath $downloadPath) { Remove-Item -LiteralPath $downloadPath -Force -ErrorAction SilentlyContinue }
    }
    Wait-NexRouteKey
}

function Invoke-NexRouteInstalledServiceRefresh {
    $controller = Join-Path $script:ServiceDirectory 'nexroute-services.ps1'
    if (-not (Test-Path -LiteralPath $controller -PathType Leaf)) { return $null }
    try {
        $json = & $controller -Mode Restart -Root $script:Root | Select-Object -Last 1
        if ($json) { return ($json | ConvertFrom-Json) }
    } catch { return [pscustomobject]@{ Installed = $true; Restarted = $false; Message = $_.Exception.Message } }
    return $null
}

function Show-NexRouteGameFilter {
    $flagPath = Join-Path $script:Root 'utils\game_filter.enabled'
    $current = '0'
    if (Test-Path -LiteralPath $flagPath -PathType Leaf) {
        $mode = (Get-Content -LiteralPath $flagPath -Raw -ErrorAction SilentlyContinue).Trim().ToLowerInvariant()
        if ($mode -eq 'all') { $current = '1' } elseif ($mode -eq 'tcp') { $current = '2' } elseif ($mode -eq 'udp') { $current = '3' }
    }
    Write-NexRouteHeader -Title $script:Text.gameTitle
    Write-NexRouteKeyValue -Key $script:Text.gameCurrent -Value $current -ValueColor Yellow
    Write-NexRouteOption -Number 0 -Label $script:Text.game0
    Write-NexRouteOption -Number 1 -Label $script:Text.game1
    Write-NexRouteOption -Number 2 -Label $script:Text.game2
    Write-NexRouteOption -Number 3 -Label $script:Text.game3
    Write-NexRouteRule -Fill '=' -Color Cyan
    if ($NonInteractive) { return }
    Write-Host ''
    Write-Host ('  > ' + $script:Text.gamePrompt + ': ') -NoNewline -ForegroundColor Cyan
    $choice = (Read-Host).Trim()
    if ($choice -notin @('0','1','2','3')) { Write-NexRouteResult -Success $false -Message $script:Text.invalid; Wait-NexRouteKey; return }
    Invoke-NexRouteAnimation -Label $script:Text.transitionApply -Duration 190
    if ($choice -eq '0') { Remove-Item -LiteralPath $flagPath -Force -ErrorAction SilentlyContinue }
    else {
        $value = if ($choice -eq '1') { 'all' } elseif ($choice -eq '2') { 'tcp' } else { 'udp' }
        [System.IO.File]::WriteAllText($flagPath, $value + [Environment]::NewLine, [System.Text.Encoding]::ASCII)
    }
    Invoke-NexRouteAnimation -Label $script:Text.gameRestart -Duration 220
    $refresh = Invoke-NexRouteInstalledServiceRefresh
    $message = $script:Text.gameSaved
    if ($refresh -and $refresh.Installed -and -not $refresh.Restarted) { $message += ': ' + $refresh.Message }
    Write-NexRouteResult -Success $true -Message $message
    Wait-NexRouteKey
}

function Invoke-NexRouteUpdateWatch {
    $flagPath = Join-Path $script:Root 'utils\check_updates.enabled'
    $enable = -not (Test-Path -LiteralPath $flagPath -PathType Leaf)
    Write-NexRouteHeader -Title $script:Text.updatesTitle
    if ($enable) {
        Invoke-NexRouteAnimation -Label $script:Text.updatesEnable -Duration 210
        [System.IO.File]::WriteAllText($flagPath, "ENABLED`r`n", [System.Text.Encoding]::ASCII)
        Write-NexRouteResult -Success $true -Message $script:Text.updatesEnabled
    } else {
        Invoke-NexRouteAnimation -Label $script:Text.updatesDisable -Duration 210
        Remove-Item -LiteralPath $flagPath -Force
        Write-NexRouteResult -Success $true -Message $script:Text.updatesDisabled
    }
    Wait-NexRouteKey
}

function Show-NexRouteTestsIntro {
    Write-NexRouteHeader -Title $script:Text.testsTitle
    Invoke-NexRouteAnimation -Label $script:Text.testsStart -Duration 190
    Invoke-NexRouteAnimation -Label 'Checking PowerShell and curl runtime' -Duration 160
    Invoke-NexRouteAnimation -Label $script:Text.testsMatrix -Duration 220
    Invoke-NexRouteAnimation -Label $script:Text.testsNetwork -Duration 220
    Invoke-NexRouteAnimation -Label $script:Text.testsWindow -Duration 150 -Color Green
    Wait-NexRouteKey
}

function Show-NexRouteTestHeader {
    Write-NexRouteHeader -Title $script:Text.testHeader
    Write-NexRouteKeyValue -Key 'SESSION' -Value ([DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss')) -ValueColor Cyan
    $privilege = if (Test-NexRouteAdministrator) { $script:Text.elevated } else { $script:Text.standard }
    Write-NexRouteKeyValue -Key $script:Text.privilege -Value $privilege -ValueColor Yellow
    Write-NexRouteKeyValue -Key $script:Text.servicesTargets -Value (Get-NexRouteServiceSummary) -ValueColor Green
    Write-NexRouteRule -Color DarkCyan
}

function Show-NexRouteScreen {
    $title = if ($ScreenId) { $ScreenId.ToUpperInvariant() } else { 'SYSTEM SCREEN' }
    Write-NexRouteHeader -Title $title
}
