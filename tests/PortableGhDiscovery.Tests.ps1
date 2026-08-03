Describe 'Temporary portable GitHub verifier discovery' {
    It 'prints the immutable GitHub CLI 2.97.0 Windows amd64 ZIP digest' {
        $headers=@{
            Accept='application/vnd.github+json'
            'User-Agent'='NexRoute-Portable-Verifier-Discovery/0.6.0'
            'X-GitHub-Api-Version'='2022-11-28'
        }
        $release=Invoke-RestMethod -Uri 'https://api.github.com/repos/cli/cli/releases/tags/v2.97.0' -Headers $headers -TimeoutSec 30
        $release.tag_name | Should -Be 'v2.97.0'
        $release.draft | Should -BeFalse
        $release.prerelease | Should -BeFalse
        $asset=@($release.assets | Where-Object { $_.name -eq 'gh_2.97.0_windows_amd64.zip' })
        $asset | Should -HaveCount 1
        $temporary=Join-Path ([IO.Path]::GetTempPath()) ('gh_2.97.0_windows_amd64-'+[guid]::NewGuid().ToString('N')+'.zip')
        try {
            Invoke-WebRequest -Uri $asset[0].browser_download_url -OutFile $temporary -UseBasicParsing -TimeoutSec 120 -Headers $headers
            $sha=(Get-FileHash -LiteralPath $temporary -Algorithm SHA256).Hash.ToLowerInvariant()
            $sha | Should -Match '^[0-9a-f]{64}$'
            (Get-Item -LiteralPath $temporary).Length | Should -BeGreaterThan 10000000
            Write-Host ('NEXROUTE_PORTABLE_GH_VERSION=2.97.0')
            Write-Host ('NEXROUTE_PORTABLE_GH_ASSET=gh_2.97.0_windows_amd64.zip')
            Write-Host ('NEXROUTE_PORTABLE_GH_SHA256='+$sha)
            if ($asset[0].PSObject.Properties['digest'] -and [string]$asset[0].digest) {
                Write-Host ('NEXROUTE_PORTABLE_GH_API_DIGEST='+[string]$asset[0].digest)
                ([string]$asset[0].digest).ToLowerInvariant() | Should -Be ('sha256:'+$sha)
            }
        } finally {
            Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
        }
    }
}
