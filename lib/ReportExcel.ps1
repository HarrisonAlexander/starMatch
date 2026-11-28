<#
ReportExcel.ps1 - Excel report generator for the Analytics tab. Produces a
multi-sheet .xlsx in .\outputs\ that snapshots whatever the user is
currently looking at on Analytics, including the active filters.

Depends on the ImportExcel module (third-party but pure-managed - no Excel
or COM needed, writes EPPlus xlsx directly). The boot path probes for the
module and disables the Export Report button if it's missing, so an
out-of-the-box machine without the module just sees a tooltip instead of
a runtime error.

Public surface:
  - Test-ImportExcelAvailable   - $true if Import-Module ImportExcel works
  - Export-AnalyticsReport      - write the multi-sheet xlsx, return path

Naming convention mirrors the HTML outputs:
  Analytics-Report_<timestamp>.xlsx
#>

# Resolve outputs dir if HtmlOutput.ps1 hasn't already done it. Both files
# write into the same .\outputs\ directory next to TrueHire.ps1.
if (-not $Script:OutputsDir) {
    $outBase = if ($Script:StateDir) { $Script:StateDir } else { Split-Path -Parent $PSCommandPath | Split-Path -Parent }
    $Script:OutputsDir = Join-Path $outBase 'outputs'
    if (-not (Test-Path -LiteralPath $Script:OutputsDir)) {
        New-Item -ItemType Directory -Path $Script:OutputsDir -Force | Out-Null
    }
}

# Cache the probe result so we don't pay the Import-Module roundtrip every
# time the user clicks Export Report. $null = not probed yet.
$Script:_ImportExcelOk = $null

function Test-ImportExcelAvailable {
    <#
    Returns $true if the ImportExcel module can be imported in this session.
    First call attempts an Import-Module; subsequent calls return the cached
    answer. Failures are logged but never thrown - the caller is expected
    to gracefully degrade (disable the Export button, show a tooltip, etc).
    #>
    if ($null -ne $Script:_ImportExcelOk) { return $Script:_ImportExcelOk }
    try {
        Import-Module ImportExcel -ErrorAction Stop
        $Script:_ImportExcelOk = $true
    } catch {
        $Script:_ImportExcelOk = $false
        if (Get-Command Write-TrueHireLog -ErrorAction SilentlyContinue) {
            Write-TrueHireLog -Level WARN -Source 'ReportExcel' `
                -Message ("ImportExcel module not available: {0}" -f $_.Exception.Message)
        }
    }
    return $Script:_ImportExcelOk
}

function _FilterCandidate {
    <#
    Mirror of views\Analytics.ps1's _PassesAnalyticsFilters so the report
    can apply the same filter the user is seeing without depending on a
    function defined in a view file. Kept in lib so layering stays clean.
    #>
    param($Cand, $Job, $Filters)
    if (-not $Filters) { return $true }
    if ($Filters.JobId   -ne 'all' -and $Cand.jobReqId -ne $Filters.JobId) { return $false }
    if ($Filters.Stage   -ne 'All Stages' -and $Cand.stage -ne $Filters.Stage) { return $false }
    if ($Job) {
        if ($Filters.Manager -ne 'all' -and $Job.hiringManager -ne $Filters.Manager) { return $false }
        if ($Filters.Dept    -ne 'all' -and $Job.department    -ne $Filters.Dept)    { return $false }
    }
    if ($Filters.DateRange -and $Filters.DateRange -ne 'All time') {
        $days = switch ($Filters.DateRange) {
            'Last 30 days' { 30 }
            'Last 60 days' { 60 }
            'Last 90 days' { 90 }
            'Year to date' { (Get-Date).DayOfYear }
            default        { 9999 }
        }
        try {
            $applied = [datetime]$Cand.appliedDate
            if ($applied -lt (Get-Date).AddDays(-$days)) { return $false }
        } catch { }
    }
    return $true
}

function _AvgAnchorAcrossCandidate {
    # Convenience: avg of submitted-rater anchors 1..5 across all categories
    # on a candidate. Anchor 0 (insufficient) and -1 (unrated) excluded, same
    # as the rest of the app. Returns $null if no scorable anchors.
    param($Cand)
    if (-not $Cand.raterEntries) { return $null }
    $sum = 0.0; $n = 0
    foreach ($e in @($Cand.raterEntries)) {
        if ($e.status -ne 'Submitted' -or -not $e.ratings) { continue }
        foreach ($p in $e.ratings.PSObject.Properties) {
            $a = 0
            try { $a = [int]$p.Value.anchor } catch { }
            if ($a -ge 1 -and $a -le 5) { $sum += $a; $n++ }
        }
    }
    if ($n -eq 0) { return $null }
    return [Math]::Round($sum / [double]$n, 2)
}

function _BuildOutputPath {
    param([string]$Prefix = 'Analytics-Report')
    $ts = Get-Date -Format 'yyyy-MM-dd-HHmmss'
    return Join-Path $Script:OutputsDir ("{0}_{1}.xlsx" -f $Prefix, $ts)
}

function _ApplyHeaderStyle {
    <#
    Bold + navy fill + white text on the header row of one worksheet. Run
    after Export-Excel returns a package - we mutate the cells directly
    rather than relying on Export-Excel's -ConditionalFormat which is
    awkward for a fixed-position header.
    #>
    param($Worksheet, [int]$ColumnCount)
    if (-not $Worksheet -or $ColumnCount -lt 1) { return }
    $hdr = $Worksheet.Cells[1, 1, 1, $ColumnCount]
    $hdr.Style.Font.Bold = $true
    $hdr.Style.Font.Color.SetColor([System.Drawing.Color]::White)
    $hdr.Style.Fill.PatternType = [OfficeOpenXml.Style.ExcelFillStyle]::Solid
    $hdr.Style.Fill.BackgroundColor.SetColor(
        [System.Drawing.ColorTranslator]::FromHtml('#0B2C45'))
    $hdr.Style.HorizontalAlignment = [OfficeOpenXml.Style.ExcelHorizontalAlignment]::Left
}

function Export-AnalyticsReport {
    <#
    Snapshot the Analytics view (and the filters it has applied) to a
    multi-sheet xlsx. Returns the path of the file written.

    Mandatory: $Data ($Script:ShellData).
    Optional:  $Filters ($Script:AnalyticsFilters); if omitted, the report
               includes ALL candidates/jobs with no filtering.

    Throws if the ImportExcel module isn't available - callers should
    Test-ImportExcelAvailable first and degrade gracefully.

    Sheets written:
      1. Summary           - filter context + KPIs + dataset counts
      2. Candidates        - one row per filtered candidate
      3. Requisitions      - one row per filtered job
      4. Funnel            - stage counts on filtered candidates
      5. Hires by Req      - top 7 by hire count (or candidate count fallback)
      6. Avg Match by Kit  - top 7 kits by avg matchScore
      7. By Manager        - in-progress candidates per hiring manager
      8. Match Distribution- histogram bands 0-50, 50-60, ..., 90-100
    #>
    param(
        [Parameter(Mandatory)]$Data,
        $Filters,
        [string]$Path
    )

    if (-not (Test-ImportExcelAvailable)) {
        throw "ImportExcel module not available. Install with: Install-Module ImportExcel -Scope CurrentUser"
    }

    if (-not $Path) { $Path = _BuildOutputPath }
    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force }

    # ---- Filter the live dataset to match what's on screen ----
    $jobs      = @($Data.Jobs)
    $cands     = @($Data.Candidates)
    $jobsById  = @{}; foreach ($j in $jobs) { $jobsById[$j.id] = $j }

    $filteredCands = @()
    foreach ($c in $cands) {
        $j = $jobsById[$c.jobReqId]
        if (_FilterCandidate -Cand $c -Job $j -Filters $Filters) { $filteredCands += $c }
    }
    $filteredJobs = @($jobs | Where-Object {
        ( -not $Filters -or $Filters.JobId   -eq 'all' -or $_.id -eq $Filters.JobId) -and
        ( -not $Filters -or $Filters.Manager -eq 'all' -or $_.hiringManager -eq $Filters.Manager) -and
        ( -not $Filters -or $Filters.Dept    -eq 'all' -or $_.department    -eq $Filters.Dept)
    })

    # ---- Sheet 1: Summary -----------------------------------------------
    $whoName = ''; $whoRole = ''
    if ($Data.Settings -and $Data.Settings.currentUser) {
        if ($Data.Settings.currentUser.name) { $whoName = [string]$Data.Settings.currentUser.name }
        if ($Data.Settings.currentUser.role) { $whoRole = [string]$Data.Settings.currentUser.role }
    }
    $fDate = if ($Filters) { $Filters.DateRange } else { 'All time' }
    $fJob  = if ($Filters -and $Filters.JobId   -ne 'all') {
                 $jj = $jobsById[$Filters.JobId]
                 if ($jj) { "$($jj.reqNumber) $($jj.title)" } else { $Filters.JobId }
             } else { 'All requisitions' }
    $fMgr  = if ($Filters -and $Filters.Manager -ne 'all') { $Filters.Manager } else { 'All managers' }
    $fDept = if ($Filters -and $Filters.Dept    -ne 'all') { $Filters.Dept }    else { 'All departments' }
    $fStg  = if ($Filters) { $Filters.Stage } else { 'All Stages' }

    $hired     = @($filteredCands | Where-Object stage -eq 'Hired').Count
    $advanced  = @($filteredCands | Where-Object { $_.stage -in 'Interview','Offer','Hired' }).Count
    $activeJob = @($filteredJobs  | Where-Object status -eq 'Active').Count
    # Derived score average. Unrated candidates ($null) excluded so the
    # mean reflects actual evidence, not "0 because nobody reviewed yet".
    $scoreSamples = @()
    foreach ($cc in $filteredCands) {
        $s = Get-CandidateScore $cc $Data
        if ($null -ne $s) { $scoreSamples += [int]$s }
    }
    $avgScore  = if (@($scoreSamples).Count -gt 0) {
        [int][Math]::Round( ($scoreSamples | Measure-Object -Average).Average )
    } else { 0 }

    $summary = @(
        [pscustomobject]@{ Field='Generated';        Value=(Get-Date -Format 'yyyy-MM-dd HH:mm') }
        [pscustomobject]@{ Field='Generated by';     Value=("{0} ({1})" -f $whoName, $whoRole) }
        [pscustomobject]@{ Field='';                 Value='' }
        [pscustomobject]@{ Field='Filter: Date';     Value=$fDate }
        [pscustomobject]@{ Field='Filter: Req';      Value=$fJob }
        [pscustomobject]@{ Field='Filter: Manager';  Value=$fMgr }
        [pscustomobject]@{ Field='Filter: Dept';     Value=$fDept }
        [pscustomobject]@{ Field='Filter: Stage';    Value=$fStg }
        [pscustomobject]@{ Field='';                 Value='' }
        [pscustomobject]@{ Field='Total reqs';       Value=$filteredJobs.Count }
        [pscustomobject]@{ Field='Active reqs';      Value=$activeJob }
        [pscustomobject]@{ Field='Total candidates'; Value=$filteredCands.Count }
        [pscustomobject]@{ Field='Advanced';         Value=$advanced }
        [pscustomobject]@{ Field='Hired';            Value=$hired }
        [pscustomobject]@{ Field='Avg match score';  Value=("{0}%" -f $avgScore) }
    )
    $pkg = $summary | Export-Excel -Path $Path -WorksheetName 'Summary' -AutoSize -PassThru
    _ApplyHeaderStyle -Worksheet $pkg.Workbook.Worksheets['Summary'] -ColumnCount 2

    # ---- Sheet 2: Candidates -------------------------------------------
    $candRows = foreach ($c in $filteredCands) {
        $j = $jobsById[$c.jobReqId]
        $avgAnch = _AvgAnchorAcrossCandidate $c
        $raters  = if ($c.raterEntries) { @($c.raterEntries).Count } else { 0 }
        $submit  = if ($c.raterEntries) { @($c.raterEntries | Where-Object status -eq 'Submitted').Count } else { 0 }
        [pscustomobject][ordered]@{
            Candidate       = $c.name
            Email           = $c.email
            Phone           = $c.phone
            ReqNumber       = if ($j) { $j.reqNumber } else { '' }
            Position        = if ($j) { $j.title }     else { $c.position }
            Department      = if ($j) { $j.department } else { '' }
            HiringManager   = if ($j) { $j.hiringManager } else { '' }
            Stage           = $c.stage
            MatchScore      = $(Get-CandidateScore $c $Data)   # $null when unrated -> blank cell
            AvgAnchor       = $avgAnch
            Raters          = $raters
            RatersSubmitted = $submit
            Recommendation  = $c.recommendation
            AppliedDate     = $c.appliedDate
            InterviewDate   = $c.interviewDate
        }
    }
    if ($candRows.Count -gt 0) {
        $pkg = $candRows | Export-Excel -ExcelPackage $pkg -WorksheetName 'Candidates' `
            -AutoSize -AutoFilter -FreezeTopRow -PassThru
        _ApplyHeaderStyle -Worksheet $pkg.Workbook.Worksheets['Candidates'] -ColumnCount 15
    } else {
        @([pscustomobject]@{ Note = 'No candidates matched the current filters.' }) |
            Export-Excel -ExcelPackage $pkg -WorksheetName 'Candidates' -AutoSize -PassThru | Out-Null
    }

    # ---- Sheet 3: Requisitions -----------------------------------------
    $reqRows = foreach ($j in $filteredJobs) {
        $candCount   = @($filteredCands | Where-Object jobReqId -eq $j.id).Count
        $hiredCount  = @($filteredCands | Where-Object { $_.jobReqId -eq $j.id -and $_.stage -eq 'Hired' }).Count
        [pscustomobject][ordered]@{
            ReqNumber     = $j.reqNumber
            Title         = $j.title
            Department    = $j.department
            Location      = $j.location
            HiringManager = $j.hiringManager
            Status        = $j.status
            Openings      = $j.openings
            Candidates    = $candCount
            Hired         = $hiredCount
            Created       = $j.createdDate
            Target        = $j.targetHireDate
        }
    }
    if ($reqRows.Count -gt 0) {
        $pkg = $reqRows | Export-Excel -ExcelPackage $pkg -WorksheetName 'Requisitions' `
            -AutoSize -AutoFilter -FreezeTopRow -PassThru
        _ApplyHeaderStyle -Worksheet $pkg.Workbook.Worksheets['Requisitions'] -ColumnCount 11
    }

    # ---- Sheet 4: Funnel -----------------------------------------------
    $funnelRows = foreach ($s in 'New','Screening','Interview','Offer','Hired','Rejected') {
        [pscustomobject][ordered]@{
            Stage = $s
            Count = @($filteredCands | Where-Object stage -eq $s).Count
        }
    }
    $pkg = $funnelRows | Export-Excel -ExcelPackage $pkg -WorksheetName 'Funnel' -AutoSize -PassThru
    _ApplyHeaderStyle -Worksheet $pkg.Workbook.Worksheets['Funnel'] -ColumnCount 2

    # ---- Sheet 5: Hires by Req -----------------------------------------
    # Always emit both Hires and Candidates columns so the schema is stable.
    # Sort by Hires desc, then Candidates desc. Top 7.
    $hbr = foreach ($j in $filteredJobs) {
        $candCnt  = @($filteredCands | Where-Object jobReqId -eq $j.id).Count
        $hireCnt  = @($filteredCands | Where-Object { $_.jobReqId -eq $j.id -and $_.stage -eq 'Hired' }).Count
        if ($candCnt -eq 0 -and $hireCnt -eq 0) { continue }
        [pscustomobject][ordered]@{
            ReqNumber  = $j.reqNumber
            Title      = $j.title
            Hires      = $hireCnt
            Candidates = $candCnt
        }
    }
    $hbr = @($hbr | Sort-Object @{Expression={[int]$_.Hires};Descending=$true},
                                @{Expression={[int]$_.Candidates};Descending=$true} |
                    Select-Object -First 7)
    if ($hbr.Count -gt 0) {
        $pkg = $hbr | Export-Excel -ExcelPackage $pkg -WorksheetName 'Hires by Req' -AutoSize -PassThru
        _ApplyHeaderStyle -Worksheet $pkg.Workbook.Worksheets['Hires by Req'] -ColumnCount 4
    }

    # ---- Sheet 6: Avg Match by Kit -------------------------------------
    $kitRows = @()
    foreach ($k in @($Data.Kits)) {
        $job = $jobsById[$k.jobReqId]
        if (-not $job) { continue }
        if ($Filters -and $Filters.JobId -ne 'all' -and $job.id -ne $Filters.JobId) { continue }
        $kc = @($filteredCands | Where-Object jobReqId -eq $k.jobReqId)
        if ($kc.Count -eq 0) { continue }
        $kitScores = @()
        foreach ($cc in $kc) {
            $s = Get-CandidateScore $cc $Data
            if ($null -ne $s) { $kitScores += [int]$s }
        }
        if (@($kitScores).Count -eq 0) { continue }
        $avg = [int][Math]::Round( ($kitScores | Measure-Object -Average).Average )
        $kitRows += [pscustomobject][ordered]@{
            Kit          = $k.name
            ReqNumber    = $job.reqNumber
            Candidates   = $kc.Count
            AvgMatchPct  = $avg
        }
    }
    $kitRows = @($kitRows | Sort-Object { -$_.AvgMatchPct } | Select-Object -First 7)
    if ($kitRows.Count -gt 0) {
        $pkg = $kitRows | Export-Excel -ExcelPackage $pkg -WorksheetName 'Avg Match by Kit' -AutoSize -PassThru
        _ApplyHeaderStyle -Worksheet $pkg.Workbook.Worksheets['Avg Match by Kit'] -ColumnCount 4
    }

    # ---- Sheet 7: By Manager -------------------------------------------
    $inProg = @($filteredCands | Where-Object { $_.stage -in 'Screening','Interview','Offer' })
    $byMgr = @{}
    foreach ($c in $inProg) {
        $j = $jobsById[$c.jobReqId]
        $mgr = if ($j -and $j.hiringManager) { $j.hiringManager } else { '(unassigned)' }
        if (-not $byMgr.ContainsKey($mgr)) { $byMgr[$mgr] = 0 }
        $byMgr[$mgr]++
    }
    $mgrRows = foreach ($k in @($byMgr.Keys | Sort-Object { -$byMgr[$_] })) {
        [pscustomobject][ordered]@{ HiringManager = $k; InProgressCandidates = $byMgr[$k] }
    }
    if ($mgrRows.Count -gt 0) {
        $pkg = $mgrRows | Export-Excel -ExcelPackage $pkg -WorksheetName 'By Manager' -AutoSize -PassThru
        _ApplyHeaderStyle -Worksheet $pkg.Workbook.Worksheets['By Manager'] -ColumnCount 2
    }

    # ---- Sheet 8: Match Distribution -----------------------------------
    $bands = @(
        @{ Label='0-50';   Min=0;  Max=50  }
        @{ Label='50-60';  Min=50; Max=60  }
        @{ Label='60-70';  Min=60; Max=70  }
        @{ Label='70-80';  Min=70; Max=80  }
        @{ Label='80-90';  Min=80; Max=90  }
        @{ Label='90-100'; Min=90; Max=101 }
    )
    $distRows = foreach ($b in $bands) {
        $cnt = @($filteredCands | Where-Object {
            $s = Get-CandidateScore $_ $Data
            $null -ne $s -and $s -ge $b.Min -and $s -lt $b.Max
        }).Count
        [pscustomobject][ordered]@{ Band = $b.Label; Count = $cnt }
    }
    $pkg = $distRows | Export-Excel -ExcelPackage $pkg -WorksheetName 'Match Distribution' -AutoSize -PassThru
    _ApplyHeaderStyle -Worksheet $pkg.Workbook.Worksheets['Match Distribution'] -ColumnCount 2

    Close-ExcelPackage $pkg

    if (Get-Command Write-TrueHireLog -ErrorAction SilentlyContinue) {
        Write-TrueHireLog -Level INFO -Source 'Export-AnalyticsReport' -Message (
            "Wrote analytics report to {0} ({1} candidates, {2} reqs, {3} sheets)" -f `
            (Split-Path $Path -Leaf), $filteredCands.Count, $filteredJobs.Count, 8)
    }
    return $Path
}
