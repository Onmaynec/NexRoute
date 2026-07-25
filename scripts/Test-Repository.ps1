[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$errors = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition,[string]$Message) {
    if ($Condition) { Write-Host "[ OK ] $Message" -ForegroundColor Green }
    else { $script:errors.Add($Message); Write-Host "[FAIL] $Message" -ForegroundColor Red }
}
function Test-PowerShellFile([string]$Path,[string]$Name) {
    $tokens=$null; $parseErrors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$parseErrors)
    foreach ($error in @($parseErrors)) { Write-Host ("       {0}:{1} {2}" -f $error.Extent.StartLineNumber,$error.Extent.StartColumnNumber,$error.Message) -ForegroundColor Yellow }
    Assert-True ($parseErrors.Count -eq 0) "$Name parses without PowerShell syntax errors"
}
Write-Host 'NexRoute repository validation' -ForegroundColor Cyan
Write-Host '================================' -ForegroundColor Cyan
$required=@(
 'README.md','LICENSE','THIRD_PARTY_NOTICES.md','CONTRIBUTING.md','SECURITY.md','.service/version.txt',
 'assets/nexroute-mark.svg','overlay/nexroute.bat','overlay/.service/nexroute-ui.ps1',
 'overlay/.service/nexroute-console.ps1','overlay/.service/nexroute-pages.ps1','overlay/.service/nexroute-services.ps1',
 'scripts/Build-NexRoute.ps1','.github/workflows/validate.yml','.github/workflows/release.yml',
 'docs/README_EN.md','docs/ARCHITECTURE.md','docs/COMPATIBILITY.md','docs/RELEASES.md','docs/UPSTREAM.md'
)
foreach ($file in $required) { Assert-True (Test-Path (Join-Path $root $file) -PathType Leaf) "Required file exists: $file" }
$version=(Get-Content (Join-Path $root '.service/version.txt') -Raw).Trim()
Assert-True ($version -match '^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$') "Version is valid semantic version: $version"
$readme=Get-Content (Join-Path $root 'README.md') -Raw
Assert-True ($readme -match [regex]::Escape($version)) 'README mentions the current version'
Assert-True ($readme -match 'Flowseal.*1\.10\.0') 'README documents the pinned Flowseal baseline'
$license=Get-Content (Join-Path $root 'LICENSE') -Raw
Assert-True ($license -match 'MIT License') 'Project license is MIT'
Assert-True ($license -match 'Copyright \(c\) 2026 Onmaynec') 'License attribution belongs to Onmaynec'
$psFiles=@(
 'scripts/Build-NexRoute.ps1','scripts/Test-Repository.ps1','overlay/.service/nexroute-ui.ps1',
 'overlay/.service/nexroute-console.ps1','overlay/.service/nexroute-pages.ps1','overlay/.service/nexroute-services.ps1'
)
foreach ($file in $psFiles) { Test-PowerShellFile (Join-Path $root $file) $file }
$build=Get-Content (Join-Path $root 'scripts/Build-NexRoute.ps1') -Raw
Assert-True ($build -match "UpstreamVersion = '1\.10\.0'") 'Flowseal baseline is pinned to 1.10.0'
Assert-True ($build -match 'releases/tags/\$UpstreamVersion') 'Builder resolves immutable upstream release tag'
Assert-True ($build -match 'Get-FileHash.+SHA256') 'Builder generates SHA-256'
Assert-True ($build -match 'nexroute-services\.ps1') 'Builder installs service matrix manager'
Assert-True ($build -match 'nexroute-pages\.ps1') 'Builder installs styled operation pages'
Assert-True ($build -match 'NEXROUTE_PROFILE_BOOT') 'Builder injects profile boot hooks'
Assert-True ($build -match 'menu_choice!\"==\"14') 'Builder wires service matrix menu option'
$services=Get-Content (Join-Path $root 'overlay/.service/nexroute-services.ps1') -Raw
foreach ($token in @('chatgpt.com','casebattle.net','whatsapp.com','telegram.org','instagram.com','twitter.com','signal.org')) {
    Assert-True ($services -match [regex]::Escape($token)) "Service catalog contains $token"
}
Assert-True ($services -match 'NEXROUTE SERVICES BEGIN') 'Service manager uses bounded managed list block'
Assert-True ($services -match 'list-general-user\.txt') 'Service manager preserves Flowseal list compatibility'
$svg=Get-Content (Join-Path $root 'assets/nexroute-mark.svg') -Raw
Assert-True ($svg -match '<svg') 'Custom NexRoute identity mark is valid SVG source'
$forbidden=@('.exe','.dll','.sys','.bin','.zip','.rar','.7z')
$bad=@(Get-ChildItem $root -File -Recurse -Force | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' -and $forbidden -contains $_.Extension.ToLowerInvariant() })
Assert-True ($bad.Count -eq 0) 'Git source tree contains no binaries or archives'
$workflows=@(Get-ChildItem (Join-Path $root '.github/workflows') -Filter '*.yml' -File)
Assert-True ($workflows.Count -ge 2) 'Validation and release workflows are present'
foreach ($workflow in $workflows) {
    $content=Get-Content $workflow.FullName -Raw
    Assert-True ($content -match '(?m)^name:\s+\S') "Workflow has a name: $($workflow.Name)"
    Assert-True ($content -match '(?m)^on:\s*$') "Workflow defines triggers: $($workflow.Name)"
    Assert-True ($content -match '(?m)^jobs:\s*$') "Workflow defines jobs: $($workflow.Name)"
}
if ($errors.Count -gt 0) { Write-Host "`nValidation failed with $($errors.Count) error(s)." -ForegroundColor Red; exit 1 }
Write-Host "`nAll NexRoute repository checks passed." -ForegroundColor Green
