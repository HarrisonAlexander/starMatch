# Full Export/Import + Demo Data Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a multi-job ("full system") ranged export/import to TrueHire and use it to seed a rich 10-job × 3-candidate demo dataset (live `userdata/` + a single `data/demo-full.truehire.zip`).

**Architecture:** A new bundle schema `truehire.fullexport/1` (arrays of jobs/kits/candidates + one catalog snapshot) implemented in `lib/Export.ps1` alongside the existing per-job format, reusing its atomic-zip plumbing and per-job upsert logic. `views/JobReqs.ps1` gets a ranged-export dialog and a schema-aware Import button. A reproducible generator `tools/Make-DemoData.ps1` produces the demo via the new export API.

**Tech Stack:** Windows PowerShell 5.1 + WPF (XAML via `XamlReader`). No unit-test framework — the gate is end-to-end `test\smoke.ps1`, extended here. Spec: `docs/superpowers/specs/2026-06-01-full-export-import-and-demo-data-design.md`.

**Branch:** `upgrades` (already checked out, stacked on the UI-scale work).

---

## TDD note for this codebase

No xUnit-style runner exists ("no build step ... no unit-test framework"). The test-first loop here: each lib task ends with a **runnable sanity command** (dot-source + call, asserting output); the permanent regression test is a new **Full export/import** section appended to `test\smoke.ps1` (Task 5), plus a Phase-2 load check. Run `test\smoke.ps1` after every task that changes loaded code.

Run the smoke gate with:
```
powershell -NoProfile -ExecutionPolicy Bypass -File .\test\smoke.ps1
```

---

## File Structure

| File | Responsibility | Action |
|---|---|---|
| `lib/Export.ps1` | Add `truehire.fullexport/1` format: range resolver, activity predicate, bundle build/write/read, schema peek, upsert import. | Modify |
| `views/JobReqs.ps1` | Ranged-export dialog (`Show-FullExportDialog`) + "Backup / Export All…" button + schema-aware Import. | Modify |
| `test/smoke.ps1` | Full export/import round-trip + idempotency assertions; register new dialog XAML for parse-check. | Modify |
| `tools/Make-DemoData.ps1` | Reproducible demo generator → `userdata/*.json` + `data/demo-full.truehire.zip`. | Create |
| `TrueHire.exe`, `.tools/stage/**` | Rebuilt artifacts. | Rebuild |

---

# PHASE 1 — Full export/import feature

## Task 1: Range resolver, activity predicate, filename + schema constant

**Files:**
- Modify: `lib/Export.ps1` (add after the `$Script:BundleSchema = 'truehire.jobreq-export/1'` line near the top, and append the functions before `New-JobReqExportBundle`)

- [ ] **Step 1: Add the full-bundle schema constant**

In `lib/Export.ps1`, immediately after the line:
```powershell
$Script:BundleSchema = 'truehire.jobreq-export/1'
```
add:
```powershell
$Script:FullBundleSchema = 'truehire.fullexport/1'
```

- [ ] **Step 2: Add the range resolver, predicate, and filename helpers**

Insert these three functions in `lib/Export.ps1` immediately before `function New-JobReqExportBundle {`:

```powershell
function Get-FullExportRange {
    <#
    Resolves a preset to a concrete [datetime] window for the full-export filter.
    'all' returns $null/$null (no filtering). 'custom' uses the supplied -From/-To
    (whole days, inclusive). All other presets are relative to "now". The To bound
    is pushed to 23:59:59 of its day so same-day activity is included.
    #>
    param(
        [ValidateSet('all','last30','last90','thisMonth','thisYear','custom')][string]$Preset,
        [datetime]$From,
        [datetime]$To
    )
    $endToday = (Get-Date).Date.AddDays(1).AddSeconds(-1)
    switch ($Preset) {
        'all'       { return @{ Mode = 'all';       From = $null; To = $null } }
        'last30'    { return @{ Mode = 'last30';    From = (Get-Date).Date.AddDays(-30); To = $endToday } }
        'last90'    { return @{ Mode = 'last90';    From = (Get-Date).Date.AddDays(-90); To = $endToday } }
        'thisMonth' { $f = (Get-Date).Date.AddDays(-((Get-Date).Day - 1)); return @{ Mode = 'thisMonth'; From = $f; To = $endToday } }
        'thisYear'  { $f = (Get-Date -Month 1 -Day 1).Date;                return @{ Mode = 'thisYear';  From = $f; To = $endToday } }
        'custom'    { return @{ Mode = 'custom'; From = $From.Date; To = $To.Date.AddDays(1).AddSeconds(-1) } }
    }
}

function Test-JobInDateWindow {
    <#
    "Any activity in window" predicate. Returns $true if the job itself, or any of
    its candidates / rater entries, has a timestamp within [From, To]. $null/$null
    (the 'all' case) always returns $true. Timestamps come in mixed formats across
    the model; each is parsed with InvariantCulture TryParse and empty/unparseable
    values simply don't contribute.
    #>
    param($Data, $Job, $From, $To)
    if (-not $From -and -not $To) { return $true }

    $stamps = New-Object System.Collections.Generic.List[string]
    foreach ($f in 'createdDate','modifiedDate') {
        if ((_HasProp $Job $f) -and $Job.$f) { $stamps.Add([string]$Job.$f) }
    }
    foreach ($c in @(Get-CandidatesFor $Data $Job.id)) {
        foreach ($f in 'appliedDate','interviewDate') {
            if ((_HasProp $c $f) -and $c.$f) { $stamps.Add([string]$c.$f) }
        }
        if ($c.raterEntries) {
            foreach ($e in @($c.raterEntries)) {
                if ((_HasProp $e 'submittedAt') -and $e.submittedAt) { $stamps.Add([string]$e.submittedAt) }
            }
        }
    }

    $ci    = [System.Globalization.CultureInfo]::InvariantCulture
    $style = [System.Globalization.DateTimeStyles]::None
    foreach ($s in $stamps) {
        $dt = [datetime]::MinValue
        if ([datetime]::TryParse($s, $ci, $style, [ref]$dt)) {
            if ($dt -ge $From -and $dt -le $To) { return $true }
        }
    }
    return $false
}

function Get-FullExportDefaultFilename {
    <#
    Default SaveFileDialog name for a full bundle: truehire-backup-<tag>-YYYYMMDD.truehire.zip
    where <tag> is 'full' for the everything export or the range mode otherwise.
    #>
    param([string]$Mode = 'all')
    $tag = 'full'
    if ($Mode -and $Mode -ne 'all') { $tag = $Mode }
    $date = (Get-Date).ToString('yyyyMMdd')
    return ("truehire-backup-{0}-{1}.truehire.zip" -f $tag, $date)
}
```

- [ ] **Step 3: Sanity-check the helpers**

Run:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command ". .\lib\Logging.ps1; . .\lib\Data.ps1; . .\lib\Export.ps1; $r=Get-FullExportRange -Preset last30; '{0} {1:yyyy-MM-dd}..{2:yyyy-MM-dd}' -f $r.Mode,$r.From,$r.To; $j=New-JobReq; $j.modifiedDate=(Get-Date).ToString('s'); $d=@{Jobs=@($j);Kits=@();Candidates=@()}; 'recent in last30: ' + (Test-JobInDateWindow -Data $d -Job $j -From $r.From -To $r.To); $j.modifiedDate=(Get-Date).AddDays(-200).ToString('s'); 'old in last30: ' + (Test-JobInDateWindow -Data $d -Job $j -From $r.From -To $r.To); Get-FullExportDefaultFilename -Mode all"
```
Expected output:
```
last30 <date>..<date>
recent in last30: True
old in last30: False
truehire-backup-full-<today>.truehire.zip
```

- [ ] **Step 4: Commit**

```powershell
git add lib/Export.ps1
git commit -m @'
feat(export): add full-export range resolver, activity predicate, schema const

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## Task 2: `New-FullExportBundle`

**Files:**
- Modify: `lib/Export.ps1` (append after `Get-FullExportDefaultFilename`)

- [ ] **Step 1: Add the bundle builder**

Insert in `lib/Export.ps1` after `Get-FullExportDefaultFilename`:

```powershell
function New-FullExportBundle {
    <#
    Filters live $Data to the jobs passing the date window (or all jobs when
    Mode='all'), gathers their kits + candidates, and returns a bundle hashtable
    with a truehire.fullexport/1 manifest. No IO. Guards a missing Settings.
    #>
    param($Data, [string]$Mode = 'all', $From = $null, $To = $null)

    $jobs   = @($Data.Jobs | Where-Object { Test-JobInDateWindow -Data $Data -Job $_ -From $From -To $To })
    $jobIds = @($jobs | ForEach-Object { $_.id })
    $kits   = @($Data.Kits       | Where-Object { $jobIds -contains $_.jobReqId })
    $cands  = @($Data.Candidates | Where-Object { $jobIds -contains $_.jobReqId })

    $raterTotal = 0; $raterSubmitted = 0
    foreach ($c in $cands) {
        if ($c.raterEntries) {
            $entries = @($c.raterEntries)
            $raterTotal     += $entries.Count
            $raterSubmitted += @($entries | Where-Object { $_.status -eq 'Submitted' }).Count
        }
    }

    $userName = ''; $userRole = ''
    if ($Data.Settings -and (_HasProp $Data.Settings 'currentUser')) {
        $cu = $Data.Settings.currentUser
        if (_HasProp $cu 'name') { $userName = [string]$cu.name }
        if (_HasProp $cu 'role') { $userRole = [string]$cu.role }
    }

    $fromStr = ''; $toStr = ''
    if ($From) { $fromStr = $From.ToString('o') }
    if ($To)   { $toStr   = $To.ToString('o') }

    $manifest = [pscustomobject]@{
        bundleSchema = $Script:FullBundleSchema
        appVersion   = 'v3'
        exportedAt   = (Get-Date).ToString('o')
        exportedBy   = [pscustomobject]@{
            name    = $userName
            role    = $userRole
            machine = "$env:COMPUTERNAME"
            user    = "$env:USERNAME"
        }
        range = [pscustomobject]@{ mode = $Mode; from = $fromStr; to = $toStr }
        counts = [pscustomobject]@{
            jobs                  = $jobs.Count
            kits                  = $kits.Count
            candidates            = $cands.Count
            raterEntries          = $raterTotal
            submittedRaterEntries = $raterSubmitted
        }
        ids = [pscustomobject]@{ jobReqIds = $jobIds }
    }

    return @{
        Manifest   = $manifest
        Jobs       = $jobs
        Kits       = $kits
        Candidates = $cands
        Catalog    = $Data.Catalog
    }
}
```

- [ ] **Step 2: Sanity-check**

Run:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command ". .\lib\Logging.ps1; . .\lib\Data.ps1; . .\lib\Export.ps1; $a=New-JobReq; $a.id='req-a'; $b=New-JobReq; $b.id='req-b'; $c=New-Candidate; $c.jobReqId='req-a'; $k=New-InterviewKit -JobReqId 'req-a'; $d=@{Jobs=@($a,$b);Kits=@($k);Candidates=@($c);Catalog=$null;Settings=$null}; $bundle=New-FullExportBundle -Data $d -Mode all; 'jobs={0} kits={1} cands={2} schema={3}' -f $bundle.Jobs.Count,$bundle.Kits.Count,$bundle.Candidates.Count,$bundle.Manifest.bundleSchema"
```
Expected:
```
jobs=2 kits=1 cands=1 schema=truehire.fullexport/1
```

- [ ] **Step 3: Commit**

```powershell
git add lib/Export.ps1
git commit -m @'
feat(export): add New-FullExportBundle (filter + manifest assembly)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## Task 3: `Write-FullExportBundle`, `Read-FullExportBundle`, `Get-BundleSchema`

**Files:**
- Modify: `lib/Export.ps1` (append after `New-FullExportBundle`)

- [ ] **Step 1: Add the writer**

Insert after `New-FullExportBundle`:

```powershell
function Write-FullExportBundle {
    <#
    Writes a full bundle to $Path as a .truehire.zip (jobs.json, kits.json,
    candidates.json, manifest.json, catalog.json). Atomic: builds in a TEMP
    scratch dir, compresses to a .tmp zip, then Move-Item -Force to $Path.
    Always cleans scratch + tmp in finally. Re-throws on failure.
    #>
    param($Bundle, [string]$Path)

    $scratch = Join-Path $env:TEMP ("TrueHire-FullExport-{0}" -f [guid]::NewGuid().ToString('N'))
    $tmpPath = Join-Path $env:TEMP ("TrueHire-FullExport-{0}.zip" -f [guid]::NewGuid().ToString('N'))
    try {
        [void](New-Item -ItemType Directory -Path $scratch -Force)
        $Bundle.Manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $scratch 'manifest.json') -Encoding UTF8
        ConvertTo-Json -InputObject @($Bundle.Jobs)       -Depth 12 | Set-Content -LiteralPath (Join-Path $scratch 'jobs.json')       -Encoding UTF8
        ConvertTo-Json -InputObject @($Bundle.Kits)       -Depth 12 | Set-Content -LiteralPath (Join-Path $scratch 'kits.json')       -Encoding UTF8
        ConvertTo-Json -InputObject @($Bundle.Candidates) -Depth 12 | Set-Content -LiteralPath (Join-Path $scratch 'candidates.json') -Encoding UTF8

        $catJson = '{}'
        if ($Bundle.Catalog) { $catJson = ($Bundle.Catalog | ConvertTo-Json -Depth 12) }
        $catJson | Set-Content -LiteralPath (Join-Path $scratch 'catalog.json') -Encoding UTF8

        if (Test-Path -LiteralPath $tmpPath) { Remove-Item -LiteralPath $tmpPath -Force }
        Compress-Archive -Path (Join-Path $scratch '*') -DestinationPath $tmpPath -CompressionLevel Optimal -Force
        Move-Item -LiteralPath $tmpPath -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $tmpPath) { Remove-Item -LiteralPath $tmpPath -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
```

- [ ] **Step 2: Add the schema peek**

Insert after `Write-FullExportBundle`:

```powershell
function Get-BundleSchema {
    <#
    Reads just manifest.json's bundleSchema from a .truehire.zip without a full
    extract, so the import handler can route per-job vs full bundles. Returns the
    schema string, or '' if the manifest/key is absent or the file is unreadable.
    #>
    param([string]$Path)
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    try {
        $full = (Resolve-Path -LiteralPath $Path).Path
        $zip  = [System.IO.Compression.ZipFile]::OpenRead($full)
        try {
            $entry = $zip.Entries | Where-Object { $_.FullName -eq 'manifest.json' } | Select-Object -First 1
            if (-not $entry) { return '' }
            $reader = New-Object System.IO.StreamReader($entry.Open())
            try { $json = $reader.ReadToEnd() } finally { $reader.Dispose() }
            $m = $json | ConvertFrom-Json
            if ($m -and ($m.PSObject.Properties.Name -contains 'bundleSchema')) { return [string]$m.bundleSchema }
            return ''
        } finally { $zip.Dispose() }
    } catch {
        return ''
    }
}
```

- [ ] **Step 3: Add the reader**

Insert after `Get-BundleSchema`:

```powershell
function Read-FullExportBundle {
    <#
    Unzips $Path, parses the five files, validates the full-export schema and that
    every kit.jobReqId / candidate.jobReqId references a job present in jobs.json.
    Returns @{ Manifest; Jobs; Kits; Candidates; Catalog; ScratchDir }. Caller MUST
    remove ScratchDir in a finally. Throws on missing files, parse/schema errors,
    or id inconsistency.
    #>
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { throw ("Bundle file not found: {0}" -f $Path) }

    $scratch = Join-Path $env:TEMP ("TrueHire-FullImport-{0}" -f [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $scratch -Force)
    try {
        Expand-Archive -LiteralPath $Path -DestinationPath $scratch -Force
    } catch {
        if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
        throw ("Could not unzip bundle: {0}" -f $_.Exception.Message)
    }

    $required = @('manifest.json','jobs.json','kits.json','candidates.json','catalog.json')
    foreach ($name in $required) {
        if (-not (Test-Path -LiteralPath (Join-Path $scratch $name))) {
            if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
            throw ("Bundle is missing required file: {0}" -f $name)
        }
    }

    $parsed = @{}
    foreach ($name in $required) {
        try {
            $parsed[$name] = Get-Content -LiteralPath (Join-Path $scratch $name) -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        } catch {
            if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
            throw ("Failed to parse {0}: {1}" -f $name, $_.Exception.Message)
        }
    }

    $manifest = $parsed['manifest.json']
    $jobs     = @($parsed['jobs.json'])
    $kits     = @($parsed['kits.json'])
    $cands    = @($parsed['candidates.json'])
    $catalog  = $parsed['catalog.json']

    if ((-not $manifest) -or (-not (_HasProp $manifest 'bundleSchema')) -or ($manifest.bundleSchema -ne $Script:FullBundleSchema)) {
        if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
        $got = ''
        if ($manifest -and (_HasProp $manifest 'bundleSchema')) { $got = [string]$manifest.bundleSchema }
        throw ("Unsupported bundle schema: '{0}'. Expected: {1}" -f $got, $Script:FullBundleSchema)
    }

    $jobIds = @($jobs | ForEach-Object { $_.id })
    $badKit = @($kits  | Where-Object { $jobIds -notcontains $_.jobReqId })
    $badCnd = @($cands | Where-Object { $jobIds -notcontains $_.jobReqId })
    if ($badKit.Count -gt 0 -or $badCnd.Count -gt 0) {
        if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
        throw ("Bundle has orphan records: {0} kit(s), {1} candidate(s) reference a job not in the bundle." -f $badKit.Count, $badCnd.Count)
    }

    return @{
        Manifest   = $manifest
        Jobs       = $jobs
        Kits       = $kits
        Candidates = $cands
        Catalog    = $catalog
        ScratchDir = $scratch
    }
}
```

- [ ] **Step 4: Sanity-check write→schema→read**

Run:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command ". .\lib\Logging.ps1; . .\lib\Data.ps1; . .\lib\Export.ps1; $a=New-JobReq; $a.id='req-a'; $c=New-Candidate; $c.jobReqId='req-a'; $d=@{Jobs=@($a);Kits=@();Candidates=@($c);Catalog=$null;Settings=$null}; $b=New-FullExportBundle -Data $d -Mode all; $p=Join-Path $env:TEMP 'fx-test.truehire.zip'; Write-FullExportBundle -Bundle $b -Path $p; 'schema=' + (Get-BundleSchema -Path $p); $r=Read-FullExportBundle -Path $p; try { 'read jobs={0} cands={1}' -f $r.Jobs.Count,$r.Candidates.Count } finally { Remove-Item $r.ScratchDir -Recurse -Force; Remove-Item $p -Force }"
```
Expected:
```
schema=truehire.fullexport/1
read jobs=1 cands=1
```

- [ ] **Step 5: Commit**

```powershell
git add lib/Export.ps1
git commit -m @'
feat(export): add Write/Read-FullExportBundle and Get-BundleSchema

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## Task 4: `Import-FullExportBundle` (smart merge / upsert)

**Files:**
- Modify: `lib/Export.ps1` (append after `Read-FullExportBundle`)

- [ ] **Step 1: Add the upsert importer**

Insert after `Read-FullExportBundle`:

```powershell
function Import-FullExportBundle {
    <#
    Merge a full bundle into live $Data by upserting each job: any local job with
    the same id (plus its kit + candidates) is removed and replaced by the bundle's
    copy; jobs not present locally are added. Idempotent - re-importing the same
    bundle yields the same dataset with no duplicates. Candidates are migrated +
    legacy-synced like the per-job import. Catalog is never overwritten. Mutates
    $Data in place; returns a summary hashtable.
    #>
    param($Data, $Bundle)
    if (-not $Data)   { throw 'Import-FullExportBundle: $Data is required' }
    if (-not $Bundle) { throw 'Import-FullExportBundle: $Bundle is required' }

    $added = 0; $updated = 0; $kitCount = 0; $candCount = 0; $raterCount = 0

    foreach ($job in @($Bundle.Jobs)) {
        $existed = [bool](Get-JobById $Data $job.id)

        # Remove any local job + its kit(s) + its candidates with this id.
        $Data.Jobs       = @($Data.Jobs       | Where-Object { $_.id       -ne $job.id })
        $Data.Kits       = @($Data.Kits       | Where-Object { $_.jobReqId -ne $job.id })
        $Data.Candidates = @($Data.Candidates | Where-Object { $_.jobReqId -ne $job.id })

        # Add the bundle's job.
        $Data.Jobs = @($Data.Jobs) + $job
        if ($existed) { $updated++ } else { $added++ }

        # Add its kit(s).
        foreach ($k in @($Bundle.Kits | Where-Object { $_.jobReqId -eq $job.id })) {
            $Data.Kits = @($Data.Kits) + $k
            $kitCount++
        }

        # Add its candidates (migrate + sync, like per-job import).
        foreach ($c in @($Bundle.Candidates | Where-Object { $_.jobReqId -eq $job.id })) {
            [void](_MigrateCandidate $c)
            Sync-CandidateLegacyRatings $c
            $Data.Candidates = @($Data.Candidates) + $c
            $candCount++
            if ($c.raterEntries) { $raterCount += @($c.raterEntries).Count }
        }
    }

    return @{
        JobsAdded       = $added
        JobsUpdated     = $updated
        KitCount        = $kitCount
        CandidateCount  = $candCount
        RaterEntryCount = $raterCount
    }
}
```

- [ ] **Step 2: Sanity-check idempotency**

Run:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command ". .\lib\Logging.ps1; . .\lib\Data.ps1; . .\lib\Export.ps1; $a=New-JobReq; $a.id='req-a'; $c=New-Candidate; $c.jobReqId='req-a'; $src=@{Jobs=@($a);Kits=@();Candidates=@($c);Catalog=$null;Settings=$null}; $b=New-FullExportBundle -Data $src -Mode all; $tgt=@{Jobs=@();Kits=@();Candidates=@()}; $s1=Import-FullExportBundle -Data $tgt -Bundle $b; $s2=Import-FullExportBundle -Data $tgt -Bundle $b; 'after2 jobs={0} added={1} updated={2}' -f @($tgt.Jobs).Count,$s2.JobsAdded,$s2.JobsUpdated"
```
Expected:
```
after2 jobs=1 added=0 updated=1
```

- [ ] **Step 3: Commit**

```powershell
git add lib/Export.ps1
git commit -m @'
feat(export): add Import-FullExportBundle (idempotent merge/upsert by job id)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## Task 5: Full export/import regression test in smoke.ps1

**Files:**
- Modify: `test/smoke.ps1` (insert before the final two lines `Write-Host ''` / `Write-Host 'Smoke test complete.'`)

- [ ] **Step 1: Append the full export/import test section**

In `test/smoke.ps1`, immediately before the final:
```powershell
Write-Host ''
Write-Host 'Smoke test complete.'
```
insert:

```powershell
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
    if ((Get-BundleSchema -Path $tmpFull) -eq 'truehire.fullexport/1') {
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
```

- [ ] **Step 2: Run smoke and verify all the new lines are OK**

Run:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\test\smoke.ps1
```
Expected: the new section prints five `OK` lines (predicate, full export, ranged export, schema detect, read-back, idempotent) and **zero** `FAIL`. Existing checks remain green. ("Smoke test complete." prints last.)

- [ ] **Step 3: Commit**

```powershell
git add test/smoke.ps1
git commit -m @'
test: full export/import round-trip + idempotency in smoke gate

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## Task 6: `Show-FullExportDialog` modal

**Files:**
- Modify: `views/JobReqs.ps1` (add a new XAML here-string + function near the other dialogs, e.g. after the `Show-ImportConflictDialog` block; and register the XAML name in `test/smoke.ps1` dialog list)

- [ ] **Step 1: Add the dialog XAML + function**

In `views/JobReqs.ps1`, after the `Show-ImportConflictDialog` function, add:

```powershell
$Script:FullExportXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Backup / Export All" Width="520" Height="470"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        Background="{StaticResource PageBg}">
  <Grid Margin="24">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <TextBlock Grid.Row="0" Style="{StaticResource H2}" Text="Backup / Export All" Margin="0,0,0,4"/>
    <TextBlock Grid.Row="1" Style="{StaticResource Caption}" Margin="0,0,0,16"
               Text="Export every job, or just the ones with activity in a date range, to a single .truehire.zip you can re-import later."/>

    <StackPanel Grid.Row="2">
      <RadioButton x:Name="RbAll" GroupName="Range" IsChecked="True" Margin="0,0,0,8"
                   Content="Everything (full system backup)" FontWeight="SemiBold"/>
      <RadioButton x:Name="RbLast30" GroupName="Range" Margin="0,0,0,8" Content="Last 30 days"/>
      <RadioButton x:Name="RbLast90" GroupName="Range" Margin="0,0,0,8" Content="Last 90 days"/>
      <RadioButton x:Name="RbMonth"  GroupName="Range" Margin="0,0,0,8" Content="This month"/>
      <RadioButton x:Name="RbYear"   GroupName="Range" Margin="0,0,0,8" Content="This year"/>
      <RadioButton x:Name="RbCustom" GroupName="Range" Margin="0,0,0,8" Content="Custom range"/>
    </StackPanel>

    <StackPanel Grid.Row="3" Orientation="Horizontal" Margin="22,4,0,0" VerticalAlignment="Top">
      <StackPanel Margin="0,0,16,0">
        <TextBlock Style="{StaticResource MicroLabel}" Text="FROM" Margin="0,0,0,4"/>
        <DatePicker x:Name="DpFrom" Width="150" IsEnabled="False"/>
      </StackPanel>
      <StackPanel>
        <TextBlock Style="{StaticResource MicroLabel}" Text="TO" Margin="0,0,0,4"/>
        <DatePicker x:Name="DpTo" Width="150" IsEnabled="False"/>
      </StackPanel>
    </StackPanel>

    <StackPanel Grid.Row="4" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
      <Button x:Name="BtnCancel" Content="Cancel" Width="100" Margin="0,0,8,0" Style="{StaticResource GhostBtn}"/>
      <Button x:Name="BtnExport" Content="Export..." Width="120" Style="{StaticResource BlueBtn}"/>
    </StackPanel>
  </Grid>
</Window>
'@

function Show-FullExportDialog {
    <#
    Modal range picker for the full export. Returns @{ Mode; From; To } resolved via
    Get-FullExportRange, or $null if cancelled. Plain (non-closure) handlers are fine
    here because the dialog is shown via ShowDialog() so this scope stays live
    (per CLAUDE.md gotcha #3). Custom requires both DatePickers (gotcha #6).
    #>
    $w = ConvertTo-Window -Xaml $Script:FullExportXaml
    $w.Owner = $Script:Shell

    $state    = @{ Range = $null }
    $rbCustom = $w.FindName('RbCustom')
    $dpFrom   = $w.FindName('DpFrom')
    $dpTo     = $w.FindName('DpTo')

    $sync = {
        $en = [bool]$rbCustom.IsChecked
        $dpFrom.IsEnabled = $en
        $dpTo.IsEnabled   = $en
    }
    foreach ($rb in 'RbAll','RbLast30','RbLast90','RbMonth','RbYear','RbCustom') {
        $w.FindName($rb).Add_Checked($sync)
    }

    $w.FindName('BtnCancel').Add_Click({ $w.DialogResult = $false })
    $w.FindName('BtnExport').Add_Click({
        $mode = 'all'
        if     ($w.FindName('RbLast30').IsChecked) { $mode = 'last30' }
        elseif ($w.FindName('RbLast90').IsChecked) { $mode = 'last90' }
        elseif ($w.FindName('RbMonth').IsChecked)  { $mode = 'thisMonth' }
        elseif ($w.FindName('RbYear').IsChecked)   { $mode = 'thisYear' }
        elseif ($rbCustom.IsChecked)               { $mode = 'custom' }

        if ($mode -eq 'custom') {
            if (-not $dpFrom.SelectedDate -or -not $dpTo.SelectedDate) {
                Set-ShellStatus -Text 'Pick both a From and To date for a custom range.' -Level WARN
                return
            }
            $state.Range = Get-FullExportRange -Preset 'custom' -From $dpFrom.SelectedDate -To $dpTo.SelectedDate
        } else {
            $state.Range = Get-FullExportRange -Preset $mode
        }
        $w.DialogResult = $true
    })

    if ($w.ShowDialog() -eq $true) { return $state.Range }
    return $null
}
```

- [ ] **Step 2: Register the dialog in the smoke parse list**

In `test/smoke.ps1`, find the `$dialogs = @(` array (the per-dialog XAML parse check) and add `'FullExportXaml'` to it. The array should now include:
```powershell
    'PickJobForKitXaml'
    'FullExportXaml'           # views\JobReqs.ps1
```
(Insert `'FullExportXaml'` as a new line inside the existing `$dialogs = @( ... )` list.)

- [ ] **Step 3: Run smoke and verify the dialog parses**

Run:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\test\smoke.ps1
```
Expected: a new line `OK   dialog FullExportXaml XAML parses`, and the full export/import section + everything else still green, zero `FAIL`.

- [ ] **Step 4: Commit**

```powershell
git add views/JobReqs.ps1 test/smoke.ps1
git commit -m @'
feat(ui): add Show-FullExportDialog range picker

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## Task 7: "Backup / Export All…" button + schema-aware Import

**Files:**
- Modify: `views/JobReqs.ps1` (left-rail XAML ~lines 30-33; the `BtnImport` handler ~lines 347-399; add a `BtnExportAll` handler in the same wiring function)

- [ ] **Step 1: Add the Export-All button to the left rail**

In `views/JobReqs.ps1`, replace the single Import button block (currently):
```powershell
      <Button x:Name="BtnImport" Grid.Row="2" Content="Import..."
              Style="{StaticResource GhostBtn}" Margin="0,0,0,12"/>
```
with a stacked pair (keeps existing row indices intact):
```powershell
      <StackPanel Grid.Row="2" Margin="0,0,0,12">
        <Button x:Name="BtnImport" Content="Import..."
                Style="{StaticResource GhostBtn}" Margin="0,0,0,8"/>
        <Button x:Name="BtnExportAll" Content="Backup / Export All..."
                Style="{StaticResource GhostBtn}"/>
      </StackPanel>
```

- [ ] **Step 2: Make the Import handler schema-aware**

In `views/JobReqs.ps1`, replace the entire `$root.FindName('BtnImport').Add_Click({ ... })` block (lines ~348-399) with this version, which routes by bundle schema:

```powershell
    # Import... button. param($sender,...) pattern - no GetNewClosure.
    # Schema-aware: routes per-job bundles to the conflict-dialog path and full
    # bundles to the merge importer.
    $root.FindName('BtnImport').Add_Click({
        param($sender, $eventArgs)
        Invoke-SafeAction -Label 'Import Bundle' -Action {
            $dlg = New-Object Microsoft.Win32.OpenFileDialog
            $dlg.Filter           = 'TrueHire bundle (*.truehire.zip)|*.truehire.zip|All files (*.*)|*.*'
            $dlg.InitialDirectory = (Get-LastExportDir)
            $dlg.Multiselect      = $false
            if ($dlg.ShowDialog($Script:Shell) -ne $true) { return }

            $schema = Get-BundleSchema -Path $dlg.FileName

            # ----- Full (multi-job) bundle: merge/upsert -----
            if ($schema -eq $Script:FullBundleSchema) {
                $bundle = $null
                try { $bundle = Read-FullExportBundle -Path $dlg.FileName }
                catch {
                    $msg = $_.Exception.Message
                    Set-ShellStatus -Text ("Import failed: {0}" -f $msg) -Level ERROR
                    Write-TrueHireLog -Level ERROR -Source 'Import' -Message $msg -Exception $_.Exception
                    return
                }
                try {
                    $summary = Import-FullExportBundle -Data $Script:ShellData -Bundle $bundle
                    Save-Jobs       $Script:ShellData
                    Save-Kits       $Script:ShellData
                    Save-Candidates $Script:ShellData
                    Set-LastExportDir (Split-Path -Parent $dlg.FileName)
                    Set-ShellStatus ("Imported backup: {0} added, {1} updated, {2} candidates" -f `
                        $summary.JobsAdded, $summary.JobsUpdated, $summary.CandidateCount)
                    Write-TrueHireLog -Level INFO -Source 'Import' -Message (
                        "Full import <- {0} added={1} updated={2} kits={3} candidates={4}" -f `
                        $dlg.FileName, $summary.JobsAdded, $summary.JobsUpdated, $summary.KitCount, $summary.CandidateCount)
                    Show-View 'TabJobReqs'
                } finally {
                    if ($bundle -and $bundle.ScratchDir -and (Test-Path -LiteralPath $bundle.ScratchDir)) {
                        Remove-Item -LiteralPath $bundle.ScratchDir -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }
                return
            }

            # ----- Per-job bundle (existing behavior) -----
            $bundle = $null
            try {
                $bundle = Read-JobReqExportBundle -Path $dlg.FileName
            } catch {
                $msg = $_.Exception.Message
                Set-ShellStatus -Text ("Import failed: {0}" -f $msg) -Level ERROR
                Write-TrueHireLog -Level ERROR -Source 'Import' -Message $msg -Exception $_.Exception
                return
            }

            try {
                $existing = Get-JobById $Script:ShellData $bundle.Job.id
                $mode = 'Replace'  # default when no conflict
                if ($existing) {
                    $mode = Show-ImportConflictDialog -Bundle $bundle
                    if (-not $mode) {
                        Set-ShellStatus "Import cancelled."
                        return
                    }
                }

                $summary = Import-JobReqExportBundle -Data $Script:ShellData -Bundle $bundle -Mode $mode
                Save-Jobs       $Script:ShellData
                Save-Kits       $Script:ShellData
                Save-Candidates $Script:ShellData
                Set-LastExportDir (Split-Path -Parent $dlg.FileName)

                $kitWord = 'no kit'
                if ($summary.KitPresent) { $kitWord = 'with kit' }
                Set-ShellStatus ("Imported {0} ({1}) - {2} candidates, {3}" -f `
                    $summary.ReqNumber, $summary.Mode, $summary.CandidateCount, $kitWord)
                Write-TrueHireLog -Level INFO -Source 'Import' -Message (
                    "Imported {0} ({1}) <- {2} mode={3} candidates={4} kitPresent={5}" -f `
                    $summary.ReqNumber, $summary.JobId, $dlg.FileName, $summary.Mode, $summary.CandidateCount, $summary.KitPresent)

                Show-View 'TabJobReqs'
            } finally {
                if ($bundle -and $bundle.ScratchDir -and (Test-Path -LiteralPath $bundle.ScratchDir)) {
                    Remove-Item -LiteralPath $bundle.ScratchDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    })
```

- [ ] **Step 3: Wire the Export-All button**

In `views/JobReqs.ps1`, immediately after the `BtnImport` handler block you just edited (still inside the same wiring function, before its closing `}`), add:

```powershell
    # Backup / Export All... button - full (multi-job) ranged export.
    $root.FindName('BtnExportAll').Add_Click({
        param($sender, $eventArgs)
        Invoke-SafeAction -Label 'Export All' -Action {
            $range = Show-FullExportDialog
            if (-not $range) { return }

            $bundle = New-FullExportBundle -Data $Script:ShellData -Mode $range.Mode -From $range.From -To $range.To
            if (@($bundle.Jobs).Count -eq 0) {
                Set-ShellStatus -Text 'No jobs matched that range - nothing to export.' -Level WARN
                return
            }

            $dlg = New-Object Microsoft.Win32.SaveFileDialog
            $dlg.FileName         = (Get-FullExportDefaultFilename $range.Mode)
            $dlg.Filter           = 'TrueHire bundle (*.truehire.zip)|*.truehire.zip|All files (*.*)|*.*'
            $dlg.InitialDirectory = (Get-LastExportDir)
            if ($dlg.ShowDialog($Script:Shell) -ne $true) { return }

            Write-FullExportBundle -Bundle $bundle -Path $dlg.FileName
            Set-LastExportDir (Split-Path -Parent $dlg.FileName)
            Set-ShellStatus ("Exported {0} job(s), {1} candidate(s) to {2}" -f `
                $bundle.Manifest.counts.jobs, $bundle.Manifest.counts.candidates, (Split-Path -Leaf $dlg.FileName))
            Write-TrueHireLog -Level INFO -Source 'Export' -Message (
                "Full export ({0}) -> {1} ({2} jobs, {3} candidates)" -f `
                $range.Mode, $dlg.FileName, $bundle.Manifest.counts.jobs, $bundle.Manifest.counts.candidates)
        }
    })
```

- [ ] **Step 4: Run smoke (parse + render must stay green)**

Run:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\test\smoke.ps1
```
Expected: `OK   JobReqs XAML parses`, `OK   JobReqs renders (...)`, the full export/import section, and the `FullExportXaml` dialog parse all green; zero `FAIL`.

- [ ] **Step 5: Commit**

```powershell
git add views/JobReqs.ps1
git commit -m @'
feat(ui): add Backup/Export All button + schema-aware Import routing

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## Task 8: Phase 1 manual UI confirmation (non-headless)

> Cannot be automated (WPF visual). Human/agent eyeball before Phase 2.

**Files:** none.

- [ ] **Step 1: Launch from source**

Run:
```powershell
powershell -ExecutionPolicy Bypass -File .\TrueHire.ps1
```

- [ ] **Step 2: Verify**

On the Job Reqs tab, confirm the left rail shows both **Import...** and **Backup / Export All...**. Click **Backup / Export All...** → the range dialog appears with "Everything (full system backup)" preselected and the From/To pickers enabled only when "Custom range" is chosen. (With no data yet it will report "No jobs matched" — that's expected; the real export is exercised in Phase 2.) Close the app. No commit.

---

# PHASE 2 — Demo dataset

## Task 9: Demo generator `tools/Make-DemoData.ps1`

**Files:**
- Create: `tools/Make-DemoData.ps1`

- [ ] **Step 1: Create the generator**

Create `tools/Make-DemoData.ps1` with exactly:

```powershell
<#
Make-DemoData.ps1 - reproducible demo seed generator.

Builds 10 generic demo jobs, one interview kit each (catalog questions pulled
live from data/categories.json, plus one custom question), and 3 candidates per
job with a completed (Submitted) evaluation. Writes jobs/kits/candidates into
userdata/ (backing up any existing files to *.bak unless -NoBackup) and produces
data/demo-full.truehire.zip via the full-export API.

Run:  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Make-DemoData.ps1
#>
[CmdletBinding()]
param([switch]$NoBackup)
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'lib\Logging.ps1')
. (Join-Path $root 'lib\Theme.ps1')
. (Join-Path $root 'lib\Data.ps1')
. (Join-Path $root 'lib\Export.ps1')

$catalog = Read-JsonFile (Join-Path $root 'data\categories.json')
if (-not $catalog -or -not $catalog.categories) { throw 'data\categories.json missing or has no categories' }
$demoCats = @($catalog.categories | Select-Object -First 6)   # competencies used by every demo kit

# --- curated content -------------------------------------------------------
$JOBS = @(
    @{ title = 'Senior Software Engineer';  dept = 'Engineering';         loc = 'Austin, TX';      status = 'Active';  mgr = 'Elena Marsh';    ageDays = 12 }
    @{ title = 'Product Manager';           dept = 'Product';             loc = 'Remote (US)';     status = 'Active';  mgr = 'Daniel Okafor';  ageDays = 20 }
    @{ title = 'UX Designer';               dept = 'Design';              loc = 'Denver, CO';      status = 'On Hold'; mgr = 'Priya Nair';     ageDays = 65 }
    @{ title = 'Data Analyst';              dept = 'Business Intelligence'; loc = 'Chicago, IL';   status = 'Active';  mgr = 'Marcus Bell';    ageDays = 8 }
    @{ title = 'Customer Success Manager';  dept = 'Customer Success';    loc = 'Atlanta, GA';     status = 'Filled';  mgr = 'Sandra Liu';     ageDays = 130 }
    @{ title = 'Project Manager';           dept = 'Operations';          loc = 'Austin, TX';      status = 'Active';  mgr = 'Tomas Reyes';    ageDays = 33 }
    @{ title = 'Financial Analyst';         dept = 'Finance';             loc = 'New York, NY';    status = 'Draft';   mgr = 'Grace Holloway'; ageDays = 3 }
    @{ title = 'Procurement Specialist';    dept = 'Procurement';         loc = 'Remote (US)';     status = 'Closed';  mgr = 'Wendell Carter'; ageDays = 210 }
    @{ title = 'HR Business Partner';       dept = 'People Operations';   loc = 'Seattle, WA';     status = 'Active';  mgr = 'Aisha Bourne';   ageDays = 45 }
    @{ title = 'Database Administrator';    dept = 'Information Technology'; loc = 'Austin, TX';   status = 'Active';  mgr = 'Victor Hahn';    ageDays = 27 }
)
# First-candidate stage per job (others are Interview / Screening) - spreads all 6 stages.
$FIRST_STAGE = @('Hired','Offer','Interview','New','Hired','Offer','New','Rejected','Interview','Screening')
$FIRST = @('James','Maria','David','Sarah','Luis','Aisha','Chen','Olivia','Mohammed','Emma','Andre','Nina','Carlos','Ruth','Kofi','Lena','Hiro','Sofia','Tariq','Bianca','Owen','Greta','Sam','Dana','Iris','Noah','Yuki','Paula','Eli','Maya')
$LAST  = @('Nguyen','Garcia','Patel','Johnson','Romero','Khan','Wei','Brooks','Ali','Santos','Dubois','Park','Mendez','Fischer','Asante','Petrov','Tanaka','Rossi','Haddad','Costa','Murphy','Lindqvist','Cohen','Walsh','Novak','Bauer','Sato','Reyes','Stein','Singh')
$NOTES = @(
    'Strong, specific example with measurable outcomes.',
    'Clear reasoning and a relevant scenario.',
    'Adequate but somewhat general response.',
    'Limited evidence; struggled to give specifics.',
    'Excellent depth and clear ownership of results.',
    'Some hesitation; only a partial example.'
)
$COLORS = @('#1E88E5','#7E57C2','#38B66E','#F5A623','#DC4C4C')

$jobs = @(); $kits = @(); $cands = @()
$nameIdx = 0

for ($i = 0; $i -lt $JOBS.Count; $i++) {
    $spec = $JOBS[$i]

    $job = New-JobReq
    $job.title          = $spec.title
    $job.position       = $spec.title
    $job.department     = $spec.dept
    $job.location       = $spec.loc
    $job.status         = $spec.status
    $job.hiringManager  = $spec.mgr
    $job.reqNumber      = ('#R{0:000}' -f (101 + $i))
    $created            = (Get-Date).AddDays(-1 * $spec.ageDays)
    $job.createdDate    = $created.ToString('s')
    $bump               = [Math]::Min(5, [int]$spec.ageDays)
    $job.modifiedDate   = $created.AddDays($bump).ToString('s')
    $job.description    = ("Seeking a {0} to join the {1} team." -f $spec.title, $spec.dept)
    $job.openings       = 1

    $kit = New-InterviewKit -JobReqId $job.id -Name ("{0} Interview Kit" -f $spec.title)
    $kit.status = 'Active'
    $kitCats = @()
    foreach ($cc in $demoCats) {
        $qs = @()
        foreach ($q in (@($cc.questions) | Select-Object -First 2)) {
            $qs += [pscustomobject]@{
                id           = ('kq-' + [guid]::NewGuid().ToString('N').Substring(0,8))
                source       = 'catalog'
                catalogIndex = [int]$q.index
                probe        = [string]$q.probe
                guide        = [string]$q.guide
            }
        }
        $kitCats += [pscustomobject]@{ id = $cc.id; description = [string]$cc.description; questions = $qs }
    }
    # One custom question, attached to the first category.
    if ($kitCats.Count -gt 0) {
        $kitCats[0].questions = @($kitCats[0].questions) + [pscustomobject]@{
            id           = ('kq-' + [guid]::NewGuid().ToString('N').Substring(0,8))
            source       = 'custom'
            catalogIndex = $null
            probe        = ("Describe a time your work directly supported {0}." -f $spec.dept)
            guide        = 'Look for concrete, role-relevant impact and ownership.'
        }
    }
    $kit.categories    = $kitCats
    $job.interviewKitId = $kit.id

    $jobs += $job
    $kits += $kit

    for ($j = 0; $j -lt 3; $j++) {
        $fn = $FIRST[$nameIdx % $FIRST.Count]
        $ln = $LAST[$nameIdx % $LAST.Count]
        $nameIdx++

        $cand = New-Candidate
        $cand.name     = ("{0} {1}" -f $fn, $ln)
        $cand.initials = ("{0}{1}" -f $fn.Substring(0,1), $ln.Substring(0,1))
        $cand.email    = ("{0}.{1}@example.com" -f $fn.ToLower(), $ln.ToLower())
        $cand.jobReqId = $job.id
        $cand.position = $spec.title
        if ($j -eq 0)    { $cand.stage = $FIRST_STAGE[$i] }
        elseif ($j -eq 1){ $cand.stage = 'Interview' }
        else             { $cand.stage = 'Screening' }
        $cand.appliedDate   = $created.AddDays(2 + $j).ToString('yyyy-MM-dd')
        $cand.interviewDate = $created.AddDays(7 + $j).ToString('yyyy-MM-dd')
        $cand.avatarColor   = $COLORS[$nameIdx % $COLORS.Count]

        # One completed evaluation. anchor 1 = strongest .. 5 = weakest.
        $entry = New-RaterEntry -RaterName $spec.mgr -RaterRole 'Hiring Manager'
        $entry.status      = 'Submitted'
        $entry.submittedAt = $created.AddDays(8 + $j).ToString('o')
        $catIdx = 0; $sum = 0; $n = 0
        foreach ($kc in $kit.categories) {
            $anchor = ((($i * 3 + $j) + $catIdx) % 5) + 1
            $note   = $NOTES[($catIdx + $j) % $NOTES.Count]
            _SetProp $entry.ratings $kc.id ([pscustomobject]@{ anchor = $anchor; note = $note })
            $sum += $anchor; $n++; $catIdx++
        }
        $avg = 6.0
        if ($n -gt 0) { $avg = $sum / $n }
        if ($avg -le 3) {
            $entry.recommendation       = 'Select'
            $entry.recommendationReason = 'DO Hire'
            $entry.recommendationText   = 'Overall strong fit based on the evaluation.'
        } else {
            $entry.recommendation       = 'Non-Select'
            $entry.recommendationReason = 'DO NOT Hire'
            $entry.recommendationText   = 'Overall limited fit based on the evaluation.'
        }
        $entry.signature = $spec.mgr
        $cand.raterEntries   = ,$entry
        $cand.recommendation = $entry.recommendation
        $cand.preparedBy     = $spec.mgr

        [void](_MigrateCandidate $cand)
        Sync-CandidateLegacyRatings $cand
        $cands += $cand
    }
}

# --- write userdata (with backup) -----------------------------------------
$ud = Join-Path $root 'userdata'
if (-not (Test-Path -LiteralPath $ud)) { New-Item -ItemType Directory -Path $ud -Force | Out-Null }
$writes = @(
    @{ file = 'jobs.json';       data = $jobs }
    @{ file = 'kits.json';       data = $kits }
    @{ file = 'candidates.json'; data = $cands }
)
foreach ($wpair in $writes) {
    $target = Join-Path $ud $wpair.file
    if (-not $NoBackup -and (Test-Path -LiteralPath $target)) {
        Copy-Item -LiteralPath $target -Destination ($target + '.bak') -Force
    }
    Write-JsonFile $target $wpair.data
}

# --- produce demo-full.truehire.zip via the full-export API ---------------
$demoData = @{ Jobs = $jobs; Kits = $kits; Candidates = $cands; Catalog = $catalog; Settings = $null }
$bundle   = New-FullExportBundle -Data $demoData -Mode 'all'
$zipPath  = Join-Path $root 'data\demo-full.truehire.zip'
Write-FullExportBundle -Bundle $bundle -Path $zipPath

Write-Host ("Demo data: {0} jobs, {1} kits, {2} candidates" -f $jobs.Count, $kits.Count, $cands.Count)
Write-Host ("Wrote: {0}\\jobs.json, kits.json, candidates.json" -f $ud)
Write-Host ("Wrote: {0}" -f $zipPath)
```

- [ ] **Step 2: Run the generator**

Run:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Make-DemoData.ps1
```
Expected output:
```
Demo data: 10 jobs, 10 kits, 30 candidates
Wrote: ...\userdata\jobs.json, kits.json, candidates.json
Wrote: ...\data\demo-full.truehire.zip
```

- [ ] **Step 3: Verify the data loads and round-trips via smoke**

Run:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\test\smoke.ps1
```
Expected: `Loaded 10 jobs, 10 kits, 30 candidates`, all view renders green, the full export/import section green, export/import round-trip green, zero `FAIL`.

- [ ] **Step 4: Verify the demo zip imports into an empty dataset**

Run:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command ". .\lib\Logging.ps1; . .\lib\Data.ps1; . .\lib\Export.ps1; 'schema=' + (Get-BundleSchema -Path .\data\demo-full.truehire.zip); $r=Read-FullExportBundle -Path .\data\demo-full.truehire.zip; try { $t=@{Jobs=@();Kits=@();Candidates=@()}; $s=Import-FullExportBundle -Data $t -Bundle $r; 'imported jobs={0} kits={1} cands={2}' -f $s.JobsAdded,$s.KitCount,$s.CandidateCount } finally { Remove-Item $r.ScratchDir -Recurse -Force }"
```
Expected:
```
schema=truehire.fullexport/1
imported jobs=10 kits=10 cands=30
```

- [ ] **Step 5: Commit**

```powershell
git add tools/Make-DemoData.ps1 userdata/jobs.json userdata/kits.json userdata/candidates.json data/demo-full.truehire.zip
git commit -m @'
feat(demo): add Make-DemoData generator; seed 10x3 demo + demo-full.truehire.zip

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## Task 10: Phase 2 manual confirmation (non-headless)

> Cannot be automated. Human/agent eyeball.

**Files:** none.

- [ ] **Step 1: Launch from source**

Run:
```powershell
powershell -ExecutionPolicy Bypass -File .\TrueHire.ps1
```

- [ ] **Step 2: Verify the demo**

Confirm: Job Reqs shows 10 jobs across statuses (Active/Draft/On Hold/Closed/Filled); Candidates shows 30 across stages with ring scores populated; opening a candidate shows a completed evaluation (anchors + notes + Select/Non-Select); Dashboard KPIs and Analytics charts are populated; an interview kit shows catalog questions plus the custom question. Then click **Backup / Export All... → Everything → Export**, save a zip, and confirm the status bar reports 10 jobs / 30 candidates. Close the app. No commit.

---

## Task 11: Rebuild the portable exe + staging mirror

**Files:**
- Rebuild: `TrueHire.exe`; Refresh: `.tools/stage/**`

- [ ] **Step 1: Rebuild via the build-exe skill**

Run the `build-exe` skill / its script:
```powershell
& "$HOME\.claude\skills\build-exe\scripts\Build-Exe.ps1" -SourceDir 'M:\VAULT-X\Projects\TrueHire\truehire.portable' -EntryScript 'TrueHire.ps1'
```
Expected: `Built: ...\TrueHire.exe` with a new bundle hash; the staged `lib/Export.ps1`, `views/JobReqs.ps1`, `tools/Make-DemoData.ps1`, and populated `userdata/` are included.

- [ ] **Step 2: Sanity-launch the rebuilt exe**

Run `.\TrueHire.exe`, confirm it opens with the demo data and the Backup/Export All button. Close it.

- [ ] **Step 3: Commit the artifacts**

```powershell
git add TrueHire.exe .tools
git commit -m @'
build: rebuild TrueHire.exe with full export/import + demo data

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
'@
```

---

## Task 12: Final regression pass

**Files:** none.

- [ ] **Step 1: Re-run the smoke gate**

Run:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\test\smoke.ps1
```
Expected: every line `OK` (loads 10/10/30, views parse + render, all dialogs parse incl. `FullExportXaml`, per-job round-trip, full export/import round-trip + idempotency). Zero `FAIL`.

- [ ] **Step 2: Confirm tree state**

Run:
```powershell
git status --short
```
Expected: no uncommitted source/artifact changes (only `logs/` untracked, and possibly `userdata/*.bak` backups created by the generator — leave or remove those at the user's discretion).

---

## Self-review notes (already applied)

- **Spec coverage:** format `truehire.fullexport/1` (Tasks 2–4) ✓; range presets incl. "Everything" + custom (Tasks 1, 6) ✓; any-activity predicate (Task 1) ✓; smart-merge upsert/idempotent (Task 4, smoke Task 5) ✓; schema-aware single Import button (Task 7) ✓; Backup/Export All button + dialog (Tasks 6–7) ✓; reuse of zip plumbing/upsert shape (Tasks 3–4) ✓; demo 10×3 with catalog+custom questions, varied status/stage, completed evals (Task 9) ✓; seed userdata + produce demo zip via the new API (Task 9) ✓; sample-*.json untouched (Task 9 writes only userdata) ✓; rebuild exe + stage (Task 11) ✓; catalog never re-imported (Task 4 leaves Data.Catalog untouched) ✓.
- **Non-goals respected:** no per-item conflict UI for full import; no scheduling/cloud/encryption; no change to first-run seeding; no new dependency (built-in `System.IO.Compression`).
- **Name/type consistency:** `$Script:FullBundleSchema`, `Get-FullExportRange`, `Test-JobInDateWindow`, `New-FullExportBundle`, `Write-FullExportBundle`, `Read-FullExportBundle`, `Get-BundleSchema`, `Import-FullExportBundle`, `Get-FullExportDefaultFilename`, `Show-FullExportDialog`, `BtnExportAll`, `FullExportXaml` used identically across lib, view, smoke, and generator. Import summary keys (`JobsAdded/JobsUpdated/KitCount/CandidateCount/RaterEntryCount`) match between Task 4 and the Task 7 status caption.
- **PS 5.1 / CLAUDE.md:** no StrictMode reliance; `Show-FullExportDialog` uses plain handlers under `ShowDialog` (gotcha #3) and guards `DatePicker.SelectedDate` (gotcha #6); kit/candidate/rater shapes match the `Data.ps1` factories and `_MigrateKit` canonical question shape.
