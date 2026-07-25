[CmdletBinding()]
param(
    [ValidateSet('Menu', 'Action', 'Launch', 'Status', 'StrategyPicker', 'PayloadManager', 'IpSetSwitch', 'SyncIpSet', 'SyncHosts', 'TestsIntro', 'TestHeader', 'Services', 'Screen')]
    [string]$Mode = 'Menu',
    [string]$ChoiceFile,
    [string]$LanguageFile,
    [string]$ActionId,
    [string]$Profile,
    [string]$ScreenId,
    [string]$Root,
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EmbeddedNexRouteArgument {
    param([string]$Source, [string]$Name)
    if ([string]::IsNullOrWhiteSpace($Source)) { return $null }
    $pattern = '(?is)-' + [regex]::Escape($Name) + '\s+(?:"(?<value>.*?)"|(?<value>.*?))(?=\s+-[A-Za-z][A-Za-z0-9]*\b|$)'
    $match = [regex]::Match($Source, $pattern)
    if (-not $match.Success) { return $null }
    return $match.Groups['value'].Value.Trim().Trim('"')
}

function Repair-NexRouteEmbeddedArguments {
    if ([string]::IsNullOrWhiteSpace($script:Root)) { return }
    $raw = $script:Root
    $marker = [regex]::Match($raw, '(?is)"?\s+-(ChoiceFile|LanguageFile|ActionId|Profile|ScreenId)\b')
    if (-not $marker.Success) { return }

    if ([string]::IsNullOrWhiteSpace($script:ChoiceFile)) { $script:ChoiceFile = Get-EmbeddedNexRouteArgument -Source $raw -Name 'ChoiceFile' }
    if ([string]::IsNullOrWhiteSpace($script:LanguageFile)) { $script:LanguageFile = Get-EmbeddedNexRouteArgument -Source $raw -Name 'LanguageFile' }
    if ([string]::IsNullOrWhiteSpace($script:ActionId)) { $script:ActionId = Get-EmbeddedNexRouteArgument -Source $raw -Name 'ActionId' }
    if ([string]::IsNullOrWhiteSpace($script:Profile)) { $script:Profile = Get-EmbeddedNexRouteArgument -Source $raw -Name 'Profile' }
    if ([string]::IsNullOrWhiteSpace($script:ScreenId)) { $script:ScreenId = Get-EmbeddedNexRouteArgument -Source $raw -Name 'ScreenId' }
    $script:Root = $raw.Substring(0, $marker.Index).Trim().Trim('"')
}

Repair-NexRouteEmbeddedArguments

. (Join-Path $PSScriptRoot 'i18n\nexroute-theme.ps1')
. (Join-Path $PSScriptRoot 'i18n\nexroute-pages.ps1')
. (Join-Path $PSScriptRoot 'i18n\nexroute-services-ui.ps1')

function Repair-NexRouteBatchLaunchers {
    try {
        $files = @(Get-ChildItem -LiteralPath $script:Root -Filter '*.bat' -File -ErrorAction Stop)
        foreach ($file in $files) {
            $content = [System.IO.File]::ReadAllText($file.FullName)
            if ($content -notmatch '-Root\s+"%~dp0"') { continue }
            $fixed = $content -replace '\s+-Root\s+"%~dp0"', ''
            [System.IO.File]::WriteAllText($file.FullName, $fixed, [System.Text.Encoding]::ASCII)
        }
    }
    catch {
    }
}

Repair-NexRouteBatchLaunchers
try { [Console]::Title = 'NexRoute // Control Node' } catch {}

switch ($Mode) {
    'Menu' { Show-NexRouteMenu }
    'Action' { Show-NexRouteAction }
    'Launch' { Show-NexRouteLaunch }
    'Status' { Show-NexRouteStatus }
    'StrategyPicker' { Show-NexRouteStrategyPicker }
    'PayloadManager' { Show-NexRoutePayloadManager }
    'IpSetSwitch' { Invoke-NexRouteIpsetSwitch }
    'SyncIpSet' { Invoke-NexRouteSyncIpSet }
    'SyncHosts' { Invoke-NexRouteSyncHosts }
    'TestsIntro' { Show-NexRouteTestsIntro }
    'TestHeader' { Show-NexRouteTestHeader }
    'Services' { Show-NexRouteServices }
    'Screen' { Show-NexRouteScreen }
}
