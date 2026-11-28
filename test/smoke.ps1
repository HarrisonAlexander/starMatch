<#
smoke.ps1 - sanity check that every view's XAML parses, every Show-*View
function loads its content host without throwing, and Compute-Metrics runs
clean on the seed data. Closes the window after rendering each view so it
runs unattended.
#>

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $root) { $root = Split-Path -Parent $PSCommandPath | Split-Path -Parent }

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml

. (Join-Path $root 'lib\Logging.ps1')
. (Join-Path $root 'lib\Theme.ps1')
. (Join-Path $root 'lib\Data.ps1')
. (Join-Path $root 'lib\Export.ps1')
. (Join-Path $root 'lib\Helpers.ps1')
. (Join-Path $root 'lib\HtmlOutput.ps1')
. (Join-Path $root 'lib\ReportExcel.ps1')
. (Join-Path $root 'views\Shell.ps1')
. (Join-Path $root 'views\Dashboard.ps1')
. (Join-Path $root 'views\JobReqs.ps1')
. (Join-Path $root 'views\InterviewKits.ps1')
. (Join-Path $root 'views\Candidates.ps1')
. (Join-Path $root 'views\Analytics.ps1')
. (Join-Path $root 'views\QuestionLibrary.ps1')

Initialize-TrueHireApp
$Script:ShellData = Load-TrueHireData

# Assert: every kit-question carries the new fields (probe text + opaque id)
# after migration. Catches a broken _MigrateKit early.
$migrationFailed = $false
foreach ($k in @($Script:ShellData.Kits)) {
    foreach ($cat in @($k.categories)) {
        foreach ($q in @($cat.questions)) {
            if (-not $q.PSObject.Properties['probe'] -or -not $q.PSObject.Properties['id']) {
                Write-Host ("FAIL _MigrateKit left kit={0} cat={1} question without probe/id" -f $k.id, $cat.id) -ForegroundColor Red
                $migrationFailed = $true
            }
        }
    }
}
if (-not $migrationFailed) { Write-Host 'OK   _MigrateKit produced canonical shape for every kit-question' }

# Assert: _MigrateKit backfills weight=1 on a category that lacks it.
$wtKit = New-InterviewKit -JobReqId 'req-wtmig'
$wtKit.categories = @([pscustomobject]@{ id = 'tech'; name = 'Tech'; description = 'x'; questions = @() })
_MigrateKit $wtKit $Script:ShellData.Catalog | Out-Null
if ($wtKit.categories[0].PSObject.Properties['weight'] -and [double]$wtKit.categories[0].weight -eq 1) {
    Write-Host 'OK   _MigrateKit backfilled category weight=1'
} else {
    Write-Host 'FAIL _MigrateKit did not backfill category weight' -ForegroundColor Red
}

# _BuildCategorySectionHeader assertions live further down - the header now
# builds reorder-arrow Buttons via $Script:Shell.FindResource('IconBtn'), so
# they must run after the shell window is created below.

Write-Host ('Loaded {0} jobs, {1} kits, {2} candidates' -f `
    $Script:ShellData.Jobs.Count, $Script:ShellData.Kits.Count, $Script:ShellData.Candidates.Count)

# Run Compute-Metrics + Find-RecentActivity
$m = Compute-Metrics $Script:ShellData
Write-Host ('Metrics: ActiveReqs={0} TotalReqs={1} Cand={2} Adv={3} Hired={4} Match={5}%' -f `
    $m.ActiveReqs, $m.TotalReqs, $m.TotalCandidates, $m.Advanced, $m.Hired, $m.OverallMatchPct)
$ra = Find-RecentActivity $Script:ShellData 4
Write-Host ('Recent activity entries: {0}' -f @($ra).Count)

# Try each view's XAML by feeding it into a host Grid (no Window shown).
$views = @(
    @{ Name='Dashboard';       Xaml=$Script:DashboardXaml }
    @{ Name='JobReqs';         Xaml=$Script:JobReqsXaml }
    @{ Name='InterviewKits';   Xaml=$Script:KitsXaml }
    @{ Name='QuestionLibrary'; Xaml=$Script:QuestionLibraryXaml }
    @{ Name='Candidates';      Xaml=$Script:CandidatesXaml }
    @{ Name='Analytics';       Xaml=$Script:AnalyticsXaml }
)
foreach ($v in $views) {
    if (-not $v.Xaml) { Write-Host ("MISSING XAML var for " + $v.Name) -ForegroundColor Red; continue }
    try {
        $null = [System.Windows.Markup.XamlReader]::Parse($v.Xaml)
        Write-Host ('OK   {0} XAML parses' -f $v.Name)
    } catch {
        Write-Host ('FAIL {0} XAML: {1}' -f $v.Name, $_.Exception.Message) -ForegroundColor Red
    }
}

# Parse the shell XAML too
try {
    $null = [System.Windows.Markup.XamlReader]::Parse($Script:ShellXaml)
    Write-Host 'OK   Shell XAML parses'
} catch {
    Write-Host ('FAIL Shell XAML: ' + $_.Exception.Message) -ForegroundColor Red
}

# Parse every modal/dialog XAML too. Without this, a malformed dialog only
# surfaces when the user actually clicks the button that opens it - which is
# exactly how the candidate-detail "Cannot convert value" XAML bug shipped
# unnoticed. Catch them here at boot.
$dialogs = @(
    'JobReqDetailXaml'        # views\JobReqs.ps1
    'ImportConflictXaml'      # views\JobReqs.ps1
    'DeleteJobReqXaml'        # views\JobReqs.ps1
    'CandDetailXaml'          # views\Candidates.ps1
    'RaterEntryXaml'          # views\Candidates.ps1
    'KitPreviewXaml'          # views\InterviewKits.ps1
    'KitEditXaml'             # views\InterviewKits.ps1
    'PickCatalogProbeXaml'    # views\InterviewKits.ps1
    'KitBuilderXaml'          # views\InterviewKits.ps1
    'PickJobForKitXaml'       # views\InterviewKits.ps1
    'FullExportXaml'           # views\JobReqs.ps1
)
foreach ($name in $dialogs) {
    $xaml = Get-Variable -Scope Script -Name $name -ErrorAction SilentlyContinue
    if (-not $xaml -or -not $xaml.Value) { Write-Host ("MISSING dialog XAML var: $name") -ForegroundColor Red; continue }
    try {
        $null = [System.Windows.Markup.XamlReader]::Parse($xaml.Value)
        Write-Host ('OK   dialog {0} XAML parses' -f $name)
    } catch {
        Write-Host ('FAIL dialog {0}: {1}' -f $name, $_.Exception.Message) -ForegroundColor Red
    }
}

# Set up a Shell window for $Script:Shell.FindResource() lookups inside views.
# The real entry point would have called Show-TrueHireShell, which sets this.
$Script:Shell = ConvertTo-Window -Xaml $Script:ShellXaml

# ---- Global UI scale (lib/Theme.ps1 -> ConvertTo-Window / Set-WindowUiScale) ----
# The shell was just built through ConvertTo-Window, which scales every window.
# These assertions are the test-first gate for the 20% UI-scale feature.
$expectScale = $Script:UiScale
if (-not $expectScale) { $expectScale = 1 }

$lt = $Script:Shell.Content.LayoutTransform
if ($lt -is [System.Windows.Media.ScaleTransform] -and
    [Math]::Abs($lt.ScaleX - $expectScale) -lt 0.0001 -and
    [Math]::Abs($lt.ScaleY - $expectScale) -lt 0.0001) {
    Write-Host ('OK   shell content scaled {0}x via LayoutTransform' -f $expectScale)
} else {
    Write-Host ('FAIL shell content LayoutTransform not {0}x (got: {1})' -f $expectScale, $lt) -ForegroundColor Red
}

$wa = [System.Windows.SystemParameters]::WorkArea
$expectW = [Math]::Min(1280 * $expectScale, $wa.Width)   # shell XAML is Width=1280
$expectH = [Math]::Min(820  * $expectScale, $wa.Height)  # shell XAML is Height=820
if ([Math]::Abs($Script:Shell.Width  - $expectW) -lt 0.5 -and
    [Math]::Abs($Script:Shell.Height - $expectH) -lt 0.5) {
    Write-Host ('OK   shell window box scaled/clamped to {0}x{1}' -f [int]$expectW, [int]$expectH)
} else {
    Write-Host ('FAIL shell window box {0}x{1}, expected {2}x{3}' -f `
        $Script:Shell.Width, $Script:Shell.Height, [int]$expectW, [int]$expectH) -ForegroundColor Red
}

# _BuildCategorySectionHeader: label + pluralized count on the left, and
# category-reorder arrows on the right that grey at the first/last category.
# Needs $Script:Shell (set just above) for the IconBtn style lookup.
$hdrCat   = [pscustomobject]@{ id = 'Problem Solving'; name = 'Problem Solving'; description = ''; questions = @() }
$hdrFirst = _BuildCategorySectionHeader $hdrCat 2 0 3   # first of three
$hdrLast  = _BuildCategorySectionHeader $hdrCat 1 2 3   # last of three
# Child = Grid; Children[0] = label stack (name+count), Children[1] = arrows.
$hdrFirstTx = (($hdrFirst.Child.Children[0].Children | ForEach-Object { $_.Text }) -join '')
$hdrLastTx  = (($hdrLast.Child.Children[0].Children | ForEach-Object { $_.Text }) -join '')
if ($hdrFirstTx -match 'Problem Solving' -and $hdrFirstTx -match '2 questions' -and $hdrLastTx -match '1 question\b') {
    Write-Host 'OK   _BuildCategorySectionHeader renders label + pluralized count'
} else {
    Write-Host ("FAIL _BuildCategorySectionHeader text was '{0}' / '{1}'" -f $hdrFirstTx, $hdrLastTx) -ForegroundColor Red
}
$firstArrows = $hdrFirst.Child.Children[1].Children   # [Up, Down] at index 0 of 3
$lastArrows  = $hdrLast.Child.Children[1].Children     # [Up, Down] at index 2 of 3
if (-not $firstArrows[0].IsEnabled -and $firstArrows[1].IsEnabled -and `
        $lastArrows[0].IsEnabled -and -not $lastArrows[1].IsEnabled) {
    Write-Host 'OK   category-reorder arrows grey at first (Up) / last (Down)'
} else {
    Write-Host ('FAIL category arrow enable first(Up={0},Down={1}) last(Up={2},Down={3})' -f `
        $firstArrows[0].IsEnabled, $firstArrows[1].IsEnabled, $lastArrows[0].IsEnabled, $lastArrows[1].IsEnabled) -ForegroundColor Red
}

# Actually render each view into a host Grid to surface any wiring errors
foreach ($v in $views) {
    try {
        $hostGrid = New-Object System.Windows.Controls.Grid
        $fn   = "Show-$($v.Name)View"
        if ($v.Name -eq 'JobReqs') { $fn = 'Show-JobRequisitionsView' }
        if ($v.Name -eq 'InterviewKits') { $fn = 'Show-InterviewKitsView' }
        & $fn $hostGrid
        Write-Host ('OK   {0} renders ({1} child elements)' -f $v.Name, $hostGrid.Children.Count)
    } catch {
        Write-Host ('FAIL {0} render: {1}' -f $v.Name, $_.Exception.Message) -ForegroundColor Red
        Write-Host ('     at: ' + $_.ScriptStackTrace) -ForegroundColor DarkGray
    }
}


# ============================================================
# Export/Import round-trip (lib/Export.ps1)
# ============================================================
Write-Host ''
Write-Host 'Export/Import round-trip:' -ForegroundColor Cyan

$victim = $Script:ShellData.Jobs | Where-Object {
    $cands = Get-CandidatesFor $Script:ShellData $_.id
    if (-not $cands -or @($cands).Count -eq 0) { return $false }
    $rater = 0
    foreach ($c in @($cands)) { if ($c.raterEntries) { $rater += @($c.raterEntries).Count } }
    return ($rater -gt 0)
} | Select-Object -First 1

if (-not $victim) {
    Write-Host '  SKIP no job with rater entries; round-trip not exercised' -ForegroundColor Yellow
} else {
    $tmpZip = Join-Path $env:TEMP ("smoke-export-{0}.truehire.zip" -f [guid]::NewGuid().ToString('N'))
    try {
        $b1 = New-JobReqExportBundle -Data $Script:ShellData -JobId $victim.id
        Write-JobReqExportBundle -Bundle $b1 -Path $tmpZip
        if (-not (Test-Path -LiteralPath $tmpZip)) {
            Write-Host '  FAIL export did not produce a file' -ForegroundColor Red
        } else {
            $b2 = Read-JobReqExportBundle -Path $tmpZip
            try {
                if ($b2.Manifest.counts.candidates -ne @($b1.Candidates).Count) {
                    Write-Host '  FAIL candidate count mismatch in manifest' -ForegroundColor Red
                } else {
                    Write-Host ('  OK   manifest counts candidates={0} raterEntries={1}' -f `
                        $b2.Manifest.counts.candidates, $b2.Manifest.counts.raterEntries)
                }

                $j1 = ConvertTo-Json -InputObject @($b1.Candidates) -Depth 12
                $j2 = ConvertTo-Json -InputObject @($b2.Candidates) -Depth 12
                if ($j1 -ne $j2) {
                    Write-Host '  FAIL candidate payload drifted through round-trip' -ForegroundColor Red
                } else {
                    Write-Host '  OK   candidate payload byte-identical through round-trip'
                }

                # Snapshot live counts (we'll mutate, then restore)
                $snapJobs = @($Script:ShellData.Jobs)
                $snapKits = @($Script:ShellData.Kits)
                $snapCand = @($Script:ShellData.Candidates)
                try {
                    $sumNew = Import-JobReqExportBundle -Data $Script:ShellData -Bundle $b2 -Mode New
                    if ($sumNew.JobId -eq $victim.id) {
                        Write-Host '  FAIL New mode reused original job id' -ForegroundColor Red
                    } else {
                        Write-Host ('  OK   New mode minted fresh job id ({0})' -f $sumNew.JobId)
                    }

                    # Restore data to pristine snapshot before testing Replace
                    $Script:ShellData.Jobs       = $snapJobs
                    $Script:ShellData.Kits       = $snapKits
                    $Script:ShellData.Candidates = $snapCand

                    $sumRep = Import-JobReqExportBundle -Data $Script:ShellData -Bundle $b2 -Mode Replace
                    if ($sumRep.JobId -ne $victim.id) {
                        Write-Host '  FAIL Replace mode changed the job id' -ForegroundColor Red
                    } else {
                        Write-Host '  OK   Replace mode preserved job id'
                    }
                } finally {
                    $Script:ShellData.Jobs       = $snapJobs
                    $Script:ShellData.Kits       = $snapKits
                    $Script:ShellData.Candidates = $snapCand
                }
            } finally {
                if ($b2 -and $b2.ScratchDir -and (Test-Path -LiteralPath $b2.ScratchDir)) {
                    Remove-Item -LiteralPath $b2.ScratchDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    } catch {
        Write-Host ('  FAIL round-trip threw: {0}' -f $_.Exception.Message) -ForegroundColor Red
        Write-Host ('       at: ' + $_.ScriptStackTrace) -ForegroundColor DarkGray
    } finally {
        if (Test-Path -LiteralPath $tmpZip) { Remove-Item -LiteralPath $tmpZip -Force -ErrorAction SilentlyContinue }
    }
}

# ============================================================
# Full export/import round-trip (lib/Export.ps1 - truehire.fullexport/1)
# ============================================================
Write-Host ''
Write-Host 'Full export/import (multi-job):' -ForegroundColor Cyan

# Deterministic in-memory fixture: jobA recent, jobB ~200 days old.
$fxA = New-JobReq; $fxA.id = 'req-fxA'; $fxA.title = 'Fixture A'; $fxA.modifiedDate = (Get-Date).ToString('s')
$fxB = New-JobReq; $fxB.id = 'req-fxB'; $fxB.title = 'Fixture B'
$fxB.createdDate = (Get-Date).AddDays(-200).ToString('s'); $fxB.modifiedDate = (Get-Date).AddDays(-200).ToString('s')
$fxCA = New-Candidate; $fxCA.id = 'cand-fxA1'; $fxCA.jobReqId = 'req-fxA'; $fxCA.appliedDate = (Get-Date).ToString('yyyy-MM-dd')
$fxCB = New-Candidate; $fxCB.id = 'cand-fxB1'; $fxCB.jobReqId = 'req-fxB'; $fxCB.appliedDate = (Get-Date).AddDays(-200).ToString('yyyy-MM-dd')
$fxK  = New-InterviewKit -JobReqId 'req-fxA'; $fxK.id = 'kit-fxA'
$fx = @{ Jobs = @($fxA, $fxB); Kits = @($fxK); Candidates = @($fxCA, $fxCB); Catalog = $Script:ShellData.Catalog; Settings = $null }

$r30 = Get-FullExportRange -Preset 'last30'
$incRecent = Test-JobInDateWindow -Data $fx -Job $fxA -From $r30.From -To $r30.To
$incOld    = Test-JobInDateWindow -Data $fx -Job $fxB -From $r30.From -To $r30.To
if ($incRecent -and -not $incOld) {
    Write-Host '  OK   date-window predicate includes recent job, excludes old job'
} else {
    Write-Host ('  FAIL date-window predicate recent={0} old={1}' -f $incRecent, $incOld) -ForegroundColor Red
}

$bAll = New-FullExportBundle -Data $fx -Mode 'all'
if ($bAll.Jobs.Count -eq 2 -and $bAll.Kits.Count -eq 1 -and $bAll.Candidates.Count -eq 2) {
    Write-Host '  OK   full export (all) gathered 2 jobs / 1 kit / 2 candidates'
} else {
    Write-Host ('  FAIL full export all j={0} k={1} c={2}' -f $bAll.Jobs.Count, $bAll.Kits.Count, $bAll.Candidates.Count) -ForegroundColor Red
}

$b30 = New-FullExportBundle -Data $fx -Mode 'last30' -From $r30.From -To $r30.To
if ($b30.Jobs.Count -eq 1 -and $b30.Jobs[0].id -eq 'req-fxA') {
    Write-Host '  OK   ranged export (last30) included only the recent job'
} else {
    Write-Host ('  FAIL ranged export count={0}' -f $b30.Jobs.Count) -ForegroundColor Red
}

$tmpFull = Join-Path $env:TEMP ("smoke-full-{0}.truehire.zip" -f [guid]::NewGuid().ToString('N'))
try {
    Write-FullExportBundle -Bundle $bAll -Path $tmpFull
    if ((Get-BundleSchema -Path $tmpFull) -eq $Script:FullBundleSchema) {
        Write-Host '  OK   Get-BundleSchema detects fullexport bundle'
    } else {
        Write-Host '  FAIL Get-BundleSchema did not detect fullexport' -ForegroundColor Red
    }
    $rd = Read-FullExportBundle -Path $tmpFull
    try {
        if ($rd.Jobs.Count -eq 2 -and $rd.Candidates.Count -eq 2) {
            Write-Host '  OK   read-back counts match (2 jobs / 2 candidates)'
        } else {
            Write-Host ('  FAIL read-back j={0} c={1}' -f $rd.Jobs.Count, $rd.Candidates.Count) -ForegroundColor Red
        }
        $tgt = @{ Jobs = @(); Kits = @(); Candidates = @(); Catalog = $fx.Catalog; Settings = $null }
        $null  = Import-FullExportBundle -Data $tgt -Bundle $rd
        $after1 = @($tgt.Jobs).Count
        $rd2 = Read-FullExportBundle -Path $tmpFull
        try { $s2 = Import-FullExportBundle -Data $tgt -Bundle $rd2 }
        finally { if ($rd2.ScratchDir -and (Test-Path -LiteralPath $rd2.ScratchDir)) { Remove-Item -LiteralPath $rd2.ScratchDir -Recurse -Force -ErrorAction SilentlyContinue } }
        $after2 = @($tgt.Jobs).Count
        if ($after1 -eq 2 -and $after2 -eq 2 -and $s2.JobsUpdated -eq 2 -and $s2.JobsAdded -eq 0) {
            Write-Host '  OK   merge import is idempotent (no duplicates on re-import)'
        } else {
            Write-Host ('  FAIL idempotency after1={0} after2={1} upd={2} add={3}' -f $after1, $after2, $s2.JobsUpdated, $s2.JobsAdded) -ForegroundColor Red
        }
    } finally {
        if ($rd.ScratchDir -and (Test-Path -LiteralPath $rd.ScratchDir)) { Remove-Item -LiteralPath $rd.ScratchDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
} finally {
    if (Test-Path -LiteralPath $tmpFull) { Remove-Item -LiteralPath $tmpFull -Force -ErrorAction SilentlyContinue }
}

# ============================================================
# Weighted category scoring (lib/Helpers.ps1 - Get-CandidateScore)
# ============================================================
Write-Host ''
Write-Host 'Weighted category scoring:' -ForegroundColor Cyan

# Helper to build a candidate with one Submitted rater entry rating the given
# categories. $Cells is a hashtable catId -> anchor (1..5).
function _SmkCand {
    param([string]$JobReqId, [hashtable]$Cells)
    $c = New-Candidate
    $c.jobReqId = $JobReqId
    $ratings = [pscustomobject]@{}
    foreach ($k in $Cells.Keys) {
        Add-Member -InputObject $ratings -MemberType NoteProperty -Name $k `
            -Value ([pscustomobject]@{ anchor = [int]$Cells[$k]; note = '' })
    }
    $entry = New-RaterEntry -RaterName 'Smoke' -RaterRole 'HM'
    $entry.status  = 'Submitted'
    $entry.ratings = $ratings
    $c.raterEntries = @($entry)
    return $c
}

# Kit: tech weighted 4, comm weighted 1, on job 'req-wt'.
$wtKit = New-InterviewKit -JobReqId 'req-wt'
$wtKit.categories = @(
    [pscustomobject]@{ id = 'tech'; name = 'Tech'; description = 'x'; weight = 4; questions = @() }
    [pscustomobject]@{ id = 'comm'; name = 'Comm'; description = 'x'; weight = 1; questions = @() }
)
$wtData = @{ Jobs = @(); Kits = @($wtKit); Candidates = @(); Catalog = $Script:ShellData.Catalog; Settings = $null }

# 1) tech=5 (100), comm=2 (40). Equal -> 70. Weighted (4,1) -> (400+40)/5 = 88.
$cBoth = _SmkCand 'req-wt' @{ tech = 5; comm = 2 }
$uneq  = Get-CandidateScore $cBoth
$wei   = Get-CandidateScore $cBoth $wtData
if ($uneq -eq 70) { Write-Host '  OK   unweighted mean = 70' } else { Write-Host ('  FAIL unweighted={0} expected 70' -f $uneq) -ForegroundColor Red }
if ($wei  -eq 88) { Write-Host '  OK   weighted (4,1) = 88' } else { Write-Host ('  FAIL weighted={0} expected 88' -f $wei) -ForegroundColor Red }

# 2) All-equal kit reproduces the unweighted score exactly.
$eqKit = New-InterviewKit -JobReqId 'req-eq'
$eqKit.categories = @(
    [pscustomobject]@{ id = 'tech'; name = 'Tech'; description = 'x'; weight = 1; questions = @() }
    [pscustomobject]@{ id = 'comm'; name = 'Comm'; description = 'x'; weight = 1; questions = @() }
)
$eqData = @{ Jobs = @(); Kits = @($eqKit); Candidates = @(); Catalog = $Script:ShellData.Catalog; Settings = $null }
$cEq = _SmkCand 'req-eq' @{ tech = 5; comm = 2 }
if ((Get-CandidateScore $cEq $eqData) -eq (Get-CandidateScore $cEq)) {
    Write-Host '  OK   all-equal weights match unweighted score'
} else { Write-Host '  FAIL all-equal weights drifted from unweighted' -ForegroundColor Red }

# 3) Heavy category unrated -> renormalize across rated categories (no drag).
#    Only comm rated (40); tech (weight 4) unrated -> score = 40, not pulled down.
$cMiss = _SmkCand 'req-wt' @{ comm = 2 }
$mis = Get-CandidateScore $cMiss $wtData
if ($mis -eq 40) { Write-Host '  OK   unrated heavy category renormalizes (= 40)' } else { Write-Host ('  FAIL renormalized={0} expected 40' -f $mis) -ForegroundColor Red }

# 4) Rated category absent from the kit defaults to weight 1 (nothing dropped).
#    Kit has only tech (weight 4). Candidate rates tech=3 (60) and extra=5 (100).
#    Weighted: (4*60 + 1*100)/5 = 68.
$soloKit = New-InterviewKit -JobReqId 'req-solo'
$soloKit.categories = @([pscustomobject]@{ id = 'tech'; name = 'Tech'; description = 'x'; weight = 4; questions = @() })
$soloData = @{ Jobs = @(); Kits = @($soloKit); Candidates = @(); Catalog = $Script:ShellData.Catalog; Settings = $null }
$cExtra = _SmkCand 'req-solo' @{ tech = 3; extra = 5 }
$ext = Get-CandidateScore $cExtra $soloData
if ($ext -eq 68) { Write-Host '  OK   category absent from kit defaults to weight 1 (= 68)' } else { Write-Host ('  FAIL absent-category={0} expected 68' -f $ext) -ForegroundColor Red }

# Category-weights panel builds with one row per category and live percents.
$panel = _BuildCategoryWeightsPanel $wtKit
if ($panel -is [System.Windows.FrameworkElement]) {
    Write-Host '  OK   _BuildCategoryWeightsPanel returns a FrameworkElement'
} else {
    Write-Host '  FAIL _BuildCategoryWeightsPanel did not return a control' -ForegroundColor Red
}

# ============================================================
# Category reorder (views/InterviewKits.ps1 - _MoveKitCategory)
# ============================================================
Write-Host ''
Write-Host 'Category reorder:' -ForegroundColor Cyan

# Build a kit with three categories, register it, then move the last one up.
# Stub Save-Kits/Show-View so the move neither writes userdata nor re-renders
# the shell. Done last in the file so the stubs can't affect earlier sections.
$mvKit = New-InterviewKit -JobReqId 'req-catmv'; $mvKit.id = 'kit-catmv'
$mvKit.categories = @(
    [pscustomobject]@{ id = 'a'; name = 'A'; description = 'x'; weight = 1; questions = @() }
    [pscustomobject]@{ id = 'b'; name = 'B'; description = 'x'; weight = 1; questions = @() }
    [pscustomobject]@{ id = 'c'; name = 'C'; description = 'x'; weight = 1; questions = @() }
)
$mvSnapKits = @($Script:ShellData.Kits)
$mvSnapKit  = $Script:CurrentKitId
$Script:ShellData.Kits = @($Script:ShellData.Kits) + $mvKit
$Script:CurrentKitId = 'kit-catmv'
function Save-Kits { param($Data) }   # stub: no disk write
function Show-View { param($Tab) }    # stub: no re-render
try {
    _MoveKitCategory 'kit-catmv' 'c' 'Up'
    $order1 = (@($mvKit.categories | ForEach-Object { $_.id }) -join ',')
    if ($order1 -eq 'a,c,b') {
        Write-Host '  OK   move last category Up -> a,c,b'
    } else {
        Write-Host ("  FAIL move Up gave '{0}' expected 'a,c,b'" -f $order1) -ForegroundColor Red
    }
    # Down on the first category swaps it past the (now) second.
    _MoveKitCategory 'kit-catmv' 'a' 'Down'
    $order2 = (@($mvKit.categories | ForEach-Object { $_.id }) -join ',')
    if ($order2 -eq 'c,a,b') {
        Write-Host '  OK   move first category Down -> c,a,b'
    } else {
        Write-Host ("  FAIL move Down gave '{0}' expected 'c,a,b'" -f $order2) -ForegroundColor Red
    }
    # Edge no-op: moving the first category Up leaves order unchanged.
    _MoveKitCategory 'kit-catmv' 'c' 'Up'
    $order3 = (@($mvKit.categories | ForEach-Object { $_.id }) -join ',')
    if ($order3 -eq 'c,a,b') {
        Write-Host '  OK   move first category Up is a no-op'
    } else {
        Write-Host ("  FAIL edge no-op gave '{0}' expected 'c,a,b'" -f $order3) -ForegroundColor Red
    }
} finally {
    $Script:ShellData.Kits = $mvSnapKits
    $Script:CurrentKitId   = $mvSnapKit
}

# ============================================================
# Candidate ranking (lib/Helpers.ps1 - ConvertTo-Ordinal / Get-CandidateRankInfo)
# ============================================================
Write-Host ''
Write-Host 'Candidate ranking:' -ForegroundColor Cyan

# ConvertTo-Ordinal: English ordinal suffixes incl. the 11-13 exceptions.
$ordCases = @{ 1='1st'; 2='2nd'; 3='3rd'; 4='4th'; 11='11th'; 12='12th'; 13='13th'; 21='21st'; 22='22nd'; 23='23rd' }
$ordOk = $true
foreach ($k in ($ordCases.Keys | Sort-Object)) {
    $got = ConvertTo-Ordinal $k
    if ($got -ne $ordCases[$k]) { $ordOk = $false; Write-Host ("  FAIL ConvertTo-Ordinal {0} = '{1}' expected '{2}'" -f $k, $got, $ordCases[$k]) -ForegroundColor Red }
}
if ($ordOk) { Write-Host '  OK   ConvertTo-Ordinal covers 1st..23rd incl. 11/12/13th' }

# Get-CandidateRankInfo: per-job ranking, shared place on ties, rated-only pool.
# Reuse the smoke _SmkCand helper (defined in the weighted-scoring section above)
# to build candidates with one Submitted entry. With no kit in $rkData every
# weight is 1, so each candidate's score is the equal mean of its category
# anchors * 20. Scores below: A=100, B=80, C=80, D=60 -> places 1,2,2,4; plus
# one unrated candidate (no raterEntries) which must rank $null.
$rkJob = 'req-rank'
# A: tech=5,comm=5 => 100 ; B: tech=4,comm=4 => 80 ; C: tech=4,comm=4 => 80 ; D: tech=3,comm=3 => 60
$rkA = _SmkCand $rkJob @{ tech = 5; comm = 5 }; $rkA.id = 'rk-A'
$rkB = _SmkCand $rkJob @{ tech = 4; comm = 4 }; $rkB.id = 'rk-B'
$rkC = _SmkCand $rkJob @{ tech = 4; comm = 4 }; $rkC.id = 'rk-C'
$rkD = _SmkCand $rkJob @{ tech = 3; comm = 3 }; $rkD.id = 'rk-D'
$rkU = New-Candidate; $rkU.jobReqId = $rkJob; $rkU.id = 'rk-U'   # unrated (no raterEntries)
$rkData = @{ Jobs=@(); Kits=@(); Candidates=@($rkA,$rkB,$rkC,$rkD,$rkU); Catalog=$Script:ShellData.Catalog; Settings=$null }

$riA = Get-CandidateRankInfo $rkA $rkData
$riB = Get-CandidateRankInfo $rkB $rkData
$riC = Get-CandidateRankInfo $rkC $rkData
$riD = Get-CandidateRankInfo $rkD $rkData
$riU = Get-CandidateRankInfo $rkU $rkData

$rankOk = $true
if ($riA.Place -ne 1 -or $riA.Display -ne '1st of 4') { $rankOk=$false; Write-Host ("  FAIL A place={0} disp='{1}' expected 1 / '1st of 4'" -f $riA.Place,$riA.Display) -ForegroundColor Red }
if ($riB.Place -ne 2 -or $riC.Place -ne 2)            { $rankOk=$false; Write-Host ("  FAIL tie B={0} C={1} expected 2/2" -f $riB.Place,$riC.Place) -ForegroundColor Red }
if ($riD.Place -ne 4 -or $riD.Display -ne '4th of 4') { $rankOk=$false; Write-Host ("  FAIL D place={0} disp='{1}' expected 4 / '4th of 4'" -f $riD.Place,$riD.Display) -ForegroundColor Red }
if ($null -ne $riU)                                   { $rankOk=$false; Write-Host '  FAIL unrated candidate should rank $null' -ForegroundColor Red }
if ($rankOk) { Write-Host '  OK   Get-CandidateRankInfo: 1st/2nd/2nd/4th, pool 4, unrated -> null' }

# _CandRankBadge renders a Border for a ranked and an unrated candidate.
$badge1 = _CandRankBadge @{ Place=1; Pool=4; Display='1st of 4' }
$badgeU = _CandRankBadge $null
$badgeText = { param($b) (@($b.Child.Children) | Where-Object { $_ -is [System.Windows.Controls.TextBlock] } | ForEach-Object { $_.Text }) -join '' }
if ($badge1 -is [System.Windows.Controls.Border] -and (& $badgeText $badge1) -match '1st of 4' -and (& $badgeText $badgeU) -match 'Not yet rated') {
    Write-Host '  OK   _CandRankBadge renders ranked + unrated badges'
} else {
    Write-Host ("  FAIL _CandRankBadge ranked='{0}' unrated='{1}'" -f (& $badgeText $badge1), (& $badgeText $badgeU)) -ForegroundColor Red
}

Write-Host ''
Write-Host 'Smoke test complete.'
