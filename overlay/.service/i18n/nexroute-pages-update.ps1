function Invoke-NexRouteUpdateWatch {
    $updater = Join-Path $script:ServiceDirectory 'nexroute-updater.ps1'
    Write-NexRouteHeader -Title $script:Text.updatesTitle

    if (-not (Test-Path -LiteralPath $updater -PathType Leaf)) {
        Write-NexRouteResult -Success $false -Message 'NexRoute updater module was not found.'
        if (-not $NonInteractive) { Wait-NexRouteKey }
        return
    }

    if ($NonInteractive) {
        & $updater -Mode Status -Root $script:Root -Json -NonInteractive | Out-Null
        return
    }

    try {
        & $updater -Mode Menu -Root $script:Root
    } catch {
        Write-NexRouteResult -Success $false -Message $_.Exception.Message
        Wait-NexRouteKey
    }
}
