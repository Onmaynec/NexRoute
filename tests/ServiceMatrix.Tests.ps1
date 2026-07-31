$ErrorActionPreference = 'Stop'

Describe 'NexRoute Service Matrix 0.2.3' {
    BeforeEach {
        $script:packageRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:serviceRoot = Join-Path $packageRoot '.service'
        $script:listsRoot = Join-Path $packageRoot 'lists'
        New-Item -ItemType Directory -Path $serviceRoot, $listsRoot -Force | Out-Null

        Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'overlay/.service/nexroute-services.ps1') -Destination (Join-Path $serviceRoot 'nexroute-services.ps1') -Force
        Set-Content -LiteralPath (Join-Path $serviceRoot 'version.txt') -Value '0.2.3' -Encoding ASCII

        $fixture = [ordered]@{
            schemaVersion = 2
            services = @(
                [ordered]@{
                    id = 'alpha'
                    nameEn = 'Alpha'
                    nameRu = 'Альфа'
                    descriptionEn = 'Alpha test service.'
                    descriptionRu = 'Тестовый сервис Альфа.'
                    defaultEnabled = $true
                    scope = 'test'
                    domains = @('shared.example', 'alpha.example')
                    tcpPorts = @('80')
                    udpPorts = @('443')
                    resolveHosts = @('localhost')
                    testTargets = @(
                        [ordered]@{ name = 'Alpha One'; role = 'web'; url = 'http://localhost' },
                        [ordered]@{ name = 'Alpha Two'; role = 'api'; url = 'http://127.0.0.1' }
                    )
                    ipCidrs = @('192.0.2.10/32')
                    ipSources = @()
                },
                [ordered]@{
                    id = 'beta'
                    nameEn = 'Beta'
                    nameRu = 'Бета'
                    descriptionEn = 'Beta test service.'
                    descriptionRu = 'Тестовый сервис Бета.'
                    defaultEnabled = $false
                    scope = 'test'
                    domains = @('shared.example', 'beta.example')
                    tcpPorts = @('443')
                    udpPorts = @('3478-3481')
                    resolveHosts = @('localhost')
                    testTargets = @(
                        [ordered]@{ name = 'Beta One'; role = 'web'; url = 'http://localhost' },
                        [ordered]@{ name = 'Beta Two'; role = 'api'; url = 'http://127.0.0.1' }
                    )
                    ipCidrs = @('198.51.100.20/32')
                    ipSources = @()
                }
            )
        }
        $fixture | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $serviceRoot 'services.json') -Encoding UTF8
        '{"alpha":true,"beta":false}' | Set-Content -LiteralPath (Join-Path $serviceRoot 'services-state.json') -Encoding UTF8
        "# user line`r`nmanual.example`r`n" | Set-Content -LiteralPath (Join-Path $listsRoot 'list-general-user.txt') -Encoding UTF8
        "# user exclude`r`nmanual-exclude.example`r`n" | Set-Content -LiteralPath (Join-Path $listsRoot 'list-exclude-user.txt') -Encoding UTF8
        $script:controller = Join-Path $serviceRoot 'nexroute-services.ps1'
    }

    function Invoke-Matrix {
        param([string]$Mode = 'Apply', [string]$DiagnosticsPath)
        if ($DiagnosticsPath) {
            return & $script:controller -Mode $Mode -Root $script:packageRoot -DiagnosticsPath $DiagnosticsPath | Select-Object -Last 1
        }
        return & $script:controller -Mode $Mode -Root $script:packageRoot | Select-Object -Last 1
    }

    It 'migrates legacy state and preserves user-managed lines' {
        Invoke-Matrix | Out-Null

        Test-Path -LiteralPath (Join-Path $serviceRoot 'services-state.v1.backup.json') | Should -BeTrue
        $state = Get-Content -LiteralPath (Join-Path $serviceRoot 'services-state.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $state.schemaVersion | Should -Be 2
        $state.services.alpha | Should -BeTrue
        $state.services.beta | Should -BeFalse

        $general = Get-Content -LiteralPath (Join-Path $listsRoot 'list-general-user.txt') -Raw -Encoding UTF8
        $general | Should -Match 'manual\.example'
        $general | Should -Match 'alpha\.example'
        $general | Should -Match 'shared\.example'

        $exclude = Get-Content -LiteralPath (Join-Path $listsRoot 'list-exclude-user.txt') -Raw -Encoding UTF8
        $exclude | Should -Match 'manual-exclude\.example'
        $exclude | Should -Match 'beta\.example'
        $exclude | Should -Not -Match '(?m)^shared\.example$'
    }

    It 'writes isolated runtime filters for enabled services' {
        Invoke-Matrix | Out-Null
        $runtime = Get-Content -LiteralPath (Join-Path $serviceRoot 'services-runtime.cmd') -Raw -Encoding ASCII

        $runtime | Should -Match 'list-service-alpha\.txt'
        $runtime | Should -Match 'ipset-service-alpha\.txt'
        $runtime | Should -Not -Match 'list-service-beta\.txt'
        $runtime | Should -Match '--filter-tcp=80'
        $runtime | Should -Match '--filter-udp=443'
        $runtime | Should -Not -Match '3478-3481'
    }

    It 'excludes a shared domain only when all owners are disabled' {
        $state = [ordered]@{ schemaVersion = 2; updatedAtUtc = [DateTime]::UtcNow.ToString('o'); services = [ordered]@{ alpha = $false; beta = $false } }
        $state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $serviceRoot 'services-state.json') -Encoding UTF8
        Invoke-Matrix | Out-Null

        $exclude = Get-Content -LiteralPath (Join-Path $listsRoot 'list-exclude-user.txt') -Raw -Encoding UTF8
        $exclude | Should -Match '(?m)^shared\.example$'
    }

    It 'rejects invalid ports and IPv4 CIDR values' {
        $document = Get-Content -LiteralPath (Join-Path $serviceRoot 'services.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $document.services[0].tcpPorts = @('70000')
        $document.services[0].ipCidrs = @('999.1.1.1/33')
        $document | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $serviceRoot 'services.json') -Encoding UTF8

        { Invoke-Matrix -Mode Validate } | Should -Throw
    }

    It 'backs up and replaces corrupt state' {
        '{broken json' | Set-Content -LiteralPath (Join-Path $serviceRoot 'services-state.json') -Encoding UTF8
        Invoke-Matrix | Out-Null

        Test-Path -LiteralPath (Join-Path $serviceRoot 'services-state.invalid.backup.json') | Should -BeTrue
        { Get-Content -LiteralPath (Join-Path $serviceRoot 'services-state.json') -Raw -Encoding UTF8 | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'is idempotent after state migration' {
        Invoke-Matrix | Out-Null
        $paths = @(
            (Join-Path $serviceRoot 'services-runtime.cmd'),
            (Join-Path $listsRoot 'list-general-user.txt'),
            (Join-Path $listsRoot 'list-exclude-user.txt'),
            (Join-Path $listsRoot 'list-service-alpha.txt'),
            (Join-Path $listsRoot 'ipset-service-alpha.txt')
        )
        $before = @{}
        foreach ($path in $paths) { $before[$path] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }

        Invoke-Matrix | Out-Null
        foreach ($path in $paths) {
            (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash | Should -Be $before[$path]
        }
    }

    It 'exports a privacy-safe diagnostics report' {
        Invoke-Matrix | Out-Null
        $diagnosticsPath = Join-Path $packageRoot 'diagnostics.json'
        Invoke-Matrix -Mode Diagnostics -DiagnosticsPath $diagnosticsPath | Out-Null

        Test-Path -LiteralPath $diagnosticsPath | Should -BeTrue
        $report = Get-Content -LiteralPath $diagnosticsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $report.nexRouteVersion | Should -Be '0.2.3'
        $report.enabledServiceIds | Should -Contain 'alpha'
        $report.privacy | Should -Match 'No domain-list contents'
        ($report | ConvertTo-Json -Depth 10) | Should -Not -Match 'manual\.example'
    }
}
