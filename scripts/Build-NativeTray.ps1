[CmdletBinding()]
param(
    [string]$SourcePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'native/NexRoute.Tray/Program.cs'),
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts/native-tray')
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Native tray compilation requires Windows.' }
$source=[IO.Path]::GetFullPath($SourcePath)
$output=[IO.Path]::GetFullPath($OutputDirectory)
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Native tray source is missing: $source" }
New-Item -ItemType Directory -Path $output -Force | Out-Null
$executable=Join-Path $output 'NexRoute.Tray.exe'
Remove-Item -LiteralPath $executable -Force -ErrorAction SilentlyContinue

$candidates=@(
    (Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET/Framework/v4.0.30319/csc.exe')
)
$csc=$candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $csc) { throw 'The .NET Framework C# compiler was not found.' }

$tempSource=Join-Path ([IO.Path]::GetTempPath()) ('NexRoute.Tray-'+[guid]::NewGuid().ToString('N')+'.cs')
try {
    $content=[IO.File]::ReadAllText($source,[Text.Encoding]::UTF8)
    # System.Threading and Windows.Forms both define Timer. Keep the checked-in
    # source readable and make the compiler binding explicit in the generated unit.
    $content=$content.Replace('using System.Threading;',"using System.Threading;`r`nusing Timer = System.Windows.Forms.Timer;")
    [IO.File]::WriteAllText($tempSource,$content,[Text.UTF8Encoding]::new($true))
    $arguments=@(
        '/nologo','/target:winexe','/optimize+','/platform:anycpu','/warn:4',
        '/reference:System.dll','/reference:System.Core.dll','/reference:System.Drawing.dll',
        '/reference:System.Windows.Forms.dll','/reference:System.ServiceProcess.dll',
        ('/out:"'+$executable+'"'),('"'+$tempSource+'"')
    )
    $outputLines=@(& $csc @arguments 2>&1)
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $executable -PathType Leaf)) {
        throw "Native tray compilation failed:`n$($outputLines -join [Environment]::NewLine)"
    }
    $assembly=[Reflection.AssemblyName]::GetAssemblyName($executable)
    if ([string]$assembly.Name -ne 'NexRoute.Tray') { throw "Unexpected native tray assembly name: $($assembly.Name)" }
    $hash=(Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash.ToLowerInvariant()
    [pscustomobject]@{
        executable=$executable
        size=(Get-Item -LiteralPath $executable).Length
        sha256=$hash
        compiler=$csc
        framework='NET Framework 4.x'
    }
} finally {
    Remove-Item -LiteralPath $tempSource -Force -ErrorAction SilentlyContinue
}
