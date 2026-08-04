[CmdletBinding()]
param(
    [string]$ManifestPath = (Join-Path (Split-Path -Parent $PSScriptRoot) '.service/upstream-manifest.json'),
    [Parameter(Mandatory)][string]$OutputPath,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'

$manifestFile=[IO.Path]::GetFullPath($ManifestPath)
$outputFile=[IO.Path]::GetFullPath($OutputPath)
if (-not (Test-Path -LiteralPath $manifestFile -PathType Leaf)) { throw "Upstream manifest is missing: $manifestFile" }
$manifest=Get-Content -LiteralPath $manifestFile -Raw -Encoding UTF8 | ConvertFrom-Json
if ([int]$manifest.schemaVersion -ne 1) { throw 'Upstream manifest schemaVersion must be 1.' }
if ([string]$manifest.repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw 'Upstream repository must use owner/name format.' }
if ([string]$manifest.tag -notmatch '^[0-9A-Za-z._-]+$') { throw 'Upstream tag contains unsafe characters.' }
$assetName=[string]$manifest.assetName
if ([string]::IsNullOrWhiteSpace($assetName) -or $assetName -match '[\\/]' -or $assetName -notmatch '\.zip$') { throw 'Upstream assetName must be one ZIP file name.' }
if ($assetName -notmatch [string]$manifest.assetPattern) { throw "Upstream assetName does not match assetPattern: $assetName" }
$expected=([string]$manifest.expectedSha256).Trim().ToLowerInvariant()
if ($expected -notmatch '^[0-9a-f]{64}$') { throw 'Upstream expectedSha256 must contain 64 hexadecimal characters.' }
if ([long]$manifest.minimumBytes -lt 1) { throw 'Upstream minimumBytes must be greater than zero.' }

$immutableUrl="https://github.com/$($manifest.repository)/releases/download/$($manifest.tag)/$assetName"
$temporary=$outputFile+'.tmp-'+[guid]::NewGuid().ToString('N')
$directory=Split-Path -Parent $outputFile
if ($directory -and -not (Test-Path -LiteralPath $directory -PathType Container)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }

function Test-PinnedArchive {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $file=Get-Item -LiteralPath $Path
    if ($file.Length -lt [long]$manifest.minimumBytes) { return $null }
    $actual=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expected) { return $null }
    return [pscustomobject]@{ path=$file.FullName; size=$file.Length; sha256=$actual; url=$immutableUrl }
}

try {
    if (-not $Force) {
        $cached=Test-PinnedArchive -Path $outputFile
        if ($cached) {
            $cached | Add-Member -NotePropertyName cached -NotePropertyValue $true
            return $cached
        }
    }
    Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    Invoke-WebRequest -Uri $immutableUrl -OutFile $temporary -UseBasicParsing -TimeoutSec 180 -Headers @{
        Accept='application/octet-stream'
        'User-Agent'='NexRoute-Pinned-Upstream/0.6.0'
    }
    $verified=Test-PinnedArchive -Path $temporary
    if (-not $verified) {
        if (-not (Test-Path -LiteralPath $temporary -PathType Leaf)) { throw 'Pinned upstream download produced no file.' }
        $actual=(Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash.ToLowerInvariant()
        $size=(Get-Item -LiteralPath $temporary).Length
        throw "Pinned upstream verification failed. Expected SHA-256 $expected and at least $($manifest.minimumBytes) bytes; got $actual and $size bytes."
    }
    Move-Item -LiteralPath $temporary -Destination $outputFile -Force
    $result=Test-PinnedArchive -Path $outputFile
    if (-not $result) { throw 'Pinned upstream verification failed after the atomic move.' }
    $result | Add-Member -NotePropertyName cached -NotePropertyValue $false
    return $result
} finally {
    Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
}
