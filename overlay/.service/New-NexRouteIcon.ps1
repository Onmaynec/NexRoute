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
$iconPartsPath = Join-Path $Root 'assets\nexroute-icon-parts'

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

        foreach ($image in $images) {
            $writer.Write([byte[]]$image.Bytes)
        }
    }
    finally {
        $writer.Dispose()
        $file.Dispose()
    }
}

if (-not (Test-Path -LiteralPath $iconPartsPath -PathType Container)) {
    throw "NexRoute icon source directory was not found: $iconPartsPath"
}

$partFiles = @(Get-ChildItem -LiteralPath $iconPartsPath -Filter '*.b64' -File | Sort-Object Name)
if ($partFiles.Count -ne 10) {
    throw "Expected 10 NexRoute icon source parts, got $($partFiles.Count)."
}

$builder = New-Object System.Text.StringBuilder
foreach ($partFile in $partFiles) {
    $part = (Get-Content -LiteralPath $partFile.FullName -Raw -Encoding ASCII).Trim()
    [void]$builder.Append($part)
}
$encoded = $builder.ToString()
$imageBytes = [Convert]::FromBase64String($encoded)
$imageStream = New-Object System.IO.MemoryStream(,$imageBytes)
$sourceImage = [System.Drawing.Image]::FromStream($imageStream)
try {
    Write-NexRouteIco -Source $sourceImage -Path $iconPath
}
finally {
    $sourceImage.Dispose()
    $imageStream.Dispose()
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
Write-Output ("Icon source parts: {0}" -f $partFiles.Count)
Write-Output ("Sanitized BAT files: {0}" -f $sanitizedFiles)
