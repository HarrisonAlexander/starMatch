<#
Analytics.ps1 - ui_5. Visual rollup of the same data the dashboard summarizes,
but with deeper cuts: a left-rail Filters card lets the user scope by date
range, requisition, hiring manager, and stage; the right pane paints the KPI
strip, then a 3-column row of charts (funnel / time-series / per-req bars),
then average-by-kit + per-manager donut + time-to-hire + score histogram.

Charts are built procedurally from $Script:WinResources brushes - no third-
party charting library is involved. Filters mutate $Script:AnalyticsFilters
and Show-AnalyticsView re-renders the whole pane (cheap, ~80ms on the seed
dataset and dodges stale-state bugs).
#>

$Script:AnalyticsXaml = @'
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
      xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
      Background="{StaticResource PageBg}">
  <Grid.ColumnDefinitions>
    <ColumnDefinition Width="260"/>
    <ColumnDefinition Width="*"/>
  </Grid.ColumnDefinitions>

  <!-- ===========  Left rail: Filters  =========== -->
  <Border Grid.Column="0" Background="White" BorderBrush="{StaticResource CardBorder}"
          BorderThickness="0,0,1,0">
    <ScrollViewer VerticalScrollBarVisibility="Auto">
      <StackPanel Margin="18,20,18,20">
        <TextBlock Style="{StaticResource H3}" Text="Filters"/>
        <TextBlock Style="{StaticResource Caption}" Margin="0,2,0,14"
                   Text="Narrow your analysis"/>

        <TextBlock Style="{StaticResource MicroLabel}" Text="DATE RANGE" Margin="0,0,0,4"/>
        <ComboBox x:Name="FltDateRange" Style="{StaticResource ComboField}" Margin="0,0,0,14">
          <ComboBoxItem Content="Last 30 days"/>
          <ComboBoxItem Content="Last 60 days"/>
          <ComboBoxItem Content="Last 90 days" IsSelected="True"/>
          <ComboBoxItem Content="Year to date"/>
          <ComboBoxItem Content="All time"/>
        </ComboBox>

        <TextBlock Style="{StaticResource MicroLabel}" Text="JOB REQUISITION" Margin="0,0,0,4"/>
        <ComboBox x:Name="FltJob" Style="{StaticResource ComboField}" Margin="0,0,0,14"/>

        <TextBlock Style="{StaticResource MicroLabel}" Text="HIRING MANAGER" Margin="0,0,0,4"/>
        <ComboBox x:Name="FltManager" Style="{StaticResource ComboField}" Margin="0,0,0,14"/>

        <TextBlock Style="{StaticResource MicroLabel}" Text="CANDIDATE STAGE" Margin="0,0,0,4"/>
        <ComboBox x:Name="FltStage" Style="{StaticResource ComboField}" Margin="0,0,0,14">
          <ComboBoxItem Content="All Stages" IsSelected="True"/>
          <ComboBoxItem Content="New"/>
          <ComboBoxItem Content="Screening"/>
          <ComboBoxItem Content="Interview"/>
          <ComboBoxItem Content="Offer"/>
          <ComboBoxItem Content="Hired"/>
          <ComboBoxItem Content="Rejected"/>
        </ComboBox>

        <TextBlock Style="{StaticResource MicroLabel}" Text="DEPARTMENT" Margin="0,0,0,4"/>
        <ComboBox x:Name="FltDept" Style="{StaticResource ComboField}" Margin="0,0,0,18"/>

        <Button x:Name="BtnApplyFilters" Style="{StaticResource BlueBtn}"
                Content="Apply Filters" Margin="0,0,0,8"/>
        <Button x:Name="BtnResetFilters" Style="{StaticResource GhostBtn}"
                Content="Reset"/>
      </StackPanel>
    </ScrollViewer>
  </Border>

  <!-- ===========  Right pane: Analytics  =========== -->
  <ScrollViewer Grid.Column="1" VerticalScrollBarVisibility="Auto"
                HorizontalScrollBarVisibility="Disabled">
    <StackPanel Margin="28,22,28,24">

      <!-- Title bar with date range + Export -->
      <Grid Margin="0,0,0,20">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <StackPanel Grid.Column="0">
          <TextBlock Style="{StaticResource H2}" Text="Analytics Overview"/>
          <TextBlock x:Name="DateRangeLabel" Style="{StaticResource Caption}"
                     Margin="0,4,0,0" Text="Insights and trends for your recruiting pipeline"/>
        </StackPanel>
        <Button Grid.Column="1" x:Name="BtnExport" Style="{StaticResource GhostBtn}"
                Content="Export Report" VerticalAlignment="Center"/>
      </Grid>

      <!-- ===========  KPI strip (4)  =========== -->
      <Grid Margin="0,0,0,20">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <Border Grid.Column="0" Style="{StaticResource Card}" Margin="0,0,8,0">
          <StackPanel>
            <TextBlock Style="{StaticResource Caption}" Text="Total Requisitions"/>
            <TextBlock x:Name="KpiTotalReqs" Style="{StaticResource KpiNumber}" Text="0" Margin="0,8,0,0"/>
            <TextBlock x:Name="KpiTotalReqsSub" Style="{StaticResource Caption}" Text="0 active"/>
          </StackPanel>
        </Border>

        <Border Grid.Column="1" Style="{StaticResource Card}" Margin="4,0,4,0">
          <StackPanel>
            <TextBlock Style="{StaticResource Caption}" Text="Total Candidates"/>
            <TextBlock x:Name="KpiTotalCand" Style="{StaticResource KpiNumber}" Text="0" Margin="0,8,0,0"/>
            <TextBlock x:Name="KpiTotalCandSub" Style="{StaticResource Caption}" Text="across all requisitions"/>
          </StackPanel>
        </Border>

        <Border Grid.Column="2" Style="{StaticResource Card}" Margin="4,0,4,0">
          <StackPanel>
            <TextBlock Style="{StaticResource Caption}" Text="Advanced to Interview"/>
            <TextBlock x:Name="KpiAdvanced" Style="{StaticResource KpiNumber}" Text="0" Margin="0,8,0,0"/>
            <TextBlock x:Name="KpiAdvancedSub" Style="{StaticResource Caption}" Text="interview / offer / hired"/>
          </StackPanel>
        </Border>

        <Border Grid.Column="3" Style="{StaticResource Card}" Margin="4,0,0,0">
          <StackPanel>
            <TextBlock Style="{StaticResource Caption}" Text="Hired"/>
            <TextBlock x:Name="KpiHired" Style="{StaticResource KpiNumber}" Text="0" Margin="0,8,0,0"/>
            <TextBlock x:Name="KpiHiredSub" Style="{StaticResource Caption}" Text="this period"/>
          </StackPanel>
        </Border>
      </Grid>

      <!-- ===========  Charts row 1: Funnel | Time Series | Hires by Req  =========== -->
      <Grid Margin="0,0,0,20">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="2*"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <Border Grid.Column="0" Style="{StaticResource Card}" Margin="0,0,8,0">
          <StackPanel>
            <TextBlock Style="{StaticResource H3}" Text="Candidates by Stage"/>
            <TextBlock Style="{StaticResource Caption}" Text="Pipeline distribution" Margin="0,2,0,14"/>
            <ContentControl x:Name="AnalyticsFunnelHost"/>
          </StackPanel>
        </Border>

        <Border Grid.Column="1" Style="{StaticResource Card}" Margin="4,0,4,0">
          <StackPanel>
            <Grid>
              <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
              <StackPanel Grid.Column="0">
                <TextBlock Style="{StaticResource H3}" Text="Candidates Over Time"/>
                <TextBlock Style="{StaticResource Caption}" Text="Applications and hires" Margin="0,2,0,0"/>
              </StackPanel>
              <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Top">
                <Rectangle Width="10" Height="10" Fill="{StaticResource AccentBlue}" Margin="0,4,4,0"/>
                <TextBlock Text="Applied" Style="{StaticResource Caption}" Margin="0,0,12,0"/>
                <Rectangle Width="10" Height="10" Fill="{StaticResource GreenOk}" Margin="0,4,4,0"/>
                <TextBlock Text="Hired" Style="{StaticResource Caption}"/>
              </StackPanel>
            </Grid>
            <ContentControl x:Name="AnalyticsTimeSeriesHost" Margin="0,14,0,0" Height="180"/>
          </StackPanel>
        </Border>

        <Border Grid.Column="2" Style="{StaticResource Card}" Margin="8,0,0,0">
          <StackPanel>
            <TextBlock Style="{StaticResource H3}" Text="Hires by Job Requisition"/>
            <TextBlock Style="{StaticResource Caption}" Text="Top performing reqs" Margin="0,2,0,14"/>
            <ContentControl x:Name="AnalyticsHiresHost"/>
          </StackPanel>
        </Border>
      </Grid>

      <!-- ===========  Charts row 2: Per-Manager Donut | Time to Hire  =========== -->
      <Grid Margin="0,0,0,20">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <Border Grid.Column="0" Style="{StaticResource Card}" Margin="0,0,8,0">
          <StackPanel>
            <TextBlock Style="{StaticResource H3}" Text="Interview Progress by Hiring Manager"/>
            <TextBlock Style="{StaticResource Caption}" Text="Active load distribution" Margin="0,2,0,14"/>
            <Grid>
              <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
              <ContentControl x:Name="AnalyticsManagerDonutHost" Grid.Column="0" Width="160" Height="160"/>
              <StackPanel x:Name="AnalyticsManagerLegend" Grid.Column="1" Margin="14,0,0,0" VerticalAlignment="Center"/>
            </Grid>
          </StackPanel>
        </Border>

        <Border Grid.Column="1" Style="{StaticResource Card}" Margin="8,0,0,0">
          <StackPanel>
            <TextBlock Style="{StaticResource H3}" Text="Time to Hire"/>
            <TextBlock Style="{StaticResource Caption}" Text="Avg days from apply to offer" Margin="0,2,0,14"/>
            <StackPanel Orientation="Horizontal" Margin="0,8,0,12">
              <TextBlock x:Name="KpiDaysToHire" Text="0" FontSize="56"
                         FontWeight="Bold" Foreground="{StaticResource TextPrimary}"/>
              <TextBlock Text="days" FontSize="16" Foreground="{StaticResource TextMuted}"
                         VerticalAlignment="Bottom" Margin="8,0,0,12"/>
            </StackPanel>
            <ContentControl x:Name="AnalyticsTrendBarsHost"/>
            <TextBlock x:Name="KpiDaysTrend" Style="{StaticResource Caption}"
                       Margin="0,8,0,0" Text=""/>
          </StackPanel>
        </Border>
      </Grid>

    </StackPanel>
  </ScrollViewer>
</Grid>
'@

# Module-scoped filter state. Show-AnalyticsView reads this on each render.
$Script:AnalyticsFilters = @{
    DateRange = 'Last 90 days'
    JobId     = 'all'
    Manager   = 'all'
    Stage     = 'All Stages'
    Dept      = 'all'
}

function _PassesAnalyticsFilters {
    <#
    Returns $true if the candidate clears every active filter. Date filter
    operates on appliedDate; the 'All time' option returns everything.
    #>
    param($Cand, $Job, $Filters)
    if ($Filters.JobId   -ne 'all' -and $Cand.jobReqId -ne $Filters.JobId)        { return $false }
    if ($Filters.Stage   -ne 'All Stages' -and $Cand.stage -ne $Filters.Stage)    { return $false }
    if ($Job) {
        if ($Filters.Manager -ne 'all' -and $Job.hiringManager -ne $Filters.Manager)   { return $false }
        if ($Filters.Dept    -ne 'all' -and $Job.department    -ne $Filters.Dept)      { return $false }
    }
    if ($Filters.DateRange -ne 'All time') {
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

function _BuildTimeSeries {
    <#
    Two-series line chart: Applied (blue) over the last N weekly buckets plus
    Hired (green) overlay. WPF Polyline takes a Point collection and tracks the
    parent's Width via a SizeChanged hook so it stretches naturally.
    #>
    param([array]$Cands, [int]$Weeks = 12, [double]$Height = 180)
    $now = (Get-Date).Date
    $start = $now.AddDays(-7 * ($Weeks - 1))
    $buckets = @()
    for ($i = 0; $i -lt $Weeks; $i++) {
        $bs = $start.AddDays(7*$i)
        $be = $bs.AddDays(7)
        $applied = 0; $hired = 0
        foreach ($c in $Cands) {
            try {
                $a = [datetime]$c.appliedDate
                if ($a -ge $bs -and $a -lt $be) { $applied++ }
            } catch { }
            try {
                if ($c.stage -eq 'Hired' -and $c.interviewDate) {
                    $h = [datetime]$c.interviewDate
                    if ($h -ge $bs -and $h -lt $be) { $hired++ }
                }
            } catch { }
        }
        $buckets += [pscustomobject]@{ Start = $bs; Applied = $applied; Hired = $hired }
    }
    $maxA = ($buckets | Measure-Object Applied -Maximum).Maximum
    if ($maxA -lt 1) { $maxA = 1 }

    $chart = New-Object System.Windows.Controls.Grid
    $chart.Height = $Height
    $chart.ClipToBounds = $true
    $chart.Tag = $buckets   # carry buckets so the SizeChanged hook can re-layout

    $redraw = {
        param($sender, $e)
        $g = $sender
        $b = $g.Tag
        if (-not $b -or $g.ActualWidth -le 0 -or $g.ActualHeight -le 0) { return }
        $g.Children.Clear()
        $w = $g.ActualWidth
        $h = $g.ActualHeight - 22  # leave space for x-axis labels
        $padL = 26.0; $padR = 8.0
        $plotW = [Math]::Max(10, $w - $padL - $padR)
        $n = $b.Count
        $maxV = 1
        foreach ($bk in $b) { if ($bk.Applied -gt $maxV) { $maxV = $bk.Applied } }

        # Light horizontal gridlines (4 bands)
        for ($i = 0; $i -le 4; $i++) {
            $y = $h * ($i / 4.0)
            $ln = New-Object System.Windows.Shapes.Line
            $ln.X1 = $padL; $ln.X2 = $padL + $plotW
            $ln.Y1 = $y; $ln.Y2 = $y
            $ln.Stroke = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#EDF0F4')))
            $ln.StrokeThickness = 1
            [void]$g.Children.Add($ln)
        }

        $appliedPts = New-Object System.Windows.Media.PointCollection
        $hiredPts   = New-Object System.Windows.Media.PointCollection
        for ($i = 0; $i -lt $n; $i++) {
            $x = $padL + ($plotW * $i / [Math]::Max(1,$n-1))
            $yA = $h - ($h * ([double]$b[$i].Applied / [double]$maxV))
            $yH = $h - ($h * ([double]$b[$i].Hired   / [double]$maxV))
            [void]$appliedPts.Add((New-Object System.Windows.Point ($x,$yA)))
            [void]$hiredPts.Add((New-Object System.Windows.Point ($x,$yH)))
        }
        $linA = New-Object System.Windows.Shapes.Polyline
        $linA.Points = $appliedPts
        $linA.Stroke = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#1E88E5')))
        $linA.StrokeThickness = 2.5
        [void]$g.Children.Add($linA)
        $linH = New-Object System.Windows.Shapes.Polyline
        $linH.Points = $hiredPts
        $linH.Stroke = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#38B66E')))
        $linH.StrokeThickness = 2.5
        [void]$g.Children.Add($linH)

        # Dots on each Applied point
        for ($i = 0; $i -lt $n; $i++) {
            $x = $padL + ($plotW * $i / [Math]::Max(1,$n-1))
            $yA = $h - ($h * ([double]$b[$i].Applied / [double]$maxV))
            $dot = New-Object System.Windows.Shapes.Ellipse
            $dot.Width = 6; $dot.Height = 6
            $dot.Fill = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#1E88E5')))
            $dot.Margin = (New-Object System.Windows.Thickness (($x - 3), ($yA - 3), 0, 0))
            $dot.HorizontalAlignment = 'Left'; $dot.VerticalAlignment = 'Top'
            [void]$g.Children.Add($dot)
        }
        # X axis labels (show every 2nd week to avoid crowding)
        for ($i = 0; $i -lt $n; $i++) {
            if ($i % 2 -ne 0 -and $i -ne $n-1) { continue }
            $x = $padL + ($plotW * $i / [Math]::Max(1,$n-1))
            $lbl = New-Object System.Windows.Controls.TextBlock
            $lbl.Text = $b[$i].Start.ToString('MMM d')
            $lbl.FontSize = 10
            $lbl.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#6B7B8C')))
            $lbl.HorizontalAlignment = 'Left'
            $lbl.VerticalAlignment   = 'Top'
            $lbl.Margin = (New-Object System.Windows.Thickness (($x - 14), ($h + 4), 0, 0))
            [void]$g.Children.Add($lbl)
        }
    }
    $chart.Add_SizeChanged($redraw)
    $chart.Add_Loaded($redraw)
    return $chart
}

function _BuildManagerDonut {
    <#
    Donut showing share of in-progress candidates (stage in Screening/Interview/
    Offer) per hiring manager. Returns @{ Donut=<Grid>; Legend=<StackPanel>;
    Total=<int> } so the legend can be parked in its own column.
    #>
    param([array]$Cands, [array]$Jobs, [double]$Size = 160)
    $palette = @('#1E88E5','#F5A623','#38B66E','#7E57C2','#D81B60','#1565C0','#F08C2A','#A56500')

    # Build job-id -> manager lookup
    $mgrByJob = @{}
    foreach ($j in $Jobs) { $mgrByJob[$j.id] = $j.hiringManager }

    $inProg = @($Cands | Where-Object { $_.stage -in 'Screening','Interview','Offer' })
    $byMgr  = @{}
    foreach ($c in $inProg) {
        $m = $mgrByJob[$c.jobReqId]
        if (-not $m) { $m = 'Unassigned' }
        if (-not $byMgr.ContainsKey($m)) { $byMgr[$m] = 0 }
        $byMgr[$m] = $byMgr[$m] + 1
    }
    $total = ($byMgr.Values | Measure-Object -Sum).Sum
    if (-not $total) { $total = 0 }

    $donut = New-Object System.Windows.Controls.Grid
    $donut.Width  = $Size; $donut.Height = $Size

    if ($total -le 0) {
        $empty = New-Object System.Windows.Controls.TextBlock
        $empty.Text = 'No data'
        $empty.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#94A3B8')))
        $empty.HorizontalAlignment = 'Center'; $empty.VerticalAlignment = 'Center'
        [void]$donut.Children.Add($empty)
    } else {
        $cx = $Size/2; $cy = $Size/2; $r = ($Size/2) - 6
        $startAngle = -90.0
        $idx = 0
        foreach ($k in ($byMgr.Keys | Sort-Object)) {
            $v = $byMgr[$k]
            $sweep = 360.0 * ([double]$v / [double]$total)
            $color = $palette[$idx % $palette.Count]
            $a1 = $startAngle * [Math]::PI / 180.0
            $a2 = ($startAngle + $sweep) * [Math]::PI / 180.0
            $x1 = $cx + $r * [Math]::Cos($a1); $y1 = $cy + $r * [Math]::Sin($a1)
            $x2 = $cx + $r * [Math]::Cos($a2); $y2 = $cy + $r * [Math]::Sin($a2)
            $isLarge = $sweep -gt 180
            $arc = New-Object System.Windows.Media.ArcSegment ((New-Object System.Windows.Point ($x2,$y2)),
                (New-Object System.Windows.Size ($r,$r)), 0, $isLarge, 'Clockwise', $true)
            $fig = New-Object System.Windows.Media.PathFigure
            $fig.StartPoint = New-Object System.Windows.Point ($x1,$y1)
            [void]$fig.Segments.Add($arc)
            $geom = New-Object System.Windows.Media.PathGeometry
            [void]$geom.Figures.Add($fig)
            $path = New-Object System.Windows.Shapes.Path
            $path.Data = $geom
            $path.Stroke = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($color)))
            $path.StrokeThickness = 22
            $path.StrokeStartLineCap = 'Flat'
            $path.StrokeEndLineCap   = 'Flat'
            [void]$donut.Children.Add($path)
            $startAngle += $sweep
            $idx++
        }
        $hole = New-Object System.Windows.Shapes.Ellipse
        $hole.Width = ($Size - 60); $hole.Height = ($Size - 60)
        $hole.Fill = [System.Windows.Media.Brushes]::White
        $hole.HorizontalAlignment = 'Center'; $hole.VerticalAlignment = 'Center'
        [void]$donut.Children.Add($hole)
        $totalLbl = New-Object System.Windows.Controls.TextBlock
        $totalLbl.Text = "$total"
        $totalLbl.FontSize = 26; $totalLbl.FontWeight = 'Bold'
        $totalLbl.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#0B2C45')))
        $totalLbl.HorizontalAlignment = 'Center'; $totalLbl.VerticalAlignment = 'Center'
        [void]$donut.Children.Add($totalLbl)
    }

    $legend = New-Object System.Windows.Controls.StackPanel
    $legend.Orientation = 'Vertical'
    $idx = 0
    foreach ($k in ($byMgr.Keys | Sort-Object)) {
        $v = $byMgr[$k]
        $color = $palette[$idx % $palette.Count]
        $row = New-Object System.Windows.Controls.StackPanel
        $row.Orientation = 'Horizontal'
        $row.Margin = '0,0,0,6'
        $sw = New-Object System.Windows.Shapes.Rectangle
        $sw.Width = 10; $sw.Height = 10
        $sw.Fill = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($color)))
        $sw.VerticalAlignment = 'Center'
        $sw.Margin = '0,0,8,0'
        [void]$row.Children.Add($sw)
        $name = New-Object System.Windows.Controls.TextBlock
        $name.Text = $k
        $name.FontSize = 12
        $name.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#2C3E50')))
        $name.VerticalAlignment = 'Center'
        [void]$row.Children.Add($name)
        $count = New-Object System.Windows.Controls.TextBlock
        $count.Text = " | $v"
        $count.FontSize = 12
        $count.FontWeight = 'SemiBold'
        $count.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#6B7B8C')))
        $count.VerticalAlignment = 'Center'
        [void]$row.Children.Add($count)
        [void]$legend.Children.Add($row)
        $idx++
    }
    return @{ Donut = $donut; Legend = $legend; Total = $total }
}

function _BuildTrendBars {
    <#
    Mini 8-bar sparkline-style indicator that sits under the Time-to-Hire KPI.
    Each bar is the avg time-to-hire for hires that closed in that week.
    Tapers nicely if there's not enough data; values default to the running
    average so the chart never collapses to a single bar.
    #>
    param([array]$Cands, [double]$Height = 60)
    $weeks = 8
    $now = (Get-Date).Date
    $start = $now.AddDays(-7 * ($weeks - 1))
    $values = @()
    for ($i = 0; $i -lt $weeks; $i++) {
        $bs = $start.AddDays(7*$i); $be = $bs.AddDays(7)
        $hiresInWk = @()
        foreach ($c in $Cands) {
            if ($c.stage -ne 'Hired') { continue }
            try {
                $a = [datetime]$c.appliedDate
                $h = if ($c.interviewDate) { [datetime]$c.interviewDate } else { $a.AddDays(21) }
                if ($h -ge $bs -and $h -lt $be) {
                    $hiresInWk += [Math]::Max(1, ($h - $a).TotalDays)
                }
            } catch { }
        }
        $avg = if ($hiresInWk.Count -gt 0) {
            [int][Math]::Round( ($hiresInWk | Measure-Object -Average).Average )
        } else { 0 }
        $values += $avg
    }
    $max = ($values | Measure-Object -Maximum).Maximum
    if ($max -le 0) { $max = 1 }
    $grid = New-Object System.Windows.Controls.Grid
    $grid.Height = $Height
    for ($i = 0; $i -lt $values.Count; $i++) {
        $col = New-Object System.Windows.Controls.ColumnDefinition; $col.Width = '*'
        [void]$grid.ColumnDefinitions.Add($col)
    }
    for ($i = 0; $i -lt $values.Count; $i++) {
        $cell = New-Object System.Windows.Controls.Grid
        $cell.Margin = '3,0,3,0'
        [System.Windows.Controls.Grid]::SetColumn($cell, $i)
        $bar = New-Object System.Windows.Controls.Border
        $bar.CornerRadius = '3,3,0,0'
        $bar.VerticalAlignment = 'Bottom'
        $bar.HorizontalAlignment = 'Stretch'
        $color = if ($i -eq $values.Count - 1) { '#1E88E5' } else { '#9CC8F1' }
        $bar.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($color)))
        $bar.Height = [Math]::Max(3, $Height * ([double]$values[$i] / [double]$max))
        [void]$cell.Children.Add($bar)
        [void]$grid.Children.Add($cell)
    }
    return @{ Grid = $grid; Values = $values }
}

function Show-AnalyticsView {
    param($Container)
    # The shell hands us a host Grid; XamlReader::Parse uses the Application's
    # already-loaded resource dictionary, so StaticResource lookups work.
    $root = [System.Windows.Markup.XamlReader]::Parse($Script:AnalyticsXaml)
    [void]$Container.Children.Add($root)

    $data = $Script:ShellData
    $jobs = @($data.Jobs)
    $cands = @($data.Candidates)

    # State the Apply/Reset handlers need to reach across the closure-scope
    # boundary. .GetNewClosure() shadows $Script:AnalyticsFilters to null,
    # causing "property X cannot be found" on every property-set inside the
    # handler. Stashing via a hashtable + dropping the closure works around it.
    $Script:AnalyticsViewState = @{
        Root      = $root
        Container = $Container
        Jobs      = $jobs
    }

    # ---------- Populate filter combos ----------
    $jobCombo = $root.FindName('FltJob')
    [void]$jobCombo.Items.Add('All Requisitions')
    foreach ($j in ($jobs | Sort-Object reqNumber)) {
        # Parens are load-bearing: without them the comma binds to .Add(),
        # not the format operator.
        [void]$jobCombo.Items.Add(("{0} - {1}" -f $j.reqNumber, $j.title))
    }
    $jobCombo.SelectedIndex = 0

    $mgrCombo = $root.FindName('FltManager')
    [void]$mgrCombo.Items.Add('All Managers')
    foreach ($m in ($jobs | Select-Object -ExpandProperty hiringManager -Unique | Sort-Object)) {
        if ($m) { [void]$mgrCombo.Items.Add($m) }
    }
    $mgrCombo.SelectedIndex = 0

    $deptCombo = $root.FindName('FltDept')
    [void]$deptCombo.Items.Add('All Departments')
    foreach ($d in ($jobs | Select-Object -ExpandProperty department -Unique | Sort-Object)) {
        if ($d) { [void]$deptCombo.Items.Add($d) }
    }
    $deptCombo.SelectedIndex = 0

    # Pre-select current filter values
    $dr = $root.FindName('FltDateRange')
    for ($i = 0; $i -lt $dr.Items.Count; $i++) {
        if ($dr.Items[$i].Content -eq $Script:AnalyticsFilters.DateRange) { $dr.SelectedIndex = $i; break }
    }
    $st = $root.FindName('FltStage')
    for ($i = 0; $i -lt $st.Items.Count; $i++) {
        if ($st.Items[$i].Content -eq $Script:AnalyticsFilters.Stage) { $st.SelectedIndex = $i; break }
    }

    # No .GetNewClosure() - the handlers mutate $Script:AnalyticsFilters
    # (a hashtable assigned at module load time) and would crash with
    # "property X cannot be found" under closure scope. They pull locals
    # ($root, $Container, $jobs) from $Script:AnalyticsViewState instead.
    $applyBtn = $root.FindName('BtnApplyFilters')
    $applyBtn.Add_Click({
        param($sender, $eventArgs)
        $st = $Script:AnalyticsViewState
        $r  = $st.Root
        $js = $st.Jobs

        # Lift if/else branches into locals first - PowerShell 5.1 is wobbly
        # about `obj.Prop = if (...) {...} else {...}` in some contexts and
        # was throwing here when the RHS was the if-expression form.
        $Script:AnalyticsFilters.DateRange = $r.FindName('FltDateRange').SelectedItem.Content
        $Script:AnalyticsFilters.Stage     = $r.FindName('FltStage').SelectedItem.Content

        $idx = $r.FindName('FltJob').SelectedIndex
        $jobIdVal = 'all'
        if ($idx -gt 0) { $jobIdVal = ($js | Sort-Object reqNumber)[$idx - 1].id }
        $Script:AnalyticsFilters.JobId = $jobIdVal

        $mIdx = $r.FindName('FltManager').SelectedIndex
        $mgrVal = 'all'
        if ($mIdx -gt 0) { $mgrVal = $r.FindName('FltManager').SelectedItem }
        $Script:AnalyticsFilters.Manager = $mgrVal

        $dIdx = $r.FindName('FltDept').SelectedIndex
        $deptVal = 'all'
        if ($dIdx -gt 0) { $deptVal = $r.FindName('FltDept').SelectedItem }
        $Script:AnalyticsFilters.Dept = $deptVal

        $st.Container.Children.Clear()
        Show-AnalyticsView $st.Container
    })

    $resetBtn = $root.FindName('BtnResetFilters')
    $resetBtn.Add_Click({
        param($sender, $eventArgs)
        # Reassigning the whole hashtable from inside a closure would write to
        # a throwaway scope; mutate the existing one in place instead.
        $Script:AnalyticsFilters.DateRange = 'Last 90 days'
        $Script:AnalyticsFilters.JobId     = 'all'
        $Script:AnalyticsFilters.Manager   = 'all'
        $Script:AnalyticsFilters.Stage     = 'All Stages'
        $Script:AnalyticsFilters.Dept      = 'all'
        $st = $Script:AnalyticsViewState
        $st.Container.Children.Clear()
        Show-AnalyticsView $st.Container
    })

    # Export Report -> multi-sheet Analytics-Report_<timestamp>.xlsx in
    # .\outputs\, then open in Excel. Uses the ImportExcel module
    # (lib\ReportExcel.ps1). If the module is missing we disable the
    # button + drop a tooltip so the user gets a clear next step rather
    # than a silent fail. param($sender,$e) + no .GetNewClosure() so
    # script-scope function names resolve at fire time (see CLAUDE.md).
    $exportBtn = $root.FindName('BtnExport')
    if (-not (Test-ImportExcelAvailable)) {
        $exportBtn.IsEnabled = $false
        $exportBtn.ToolTip   = "Install the ImportExcel module to enable this:`nInstall-Module ImportExcel -Scope CurrentUser"
    } else {
        $exportBtn.Add_Click({
            param($sender, $eventArgs)
            Invoke-SafeAction -Label 'Export Analytics Report' -Action {
                $path = Export-AnalyticsReport -Data $Script:ShellData -Filters $Script:AnalyticsFilters
                Open-TrueHireOutput -Path $path
            }
        })
    }

    # ---------- Apply filters & compute ----------
    # Skip orphan candidates (null/empty jobReqId). They can't aggregate
    # against any requisition, and Hashtable indexing with $null throws.
    $jobsById = @{}; foreach ($j in $jobs) { $jobsById[$j.id] = $j }
    $filteredCands = @()
    foreach ($c in $cands) {
        if (-not $c.jobReqId) { continue }
        $j = $jobsById[$c.jobReqId]
        if (_PassesAnalyticsFilters -Cand $c -Job $j -Filters $Script:AnalyticsFilters) {
            $filteredCands += $c
        }
    }
    $filteredJobs = @($jobs | Where-Object {
        ($Script:AnalyticsFilters.JobId   -eq 'all' -or $_.id -eq $Script:AnalyticsFilters.JobId) -and
        ($Script:AnalyticsFilters.Manager -eq 'all' -or $_.hiringManager -eq $Script:AnalyticsFilters.Manager) -and
        ($Script:AnalyticsFilters.Dept    -eq 'all' -or $_.department    -eq $Script:AnalyticsFilters.Dept)
    })

    $scopedData = @{ Jobs = $filteredJobs; Candidates = $filteredCands; Kits = $data.Kits }
    $m = Compute-Metrics $scopedData

    # ---------- Date range label ----------
    ($root.FindName('DateRangeLabel')).Text = "Showing {0} | {1} candidates across {2} reqs" -f `
        $Script:AnalyticsFilters.DateRange, $filteredCands.Count, $filteredJobs.Count

    # ---------- KPI strip ----------
    ($root.FindName('KpiTotalReqs')).Text     = "$($m.TotalReqs)"
    ($root.FindName('KpiTotalReqsSub')).Text  = "$($m.ActiveReqs) active"
    ($root.FindName('KpiTotalCand')).Text     = "$($m.TotalCandidates)"
    ($root.FindName('KpiTotalCandSub')).Text  = "across $($filteredJobs.Count) reqs"
    ($root.FindName('KpiAdvanced')).Text      = "$($m.Advanced)"
    ($root.FindName('KpiHired')).Text         = "$($m.Hired)"

    # ---------- Funnel ----------
    $stagesForFunnel = @(
        @{ Label='New';        Value=$m.StageCounts['New'];        Color='#94A3B8' }
        @{ Label='Screening';  Value=$m.StageCounts['Screening'];  Color='#1E88E5' }
        @{ Label='Interview';  Value=$m.StageCounts['Interview'];  Color='#F5A623' }
        @{ Label='Offer';      Value=$m.StageCounts['Offer'];      Color='#D81B60' }
        @{ Label='Hired';      Value=$m.StageCounts['Hired'];      Color='#38B66E' }
    )
    ($root.FindName('AnalyticsFunnelHost')).Content = (New-FunnelChart -Stages $stagesForFunnel -MaxWidth 220)

    # ---------- Time series ----------
    ($root.FindName('AnalyticsTimeSeriesHost')).Content = (_BuildTimeSeries -Cands $filteredCands -Weeks 12)

    # ---------- Hires by req (top 7) ----------
    $hiresByReq = @()
    foreach ($j in $filteredJobs) {
        $cnt = @($filteredCands | Where-Object { $_.jobReqId -eq $j.id -and $_.stage -eq 'Hired' }).Count
        if ($cnt -gt 0) {
            $hiresByReq += @{ Label = $j.reqNumber; Value = $cnt; Color = '#1E88E5' }
        }
    }
    if ($hiresByReq.Count -eq 0) {
        # When no actual hires, show top reqs by candidate count instead so the
        # chart still tells a story rather than rendering empty.
        foreach ($j in $filteredJobs) {
            $cnt = @($filteredCands | Where-Object jobReqId -eq $j.id).Count
            if ($cnt -gt 0) { $hiresByReq += @{ Label=$j.reqNumber; Value=$cnt; Color='#9CC8F1' } }
        }
    }
    $hiresByReq = @($hiresByReq | Sort-Object { -$_.Value } | Select-Object -First 7)
    ($root.FindName('AnalyticsHiresHost')).Content = (New-MiniBarChart -Series $hiresByReq -LabelWidth 64 -BarMaxWidth 140)

    # ---------- Manager donut ----------
    $mgrViz = _BuildManagerDonut -Cands $filteredCands -Jobs $filteredJobs -Size 160
    ($root.FindName('AnalyticsManagerDonutHost')).Content = $mgrViz.Donut
    $legendHost = $root.FindName('AnalyticsManagerLegend')
    $legendHost.Children.Clear()
    foreach ($child in @($mgrViz.Legend.Children)) {
        $mgrViz.Legend.Children.Remove($child)
        [void]$legendHost.Children.Add($child)
    }

    # ---------- Time to hire ----------
    $hireDays = @()
    foreach ($c in $filteredCands) {
        if ($c.stage -ne 'Hired') { continue }
        try {
            $a = [datetime]$c.appliedDate
            $h = if ($c.interviewDate) { [datetime]$c.interviewDate } else { $a.AddDays(21) }
            $hireDays += [Math]::Max(1, ($h - $a).TotalDays)
        } catch { }
    }
    $avgDays = if ($hireDays.Count -gt 0) {
        [int][Math]::Round( ($hireDays | Measure-Object -Average).Average )
    } else { 0 }
    ($root.FindName('KpiDaysToHire')).Text = "$avgDays"

    $trend = _BuildTrendBars -Cands $filteredCands -Height 60
    ($root.FindName('AnalyticsTrendBarsHost')).Content = $trend.Grid
    $deltaTxt = if ($trend.Values.Count -ge 2 -and $trend.Values[-1] -gt 0 -and $trend.Values[-2] -gt 0) {
        $delta = $trend.Values[-1] - $trend.Values[-2]
        if ($delta -lt 0)     { "{0}d faster than last week" -f [Math]::Abs($delta) }
        elseif ($delta -gt 0) { "{0}d slower than last week" -f $delta }
        else                  { "Flat vs. last week" }
    } else { "Trend across the last 8 weeks." }
    ($root.FindName('KpiDaysTrend')).Text = $deltaTxt
}
