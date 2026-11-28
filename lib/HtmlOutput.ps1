<#
HtmlOutput.ps1 - printable HTML generators for the interview handout and the
rating sheet. Output is written to .\outputs\ and opened in the user's default
browser, where a top-right "Print / Save as PDF" button triggers the browser's
native print dialog. Zero third-party dependencies; the user's existing PDF
workflow (browser print) handles the actual PDF generation.

Public surface:
  - New-InterviewHandoutHtml -Kit $kit [-Job $job] [-Candidate $cand]
  - New-RatingSheetHtml      -Kit $kit -Candidate $cand [-Blank]
  - Open-TrueHireOutput     -Path "..."

Output directory lives at .\outputs\ next to TrueHire.ps1 (same convention
as .\logs\). Filenames include the candidate name + date so multiple exports
the same day don't clobber each other.
#>

# Resolve the outputs directory. Same fallback logic as Logging.ps1.
$outBase = if ($Script:RootDir) { $Script:RootDir } else { Split-Path -Parent $PSCommandPath | Split-Path -Parent }
$Script:OutputsDir = Join-Path $outBase 'outputs'
if (-not (Test-Path -LiteralPath $Script:OutputsDir)) {
    New-Item -ItemType Directory -Path $Script:OutputsDir -Force | Out-Null
}

# Shared CSS. Navy #0B2C45 headlines, orange #F5A623 accents, blue links.
# -webkit-print-color-adjust:exact keeps the header rules and anchor
# checkmarks colored when printing.
$Script:HtmlBaseStyles = @'
<style>
  * { box-sizing: border-box; }
  body { font-family: Calibri, Arial, 'Segoe UI', Verdana, sans-serif; color:#111827;
         margin:0; padding:28px 40px; background:#FFFFFF; line-height:1.42; font-size:14px;
         -webkit-print-color-adjust: exact; print-color-adjust: exact;
         text-rendering: geometricPrecision; }
  h1 { color:#0B2C45; font-weight:700; margin:0 0 4px 0; font-size:24px; }
  h2 { color:#0B2C45; font-weight:700; font-size:17px; margin:18px 0 6px 0;
       padding:5px 0; border-bottom:2px solid #CBDBEA; }
  h3 { color:#374151; font-weight:600; font-size:14px; margin:14px 0 4px 0; }
  .meta { color:#5B5B5B; font-size:12px; margin-bottom:18px; }
  .meta-grid { display:grid; grid-template-columns: 160px 1fr; gap:3px 16px;
               font-size:14px; margin:4px 0 12px 0; }
  .meta-grid .lbl { color:#374151; font-weight:600; }
  .probe { font-size:14.5px; line-height:1.5; margin:2px 0 6px 24px; color:#1F2937; }
  .guide { font-size:12.5px; line-height:1.45; margin:0 0 10px 24px; color:#374151;
           font-style:italic; border-left:3px solid #CBDBEA; padding-left:10px; }
  .qnum { display:inline-block; width:22px; color:#F5A623; font-weight:700; }
  .notes-block { margin: 4px 0 12px 24px; }
  .notes-block .note-line { border-bottom:1px solid #CBDBEA; height:18px; margin-top:6px; }
  table.rating { border-collapse:collapse; width:100%; font-size:12.5px; margin-top:10px; }
  table.rating th, table.rating td { border:1px solid #A9C1D8; padding:6px 8px; vertical-align:top; }
  table.rating th { background:#CBDBEA; color:#0B2C45; font-weight:700; text-align:center; }
  table.rating td.cat { width:22%; color:#1F2937; }
  table.rating td.box { text-align:center; width:13%; color:#F5A623; font-weight:700; font-size:14px; }
  table.rating td.box.blank { color:#A9C1D8; }
  .rec { background:#E1EEF9; padding:14px; border-radius:4px; margin:18px 0;
         border-left:4px solid #0B2C45; }
  .rec strong { color:#0B2C45; }
  .rec-text { margin:6px 0 0 0; color:#374151; }
  .footer { margin-top:32px; font-size:11px; color:#5B5B5B; border-top:1px solid #A9C1D8;
            padding-top:12px; }
  .sigrow { display:grid; grid-template-columns:1fr 1fr 1fr; gap:24px; margin-top:24px; font-size:12px; }
  .sigrow .lbl { color:#5B5B5B; font-weight:600; }
  .sigrow .field { border-bottom:1px solid #5B5B5B; height:22px; margin-top:18px; color:#374151; }
  .toolbar { position:fixed; top:12px; right:24px; }
  .toolbar button { background:#F5A623; color:#FFFFFF; border:0; padding:9px 18px;
                    border-radius:4px; font-weight:600; cursor:pointer;
                    text-transform:uppercase; letter-spacing:0.04em; font-size:12px; }
  .toolbar button:hover { background:#E07A14; }
  @media print {
    .toolbar { display:none; }
    body { padding:14px 22px; }
    h2 { page-break-after:avoid; }
    .qblock { page-break-inside:avoid; }
  }
  .qblock { margin-bottom:6px; }
  .desc { font-size:12.5px; color:#374151; margin:0 0 8px 0; font-style:italic; }
  .anchor-key { font-size:11.5px; color:#374151; margin:6px 0 0 0; }
  .anchor-key b { color:#0B2C45; }
  /* One-question-per-page handout layout */
  .qpage { page-break-after: always; }
  .qpage:last-of-type { page-break-after: auto; }
  .qpage-head { border-bottom:2px solid #CBDBEA; padding-bottom:8px; margin-bottom:14px; }
  .qpage-head .jobname { color:#0B2C45; font-weight:700; font-size:20px; }
  .qpage-head .reqnum { color:#5B5B5B; font-size:13px; margin-top:2px; }
  .qpage .qmeta { color:#5B5B5B; font-size:12px; margin-bottom:6px;
                  text-transform:uppercase; letter-spacing:0.04em; }
  .qpage .qcat { color:#0B2C45; font-weight:700; font-size:17px; margin:0 0 4px 0; }
  .qpage .qprobe { font-size:16px; line-height:1.5; margin:14px 0 8px 0; color:#1F2937; }
  .qpage .qnotes-label { font-size:12px; color:#374151; font-weight:600;
                         margin:18px 0 4px 0; }
  /* Candidate question-set flow layout: same fonts as the one-per-page handout,
     but multiple questions per page (each kept whole via page-break-inside). */
  .qflow-head { border-bottom:2px solid #CBDBEA; padding-bottom:8px; margin-bottom:16px; }
  .qflow-head .jobname { color:#0B2C45; font-weight:700; font-size:20px; }
  .qflow-head .subline { color:#5B5B5B; font-size:13px; margin-top:3px; }
  .qflow-cat { color:#0B2C45; font-weight:700; font-size:17px; margin:22px 0 4px 0;
               padding:5px 0; border-bottom:2px solid #CBDBEA; page-break-after:avoid; }
  .qflow-item { margin:0 0 16px 0; page-break-inside:avoid; }
  .qflow-probe { font-size:16px; line-height:1.5; margin:12px 0 6px 0; color:#1F2937; }
</style>
'@

function ConvertTo-HtmlText {
    <#
    HTML-escape + preserve newlines as <br/>. Returns '' for $null so the
    template strings don't print 'System.String.Empty' or worse.
    #>
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    return [System.Net.WebUtility]::HtmlEncode($Text) -replace "`r?`n", '<br/>'
}

function _Sanitize-Filename {
    <#
    Build a safe filename token from arbitrary text. Strips anything that
    isn't [A-Za-z0-9._-] and collapses runs of underscores.
    #>
    param([string]$Text)
    if (-not $Text) { return '' }
    $t = $Text -replace '[^A-Za-z0-9._-]+', '_'
    $t = $t.Trim('_')
    if ($t.Length -gt 80) { $t = $t.Substring(0, 80).TrimEnd('_','-','.') }
    return $t
}

function _Build-OutputFileName {
    param(
        [Parameter(Mandatory)][string]$Prefix,   # 'Interview' | 'Rating' | 'Rating-Blank'
        [Parameter(Mandatory)]$Kit,
        $Candidate,
        $Job
    )
    $parts = @($Prefix)
    if ($Candidate -and $Candidate.name) { $parts += (_Sanitize-Filename $Candidate.name) }
    elseif ($Job -and $Job.title)        { $parts += (_Sanitize-Filename $Job.title) }
    elseif ($Kit  -and $Kit.name)        { $parts += (_Sanitize-Filename $Kit.name) }
    $parts += (Get-Date -Format 'yyyy-MM-dd-HHmmss')
    return (($parts -join '_') + '.html')
}

function _Render-MetaGrid {
    <#
    Builds the grey metadata grid at the top of each output. Only emits rows
    for non-empty values - keeps the header tidy when fields aren't filled in.
    #>
    param([hashtable]$Fields)
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('<div class="meta-grid">')
    foreach ($k in $Fields.Keys) {
        $v = $Fields[$k]
        if (-not $v) { continue }
        [void]$sb.AppendLine("<div class='lbl'>$(ConvertTo-HtmlText $k)</div><div>$(ConvertTo-HtmlText $v)</div>")
    }
    [void]$sb.AppendLine('</div>')
    return $sb.ToString()
}

function _Resolve-ProbeText {
    <#
    Returns the probe + guide for a kit-question. Post-migration the kit
    owns these directly; the catalog parameter is kept for back-compat with
    any pre-migration callers but is no longer used.
    #>
    param($Catalog, $KitCategory, $KitQuestion)
    if (-not $KitQuestion) { return @{ probe = ''; guide = '' } }
    $probe = if ($KitQuestion.PSObject.Properties['probe']) { [string]$KitQuestion.probe } else { '' }
    $guide = if ($KitQuestion.PSObject.Properties['guide']) { [string]$KitQuestion.guide } else { '' }
    return @{ probe = $probe; guide = $guide }
}

function New-InterviewHandoutHtml {
    <#
    Generates the printable interview handout - the questions the interviewer
    takes into the room. Returns the path to the written .html file.

    -CandidateCopy produces the version handed to the candidate: it omits the
    interpretive/scoring guide under each probe (the "answers" the interviewer
    scores against) and labels the sheet a candidate copy. Everything else -
    questions, ordering, note lines - matches the interviewer's set so the two
    print runs stay in lockstep.
    #>
    param(
        [Parameter(Mandatory)]$Kit,
        $Job,
        $Candidate,
        $Catalog,
        [switch]$CandidateCopy
    )
    if (-not $Catalog) { $Catalog = $Script:ShellData.Catalog }

    $docTitle = if ($CandidateCopy) { 'Interview Question Set (Candidate Copy)' } else { 'Interview Handout' }
    $h1       = if ($CandidateCopy) { 'Interview Question Set' } else { 'Interview Question Set' }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('<!doctype html><html><head><meta charset="utf-8"/>')
    [void]$sb.AppendLine("<title>$(ConvertTo-HtmlText $docTitle)</title>")
    [void]$sb.AppendLine($Script:HtmlBaseStyles)
    [void]$sb.AppendLine('</head><body>')
    [void]$sb.AppendLine('<div class="toolbar"><button onclick="window.print()">Print / Save as PDF</button></div>')
    [void]$sb.AppendLine("<h1>$(ConvertTo-HtmlText $h1)</h1>")
    if ($CandidateCopy) {
        # Candidate copy: a minimal questions-only sheet. Header is just the
        # position + requisition number; the body is each category heading
        # followed by a bare numbered list of its questions. No category
        # descriptions, no interpretive guide, no note/writing lines.
        $jobName = if ($Job) { $Job.title } else { $Kit.name }
        $reqNum  = if ($Job) { $Job.reqNumber } else { '' }

        [void]$sb.AppendLine('<div class="qflow-head">')
        [void]$sb.AppendLine("<div class='jobname'>$(ConvertTo-HtmlText $jobName)</div>")
        if ($reqNum) { [void]$sb.AppendLine("<div class='subline'>Requisition #: $(ConvertTo-HtmlText $reqNum)</div>") }
        [void]$sb.AppendLine('</div>')

        $n = 0
        foreach ($cat in @($Kit.categories)) {
            $n++
            # Kit categories usually store only id + description (the id IS the
            # label); resolve the human label via the shared helper so the heading
            # shows e.g. "1. Problem Solving" rather than a bare number.
            $catLabel = Get-CategoryLabel -Cat $cat -Catalog $Catalog
            [void]$sb.AppendLine("<div class='qflow-cat'>$n. $(ConvertTo-HtmlText $catLabel)</div>")
            $probeNum = 0
            foreach ($q in @($cat.questions)) {
                $probeNum++
                $resolved = _Resolve-ProbeText -Catalog $Catalog -KitCategory $cat -KitQuestion $q
                [void]$sb.AppendLine("<div class='qflow-probe'><span class='qnum'>$probeNum.</span>$(ConvertTo-HtmlText $resolved.probe)</div>")
            }
        }
    }
    else {
        # Interviewer handout: ONE question per page. Each page carries only the
        # job name + requisition number, then the category + its description,
        # the question, the interpretive guide, and blank note lines.
        $jobName = if ($Job) { $Job.title } else { $Kit.name }
        $reqNum  = if ($Job) { $Job.reqNumber } else { '' }

        # Flatten to a single ordered list of questions so numbering runs 1..N
        # across the whole kit (one page each).
        $total = 0
        foreach ($cat in @($Kit.categories)) { $total += @($cat.questions).Count }

        $qIndex = 0
        foreach ($cat in @($Kit.categories)) {
            $catLabel = Get-CategoryLabel -Cat $cat -Catalog $Catalog
            $catalogCat = $Catalog.categories | Where-Object id -eq $cat.id | Select-Object -First 1
            $catDesc = if ($catalogCat -and $catalogCat.description) { $catalogCat.description } else { '' }
            foreach ($q in @($cat.questions)) {
                $qIndex++
                $resolved = _Resolve-ProbeText -Catalog $Catalog -KitCategory $cat -KitQuestion $q
                [void]$sb.AppendLine('<div class="qpage">')
                [void]$sb.AppendLine('<div class="qpage-head">')
                [void]$sb.AppendLine("<div class='jobname'>$(ConvertTo-HtmlText $jobName)</div>")
                if ($reqNum) {
                    [void]$sb.AppendLine("<div class='reqnum'>Requisition #: $(ConvertTo-HtmlText $reqNum)</div>")
                }
                [void]$sb.AppendLine('</div>')
                [void]$sb.AppendLine("<div class='qmeta'>Question $qIndex of $total</div>")
                [void]$sb.AppendLine("<div class='qcat'>$(ConvertTo-HtmlText $catLabel)</div>")
                if ($catDesc) {
                    [void]$sb.AppendLine("<p class='desc'>$(ConvertTo-HtmlText $catDesc)</p>")
                }
                [void]$sb.AppendLine("<div class='qprobe'>$(ConvertTo-HtmlText $resolved.probe)</div>")
                if ($resolved.guide) {
                    [void]$sb.AppendLine("<div class='guide'><strong>Interpretive guide:</strong> $(ConvertTo-HtmlText $resolved.guide)</div>")
                }
                # Blank note lines fill the page's whitespace for handwriting.
                [void]$sb.AppendLine("<div class='qnotes-label'>Notes</div>")
                [void]$sb.AppendLine('<div class="notes-block">')
                for ($ln = 0; $ln -lt 18; $ln++) {
                    [void]$sb.AppendLine('<div class="note-line"></div>')
                }
                [void]$sb.AppendLine('</div>')
                [void]$sb.AppendLine('</div>')
            }
        }
    }

    [void]$sb.AppendLine("<div class='footer'>Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm')</div>")
    [void]$sb.AppendLine('</body></html>')

    $prefix = if ($CandidateCopy) { 'Interview-Candidate' } else { 'Interview' }
    $path = Join-Path $Script:OutputsDir (_Build-OutputFileName -Prefix $prefix -Kit $Kit -Candidate $Candidate -Job $Job)
    $sb.ToString() | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function _Render-RatingTable {
    <#
    Renders one rating table given a per-category lookup of {anchor, note} or
    $null (blank). Shared between blank, per-rater filled, and aggregated
    columns of the consolidated sheet.
    #>
    param($Kit, $Anchors, $Lookup, $Catalog, [switch]$Blank)
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('<table class="rating">')
    [void]$sb.AppendLine('<tr><th class="cat">Category</th>')
    for ($i = 0; $i -lt $Anchors.Count; $i++) {
        [void]$sb.AppendLine("<th class='box'>$i</th>")
    }
    [void]$sb.AppendLine('</tr>')
    foreach ($cat in @($Kit.categories)) {
        $entry = if ($Lookup -and $Lookup.ContainsKey($cat.id)) { $Lookup[$cat.id] } else { $null }
        $catLabel = Get-CategoryLabel -Cat $cat -Catalog $Catalog
        [void]$sb.AppendLine("<tr><td class='cat'><strong>$(ConvertTo-HtmlText $catLabel)</strong>")
        if ($entry -and $entry.note) {
            [void]$sb.AppendLine("<div style='font-size:12px;color:#374151;margin-top:4px'>$(ConvertTo-HtmlText $entry.note)</div>")
        }
        [void]$sb.AppendLine('</td>')
        for ($i = 0; $i -lt $Anchors.Count; $i++) {
            if ($Blank) {
                [void]$sb.AppendLine("<td class='box blank'>&nbsp;</td>")
            } else {
                $mark = if ($entry -and [int]$entry.anchor -eq $i) { '&#10003;' } else { '' }
                [void]$sb.AppendLine("<td class='box'>$mark</td>")
            }
        }
        [void]$sb.AppendLine('</tr>')
    }
    [void]$sb.AppendLine('</table>')
    return $sb.ToString()
}

function _Lookup-FromRaterEntry {
    <#
    Turn a rater entry's ratings PSObject into a plain hashtable keyed by
    category id, the shape _Render-RatingTable expects.
    #>
    param($Entry)
    $h = @{}
    if ($Entry -and $Entry.ratings) {
        foreach ($p in $Entry.ratings.PSObject.Properties) { $h[$p.Name] = $p.Value }
    }
    return $h
}

function New-RatingSheetHtml {
    <#
    Printable rating sheet. Three modes:
      -Blank             : empty grid + space for one rater's name/role/sig
      -RaterEntry $entry : one rater's filled submission
      (default)          : the candidate's aggregated/consolidated sheet, with
                           the aggregated anchor grid + a section per rater
    #>
    param(
        [Parameter(Mandatory)]$Kit,
        [Parameter(Mandatory)]$Candidate,
        $Job,
        $Catalog,
        $RaterEntry,
        [switch]$Blank
    )
    if (-not $Catalog) { $Catalog = $Script:ShellData.Catalog }
    $anchors = @($Catalog.anchors)

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('<!doctype html><html><head><meta charset="utf-8"/>')
    [void]$sb.AppendLine('<title>Rating Sheet</title>')
    [void]$sb.AppendLine($Script:HtmlBaseStyles)
    [void]$sb.AppendLine('</head><body>')
    [void]$sb.AppendLine('<div class="toolbar"><button onclick="window.print()">Print / Save as PDF</button></div>')

    $title =
        if     ($Blank)       { 'Interview Rating Sheet' }
        elseif ($RaterEntry)  { 'Rater Submission' }
        else                  { 'Consolidated Rating Summary' }
    [void]$sb.AppendLine("<h1>$title</h1>")

    # Header meta - common across modes
    $meta = [ordered]@{
        'Candidate'      = $Candidate.name
        'Position'       = if ($Job) { $Job.title } else { $Candidate.position }
        'Requisition #'  = if ($Job) { $Job.reqNumber } else { '' }
        'Hiring Manager' = if ($Job) { $Job.hiringManager } else { '' }
        'Interview Date' = $Candidate.interviewDate
        'Stage'          = $Candidate.stage
    }
    if ($RaterEntry) {
        $meta['Rater']      = $RaterEntry.raterName
        $meta['Rater Role'] = $RaterEntry.raterRole
        $meta['Status']     = $RaterEntry.status
    }
    [void]$sb.AppendLine((_Render-MetaGrid -Fields $meta))

    # Compact anchor legend so the printed sheet stands alone
    $keyLines = for ($i = 0; $i -lt $anchors.Count; $i++) {
        "<b>{0}</b> = {1}" -f $i, (ConvertTo-HtmlText $anchors[$i])
    }
    [void]$sb.AppendLine("<p class='anchor-key'>$($keyLines -join '  &nbsp;  ')</p>")

    if ($Blank) {
        # Blank: a single empty grid + an explicit Rater Name/Role row so
        # each interviewer's printed copy is attributable when they hand it
        # back in. Manager re-keys these into the app.
        [void]$sb.AppendLine('<h2>Rater Information</h2>')
        [void]$sb.AppendLine('<div class="sigrow">')
        [void]$sb.AppendLine("<div><div class='lbl'>Rater Name</div><div class='field'></div></div>")
        [void]$sb.AppendLine("<div><div class='lbl'>Rater Role</div><div class='field'></div></div>")
        [void]$sb.AppendLine("<div><div class='lbl'>Interview Date</div><div class='field'></div></div>")
        [void]$sb.AppendLine('</div>')
        [void]$sb.AppendLine('<h2>Skill Ratings</h2>')
        [void]$sb.AppendLine((_Render-RatingTable -Kit $Kit -Anchors $anchors -Lookup $null -Catalog $Catalog -Blank))
        [void]$sb.AppendLine('<div class="rec">')
        [void]$sb.AppendLine('<strong>Recommendation:</strong> &nbsp; &#9633; Select &nbsp; &nbsp; &#9633; Non-Select &nbsp; &mdash; &nbsp; reason: ___________________________')
        [void]$sb.AppendLine('</div>')
        [void]$sb.AppendLine('<div class="sigrow">')
        [void]$sb.AppendLine("<div><div class='lbl'>Signature</div><div class='field'></div></div>")
        [void]$sb.AppendLine("<div><div class='lbl'>Date</div><div class='field'></div></div>")
        [void]$sb.AppendLine('<div></div>')
        [void]$sb.AppendLine('</div>')
    }
    elseif ($RaterEntry) {
        # One rater's filled submission
        $lookup = _Lookup-FromRaterEntry $RaterEntry
        [void]$sb.AppendLine('<h2>Skill Ratings</h2>')
        [void]$sb.AppendLine((_Render-RatingTable -Kit $Kit -Anchors $anchors -Lookup $lookup -Catalog $Catalog))
        [void]$sb.AppendLine('<div class="rec">')
        $rec = if ($RaterEntry.recommendation) { $RaterEntry.recommendation } else { '(not yet recorded)' }
        $rea = if ($RaterEntry.recommendationReason) { $RaterEntry.recommendationReason } else { '' }
        [void]$sb.AppendLine("<strong>Recommendation:</strong> $(ConvertTo-HtmlText $rec) &nbsp; &mdash; &nbsp; $(ConvertTo-HtmlText $rea)")
        if ($RaterEntry.recommendationText) {
            [void]$sb.AppendLine("<p class='rec-text'>$(ConvertTo-HtmlText $RaterEntry.recommendationText)</p>")
        }
        [void]$sb.AppendLine('</div>')
        [void]$sb.AppendLine('<div class="sigrow">')
        [void]$sb.AppendLine("<div><div class='lbl'>Rater</div><div class='field'>$(ConvertTo-HtmlText $RaterEntry.raterName)</div></div>")
        $dateLabel = if ($RaterEntry.submittedAt) { ([datetime]$RaterEntry.submittedAt).ToString('yyyy-MM-dd') } else { '' }
        [void]$sb.AppendLine("<div><div class='lbl'>Date Submitted</div><div class='field'>$(ConvertTo-HtmlText $dateLabel)</div></div>")
        [void]$sb.AppendLine("<div><div class='lbl'>Signature</div><div class='field'>$(ConvertTo-HtmlText $RaterEntry.signature)</div></div>")
        [void]$sb.AppendLine('</div>')
    }
    else {
        # Single evaluation: the hiring manager's anchor grid + disposition.
        $entry = Get-PrimaryRaterEntry $Candidate
        [void]$sb.AppendLine('<h2>Skill Ratings</h2>')
        if (-not $entry -or $entry.status -ne 'Submitted') {
            [void]$sb.AppendLine('<p class="desc">No submitted evaluation yet.</p>')
            [void]$sb.AppendLine((_Render-RatingTable -Kit $Kit -Anchors $anchors -Lookup $null -Catalog $Catalog -Blank))
        } else {
            $lookup = _Lookup-FromRaterEntry $entry
            [void]$sb.AppendLine((_Render-RatingTable -Kit $Kit -Anchors $anchors -Lookup $lookup -Catalog $Catalog))
        }

        # Disposition (the hiring manager's call - mirrored onto the candidate)
        [void]$sb.AppendLine('<div class="rec">')
        $rec = if ($Candidate.recommendation) { $Candidate.recommendation } else { '(not yet recorded)' }
        $rea = if ($Candidate.recommendationReason) { $Candidate.recommendationReason } else { '' }
        [void]$sb.AppendLine("<strong>Final Recommendation:</strong> $(ConvertTo-HtmlText $rec) &nbsp; &mdash; &nbsp; $(ConvertTo-HtmlText $rea)")
        if ($Candidate.recommendationText) {
            [void]$sb.AppendLine("<p class='rec-text'>$(ConvertTo-HtmlText $Candidate.recommendationText)</p>")
        }
        [void]$sb.AppendLine('</div>')

        $sigName = if ($Candidate.preparedBy) { $Candidate.preparedBy } elseif ($entry) { $entry.raterName } else { '' }
        $sigRole = if ($entry -and $entry.raterRole) { $entry.raterRole } else { 'Hiring Manager' }
        [void]$sb.AppendLine('<div class="sigrow">')
        [void]$sb.AppendLine("<div><div class='lbl'>$(ConvertTo-HtmlText $sigRole)</div><div class='field'>$(ConvertTo-HtmlText $sigName)</div></div>")
        [void]$sb.AppendLine("<div><div class='lbl'>Date Prepared</div><div class='field'>$(ConvertTo-HtmlText (Get-Date -Format 'yyyy-MM-dd'))</div></div>")
        [void]$sb.AppendLine("<div><div class='lbl'>Signature</div><div class='field'>$(ConvertTo-HtmlText $Candidate.signature)</div></div>")
        [void]$sb.AppendLine('</div>')
    }

    [void]$sb.AppendLine("<div class='footer'>Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm')</div>")
    [void]$sb.AppendLine('</body></html>')

    $prefix =
        if     ($Blank)      { 'Rating-Blank' }
        elseif ($RaterEntry) { 'Rating-' + (_Sanitize-Filename $RaterEntry.raterName) }
        else                 { 'Rating' }
    $path = Join-Path $Script:OutputsDir (_Build-OutputFileName -Prefix $prefix -Kit $Kit -Candidate $Candidate -Job $Job)
    $sb.ToString() | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function Open-TrueHireOutput {
    <#
    Launches the file in whatever's registered for .html (browser by default).
    Logs the action and captions the status bar.
    #>
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        if (Get-Command Write-TrueHireLog -ErrorAction SilentlyContinue) {
            Write-TrueHireLog -Level ERROR -Source 'Open-TrueHireOutput' -Message "Output not found: $Path"
        }
        return
    }
    try {
        Start-Process $Path
        if (Get-Command Write-TrueHireLog -ErrorAction SilentlyContinue) {
            Write-TrueHireLog -Level INFO -Source 'Open-TrueHireOutput' -Message ("Opened {0}" -f (Split-Path $Path -Leaf))
        }
        if (Get-Command Set-ShellStatus -ErrorAction SilentlyContinue) {
            Set-ShellStatus -Text ("Opened {0} in your browser - use Print to save as PDF" -f (Split-Path $Path -Leaf))
        }
    } catch {
        if (Get-Command Write-TrueHireLog -ErrorAction SilentlyContinue) {
            Write-TrueHireLog -Level ERROR -Source 'Open-TrueHireOutput' -Message $_.Exception.Message -Exception $_.Exception
        }
    }
}
