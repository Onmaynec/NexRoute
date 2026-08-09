[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot

function Read-NrText([string]$RelativePath) {
    [IO.File]::ReadAllText((Join-Path $root $RelativePath),[Text.Encoding]::UTF8)
}
function Write-NrText([string]$RelativePath,[string]$Text) {
    [IO.File]::WriteAllText((Join-Path $root $RelativePath),$Text,[Text.UTF8Encoding]::new($false))
}
function Replace-NrRequired([string]$RelativePath,[string]$Old,[string]$New) {
    $text=Read-NrText $RelativePath
    if(-not $text.Contains($Old)){throw "Required version token not found in $RelativePath: $Old"}
    Write-NrText $RelativePath ($text.Replace($Old,$New))
}
function Replace-NrRegexCount([string]$RelativePath,[string]$Pattern,[string]$Replacement,[int]$Count) {
    $text=Read-NrText $RelativePath
    $matches=[regex]::Matches($text,$Pattern)
    if($matches.Count -lt $Count){throw "Expected at least $Count matches in $RelativePath for $Pattern; got $($matches.Count)."}
    $updated=[regex]::Replace($text,$Pattern,$Replacement,$Count)
    Write-NrText $RelativePath $updated
}

# Canonical package version.
Write-NrText '.service/version.txt' "0.6.4`n"

# Website package and lock metadata. The first two lockfile version fields are the lock root and packages[\"\"].
Replace-NrRegexCount 'website/package.json' '(?m)^(\s*"version"\s*:\s*)"0\.6\.3"' '${1}"0.6.4"' 1
Replace-NrRegexCount 'website/package-lock.json' '(?m)^(\s*"version"\s*:\s*)"0\.6\.3"' '${1}"0.6.4"' 2

# Repository coherence points. Preserve 0.6.3-specific strategy-refresh evidence and historical files.
$repo='scripts/Test-Repository.ps1'
Replace-NrRequired $repo "`$expectedVersion='0.6.3'" "`$expectedVersion='0.6.4'"
Replace-NrRequired $repo "`$releaseNotes=Read-Text '.github/release-notes/v0.6.3.md'" "`$releaseNotes=Read-Text '.github/release-notes/v0.6.4.md'"
Replace-NrRequired $repo "`$acceptance=Read-Text 'docs/RELEASE_0.6.3_ACCEPTANCE.md'" "`$acceptance=Read-Text 'docs/RELEASE_0.6.4_ACCEPTANCE.md'"
Replace-NrRequired $repo "Assert-True (`$releaseNotes -match [regex]::Escape('# NexRoute 0.6.3 — Discord and YouTube strategy refresh')) 'Release notes describe 0.6.3'" "Assert-True (`$releaseNotes -match [regex]::Escape('# NexRoute 0.6.4 — hardening, evidence and explainable ranking')) 'Release notes describe 0.6.4'"
Replace-NrRequired $repo "Assert-True (`$acceptance -match [regex]::Escape('NexRoute 0.6.3 release acceptance')) '0.6.3 acceptance document exists'" "Assert-True (`$acceptance -match [regex]::Escape('NexRoute 0.6.4 release acceptance')) '0.6.4 acceptance document exists'"
Replace-NrRequired $repo "foreach (`$asset in @('NexRoute-0.6.3-win-x64.zip','NexRoute-0.6.3-win-x64.zip.sha256','NexRoute-0.6.3-validation.json','NexRoute-0.6.3-validation.md'))" "foreach (`$asset in @('NexRoute-0.6.4-win-x64.zip','NexRoute-0.6.4-win-x64.zip.sha256','NexRoute-0.6.4-validation.json','NexRoute-0.6.4-validation.md'))"
Replace-NrRequired $repo 'Assert-True ($releaseNotes -match [regex]::Escape($asset)) "Release notes document $asset"' 'Assert-True ($releaseNotes -match [regex]::Escape($asset)) "Release notes document $asset"'
Replace-NrRequired $repo "foreach (`$token in @('NexRoute 0.6.3','Test-WindowsLaunchers.ps1'" "foreach (`$token in @('NexRoute 0.6.4','Test-WindowsLaunchers.ps1'"

# Require the new release notes/acceptance docs in addition to historical release documentation.
$repoText=Read-NrText $repo
if(-not $repoText.Contains("'.github/release-notes/v0.6.4.md'")){
    $repoText=$repoText.Replace("'.github/release-notes/v0.6.3.md',", "'.github/release-notes/v0.6.3.md','.github/release-notes/v0.6.4.md',")
}
if(-not $repoText.Contains("'docs/RELEASE_0.6.4_ACCEPTANCE.md'")){
    $repoText=$repoText.Replace("'docs/RELEASE_0.6.3_ACCEPTANCE.md',", "'docs/RELEASE_0.6.3_ACCEPTANCE.md','docs/RELEASE_0.6.4_ACCEPTANCE.md',")
}
if(-not $repoText.Contains("'docs/STRATEGY_LAB_RANKING.md'")){
    $repoText=$repoText.Replace("'docs/FIELD_EVIDENCE.md',", "'docs/FIELD_EVIDENCE.md','docs/STRATEGY_LAB_RANKING.md','docs/GITHUB_ACTIONS_PINNING.md',")
}
Write-NrText $repo $repoText

# Changelog entry is intentionally factual and limited to implemented 0.6.4 scope.
$changelog='CHANGELOG.md'
$changeText=Read-NrText $changelog
if($changeText -notmatch '(?m)^##\s+0\.6\.4\b'){
    $entry=@'

## 0.6.4 — hardening, evidence and explainable ranking

- Added deterministic privacy-safe Strategy Lab field-evidence receipts with candidate/source hashes and fail-closed validation.
- Reworked Strategy Lab ranking around repeated critical-service observations, controls, stability, null-safe optional telemetry and explainable deterministic tie-breaking.
- Added transactional post-update health validation plus rollback/idempotence regression coverage and a real published 0.6.2 -> 0.6.3 migration evidence gate.
- Pinned every external GitHub Action in current and legacy workflows to reviewed full commit SHAs and added a fail-closed allowlist validator.
- Updated the native Dashboard to surface the same ranking/inconclusive/winner-explanation model used by the CLI.

'@
    if($changeText -match '^#\s+[^\r\n]+\r?\n'){
        $firstBreak=$changeText.IndexOf("`n")+1
        $changeText=$changeText.Substring(0,$firstBreak)+$entry+$changeText.Substring($firstBreak)
    } else {
        $changeText="# Changelog`n"+$entry+$changeText
    }
    Write-NrText $changelog $changeText
}

# Remove this one-shot synchronizer after it has materialized the version-bearing source files.
Remove-Item -LiteralPath $PSCommandPath -Force
