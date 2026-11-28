# CLAUDE.md — TrueHire developer guide

Working notes for anyone (human or AI) modifying this codebase. The user-facing
overview lives in [README.md](README.md); this file is the architecture,
invariants, and the hard-won PowerShell + WPF gotchas with reproductions.

## Run & test

```powershell
# Run from source
powershell -ExecutionPolicy Bypass -File .\TrueHire.ps1
#   or double-click TrueHire.exe / Run-TrueHire.cmd

# Headless gate — parses every view/dialog XAML, renders into a host Grid,
# runs Compute-Metrics on seed data, exercises export/import round-trip.
powershell -NoProfile -ExecutionPolicy Bypass -File .\test\smoke.ps1
```

Run `smoke.ps1` after any view or library change. There is no build step for the
scripts and no unit-test framework.

## Architecture

Four layers, dot-sourced into one PowerShell script scope. No MVVM, no data
binding, no charting library — charts are `ArcSegment` + `PathGeometry`.

```
TrueHire.ps1        entry: loads WPF, dot-sources lib + views, registers
                     exception handlers, hydrates data, Show-TrueHireShell
lib/Logging.ps1      daily log + DispatcherUnhandledException capture
lib/Theme.ps1        shared XAML ResourceDictionary; ConvertTo-Window
lib/Data.ps1         JSON I/O, model factories, migration, aggregation, lookups
lib/Helpers.ps1      WPF builders (pills, avatars, charts), Get-CandidateScore,
                     Compute-Metrics
lib/HtmlOutput.ps1   printable HTML (handout, rating sheets)
lib/ReportExcel.ps1  optional ImportExcel-backed Analytics export
lib/Export.ps1       .truehire.zip export/import bundle
views/Shell.ps1      main window + Show-View tab router (clears ContentHost,
                     calls the matching Show-*View)
views/*.ps1          one $Script:XxxXaml here-string + one Show-XxxView per tab
```

Views rebuild from scratch on every tab switch — cheap, and avoids stale-state
bugs. Each tab switch routes through `Show-View 'TabXxx'`.

## Data model invariants

### Single-evaluation model
Despite the name, `candidate.raterEntries` holds **one** evaluation (the hiring
manager's). It stays an array for storage/back-compat but the UI never surfaces
more than the primary entry. `Get-OrCreatePrimaryRaterEntry` collapses any stray
extras to the first; `Get-PrimaryRaterEntry` returns it or `$null`.

### Anchor scale is V4 0..5 (5 = strongest) — the array index IS the stored value
The catalog `data/categories.json → anchors[]` array is ordered so its **0-based
index equals the stored anchor value**: element 0 = "Insufficient evidence",
element 5 = "Very strong evidence IS present". Every renderer (rating buttons,
printable-sheet columns, legends) uses the index `$i` directly (0..5), never `$i+1`.

| Stored `anchor` | Meaning | Score |
|---|---|---|
| -1 | not yet rated (no button selected) | excluded |
| 0 | insufficient evidence for or against skill | excluded |
| 1 | very strong evidence NOT present | 20 |
| 2 | strong evidence NOT present | 40 |
| 3 | some evidence IS present | 60 |
| 4 | strong evidence IS present | 80 |
| 5 | very strong evidence IS present | 100 |

`Get-CandidateScore` (lib/Helpers.ps1): for each **Submitted** `(rater × category)`
pair with `anchor` in 1..5, `score += anchor * 20`; mean; round. `0` (insufficient)
and `-1` (unrated) are excluded as missing data. Returns `$null` when there are no
Submitted ratings.

> **History — the V4 flip.** The scale was inverted from the old 1-based form
> (1 = strongest → 100, 6 = insufficient, 0 = unrated) to this 0..5 form
> (5 = strongest, 0 = insufficient, **-1 = unrated**). The unrated sentinel had to
> move from 0 to -1 because 0 now means "insufficient evidence" (a selectable
> button). Existing on-disk data is migrated exactly once by `_RemapAnchorToV4` /
> `_MigrateCandidate`, guarded by a per-candidate `anchorScheme = 'v4'` marker that
> `New-Candidate` stamps at creation. The remap (`old 1..5 → 6-old`, `6 → 0`,
> `0 → -1`) is **score-preserving**. Consumers that must stay consistent on the
> 0..5 scale: `_BuildRatingRow` (storage + buttons), the rater-list "avg anchor"
> display (now *higher* = stronger evidence), `Get-CandidateAggregatedRatings`,
> `HtmlOutput`'s rating table, and `ReportExcel`'s `_AvgAnchorAcrossCandidate`.
>
> An even earlier version scored 0-based (`(5 - anchor) * 20`, excluding `> 4`),
> which silently dropped the worst real rating as "insufficient" — do not
> reintroduce that.

### Category weights (per-kit)
Each kit category carries a relative `weight` (number, default `1`). The
candidate match score is a **weighted mean** of per-category scores:
`Get-CandidateScore` resolves the candidate's kit via `jobReqId → Get-KitForJob`
(passed in as the second arg, `-Data`) and computes `Σ(weight × catScore) /
Σ(weight)` over the **rated** categories only — a missing/insufficient category
drops out and its weight leaves the denominator (renormalization). A category
absent from the kit, or lacking a `weight`, defaults to `1`, so nothing is ever
silently dropped. If every rated category is weighted `0`, it falls back to an
equal-weighted mean (no divide-by-zero).

`weight` is backfilled to `1` by `_MigrateKit` (score-preserving — with every
weight equal the weighted mean equals the old flat mean under the
single-evaluation model). Weights are authored in the kit editor's "Category
weights" panel (`_BuildCategoryWeightsPanel` in views/InterviewKits.ps1). When
`Get-CandidateScore` is called **without** `-Data`, every weight is `1` (equal
weighting) — so the score is unchanged until a non-uniform weight is set.

### Legacy ratings mirror & delete persistence
`candidate.ratings` (a `{ catId: { anchor, note } }` map) is a **derived mirror**
of the Submitted anchors, kept only so the printable consolidated rating sheet can
draw its checkmark column. Two rules keep deletes from "coming back":

1. **`Sync-CandidateLegacyRatings` rebuilds the map from scratch** (resets to
   empty, then repopulates from `Get-CandidateAggregatedRatings`). It must not
   *merge* — a merge leaves stale categories behind after the evaluation is
   deleted.
2. **`_MigrateCandidate` only promotes genuinely-legacy candidates** — those that
   have no `raterEntries` property at all. A current-shape candidate whose
   evaluation was deleted has an empty `raterEntries` array (property present), so
   it is left alone, and any stale `ratings` map is cleared (self-heal).

> Reverting either rule reintroduces the bug where a deleted evaluation is rebuilt
> from the stale `ratings` map on the next load.

### Per-candidate score scope
The derived score appears **only** on the Candidates list (ring/bar + default
sort) and the Excel export. It was removed from the Dashboard and Analytics
(no "Overall Match" KPI, no avg-by-kit chart, no distribution histogram).
`Compute-Metrics` still returns `OverallMatchPct`/`RankedCandidates` because the
Excel report and `smoke.ps1` consume them — leave them in place.

## PowerShell + WPF gotchas (with reproductions)

These patterns look reasonable but bite under PowerShell 5.1 + WPF.

1. **No `Set-StrictMode -Version Latest`.** `ConvertFrom-Json` objects rely on
   absent properties reading as `$null` rather than throwing. Use `_HasProp` /
   `_SetProp` to probe/extend shapes.

2. **No `.GetNewClosure()` on WPF handlers that write `$Script:` state or call
   script-scope functions.** The closure captures a *copy* of script scope, so
   `$Script:CurrentKitId = ...` writes into the closure and is lost; and helper
   names like `Show-View` / `Save-Kits` can resolve to `$null` at fire time
   ("term not recognized" / "expression after '&' is not valid" on paste).
   *Fix:* `param($sender, $eventArgs)` (restores dynamic scope) and stash
   per-item context on the control's `.Tag`, read back as `$sender.Tag`.
   *Repro:* with `.GetNewClosure()`, clicking a non-default kit rail row silently
   no-ops; pasting into the probe editor throws a dispatcher error.

3. **Modal dialogs are the exception.** Inside a `ShowDialog()` modal, the
   building function's scope is still live on the stack, so plain (non-closure)
   handlers *can* reference its locals (e.g. `$rowState`, `$recompute` in
   `Show-KitBuilder`). Per-row identity still goes on `.Tag` to avoid loop-var
   capture.

4. **Cross-file `$Script:` state does not share**, even with dot-sourcing — each
   file has its own script scope. Cross-file communication goes through exposed
   helpers (`Set-CurrentKitForJob`, `Set-CandidateJobFilter`), not shared
   variables.

5. **Variables are case-insensitive.** `$Cat` and `$cat` are the same variable —
   a local TextBlock named `$cat` will clobber a parameter `$Cat`. Don't shadow
   parameters with short-form locals.

6. **`DatePicker.SelectedDate` is `Nullable<DateTime>`.** Only assign it when you
   have a parseable value; assigning `$null` can silently abort the save handler,
   so a stage change never reaches `Save-Candidates`. See `Show-CandidateDetail`.

7. **`Measure-Object -Property` fails on Hashtable collections**, and a candidate
   may lack `raterEntries` on older shapes. Use `foreach` + a counter.

## Build & packaging

- `build/Build-Exe.ps1` produces `dist/TrueHire.exe`: a tiny .NET WinExe
  (compiled with the framework `csc.exe` from `build/Launcher.cs`) that embeds a
  zip of the runtime tree, extracts it to `%LOCALAPPDATA%\TrueHire\<hash>\`, and
  launches `powershell.exe` against it with `TRUEHIRE_DATA_ROOT=<exeDir>\userdata`.
- Rebuild after any source change you want reflected in the `.exe`. `dist/` is
  gitignored; publish the exe as a GitHub Release asset.
- `logs/`, `outputs/`, `userdata/` and `portable.flag` are runtime state and are
  gitignored.

## Diagnostic logging

`_LogRaterSnapshot` (views/Candidates.ps1) writes every candidate's
`raterEntries` count to `logs\truehire-<date>.log` around each evaluation
**submit** and **delete**, tagged `RaterDelete`. It exists to catch any
cross-candidate effect on the rating workflow; it is low-noise (INFO, fires only
on submit/delete) and safe to remove once the workflow is trusted.

## Recent changes

- **Category weights:** kit categories now carry a relative `weight` (default 1).
  `Get-CandidateScore` takes an optional `-Data` and computes a weighted mean of
  per-category scores, renormalized across rated categories. Authored in the kit
  editor's "Category weights" panel. Migration backfills `weight=1`
  (score-preserving). Surfaces only where the score already lives (Candidates
  list + Excel).
- **Anchor scale (V4):** flipped the rating scale to **0..5 with 5 = strongest**
  (was 1 = strongest). 0 = insufficient evidence, -1 = unrated. The catalog
  `anchors[]` was reordered so index = stored value, every renderer is now 0-based,
  and `Get-CandidateScore` is `anchor * 20`. Existing data is migrated once via the
  `anchorScheme='v4'` guard; the remap is score-preserving (see the anchor section).
- **Interview Kits:** "Build from Catalog" now lets you expand a category and tick
  the exact probes to add (with select-all per category), instead of only picking
  a count of first-N probes.
- **Dashboard/Analytics:** removed the match-score KPIs/charts (Overall Match KPI,
  avg-match-by-kit chart, match-score distribution histogram). Per-candidate score
  retained on the Candidates list + Excel.
- **Scoring:** fixed the anchor→score off-by-one (now 1-based; see above).
- **Candidate dialog:** widened 900→1060 px so the footer's Delete button isn't
  clipped.
- **Delete persistence:** deleted evaluations no longer reappear on reload
  (`Sync-CandidateLegacyRatings` rebuild + `_MigrateCandidate` guard/heal).
- Added the `_LogRaterSnapshot` diagnostic logging described above.
