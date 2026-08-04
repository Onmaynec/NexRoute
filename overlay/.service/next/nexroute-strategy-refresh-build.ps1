Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$refreshModule = Join-Path $PSScriptRoot 'nexroute-strategy-refresh.ps1'
if (-not (Test-Path -LiteralPath $refreshModule -PathType Leaf)) {
    throw "NexRoute strategy refresh module is missing: $refreshModule"
}
. $refreshModule

function Remove-NexRoute063RuntimeTail {
    param([Parameter(Mandatory)][string]$Path)

    $lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        [void]$lines.Add($line)
    }

    $tcpIndex = -1
    $udpIndex = -1
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index].Trim() -eq '%NEXROUTE_SERVICE_TCP_ARGS% ^') { $tcpIndex = $index }
        if ($lines[$index].Trim() -eq '%NEXROUTE_SERVICE_UDP_ARGS%') { $udpIndex = $index }
    }

    if ($tcpIndex -lt 1 -or $udpIndex -ne ($tcpIndex + 1)) {
        throw "Refreshed strategy has an invalid temporary runtime tail: $Path"
    }

    $commandTail = $lines[$tcpIndex - 1].TrimEnd()
    if (-not $commandTail.EndsWith('^')) {
        throw "Refreshed strategy command does not continue into its temporary runtime tail: $Path"
    }
    $lines[$tcpIndex - 1] = [regex]::Replace($commandTail, '\s*\^\s*$', '')
    $lines.RemoveAt($udpIndex)
    $lines.RemoveAt($tcpIndex)

    [System.IO.File]::WriteAllLines($Path, $lines, [System.Text.Encoding]::ASCII)
}

function Invoke-NexRoute063StrategyRefreshBuild {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root)

    $rootPath = [System.IO.Path]::GetFullPath($Root)
    Assert-NexRoute063Payloads -Root $rootPath

    $catalog = @(Get-NexRoute063StrategyCatalog)
    if ($catalog.Count -ne 21) {
        throw "Expected 21 NexRoute 0.6.3 strategy profiles, got $($catalog.Count)."
    }
    if (@($catalog.Profile | Sort-Object -Unique).Count -ne 21) {
        throw 'NexRoute 0.6.3 strategy profile IDs must be unique.'
    }

    $listsRoot = Join-Path $rootPath 'lists'
    $discordListPath = Join-Path $listsRoot 'list-nexroute-discord-critical.txt'
    $youtubeListPath = Join-Path $listsRoot 'list-nexroute-youtube-critical.txt'

    Write-NexRoute063HostList -Path $discordListPath -Domains @(
        'gateway.discord.gg',
        'cdn.discordapp.com',
        'updates.discord.com',
        'discord.com',
        'discord.gg',
        'discordapp.com',
        'discordapp.net',
        'discord.media',
        'discordcdn.com',
        'stable.dl2.discordapp.net'
    )
    Write-NexRoute063HostList -Path $youtubeListPath -Domains @(
        'www.youtube.com',
        'youtu.be',
        'i.ytimg.com',
        'redirector.googlevideo.com',
        'youtube.com',
        'youtube-nocookie.com',
        'ytimg.com',
        'googlevideo.com',
        'youtubei.googleapis.com',
        'youtube.googleapis.com',
        'ggpht.com',
        'yt3.ggpht.com'
    )

    $strategyReports = New-Object 'System.Collections.Generic.List[object]'
    foreach ($spec in $catalog) {
        $path = Join-Path $rootPath ([string]$spec.File)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Missing strategy file: $($spec.File)"
        }

        $before = Get-NexRoute063Sha256 -Path $path
        Set-NexRoute063StrategyFile -Path $path -Spec $spec

        # Build-Release applies the normal Service Matrix patch immediately
        # after this refresh. Remove the temporary runtime tail emitted by the
        # reusable strategy generator so the tracked patch inserts it exactly
        # once and its before hash links to this refresh report.
        Remove-NexRoute063RuntimeTail -Path $path

        $after = Get-NexRoute063Sha256 -Path $path
        if ($before -eq $after) {
            throw "Strategy refresh did not change: $($spec.File)"
        }

        $strategyReports.Add([pscustomobject]@{
            file = ([string]$spec.File).Replace('\','/')
            profile = [string]$spec.Profile
            family = [string]$spec.Family
            beforeSha256 = $before
            afterSha256 = $after
        })
    }

    $versionPath = Join-Path $rootPath '.service/version.txt'
    $sourceVersion = if (Test-Path -LiteralPath $versionPath -PathType Leaf) {
        (Get-Content -LiteralPath $versionPath -Raw -Encoding UTF8).Trim()
    }
    else {
        'unknown'
    }
    $targetVersion = if ($sourceVersion -eq '0.6.3') { '0.6.3' } else { '0.6.3-candidate' }

    $report = [ordered]@{
        schemaVersion = 1
        nexRouteVersion = $targetVersion
        sourceVersion = $sourceVersion
        targetProvider = 'Informatsionnye Kommunikatsii / wired / Sibay, Russia'
        strategyCount = $strategyReports.Count
        strategySet = 'NexRoute 0.6.3 RKN refresh'
        criticalTargets = @(
            'DiscordGateway',
            'DiscordCDN',
            'DiscordUpdates',
            'YouTubeWeb',
            'YouTubeShort',
            'YouTubeImage',
            'YouTubeVideoRedirect'
        )
        lists = @(
            [ordered]@{
                file = 'lists/list-nexroute-discord-critical.txt'
                sha256 = Get-NexRoute063Sha256 -Path $discordListPath
            },
            [ordered]@{
                file = 'lists/list-nexroute-youtube-critical.txt'
                sha256 = Get-NexRoute063Sha256 -Path $youtubeListPath
            }
        )
        strategies = @($strategyReports.ToArray())
    }

    $reportPath = Join-Path $rootPath '.service/strategy-refresh-report.json'
    $reportJson = $report | ConvertTo-Json -Depth 12
    [System.IO.File]::WriteAllText(
        $reportPath,
        ($reportJson + "`r`n"),
        [System.Text.UTF8Encoding]::new($false)
    )

    return [pscustomobject]@{
        StrategyCount = $strategyReports.Count
        Report = $reportPath
        DiscordList = $discordListPath
        YouTubeList = $youtubeListPath
    }
}
