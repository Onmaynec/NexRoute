[CmdletBinding()]
param([string]$Root)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$next=Join-Path $PSScriptRoot 'next'
. (Join-Path $next 'nexroute-common.ps1')
. (Join-Path $next 'nexroute-strategies.ps1')
Initialize-NrEnvironment -RootPath $Root

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

$context=New-Object Windows.Forms.ContextMenuStrip
$open=$context.Items.Add('Open NexRoute')
$toggle=$context.Items.Add('Enable / disable service')
$status=$context.Items.Add('Service status')
$update=$context.Items.Add('Check Update')
[void]$context.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
$exit=$context.Items.Add('Exit tray')

$notify=New-Object Windows.Forms.NotifyIcon
$notify.Icon=[Drawing.SystemIcons]::Shield
$notify.Text='NexRoute'
$notify.ContextMenuStrip=$context
$notify.Visible=$true

$open.add_Click({ Start-Process -FilePath (Join-Path $script:NrRoot 'nexroute.bat') -WorkingDirectory $script:NrRoot | Out-Null })
$toggle.add_Click({
    try {
        if (Test-NrServiceRunning -Name zapret) {
            Stop-Service zapret -Force -ErrorAction SilentlyContinue
            Get-Process winws -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            $notify.ShowBalloonTip(3000,'NexRoute','Service disabled',[Windows.Forms.ToolTipIcon]::Info)
        } else {
            Start-Service zapret -ErrorAction Stop
            $notify.ShowBalloonTip(3000,'NexRoute','Service enabled',[Windows.Forms.ToolTipIcon]::Info)
        }
    } catch { $notify.ShowBalloonTip(4000,'NexRoute',$_.Exception.Message,[Windows.Forms.ToolTipIcon]::Error) }
})
$status.add_Click({
    $text=('Strategy: {0}`nService: {1}`nNetwork: {2}' -f (Get-NrInstalledStrategy),$(if (Test-NrServiceRunning zapret) { 'RUNNING' } else { 'STOPPED' }),(Get-NrActiveNetworkKey))
    $notify.ShowBalloonTip(5000,'NexRoute',$text,[Windows.Forms.ToolTipIcon]::Info)
})
$update.add_Click({ Start-Process -FilePath (Join-Path $script:NrRoot 'nexroute.bat') -ArgumentList '--update' -WorkingDirectory $script:NrRoot | Out-Null })
$exit.add_Click({ $notify.Visible=$false; $notify.Dispose(); [Windows.Forms.Application]::Exit() })
$notify.add_DoubleClick({ Start-Process -FilePath (Join-Path $script:NrRoot 'nexroute.bat') -WorkingDirectory $script:NrRoot | Out-Null })

$timer=New-Object Windows.Forms.Timer
$timer.Interval=5000
$timer.add_Tick({
    $running=Test-NrServiceRunning -Name zapret
    $notify.Icon=if ($running) { [Drawing.SystemIcons]::Shield } else { [Drawing.SystemIcons]::Warning }
    $text='NexRoute | ' + $(if ($running) { 'RUNNING' } else { 'STOPPED' }) + ' | ' + (Get-NrInstalledStrategy)
    $notify.Text=$text.Substring(0,[Math]::Min(63,$text.Length))
})
$timer.Start()
[Windows.Forms.Application]::Run()
