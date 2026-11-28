# Design: Full dataset export/import (ranged backup) + demo seed

**Date:** 2026-06-01
**Branch:** `upgrades` (stacked on the UI-scale work)
**Status:** Approved (design), pending implementation plan

## Goal

Add a **multi-job ("full system") export/import** to TrueHire so the user can:

1. Back up the entire dataset, or an incremental slice (e.g. "last 30 days"), into a
   single `.truehire.zip`, and restore it in one action (idempotent merge).
2. Ship/seed a rich demo dataset (10 jobs x 3 candidates, with kits, catalog +
   custom questions, and completed evaluations) — delivered both as live
   `userdata/` and as a single importable `demo-full.truehire.zip`.

Today's import/export is **one job per zip** (`lib/Export.ps1`, schema
`truehire.jobreq-export/1`); `Read-JobReqExportBundle` rejects any bundle whose
candidates/kit don't all match a single `job.id`. This feature adds a parallel
multi-job format and reuses the existing per-job upsert logic, looped.

## Decisions (locked)

- **Range filter predicate:** *any activity in window* — a job is included if ANY of
  these timestamps falls in [From, To]: `job.createdDate`, `job.modifiedDate`, any of
  its candidates' `appliedDate`/`interviewDate`, or any rater entry's `submittedAt`.
- **Import behavior:** *smart merge / upsert by job id* — existing jobs (same id) are
  replaced from the bundle (job + kit + candidates); new jobs are added. Idempotent,
  no duplicates. Catalog is never overwritten.
- **Whole-system export is an explicit choice:** the dialog's first option is
  **"Everything (full system backup)"** — no date filter, every job. Date presets are
  the incremental options layered on top.

## Phase split

- **Phase 1 — the export/import feature** (format + ranged export UI + merge import +
  schema-aware import routing + smoke round-trip). Headless-testable.
- **Phase 2 — the demo dataset** (generate 10x3, seed `userdata/`, produce
  `data/demo-full.truehire.zip` via the Phase-1 exporter). Depends on Phase 1.

---

## Phase 1 — Full export/import

### Bundle format: `truehire.fullexport/1`

A `.truehire.zip` with five files at the archive root:

| File | Contents |
|---|---|
| `manifest.json` | schema, appVersion, exportedAt, exportedBy {name, role, machine, user}, **range** {mode, from, to}, **counts** {jobs, kits, candidates, raterEntries, submittedRaterEntries}, **ids** {jobReqIds[]} |
| `jobs.json` | array of job objects (those passing the filter) |
| `kits.json` | array of kits whose `jobReqId` is in the included jobs |
| `candidates.json` | array of candidates whose `jobReqId` is in the included jobs |
| `catalog.json` | one reference snapshot of `data/categories.json` (never re-imported) |

`range.mode` is one of `all | last30 | last90 | thisMonth | thisYear | custom`. For
`all`, `from`/`to` are empty and no filtering occurs. Schema string is deliberately
distinct from `truehire.jobreq-export/1` so the importer can tell them apart.

### New functions in `lib/Export.ps1`

```
Get-FullExportRange  -Preset            -> @{ Mode; From; To }   # resolves presets to dates
Test-JobInDateWindow -Data -Job -From -To -> [bool]             # any-activity predicate
New-FullExportBundle -Data -Mode -From -To -> bundle hashtable   # filter + assemble + manifest
Write-FullExportBundle -Bundle -Path                            # zip writer (atomic, like per-job)
Read-FullExportBundle  -Path             -> bundle + ScratchDir  # unzip + validate + parse
Import-FullExportBundle -Data -Bundle    -> summary hashtable    # upsert loop
Get-FullExportDefaultFilename -Mode      -> string               # truehire-backup-YYYYMMDD.truehire.zip
Get-BundleSchema -Path                   -> string               # peek manifest.bundleSchema without full extract
```

**Date handling.** Model timestamps are mixed formats (`createdDate`/`modifiedDate`
via `ToString('s')`; `appliedDate`/`interviewDate` `yyyy-MM-dd`; `submittedAt`
`ToString('o')`; some empty). `Test-JobInDateWindow` parses each candidate timestamp
with `[datetime]::TryParse(... InvariantCulture ...)`; unparseable/empty values simply
don't contribute. Window test is inclusive; `To` is treated as end-of-day. `Mode=all`
short-circuits to `$true`.

**Validation in `Read-FullExportBundle`** (mirrors per-job strictness): required files
present; manifest schema == `truehire.fullexport/1`; every `kit.jobReqId` and
`candidate.jobReqId` references a job id present in `jobs.json` (throw on orphan).
Caller cleans `ScratchDir` in a `finally`.

**`Import-FullExportBundle` (upsert).** For each job in the bundle:
- remove local `Jobs`/`Kits`/`Candidates` matching that job id (the per-job "Replace"
  scope), then add the bundle's job + its kit + its candidates;
- run `_MigrateCandidate` + `Sync-CandidateLegacyRatings` on each candidate (same as
  per-job import);
- tally added vs. updated.
Catalog is untouched. Returns `@{ JobsAdded; JobsUpdated; KitCount; CandidateCount;
RaterEntryCount }`. Re-importing the same bundle is a no-op in effect (idempotent).

Reuse: `Write/Read-FullExportBundle` follow the exact atomic-zip + scratch-dir pattern
of the per-job functions. The upsert reuses the per-job Replace removal/add logic,
factored so both call one helper rather than duplicating it.

### UI (`views/JobReqs.ps1`)

- **Export:** add a **"Backup / Export All…"** button to the Job Reqs list header
  (next to the existing `Import...`). It opens a new modal `Show-FullExportDialog`
  returning `@{ Mode; From; To }` or `$null` (cancel). The dialog offers radio options:
  **Everything (full system backup)**, Last 30 days, Last 90 days, This month, This
  year, and **Custom range…** with two `DatePicker`s enabled only when Custom is
  selected. Per CLAUDE.md gotcha #6, read `DatePicker.SelectedDate` only when Custom is
  active and the value is non-null. On confirm: `New-FullExportBundle` ->
  `SaveFileDialog` (default name from `Get-FullExportDefaultFilename`) ->
  `Write-FullExportBundle` -> status caption + log.
- **Import (schema-aware):** the existing `BtnImport` handler first calls
  `Get-BundleSchema` on the chosen file. If `truehire.jobreq-export/1`, the current
  per-job path runs unchanged (conflict dialog -> `Import-JobReqExportBundle`). If
  `truehire.fullexport/1`, it runs `Read-FullExportBundle` ->
  `Import-FullExportBundle` (merge; no per-item conflict prompt — merge is the defined
  behavior) -> summary caption. Unknown schema -> clear error.

### Verification (Phase 1)

Extend `test/smoke.ps1`: build a full bundle from seed data (Mode=all), write to a temp
zip, read it back, assert manifest counts match; import into a copy of the data and
assert idempotency (importing twice yields identical job/candidate counts and no id
churn). Keep the existing per-job round-trip. `Get-BundleSchema` correctly distinguishes
the two formats. All existing smoke checks stay green.

---

## Phase 2 — Demo dataset (10 jobs x 3 candidates)

### Generator: `tools/Make-DemoData.ps1`

A reproducible script that dot-sources `lib/*.ps1` (factories + Export) and assembles
"really good", domain-authentic data, then writes it out. Curated content lives in
in-script tables so it's high quality, but records are built via the real factories
(`New-JobReq`, `New-InterviewKit`, `New-Candidate`, `New-RaterEntry`) so they're always
schema-valid.

**Content target:**
- **10 jobs**, common titles drawn from `data/positions.json` (e.g. Senior
  Software Engineer, Product Manager, UX Designer, Data Analyst, Project
  Manager…), with realistic descriptions, departments, locations, hiring managers, and
  **varied statuses** spanning the app's pill set (Active / Draft / On Hold / Closed /
  Filled), plus varied `createdDate`/`modifiedDate` spread across recent months so the
  date-range export has meaningful slices to filter.
- **10 kits** (1 per job), each with several catalog categories (real probes pulled
  from `data/categories.json`) **plus 1–2 custom questions** (`source = "custom"`), so
  both question sources are represented.
- **30 candidates** (3 per job), **varied stages** across the app's stage set, each with
  one **Submitted** rater entry: anchors (1–5) across the kit's categories, short notes,
  and a `recommendation` (Select / Non-Select) — so the Candidates ring scores,
  Dashboard KPIs, and Analytics charts all populate.

(Exact valid status/stage strings will be read from the app's pill/stage definitions
during planning so they match the UI filters precisely.)

**Outputs:**
1. Writes `userdata/jobs.json`, `userdata/kits.json`, `userdata/candidates.json` — so
   launching the app immediately shows the populated demo. (Current `userdata/` is empty,
   so nothing is lost; the script backs up any existing files to `*.bak` first.)
2. Produces `data/demo-full.truehire.zip` via `New-FullExportBundle -Mode all` +
   `Write-FullExportBundle` — the single-file, one-import demo.

**Not changed by default:** the `data/sample-*.json` first-run seeds are left as-is, so
fresh installs don't auto-load demo data. (Seeding those is a one-line option if the
user later wants every new install to start populated.)

### Verification (Phase 2)

Run the generator; run `test/smoke.ps1` (loads the new `userdata/`, exercises
`Compute-Metrics`, view renders, and a full round-trip) — must be green. Launch the app
and eyeball: 10 jobs across statuses, 3 candidates each across stages, evaluations
populated, charts lit. Confirm `data/demo-full.truehire.zip` imports cleanly into an
empty app via the new Import path.

---

## Cross-cutting

- **Rebuild `TrueHire.exe`** + refresh `.tools/stage` after both phases (repo commits
  these), then commit on `upgrades`.
- **No change** to the per-job format, the catalog, scoring, or any UI-scale work.

## Scope boundaries (non-goals)

- No per-item conflict resolution UI for full import (merge is the defined behavior).
- No cloud/remote backup, scheduling, or encryption — local zip only.
- No change to the first-run `sample-*.json` seeding behavior by default.
- No new dependency; uses built-in `System.IO.Compression` / `Compress-Archive`.

## Risks

- **Mixed date formats** in the activity predicate — mitigated by tolerant
  `TryParse(InvariantCulture)` with empty/unparseable treated as non-contributing.
- **Large "Everything" bundles** embed a ~138 KB catalog snapshot once (not per job),
  so a full export is far smaller than N per-job bundles.
- **Destructive merge** (upsert replaces matching jobs): documented in the import
  summary; the user exports before importing if unsure. Restoring a backup over newer
  local edits to the same job id overwrites them — same caveat as today's per-job
  Replace, now at dataset scope.
