# Kit Question Reorder — Visible Category Sections Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render the Interview Kits question list as visible per-category sections (static header + per-category numbering restarting at 1) so the existing within-category reorder arrows are self-explanatory instead of looking buggy.

**Architecture:** Presentation-only change in one file. The reorder logic (`_MoveKitQuestion`) and arrow enable/disable (`RowIndex`/`TotalRows`) are correct and stay untouched. We add a section-header builder and change the render loop to emit a header per category and pass the per-category index as the displayed number. No data-model, migration, or scoring change.

**Tech Stack:** Windows PowerShell 5.1 + WPF (code-built controls, no XAML data binding, no MVVM). Tests run through `test\smoke.ps1` (the repo's only test harness — it loads WPF, dot-sources every lib/view, migrates seed data, and renders each view). There is no unit-test framework; "write a failing test" means adding an assertion to `smoke.ps1`.

**Reference spec:** `docs/superpowers/specs/2026-06-05-kit-question-reorder-sections-design.md`

---

## File structure

- **Modify:** `views/InterviewKits.ps1`
  - Add new function `_BuildCategorySectionHeader` (near `_QuestionRow`, before line 214).
  - Change the render loop (~lines 1339–1350) to emit one header per category and number questions per-category.
  - Update the `_QuestionRow` doc comment for the new meaning of `$Order`.
- **Modify (tests):** `test\smoke.ps1`
  - Add an assertion block that exercises `_BuildCategorySectionHeader`.

No other files change. After the code is verified, rebuild `TrueHire.exe` (build-exe skill) and refresh the `.tools/stage` mirror per repo convention — that is a manual finishing step, noted at the end, not a code task.

---

## Task 1: Failing smoke assertion for the section-header builder

**Files:**
- Test: `test\smoke.ps1` (insert after the existing weight-backfill assertion, which ends at line 58 with the closing `}` of the `else` on line 57)

- [ ] **Step 1: Add the failing assertion**

Open `test\smoke.ps1`. Find this existing block (around lines 50–58):

```powershell
$wtKit = New-InterviewKit -JobReqId 'req-wtmig'
$wtKit.categories = @([pscustomobject]@{ id = 'tech'; name = 'Tech'; description = 'x'; questions = @() })
_MigrateKit $wtKit $Script:ShellData.Catalog | Out-Null
if ($wtKit.categories[0].PSObject.Properties['weight'] -and [double]$wtKit.categories[0].weight -eq 1) {
    Write-Host 'OK   _MigrateKit backfilled category weight=1'
} else {
    Write-Host 'FAIL _MigrateKit did not backfill category weight' -ForegroundColor Red
}
```

Immediately **after** it, insert:

```powershell
# Assert: _BuildCategorySectionHeader renders a header with the category
# label + a singular/plural-correct question count. This is the visible
# section divider that makes within-category reorder self-explanatory.
$hdrCat   = [pscustomobject]@{ id = 'Problem Solving'; name = 'Problem Solving'; description = ''; questions = @() }
$hdrTwo   = _BuildCategorySectionHeader $hdrCat 2
$hdrOne   = _BuildCategorySectionHeader $hdrCat 1
$hdrTwoTx = (($hdrTwo.Child.Children | ForEach-Object { $_.Text }) -join '')
$hdrOneTx = (($hdrOne.Child.Children | ForEach-Object { $_.Text }) -join '')
if ($hdrTwoTx -match 'Problem Solving' -and $hdrTwoTx -match '2 questions' -and $hdrOneTx -match '1 question\b') {
    Write-Host 'OK   _BuildCategorySectionHeader renders label + pluralized count'
} else {
    Write-Host ("FAIL _BuildCategorySectionHeader text was '{0}' / '{1}'" -f $hdrTwoTx, $hdrOneTx) -ForegroundColor Red
}
```

- [ ] **Step 2: Run smoke to verify it fails**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\test\smoke.ps1
```

Expected: the run throws / aborts at the new block with an error like
`The term '_BuildCategorySectionHeader' is not recognized as the name of a cmdlet, function...`
(`$ErrorActionPreference = 'Stop'` makes the unknown-function call terminate the script). This is the expected failure — the function does not exist yet.

---

## Task 2: Implement `_BuildCategorySectionHeader`

**Files:**
- Modify: `views/InterviewKits.ps1` (insert a new function immediately before `function _QuestionRow {` at line 214)

- [ ] **Step 1: Add the function**

In `views/InterviewKits.ps1`, immediately **before** line 214 (`function _QuestionRow {`), insert:

```powershell
function _BuildCategorySectionHeader {
    <#
    A static (non-collapsible) section band shown above each category's
    question rows in the kit editor. Makes the within-category reorder
    boundary visible: the Down arrow greys at the last row of a section and
    the next header explains why (see _MoveKitQuestion). Shows the category
    label + a pluralized question count. Weight is intentionally NOT shown
    here - it lives in _BuildCategoryWeightsPanel above the list.
    #>
    param($Cat, [int]$Count)
    $b = New-Object System.Windows.Controls.Border
    $b.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#F1F5F9')))
    $b.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#E4E8EF')))
    $b.BorderThickness = '0,0,0,1'
    $b.Padding = '16,8'

    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'

    $name = New-Object System.Windows.Controls.TextBlock
    $name.Text = Get-CategoryLabel $Cat $Script:ShellData.Catalog
    $name.FontWeight = 'SemiBold'
    $name.FontSize = 12.5
    $name.VerticalAlignment = 'Center'
    $name.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#2C3E50')))
    [void]$row.Children.Add($name)

    $count = New-Object System.Windows.Controls.TextBlock
    $suffix = if ($Count -eq 1) { '' } else { 's' }
    $count.Text = (" `u{00B7} {0} question{1}" -f $Count, $suffix)   # middot separator
    $count.FontSize = 12.5
    $count.VerticalAlignment = 'Center'
    $count.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#6B7B8C')))
    [void]$row.Children.Add($count)

    $b.Child = $row
    return $b
}
```

> Note: `` `u{00B7} `` is the PowerShell 5.1-compatible escape for the middot (·). If the worker's editor mangles it, use a literal `·` character instead — the assertion only checks for the digits + "question(s)", not the separator.

- [ ] **Step 2: Run smoke to verify the new assertion passes**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\test\smoke.ps1
```

Expected: the line `OK   _BuildCategorySectionHeader renders label + pluralized count` appears, and the script proceeds past it (no longer aborts). The view-render section further down should still print `OK   InterviewKits renders (...)`.

- [ ] **Step 3: Commit**

```powershell
git add views/InterviewKits.ps1 test/smoke.ps1
git commit -m "feat(kits): add _BuildCategorySectionHeader for question list sections

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Wire the render loop to emit sections + per-category numbering

**Files:**
- Modify: `views/InterviewKits.ps1` (the render loop, currently lines 1339–1350)

- [ ] **Step 1: Replace the flat render loop**

In `views/InterviewKits.ps1`, find this block (lines 1339–1350):

```powershell
            $i = 0
            foreach ($cat in $kit.categories) {
                $catQs = @($cat.questions)
                for ($qi = 0; $qi -lt $catQs.Count; $qi++) {
                    $q = $catQs[$qi]
                    [void]$qPanel.Children.Add( (_QuestionRow ($i + 1) $cat $q $qi $catQs.Count) )
                    if ($Script:ExpandedQuestionId -eq $q.id) {
                        [void]$qPanel.Children.Add( (_QuestionRowExpanded $cat $q $false) )
                    }
                    $i++
                }
            }
```

Replace it with (emit a header per category; number per-category; drop the global `$i`):

```powershell
            # One visible section per category. Numbering restarts at 1 inside
            # each section so the per-category reorder (arrows grey at section
            # edges) reads correctly. RowIndex/TotalRows passed to _QuestionRow
            # are already per-category and still drive arrow enablement.
            foreach ($cat in $kit.categories) {
                $catQs = @($cat.questions)
                [void]$qPanel.Children.Add( (_BuildCategorySectionHeader $cat $catQs.Count) )
                for ($qi = 0; $qi -lt $catQs.Count; $qi++) {
                    $q = $catQs[$qi]
                    [void]$qPanel.Children.Add( (_QuestionRow ($qi + 1) $cat $q $qi $catQs.Count) )
                    if ($Script:ExpandedQuestionId -eq $q.id) {
                        [void]$qPanel.Children.Add( (_QuestionRowExpanded $cat $q $false) )
                    }
                }
            }
```

- [ ] **Step 2: Run smoke to verify the view still renders**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\test\smoke.ps1
```

Expected: `OK   InterviewKits renders (N child elements)` prints with no `FAIL`. The whole script finishes with its normal summary (no red `FAIL` lines).

- [ ] **Step 3: Manual visual verification**

Run the app:

```powershell
powershell -ExecutionPolicy Bypass -File .\TrueHire.ps1
```

Go to **Interview Kits** and select the **Product Manager Interview Kit** (it has a 3-question category — `Problem Solving` — and several 2-question categories). Verify:
- Each category shows a header band: e.g. `Problem Solving · 3 questions`, `Communication · 2 questions`.
- The number column restarts at `1` in every section.
- On a 2-question section: the Down arrow on row 2 is greyed, and the next section's header sits directly below it.
- On the 3-question `Problem Solving` section: Down on row 1 moves it to row 2 (order persists after switching tabs away and back).

Close the app.

- [ ] **Step 4: Commit**

```powershell
git add views/InterviewKits.ps1
git commit -m "feat(kits): render question list as per-category sections

Each category now shows a static header (name + count) and numbers its
questions from 1, making the within-category reorder boundary visible.
Fixes the 'move down once then stuck / inconsistent' report (the arrows
were correct; the invisible category boundaries made them look broken).

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Update the `_QuestionRow` doc comment

**Files:**
- Modify: `views/InterviewKits.ps1:219-222` (the `$Order` description inside `_QuestionRow`'s comment block)

- [ ] **Step 1: Correct the stale comment**

In `views/InterviewKits.ps1`, find these lines (219–222):

```powershell
    $Order is the global running number for the "#" column. $RowIndex/$TotalRows
    are the question's position WITHIN its category - they drive Up/Down enable
    so the arrows grey out at the first/last slot of each category (reorder is
    within-category; see _MoveKitQuestion).
```

Replace with:

```powershell
    $Order is the question's 1-based position WITHIN its category (shown in the
    "#" column; numbering restarts each section). $RowIndex/$TotalRows are the
    same per-category position/size and drive Up/Down enable so the arrows grey
    out at the first/last slot of each category (reorder is within-category; see
    _MoveKitQuestion and _BuildCategorySectionHeader).
```

- [ ] **Step 2: Run smoke to confirm nothing broke**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\test\smoke.ps1
```

Expected: no `FAIL` lines; `OK   InterviewKits renders (...)` and `OK   _BuildCategorySectionHeader ...` both present.

- [ ] **Step 3: Commit**

```powershell
git add views/InterviewKits.ps1
git commit -m "docs(kits): correct _QuestionRow \$Order comment (now per-category)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Finishing step (manual, not a code task)

After all tasks pass and the change is verified in the running app:

1. Rebuild `TrueHire.exe` via the **build-exe** skill and refresh the `.tools/stage` mirror (per the repo's commit convention in `CLAUDE.md` — the tracked `.exe` and stage tree are updated alongside source).
2. Optionally add a `CHANGELOG.md` entry under the existing Interview Kits notes.

---

## Self-review

**Spec coverage:**
- Within-category reorder unchanged → Tasks leave `_MoveKitQuestion` and arrow handlers untouched (explicit in Task 3 comment and architecture). ✓
- Per-category numbering restarting at 1 → Task 3 passes `($qi + 1)`. ✓
- Visible static section headers (name + count, no weight, non-collapsible) → Task 2 `_BuildCategorySectionHeader`. ✓
- Singular/plural count → Task 2 `$suffix` logic, asserted in Task 1. ✓
- No data-model/migration/scoring change → no lib files touched. ✓
- smoke renders cleanly → verified in Tasks 2–4. ✓
- Rebuild exe / stage mirror → finishing step. ✓

**Placeholder scan:** No TBD/TODO; every code step shows full code; commands have expected output. ✓

**Type/name consistency:** `_BuildCategorySectionHeader $Cat $Count` defined in Task 1 (test) and Task 2 (impl), called identically in Task 3. `Get-CategoryLabel $Cat $Catalog` matches `lib/Helpers.ps1:376`. `$Script:ShellData.Catalog` is available in both smoke (line 33) and the live view. Header structure (`Border.Child` = horizontal `StackPanel` of two `TextBlock`s) is what the Task 1 assertion walks (`$hdr.Child.Children`). ✓
