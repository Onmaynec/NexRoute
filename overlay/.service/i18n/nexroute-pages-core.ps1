function Show-NexRouteMenu {
    $version = Get-NexRouteEnvironmentValue -Name 'NEXROUTE_VERSION' -Fallback '0.2.2'
    $game = Get-NexRouteEnvironmentValue -Name 'NEXROUTE_GAME_STATUS' -Fallback 'disabled'
    $ipset = Get-NexRouteEnvironmentValue -Name 'NEXROUTE_IPSET_STATUS' -Fallback 'none'
    $updates = Get-NexRouteEnvironmentValue -Name 'NEXROUTE_UPDATE_STATUS' -Fallback 'disabled'
    $serviceSummary = Get-NexRouteServiceSummary

    if ((Get-NexRouteEnvironmentValue -Name 'NEXROUTE_UI_ANIMATE' -Fallback '0') -eq '1') {
        try { [Console]::CursorVisible = $false } catch {}
        Clear-Host
        Write-NexRouteLogo
        Write-NexRouteRule -Fill '=' -Color Cyan
        Write-NexRouteCentered -Value $script:Text.boot1 -Color Magenta
        Write-NexRouteRule -Fill '=' -Color Cyan
        Write-Host ''
        Invoke-NexRouteAnimation -Label $script:Text.boot1 -Duration 180
        Invoke-NexRouteAnimation -Label $script:Text.boot2 -Duration 180
        Invoke-NexRouteAnimation -Label $script:Text.boot3 -Duration 210
        Invoke-NexRouteAnimation -Label $script:Text.boot4 -Duration 240
        Invoke-NexRouteAnimation -Label $script:Text.boot5 -Duration 170 -Color Green
        Start-Sleep -Milliseconds 260
        try { [Console]::CursorVisible = $true } catch {}
    }

    while ($true) {
        Write-NexRouteHeader -Title ("CONTROL NODE v$version")
        Write-NexRoutePanel -Title $script:Text.mainService
        Write-NexRouteOption -Number 1 -Label $script:Text.menu1
        Write-NexRouteOption -Number 2 -Label $script:Text.menu2
        Write-NexRouteOption -Number 3 -Label $script:Text.menu3
        Write-NexRoutePanel -Title $script:Text.mainFilters
        Write-NexRouteOption -Number 4 -Label $script:Text.menu4 -Status $game
        Write-NexRouteOption -Number 5 -Label $script:Text.menu5 -Status $ipset
        Write-NexRouteOption -Number 6 -Label $script:Text.menu6 -Status $updates
        Write-NexRouteOption -Number 7 -Label $script:Text.menu7
        Write-NexRoutePanel -Title $script:Text.mainData
        Write-NexRouteOption -Number 8 -Label $script:Text.menu8
        Write-NexRouteOption -Number 9 -Label $script:Text.menu9
        Write-NexRouteOption -Number 10 -Label $script:Text.menu10
        Write-NexRoutePanel -Title $script:Text.mainOther
        Write-NexRouteOption -Number 14 -Label $script:Text.menu14 -Status $serviceSummary
        Write-NexRoutePanel -Title $script:Text.mainTools
        Write-NexRouteOption -Number 11 -Label $script:Text.menu11
        Write-NexRouteOption -Number 12 -Label $script:Text.menu12
        $targetLanguage = if ($script:Language -eq 'RU') { 'EN' } else { 'RU' }
        Write-NexRouteOption -Number 13 -Label $script:Text.menu13 -Status $targetLanguage
        Write-NexRouteRule -Color DarkCyan
        Write-Host '|' -NoNewline -ForegroundColor DarkCyan
        Write-Host ' [00] ' -NoNewline -ForegroundColor Cyan
        Write-Host (Format-NexRouteText -Value $script:Text.menu0 -Length ($script:Width - 10)) -NoNewline -ForegroundColor DarkGray
        Write-Host '|' -ForegroundColor DarkCyan
        Write-NexRouteRule -Fill '=' -Color Cyan

        if ($NonInteractive) { return }
        Write-Host ''
        Write-Host ('  > ' + $script:Text.prompt + ': ') -NoNewline -ForegroundColor Cyan
        $choice = (Read-Host).Trim()
        $number = 0
        if ([int]::TryParse($choice, [ref]$number) -and $number -ge 0 -and $number -le 14) {
            if (-not $ChoiceFile) { throw 'ChoiceFile is required in Menu mode.' }
            [System.IO.File]::WriteAllText($ChoiceFile, $number.ToString(), [System.Text.Encoding]::ASCII)
            return
        }
        Write-Host ''
        Write-NexRouteCentered -Value $script:Text.invalid -Color Red
        Start-Sleep -Milliseconds 750
    }
}

function Get-NexRouteActionLabel {
    param([string]$Id)
    $map = @{
        deploy = 'menu1'; remove = 'menu2'; status = 'menu3'; game = 'menu4';
        ipset = 'menu5'; updatecheck = 'menu6'; payload = 'menu7'; syncipset = 'menu8';
        synchosts = 'menu9'; releases = 'menu10'; diagnostics = 'menu11'; tests = 'menu12'; services = 'menu14'
    }
    if ($map.ContainsKey($Id)) {
        $property = $script:Text.PSObject.Properties[$map[$Id]]
        if ($property) { return [string]$property.Value }
    }
    return $Id.ToUpperInvariant()
}

function Show-NexRouteAction {
    $label = Get-NexRouteActionLabel -Id $ActionId
    Write-NexRouteHeader -Title $script:Text.actionTitle
    Write-NexRouteKeyValue -Key 'OPERATION' -Value $label -ValueColor Cyan
    Invoke-NexRouteAnimation -Label 'Validating request' -Duration 150
    Invoke-NexRouteAnimation -Label 'Locking configuration state' -Duration 170
    Invoke-NexRouteAnimation -Label 'Preparing system module' -Duration 190
    Invoke-NexRouteAnimation -Label $script:Text.actionComplete -Duration 140 -Color Green
}

function Show-NexRouteLaunch {
    $profileName = if ($Profile) { $Profile } else { 'general' }
    Write-NexRouteHeader -Title $script:Text.launchTitle
    Write-NexRouteKeyValue -Key $script:Text.profile -Value $profileName -ValueColor Cyan
    Invoke-NexRouteAnimation -Label $script:Text.launchRead -Duration 150
    $engineOk = Test-Path -LiteralPath (Join-Path $script:Root 'bin\winws.exe') -PathType Leaf
    $driverOk = Test-Path -LiteralPath (Join-Path $script:Root 'bin\WinDivert64.sys') -PathType Leaf
    Invoke-NexRouteAnimation -Label $script:Text.launchEngine -Duration 150 -Color $(if ($engineOk) { 'Green' } else { 'Red' })
    Invoke-NexRouteAnimation -Label $script:Text.launchDriver -Duration 150 -Color $(if ($driverOk) { 'Green' } else { 'Red' })
    Invoke-NexRouteAnimation -Label $script:Text.launchLists -Duration 180
    Invoke-NexRouteAnimation -Label $script:Text.launchCommand -Duration 190
    Invoke-NexRouteAnimation -Label $script:Text.launchTransfer -Duration 150 -Color Green
    if (-not $engineOk -or -not $driverOk) {
        Write-NexRouteResult -Success $false -Message 'Required engine components are missing.'
        exit 2
    }
}

function Show-NexRouteStatus {
    Write-NexRouteHeader -Title $script:Text.statusTitle
    $strategy = 'none'
    try {
        $value = Get-ItemPropertyValue -Path 'HKLM:\System\CurrentControlSet\Services\zapret' -Name 'zapret-discord-youtube' -ErrorAction Stop
        if ($value) { $strategy = [string]$value }
    } catch {}
    $zapretState = if (Test-NexRouteServiceRunning -Name 'zapret') { $script:Text.running } else { $script:Text.stopped }
    $windivertState = if (Test-NexRouteServiceRunning -Name 'WinDivert') { $script:Text.running } else { $script:Text.stopped }
    $engineState = if (Get-Process -Name 'winws' -ErrorAction SilentlyContinue) { $script:Text.running } else { $script:Text.stopped }
    $driverState = if (Test-Path -LiteralPath (Join-Path $script:Root 'bin\WinDivert64.sys')) { $script:Text.ready } else { $script:Text.missing }
    Write-NexRouteKeyValue -Key $script:Text.statusStrategy -Value $strategy -ValueColor Cyan
    Write-NexRouteKeyValue -Key $script:Text.statusZapret -Value $zapretState -ValueColor (Get-NexRouteStateColor -State $zapretState)
    Write-NexRouteKeyValue -Key $script:Text.statusWinDivert -Value $windivertState -ValueColor (Get-NexRouteStateColor -State $windivertState)
    Write-NexRouteKeyValue -Key $script:Text.statusEngine -Value $engineState -ValueColor (Get-NexRouteStateColor -State $engineState)
    Write-NexRouteKeyValue -Key 'WinDivert64.sys' -Value $driverState -ValueColor (Get-NexRouteStateColor -State $driverState)
    Write-NexRouteKeyValue -Key $script:Text.statusDomains -Value (Get-NexRouteServiceSummary) -ValueColor Yellow
    Write-NexRouteRule -Fill '=' -Color Cyan
    Wait-NexRouteKey
}

function Get-NexRouteStrategyCategory {
    param([string]$Name)
    $upper = $Name.ToUpperInvariant()
    if ($upper -match 'EXP') { return $script:Text.strategyExperimental }
    if ($upper -match 'ALT|FAKE') { return $script:Text.strategyAdvanced }
    return $script:Text.strategyStable
}

function Show-NexRouteStrategyPicker {
    $files = @(Get-ChildItem -LiteralPath $script:Root -Filter '*.bat' -File | Where-Object { $_.Name -notin @('service.bat', 'nexroute.bat') } | Sort-Object Name)
    Write-NexRouteHeader -Title $script:Text.strategyTitle
    Write-NexRouteCentered -Value $script:Text.strategyHint -Color DarkGray
    Write-NexRoutePanel -Title 'AVAILABLE PROFILES'
    for ($index = 0; $index -lt $files.Count; $index++) {
        Write-NexRouteOption -Number ($index + 1) -Label $files[$index].BaseName -Status (Get-NexRouteStrategyCategory -Name $files[$index].Name)
    }
    Write-NexRouteOption -Number 0 -Label $script:Text.strategyExit
    Write-NexRouteRule -Fill '=' -Color Cyan
    if ($NonInteractive) { return }
    while ($true) {
        Write-Host ''
        Write-Host ('  > ' + $script:Text.strategyPrompt + " [0-$($files.Count)]: ") -NoNewline -ForegroundColor Cyan
        $raw = (Read-Host).Trim()
        $choice = 0
        if ([int]::TryParse($raw, [ref]$choice) -and $choice -ge 0 -and $choice -le $files.Count) {
            $value = if ($choice -eq 0) { '0' } else { $files[$choice - 1].Name }
            if ($ChoiceFile) { [System.IO.File]::WriteAllText($ChoiceFile, $value, (New-Object System.Text.UTF8Encoding($false))) }
            return
        }
        Write-NexRouteCentered -Value $script:Text.invalid -Color Red
    }
}

function Get-NexRouteFileHash {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Show-NexRoutePayloadManager {
    $binPath = Join-Path $script:Root 'bin'
    if (-not (Test-Path -LiteralPath $binPath -PathType Container)) {
        Write-NexRouteHeader -Title $script:Text.payloadTitle
        Write-NexRouteResult -Success $false -Message 'bin directory was not found.'
        Wait-NexRouteKey
        return
    }
    while ($true) {
        $files = @(Get-ChildItem -LiteralPath $binPath -Filter '*.bin' -File | Where-Object { $_.BaseName -notlike 'ACTIVE_*' } | Sort-Object BaseName)
        $discordActive = Join-Path $binPath 'ACTIVE_DISCORD_UDP.bin'
        $gameActive = Join-Path $binPath 'ACTIVE_GAME_UDP.bin'
        $discordHash = Get-NexRouteFileHash -Path $discordActive
        $gameHash = Get-NexRouteFileHash -Path $gameActive
        $discordName = $script:Text.missing
        $gameName = $script:Text.missing
        foreach ($file in $files) {
            $hash = Get-NexRouteFileHash -Path $file.FullName
            if ($discordHash -and $hash -eq $discordHash) { $discordName = $file.BaseName }
            if ($gameHash -and $hash -eq $gameHash) { $gameName = $file.BaseName }
        }
        Write-NexRouteHeader -Title $script:Text.payloadTitle
        Write-NexRoutePanel -Title $script:Text.payloadTypes
        Write-NexRouteOption -Number 1 -Label $script:Text.payloadDiscord -Status $discordName
        Write-NexRouteOption -Number 2 -Label $script:Text.payloadGame -Status $gameName
        Write-NexRoutePanel -Title $script:Text.payloadFiles
        for ($index = 0; $index -lt $files.Count; $index++) { Write-NexRouteOption -Number ($index + 1) -Label $files[$index].BaseName }
        Write-NexRouteRule -Fill '=' -Color Cyan
        if ($NonInteractive) { return }
        Write-Host ''
        Write-Host ('  > ' + $script:Text.payloadPrompt + ': ') -NoNewline -ForegroundColor Cyan
        $choice = (Read-Host).Trim()
        if ($choice -eq '0' -or [string]::IsNullOrWhiteSpace($choice)) { return }
        $parts = @($choice -split '\s+' | Where-Object { $_ })
        $type = 0; $fileNumber = 0
        if ($parts.Count -ne 2 -or -not [int]::TryParse($parts[0], [ref]$type) -or -not [int]::TryParse($parts[1], [ref]$fileNumber) -or $type -notin @(1, 2) -or $fileNumber -lt 1 -or $fileNumber -gt $files.Count) {
            Write-NexRouteCentered -Value $script:Text.invalid -Color Red
            Start-Sleep -Milliseconds 600
            continue
        }
        $destination = if ($type -eq 1) { $discordActive } else { $gameActive }
        try {
            Invoke-NexRouteAnimation -Label 'Unlocking payload vault' -Duration 150
            Copy-Item -LiteralPath $files[$fileNumber - 1].FullName -Destination $destination -Force
            Invoke-NexRouteAnimation -Label 'Committing active payload' -Duration 150 -Color Green
            Write-NexRouteResult -Success $true -Message $script:Text.payloadSuccess
        } catch { Write-NexRouteResult -Success $false -Message ($script:Text.payloadFailure + ': ' + $_.Exception.Message) }
        Wait-NexRouteKey
    }
}

