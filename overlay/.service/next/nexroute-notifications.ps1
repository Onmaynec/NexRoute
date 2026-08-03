Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

if (-not (Get-Variable -Name NrLegacySendNotification -Scope Script -ErrorAction SilentlyContinue)) {
    $script:NrLegacySendNotification=$null
}
if (-not $script:NrLegacySendNotification) {
    $existing=Get-Command Send-NrNotification -CommandType Function -ErrorAction SilentlyContinue
    if ($existing) { $script:NrLegacySendNotification=${function:Send-NrNotification} }
}

function ConvertTo-NrNotificationBase64 {
    param([AllowEmptyString()][string]$Value)
    return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([string]$Value))
}

function ConvertTo-NrToastXmlText {
    param([AllowEmptyString()][string]$Value)
    $normalized=([string]$Value) -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]',''
    return [Security.SecurityElement]::Escape($normalized)
}

function New-NrToastPayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][string]$Level,
        [int]$TimeoutMilliseconds=5000,
        [string]$AppId='NexRoute'
    )
    $boundedTimeout=[Math]::Min(15000,[Math]::Max(1000,$TimeoutMilliseconds))
    $normalizedLevel=switch ($Level.ToLowerInvariant()) {
        'error' { 'ERROR' }
        'warning' { 'WARNING' }
        'warn' { 'WARNING' }
        default { 'INFO' }
    }
    $titleXml=ConvertTo-NrToastXmlText -Value $Title
    $messageXml=ConvertTo-NrToastXmlText -Value $Message
    $levelXml=ConvertTo-NrToastXmlText -Value ("NexRoute · $normalizedLevel")
    $xml='<toast duration="short"><visual><binding template="ToastGeneric"><text>'+$titleXml+'</text><text>'+$messageXml+'</text><text placement="attribution">'+$levelXml+'</text></binding></visual></toast>'
    return [pscustomobject][ordered]@{
        appId=$AppId
        title=$Title
        message=$Message
        level=$normalizedLevel.ToLowerInvariant()
        timeoutMilliseconds=$boundedTimeout
        xml=$xml
    }
}

function Invoke-NrWindowsToastNotification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][string]$Level,
        [int]$TimeoutMilliseconds=5000,
        [string]$AppId='NexRoute',
        [scriptblock]$Runner
    )
    $payload=New-NrToastPayload -Title $Title -Message $Message -Level $Level -TimeoutMilliseconds $TimeoutMilliseconds -AppId $AppId
    if ($Runner) {
        $result=& $Runner $payload
        if ($null -eq $result) { throw 'Toast runner returned no delivery result.' }
        if ($result.PSObject.Properties['setting'] -and [string]$result.setting -ne 'Enabled') {
            throw "Toast notifications are disabled: $($result.setting)."
        }
        if (-not $result.PSObject.Properties['delivered'] -or -not [bool]$result.delivered) {
            throw 'Toast runner did not confirm delivery.'
        }
        return [pscustomobject]@{ delivered=$true; channel='windows-toast'; appId=$payload.appId; setting='Enabled'; payload=$payload }
    }
    if ($env:OS -ne 'Windows_NT') { throw 'Windows toast notifications are unavailable on this platform.' }

    Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction Stop
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime] | Out-Null
    [Windows.UI.Notifications.ToastNotification, Windows.UI.Notifications, ContentType=WindowsRuntime] | Out-Null
    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType=WindowsRuntime] | Out-Null

    $document=New-Object Windows.Data.Xml.Dom.XmlDocument
    $document.LoadXml($payload.xml)
    $toast=New-Object Windows.UI.Notifications.ToastNotification $document
    $toast.ExpirationTime=[DateTimeOffset]::Now.AddMilliseconds($payload.timeoutMilliseconds)
    $notifier=[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($payload.appId)
    $setting=[string]$notifier.Setting
    if ($setting -ne 'Enabled') { throw "Toast notifications are disabled: $setting." }
    $notifier.Show($toast)
    return [pscustomobject]@{ delivered=$true; channel='windows-toast'; appId=$payload.appId; setting=$setting; payload=$payload }
}

function Write-NrNotificationHistory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][string]$Level,
        [Parameter(Mandatory)][string]$Channel,
        [string]$ErrorMessage,
        [string[]]$Attempts=@()
    )
    $directory=Join-Path $Root '.service/notifications/history'
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $stamp=[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fffffff')
    $path=Join-Path $directory ($stamp+'-'+[guid]::NewGuid().ToString('N')+'.json')
    $record=[ordered]@{
        schemaVersion=1
        timestampUtc=[DateTime]::UtcNow.ToString('o')
        title=$Title
        message=$Message
        level=$Level
        channel=$Channel
        attempts=[string[]]$Attempts
        processId=$PID
        error=$ErrorMessage
    }
    $temporary=$path+'.tmp'
    [IO.File]::WriteAllText($temporary,($record | ConvertTo-Json -Depth 8)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $path -Force
    return $path
}

function Invoke-NrNativeNotification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][string]$Level,
        [int]$TimeoutMilliseconds=5000,
        [scriptblock]$Runner
    )
    if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) { throw "Native notifier is missing: $Executable" }
    $normalizedLevel=switch ($Level.ToLowerInvariant()) {
        'error' { 'error' }
        'warning' { 'warning' }
        'warn' { 'warning' }
        default { 'info' }
    }
    $arguments=[string[]]@(
        '--title64',(ConvertTo-NrNotificationBase64 -Value $Title),
        '--message64',(ConvertTo-NrNotificationBase64 -Value $Message),
        '--level',$normalizedLevel,
        '--timeout',[string]([Math]::Min(15000,[Math]::Max(1000,$TimeoutMilliseconds)))
    )
    if ($Runner) {
        $result=& $Runner $Executable $arguments
        if ($null -ne $result -and $result.PSObject.Properties['exitCode'] -and [int]$result.exitCode -ne 0) {
            throw "Native notifier runner returned exit code $($result.exitCode)."
        }
        return [pscustomobject]@{ started=$true; executable=$Executable; arguments=$arguments; processId=$(if ($result -and $result.PSObject.Properties['processId']) { [int]$result.processId } else { 0 }) }
    }
    $process=Start-Process -FilePath $Executable -ArgumentList $arguments -WindowStyle Hidden -PassThru
    return [pscustomobject]@{ started=$true; executable=$Executable; arguments=$arguments; processId=$process.Id }
}

function Send-NrNotification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('Info','Warning','Error')][string]$Level='Info',
        [string]$Root,
        [int]$TimeoutMilliseconds=5000,
        [string]$ToastAppId='NexRoute',
        [switch]$DisableToast,
        [scriptblock]$ToastRunner,
        [scriptblock]$Runner,
        [scriptblock]$Fallback
    )
    if (-not $Root) {
        if (Get-Variable -Name NrRoot -Scope Script -ErrorAction SilentlyContinue) { $Root=[string]$script:NrRoot }
        else { $Root=(Get-Location).Path }
    }
    $rootPath=[IO.Path]::GetFullPath($Root)
    $channel='console'
    $attempts=New-Object 'System.Collections.Generic.List[string]'
    $errors=New-Object 'System.Collections.Generic.List[string]'
    $native=Join-Path $rootPath '.service/native/NexRoute.Notifier.exe'
    $toastDisabled=$DisableToast -or $env:NEXROUTE_DISABLE_TOAST -eq '1'

    try {
        $attempts.Add('windows-toast')
        if ($toastDisabled) { throw 'Toast notifications are disabled by NexRoute configuration.' }
        if (-not $ToastRunner -and $env:OS -ne 'Windows_NT') { throw 'Windows toast notifications are unavailable on this platform.' }
        Invoke-NrWindowsToastNotification -Title $Title -Message $Message -Level $Level -TimeoutMilliseconds $TimeoutMilliseconds -AppId $ToastAppId -Runner $ToastRunner | Out-Null
        $channel='windows-toast'
    } catch {
        $errors.Add('windows-toast: '+$_.Exception.Message)
    }

    if ($channel -eq 'console') {
        try {
            $attempts.Add('native-balloon')
            if ($env:OS -eq 'Windows_NT' -and (Test-Path -LiteralPath $native -PathType Leaf)) {
                Invoke-NrNativeNotification -Executable $native -Title $Title -Message $Message -Level $Level -TimeoutMilliseconds $TimeoutMilliseconds -Runner $Runner | Out-Null
                $channel='native-balloon'
            } else {
                throw 'Native notifier is unavailable.'
            }
        } catch {
            $errors.Add('native-balloon: '+$_.Exception.Message)
        }
    }

    if ($channel -eq 'console') {
        try {
            if ($Fallback) { $attempts.Add('injected-fallback'); & $Fallback $Title $Message $Level | Out-Null; $channel='injected-fallback' }
            elseif ($script:NrLegacySendNotification) { $attempts.Add('powershell-fallback'); & $script:NrLegacySendNotification -Title $Title -Message $Message -Level $Level; $channel='powershell-fallback' }
            else { $attempts.Add('console'); Write-Host ("[{0}] {1}: {2}" -f $Level.ToUpperInvariant(),$Title,$Message); $channel='console' }
        } catch {
            $errors.Add('fallback: '+$_.Exception.Message)
            $attempts.Add('console')
            Write-Host ("[{0}] {1}: {2}" -f $Level.ToUpperInvariant(),$Title,$Message)
            $channel='console'
        }
    }

    $errorMessage=if ($errors.Count -gt 0) { $errors -join ' ' } else { $null }
    $history=Write-NrNotificationHistory -Root $rootPath -Title $Title -Message $Message -Level $Level -Channel $channel -ErrorMessage $errorMessage -Attempts $attempts.ToArray()
    return [pscustomobject]@{ delivered=($channel -ne 'console'); channel=$channel; attempts=$attempts.ToArray(); historyPath=$history; error=$errorMessage }
}
