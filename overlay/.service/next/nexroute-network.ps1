Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-NrActiveAdapters {
    try {
        return @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' } | Sort-Object ifIndex)
    } catch { return @() }
}

function Get-NrDnsProviders {
    return @(
        [pscustomobject]@{ id='system'; name='System / DHCP'; ipv4=@(); ipv6=@(); doh=$null; dot=$null },
        [pscustomobject]@{ id='cloudflare'; name='Cloudflare'; ipv4=@('1.1.1.1','1.0.0.1'); ipv6=@('2606:4700:4700::1111','2606:4700:4700::1001'); doh='https://cloudflare-dns.com/dns-query'; dot='cloudflare-dns.com:853' },
        [pscustomobject]@{ id='google'; name='Google Public DNS'; ipv4=@('8.8.8.8','8.8.4.4'); ipv6=@('2001:4860:4860::8888','2001:4860:4860::8844'); doh='https://dns.google/dns-query'; dot='dns.google:853' },
        [pscustomobject]@{ id='quad9'; name='Quad9'; ipv4=@('9.9.9.9','149.112.112.112'); ipv6=@('2620:fe::fe','2620:fe::9'); doh='https://dns.quad9.net/dns-query'; dot='dns.quad9.net:853' },
        [pscustomobject]@{ id='adguard'; name='AdGuard DNS'; ipv4=@('94.140.14.14','94.140.15.15'); ipv6=@('2a10:50c0::ad1:ff','2a10:50c0::ad2:ff'); doh='https://dns.adguard-dns.com/dns-query'; dot='dns.adguard-dns.com:853' }
    )
}

function Set-NrDnsProvider {
    param([Parameter(Mandatory)]$Provider,[Parameter(Mandatory)][object[]]$Adapters,[ValidateSet('system','plain','doh','dot')][string]$Encryption='plain')
    foreach ($adapter in $Adapters) {
        $alias=[string]$adapter.Name
        if ($Provider.id -eq 'system') {
            Set-DnsClientServerAddress -InterfaceAlias $alias -ResetServerAddresses -ErrorAction Stop
            continue
        }
        $addresses=@($Provider.ipv4 + $Provider.ipv6)
        Set-DnsClientServerAddress -InterfaceAlias $alias -ServerAddresses $addresses -ErrorAction Stop
        if ($Encryption -eq 'doh') {
            foreach ($address in $addresses) {
                & netsh.exe dnsclient delete encryption server=$address protocol=doh 2>$null | Out-Null
                & netsh.exe dnsclient add encryption server=$address dohtemplate=$($Provider.doh) autoupgrade=yes udpfallback=no | Out-Null
            }
            & netsh.exe dnsclient set global doh=yes dot=no | Out-Null
        }
        elseif ($Encryption -eq 'dot') {
            foreach ($address in $addresses) {
                & netsh.exe dnsclient delete encryption server=$address protocol=dot 2>$null | Out-Null
                & netsh.exe dnsclient add encryption server=$address dothost=$($Provider.dot) autoupgrade=yes udpfallback=no | Out-Null
            }
            & netsh.exe dnsclient set global dot=yes doh=no | Out-Null
        }
        else {
            & netsh.exe dnsclient set global doh=no dot=no | Out-Null
        }
    }
    Clear-DnsClientCache -ErrorAction SilentlyContinue
    $script:NrState.dnsProvider=[string]$Provider.id
    $script:NrState.dnsEncryption=$Encryption
    Save-NrState
    Write-NrLog -Level INFO -Message 'DNS provider changed' -Data @{ provider=$Provider.id; encryption=$Encryption; adapters=@($Adapters | ForEach-Object { $_.Name }) }
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
            New-NrMenuItem -Id 'dot' -Label (T 'dot') -Section (T 'dnsProvider') -Status (T 'experimental')
        )
        $encryption=Invoke-NrMenu -Title (T 'dnsProvider') -Items $encryptionItems -AllowEscape
        if (-not $encryption) { return }
    }
    try { Set-NrDnsProvider -Provider $provider -Adapters $chosen -Encryption $encryption; Show-NrMessage -Title (T 'dnsProvider') -Message (T 'operationComplete') -Color Green }
    catch { Show-NrMessage -Title (T 'operationFailed') -Message $_.Exception.Message -Color Red }
}

function Invoke-NrDnsDiagnostics {
    $report=New-Object 'System.Collections.Generic.List[object]'
    $servers=@()
    try { $servers=@(Get-DnsClientServerAddress -ErrorAction Stop | Where-Object { $_.ServerAddresses.Count -gt 0 }) } catch { }
    foreach ($entry in $servers) {
        foreach ($server in @($entry.ServerAddresses)) {
            $watch=[Diagnostics.Stopwatch]::StartNew()
            $ok=$false; $error=$null
            try {
                Resolve-DnsName -Name 'www.youtube.com' -Server $server -DnsOnly -ErrorAction Stop | Out-Null
                $ok=$true
            } catch { $error=$_.Exception.Message }
            $watch.Stop()
            $report.Add([pscustomobject]@{ adapter=$entry.InterfaceAlias; family=$entry.AddressFamily; server=$server; ok=$ok; latencyMs=[math]::Round($watch.Elapsed.TotalMilliseconds,2); error=$error })
        }
    }
    Write-NrHeader -Title (T 'dnsDiagnostics')
    foreach ($item in $report) {
        Write-Host ('  {0,-20} {1,-39} {2,8:N1} ms  {3}' -f $item.adapter,$item.server,$item.latencyMs,$(if ($item.ok) { 'OK' } else { 'FAIL' })) -ForegroundColor $(if ($item.ok) { [ConsoleColor]::Green } else { [ConsoleColor]::Red })
    }
    Write-Host ''
    Write-Host '  netsh dnsclient show global' -ForegroundColor DarkGray
    try { & netsh.exe dnsclient show global } catch { }
    Wait-NrKey
    $path=Join-Path $script:NrHistoryDir ('dns-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '.json')
    [System.IO.File]::WriteAllText($path,($report | ConvertTo-Json -Depth 10)+[Environment]::NewLine,(New-Object System.Text.UTF8Encoding($false)))
}

function Get-NrProviderInfo {
    $result=[ordered]@{ ip=$null; hostname=$null; city=$null; region=$null; country=$null; organization=$null; source=$null }
    foreach ($uri in @('https://ipinfo.io/json','https://ipapi.co/json/')) {
        try {
            $data=Invoke-RestMethod -Uri $uri -Headers @{ 'User-Agent'='NexRoute/0.5.0' } -TimeoutSec 8
            if ($uri -match 'ipinfo') {
                $result.ip=$data.ip; $result.hostname=$data.hostname; $result.city=$data.city; $result.region=$data.region; $result.country=$data.country; $result.organization=$data.org
            } else {
                $result.ip=$data.ip; $result.city=$data.city; $result.region=$data.region; $result.country=$data.country_name; $result.organization=$data.org
            }
            $result.source=$uri
            break
        } catch { }
    }
    return [pscustomobject]$result
}

function Show-NrProviderInfo {
    $data=Get-NrProviderInfo
    Write-NrHeader -Title (T 'provider')
    foreach ($pair in @(
        @('Public IP',$data.ip),@('Provider',$data.organization),@('Hostname',$data.hostname),@('Location',(($data.city,$data.region,$data.country | Where-Object { $_ }) -join ', ')),@('Network',(Get-NrActiveNetworkKey))
    )) {
        Write-Host ('  {0,-18}: {1}' -f $pair[0],$pair[1]) -ForegroundColor Gray
    }
    Wait-NrKey
}

function Show-NrAdapters {
    $adapters=@(Get-NetAdapter -ErrorAction SilentlyContinue | Sort-Object ifIndex)
    Write-NrHeader -Title (T 'adapters')
    foreach ($adapter in $adapters) {
        $addresses=@(Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -ErrorAction SilentlyContinue | Where-Object { $_.AddressState -eq 'Preferred' } | ForEach-Object { $_.IPAddress })
        Write-Host ('  {0,-4} {1,-24} {2,-12} {3,-14} {4}' -f $adapter.ifIndex,$adapter.Name,$adapter.Status,$adapter.LinkSpeed,($addresses -join ', ')) -ForegroundColor $(if ($adapter.Status -eq 'Up') { [ConsoleColor]::Green } else { [ConsoleColor]::DarkGray })
    }
    Wait-NrKey
}

function Save-NrCurrentNetworkProfile {
    $key=Get-NrActiveNetworkKey
    $strategy=Get-NrInstalledStrategy
    $table=[ordered]@{}
    try { foreach ($property in @($script:NrState.networkProfiles.PSObject.Properties)) { $table[$property.Name]=$property.Value } } catch { }
    $table[$key]=[ordered]@{ strategy=$strategy; dnsProvider=[string]$script:NrState.dnsProvider; dnsEncryption=[string]$script:NrState.dnsEncryption; savedUtc=[DateTime]::UtcNow.ToString('o') }
    $script:NrState.networkProfiles=[pscustomobject]$table
    $script:NrState.currentNetworkKey=$key
    Save-NrState
    Show-NrMessage -Title (T 'networkProfiles') -Message ($key + ' / ' + $strategy) -Color Green
}

function Apply-NrNetworkProfile {
    $key=Get-NrActiveNetworkKey
    $profile=$null
    try { $property=$script:NrState.networkProfiles.PSObject.Properties[$key]; if ($property) { $profile=$property.Value } } catch { }
    if (-not $profile) { return $false }
    $strategyName=[string]$profile.strategy
    $strategy=Get-NrStrategies | Where-Object { $_.BaseName -eq $strategyName -or $_.Name -eq $strategyName } | Select-Object -First 1
    if ($strategy) { Install-NrStrategy -Strategy $strategy -Silent }
    $provider=Get-NrDnsProviders | Where-Object { $_.id -eq [string]$profile.dnsProvider } | Select-Object -First 1
    if ($provider) { Set-NrDnsProvider -Provider $provider -Adapters (Get-NrActiveAdapters) -Encryption ([string]$profile.dnsEncryption) }
    $script:NrState.currentNetworkKey=$key
    Save-NrState
    return $true
}

function Show-NrNetworkProfiles {
    $items=@(
        New-NrMenuItem -Id 'save' -Label (T 'save') -Section (T 'networkProfiles')
        New-NrMenuItem -Id 'apply' -Label (T 'networkProfiles') -Section (T 'networkProfiles') -Status 'APPLY CURRENT'
        New-NrMenuItem -Id 'edit' -Label (T 'edit') -Section (T 'networkProfiles')
        New-NrMenuItem -Id 'back' -Label (T 'back') -Section (T 'networkProfiles')
    )
    $choice=Invoke-NrMenu -Title (T 'networkProfiles') -Items $items -AllowEscape
    switch ($choice) {
        'save' { Save-NrCurrentNetworkProfile }
        'apply' { if (Apply-NrNetworkProfile) { Show-NrMessage -Title (T 'networkProfiles') -Message (T 'operationComplete') -Color Green } else { Show-NrMessage -Title (T 'networkProfiles') -Message (T 'noResults') -Color Yellow } }
        'edit' { Open-NrTextFile -Path $script:NrStatePath }
    }
}

function Reset-NrNetworkStack {
    if (-not (Confirm-NrY -Message ((T 'resetNetwork') + '? Press Y to confirm.'))) { return }
    $commands=@(
        @('int','ip','reset'),@('winhttp','reset','proxy'),@('winsock','reset'),@('interface','ipv4','reset'),@('interface','ipv6','reset')
    )
    foreach ($args in $commands) {
        try { & netsh.exe @args | Out-Null; Write-NrLog -Level INFO -Message 'Network reset command' -Data @{ args=($args -join ' ') } }
        catch { Write-NrLog -Level ERROR -Message 'Network reset failed' -Data @{ args=($args -join ' '); error=$_.Exception.Message } }
    }
    try { & ipconfig.exe /flushdns | Out-Null } catch { }
    Show-NrMessage -Title (T 'resetNetwork') -Message 'Network stack reset completed. Restart Windows to finish.' -Color Yellow
}

function Test-NrIpv6Readiness {
    $results=New-Object 'System.Collections.Generic.List[object]'
    $adapters=@(Get-NrActiveAdapters)
    foreach ($adapter in $adapters) {
        $addresses=@(Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv6 -ErrorAction SilentlyContinue | Where-Object { $_.AddressState -eq 'Preferred' -and $_.IPAddress -notlike 'fe80:*' })
        $results.Add([pscustomobject]@{ adapter=$adapter.Name; globalAddresses=@($addresses | ForEach-Object { $_.IPAddress }); ready=($addresses.Count -gt 0) })
    }
    $dnsOk=$false
    try { $dnsOk=@(Resolve-DnsName -Name 'ipv6.google.com' -Type AAAA -DnsOnly -ErrorAction Stop).Count -gt 0 } catch { }
    $httpOk=$false
    try { $httpOk=(Invoke-WebRequest -Uri 'https://[2606:4700:4700::1111]/cdn-cgi/trace' -UseBasicParsing -TimeoutSec 8 -Headers @{ Host='cloudflare.com' }).StatusCode -ge 200 } catch { }
    Write-NrHeader -Title (T 'ipv6')
    foreach ($result in $results) {
        Write-Host ('  {0,-24} {1,-8} {2}' -f $result.adapter,$(if ($result.ready) { 'READY' } else { 'NO IPv6' }),($result.globalAddresses -join ', ')) -ForegroundColor $(if ($result.ready) { [ConsoleColor]::Green } else { [ConsoleColor]::Yellow })
    }
    Write-Host ('  AAAA DNS: ' + $(if ($dnsOk) { 'OK' } else { 'FAIL' })) -ForegroundColor $(if ($dnsOk) { [ConsoleColor]::Green } else { [ConsoleColor]::Red })
    Write-Host ('  IPv6 HTTPS: ' + $(if ($httpOk) { 'OK' } else { 'UNAVAILABLE' })) -ForegroundColor $(if ($httpOk) { [ConsoleColor]::Green } else { [ConsoleColor]::Yellow })
    Wait-NrKey
}

function Show-NrNetworkMenu {
    while ($true) {
        $items=@(
            New-NrMenuItem -Id 'dnsdiag' -Label (T 'dnsDiagnostics') -Section (T 'networkDns')
            New-NrMenuItem -Id 'dnsprovider' -Label (T 'dnsProvider') -Section (T 'networkDns') -Status ([string]$script:NrState.dnsProvider)
            New-NrMenuItem -Id 'adapters' -Label (T 'adapters') -Section (T 'networkDns')
            New-NrMenuItem -Id 'profiles' -Label (T 'networkProfiles') -Section (T 'networkDns')
            New-NrMenuItem -Id 'provider' -Label (T 'provider') -Section (T 'networkDns')
            New-NrMenuItem -Id 'ipv6' -Label (T 'ipv6') -Section (T 'networkDns')
            New-NrMenuItem -Id 'reset' -Label (T 'resetNetwork') -Section (T 'networkDns')
            New-NrMenuItem -Id 'back' -Label (T 'back') -Section (T 'networkDns')
        )
        $choice=Invoke-NrMenu -Title (T 'networkDns') -Items $items -AllowEscape
        if (-not $choice -or $choice -eq 'back') { return }
        switch ($choice) {
            'dnsdiag' { Invoke-NrDnsDiagnostics }
            'dnsprovider' { Show-NrDnsProviderMenu }
            'adapters' { Show-NrAdapters }
            'profiles' { Show-NrNetworkProfiles }
            'provider' { Show-NrProviderInfo }
            'ipv6' { Test-NrIpv6Readiness }
            'reset' { Reset-NrNetworkStack }
        }
    }
}
