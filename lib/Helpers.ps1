<#
Helpers.ps1 — UI-construction helpers used by every view. All return live WPF
objects (Border/Grid/TextBlock) ready to drop into a panel; nothing here
mutates the data model.
#>

# Re-export the same pill palette the XAML resources use. Stage colors stay
# slightly muted from req-status pills so they don't visually compete in
# candidate cards.
$Script:StatusPalette = @{
    'Active'     = @{ Bg = '#E5F4EC'; Fg = '#2A8E54' }
    'Draft'      = @{ Bg = '#EDF0F4'; Fg = '#5C6B7B' }
    'On Hold'    = @{ Bg = '#FFF1DF'; Fg = '#C77000' }
    'Closed'     = @{ Bg = '#FBE6E6'; Fg = '#B23A3A' }
    'Filled'     = @{ Bg = '#E1EEF9'; Fg = '#1565C0' }
}
$Script:StagePalette = @{
    'New'        = @{ Bg = '#EDF0F4'; Fg = '#5C6B7B' }
    'Screening'  = @{ Bg = '#E1EEF9'; Fg = '#1565C0' }
    'Interview'  = @{ Bg = '#FFF1DF'; Fg = '#C77000' }
    'Offer'      = @{ Bg = '#FFE9F3'; Fg = '#D81B60' }
    'Hired'      = @{ Bg = '#E5F4EC'; Fg = '#2A8E54' }
    'Rejected'   = @{ Bg = '#FBE6E6'; Fg = '#B23A3A' }
}

function New-StatusPill {
    <#
    Returns a Border + TextBlock styled by the status string. Falls back to the
    Draft palette so unknown values still render as something.
    #>
    param([string]$Status, [hashtable]$Palette = $Script:StatusPalette)
    $entry = $Palette[$Status]
    if (-not $entry) { $entry = $Palette['Draft'] }
    $border = New-Object System.Windows.Controls.Border
    $border.CornerRadius = '10'
    $border.Padding      = '10,2'
    $border.Background   = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($entry.Bg)))
    $border.VerticalAlignment = 'Center'
    $border.HorizontalAlignment = 'Left'
    $border.Height = 22
    $txt = New-Object System.Windows.Controls.TextBlock
    $txt.Text       = $Status
    $txt.FontSize   = 11
    $txt.FontWeight = 'SemiBold'
    $txt.VerticalAlignment = 'Center'
    $txt.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($entry.Fg)))
    $border.Child = $txt
    return $border
}

function New-StagePill {
    param([string]$Stage)
    return (New-StatusPill -Status $Stage -Palette $Script:StagePalette)
}

function Get-Initials {
    <#
    "John Smith" -> "JS". Single-word names lose to first two letters of the
    word. Used by the candidate avatar swatches in ui_4.
    #>
    param([string]$Name)
    if (-not $Name) { return '?' }
    $parts = @($Name -split '\s+' | Where-Object { $_ })
    if ($parts.Count -ge 2) {
        return ($parts[0].Substring(0,1) + $parts[-1].Substring(0,1)).ToUpper()
    }
    return $parts[0].Substring(0,[Math]::Min(2,$parts[0].Length)).ToUpper()
}

function Get-CurrentUserFromAd {
    <#
    Resolves the current Windows user's display name + title via ADSI so the
    shell header chip and dashboard welcome line can be dynamic instead of
    pinned to whatever sits in settings.json. Returns a hashtable with
    Name/FirstName/LastName/Role/Email, or $null when the lookup can't run
    (workgroup machine, no domain controller, network down, etc.). The
    caller is responsible for falling back to a generic greeting.

    Cached for the session so we don't bind to a DC more than once.
    #>
    if ($Script:_AdUserCacheSet) { return $Script:_AdUserCache }
    $Script:_AdUserCacheSet = $true
    $Script:_AdUserCache    = $null

    try {
        # USERDNSDOMAIN is populated by the Netlogon service on domain-joined
        # boxes; absent means we're on a workgroup machine and shouldn't try
        # to bind to a DC at all (the DirectorySearcher default would
        # otherwise spin on serverless rootDSE timeouts).
        if ([string]::IsNullOrWhiteSpace($env:USERDNSDOMAIN)) { return $null }
        if ([string]::IsNullOrWhiteSpace($env:USERNAME))      { return $null }

        $searcher = New-Object System.DirectoryServices.DirectorySearcher
        $searcher.Filter        = "(&(objectCategory=user)(sAMAccountName=$($env:USERNAME)))"
        $searcher.PageSize      = 1
        $searcher.SizeLimit     = 1
        $searcher.ClientTimeout = [TimeSpan]::FromSeconds(3)
        [void]$searcher.PropertiesToLoad.AddRange(@('givenname','sn','displayname','title','mail'))

        $result = $searcher.FindOne()
        if (-not $result) { return $null }

        $p = $result.Properties
        $first = if ($p['givenname'].Count)   { [string]$p['givenname'][0] }   else { '' }
        $last  = if ($p['sn'].Count)          { [string]$p['sn'][0] }          else { '' }
        $disp  = if ($p['displayname'].Count) { [string]$p['displayname'][0] } else { '' }
        $title = if ($p['title'].Count)       { [string]$p['title'][0] }       else { '' }
        $mail  = if ($p['mail'].Count)        { [string]$p['mail'][0] }        else { '' }

        $name = ''
        if ($first -or $last) { $name = ("{0} {1}" -f $first, $last).Trim() }
        elseif ($disp)        { $name = $disp.Trim() }
        if (-not $name) { return $null }

        $firstOut = if ($first) { $first } else { ($name -split '\s+')[0] }
        $Script:_AdUserCache = @{
            Name      = $name
            FirstName = $firstOut
            LastName  = $last
            Role      = $title
            Email     = $mail
        }
        return $Script:_AdUserCache
    } catch {
        if (Get-Command Write-TrueHireLog -ErrorAction SilentlyContinue) {
            Write-TrueHireLog -Level INFO -Source 'Get-CurrentUserFromAd' `
                -Message ('AD lookup unavailable; using fallback identity: ' + $_.Exception.Message)
        }
        return $null
    }
}

function New-Avatar {
    <#
    Circular initials chip. $Size scales the whole control; font tracks ~38% of
    the diameter so initials don't crowd the edge.
    #>
    param([string]$Initials = '?', [string]$ColorHex = '#1E88E5', [double]$Size = 40)
    $border = New-Object System.Windows.Controls.Border
    $border.Width  = $Size
    $border.Height = $Size
    $border.CornerRadius = ($Size/2)
    $border.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($ColorHex)))
    $txt = New-Object System.Windows.Controls.TextBlock
    $txt.Text = $Initials
    $txt.Foreground = [System.Windows.Media.Brushes]::White
    $txt.FontWeight = 'Bold'
    $txt.FontSize = [Math]::Max(10,[int]($Size*0.38))
    $txt.HorizontalAlignment = 'Center'
    $txt.VerticalAlignment   = 'Center'
    $border.Child = $txt
    return $border
}

function New-MiniBarChart {
    <#
    Horizontal-bar mini-chart for dashboard / analytics. $Series is an array of
    @{ Label='...'; Value=N; Color='#hex' } hashtables. Bars share a max for a
    fair visual comparison.
    #>
    param([array]$Series, [double]$RowHeight = 22, [double]$LabelWidth = 130, [double]$BarMaxWidth = 220)
    $panel = New-Object System.Windows.Controls.StackPanel
    $panel.Orientation = 'Vertical'
    if (-not $Series -or $Series.Count -eq 0) { return $panel }
    # Measure-Object -Property doesn't work against Hashtable in PS 5.1; loop.
    $max = 0
    foreach ($it in $Series) { if ($it.Value -gt $max) { $max = $it.Value } }
    if ($max -le 0) { $max = 1 }
    foreach ($item in $Series) {
        $row = New-Object System.Windows.Controls.Grid
        $row.Margin = '0,0,0,8'
        $row.Height = $RowHeight
        $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = ([System.Windows.GridLength]::new($LabelWidth))
        $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = '*'
        $c3 = New-Object System.Windows.Controls.ColumnDefinition; $c3.Width = 'Auto'
        [void]$row.ColumnDefinitions.Add($c1); [void]$row.ColumnDefinitions.Add($c2); [void]$row.ColumnDefinitions.Add($c3)

        $lbl = New-Object System.Windows.Controls.TextBlock
        $lbl.Text = $item.Label
        $lbl.FontSize = 12
        $lbl.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#2C3E50')))
        $lbl.VerticalAlignment = 'Center'
        [System.Windows.Controls.Grid]::SetColumn($lbl, 0)
        [void]$row.Children.Add($lbl)

        $bg = New-Object System.Windows.Controls.Border
        $bg.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#EDF0F4')))
        $bg.Height = 8
        $bg.CornerRadius = '4'
        $bg.VerticalAlignment = 'Center'
        [System.Windows.Controls.Grid]::SetColumn($bg, 1)
        [void]$row.Children.Add($bg)

        $fill = New-Object System.Windows.Controls.Border
        $fill.Height = 8
        $fill.CornerRadius = '4'
        $fill.HorizontalAlignment = 'Left'
        $fill.VerticalAlignment = 'Center'
        $fill.Width = [Math]::Max(4, $BarMaxWidth * ([double]$item.Value / [double]$max))
        $color = if ($item.Color) { $item.Color } else { '#1E88E5' }
        $fill.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($color)))
        [System.Windows.Controls.Grid]::SetColumn($fill, 1)
        [void]$row.Children.Add($fill)

        $val = New-Object System.Windows.Controls.TextBlock
        $val.Text = "$($item.Value)"
        $val.FontSize = 12
        $val.FontWeight = 'SemiBold'
        $val.Margin = '10,0,0,0'
        $val.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#0B2C45')))
        $val.VerticalAlignment = 'Center'
        [System.Windows.Controls.Grid]::SetColumn($val, 2)
        [void]$row.Children.Add($val)

        [void]$panel.Children.Add($row)
    }
    return $panel
}

function New-FunnelChart {
    <#
    Tapered funnel for "Candidates by Stage" on the dashboard. Each rung is a
    Border whose width tracks the count proportionally to the largest stage.
    The label tucks to the right with the raw number.
    #>
    param([array]$Stages, [double]$MaxWidth = 280)
    $panel = New-Object System.Windows.Controls.StackPanel
    $panel.Orientation = 'Vertical'
    if (-not $Stages -or $Stages.Count -eq 0) { return $panel }
    # Measure-Object -Property doesn't accept Hashtable members in PS 5.1.
    $max = 0
    foreach ($s in $Stages) { if ($s.Value -gt $max) { $max = $s.Value } }
    if ($max -le 0) { $max = 1 }
    foreach ($s in $Stages) {
        $row = New-Object System.Windows.Controls.Grid
        $row.Margin = '0,0,0,4'
        $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = '*'
        $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = 'Auto'
        [void]$row.ColumnDefinitions.Add($c1); [void]$row.ColumnDefinitions.Add($c2)

        $bar = New-Object System.Windows.Controls.Border
        $bar.Height = 28
        $bar.CornerRadius = '4'
        $bar.HorizontalAlignment = 'Center'
        $bar.Width = [Math]::Max(40, $MaxWidth * ([double]$s.Value / [double]$max))
        $color = if ($s.Color) { $s.Color } else { '#1E88E5' }
        $bar.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($color)))
        $inner = New-Object System.Windows.Controls.TextBlock
        $inner.Text = $s.Label
        $inner.HorizontalAlignment = 'Center'
        $inner.VerticalAlignment   = 'Center'
        $inner.Foreground = [System.Windows.Media.Brushes]::White
        $inner.FontWeight = 'SemiBold'
        $inner.FontSize = 12
        $bar.Child = $inner
        [System.Windows.Controls.Grid]::SetColumn($bar, 0)
        [void]$row.Children.Add($bar)

        $val = New-Object System.Windows.Controls.TextBlock
        $val.Text = "$($s.Value)"
        $val.Margin = '12,0,4,0'
        $val.FontWeight = 'Bold'
        $val.FontSize = 13
        $val.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#0B2C45')))
        $val.VerticalAlignment = 'Center'
        [System.Windows.Controls.Grid]::SetColumn($val, 1)
        [void]$row.Children.Add($val)

        [void]$panel.Children.Add($row)
    }
    return $panel
}

function Get-CategoryLabel {
    <#
    Human label for a category object. Kit categories often store only id +
    description (the id IS the label, e.g. "Problem Solving"); only custom kit
    categories carry an explicit name. Resolution order: explicit name ->
    catalog displayName by id -> raw id. $Catalog is passed in (not read from
    $Script: scope) because script scope doesn't share across dot-sourced files.
    #>
    param($Cat, $Catalog)
    if (-not $Cat) { return '' }
    if ($Cat.PSObject.Properties['name'] -and $Cat.name) { return [string]$Cat.name }
    if ($Catalog -and $Catalog.categories) {
        $cz = $Catalog.categories | Where-Object id -eq $Cat.id | Select-Object -First 1
        if ($cz -and $cz.displayName) { return [string]$cz.displayName }
    }
    return [string]$Cat.id
}

function ConvertTo-Ordinal {
    <#
    English ordinal for a positive integer: 1 -> "1st", 2 -> "2nd",
    3 -> "3rd", 4 -> "4th" ... The 11th/12th/13th are "th" exceptions even
    though they end in 1/2/3, so check the last TWO digits first.
    #>
    param([int]$N)
    $mod100 = $N % 100
    if ($mod100 -ge 11 -and $mod100 -le 13) { return ("{0}th" -f $N) }
    switch ($N % 10) {
        1 { return ("{0}st" -f $N) }
        2 { return ("{0}nd" -f $N) }
        3 { return ("{0}rd" -f $N) }
        default { return ("{0}th" -f $N) }
    }
}

function Get-CandidateRankInfo {
    <#
    Per-job ordinal rank for a candidate. Ranks $Candidate against every other
    candidate sharing its jobReqId, using Get-CandidateScore. Only RATED
    candidates (non-null score) get a place and count toward the pool size;
    unrated ones are excluded. Ties share a place (standard competition
    ranking): scores 100,80,80,60 -> places 1,2,2,4.

    Returns @{ Place=<int>; Pool=<int>; Display="<ordinal> of <Pool>" }
    or $null when $Candidate has no Submitted score.
    #>
    param($Candidate, $Data)
    if (-not $Candidate) { return $null }

    # Score every candidate in the same job; keep only the rated ones.
    $jobId = $Candidate.jobReqId
    $rated = @()
    foreach ($c in @($Data.Candidates)) {
        if ($c.jobReqId -ne $jobId) { continue }
        $sc = Get-CandidateScore $c $Data
        if ($null -ne $sc) { $rated += [pscustomobject]@{ Id = $c.id; Score = [int]$sc } }
    }
    if ($rated.Count -eq 0) { return $null }

    # Sort desc; assign shared place (place = 1-based position of the first row
    # holding that score). Walk in order, bumping place only when the score drops.
    $sorted = @($rated | Sort-Object Score -Descending)
    $pool = $sorted.Count
    $place = 1
    $prevScore = $null
    $myPlace = $null
    for ($i = 0; $i -lt $pool; $i++) {
        if ($null -ne $prevScore -and $sorted[$i].Score -lt $prevScore) { $place = $i + 1 }
        if ($sorted[$i].Id -eq $Candidate.id) { $myPlace = $place }
        $prevScore = $sorted[$i].Score
    }
    if ($null -eq $myPlace) { return $null }   # candidate itself is unrated

    return @{
        Place   = $myPlace
        Pool    = $pool
        Display = ("{0} of {1}" -f (ConvertTo-Ordinal $myPlace), $pool)
    }
}

function Get-CandidateScore {
    <#
    Computed match score from the candidate's Submitted rater anchors.

    Anchors run 0..5: 5 = strongest evidence (100) .. 1 = weakest real rating
    (20). 0 (insufficient) and -1 (unrated) are missing data and excluded.

    Ratings are grouped by category, each category averaged, then combined as a
    WEIGHTED mean using the candidate's kit category weights (resolved via
    jobReqId -> Get-KitForJob when -Data is supplied). A category's weight
    defaults to 1 when it is absent from the kit or carries no weight, so the
    weighted mean renormalizes naturally across only the rated categories.

    -Data omitted (or kit not found) => every weight is 1 => the score equals
    the equal-weighted mean of per-category scores. Under the single-evaluation
    model (one rater, one cell per category) that is identical to the old flat
    cell mean — the change is score-preserving until a non-uniform weight is set.

    Returns:
        [int] 0..100  -- at least one Submitted rated category
        $null         -- no Submitted ratings yet (UI should show "--")
    #>
    param($Candidate, $Data)
    if (-not $Candidate)              { return $null }
    if (-not $Candidate.raterEntries) { return $null }

    # Group cell scores by category across all Submitted rater entries.
    $byCat = @{}
    foreach ($r in @($Candidate.raterEntries)) {
        if ($r.status -ne 'Submitted') { continue }
        if (-not $r.ratings)           { continue }
        foreach ($p in $r.ratings.PSObject.Properties) {
            $v = $p.Value
            if (-not $v) { continue }
            $anchor = $null
            if ($v.PSObject.Properties['anchor']) { $anchor = $v.anchor }
            if ($null -eq $anchor) { continue }
            $a = [int]$anchor
            if ($a -lt 1 -or $a -gt 5) { continue }   # 0 / -1 excluded as missing
            $catId = [string]$p.Name
            if (-not $byCat.ContainsKey($catId)) { $byCat[$catId] = @() }
            $byCat[$catId] += ($a * 20)
        }
    }
    if ($byCat.Keys.Count -eq 0) { return $null }

    # Mean score per category.
    $catScore = @{}
    foreach ($cid in @($byCat.Keys)) {
        $catScore[$cid] = ($byCat[$cid] | Measure-Object -Average).Average
    }

    # Category weights from the candidate's kit (default 1 each).
    $weights = @{}
    if ($Data) {
        $kit = Get-KitForJob $Data $Candidate.jobReqId
        if ($kit -and $kit.categories) {
            foreach ($cat in @($kit.categories)) {
                $wv = 1.0
                if ($cat.PSObject.Properties['weight'] -and $null -ne $cat.weight) {
                    $wv = [double]$cat.weight
                    if ($wv -lt 0) { $wv = 0 }
                }
                $weights[[string]$cat.id] = $wv
            }
        }
    }

    # Weighted mean over rated categories; missing weight => 1.
    $wsum = 0.0; $acc = 0.0
    foreach ($cid in @($catScore.Keys)) {
        $w = if ($weights.ContainsKey($cid)) { $weights[$cid] } else { 1.0 }
        $acc  += $w * $catScore[$cid]
        $wsum += $w
    }
    if ($wsum -le 0) {
        # Every rated category weighted 0 -> avoid divide-by-zero; fall back to
        # an equal-weighted mean so the score never vanishes.
        return [int][Math]::Round( (@($catScore.Values) | Measure-Object -Average).Average )
    }
    return [int][Math]::Round( $acc / $wsum )
}

function Compute-Metrics {
    <#
    Single rollup the dashboard + analytics views both consume. Keeps math in
    one place so KPIs in both screens never drift.

    OverallMatchPct now derives from Get-CandidateScore (real ratings,
    not manager-entered guesses) and averages ONLY candidates with at
    least one Submitted rated cell. Unranked candidates don't drag the
    average down to zero. RankedCandidates surfaces the denominator so
    the UI can show "72% (1 ranked)" instead of just "72%".
    #>
    param($Data)
    $jobs   = @($Data.Jobs)
    $cands  = @($Data.Candidates)
    $active = @($jobs | Where-Object status -eq 'Active')
    $hired  = @($cands | Where-Object stage -eq 'Hired')
    $advanced = @($cands | Where-Object { $_.stage -in 'Interview','Offer','Hired' })

    $stageCounts = [ordered]@{}
    foreach ($s in 'New','Screening','Interview','Offer','Hired','Rejected') {
        $stageCounts[$s] = @($cands | Where-Object stage -eq $s).Count
    }
    $statusCounts = [ordered]@{}
    foreach ($s in 'Active','Draft','On Hold','Closed','Filled') {
        $statusCounts[$s] = @($jobs | Where-Object status -eq $s).Count
    }
    # Derived match scores; unrated candidates excluded.
    $scores = @()
    foreach ($c in $cands) {
        $s = Get-CandidateScore $c $Data
        if ($null -ne $s) { $scores += [int]$s }
    }
    $avgScore = if (@($scores).Count -gt 0) {
        [int][Math]::Round( ($scores | Measure-Object -Average).Average )
    } else { $null }
    return [pscustomobject]@{
        ActiveReqs        = $active.Count
        TotalReqs         = $jobs.Count
        TotalCandidates   = $cands.Count
        Advanced          = $advanced.Count
        Hired             = $hired.Count
        OverallMatchPct   = $avgScore        # $null when no candidate has been rated
        RankedCandidates  = @($scores).Count # denominator for "(n ranked)" caption
        StageCounts       = $stageCounts
        StatusCounts      = $statusCounts
    }
}

function Find-RecentActivity {
    <#
    Synthesizes a recent-activity feed from modifiedDate / appliedDate. Keeps
    the dashboard list lively without needing a real audit log yet.
    #>
    param($Data, [int]$Take = 6)
    $events = New-Object System.Collections.Generic.List[object]
    foreach ($c in $Data.Candidates) {
        $events.Add([pscustomobject]@{
            When   = [datetime]$c.appliedDate
            Text   = ("{0} applied to {1}" -f $c.name, $c.position)
            Color  = '#1E88E5'
            Icon   = 'P'
        })
        if ($c.interviewDate) {
            $events.Add([pscustomobject]@{
                When  = [datetime]$c.interviewDate
                Text  = ("Interview scheduled with {0} ({1})" -f $c.name, $c.position)
                Color = '#F5A623'
                Icon  = 'I'
            })
        }
    }
    foreach ($j in $Data.Jobs) {
        $events.Add([pscustomobject]@{
            When  = [datetime]$j.modifiedDate
            Text  = ("Job requisition '{0}' updated" -f $j.title)
            Color = '#7E57C2'
            Icon  = 'R'
        })
    }
    return ($events | Sort-Object When -Descending | Select-Object -First $Take)
}
