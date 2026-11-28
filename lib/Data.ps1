<#
Data.ps1 — load/save the v3 model. The seed JSONs under .\data ship with the
app; the live working copy lives under %APPDATA%\TrueHire\* so the user's
edits survive a re-pull of the source tree.

Model:
  JobRequisition (jobs.json)   - parent entity
  InterviewKit   (kits.json)   - 1:1 to job (kit.jobReqId)
  Candidate      (candidates.json) - many:1 to job (cand.jobReqId)
  Settings       (settings.json)
  Categories     (data\categories.json) - read-only catalog from v2
#>

# Resolve paths ------------------------------------------------------------
$Script:AppRoot     = Split-Path -Parent $PSCommandPath | Split-Path -Parent
$Script:SeedDir     = Join-Path $Script:AppRoot 'data'
$Script:ImagesDir   = Join-Path $Script:AppRoot 'images'
$Script:BannerPath  = Join-Path $Script:ImagesDir 'banner.png'
$Script:LogoPath    = Join-Path $Script:ImagesDir 'logo.png'
$Script:IconPath    = Join-Path $Script:AppRoot 'icon.ico'

# UserDataDir resolution. Three modes, checked in order:
#   1. $env:TRUEHIRE_DATA_ROOT - explicit override (set by the EXE launcher
#      to the EXE's own folder so data lives next to the .exe binary and
#      survives EXE rebuilds; extraction temp gets purged on update).
#   2. portable.flag next to TrueHire.ps1 - portable / USB-stick mode:
#      data lives in <AppRoot>\userdata\ so it travels with the folder.
#   3. Default - %APPDATA%\TrueHire\, the original main-repo behavior.
$Script:PortableFlag = Join-Path $Script:AppRoot 'portable.flag'
if ($env:TRUEHIRE_DATA_ROOT) {
    $Script:UserDataDir = $env:TRUEHIRE_DATA_ROOT
} elseif (Test-Path -LiteralPath $Script:PortableFlag) {
    $Script:UserDataDir = Join-Path $Script:AppRoot 'userdata'
} else {
    $Script:UserDataDir = Join-Path $env:APPDATA 'TrueHire'
}
if (-not (Test-Path $Script:UserDataDir)) { New-Item -ItemType Directory -Path $Script:UserDataDir -Force | Out-Null }

$Script:JobsPath       = Join-Path $Script:UserDataDir 'jobs.json'
$Script:KitsPath       = Join-Path $Script:UserDataDir 'kits.json'
$Script:CandidatesPath = Join-Path $Script:UserDataDir 'candidates.json'
$Script:SettingsPath   = Join-Path $Script:UserDataDir 'settings.json'

$Script:CategoriesPath = Join-Path $Script:SeedDir 'categories.json'
$Script:PositionsPath  = Join-Path $Script:SeedDir 'positions.json'

function Initialize-UserData {
    <#
    First-run bootstrap: if any of the four user files don't exist, copy the
    matching sample-*.json / default-settings.json into APPDATA. After this
    runs the user owns those files; subsequent runs read from APPDATA only.
    #>
    $seeds = @{
        $Script:JobsPath       = 'sample-jobs.json'
        $Script:KitsPath       = 'sample-kits.json'
        $Script:CandidatesPath = 'sample-candidates.json'
        $Script:SettingsPath   = 'default-settings.json'
    }
    foreach ($target in $seeds.Keys) {
        if (-not (Test-Path -LiteralPath $target)) {
            $src = Join-Path $Script:SeedDir $seeds[$target]
            if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination $target -Force }
        }
    }
}

function Read-JsonFile {
    <#
    Read + parse JSON. Returns $null if the file doesn't exist (that's a valid
    "not seeded yet" state). On parse/IO failure, logs ERROR and re-throws so
    the caller (Load-TrueHireData / migration) can decide whether to fall
    back. Read failures are loud because they often mean corrupt seed data.
    #>
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    } catch {
        $name = Split-Path $Path -Leaf
        if (Get-Command Write-TrueHireLog -ErrorAction SilentlyContinue) {
            Write-TrueHireLog -Level ERROR -Source ('Read-JsonFile:' + $name) -Message $_.Exception.Message -Exception $_.Exception
        }
        throw
    }
}

function Write-JsonFile {
    <#
    Write JSON. On failure, logs ERROR and captions the status bar so the user
    knows the save didn't land - but does NOT re-throw. Saves are best-effort:
    losing one save shouldn't kill the dispatcher or corrupt in-memory state.
    The next user action that triggers a save retries from in-memory truth.

    PS 5.1 ConvertTo-Json has two opposite traps with arrays:

      1) Pipeline form: piping an empty array unwraps to nothing, so
         Set-Content sees no input and never creates the file. Saving
         "jobs is now empty" then silently leaves the old file on disk
         and the deleted records reappear on next launch.

      2) -InputObject form: an Object[] returned from ConvertFrom-Json
         gets serialized via its Array metadata properties as
         {"value":[...],"Count":N} instead of as a JSON array. Once on
         disk, every subsequent read+write cycle perpetuates the wrap
         and the file is permanently corrupted (the live load returns a
         single PSCustomObject with .value/.Count and the UI sees no
         records).

    The fix: explicitly detect arrays and wrap them through a fresh @()
    Object[] before handing to ConvertTo-Json -InputObject. That dodges
    the ConvertFrom-Json metadata trap while still emitting [] for empty
    arrays. Non-array data (Settings hashtable, single objects) passes
    straight through.
    #>
    param([string]$Path, $Data)
    try {
        if ($null -eq $Data) {
            $json = 'null'
        } elseif ($Data -is [System.Array] -or $Data -is [System.Collections.IList]) {
            $json = ConvertTo-Json -InputObject @($Data) -Depth 12
        } else {
            $json = ConvertTo-Json -InputObject $Data -Depth 12
        }
        if ($null -eq $json) { $json = 'null' }
        Set-Content -LiteralPath $Path -Value $json -Encoding UTF8 -ErrorAction Stop
    } catch {
        $name = Split-Path $Path -Leaf
        if (Get-Command Write-TrueHireLog -ErrorAction SilentlyContinue) {
            Write-TrueHireLog -Level ERROR -Source ('Write-JsonFile:' + $name) -Message $_.Exception.Message -Exception $_.Exception
        }
        if (Get-Command Set-ShellStatus -ErrorAction SilentlyContinue) {
            Set-ShellStatus -Text ("Failed to save {0}: {1}" -f $name, $_.Exception.Message) -Level ERROR
        }
    }
}

function _HasProp {
    # Tiny shim so the migration reads as `if (_HasProp $obj 'name')` rather
    # than `$obj.PSObject.Properties.Name -contains 'name'` four times a line.
    param($Object, [string]$Name)
    if (-not $Object) { return $false }
    return ($Object.PSObject.Properties.Name -contains $Name)
}

function _SetProp {
    param($Object, [string]$Name, $Value)
    if (_HasProp $Object $Name) { $Object.$Name = $Value }
    else { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force }
}

function _RemoveProp {
    param($Object, [string]$Name)
    if (_HasProp $Object $Name) { $Object.PSObject.Properties.Remove($Name) }
}

function _MigrateSettings {
    <#
    In-memory up-convert from the v3.0 settings shape (which Settings.ps1
    never read correctly) to the v3.1 canonical shape that Settings.ps1
    reads and writes. Idempotent: if every canonical key already exists,
    this is a no-op. The migration only mutates the in-memory object;
    Save-Settings persists the canonical form when the user clicks Save in
    the UI, so on-disk migration happens lazily.

    Drift fixed here:
      - interviewKitDefaults  -> kitDefaults (combo-friendly strings)
      - fileUpload.maxSizeMb  -> fileUpload.maxSize ("25 MB")
      - fileUpload.allowedTypes CSV string -> array of ".EXT" tokens
      - top-level language    -> appPreferences.language
      - session.timeoutMinutes -> appPreferences.sessionTimeout ("30 minutes")
      - dateTime: cryptic IANA/format strings -> Combo-friendly labels
    #>
    param($Settings)
    if (-not $Settings) { return $Settings }

    # Kit defaults ---------------------------------------------------------
    if (-not (_HasProp $Settings 'kitDefaults') -and (_HasProp $Settings 'interviewKitDefaults')) {
        $old = $Settings.interviewKitDefaults
        $kit = [pscustomobject]@{
            ratingScale         = '1-7 (Standard)'
            requiredCategories  = if (_HasProp $old 'minQuestions') { "$($old.minQuestions)" } else { '5' }
            defaultQuestionType = if (_HasProp $old 'defaultType')  { $old.defaultType }      else { 'Behavioral' }
        }
        _SetProp $Settings 'kitDefaults' $kit
    }
    _RemoveProp $Settings 'interviewKitDefaults'

    # File upload ----------------------------------------------------------
    if ($Settings.fileUpload) {
        $fu = $Settings.fileUpload
        if (-not (_HasProp $fu 'maxSize') -and (_HasProp $fu 'maxSizeMb')) {
            _SetProp $fu 'maxSize' ("{0} MB" -f $fu.maxSizeMb)
        }
        _RemoveProp $fu 'maxSizeMb'
        if ((_HasProp $fu 'allowedTypes') -and $fu.allowedTypes -is [string]) {
            # CSV "pdf,doc,docx" -> [".PDF", ".DOC", ".DOCX"]
            $arr = @(
                $fu.allowedTypes -split '\s*,\s*' |
                    Where-Object { $_ } |
                    ForEach-Object { '.' + ($_.Trim().TrimStart('.').ToUpper()) }
            )
            _SetProp $fu 'allowedTypes' $arr
        }
    }

    # lastExportDir - added in the JobReq import/export feature. Default
    # empty; Get-LastExportDir falls back to MyDocuments if blank.
    if (-not (_HasProp $Settings 'lastExportDir')) {
        _SetProp $Settings 'lastExportDir' ''
    }

    # Preferences / language / session -------------------------------------
    if (-not (_HasProp $Settings 'appPreferences')) {
        _SetProp $Settings 'appPreferences' ([pscustomobject]@{})
    }
    $prefs = $Settings.appPreferences
    if (-not (_HasProp $prefs 'language') -and (_HasProp $Settings 'language')) {
        _SetProp $prefs 'language' $Settings.language
    }
    if (-not (_HasProp $prefs 'sessionTimeout') -and (_HasProp $Settings 'session') -and (_HasProp $Settings.session 'timeoutMinutes')) {
        _SetProp $prefs 'sessionTimeout' ("{0} minutes" -f $Settings.session.timeoutMinutes)
    }
    _RemoveProp $Settings 'language'
    _RemoveProp $Settings 'session'

    # Date/time labels - map a couple of well-known old values to the combo
    # labels. Anything else falls through; the combo just keeps its XAML
    # default, which is the same as the seed's value anyway.
    if ($Settings.dateTime) {
        $dt = $Settings.dateTime
        $tzMap = @{
            'America/New_York' = '(UTC-05:00) Eastern Time (US & Canada)'
            'America/Chicago'  = '(UTC-06:00) Central Time (US & Canada)'
            'America/Denver'   = '(UTC-07:00) Mountain Time (US & Canada)'
            'America/Los_Angeles' = '(UTC-08:00) Pacific Time (US & Canada)'
            'UTC'              = '(UTC) Coordinated Universal Time'
        }
        if ((_HasProp $dt 'timezone') -and $tzMap.ContainsKey($dt.timezone)) { $dt.timezone = $tzMap[$dt.timezone] }
        $dfMap = @{ 'yyyy-MM-dd' = 'YYYY-MM-DD'; 'MM/dd/yyyy' = 'MM/DD/YYYY'; 'dd/MM/yyyy' = 'DD/MM/YYYY' }
        if ((_HasProp $dt 'dateFormat') -and $dfMap.ContainsKey($dt.dateFormat)) { $dt.dateFormat = $dfMap[$dt.dateFormat] }
        $tfMap = @{ 'h:mm tt' = '12 Hour (1:00 PM)'; 'HH:mm' = '24 Hour (13:00)' }
        if ((_HasProp $dt 'timeFormat') -and $tfMap.ContainsKey($dt.timeFormat)) { $dt.timeFormat = $tfMap[$dt.timeFormat] }
    }

    return $Settings
}

function _MigrateKit {
    <#
    In-memory up-convert from the v3.0 kit shape (each kit-question is just
    {index, score, type} - a pointer into data/categories.json) to the v3.2
    canonical shape, where the kit owns probe + guide text directly. Also
    backfills category-level description from the catalog.

    Idempotent: a question that already has a non-null probe field AND an
    id field is left alone. The new shape per question:
        id           # opaque, stable, e.g. "kq-9f3a2b71"
        source       # "catalog" | "custom"
        catalogIndex # int or $null
        probe        # kit-local probe text
        guide        # kit-local scoring guide

    Legacy index/score/type fields on the question stay in memory after
    migration; the next Save-Kits writes the canonical form and they vanish
    from disk. Same for category-level order/required/type.

    Failures (catalog category gone, index out of range) keep the question
    with empty text and source="custom" - never drop. Logs WARN with the
    catalog id + index so the user can spot orphans.
    #>
    param($Kit, $Catalog)
    if (-not $Kit) { return $Kit }
    if (-not (_HasProp $Kit 'categories')) { _SetProp $Kit 'categories' @() }

    foreach ($cat in @($Kit.categories)) {
        # Category-level: backfill description from catalog.
        if (-not (_HasProp $cat 'description')) { _SetProp $cat 'description' '' }
        if (-not $cat.description -and $Catalog) {
            $catEntry = $Catalog.categories | Where-Object id -eq $cat.id | Select-Object -First 1
            if ($catEntry -and $catEntry.description) {
                _SetProp $cat 'description' $catEntry.description
            } elseif (Get-Command Write-TrueHireLog -ErrorAction SilentlyContinue) {
                Write-TrueHireLog -Level WARN -Source 'KitMigrate' -Message (
                    "Kit '{0}' category '{1}' has no description and no catalog entry" -f $Kit.id, $cat.id)
            }
        }

        # Category-level: backfill relative weight (default 1 = equal weighting).
        # Score-preserving: with every category at 1 the weighted mean equals
        # the old flat mean. See docs/specs/2026-06-04-category-weights-design.md.
        if (-not (_HasProp $cat 'weight') -or $null -eq $cat.weight) {
            _SetProp $cat 'weight' 1
        }

        # Question-level: inline probe + guide.
        if (-not (_HasProp $cat 'questions')) { _SetProp $cat 'questions' @() }
        foreach ($q in @($cat.questions)) {
            $alreadyMigrated = (_HasProp $q 'id') -and (_HasProp $q 'probe')
            if ($alreadyMigrated) { continue }

            # Generate stable id for this question.
            _SetProp $q 'id' ('kq-' + [guid]::NewGuid().ToString('N').Substring(0,8))

            $legacyIndex = if (_HasProp $q 'index') { [int]$q.index } else { 0 }
            $resolved = $null
            if ($Catalog -and $legacyIndex -gt 0) {
                $catEntry = $Catalog.categories | Where-Object id -eq $cat.id | Select-Object -First 1
                if ($catEntry) {
                    $resolved = $catEntry.questions | Where-Object index -eq $legacyIndex | Select-Object -First 1
                }
            }

            if ($resolved) {
                _SetProp $q 'source'       'catalog'
                _SetProp $q 'catalogIndex' $legacyIndex
                _SetProp $q 'probe'        ([string]$resolved.probe)
                _SetProp $q 'guide'        ([string]$resolved.guide)
                if (Get-Command Write-TrueHireLog -ErrorAction SilentlyContinue) {
                    Write-TrueHireLog -Level INFO -Source 'KitMigrate' -Message (
                        "Kit '{0}' inlined probe for {1}/{2}" -f $Kit.id, $cat.id, $legacyIndex)
                }
            } else {
                _SetProp $q 'source'       'custom'
                _SetProp $q 'catalogIndex' $null
                _SetProp $q 'probe'        ''
                _SetProp $q 'guide'        ''
                if (Get-Command Write-TrueHireLog -ErrorAction SilentlyContinue) {
                    Write-TrueHireLog -Level WARN -Source 'KitMigrate' -Message (
                        "Kit '{0}' could not resolve {1}/{2}; question kept as empty custom" -f $Kit.id, $cat.id, $legacyIndex)
                }
            }
        }
    }
    return $Kit
}

function _RemapAnchorToV4 {
    <#
    One-shot conversion from the pre-V4 1-based anchor scale (1 = strongest,
    6 = insufficient, 0 = unrated) to the V4 0..5 scale (5 = strongest,
    0 = insufficient, -1 = unrated):
        old 1..5 -> 6 - a   (preserves derived score exactly)
        old 6    -> 0       (insufficient)
        old 0    -> -1      (unrated)
    Anything already outside 0..6 (e.g. -1) is left untouched.
    #>
    param([int]$Anchor)
    if     ($Anchor -ge 1 -and $Anchor -le 5) { return (6 - $Anchor) }
    elseif ($Anchor -eq 6)                    { return 0 }
    elseif ($Anchor -eq 0)                    { return -1 }
    else                                      { return $Anchor }
}

function _MigrateCandidate {
    <#
    Backfills rating-related fields onto candidates that pre-date the rating
    system. Idempotent; safe to run every load. Existing matchScore values
    are preserved (manual scoring) until the user captures actual ratings.

    Multi-rater migration: if a candidate has the old single-rating shape
    (ratings populated, no raterEntries), promote it into a single rater
    entry under raterEntries so the new UI sees it. The old fields are kept
    alongside as a legacy view; Aggregate-CandidateRatings writes them back
    in sync after each save.
    #>
    param($Cand)
    if (-not $Cand) { return $Cand }
    # Capture BEFORE normalization: a genuinely legacy candidate (pre-dating
    # the rater-entries model) has no 'raterEntries' property at all. A
    # current-shape candidate whose evaluation was deleted has the property
    # present but empty - that is an intentional delete we must NOT undo.
    $isLegacyShape = -not (_HasProp $Cand 'raterEntries')
    if (-not (_HasProp $Cand 'ratings'))              { _SetProp $Cand 'ratings'              ([pscustomobject]@{}) }
    if (-not (_HasProp $Cand 'recommendation'))       { _SetProp $Cand 'recommendation'       '' }
    if (-not (_HasProp $Cand 'recommendationReason')) { _SetProp $Cand 'recommendationReason' '' }
    if (-not (_HasProp $Cand 'recommendationText'))   { _SetProp $Cand 'recommendationText'   '' }
    if (-not (_HasProp $Cand 'preparedBy'))           { _SetProp $Cand 'preparedBy'           '' }
    if (-not (_HasProp $Cand 'signature'))            { _SetProp $Cand 'signature'            '' }
    if (-not (_HasProp $Cand 'raterEntries'))         { _SetProp $Cand 'raterEntries'         @() }

    $hasLegacyRatings = $false
    if ($Cand.ratings -and $Cand.ratings.PSObject -and $Cand.ratings.PSObject.Properties) {
        $hasLegacyRatings = (@($Cand.ratings.PSObject.Properties).Count -gt 0)
    }
    if ($hasLegacyRatings -and $isLegacyShape) {
        # Genuinely legacy single-rating data, no rater entries ever: promote
        # it into one entry so it's visible in the evaluation UI.
        $entry = New-RaterEntry -RaterName ($Cand.preparedBy) -RaterRole 'Initial Rating'
        $entry.status      = 'Submitted'
        $entry.submittedAt = (Get-Date).ToString('o')
        # Copy legacy per-category ratings into the entry
        foreach ($prop in $Cand.ratings.PSObject.Properties) {
            $r = $prop.Value
            if ($null -ne $r) {
                _SetProp $entry.ratings $prop.Name ([pscustomobject]@{
                    anchor = [int]$r.anchor
                    note   = [string]$r.note
                })
            }
        }
        $entry.recommendation       = $Cand.recommendation
        $entry.recommendationReason = $Cand.recommendationReason
        $entry.recommendationText   = $Cand.recommendationText
        $entry.signature            = $Cand.signature
        $Cand.raterEntries = ,$entry
    }
    elseif ($hasLegacyRatings -and (@($Cand.raterEntries).Count -eq 0)) {
        # Current-shape candidate whose evaluation was deleted but left a stale
        # legacy ratings map behind (the old Sync-CandidateLegacyRatings never
        # cleared it). Heal it: clear the ghost map so nothing resurrects the
        # deleted evaluation and the printable sheet shows no phantom marks.
        $Cand.ratings = [pscustomobject]@{}
    }

    # One-time anchor-scale flip to the V4 0..5 scheme (5 = strongest). Guarded
    # by the per-candidate 'anchorScheme' marker so it runs exactly once and
    # survives re-imports of pre-V4 exports. Runs AFTER the legacy-promotion
    # block above so anchors copied into a freshly promoted entry are flipped
    # too. New-Candidate stamps 'v4' at creation, so new data is never touched.
    if (-not (_HasProp $Cand 'anchorScheme') -or $Cand.anchorScheme -ne 'v4') {
        foreach ($entry in @($Cand.raterEntries)) {
            if ($entry -and $entry.ratings) {
                foreach ($prop in $entry.ratings.PSObject.Properties) {
                    if ($null -ne $prop.Value -and (_HasProp $prop.Value 'anchor')) {
                        $prop.Value.anchor = _RemapAnchorToV4 ([int]$prop.Value.anchor)
                    }
                }
            }
        }
        if ($Cand.ratings) {
            foreach ($prop in $Cand.ratings.PSObject.Properties) {
                if ($null -ne $prop.Value -and (_HasProp $prop.Value 'anchor')) {
                    $prop.Value.anchor = _RemapAnchorToV4 ([int]$prop.Value.anchor)
                }
            }
        }
        _SetProp $Cand 'anchorScheme' 'v4'
    }

    return $Cand
}

function Get-CandidateRating {
    <#
    Returns the rating entry for a category id, creating an empty default if
    none exists. The returned object is the live property on $Cand.ratings,
    so caller mutations propagate (no copy).
    #>
    param($Cand, [string]$CategoryId)
    if (-not $Cand.ratings) { _SetProp $Cand 'ratings' ([pscustomobject]@{}) }
    if (-not (_HasProp $Cand.ratings $CategoryId)) {
        _SetProp $Cand.ratings $CategoryId ([pscustomobject]@{ anchor = -1; note = '' })
    }
    return $Cand.ratings.$CategoryId
}

function Set-CandidateRating {
    <#
    Convenience setter the rating UI calls per row. Always mutates the same
    rating object so reads (Get-CandidateRating) see the change.
    #>
    param($Cand, [string]$CategoryId, [int]$Anchor, [string]$Note)
    $r = Get-CandidateRating -Cand $Cand -CategoryId $CategoryId
    _SetProp $r 'anchor' ([int]$Anchor)
    _SetProp $r 'note'   ([string]$Note)
}

# Per-rater equivalents of the above. They operate on a RaterEntry (one item
# from candidate.raterEntries) rather than the legacy single map.
function Get-RaterRating {
    param($Entry, [string]$CategoryId)
    if (-not $Entry.ratings) { _SetProp $Entry 'ratings' ([pscustomobject]@{}) }
    if (-not (_HasProp $Entry.ratings $CategoryId)) {
        _SetProp $Entry.ratings $CategoryId ([pscustomobject]@{ anchor = -1; note = '' })
    }
    return $Entry.ratings.$CategoryId
}

function Set-RaterRating {
    param($Entry, [string]$CategoryId, [int]$Anchor, [string]$Note)
    $r = Get-RaterRating -Entry $Entry -CategoryId $CategoryId
    _SetProp $r 'anchor' ([int]$Anchor)
    _SetProp $r 'note'   ([string]$Note)
}

function Get-RaterEntryById {
    param($Cand, [string]$EntryId)
    if (-not $Cand -or -not $Cand.raterEntries) { return $null }
    return @($Cand.raterEntries | Where-Object id -eq $EntryId | Select-Object -First 1)[0]
}

function Add-RaterEntry {
    <#
    Appends a fresh rater entry to the candidate. Returns the new entry so
    the caller can immediately open it for editing.
    #>
    param($Cand, [string]$RaterName = '', [string]$RaterRole = '')
    $entry = New-RaterEntry -RaterName $RaterName -RaterRole $RaterRole
    $Cand.raterEntries = @($Cand.raterEntries) + $entry
    return $entry
}

function Remove-RaterEntry {
    param($Cand, [string]$EntryId)
    if (-not $Cand -or -not $Cand.raterEntries) { return }
    $Cand.raterEntries = @($Cand.raterEntries | Where-Object id -ne $EntryId)
}

# --- Single-evaluation model ------------------------------------------------
# The app collects ONE interview evaluation per candidate, authored by the
# hiring manager. raterEntries is retained as the storage shape (and stays a
# 1-element array) so existing data, exports, and the score helper keep
# working - but the UI never surfaces more than the primary entry. No nesting,
# no cross-rater aggregation.
function Get-PrimaryRaterEntry {
    <#
    Returns the candidate's single evaluation entry, or $null if none exists.
    If legacy data left more than one entry behind, the first is treated as
    canonical (the rest are ignored by the UI; Get-OrCreatePrimaryRaterEntry
    trims them on next edit).
    #>
    param($Cand)
    if (-not $Cand -or -not $Cand.raterEntries) { return $null }
    return @($Cand.raterEntries | Select-Object -First 1)[0]
}

function Get-OrCreatePrimaryRaterEntry {
    <#
    Returns the candidate's single evaluation, creating one (attributed to the
    hiring manager) if absent. Collapses any stray extra entries down to the
    first so the single-evaluation invariant holds after every edit.
    #>
    param($Cand, [string]$RaterName = '', [string]$RaterRole = 'Hiring Manager')
    $existing = @($Cand.raterEntries)
    if ($existing.Count -ge 1) {
        # Enforce the single-entry invariant; keep the first.
        if ($existing.Count -gt 1) { $Cand.raterEntries = ,$existing[0] }
        return $existing[0]
    }
    $entry = New-RaterEntry -RaterName $RaterName -RaterRole $RaterRole
    $Cand.raterEntries = ,$entry
    return $entry
}

# NOTE: removed $Script:AnchorScores (anchor->0..100 map) and the helper
# Update-CandidateScoreFromRatings / Update-CandidateAggregatedScore /
# _AnchorToScore. The v1 canonical methodology does NOT derive a numeric
# match score from anchor selections - the anchor grid is qualitative
# output, and the holistic Select/Non-Select call lives in
# candidate.recommendation. Anchor aggregation (avg per category) still
# lives in Get-CandidateAggregatedRatings; nothing converts that to a
# 0..100 number anymore.

function Get-CandidateAggregatedRatings {
    <#
    Walks every Submitted rater entry on the candidate and computes the
    mean anchor per category. Returns:
      @{
        ByCategory = @{ <catId> = @{ AvgAnchor; RaterCount; Anchors=@(...) } }
        SubmittedRaterCount = int
        RatedCategoryCount  = int
      }
    Anchor 0 ("Insufficient evidence") and -1 (unrated) are excluded.

    Intentionally does NOT compute a derived numeric score. The canonical
    v1 rating methodology is qualitative: the anchor grid is the output,
    and the holistic Select/Non-Select call belongs to the manager via
    candidate.recommendation. Earlier v3 versions derived a 0..100 score by
    mapping anchors to fixed points and averaging - that was a v3
    invention with no basis in the v1 Excel and has been removed.
    #>
    param($Cand)
    $result = @{
        ByCategory          = @{}
        RatedCategoryCount  = 0
        SubmittedRaterCount = 0
    }
    if (-not $Cand -or -not $Cand.raterEntries) { return $result }
    $submitted = @($Cand.raterEntries | Where-Object { $_.status -eq 'Submitted' })
    $result.SubmittedRaterCount = $submitted.Count
    if ($submitted.Count -eq 0) { return $result }

    foreach ($entry in $submitted) {
        if (-not $entry.ratings) { continue }
        foreach ($prop in $entry.ratings.PSObject.Properties) {
            $catId = $prop.Name
            $r = $prop.Value
            if ($null -eq $r) { continue }
            $a = [int]$r.anchor
            if ($a -lt 1 -or $a -gt 5) { continue }
            if (-not $result.ByCategory.ContainsKey($catId)) {
                $result.ByCategory[$catId] = @{ Anchors = @(); RaterCount = 0; AvgAnchor = 0.0 }
            }
            $result.ByCategory[$catId].Anchors    = @($result.ByCategory[$catId].Anchors) + $a
            $result.ByCategory[$catId].RaterCount = $result.ByCategory[$catId].Anchors.Count
        }
    }

    foreach ($catId in @($result.ByCategory.Keys)) {
        $arr = $result.ByCategory[$catId].Anchors
        if ($arr.Count -eq 0) { continue }
        $result.ByCategory[$catId].AvgAnchor = [double](($arr | Measure-Object -Average).Average)
        $result.RatedCategoryCount++
    }
    return $result
}

function Sync-CandidateLegacyRatings {
    <#
    Mirrors the per-category aggregated anchor into candidate.ratings so the
    printable consolidated rating sheet (which reads candidate.ratings to
    draw the checkmark column) still has the right ✓ position. This is a
    pure side-effect for the HTML output; it doesn't compute a match score.
    Call after rater entries change.
    #>
    param($Cand)
    if (-not $Cand) { return }
    $agg = Get-CandidateAggregatedRatings $Cand
    # Rebuild from scratch (not merge): categories that no longer have any
    # Submitted anchors - e.g. after the evaluation was deleted - must NOT
    # leave stale entries behind. An empty map is the correct result when the
    # candidate has no rater entries. Leaving stale anchors here was what let
    # a deleted evaluation get resurrected by _MigrateCandidate on next load.
    $Cand.ratings = [pscustomobject]@{}
    foreach ($catId in @($agg.ByCategory.Keys)) {
        $entry = $agg.ByCategory[$catId]
        $approxAnchor = [int][Math]::Round($entry.AvgAnchor)
        $note = "avg anchor {0:N1} across {1} rater(s)" -f $entry.AvgAnchor, $entry.RaterCount
        _SetProp $Cand.ratings $catId ([pscustomobject]@{
            anchor = $approxAnchor
            note   = $note
        })
    }
}

function Load-TrueHireData {
    <#
    Returns a single hashtable containing every collection plus the catalog.
    Views mutate the contained arrays in place; Save-TrueHireData persists
    whatever section the caller passes.
    #>
    Initialize-UserData
    $cands = Read-JsonFile $Script:CandidatesPath
    if ($cands) { foreach ($c in $cands) { [void](_MigrateCandidate $c) } }
    $catalog = Read-JsonFile $Script:CategoriesPath
    $kits = Read-JsonFile $Script:KitsPath
    if ($kits) { foreach ($k in $kits) { [void](_MigrateKit $k $catalog) } }
    # NOTE: @() around these would re-wrap the returned Object[] inside a
    # 1-element outer array (because the function returns the array as a
    # single value). Take the pipeline output directly instead.
    return @{
        Jobs       = (Read-JsonFile $Script:JobsPath)
        Kits       = $kits
        Candidates = $cands
        Settings   = (_MigrateSettings (Read-JsonFile $Script:SettingsPath))
        Catalog    = $catalog
        Positions  = (Read-JsonFile $Script:PositionsPath)
    }
}

function Save-Jobs       { param($Data) Write-JsonFile $Script:JobsPath       $Data.Jobs }
function Save-Kits       { param($Data) Write-JsonFile $Script:KitsPath       $Data.Kits }
function Save-Candidates { param($Data) Write-JsonFile $Script:CandidatesPath $Data.Candidates }
function Save-Settings   { param($Data) Write-JsonFile $Script:SettingsPath   $Data.Settings }

function Remove-JobReq {
    <#
    Cascade-delete a job requisition and everything attached to it: the 1:1
    interview kit and all N:1 candidates (with their rater entries). The
    deletion scope mirrors New-JobReqExportBundle so an export -> delete ->
    re-import round-trip is lossless.

    Mutates $Data in place AND persists each affected layer via Save-Jobs /
    Save-Kits / Save-Candidates. Returns a summary hashtable so the caller
    can caption the status bar / write a log line. Returns $null if the job
    id was not found - callers should treat that as a no-op.

    No undo. Callers should give the user a backup-export option before
    invoking this (see Show-DeleteJobReqDialog in views/JobReqs.ps1).
    #>
    param($Data, [string]$JobId)

    $job = Get-JobById $Data $JobId
    if (-not $job) { return $null }

    # Count BEFORE mutation so the caller can report what got removed.
    $kit   = Get-KitForJob     $Data $JobId
    $cands = @(Get-CandidatesFor $Data $JobId)

    # CLAUDE.md: Measure-Object -Property doesn't work on Hashtable
    # collections, and a candidate.raterEntries entry may be missing
    # entirely on older shapes. foreach + count is the safe form.
    $raterCount = 0
    foreach ($c in $cands) {
        if ($c.raterEntries) { $raterCount += @($c.raterEntries).Count }
    }

    # Mutate + persist. Order: children first, parent last - so if a save
    # mid-way fails we never leave dangling parent-with-no-children visible
    # (and Write-JsonFile is best-effort: it logs but doesn't throw on
    # failure, per Data.ps1 contract).
    if ($cands.Count -gt 0) {
        $candIds = @($cands | ForEach-Object { $_.id })
        $Data.Candidates = @($Data.Candidates | Where-Object { $candIds -notcontains $_.id })
        Save-Candidates $Data
    }
    if ($kit) {
        $Data.Kits = @($Data.Kits | Where-Object id -ne $kit.id)
        Save-Kits $Data
    }
    $Data.Jobs = @($Data.Jobs | Where-Object id -ne $job.id)
    Save-Jobs $Data

    $summary = @{
        JobReqNumber        = $job.reqNumber
        JobTitle            = $job.title
        DeletedKits         = if ($kit) { 1 } else { 0 }
        DeletedCandidates   = $cands.Count
        DeletedRaterEntries = $raterCount
    }

    if (Get-Command Write-TrueHireLog -ErrorAction SilentlyContinue) {
        Write-TrueHireLog -Level INFO -Source 'Remove-JobReq' -Message (
            "Deleted {0} ({1}): {2} kit, {3} candidates, {4} rater entries" -f `
            $summary.JobReqNumber, $job.id, $summary.DeletedKits,
            $summary.DeletedCandidates, $summary.DeletedRaterEntries)
    }

    return $summary
}

# Factory helpers ----------------------------------------------------------
function New-JobReq {
    [pscustomobject]@{
        id             = 'req-' + [guid]::NewGuid().ToString('N').Substring(0,8)
        reqNumber      = '#R' + (Get-Random -Min 100 -Max 999)
        title          = ''
        position       = ''
        hiringManager  = ''
        status         = 'Draft'
        department     = ''
        location       = ''
        description    = ''
        createdDate    = (Get-Date).ToString('s')
        modifiedDate   = (Get-Date).ToString('s')
        targetHireDate = (Get-Date).AddMonths(3).ToString('yyyy-MM-dd')
        openings       = 1
        candidateCount = 0
        interviewKitId = ''
    }
}

function New-InterviewKit {
    param([string]$JobReqId, [string]$Name = '')
    [pscustomobject]@{
        id          = 'kit-' + [guid]::NewGuid().ToString('N').Substring(0,8)
        jobReqId    = $JobReqId
        name        = if ($Name) { $Name } else { 'New Interview Kit' }
        status      = 'Draft'
        createdDate = (Get-Date).ToString('s')
        categories  = @()
    }
}

function New-Candidate {
    <#
    Match score is DERIVED at display time from Submitted rater anchors
    (see Get-CandidateScore in lib/Helpers.ps1) -- not stored. The
    legacy 'matchScore' field is no longer written by any code path;
    existing values on disk are simply ignored.

    Rater entry shape (one per interviewer):
      @{ id; raterName; raterRole; status='Draft'|'Submitted'; submittedAt;
         ratings = { categoryId: { anchor=0..5 (-1 = unrated); note } };
         recommendation; recommendationReason; recommendationText; signature }

    The candidate-level recommendation/preparedBy/signature fields are kept
    for back-compat and for the manager's "final call" view; multi-rater
    workflows write into per-entry copies.
    #>
    [pscustomobject]@{
        id                   = 'cand-' + [guid]::NewGuid().ToString('N').Substring(0,8)
        name                 = ''
        email                = ''
        phone                = ''
        jobReqId             = ''
        position             = ''
        stage                = 'New'
        appliedDate          = (Get-Date).ToString('yyyy-MM-dd')
        interviewDate        = ''
        raterEntries         = @()      # array of rater submissions (see New-RaterEntry)
        ratings              = @{}      # legacy: single consolidated map (kept for back-compat)
        recommendation       = ''       # candidate-level / manager's final call
        recommendationReason = ''
        recommendationText   = ''
        preparedBy           = ''
        signature            = ''
        notes                = ''
        avatarColor          = '#1E88E5'
        initials             = ''
        anchorScheme         = 'v4'     # anchors stored on the 0..5 scale (5 = strongest)
    }
}

function New-RaterEntry {
    <#
    A single interviewer's rating submission for one candidate. id is opaque
    and unique within the candidate. Default status='Draft' so the manager
    can stage entries before counting them in the aggregate.
    #>
    param(
        [string]$RaterName = '',
        [string]$RaterRole = ''
    )
    [pscustomobject]@{
        id                   = 'rate-' + [guid]::NewGuid().ToString('N').Substring(0,8)
        raterName            = $RaterName
        raterRole            = $RaterRole
        status               = 'Draft'    # 'Draft' | 'Submitted'
        submittedAt          = ''
        ratings              = [pscustomobject]@{}   # categoryId -> @{ anchor; note }
        recommendation       = ''
        recommendationReason = ''
        recommendationText   = ''
        signature            = ''
    }
}

# Lookup helpers -----------------------------------------------------------
function Get-JobById       { param($Data,[string]$Id) $Data.Jobs       | Where-Object id -eq $Id | Select-Object -First 1 }
function Get-KitById       { param($Data,[string]$Id) $Data.Kits       | Where-Object id -eq $Id | Select-Object -First 1 }
function Get-CandidateById { param($Data,[string]$Id) $Data.Candidates | Where-Object id -eq $Id | Select-Object -First 1 }
function Get-KitForJob     { param($Data,[string]$JobId) $Data.Kits    | Where-Object jobReqId -eq $JobId | Select-Object -First 1 }
function Get-CandidatesFor { param($Data,[string]$JobId) @($Data.Candidates | Where-Object jobReqId -eq $JobId) }
