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
# NOTE: named $JOB_SPECS (not $JOBS) to avoid PowerShell 5.1 case-insensitive
# collision with the output accumulator $jobs (CLAUDE.md gotcha #5).
$JOB_SPECS = @(
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

for ($i = 0; $i -lt $JOB_SPECS.Count; $i++) {
    $spec = $JOB_SPECS[$i]

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

        # One completed evaluation. V4 scale: anchor 5 = strongest .. 1 = weakest.
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
        $avg = 0.0
        if ($n -gt 0) { $avg = $sum / $n }
        if ($avg -ge 3) {
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
Write-Host ("Wrote: {0}\jobs.json, kits.json, candidates.json" -f $ud)
Write-Host ("Wrote: {0}" -f $zipPath)
