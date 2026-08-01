[CmdletBinding()]
param(
    [Parameter()][ValidatePattern('^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$')][string]$Version,
    [Parameter()][string]$UpstreamVersion,
    [Parameter()][string]$OutputDirectory,
    [Parameter()][string]$UpstreamArchive,
    [Parameter()][string]$UpstreamCachePath,
    [switch]$AllowUnlockedUpstream
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
if (-not $Version) { $Version = (Get-Content -LiteralPath (Join-Path $repositoryRoot '.service/version.txt') -Raw).Trim() }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repositoryRoot 'artifacts' }
$outputPath = [System.IO.Path]::GetFullPath($OutputDirectory)
$baseBuilder = Join-Path $PSScriptRoot 'Build-NexRoute.ps1'
$upstreamModule = Join-Path $PSScriptRoot 'NexRoute.Upstream.psm1'
$manifestPath = Join-Path $repositoryRoot '.service/upstream-manifest.json'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("nexroute-release-{0}" -f [guid]::NewGuid().ToString('N'))
$packageRoot = Join-Path $tempRoot 'package'
$upstreamWork = Join-Path $tempRoot 'upstream-contract'

Import-Module $upstreamModule -Force
$manifest = Read-NexRouteUpstreamManifest -Path $manifestPath
if ($UpstreamVersion -and $UpstreamVersion -ne $manifest.tag) {
    throw "Requested upstream $UpstreamVersion differs from manifest tag $($manifest.tag)."
}
$UpstreamVersion = $manifest.tag

function Write-Step {
    param([string]$Message)
    Write-Host ("[NexRoute {0}] {1}" -f $Version, $Message) -ForegroundColor Cyan
}

function Write-AsciiFile {
    param([string]$Path, [string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.Encoding]::ASCII)
}

function Get-LiteralCount {
    param([Parameter(Mandatory)][string]$Content, [Parameter(Mandatory)][string]$Value)
    if ($Value.Length -eq 0) { throw 'Literal patch value cannot be empty.' }
    return [regex]::Matches($Content, [regex]::Escape($Value)).Count
}

function Replace-RequiredLiteral {
    param(
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][string]$OldValue,
        [Parameter(Mandatory)][string]$NewValue,
        [Parameter(Mandatory)][string]$PatchId,
        [int]$ExpectedCount = 1
    )
    $count = Get-LiteralCount -Content $Content -Value $OldValue
    if ($count -ne $ExpectedCount) {
        throw "Patch '$PatchId' expected $ExpectedCount literal match(es), got $count."
    }
    return $Content.Replace($OldValue, $NewValue)
}

function Patch-NexRouteStrategy {
    param([System.IO.FileInfo]$File)

    $lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($line in [System.IO.File]::ReadAllLines($File.FullName)) { $lines.Add($line) }
    if ($lines -contains 'rem NEXROUTE_SERVICE_FILTERS_V4') {
        throw "Strategy was already patched: $($File.Name)"
    }

    $hookMatches = New-Object 'System.Collections.Generic.List[int]'
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match 'nexroute-services\.ps1.+-Mode Apply') { $hookMatches.Add($i) }
    }
    if ($hookMatches.Count -ne 1) {
        throw "Strategy '$($File.Name)' expected one Service Matrix apply hook, got $($hookMatches.Count)."
    }
    $hookIndex = $hookMatches[0]
    $lines.Insert($hookIndex + 1, 'rem NEXROUTE_SERVICE_FILTERS_V4')
    $lines.Insert($hookIndex + 2, 'if exist "%~dp0.service\services-runtime.cmd" call "%~dp0.service\services-runtime.cmd"')

    $startMatches = New-Object 'System.Collections.Generic.List[int]'
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '(?i)^\s*start\s+.+winws\.exe') { $startMatches.Add($i) }
    }
    if ($startMatches.Count -ne 1) {
        throw "Strategy '$($File.Name)' expected one winws command, got $($startMatches.Count)."
    }

    $endIndex = $startMatches[0]
    while ($endIndex -lt ($lines.Count - 1) -and $lines[$endIndex].TrimEnd().EndsWith('^')) { $endIndex++ }
    $lines[$endIndex] = $lines[$endIndex].TrimEnd() + ' ^'
    $lines.Insert($endIndex + 1, '%NEXROUTE_SERVICE_TCP_ARGS% ^')
    $lines.Insert($endIndex + 2, '%NEXROUTE_SERVICE_UDP_ARGS%')
    [System.IO.File]::WriteAllLines($File.FullName, $lines, [System.Text.Encoding]::ASCII)
    return 4
}

function Patch-NexRouteServiceBat {
    param([string]$Path)

    $content = [System.IO.File]::ReadAllText($Path)
    $nl = "`r`n"
    $operations = 0

    $handler = @'
rem NEXROUTE_REFRESH_MATRIX_V4
if /I "%~1"=="refresh_matrix" (
    setlocal EnableExtensions EnableDelayedExpansion
    set "NEXROUTE_REFRESH_FILE=%~2"
    if not defined NEXROUTE_REFRESH_FILE exit /b 2
    goto service_install
)

'@ -replace "`n", $nl
    $adminAnchor = 'if "%1"=="admin" ('
    $content = Replace-RequiredLiteral -Content $content -OldValue $adminAnchor -NewValue ($handler + $adminAnchor) -PatchId 'service.refresh-route'
    $operations++

    $content = Replace-RequiredLiteral `
        -Content $content `
        -OldValue 'if "!menu_choice!"=="4" (call :nexroute_action game&goto game_switch)' `
        -NewValue 'if "!menu_choice!"=="4" goto nexroute_game_filter' `
        -PatchId 'service.game-filter-route'
    $operations++
    $content = Replace-RequiredLiteral `
        -Content $content `
        -OldValue 'if "!menu_choice!"=="6" (call :nexroute_action updatecheck&goto check_updates_switch)' `
        -NewValue 'if "!menu_choice!"=="6" goto nexroute_update_watch' `
        -PatchId 'service.update-watch-route'
    $operations++

    $routes = @'
:nexroute_game_filter
if exist "!NEXROUTE_UI!" powershell -NoProfile -ExecutionPolicy Bypass -File "!NEXROUTE_UI!" -Mode GameFilter -LanguageFile "!NEXROUTE_LANGUAGE_FILE!"
goto menu

:nexroute_update_watch
if exist "!NEXROUTE_UI!" powershell -NoProfile -ExecutionPolicy Bypass -File "!NEXROUTE_UI!" -Mode UpdateWatch -LanguageFile "!NEXROUTE_LANGUAGE_FILE!"
goto menu

'@ -replace "`n", $nl
    $servicesAnchor = ':nexroute_services_matrix'
    $content = Replace-RequiredLiteral -Content $content -OldValue $servicesAnchor -NewValue ($routes + $servicesAnchor) -PatchId 'service.styled-routes'
    $operations++

    $refreshInstall = @'
rem NEXROUTE_REFRESH_INSTALL_V4
if exist "%~dp0.service\nexroute-services.ps1" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0.service\nexroute-services.ps1" -Mode Apply -Root "%~dp0" >nul 2>&1
if exist "%~dp0.service\services-runtime.cmd" call "%~dp0.service\services-runtime.cmd"
if defined NEXROUTE_REFRESH_FILE (
    set "selectedFile=!NEXROUTE_REFRESH_FILE!"
    if not exist "!selectedFile!" set "selectedFile=%~dp0!NEXROUTE_REFRESH_FILE!"
    if not exist "!selectedFile!" exit /b 3
    set "choice=1"
    set "file1=!selectedFile!"
    goto nexroute_refresh_parse
)

'@ -replace "`n", $nl
    $installAnchor = ':: Searching for strategy launchers through NexRoute selector'
    $content = Replace-RequiredLiteral -Content $content -OldValue $installAnchor -NewValue ($refreshInstall + $installAnchor) -PatchId 'service.refresh-install'
    $operations++
    $argsAnchor = ':: Args that should be followed by value'
    $content = Replace-RequiredLiteral -Content $content -OldValue $argsAnchor -NewValue (':nexroute_refresh_parse' + $nl + $argsAnchor) -PatchId 'service.refresh-parse'
    $operations++

    $expandLine = 'call set "ARGS=%%ARGS:EXCL_MARK=^!%%"'
    $expandReplacement = $expandLine + $nl + 'rem NEXROUTE_EXPAND_RUNTIME_ARGS' + $nl + 'call set "ARGS=%%ARGS%%"'
    $content = Replace-RequiredLiteral -Content $content -OldValue $expandLine -NewValue $expandReplacement -PatchId 'service.expand-runtime'
    $operations++

    $registryLine = 'reg add "HKLM\System\CurrentControlSet\Services\zapret" /v zapret-discord-youtube /t REG_SZ /d "!filename!" /f'
    $content = Replace-RequiredLiteral `
        -Content $content `
        -OldValue $registryLine `
        -NewValue ($registryLine + $nl + 'if defined NEXROUTE_REFRESH_FILE exit /b 0') `
        -PatchId 'service.refresh-exit'
    $operations++

    Write-AsciiFile -Path $Path -Content $content
    return $operations
}

function Patch-NexRouteTestLab {
    param([string]$Path)

    $content = [System.IO.File]::ReadAllText($Path)
    $nl = "`r`n"
    $operations = 0

    $languageBootstrap = @'
# NEXROUTE_TEST_LANGUAGE_V4
$nrLanguagePath = Join-Path (Split-Path $PSScriptRoot) '.service\language.txt'
$nrLanguage = 'EN'
if (Test-Path -LiteralPath $nrLanguagePath -PathType Leaf) {
    try { $nrLanguage = (Get-Content -LiteralPath $nrLanguagePath -Raw -Encoding ASCII).Trim().ToUpperInvariant() } catch { }
}

'@ -replace "`n", $nl
    $header = '# NEXROUTE_TEST_HEADER'
    $content = Replace-RequiredLiteral -Content $content -OldValue $header -NewValue ($header + $nl + $languageBootstrap) -PatchId 'testlab.language-bootstrap'
    $operations++

    $content = Replace-RequiredLiteral `
        -Content $content `
        -OldValue 'Where-Object { $_.Name -notlike "service*" }' `
        -NewValue 'Where-Object { $_.Name -notlike "service*" -and $_.Name -ne "nexroute.bat" }' `
        -PatchId 'testlab.exclude-launcher'
    $operations++

    $block = @'
    # NEXROUTE_DYNAMIC_TARGETS_V4
    $nrServiceRoot = Split-Path $PSScriptRoot
    $nrController = Join-Path $nrServiceRoot '.service\nexroute-services.ps1'
    if (Test-Path -LiteralPath $nrController -PathType Leaf) {
        try {
            $nrJson = & $nrController -Mode TestTargets -Root $nrServiceRoot | Select-Object -Last 1
            $nrTargets = if ($nrJson) { @($nrJson | ConvertFrom-Json) } else { @() }
            foreach ($nrTarget in $nrTargets) {
                $nrName = if ($nrLanguage -eq 'RU') { [string]$nrTarget.NameRu } else { [string]$nrTarget.NameEn }
                if (-not [string]::IsNullOrWhiteSpace($nrName) -and -not [string]::IsNullOrWhiteSpace([string]$nrTarget.Value)) {
                    Add-OrSet -dict $rawTargets -key $nrName -val ([string]$nrTarget.Value)
                }
            }
            Write-Host $(if ($nrLanguage -eq 'RU') { "[INFO] Добавлено целей из матрицы сервисов: $($nrTargets.Count)" } else { "[INFO] Service Matrix targets added: $($nrTargets.Count)" }) -ForegroundColor Cyan
        }
        catch {
            Write-Host $(if ($nrLanguage -eq 'RU') { "[WARN] Не удалось загрузить цели матрицы сервисов." } else { "[WARN] Unable to load Service Matrix targets." }) -ForegroundColor Yellow
        }
    }

'@ -replace "`n", $nl
    $targetAnchor = '    foreach ($key in $rawTargets.Keys) {'
    $content = Replace-RequiredLiteral -Content $content -OldValue $targetAnchor -NewValue ($block + $targetAnchor) -PatchId 'testlab.dynamic-targets'
    $operations++

    $localizedReplacements = @(
        @('Write-Host "Select test type:" -ForegroundColor Cyan', 'Write-Host $(if ($nrLanguage -eq ''RU'') { ''Выберите тип проверки:'' } else { ''Select test type:'' }) -ForegroundColor Cyan'),
        @('Write-Host "  [1] Standard tests (HTTP/ping)" -ForegroundColor Gray', 'Write-Host $(if ($nrLanguage -eq ''RU'') { ''  [1] Стандартная проверка (HTTP/ping)'' } else { ''  [1] Standard tests (HTTP/ping)'' }) -ForegroundColor Gray'),
        @('Write-Host "  [2] DPI checkers (TCP 16-20 freeze)" -ForegroundColor Gray', 'Write-Host $(if ($nrLanguage -eq ''RU'') { ''  [2] DPI-проверка (зависание TCP 16-20 КБ)'' } else { ''  [2] DPI checkers (TCP 16-20 freeze)'' }) -ForegroundColor Gray'),
        @('$choice = Read-Host "Enter 1 or 2"', '$choice = Read-Host $(if ($nrLanguage -eq ''RU'') { ''Введите 1 или 2'' } else { ''Enter 1 or 2'' })'),
        @('Write-Host "Select test run mode:" -ForegroundColor Cyan', 'Write-Host $(if ($nrLanguage -eq ''RU'') { ''Выберите режим запуска:'' } else { ''Select test run mode:'' }) -ForegroundColor Cyan'),
        @('Write-Host "  [1] All configs" -ForegroundColor Gray', 'Write-Host $(if ($nrLanguage -eq ''RU'') { ''  [1] Все конфигурации'' } else { ''  [1] All configs'' }) -ForegroundColor Gray'),
        @('Write-Host "  [2] Selected configs" -ForegroundColor Gray', 'Write-Host $(if ($nrLanguage -eq ''RU'') { ''  [2] Выбранные конфигурации'' } else { ''  [2] Selected configs'' }) -ForegroundColor Gray'),
        @('Write-Host "Available configs:" -ForegroundColor Cyan', 'Write-Host $(if ($nrLanguage -eq ''RU'') { ''Доступные конфигурации:'' } else { ''Available configs:'' }) -ForegroundColor Cyan'),
        @('Write-Host "All tests finished." -ForegroundColor Green', 'Write-Host $(if ($nrLanguage -eq ''RU'') { ''Все проверки завершены.'' } else { ''All tests finished.'' }) -ForegroundColor Green'),
        @('Write-Host "=== ANALYTICS ===" -ForegroundColor Cyan', 'Write-Host $(if ($nrLanguage -eq ''RU'') { ''=== ИТОГОВАЯ АНАЛИТИКА ==='' } else { ''=== ANALYTICS ==='' }) -ForegroundColor Cyan')
    )
    for ($index = 0; $index -lt $localizedReplacements.Count; $index++) {
        $pair = $localizedReplacements[$index]
        $content = Replace-RequiredLiteral -Content $content -OldValue $pair[0] -NewValue $pair[1] -PatchId ("testlab.locale-{0}" -f ($index + 1))
        $operations++
    }

    [System.IO.File]::WriteAllText($Path, $content, (New-Object System.Text.UTF8Encoding($false)))
    return $operations
}

$patchJournal = New-Object 'System.Collections.Generic.List[object]'

function Get-PackageRelativePath {
    param([Parameter(Mandatory)][string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    $root = [System.IO.Path]::GetFullPath($packageRoot).TrimEnd('\','/') + [System.IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Patch target is outside the package root: $Path"
    }
    return $full.Substring($root.Length).Replace('\','/')
}

function Invoke-TrackedPatch {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][scriptblock]$Action
    )
    if ($patchJournal.Id -contains $Id) { throw "Duplicate patch id: $Id" }
    $before = Get-NexRouteSha256 -Path $Target
    $operations = [int](& $Action | Select-Object -Last 1)
    $after = Get-NexRouteSha256 -Path $Target
    if ($operations -lt 1) { throw "Patch '$Id' reported no operations." }
    if ($before -eq $after) { throw "Patch '$Id' did not change its target." }
    $patchJournal.Add([pscustomobject]@{
        id = $Id
        target = Get-PackageRelativePath -Path $Target
        operations = $operations
        beforeSha256 = $before
        afterSha256 = $after
    })
}

try {
    if (-not (Test-Path -LiteralPath $baseBuilder -PathType Leaf)) { throw "Base builder not found: $baseBuilder" }
    New-Item -ItemType Directory -Path $outputPath, $packageRoot -Force | Out-Null

    Write-Step "Resolving locked Flowseal $UpstreamVersion archive"
    $resolvedUpstream = Resolve-NexRouteUpstreamArchive `
        -Manifest $manifest `
        -WorkingDirectory $upstreamWork `
        -ArchivePath $UpstreamArchive `
        -AllowUnlocked:$AllowUnlockedUpstream
    Write-Step ("Upstream {0}: {1}" -f $resolvedUpstream.ResolutionMode, $resolvedUpstream.Lock.assetName)
    Write-Step ("Upstream SHA-256: {0}" -f $resolvedUpstream.Lock.sha256)

    if ($UpstreamCachePath) {
        $cacheDirectory = Split-Path -Parent $UpstreamCachePath
        if ($cacheDirectory -and -not (Test-Path -LiteralPath $cacheDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $cacheDirectory -Force | Out-Null
        }
        Copy-Item -LiteralPath $resolvedUpstream.ArchivePath -Destination $UpstreamCachePath -Force
        Write-Step "Saved verified upstream cache: $UpstreamCachePath"
    }

    $global:nexrouteProxyReleaseUrl = $resolvedUpstream.ReleaseApiUrl
    $global:nexrouteProxyAssetUrl = 'https://nexroute.invalid/verified-upstream.zip'
    $global:nexrouteProxyArchive = $resolvedUpstream.ArchivePath
    $global:nexrouteProxyRelease = New-NexRouteProxyRelease -ResolvedUpstream $resolvedUpstream -ProxyAssetUrl $global:nexrouteProxyAssetUrl

    function Invoke-RestMethod {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)][string]$Uri,
            [hashtable]$Headers,
            [string]$Method = 'Get'
        )
        if ($Uri -eq $global:nexrouteProxyReleaseUrl) { return $global:nexrouteProxyRelease }
        return Microsoft.PowerShell.Utility\Invoke-RestMethod @PSBoundParameters
    }

    function Invoke-WebRequest {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)][string]$Uri,
            [hashtable]$Headers,
            [string]$OutFile,
            [switch]$UseBasicParsing
        )
        if ($Uri -eq $global:nexrouteProxyAssetUrl) {
            if (-not $OutFile) { throw 'The verified upstream proxy requires OutFile.' }
            Copy-Item -LiteralPath $global:nexrouteProxyArchive -Destination $OutFile -Force
            return [pscustomobject]@{ StatusCode = 200 }
        }
        return Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters
    }

    Write-Step "Building Flowseal $UpstreamVersion baseline from verified archive"
    $baseResult = @(& $baseBuilder -Version $Version -UpstreamVersion $UpstreamVersion -OutputDirectory $outputPath) | Select-Object -Last 1

    $zipPath = Join-Path $outputPath ("NexRoute-{0}-win-x64.zip" -f $Version)
    $checksumPath = $zipPath + '.sha256'
    if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) { throw "Base package was not created: $zipPath" }

    Write-Step 'Expanding package for Service Matrix integration'
    Expand-Archive -LiteralPath $zipPath -DestinationPath $packageRoot -Force

    $serviceDirectory = Join-Path $packageRoot '.service'
    $coreController = Join-Path $serviceDirectory 'nexroute-services-core.ps1'
    $controller = Join-Path $serviceDirectory 'nexroute-services.ps1'
    Copy-Item -LiteralPath $controller -Destination $coreController -Force
    Copy-Item -LiteralPath (Join-Path $repositoryRoot 'overlay/.service/nexroute-services-entry.ps1') -Destination $controller -Force
    Set-Content -LiteralPath (Join-Path $serviceDirectory 'language.txt') -Value 'EN' -Encoding ASCII

    Write-Step 'Applying Service Matrix runtime'
    & $controller -Mode Apply -Root $packageRoot | Out-Null

    $strategyFiles = @(Get-ChildItem -LiteralPath $packageRoot -Filter '*.bat' -File | Where-Object { $_.Name -notin @('service.bat', 'nexroute.bat') })
    if ($strategyFiles.Count -ne 21) { throw "Expected 21 real strategy BAT files, got $($strategyFiles.Count)." }
    foreach ($strategyFile in $strategyFiles) {
        $current = $strategyFile
        Invoke-TrackedPatch -Id ("strategy.{0}" -f $current.BaseName.ToLowerInvariant()) -Target $current.FullName -Action {
            Patch-NexRouteStrategy -File $current
        }
    }

    Write-Step 'Applying tracked service and Strategy Lab patches'
    $serviceBatPath = Join-Path $packageRoot 'service.bat'
    Invoke-TrackedPatch -Id 'service.control-node' -Target $serviceBatPath -Action {
        Patch-NexRouteServiceBat -Path $serviceBatPath
    }
    $testLabPath = Join-Path $packageRoot 'utils\test zapret.ps1'
    Invoke-TrackedPatch -Id 'testlab.dynamic-matrix' -Target $testLabPath -Action {
        Patch-NexRouteTestLab -Path $testLabPath
    }

    if ($patchJournal.Count -ne 23) {
        throw "Expected 23 tracked patch targets, got $($patchJournal.Count)."
    }
    if (($patchJournal.Id | Sort-Object -Unique).Count -ne $patchJournal.Count) {
        throw 'Patch report contains duplicate IDs.'
    }

    Write-Step 'Writing upstream lock and patch provenance'
    Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $serviceDirectory 'upstream-manifest.json') -Force
    Write-NexRouteJson -Path (Join-Path $serviceDirectory 'upstream-lock.json') -Value $resolvedUpstream.Lock
    $operationCount = @($patchJournal | Measure-Object -Property operations -Sum).Sum
    $patchReport = [ordered]@{
        schemaVersion = 1
        nexRouteVersion = $Version
        upstreamSha256 = [string]$resolvedUpstream.Lock.sha256
        summary = [ordered]@{
            targetCount = $patchJournal.Count
            operationCount = [int]$operationCount
            strategyTargets = 21
            infrastructureTargets = 2
        }
        patches = @($patchJournal.ToArray())
    }
    Write-NexRouteJson -Path (Join-Path $serviceDirectory 'patch-report.json') -Value $patchReport

    Write-Step 'Regenerating multi-resolution NexRoute icon and shortcut'
    & (Join-Path $serviceDirectory 'New-NexRouteIcon.ps1') -Root $packageRoot | Out-Null

    $buildInfoPath = Join-Path $packageRoot 'NEXROUTE_BUILD_INFO.txt'
    Add-Content -LiteralPath $buildInfoPath -Value @(
        'Release contract: upstream manifest schema 1',
        ('Upstream archive SHA-256: {0}' -f $resolvedUpstream.Lock.sha256),
        ('Tracked patch targets: {0}' -f $patchJournal.Count),
        ('Tracked patch operations: {0}' -f $operationCount),
        'Service Matrix schema: 2',
        'State schema: 2 with legacy migration and backup',
        'Strategy integration: 21/21 real Flowseal BAT profiles',
        'Dynamic filters: isolated per-service domain/IP/TCP/UDP groups',
        'Shared-domain policy: excluded only when every owner is disabled',
        'IP sources: strict IPv4 CIDR validation and 14-day last-known-good cache',
        'Diagnostics: privacy-safe JSON export',
        'Default language: EN',
        'Icon: NexRoute supplied artwork motif, multi-resolution ICO'
    ) -Encoding UTF8

    Write-Step "Repacking verified $Version artifact"
    Remove-Item -LiteralPath $zipPath -Force
    if (Test-Path -LiteralPath $checksumPath) { Remove-Item -LiteralPath $checksumPath -Force }
    Compress-Archive -Path (Join-Path $packageRoot '*') -DestinationPath $zipPath -CompressionLevel Optimal
    $hash = Get-FileHash -LiteralPath $zipPath -Algorithm SHA256
    Set-Content -LiteralPath $checksumPath -Value ("{0}  {1}" -f $hash.Hash.ToLowerInvariant(), (Split-Path $zipPath -Leaf)) -Encoding ASCII

    Write-Step ("Created {0}" -f $zipPath)
    Write-Step ("SHA-256 {0}" -f $hash.Hash)

    [pscustomobject]@{
        Version = $Version
        UpstreamVersion = $UpstreamVersion
        UpstreamAsset = [string]$resolvedUpstream.Lock.assetName
        UpstreamSha256 = [string]$resolvedUpstream.Lock.sha256
        UpstreamResolution = [string]$resolvedUpstream.ResolutionMode
        PatchTargetCount = $patchJournal.Count
        PatchOperationCount = [int]$operationCount
        StrategyCount = 21
        ServiceCount = 15
        Archive = $zipPath
        Checksum = $checksumPath
        Sha256 = $hash.Hash.ToLowerInvariant()
    }
}
finally {
    Remove-Variable -Name nexrouteProxyReleaseUrl,nexrouteProxyAssetUrl,nexrouteProxyArchive,nexrouteProxyRelease -Scope Global -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
