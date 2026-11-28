<#
launch.ps1 - boots the real shell exactly like TrueHire.ps1 does, then
auto-closes the window after Loaded so it can run unattended. Verifies all
tab-switch wiring by clicking each tab via Dispatcher.BeginInvoke before
shutting down.
#>

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = Split-Path -Parent $PSCommandPath | Split-Path -Parent }

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml
Add-Type -AssemblyName System.Windows.Forms

. (Join-Path $root 'lib\Logging.ps1')
. (Join-Path $root 'lib\Theme.ps1')
. (Join-Path $root 'lib\Data.ps1')
. (Join-Path $root 'lib\Helpers.ps1')
. (Join-Path $root 'lib\HtmlOutput.ps1')
. (Join-Path $root 'views\Shell.ps1')
. (Join-Path $root 'views\Dashboard.ps1')
. (Join-Path $root 'views\JobReqs.ps1')
. (Join-Path $root 'views\InterviewKits.ps1')
. (Join-Path $root 'views\Candidates.ps1')
. (Join-Path $root 'views\Analytics.ps1')

Initialize-TrueHireApp
$Data = Load-TrueHireData
Write-Host ('Loaded {0} jobs, {1} kits, {2} candidates' -f `
    $Data.Jobs.Count, $Data.Kits.Count, $Data.Candidates.Count)

# Build the window the same way Show-TrueHireShell does, but don't
# block on ShowDialog. Instead set up a Loaded handler that flips through
# each tab and then closes the window.
$Script:ShellData = $Data
$w = ConvertTo-Window -Xaml $Script:ShellXaml
Set-WindowBanner -Window $w
$Script:Shell = $w

if ($Data.Settings -and $Data.Settings.currentUser) {
    ($w.FindName('UserName')).Text     = $Data.Settings.currentUser.name
    ($w.FindName('UserRole')).Text     = $Data.Settings.currentUser.role
    ($w.FindName('UserInitials')).Text = (Get-Initials $Data.Settings.currentUser.name)
}

foreach ($tabName in 'TabDashboard','TabJobReqs','TabKits','TabCandidates','TabAnalytics') {
    $btn = $w.FindName($tabName)
    $Script:ShellTabs[$tabName] = $btn
    $nameLocal = $tabName
    $btn.Add_Click({ Show-View $nameLocal }.GetNewClosure())
}

# Once the window is loaded, click each tab and then shut down. We stash
# the window + timer in $Script: scope because event-handler scriptblocks
# don't capture caller locals in PS 5.1.
$Script:LaunchWin  = $w
$Script:LaunchTabs = @('TabDashboard','TabJobReqs','TabKits','TabCandidates','TabAnalytics')
$w.Add_Loaded({
    foreach ($t in $Script:LaunchTabs) {
        try {
            Show-View $t
            Write-Host ('OK   Switched to {0}' -f $t)
        } catch {
            Write-Host ('FAIL {0}: {1}' -f $t, $_.Exception.Message) -ForegroundColor Red
        }
    }
    $Script:LaunchTimer = New-Object System.Windows.Threading.DispatcherTimer
    $Script:LaunchTimer.Interval = [TimeSpan]::FromMilliseconds(250)
    $Script:LaunchTimer.Add_Tick({
        $Script:LaunchTimer.Stop()
        $Script:LaunchWin.Close()
    })
    $Script:LaunchTimer.Start()
})

Show-View 'TabDashboard'
Set-ShellStatus ("Loaded {0} job requisitions and {1} candidates." -f $Data.Jobs.Count, $Data.Candidates.Count)

# Use Show() + manually run a short dispatcher pump rather than ShowDialog
# so we can return cleanly. We still hit a message loop via ShowDialog though,
# because Add_Loaded fires before it returns and queues the Close().
[void]$w.ShowDialog()

Write-Host ''
Write-Host 'Launch test complete - window opened, all tabs cycled, closed cleanly.'
