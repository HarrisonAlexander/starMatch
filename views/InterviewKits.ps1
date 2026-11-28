<#
InterviewKits.ps1 — Interview Kits view (ui_3). Left rail: every kit (one per
job req); selected kit's questions render on the right with category, type,
required flag. Each question pulls its full text + scoring guide from the
catalog (categories.json) at display time so changes to the catalog flow in
automatically.
#>

$Script:KitsXaml = @'
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
      xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <Grid.ColumnDefinitions>
    <ColumnDefinition Width="280"/>
    <ColumnDefinition Width="*"/>
  </Grid.ColumnDefinitions>

  <!-- Left rail -->
  <Border Grid.Column="0" Background="White" BorderBrush="{StaticResource CardBorder}"
          BorderThickness="0,0,1,0">
    <Grid Margin="20,24,20,20">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>
      <TextBlock Grid.Row="0" Style="{StaticResource H3}" Text="Interview Kits" Margin="0,0,0,12"/>
      <Button x:Name="BtnNewKit" Grid.Row="1" Content="+ New Interview Kit"
              Style="{StaticResource PrimaryBtn}" Margin="0,0,0,12"/>
      <TextBox x:Name="KitSearch" Grid.Row="2" Style="{StaticResource SearchField}" Margin="0,0,0,12"/>
      <ScrollViewer Grid.Row="3" VerticalScrollBarVisibility="Auto">
        <StackPanel x:Name="KitListPanel"/>
      </ScrollViewer>
      <TextBlock x:Name="KitListCount" Grid.Row="4" Style="{StaticResource Caption}"
                 Margin="0,12,0,0" Text=""/>
    </Grid>
  </Border>

  <!-- Detail pane -->
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
      <StackPanel Grid.Column="0">
        <StackPanel Orientation="Horizontal">
          <TextBlock x:Name="KitName" Style="{StaticResource H2}" Text="" VerticalAlignment="Center"/>
          <Border x:Name="KitPillHost" Margin="12,0,0,0" VerticalAlignment="Center"/>
        </StackPanel>
        <TextBlock x:Name="KitMeta" Style="{StaticResource Caption}" Margin="0,4,0,0" Text=""/>
      </StackPanel>
      <StackPanel Grid.Column="1" Orientation="Horizontal">
        <Button x:Name="BtnPrintHandout"   Content="Print Handout"        Style="{StaticResource PrimaryBtn}" Margin="0,0,8,0"/>
        <Button x:Name="BtnPrintCandidate" Content="Print Candidate Set"  Style="{StaticResource GhostBtn}"   Margin="0,0,8,0"/>
        <Button x:Name="BtnPreview"        Content="Preview Kit"          Style="{StaticResource GhostBtn}"   Margin="0,0,8,0"/>
        <Button x:Name="BtnEditKit"     Content="Edit Details"  Style="{StaticResource GhostBtn}"/>
      </StackPanel>
    </Grid>

    <Grid Grid.Row="1" Margin="0,0,0,12">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
      <TextBlock Grid.Column="0" Style="{StaticResource H3}" Text="Questions" VerticalAlignment="Center"/>
      <StackPanel Grid.Column="1" Orientation="Horizontal">
        <Button x:Name="BtnBuildFromCatalog" Content="+ Build from Catalog..." Style="{StaticResource BlueBtn}" Margin="0,0,8,0"/>
        <Button x:Name="BtnAddQuestion" Content="+ Add Question" Style="{StaticResource PrimaryBtn}"/>
      </StackPanel>
    </Grid>

    <Border Grid.Row="2" Style="{StaticResource Card}" Padding="0">
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Border Grid.Row="0" Background="#F8FAFC" BorderBrush="{StaticResource CardBorder}"
                BorderThickness="0,0,0,1" CornerRadius="10,10,0,0">
          <Grid Margin="16,12">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="40"/>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="140"/>
              <ColumnDefinition Width="120"/>
            </Grid.ColumnDefinitions>
            <TextBlock Grid.Column="0" Style="{StaticResource GridHeaderText}" Text="#"/>
            <TextBlock Grid.Column="1" Style="{StaticResource GridHeaderText}" Text="QUESTION"/>
            <TextBlock Grid.Column="2" Style="{StaticResource GridHeaderText}" Text="CATEGORY"/>
            <TextBlock Grid.Column="3" Style="{StaticResource GridHeaderText}" Text="ACTIONS"/>
          </Grid>
        </Border>
        <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
          <StackPanel x:Name="QuestionsPanel"/>
        </ScrollViewer>
        <Border Grid.Row="2" Background="#F8FAFC" Padding="16,10"
                BorderBrush="{StaticResource CardBorder}" BorderThickness="0,1,0,0"
                CornerRadius="0,0,10,10">
          <TextBlock x:Name="KitQuestionCount" Style="{StaticResource Caption}" Text=""/>
        </Border>
      </Grid>
    </Border>
  </Grid>
</Grid>
'@

# Module-scoped: selected kit id + a hook the JobReqs view calls when the
# user navigates here from a job-req detail dialog.
$Script:CurrentKitId   = $null
$Script:KitSelectAction = $null
# Currently-expanded inline editor row, or $null. Pencil button toggles.
$Script:ExpandedQuestionId = $null
# Pending-new-question hashtable, or $null. Set by '+ Add Question';
# rendered as an extra expanded-editor block at the bottom of the panel.
$Script:PendingNewQuestion = $null

function Clear-PendingKitQuestion {
    <#
    Called by the tab router (views/Shell.ps1::Show-View) when navigating
    away from TabKits, so an in-flight + Add Question is discarded rather
    than reappearing on return.
    #>
    $Script:PendingNewQuestion = $null
    $Script:ExpandedQuestionId = $null
}

function Set-CurrentKitForJob {
    <#
    Switches the kit-list selection to the kit attached to the given job id.
    Called by JobReqs.ps1's "Open Kit" button. Lives here (not at the
    caller's site) so the $Script:CurrentKitId write lands in this file's
    Script scope - which is where Show-InterviewKitsView reads from on the
    subsequent Show-View 'TabKits' rebuild. Cross-file $Script: state
    doesn't share across files even with dot-sourcing.
    #>
    param([string]$JobId)
    $kit = Get-KitForJob $Script:ShellData $JobId
    if ($kit) { $Script:CurrentKitId = $kit.id }
}

function _KitRailRow {
    param($Kit, $Job)
    $b = New-Object System.Windows.Controls.Border
    $b.Background = 'White'
    $b.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#E4E8EF')))
    $b.BorderThickness = '1'
    $b.CornerRadius = '8'
    $b.Padding = '12'
    $b.Margin = '0,0,0,8'
    $b.Cursor = 'Hand'
    $b.Tag = $Kit.id
    if ($Kit.id -eq $Script:CurrentKitId) {
        $b.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#1E88E5')))
        $b.BorderThickness = '2'
    }

    # Row 1: title only, allowed to wrap. Pill moved to row 2 so a long
    # kit name (e.g. 'Sr. Software Engineer Kit') doesn't get
    # truncated under the status chip. Same pattern as _MakeRailRow in
    # JobReqs.ps1.
    $stack = New-Object System.Windows.Controls.StackPanel

    $title = New-Object System.Windows.Controls.TextBlock
    $title.Text = if ($Job) { "$($Job.title) Kit" } else { $Kit.name }
    $title.FontWeight = 'SemiBold'; $title.FontSize = 13
    $title.TextWrapping = 'Wrap'
    $title.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#0B2C45')))
    [void]$stack.Children.Add($title)

    # Row 2: "N questions" caption on the left, status pill on the right.
    $row2 = New-Object System.Windows.Controls.Grid
    $row2.Margin = '0,4,0,0'
    $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = '*'
    $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = 'Auto'
    [void]$row2.ColumnDefinitions.Add($c1); [void]$row2.ColumnDefinitions.Add($c2)

    $sub = New-Object System.Windows.Controls.TextBlock
    $cnt = 0
    foreach ($kc in @($Kit.categories)) { $cnt += @($kc.questions).Count }
    $sub.Text = ("{0} questions" -f $cnt)
    $sub.FontSize = 11
    $sub.VerticalAlignment = 'Center'
    $sub.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#6B7B8C')))
    [System.Windows.Controls.Grid]::SetColumn($sub, 0)
    [void]$row2.Children.Add($sub)

    $pill = New-StatusPill -Status $Kit.status
    [System.Windows.Controls.Grid]::SetColumn($pill, 1)
    [void]$row2.Children.Add($pill)

    [void]$stack.Children.Add($row2)

    $b.Child = $stack
    # No .GetNewClosure() - it would shadow the $Script:CurrentKitId write
    # (per CLAUDE.md closure-scope trap), making clicks on non-default rows
    # silently no-op. param() restores dynamic scope so the write reaches
    # the real script-level variable and Show-View resolves.
    $b.Add_MouseLeftButtonUp({
        param($s,$e)
        $Script:CurrentKitId = $s.Tag
        Show-View 'TabKits'
    })
    return $b
}

function _BuildCategorySectionHeader {
    <#
    A static (non-collapsible) section band shown above each category's
    question rows in the kit editor. The left side shows the category label +
    a pluralized question count; the right side carries Up/Down arrows that
    reorder the WHOLE category among the kit's categories (see
    _MoveKitCategory). The Up arrow greys on the first category, the Down arrow
    on the last - $CatIndex/$TotalCats drive that. (Separately, the per-question
    arrows inside each row reorder within the category and grey at the
    section's own first/last row - see _MoveKitQuestion.) Weight is
    intentionally NOT shown here - it lives in _BuildCategoryWeightsPanel above
    the list.
    #>
    param($Cat, [int]$Count, [int]$CatIndex = 0, [int]$TotalCats = 1)
    $b = New-Object System.Windows.Controls.Border
    $b.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#F1F5F9')))
    $b.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#E4E8EF')))
    $b.BorderThickness = '0,0,0,1'
    $b.Padding = '16,8'

    # Two columns: label/count (*) on the left, reorder arrows (Auto) on the
    # right. The smoke test reads Children[0] (label stack) and Children[1]
    # (arrow stack), so keep that order.
    $g = New-Object System.Windows.Controls.Grid
    $cMain = New-Object System.Windows.Controls.ColumnDefinition; $cMain.Width = '*'
    $cAct  = New-Object System.Windows.Controls.ColumnDefinition; $cAct.Width = 'Auto'
    [void]$g.ColumnDefinitions.Add($cMain); [void]$g.ColumnDefinitions.Add($cAct)

    $row = New-Object System.Windows.Controls.StackPanel
    $row.Orientation = 'Horizontal'
    $row.VerticalAlignment = 'Center'
    [System.Windows.Controls.Grid]::SetColumn($row, 0)

    $name = New-Object System.Windows.Controls.TextBlock
    $name.Text = Get-CategoryLabel $Cat $Script:ShellData.Catalog
    $name.FontWeight = 'SemiBold'
    $name.FontSize = 12.5
    $name.VerticalAlignment = 'Center'
    $name.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#2C3E50')))
    [void]$row.Children.Add($name)

    $countTb = New-Object System.Windows.Controls.TextBlock
    $suffix = if ($Count -eq 1) { '' } else { 's' }
    $countTb.Text = ' ' + [char]0x00B7 + (' {0} question{1}' -f $Count, $suffix)
    $countTb.FontSize = 12.5
    $countTb.VerticalAlignment = 'Center'
    $countTb.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#6B7B8C')))
    [void]$row.Children.Add($countTb)
    [void]$g.Children.Add($row)

    # Reorder arrows. Same Tag-stash pattern as the question rows: stash the
    # category id on .Tag so the handler doesn't close over the loop var, and
    # use param($sender,...) so script-scope helpers resolve at fire time.
    $acts = New-Object System.Windows.Controls.StackPanel
    $acts.Orientation = 'Horizontal'
    $acts.HorizontalAlignment = 'Right'
    [System.Windows.Controls.Grid]::SetColumn($acts, 1)

    $catUp = New-Object System.Windows.Controls.Button
    $catUp.Content = [char]0x25B2   # BLACK UP-POINTING TRIANGLE
    $catUp.Style = $Script:Shell.FindResource('IconBtn')
    $catUp.ToolTip = 'Move category up'
    $catUp.Tag = $Cat.id
    $catUp.IsEnabled = ($CatIndex -gt 0)
    $catUp.Add_Click({
        param($sender, $eventArgs)
        if (Get-Command Write-TrueHireLog -ErrorAction SilentlyContinue) {
            Write-TrueHireLog -Level INFO -Source 'KitReorder' -Message ("CLICK CatUp   kit={0} tag={1}" -f $Script:CurrentKitId, $sender.Tag)
        }
        _MoveKitCategory $Script:CurrentKitId $sender.Tag 'Up'
    })
    [void]$acts.Children.Add($catUp)

    $catDown = New-Object System.Windows.Controls.Button
    $catDown.Content = [char]0x25BC  # BLACK DOWN-POINTING TRIANGLE
    $catDown.Style = $Script:Shell.FindResource('IconBtn')
    $catDown.ToolTip = 'Move category down'
    $catDown.Tag = $Cat.id
    $catDown.IsEnabled = ($CatIndex -lt ($TotalCats - 1))
    $catDown.Add_Click({
        param($sender, $eventArgs)
        if (Get-Command Write-TrueHireLog -ErrorAction SilentlyContinue) {
            Write-TrueHireLog -Level INFO -Source 'KitReorder' -Message ("CLICK CatDown kit={0} tag={1}" -f $Script:CurrentKitId, $sender.Tag)
        }
        _MoveKitCategory $Script:CurrentKitId $sender.Tag 'Down'
    })
    [void]$acts.Children.Add($catDown)

    [void]$g.Children.Add($acts)

    $b.Child = $g
    return $b
}

function _QuestionRow {
    <#
    One row in the questions grid. Columns: # | QUESTION | CATEGORY | ACTIONS.
    Actions hold four IconBtns: up, down, edit-toggle, remove.
    Probe text is owned by the kit-question (post _MigrateKit).
    $Order is the question's 1-based position WITHIN its category (shown in the
    "#" column; numbering restarts each section). $RowIndex/$TotalRows are the
    same per-category position/size and drive Up/Down enable so the arrows grey
    out at the first/last slot of each category (reorder is within-category; see
    _MoveKitQuestion and _BuildCategorySectionHeader).
    #>
    param([int]$Order, $Cat, $Q, [int]$RowIndex, [int]$TotalRows)
    $b = New-Object System.Windows.Controls.Border
    $b.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#EDF0F4')))
    $b.BorderThickness = '0,0,0,1'

    $g = New-Object System.Windows.Controls.Grid
    $g.Margin = '16,12'
    foreach ($w in 40,'*',140,120) {
        $cd = New-Object System.Windows.Controls.ColumnDefinition
        $cd.Width = if ($w -is [string]) { '*' } else { [System.Windows.GridLength]::new($w) }
        [void]$g.ColumnDefinitions.Add($cd)
    }

    # Column 0: order number
    $n = New-Object System.Windows.Controls.TextBlock
    $n.Text = "$Order"; $n.FontWeight = 'SemiBold'; $n.FontSize = 12
    $n.VerticalAlignment = 'Center'
    $n.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#1565C0')))
    [System.Windows.Controls.Grid]::SetColumn($n, 0)
    [void]$g.Children.Add($n)

    # Column 1: probe text (kit-local, post-migration)
    $probeText = if ($Q.PSObject.Properties['probe'] -and $Q.probe) { [string]$Q.probe } else { Get-CategoryLabel $Cat $Script:ShellData.Catalog }
    $qCell = New-Object System.Windows.Controls.TextBlock
    $qCell.Text = $probeText
    $qCell.TextWrapping = 'Wrap'
    $qCell.FontSize = 12.5
    $qCell.VerticalAlignment = 'Center'
    $qCell.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#0B2C45')))
    [System.Windows.Controls.Grid]::SetColumn($qCell, 1)
    [void]$g.Children.Add($qCell)

    # Column 2: category name
    $catCell = New-Object System.Windows.Controls.TextBlock
    $catCell.Text = Get-CategoryLabel $Cat $Script:ShellData.Catalog; $catCell.FontSize = 12.5
    $catCell.VerticalAlignment = 'Center'
    $catCell.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#2C3E50')))
    [System.Windows.Controls.Grid]::SetColumn($catCell, 2)
    [void]$g.Children.Add($catCell)

    # Column 3: actions (up, down, edit, remove). Each button stashes the
    # question id on its Tag so the handler doesn't close over loop variables.
    $actions = New-Object System.Windows.Controls.StackPanel
    $actions.Orientation = 'Horizontal'
    $actions.HorizontalAlignment = 'Left'

    $btnUp = New-Object System.Windows.Controls.Button
    $btnUp.Content = [char]0x25B2   # BLACK UP-POINTING TRIANGLE
    $btnUp.Style = $Script:Shell.FindResource('IconBtn')
    $btnUp.ToolTip = 'Move up'
    $btnUp.Tag = $Q.id
    $btnUp.IsEnabled = ($RowIndex -gt 0)
    $btnUp.Add_Click({
        param($sender, $eventArgs)
        if (Get-Command Write-TrueHireLog -ErrorAction SilentlyContinue) {
            Write-TrueHireLog -Level INFO -Source 'KitReorder' -Message ("CLICK Up  kit={0} tag={1}" -f $Script:CurrentKitId, $sender.Tag)
        }
        _MoveKitQuestion $Script:CurrentKitId $sender.Tag 'Up'
    })
    [void]$actions.Children.Add($btnUp)

    $btnDown = New-Object System.Windows.Controls.Button
    $btnDown.Content = [char]0x25BC  # BLACK DOWN-POINTING TRIANGLE
    $btnDown.Style = $Script:Shell.FindResource('IconBtn')
    $btnDown.ToolTip = 'Move down'
    $btnDown.Tag = $Q.id
    $btnDown.IsEnabled = ($RowIndex -lt ($TotalRows - 1))
    $btnDown.Add_Click({
        param($sender, $eventArgs)
        if (Get-Command Write-TrueHireLog -ErrorAction SilentlyContinue) {
            Write-TrueHireLog -Level INFO -Source 'KitReorder' -Message ("CLICK Down kit={0} tag={1}" -f $Script:CurrentKitId, $sender.Tag)
        }
        _MoveKitQuestion $Script:CurrentKitId $sender.Tag 'Down'
    })
    [void]$actions.Children.Add($btnDown)

    $btnEdit = New-Object System.Windows.Controls.Button
    $btnEdit.Content = [char]0x270E  # PENCIL
    $btnEdit.Style = $Script:Shell.FindResource('IconBtn')
    $btnEdit.ToolTip = 'Edit question'
    $btnEdit.Tag = $Q.id
    $btnEdit.Add_Click({
        param($sender, $eventArgs)
        # Toggle: clicking the same row's pencil twice collapses.
        if ($Script:ExpandedQuestionId -eq $sender.Tag) {
            $Script:ExpandedQuestionId = $null
        } else {
            $Script:ExpandedQuestionId = $sender.Tag
        }
        Show-View 'TabKits'
    })
    [void]$actions.Children.Add($btnEdit)

    $btnDel = New-Object System.Windows.Controls.Button
    $btnDel.Content = [char]0x2715  # MULTIPLICATION X
    $btnDel.Style = $Script:Shell.FindResource('IconBtn')
    $btnDel.ToolTip = 'Remove'
    $btnDel.Tag = $Q.id
    $btnDel.Add_Click({
        param($sender, $eventArgs)
        Remove-KitQuestion $Script:CurrentKitId $sender.Tag
    })
    [void]$actions.Children.Add($btnDel)

    [System.Windows.Controls.Grid]::SetColumn($actions, 3)
    [void]$g.Children.Add($actions)

    $b.Child = $g
    return $b
}

function Remove-KitQuestion {
    <#
    Drops one question from a kit. If the question's category is left empty,
    the category is also dropped. Persists + re-renders.
    #>
    param([string]$KitId, [string]$QuestionId)
    $data = $Script:ShellData
    $kit = Get-KitById $data $KitId
    if (-not $kit) { return }
    $changed = $false
    foreach ($cat in @($kit.categories)) {
        $before = @($cat.questions).Count
        $cat.questions = @($cat.questions | Where-Object id -ne $QuestionId)
        if (@($cat.questions).Count -lt $before) { $changed = $true }
    }
    if ($changed) {
        # Prune empty categories.
        $kit.categories = @($kit.categories | Where-Object { @($_.questions).Count -gt 0 })
        Save-Kits $data
        Set-ShellStatus "Question removed."
        Show-View 'TabKits'
    }
}

function _MoveKitQuestion {
    <#
    Reorders one question up or down WITHIN its own category. Questions are
    stored grouped under categories and the arrows only shuffle neighbors in
    the same bucket - a question never changes category by arrow (use the
    inline edit panel's category dropdown for that). At the first/last slot of
    a category the move is a no-op (the buttons are also disabled there).
    #>
    param([string]$KitId, [string]$QuestionId, [ValidateSet('Up','Down')][string]$Direction)
    # Diagnostic logging (tagged 'KitReorder') to trace any reorder anomaly in
    # the live app - the workflow is fully verified headlessly, so this exists
    # to catch a real-environment-only effect. Low-noise (fires only on a move).
    # Safe to remove once reorder is trusted.
    $log = Get-Command Write-TrueHireLog -ErrorAction SilentlyContinue
    $data = $Script:ShellData
    $kit = Get-KitById $data $KitId
    if (-not $kit) {
        if ($log) { Write-TrueHireLog -Level WARN -Source 'KitReorder' -Message ("ENTER {0} q={1}: kit '{2}' NOT FOUND" -f $Direction, $QuestionId, $KitId) }
        return
    }

    foreach ($cat in $kit.categories) {
        $arr = @($cat.questions)
        $myIdx = -1
        for ($qi = 0; $qi -lt $arr.Count; $qi++) {
            if ($arr[$qi].id -eq $QuestionId) { $myIdx = $qi; break }
        }
        if ($myIdx -lt 0) { continue }   # not in this category - keep looking

        $neighborIdx = if ($Direction -eq 'Up') { $myIdx - 1 } else { $myIdx + 1 }
        if ($log) {
            $before = (@($arr | ForEach-Object { $_.id }) -join ',')
            Write-TrueHireLog -Level INFO -Source 'KitReorder' -Message (
                "MOVE {0} q={1} cat={2} myIdx={3} neighborIdx={4} count={5} before=[{6}]" -f `
                $Direction, $QuestionId, $cat.id, $myIdx, $neighborIdx, $arr.Count, $before)
        }
        if ($neighborIdx -lt 0 -or $neighborIdx -ge $arr.Count) {
            if ($log) { Write-TrueHireLog -Level INFO -Source 'KitReorder' -Message ("  -> edge no-op (neighborIdx={0})" -f $neighborIdx) }
            return  # at edge - no-op
        }

        $tmp = $arr[$myIdx]
        $arr[$myIdx] = $arr[$neighborIdx]
        $arr[$neighborIdx] = $tmp
        $cat.questions = $arr
        if ($log) {
            $after = (@($arr | ForEach-Object { $_.id }) -join ',')
            Write-TrueHireLog -Level INFO -Source 'KitReorder' -Message ("  -> after=[{0}]" -f $after)
        }
        Save-Kits $data
        Show-View 'TabKits'
        return
    }
    if ($log) { Write-TrueHireLog -Level WARN -Source 'KitReorder' -Message ("MOVE {0} q={1}: id not found in any category of kit {2}" -f $Direction, $QuestionId, $KitId) }
}

function _MoveKitCategory {
    <#
    Reorders one whole category up or down among the kit's categories by
    swapping two entries in $kit.categories. Every downstream consumer walks
    that array in order - the question list, the weights panel, the kit
    preview, and the printable handout - so the new order flows through to all
    of them. At the first/last category the move is a no-op (the section
    header's arrows are also disabled there). Structural twin of
    _MoveKitQuestion (which swaps within a category's questions instead).
    #>
    param([string]$KitId, [string]$CategoryId, [ValidateSet('Up','Down')][string]$Direction)
    $log = Get-Command Write-TrueHireLog -ErrorAction SilentlyContinue
    $data = $Script:ShellData
    $kit = Get-KitById $data $KitId
    if (-not $kit) {
        if ($log) { Write-TrueHireLog -Level WARN -Source 'KitReorder' -Message ("CAT {0} cat={1}: kit '{2}' NOT FOUND" -f $Direction, $CategoryId, $KitId) }
        return
    }

    $cats = @($kit.categories)
    $myIdx = -1
    for ($ci = 0; $ci -lt $cats.Count; $ci++) {
        if ($cats[$ci].id -eq $CategoryId) { $myIdx = $ci; break }
    }
    if ($myIdx -lt 0) {
        if ($log) { Write-TrueHireLog -Level WARN -Source 'KitReorder' -Message ("CAT {0} cat={1}: not found in kit {2}" -f $Direction, $CategoryId, $KitId) }
        return
    }

    $neighborIdx = if ($Direction -eq 'Up') { $myIdx - 1 } else { $myIdx + 1 }
    if ($log) {
        $before = (@($cats | ForEach-Object { $_.id }) -join ',')
        Write-TrueHireLog -Level INFO -Source 'KitReorder' -Message (
            "CAT {0} cat={1} myIdx={2} neighborIdx={3} count={4} before=[{5}]" -f `
            $Direction, $CategoryId, $myIdx, $neighborIdx, $cats.Count, $before)
    }
    if ($neighborIdx -lt 0 -or $neighborIdx -ge $cats.Count) {
        if ($log) { Write-TrueHireLog -Level INFO -Source 'KitReorder' -Message ("  -> cat edge no-op (neighborIdx={0})" -f $neighborIdx) }
        return  # at edge - no-op
    }

    $tmp = $cats[$myIdx]
    $cats[$myIdx] = $cats[$neighborIdx]
    $cats[$neighborIdx] = $tmp
    $kit.categories = $cats
    if ($log) {
        $after = (@($cats | ForEach-Object { $_.id }) -join ',')
        Write-TrueHireLog -Level INFO -Source 'KitReorder' -Message ("  -> after=[{0}]" -f $after)
    }
    Save-Kits $data
    Show-View 'TabKits'
}

function _QuestionRowExpanded {
    <#
    Renders the inline editor that drops down under a question row when the
    pencil is clicked. Width matches the row; orange left border per the
    brainstorming mock. Returns a single Border.

    Q may be a real kit-question (live object on the kit) OR the pending-new
    hashtable from $Script:PendingNewQuestion. The IsPending flag tells the
    Save handler which path to take.
    #>
    param($Cat, $Q, [bool]$IsPending = $false)
    $data = $Script:ShellData

    $b = New-Object System.Windows.Controls.Border
    $b.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#FFFBF0')))
    $b.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#F5A623')))
    $b.BorderThickness = '3,0,0,1'
    $b.Padding = '40,14,16,14'

    $sp = New-Object System.Windows.Controls.StackPanel

    # --- CATEGORY combo -------------------------------------------------
    $catLabel = New-Object System.Windows.Controls.TextBlock
    $catLabel.Text = 'CATEGORY'; $catLabel.FontSize = 10; $catLabel.FontWeight = 'Bold'
    $catLabel.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#6B7B8C')))
    [void]$sp.Children.Add($catLabel)
    $catCombo = New-Object System.Windows.Controls.ComboBox
    $catCombo.Margin = '0,4,0,10'

    # Choices = catalog categories + any custom categories already on THIS kit
    # (custom=true, not shadowing a catalog id) so a custom category minted
    # earlier in the kit is reusable for the next question. All sorted A-Z; a
    # trailing "+ New category..." sentinel mints a brand-new custom category.
    $kitForCats = Get-KitById $data $Script:CurrentKitId
    $catalogIds = @($data.Catalog.categories | ForEach-Object { $_.id })
    $catChoices = @($data.Catalog.categories | ForEach-Object {
        [pscustomobject]@{ Id = $_.id; Name = [string]$_.name; Custom = $false }
    })
    if ($kitForCats) {
        foreach ($kc in @($kitForCats.categories)) {
            $isCustom = ($kc.PSObject.Properties['custom'] -and $kc.custom)
            if ($isCustom -and ($catalogIds -notcontains $kc.id)) {
                $catChoices += [pscustomobject]@{ Id = $kc.id; Name = [string]$kc.name; Custom = $true }
            }
        }
    }
    foreach ($cc in @($catChoices | Sort-Object { [string]$_.Name })) {
        $item = New-Object System.Windows.Controls.ComboBoxItem
        $item.Content = if ($cc.Custom) { "{0}  (custom)" -f $cc.Name } else { $cc.Name }
        $item.Tag = $cc.Id
        [void]$catCombo.Items.Add($item)
        if ($Cat -and $cc.Id -eq $Cat.id) { $catCombo.SelectedItem = $item }
    }
    $newCatItem = New-Object System.Windows.Controls.ComboBoxItem
    $newCatItem.Content = '+ New category...'
    $newCatItem.Tag = '__NEW__'
    [void]$catCombo.Items.Add($newCatItem)
    [void]$sp.Children.Add($catCombo)

    # Collapsed box revealed when the "+ New category..." sentinel is picked.
    $newCatBox = New-Object System.Windows.Controls.TextBox
    $newCatBox.Margin = '0,0,0,10'
    $newCatBox.Padding = '6'
    $newCatBox.Visibility = 'Collapsed'
    $newCatBox.ToolTip = 'Name for the new custom category'
    [void]$sp.Children.Add($newCatBox)

    # Show/hide the new-category box on selection. Inline (non-modal) editor =>
    # no GetNewClosure; read the box back via $sender.Tag (CLAUDE.md gotcha #2).
    $catCombo.Tag = @{ NewCatBox = $newCatBox }
    $catCombo.Add_SelectionChanged({
        param($sender, $eventArgs)
        $sel = $sender.SelectedItem
        $isNew = ($sel -and $sel.Tag -eq '__NEW__')
        $sender.Tag.NewCatBox.Visibility = if ($isNew) { 'Visible' } else { 'Collapsed' }
    })

    # --- PROBE textarea -------------------------------------------------
    $probeLabel = New-Object System.Windows.Controls.TextBlock
    $probeLabel.Text = 'PROBE'; $probeLabel.FontSize = 10; $probeLabel.FontWeight = 'Bold'
    $probeLabel.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#6B7B8C')))
    [void]$sp.Children.Add($probeLabel)
    $probeBx = New-Object System.Windows.Controls.TextBox
    $probeBx.AcceptsReturn = $true
    $probeBx.SpellCheck.IsEnabled = $true   # live spell check (built in XAML via MultilineField; set explicitly for this code-built box)
    $probeBx.TextWrapping = 'Wrap'
    $probeBx.MinHeight = 70
    $probeBx.Margin = '0,4,0,10'
    $probeBx.Padding = '6'
    $probeBx.Text = if ($Q.PSObject.Properties['probe']) { [string]$Q.probe } else { '' }
    [void]$sp.Children.Add($probeBx)

    # --- GUIDE textarea -------------------------------------------------
    $guideLabel = New-Object System.Windows.Controls.TextBlock
    $guideLabel.Text = 'SCORING GUIDE'; $guideLabel.FontSize = 10; $guideLabel.FontWeight = 'Bold'
    $guideLabel.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#6B7B8C')))
    [void]$sp.Children.Add($guideLabel)
    $guideBx = New-Object System.Windows.Controls.TextBox
    $guideBx.AcceptsReturn = $true
    $guideBx.SpellCheck.IsEnabled = $true   # live spell check, same as the probe box
    $guideBx.TextWrapping = 'Wrap'
    $guideBx.MinHeight = 70
    $guideBx.Margin = '0,4,0,10'
    $guideBx.Padding = '6'
    $guideBx.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#FAFAFC')))
    $guideBx.Text = if ($Q.PSObject.Properties['guide']) { [string]$Q.guide } else { '' }
    [void]$sp.Children.Add($guideBx)

    # --- Footer row: source label + action buttons ----------------------
    $foot = New-Object System.Windows.Controls.Grid
    $cd1 = New-Object System.Windows.Controls.ColumnDefinition; $cd1.Width = '*'
    $cd2 = New-Object System.Windows.Controls.ColumnDefinition; $cd2.Width = 'Auto'
    [void]$foot.ColumnDefinitions.Add($cd1); [void]$foot.ColumnDefinitions.Add($cd2)

    $sourceLabel = New-Object System.Windows.Controls.TextBlock
    $sourceLabel.FontSize = 11
    $sourceLabel.VerticalAlignment = 'Center'
    $sourceLabel.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#6B7B8C')))
    [System.Windows.Controls.Grid]::SetColumn($sourceLabel, 0)
    [void]$foot.Children.Add($sourceLabel)

    $btnPanel = New-Object System.Windows.Controls.StackPanel
    $btnPanel.Orientation = 'Horizontal'
    [System.Windows.Controls.Grid]::SetColumn($btnPanel, 1)

    $btnPick = New-Object System.Windows.Controls.Button
    $btnPick.Content = 'Pick from catalog...'
    $btnPick.Style = $Script:Shell.FindResource('GhostBtn')
    $btnPick.Margin = '0,0,8,0'
    [void]$btnPanel.Children.Add($btnPick)

    $btnRemove = New-Object System.Windows.Controls.Button
    $btnRemove.Content = 'Remove from kit'
    $btnRemove.Style = $Script:Shell.FindResource('GhostBtn')
    $btnRemove.Margin = '0,0,16,0'
    if ($IsPending) { $btnRemove.Visibility = 'Collapsed' }  # Nothing to remove yet.
    [void]$btnPanel.Children.Add($btnRemove)

    $btnCancel = New-Object System.Windows.Controls.Button
    $btnCancel.Content = 'Cancel'
    $btnCancel.Style = $Script:Shell.FindResource('GhostBtn')
    $btnCancel.Margin = '0,0,8,0'
    [void]$btnPanel.Children.Add($btnCancel)

    $btnSave = New-Object System.Windows.Controls.Button
    $btnSave.Content = 'Save'
    $btnSave.Style = $Script:Shell.FindResource('PrimaryBtn')
    [void]$btnPanel.Children.Add($btnSave)

    [void]$foot.Children.Add($btnPanel)
    [void]$sp.Children.Add($foot)

    # --- Source-label live update --------------------------------------
    # Stash everything the TextChanged handler needs on $probeBx.Tag so the
    # handler can read it back at fire-time via $sender.Tag. Earlier this used
    # `$sourceUpdater = {...}.GetNewClosure()` + `Add_TextChanged({ & $sourceUpdater })`
    # but WPF Paste raises TextChanged from a context where the captured
    # closure variable resolved to $null - producing the "expression after '&'
    # ... not valid" dispatcher error every paste. The Tag-stash form mirrors
    # the candidate-detail print buttons and is robust against the same trap.
    $probeBx.Tag = @{
        SourceLabel    = $sourceLabel
        CatCombo       = $catCombo
        Catalog        = $data.Catalog
        IsPending      = $IsPending
        QSource        = if ($Q.PSObject.Properties['source'])       { [string]$Q.source }   else { 'custom' }
        QCatalogIndex  = if ($Q.PSObject.Properties['catalogIndex']) { $Q.catalogIndex }     else { $null }
    }
    $updateSourceLabel = {
        param($Tb)
        $ctx = $Tb.Tag
        if ($ctx.IsPending) { $ctx.SourceLabel.Text = 'New custom probe'; return }
        if ($ctx.QSource -eq 'custom') { $ctx.SourceLabel.Text = 'Custom probe'; return }
        $catIdx = $ctx.QCatalogIndex
        $canonicalProbe = ''
        $catId = if ($ctx.CatCombo.SelectedItem) { $ctx.CatCombo.SelectedItem.Tag } else { '' }
        $catEntry = $ctx.Catalog.categories | Where-Object id -eq $catId | Select-Object -First 1
        if ($catEntry -and $catIdx) {
            $qq = $catEntry.questions | Where-Object index -eq $catIdx | Select-Object -First 1
            if ($qq) { $canonicalProbe = [string]$qq.probe }
        }
        if ($canonicalProbe -and ($Tb.Text.Trim() -eq $canonicalProbe.Trim())) {
            $ctx.SourceLabel.Text = ("Probe {0} from catalog" -f $catIdx)
        } else {
            $ctx.SourceLabel.Text = ("Probe {0} from catalog (edited)" -f $catIdx)
        }
    }
    & $updateSourceLabel $probeBx
    $probeBx.Add_TextChanged({
        param($sender, $eventArgs)
        $ctx = $sender.Tag
        if ($ctx.IsPending) { $ctx.SourceLabel.Text = 'New custom probe'; return }
        if ($ctx.QSource -eq 'custom') { $ctx.SourceLabel.Text = 'Custom probe'; return }
        $catIdx = $ctx.QCatalogIndex
        $canonicalProbe = ''
        $catId = if ($ctx.CatCombo.SelectedItem) { $ctx.CatCombo.SelectedItem.Tag } else { '' }
        $catEntry = $ctx.Catalog.categories | Where-Object id -eq $catId | Select-Object -First 1
        if ($catEntry -and $catIdx) {
            $qq = $catEntry.questions | Where-Object index -eq $catIdx | Select-Object -First 1
            if ($qq) { $canonicalProbe = [string]$qq.probe }
        }
        if ($canonicalProbe -and ($sender.Text.Trim() -eq $canonicalProbe.Trim())) {
            $ctx.SourceLabel.Text = ("Probe {0} from catalog" -f $catIdx)
        } else {
            $ctx.SourceLabel.Text = ("Probe {0} from catalog (edited)" -f $catIdx)
        }
    })

    # --- Click handlers (no GetNewClosure - they need to resolve helpers
    #     like Save-Kits / Show-View at fire time, per CLAUDE.md.) -------
    # Stash everything the handlers need on the Tag of one button so the
    # script-scope handler can read it back.
    $ctx = @{
        QuestionId   = $Q.id
        IsPending    = $IsPending
        KitId        = $Script:CurrentKitId
        ProbeBx      = $probeBx
        GuideBx      = $guideBx
        CatCombo     = $catCombo
        NewCatBox    = $newCatBox
    }
    $btnSave.Tag   = $ctx
    $btnCancel.Tag = $ctx
    $btnRemove.Tag = $ctx
    $btnPick.Tag   = $ctx

    $btnSave.Add_Click({
        param($sender, $eventArgs)
        Save-KitQuestionEdit $sender.Tag
    })
    $btnCancel.Add_Click({
        param($sender, $eventArgs)
        $Script:ExpandedQuestionId = $null
        if ($sender.Tag.IsPending) { $Script:PendingNewQuestion = $null }
        Show-View 'TabKits'
    })
    $btnRemove.Add_Click({
        param($sender, $eventArgs)
        $Script:ExpandedQuestionId = $null
        Remove-KitQuestion $sender.Tag.KitId $sender.Tag.QuestionId
    })
    $btnPick.Add_Click({
        param($sender, $eventArgs)
        $catId = if ($sender.Tag.CatCombo.SelectedItem) { $sender.Tag.CatCombo.SelectedItem.Tag } else { $null }
        if (-not $catId) {
            [System.Windows.MessageBox]::Show('Pick a category first.','TrueHire','OK','Information') | Out-Null
            return
        }
        $picked = Show-PickCatalogProbeDialog $catId
        if ($picked) {
            $sender.Tag.ProbeBx.Text = [string]$picked.probe
            $sender.Tag.GuideBx.Text = [string]$picked.guide
            # Stash the picked index on the context so Save can record it.
            $sender.Tag.PickedCatalogIndex = $picked.index
        }
    })

    $b.Child = $sp
    return $b
}

function Save-KitQuestionEdit {
    <#
    Commits an expanded-row edit. $Ctx is the hashtable stashed on each
    button's Tag inside _QuestionRowExpanded. Handles both real edits and
    the pending-new-question path.
    #>
    param([hashtable]$Ctx)
    $data = $Script:ShellData
    $kit = Get-KitById $data $Ctx.KitId
    if (-not $kit) { return }

    $probeText = $Ctx.ProbeBx.Text
    if (-not $probeText -or -not ($probeText.Trim())) {
        $Ctx.ProbeBx.BorderBrush = [System.Windows.Media.Brushes]::Red
        return
    }
    $guideText = $Ctx.GuideBx.Text
    $newCatId  = if ($Ctx.CatCombo.SelectedItem) { $Ctx.CatCombo.SelectedItem.Tag } else { $null }
    if (-not $newCatId) {
        [System.Windows.MessageBox]::Show('Pick a category.','TrueHire','OK','Information') | Out-Null
        return
    }

    # Resolve the "+ New category..." sentinel into a real category id. A typed
    # name that matches an existing catalog/kit category (case-insensitive)
    # reuses that id; otherwise we mint a fresh custom kit category.
    $newCatName = ''
    $newCatIsCustom = $false
    if ($newCatId -eq '__NEW__') {
        $box = $Ctx.NewCatBox
        $typed = if ($box) { ([string]$box.Text).Trim() } else { '' }
        if (-not $typed) {
            if ($box) { $box.BorderBrush = [System.Windows.Media.Brushes]::Red }
            return
        }
        $existingId = $null
        foreach ($cc in @($data.Catalog.categories)) {
            if ([string]$cc.name -ieq $typed) { $existingId = $cc.id; break }
        }
        if (-not $existingId) {
            foreach ($kc in @($kit.categories)) {
                if ([string]$kc.name -ieq $typed) { $existingId = $kc.id; break }
            }
        }
        if ($existingId) {
            $newCatId = $existingId
        } else {
            $newCatId = 'cat-' + [guid]::NewGuid().ToString('N').Substring(0,8)
            $newCatName = $typed
            $newCatIsCustom = $true
        }
    }

    if ($Ctx.IsPending) {
        # Build a brand-new kit-question from the pending hashtable.
        $newQ = [pscustomobject]@{
            id           = $Ctx.QuestionId
            source       = if ($Ctx.ContainsKey('PickedCatalogIndex') -and $Ctx.PickedCatalogIndex) { 'catalog' } else { 'custom' }
            catalogIndex = if ($Ctx.ContainsKey('PickedCatalogIndex')) { $Ctx.PickedCatalogIndex } else { $null }
            probe        = $probeText
            guide        = $guideText
        }
        _AppendToKitCategory $kit $newCatId $newQ -Name $newCatName -Custom:$newCatIsCustom
        $Script:PendingNewQuestion  = $null
        $Script:ExpandedQuestionId  = $null
    } else {
        # Find the existing question and mutate in place.
        $foundCat = $null; $foundQ = $null
        foreach ($cat in @($kit.categories)) {
            $candidate = $cat.questions | Where-Object id -eq $Ctx.QuestionId | Select-Object -First 1
            if ($candidate) { $foundCat = $cat; $foundQ = $candidate; break }
        }
        if (-not $foundQ) { return }
        $foundQ.probe = $probeText
        $foundQ.guide = $guideText
        if ($Ctx.ContainsKey('PickedCatalogIndex') -and $Ctx.PickedCatalogIndex) {
            $foundQ.source       = 'catalog'
            $foundQ.catalogIndex = $Ctx.PickedCatalogIndex
        }
        if ($foundCat.id -ne $newCatId) {
            # Category changed: pull from old bucket, push onto new.
            $foundCat.questions = @($foundCat.questions | Where-Object id -ne $foundQ.id)
            _AppendToKitCategory $kit $newCatId $foundQ -Name $newCatName -Custom:$newCatIsCustom
            # Prune empty source.
            if (@($foundCat.questions).Count -eq 0) {
                $kit.categories = @($kit.categories | Where-Object id -ne $foundCat.id)
            }
        }
        $Script:ExpandedQuestionId = $null
    }
    Save-Kits $data
    Set-ShellStatus 'Question saved.'
    Show-View 'TabKits'
}

function Show-PickCatalogProbeDialog {
    <#
    Modal lister for the canonical probes inside one catalog category.
    Returns @{ index; probe; guide } for the clicked row, or $null on cancel.
    Called from the expanded-row editor's "Pick from catalog..." link.
    #>
    param([string]$CategoryId)
    $data = $Script:ShellData
    $catEntry = $data.Catalog.categories | Where-Object id -eq $CategoryId | Select-Object -First 1
    if (-not $catEntry) {
        [System.Windows.MessageBox]::Show("No catalog entry for '$CategoryId'.",'TrueHire','OK','Information') | Out-Null
        return $null
    }

    $w = ConvertTo-Window -Xaml $Script:PickCatalogProbeXaml
    $w.Owner = $Script:Shell
    ($w.FindName('PcpHeader')).Text = $catEntry.name
    ($w.FindName('PcpSub')).Text    = 'Click a probe to copy its text and scoring guide into the editor.'
    $list = $w.FindName('PcpList')

    # Local state holder so the click handlers can communicate back.
    $picked = @{ Value = $null }

    foreach ($qq in @($catEntry.questions)) {
        $row = New-Object System.Windows.Controls.Border
        $row.Background = 'White'
        $row.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#E4E8EF')))
        $row.BorderThickness = '1'
        $row.CornerRadius = '8'
        $row.Padding = '12'
        $row.Margin = '0,0,0,8'
        $row.Cursor = 'Hand'
        $row.Tag = @{ Index = [int]$qq.index; Probe = [string]$qq.probe; Guide = [string]$qq.guide; Win = $w; Picked = $picked }

        $st = New-Object System.Windows.Controls.StackPanel
        $head = New-Object System.Windows.Controls.TextBlock
        $head.Text = "Probe $($qq.index)"
        $head.FontWeight = 'SemiBold'; $head.FontSize = 12
        $head.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#1565C0')))
        [void]$st.Children.Add($head)

        $probe = New-Object System.Windows.Controls.TextBlock
        $probe.Text = $qq.probe
        $probe.FontSize = 13
        $probe.TextWrapping = 'Wrap'
        $probe.Margin = '0,4,0,0'
        $probe.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#0B2C45')))
        [void]$st.Children.Add($probe)

        if ($qq.guide) {
            $guide = New-Object System.Windows.Controls.TextBlock
            $guide.Text = "Scoring: $($qq.guide)"
            $guide.FontSize = 11
            $guide.TextWrapping = 'Wrap'
            $guide.Margin = '0,4,0,0'
            $guide.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#6B7B8C')))
            [void]$st.Children.Add($guide)
        }

        $row.Child = $st
        $row.Add_MouseLeftButtonUp({
            param($sender, $eventArgs)
            $t = $sender.Tag
            $t.Picked.Value = @{ index = $t.Index; probe = $t.Probe; guide = $t.Guide }
            $t.Win.DialogResult = $true; $t.Win.Close()
        })
        [void]$list.Children.Add($row)
    }

    $w.FindName('PcpCancel').Add_Click({
        param($sender, $eventArgs)
        $w.DialogResult = $false; $w.Close()
    })
    [void]$w.ShowDialog()
    return $picked.Value
}

function Show-KitBuilder {
    <#
    Bulk-add specific catalog probes to a kit. Each catalog category renders
    as an expandable header (expand toggle + select-all checkbox + name +
    "n of m selected"); expanding it lists every canonical probe with its own
    checkbox so the user can pick exactly the questions they want - e.g. two
    of five - rather than just a count. Appends - never replaces - existing
    kit questions so the builder can be re-run to grow a kit.
    #>
    param([string]$KitId)
    $data = $Script:ShellData
    $kit = Get-KitById $data $KitId
    if (-not $kit) { return }

    $w = ConvertTo-Window -Xaml $Script:KitBuilderXaml
    $w.Owner = $Script:Shell

    # Per-category UI state keyed by category id:
    #   { CatEntry; Expanded; ExpandBtn; ChildPanel; HeaderCheck; CountLabel;
    #     QStates = [ { Index; QEntry; Selected; Check }, ... ] }
    $rowState = @{}
    $list  = $w.FindName('KbList')
    $count = $w.FindName('KbCount')
    $apply = $w.FindName('KbApply')

    $recompute = {
        $totalQ = 0; $totalCats = 0
        foreach ($cid in $rowState.Keys) {
            $st = $rowState[$cid]
            $selCount = @($st.QStates | Where-Object { $_.Selected }).Count
            $availCount = @($st.QStates).Count
            $st.CountLabel.Text = ("{0} of {1}" -f $selCount, $availCount)
            if ($selCount -gt 0) { $totalQ += $selCount; $totalCats++ }
            # Reflect all/some/none on the select-all checkbox. Setting
            # IsChecked programmatically does NOT raise Click, so this can't
            # re-enter the header handler.
            if     ($selCount -eq 0)          { $st.HeaderCheck.IsChecked = $false }
            elseif ($selCount -eq $availCount){ $st.HeaderCheck.IsChecked = $true }
            else                              { $st.HeaderCheck.IsChecked = $null }  # indeterminate
        }
        $count.Text = ("{0} questions across {1} categories" -f $totalQ, $totalCats)
        $apply.IsEnabled = ($totalQ -gt 0)
    }.GetNewClosure()

    foreach ($cat in @($data.Catalog.categories | Sort-Object { [string]$_.name })) {
        $catId = $cat.id
        $sortedQs = @($cat.questions | Sort-Object { [int]$_.index })

        $catBox = New-Object System.Windows.Controls.StackPanel
        $catBox.Margin = '0,0,0,2'

        # --- Header row: expand | select-all | name | count -----------------
        $header = New-Object System.Windows.Controls.Grid
        $header.Margin = '0,4,0,2'
        foreach ($wd in 26,26,'*',70) {
            $cd = New-Object System.Windows.Controls.ColumnDefinition
            $cd.Width = if ($wd -is [string]) { '*' } else { [System.Windows.GridLength]::new($wd) }
            [void]$header.ColumnDefinitions.Add($cd)
        }

        $expandBtn = New-Object System.Windows.Controls.Button
        $expandBtn.Content = [char]0x25B8   # BLACK RIGHT-POINTING SMALL TRIANGLE
        $expandBtn.Style = $Script:Shell.FindResource('IconBtn')
        $expandBtn.ToolTip = 'Show / hide questions'
        $expandBtn.Tag = $catId
        [System.Windows.Controls.Grid]::SetColumn($expandBtn, 0)
        [void]$header.Children.Add($expandBtn)

        $hcb = New-Object System.Windows.Controls.CheckBox
        $hcb.VerticalAlignment = 'Center'
        $hcb.IsThreeState = $true
        $hcb.ToolTip = 'Select / clear all questions in this category'
        $hcb.Tag = $catId
        [System.Windows.Controls.Grid]::SetColumn($hcb, 1)
        [void]$header.Children.Add($hcb)

        $nm = New-Object System.Windows.Controls.TextBlock
        $nm.Text = $cat.name
        $nm.FontSize = 13; $nm.FontWeight = 'SemiBold'
        $nm.VerticalAlignment = 'Center'
        $nm.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#0B2C45')))
        [System.Windows.Controls.Grid]::SetColumn($nm, 2)
        [void]$header.Children.Add($nm)

        $cntLbl = New-Object System.Windows.Controls.TextBlock
        $cntLbl.FontSize = 11
        $cntLbl.VerticalAlignment = 'Center'
        $cntLbl.HorizontalAlignment = 'Right'
        $cntLbl.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#6B7B8C')))
        [System.Windows.Controls.Grid]::SetColumn($cntLbl, 3)
        [void]$header.Children.Add($cntLbl)

        [void]$catBox.Children.Add($header)

        # --- Child panel: one checkbox row per canonical probe (collapsed) ---
        $childPanel = New-Object System.Windows.Controls.StackPanel
        $childPanel.Margin = '52,0,0,8'
        $childPanel.Visibility = 'Collapsed'

        $qStates = New-Object System.Collections.ArrayList
        foreach ($qq in $sortedQs) {
            $qrow = New-Object System.Windows.Controls.Grid
            $qrow.Margin = '0,3,0,3'
            $cda = New-Object System.Windows.Controls.ColumnDefinition; $cda.Width = [System.Windows.GridLength]::new(26)
            $cdb = New-Object System.Windows.Controls.ColumnDefinition; $cdb.Width = '*'
            [void]$qrow.ColumnDefinitions.Add($cda); [void]$qrow.ColumnDefinitions.Add($cdb)

            $qcb = New-Object System.Windows.Controls.CheckBox
            $qcb.VerticalAlignment = 'Top'
            $qcb.Margin = '0,2,0,0'
            [System.Windows.Controls.Grid]::SetColumn($qcb, 0)
            [void]$qrow.Children.Add($qcb)

            $qtxt = New-Object System.Windows.Controls.TextBlock
            $qtxt.Text = ("{0}. {1}" -f [int]$qq.index, [string]$qq.probe)
            $qtxt.FontSize = 12.5
            $qtxt.TextWrapping = 'Wrap'
            $qtxt.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#2C3E50')))
            [System.Windows.Controls.Grid]::SetColumn($qtxt, 1)
            [void]$qrow.Children.Add($qtxt)

            [void]$childPanel.Children.Add($qrow)

            $qstate = @{ Index = [int]$qq.index; QEntry = $qq; Selected = $false; Check = $qcb }
            [void]$qStates.Add($qstate)

            # Stash the question's own state on the checkbox so the handler
            # mutates the right row without closing over the loop variable.
            $qcb.Tag = $qstate
            $qcb.Add_Click({
                param($sender, $eventArgs)
                $sender.Tag.Selected = [bool]$sender.IsChecked
                & $recompute
            })
        }

        [void]$catBox.Children.Add($childPanel)
        [void]$list.Children.Add($catBox)

        $rowState[$catId] = @{
            CatEntry    = $cat
            Expanded    = $false
            ExpandBtn   = $expandBtn
            ChildPanel  = $childPanel
            HeaderCheck = $hcb
            CountLabel  = $cntLbl
            QStates     = $qStates
        }

        $expandBtn.Add_Click({
            param($sender, $eventArgs)
            $st = $rowState[$sender.Tag]
            $st.Expanded = -not $st.Expanded
            if ($st.Expanded) {
                $st.ChildPanel.Visibility = 'Visible'
                $sender.Content = [char]0x25BE   # BLACK DOWN-POINTING SMALL TRIANGLE
            } else {
                $st.ChildPanel.Visibility = 'Collapsed'
                $sender.Content = [char]0x25B8
            }
        })

        $hcb.Add_Click({
            param($sender, $eventArgs)
            $st = $rowState[$sender.Tag]
            # Click toggles the whole category: select all unless everything is
            # already selected, in which case clear all.
            $allSelected = (@($st.QStates | Where-Object { $_.Selected }).Count -eq @($st.QStates).Count)
            $target = -not $allSelected
            foreach ($qs in $st.QStates) {
                $qs.Selected = $target
                $qs.Check.IsChecked = $target
            }
            & $recompute
        })
    }
    & $recompute

    $w.FindName('KbCancel').Add_Click({
        param($sender, $eventArgs)
        $w.DialogResult = $false; $w.Close()
    })
    $w.FindName('KbApply').Add_Click({
        param($sender, $eventArgs)
        Apply-KitBuilderSelection $KitId $rowState
        $w.DialogResult = $true; $w.Close()
    })
    [void]$w.ShowDialog()
}

function Apply-KitBuilderSelection {
    <#
    Walks the dialog's row state and appends the individually-selected probes
    to the kit. For each category, takes exactly the probes the user ticked
    (in catalog order), copies probe+guide into new kit-questions, and appends
    them to the kit's bucket (creating the bucket if missing). Persists and
    refreshes the view.
    #>
    param([string]$KitId, [hashtable]$RowState)
    $data = $Script:ShellData
    $kit = Get-KitById $data $KitId
    if (-not $kit) { return }
    $added = 0
    foreach ($cid in $RowState.Keys) {
        $st = $RowState[$cid]
        $picked = @($st.QStates | Where-Object { $_.Selected } | Sort-Object { [int]$_.Index })
        foreach ($qs in $picked) {
            $cq = $qs.QEntry
            $newQ = [pscustomobject]@{
                id           = 'kq-' + [guid]::NewGuid().ToString('N').Substring(0,8)
                source       = 'catalog'
                catalogIndex = [int]$cq.index
                probe        = [string]$cq.probe
                guide        = [string]$cq.guide
            }
            _AppendToKitCategory $kit $cid $newQ
            $added++
        }
    }
    Save-Kits $data
    Set-ShellStatus ("Added {0} questions to '{1}'." -f $added, $kit.name)
    Show-View 'TabKits'
}

function Show-PickJobForKitDialog {
    <#
    Modal picker for when + New Interview Kit finds multiple orphan jobs.
    Returns the chosen job object, or $null on cancel.
    #>
    param([array]$Orphans)
    $w = ConvertTo-Window -Xaml $Script:PickJobForKitXaml
    $w.Owner = $Script:Shell
    $listBox = $w.FindName('PjkList')
    foreach ($job in $Orphans) {
        $item = New-Object System.Windows.Controls.ListBoxItem
        $item.Content = "$($job.reqNumber) - $($job.title)"
        $item.Tag = $job
        [void]$listBox.Items.Add($item)
    }
    $create = $w.FindName('PjkCreate')
    $listBox.Add_SelectionChanged({
        param($sender, $eventArgs)
        $create.IsEnabled = ($sender.SelectedItem -ne $null)
    })

    $picked = @{ Value = $null }
    $w.FindName('PjkCancel').Add_Click({
        param($sender, $eventArgs)
        $w.DialogResult = $false; $w.Close()
    })
    $create.Add_Click({
        param($sender, $eventArgs)
        if ($listBox.SelectedItem) { $picked.Value = $listBox.SelectedItem.Tag }
        $w.DialogResult = $true; $w.Close()
    })
    [void]$w.ShowDialog()
    return $picked.Value
}

function _RecomputeWeightPercents {
    <#
    Updates each row's effective-% label = weight / sum(weights). Reads the
    live weight off each row's category object. $Rows is an array of
    @{ Cat; Box; Pct } hashtables.
    #>
    param($Rows)
    $sum = 0.0
    foreach ($r in $Rows) { $sum += [double]$r.Cat.weight }
    foreach ($r in $Rows) {
        $pct = if ($sum -gt 0) { 100.0 * [double]$r.Cat.weight / $sum } else { 0 }
        $r.Pct.Text = ("{0:0}%" -f $pct)
    }
}

function _BuildCategoryWeightsPanel {
    <#
    Returns a panel listing each kit category with a relative-weight TextBox and
    a live effective-% readout. Editing a box (on LostFocus) writes the weight
    back onto the category object, recomputes all percentages, and persists via
    Save-Kits. Built for a NON-modal view: handlers use param($sender,...) and
    read shared state off $sender.Tag - NO GetNewClosure (see CLAUDE.md gotcha 2).
    #>
    param($Kit)

    $card = New-Object System.Windows.Controls.Border
    $card.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#F7F9FC')))
    $card.CornerRadius = '8'
    $card.Padding = '14'
    $card.Margin = '0,0,0,14'

    $outer = New-Object System.Windows.Controls.StackPanel

    $hdr = New-Object System.Windows.Controls.TextBlock
    $hdr.Text = 'Category weights'
    $hdr.FontSize = 13
    $hdr.FontWeight = 'SemiBold'
    $hdr.Margin = '0,0,0,2'
    $hdr.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#0B2C45')))
    [void]$outer.Children.Add($hdr)

    $sub = New-Object System.Windows.Controls.TextBlock
    $sub.Text = 'Relative importance per category. Effective % is shown live and totals ~100%.'
    $sub.FontSize = 11
    $sub.TextWrapping = 'Wrap'
    $sub.Margin = '0,0,0,10'
    $sub.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#6B7B8C')))
    [void]$outer.Children.Add($sub)

    $rows = New-Object System.Collections.ArrayList   # @{ Cat; Box; Pct }
    $shared = @{ Rows = $rows }

    foreach ($cat in @($Kit.categories)) {
        if (-not (_HasProp $cat 'weight') -or $null -eq $cat.weight) { _SetProp $cat 'weight' 1 }

        $row = New-Object System.Windows.Controls.Grid
        $row.Margin = '0,0,0,6'
        foreach ($wd in '*', 70, 60) {
            $cd = New-Object System.Windows.Controls.ColumnDefinition
            $cd.Width = if ($wd -is [string]) { '*' } else { [System.Windows.GridLength]::new($wd) }
            [void]$row.ColumnDefinitions.Add($cd)
        }

        $nm = New-Object System.Windows.Controls.TextBlock
        $nm.Text = (Get-CategoryLabel $cat $Script:ShellData.Catalog)
        $nm.FontSize = 12.5
        $nm.VerticalAlignment = 'Center'
        $nm.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#2C3E50')))
        [System.Windows.Controls.Grid]::SetColumn($nm, 0)
        [void]$row.Children.Add($nm)

        $box = New-Object System.Windows.Controls.TextBox
        $box.Width = 56
        $box.HorizontalAlignment = 'Left'
        $box.VerticalContentAlignment = 'Center'
        $box.Text = [string]$cat.weight
        [System.Windows.Controls.Grid]::SetColumn($box, 1)
        [void]$row.Children.Add($box)

        $pct = New-Object System.Windows.Controls.TextBlock
        $pct.FontSize = 12.5
        $pct.FontWeight = 'SemiBold'
        $pct.HorizontalAlignment = 'Right'
        $pct.VerticalAlignment = 'Center'
        $pct.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#1565C0')))
        [System.Windows.Controls.Grid]::SetColumn($pct, 2)
        [void]$row.Children.Add($pct)

        $rowState = @{ Cat = $cat; Box = $box; Pct = $pct }
        [void]$rows.Add($rowState)

        $box.Tag = $shared
        $box.Add_LostFocus({
            param($sender, $eventArgs)
            $sh = $sender.Tag
            $me = $null
            foreach ($r in $sh.Rows) { if ($r.Box -eq $sender) { $me = $r; break } }
            if (-not $me) { return }
            $val = 0.0
            if ([double]::TryParse($sender.Text, [ref]$val) -and $val -ge 0) {
                _SetProp $me.Cat 'weight' $val
                $sender.Text = [string]$val   # canonicalize (e.g. "2." -> "2")
            } else {
                $sender.Text = [string]$me.Cat.weight   # revert invalid input
            }
            _RecomputeWeightPercents $sh.Rows
            Save-Kits $Script:ShellData
        })

        [void]$outer.Children.Add($row)
    }

    _RecomputeWeightPercents $rows
    $card.Child = $outer
    return $card
}

function _AppendToKitCategory {
    <#
    Adds a question to the named category in a kit. Creates the category
    bucket (seeded from the catalog's name + description) if it doesn't
    exist yet. -Name / -Custom let callers create a kit-local custom category
    that has no catalog entry; custom buckets get a non-empty description so
    _MigrateKit doesn't emit a per-load "no description" WARN.
    #>
    param($Kit, [string]$CatId, $Question, [string]$Name = '', [switch]$Custom)
    $data = $Script:ShellData
    $bucket = $Kit.categories | Where-Object id -eq $CatId | Select-Object -First 1
    if (-not $bucket) {
        $catEntry = $data.Catalog.categories | Where-Object id -eq $CatId | Select-Object -First 1
        $bucketName = if ($Name)         { $Name }
                      elseif ($catEntry) { [string]$catEntry.name }
                      else               { $CatId }
        $bucketDesc = if ($catEntry)   { [string]$catEntry.description }
                      elseif ($Custom) { 'Custom category.' }
                      else             { '' }
        $bucket = [pscustomobject]@{
            id          = $CatId
            name        = $bucketName
            description = $bucketDesc
            custom      = [bool]$Custom
            weight      = 1
            questions   = @()
        }
        $Kit.categories = @($Kit.categories) + $bucket
    }
    $bucket.questions = @($bucket.questions) + @($Question)
}

function Show-InterviewKitsView {
    param($Container)
    $root = [System.Windows.Markup.XamlReader]::Parse($Script:KitsXaml)
    [void]$Container.Children.Add($root)
    $data = $Script:ShellData

    $railPanel = $root.FindName('KitListPanel')
    $searchBox = $root.FindName('KitSearch')
    $countTxt  = $root.FindName('KitListCount')
    $qPanel    = $root.FindName('QuestionsPanel')

    if (-not $Script:CurrentKitId -and $data.Kits.Count -gt 0) {
        $Script:CurrentKitId = $data.Kits[0].id
    }

    $renderRail = {
        $railPanel.Children.Clear()
        $q = $searchBox.Text
        $kits = @($data.Kits)
        if ($q) {
            $kits = @($kits | Where-Object { $_.name -like "*$q*" })
        }
        foreach ($k in $kits) {
            $job = Get-JobById $data $k.jobReqId
            [void]$railPanel.Children.Add( (_KitRailRow $k $job) )
        }
        $countTxt.Text = ("Showing {0} of {1} kits" -f $kits.Count, $data.Kits.Count)
    }.GetNewClosure()

    & $renderRail
    $searchBox.Add_TextChanged({ & $renderRail }.GetNewClosure())

    # Right pane ----------------------------------------------------------
    $kit = Get-KitById $data $Script:CurrentKitId
    $job = if ($kit) { Get-JobById $data $kit.jobReqId } else { $null }
    if ($kit) {
        # PowerShell's `if` is a statement here; lift the branches into vars.
        $kitNameTxt = if ($job) { "$($job.title) Kit" } else { $kit.name }
        ($root.FindName('KitName')).Text = $kitNameTxt
        $jobLabel = if ($job) { $job.reqNumber + ' ' + $job.title } else { 'unlinked' }
        $createdFmt = ([datetime]$kit.createdDate).ToString('MMM d, yyyy')
        ($root.FindName('KitMeta')).Text = "Job: {0}    Created: {1}" -f $jobLabel, $createdFmt
        ($root.FindName('KitPillHost')).Child = (New-StatusPill -Status $kit.status)
        # Total questions = sum of questions across all categories. The old
        # code used {0} twice and counted categories - misleading on its face
        # AND wrong in principle (a category can hold multiple questions).
        $totalQuestions = 0
        foreach ($cat in $kit.categories) { $totalQuestions += @($cat.questions).Count }
        $cap = $root.FindName('KitQuestionCount')
        if ($totalQuestions -ge 10) {
            $cap.Text = ("[!] {0} questions across {1} categories - over recommended limit (10)" -f $totalQuestions, @($kit.categories).Count)
            $cap.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#F5A623')))
            $cap.FontWeight = 'SemiBold'
        } else {
            $cap.Text = ("{0} questions across {1} categories" -f $totalQuestions, @($kit.categories).Count)
            $cap.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#6B7B8C')))
            $cap.FontWeight = 'Normal'
        }

        if (@($kit.categories).Count -eq 0 -and -not $Script:PendingNewQuestion) {
            # Empty state: centered CTA in place of the grid.
            $empty = New-Object System.Windows.Controls.StackPanel
            $empty.HorizontalAlignment = 'Center'
            $empty.VerticalAlignment   = 'Center'
            $empty.Margin = '0,60,0,60'

            $msg = New-Object System.Windows.Controls.TextBlock
            $msg.Text = 'This kit has no questions yet.'
            $msg.FontSize = 14
            $msg.HorizontalAlignment = 'Center'
            $msg.Margin = '0,0,0,14'
            $msg.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#6B7B8C')))
            [void]$empty.Children.Add($msg)

            $btns = New-Object System.Windows.Controls.StackPanel
            $btns.Orientation = 'Horizontal'
            $btns.HorizontalAlignment = 'Center'
            $bb = New-Object System.Windows.Controls.Button
            $bb.Content = '+ Build from Catalog...'
            $bb.Style = $Script:Shell.FindResource('BlueBtn')
            $bb.Margin = '0,0,16,0'
            $bb.Add_Click({
                param($sender, $eventArgs)
                if ($Script:CurrentKitId) { Show-KitBuilder $Script:CurrentKitId }
            })
            [void]$btns.Children.Add($bb)
            $aq = New-Object System.Windows.Controls.Button
            $aq.Content = '+ Add Question'
            $aq.Style = $Script:Shell.FindResource('PrimaryBtn')
            $aq.Add_Click({
                param($sender, $eventArgs)
                if (-not $Script:CurrentKitId) { return }
                $newId = 'kq-' + [guid]::NewGuid().ToString('N').Substring(0,8)
                $Script:PendingNewQuestion = @{ id = $newId; categoryId = ''; probe = ''; guide = '' }
                $Script:ExpandedQuestionId = $newId
                Show-View 'TabKits'
            })
            [void]$btns.Children.Add($aq)
            [void]$empty.Children.Add($btns)

            [void]$qPanel.Children.Add($empty)
        } else {
            # Category weights editor (one row per category, live effective %).
            # Skipped when there are no categories yet (e.g. only a pending new
            # question) so we don't render an empty weights card.
            if (@($kit.categories).Count -gt 0) {
                [void]$qPanel.Children.Add( (_BuildCategoryWeightsPanel $kit) )
            }
            # One visible section per category. The header carries the
            # category-reorder arrows ($ci/$catList.Count drive their grey-out
            # at the first/last category). Numbering restarts at 1 inside each
            # section so the per-question reorder (arrows grey at section edges)
            # reads correctly; RowIndex/TotalRows passed to _QuestionRow are
            # already per-category and still drive arrow enablement.
            $catList = @($kit.categories)
            for ($ci = 0; $ci -lt $catList.Count; $ci++) {
                $cat = $catList[$ci]
                $catQs = @($cat.questions)
                [void]$qPanel.Children.Add( (_BuildCategorySectionHeader $cat $catQs.Count $ci $catList.Count) )
                for ($qi = 0; $qi -lt $catQs.Count; $qi++) {
                    $q = $catQs[$qi]
                    [void]$qPanel.Children.Add( (_QuestionRow ($qi + 1) $cat $q $qi $catQs.Count) )
                    if ($Script:ExpandedQuestionId -eq $q.id) {
                        [void]$qPanel.Children.Add( (_QuestionRowExpanded $cat $q $false) )
                    }
                }
            }
            # Pending-new question - render an extra expanded block at the bottom.
            if ($Script:PendingNewQuestion -and $Script:ExpandedQuestionId -eq $Script:PendingNewQuestion.id) {
                # Build a faux question PSCustomObject so _QuestionRowExpanded reads from it.
                $pendingQ = [pscustomobject]@{
                    id     = $Script:PendingNewQuestion.id
                    probe  = $Script:PendingNewQuestion.probe
                    guide  = $Script:PendingNewQuestion.guide
                    source = 'custom'
                }
                # Cat=$null lets _QuestionRowExpanded show the combo with no pre-selection.
                [void]$qPanel.Children.Add( (_QuestionRowExpanded $null $pendingQ $true) )
            }
        }
    } else {
        ($root.FindName('KitName')).Text = 'No kits yet'
        ($root.FindName('KitMeta')).Text = 'Create a job requisition first, then build its interview kit.'
    }

    # Hook so JobReqs view can jump straight to the matching kit ------------
    # NOTE: cross-file $Script: state doesn't work - functions defined in
    # different .ps1 files have separate Script scopes even when dot-sourced.
    # This hook is still set for backwards compat but the BtnOpenKit handler
    # in JobReqs.ps1 no longer calls through it; it does the navigation
    # inline (Get-KitForJob + assign + Show-View) via a script-scope-safe
    # helper. See Set-CurrentKitForJob below.
    $Script:KitSelectAction = {
        param($JobId)
        $k = Get-KitForJob $Script:ShellData $JobId
        if ($k) {
            $Script:CurrentKitId = $k.id
            Show-View 'TabKits'
        }
    }

    # New kit button ---------------------------------------------------------
    # The model is 1:1 (kit.jobReqId is unique). Refuse to create a second kit
    # for a job that already has one. When multiple orphan jobs exist, ask
    # which one to attach the kit to.
    $root.FindName('BtnNewKit').Add_Click({
        param($sender, $eventArgs)
        $data = $Script:ShellData
        if (-not $data.Jobs -or @($data.Jobs).Count -eq 0) {
            [System.Windows.MessageBox]::Show('Create a Job Requisition first.','TrueHire','OK','Information') | Out-Null
            return
        }
        $orphans = @($data.Jobs | Where-Object {
            $jobId = $_.id
            -not ($data.Kits | Where-Object jobReqId -eq $jobId)
        })
        if ($orphans.Count -eq 0) {
            [System.Windows.MessageBox]::Show(
                'Every job requisition already has an interview kit. Create a new requisition first.',
                'TrueHire','OK','Information') | Out-Null
            return
        }
        $job = if ($orphans.Count -eq 1) { $orphans[0] } else { Show-PickJobForKitDialog -Orphans $orphans }
        if (-not $job) { return }
        $newKit = New-InterviewKit -JobReqId $job.id -Name "$($job.title) Kit"
        $data.Kits = @($data.Kits) + $newKit
        Save-Kits $data
        $Script:CurrentKitId = $newKit.id
        Show-View 'TabKits'
    })

    # Build from Catalog button - open the bulk picker ----------------------
    $root.FindName('BtnBuildFromCatalog').Add_Click({
        param($sender, $eventArgs)
        if (-not $Script:CurrentKitId) { return }
        Show-KitBuilder $Script:CurrentKitId
    })

    # Add Question button - spawn a pending-new editor at the bottom -------
    $root.FindName('BtnAddQuestion').Add_Click({
        param($sender, $eventArgs)
        if (-not $Script:CurrentKitId) { return }
        if ($Script:PendingNewQuestion) {
            # Already adding one - just make sure the expanded editor is on it.
            $Script:ExpandedQuestionId = $Script:PendingNewQuestion.id
            Show-View 'TabKits'
            return
        }
        $newId = 'kq-' + [guid]::NewGuid().ToString('N').Substring(0,8)
        $Script:PendingNewQuestion = @{ id = $newId; categoryId = ''; probe = ''; guide = '' }
        $Script:ExpandedQuestionId = $newId
        Show-View 'TabKits'
    })

    # Preview / Edit / Print Handout: NO .GetNewClosure(). A closure-wrapped
    # WPF handler can't resolve script-scope function names like
    # Show-KitPreview / New-InterviewHandoutHtml at fire time - the call
    # silently throws "term not recognized" and the button looks dead.
    # param($sender, $eventArgs) forces dynamic scope so the function names
    # resolve against the dot-sourced session at click time. Same pattern
    # the Candidates view print buttons use. See CLAUDE.md.
    $root.FindName('BtnPreview').Add_Click({
        param($sender, $eventArgs)
        if (-not $Script:CurrentKitId) { return }
        Show-KitPreview $Script:CurrentKitId
    })

    $root.FindName('BtnEditKit').Add_Click({
        param($sender, $eventArgs)
        if (-not $Script:CurrentKitId) { return }
        Show-KitEditDialog $Script:CurrentKitId
    })

    # Print Handout: generate the printable HTML and open it in the user's
    # browser. The browser's native print dialog produces the actual PDF.
    $root.FindName('BtnPrintHandout').Add_Click({
        param($sender, $eventArgs)
        if (-not $Script:CurrentKitId) { return }
        $k = Get-KitById $Script:ShellData $Script:CurrentKitId
        if (-not $k) { return }
        $j = Get-JobById $Script:ShellData $k.jobReqId
        $path = New-InterviewHandoutHtml -Kit $k -Job $j -Catalog $Script:ShellData.Catalog
        Open-TrueHireOutput -Path $path
    })

    # Print Candidate Set: same questions, no interpretive/scoring guide -
    # the copy you hand to the candidate. -CandidateCopy strips the answers.
    $root.FindName('BtnPrintCandidate').Add_Click({
        param($sender, $eventArgs)
        if (-not $Script:CurrentKitId) { return }
        $k = Get-KitById $Script:ShellData $Script:CurrentKitId
        if (-not $k) { return }
        $j = Get-JobById $Script:ShellData $k.jobReqId
        $path = New-InterviewHandoutHtml -Kit $k -Job $j -Catalog $Script:ShellData.Catalog -CandidateCopy
        Open-TrueHireOutput -Path $path
    })
}

$Script:PickJobForKitXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Pick a Job Requisition" Width="520" Height="420"
        WindowStartupLocation="CenterOwner"
        Background="{StaticResource PageBg}" FontFamily="Segoe UI">
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <Border Grid.Row="0" Background="#0B2C45" Padding="20,14">
      <StackPanel>
        <TextBlock Foreground="White" FontSize="18" FontWeight="Bold" Text="Pick a Job Requisition"/>
        <TextBlock Foreground="#CBDBEA" FontSize="12"
                   Text="More than one job has no interview kit yet. Pick which one to build a kit for."/>
      </StackPanel>
    </Border>
    <ListBox x:Name="PjkList" Grid.Row="1" Margin="20,12,20,12"
             BorderBrush="{StaticResource CardBorder}" BorderThickness="1"/>
    <Border Grid.Row="2" Background="White" BorderBrush="{StaticResource CardBorder}"
            BorderThickness="0,1,0,0" Padding="20,12">
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Button x:Name="PjkCancel" Content="Cancel" Style="{StaticResource GhostBtn}" Margin="0,0,8,0"/>
        <Button x:Name="PjkCreate" Content="Create Kit" Style="{StaticResource PrimaryBtn}" IsEnabled="False"/>
      </StackPanel>
    </Border>
  </Grid>
</Window>
'@

$Script:KitBuilderXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Build from Catalog" Width="700" Height="620"
        WindowStartupLocation="CenterOwner"
        Background="{StaticResource PageBg}" FontFamily="Segoe UI">
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <Border Grid.Row="0" Background="#0B2C45" Padding="20,14">
      <StackPanel>
        <TextBlock Foreground="White" FontSize="18" FontWeight="Bold" Text="Build from Catalog"/>
        <TextBlock Foreground="#CBDBEA" FontSize="12"
                   Text="Expand a category and tick the specific questions you want. Use a category's checkbox to select or clear all of its questions."
                   TextWrapping="Wrap"/>
      </StackPanel>
    </Border>
    <Grid Grid.Row="1" Margin="20,12,20,4">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
      <TextBlock Grid.Column="0" Style="{StaticResource GridHeaderText}" Text="CATEGORY / QUESTION"/>
      <TextBlock Grid.Column="1" Style="{StaticResource GridHeaderText}" Text="SELECTED"/>
    </Grid>
    <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto">
      <StackPanel x:Name="KbList" Margin="20,0,20,16"/>
    </ScrollViewer>
    <Border Grid.Row="3" Background="White" BorderBrush="{StaticResource CardBorder}"
            BorderThickness="0,1,0,0" Padding="20,12">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <TextBlock x:Name="KbCount" Grid.Column="0" Style="{StaticResource Caption}"
                   VerticalAlignment="Center" Text="0 questions across 0 categories"/>
        <StackPanel Grid.Column="1" Orientation="Horizontal">
          <Button x:Name="KbCancel" Content="Cancel" Style="{StaticResource GhostBtn}" Margin="0,0,8,0"/>
          <Button x:Name="KbApply"  Content="Apply to kit" Style="{StaticResource PrimaryBtn}" IsEnabled="False"/>
        </StackPanel>
      </Grid>
    </Border>
  </Grid>
</Window>
'@
# Kit preview dialog ---------------------------------------------------------
$Script:KitPreviewXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Interview Kit Preview" Width="780" Height="700"
        WindowStartupLocation="CenterOwner"
        Background="{StaticResource PageBg}" FontFamily="Segoe UI">
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="78"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <Border x:Name="HeroBorder" Grid.Row="0" Background="{StaticResource BannerFallback}">
      <StackPanel Margin="24,16" VerticalAlignment="Center">
        <TextBlock x:Name="PvTitle" Foreground="White" FontSize="20" FontWeight="Bold" Text="Kit"/>
        <TextBlock x:Name="PvSub" Foreground="#CBDBEA" FontSize="12" Text=""/>
      </StackPanel>
    </Border>
    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="24,18">
      <StackPanel x:Name="PvBody"/>
    </ScrollViewer>
    <Border Grid.Row="2" Background="White" BorderBrush="{StaticResource CardBorder}"
            BorderThickness="0,1,0,0" Padding="20,12">
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Button x:Name="BtnClose" Content="Close" Style="{StaticResource GhostBtn}"/>
      </StackPanel>
    </Border>
  </Grid>
</Window>
'@

function Show-KitPreview {
    param([string]$KitId)
    $data = $Script:ShellData
    $kit  = Get-KitById $data $KitId
    if (-not $kit) { return }
    $job  = Get-JobById $data $kit.jobReqId
    $w = ConvertTo-Window -Xaml $Script:KitPreviewXaml
    Set-WindowBanner -Window $w
    $w.Owner = $Script:Shell
    ($w.FindName('PvTitle')).Text = if ($job) { "$($job.title) Kit" } else { $kit.name }
    ($w.FindName('PvSub')).Text   = ("{0} categories - {1}" -f @($kit.categories).Count, $kit.status)

    $body = $w.FindName('PvBody')
    $idx = 1
    foreach ($cat in $kit.categories) {
        $catalogCat = $data.Catalog.categories | Where-Object id -eq $cat.id | Select-Object -First 1
        foreach ($q in $cat.questions) {
            $card = New-Object System.Windows.Controls.Border
            $card.Style = $Script:Shell.FindResource('FlatCard')
            $card.Margin = '0,0,0,10'
            $st = New-Object System.Windows.Controls.StackPanel
            $h = New-Object System.Windows.Controls.TextBlock
            $h.Text = ("{0}. {1}" -f $idx, $cat.name)
            $h.FontWeight = 'SemiBold'; $h.FontSize = 13
            $h.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#1565C0')))
            [void]$st.Children.Add($h)
            $probeText = if ($q.PSObject.Properties['probe']) { [string]$q.probe } else { '' }
            $guideText = if ($q.PSObject.Properties['guide']) { [string]$q.guide } else { '' }
            $p = New-Object System.Windows.Controls.TextBlock
            $p.Text = $probeText
            $p.FontSize = 13; $p.TextWrapping = 'Wrap'
            $p.Margin = '0,6,0,0'
            $p.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#0B2C45')))
            [void]$st.Children.Add($p)
            $g = New-Object System.Windows.Controls.TextBlock
            $g.Text = "Scoring guide: $guideText"
            $g.FontSize = 11; $g.TextWrapping = 'Wrap'
            $g.Margin = '0,6,0,0'
            $g.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#6B7B8C')))
            [void]$st.Children.Add($g)
            $card.Child = $st
            [void]$body.Children.Add($card)
            $idx++
        }
    }
    $w.FindName('BtnClose').Add_Click({ $w.DialogResult = $true; $w.Close() })
    [void]$w.ShowDialog()
}

# ----------------------------------------------------------------------------
# Edit-kit dialog: rename the kit and change its status. Wired to BtnEditKit.
# ----------------------------------------------------------------------------
$Script:KitEditXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Edit Interview Kit" Width="520" Height="320"
        WindowStartupLocation="CenterOwner"
        Background="{StaticResource PageBg}" FontFamily="Segoe UI">
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <Border Grid.Row="0" Background="#0B2C45" Padding="20,14">
      <StackPanel>
        <TextBlock Foreground="White" FontSize="18" FontWeight="Bold" Text="Edit Kit"/>
        <TextBlock x:Name="EkSub" Foreground="#CBDBEA" FontSize="12" Text=""/>
      </StackPanel>
    </Border>
    <StackPanel Grid.Row="1" Margin="24,18,24,12">
      <TextBlock Style="{StaticResource MicroLabel}" Text="KIT NAME" Margin="0,0,0,4"/>
      <TextBox x:Name="EkName" Style="{StaticResource Field}" Margin="0,0,0,14"/>
      <TextBlock Style="{StaticResource MicroLabel}" Text="STATUS" Margin="0,0,0,4"/>
      <ComboBox x:Name="EkStatus" Style="{StaticResource ComboField}">
        <ComboBoxItem Content="Active"/>
        <ComboBoxItem Content="Draft"/>
        <ComboBoxItem Content="On Hold"/>
        <ComboBoxItem Content="Closed"/>
      </ComboBox>
    </StackPanel>
    <Border Grid.Row="2" Background="White" BorderBrush="{StaticResource CardBorder}"
            BorderThickness="0,1,0,0" Padding="20,12">
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Button x:Name="EkCancel" Content="Cancel" Style="{StaticResource GhostBtn}" Margin="0,0,8,0"/>
        <Button x:Name="EkSave"   Content="Save Changes" Style="{StaticResource PrimaryBtn}"/>
      </StackPanel>
    </Border>
  </Grid>
</Window>
'@

function Show-KitEditDialog {
    param([string]$KitId)
    $data = $Script:ShellData
    $kit  = Get-KitById $data $KitId
    if (-not $kit) { return }
    $job  = Get-JobById $data $kit.jobReqId

    $w = ConvertTo-Window -Xaml $Script:KitEditXaml
    $w.Owner = $Script:Shell

    ($w.FindName('EkSub')).Text  = if ($job) { "$($job.reqNumber) - $($job.title)" } else { 'Unlinked kit' }
    ($w.FindName('EkName')).Text = $kit.name
    $cbStatus = $w.FindName('EkStatus')
    foreach ($i in 0..($cbStatus.Items.Count-1)) {
        if ("$($cbStatus.Items[$i].Content)" -eq $kit.status) { $cbStatus.SelectedIndex = $i }
    }
    if ($cbStatus.SelectedIndex -lt 0) { $cbStatus.SelectedIndex = 1 }   # Draft fallback

    $w.FindName('EkCancel').Add_Click({ $w.DialogResult = $false; $w.Close() })
    $w.FindName('EkSave').Add_Click({
        param($sender, $eventArgs)
        # No GetNewClosure - $Script:ShellData must resolve dynamically.
        $k = Get-KitById $Script:ShellData $KitId
        if ($k) {
            $newName = ($w.FindName('EkName')).Text
            if ($newName) { $k.name = $newName }
            $sel = ($w.FindName('EkStatus')).SelectedItem
            if ($sel) { $k.status = "$($sel.Content)" }
            Save-Kits $Script:ShellData
            Set-ShellStatus ("Saved kit '{0}'." -f $k.name)
        }
        $w.DialogResult = $true; $w.Close()
        Show-View 'TabKits'
    })
    [void]$w.ShowDialog()
}

$Script:PickCatalogProbeXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Pick from Catalog" Width="640" Height="600"
        WindowStartupLocation="CenterOwner"
        Background="{StaticResource PageBg}" FontFamily="Segoe UI">
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <Border Grid.Row="0" Background="#0B2C45" Padding="20,14">
      <StackPanel>
        <TextBlock x:Name="PcpHeader" Foreground="White" FontSize="18" FontWeight="Bold" Text="Pick from Catalog"/>
        <TextBlock x:Name="PcpSub"    Foreground="#CBDBEA" FontSize="12" Text=""/>
      </StackPanel>
    </Border>
    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
      <StackPanel x:Name="PcpList" Margin="20,16"/>
    </ScrollViewer>
    <Border Grid.Row="2" Background="White" BorderBrush="{StaticResource CardBorder}"
            BorderThickness="0,1,0,0" Padding="20,12">
      <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
        <Button x:Name="PcpCancel" Content="Cancel" Style="{StaticResource GhostBtn}"/>
      </StackPanel>
    </Border>
  </Grid>
</Window>
'@
