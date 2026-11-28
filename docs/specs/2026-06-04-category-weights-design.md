# Category Weights for Interview Kits — Design

**Date:** 2026-06-04
**Status:** Approved (design); pending implementation plan
**Author:** Brainstormed with Claude

## Problem

The candidate match score is an **equal-weighted mean** across every rated
category. But categories don't matter equally for every job: when interviewing an
engineer, Technical Engineering should drive the score more than, say, Problem Solving.
Today there is no way to express that, so rankings treat a strong showing on a
minor category the same as a strong showing on the critical one.

We want to let kit authors weight categories so the overall match score — and
therefore candidate rankings — reflects what actually matters for that job.

## Decisions (locked during brainstorming)

1. **Category-level weights only.** Ratings are stored as one anchor per
   *category* (questions/probes are discussion prompts, not individually scored),
   so category weights plug directly into the existing scoring model.
   Question-level weights have nothing to attach to and are out of scope.
2. **Relative weights, auto-normalized.** Authors type any number per category;
   the app normalizes to an effective % live. No requirement to total 100.
3. **Missing ratings renormalize across rated categories.** An unrated or
   "insufficient evidence" category drops out and its weight leaves the
   denominator — the score reflects only what was actually assessed. No coverage
   warning (kept deliberately simple).

## Architecture

Weights live on the **kit** (single source of truth — they are authored "when
creating the interview kit"). `Get-CandidateScore` resolves the candidate's kit
at compute time via `jobReqId → Get-KitForJob` and computes a weighted mean.
Editing a kit's weights instantly re-ranks every candidate on that job; nothing
is snapshotted onto candidates.

Rejected alternatives:
- **Snapshot weights onto each candidate** — weights would go stale on every kit
  edit and require re-syncing.
- **Weights on the job req** — categories already live on the kit; the kit is the
  natural home and matches the author's mental model.

## Data model

Add one field to each **kit category** object in `userdata/kits.json`:

```
weight : number   # relative importance, default 1
```

- This is the **only** stored change.
- Candidate ratings, anchors, and the rater-entry shape are untouched.
- Question objects get **no** weight field.
- Weight is a relative magnitude, not a percentage. `{3, 1, 1, 1}` and
  `{0.5, 0.5, 0.5, 0.5}`-style values are all valid; only the ratios matter.

## Scoring (`Get-CandidateScore`, lib/Helpers.ps1)

Add an optional `-Kit` parameter. When `-Kit` is omitted or carries no weights,
behavior is identical to today (equal weighting).

Algorithm:

1. For each category the candidate has a **Submitted** rating on with `anchor`
   in 1..5, compute the cell score `anchor * 20` (unchanged mapping).
2. Look up that category's `weight` from the kit. **Default to `1`** when the
   category is absent from the kit or has no `weight` — no rating is ever
   silently dropped.
3. Weighted mean over **rated categories only**:
   `round( Σ(weight × score) / Σ(weight) )`.
4. Unrated / `0` (insufficient) / `-1` (unrated) categories drop out — their
   weight leaves the denominator (renormalization).
5. Return `$null` when there are no Submitted rated categories (UI shows `--`).

### Backward compatibility (score-preserving)

With all weights equal — the post-migration reality — and the single-evaluation
model (one rater ⇒ exactly one cell per category), the weighted mean reduces to
today's flat mean **exactly**. No candidate's score changes until an author sets
a non-uniform weight. This mirrors the V4 anchor migration's score-preserving
guarantee.

> **Note on grouping.** Today's flat mean pools every `(rater × category)` cell
> equally. The weighted form groups by category first (so each category
> contributes once, scaled by its weight). Under the single-evaluation model these
> are identical. If multi-rater evaluations are ever surfaced, the grouped form is
> the intended semantics (one weighted slot per category, averaging raters within
> it) — call this out to the implementer so the grouping is explicit, not
> accidental.

## Authoring UI (kit editor)

In the kit's category list (the main kit editor, **not** the "Build from Catalog"
bulk-add modal — that modal only *adds* probes):

- Each category row gains a small numeric **weight input** (default shows `1`).
- A live readout shows each category's **effective %** = `weight / Σweights`,
  always totaling 100%. No manual balancing.
- Adding/removing a category rebalances the percentages automatically.
- A category left at the default shares evenly with other defaults.

PowerShell + WPF constraints to honor (per CLAUDE.md):
- Handlers that write `$Script:` state or call script-scope helpers must use
  `param($sender, $eventArgs)` and stash per-row context on `.Tag` — **no**
  `.GetNewClosure()` (except inside a live `ShowDialog()` modal scope).
- Use `_HasProp` / `_SetProp` to read/extend the weight field; no
  `Set-StrictMode`.

## Score display scope

The weighted score surfaces exactly where the per-candidate score lives today,
per the existing "per-candidate score scope" invariant:

- **Candidates list** — ring/bar + default sort.
- **Excel export** (`lib/ReportExcel.ps1`).

No new KPI. **No** Dashboard or Analytics changes. `Compute-Metrics` resolves
each candidate's kit when rolling up `OverallMatchPct` / `RankedCandidates`
(those stay for the Excel report and `smoke.ps1`).

### Call sites to thread `-Kit` through

- `lib/Helpers.ps1` — `Get-CandidateScore` (definition) and `Compute-Metrics`.
- `views/Candidates.ps1` — list ring/bar + sort.
- `lib/ReportExcel.ps1` — Excel export.
- `tools/seed-demo-data.ps1` — seed/demo usage.

Each caller already has `$Data` (or can resolve it), so kit lookup is local.
Callers that can't resolve a kit pass nothing and get today's equal-weight score.

## Migration & back-compat

`_MigrateKit` (lib/Data.ps1) backfills `weight = 1` on every kit category lacking
the field — idempotent and score-preserving, following the existing
description-backfill pattern. Old kits load and score identically. The next
`Save-Kits` writes the canonical shape with `weight`.

## Testing (`test/smoke.ps1`)

Extend the headless gate to assert:

1. A kit with **unequal weights** produces the expected weighted ranking
   (e.g. a candidate strong on the 50%-weighted category outranks one strong only
   on minor categories).
2. An **all-equal** kit reproduces the pre-change (flat-mean) score exactly.
3. A candidate with an **unrated heavy category** renormalizes correctly (the
   missing weight leaves the denominator).
4. A rated category **absent from the kit** defaults to weight `1` and is still
   counted (nothing dropped).
5. Migration backfills `weight = 1` and leaves existing scores unchanged.

Run `smoke.ps1` after the change, per the standard workflow.

## Out of scope

- Per-question weights (would require splitting ratings to per-question).
- Coverage/low-evidence warnings on the candidate row.
- Any Dashboard/Analytics surfacing of the weighted score.
- Changes to the anchor scale or rater-entry shape.
