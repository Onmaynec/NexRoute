Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

if (-not (Get-Variable -Name NrLegacySetDnsProvider -Scope Script -ErrorAction SilentlyContinue)) {
    $script:NrLegacySetDnsProvider=$null
}
