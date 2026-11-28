<#
Candidates.ps1 — Candidates view (ui_4). Left rail: filters by job
requisition and pipeline stage with counts. Main: card grid of every
candidate with avatar, per-job rank badge and stage pill.
Clicking a card opens the candidate detail dialog. CandFilterAction lets
the JobReqs view pre-apply a requisition filter.
#>

$Script:CandidatesXaml = @'
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
      xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <Grid.ColumnDefinitions>
    <ColumnDefinition Width="280"/>
    <ColumnDefinition Width="*"/>
  </Grid.ColumnDefinitions>

  <Border Grid.Column="0" Background="White" BorderBrush="{StaticResource CardBorder}"
          BorderThickness="0,0,1,0">
    <Grid Margin="20,24,20,20">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
      </Grid.RowDefinitions>
      <TextBlock Grid.Row="0" Style="{StaticResource H3}" Text="Candidates" Margin="0,0,0,12"/>
      <Button x:Name="BtnNewCand" Grid.Row="1" Content="+ Add Candidate"
              Style="{StaticResource PrimaryBtn}" Margin="0,0,0,12"/>
      <TextBox x:Name="CandSearch" Grid.Row="2" Style="{StaticResource SearchField}" Margin="0,0,0,16"/>

      <StackPanel Grid.Row="3" Margin="0,0,0,12">
        <TextBlock Style="{StaticResource MicroLabel}" Text="ALL REQUISITIONS" Margin="0,0,0,8"/>
        <ScrollViewer MaxHeight="200" VerticalScrollBarVisibility="Auto">
          <StackPanel x:Name="ReqFilterPanel"/>
        </ScrollViewer>
      </StackPanel>
      <StackPanel Grid.Row="4">
        <TextBlock Style="{StaticResource MicroLabel}" Text="STATUS" Margin="0,0,0,8"/>
        <StackPanel x:Name="StageFilterPanel"/>
      </StackPanel>
    </Grid>
  </Border>

  <Grid Grid.Column="1" Margin="28,24,28,24">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
    </Grid.RowDefinitions>
    <Grid Grid.Row="0" Margin="0,0,0,18">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="Auto"/>
        <ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
      <StackPanel Grid.Column="0">
        <TextBlock x:Name="CandTitle" Style="{StaticResource H2}" Text="All Candidates"/>
        <TextBlock x:Name="CandSub" Style="{StaticResource Caption}" Text=""/>
      </StackPanel>
      <TextBlock Grid.Column="1" Text="Sort:" Style="{StaticResource Caption}"
                 VerticalAlignment="Center" Margin="0,0,8,0"/>
      <ComboBox x:Name="CbSort" Grid.Column="2" Style="{StaticResource ComboField}" Width="130">
        <ComboBoxItem Content="Rank" IsSelected="True"/>
        <ComboBoxItem Content="Last Updated"/>
        <ComboBoxItem Content="Name"/>
      </ComboBox>
    </Grid>
    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
      <WrapPanel x:Name="CandCardHost" Orientation="Horizontal"/>
    </ScrollViewer>
  </Grid>
</Grid>
'@

# Filter state shared across renders. Every text/click handler in this view
# triggers a full Show-View rebuild, so the TextBox is recreated empty each
# time - we have to remember what the user typed here.
#
# IMPORTANT: scalars set via $Script:Name inside a .GetNewClosure() handler
# write to the closure's own scope, not this file's script scope, so the
# value is lost between successive events (verified - the search box reset
# the previous keystroke every time). Wrap state in a hashtable instead:
# hashtables mutate by reference, so $Script:CandFilters.SearchText = ...
# from any closure updates the same dictionary every render reads from.
$Script:CandFilters = @{
    JobId        = 'all'   # 'all' or job id
    Stage        = 'all'   # 'all' or stage name
    SortBy       = 'Rank'
    SearchText   = ''
}
$Script:CandFilterAction = $null

function Set-CandidateJobFilter {
    <#
    Pre-applies a job-id filter to the candidate list. Called by JobReqs.ps1's
    "View Candidates" button. Lives here (not at the caller's site) so the
    hashtable mutation is on the same $Script:CandFilters reference that
    Show-CandidatesView reads from. Cross-file $Script: state doesn't share
    across files even with dot-sourcing.
    #>
    param([string]$JobId)
    $Script:CandFilters.JobId = $JobId
}

function _CandRankBadge {
    <#
    A pill showing a candidate's per-job ordinal place ("2nd of 8"). $RankInfo
    is the Get-CandidateRankInfo hashtable, or $null for an unrated candidate
    ("Not yet rated", muted). Place 1/2/3 get gold/silver/bronze accent (a
    drawn disc + tinted pill); 4+ neutral. Medal maps to the PLACE value, so a
    tie for 2nd shows two silver badges and no bronze.
    #>
    param($RankInfo)
    if ($null -eq $RankInfo) {
        $accent = '#94A3B8'; $bg = '#F1F5F9'; $fg = '#94A3B8'; $text = 'Not yet rated'; $disc = $false
    } else {
        $text = [string]$RankInfo.Display
        switch ([int]$RankInfo.Place) {
            1       { $accent = '#C9A227'; $bg = '#FBF5DD'; $fg = '#7A6212'; $disc = $true }
            2       { $accent = '#8E99A3'; $bg = '#EFF2F4'; $fg = '#465460'; $disc = $true }
            3       { $accent = '#B0703A'; $bg = '#F7ECE2'; $fg = '#7A4D26'; $disc = $true }
            default { $accent = '#CBD5E1'; $bg = '#F1F5F9'; $fg = '#2C3E50'; $disc = $false }
        }
    }
    $b = New-Object System.Windows.Controls.Border
    $b.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($bg)))
    $b.CornerRadius = '10'
    $b.Padding = '10,5'
    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'
    if ($disc) {
        $dot = New-Object System.Windows.Shapes.Ellipse
        $dot.Width = 10; $dot.Height = 10
        $dot.VerticalAlignment = 'Center'
        $dot.Margin = '0,0,7,0'
        $dot.Fill = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($accent)))
        [void]$row.Children.Add($dot)
    }
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $text
    $t.FontSize = 13
    $t.FontWeight = 'SemiBold'
    $t.VerticalAlignment = 'Center'
    $t.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($fg)))
    [void]$row.Children.Add($t)
    $b.Child = $row
    return $b
}

function _CandCard {
    <#
    Single candidate card. ~280px wide so 3-4 fit per row at common widths;
    keeps the mockup's compact grid feel.
    #>
    param($Cand, $Job)
    $card = New-Object System.Windows.Controls.Border
    $card.Background = 'White'
    $card.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#E4E8EF')))
    $card.BorderThickness = '1'
    $card.CornerRadius = '10'
    $card.Padding = '16'
    $card.Margin = '0,0,16,16'
    $card.Width = 280
    $card.Cursor = 'Hand'

    $s = New-Object System.Windows.Controls.StackPanel

    # Header: avatar + name + star
    $top = New-Object System.Windows.Controls.Grid
    $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = 'Auto'
    $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = '*'
    $c3 = New-Object System.Windows.Controls.ColumnDefinition; $c3.Width = 'Auto'
    [void]$top.ColumnDefinitions.Add($c1); [void]$top.ColumnDefinitions.Add($c2); [void]$top.ColumnDefinitions.Add($c3)

    $av = New-Avatar -Initials (Get-Initials $Cand.name) -ColorHex $Cand.avatarColor -Size 44
    $av.Margin = '0,0,10,0'
    [System.Windows.Controls.Grid]::SetColumn($av, 0)
    [void]$top.Children.Add($av)

    $names = New-Object System.Windows.Controls.StackPanel
    $names.VerticalAlignment = 'Center'
    $n = New-Object System.Windows.Controls.TextBlock
    $n.Text = $Cand.name; $n.FontWeight = 'SemiBold'; $n.FontSize = 14
    $n.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#0B2C45')))
    [void]$names.Children.Add($n)
    $sub = New-Object System.Windows.Controls.TextBlock
    $sub.Text = $Cand.position
    $sub.FontSize = 11
    $sub.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#6B7B8C')))
    [void]$names.Children.Add($sub)
    [System.Windows.Controls.Grid]::SetColumn($names, 1)
    [void]$top.Children.Add($names)

    $star = New-Object System.Windows.Controls.TextBlock
    $star.Text = "☆"; $star.FontSize = 18
    $star.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#94A3B8')))
    $star.VerticalAlignment = 'Top'
    [System.Windows.Controls.Grid]::SetColumn($star, 2)
    [void]$top.Children.Add($star)

    [void]$s.Children.Add($top)

    # Applied / job number row
    $jobLine = New-Object System.Windows.Controls.TextBlock
    # `if` is a statement, not an expression in arg lists; $(...) wraps it.
    $reqLabel = if ($Job) { $Job.reqNumber } else { '#-' }
    $appliedFmt = ([datetime]$Cand.appliedDate).ToString('MMM d, yyyy')
    $jobLine.Text = "{0} - applied {1}" -f $reqLabel, $appliedFmt
    $jobLine.FontSize = 11
    $jobLine.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#94A3B8')))
    $jobLine.Margin = '0,8,0,4'
    [void]$s.Children.Add($jobLine)

    # Per-job ordinal rank badge (replaces the old %-ring + score bar). The
    # underlying 0..100 score still decides placement; see Get-CandidateRankInfo.
    $rankBox = New-Object System.Windows.Controls.StackPanel
    $rankBox.Margin = '0,10,0,0'
    $lbl = New-Object System.Windows.Controls.TextBlock
    $lbl.Text = 'Rank'
    $lbl.FontSize = 11
    $lbl.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#6B7B8C')))
    [void]$rankBox.Children.Add($lbl)
    $rankInfo = Get-CandidateRankInfo $Cand $Script:ShellData
    $badge = _CandRankBadge $rankInfo
    $badge.Margin = '0,6,0,0'
    $badge.HorizontalAlignment = 'Left'
    [void]$rankBox.Children.Add($badge)
    [void]$s.Children.Add($rankBox)

    # Stage pill
    $pill = New-StagePill -Stage $Cand.stage
    $pill.Margin = '0,12,0,0'
    [void]$s.Children.Add($pill)

    # Bottom: profile / advance buttons
    $btnRow = New-Object System.Windows.Controls.Grid
    $btnRow.Margin = '0,12,0,0'
    $b1 = New-Object System.Windows.Controls.ColumnDefinition; $b1.Width = '*'
    $b2 = New-Object System.Windows.Controls.ColumnDefinition; $b2.Width = '*'
    [void]$btnRow.ColumnDefinitions.Add($b1); [void]$btnRow.ColumnDefinitions.Add($b2)
    $bV = New-Object System.Windows.Controls.Button
    $bV.Content = 'View Profile'
    $bV.Style = $Script:Shell.FindResource('GhostBtn')
    $bV.Margin = '0,0,4,0'
    $bV.Tag = $Cand.id
    $bV.Add_Click({ Show-CandidateDetail $args[0].Tag }.GetNewClosure())
    [System.Windows.Controls.Grid]::SetColumn($bV, 0)
    [void]$btnRow.Children.Add($bV)
    $bA = New-Object System.Windows.Controls.Button
    $bA.Content = 'Advance'
    $bA.Style = $Script:Shell.FindResource('BlueBtn')
    $bA.Margin = '4,0,0,0'
    $bA.Tag = $Cand.id
    # No .GetNewClosure() - inside a closure $Script:ShellData reads as $null
    # in handlers that fire after the closure is detached from its creation
    # call stack. Drop the closure and read the candidate id off the sender's
    # Tag (set above).
    $bA.Add_Click({
        param($sender, $eventArgs)
        $cid = $sender.Tag
        $c = $Script:ShellData.Candidates | Where-Object id -eq $cid | Select-Object -First 1
        if ($c) {
            $order = 'New','Screening','Interview','Offer','Hired'
            $i = [Array]::IndexOf($order, $c.stage)
            if ($i -ge 0 -and $i -lt $order.Count-1) { $c.stage = $order[$i+1] }
            Save-Candidates $Script:ShellData
            Show-View 'TabCandidates'
        }
    })
    [System.Windows.Controls.Grid]::SetColumn($bA, 1)
    [void]$btnRow.Children.Add($bA)
    [void]$s.Children.Add($btnRow)

    $card.Child = $s
    $card.Tag = $Cand.id
    $card.Add_MouseLeftButtonUp({
        param($snd,$e)
        # Skip if a child button absorbed the click already
        if ($e.OriginalSource -is [System.Windows.Controls.Button]) { return }
        Show-CandidateDetail $snd.Tag
    }.GetNewClosure())
    return $card
}

function _StageFilterBtn {
    param([string]$Stage, [int]$Count)
    $b = New-Object System.Windows.Controls.Border
    $b.Background = if ($Stage -eq $Script:CandFilters.Stage) { (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#E1EEF9'))) } else { 'Transparent' }
    $b.CornerRadius = '6'
    $b.Padding = '10,6'
    $b.Margin = '0,0,0,4'
    $b.Cursor = 'Hand'
    $b.Tag = $Stage
    $g = New-Object System.Windows.Controls.Grid
    $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = '*'
    $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = 'Auto'
    [void]$g.ColumnDefinitions.Add($c1); [void]$g.ColumnDefinitions.Add($c2)
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = if ($Stage -eq 'all') { 'All Stages' } else { $Stage }
    $t.FontSize = 12.5
    $t.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#0B2C45')))
    [System.Windows.Controls.Grid]::SetColumn($t, 0)
    [void]$g.Children.Add($t)
    $cnt = New-Object System.Windows.Controls.TextBlock
    $cnt.Text = "$Count"
    $cnt.FontSize = 11
    $cnt.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#6B7B8C')))
    [System.Windows.Controls.Grid]::SetColumn($cnt, 1)
    [void]$g.Children.Add($cnt)
    $b.Child = $g
    # No GetNewClosure - inside a closure $Script:CandFilters can shadow to a
    # half-initialised PSCustomObject (only the property we just wrote),
    # and the subsequent Show-View re-render then throws "property Stage
    # cannot be found" when it reads other keys. param($sender,$e) keeps
    # the lookup dynamic and hits the real file-scope hashtable.
    $b.Add_MouseLeftButtonUp({
        param($sender, $eventArgs)
        $Script:CandFilters.Stage = $sender.Tag
        Show-View 'TabCandidates'
    })
    return $b
}

function _ReqFilterBtn {
    param([string]$JobId, [string]$Label, [int]$Count)
    $b = New-Object System.Windows.Controls.Border
    $b.Background = if ($JobId -eq $Script:CandFilters.JobId) { (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#E1EEF9'))) } else { 'Transparent' }
    $b.CornerRadius = '6'
    $b.Padding = '10,6'
    $b.Margin = '0,0,0,4'
    $b.Cursor = 'Hand'
    $b.Tag = $JobId
    $g = New-Object System.Windows.Controls.Grid
    $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = '*'
    $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = 'Auto'
    [void]$g.ColumnDefinitions.Add($c1); [void]$g.ColumnDefinitions.Add($c2)
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $Label
    $t.FontSize = 12.5
    $t.TextTrimming = 'CharacterEllipsis'
    $t.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#0B2C45')))
    [System.Windows.Controls.Grid]::SetColumn($t, 0)
    [void]$g.Children.Add($t)
    $cnt = New-Object System.Windows.Controls.TextBlock
    $cnt.Text = "$Count"
    $cnt.FontSize = 11
    $cnt.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#6B7B8C')))
    [System.Windows.Controls.Grid]::SetColumn($cnt, 1)
    [void]$g.Children.Add($cnt)
    $b.Child = $g
    # See matching comment in _StageFilterBtn re: dropped GetNewClosure.
    $b.Add_MouseLeftButtonUp({
        param($sender, $eventArgs)
        $Script:CandFilters.JobId = $sender.Tag
        Show-View 'TabCandidates'
    })
    return $b
}

function _RefilterCandidateGrid {
    <#
    Rebuilds JUST the candidate card grid + count label from $Script:CandFilters,
    leaving the rest of the view (search box, sort dropdown, rail filters) in
    place. Called both by the initial Show-CandidatesView render and by the
    search-box TextChanged handler so typing doesn't tear down the very
    TextBox the user is typing in (which was causing fast-typed letters to
    drop because they raced the tear-down/rebuild cycle).
    #>
    param($Root)
    $data = $Script:ShellData
    if (-not $data) { return }

    $list = @($data.Candidates)
    if ($Script:CandFilters.JobId -ne 'all') {
        $list = @($list | Where-Object jobReqId -eq $Script:CandFilters.JobId)
    }
    if ($Script:CandFilters.Stage -ne 'all') {
        $list = @($list | Where-Object stage -eq $Script:CandFilters.Stage)
    }
    $q = $Script:CandFilters.SearchText
    if ($q) {
        $list = @($list | Where-Object {
            $_.name -like "*$q*" -or $_.position -like "*$q*" -or $_.email -like "*$q*"
        })
    }
    $sort = $Script:CandFilters.SortBy
    $list = switch ($sort) {
        'Rank'         {
            # Sort by computed score desc; unrated ($null score) candidates
            # fall to the end. Sort-Object treats $null as smaller than any
            # number, so -Descending puts numerics first and nulls last.
            @($list | Sort-Object { Get-CandidateScore $_ $data } -Descending)
        }
        'Name'         { @($list | Sort-Object name) }
        default        { @($list | Sort-Object appliedDate -Descending) }
    }

    # Header text
    $titleTxt = 'All Candidates'
    if ($Script:CandFilters.JobId -ne 'all') {
        $j = Get-JobById $data $Script:CandFilters.JobId
        if ($j) { $titleTxt = "$($j.title) - Candidates" }
    }
    ($Root.FindName('CandTitle')).Text = $titleTxt
    ($Root.FindName('CandSub')).Text   = ("{0} candidates" -f $list.Count)

    # Card grid - clear, then rebuild
    $cardHost = $Root.FindName('CandCardHost')
    $cardHost.Children.Clear()
    foreach ($c in $list) {
        $j = Get-JobById $data $c.jobReqId
        [void]$cardHost.Children.Add( (_CandCard $c $j) )
    }
}

function Show-CandidatesView {
    param($Container)
    $root = [System.Windows.Markup.XamlReader]::Parse($Script:CandidatesXaml)
    [void]$Container.Children.Add($root)
    $data = $Script:ShellData

    # JobReqs view sets this hook so navigating from a job-req detail
    # auto-filters this list by that requisition.
    $Script:CandFilterAction = {
        param($JobId)
        $Script:CandFilters.JobId = $JobId
        Show-View 'TabCandidates'
    }

    # Stage filter list ------------------------------------------------------
    $stagePanel = $root.FindName('StageFilterPanel')
    $stagePanel.Children.Clear()
    [void]$stagePanel.Children.Add( (_StageFilterBtn 'all' @($data.Candidates).Count) )
    foreach ($s in 'New','Screening','Interview','Offer','Hired','Rejected') {
        $cnt = @($data.Candidates | Where-Object stage -eq $s).Count
        [void]$stagePanel.Children.Add( (_StageFilterBtn $s $cnt) )
    }

    # Req filter list --------------------------------------------------------
    $reqPanel = $root.FindName('ReqFilterPanel')
    $reqPanel.Children.Clear()
    [void]$reqPanel.Children.Add( (_ReqFilterBtn 'all' 'All Requisitions' @($data.Candidates).Count) )
    foreach ($j in $data.Jobs) {
        $cnt = @($data.Candidates | Where-Object jobReqId -eq $j.id).Count
        if ($cnt -gt 0 -or $j.status -eq 'Active') {
            [void]$reqPanel.Children.Add( (_ReqFilterBtn $j.id "$($j.title)" $cnt) )
        }
    }

    # Restore the typed text into the fresh TextBox. The view itself is no
    # longer rebuilt on every keystroke (we refilter in place), but it IS
    # rebuilt when switching tabs / clicking filter chips - so we still need
    # to put back whatever the user had typed.
    $searchBox = $root.FindName('CandSearch')
    $searchBox.Text = $Script:CandFilters.SearchText

    # Initial card render
    _RefilterCandidateGrid -Root $root

    # Wire search + sort -----------------------------------------------------
    # TextChanged refilters in place via _RefilterCandidateGrid - it does NOT
    # call Show-View, because that would tear down this very TextBox during
    # the event and drop fast-typed letters. No GetNewClosure either: same
    # scope-shadow trap as the filter buttons; param($sender,$e) keeps
    # $Script: lookups dynamic.
    $searchBox.Add_TextChanged({
        param($sender, $eventArgs)
        $Script:CandFilters.SearchText = $sender.Text
        $content = $Script:Shell.FindName('ContentHost')
        if ($content -and $content.Children.Count -gt 0) {
            _RefilterCandidateGrid -Root $content.Children[0]
        }
    })
    $sortBox = $root.FindName('CbSort')
    # Restore previous sort selection into the fresh ComboBox (rebuild
    # creates new items each render). Without this the dropdown silently
    # snaps back to "Rank" on every keystroke / filter click even
    # though the actual sort applied is whatever the user picked last.
    for ($i = 0; $i -lt $sortBox.Items.Count; $i++) {
        $label = "$($sortBox.Items[$i].Content)" -replace '^Sort:\s*',''
        if ($label -eq $Script:CandFilters.SortBy) { $sortBox.SelectedIndex = $i; break }
    }
    # No GetNewClosure - same scope-shadow trap as the filter buttons above.
    $sortBox.Add_SelectionChanged({
        param($sender, $eventArgs)
        $sel = $sender.SelectedItem
        if ($sel) {
            $t = "$($sel.Content)" -replace '^Sort:\s*',''
            # Only re-render if the value actually changed - otherwise the
            # restore-on-render above triggers SelectionChanged → infinite loop.
            if ($Script:CandFilters.SortBy -ne $t) {
                $Script:CandFilters.SortBy = $t
                Show-View 'TabCandidates'
            }
        }
    })

    # New candidate ----------------------------------------------------------
    $root.FindName('BtnNewCand').Add_Click({
        $newC = New-Candidate
        if ($Script:CandFilters.JobId -ne 'all') {
            $newC.jobReqId = $Script:CandFilters.JobId
            $j = Get-JobById $data $Script:CandFilters.JobId
            if ($j) { $newC.position = $j.title }
        }
        $data.Candidates = @($data.Candidates) + $newC
        Save-Candidates $data
        Show-CandidateDetail $newC.id
    }.GetNewClosure())
}

# ----------------------------------------------------------------------------
# Candidate detail dialog
# ----------------------------------------------------------------------------
$Script:CandDetailXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Candidate" Width="1060" Height="820"
        WindowStartupLocation="CenterOwner"
        Background="{StaticResource PageBg}" FontFamily="Segoe UI">
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="100"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <Border x:Name="HeroBorder" Grid.Row="0" Background="{StaticResource BannerFallback}">
      <Grid Margin="24,16">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <Grid x:Name="AvatarHost" Grid.Column="0" Width="60" Height="60" Margin="0,0,16,0"/>
        <StackPanel Grid.Column="1" VerticalAlignment="Center">
          <TextBlock x:Name="DlgName" Foreground="White" FontSize="22" FontWeight="Bold" Text="Candidate"/>
          <TextBlock x:Name="DlgRole" Foreground="#CBDBEA" FontSize="12" Text=""/>
        </StackPanel>
        <Border x:Name="DlgStagePillHost" Grid.Column="2" VerticalAlignment="Center"/>
      </Grid>
    </Border>
    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="24,18">
      <StackPanel>
        <UniformGrid Rows="1" Columns="2" Margin="0,0,0,12">
          <StackPanel Margin="0,0,8,0">
            <TextBlock Style="{StaticResource MicroLabel}" Text="FULL NAME" Margin="0,0,0,4"/>
            <TextBox x:Name="TbName" Style="{StaticResource Field}"/>
          </StackPanel>
          <StackPanel Margin="8,0,0,0">
            <TextBlock Style="{StaticResource MicroLabel}" Text="JOB REQUISITION" Margin="0,0,0,4"/>
            <ComboBox x:Name="CbJob" Style="{StaticResource ComboField}"/>
          </StackPanel>
        </UniformGrid>
        <UniformGrid Rows="1" Columns="2" Margin="0,0,0,12">
          <StackPanel Margin="0,0,8,0">
            <TextBlock Style="{StaticResource MicroLabel}" Text="EMAIL" Margin="0,0,0,4"/>
            <TextBox x:Name="TbEmail" Style="{StaticResource Field}"/>
          </StackPanel>
          <StackPanel Margin="8,0,0,0">
            <TextBlock Style="{StaticResource MicroLabel}" Text="PHONE" Margin="0,0,0,4"/>
            <TextBox x:Name="TbPhone" Style="{StaticResource Field}"/>
          </StackPanel>
        </UniformGrid>
        <UniformGrid Rows="1" Columns="3" Margin="0,0,0,12">
          <StackPanel Margin="0,0,8,0">
            <TextBlock Style="{StaticResource MicroLabel}" Text="STAGE" Margin="0,0,0,4"/>
            <ComboBox x:Name="CbStage" Style="{StaticResource ComboField}">
              <ComboBoxItem Content="New"/>
              <ComboBoxItem Content="Screening"/>
              <ComboBoxItem Content="Interview"/>
              <ComboBoxItem Content="Offer"/>
              <ComboBoxItem Content="Hired"/>
              <ComboBoxItem Content="Rejected"/>
            </ComboBox>
          </StackPanel>
          <StackPanel Margin="4,0,4,0">
            <TextBlock Style="{StaticResource MicroLabel}" Text="RANK" Margin="0,0,0,4"/>
            <Border BorderBrush="#CBD5E1" BorderThickness="1" CornerRadius="6"
                    Background="#F8FAFC" Padding="10,7" Height="34"
                    ToolTip="This candidate's place among the rated candidates for the same job, by derived match score (higher score = higher place). Ties share a place. Shows 'Not yet rated' until a Submitted evaluation exists.">
              <TextBlock x:Name="TbScore" VerticalAlignment="Center" FontSize="13"
                         Foreground="{StaticResource TextBody}" Text=""/>
            </Border>
          </StackPanel>
          <StackPanel Margin="8,0,0,0">
            <TextBlock Style="{StaticResource MicroLabel}" Text="RECOMMENDATION" Margin="0,0,0,4"/>
            <ComboBox x:Name="CbRec" Style="{StaticResource ComboField}">
              <ComboBoxItem Content=""/>
              <ComboBoxItem Content="Select"/>
              <ComboBoxItem Content="Non-Select"/>
            </ComboBox>
          </StackPanel>
        </UniformGrid>
        <UniformGrid Rows="1" Columns="2" Margin="0,0,0,12">
          <StackPanel Margin="0,0,8,0">
            <TextBlock Style="{StaticResource MicroLabel}" Text="APPLIED" Margin="0,0,0,4"/>
            <DatePicker x:Name="TbApplied"
                        SelectedDateFormat="Short"
                        FirstDayOfWeek="Sunday"
                        Height="34"/>
          </StackPanel>
          <StackPanel Margin="8,0,0,0">
            <TextBlock Style="{StaticResource MicroLabel}" Text="INTERVIEW DATE" Margin="0,0,0,4"/>
            <DatePicker x:Name="TbInterview"
                        SelectedDateFormat="Short"
                        FirstDayOfWeek="Sunday"
                        Height="34"/>
          </StackPanel>
        </UniformGrid>
        <StackPanel>
          <TextBlock Style="{StaticResource MicroLabel}" Text="NOTES" Margin="0,0,0,4"/>
          <TextBox x:Name="TbNotes" Style="{StaticResource MultilineField}" MinHeight="80"/>
        </StackPanel>

        <!-- ===  Interview Evaluation (hiring manager)  === -->
        <Border Style="{StaticResource Card}" Margin="0,18,0,0">
          <StackPanel>
            <TextBlock Style="{StaticResource H3}" Text="Interview Evaluation"/>
            <TextBlock Style="{StaticResource Caption}" Margin="0,0,0,8"
                       Text="The hiring manager's anchor ratings and disposition for this candidate. One evaluation per candidate."/>
            <StackPanel x:Name="EvalHost" Margin="0,4,0,0"/>
            <TextBlock x:Name="EvalEmpty" Style="{StaticResource Caption}"
                       Foreground="#94A3B8" Margin="0,4,0,0"
                       Text="Not yet evaluated. Click Rate Candidate to enter the hiring manager's ratings and disposition."/>
            <Button x:Name="BtnRateCandidate" Content="Rate Candidate"
                    Style="{StaticResource BlueBtn}"
                    HorizontalAlignment="Right" Margin="0,10,0,0"/>
          </StackPanel>
        </Border>

        <!-- ===  Final Recommendation (disposition)  === -->
        <Border Style="{StaticResource Card}" Margin="0,12,0,0">
          <StackPanel>
            <TextBlock Style="{StaticResource H3}" Text="Final Recommendation" Margin="0,0,0,4"/>
            <TextBlock Style="{StaticResource Caption}" Margin="0,0,0,10"
                       Text="The hiring manager's disposition. Kept in sync with the interview evaluation above."/>
            <UniformGrid Rows="1" Columns="2" Margin="0,0,0,12">
              <StackPanel Margin="0,0,8,0">
                <TextBlock Style="{StaticResource MicroLabel}" Text="REASON" Margin="0,0,0,4"/>
                <ComboBox x:Name="CbRecReason" Style="{StaticResource ComboField}"/>
              </StackPanel>
              <StackPanel Margin="8,0,0,0">
                <TextBlock Style="{StaticResource MicroLabel}" Text="PREPARED BY" Margin="0,0,0,4"/>
                <TextBox x:Name="TbPreparedBy" Style="{StaticResource Field}"/>
              </StackPanel>
            </UniformGrid>
            <StackPanel Margin="0,0,0,12">
              <TextBlock Style="{StaticResource MicroLabel}" Text="REASON DETAIL (for the rating sheet)" Margin="0,0,0,4"/>
              <TextBox x:Name="TbRecText" Style="{StaticResource MultilineField}" MinHeight="60"/>
            </StackPanel>
            <StackPanel>
              <TextBlock Style="{StaticResource MicroLabel}" Text="SIGNATURE" Margin="0,0,0,4"/>
              <TextBox x:Name="TbSignature" Style="{StaticResource Field}"/>
            </StackPanel>
          </StackPanel>
        </Border>
      </StackPanel>
    </ScrollViewer>
    <Border Grid.Row="2" Background="White" BorderBrush="{StaticResource CardBorder}"
            BorderThickness="0,1,0,0" Padding="20,12">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <Button x:Name="BtnPrintHandout"     Grid.Column="0" Content="Print Handout"
                Style="{StaticResource GhostBtn}" Margin="0,0,8,0"/>
        <Button x:Name="BtnPrintCandidate"   Grid.Column="1" Content="Print Candidate Set"
                Style="{StaticResource GhostBtn}" Margin="0,0,8,0"/>
        <Button x:Name="BtnPrintBlankRating" Grid.Column="2" Content="Print Blank Rating Sheet"
                Style="{StaticResource GhostBtn}" Margin="0,0,8,0"/>
        <Button x:Name="BtnPrintRating"      Grid.Column="3" Content="Print Filled Rating Sheet"
                Style="{StaticResource GhostBtn}" Margin="0,0,8,0"/>
        <Button x:Name="BtnDelete"           Grid.Column="4" Content="Delete Candidate"
                Style="{StaticResource GhostBtn}" HorizontalAlignment="Left" Foreground="#B23A3A"/>
        <StackPanel Grid.Column="5" Orientation="Horizontal">
          <Button x:Name="BtnCancel" Content="Cancel" Style="{StaticResource GhostBtn}" Margin="0,0,8,0"/>
          <Button x:Name="BtnSave"   Content="Save Changes" Style="{StaticResource PrimaryBtn}"/>
        </StackPanel>
      </Grid>
    </Border>
  </Grid>
</Window>
'@

function _BuildRatingRow {
    <#
    One row in the per-rater entry dialog. Returns a WPF Border containing
    the category name, 6 anchor radio buttons (numbered 1..6, with the full
    anchor text on hover via ToolTip), and a note textbox.

    Mutations write through to $Rating - a live reference to one entry in
    raterEntry.ratings.<categoryId> - via Tag indirection on each control.
    No GetNewClosure: $sender.Tag carries everything the handler needs.
    #>
    param($Cat, $Anchors, $Rating)

    $row = New-Object System.Windows.Controls.Border
    $row.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#EDF0F4')))
    $row.BorderThickness = '0,0,0,1'
    $row.Padding = '0,8'

    $g = New-Object System.Windows.Controls.Grid
    $cdName    = New-Object System.Windows.Controls.ColumnDefinition; $cdName.Width    = ([System.Windows.GridLength]::new(220))
    $cdAnchors = New-Object System.Windows.Controls.ColumnDefinition; $cdAnchors.Width = 'Auto'
    $cdNote    = New-Object System.Windows.Controls.ColumnDefinition; $cdNote.Width    = '*'
    [void]$g.ColumnDefinitions.Add($cdName)
    [void]$g.ColumnDefinitions.Add($cdAnchors)
    [void]$g.ColumnDefinitions.Add($cdNote)

    # Category name (left). Custom kit categories get a "CUSTOM" badge so the
    # rater can tell them apart from the standard catalog competencies.
    $nameBox = New-Object System.Windows.Controls.StackPanel
    $nameBox.VerticalAlignment = 'Center'

    # Kit categories store id + description but usually no `name` (the id is the
    # label, e.g. "Problem Solving"); only custom categories set a name. Resolve a
    # display label via the shared helper (name -> catalog displayName -> id).
    $catLabel = Get-CategoryLabel $Cat $Script:ShellData.Catalog
    $nm = New-Object System.Windows.Controls.TextBlock
    $nm.Text = $catLabel
    $nm.FontWeight = 'SemiBold'; $nm.FontSize = 13
    $nm.TextWrapping = 'Wrap'
    $nm.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#0B2C45')))
    [void]$nameBox.Children.Add($nm)

    if ($Cat.PSObject.Properties['custom'] -and $Cat.custom) {
        $badge = New-Object System.Windows.Controls.Border
        $badge.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#F5A623')))
        $badge.CornerRadius = New-Object System.Windows.CornerRadius 3
        $badge.Padding = '5,1'
        $badge.HorizontalAlignment = 'Left'
        $badge.Margin = '0,3,0,0'
        $badgeTxt = New-Object System.Windows.Controls.TextBlock
        $badgeTxt.Text = 'CUSTOM'
        $badgeTxt.FontSize = 9
        $badgeTxt.FontWeight = 'Bold'
        $badgeTxt.Foreground = [System.Windows.Media.Brushes]::White
        $badge.Child = $badgeTxt
        [void]$nameBox.Children.Add($badge)
    }
    [System.Windows.Controls.Grid]::SetColumn($nameBox, 0)
    [void]$g.Children.Add($nameBox)

    # Anchor radio buttons (middle). GroupName must be unique per row.
    $anchorPanel = New-Object System.Windows.Controls.StackPanel
    $anchorPanel.Orientation = 'Horizontal'
    $anchorPanel.Margin = '8,0,12,0'
    $groupName = 'anchor_' + ($Cat.id -replace '\W','_') + '_' + ([guid]::NewGuid().ToString('N').Substring(0,4))
    # Anchors are 0-based (0 = insufficient .. 5 = very strong evidence present).
    # The unrated sentinel is -1, so a never-rated row shows no selection.
    for ($i = 0; $i -lt $Anchors.Count; $i++) {
        $rb = New-Object System.Windows.Controls.RadioButton
        $rb.GroupName = $groupName
        $rb.Content = "$i"
        $rb.ToolTip = $Anchors[$i]
        $rb.Margin = '0,0,8,0'
        $rb.VerticalAlignment = 'Center'
        $rb.FontSize = 12
        $rb.Tag = @{ Rating = $Rating; Anchor = $i }
        if ([int]$Rating.anchor -eq $i) { $rb.IsChecked = $true }
        $rb.Add_Checked({
            param($sender, $eventArgs)
            $ctx = $sender.Tag
            $ctx.Rating.anchor = $ctx.Anchor
        })
        [void]$anchorPanel.Children.Add($rb)
    }
    [System.Windows.Controls.Grid]::SetColumn($anchorPanel, 1)
    [void]$g.Children.Add($anchorPanel)

    # Note textbox (right)
    $note = New-Object System.Windows.Controls.TextBox
    $note.Text = $Rating.note
    $note.FontSize = 12
    $note.Margin = '0,0,0,0'
    $note.Tag = $Rating
    $note.Add_TextChanged({
        param($sender, $eventArgs)
        $sender.Tag.note = $sender.Text
    })
    [System.Windows.Controls.Grid]::SetColumn($note, 2)
    [void]$g.Children.Add($note)

    $row.Child = $g
    return $row
}

function _LogRaterSnapshot {
    <#
    Diagnostic: dump every candidate's raterEntries count to the daily log
    around a delete, so we can see whether a single delete ever touches more
    than the targeted candidate (reported: "deleting one ranking cleared
    both candidates"). Safe no-op if the logger isn't loaded.
    #>
    param([string]$Phase, [string]$CandId, [string]$EntryId)
    if (-not (Get-Command Write-TrueHireLog -ErrorAction SilentlyContinue)) { return }
    $snap = (@($Script:ShellData.Candidates) | ForEach-Object {
        '{0}:{1}' -f $_.id, @($_.raterEntries).Count
    }) -join ', '
    Write-TrueHireLog -Level INFO -Source 'RaterDelete' -Message (
        "{0} cand={1} entry={2} | counts -> {3}" -f $Phase, $CandId, $EntryId, $snap)
}

function _BuildRaterListRow {
    <#
    One row in the Rater Submissions list inside the candidate detail
    dialog. Compact summary (rater name + role + status pill + score) plus
    Edit and Delete buttons. Clicking Edit opens Show-RaterEntryDialog;
    Delete asks for confirmation.
    #>
    param($Cand, $Entry)

    $b = New-Object System.Windows.Controls.Border
    $b.Background = 'White'
    $b.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#E4E8EF')))
    $b.BorderThickness = '1'
    $b.CornerRadius = '6'
    $b.Padding = '12,8'
    $b.Margin = '0,0,0,6'

    $g = New-Object System.Windows.Controls.Grid
    $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = '*'
    $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = 'Auto'
    $c3 = New-Object System.Windows.Controls.ColumnDefinition; $c3.Width = 'Auto'
    $c4 = New-Object System.Windows.Controls.ColumnDefinition; $c4.Width = 'Auto'
    [void]$g.ColumnDefinitions.Add($c1); [void]$g.ColumnDefinitions.Add($c2)
    [void]$g.ColumnDefinitions.Add($c3); [void]$g.ColumnDefinitions.Add($c4)

    # Name + role
    $nameStack = New-Object System.Windows.Controls.StackPanel
    $nameTb = New-Object System.Windows.Controls.TextBlock
    $nameTb.Text = if ($Entry.raterName) { $Entry.raterName } else { '(unnamed rater)' }
    $nameTb.FontWeight = 'SemiBold'; $nameTb.FontSize = 13
    $nameTb.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#0B2C45')))
    [void]$nameStack.Children.Add($nameTb)
    $roleTb = New-Object System.Windows.Controls.TextBlock
    $roleTb.Text = $Entry.raterRole
    $roleTb.FontSize = 11
    $roleTb.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#6B7B8C')))
    [void]$nameStack.Children.Add($roleTb)
    [System.Windows.Controls.Grid]::SetColumn($nameStack, 0)
    [void]$g.Children.Add($nameStack)

    # Status pill (Submitted / Draft)
    $pillBg = if ($Entry.status -eq 'Submitted') { '#E5F4EC' } else { '#EDF0F4' }
    $pillFg = if ($Entry.status -eq 'Submitted') { '#2A8E54' } else { '#5C6B7B' }
    $pill = New-Object System.Windows.Controls.Border
    $pill.CornerRadius = '10'; $pill.Padding = '10,2'; $pill.Margin = '12,0,12,0'
    $pill.Height = 22; $pill.VerticalAlignment = 'Center'
    $pill.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($pillBg)))
    $pillTxt = New-Object System.Windows.Controls.TextBlock
    $pillTxt.Text = $Entry.status; $pillTxt.FontSize = 11; $pillTxt.FontWeight = 'SemiBold'
    $pillTxt.VerticalAlignment = 'Center'
    $pillTxt.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($pillFg)))
    $pill.Child = $pillTxt
    [System.Windows.Controls.Grid]::SetColumn($pill, 1)
    [void]$g.Children.Add($pill)

    # Average anchor across THIS rater's scorable categories (1..5; anchor
    # 0 = insufficient and -1 = unrated are excluded). Shown as a qualitative
    # indicator - higher is stronger evidence on the V4 scale. We deliberately
    # do NOT compute a 0..100 score per the v1 methodology.
    $sum = 0.0; $n = 0
    if ($Entry.ratings) {
        foreach ($prop in $Entry.ratings.PSObject.Properties) {
            $a = [int]$prop.Value.anchor
            if ($a -ge 1 -and $a -le 5) { $sum += $a; $n++ }
        }
    }
    $avgAnchor = if ($n -gt 0) { $sum / [double]$n } else { $null }
    $anchorTb = New-Object System.Windows.Controls.TextBlock
    $anchorTb.Text = if ($null -ne $avgAnchor) { ("avg anchor {0:N1}" -f $avgAnchor) } else { '(no anchors)' }
    $anchorTb.FontSize = 11
    $anchorTb.FontWeight = 'SemiBold'
    $anchorTb.Margin = '0,0,16,0'; $anchorTb.VerticalAlignment = 'Center'
    # Color band: higher anchor (stronger evidence) trends green, lower trends red.
    $anchorColor = if     ($null -eq $avgAnchor) { '#94A3B8' }
                   elseif ($avgAnchor -ge 4.0)   { '#2A8E54' }
                   elseif ($avgAnchor -ge 3.0)   { '#F5A623' }
                   else                          { '#DC4C4C' }
    $anchorTb.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($anchorColor)))
    [System.Windows.Controls.Grid]::SetColumn($anchorTb, 2)
    [void]$g.Children.Add($anchorTb)

    # Edit + Delete buttons
    $btnStack = New-Object System.Windows.Controls.StackPanel
    $btnStack.Orientation = 'Horizontal'
    $btnEdit = New-Object System.Windows.Controls.Button
    $btnEdit.Content = 'Edit'
    $btnEdit.Style = $Script:Shell.FindResource('GhostBtn')
    $btnEdit.Margin = '0,0,6,0'
    $btnEdit.Tag = @{ CandId = $Cand.id; EntryId = $Entry.id }
    $btnEdit.Add_Click({
        param($sender, $eventArgs)
        $ctx = $sender.Tag
        Show-RaterEntryDialog -CandId $ctx.CandId -EntryId $ctx.EntryId
    })
    [void]$btnStack.Children.Add($btnEdit)
    $btnDel = New-Object System.Windows.Controls.Button
    $btnDel.Content = 'Delete'
    $btnDel.Style = $Script:Shell.FindResource('GhostBtn')
    $btnDel.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#B23A3A')))
    $btnDel.Tag = @{ CandId = $Cand.id; EntryId = $Entry.id; RaterName = $Entry.raterName }
    $btnDel.Add_Click({
        param($sender, $eventArgs)
        $ctx = $sender.Tag
        $who = if ($ctx.RaterName) { "$($ctx.RaterName)'s submission" } else { 'this rater entry' }
        $confirm = [System.Windows.MessageBox]::Show("Delete $who?",'Delete Rater Entry','YesNo','Question')
        if ($confirm -eq 'Yes') {
            $cd = Get-CandidateById $Script:ShellData $ctx.CandId
            if ($cd) {
                _LogRaterSnapshot 'BEFORE' $ctx.CandId $ctx.EntryId
                Remove-RaterEntry -Cand $cd -EntryId $ctx.EntryId
                _LogRaterSnapshot 'AFTER ' $ctx.CandId $ctx.EntryId
                Sync-CandidateLegacyRatings $cd   # refresh aggregated checkmarks for the printable sheet
                Save-Candidates $Script:ShellData
                # Re-open the candidate detail dialog to refresh the list
                Show-RefreshCandidateDetail $ctx.CandId
            }
        }
    })
    [void]$btnStack.Children.Add($btnDel)
    [System.Windows.Controls.Grid]::SetColumn($btnStack, 3)
    [void]$g.Children.Add($btnStack)

    $b.Child = $g
    return $b
}

function Show-RefreshCandidateDetail {
    <#
    Closes the current candidate detail dialog (if any) and re-opens it for
    the same candidate so the rater list reflects fresh state. Called after
    Add/Edit/Delete of rater entries because the candidate detail is the
    parent dialog and WPF doesn't expose an easy "refresh just this region"
    affordance with our hand-built rater list.
    #>
    param([string]$CandId)
    foreach ($w in @([System.Windows.Application]::Current.Windows)) {
        if ($w -ne $Script:Shell -and $w.Title -eq 'Candidate') {
            try { $w.DialogResult = $true; $w.Close() } catch { try { $w.Close() } catch {} }
        }
    }
    Show-CandidateDetail $CandId
}

function Show-CandidateDetail {
    param([string]$CandId)
    $data = $Script:ShellData
    $c = $data.Candidates | Where-Object id -eq $CandId | Select-Object -First 1
    if (-not $c) { return }
    $w = ConvertTo-Window -Xaml $Script:CandDetailXaml
    # Intentionally no Set-WindowBanner call - the navy BannerFallback gradient
    # reads cleaner behind white title text than the cover.png overlay (matches
    # the JobReqs detail dialog style).
    $w.Owner = $Script:Shell

    ($w.FindName('AvatarHost')).Children.Add( (New-Avatar -Initials (Get-Initials $c.name) -ColorHex $c.avatarColor -Size 60) ) | Out-Null
    ($w.FindName('DlgName')).Text = if ($c.name) { $c.name } else { '(new candidate)' }
    ($w.FindName('DlgRole')).Text = $c.position
    ($w.FindName('DlgStagePillHost')).Child = (New-StagePill -Stage $c.stage)

    ($w.FindName('TbName')).Text       = $c.name
    ($w.FindName('TbEmail')).Text      = $c.email
    ($w.FindName('TbPhone')).Text      = $c.phone
    # Per-job ordinal rank (read-only). Underlying score still drives placement.
    $cRank = Get-CandidateRankInfo $c $Script:ShellData
    ($w.FindName('TbScore')).Text = if ($null -eq $cRank) { 'Not yet rated' } else { [string]$cRank.Display }

    # DatePickers want Nullable<DateTime>. Stored format is yyyy-MM-dd or ''.
    # A freshly-parsed DatePicker has SelectedDate = $null by default, so we
    # only ASSIGN when we have a parseable value. Avoids any PS-to-WPF quirk
    # around explicit $null assignment on a Nullable property -- which was
    # silently aborting the save handler on candidates with empty dates,
    # preventing the stage change from ever reaching Save-Candidates.
    $applied = [DateTime]::MinValue
    if ($c.appliedDate -and [DateTime]::TryParse($c.appliedDate, [ref]$applied)) {
        ($w.FindName('TbApplied')).SelectedDate = $applied
    }
    $interview = [DateTime]::MinValue
    if ($c.interviewDate -and [DateTime]::TryParse($c.interviewDate, [ref]$interview)) {
        ($w.FindName('TbInterview')).SelectedDate = $interview
    }
    ($w.FindName('TbNotes')).Text      = $c.notes
    ($w.FindName('TbRecText')).Text    = $c.recommendationText
    ($w.FindName('TbSignature')).Text  = $c.signature
    # Pre-fill preparedBy with the current user if the candidate hasn't been
    # rated yet; if there's already a preparer recorded, keep that one.
    $preparedBy = if ($c.preparedBy) { $c.preparedBy }
                  elseif ($data.Settings -and $data.Settings.currentUser) { $data.Settings.currentUser.name }
                  else { '' }
    ($w.FindName('TbPreparedBy')).Text = $preparedBy

    # Job combo
    $cbJob = $w.FindName('CbJob')
    foreach ($j in $data.Jobs) {
        $item = New-Object System.Windows.Controls.ComboBoxItem
        $item.Content = "$($j.reqNumber) - $($j.title)"
        $item.Tag = $j.id
        [void]$cbJob.Items.Add($item)
        if ($j.id -eq $c.jobReqId) { $cbJob.SelectedItem = $item }
    }

    # Stage combo
    $cbStage = $w.FindName('CbStage')
    foreach ($i in 0..($cbStage.Items.Count-1)) {
        if ("$($cbStage.Items[$i].Content)" -eq $c.stage) { $cbStage.SelectedIndex = $i }
    }
    # Rec combo (Select / Non-Select)
    $cbRec = $w.FindName('CbRec')
    foreach ($i in 0..($cbRec.Items.Count-1)) {
        if ("$($cbRec.Items[$i].Content)" -eq $c.recommendation) { $cbRec.SelectedIndex = $i }
    }
    # Rec reason combo populated from the catalog (DO Hire / DO Promote / etc.)
    $cbRecReason = $w.FindName('CbRecReason')
    [void]$cbRecReason.Items.Add('')   # blank == unset
    if ($data.Catalog -and $data.Catalog.recommendationReasons) {
        foreach ($r in $data.Catalog.recommendationReasons) { [void]$cbRecReason.Items.Add($r) }
    }
    foreach ($i in 0..($cbRecReason.Items.Count-1)) {
        if ("$($cbRecReason.Items[$i])" -eq $c.recommendationReason) { $cbRecReason.SelectedIndex = $i }
    }

    # --- Interview Evaluation (single, hiring manager) --------------------
    $evalHost  = $w.FindName('EvalHost')
    $evalEmpty = $w.FindName('EvalEmpty')
    $rateBtn   = $w.FindName('BtnRateCandidate')

    $entry = Get-PrimaryRaterEntry $c
    if ($entry) {
        $evalEmpty.Visibility = 'Collapsed'
        [void]$evalHost.Children.Add( (_BuildRaterListRow -Cand $c -Entry $entry) )
        $rateBtn.Content = 'Edit Evaluation'
    }

    $rateBtn.Tag = $c.id
    $rateBtn.Add_Click({
        param($sender, $eventArgs)
        $cd = Get-CandidateById $Script:ShellData $sender.Tag
        if (-not $cd) { return }
        # Require a kit before evaluating (the form renders kit categories).
        $k = Get-KitForJob $Script:ShellData $cd.jobReqId
        if (-not $k) {
            Set-ShellStatus -Text "No interview kit for this candidate's job - build one first." -Level WARN
            return
        }
        # One evaluation, attributed to the hiring manager by default.
        $job = Get-JobById $Script:ShellData $cd.jobReqId
        $hm  = if ($job -and $job.hiringManager) { $job.hiringManager } else { '' }
        $e = Get-OrCreatePrimaryRaterEntry -Cand $cd -RaterName $hm -RaterRole 'Hiring Manager'
        Save-Candidates $Script:ShellData
        Show-RaterEntryDialog -CandId $cd.id -EntryId $e.id
    })

    # --- Print buttons -----------------------------------------------------
    # All three open in the browser with the print/save-as-PDF button visible.
    # Capture the candidate id on each button so the handlers don't need to
    # close over $c (closure scope can shadow $Script:ShellData reads).
    $printHandout     = $w.FindName('BtnPrintHandout')
    $printCandidate   = $w.FindName('BtnPrintCandidate')
    $printBlankRating = $w.FindName('BtnPrintBlankRating')
    $printRating      = $w.FindName('BtnPrintRating')
    $printHandout.Tag     = $c.id
    $printCandidate.Tag   = $c.id
    $printBlankRating.Tag = $c.id
    $printRating.Tag      = $c.id

    $printHandout.Add_Click({
        param($sender, $eventArgs)
        $cd = Get-CandidateById $Script:ShellData $sender.Tag
        if (-not $cd) { return }
        $k  = Get-KitForJob   $Script:ShellData $cd.jobReqId
        $j  = Get-JobById     $Script:ShellData $cd.jobReqId
        if (-not $k) {
            Set-ShellStatus -Text "No interview kit for this candidate's job - build one first." -Level WARN
            return
        }
        $path = New-InterviewHandoutHtml -Kit $k -Job $j -Candidate $cd -Catalog $Script:ShellData.Catalog
        Open-TrueHireOutput -Path $path
    })
    # Candidate copy: questions only, no interpretive/scoring guide.
    $printCandidate.Add_Click({
        param($sender, $eventArgs)
        $cd = Get-CandidateById $Script:ShellData $sender.Tag
        if (-not $cd) { return }
        $k  = Get-KitForJob   $Script:ShellData $cd.jobReqId
        $j  = Get-JobById     $Script:ShellData $cd.jobReqId
        if (-not $k) {
            Set-ShellStatus -Text "No interview kit for this candidate's job - build one first." -Level WARN
            return
        }
        $path = New-InterviewHandoutHtml -Kit $k -Job $j -Candidate $cd -Catalog $Script:ShellData.Catalog -CandidateCopy
        Open-TrueHireOutput -Path $path
    })
    $printBlankRating.Add_Click({
        param($sender, $eventArgs)
        $cd = Get-CandidateById $Script:ShellData $sender.Tag
        if (-not $cd) { return }
        $k  = Get-KitForJob $Script:ShellData $cd.jobReqId
        $j  = Get-JobById   $Script:ShellData $cd.jobReqId
        if (-not $k) {
            Set-ShellStatus -Text "No interview kit for this candidate's job - build one first." -Level WARN
            return
        }
        $path = New-RatingSheetHtml -Kit $k -Candidate $cd -Job $j -Catalog $Script:ShellData.Catalog -Blank
        Open-TrueHireOutput -Path $path
    })
    $printRating.Add_Click({
        param($sender, $eventArgs)
        $cd = Get-CandidateById $Script:ShellData $sender.Tag
        if (-not $cd) { return }
        $k  = Get-KitForJob $Script:ShellData $cd.jobReqId
        $j  = Get-JobById   $Script:ShellData $cd.jobReqId
        if (-not $k) {
            Set-ShellStatus -Text "No interview kit for this candidate's job - build one first." -Level WARN
            return
        }
        $path = New-RatingSheetHtml -Kit $k -Candidate $cd -Job $j -Catalog $Script:ShellData.Catalog
        Open-TrueHireOutput -Path $path
    })

    # --- Cancel / Delete / Save -------------------------------------------
    $w.FindName('BtnCancel').Add_Click({ $w.DialogResult = $false; $w.Close() })
    $w.FindName('BtnDelete').Add_Click({
        $confirm = [System.Windows.MessageBox]::Show("Delete this candidate?",'Delete','YesNo','Question')
        if ($confirm -eq 'Yes') {
            $data.Candidates = @($data.Candidates | Where-Object id -ne $c.id)
            Save-Candidates $data
            $w.DialogResult = $true; $w.Close()
            Show-View 'TabCandidates'
        }
    }.GetNewClosure())
    $w.FindName('BtnSave').Add_Click({
        $c.name          = ($w.FindName('TbName')).Text
        $c.email         = ($w.FindName('TbEmail')).Text
        $c.phone         = ($w.FindName('TbPhone')).Text
        # DatePicker.SelectedDate is Nullable<DateTime>. Canonical storage
        # stays 'yyyy-MM-dd' so the rest of the app (export bundles,
        # sort-by-date, analytics) doesn't have to care about culture.
        # Wrapped in try/catch so a future PS+WPF nullable quirk on these
        # two fields can never silently block the stage / matchScore /
        # recommendation writes below from reaching Save-Candidates.
        try {
            $appliedSd = ($w.FindName('TbApplied')).SelectedDate
            $c.appliedDate   = if ($appliedSd) { $appliedSd.ToString('yyyy-MM-dd') } else { '' }
            $interviewSd = ($w.FindName('TbInterview')).SelectedDate
            $c.interviewDate = if ($interviewSd) { $interviewSd.ToString('yyyy-MM-dd') } else { '' }
        } catch {
            if (Get-Command Write-TrueHireLog -ErrorAction SilentlyContinue) {
                Write-TrueHireLog -Level WARN -Source 'CandidateSave' -Message ('DatePicker read failed; dates left unchanged: ' + $_.Exception.Message) -Exception $_.Exception
            }
        }
        $c.notes         = ($w.FindName('TbNotes')).Text
        # Rating-derived fields:
        $c.preparedBy          = ($w.FindName('TbPreparedBy')).Text
        $c.recommendationText  = ($w.FindName('TbRecText')).Text
        $c.signature           = ($w.FindName('TbSignature')).Text
        $rrSel = ($w.FindName('CbRecReason')).SelectedItem
        if ($rrSel -ne $null) { $c.recommendationReason = "$rrSel" }

        $jSel = ($w.FindName('CbJob')).SelectedItem
        if ($jSel) {
            $c.jobReqId = $jSel.Tag
            $j = Get-JobById $data $jSel.Tag
            if ($j) { $c.position = $j.title }
        }
        $sSel = ($w.FindName('CbStage')).SelectedItem
        if ($sSel) { $c.stage = "$($sSel.Content)" }
        $rSel = ($w.FindName('CbRec')).SelectedItem
        if ($rSel) { $c.recommendation = "$($rSel.Content)" }
        $c.initials = Get-Initials $c.name

        # Match score is now DERIVED from Submitted rater anchors (see
        # Get-CandidateScore in lib/Helpers.ps1) -- no longer a manager-
        # entered field. The TbScore element is a read-only TextBlock now;
        # we don't write anything back into $c.matchScore from the dialog.
        # Keep candidate.ratings (legacy single-rating map) in sync with the
        # aggregated anchors so the printable consolidated sheet still
        # draws the right ✓ column. This is a pure UI side-effect.
        Sync-CandidateLegacyRatings $c

        Save-Candidates $data
        $derived = Get-CandidateScore $c $data
        $scoreLabel = if ($null -eq $derived) { 'not yet rated' } else { ('match {0}%' -f $derived) }
        Set-ShellStatus ("Saved {0} ({1})." -f $c.name, $scoreLabel)
        $w.DialogResult = $true; $w.Close()
        Show-View 'TabCandidates'
    }.GetNewClosure())

    [void]$w.ShowDialog()
}

# ----------------------------------------------------------------------------
# Per-rater entry dialog. Opens from the Edit button on a Rater Submissions
# row in the candidate detail dialog. Lets the manager (or rater themselves)
# enter that rater's anchors per category, recommendation, and signature, and
# flip the status from Draft to Submitted (or back).
# ----------------------------------------------------------------------------
$Script:RaterEntryXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Rater Entry" Width="940" Height="780"
        WindowStartupLocation="CenterOwner"
        Background="{StaticResource PageBg}" FontFamily="Segoe UI">
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="84"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <Border Grid.Row="0" Background="{StaticResource BannerFallback}">
      <Grid Margin="24,14">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <StackPanel Grid.Column="0" VerticalAlignment="Center">
          <TextBlock x:Name="ReTitle" Foreground="White" FontSize="20" FontWeight="Bold" Text="Rater Submission"/>
          <TextBlock x:Name="ReSub"   Foreground="#CBDBEA" FontSize="12" Text=""/>
        </StackPanel>
        <Border x:Name="ReStatusPillHost" Grid.Column="1" VerticalAlignment="Center"/>
      </Grid>
    </Border>
    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="24,18">
      <StackPanel>
        <UniformGrid Rows="1" Columns="2" Margin="0,0,0,12">
          <StackPanel Margin="0,0,8,0">
            <TextBlock Style="{StaticResource MicroLabel}" Text="RATER NAME" Margin="0,0,0,4"/>
            <TextBox x:Name="ReName" Style="{StaticResource Field}"/>
          </StackPanel>
          <StackPanel Margin="8,0,0,0">
            <TextBlock Style="{StaticResource MicroLabel}" Text="RATER ROLE" Margin="0,0,0,4"/>
            <TextBox x:Name="ReRole" Style="{StaticResource Field}"/>
          </StackPanel>
        </UniformGrid>

        <TextBlock x:Name="ReAnchorKey" Style="{StaticResource Caption}" FontStyle="Italic"
                   TextWrapping="Wrap" Margin="0,0,0,8"/>

        <Border Style="{StaticResource Card}" Padding="14,10">
          <StackPanel x:Name="ReRatingHost"/>
        </Border>

        <Border Style="{StaticResource Card}" Margin="0,12,0,0">
          <StackPanel>
            <TextBlock Style="{StaticResource H3}" Text="Recommendation" Margin="0,0,0,8"/>
            <UniformGrid Rows="1" Columns="2" Margin="0,0,0,12">
              <StackPanel Margin="0,0,8,0">
                <TextBlock Style="{StaticResource MicroLabel}" Text="OVERALL" Margin="0,0,0,4"/>
                <ComboBox x:Name="ReRec" Style="{StaticResource ComboField}">
                  <ComboBoxItem Content=""/>
                  <ComboBoxItem Content="Select"/>
                  <ComboBoxItem Content="Non-Select"/>
                </ComboBox>
              </StackPanel>
              <StackPanel Margin="8,0,0,0">
                <TextBlock Style="{StaticResource MicroLabel}" Text="REASON" Margin="0,0,0,4"/>
                <ComboBox x:Name="ReRecReason" Style="{StaticResource ComboField}"/>
              </StackPanel>
            </UniformGrid>
            <StackPanel Margin="0,0,0,12">
              <TextBlock Style="{StaticResource MicroLabel}" Text="REASON DETAIL" Margin="0,0,0,4"/>
              <TextBox x:Name="ReRecText" Style="{StaticResource MultilineField}" MinHeight="60"/>
            </StackPanel>
            <StackPanel>
              <TextBlock Style="{StaticResource MicroLabel}" Text="SIGNATURE" Margin="0,0,0,4"/>
              <TextBox x:Name="ReSignature" Style="{StaticResource Field}"/>
            </StackPanel>
          </StackPanel>
        </Border>
      </StackPanel>
    </ScrollViewer>
    <Border Grid.Row="2" Background="White" BorderBrush="{StaticResource CardBorder}"
            BorderThickness="0,1,0,0" Padding="20,12">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <Button x:Name="ReDelete" Grid.Column="0" Content="Delete this submission"
                Style="{StaticResource GhostBtn}" HorizontalAlignment="Left" Foreground="#B23A3A"/>
        <StackPanel Grid.Column="1" Orientation="Horizontal">
          <Button x:Name="ReCancel"      Content="Cancel"            Style="{StaticResource GhostBtn}"  Margin="0,0,8,0"/>
          <Button x:Name="ReSaveDraft"   Content="Save as Draft"     Style="{StaticResource GhostBtn}"  Margin="0,0,8,0"/>
          <Button x:Name="ReSubmit"      Content="Submit"            Style="{StaticResource PrimaryBtn}"/>
        </StackPanel>
      </Grid>
    </Border>
  </Grid>
</Window>
'@

function Show-RaterEntryDialog {
    <#
    Modal for one interviewer's rating submission. Mutates the live
    rater entry on the candidate's raterEntries array; persists via
    Save-Candidates on Save Draft / Submit. Submit flips status to
    'Submitted' so the aggregation pass starts counting it.
    #>
    param([string]$CandId, [string]$EntryId)
    $data = $Script:ShellData
    $c = Get-CandidateById $data $CandId
    if (-not $c) { return }
    $entry = Get-RaterEntryById $c $EntryId
    if (-not $entry) { return }
    $kit = Get-KitForJob $data $c.jobReqId
    if (-not $kit) {
        [System.Windows.MessageBox]::Show(
            "No interview kit exists for this candidate's job. Build a kit on the Interview Kits tab first.",
            'TrueHire','OK','Information') | Out-Null
        return
    }

    $w = ConvertTo-Window -Xaml $Script:RaterEntryXaml
    $w.Owner = $Script:Shell

    ($w.FindName('ReTitle')).Text = if ($c.name) { "Interview evaluation for $($c.name)" } else { 'Interview evaluation' }
    $jobLabel = if ($c.position) { $c.position } else { '' }
    ($w.FindName('ReSub')).Text   = $jobLabel
    ($w.FindName('ReStatusPillHost')).Child = (New-StatusPill -Status $(if ($entry.status -eq 'Submitted') { 'Active' } else { 'Draft' }))

    # Single evaluation == the hiring manager. Prefill from the job when the
    # entry hasn't been attributed yet, so the rater fields read correctly
    # without the user retyping who they are.
    $job = Get-JobById $data $c.jobReqId
    $raterNameVal = if ($entry.raterName) { $entry.raterName }
                    elseif ($job -and $job.hiringManager) { $job.hiringManager }
                    else { '' }
    $raterRoleVal = if ($entry.raterRole) { $entry.raterRole } else { 'Hiring Manager' }
    ($w.FindName('ReName')).Text      = $raterNameVal
    ($w.FindName('ReRole')).Text      = $raterRoleVal
    ($w.FindName('ReRecText')).Text   = $entry.recommendationText
    ($w.FindName('ReSignature')).Text = $entry.signature

    # Overall Select / Non-Select
    $cbRec = $w.FindName('ReRec')
    foreach ($i in 0..($cbRec.Items.Count-1)) {
        if ("$($cbRec.Items[$i].Content)" -eq $entry.recommendation) { $cbRec.SelectedIndex = $i }
    }
    # Reason combo from catalog
    $cbRecReason = $w.FindName('ReRecReason')
    [void]$cbRecReason.Items.Add('')
    if ($data.Catalog -and $data.Catalog.recommendationReasons) {
        foreach ($r in $data.Catalog.recommendationReasons) { [void]$cbRecReason.Items.Add($r) }
    }
    foreach ($i in 0..($cbRecReason.Items.Count-1)) {
        if ("$($cbRecReason.Items[$i])" -eq $entry.recommendationReason) { $cbRecReason.SelectedIndex = $i }
    }

    # Anchor key + per-category rows
    $anchors = @($data.Catalog.anchors)
    $legendBits = for ($i = 0; $i -lt $anchors.Count; $i++) {
        "{0} = {1}" -f $i, $anchors[$i]
    }
    ($w.FindName('ReAnchorKey')).Text = $legendBits -join '   |   '
    $ratingHost = $w.FindName('ReRatingHost')
    foreach ($cat in @($kit.categories)) {
        $rating = Get-RaterRating -Entry $entry -CategoryId $cat.id
        $row = _BuildRatingRow -Cat $cat -Anchors $anchors -Rating $rating
        [void]$ratingHost.Children.Add($row)
    }

    # ---- Button handlers (no GetNewClosure - $Script:ShellData reads need
    # dynamic resolution and we capture context via the dialog's locals
    # captured per-button on Tag where needed) ----
    $w.FindName('ReCancel').Add_Click({ $w.DialogResult = $false; $w.Close() })

    $finalize = {
        param([string]$NewStatus)
        # Pull form values back into the entry
        $entry.raterName            = ($w.FindName('ReName')).Text
        $entry.raterRole            = ($w.FindName('ReRole')).Text
        $entry.recommendationText   = ($w.FindName('ReRecText')).Text
        $entry.signature            = ($w.FindName('ReSignature')).Text
        $rSel = ($w.FindName('ReRec')).SelectedItem
        if ($rSel) { $entry.recommendation = "$($rSel.Content)" }
        $rrSel = ($w.FindName('ReRecReason')).SelectedItem
        if ($rrSel -ne $null) { $entry.recommendationReason = "$rrSel" }
        $entry.status = $NewStatus
        if ($NewStatus -eq 'Submitted') {
            $entry.submittedAt = (Get-Date).ToString('o')
        }
        # Single-evaluation model: the hiring manager rates AND dispositions
        # here, so mirror the evaluation's disposition up to the candidate-
        # level fields the rest of the app reads (candidate list, analytics,
        # the Final Recommendation card, the printable rating sheet).
        $c.recommendation       = $entry.recommendation
        $c.recommendationReason = $entry.recommendationReason
        $c.recommendationText   = $entry.recommendationText
        $c.signature            = $entry.signature
        if ($entry.raterName) { $c.preparedBy = $entry.raterName }
        # Sync candidate.ratings (the legacy single-anchor-per-cat map used
        # by the printable rating sheet) with the evaluation's anchors.
        # No derived match score: matchScore is derived at display time.
        Sync-CandidateLegacyRatings $c
        Save-Candidates $data
        _LogRaterSnapshot ("SUBMIT:" + $NewStatus) $CandId $entry.id
        Set-ShellStatus ("Saved rater submission ({0})." -f $NewStatus)
        $w.DialogResult = $true; $w.Close()
        Show-RefreshCandidateDetail $CandId
    }
    $w.FindName('ReSaveDraft').Add_Click({ & $finalize 'Draft' }.GetNewClosure())
    $w.FindName('ReSubmit').Add_Click({ & $finalize 'Submitted' }.GetNewClosure())

    $w.FindName('ReDelete').Add_Click({
        $confirm = [System.Windows.MessageBox]::Show(
            "Delete this rater submission?",'Delete Rater Entry','YesNo','Question')
        if ($confirm -eq 'Yes') {
            _LogRaterSnapshot 'BEFORE' $CandId $entry.id
            Remove-RaterEntry -Cand $c -EntryId $entry.id
            _LogRaterSnapshot 'AFTER ' $CandId $entry.id
            Sync-CandidateLegacyRatings $c
            Save-Candidates $data
            $w.DialogResult = $true; $w.Close()
            Show-RefreshCandidateDetail $CandId
        }
    }.GetNewClosure())

    [void]$w.ShowDialog()
}
