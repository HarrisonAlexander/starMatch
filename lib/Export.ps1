<#
Export.ps1 - Job Requisition import/export bundles.

A bundle is a .truehire.zip containing five JSON files at the archive
root: manifest.json (schema/provenance/counts/ids), job.json (one
requisition), kit.json (one interview kit, or {"present": false}),
candidates.json (array of candidates for this job, raterEntries intact),
and catalog.json (snapshot of categories.json - reference only, never
overwrites the local catalog).

Public surface:
  New-JobReqExportBundle   - build bundle hashtable from in-memory data
  Write-JobReqExportBundle - write bundle to disk atomically
  Read-JobReqExportBundle  - unzip + validate, return bundle hashtable
  Import-JobReqExportBundle - apply bundle to live data (Replace|New)
  Get-JobReqExportDefaultFilename - slug builder for SaveFileDialog
  Get-LastExportDir / Set-LastExportDir - settings-backed last-used dir
  --- Full (multi-job) export, schema truehire.fullexport/1 ---
  A full bundle is a .truehire.zip with PLURAL files: jobs.json, kits.json,
  candidates.json (arrays), manifest.json, catalog.json - distinct from the
  per-job bundle's singular job.json / kit.json.
  New-FullExportBundle / Write-FullExportBundle / Read-FullExportBundle
  Import-FullExportBundle  - merge/upsert by job id (idempotent)
  Get-FullExportRange / Test-JobInDateWindow - date-window filter
  Get-FullExportDefaultFilename - SaveFileDialog name
  Get-BundleSchema - peek manifest.bundleSchema to route per-job vs full

Depends on Data.ps1 (Get-JobById, Get-KitForJob, Get-CandidatesFor,
_HasProp, _MigrateCandidate, Sync-CandidateLegacyRatings, Save-Settings).
#>

$Script:BundleSchema = 'truehire.jobreq-export/1'
$Script:FullBundleSchema = 'truehire.fullexport/1'

function Get-JobReqExportDefaultFilename {
    <#
    Builds the default .truehire.zip filename for a SaveFileDialog.
    {reqNumber-stripped-of-non-alphanum}-{slug-title}-{YYYYMMDD}.truehire.zip
    Empty req/title fall back to "untitled".
    #>
    param($Job)
    $req = ''
    if ($Job -and $Job.reqNumber) {
        $req = ([string]$Job.reqNumber) -replace '[^A-Za-z0-9]',''
    }
    $title = ''
    if ($Job -and $Job.title) {
        $title = ([string]$Job.title) -replace '[^A-Za-z0-9]+','-'
        $title = $title.Trim('-').ToLower()
        if ($title.Length -gt 60) {
            $title = $title.Substring(0,60).TrimEnd('-')
        }
    }
    if (-not $req -and -not $title) { $req = 'untitled' }
    $date = (Get-Date).ToString('yyyyMMdd')
    $parts = @($req, $title, $date) | Where-Object { $_ }
    return (($parts -join '-') + '.truehire.zip')
}

function Get-LastExportDir {
    <#
    Returns the persisted last-used export directory, or the user's
    Documents folder if blank/missing. Pure read; never throws.
    #>
    $dir = ''
    if ($Script:ShellData -and $Script:ShellData.Settings -and (_HasProp $Script:ShellData.Settings 'lastExportDir')) {
        $dir = [string]$Script:ShellData.Settings.lastExportDir
    }
    if ([string]::IsNullOrWhiteSpace($dir)) {
        return [Environment]::GetFolderPath('MyDocuments')
    }
    return $dir
}

function Set-LastExportDir {
    <#
    Persists the last-used export directory through Save-Settings. Safe
    to call before $Script:ShellData exists (no-op in that case).
    #>
    param([string]$Path)
    if (-not $Script:ShellData -or -not $Script:ShellData.Settings) { return }
    _SetProp $Script:ShellData.Settings 'lastExportDir' ([string]$Path)
    Save-Settings $Script:ShellData
}

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
    $now      = Get-Date
    $endToday = $now.Date.AddDays(1).AddSeconds(-1)
    switch ($Preset) {
        'all'       { return @{ Mode = 'all';       From = $null; To = $null } }
        'last30'    { return @{ Mode = 'last30';    From = $now.Date.AddDays(-30); To = $endToday } }
        'last90'    { return @{ Mode = 'last90';    From = $now.Date.AddDays(-90); To = $endToday } }
        'thisMonth' { $f = $now.Date.AddDays(-($now.Day - 1)); return @{ Mode = 'thisMonth'; From = $f; To = $endToday } }
        'thisYear'  { $f = (Get-Date -Year $now.Year -Month 1 -Day 1).Date; return @{ Mode = 'thisYear'; From = $f; To = $endToday } }
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
    if (-not $From) { $From = [datetime]::MinValue }
    if (-not $To)   { $To   = [datetime]::MaxValue }

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

function New-JobReqExportBundle {
    <#
    Filters live in-memory $Data to one job + its kit + its candidates,
    builds the manifest, and returns a bundle hashtable. No IO and no
    writes, but exportedAt and exportedBy.machine/user are stamped at
    call time, so two calls on the same $Data produce different manifests.
    Throws if the job is not found.
    #>
    param($Data, [string]$JobId)

    $job = Get-JobById $Data $JobId
    if (-not $job) { throw ("Requisition not found: {0}" -f $JobId) }

    $kit   = Get-KitForJob $Data $JobId
    $cands = @(Get-CandidatesFor $Data $JobId)

    # Count rater entries
    $raterTotal     = 0
    $raterSubmitted = 0
    foreach ($c in $cands) {
        if ($c.raterEntries) {
            $entries = @($c.raterEntries)
            $raterTotal     += $entries.Count
            $raterSubmitted += @($entries | Where-Object { $_.status -eq 'Submitted' }).Count
        }
    }

    # exportedBy
    $userName = ''
    $userRole = ''
    if ($Data.Settings -and (_HasProp $Data.Settings 'currentUser')) {
        $cu = $Data.Settings.currentUser
        if (_HasProp $cu 'name') { $userName = [string]$cu.name }
        if (_HasProp $cu 'role') { $userRole = [string]$cu.role }
    }

    # if/else as a statement, not expression, per CLAUDE.md
    $kitCount = 0
    $kitId    = ''
    if ($kit) { $kitCount = 1; $kitId = $kit.id }

    $manifest = [pscustomobject]@{
        bundleSchema = $Script:BundleSchema
        appVersion   = 'v3'
        exportedAt   = (Get-Date).ToString('o')
        exportedBy   = [pscustomobject]@{
            name    = $userName
            role    = $userRole
            machine = "$env:COMPUTERNAME"
            user    = "$env:USERNAME"
        }
        source = [pscustomobject]@{
            jobReqId  = $job.id
            reqNumber = $job.reqNumber
            title     = $job.title
        }
        counts = [pscustomobject]@{
            kits                  = $kitCount
            candidates            = $cands.Count
            raterEntries          = $raterTotal
            submittedRaterEntries = $raterSubmitted
        }
        ids = [pscustomobject]@{
            jobReqId     = $job.id
            kitId        = $kitId
            candidateIds = @($cands | ForEach-Object { $_.id })
        }
    }

    return @{
        Manifest   = $manifest
        Job        = $job
        Kit        = $kit
        Candidates = $cands
        Catalog    = $Data.Catalog
    }
}

function Write-JobReqExportBundle {
    <#
    Writes a bundle to $Path as a .truehire.zip. Atomic: writes to a
    .tmp neighbor first, then Move-Item -Force to the final name. A
    finally block guarantees scratch dir + .tmp removal even on failure.
    Re-throws on IO/serialization errors.
    #>
    param($Bundle, [string]$Path)

    $scratch = Join-Path $env:TEMP ("TrueHire-Export-{0}" -f [guid]::NewGuid().ToString('N'))
    # Compress-Archive requires .zip extension; use a .zip temp name in TEMP then move.
    $tmpPath = Join-Path $env:TEMP ("TrueHire-Export-{0}.zip" -f [guid]::NewGuid().ToString('N'))

    try {
        [void](New-Item -ItemType Directory -Path $scratch -Force)

        # Use -InputObject to keep arrays as arrays (pipeline unwraps a 1-element
        # array to a bare object in PowerShell 5.1). Depth 12 matches Write-JsonFile.
        $Bundle.Manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $scratch 'manifest.json') -Encoding UTF8
        $Bundle.Job      | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $scratch 'job.json')      -Encoding UTF8

        $kitJson = '{"present":false}'
        if ($Bundle.Kit) { $kitJson = ($Bundle.Kit | ConvertTo-Json -Depth 12) }
        $kitJson | Set-Content -LiteralPath (Join-Path $scratch 'kit.json') -Encoding UTF8

        $candJson = ConvertTo-Json -InputObject @($Bundle.Candidates) -Depth 12
        $candJson | Set-Content -LiteralPath (Join-Path $scratch 'candidates.json') -Encoding UTF8

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

function Read-JobReqExportBundle {
    <#
    Unzips $Path to a scratch dir, parses all five files, validates the
    manifest schema and ID consistency, and returns:
        @{ Manifest; Job; Kit; Candidates; Catalog; ScratchDir }
    The caller MUST clean ScratchDir in a finally block. Throws on
    missing files, parse errors, schema-version mismatch, or ID
    inconsistency between manifest and payload.
    #>
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw ("Bundle file not found: {0}" -f $Path)
    }

    $scratch = Join-Path $env:TEMP ("TrueHire-Import-{0}" -f [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $scratch -Force)
    try {
        Expand-Archive -LiteralPath $Path -DestinationPath $scratch -Force
    } catch {
        if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
        throw ("Could not unzip bundle: {0}" -f $_.Exception.Message)
    }

    # Validate file presence
    $required = @('manifest.json','job.json','kit.json','candidates.json','catalog.json')
    foreach ($name in $required) {
        $p = Join-Path $scratch $name
        if (-not (Test-Path -LiteralPath $p)) {
            if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
            throw ("Bundle is missing required file: {0}" -f $name)
        }
    }

    # Parse each file (let parse errors propagate with file name context)
    $parsed = @{}
    foreach ($name in $required) {
        $p = Join-Path $scratch $name
        try {
            $parsed[$name] = Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        } catch {
            if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
            throw ("Failed to parse {0}: {1}" -f $name, $_.Exception.Message)
        }
    }

    $manifest = $parsed['manifest.json']
    $job      = $parsed['job.json']
    $kitRaw   = $parsed['kit.json']
    $cands    = @($parsed['candidates.json'])
    $catalog  = $parsed['catalog.json']

    # Schema version
    if ((-not $manifest) -or (-not (_HasProp $manifest 'bundleSchema')) -or ($manifest.bundleSchema -ne $Script:BundleSchema)) {
        if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
        $got = ''
        if ($manifest -and (_HasProp $manifest 'bundleSchema')) { $got = [string]$manifest.bundleSchema }
        throw ("Unsupported bundle schema: '{0}'. This version of TrueHire supports: {1}" -f $got, $Script:BundleSchema)
    }

    # ID consistency: manifest.ids.jobReqId vs job.id
    if ($manifest.ids.jobReqId -ne $job.id) {
        if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
        throw ("Manifest jobReqId ({0}) does not match job.id ({1})" -f $manifest.ids.jobReqId, $job.id)
    }

    # Resolve kit: {"present":false} sentinel -> $null, anything else is the real kit object
    $kit = $null
    if (-not ($kitRaw -and (_HasProp $kitRaw 'present') -and ($kitRaw.present -eq $false))) {
        $kit = $kitRaw
    }

    # ID consistency: kit.jobReqId vs job.id (only when kit is real)
    if ($kit -and $kit.jobReqId -ne $job.id) {
        if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
        throw ("Kit jobReqId ({0}) does not match job.id ({1})" -f $kit.jobReqId, $job.id)
    }

    # ID consistency: every candidate.jobReqId vs job.id
    $bad = @($cands | Where-Object { $_.jobReqId -ne $job.id })
    if ($bad.Count -gt 0) {
        if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue }
        $ids = ($bad | ForEach-Object { $_.id }) -join ', '
        throw ("Candidate(s) have wrong jobReqId: {0}" -f $ids)
    }

    return @{
        Manifest   = $manifest
        Job        = $job
        Kit        = $kit
        Candidates = $cands
        Catalog    = $catalog
        ScratchDir = $scratch
    }
}

function Import-JobReqExportBundle {
    <#
    Apply a bundle to live $Data. Mode 'Replace' overwrites any local
    entries with matching ids/jobReqIds. Mode 'New' rewrites every id
    (job/kit/candidates/rater entries) and appends as a clean copy with
    " (Imported)" appended to the title. Mutates $Data in place and
    returns a small summary hashtable.

    Catalog is NEVER overwritten - the bundle's catalog rides as metadata.
    #>
    param($Data, $Bundle, [ValidateSet('Replace','New')][string]$Mode)

    if (-not $Data)   { throw 'Import-JobReqExportBundle: $Data is required' }
    if (-not $Bundle) { throw 'Import-JobReqExportBundle: $Bundle is required' }

    $newJob   = $null
    $newKit   = $null
    $newCands = @()

    if ($Mode -eq 'Replace') {
        $jobId = $Bundle.Job.id
        $Data.Jobs       = @($Data.Jobs       | Where-Object { $_.id -ne $jobId })
        $Data.Kits       = @($Data.Kits       | Where-Object { $_.jobReqId -ne $jobId })
        $Data.Candidates = @($Data.Candidates | Where-Object { $_.jobReqId -ne $jobId })

        $newJob   = $Bundle.Job
        $newKit   = $Bundle.Kit
        $newCands = @($Bundle.Candidates)
    }
    elseif ($Mode -eq 'New') {
        # Deep-clone via JSON round-trip so we don't mutate the bundle in place
        # (the same bundle object could be imported twice in the same session).
        $cloneJob   = $Bundle.Job        | ConvertTo-Json -Depth 12 | ConvertFrom-Json
        $cloneKit   = $null
        if ($Bundle.Kit) { $cloneKit = $Bundle.Kit | ConvertTo-Json -Depth 12 | ConvertFrom-Json }
        $cloneCands = @()
        foreach ($c in @($Bundle.Candidates)) {
            $cloneCands += ($c | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
        }

        # Mint a fresh id helper (matches New-JobReq / New-InterviewKit /
        # New-Candidate / New-RaterEntry conventions in Data.ps1).
        $newId = { param([string]$Prefix) "{0}-{1}" -f $Prefix, ([guid]::NewGuid().ToString('N').Substring(0,8)) }

        $newJobId = & $newId 'req'
        $cloneJob.id = $newJobId
        $cloneJob.title = "{0} (Imported)" -f $cloneJob.title

        if ($cloneKit) {
            $cloneKit.id       = & $newId 'kit'
            $cloneKit.jobReqId = $newJobId
        }

        foreach ($c in $cloneCands) {
            $c.id       = & $newId 'cand'
            $c.jobReqId = $newJobId
            if ($c.raterEntries) {
                foreach ($e in @($c.raterEntries)) {
                    $e.id = & $newId 'rate'
                }
            }
        }

        $newJob   = $cloneJob
        $newKit   = $cloneKit
        $newCands = $cloneCands
    }

    # Append + migrate
    $Data.Jobs = @($Data.Jobs) + $newJob
    if ($newKit) { $Data.Kits = @($Data.Kits) + $newKit }
    foreach ($c in $newCands) {
        [void](_MigrateCandidate $c)
        Sync-CandidateLegacyRatings $c
        $Data.Candidates = @($Data.Candidates) + $c
    }

    $kitId      = ''
    $kitPresent = $false
    if ($newKit) { $kitId = $newKit.id; $kitPresent = $true }

    return @{
        Mode           = $Mode
        JobId          = $newJob.id
        ReqNumber      = $newJob.reqNumber
        KitId          = $kitId
        KitPresent     = $kitPresent
        CandidateCount = $newCands.Count
    }
}
