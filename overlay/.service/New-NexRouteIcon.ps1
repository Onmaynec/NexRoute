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

# Repair legacy launchers affected by the quoted trailing-backslash argument bug.
$sanitizedFiles = 0
foreach ($batFile in @(Get-ChildItem -LiteralPath $Root -Filter '*.bat' -File -ErrorAction SilentlyContinue)) {
    $content = [System.IO.File]::ReadAllText($batFile.FullName)
    $fixed = $content -replace '\s+-Root\s+"%~dp0"', ''
    if ($fixed -ne $content) {
        [System.IO.File]::WriteAllText($batFile.FullName, $fixed, [System.Text.Encoding]::ASCII)
        $sanitizedFiles++
    }
}

function New-RoundedRectanglePath {
    param(
        [float]$X,
        [float]$Y,
        [float]$Width,
        [float]$Height,
        [float]$Radius
    )

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $diameter = $Radius * 2
    $path.AddArc($X, $Y, $diameter, $diameter, 180, 90)
    $path.AddArc($X + $Width - $diameter, $Y, $diameter, $diameter, 270, 90)
    $path.AddArc($X + $Width - $diameter, $Y + $Height - $diameter, $diameter, $diameter, 0, 90)
    $path.AddArc($X, $Y + $Height - $diameter, $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    return $path
}

function New-NexRouteArtwork {
    $size = 512
    $bitmap = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.Clear([System.Drawing.Color]::Transparent)

    $outerPath = New-RoundedRectanglePath -X 16 -Y 16 -Width 480 -Height 480 -Radius 66
    $outerBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Rectangle(16, 16, 480, 480)),
        [System.Drawing.Color]::FromArgb(255, 13, 22, 40),
        [System.Drawing.Color]::FromArgb(255, 2, 8, 18),
        55.0
    )
    $graphics.FillPath($outerBrush, $outerPath)

    $borderBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Rectangle(16, 16, 480, 480)),
        [System.Drawing.Color]::FromArgb(255, 81, 75, 151),
        [System.Drawing.Color]::FromArgb(255, 8, 36, 74),
        45.0
    )
    $borderPen = New-Object System.Drawing.Pen($borderBrush, 5)
    $graphics.DrawPath($borderPen, $outerPath)

    # Subtle inner glow.
    $innerPath = New-RoundedRectanglePath -X 28 -Y 28 -Width 456 -Height 456 -Radius 57
    $innerPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(75, 72, 119, 205), 2)
    $graphics.DrawPath($innerPen, $innerPath)

    # Orbit and globe field inspired by the supplied artwork.
    $orbitBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Rectangle(80, 65, 350, 350)),
        [System.Drawing.Color]::FromArgb(255, 177, 57, 255),
        [System.Drawing.Color]::FromArgb(255, 0, 202, 255),
        0.0
    )
    $orbitPen = New-Object System.Drawing.Pen($orbitBrush, 3)
    $graphics.DrawEllipse($orbitPen, 82, 67, 348, 348)

    $dotBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(68, 47, 94, 188))
    $worldDots = @(
        @(150,128),@(161,124),@(172,126),@(183,132),@(194,143),@(205,151),
        @(137,144),@(148,151),@(161,156),@(174,162),@(188,166),@(202,169),
        @(262,130),@(276,134),@(288,143),@(300,151),@(316,154),@(329,164),
        @(249,154),@(260,164),@(273,171),@(287,177),@(301,184),@(317,190),
        @(340,205),@(353,216),@(365,230),@(373,247),@(379,263),
        @(153,204),@(163,217),@(171,231),@(179,247),@(188,260),@(198,273),
        @(285,218),@(297,229),@(311,240),@(325,254),@(337,269),@(350,284)
    )
    foreach ($point in $worldDots) {
        $graphics.FillEllipse($dotBrush, [int]$point[0], [int]$point[1], 5, 5)
    }

    # Orbit nodes.
    foreach ($node in @(@(127,91, [System.Drawing.Color]::FromArgb(255,177,57,255)), @(373,93,[System.Drawing.Color]::FromArgb(255,0,184,255)), @(403,344,[System.Drawing.Color]::FromArgb(255,0,174,255)))) {
        $nodeBrush = New-Object System.Drawing.SolidBrush($node[2])
        $graphics.FillEllipse($nodeBrush, [int]$node[0] - 9, [int]$node[1] - 9, 18, 18)
        $nodeCore = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 7, 20, 43))
        $graphics.FillEllipse($nodeCore, [int]$node[0] - 4, [int]$node[1] - 4, 8, 8)
        $nodeBrush.Dispose()
        $nodeCore.Dispose()
    }

    $brandBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Rectangle(105, 135, 315, 245)),
        [System.Drawing.Color]::FromArgb(255, 231, 67, 255),
        [System.Drawing.Color]::FromArgb(255, 0, 154, 255),
        0.0
    )
    $highlightPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(150, 218, 232, 255), 2)

    # Stylized N.
    $leftPath = New-Object System.Drawing.Drawing2D.GraphicsPath
    $leftPath.AddPolygon([System.Drawing.Point[]]@(
        (New-Object System.Drawing.Point(118,154)),
        (New-Object System.Drawing.Point(173,154)),
        (New-Object System.Drawing.Point(173,333)),
        (New-Object System.Drawing.Point(118,376))
    ))
    $graphics.FillPath($brandBrush, $leftPath)
    $graphics.DrawPath($highlightPen, $leftPath)

    $middlePath = New-Object System.Drawing.Drawing2D.GraphicsPath
    $middlePath.AddPolygon([System.Drawing.Point[]]@(
        (New-Object System.Drawing.Point(165,171)),
        (New-Object System.Drawing.Point(248,275)),
        (New-Object System.Drawing.Point(336,164)),
        (New-Object System.Drawing.Point(385,164)),
        (New-Object System.Drawing.Point(252,326)),
        (New-Object System.Drawing.Point(218,326)),
        (New-Object System.Drawing.Point(165,255))
    ))
    $graphics.FillPath($brandBrush, $middlePath)
    $graphics.DrawPath($highlightPen, $middlePath)

    $rightPath = New-Object System.Drawing.Drawing2D.GraphicsPath
    $rightPath.AddPolygon([System.Drawing.Point[]]@(
        (New-Object System.Drawing.Point(287,301)),
        (New-Object System.Drawing.Point(337,354)),
        (New-Object System.Drawing.Point(386,354)),
        (New-Object System.Drawing.Point(322,272))
    ))
    $graphics.FillPath($brandBrush, $rightPath)

    # Ascending road-arrow crossing the N.
    $roadPath = New-Object System.Drawing.Drawing2D.GraphicsPath
    $roadPath.AddPolygon([System.Drawing.Point[]]@(
        (New-Object System.Drawing.Point(86,398)),
        (New-Object System.Drawing.Point(241,304)),
        (New-Object System.Drawing.Point(351,200)),
        (New-Object System.Drawing.Point(319,199)),
        (New-Object System.Drawing.Point(352,158)),
        (New-Object System.Drawing.Point(411,151)),
        (New-Object System.Drawing.Point(398,211)),
        (New-Object System.Drawing.Point(366,243)),
        (New-Object System.Drawing.Point(367,211)),
        (New-Object System.Drawing.Point(267,329)),
        (New-Object System.Drawing.Point(170,398))
    ))
    $roadBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Rectangle(86, 150, 330, 250)),
        [System.Drawing.Color]::FromArgb(255, 54, 23, 117),
        [System.Drawing.Color]::FromArgb(255, 0, 98, 213),
        0.0
    )
    $graphics.FillPath($roadBrush, $roadPath)
    $roadPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(230, 80, 192, 255), 3)
    $graphics.DrawPath($roadPen, $roadPath)

    $lanePen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 0, 224, 255), 5)
    $lanePen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dash
    $graphics.DrawLine($lanePen, 159, 376, 343, 223)

    # Wordmark.
    $font = New-Object System.Drawing.Font('Segoe UI', 30, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $textBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Rectangle(105, 410, 305, 45)),
        [System.Drawing.Color]::FromArgb(255, 193, 69, 255),
        [System.Drawing.Color]::FromArgb(255, 0, 200, 255),
        0.0
    )
    $format = New-Object System.Drawing.StringFormat
    $format.Alignment = [System.Drawing.StringAlignment]::Center
    $graphics.DrawString('N E X R O U T E', $font, $textBrush, (New-Object System.Drawing.RectangleF(74, 418, 364, 42)), $format)

    $format.Dispose()
    $font.Dispose()
    $textBrush.Dispose()
    $lanePen.Dispose()
    $roadPen.Dispose()
    $roadBrush.Dispose()
    $roadPath.Dispose()
    $rightPath.Dispose()
    $middlePath.Dispose()
    $leftPath.Dispose()
    $highlightPen.Dispose()
    $brandBrush.Dispose()
    $dotBrush.Dispose()
    $orbitPen.Dispose()
    $orbitBrush.Dispose()
    $innerPen.Dispose()
    $innerPath.Dispose()
    $borderPen.Dispose()
    $borderBrush.Dispose()
    $outerBrush.Dispose()
    $outerPath.Dispose()
    $graphics.Dispose()

    return $bitmap
}

function New-NexRoutePngBytes {
    param(
        [Parameter(Mandatory)][System.Drawing.Image]$Source,
        [Parameter(Mandatory)][int]$Size
    )

    $bitmap = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $stream = New-Object System.IO.MemoryStream
    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $graphics.DrawImage($Source, 0, 0, $Size, $Size)
        $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
        return $stream.ToArray()
    }
    finally {
        $stream.Dispose()
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function Write-NexRouteIco {
    param(
        [Parameter(Mandatory)][System.Drawing.Image]$Source,
        [Parameter(Mandatory)][string]$Path
    )

    $sizes = @(16, 20, 24, 32, 40, 48, 64, 128, 256)
    $images = @()
    foreach ($size in $sizes) {
        $images += [pscustomobject]@{
            Size = $size
            Bytes = New-NexRoutePngBytes -Source $Source -Size $size
        }
    }

    $file = [System.IO.File]::Create($Path)
    $writer = New-Object System.IO.BinaryWriter($file)
    try {
        $writer.Write([uint16]0)
        $writer.Write([uint16]1)
        $writer.Write([uint16]$images.Count)
        $offset = 6 + (16 * $images.Count)
        foreach ($image in $images) {
            $dimension = if ($image.Size -ge 256) { [byte]0 } else { [byte]$image.Size }
            $writer.Write($dimension)
            $writer.Write($dimension)
            $writer.Write([byte]0)
            $writer.Write([byte]0)
            $writer.Write([uint16]1)
            $writer.Write([uint16]32)
            $writer.Write([uint32]$image.Bytes.Length)
            $writer.Write([uint32]$offset)
            $offset += $image.Bytes.Length
        }
        foreach ($image in $images) { $writer.Write([byte[]]$image.Bytes) }
    }
    finally {
        $writer.Dispose()
        $file.Dispose()
    }
}

$sourceImage = New-NexRouteArtwork
try {
    Write-NexRouteIco -Source $sourceImage -Path $iconPath
}
finally {
    $sourceImage.Dispose()
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

Write-Output ("Icon: {0}" -f $iconPath)
Write-Output 'Icon design: NexRoute supplied artwork motif'
Write-Output ("Sanitized BAT files: {0}" -f $sanitizedFiles)
