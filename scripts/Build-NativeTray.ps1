[CmdletBinding()]
param(
    [string]$SourcePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'native/NexRoute.Tray/Program.cs'),
    [string]$NotifierSourcePath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'native/NexRoute.Notifier/Program.cs'),
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts/native-tray')
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Native tray compilation requires Windows.' }
$source=[IO.Path]::GetFullPath($SourcePath)
$notifierSource=[IO.Path]::GetFullPath($NotifierSourcePath)
$output=[IO.Path]::GetFullPath($OutputDirectory)
foreach ($requiredSource in @($source,$notifierSource)) {
    if (-not (Test-Path -LiteralPath $requiredSource -PathType Leaf)) { throw "Native Windows source is missing: $requiredSource" }
}
New-Item -ItemType Directory -Path $output -Force | Out-Null

$candidates=@(
    (Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET/Framework/v4.0.30319/csc.exe')
)
$csc=$candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $csc) { throw 'The .NET Framework C# compiler was not found.' }

function Invoke-NrNativeCompile {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$AssemblyName,
        [Parameter(Mandatory)][string[]]$References,
        [switch]$AddTimerAlias
    )
    $executable=Join-Path $output ($AssemblyName+'.exe')
    Remove-Item -LiteralPath $executable -Force -ErrorAction SilentlyContinue
    $temporary=Join-Path ([IO.Path]::GetTempPath()) ($AssemblyName+'-'+[guid]::NewGuid().ToString('N')+'.cs')
    try {
        $content=[IO.File]::ReadAllText($Source,[Text.Encoding]::UTF8)
        if ($AddTimerAlias) {
            $content=$content.Replace('using System.Threading;',"using System.Threading;`r`nusing Timer = System.Windows.Forms.Timer;")
        }
        [IO.File]::WriteAllText($temporary,$content,[Text.UTF8Encoding]::new($true))
        $arguments=New-Object 'System.Collections.Generic.List[string]'
        foreach ($argument in @('/nologo','/target:winexe','/optimize+','/platform:anycpu','/warn:4')) { $arguments.Add($argument) }
        foreach ($reference in $References) { $arguments.Add('/reference:'+$reference) }
        $arguments.Add('/out:'+$executable)
        $arguments.Add($temporary)
        $outputLines=@(& $csc @($arguments.ToArray()) 2>&1)
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $executable -PathType Leaf)) {
            throw "$AssemblyName compilation failed:`n$($outputLines -join [Environment]::NewLine)"
        }
        $assembly=[Reflection.AssemblyName]::GetAssemblyName($executable)
        if ([string]$assembly.Name -ne $AssemblyName) { throw "Unexpected native assembly name: $($assembly.Name); expected $AssemblyName" }
        return [pscustomobject]@{
            executable=$executable
            size=(Get-Item -LiteralPath $executable).Length
            sha256=(Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash.ToLowerInvariant()
            assemblyName=[string]$assembly.Name
        }
    } finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
}

$tray=Invoke-NrNativeCompile -Source $source -AssemblyName 'NexRoute.Tray' -References @(
    'System.dll','System.Core.dll','System.Drawing.dll','System.Windows.Forms.dll','System.ServiceProcess.dll'
) -AddTimerAlias
$notifier=Invoke-NrNativeCompile -Source $notifierSource -AssemblyName 'NexRoute.Notifier' -References @(
    'System.dll','System.Core.dll','System.Drawing.dll','System.Windows.Forms.dll'
)

[pscustomobject]@{
    executable=$tray.executable
    size=$tray.size
    sha256=$tray.sha256
    notifierExecutable=$notifier.executable
    notifierSize=$notifier.size
    notifierSha256=$notifier.sha256
    compiler=$csc
    framework='NET Framework 4.x'
}
