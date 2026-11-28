<#
reset-to-empty.ps1 - wipe the local working copy so the app boots blank.

Use this when:
  - You've been working with demo data (tools/Make-DemoData.ps1) and
    want to return to a clean slate.
  - Your APPDATA copy has accumulated test data you don't need.
  - You're preparing a fresh install for end users - though for a true
    "shipped install" scenario, the seed files in data/sample-*.json
    are already empty, so deploying the repo + first run lands blank
    automatically.

What it does:
  - Removes %APPDATA%\TrueHire\jobs.json, kits.json, candidates.json.
  - Optionally removes settings.json too (with -IncludeSettings).
  - Does NOT touch data/sample-*.json - those are the install seeds.
  - Does NOT touch the catalog or positions catalogs in data/.

Next time you launch TrueHire.ps1, Initialize-UserData will see the
missing APPDATA files and copy fresh empty seeds from data/sample-*.json.

Usage:
  powershell -ExecutionPolicy Bypass -File .\tools\reset-to-empty.ps1
  powershell -ExecutionPolicy Bypass -File .\tools\reset-to-empty.ps1 -IncludeSettings
#>

[CmdletBinding()]
param(
    [switch]$IncludeSettings
)

$ErrorActionPreference = 'Stop'
$appData = Join-Path $env:APPDATA 'TrueHire'

if (-not (Test-Path -LiteralPath $appData)) {
    Write-Host "No %APPDATA%\TrueHire\ directory found - already in fresh state." -ForegroundColor Green
    return
}

$targets = @('jobs.json', 'kits.json', 'candidates.json')
if ($IncludeSettings) { $targets += 'settings.json' }

$removed = @()
foreach ($name in $targets) {
    $path = Join-Path $appData $name
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force
        $removed += $name
    }
}

if ($removed.Count -eq 0) {
    Write-Host "Nothing to remove - already empty." -ForegroundColor Green
} else {
    Write-Host ("Removed: {0}" -f ($removed -join ', ')) -ForegroundColor Cyan
    Write-Host "Next TrueHire.ps1 launch will reseed from data/sample-*.json (empty by default)."
}
