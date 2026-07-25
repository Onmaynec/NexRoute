[CmdletBinding()]
param(
    [ValidateSet('status','remove','strategy','payload','tests','sync-ipset','sync-hosts','diagnostics','updates')]
    [string]$Page,
    [string]$LanguageFile
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
$width = 88
function Rule([char]$Fill = '=') { Write-Host ($Fill * $width) -ForegroundColor DarkCyan }
function Bar([string]$Label, [ConsoleColor]$Color = [ConsoleColor]::Cyan) {
    for ($p = 0; $p -le 100; $p += 10) {
        $filled = [int]($p / 5)
        $line = ('  {0,-32} [{1}] {2,3}%' -f $Label, (('#' * $filled) + ('-' * (20 - $filled))), $p)
        Write-Host ("`r" + $line) -NoNewline -ForegroundColor $Color
        Start-Sleep -Milliseconds 28
    }
    Write-Host
}
function Header([string]$Title, [string]$Subtitle) {
    Clear-Host
    Rule
    Write-Host '  NX' -NoNewline -ForegroundColor Magenta
    Write-Host ' // NEXROUTE CONTROL NODE' -ForegroundColor Cyan
    Write-Host ('  ' + $Title.ToUpperInvariant()) -ForegroundColor White
    Write-Host ('  ' + $Subtitle) -ForegroundColor DarkGray
    Rule '-'
}

switch ($Page) {
    'status' {
        Header 'Runtime telemetry' 'Service, driver and packet engine state'
        Bar 'Querying Windows services'
        Bar 'Scanning winws process table'
        Write-Host '  LIVE OUTPUT' -ForegroundColor Yellow
        Rule '-'
    }
    'remove' {
        Header 'Service purge' 'Stopping and removing NexRoute runtime components'
        Bar 'Preparing service shutdown' Yellow
        Write-Host '  REMOVAL LOG' -ForegroundColor Yellow
        Rule '-'
    }
    'strategy' {
        Header 'Strategy deployment' 'Select a packet-processing profile for the Windows service'
        Bar 'Indexing strategy launchers'
        Write-Host '  PROFILE CATALOG' -ForegroundColor Yellow
        Rule '-'
    }
    'payload' {
        Header 'Payload vault' 'Select active fake packet payloads for supported transports'
        Bar 'Scanning payload inventory' Magenta
        Write-Host '  PAYLOAD MATRIX' -ForegroundColor Yellow
        Rule '-'
    }
    'tests' {
        Header 'Strategy laboratory' 'Configuration and DPI tests require the service to be stopped'
        Bar 'Preparing isolated test environment' Yellow
        Write-Host '  TEST CONSOLE' -ForegroundColor Yellow
        Rule '-'
    }
    'sync-ipset' {
        Header 'IPSet synchronization' 'Refreshing network ranges and rebuilding the active data set'
        Bar 'Opening remote channel'
        Bar 'Downloading IP ranges'
        Bar 'Validating response' Green
        Bar 'Committing data set' Magenta
        Write-Host '  UPSTREAM SYNC LOG' -ForegroundColor Yellow
        Rule '-'
    }
    'sync-hosts' {
        Header 'Hosts synchronization' 'Refreshing system host mappings and validating permissions'
        Bar 'Checking administrator token'
        Bar 'Reading remote mappings'
        Bar 'Validating host records' Green
        Bar 'Preparing atomic update' Magenta
        Write-Host '  HOSTS SYNC LOG' -ForegroundColor Yellow
        Rule '-'
    }
    'diagnostics' {
        Header 'Diagnostic core' 'Scanning filters, proxies, drivers, DNS and conflicting software'
        Bar 'Initializing diagnostic probes'
        Write-Host '  DIAGNOSTIC STREAM' -ForegroundColor Yellow
        Rule '-'
    }
    'updates' {
        Header 'Release channel' 'Checking NexRoute version metadata and available packages'
        Bar 'Contacting release endpoint'
        Write-Host '  RELEASE CHECK' -ForegroundColor Yellow
        Rule '-'
    }
}
