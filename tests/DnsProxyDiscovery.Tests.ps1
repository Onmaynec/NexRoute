Describe 'Temporary dnsproxy release discovery' {
    It 'prints the immutable AdGuard dnsproxy v0.81.4 Windows amd64 digest' {
        $headers=@{
            Accept='application/vnd.github+json'
            'User-Agent'='NexRoute-DoT-Resolver-Discovery/0.6.0'
            'X-GitHub-Api-Version'='2022-11-28'
        }
        $release=Invoke-RestMethod -Uri 'https://api.github.com/repos/AdguardTeam/dnsproxy/releases/tags/v0.81.4' -Headers $headers -TimeoutSec 30
        $release.tag_name | Should -Be 'v0.81.4'
        $release.draft | Should -BeFalse
        $release.prerelease | Should -BeFalse
        $asset=@($release.assets | Where-Object { $_.name -eq 'dnsproxy-windows-amd64-v0.81.4.zip' })
        $asset | Should -HaveCount 1
        $temporary=Join-Path ([IO.Path]::GetTempPath()) ('dnsproxy-v0.81.4-'+[guid]::NewGuid().ToString('N')+'.zip')
        try {
            Invoke-WebRequest -Uri $asset[0].browser_download_url -OutFile $temporary -UseBasicParsing -TimeoutSec 120 -Headers $headers
            $sha=(Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash.ToLowerInvariant()
            $sha | Should -Match '^[0-9a-f]{64}$'
            (Get-Item -LiteralPath $temporary).Length | Should -BeGreaterThan 1000000
            Write-Host 'NEXROUTE_DNSPROXY_VERSION=0.81.4'
            Write-Host 'NEXROUTE_DNSPROXY_ASSET=dnsproxy-windows-amd64-v0.81.4.zip'
            Write-Host ('NEXROUTE_DNSPROXY_SHA256='+$sha)
            if ($asset[0].PSObject.Properties['digest'] -and [string]$asset[0].digest) {
                Write-Host ('NEXROUTE_DNSPROXY_API_DIGEST='+[string]$asset[0].digest)
                ([string]$asset[0].digest).ToLowerInvariant() | Should -Be ('sha256:'+$sha)
            }
        } finally { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    }
}
