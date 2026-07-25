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
        }
        catch {}
    }
    return $state
}

function Save-NexRouteServiceState {
    param($State)
    $path = Join-Path $script:ServiceDirectory 'services-state.json'
    [System.IO.File]::WriteAllText($path, (($State | ConvertTo-Json -Depth 4) + [Environment]::NewLine), (New-Object System.Text.UTF8Encoding($false)))
    & (Join-Path $script:ServiceDirectory 'nexroute-services.ps1') -Mode Apply -Root $script:Root | Out-Null
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
            $name = if ($script:Language -eq 'RU') { $item.nameRu } else { $item.nameEn }
            $scope = if ($item.scope -eq 'experimental') { $script:Text.experimental } elseif ($item.scope -eq 'baseline') { $script:Text.baseline } else { $script:Text.web }
            $status = if ([bool]$state[$item.id]) { $script:Text.enabled } else { $script:Text.disabled }
            $prefix = if ($index -eq $selected) { '>' } else { ' ' }
            Write-Host '|' -NoNewline -ForegroundColor DarkCyan
            Write-Host (" $prefix [{0:00}] " -f ($index + 1)) -NoNewline -ForegroundColor $(if ($index -eq $selected) { 'Cyan' } else { 'DarkGray' })
            Write-Host (Format-NexRouteText -Value $name -Length 30) -NoNewline -ForegroundColor White
            Write-Host (Format-NexRouteText -Value $scope -Length 18) -NoNewline -ForegroundColor (Get-NexRouteStateColor -State $scope)
            $statusText = '[' + $status.ToUpperInvariant() + ']'
            Write-Host (Format-NexRouteText -Value $statusText -Length ($script:Width - 57)) -NoNewline -ForegroundColor (Get-NexRouteStateColor -State $status)
            Write-Host '|' -ForegroundColor DarkCyan
        }
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
            'Enter' { Invoke-NexRouteAnimation -Label $script:Text.launchLists -Duration 150; Save-NexRouteServiceState -State $state; Write-NexRouteResult -Success $true -Message $script:Text.servicesSaved; Start-Sleep -Milliseconds 700; return }
            'Escape' { Write-NexRouteResult -Success $true -Message $script:Text.servicesCancelled; Start-Sleep -Milliseconds 400; return }
        }
    }
}
