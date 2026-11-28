# Category Weights for Interview Kits — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let kit authors weight each category so a candidate's match score and ranking reflect what matters most for that job.

**Architecture:** Each kit category gains a relative `weight` (default 1). `Get-CandidateScore` resolves the candidate's kit via `jobReqId → Get-KitForJob` and computes a weighted mean of per-category scores, renormalized across only the rated categories. Weights are authored in a new panel in the kit editor showing a live effective-% readout. With all weights equal (the post-migration default), the score is identical to today.

**Tech Stack:** PowerShell 5.1, WPF (no MVVM/binding), JSON persistence. Headless gate: `test/smoke.ps1`.

---

## Spec

Design spec: `docs/superpowers/specs/2026-06-04-category-weights-design.md`

## Key conventions (from CLAUDE.md — read before coding)

- **No `Set-StrictMode`.** Probe/extend object shapes with `_HasProp` / `_SetProp`; absent properties read as `$null`.
- **WPF handlers in non-modal views:** use `param($sender, $eventArgs)` and read per-row context off `$sender.Tag`. Do **NOT** use `.GetNewClosure()` on handlers that write data or call script-scope helpers (e.g. `Save-Kits`) — the helper resolves to `$null` at fire time.
- **Anchors are 0..5, array-index = stored value.** Score mapping is `anchor * 20` for anchor in 1..5; `0` (insufficient) and `-1` (unrated) are excluded as missing data.
- **`$Script:ShellData`** is reachable throughout `views/InterviewKits.ps1` and `views/Candidates.ps1` (it is read at `InterviewKits.ps1:1110/1274/1287` and `Candidates.ps1:343`).
- Run `powershell -NoProfile -ExecutionPolicy Bypass -File .\test\smoke.ps1` after every change.

## File map

- `lib/Data.ps1` — `_AppendToKitCategory` lives in `views/InterviewKits.ps1`, but the category **migration backfill** is in `_MigrateKit` here. Modify `_MigrateKit`.
- `views/InterviewKits.ps1` — default `weight` at category creation (`_AppendToKitCategory`); new `_BuildCategoryWeightsPanel` + `_RecomputeWeightPercents` helpers; insert the panel in `Show-InterviewKitsView`.
- `lib/Helpers.ps1` — rewrite `Get-CandidateScore` to be weight-aware (optional `-Data`); pass `$Data` from `Compute-Metrics`.
- `views/Candidates.ps1` — pass data into the 4 `Get-CandidateScore` calls.
- `lib/ReportExcel.ps1` — pass `$Data` into the 4 `Get-CandidateScore` calls.
- `tools/seed-demo-data.ps1` — pass a `@{ Kits = $kits }` shim into the summary call (display-only).
- `test/smoke.ps1` — new weighted-scoring assertion block + migration-backfill assertion.
- `CLAUDE.md` — document the new invariant and add a Recent-changes bullet.

---

## Task 1: Category `weight` field — creation default + migration backfill

**Files:**
- Modify: `views/InterviewKits.ps1` (`_AppendToKitCategory`, ~line 1120)
- Modify: `lib/Data.ps1` (`_MigrateKit` category loop, ~line 293-305)
- Test: `test/smoke.ps1` (new assertion near the existing `_MigrateKit` check, ~line 48)

- [ ] **Step 1: Write the failing migration assertion**

In `test/smoke.ps1`, immediately after the existing block that prints `OK   _MigrateKit produced canonical shape for every kit-question` (after line 48), add:

```powershell
# Assert: _MigrateKit backfills weight=1 on a category that lacks it.
$wtKit = New-InterviewKit -JobReqId 'req-wtmig'
$wtKit.categories = @([pscustomobject]@{ id = 'tech'; name = 'Tech'; description = 'x'; questions = @() })
_MigrateKit $wtKit $Script:ShellData.Catalog | Out-Null
if ($wtKit.categories[0].PSObject.Properties['weight'] -and [double]$wtKit.categories[0].weight -eq 1) {
    Write-Host 'OK   _MigrateKit backfilled category weight=1'
} else {
    Write-Host 'FAIL _MigrateKit did not backfill category weight' -ForegroundColor Red
}
```

- [ ] **Step 2: Run smoke to verify it fails**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File .\test\smoke.ps1`
Expected: a red `FAIL _MigrateKit did not backfill category weight` line (the property doesn't exist yet).

- [ ] **Step 3: Backfill weight in `_MigrateKit`**

In `lib/Data.ps1`, inside `_MigrateKit`'s `foreach ($cat in @($Kit.categories))` loop, right after the description-backfill block (after the `if (-not $cat.description ...)` block, before the `# Question-level` comment ~line 306), add:

```powershell
        # Category-level: backfill relative weight (default 1 = equal weighting).
        # Score-preserving: with every category at 1 the weighted mean equals
        # the old flat mean. See docs/.../category-weights-design.md.
        if (-not (_HasProp $cat 'weight') -or $null -eq $cat.weight) {
            _SetProp $cat 'weight' 1
        }
```

- [ ] **Step 4: Default weight at category creation**

In `views/InterviewKits.ps1`, in `_AppendToKitCategory`, extend the new-bucket literal (the `$bucket = [pscustomobject]@{ ... }` at ~line 1120) to include `weight`:

```powershell
        $bucket = [pscustomobject]@{
            id          = $CatId
            name        = $bucketName
            description = $bucketDesc
            custom      = [bool]$Custom
            weight      = 1
            questions   = @()
        }
```

- [ ] **Step 5: Run smoke to verify it passes**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File .\test\smoke.ps1`
Expected: `OK   _MigrateKit backfilled category weight=1`, and no new FAIL lines.

- [ ] **Step 6: Commit**

```bash
git add lib/Data.ps1 views/InterviewKits.ps1 test/smoke.ps1
git commit -m "feat(kits): add category weight field with migration backfill"
```

---

## Task 2: Weight-aware `Get-CandidateScore`

**Files:**
- Modify: `lib/Helpers.ps1` (`Get-CandidateScore`, lines 386-435)
- Test: `test/smoke.ps1` (new block before the `Smoke test complete.` line, ~line 316)

- [ ] **Step 1: Write the failing weighted-scoring assertions**

In `test/smoke.ps1`, just before the final `Write-Host ''` / `Write-Host 'Smoke test complete.'` (line 316), add:

```powershell
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
```

- [ ] **Step 2: Run smoke to verify it fails**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File .\test\smoke.ps1`
Expected: failures — `Get-CandidateScore $cBoth $wtData` either errors with "A positional parameter cannot be found that accepts argument" (the `$Data` param doesn't exist yet) or returns 70, so `FAIL weighted=70 expected 88` and `FAIL renormalized=... ` / `FAIL absent-category=...` appear.

- [ ] **Step 3: Rewrite `Get-CandidateScore` to be weight-aware**

In `lib/Helpers.ps1`, replace the entire `Get-CandidateScore` function (lines 386-435) with:

```powershell
function Get-CandidateScore {
    <#
    Computed match score from the candidate's Submitted rater anchors.

    Anchors run 0..5: 5 = strongest evidence (100) .. 1 = weakest real rating
    (20). 0 (insufficient) and -1 (unrated) are missing data and excluded.

    Ratings are grouped by category, each category averaged, then combined as a
    WEIGHTED mean using the candidate's kit category weights (resolved via
    jobReqId -> Get-KitForJob when -Data is supplied). A category's weight
    defaults to 1 when it is absent from the kit or carries no weight, so the
    weighted mean renormalizes naturally across only the rated categories.

    -Data omitted (or kit not found) => every weight is 1 => the score equals
    the equal-weighted mean of per-category scores. Under the single-evaluation
    model (one rater, one cell per category) that is identical to the old flat
    cell mean — the change is score-preserving until a non-uniform weight is set.

    Returns:
        [int] 0..100  -- at least one Submitted rated category
        $null         -- no Submitted ratings yet (UI should show "--")
    #>
    param($Candidate, $Data)
    if (-not $Candidate)              { return $null }
    if (-not $Candidate.raterEntries) { return $null }

    # Group cell scores by category across all Submitted rater entries.
    $byCat = @{}
    foreach ($r in @($Candidate.raterEntries)) {
        if ($r.status -ne 'Submitted') { continue }
        if (-not $r.ratings)           { continue }
        foreach ($p in $r.ratings.PSObject.Properties) {
            $v = $p.Value
            if (-not $v) { continue }
            $anchor = $null
            if ($v.PSObject.Properties['anchor']) { $anchor = $v.anchor }
            if ($null -eq $anchor) { continue }
            $a = [int]$anchor
            if ($a -lt 1 -or $a -gt 5) { continue }   # 0 / -1 excluded as missing
            $catId = [string]$p.Name
            if (-not $byCat.ContainsKey($catId)) { $byCat[$catId] = @() }
            $byCat[$catId] += ($a * 20)
        }
    }
    if ($byCat.Keys.Count -eq 0) { return $null }

    # Mean score per category.
    $catScore = @{}
    foreach ($cid in @($byCat.Keys)) {
        $catScore[$cid] = ($byCat[$cid] | Measure-Object -Average).Average
    }

    # Category weights from the candidate's kit (default 1 each).
    $weights = @{}
    if ($Data) {
        $kit = Get-KitForJob $Data $Candidate.jobReqId
        if ($kit -and $kit.categories) {
            foreach ($cat in @($kit.categories)) {
                $wv = 1.0
                if ($cat.PSObject.Properties['weight'] -and $null -ne $cat.weight) {
                    $wv = [double]$cat.weight
                    if ($wv -lt 0) { $wv = 0 }
                }
                $weights[[string]$cat.id] = $wv
            }
        }
    }

    # Weighted mean over rated categories; missing weight => 1.
    $wsum = 0.0; $acc = 0.0
    foreach ($cid in @($catScore.Keys)) {
        $w = if ($weights.ContainsKey($cid)) { $weights[$cid] } else { 1.0 }
        $acc  += $w * $catScore[$cid]
        $wsum += $w
    }
    if ($wsum -le 0) {
        # Every rated category weighted 0 -> avoid divide-by-zero; fall back to
        # an equal-weighted mean so the score never vanishes.
        return [int][Math]::Round( (@($catScore.Values) | Measure-Object -Average).Average )
    }
    return [int][Math]::Round( $acc / $wsum )
}
```

- [ ] **Step 4: Pass `$Data` from `Compute-Metrics`**

In `lib/Helpers.ps1`, in `Compute-Metrics`, change the score loop (line ~466) from `$s = Get-CandidateScore $c` to:

```powershell
        $s = Get-CandidateScore $c $Data
```

- [ ] **Step 5: Run smoke to verify it passes**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File .\test\smoke.ps1`
Expected, under `Weighted category scoring:`:
```
  OK   unweighted mean = 70
  OK   weighted (4,1) = 88
  OK   all-equal weights match unweighted score
  OK   unrated heavy category renormalizes (= 40)
  OK   category absent from kit defaults to weight 1 (= 68)
```
And the existing `Metrics: ... Match=NN%` line still prints without error.

- [ ] **Step 6: Commit**

```bash
git add lib/Helpers.ps1 test/smoke.ps1
git commit -m "feat(scoring): weight Get-CandidateScore by kit category weights"
```

---

## Task 3: Thread `$Data` into the remaining score call sites

These callers must pass data so the displayed/exported score is the weighted one. All are score-preserving today (weights all 1).

**Files:**
- Modify: `views/Candidates.ps1` (lines 179, 365, 945, 1161)
- Modify: `lib/ReportExcel.ps1` (lines 201, 243, 327, 373)
- Modify: `tools/seed-demo-data.ps1` (line 668)

- [ ] **Step 1: Candidates view**

In `views/Candidates.ps1` make these exact replacements:

- Line 179: `$candScore = Get-CandidateScore $Cand` → `$candScore = Get-CandidateScore $Cand $Script:ShellData`
- Line 365: `@($list | Sort-Object { Get-CandidateScore $_ } -Descending)` → `@($list | Sort-Object { Get-CandidateScore $_ $data } -Descending)`
  (`$data = $Script:ShellData` is already in scope at line 343 of `_RefilterCandidateGrid`.)
- Line 945: `$cScore = Get-CandidateScore $c` → `$cScore = Get-CandidateScore $c $Script:ShellData`
- Line 1161: `$derived = Get-CandidateScore $c` → `$derived = Get-CandidateScore $c $data`
  (`$data` is local — it is used at line 1160 `Save-Candidates $data`.)

- [ ] **Step 2: ReportExcel**

In `lib/ReportExcel.ps1` (`$Data` is the function parameter, in scope at all four sites):

- Line 201: `$s = Get-CandidateScore $cc` → `$s = Get-CandidateScore $cc $Data`
- Line 243: `MatchScore = $(Get-CandidateScore $c)` → `MatchScore = $(Get-CandidateScore $c $Data)`
- Line 327: `$s = Get-CandidateScore $cc` → `$s = Get-CandidateScore $cc $Data`
- Line 373: `$s = Get-CandidateScore $_` → `$s = Get-CandidateScore $_ $Data`

- [ ] **Step 3: Seed demo summary (display-only)**

In `tools/seed-demo-data.ps1` line 668, change `$s = Get-CandidateScore $_` to:

```powershell
        $s = Get-CandidateScore $_ @{ Kits = $kits }
```

(`Get-KitForJob` only reads `.Kits`; this shim is enough for the printed summary.)

- [ ] **Step 4: Run smoke to verify nothing regressed**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File .\test\smoke.ps1`
Expected: `OK   Candidates renders (...)`, `OK   InterviewKits renders (...)`, the weighted block still all-OK, and no new FAIL lines.

- [ ] **Step 5: Commit**

```bash
git add views/Candidates.ps1 lib/ReportExcel.ps1 tools/seed-demo-data.ps1
git commit -m "feat(scoring): pass kit data into all Get-CandidateScore consumers"
```

---

## Task 4: Category-weights panel in the kit editor

Adds a panel at the top of the kit editor's questions area listing each category with an editable relative-weight box and a live effective-% readout. Editing writes the weight, recomputes percentages, and persists.

**Files:**
- Modify: `views/InterviewKits.ps1` (add two helpers near `_AppendToKitCategory`; insert panel in `Show-InterviewKitsView` ~line 1233-1237)
- Test: `test/smoke.ps1` (panel-build assertion appended to the weighted-scoring block)

- [ ] **Step 1: Write the failing panel-build assertion**

In `test/smoke.ps1`, at the end of the `Weighted category scoring:` block added in Task 2, append:

```powershell
# Category-weights panel builds with one row per category and live percents.
$panel = _BuildCategoryWeightsPanel $wtKit
if ($panel -is [System.Windows.FrameworkElement]) {
    Write-Host '  OK   _BuildCategoryWeightsPanel returns a FrameworkElement'
} else {
    Write-Host '  FAIL _BuildCategoryWeightsPanel did not return a control' -ForegroundColor Red
}
```

- [ ] **Step 2: Run smoke to verify it fails**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File .\test\smoke.ps1`
Expected: an error / `FAIL` because `_BuildCategoryWeightsPanel` is not defined (`The term '_BuildCategoryWeightsPanel' is not recognized`).

- [ ] **Step 3: Add the recompute helper**

In `views/InterviewKits.ps1`, immediately above `function _AppendToKitCategory {` (line ~1101), add:

```powershell
function _RecomputeWeightPercents {
    <#
    Updates each row's effective-% label = weight / sum(weights). Reads the
    live weight off each row's category object. $Rows is an array of
    @{ Cat; Box; Pct } hashtables.
    #>
    param($Rows)
    $sum = 0.0
    foreach ($r in $Rows) { $sum += [double]$r.Cat.weight }
    foreach ($r in $Rows) {
        $pct = if ($sum -gt 0) { 100.0 * [double]$r.Cat.weight / $sum } else { 0 }
        $r.Pct.Text = ("{0:0}%" -f $pct)
    }
}

function _BuildCategoryWeightsPanel {
    <#
    Returns a panel listing each kit category with a relative-weight TextBox and
    a live effective-% readout. Editing a box (on LostFocus) writes the weight
    back onto the category object, recomputes all percentages, and persists via
    Save-Kits. Built for a NON-modal view: handlers use param($sender,...) and
    read shared state off $sender.Tag - NO GetNewClosure (see CLAUDE.md gotcha 2).
    #>
    param($Kit)

    $card = New-Object System.Windows.Controls.Border
    $card.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#F7F9FC')))
    $card.CornerRadius = '8'
    $card.Padding = '14'
    $card.Margin = '0,0,0,14'

    $outer = New-Object System.Windows.Controls.StackPanel

    $hdr = New-Object System.Windows.Controls.TextBlock
    $hdr.Text = 'Category weights'
    $hdr.FontSize = 13
    $hdr.FontWeight = 'SemiBold'
    $hdr.Margin = '0,0,0,2'
    $hdr.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#0B2C45')))
    [void]$outer.Children.Add($hdr)

    $sub = New-Object System.Windows.Controls.TextBlock
    $sub.Text = 'Relative importance per category. Effective % is shown live and always totals 100%.'
    $sub.FontSize = 11
    $sub.TextWrapping = 'Wrap'
    $sub.Margin = '0,0,0,10'
    $sub.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#6B7B8C')))
    [void]$outer.Children.Add($sub)

    $rows = New-Object System.Collections.ArrayList   # @{ Cat; Box; Pct }
    $shared = @{ Rows = $rows }

    foreach ($cat in @($Kit.categories)) {
        if (-not (_HasProp $cat 'weight') -or $null -eq $cat.weight) { _SetProp $cat 'weight' 1 }

        $row = New-Object System.Windows.Controls.Grid
        $row.Margin = '0,0,0,6'
        foreach ($wd in '*', 70, 60) {
            $cd = New-Object System.Windows.Controls.ColumnDefinition
            $cd.Width = if ($wd -is [string]) { '*' } else { [System.Windows.GridLength]::new($wd) }
            [void]$row.ColumnDefinitions.Add($cd)
        }

        $nm = New-Object System.Windows.Controls.TextBlock
        $nm.Text = (Get-CategoryLabel $cat $Script:ShellData.Catalog)
        $nm.FontSize = 12.5
        $nm.VerticalAlignment = 'Center'
        $nm.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#2C3E50')))
        [System.Windows.Controls.Grid]::SetColumn($nm, 0)
        [void]$row.Children.Add($nm)

        $box = New-Object System.Windows.Controls.TextBox
        $box.Width = 56
        $box.HorizontalAlignment = 'Left'
        $box.VerticalContentAlignment = 'Center'
        $box.Text = [string]$cat.weight
        [System.Windows.Controls.Grid]::SetColumn($box, 1)
        [void]$row.Children.Add($box)

        $pct = New-Object System.Windows.Controls.TextBlock
        $pct.FontSize = 12.5
        $pct.FontWeight = 'SemiBold'
        $pct.HorizontalAlignment = 'Right'
        $pct.VerticalAlignment = 'Center'
        $pct.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#1565C0')))
        [System.Windows.Controls.Grid]::SetColumn($pct, 2)
        [void]$row.Children.Add($pct)

        $rowState = @{ Cat = $cat; Box = $box; Pct = $pct }
        [void]$rows.Add($rowState)

        $box.Tag = $shared
        $box.Add_LostFocus({
            param($sender, $eventArgs)
            $sh = $sender.Tag
            $me = $null
            foreach ($r in $sh.Rows) { if ($r.Box -eq $sender) { $me = $r; break } }
            if (-not $me) { return }
            $val = 0.0
            if ([double]::TryParse($sender.Text, [ref]$val) -and $val -ge 0) {
                _SetProp $me.Cat 'weight' $val
                $sender.Text = [string]$val   # canonicalize (e.g. "2." -> "2")
            } else {
                $sender.Text = [string]$me.Cat.weight   # revert invalid input
            }
            _RecomputeWeightPercents $sh.Rows
            Save-Kits $Script:ShellData
        })

        [void]$outer.Children.Add($row)
    }

    _RecomputeWeightPercents $rows
    $card.Child = $outer
    return $card
}
```

- [ ] **Step 4: Insert the panel into the kit editor**

In `views/InterviewKits.ps1`, in `Show-InterviewKitsView`, inside the `else` branch that renders categories with questions (the block starting `# Count total rows first...` ~line 1234), add the panel as the **first** child of `$qPanel`, immediately before the `$total = 0` line:

```powershell
            # Category weights editor (one row per category, live effective %).
            [void]$qPanel.Children.Add( (_BuildCategoryWeightsPanel $kit) )
            # Count total rows first so each row knows whether up/down are enabled.
            $total = 0
```

- [ ] **Step 5: Run smoke to verify it passes**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File .\test\smoke.ps1`
Expected: `  OK   _BuildCategoryWeightsPanel returns a FrameworkElement`, `OK   InterviewKits renders (...)` (now includes the weights panel), and no FAIL lines.

- [ ] **Step 6: Manual visual check**

Run: `powershell -ExecutionPolicy Bypass -File .\TrueHire.ps1`
Open the **Interview Kits** tab, select a kit with categories. Confirm:
- A "Category weights" card appears above the question list, one row per category.
- Each row shows the category name, a weight box (default `1`), and an effective % on the right; the percentages total 100%.
- Change a weight (e.g. set one category to `4`), click elsewhere (blur): the percentages rebalance immediately and persist (reopen the tab — the value is retained).

- [ ] **Step 7: Commit**

```bash
git add views/InterviewKits.ps1 test/smoke.ps1
git commit -m "feat(kits): category-weights editor with live effective-% readout"
```

---

## Task 5: Documentation

**Files:**
- Modify: `CLAUDE.md` (data-model invariants + Recent changes)

- [ ] **Step 1: Add a data-model invariant subsection**

In `CLAUDE.md`, under `## Data model invariants`, after the `### Anchor scale is V4 0..5` section, add:

```markdown
### Category weights (per-kit)
Each kit category carries a relative `weight` (number, default `1`). The
candidate match score is a **weighted mean** of per-category scores:
`Get-CandidateScore` resolves the candidate's kit via `jobReqId → Get-KitForJob`
(passed in as `-Data`) and computes `Σ(weight × catScore) / Σ(weight)` over the
**rated** categories only — a missing/insufficient category drops out and its
weight leaves the denominator (renormalization). A category absent from the kit,
or lacking a `weight`, defaults to `1`, so nothing is ever silently dropped.

`weight` is backfilled to `1` by `_MigrateKit` (score-preserving — with every
weight equal the weighted mean equals the old flat mean under the
single-evaluation model). Weights are authored in the kit editor's "Category
weights" panel (`_BuildCategoryWeightsPanel`). When `Get-CandidateScore` is
called **without** `-Data`, every weight is `1` (equal weighting).
```

- [ ] **Step 2: Add a Recent-changes bullet**

In `CLAUDE.md`, under `## Recent changes`, add as the first bullet:

```markdown
- **Category weights:** kit categories now carry a relative `weight` (default 1).
  `Get-CandidateScore` takes an optional `-Data` and computes a weighted mean of
  per-category scores, renormalized across rated categories. Authored in the kit
  editor's "Category weights" panel. Migration backfills `weight=1`
  (score-preserving). Surfaces only where the score already lives (Candidates
  list + Excel).
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: document per-kit category weights"
```

---

## Task 6: Final verification

- [ ] **Step 1: Full smoke run**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File .\test\smoke.ps1`
Expected: no red `FAIL` lines anywhere; the weighted-scoring block reports all five OK lines plus the panel-build OK; export/import round-trip still OK.

- [ ] **Step 2: Confirm clean tree**

Run: `git status`
Expected: only intended files changed; everything committed.

---

## Notes for the implementer

- **Why grouping by category changed the math:** the old `Get-CandidateScore` pooled every `(rater × category)` cell into one flat mean. The new form averages within a category first, then weights. Under the single-evaluation model (one rater ⇒ one cell per category) these are arithmetically identical, so existing scores don't move. If multi-rater evaluations are ever surfaced, the grouped form is the intended semantics (one weighted slot per category).
- **Do not** add weighting to the Dashboard/Analytics KPIs — the per-candidate score scope is deliberately limited to the Candidates list + Excel (see the "Per-candidate score scope" invariant in CLAUDE.md). `Compute-Metrics` already gets `$Data`; that is only so its `OverallMatchPct`/`RankedCandidates` (consumed by Excel + smoke) stay consistent.
- **No coverage warning** is in scope — the design deliberately keeps the UI clean (plain renormalization).
- Weight `0` is allowed (excludes a category). If every rated category is weighted `0`, the score falls back to an equal-weighted mean rather than dividing by zero.
