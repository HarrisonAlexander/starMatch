<#
Shell.ps1 — top-level window. The banner runs across the full width;
underneath sits the tab strip (Dashboard / Job Reqs / Interview Kits /
Question Library / Candidates / Analytics) and a content host that each view
paints into. Show-TrueHireShell is the only public entry point.
#>

$Script:ShellXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="TrueHire - Behavioral Interview Analytics"
        Width="1280" Height="820"
        ResizeMode="CanMinimize"
        Background="{StaticResource PageBg}"
        WindowStartupLocation="CenterScreen"
        FontFamily="Segoe UI">
  <Grid>
    <Grid.RowDefinitions>
      <RowDefinition Height="216"/>     <!-- Banner: near aspect match.
                                              banner.png is 2172x393
                                              (aspect 5.527). At banner
                                              1280x216 the box aspect is 5.926,
                                              so UniformToFill crops ~8px off
                                              top and bottom - the logo and
                                              figures stay well inside the
                                              frame; no stretch, no letterbox. -->
      <RowDefinition Height="Auto"/>    <!-- Tabs -->
      <RowDefinition Height="*"/>       <!-- Content -->
      <RowDefinition Height="Auto"/>    <!-- Status bar -->
    </Grid.RowDefinitions>

    <!-- ============  Banner  ============ -->
    <!-- Image element fills the banner edge-to-edge. Title text is baked
         into cover.png, so no overlay is needed here. -->
    <Border x:Name="BannerHost" Grid.Row="0" Background="#0B2C45">
      <Grid Margin="0">
        <Image x:Name="BannerImage" Stretch="UniformToFill"
               HorizontalAlignment="Stretch" VerticalAlignment="Stretch"
               RenderOptions.BitmapScalingMode="HighQuality"/>
      </Grid>
    </Border>

    <!-- ============  Tabs  ============ -->
    <Border Grid.Row="1" Background="#0B2C45">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <StackPanel Grid.Column="0" Orientation="Horizontal" Margin="36,0,0,0">
          <Button x:Name="TabDashboard"     Content="Dashboard"        Style="{StaticResource NavTabBtnActive}"/>
          <Button x:Name="TabJobReqs"       Content="Job Requisitions" Style="{StaticResource NavTabBtn}"/>
          <Button x:Name="TabKits"          Content="Interview Kits"   Style="{StaticResource NavTabBtn}"/>
          <Button x:Name="TabLibrary"       Content="Question Library" Style="{StaticResource NavTabBtn}"/>
          <Button x:Name="TabCandidates"    Content="Candidates"       Style="{StaticResource NavTabBtn}"/>
          <Button x:Name="TabAnalytics"     Content="Analytics"        Style="{StaticResource NavTabBtn}"/>
        </StackPanel>
        <!-- User chip — lives in the tab strip, right-aligned and vertically
             centered with the tab buttons. No pill background needed; the
             navy strip itself is the container. -->
        <StackPanel Grid.Column="2" Orientation="Horizontal"
                    VerticalAlignment="Center" Margin="0,0,28,0">
          <Border Width="28" Height="28" CornerRadius="14"
                  Background="#F5A623" Margin="0,0,8,0">
            <TextBlock x:Name="UserInitials" Text="?" Foreground="White"
                       FontWeight="Bold" FontSize="11"
                       HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <StackPanel VerticalAlignment="Center">
            <TextBlock x:Name="UserName" Text="Hello"
                       Foreground="White" FontSize="12" FontWeight="SemiBold"/>
            <TextBlock x:Name="UserRole" Text=""
                       Foreground="#CBDBEA" FontSize="10.5"/>
          </StackPanel>
        </StackPanel>
      </Grid>
    </Border>

    <!-- ============  Content host  ============ -->
    <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto"
                  HorizontalScrollBarVisibility="Disabled" Padding="0">
      <Grid x:Name="ContentHost" Margin="0"/>
    </ScrollViewer>

    <!-- ============  Status bar  ============ -->
    <Border Grid.Row="3" Background="#0B2C45" Height="24">
      <Grid Margin="14,0">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <TextBlock x:Name="StatusText" Grid.Column="0" Foreground="#CBDBEA"
                   FontSize="11" VerticalAlignment="Center" Text="Ready."/>
        <!-- Opens today's log in Notepad. See Open-TrueHireLog in lib\Logging.ps1. -->
        <Button x:Name="StatusLogLink" Grid.Column="1" Content="View log"
                Background="Transparent" BorderThickness="0" Padding="6,0"
                Foreground="#7E97AE" Cursor="Hand" FontSize="11"
                VerticalAlignment="Center"/>
        <TextBlock x:Name="StatusBuild" Grid.Column="2" Foreground="#7E97AE"
                   FontSize="11" VerticalAlignment="Center" Margin="14,0,0,0"
                   Text="TrueHire - PowerShell + WPF"/>
      </Grid>
    </Border>
  </Grid>
</Window>
'@

# Module-scoped shell state. Views write back here to switch tabs / update
# the status bar; we keep it on $Script so nested handlers can reach it.
$Script:Shell = $null
$Script:ShellTabs = @{}
$Script:ShellData = $null
$Script:CurrentView = $null

function Set-ShellStatus {
    <#
    Update the bottom status bar text. -Level controls the foreground color
    so errors are visible without being intrusive:
      INFO  (default) = light blue, the normal navy-bar tone
      WARN            = amber
      ERROR           = salmon, visible against the navy background
    Errors should also be logged via Write-TrueHireLog; the dispatcher
    catch-all does both automatically.
    #>
    param(
        [string]$Text,
        [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO'
    )
    if (-not $Script:Shell) { return }
    $t = $Script:Shell.FindName('StatusText')
    if (-not $t) { return }
    $t.Text = $Text
    $color = switch ($Level) {
        'ERROR' { '#FFA8A8' }   # salmon
        'WARN'  { '#FFD27A' }   # amber
        default { '#CBDBEA' }   # default light blue
    }
    $t.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($color)))
}

function Set-ActiveTab {
    param([string]$TabName)
    foreach ($name in $Script:ShellTabs.Keys) {
        $btn = $Script:ShellTabs[$name]
        $btn.Style = if ($name -eq $TabName) {
            $Script:Shell.FindResource('NavTabBtnActive')
        } else {
            $Script:Shell.FindResource('NavTabBtn')
        }
    }
}

function Show-View {
    <#
    Routes Tab* clicks to the matching Show-*View function and toggles the
    active-tab styling. Each view function rebuilds the content host from
    scratch — cheap, and dodges stale-state bugs.
    #>
    param([string]$TabName)
    # If we're leaving the Kits tab, drop any in-flight + Add Question so
    # it doesn't ghost back into view on return.
    if ($TabName -ne 'TabKits' -and (Get-Command Clear-PendingKitQuestion -ErrorAction SilentlyContinue)) {
        Clear-PendingKitQuestion
    }
    $Script:CurrentView = $TabName
    Set-ActiveTab $TabName

    # Force a disk-reload of the working copy before any tab paints. The
    # canonical state is %APPDATA%\TrueHire\*.json on disk - every UI
    # mutation goes through Save-*; nothing depends on un-persisted
    # in-memory edits surviving a tab switch (dialogs are modal and save
    # before they close). This catches the failure mode where a Save in
    # one tab's handler succeeded to disk but an in-memory reference
    # somewhere never observed the mutation (cross-file $Script: scope
    # quirks, closure-captured stale references, etc) so the next view
    # would otherwise paint stale KPIs.
    #
    # Mutates the EXISTING $Script:ShellData hashtable's keys in place
    # rather than reassigning the variable; that way any code path
    # holding a reference to the same hashtable picks up the refresh.
    try {
        $fresh = Load-TrueHireData
        if ($fresh -and $Script:ShellData) {
            foreach ($k in @($fresh.Keys)) { $Script:ShellData[$k] = $fresh[$k] }
        } elseif ($fresh) {
            $Script:ShellData = $fresh
        }
    } catch {
        if (Get-Command Write-TrueHireLog -ErrorAction SilentlyContinue) {
            Write-TrueHireLog -Level WARN -Source 'Show-View' -Message ('Refresh failed; painting with stale state: ' + $_.Exception.Message) -Exception $_.Exception
        }
    }

    # $host is a read-only automatic in PowerShell; use $content for the host.
    $content = $Script:Shell.FindName('ContentHost')
    $content.Children.Clear()
    switch ($TabName) {
        'TabDashboard'  { Show-DashboardView       $content }
        'TabJobReqs'    { Show-JobRequisitionsView $content }
        'TabKits'       { Show-InterviewKitsView   $content }
        'TabLibrary'    { Show-QuestionLibraryView $content }
        'TabCandidates' { Show-CandidatesView      $content }
        'TabAnalytics'  { Show-AnalyticsView       $content }
    }
}

function Show-TrueHireShell {
    param($Data)
    $Script:ShellData = $Data
    $w = ConvertTo-Window -Xaml $Script:ShellXaml
    Set-WindowBanner -Window $w
    $Script:Shell = $w

    # User chip: try Active Directory first via ADSI so the banner reflects
    # whoever is actually logged in. AD wins; on AD success we also mirror
    # name/role/email back into Settings.currentUser so downstream consumers
    # (export "exportedBy" stamp in lib/Export.ps1, the Analytics report
    # author in lib/ReportExcel.ps1, and the rater pre-fill in
    # views/Candidates.ps1) all see the live identity without each needing
    # its own AD probe. If AD is unreachable we fall back to whatever sits
    # in Settings.currentUser, and finally to a generic "Hello" with no
    # name when neither source has a value.
    $adUser = Get-CurrentUserFromAd
    $userName = ''
    $userRole = ''

    if ($adUser) {
        $userName = $adUser.Name
        if ($adUser.Role) { $userRole = $adUser.Role }
        if ($Data.Settings -and $Data.Settings.currentUser) {
            $cu = $Data.Settings.currentUser
            if ($adUser.Name  -and $cu.PSObject.Properties['name'])  { $cu.name  = $adUser.Name }
            if ($adUser.Role  -and $cu.PSObject.Properties['role'])  { $cu.role  = $adUser.Role }
            if ($adUser.Email -and $cu.PSObject.Properties['email']) { $cu.email = $adUser.Email }
        }
    }
    if ((-not $userName) -and $Data.Settings -and $Data.Settings.currentUser -and $Data.Settings.currentUser.name) {
        $userName = [string]$Data.Settings.currentUser.name
    }
    if ((-not $userRole) -and $Data.Settings -and $Data.Settings.currentUser -and $Data.Settings.currentUser.role) {
        $userRole = [string]$Data.Settings.currentUser.role
    }

    if ($userName) {
        ($w.FindName('UserName')).Text     = $userName
        ($w.FindName('UserInitials')).Text = (Get-Initials $userName)
    } else {
        ($w.FindName('UserName')).Text     = 'Hello'
        ($w.FindName('UserInitials')).Text = '?'
    }
    ($w.FindName('UserRole')).Text = $userRole

    # Wire tabs --------------------------------------------------------------
    # PS quirk: scriptblocks fired from WPF event handlers don't reliably
    # resolve *function names* from script scope - the error is
    # "The term 'Show-View' is not recognized". Variables (including
    # scriptblock references) ARE captured by .GetNewClosure(), so we grab
    # a reference to the function once and invoke it via & in the handler.
    $showViewRef = ${function:Show-View}
    foreach ($tabName in 'TabDashboard','TabJobReqs','TabKits','TabLibrary','TabCandidates','TabAnalytics') {
        $btn = $w.FindName($tabName)
        $Script:ShellTabs[$tabName] = $btn
        $nameLocal = $tabName
        $btn.Add_Click({ & $showViewRef $nameLocal }.GetNewClosure())
    }

    # "View log" link in the status bar - opens today's log in Notepad
    $logBtn = $w.FindName('StatusLogLink')
    if ($logBtn) {
        $logBtn.Add_Click({
            if (Get-Command Open-TrueHireLog -ErrorAction SilentlyContinue) {
                Open-TrueHireLog
            }
        })
    }

    # First view
    Show-View 'TabDashboard'
    Set-ShellStatus ("Loaded {0} job requisitions and {1} candidates." -f $Data.Jobs.Count, $Data.Candidates.Count)

    [void]$w.ShowDialog()
}
