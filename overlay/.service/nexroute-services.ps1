[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [string]$LanguageFile = (Join-Path $PSScriptRoot 'language.txt')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$width = 86
$statePath = Join-Path $PSScriptRoot 'services-enabled.txt'
$listPath = Join-Path $RootPath 'lists\list-general-user.txt'
$beginMarker = '# NEXROUTE SERVICES BEGIN'
$endMarker = '# NEXROUTE SERVICES END'
$catalog = [ordered]@{
    youtube    = @{ Name = 'YouTube'; Domains = @('youtube.com','youtu.be','googlevideo.com','ytimg.com','youtubei.googleapis.com') }
    discord    = @{ Name = 'Discord'; Domains = @('discord.com','discord.gg','discordapp.com','discordapp.net','discordcdn.com','discord.media') }
    chatgpt    = @{ Name = 'ChatGPT'; Domains = @('chatgpt.com','openai.com','oaistatic.com','oaiusercontent.com') }
    facetime   = @{ Name = 'FaceTime'; Domains = @('facetime.apple.com','push.apple.com','courier.push.apple.com','gateway.push.apple.com') }
    snapchat   = @{ Name = 'Snapchat'; Domains = @('snapchat.com','sc-cdn.net','snapkit.com') }
    viber      = @{ Name = 'Viber'; Domains = @('viber.com','viber.co.jp','vibercdn.com') }
    signal     = @{ Name = 'Signal'; Domains = @('signal.org','signal.art','signalusers.org') }
    twitter    = @{ Name = 'X / Twitter'; Domains = @('x.com','twitter.com','t.co','twimg.com') }
    instagram  = @{ Name = 'Instagram'; Domains = @('instagram.com','cdninstagram.com') }
    facebook   = @{ Name = 'Facebook'; Domains = @('facebook.com','fbcdn.net','fbsbx.com','messenger.com') }
    telegram   = @{ Name = 'Telegram'; Domains = @('telegram.org','t.me','telegram.me','telegra.ph','telesco.pe') }
    linkedin   = @{ Name = 'LinkedIn'; Domains = @('linkedin.com','licdn.com') }
    tiktok     = @{ Name = 'TikTok'; Domains = @('tiktok.com','tiktokcdn.com','tiktokv.com','byteoversea.com') }
    whatsapp   = @{ Name = 'WhatsApp'; Domains = @('whatsapp.com','whatsapp.net') }
    casebattle = @{ Name = 'Case Battle'; Domains = @('casebattle.net') }
}
function Rule([string]$Fill = '=') { Write-Host ($Fill * $width) -ForegroundColor DarkCyan }
function Fit([string]$Text, [int]$Length) {
    if ($Text.Length -gt $Length) { return $Text.Substring(0, [Math]::Max(0, $Length - 3)) + '...' }
    return $Text + (' ' * ($Length - $Text.Length))
}
function Read-State {
    $enabled = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if (Test-Path -LiteralPath $statePath) {
        foreach ($line in Get-Content -LiteralPath $statePath) {
            $value = $line.Trim()
            if ($catalog.Contains($value)) { [void]$enabled.Add($value) }
        }
    }
    return $enabled
}
function Save-State($Enabled) {
    @($catalog.Keys | Where-Object { $Enabled.Contains($_) }) | Set-Content -LiteralPath $statePath -Encoding ascii
}
function Sync-UserList($Enabled) {
    $directory = Split-Path -Parent $listPath
    if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $existing = if (Test-Path -LiteralPath $listPath) { Get-Content -LiteralPath $listPath -Raw } else { "# NexRoute user domains`r`n" }
    $pattern = '(?ms)^' + [regex]::Escape($beginMarker) + '.*?^' + [regex]::Escape($endMarker) + '\s*'
    $clean = [regex]::Replace($existing, $pattern, '').TrimEnd()
    $domains = foreach ($key in $catalog.Keys) { if ($Enabled.Contains($key)) { $catalog[$key].Domains } }
    $managed = @($beginMarker) + @($domains | Sort-Object -Unique) + @($endMarker)
    $result = $clean + "`r`n`r`n" + ($managed -join "`r`n") + "`r`n"
    [System.IO.File]::WriteAllText($listPath, $result, [System.Text.UTF8Encoding]::new($false))
}
function Draw($Enabled) {
    Clear-Host
    Rule
    Write-Host '  NEXROUTE // SERVICE BYPASS MATRIX' -ForegroundColor Cyan
    Write-Host '  Select services whose domains are written to list-general-user.txt' -ForegroundColor DarkGray
    Rule '-'
    $index = 1
    foreach ($key in $catalog.Keys) {
        $on = $Enabled.Contains($key)
        $state = if ($on) { 'ENABLED ' } else { 'DISABLED' }
        $color = if ($on) { 'Green' } else { 'DarkGray' }
        Write-Host ('  [{0,2}] ' -f $index) -NoNewline -ForegroundColor Cyan
        Write-Host (Fit $catalog[$key].Name 28) -NoNewline -ForegroundColor White
        Write-Host ('[' + $state + ']') -ForegroundColor $color
        $index++
    }
    Rule '-'
    Write-Host '  [A] Enable all   [N] Disable all   [S] Save and apply   [0] Return' -ForegroundColor Yellow
    Rule
}
$enabled = Read-State
while ($true) {
    Draw $enabled
    $choice = (Read-Host '  Command').Trim()
    if ($choice -eq '0') { break }
    if ($choice -match '^[Aa]$') { foreach ($key in $catalog.Keys) { [void]$enabled.Add($key) }; continue }
    if ($choice -match '^[Nn]$') { $enabled.Clear(); continue }
    if ($choice -match '^[Ss]$') {
        Write-Host '  Synchronizing service profile...' -ForegroundColor Cyan
        for ($p = 0; $p -le 100; $p += 20) {
            $filled = [int]($p / 5)
            Write-Host ("`r  [" + ('#' * $filled) + ('-' * (20 - $filled)) + "] $p%") -NoNewline -ForegroundColor Cyan
            Start-Sleep -Milliseconds 45
        }
        Write-Host
        Save-State $enabled
        Sync-UserList $enabled
        Write-Host '  Service matrix applied. Reinstall or restart the active strategy service to load changes.' -ForegroundColor Green
        Read-Host '  Press ENTER to return' | Out-Null
        continue
    }
    $number = 0
    if ([int]::TryParse($choice, [ref]$number) -and $number -ge 1 -and $number -le $catalog.Count) {
        $key = @($catalog.Keys)[$number - 1]
        if ($enabled.Contains($key)) { [void]$enabled.Remove($key) } else { [void]$enabled.Add($key) }
    }
}
