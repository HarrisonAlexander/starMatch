<#
Capture-Screenshots.ps1 - renders every tab of the real shell to
docs\screenshots\NN-TabXxx.png (1904x1061) for the README.

Runs against a throwaway copy of data\demo-full.truehire.zip (staged in %TEMP%
via TRUEHIRE_DATA_ROOT), so your own data is never read or touched. Then run
assets\readme\source\make_art.py to refresh app-on-laptop.jpg.

Run:  powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tools\Capture-Screenshots.ps1
#>
$ErrorActionPreference = 'Stop'
$Script:RootDir = Split-Path -Parent $PSScriptRoot

# ---------- stage demo data ----------
$stage = Join-Path $env:TEMP ('truehire-shots-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead((Join-Path $Script:RootDir 'data\demo-full.truehire.zip'))
try {
    foreach ($e in $zip.Entries) {
        if ($e.FullName -in 'jobs.json','kits.json','candidates.json') {
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, (Join-Path $stage $e.FullName))
        }
    }
} finally { $zip.Dispose() }
@{ currentUser = @{ name = 'Jordan Lee'; role = 'Hiring Manager' } } |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stage 'settings.json') -Encoding UTF8
$env:TRUEHIRE_DATA_ROOT = $stage

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml, System.Windows.Forms
foreach ($f in 'lib\Logging','lib\Theme','lib\Data','lib\Export','lib\Helpers','lib\HtmlOutput','lib\ReportExcel',
               'views\Shell','views\Dashboard','views\JobReqs','views\InterviewKits','views\Candidates',
               'views\Analytics','views\QuestionLibrary') {
    . (Join-Path $Script:RootDir ($f + '.ps1'))
}

Initialize-TrueHireApp
$Data = Load-TrueHireData
$Script:ShellData = $Data
$w = ConvertTo-Window -Xaml $Script:ShellXaml
Set-WindowBanner -Window $w
$Script:Shell = $w
($w.FindName('UserName')).Text     = $Data.Settings.currentUser.name
($w.FindName('UserRole')).Text     = $Data.Settings.currentUser.role
($w.FindName('UserInitials')).Text = (Get-Initials $Data.Settings.currentUser.name)

$Script:ShotTabs = @('TabDashboard','TabJobReqs','TabKits','TabLibrary','TabCandidates','TabAnalytics')
foreach ($t in $Script:ShotTabs) { $Script:ShellTabs[$t] = $w.FindName($t) }
$w.WindowStartupLocation = 'Manual'; $w.Left = 0; $w.Top = 0; $w.Width = 1920; $w.Height = 1100
$Script:ShotWin = $w
$Script:ShotOut = Join-Path $Script:RootDir 'docs\screenshots'

# Content is arranged at a fixed 1904x1061 regardless of screen size / DPI,
# rendered with RenderTargetBitmap, then flattened onto the page background
# (#F4F6FA) because the shell's page area is transparent.
$w.Add_ContentRendered({
    $i = 1
    foreach ($t in $Script:ShotTabs) {
        Show-View $t
        Set-ShellStatus ('Loaded {0} job requisitions and {1} candidates.' -f $Script:ShellData.Jobs.Count, $Script:ShellData.Candidates.Count)
        $Script:ShotWin.UpdateLayout()
        [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::ContextIdle)
        $root = $Script:ShotWin.Content
        $root.Measure([System.Windows.Size]::new(1904, 1061))
        $root.Arrange([System.Windows.Rect]::new(0, 0, 1904, 1061))
        $root.UpdateLayout()
        [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Render)

        $dv = New-Object System.Windows.Media.DrawingVisual
        $dc = $dv.RenderOpen()
        $dc.DrawRectangle([System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(0xF4, 0xF6, 0xFA)), $null, [System.Windows.Rect]::new(0, 0, 1904, 1061))
        $dc.DrawRectangle([System.Windows.Media.VisualBrush]::new($root), $null, [System.Windows.Rect]::new(0, 0, 1904, 1061))
        $dc.Close()
        $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap(1904, 1061, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
        $rtb.Render($dv)

        $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
        $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
        $path = Join-Path $Script:ShotOut ('{0:00}-{1}.png' -f $i, $t)
        $fs = [System.IO.File]::Create($path); try { $enc.Save($fs) } finally { $fs.Close() }
        Write-Host ('saved {0}' -f $path)
        $i++
    }
    $Script:ShotWin.Close()
})
[void]$w.ShowDialog()
Remove-Item -LiteralPath $stage -Recurse -Force
