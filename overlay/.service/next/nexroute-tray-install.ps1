[CmdletBinding()]
param(
    [ValidateSet('Install','Uninstall','Start','Stop','Status')][string]$Mode='Status',
    [string]$Root,
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if (-not $Root) { $Root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
$Root=[IO.Path]::GetFullPath($Root)
$taskName='NexRoute Native Tray'
$executable=Join-Path $Root '.service/native/NexRoute.Tray.exe'

function Get-NrTrayProcesses {
    $expected=[IO.Path]::GetFullPath($executable)
    $result=New-Object 'System.Collections.Generic.List[object]'
    foreach ($process in @(Get-CimInstance Win32_Process -Filter "Name='NexRoute.Tray.exe'" -ErrorAction SilentlyContinue)) {
        $path=$null
        try { $path=[IO.Path]::GetFullPath([string]$process.ExecutablePath) } catch { }
        if ($path -and $path.Equals($expected,[StringComparison]::OrdinalIgnoreCase)) { $result.Add($process) }
    }
    return $result.ToArray()
}

function Stop-NrTrayProcesses {
    $stopped=0
    foreach ($process in @(Get-NrTrayProcesses)) {
        try { Stop-Process -Id ([int]$process.ProcessId) -Force -ErrorAction Stop; $stopped++ } catch { }
    }
    return $stopped
}

function Start-NrNativeTray {
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) { throw "Native tray executable is missing: $executable" }
    if (@(Get-NrTrayProcesses).Count -gt 0) { return $false }
    Start-Process -FilePath $executable -ArgumentList @('--root',$Root) -WorkingDirectory $Root | Out-Null
    return $true
}

function Register-NrNativeTrayTask {
    if ($env:OS -ne 'Windows_NT') { throw 'Native tray installation is supported on Windows only.' }
    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) { throw "Native tray executable is missing: $executable" }
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent().Name
    if ([string]::IsNullOrWhiteSpace($identity)) { throw 'Unable to resolve the current Windows user.' }
    $arguments='--root "'+$Root+'"'
    $action=New-ScheduledTaskAction -Execute $executable -Argument $arguments -WorkingDirectory $Root
    $trigger=New-ScheduledTaskTrigger -AtLogOn -User $identity
    $principal=New-ScheduledTaskPrincipal -UserId $identity -LogonType Interactive -RunLevel Highest
    $settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'NexRoute native tray controller and service status monitor.' -Force | Out-Null
    return $identity
}

function Get-NrTrayStatus {
    $task=$null
    try { $task=Get-ScheduledTask -TaskName $taskName -ErrorAction Stop } catch { }
    $processes=@(Get-NrTrayProcesses)
    return [pscustomobject]@{
        schemaVersion=1
        root=$Root
        executable=$executable
        executableExists=(Test-Path -LiteralPath $executable -PathType Leaf)
        installed=($null -ne $task)
        taskState=$(if ($task) { [string]$task.State } else { 'Missing' })
        running=($processes.Count -gt 0)
        processIds=[int[]]@($processes | ForEach-Object { [int]$_.ProcessId })
    }
}

switch ($Mode) {
    'Install' {
        $user=Register-NrNativeTrayTask
        Stop-NrTrayProcesses | Out-Null
        Start-NrNativeTray | Out-Null
        $result=Get-NrTrayStatus
        $result | Add-Member -NotePropertyName installedFor -NotePropertyValue $user
    }
    'Uninstall' {
        Stop-NrTrayProcesses | Out-Null
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        $result=Get-NrTrayStatus
    }
    'Start' {
        Start-NrNativeTray | Out-Null
        $result=Get-NrTrayStatus
    }
    'Stop' {
        Stop-NrTrayProcesses | Out-Null
        $result=Get-NrTrayStatus
    }
    'Status' { $result=Get-NrTrayStatus }
}

if ($Json) { $result | ConvertTo-Json -Depth 8 }
else { $result | Format-List }
