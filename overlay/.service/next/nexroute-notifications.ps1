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

function Write-NrNotificationHistory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][string]$Level,
        [Parameter(Mandatory)][string]$Channel,
        [string]$ErrorMessage
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
        [scriptblock]$Runner,
        [scriptblock]$Fallback
    )
    if (-not $Root) {
        if (Get-Variable -Name NrRoot -Scope Script -ErrorAction SilentlyContinue) { $Root=[string]$script:NrRoot }
        else { $Root=(Get-Location).Path }
    }
    $rootPath=[IO.Path]::GetFullPath($Root)
    $channel='console'
    $errorMessage=$null
    $native=Join-Path $rootPath '.service/native/NexRoute.Notifier.exe'
    try {
        if ($env:OS -eq 'Windows_NT' -and (Test-Path -LiteralPath $native -PathType Leaf)) {
            $result=Invoke-NrNativeNotification -Executable $native -Title $Title -Message $Message -Level $Level -TimeoutMilliseconds $TimeoutMilliseconds -Runner $Runner
            $channel='native-balloon'
        } else {
            throw 'Native notifier is unavailable.'
        }
    } catch {
        $errorMessage=$_.Exception.Message
        try {
            if ($Fallback) { & $Fallback $Title $Message $Level | Out-Null; $channel='injected-fallback' }
            elseif ($script:NrLegacySendNotification) { & $script:NrLegacySendNotification -Title $Title -Message $Message -Level $Level; $channel='powershell-fallback' }
            else { Write-Host ("[{0}] {1}: {2}" -f $Level.ToUpperInvariant(),$Title,$Message); $channel='console' }
        } catch {
            $errorMessage=$errorMessage+' Fallback failed: '+$_.Exception.Message
            Write-Host ("[{0}] {1}: {2}" -f $Level.ToUpperInvariant(),$Title,$Message)
            $channel='console'
        }
    }
    $history=Write-NrNotificationHistory -Root $rootPath -Title $Title -Message $Message -Level $Level -Channel $channel -ErrorMessage $errorMessage
    return [pscustomobject]@{ delivered=($channel -ne 'console'); channel=$channel; historyPath=$history; error=$errorMessage }
}
