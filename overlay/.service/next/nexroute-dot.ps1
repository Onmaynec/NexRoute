Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

function Read-NrDnsProxyToolDefinition {
    [CmdletBinding()]
    param([string]$ManifestPath)
    if (-not $ManifestPath) { $ManifestPath=Join-Path $script:NrService 'portable-tools.json' }
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw "Portable tools manifest is missing: $ManifestPath" }
    $manifest=Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$manifest.schemaVersion -ne 1) { throw 'Portable tools manifest schemaVersion must be 1.' }
    $tool=$manifest.tools.dnsproxy
    if (-not $tool) { throw 'Portable tools manifest has no dnsproxy definition.' }
    if ([string]$tool.repository -ne 'AdguardTeam/dnsproxy') { throw 'DoT resolver repository must be AdguardTeam/dnsproxy.' }
    if ([string]$tool.assetUrl -notmatch '^https://github\.com/AdguardTeam/dnsproxy/releases/download/v[0-9]+\.[0-9]+\.[0-9]+/') { throw 'DoT resolver URL is not an official immutable release URL.' }
    if ([string]$tool.sha256 -notmatch '^[0-9a-fA-F]{64}$') { throw 'DoT resolver SHA-256 is invalid.' }
    if ([long]$tool.minimumBytes -lt 1000000) { throw 'DoT resolver minimumBytes is unsafe.' }
    if ([string]$tool.executableFileName -ne 'dnsproxy.exe') { throw 'DoT resolver executable must be dnsproxy.exe.' }
    return $tool
}

function Test-NrDnsProxyCache {
    param([Parameter(Mandatory)][string]$CacheDirectory,[Parameter(Mandatory)]$Tool,[switch]$SkipVersionProbe)
    $receiptPath=Join-Path $CacheDirectory 'verified-tool.json'
    $executable=Join-Path $CacheDirectory 'bin/dnsproxy.exe'
    if (-not (Test-Path -LiteralPath $receiptPath -PathType Leaf) -or -not (Test-Path -LiteralPath $executable -PathType Leaf)) { return $null }
    try {
        $receipt=Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([int]$receipt.schemaVersion -ne 1 -or [string]$receipt.version -ne [string]$Tool.version -or [string]$receipt.archiveSha256 -ne ([string]$Tool.sha256).ToLowerInvariant()) { return $null }
        $actual=(Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne [string]$receipt.executableSha256) { return $null }
        if (-not $SkipVersionProbe -and $env:OS -eq 'Windows_NT') {
            $output=@(& $executable --version 2>&1) -join "`n"
            if ($LASTEXITCODE -ne 0 -or $output -notmatch [regex]::Escape([string]$Tool.version)) { return $null }
        }
        return [pscustomobject]@{ executable=[IO.Path]::GetFullPath($executable); receipt=$receiptPath; executableSha256=$actual; cached=$true }
    } catch { return $null }
}

function Get-NrDnsProxyBinary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [string]$ManifestPath,
        [string]$ArchivePath,
        [switch]$SkipVersionProbe
    )
    $rootPath=[IO.Path]::GetFullPath($Root)
    if (-not $ManifestPath) { $ManifestPath=Join-Path $rootPath '.service/portable-tools.json' }
    $tool=Read-NrDnsProxyToolDefinition -ManifestPath $ManifestPath
    $cacheDirectory=Join-Path $rootPath ('.service/tools/dnsproxy/'+[string]$tool.version)
    $cached=Test-NrDnsProxyCache -CacheDirectory $cacheDirectory -Tool $tool -SkipVersionProbe:$SkipVersionProbe
    if ($cached) { return $cached }

    $downloads=Join-Path $rootPath '.service/tools/downloads'
    New-Item -ItemType Directory -Path $downloads -Force | Out-Null
    $temporaryArchive=Join-Path $downloads (([string]$tool.assetName)+'.tmp-'+[guid]::NewGuid().ToString('N'))
    $staging=$cacheDirectory+'.staging-'+[guid]::NewGuid().ToString('N')
    try {
        if ($ArchivePath) { Copy-Item -LiteralPath $ArchivePath -Destination $temporaryArchive -Force }
        else {
            Invoke-WebRequest -Uri ([string]$tool.assetUrl) -OutFile $temporaryArchive -UseBasicParsing -TimeoutSec 180 -Headers @{
                Accept='application/octet-stream'
                'User-Agent'='NexRoute-DoT-Resolver/0.6.0'
            }
        }
        $archive=Test-NrPortableToolArchive -Path $temporaryArchive -Tool $tool
        $expanded=Join-Path $staging 'expanded'
        Expand-NrPortableToolArchive -ArchivePath $temporaryArchive -Destination $expanded | Out-Null
        $matches=@(Get-ChildItem -LiteralPath $expanded -Filter 'dnsproxy.exe' -File -Recurse -ErrorAction Stop)
        if ($matches.Count -ne 1) { throw "Expected exactly one dnsproxy.exe in the resolver archive, found $($matches.Count)." }
        $bin=Join-Path $staging 'bin'
        New-Item -ItemType Directory -Path $bin -Force | Out-Null
        $canonical=Join-Path $bin 'dnsproxy.exe'
        Copy-Item -LiteralPath $matches[0].FullName -Destination $canonical -Force
        Remove-Item -LiteralPath $expanded -Recurse -Force
        if (-not $SkipVersionProbe -and $env:OS -eq 'Windows_NT') {
            $output=@(& $canonical --version 2>&1) -join "`n"
            if ($LASTEXITCODE -ne 0 -or $output -notmatch [regex]::Escape([string]$tool.version)) { throw "dnsproxy version probe failed. Expected $($tool.version)." }
        }
        $executableSha=(Get-FileHash -LiteralPath $canonical -Algorithm SHA256).Hash.ToLowerInvariant()
        $receipt=[ordered]@{
            schemaVersion=1; verifiedUtc=[DateTime]::UtcNow.ToString('o'); version=[string]$tool.version;
            repository=[string]$tool.repository; assetName=[string]$tool.assetName; archiveSha256=[string]$archive.sha256;
            executableRelativePath='bin/dnsproxy.exe'; executableSha256=$executableSha
        }
        [IO.File]::WriteAllText((Join-Path $staging 'verified-tool.json'),($receipt | ConvertTo-Json -Depth 8)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
        if (Test-Path -LiteralPath $cacheDirectory) { Remove-Item -LiteralPath $cacheDirectory -Recurse -Force }
        $parent=Split-Path -Parent $cacheDirectory
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
        Move-Item -LiteralPath $staging -Destination $cacheDirectory -Force
        $verified=Test-NrDnsProxyCache -CacheDirectory $cacheDirectory -Tool $tool -SkipVersionProbe:$SkipVersionProbe
        if (-not $verified) { throw 'DoT resolver cache verification failed after installation.' }
        $verified.cached=$false
        return $verified
    } finally {
        Remove-Item -LiteralPath $temporaryArchive -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function ConvertTo-NrDotUpstreamUri {
    param([Parameter(Mandatory)]$Provider)
    $value=[string]$Provider.dot
    if ([string]::IsNullOrWhiteSpace($value)) { throw "DNS provider '$($Provider.id)' has no DNS-over-TLS endpoint." }
    if ($value -notmatch '^tls://') { $value='tls://'+$value }
    $uri=[Uri]$value
    if ($uri.Scheme -ne 'tls' -or [string]::IsNullOrWhiteSpace($uri.Host)) { throw "Invalid DNS-over-TLS endpoint: $value" }
    return $value
}

function New-NrDnsProxyArguments {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Provider,[Parameter(Mandatory)][string]$LogPath)
    $upstream=ConvertTo-NrDotUpstreamUri -Provider $Provider
    $arguments=New-Object 'System.Collections.Generic.List[string]'
    foreach ($item in @('-l','127.0.0.1','-l','::1','-p','53','-u',$upstream,'--upstream-mode','parallel','--cache','--cache-size','4194304','--pending-requests-enabled','--refuse-any','--timeout','10s','--output',$LogPath)) { $arguments.Add([string]$item) }
    foreach ($address in @($Provider.ipv4 | Select-Object -First 2)) {
        if ([string]$address) { $arguments.Add('-b'); $arguments.Add(([string]$address)+':53') }
    }
    return $arguments.ToArray()
}

function Get-NrDnsAdapterSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Adapters)
    $rows=New-Object 'System.Collections.Generic.List[object]'
    foreach ($adapter in $Adapters) {
        $index=[int]$adapter.ifIndex
        foreach ($family in @('IPv4','IPv6')) {
            $addresses=@()
            try {
                $entry=Get-DnsClientServerAddress -InterfaceIndex $index -AddressFamily $family -ErrorAction Stop
                $addresses=@($entry.ServerAddresses | Where-Object { $_ })
            } catch { }
            $rows.Add([pscustomobject]@{ interfaceIndex=$index; interfaceAlias=[string]$adapter.Name; addressFamily=$family; serverAddresses=[string[]]$addresses })
        }
    }
    return $rows.ToArray()
}

function Save-NrDnsAdapterSnapshot {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][object[]]$Snapshot)
    $directory=Join-Path $Root '.service/dns-backups'
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $path=Join-Path $directory ('dns-before-dot-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')+'.json')
    $document=[ordered]@{ schemaVersion=1; createdUtc=[DateTime]::UtcNow.ToString('o'); entries=$Snapshot }
    [IO.File]::WriteAllText($path,($document | ConvertTo-Json -Depth 12)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
    return $path
}

function Restore-NrDnsAdapterSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$Snapshot)
    foreach ($entry in $Snapshot) {
        $addresses=[string[]]@($entry.serverAddresses)
        if ($addresses.Count -gt 0) {
            Set-DnsClientServerAddress -InterfaceIndex ([int]$entry.interfaceIndex) -ServerAddresses $addresses -ErrorAction Stop
        } else {
            Set-DnsClientServerAddress -InterfaceIndex ([int]$entry.interfaceIndex) -ResetServerAddresses -ErrorAction Stop
        }
    }
    Clear-DnsClientCache -ErrorAction SilentlyContinue
}

function Get-NrDotRuntimeDirectory {
    param([Parameter(Mandatory)][string]$Root)
    $path=Join-Path $Root '.service/dot'
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

function Stop-NrDotRuntime {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root,[switch]$KeepTask)
    $runtime=Get-NrDotRuntimeDirectory -Root $Root
    $pidPath=Join-Path $runtime 'dnsproxy.pid'
    if (Test-Path -LiteralPath $pidPath -PathType Leaf) {
        try {
            $resolverPid=[int](Get-Content -LiteralPath $pidPath -Raw).Trim()
            if ($resolverPid -gt 0) { Stop-Process -Id $resolverPid -Force -ErrorAction SilentlyContinue }
        } catch { }
        Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
    }
    if (-not $KeepTask -and $env:OS -eq 'Windows_NT') {
        Unregister-ScheduledTask -TaskName 'NexRoute DoT Resolver' -Confirm:$false -ErrorAction SilentlyContinue
    }
}

function Register-NrDotRuntimeTask {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$Executable,[Parameter(Mandatory)][string[]]$Arguments)
    if ($env:OS -ne 'Windows_NT') { return $null }
    $quoted=($Arguments | ForEach-Object { if ($_ -match '[\s"]') { '"'+$_.Replace('"','\"')+'"' } else { $_ } }) -join ' '
    $action=New-ScheduledTaskAction -Execute $Executable -Argument $quoted -WorkingDirectory $Root
    $trigger=New-ScheduledTaskTrigger -AtLogOn
    $settings=New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 5 -RestartInterval (New-TimeSpan -Minutes 1)
    Register-ScheduledTask -TaskName 'NexRoute DoT Resolver' -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest -Force | Out-Null
    return 'NexRoute DoT Resolver'
}

function Start-NrDotRuntime {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$Executable,[Parameter(Mandatory)][string[]]$Arguments)
    Stop-NrDotRuntime -Root $Root
    $process=Start-Process -FilePath $Executable -ArgumentList $Arguments -WorkingDirectory $Root -WindowStyle Hidden -PassThru
    $runtime=Get-NrDotRuntimeDirectory -Root $Root
    [IO.File]::WriteAllText((Join-Path $runtime 'dnsproxy.pid'),[string]$process.Id,[Text.Encoding]::ASCII)
    Register-NrDotRuntimeTask -Root $Root -Executable $Executable -Arguments $Arguments | Out-Null
    return [pscustomobject]@{ pid=$process.Id; executable=$Executable; arguments=$Arguments }
}

function Test-NrDotResolver {
    [CmdletBinding()]
    param([string]$Server='127.0.0.1',[string]$Name='example.com',[int]$Attempts=20)
    $lastError=$null
    for ($attempt=1;$attempt -le $Attempts;$attempt++) {
        try {
            $answer=@(Resolve-DnsName -Name $Name -Server $Server -DnsOnly -ErrorAction Stop)
            if ($answer.Count -gt 0) { return [pscustomobject]@{ ok=$true; server=$Server; name=$Name; attempts=$attempt; answers=$answer.Count; error=$null } }
        } catch { $lastError=$_.Exception.Message }
        Start-Sleep -Milliseconds 250
    }
    return [pscustomobject]@{ ok=$false; server=$Server; name=$Name; attempts=$Attempts; answers=0; error=$lastError }
}

function Write-NrDotTransactionRecord {
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$Status,[Parameter(Mandatory)]$Provider,[string]$SnapshotPath,[object]$Probe,[object]$Runtime,[string]$Message)
    $runtimeDirectory=Get-NrDotRuntimeDirectory -Root $Root
    $record=[ordered]@{
        schemaVersion=1; timestampUtc=[DateTime]::UtcNow.ToString('o'); status=$Status; provider=[string]$Provider.id;
        upstream=ConvertTo-NrDotUpstreamUri -Provider $Provider; snapshotPath=$SnapshotPath; probe=$Probe; runtime=$Runtime; message=$Message
    }
    $path=Join-Path $runtimeDirectory 'transaction.json'
    [IO.File]::WriteAllText($path,($record | ConvertTo-Json -Depth 12)+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
    return $path
}

function Invoke-NrDotTransaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)]$Provider,
        [Parameter(Mandatory)][object[]]$Adapters,
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][string[]]$Arguments,
        [scriptblock]$SnapshotReader,
        [scriptblock]$RuntimeStarter,
        [scriptblock]$LoopbackSetter,
        [scriptblock]$Probe,
        [scriptblock]$SnapshotRestorer,
        [scriptblock]$RuntimeStopper
    )
    $snapshot=if ($SnapshotReader) { & $SnapshotReader $Adapters } else { Get-NrDnsAdapterSnapshot -Adapters $Adapters }
    $snapshotPath=Save-NrDnsAdapterSnapshot -Root $Root -Snapshot $snapshot
    Write-NrDotTransactionRecord -Root $Root -Status 'verifying' -Provider $Provider -SnapshotPath $snapshotPath -Probe $null -Runtime $null -Message 'Starting local DNS-over-TLS resolver.' | Out-Null
    $runtime=$null
    try {
        $runtime=if ($RuntimeStarter) { & $RuntimeStarter $Root $Executable $Arguments } else { Start-NrDotRuntime -Root $Root -Executable $Executable -Arguments $Arguments }
        $directProbe=if ($Probe) { & $Probe 'direct' } else { Test-NrDotResolver -Server '127.0.0.1' }
        if (-not $directProbe -or -not [bool]$directProbe.ok) { throw 'Local DNS-over-TLS resolver did not answer a direct loopback query.' }
        if ($LoopbackSetter) { & $LoopbackSetter $Adapters }
        else {
            foreach ($adapter in $Adapters) { Set-DnsClientServerAddress -InterfaceIndex ([int]$adapter.ifIndex) -ServerAddresses @('127.0.0.1','::1') -ErrorAction Stop }
            Clear-DnsClientCache -ErrorAction SilentlyContinue
        }
        $systemProbe=if ($Probe) { & $Probe 'system' } else {
            try { $answer=@(Resolve-DnsName -Name 'example.com' -DnsOnly -ErrorAction Stop); [pscustomobject]@{ ok=($answer.Count -gt 0); answers=$answer.Count } }
            catch { [pscustomobject]@{ ok=$false; error=$_.Exception.Message } }
        }
        if (-not $systemProbe -or -not [bool]$systemProbe.ok) { throw 'Windows DNS resolution failed after switching adapters to the local DoT resolver.' }
        $message='DNS-over-TLS resolver was committed.'
        Write-NrDotTransactionRecord -Root $Root -Status 'committed' -Provider $Provider -SnapshotPath $snapshotPath -Probe $systemProbe -Runtime $runtime -Message $message | Out-Null
        return [pscustomobject]@{ status='committed'; committed=$true; snapshotPath=$snapshotPath; runtime=$runtime; directProbe=$directProbe; systemProbe=$systemProbe; message=$message }
    } catch {
        $failure=$_.Exception.Message
        try {
            if ($SnapshotRestorer) { & $SnapshotRestorer $snapshot } else { Restore-NrDnsAdapterSnapshot -Snapshot $snapshot }
        } finally {
            if ($RuntimeStopper) { & $RuntimeStopper $Root } else { Stop-NrDotRuntime -Root $Root }
        }
        $message=$failure+' Previous DNS settings were restored.'
        Write-NrDotTransactionRecord -Root $Root -Status 'rolled-back' -Provider $Provider -SnapshotPath $snapshotPath -Probe $null -Runtime $runtime -Message $message | Out-Null
        return [pscustomobject]@{ status='rolled-back'; committed=$false; snapshotPath=$snapshotPath; runtime=$runtime; directProbe=$null; systemProbe=$null; message=$message }
    }
}

function Enable-NrDnsOverTls {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Provider,[Parameter(Mandatory)][object[]]$Adapters)
    if ($env:OS -ne 'Windows_NT') { throw 'The NexRoute DoT resolver is supported on Windows only.' }
    $resolver=Get-NrDnsProxyBinary -Root $script:NrRoot
    $runtime=Get-NrDotRuntimeDirectory -Root $script:NrRoot
    $logPath=Join-Path $runtime 'dnsproxy.log'
    $arguments=New-NrDnsProxyArguments -Provider $Provider -LogPath $logPath
    $transaction=Invoke-NrDotTransaction -Root $script:NrRoot -Provider $Provider -Adapters $Adapters -Executable $resolver.executable -Arguments $arguments
    if (-not $transaction.committed) { throw $transaction.message }
    $script:NrState.dnsProvider=[string]$Provider.id
    $script:NrState.dnsEncryption='dot'
    $script:NrState.dotResolverVersion='0.81.4'
    $script:NrState.dotSnapshotPath=[string]$transaction.snapshotPath
    Save-NrState
    Write-NrLog -Level INFO -Message 'DNS-over-TLS resolver committed' -Data @{ provider=$Provider.id; pid=$transaction.runtime.pid; snapshot=$transaction.snapshotPath }
    return $transaction
}

if (-not $script:NrLegacySetDnsProvider) { $script:NrLegacySetDnsProvider=${function:Set-NrDnsProvider} }
function Set-NrDnsProvider {
    param([Parameter(Mandatory)]$Provider,[Parameter(Mandatory)][object[]]$Adapters,[ValidateSet('system','plain','doh','dot')][string]$Encryption='plain')
    if ($Encryption -eq 'dot') { return Enable-NrDnsOverTls -Provider $Provider -Adapters $Adapters }
    Stop-NrDotRuntime -Root $script:NrRoot
    return & $script:NrLegacySetDnsProvider -Provider $Provider -Adapters $Adapters -Encryption $Encryption
}

function Show-NrDnsProviderMenu {
    $providers=Get-NrDnsProviders
    $providerItems=@($providers | ForEach-Object { New-NrMenuItem -Id $_.id -Label $_.name -Section (T 'dnsProvider') -Status $(if ($_.id -eq [string]$script:NrState.dnsProvider) { T 'current' } else { '' }) })
    $providerId=Invoke-NrMenu -Title (T 'dnsProvider') -Items $providerItems -AllowEscape
    if (-not $providerId) { return }
    $provider=$providers | Where-Object { $_.id -eq $providerId } | Select-Object -First 1
    $adapters=@(Get-NrActiveAdapters)
    if ($adapters.Count -eq 0) { Show-NrMessage -Title (T 'dnsProvider') -Message 'No active adapters.' -Color Red; return }
    $adapterItems=@($adapters | ForEach-Object { [pscustomobject]@{ Id=[string]$_.ifIndex; Label=[string]$_.Name; Status=[string]$_.LinkSpeed } })
    $selected=Invoke-NrMultiSelect -Title (T 'adapters') -Items $adapterItems -SelectedIds @($adapterItems | ForEach-Object { $_.Id })
    if ($null -eq $selected -or $selected.Count -eq 0) { return }
    $chosen=@($adapters | Where-Object { $selected -contains [string]$_.ifIndex })
    $encryption='system'
    if ($provider.id -ne 'system') {
        $encryptionItems=@(
            New-NrMenuItem -Id 'plain' -Label 'Plain DNS' -Section (T 'dnsProvider')
            New-NrMenuItem -Id 'doh' -Label (T 'doh') -Section (T 'dnsProvider')
            New-NrMenuItem -Id 'dot' -Label (T 'dot') -Section (T 'dnsProvider') -Status 'LOCAL TLS RESOLVER'
        )
        $encryption=Invoke-NrMenu -Title (T 'dnsProvider') -Items $encryptionItems -AllowEscape
        if (-not $encryption) { return }
    }
    try { Set-NrDnsProvider -Provider $provider -Adapters $chosen -Encryption $encryption; Show-NrMessage -Title (T 'dnsProvider') -Message (T 'operationComplete') -Color Green }
    catch { Show-NrMessage -Title (T 'operationFailed') -Message $_.Exception.Message -Color Red }
}
