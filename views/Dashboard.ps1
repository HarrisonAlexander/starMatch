<#
Dashboard.ps1 — landing view (ui_1_c). Top row: five KPI cards. Middle: a
funnel (candidates by stage), a donut (requisitions by status), and a bar
chart (hires by job req). Bottom: recent activity + upcoming interviews.
Everything reads through Compute-Metrics so adding a candidate elsewhere
immediately changes the numbers on the next tab visit.
#>

$Script:DashboardXaml = @'
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
      xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
      Margin="32,24,32,24">
  <Grid.RowDefinitions>
    <RowDefinition Height="Auto"/>   <!-- Welcome strip -->
    <RowDefinition Height="Auto"/>   <!-- KPI row -->
    <RowDefinition Height="Auto"/>   <!-- Charts row -->
    <RowDefinition Height="Auto"/>   <!-- Bottom row -->
  </Grid.RowDefinitions>

  <!-- Welcome strip -->
  <Grid Grid.Row="0" Margin="0,0,0,16">
    <StackPanel>
      <TextBlock Style="{StaticResource H2}" x:Name="WelcomeText" Text="Welcome back!"/>
      <TextBlock Style="{StaticResource Caption}"
                 Text="Here's what's happening with your hiring pipeline."/>
    </StackPanel>
  </Grid>

  <!-- KPI row -->
  <UniformGrid Grid.Row="1" Rows="1" Columns="4" Margin="0,0,0,18">
    <Border Style="{StaticResource Card}" Margin="0,0,8,0">
      <StackPanel>
        <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
          <Border Background="#E1EEF9" CornerRadius="8" Width="36" Height="36" Margin="0,0,10,0">
            <TextBlock Text="&#x1F4C4;" FontSize="18" Foreground="#1565C0"
                       HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <TextBlock Style="{StaticResource MicroLabel}" Text="ACTIVE REQUISITIONS" VerticalAlignment="Center"/>
        </StackPanel>
        <TextBlock x:Name="KpiActive" Style="{StaticResource KpiNumber}" Text="0"/>
        <TextBlock x:Name="KpiActiveSub" Style="{StaticResource Caption}" Text="open positions"/>
      </StackPanel>
    </Border>
    <Border Style="{StaticResource Card}" Margin="8,0,8,0">
      <StackPanel>
        <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
          <Border Background="#E5F4EC" CornerRadius="8" Width="36" Height="36" Margin="0,0,10,0">
            <TextBlock Text="&#x1F465;" FontSize="18" Foreground="#2A8E54"
                       HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <TextBlock Style="{StaticResource MicroLabel}" Text="TOTAL CANDIDATES" VerticalAlignment="Center"/>
        </StackPanel>
        <TextBlock x:Name="KpiCands" Style="{StaticResource KpiNumber}" Text="0"/>
        <TextBlock x:Name="KpiCandsSub" Style="{StaticResource Caption}" Text="across all requisitions"/>
      </StackPanel>
    </Border>
    <Border Style="{StaticResource Card}" Margin="8,0,8,0">
      <StackPanel>
        <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
          <Border Background="#FFF1DF" CornerRadius="8" Width="36" Height="36" Margin="0,0,10,0">
            <TextBlock Text="&#x1F4C8;" FontSize="18" Foreground="#C77000"
                       HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <TextBlock Style="{StaticResource MicroLabel}" Text="ADVANCED TO INTERVIEW" VerticalAlignment="Center"/>
        </StackPanel>
        <TextBlock x:Name="KpiAdv" Style="{StaticResource KpiNumber}" Text="0"/>
        <TextBlock x:Name="KpiAdvSub" Style="{StaticResource Caption}" Text="in active pipelines"/>
      </StackPanel>
    </Border>
    <Border Style="{StaticResource Card}" Margin="8,0,0,0">
      <StackPanel>
        <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
          <Border Background="#E1EEF9" CornerRadius="8" Width="36" Height="36" Margin="0,0,10,0">
            <TextBlock Text="&#x2605;" FontSize="18" Foreground="#1E88E5"
                       HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <TextBlock Style="{StaticResource MicroLabel}" Text="HIRED" VerticalAlignment="Center"/>
        </StackPanel>
        <TextBlock x:Name="KpiHired" Style="{StaticResource KpiNumber}" Text="0"/>
        <TextBlock x:Name="KpiHiredSub" Style="{StaticResource Caption}" Text="this period"/>
      </StackPanel>
    </Border>
  </UniformGrid>

  <!-- Charts row -->
  <Grid Grid.Row="2" Margin="0,0,0,18">
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="*"/>
      <ColumnDefinition Width="*"/>
      <ColumnDefinition Width="*"/>
    </Grid.ColumnDefinitions>

    <Border Grid.Column="0" Style="{StaticResource Card}" Margin="0,0,8,0">
      <StackPanel>
        <TextBlock Style="{StaticResource H3}" Text="Candidates by Stage" Margin="0,0,0,12"/>
        <StackPanel x:Name="FunnelHost" Margin="0,0,0,4"/>
      </StackPanel>
    </Border>

    <Border Grid.Column="1" Style="{StaticResource Card}" Margin="8,0,8,0">
      <StackPanel>
        <TextBlock Style="{StaticResource H3}" Text="Requisitions by Status" Margin="0,0,0,12"/>
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>
          <Grid x:Name="DonutHost" Grid.Column="0" Width="140" Height="140" Margin="0,0,16,0"/>
          <StackPanel Grid.Column="1" x:Name="DonutLegendHost" VerticalAlignment="Center"/>
        </Grid>
      </StackPanel>
    </Border>

    <Border Grid.Column="2" Style="{StaticResource Card}" Margin="8,0,0,0">
      <StackPanel>
        <TextBlock Style="{StaticResource H3}" Text="Hires by Job Requisition" Margin="0,0,0,12"/>
        <StackPanel x:Name="HireBarHost"/>
      </StackPanel>
    </Border>
  </Grid>

  <!-- Bottom row -->
  <Grid Grid.Row="3">
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="2*"/>
      <ColumnDefinition Width="1*"/>
    </Grid.ColumnDefinitions>

    <Border Grid.Column="0" Style="{StaticResource Card}" Margin="0,0,8,0">
      <StackPanel>
        <TextBlock Style="{StaticResource H3}" Text="Recent Activity" Margin="0,0,0,12"/>
        <StackPanel x:Name="ActivityHost"/>
      </StackPanel>
    </Border>

    <Border Grid.Column="1" Style="{StaticResource Card}" Margin="8,0,0,0">
      <StackPanel>
        <TextBlock Style="{StaticResource H3}" Text="Upcoming Interviews" Margin="0,0,0,12"/>
        <StackPanel x:Name="UpcomingHost"/>
      </StackPanel>
    </Border>
  </Grid>
</Grid>
'@

function Show-DashboardView {
    param($Container)
    $root = [System.Windows.Markup.XamlReader]::Parse($Script:DashboardXaml)
    [void]$Container.Children.Add($root)
    $data    = $Script:ShellData
    $metrics = Compute-Metrics $data

    # Welcome name: try AD first (cached from the shell's earlier probe),
    # fall back to whatever Settings.currentUser has, and finally to a
    # generic greeting when neither source can give us a first name.
    $first = ''
    $adUser = Get-CurrentUserFromAd
    if ($adUser -and $adUser.FirstName) {
        $first = $adUser.FirstName
    } elseif ($data.Settings -and $data.Settings.currentUser -and $data.Settings.currentUser.name) {
        $first = ([string]$data.Settings.currentUser.name -split '\s+')[0]
    }
    $welcome = if ($first) { "Welcome back, $first!" } else { 'Welcome back!' }
    ($root.FindName('WelcomeText')).Text = $welcome

    # KPI numbers ------------------------------------------------------------
    ($root.FindName('KpiActive')).Text  = "$($metrics.ActiveReqs)"
    ($root.FindName('KpiCands')).Text   = "$($metrics.TotalCandidates)"
    ($root.FindName('KpiAdv')).Text     = "$($metrics.Advanced)"
    ($root.FindName('KpiHired')).Text   = "$($metrics.Hired)"

    # Funnel: candidates by stage --------------------------------------------
    $stageColors = @{
        'New'='#94A3B8'; 'Screening'='#1E88E5'; 'Interview'='#F5A623';
        'Offer'='#D81B60'; 'Hired'='#2A8E54'; 'Rejected'='#B23A3A'
    }
    $stages = @()
    foreach ($k in $metrics.StageCounts.Keys) {
        $stages += @{ Label=$k; Value=$metrics.StageCounts[$k]; Color=$stageColors[$k] }
    }
    $funnel = New-FunnelChart -Stages $stages -MaxWidth 280
    [void]($root.FindName('FunnelHost')).Children.Add($funnel)

    # Donut: requisitions by status ------------------------------------------
    $statusColors = @{
        'Active'='#2A8E54'; 'Draft'='#94A3B8'; 'On Hold'='#F5A623';
        'Closed'='#B23A3A'; 'Filled'='#1565C0'
    }
    $donutHost = $root.FindName('DonutHost')
    $legend    = $root.FindName('DonutLegendHost')
    # $total is the actual count (shown as the donut's center label, can be 0).
    # $denom is the divide-by-zero guard for the arc-sweep math below. Keep
    # them separate or an empty dataset shows "1" in the center.
    $total = [int](($metrics.StatusCounts.Values | Measure-Object -Sum).Sum)
    $denom = if ($total -gt 0) { $total } else { 1 }
    $cx = 70; $cy = 70; $r = 56
    $start = 0.0
    foreach ($k in $metrics.StatusCounts.Keys) {
        $cnt = $metrics.StatusCounts[$k]
        if ($cnt -le 0) { continue }
        $sweep = ([double]$cnt / [double]$denom) * 360.0
        $end = $start + $sweep
        $a1 = ($start - 90.0) * [Math]::PI / 180.0
        $a2 = ($end   - 90.0) * [Math]::PI / 180.0
        $p1 = New-Object System.Windows.Point (($cx + $r * [Math]::Cos($a1)), ($cy + $r * [Math]::Sin($a1)))
        $p2 = New-Object System.Windows.Point (($cx + $r * [Math]::Cos($a2)), ($cy + $r * [Math]::Sin($a2)))
        $isLarge = $sweep -gt 180.0
        $arc = New-Object System.Windows.Media.ArcSegment ($p2,
            (New-Object System.Windows.Size ($r,$r)), 0, $isLarge, 'Clockwise', $true)
        $fig = New-Object System.Windows.Media.PathFigure
        $fig.StartPoint = $p1
        [void]$fig.Segments.Add($arc)
        $geom = New-Object System.Windows.Media.PathGeometry
        [void]$geom.Figures.Add($fig)
        $path = New-Object System.Windows.Shapes.Path
        $path.Stroke = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($statusColors[$k])))
        $path.StrokeThickness = 18
        $path.StrokeStartLineCap = 'Flat'
        $path.StrokeEndLineCap   = 'Flat'
        $path.Data = $geom
        [void]$donutHost.Children.Add($path)
        $start = $end

        # Legend row
        $leg = New-Object System.Windows.Controls.StackPanel
        $leg.Orientation = 'Horizontal'
        $leg.Margin = '0,0,0,6'
        $sw = New-Object System.Windows.Shapes.Ellipse
        $sw.Width = 10; $sw.Height = 10; $sw.Margin = '0,0,8,0'
        $sw.Fill = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($statusColors[$k])))
        $sw.VerticalAlignment = 'Center'
        [void]$leg.Children.Add($sw)
        $lt = New-Object System.Windows.Controls.TextBlock
        $lt.Text = "$k ($cnt)"
        $lt.FontSize = 12
        $lt.VerticalAlignment = 'Center'
        $lt.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#2C3E50')))
        [void]$leg.Children.Add($lt)
        [void]$legend.Children.Add($leg)
    }
    # Center total label
    $lbl = New-Object System.Windows.Controls.TextBlock
    $lbl.Text = "$total"
    $lbl.HorizontalAlignment = 'Center'
    $lbl.VerticalAlignment   = 'Center'
    $lbl.FontWeight = 'Bold'
    $lbl.FontSize = 22
    $lbl.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#0B2C45')))
    [void]$donutHost.Children.Add($lbl)

    # Hires by job req bars --------------------------------------------------
    $hireSeries = @()
    foreach ($j in $data.Jobs) {
        $hired = @($data.Candidates | Where-Object { $_.jobReqId -eq $j.id -and $_.stage -eq 'Hired' }).Count
        $offers = @($data.Candidates | Where-Object { $_.jobReqId -eq $j.id -and $_.stage -eq 'Offer' }).Count
        $val = $hired + $offers
        if ($val -gt 0) {
            $hireSeries += @{ Label = $j.title; Value = $val; Color = '#1E88E5' }
        }
    }
    if ($hireSeries.Count -eq 0) {
        # Fall back to top-5 by candidate count so the chart still says something
        $hireSeries = @()
        $tops = $data.Jobs | Sort-Object candidateCount -Descending | Select-Object -First 5
        foreach ($j in $tops) {
            $hireSeries += @{ Label = $j.title; Value = $j.candidateCount; Color = '#1E88E5' }
        }
    }
    $bars = New-MiniBarChart -Series $hireSeries -LabelWidth 150 -BarMaxWidth 180
    [void]($root.FindName('HireBarHost')).Children.Add($bars)

    # Recent activity --------------------------------------------------------
    $activityHost = $root.FindName('ActivityHost')
    foreach ($e in (Find-RecentActivity $data 6)) {
        $row = New-Object System.Windows.Controls.Grid
        $row.Margin = '0,0,0,10'
        $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = 'Auto'
        $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = '*'
        $c3 = New-Object System.Windows.Controls.ColumnDefinition; $c3.Width = 'Auto'
        [void]$row.ColumnDefinitions.Add($c1); [void]$row.ColumnDefinitions.Add($c2); [void]$row.ColumnDefinitions.Add($c3)

        $dot = New-Object System.Windows.Controls.Border
        $dot.Width = 30; $dot.Height = 30; $dot.CornerRadius = '15'
        $dot.Margin = '0,0,10,0'
        $dot.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($e.Color)))
        $dotTxt = New-Object System.Windows.Controls.TextBlock
        $dotTxt.Text = $e.Icon; $dotTxt.Foreground = 'White'
        $dotTxt.FontWeight = 'Bold'; $dotTxt.FontSize = 12
        $dotTxt.HorizontalAlignment = 'Center'; $dotTxt.VerticalAlignment = 'Center'
        $dot.Child = $dotTxt
        [System.Windows.Controls.Grid]::SetColumn($dot, 0)
        [void]$row.Children.Add($dot)

        $msg = New-Object System.Windows.Controls.TextBlock
        $msg.Text = $e.Text
        $msg.FontSize = 13
        $msg.TextWrapping = 'Wrap'
        $msg.VerticalAlignment = 'Center'
        $msg.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#2C3E50')))
        [System.Windows.Controls.Grid]::SetColumn($msg, 1)
        [void]$row.Children.Add($msg)

        $time = New-Object System.Windows.Controls.TextBlock
        $time.Text = $e.When.ToString('MMM d')
        $time.FontSize = 11
        $time.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#94A3B8')))
        $time.VerticalAlignment = 'Center'
        $time.Margin = '8,0,0,0'
        [System.Windows.Controls.Grid]::SetColumn($time, 2)
        [void]$row.Children.Add($time)

        [void]$activityHost.Children.Add($row)
    }

    # Upcoming interviews ----------------------------------------------------
    # Strict date-driven semantics: a candidate appears here ONLY if they
    # have a parseable interviewDate >= today. No date or past date -> not
    # upcoming. This intentionally diverges from the Advanced KPI count
    # (which is purely stage-based) -- they answer different questions:
    # "how many candidates are in the pipeline at Interview+ stage?" vs
    # "what interviews do I need to prepare for next?". Mixing undated
    # rows in here made the section feel like a stale to-do list.
    $upHost = $root.FindName('UpcomingHost')
    $today = Get-Date
    $upcoming = @($data.Candidates | Where-Object {
        if (-not $_.interviewDate) { return $false }
        $when = $null
        try { $when = [datetime]$_.interviewDate } catch { return $false }
        return ($when -ge $today.Date)
    } | Sort-Object { [datetime]$_.interviewDate } | Select-Object -First 5)

    if ($upcoming.Count -eq 0) {
        $tx = New-Object System.Windows.Controls.TextBlock
        $tx.Text = 'No interviews scheduled.'
        $tx.FontSize = 12
        $tx.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#94A3B8')))
        [void]$upHost.Children.Add($tx)
    }
    foreach ($c in $upcoming) {
        $row = New-Object System.Windows.Controls.Grid
        $row.Margin = '0,0,0,10'
        $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = 'Auto'
        $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = '*'
        [void]$row.ColumnDefinitions.Add($c1); [void]$row.ColumnDefinitions.Add($c2)

        $av = New-Avatar -Initials (Get-Initials $c.name) -ColorHex $c.avatarColor -Size 36
        $av.Margin = '0,0,10,0'
        [System.Windows.Controls.Grid]::SetColumn($av, 0)
        [void]$row.Children.Add($av)

        $stack = New-Object System.Windows.Controls.StackPanel
        $stack.VerticalAlignment = 'Center'
        $n = New-Object System.Windows.Controls.TextBlock
        $n.Text = $c.name; $n.FontWeight = 'SemiBold'; $n.FontSize = 13
        $n.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#0B2C45')))
        [void]$stack.Children.Add($n)
        $sub = New-Object System.Windows.Controls.TextBlock
        $whenText = if ($c.interviewDate) {
            try { ([datetime]$c.interviewDate).ToString('MMM d, h:mm tt') } catch { 'Date TBD' }
        } else { 'Date TBD' }
        $sub.Text = ("{0} - {1}" -f $c.position, $whenText)
        $sub.FontSize = 11
        $sub.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#6B7B8C')))
        [void]$stack.Children.Add($sub)
        [System.Windows.Controls.Grid]::SetColumn($stack, 1)
        [void]$row.Children.Add($stack)

        [void]$upHost.Children.Add($row)
    }
}
