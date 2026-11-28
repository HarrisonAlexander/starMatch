<#
JobReqs.ps1 — Job Requisitions view (ui_2). Left rail lists every requisition
with status pill and badge counts. Right pane is the grid of all reqs with
search/filter on top. Clicking a req in the rail opens the detail dialog
where you can edit fields and jump to its candidates or interview kit.
#>

$Script:JobReqsXaml = @'
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
      xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
      Margin="0">
  <Grid.ColumnDefinitions>
    <ColumnDefinition Width="280"/>
    <ColumnDefinition Width="*"/>
  </Grid.ColumnDefinitions>

  <!-- ============  Left rail  ============ -->
  <Border Grid.Column="0" Background="White" BorderBrush="{StaticResource CardBorder}"
          BorderThickness="0,0,1,0">
    <Grid Margin="20,24,20,20">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <TextBlock Grid.Row="0" Style="{StaticResource H3}" Text="Job Requisitions" Margin="0,0,0,12"/>
      <Button x:Name="BtnNewReq" Grid.Row="1" Content="+ New Requisition"
              Style="{StaticResource PrimaryBtn}" Margin="0,0,0,8"/>
      <StackPanel Grid.Row="2" Margin="0,0,0,12">
        <Button x:Name="BtnImport" Content="Import..."
                Style="{StaticResource GhostBtn}" Margin="0,0,0,8"/>
        <Button x:Name="BtnExportAll" Content="Backup / Export All..."
                Style="{StaticResource GhostBtn}"/>
      </StackPanel>
      <ComboBox x:Name="StatusFilter" Grid.Row="3" Style="{StaticResource ComboField}"
                Margin="0,0,0,12">
        <ComboBoxItem Content="All Status" IsSelected="True"/>
        <ComboBoxItem Content="Active"/>
        <ComboBoxItem Content="Draft"/>
        <ComboBoxItem Content="On Hold"/>
        <ComboBoxItem Content="Closed"/>
        <ComboBoxItem Content="Filled"/>
      </ComboBox>
      <ScrollViewer Grid.Row="4" VerticalScrollBarVisibility="Auto">
        <StackPanel x:Name="JobListPanel"/>
      </ScrollViewer>
      <TextBlock x:Name="JobListCount" Grid.Row="5" Style="{StaticResource Caption}"
                 Margin="0,12,0,0" Text=""/>
    </Grid>
  </Border>

  <!-- ============  Right grid  ============ -->
  <Grid Grid.Column="1" Margin="28,24,28,24">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
    </Grid.RowDefinitions>

    <Grid Grid.Row="0" Margin="0,0,0,16">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
      <TextBlock Grid.Column="0" Style="{StaticResource H2}" Text="All Job Requisitions"
                 VerticalAlignment="Center"/>
      <TextBox x:Name="SearchBox" Grid.Column="1" Style="{StaticResource SearchField}"
               Width="260"/>
    </Grid>

    <!-- Grid header -->
    <Border Grid.Row="1" Background="#F8FAFC" BorderBrush="{StaticResource CardBorder}"
            BorderThickness="1" CornerRadius="8,8,0,0" Padding="0">
      <Grid Margin="16,10">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="100"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="160"/>
          <ColumnDefinition Width="120"/>
          <ColumnDefinition Width="110"/>
          <ColumnDefinition Width="110"/>
          <ColumnDefinition Width="60"/>
        </Grid.ColumnDefinitions>
        <TextBlock Grid.Column="0" Style="{StaticResource GridHeaderText}" Text="REQUISITION #"/>
        <TextBlock Grid.Column="1" Style="{StaticResource GridHeaderText}" Text="POSITION TITLE"/>
        <TextBlock Grid.Column="2" Style="{StaticResource GridHeaderText}" Text="HIRING MANAGER"/>
        <TextBlock Grid.Column="3" Style="{StaticResource GridHeaderText}" Text="STATUS"/>
        <TextBlock Grid.Column="4" Style="{StaticResource GridHeaderText}" Text="CANDIDATES"/>
        <TextBlock Grid.Column="5" Style="{StaticResource GridHeaderText}" Text="CREATED DATE"/>
        <TextBlock Grid.Column="6" Style="{StaticResource GridHeaderText}" Text=""/>
      </Grid>
    </Border>

    <Border Grid.Row="2" Background="White" BorderBrush="{StaticResource CardBorder}"
            BorderThickness="1,0,1,1" CornerRadius="0,0,8,8">
      <ScrollViewer VerticalScrollBarVisibility="Auto">
        <StackPanel x:Name="JobGridPanel"/>
      </ScrollViewer>
    </Border>
  </Grid>
</Grid>
'@

function _MakeRailRow {
    <#
    One card-row for the left rail. Click navigates to the detail dialog.
    #>
    param($Job)
    $b = New-Object System.Windows.Controls.Border
    $b.Background = 'White'
    $b.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#E4E8EF')))
    $b.BorderThickness = '1'
    $b.CornerRadius = '8'
    $b.Padding = '12'
    $b.Margin = '0,0,0,8'
    $b.Cursor = 'Hand'
    $b.Tag = $Job.id

    # Row 1: title only, allowed to wrap. Pill moved to row 2 so a long
    # title doesn't get truncated under the status chip.
    $stack = New-Object System.Windows.Controls.StackPanel

    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = $Job.title
    $title.FontWeight = 'SemiBold'
    $title.FontSize = 13
    $title.TextWrapping = 'Wrap'
    $title.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#0B2C45')))
    [void]$stack.Children.Add($title)

    # Row 2: req number on the left, status pill on the right
    $row2 = New-Object System.Windows.Controls.Grid
    $row2.Margin = '0,4,0,0'
    $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = '*'
    $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = 'Auto'
    [void]$row2.ColumnDefinitions.Add($c1); [void]$row2.ColumnDefinitions.Add($c2)

    $sub = New-Object System.Windows.Controls.TextBlock
    $sub.Text = $Job.reqNumber
    $sub.FontSize = 11
    $sub.VerticalAlignment = 'Center'
    $sub.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#6B7B8C')))
    [System.Windows.Controls.Grid]::SetColumn($sub, 0)
    [void]$row2.Children.Add($sub)

    $pill = New-StatusPill -Status $Job.status
    [System.Windows.Controls.Grid]::SetColumn($pill, 1)
    [void]$row2.Children.Add($pill)

    [void]$stack.Children.Add($row2)

    $b.Child = $stack
    $b.Add_MouseLeftButtonUp({
        param($s,$e)
        Show-JobReqDetail $s.Tag
    }.GetNewClosure())
    return $b
}

function _MakeGridRow {
    # $CandidateCount is the live count computed by the caller, not the
    # decorative $Job.candidateCount field stored on the JSON record (which
    # drifts as candidates are added/removed via the UI).
    param($Job, [int]$CandidateCount = 0)
    $b = New-Object System.Windows.Controls.Border
    $b.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#EDF0F4')))
    $b.BorderThickness = '0,0,0,1'
    $b.Padding = '0'
    $b.Cursor = 'Hand'
    $b.Tag = $Job.id

    $g = New-Object System.Windows.Controls.Grid
    $g.Margin = '16,12'
    # Last column widened to 88 to fit the ✕ delete button + › open arrow
    # without crowding. Header at the top is still 60 wide; that's
    # cosmetic - the header column just labels what's underneath.
    $widths = 100,'*',160,120,110,110,88
    foreach ($w in $widths) {
        $cd = New-Object System.Windows.Controls.ColumnDefinition
        $cd.Width = if ($w -is [string]) { '*' } else { [System.Windows.GridLength]::new($w) }
        [void]$g.ColumnDefinitions.Add($cd)
    }

    $t0 = New-Object System.Windows.Controls.TextBlock
    $t0.Text = $Job.reqNumber; $t0.VerticalAlignment = 'Center'
    $t0.FontWeight = 'SemiBold'; $t0.FontSize = 12.5
    $t0.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#1565C0')))
    [System.Windows.Controls.Grid]::SetColumn($t0, 0)
    [void]$g.Children.Add($t0)

    $t1 = New-Object System.Windows.Controls.TextBlock
    $t1.Text = $Job.title; $t1.VerticalAlignment = 'Center'
    $t1.FontWeight = 'SemiBold'; $t1.FontSize = 13
    $t1.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#0B2C45')))
    [System.Windows.Controls.Grid]::SetColumn($t1, 1)
    [void]$g.Children.Add($t1)

    $t2 = New-Object System.Windows.Controls.TextBlock
    $t2.Text = $Job.hiringManager; $t2.VerticalAlignment = 'Center'
    $t2.FontSize = 12.5
    $t2.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#2C3E50')))
    [System.Windows.Controls.Grid]::SetColumn($t2, 2)
    [void]$g.Children.Add($t2)

    $pill = New-StatusPill -Status $Job.status
    [System.Windows.Controls.Grid]::SetColumn($pill, 3)
    [void]$g.Children.Add($pill)

    $t4 = New-Object System.Windows.Controls.TextBlock
    $t4.Text = "$CandidateCount"
    $t4.VerticalAlignment = 'Center'; $t4.FontSize = 12.5
    $t4.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#2C3E50')))
    [System.Windows.Controls.Grid]::SetColumn($t4, 4)
    [void]$g.Children.Add($t4)

    $t5 = New-Object System.Windows.Controls.TextBlock
    $t5.Text = ([datetime]$Job.createdDate).ToString('MM/dd/yyyy')
    $t5.VerticalAlignment = 'Center'; $t5.FontSize = 12.5
    $t5.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#6B7B8C')))
    [System.Windows.Controls.Grid]::SetColumn($t5, 5)
    [void]$g.Children.Add($t5)

    # Column 6: [ ✕ delete ][ › open ] right-aligned. Button click on
    # the ✕ short-circuits the row's MouseLeftButtonUp (the click event is
    # consumed by ButtonBase before it bubbles), so deleting doesn't also
    # open the detail dialog.
    $actions = New-Object System.Windows.Controls.StackPanel
    $actions.Orientation = 'Horizontal'
    $actions.HorizontalAlignment = 'Right'
    $actions.VerticalAlignment = 'Center'

    $btnDel = New-Object System.Windows.Controls.Button
    $btnDel.Content = '✕'
    $btnDel.ToolTip = 'Delete requisition (cascades to kit + candidates)'
    $btnDel.Background = 'Transparent'
    $btnDel.BorderThickness = '0'
    $btnDel.Padding = '6,2'
    $btnDel.FontSize = 13
    $btnDel.FontWeight = 'SemiBold'
    $btnDel.Cursor = 'Hand'
    $btnDel.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#B23A3A')))
    $btnDel.Tag = $Job.id
    # param($sender,$e) + no .GetNewClosure() so Show-DeleteJobReqDialog
    # resolves at fire time. Same pattern as the Candidates view print
    # buttons and the kit detail buttons.
    $btnDel.Add_Click({
        param($sender, $eventArgs)
        Show-DeleteJobReqDialog $sender.Tag
    })
    [void]$actions.Children.Add($btnDel)

    $arrow = New-Object System.Windows.Controls.TextBlock
    $arrow.Text = "›"
    $arrow.FontSize = 18; $arrow.FontWeight = 'Bold'
    $arrow.VerticalAlignment = 'Center'
    $arrow.Margin = '6,0,0,0'
    $arrow.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#94A3B8')))
    [void]$actions.Children.Add($arrow)

    [System.Windows.Controls.Grid]::SetColumn($actions, 6)
    [void]$g.Children.Add($actions)

    $b.Child = $g
    $b.Add_MouseEnter({ $args[0].Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#F8FAFC'))) })
    $b.Add_MouseLeave({ $args[0].Background = $null })
    $b.Add_MouseLeftButtonUp({
        param($s,$e)
        Show-JobReqDetail $s.Tag
    }.GetNewClosure())
    return $b
}

function Show-JobRequisitionsView {
    param($Container)
    $root = [System.Windows.Markup.XamlReader]::Parse($Script:JobReqsXaml)
    [void]$Container.Children.Add($root)
    $data = $Script:ShellData

    $railPanel = $root.FindName('JobListPanel')
    $gridPanel = $root.FindName('JobGridPanel')
    $searchBox = $root.FindName('SearchBox')
    $statusBox = $root.FindName('StatusFilter')
    $countTxt  = $root.FindName('JobListCount')

    $render = {
        param($filter)
        $railPanel.Children.Clear()
        $gridPanel.Children.Clear()
        $jobs = @($data.Jobs)
        if ($filter -and $filter -ne 'All Status') {
            $jobs = @($jobs | Where-Object status -eq $filter)
        }
        $q = $searchBox.Text
        if ($q) {
            $jobs = @($jobs | Where-Object {
                $_.title -like "*$q*" -or
                $_.reqNumber -like "*$q*" -or
                $_.hiringManager -like "*$q*"
            })
        }
        # Pre-bucket candidates by job id so we count each job in O(1) instead
        # of scanning the whole candidate list per row. Skip orphans (candidate
        # with null/empty jobReqId): Hashtable.ContainsKey throws on $null keys.
        # Orphans can sneak in via an aborted "+ Add Candidate" flow that
        # creates a candidate before the user picks a job.
        $candsByJob = @{}
        foreach ($c in $data.Candidates) {
            if (-not $c.jobReqId) { continue }
            if (-not $candsByJob.ContainsKey($c.jobReqId)) { $candsByJob[$c.jobReqId] = 0 }
            $candsByJob[$c.jobReqId] = $candsByJob[$c.jobReqId] + 1
        }
        foreach ($j in $jobs) {
            $live = if ($candsByJob.ContainsKey($j.id)) { $candsByJob[$j.id] } else { 0 }
            [void]$railPanel.Children.Add( (_MakeRailRow $j) )
            [void]$gridPanel.Children.Add( (_MakeGridRow $j $live) )
        }
        $countTxt.Text = ("Showing {0} of {1} requisitions" -f $jobs.Count, $data.Jobs.Count)
    }.GetNewClosure()

    & $render 'All Status'

    $statusBox.Add_SelectionChanged({
        $sel = $statusBox.SelectedItem
        $val = if ($sel) { "$($sel.Content)" } else { 'All Status' }
        & $render $val
    }.GetNewClosure())
    $searchBox.Add_TextChanged({
        $sel = $statusBox.SelectedItem
        $val = if ($sel) { "$($sel.Content)" } else { 'All Status' }
        & $render $val
    }.GetNewClosure())

    $root.FindName('BtnNewReq').Add_Click({
        $new = New-JobReq
        # Auto-spin an empty 1:1 interview kit so the Interview Kits tab
        # has something to customize the moment the user switches there.
        # Without this the kits view sees the new job has no kit and the
        # user has to hit "+ New Interview Kit" by hand.
        $kit = New-InterviewKit -JobReqId $new.id -Name 'New Interview Kit'
        $new.interviewKitId = $kit.id
        $data.Jobs = @($data.Jobs) + $new
        $data.Kits = @($data.Kits) + $kit
        Save-Jobs $data
        Save-Kits $data
        Show-JobReqDetail $new.id
    }.GetNewClosure())

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
                    # Import mutates $Script:ShellData in place and is non-atomic;
                    # on a mid-import throw nothing is persisted (Save-* below never
                    # runs), so a reload restores the pre-import state from disk.
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

}

# ----------------------------------------------------------------------------
# Job-requisition detail dialog
# ----------------------------------------------------------------------------
$Script:JobReqDetailXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Job Requisition" Width="780" Height="700"
        WindowStartupLocation="CenterOwner"
        Background="{StaticResource PageBg}" FontFamily="Segoe UI">
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="78"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <Border x:Name="HeroBorder" Grid.Row="0" Background="{StaticResource BannerFallback}">
      <Grid Margin="24,14">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <StackPanel Grid.Column="0">
          <TextBlock x:Name="DlgTitle" Foreground="White" FontSize="20" FontWeight="Bold" Text="Edit Requisition"/>
          <TextBlock x:Name="DlgSub" Foreground="#CBDBEA" FontSize="12" Text=""/>
        </StackPanel>
        <Border x:Name="DlgPillHost" Grid.Column="1" VerticalAlignment="Center"/>
      </Grid>
    </Border>
    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="24,18">
      <StackPanel>
        <UniformGrid Rows="1" Columns="2" Margin="0,0,0,12">
          <StackPanel Margin="0,0,8,0">
            <TextBlock Style="{StaticResource MicroLabel}" Text="REQUISITION #" Margin="0,0,0,4"/>
            <TextBox x:Name="TbReqNumber" Style="{StaticResource Field}"/>
          </StackPanel>
          <StackPanel Margin="8,0,0,0">
            <TextBlock Style="{StaticResource MicroLabel}" Text="STATUS" Margin="0,0,0,4"/>
            <ComboBox x:Name="CbStatus" Style="{StaticResource ComboField}">
              <ComboBoxItem Content="Active"/>
              <ComboBoxItem Content="Draft"/>
              <ComboBoxItem Content="On Hold"/>
              <ComboBoxItem Content="Closed"/>
              <ComboBoxItem Content="Filled"/>
            </ComboBox>
          </StackPanel>
        </UniformGrid>
        <StackPanel Margin="0,0,0,12">
          <TextBlock Style="{StaticResource MicroLabel}" Text="POSITION TITLE" Margin="0,0,0,4"/>
          <TextBox x:Name="TbTitle" Style="{StaticResource Field}"/>
        </StackPanel>
        <UniformGrid Rows="1" Columns="2" Margin="0,0,0,12">
          <StackPanel Margin="0,0,8,0">
            <TextBlock Style="{StaticResource MicroLabel}" Text="CLASSIFICATION" Margin="0,0,0,4"/>
            <ComboBox x:Name="CbPosition" Style="{StaticResource ComboField}" IsEditable="True"/>
          </StackPanel>
          <StackPanel Margin="8,0,0,0">
            <TextBlock Style="{StaticResource MicroLabel}" Text="HIRING MANAGER" Margin="0,0,0,4"/>
            <TextBox x:Name="TbHM" Style="{StaticResource Field}"/>
          </StackPanel>
        </UniformGrid>
        <UniformGrid Rows="1" Columns="3" Margin="0,0,0,12">
          <StackPanel Margin="0,0,8,0">
            <TextBlock Style="{StaticResource MicroLabel}" Text="DEPARTMENT" Margin="0,0,0,4"/>
            <TextBox x:Name="TbDept" Style="{StaticResource Field}"/>
          </StackPanel>
          <StackPanel Margin="4,0,4,0">
            <TextBlock Style="{StaticResource MicroLabel}" Text="LOCATION" Margin="0,0,0,4"/>
            <TextBox x:Name="TbLoc" Style="{StaticResource Field}"/>
          </StackPanel>
          <StackPanel Margin="8,0,0,0">
            <TextBlock Style="{StaticResource MicroLabel}" Text="OPENINGS" Margin="0,0,0,4"/>
            <TextBox x:Name="TbOpenings" Style="{StaticResource Field}"/>
          </StackPanel>
        </UniformGrid>
        <UniformGrid Rows="1" Columns="2" Margin="0,0,0,12">
          <StackPanel Margin="0,0,8,0">
            <TextBlock Style="{StaticResource MicroLabel}" Text="CREATED" Margin="0,0,0,4"/>
            <DatePicker x:Name="DpCreated"
                        SelectedDateFormat="Short"
                        FirstDayOfWeek="Sunday"
                        Height="34"/>
          </StackPanel>
          <StackPanel Margin="8,0,0,0">
            <TextBlock Style="{StaticResource MicroLabel}" Text="TARGET HIRE DATE" Margin="0,0,0,4"/>
            <DatePicker x:Name="DpTarget"
                        SelectedDateFormat="Short"
                        FirstDayOfWeek="Sunday"
                        Height="34"/>
          </StackPanel>
        </UniformGrid>
        <StackPanel Margin="0,0,0,12">
          <TextBlock Style="{StaticResource MicroLabel}" Text="DESCRIPTION" Margin="0,0,0,4"/>
          <TextBox x:Name="TbDesc" Style="{StaticResource MultilineField}" MinHeight="110"/>
        </StackPanel>

        <!-- Linked entities -->
        <Border Style="{StaticResource FlatCard}" Margin="0,4,0,12">
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0">
              <TextBlock Style="{StaticResource H3}" Text="Interview Kit"/>
              <TextBlock x:Name="KitInfo" Style="{StaticResource Caption}" Text="No kit attached"/>
            </StackPanel>
            <Button x:Name="BtnOpenKit" Grid.Column="1" Content="Open Kit" Style="{StaticResource GhostBtn}"/>
          </Grid>
        </Border>
        <Border Style="{StaticResource FlatCard}">
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <StackPanel Grid.Column="0">
              <TextBlock Style="{StaticResource H3}" Text="Candidates"/>
              <TextBlock x:Name="CandsInfo" Style="{StaticResource Caption}" Text=""/>
            </StackPanel>
            <StackPanel Grid.Column="1" Orientation="Horizontal">
              <Button x:Name="BtnOpenCands" Content="View Candidates"  Style="{StaticResource GhostBtn}" Margin="0,0,8,0"/>
              <Button x:Name="BtnAddCand"   Content="+ Add Candidate"  Style="{StaticResource BlueBtn}"/>
            </StackPanel>
          </Grid>
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
        <StackPanel Grid.Column="0" Orientation="Horizontal" HorizontalAlignment="Left">
          <Button x:Name="BtnDelete" Content="Delete" Style="{StaticResource GhostBtn}"
                  Foreground="#B23A3A" Margin="0,0,8,0"/>
          <Button x:Name="BtnExport" Content="Export..." Style="{StaticResource GhostBtn}"/>
        </StackPanel>
        <StackPanel Grid.Column="1" Orientation="Horizontal">
          <Button x:Name="BtnCancel" Content="Cancel" Style="{StaticResource GhostBtn}" Margin="0,0,8,0"/>
          <Button x:Name="BtnSave"   Content="Save Changes" Style="{StaticResource PrimaryBtn}"/>
        </StackPanel>
      </Grid>
    </Border>
  </Grid>
</Window>
'@

function Show-JobReqDetail {
    param([string]$JobId)
    $data = $Script:ShellData
    $job  = Get-JobById $data $JobId
    if (-not $job) { return }
    $w = ConvertTo-Window -Xaml $Script:JobReqDetailXaml
    # No banner image on this dialog - the navy BannerFallback gradient
    # behind the title reads cleaner than the cover.png painted underneath
    # the text. White title / light-blue subtitle stand out on their own.
    $w.Owner = $Script:Shell

    ($w.FindName('DlgTitle')).Text = "$($job.reqNumber) - $($job.title)"
    ($w.FindName('DlgSub')).Text   = ("{0} - {1}" -f $job.department, $job.location)
    ($w.FindName('DlgPillHost')).Child = (New-StatusPill -Status $job.status)

    ($w.FindName('TbReqNumber')).Text  = $job.reqNumber
    ($w.FindName('TbTitle')).Text      = $job.title
    ($w.FindName('TbHM')).Text         = $job.hiringManager
    ($w.FindName('TbDept')).Text       = $job.department
    ($w.FindName('TbLoc')).Text        = $job.location
    ($w.FindName('TbOpenings')).Text   = "$($job.openings)"
    # DatePicker.SelectedDate is Nullable<DateTime> - only assign when we
    # have a parseable value. Mirrors the candidate detail dialog pattern
    # (see views\Candidates.ps1) so empty/garbage dates do not throw.
    $created = [DateTime]::MinValue
    if ($job.createdDate -and [DateTime]::TryParse($job.createdDate, [ref]$created)) {
        ($w.FindName('DpCreated')).SelectedDate = $created
    }
    $target = [DateTime]::MinValue
    if ($job.targetHireDate -and [DateTime]::TryParse($job.targetHireDate, [ref]$target)) {
        ($w.FindName('DpTarget')).SelectedDate = $target
    }
    ($w.FindName('TbDesc')).Text       = $job.description

    # Status combo
    $cbStatus = $w.FindName('CbStatus')
    foreach ($i in 0..($cbStatus.Items.Count-1)) {
        if ("$($cbStatus.Items[$i].Content)" -eq $job.status) { $cbStatus.SelectedIndex = $i }
    }
    # Position combo populated from catalog
    $cbPos = $w.FindName('CbPosition')
    foreach ($p in $data.Positions) { [void]$cbPos.Items.Add($p) }
    $cbPos.Text = $job.position

    # Linked entities --------------------------------------------------------
    $kit = Get-KitForJob $data $JobId
    if ($kit) {
        ($w.FindName('KitInfo')).Text = ("{0} - {1} categories" -f $kit.name, @($kit.categories).Count)
    }
    $cands = Get-CandidatesFor $data $JobId
    ($w.FindName('CandsInfo')).Text = ("{0} candidates assigned" -f $cands.Count)

    # Stash the dialog + job id on each button so the handlers don't need
    # GetNewClosure. Call Set-CurrentKitForJob / Set-CandidateJobFilter
    # (defined in InterviewKits.ps1 / Candidates.ps1) BEFORE Show-View so the
    # state write lands in the right file's $Script: scope and the rebuild
    # sees it. Cross-file $Script: variable state doesn't share - we tried
    # the $Script:KitSelectAction / $Script:CandFilterAction callback dance
    # and it silently no-op'd because the callback was set in one file's
    # scope and read as $null from another.
    $openKitBtn = $w.FindName('BtnOpenKit')
    $openKitBtn.Tag = @{ Win = $w; JobId = $JobId }
    $openKitBtn.Add_Click({
        param($sender, $eventArgs)
        $ctx = $sender.Tag
        $ctx.Win.DialogResult = $true; $ctx.Win.Close()
        Set-CurrentKitForJob $ctx.JobId
        Set-ActiveTab 'TabKits'
        Show-View 'TabKits'
    })

    $openCandsBtn = $w.FindName('BtnOpenCands')
    $openCandsBtn.Tag = @{ Win = $w; JobId = $JobId }
    $openCandsBtn.Add_Click({
        param($sender, $eventArgs)
        $ctx = $sender.Tag
        $ctx.Win.DialogResult = $true; $ctx.Win.Close()
        Set-CandidateJobFilter $ctx.JobId
        Set-ActiveTab 'TabCandidates'
        Show-View 'TabCandidates'
    })

    # "+ Add Candidate": create a new candidate pre-attached to this job,
    # close the JobReq dialog, jump to the Candidates tab pre-filtered to
    # this job, and open the candidate detail dialog for editing.
    # Context via Tag so the handler doesn't need GetNewClosure (same
    # closure-scope trap that bit the cross-tab handoff earlier).
    $addCandBtn = $w.FindName('BtnAddCand')
    $addCandBtn.Tag = @{ Win = $w; JobId = $JobId }
    $addCandBtn.Add_Click({
        param($sender, $eventArgs)
        $ctx = $sender.Tag
        $newC = New-Candidate
        $newC.jobReqId = $ctx.JobId
        $j = Get-JobById $Script:ShellData $ctx.JobId
        if ($j) { $newC.position = $j.title }
        $newC.appliedDate = (Get-Date).ToString('yyyy-MM-dd')
        $Script:ShellData.Candidates = @($Script:ShellData.Candidates) + $newC
        Save-Candidates $Script:ShellData
        # Close this dialog before opening the next so they don't stack.
        $ctx.Win.DialogResult = $true; $ctx.Win.Close()
        # Pre-filter the Candidates tab to this job (so when the candidate
        # dialog closes, the user lands on the relevant filtered list).
        Set-CandidateJobFilter $ctx.JobId
        Set-ActiveTab 'TabCandidates'
        Show-View 'TabCandidates'
        Show-CandidateDetail $newC.id
    })

    # Export button - use Tag/param pattern, not .GetNewClosure() (closures
    # shadow $Script: writes between events; see CLAUDE.md).
    $exportBtn = $w.FindName('BtnExport')
    $exportBtn.Tag = @{ Win = $w; JobId = $JobId }
    $exportBtn.Add_Click({
        param($sender, $eventArgs)
        $ctx = $sender.Tag
        Invoke-SafeAction -Label 'Export JobReq' -Action {
            $j      = Get-JobById $Script:ShellData $ctx.JobId
            if (-not $j) { return }
            $bundle = New-JobReqExportBundle -Data $Script:ShellData -JobId $ctx.JobId

            $dlg = New-Object Microsoft.Win32.SaveFileDialog
            $dlg.FileName         = (Get-JobReqExportDefaultFilename $j)
            $dlg.Filter           = 'TrueHire bundle (*.truehire.zip)|*.truehire.zip|All files (*.*)|*.*'
            $dlg.InitialDirectory = (Get-LastExportDir)
            $dlg.OverwritePrompt  = $true

            if ($dlg.ShowDialog($ctx.Win) -eq $true) {
                Write-JobReqExportBundle -Bundle $bundle -Path $dlg.FileName
                Set-LastExportDir (Split-Path -Parent $dlg.FileName)

                $kitWord = 'no kit'
                if ($bundle.Kit) { $kitWord = 'with kit' }
                Set-ShellStatus ("Exported {0} to {1} ({2} candidates, {3})" -f `
                    $j.reqNumber, (Split-Path -Leaf $dlg.FileName), @($bundle.Candidates).Count, $kitWord)
                Write-TrueHireLog -Level INFO -Source 'Export' -Message (
                    "Exported {0} ({1}) -> {2} ({3} candidates, {4} rater entries)" -f `
                    $j.reqNumber, $j.id, $dlg.FileName, $bundle.Manifest.counts.candidates, $bundle.Manifest.counts.raterEntries)
            }
        }
    })

    $w.FindName('BtnCancel').Add_Click({ $w.DialogResult = $false; $w.Close() })
    # Delete routes through Show-DeleteJobReqDialog so the confirm dialog,
    # cascade scope, and backup-export option are identical to the
    # card-level delete button on the JobReqs grid. param($sender,...) + no
    # .GetNewClosure() so script-scope function names resolve dynamically
    # at fire time (see CLAUDE.md).
    $delBtn = $w.FindName('BtnDelete')
    $delBtn.Tag = @{ Win = $w; JobId = $JobId }
    $delBtn.Add_Click({
        param($sender, $eventArgs)
        $ctx = $sender.Tag
        $deleted = Show-DeleteJobReqDialog $ctx.JobId
        if ($deleted) { $ctx.Win.DialogResult = $true; $ctx.Win.Close() }
    })
    $w.FindName('BtnSave').Add_Click({
        $job.reqNumber     = ($w.FindName('TbReqNumber')).Text
        $job.title         = ($w.FindName('TbTitle')).Text
        $job.position      = ($w.FindName('CbPosition')).Text
        $job.hiringManager = ($w.FindName('TbHM')).Text
        $job.department    = ($w.FindName('TbDept')).Text
        $job.location      = ($w.FindName('TbLoc')).Text
        $sel = ($w.FindName('CbStatus')).SelectedItem
        if ($sel) { $job.status = "$($sel.Content)" }
        $o = 0
        if ([int]::TryParse(($w.FindName('TbOpenings')).Text, [ref]$o)) { $job.openings = $o }
        # Wrapped in try/catch so a future PS+WPF nullable quirk on these
        # two fields can never silently block subsequent writes from
        # reaching Save-Jobs - same defensive shape as Candidates.ps1.
        try {
            $createdSd = ($w.FindName('DpCreated')).SelectedDate
            if ($createdSd) { $job.createdDate = $createdSd.ToString('s') }
            $targetSd  = ($w.FindName('DpTarget')).SelectedDate
            $job.targetHireDate = if ($targetSd) { $targetSd.ToString('yyyy-MM-dd') } else { '' }
        } catch {
            if (Get-Command Write-TrueHireLog -ErrorAction SilentlyContinue) {
                Write-TrueHireLog -Level WARN -Source 'JobReqSave' -Message ('DatePicker read failed; dates left unchanged: ' + $_.Exception.Message) -Exception $_.Exception
            }
        }
        $job.description    = ($w.FindName('TbDesc')).Text
        $job.modifiedDate   = (Get-Date).ToString('s')
        Save-Jobs $data
        Set-ShellStatus ("Saved {0}." -f $job.reqNumber)
        $w.DialogResult = $true; $w.Close()
        Show-View 'TabJobReqs'
    }.GetNewClosure())

    [void]$w.ShowDialog()
}

$Script:ImportConflictXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Import Requisition" Width="520" Height="380"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        Background="White" FontFamily="Segoe UI" FontSize="13">
  <Grid Margin="0">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <Border Grid.Row="0" Background="#0B2C45" Padding="20,16">
      <StackPanel>
        <TextBlock x:Name="DlgTitle"  Foreground="White"   FontSize="18" FontWeight="SemiBold" Text=""/>
        <TextBlock x:Name="DlgSub"    Foreground="#BBDEFB" FontSize="12" Margin="0,4,0,0"      Text=""/>
        <TextBlock x:Name="DlgCounts" Foreground="#BBDEFB" FontSize="12" Margin="0,2,0,0"      Text=""/>
      </StackPanel>
    </Border>
    <StackPanel Grid.Row="1" Margin="20,16,20,12">
      <TextBlock Text="A requisition with this ID already exists locally."
                 Foreground="#B23A3A" FontWeight="SemiBold" Margin="0,0,0,12"/>
      <RadioButton x:Name="RbReplace" GroupName="ImportMode" IsChecked="True" Margin="0,0,0,8">
        <StackPanel>
          <TextBlock Text="Replace existing" FontWeight="SemiBold"/>
          <TextBlock Foreground="#666" TextWrapping="Wrap" Margin="0,2,0,0"
                     Text="Overwrite the local job, kit, and candidates with the bundle. Local edits since export are LOST."/>
        </StackPanel>
      </RadioButton>
      <RadioButton x:Name="RbNew" GroupName="ImportMode" Margin="0,0,0,8">
        <StackPanel>
          <TextBlock Text="Import as new copy" FontWeight="SemiBold"/>
          <TextBlock Foreground="#666" TextWrapping="Wrap" Margin="0,2,0,0"
                     Text="Assign fresh IDs to job, kit, candidates, and rater entries. Keeps both copies. Title gets ' (Imported)' appended."/>
        </StackPanel>
      </RadioButton>
    </StackPanel>
    <Border Grid.Row="2" Background="White" BorderBrush="#E0E0E0"
            BorderThickness="0,1,0,0" Padding="20,12">
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Button x:Name="BtnCancel" Content="Cancel" Width="100" Margin="0,0,8,0"/>
        <Button x:Name="BtnImport" Content="Import" Width="100"/>
      </StackPanel>
    </Border>
  </Grid>
</Window>
'@

function Show-ImportConflictDialog {
    <#
    Modal that asks the user how to resolve an ID conflict on import.
    Returns 'Replace', 'New', or $null (user cancelled / closed).
    #>
    param($Bundle)
    $w = ConvertTo-Window -Xaml $Script:ImportConflictXaml
    $w.Owner = $Script:Shell

    $m = $Bundle.Manifest
    ($w.FindName('DlgTitle')).Text = ("{0} - {1}" -f $m.source.reqNumber, $m.source.title)

    $exportedAtText = ''
    if ($m.exportedAt) {
        try {
            $dt = [datetime]::Parse($m.exportedAt)
            $exportedAtText = $dt.ToString('yyyy-MM-dd HH:mm')
        } catch { $exportedAtText = [string]$m.exportedAt }
    }
    $byName = ''
    if ($m.exportedBy -and (_HasProp $m.exportedBy 'name')) { $byName = [string]$m.exportedBy.name }
    ($w.FindName('DlgSub')).Text = ("Exported {0} by {1}" -f $exportedAtText, $byName)

    ($w.FindName('DlgCounts')).Text = (
        "{0} candidates, {1} rater entries ({2} submitted)" -f `
        $m.counts.candidates, $m.counts.raterEntries, $m.counts.submittedRaterEntries)

    $script:_importChoice = $null
    $w.FindName('BtnCancel').Add_Click({ $w.DialogResult = $false; $w.Close() })
    $w.FindName('BtnImport').Add_Click({
        param($sender, $eventArgs)
        if (($w.FindName('RbReplace')).IsChecked -eq $true) { $script:_importChoice = 'Replace' }
        elseif (($w.FindName('RbNew')).IsChecked -eq $true) { $script:_importChoice = 'New' }
        $w.DialogResult = $true
        $w.Close()
    })

    [void]$w.ShowDialog()
    return $script:_importChoice
}

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

    $w.FindName('BtnCancel').Add_Click({ $w.DialogResult = $false; $w.Close() })
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
        $w.Close()
    })

    if ($w.ShowDialog() -eq $true) { return $state.Range }
    return $null
}

# ----------------------------------------------------------------------------
# Delete-requisition dialog. Shows what will be cascade-deleted (kit +
# candidates + rater entries), and offers an opt-out for "Export bundle as
# backup first" so the destructive action is recoverable via re-import.
# Wired to BtnDelete on the requisition detail dialog AND the card-level
# red x button on each row of the JobReqs grid.
# ----------------------------------------------------------------------------
$Script:DeleteJobReqXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Delete Job Requisition" Width="540" Height="380"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        Background="White" FontFamily="Segoe UI" FontSize="13">
  <Grid Margin="0">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <Border Grid.Row="0" Background="#B23A3A" Padding="20,16">
      <StackPanel>
        <TextBlock Foreground="White" FontSize="18" FontWeight="SemiBold" Text="Delete Job Requisition"/>
        <TextBlock x:Name="DlgSub" Foreground="#FFE0E0" FontSize="12" Margin="0,4,0,0" Text=""/>
      </StackPanel>
    </Border>
    <StackPanel Grid.Row="1" Margin="20,18,20,12">
      <TextBlock Text="This will permanently delete:" FontWeight="SemiBold" Margin="0,0,0,8"/>
      <TextBlock x:Name="DlgBulletJob"   Margin="12,0,0,4" Text=""/>
      <TextBlock x:Name="DlgBulletKit"   Margin="12,0,0,4" Text=""/>
      <TextBlock x:Name="DlgBulletCands" Margin="12,0,0,16" Text=""/>
      <TextBlock Text="Delete is permanent and cannot be undone."
                 Foreground="#B23A3A" FontStyle="Italic" Margin="0,0,0,12"/>
      <CheckBox x:Name="CbBackup" IsChecked="True">
        <StackPanel Margin="6,0,0,0">
          <TextBlock Text="Export bundle as backup first" FontWeight="SemiBold"/>
          <TextBlock Foreground="#666" TextWrapping="Wrap" Margin="0,2,0,0"
                     Text="Recommended. Saves a .truehire.zip you can re-import later to restore everything."/>
        </StackPanel>
      </CheckBox>
    </StackPanel>
    <Border Grid.Row="2" Background="White" BorderBrush="#E0E0E0"
            BorderThickness="0,1,0,0" Padding="20,12">
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Button x:Name="BtnCancel" Content="Cancel" Width="100" Margin="0,0,8,0"/>
        <Button x:Name="BtnDelete" Content="Delete" Width="100"
                Background="#B23A3A" Foreground="White" FontWeight="SemiBold"/>
      </StackPanel>
    </Border>
  </Grid>
</Window>
'@

function Show-DeleteJobReqDialog {
    <#
    Modal confirmation for the cascade delete. Counts the to-be-deleted
    kit + candidates + rater entries, offers an opt-out backup export
    (default ON), and on confirm calls Remove-JobReq. Refreshes the
    JobReqs view at the end so the deleted card vanishes.
    Returns $true if a delete happened, $false otherwise (cancel/close
    or job-not-found).
    #>
    param([string]$JobId)
    $data = $Script:ShellData
    $job  = Get-JobById $data $JobId
    if (-not $job) { return $false }

    $kit   = Get-KitForJob     $data $JobId
    $cands = @(Get-CandidatesFor $data $JobId)
    $raterCount = 0
    foreach ($c in $cands) {
        if ($c.raterEntries) { $raterCount += @($c.raterEntries).Count }
    }

    $w = ConvertTo-Window -Xaml $Script:DeleteJobReqXaml
    $w.Owner = $Script:Shell

    ($w.FindName('DlgSub')).Text         = ("{0} - {1}" -f $job.reqNumber, $job.title)
    ($w.FindName('DlgBulletJob')).Text   = ("- This job requisition ({0})" -f $job.reqNumber)
    $kitText = if ($kit) { "- Its interview kit ($($kit.name))" } else { '- (no interview kit attached)' }
    ($w.FindName('DlgBulletKit')).Text   = $kitText
    $candText =
        if ($cands.Count -eq 0)        { '- (no candidates)' }
        elseif ($raterCount -eq 0)     { "- $($cands.Count) candidate(s)" }
        else                           { "- $($cands.Count) candidate(s) and $raterCount rater entr$(if($raterCount -eq 1){'y'}else{'ies'})" }
    ($w.FindName('DlgBulletCands')).Text = $candText

    # Cancel just closes - we use a script-scope flag so the caller knows
    # whether to refresh the view.
    $script:_deleteHappened = $false
    $w.FindName('BtnCancel').Add_Click({ $w.DialogResult = $false; $w.Close() })

    $w.FindName('BtnDelete').Add_Click({
        param($sender, $eventArgs)
        # Backup-export step (opt-out). Runs BEFORE the destructive call.
        # If the user cancels the save-file dialog we abort the whole
        # operation - they explicitly asked for a backup, don't betray that
        # by deleting anyway.
        if (($w.FindName('CbBackup')).IsChecked -eq $true) {
            $proceeded = $false
            Invoke-SafeAction -Label 'Backup before Delete' -Action {
                $bundle = New-JobReqExportBundle -Data $Script:ShellData -JobId $JobId
                $dlg = New-Object Microsoft.Win32.SaveFileDialog
                $dlg.FileName         = (Get-JobReqExportDefaultFilename $job)
                $dlg.Filter           = 'TrueHire bundle (*.truehire.zip)|*.truehire.zip|All files (*.*)|*.*'
                $dlg.InitialDirectory = (Get-LastExportDir)
                $dlg.OverwritePrompt  = $true
                if ($dlg.ShowDialog($w) -eq $true) {
                    Write-JobReqExportBundle -Bundle $bundle -Path $dlg.FileName
                    Set-LastExportDir (Split-Path -Parent $dlg.FileName)
                    Write-TrueHireLog -Level INFO -Source 'Delete-Backup' -Message (
                        "Backup written to {0} before delete" -f $dlg.FileName)
                    $script:_deleteBackupOk = $true
                } else {
                    $script:_deleteBackupOk = $false
                }
            }
            if (-not $script:_deleteBackupOk) {
                # User cancelled save dialog OR Invoke-SafeAction caught a
                # throw. Either way, do not proceed with destruction.
                Set-ShellStatus -Text "Delete cancelled - backup not saved." -Level WARN
                $w.DialogResult = $false; $w.Close()
                return
            }
        }

        $summary = Remove-JobReq -Data $Script:ShellData -JobId $JobId
        if ($summary) {
            $script:_deleteHappened = $true
            Set-ShellStatus ("Deleted {0} - {1} ({2} kit, {3} candidate(s), {4} rater entr{5})" -f `
                $summary.JobReqNumber, $summary.JobTitle, `
                $summary.DeletedKits, $summary.DeletedCandidates, `
                $summary.DeletedRaterEntries, `
                $(if ($summary.DeletedRaterEntries -eq 1) { 'y' } else { 'ies' }))
        }
        $w.DialogResult = $true; $w.Close()
    })

    [void]$w.ShowDialog()
    if ($script:_deleteHappened) {
        Show-View 'TabJobReqs'
        return $true
    }
    return $false
}
