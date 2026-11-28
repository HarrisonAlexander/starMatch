<#
QuestionLibrary.ps1 - read-only browse of the seeded behavioral catalog
(data\categories.json). Available immediately on app launch, with no Job
Requisition or Interview Kit required. Left rail = every category in the
catalog (with a count chip); right pane = that category's probe +
interviewer guide pairs. Search filters across category name, probe text,
and guide text.

This view never mutates the catalog. The catalog file is loaded read-only
from the source tree by lib\Data.ps1 (Initialize-UserData deliberately
excludes it from the APPDATA seed). Per-kit custom additions still flow
through Interview Kits -> + Add Question, which writes to
%APPDATA%\TrueHire\kits.json.

PS quirks observed in this view (see CLAUDE.md for the catalog):
- Event handlers use param($sender,$e) WITHOUT .GetNewClosure() so $Script:
  reads/writes resolve dynamically at fire time and function names in the
  same file are visible. Same idiom as the Candidates search box.
- Search box / category-button handlers reach the live root via
  $Script:Shell.FindName('ContentHost').Children[0] rather than capturing
  it in a closure, again to dodge the GetNewClosure scope-shadow trap.
- Variable naming: never use $cat as a local TextBlock or Button - the
  outer foreach var $cat (the catalog category) would be clobbered
  (PowerShell is case-insensitive). Locals are named $catRow / $catBtn etc.
#>

$Script:QuestionLibraryXaml = @'
<Grid xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
      xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
  <Grid.ColumnDefinitions>
    <ColumnDefinition Width="300"/>
    <ColumnDefinition Width="*"/>
  </Grid.ColumnDefinitions>

  <!-- ===========  Left rail: category list  =========== -->
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
      <TextBlock Grid.Row="0" Style="{StaticResource H3}" Text="Question Library" Margin="0,0,0,4"/>
      <TextBlock Grid.Row="1" Style="{StaticResource Caption}" TextWrapping="Wrap"
                 Margin="0,0,0,12"
                 Text="Read-only base set. Custom additions live per kit."/>
      <TextBox  x:Name="LibSearch" Grid.Row="2" Style="{StaticResource SearchField}" Margin="0,0,0,12"
                ToolTip="Filter by category, probe text, or interviewer guide"/>
      <ScrollViewer Grid.Row="3" VerticalScrollBarVisibility="Auto">
        <StackPanel x:Name="LibCatList"/>
      </ScrollViewer>
      <TextBlock x:Name="LibFooter" Grid.Row="4" Style="{StaticResource Caption}"
                 Margin="0,12,0,0" TextWrapping="Wrap" Text=""/>
    </Grid>
  </Border>

  <!-- ===========  Right pane: questions  =========== -->
  <Grid Grid.Column="1" Margin="28,24,28,24">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
    </Grid.RowDefinitions>
    <TextBlock x:Name="LibPaneTitle" Grid.Row="0" Style="{StaticResource H2}" Text=""/>
    <TextBlock x:Name="LibPaneDesc"  Grid.Row="1" Style="{StaticResource Body}"
               Margin="0,4,0,0" TextWrapping="Wrap" Text="" Foreground="{StaticResource TextMuted}"/>
    <TextBlock x:Name="LibPaneCount" Grid.Row="2" Style="{StaticResource Caption}"
               Margin="0,10,0,12" Text=""/>
    <ScrollViewer Grid.Row="3" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
      <StackPanel x:Name="LibQList"/>
    </ScrollViewer>
  </Grid>
</Grid>
'@

# Per-view state. Survives re-renders of the Library tab because all the
# Show-* / _Refilter-* functions in THIS file share one script scope. (Other
# .ps1 files cannot see these; that's fine - only this view reads them.)
$Script:LibrarySelectedCategoryId = $null   # $null = "All Categories"
$Script:LibrarySearchText         = ''

function _Library-MakeBrush {
    param([string]$Hex)
    New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($Hex))
}

function _Library-MatchesSearch {
    <#
    Case-insensitive substring match against category name + probe + guide.
    Empty/whitespace search returns $true (match all).
    #>
    param($CatalogCategory, $Question, [string]$Needle)
    if (-not $Needle -or [string]::IsNullOrWhiteSpace($Needle)) { return $true }
    $n = $Needle.Trim().ToLowerInvariant()
    $hay = @(
        $CatalogCategory.name
        $CatalogCategory.displayName
        $CatalogCategory.description
        $Question.probe
        $Question.guide
    ) -join "`n"
    return ($hay.ToLowerInvariant().IndexOf($n) -ge 0)
}

function _Library-FilteredCount {
    <#
    Number of questions in one catalog category that match the current
    search. Used for the count chip in the rail.
    #>
    param($CatalogCategory, [string]$Needle)
    $hits = 0
    foreach ($q in @($CatalogCategory.questions)) {
        if (_Library-MatchesSearch $CatalogCategory $q $Needle) { $hits++ }
    }
    return $hits
}

function _Library-BuildCategoryRow {
    <#
    One clickable row in the left rail. Real WPF Button so keyboard nav
    (Tab/Enter) works. Selected state is painted via Background; we don't
    rely on a Style trigger because Show-* rebuilds on every tab switch.
    #>
    param($CatalogCategory, [int]$MatchCount, [bool]$IsSelected, [bool]$IsAll)

    $btn = New-Object System.Windows.Controls.Button
    $btn.BorderThickness  = New-Object System.Windows.Thickness 0
    $btn.Padding          = '10,8'
    $btn.Margin           = '0,0,0,2'
    $btn.Cursor           = 'Hand'
    $btn.HorizontalContentAlignment = 'Stretch'
    $btn.Background = if ($IsSelected) {
        _Library-MakeBrush '#E1EEF9'   # SidebarSelected
    } else {
        [System.Windows.Media.Brushes]::Transparent
    }
    # Tag carries the routing key. $null = "All".
    if ($IsAll) { $btn.Tag = '__ALL__' } else { $btn.Tag = $CatalogCategory.id }

    $g = New-Object System.Windows.Controls.Grid
    $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = '*'
    $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = 'Auto'
    [void]$g.ColumnDefinitions.Add($c1); [void]$g.ColumnDefinitions.Add($c2)

    $name = New-Object System.Windows.Controls.TextBlock
    if ($IsAll) {
        $name.Text = 'All Categories'
        $name.FontWeight = 'SemiBold'
    } else {
        $name.Text = $CatalogCategory.displayName
    }
    $name.FontSize = 13
    $name.Foreground = _Library-MakeBrush '#0B2C45'
    $name.VerticalAlignment = 'Center'
    $name.TextTrimming = 'CharacterEllipsis'
    [System.Windows.Controls.Grid]::SetColumn($name, 0)
    [void]$g.Children.Add($name)

    # Count chip on the right. Dim when zero so the rail visually narrows
    # under heavy search.
    $chip = New-Object System.Windows.Controls.Border
    if ($MatchCount -gt 0) {
        $chip.Background = _Library-MakeBrush '#EEF3FA'
    } else {
        $chip.Background = _Library-MakeBrush '#F4F6FA'
    }
    $chip.CornerRadius = New-Object System.Windows.CornerRadius 9
    $chip.Padding = '8,1'
    $chip.VerticalAlignment = 'Center'
    $countTb = New-Object System.Windows.Controls.TextBlock
    $countTb.Text = "$MatchCount"
    $countTb.FontSize = 11
    $countTb.FontWeight = 'SemiBold'
    if ($MatchCount -gt 0) {
        $countTb.Foreground = _Library-MakeBrush '#1565C0'
    } else {
        $countTb.Foreground = _Library-MakeBrush '#94A3B8'
    }
    $chip.Child = $countTb
    [System.Windows.Controls.Grid]::SetColumn($chip, 1)
    [void]$g.Children.Add($chip)

    $btn.Content = $g

    # Flatten the default button chrome (no rounded blue focus halo, no
    # 3D background). Re-implement minimal hover/pressed via the template
    # so transparent rows still feel clickable.
    $tpl = [System.Windows.Markup.XamlReader]::Parse(@'
<ControlTemplate xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                 xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
                 TargetType="Button">
  <Border x:Name="B" Background="{TemplateBinding Background}"
          CornerRadius="6" Padding="{TemplateBinding Padding}">
    <ContentPresenter HorizontalAlignment="Stretch" VerticalAlignment="Center"/>
  </Border>
  <ControlTemplate.Triggers>
    <Trigger Property="IsMouseOver" Value="True">
      <Setter TargetName="B" Property="Background" Value="#EEF3FA"/>
    </Trigger>
  </ControlTemplate.Triggers>
</ControlTemplate>
'@)
    $btn.Template = $tpl

    # Pattern (b) handler: no .GetNewClosure, $Script: reads/writes resolve
    # dynamically, in-file function names are visible.
    $btn.Add_Click({
        param($sender, $eventArgs)
        $tag = $sender.Tag
        if ($tag -eq '__ALL__') {
            $Script:LibrarySelectedCategoryId = $null
        } else {
            $Script:LibrarySelectedCategoryId = $tag
        }
        $content = $Script:Shell.FindName('ContentHost')
        if ($content -and $content.Children.Count -gt 0) {
            _Library-Refresh -Root $content.Children[0]
        }
    })

    return $btn
}

function _Library-BuildQuestionCard {
    <#
    One card on the right pane: small index/score pill + probe text + the
    interviewer-guide paragraph beneath. The category label appears too so
    "All Categories" view is readable without scrolling back to the rail.
    #>
    param($CatalogCategory, $Question, [bool]$ShowCategoryLabel)

    $card = New-Object System.Windows.Controls.Border
    $card.Background      = [System.Windows.Media.Brushes]::White
    $card.BorderBrush     = _Library-MakeBrush '#E4E8EF'    # CardBorder
    $card.BorderThickness = New-Object System.Windows.Thickness 1
    $card.CornerRadius    = New-Object System.Windows.CornerRadius 10
    $card.Padding         = '16,14'
    $card.Margin          = '0,0,0,10'

    $stack = New-Object System.Windows.Controls.StackPanel
    $card.Child = $stack

    # ----- header row: index pill, optional category chip ----------------
    $headerRow = New-Object System.Windows.Controls.StackPanel
    $headerRow.Orientation = 'Horizontal'
    $headerRow.Margin = '0,0,0,8'

    $pill = New-Object System.Windows.Controls.Border
    $pill.Background    = _Library-MakeBrush '#0B2C45'
    $pill.CornerRadius  = New-Object System.Windows.CornerRadius 4
    $pill.Padding       = '7,2'
    $pill.VerticalAlignment = 'Center'
    $pillText = New-Object System.Windows.Controls.TextBlock
    $pillText.Text       = "Q$($Question.index)"
    $pillText.Foreground = [System.Windows.Media.Brushes]::White
    $pillText.FontSize   = 11
    $pillText.FontWeight = 'Bold'
    $pill.Child = $pillText
    [void]$headerRow.Children.Add($pill)

    if ($ShowCategoryLabel) {
        $catChip = New-Object System.Windows.Controls.Border
        $catChip.Background   = _Library-MakeBrush '#E1EEF9'
        $catChip.CornerRadius = New-Object System.Windows.CornerRadius 4
        $catChip.Padding      = '7,2'
        $catChip.Margin       = '8,0,0,0'
        $catChip.VerticalAlignment = 'Center'
        $catChipText = New-Object System.Windows.Controls.TextBlock
        $catChipText.Text       = $CatalogCategory.displayName
        $catChipText.Foreground = _Library-MakeBrush '#1565C0'
        $catChipText.FontSize   = 11
        $catChipText.FontWeight = 'SemiBold'
        $catChip.Child = $catChipText
        [void]$headerRow.Children.Add($catChip)
    }
    [void]$stack.Children.Add($headerRow)

    # ----- probe text ----------------------------------------------------
    $probe = New-Object System.Windows.Controls.TextBlock
    $probe.Text         = "$($Question.probe)"
    $probe.FontSize     = 14
    $probe.FontWeight   = 'SemiBold'
    $probe.Foreground   = _Library-MakeBrush '#0B2C45'
    $probe.TextWrapping = 'Wrap'
    [void]$stack.Children.Add($probe)

    # ----- guide label + guide text -------------------------------------
    if ($Question.guide -and -not [string]::IsNullOrWhiteSpace($Question.guide)) {
        $guideLbl = New-Object System.Windows.Controls.TextBlock
        $guideLbl.Text       = 'INTERVIEWER GUIDE'
        $guideLbl.FontSize   = 10
        $guideLbl.FontWeight = 'Bold'
        $guideLbl.Foreground = _Library-MakeBrush '#94A3B8'
        $guideLbl.Margin     = '0,10,0,2'
        [void]$stack.Children.Add($guideLbl)

        $guide = New-Object System.Windows.Controls.TextBlock
        $guide.Text         = "$($Question.guide)"
        $guide.FontSize     = 12.5
        $guide.FontStyle    = 'Italic'
        $guide.Foreground   = _Library-MakeBrush '#2C3E50'
        $guide.TextWrapping = 'Wrap'
        [void]$stack.Children.Add($guide)
    }

    return $card
}

function _Library-Refresh {
    <#
    Re-renders the rail counts AND the right pane against current state
    ($Script:LibrarySelectedCategoryId + $Script:LibrarySearchText).
    Called on first paint, on search-box keystroke, and on category click.
    Cheap enough to fully rebuild every time - the catalog is ~170 items.
    #>
    param($Root)
    if (-not $Root) { return }

    $data = $Script:ShellData
    if (-not $data -or -not $data.Catalog -or -not $data.Catalog.categories) { return }
    $catalog = $data.Catalog
    $needle  = "$($Script:LibrarySearchText)"

    $catList     = $Root.FindName('LibCatList')
    $title       = $Root.FindName('LibPaneTitle')
    $desc        = $Root.FindName('LibPaneDesc')
    $countLbl    = $Root.FindName('LibPaneCount')
    $qList       = $Root.FindName('LibQList')
    $footer      = $Root.FindName('LibFooter')

    # ----- rebuild the left rail ---------------------------------------
    $catList.Children.Clear()

    # All-categories row at the top
    $totalMatches = 0
    $perCat = @{}
    foreach ($cc in @($catalog.categories)) {
        $hits = _Library-FilteredCount $cc $needle
        $perCat[$cc.id] = $hits
        $totalMatches  += $hits
    }
    $allSelected = (-not $Script:LibrarySelectedCategoryId)
    [void]$catList.Children.Add( (_Library-BuildCategoryRow -CatalogCategory $null -MatchCount $totalMatches -IsSelected:$allSelected -IsAll:$true) )

    # Thin divider so 'All' visually separates from the per-category list
    $divider = New-Object System.Windows.Controls.Border
    $divider.Height = 1
    $divider.Background = _Library-MakeBrush '#EDF0F4'
    $divider.Margin = '0,6,0,6'
    [void]$catList.Children.Add($divider)

    foreach ($cc in @($catalog.categories | Sort-Object { [string]$_.displayName })) {
        $isSel = ($Script:LibrarySelectedCategoryId -eq $cc.id)
        $hits  = $perCat[$cc.id]
        [void]$catList.Children.Add( (_Library-BuildCategoryRow -CatalogCategory $cc -MatchCount $hits -IsSelected:$isSel -IsAll:$false) )
    }

    # ----- footer caption ---------------------------------------------
    $totalQ = 0
    foreach ($cc in @($catalog.categories)) { $totalQ += @($cc.questions).Count }
    $totalCats = @($catalog.categories).Count
    $footer.Text = ("{0} probes across {1} categories." -f $totalQ, $totalCats) + `
                   "`nCatalog file is read-only. Add custom probes per kit via Interview Kits."

    # ----- right pane --------------------------------------------------
    $qList.Children.Clear()
    $selId = $Script:LibrarySelectedCategoryId
    $showCatLabel = $false

    if ($selId) {
        $sel = $catalog.categories | Where-Object id -eq $selId | Select-Object -First 1
        if (-not $sel) {
            # Stale id (catalog reloaded with a renamed category, etc) - fall back to All
            $Script:LibrarySelectedCategoryId = $null
            $selId = $null
        } else {
            $title.Text = $sel.displayName
            $desc.Text  = if ($sel.description) { $sel.description } else { '' }
            $matches = @()
            foreach ($q in @($sel.questions)) {
                if (_Library-MatchesSearch $sel $q $needle) { $matches += @{ Cat=$sel; Q=$q } }
            }
            if (@($sel.questions).Count -eq 0) {
                $countLbl.Text = 'Custom category - no seeded probes. Add questions per kit from Interview Kits -> + Add Question.'
            } elseif ($needle -and [string]::IsNullOrWhiteSpace($needle) -eq $false) {
                $countLbl.Text = ("{0} of {1} probes match '{2}'." -f $matches.Count, @($sel.questions).Count, $needle.Trim())
            } else {
                $countLbl.Text = ("{0} probes" -f @($sel.questions).Count)
            }
            foreach ($m in $matches) {
                [void]$qList.Children.Add( (_Library-BuildQuestionCard -CatalogCategory $m.Cat -Question $m.Q -ShowCategoryLabel:$false) )
            }
        }
    }

    if (-not $selId) {
        $title.Text = 'All Categories'
        $desc.Text  = 'Behavioral interview questions that work for any role, from entry level to leadership.'
        $showCatLabel = $true

        $matches = @()
        foreach ($cc in @($catalog.categories)) {
            foreach ($q in @($cc.questions)) {
                if (_Library-MatchesSearch $cc $q $needle) {
                    $matches += @{ Cat=$cc; Q=$q }
                }
            }
        }
        if ($needle -and -not [string]::IsNullOrWhiteSpace($needle)) {
            $countLbl.Text = ("{0} of {1} probes match '{2}'." -f $matches.Count, $totalQ, $needle.Trim())
        } else {
            $countLbl.Text = ("{0} probes across {1} categories" -f $totalQ, $totalCats)
        }
        foreach ($m in $matches) {
            [void]$qList.Children.Add( (_Library-BuildQuestionCard -CatalogCategory $m.Cat -Question $m.Q -ShowCategoryLabel:$true) )
        }

        if (@($matches).Count -eq 0 -and $needle -and -not [string]::IsNullOrWhiteSpace($needle)) {
            $none = New-Object System.Windows.Controls.TextBlock
            $none.Text       = "No probes match '$($needle.Trim())'."
            $none.Foreground = _Library-MakeBrush '#6B7B8C'
            $none.FontSize   = 13
            $none.Margin     = '0,6,0,0'
            [void]$qList.Children.Add($none)
        }
    }
}

function Show-QuestionLibraryView {
    <#
    Entry point routed from Show-View in views\Shell.ps1. Always renders
    even when there are zero jobs / kits / candidates - that's the whole
    point of this view existing.
    #>
    param($Container)
    $root = [System.Windows.Markup.XamlReader]::Parse($Script:QuestionLibraryXaml)
    [void]$Container.Children.Add($root)

    $data = $Script:ShellData
    if (-not $data -or -not $data.Catalog -or -not $data.Catalog.categories) {
        # Honest empty-state. The catalog SHOULD always load (it ships with
        # the app), but if data\categories.json was deleted/corrupted, say
        # so instead of rendering a blank screen.
        ($root.FindName('LibPaneTitle')).Text = 'Catalog unavailable'
        ($root.FindName('LibPaneDesc')).Text  = 'data\categories.json failed to load. Confirm the file exists in the source tree and is valid JSON.'
        ($root.FindName('LibPaneCount')).Text = ''
        ($root.FindName('LibFooter')).Text    = ''
        return
    }

    # Restore typed search text into the fresh TextBox (re-render replaces
    # the control). Same idea as the Candidates search box.
    $searchBox = $root.FindName('LibSearch')
    $searchBox.Text = "$($Script:LibrarySearchText)"
    # Pattern (b): no GetNewClosure. $Script: writes and in-file function
    # calls work dynamically at fire time. Closure-style handlers would
    # silently stop seeing updated $Script: values across keystrokes.
    $searchBox.Add_TextChanged({
        param($sender, $eventArgs)
        $Script:LibrarySearchText = $sender.Text
        $content = $Script:Shell.FindName('ContentHost')
        if ($content -and $content.Children.Count -gt 0) {
            _Library-Refresh -Root $content.Children[0]
        }
    })

    _Library-Refresh -Root $root
}
