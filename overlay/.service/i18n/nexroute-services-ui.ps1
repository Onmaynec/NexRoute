function Get-NexRouteServiceDefinitions {
    return @((Get-Content -LiteralPath (Join-Path $script:ServiceDirectory 'services.json') -Raw -Encoding UTF8 | ConvertFrom-Json).services)
}

function Get-NexRouteServiceState {
    param([array]$Definitions)
    $state = [ordered]@{}
    foreach ($item in $Definitions) { $state[$item.id] = [bool]$item.defaultEnabled }
    $path = Join-Path $script:ServiceDirectory 'services-state.json'
    if (Test-Path -LiteralPath $path) {
        try {
            $saved = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($item in $Definitions) {
                $property = $saved.PSObject.Properties[$item.id]
                if ($property) { $state[$item.id] = [bool]$property.Value }
            }
        } catch {}
    }
    return $state
}

function Save-NexRouteServiceState {
    param($State)
    $path = Join-Path $script:ServiceDirectory 'services-state.json'
    [System.IO.File]::WriteAllText($path, (($State | ConvertTo-Json -Depth 6) + [Environment]::NewLine), (New-Object System.Text.UTF8Encoding($false)))
    $controller = Join-Path $script:ServiceDirectory 'nexroute-services.ps1'
    $applyJson = & $controller -Mode Apply -Root $script:Root | Select-Object -Last 1
    $apply = if ($applyJson) { $applyJson | ConvertFrom-Json } else { $null }
    $restartJson = & $controller -Mode Restart -Root $script:Root | Select-Object -Last 1
    $restart = if ($restartJson) { $restartJson | ConvertFrom-Json } else { $null }
    return [pscustomobject]@{ Apply = $apply; Restart = $restart }
}

function Get-NexRouteScopeLabel {
    param([string]$Scope)
    if ($Scope -eq 'baseline') { return $script:Text.baseline }
    if ($Scope -eq 'full') { return $script:Text.full }
    if ($Scope -eq 'social') { return $script:Text.social }
    if ($Scope -eq 'experimental') { return $script:Text.experimental }
    return $script:Text.web
}

function Show-NexRouteServices {
    $definitions = Get-NexRouteServiceDefinitions
    $state = Get-NexRouteServiceState -Definitions $definitions
    $selected = 0
    while ($true) {
        Write-NexRouteHeader -Title $script:Text.servicesTitle
        $enabledCount = @($definitions | Where-Object { [bool]$state[$_.id] }).Count
        Write-NexRouteKeyValue -Key $script:Text.servicesActive -Value ("$enabledCount/$($definitions.Count)") -ValueColor Yellow
        Write-NexRoutePanel -Title $script:Text.servicesTitle
        for ($index = 0; $index -lt $definitions.Count; $index++) {
            $item = $definitions[$index]
            $name = if ($script:Language -eq 'RU') { [string]$item.nameRu } else { [string]$item.nameEn }
            $scope = Get-NexRouteScopeLabel -Scope ([string]$item.scope)
            $status = if ([bool]$state[$item.id]) { $script:Text.enabled } else { $script:Text.disabled }
            $prefix = if ($index -eq $selected) { '>' } else { ' ' }
            $nameWidth = [Math]::Min(54, [Math]::Max(36, $script:Width - 49))
            $scopeWidth = 20
            $statusWidth = [Math]::Max(8, $script:Width - $nameWidth - $scopeWidth - 13)
            Write-Host '|' -NoNewline -ForegroundColor DarkCyan
            Write-Host (" $prefix [{0:00}] " -f ($index + 1)) -NoNewline -ForegroundColor $(if ($index -eq $selected) { 'Cyan' } else { 'DarkGray' })
            Write-Host (Format-NexRouteText -Value $name -Length $nameWidth) -NoNewline -ForegroundColor White
            Write-Host (Format-NexRouteText -Value $scope -Length $scopeWidth) -NoNewline -ForegroundColor (Get-NexRouteStateColor -State $scope)
            $statusText = '[' + $status.ToUpperInvariant() + ']'
            Write-Host (Format-NexRouteText -Value $statusText -Length $statusWidth) -NoNewline -ForegroundColor (Get-NexRouteStateColor -State $status)
            Write-Host '|' -ForegroundColor DarkCyan
        }
        Write-NexRouteRule -Color DarkCyan
        $current = $definitions[$selected]
        $description = if ($script:Language -eq 'RU') { [string]$current.descriptionRu } else { [string]$current.descriptionEn }
        $tcp = @($current.tcpPorts) -join ','
        $udp = @($current.udpPorts) -join ','
        Write-NexRouteKeyValue -Key $script:Text.servicesDescription -Value $description -ValueColor White
        Write-NexRouteKeyValue -Key $script:Text.servicesPorts -Value ("TCP: $tcp  |  UDP: $udp") -ValueColor Cyan
        Write-NexRouteKeyValue -Key $script:Text.servicesTargets -Value (@($current.testTargets).Count.ToString()) -ValueColor Green
        Write-NexRouteRule -Color DarkCyan
        Write-NexRouteCentered -Value $script:Text.servicesWarning -Color Yellow
        Write-NexRouteCentered -Value $script:Text.servicesHelp -Color DarkGray
        Write-NexRouteRule -Fill '=' -Color Cyan
        if ($NonInteractive) { return }
        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            'UpArrow' { $selected = if ($selected -le 0) { $definitions.Count - 1 } else { $selected - 1 } }
            'DownArrow' { $selected = if ($selected -ge $definitions.Count - 1) { 0 } else { $selected + 1 } }
            'Spacebar' { $id = $definitions[$selected].id; $state[$id] = -not [bool]$state[$id] }
            'A' { foreach ($item in $definitions) { $state[$item.id] = $true } }
            'N' { foreach ($item in $definitions) { $state[$item.id] = $false } }
            'Enter' {
                try {
                    Invoke-NexRouteAnimation -Label $script:Text.launchLists -Duration 210
                    Invoke-NexRouteAnimation -Label 'Resolving enabled endpoint addresses' -Duration 230
                    Invoke-NexRouteAnimation -Label 'Generating TCP and UDP runtime filters' -Duration 230
                    $result = Save-NexRouteServiceState -State $state
                    Invoke-NexRouteAnimation -Label $script:Text.servicesRestarting -Duration 260
                    $message = $script:Text.servicesSaved
                    if ($result.Restart -and $result.Restart.Installed -and $result.Restart.Restarted) { $message += ' ' + $script:Text.servicesRestarted }
                    elseif ($result.Restart -and -not $result.Restart.Installed) { $message += ' ' + $script:Text.servicesNotInstalled }
                    elseif ($result.Restart -and $result.Restart.Message) { $message += ' ' + $result.Restart.Message }
                    Write-NexRouteResult -Success $true -Message $message
                }
                catch { Write-NexRouteResult -Success $false -Message $_.Exception.Message }
                Start-Sleep -Milliseconds 950
                return
            }
            'Escape' { Write-NexRouteResult -Success $true -Message $script:Text.servicesCancelled; Start-Sleep -Milliseconds 450; return }
        }
    }
}
