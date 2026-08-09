[CmdletBinding()]
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$approved = [ordered]@{
    'actions/checkout' = [ordered]@{ version = 'v6.1.0'; sha = 'd23441a48e516b6c34aea4fa41551a30e30af803' }
    'actions/setup-node' = [ordered]@{ version = 'v6.5.0'; sha = '249970729cb0ef3589644e2896645e5dc5ba9c38' }
    'actions/upload-artifact' = [ordered]@{ version = 'v7.0.1'; sha = '043fb46d1a93c77aae656e7c1c64a875d1fc6a0a' }
    'actions/attest' = [ordered]@{ version = 'v4.2.2'; sha = '1e69f48acb82d1966a394da916b4c1698aa569d6' }
    'actions/configure-pages' = [ordered]@{ version = 'v5.0.0'; sha = '983d7736d9b0ae728b81ab479565c72886d7745b' }
    'actions/upload-pages-artifact' = [ordered]@{ version = 'v5.0.0'; sha = 'fc324d3547104276b827a68afc52ff2a11cc49c9' }
    'actions/deploy-pages' = [ordered]@{ version = 'v4.0.5'; sha = 'd6db90164ac5ed86f2b6aed7e0febac5b3c0c03e' }
}

$workflowRoot = Join-Path $Root '.github/workflows'
if (-not (Test-Path -LiteralPath $workflowRoot -PathType Container)) {
    throw "GitHub Actions workflow directory is missing: $workflowRoot"
}

$errors = New-Object 'System.Collections.Generic.List[string]'
$usesCount = 0
$externalCount = 0
$workflowFiles = @(Get-ChildItem -LiteralPath $workflowRoot -File -ErrorAction Stop | Where-Object { $_.Extension -in @('.yml','.yaml') } | Sort-Object Name)

foreach ($file in $workflowFiles) {
    $lines = @(Get-Content -LiteralPath $file.FullName -Encoding UTF8)
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = [string]$lines[$index]
        $match = [regex]::Match($line, '^\s*-\s+uses:\s*(?<action>[^@\s#]+)@(?<ref>[^\s#]+)(?<comment>\s+#.*)?$')
        if (-not $match.Success) { continue }
        $usesCount++
        $action = [string]$match.Groups['action'].Value
        $ref = [string]$match.Groups['ref'].Value
        $comment = [string]$match.Groups['comment'].Value
        if ($action.StartsWith('./', [StringComparison]::Ordinal)) { continue }
        $externalCount++
        $location = '{0}:{1}' -f $file.Name, ($index + 1)

        if (-not $approved.Contains($action)) {
            $errors.Add("$location uses unknown external action '$action'. Add it to the reviewed allowlist with an immutable 40-character commit SHA before use.")
            continue
        }

        $entry = $approved[$action]
        if ($ref -notmatch '^[0-9a-f]{40}$') {
            $errors.Add("$location uses mutable ref '$action@$ref'. Expected full commit SHA $($entry.sha) ($($entry.version)).")
            continue
        }
        if ($ref -ne [string]$entry.sha) {
            $errors.Add("$location pins $action to unapproved SHA $ref. Expected $($entry.sha) ($($entry.version)).")
            continue
        }

        $expectedComment = '# {0} {1}' -f $action, $entry.version
        if ($comment.Trim() -ne $expectedComment) {
            $errors.Add("$location must keep the human-readable pin comment '$expectedComment'.")
        }
    }
}

if ($externalCount -eq 0) {
    $errors.Add('No external GitHub Actions references were found; the pinning validator cannot prove the workflow supply-chain contract.')
}

if ($errors.Count -gt 0) {
    throw ("GitHub Actions pinning validation failed:`n - " + ($errors -join "`n - "))
}

[pscustomobject]@{
    status = 'passed'
    workflowCount = $workflowFiles.Count
    usesCount = $usesCount
    externalActionCount = $externalCount
    approvedActionCount = $approved.Count
    approved = @(
        foreach ($name in $approved.Keys) {
            [pscustomobject]@{ action = $name; version = $approved[$name].version; sha = $approved[$name].sha }
        }
    )
}
