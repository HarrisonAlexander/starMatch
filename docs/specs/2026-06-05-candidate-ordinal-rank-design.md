# Candidate Ordinal Rank (instead of % match) — Design

**Date:** 2026-06-05
**Status:** Approved (design); pending implementation plan
**Author:** Brainstormed with Claude

## Problem

Candidate cards present the derived match score as an absolute numerical
percentage (a `93%` ring + a colored progress bar). The hiring manager doesn't
think in absolute percentages — they think in *places*: who is the strongest
candidate for this role, who is second, third. A `93` vs `94` distinction reads
as false precision and invites over-interpretation of small score gaps.

We want the in-app UI to show an **ordinal rank** ("1st of 8", "2nd of 8") in
place of the percentage, while keeping the underlying 0–100 score as the engine
that decides who ranks where.

## Decisions (locked during brainstorming)

1. **Ranking group = per job requisition.** A candidate's place is computed
   against the other candidates sharing their `jobReqId`. Each job's pool has its
   own 1st/2nd/3rd. This is stable regardless of any on-screen stage/job filter —
   filtering the list never changes a candidate's place.
2. **Display format = ordinal + pool size:** `"2nd of 8"`. The bare ordinal
   without the denominator loses the relative context.
3. **Ties = shared place (standard competition ranking).** Scores 90, 85, 85, 70
   → 1st, 2nd, 2nd, 4th. The place after a tie skips.
4. **Pool denominator = rated candidates only.** "of 8" means 8 candidates in
   that job have a Submitted score. Unrated candidates are **not** counted in the
   denominator.
5. **Unrated candidates** (no Submitted ratings, score `$null`) show
   **"Not yet rated"**, occupy no numbered place, and sort to the bottom of the
   pool.
6. **Card visual = single rank badge, medal accent for top 3.** Remove the ring
   and the progress bar. Places 1/2/3 get gold/silver/bronze; the rest neutral;
   unrated muted gray. The medal maps to the *place value*, so a tie for 2nd
   shows two silver badges and no bronze.
7. **Excel export unchanged.** It is an analytical artifact; the numeric
   `OverallMatchPct` / ranked list stay. Only the in-app UI changes.

## Architecture

`Get-CandidateScore` (lib/Helpers.ps1) is **unchanged** — it remains the 0–100
source of truth that drives both ranking and the default sort. Rank is a pure
*presentation* derived from it at render time; nothing is snapshotted onto
candidates, so editing ratings (or kit weights) instantly re-ranks the pool.

Two new pure helpers in **lib/Helpers.ps1**:

```
ConvertTo-Ordinal [int] -> string
    1 -> "1st", 2 -> "2nd", 3 -> "3rd", 4 -> "4th", 11 -> "11th",
    12 -> "12th", 13 -> "13th", 21 -> "21st", 22 -> "22nd", ...
    (English ordinal suffix rules, including the 11–13 exceptions.)

Get-CandidateRankInfo $Cand $Data -> hashtable | $null
    Returns @{ Place = <int>; Pool = <int>; Display = "<ordinal> of <Pool>" }
    or $null when the candidate has no Submitted score.

    Algorithm:
      1. Gather all candidates with the same jobReqId as $Cand.
      2. Score each via Get-CandidateScore $_ $Data; keep only rated (non-null).
      3. Pool = count of rated candidates.
      4. Sort rated desc by score. Assign place with shared-place tie rule:
         first row = place 1; each later row keeps the previous place when its
         score equals the previous score, else place = its 1-based position.
      5. Return the row matching $Cand.id; $null if $Cand isn't rated.
```

Complexity is O(N²) across a job pool (each card recomputes the pool), which is
fine at this data scale (tens of candidates per job) and mirrors the existing
per-candidate `Get-CandidateScore` call style. No caching layer is introduced.

## UI changes (views/Candidates.ps1)

### Candidate card (~lines 170–201)
- Remove the `New-MetricRing` ring and the `New-MatchScoreBar` bar.
- Render a **rank badge**: a tinted pill/border containing the `Display` text
  (`"2nd of 8"`) or `"Not yet rated"`.
- Tint by place: 1 = gold, 2 = silver, 3 = bronze, 4+ = neutral, unrated = muted
  gray. Medal is a **drawn colored badge** (consistent with the app's shape-based
  visuals — no emoji glyphs).
- The caption "Match Score" becomes **"Rank"**.

### Candidate detail dialog (~line 946)
- The "MATCH SCORE" field (`"$cScore%"` / `"--  (not yet rated)"`) becomes a
  **"RANK"** field showing `Get-CandidateRankInfo`'s `Display`, or "Not yet
  rated".
- Reword the field's tooltip from the anchor-math explanation to describe per-job
  ranking.

### Sort
- Default sort stays `Get-CandidateScore` descending (== rank order). Relabel the
  sort dropdown item **"Match Score" → "Rank"**; behavior unchanged.

## Cleanup

`New-MetricRing` and `New-MatchScoreBar` (lib/Helpers.ps1) become unused after
this change — nothing else references them (the Dashboard "Overall Match" KPI
that once used the ring was removed in an earlier change). Both are removed as
orphaned code.

## Out of scope

- Dashboard and Analytics — already carry no per-candidate score; untouched.
- Excel export — unchanged.
- `Get-CandidateScore` and the anchor/weight scoring model — unchanged.
- Total-applicants denominator (we count rated candidates only).

## Testing (test/smoke.ps1)

- **`ConvertTo-Ordinal`:** 1→1st, 2→2nd, 3→3rd, 4→4th, 11→11th, 12→12th,
  13→13th, 21→21st, 22→22nd, 23→23rd.
- **`Get-CandidateRankInfo`:** in-memory job with candidate scores 90/85/85/70
  plus one unrated → places 1st/2nd/2nd/4th, `Pool = 4`, displays "1st of 4" …
  "4th of 4"; the unrated candidate returns `$null`.
- Existing Candidates view render assertion still passes (badge path renders).

## Mechanics

Edit `lib/Helpers.ps1`, `views/Candidates.ps1`, `test/smoke.ps1`; mirror to
`.tools/stage/`; run `test/smoke.ps1`; rebuild `TrueHire.exe` (with the
`TrueHire.zip`/`demo`/`outputs` excludes).
