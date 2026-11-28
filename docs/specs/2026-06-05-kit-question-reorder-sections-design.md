# Spec — Kit question reorder: visible category sections

**Date:** 2026-06-05
**Area:** `views/InterviewKits.ps1` (Interview Kits tab — question list)
**Status:** Approved, ready for implementation plan

## Problem

Users report that reordering questions with the up/down arrows is "buggy and
inconsistent": a question can be moved **down once, then the Down arrow stops
working** and won't move it to the next row.

### Root cause (diagnosed — not an actual code bug)

`_MoveKitQuestion` is correct. It swaps a question with its neighbor **within its
own personality category** and persists fine. Arrows are intentionally disabled at
the first/last slot of each category (`RowIndex`/`TotalRows` drive enablement) —
reorder is within-category by design; cross-category movement is done via the
inline edit panel's category dropdown.

The problem is purely **presentation**: the list is rendered as one continuous,
globally-numbered list (`#1…#N`) with **no visible boundary between categories**.
Real kits hold mostly **2 questions per category** (some 3), spread across 6–7
categories. So:

- In a 2-question category: Down works **once**, then the arrow greys at the
  section boundary — reads as "stuck."
- In a 3-question category: Down works **twice** — reads as "inconsistent."

Both behaviors are correct; the invisible category boundaries make them look
broken.

## Decision

Keep reorder **within-category** (lowest risk; never silently re-categorizes a
question, so scoring/weights stay stable). Fix the *rendering* so the existing
behavior is self-explanatory. Confirmed design choices:

1. **Within-category reorder** stays. Cross-category movement stays where it is
   (inline edit panel's category dropdown).
2. **Per-category numbering** — numbers restart at `1` inside each section.
3. **Visible, static section headers** — non-collapsible (no expand/collapse
   state to manage).
4. Section headers show **category name + question count** (e.g.
   `Problem Solving · 2 questions`). **Not** weight — weight already lives in the
   `Category weights` panel above the list; duplicating it would be confusing.

## Changes

All in `views/InterviewKits.ps1`. **No data-model change, no migration, no scoring
change.**

### 1. Render loop (currently ~lines 1339–1350)

Today:

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

Becomes (per-category sections, per-category numbering, drop the global `$i`):

```powershell
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

Key points:
- `_QuestionRow` now receives `($qi + 1)` — the per-category position — instead of
  the global `($i + 1)`.
- `RowIndex`/`TotalRows` already passed are per-category, so **arrow enable/disable
  logic is unchanged**.

### 2. New helper `_BuildCategorySectionHeader`

A small builder returning a single `Border` styled as a subtle divider band,
consistent with the existing `#F8FAFC` card-header look:

```powershell
function _BuildCategorySectionHeader {
    param($Cat, [int]$Count)
    # Border: background #F8FAFC, bottom border #EDF0F4, padding ~16,8.
    # TextBlock: "<CategoryLabel> · <Count> question(s)"
    #   - CategoryLabel via Get-CategoryLabel $Cat $Script:ShellData.Catalog
    #   - SemiBold, ~12.5px, muted slate (#2C3E50 / #6B7B8C for the count)
    # Returns the Border.
}
```

Singular/plural the count ("1 question" / "2 questions").

### 3. `_QuestionRow` doc comment

Update the `$Order` description: it is now the **per-category** position, not the
global running number. The `#`-column header text in the grid header (Row 0 of the
card, ~lines 87–101) — if it reads "#", leave as-is; the column still shows a
number, just section-relative.

### 4. Unchanged on purpose

- `_MoveKitQuestion` — verified correct, left byte-for-byte.
- Up/Down click handlers — unchanged (`$sender.Tag = $Q.id`, call
  `_MoveKitQuestion`).
- `_BuildCategoryWeightsPanel` and the weights card above the list.
- Data layer (`Save-Kits`, `_MigrateKit`, load) — order already preserved.

## Testing / acceptance

- `test/smoke.ps1` renders the Kits view without error (it parses/renders views).
- Manual: open a kit with ≥1 category of 3 questions and several of 2.
  - Each category shows a header with the correct name + count.
  - Numbers restart at 1 in every section.
  - Down on the last question of a section is greyed; the section boundary is
    visibly right below it.
  - Down on a middle question (3-question category) moves it; order persists
    after a tab switch and after app restart (reload from disk).
- Rebuild `TrueHire.exe` (build-exe) after the change, per repo convention; update
  `.tools/stage` mirror.

## Out of scope

- Drag-and-drop reordering.
- Cross-category movement via arrows (stays in the edit panel dropdown).
- Collapsible sections.
- Any weight/scoring change.
