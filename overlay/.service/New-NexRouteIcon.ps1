[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Root
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

$serviceDir = Join-Path $Root '.service'
$iconPath = Join-Path $serviceDir 'nexroute.ico'
$shortcutPath = Join-Path $Root 'NexRoute.lnk'
$serviceBat = Join-Path $Root 'service.bat'

New-Item -ItemType Directory -Path $serviceDir -Force | Out-Null

$size = 64
$bitmap = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.Clear([System.Drawing.Color]::FromArgb(7, 12, 18))

$cyan = [System.Drawing.Color]::FromArgb(36, 225, 214)
$light = [System.Drawing.Color]::FromArgb(190, 255, 250)
$dark = [System.Drawing.Color]::FromArgb(10, 20, 28)
$backgroundBrush = New-Object System.Drawing.SolidBrush($dark)
$ring = New-Object System.Drawing.Pen($cyan, 3)
$innerRing = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(14, 90, 98), 1)
$route = New-Object System.Drawing.Pen($cyan, 4)
$route.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
$highlight = New-Object System.Drawing.Pen($light, 1)
$nodeBrush = New-Object System.Drawing.SolidBrush($dark)
$nodePen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(70, 255, 234), 2)
$arrowBrush = New-Object System.Drawing.SolidBrush($cyan)

$graphics.FillEllipse($backgroundBrush, 5, 5, 54, 54)
$graphics.DrawEllipse($ring, 5, 5, 54, 54)
$graphics.DrawEllipse($innerRing, 10, 10, 44, 44)

[System.Drawing.Point[]]$points = @(
    (New-Object System.Drawing.Point(17, 47)),
    (New-Object System.Drawing.Point(17, 18)),
    (New-Object System.Drawing.Point(32, 38)),
    (New-Object System.Drawing.Point(47, 18)),
    (New-Object System.Drawing.Point(47, 46))
)
$graphics.DrawLines($route, $points)
$graphics.DrawLines($highlight, $points)

foreach ($point in $points) {
    $graphics.FillEllipse($nodeBrush, $point.X - 3, $point.Y - 3, 6, 6)
    $graphics.DrawEllipse($nodePen, $point.X - 3, $point.Y - 3, 6, 6)
}

[System.Drawing.Point[]]$arrow = @(
    (New-Object System.Drawing.Point(47, 55)),
    (New-Object System.Drawing.Point(42, 46)),
    (New-Object System.Drawing.Point(52, 46))
)
$graphics.FillPolygon($arrowBrush, $arrow)

$handle = $bitmap.GetHicon()
$icon = [System.Drawing.Icon]::FromHandle($handle)
$stream = [System.IO.File]::Create($iconPath)
try {
    $icon.Save($stream)
}
finally {
    $stream.Dispose()
    $icon.Dispose()
    $graphics.Dispose()
    $bitmap.Dispose()
    $backgroundBrush.Dispose()
    $ring.Dispose()
    $innerRing.Dispose()
    $route.Dispose()
    $highlight.Dispose()
    $nodeBrush.Dispose()
    $nodePen.Dispose()
    $arrowBrush.Dispose()
}

if (Test-Path -LiteralPath $serviceBat -PathType Leaf) {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $serviceBat
    $shortcut.WorkingDirectory = $Root
    $shortcut.IconLocation = "$iconPath,0"
    $shortcut.Description = 'NexRoute Control Node'
    $shortcut.Save()
}

Write-Output $iconPath
