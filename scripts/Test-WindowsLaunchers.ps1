[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ExtractDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw 'Windows launcher smoke tests require Windows.'
}

$sourceRoot = (Resolve-Path -LiteralPath $ExtractDirectory).Path
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'NexRoute 0.6.1 Hot Fix Тест {0}' -f [guid]::NewGuid().ToString('N')
)
$results = New-Object 'System.Collections.Generic.List[object]'

try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    foreach ($item in @(Get-ChildItem -LiteralPath $sourceRoot -Force -ErrorAction Stop)) {
        Copy-Item -LiteralPath $item.FullName -Destination $testRoot -Recurse -Force
    }

    Remove-Item -LiteralPath (Join-Path $testRoot 'utils\check_updates.enabled') -Force -ErrorAction SilentlyContinue

    foreach ($fixture in @(
        [pscustomobject]@{ Name = 'service.bat'; Arguments = '--status' },
        [pscustomobject]@{ Name = 'nexroute.bat'; Arguments = '--status' },
        [pscustomobject]@{ Name = 'nexroute-update.cmd'; Arguments = '--status' }
    )) {
        $launcher = Join-Path $testRoot $fixture.Name
        if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) {
            throw "Launcher is missing from the extracted package: $($fixture.Name)"
        }

        $commandLine = 'call "{0}" {1}' -f $launcher, $fixture.Arguments
        $output = & $env:ComSpec /d /s /c $commandLine 2>&1
        $exitCode = $LASTEXITCODE
        $text = (($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine)

        if ($exitCode -ne 0) {
            throw "Launcher $($fixture.Name) failed with exit code $exitCode.`n$text"
        }
        if ($text -match '(?i)GetFullPath|Illegal characters in path|Недопустимые знаки|MethodInvocationException|ArgumentException') {
            throw "Launcher $($fixture.Name) reproduced the path crash.`n$text"
        }

        $results.Add([pscustomobject]@{
            launcher = $fixture.Name
            exitCode = $exitCode
            outputLength = $text.Length
        })
    }

    return [pscustomobject]@{
        status = 'passed'
        testRoot = $testRoot
        launcherCount = $results.Count
        launchers = $results.ToArray()
    }
} finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
