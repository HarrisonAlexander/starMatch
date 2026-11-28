<#
TrueHire.ps1 - entry point for TrueHire.

Loads WPF assemblies, dot-sources the library + view scripts, hydrates the
data model from %APPDATA%\TrueHire\* (seeded on first run from .\data),
then shows the main shell. Run from a PowerShell prompt:

    powershell -ExecutionPolicy Bypass -File .\TrueHire.ps1

The script is intentionally tiny - everything view-related lives under .\views
and the shared resources / data layer under .\lib.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
# Strict-mode "Latest" trips on JSON-loaded objects with absent optional
# properties (e.g. a kit without a `type` field, partial settings). The view
# code was built to tolerate those - leave strict mode off so missing
# properties read as $null instead of throwing.

# ---------- Locate root and load WPF assemblies ----------
$Script:RootDir = Split-Path -Parent $PSCommandPath

# Writable base for logs\ and outputs\. The MSI ships installed.flag next to
# this script because Program Files is read-only for normal users, so an
# installed copy writes them under %APPDATA%\TrueHire\ instead.
$Script:StateDir = if (Test-Path -LiteralPath (Join-Path $Script:RootDir 'installed.flag')) {
    Join-Path $env:APPDATA 'TrueHire'
} else { $Script:RootDir }

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml
Add-Type -AssemblyName System.Windows.Forms

# Pin a stable AppUserModelID so the taskbar groups our window separately
# from other PowerShell hosts.
try {
    Add-Type -Namespace _SM -Name Shell -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("shell32.dll", SetLastError=true)]
public static extern int SetCurrentProcessExplicitAppUserModelID(
    [System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.LPWStr)] string AppID);
'@ -ErrorAction SilentlyContinue
    [void][_SM.Shell]::SetCurrentProcessExplicitAppUserModelID('TrueHire.App.v3')
} catch { }

# ---------- Dot-source library + views ----------
. (Join-Path $Script:RootDir 'lib\Logging.ps1')
. (Join-Path $Script:RootDir 'lib\Theme.ps1')
. (Join-Path $Script:RootDir 'lib\Data.ps1')
. (Join-Path $Script:RootDir 'lib\Export.ps1')
. (Join-Path $Script:RootDir 'lib\Helpers.ps1')
. (Join-Path $Script:RootDir 'lib\HtmlOutput.ps1')
. (Join-Path $Script:RootDir 'lib\ReportExcel.ps1')
. (Join-Path $Script:RootDir 'views\Shell.ps1')
. (Join-Path $Script:RootDir 'views\Dashboard.ps1')
. (Join-Path $Script:RootDir 'views\JobReqs.ps1')
. (Join-Path $Script:RootDir 'views\InterviewKits.ps1')
. (Join-Path $Script:RootDir 'views\Candidates.ps1')
. (Join-Path $Script:RootDir 'views\Analytics.ps1')
. (Join-Path $Script:RootDir 'views\QuestionLibrary.ps1')

# ---------- Boot ----------
Initialize-TrueHireApp
Write-TrueHireSessionBanner
Register-TrueHireExceptionHandlers

try {
    $Data = Load-TrueHireData
    Write-TrueHireLog -Level INFO -Source 'Boot' -Message (
        "Loaded {0} jobs, {1} kits, {2} candidates from {3}" -f `
        $Data.Jobs.Count, $Data.Kits.Count, $Data.Candidates.Count, $Script:UserDataDir
    )
} catch {
    Write-TrueHireLog -Level FATAL -Source 'Boot' -Message 'Data load failed' -Exception $_.Exception
    throw
}

# Friendly first-run message in the console
Write-Host ""
Write-Host "  TrueHire" -ForegroundColor Cyan
Write-Host "  Loaded $($Data.Jobs.Count) job requisitions, $($Data.Candidates.Count) candidates, $($Data.Kits.Count) interview kits."
Write-Host "  User data: $Script:UserDataDir"
Write-Host "  Log file:  $(Get-TrueHireLogPath)"
Write-Host ""

try {
    Show-TrueHireShell -Data $Data
    Write-TrueHireLog -Level INFO -Source 'Boot' -Message 'Shell closed cleanly.'
} catch {
    Write-TrueHireLog -Level FATAL -Source 'Boot' -Message 'Shell threw on ShowDialog' -Exception $_.Exception
    throw
}
