<#
Theme.ps1 — shared XAML resources (colors, brushes, control styles) plus
ConvertTo-Window / window-branding helpers. Imported by TrueHire.ps1 once at
startup; every view's XAML resolves StaticResource references against this.

Palette mirrors the v3 mockups (ui_1_c..ui_6): dark-navy banner header,
light page background, white cards, blue/orange accents, status pills.
#>

# Global UI magnification. Every window built through ConvertTo-Window is scaled
# by this factor (content LayoutTransform + window box, clamped to the work area),
# so the whole app renders proportionally larger without touching view XAML.
# 1.0 = no scaling. Defined here because ConvertTo-Window (same file) reads it and
# $Script: state does not cross files in this codebase.
$Script:UiScale = 1.2

$Script:WinResources = @'
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">

  <!-- Core palette -->
  <SolidColorBrush x:Key="PageBg"          Color="#F4F6FA"/>
  <SolidColorBrush x:Key="CardBg"          Color="#FFFFFF"/>
  <SolidColorBrush x:Key="CardBorder"      Color="#E4E8EF"/>
  <SolidColorBrush x:Key="DividerBrush"    Color="#EDF0F4"/>
  <SolidColorBrush x:Key="TextPrimary"     Color="#0B2C45"/>
  <SolidColorBrush x:Key="TextBody"        Color="#2C3E50"/>
  <SolidColorBrush x:Key="TextMuted"       Color="#6B7B8C"/>
  <SolidColorBrush x:Key="TextSubtle"      Color="#94A3B8"/>
  <SolidColorBrush x:Key="AccentBlue"      Color="#1E88E5"/>
  <SolidColorBrush x:Key="AccentBlueDark"  Color="#1565C0"/>
  <SolidColorBrush x:Key="AccentOrange"    Color="#F5A623"/>
  <SolidColorBrush x:Key="AccentOrangeDk"  Color="#E89923"/>
  <SolidColorBrush x:Key="StarYellow"      Color="#FFC847"/>
  <SolidColorBrush x:Key="GreenOk"         Color="#38B66E"/>
  <SolidColorBrush x:Key="OrangeWarn"      Color="#F08C2A"/>
  <SolidColorBrush x:Key="RedAlert"        Color="#DC4C4C"/>
  <SolidColorBrush x:Key="PurpleSoft"      Color="#7E57C2"/>
  <SolidColorBrush x:Key="SidebarBg"       Color="#FFFFFF"/>
  <SolidColorBrush x:Key="SidebarHover"    Color="#EEF3FA"/>
  <SolidColorBrush x:Key="SidebarSelected" Color="#E1EEF9"/>

  <!-- Banner gradient (used when the actual starry banner image fails to load) -->
  <LinearGradientBrush x:Key="BannerFallback" StartPoint="0,0" EndPoint="1,0">
    <GradientStop Color="#06223C" Offset="0"/>
    <GradientStop Color="#0B2C45" Offset="0.5"/>
    <GradientStop Color="#143A60" Offset="1"/>
  </LinearGradientBrush>

  <LinearGradientBrush x:Key="BannerOverlay" StartPoint="0,0" EndPoint="1,0">
    <GradientStop Color="#CC06223C" Offset="0"/>
    <GradientStop Color="#7A0B2C45" Offset="0.55"/>
    <GradientStop Color="#26143A60" Offset="1"/>
  </LinearGradientBrush>

  <LinearGradientBrush x:Key="OrangeGradient" StartPoint="0,0" EndPoint="1,1">
    <GradientStop Color="#F5A623" Offset="0"/>
    <GradientStop Color="#E07A14" Offset="1"/>
  </LinearGradientBrush>

  <LinearGradientBrush x:Key="BlueGradient" StartPoint="0,0" EndPoint="1,1">
    <GradientStop Color="#1E88E5" Offset="0"/>
    <GradientStop Color="#1565C0" Offset="1"/>
  </LinearGradientBrush>

  <!-- Status pill brushes -->
  <SolidColorBrush x:Key="PillActiveBg"   Color="#E5F4EC"/>
  <SolidColorBrush x:Key="PillActiveFg"   Color="#2A8E54"/>
  <SolidColorBrush x:Key="PillDraftBg"    Color="#EDF0F4"/>
  <SolidColorBrush x:Key="PillDraftFg"    Color="#5C6B7B"/>
  <SolidColorBrush x:Key="PillHoldBg"     Color="#FFF1DF"/>
  <SolidColorBrush x:Key="PillHoldFg"     Color="#C77000"/>
  <SolidColorBrush x:Key="PillClosedBg"   Color="#FBE6E6"/>
  <SolidColorBrush x:Key="PillClosedFg"   Color="#B23A3A"/>
  <SolidColorBrush x:Key="PillFilledBg"   Color="#E1EEF9"/>
  <SolidColorBrush x:Key="PillFilledFg"   Color="#1565C0"/>

  <!-- =====  Typography  ===== -->
  <Style x:Key="H1" TargetType="TextBlock">
    <Setter Property="FontSize" Value="32"/>
    <Setter Property="FontWeight" Value="Bold"/>
    <Setter Property="Foreground" Value="White"/>
    <Setter Property="FontFamily" Value="Segoe UI"/>
  </Style>
  <Style x:Key="H2" TargetType="TextBlock">
    <Setter Property="FontSize" Value="20"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
    <Setter Property="Foreground" Value="{StaticResource TextPrimary}"/>
    <Setter Property="FontFamily" Value="Segoe UI"/>
  </Style>
  <Style x:Key="H3" TargetType="TextBlock">
    <Setter Property="FontSize" Value="15"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
    <Setter Property="Foreground" Value="{StaticResource TextPrimary}"/>
    <Setter Property="FontFamily" Value="Segoe UI"/>
  </Style>
  <Style x:Key="Body" TargetType="TextBlock">
    <Setter Property="FontSize" Value="13"/>
    <Setter Property="Foreground" Value="{StaticResource TextBody}"/>
    <Setter Property="FontFamily" Value="Segoe UI"/>
    <Setter Property="TextWrapping" Value="Wrap"/>
  </Style>
  <Style x:Key="Caption" TargetType="TextBlock">
    <Setter Property="FontSize" Value="12"/>
    <Setter Property="Foreground" Value="{StaticResource TextMuted}"/>
    <Setter Property="FontFamily" Value="Segoe UI"/>
  </Style>
  <Style x:Key="MicroLabel" TargetType="TextBlock">
    <Setter Property="FontSize" Value="11"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
    <Setter Property="Foreground" Value="{StaticResource TextMuted}"/>
    <Setter Property="FontFamily" Value="Segoe UI"/>
  </Style>
  <Style x:Key="KpiNumber" TargetType="TextBlock">
    <Setter Property="FontSize" Value="32"/>
    <Setter Property="FontWeight" Value="Bold"/>
    <Setter Property="Foreground" Value="{StaticResource TextPrimary}"/>
    <Setter Property="FontFamily" Value="Segoe UI"/>
  </Style>
  <Style x:Key="HeroSub" TargetType="TextBlock">
    <Setter Property="FontSize" Value="13"/>
    <Setter Property="Foreground" Value="#CBDBEA"/>
    <Setter Property="FontFamily" Value="Segoe UI"/>
  </Style>

  <!-- =====  Cards & surfaces  ===== -->
  <Style x:Key="Card" TargetType="Border">
    <Setter Property="Background" Value="{StaticResource CardBg}"/>
    <Setter Property="BorderBrush" Value="{StaticResource CardBorder}"/>
    <Setter Property="BorderThickness" Value="1"/>
    <Setter Property="CornerRadius" Value="10"/>
    <Setter Property="Padding" Value="18"/>
    <Setter Property="Effect">
      <Setter.Value>
        <DropShadowEffect Color="#10000000" BlurRadius="14" ShadowDepth="2" Opacity="0.6"/>
      </Setter.Value>
    </Setter>
  </Style>
  <Style x:Key="FlatCard" TargetType="Border">
    <Setter Property="Background" Value="{StaticResource CardBg}"/>
    <Setter Property="BorderBrush" Value="{StaticResource CardBorder}"/>
    <Setter Property="BorderThickness" Value="1"/>
    <Setter Property="CornerRadius" Value="10"/>
    <Setter Property="Padding" Value="16"/>
  </Style>
  <Style x:Key="SidebarCard" TargetType="Border" BasedOn="{StaticResource Card}">
    <Setter Property="Padding" Value="14"/>
  </Style>

  <!-- =====  Inputs  ===== -->
  <Style x:Key="Field" TargetType="TextBox">
    <Setter Property="Background" Value="White"/>
    <Setter Property="BorderBrush" Value="#CBD5E1"/>
    <Setter Property="BorderThickness" Value="1"/>
    <Setter Property="Padding" Value="10,7"/>
    <Setter Property="FontSize" Value="13"/>
    <Setter Property="Foreground" Value="{StaticResource TextBody}"/>
    <Setter Property="VerticalContentAlignment" Value="Center"/>
    <Setter Property="MinHeight" Value="34"/>
    <Setter Property="FontFamily" Value="Segoe UI"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="TextBox">
          <Border Background="{TemplateBinding Background}"
                  BorderBrush="{TemplateBinding BorderBrush}"
                  BorderThickness="{TemplateBinding BorderThickness}"
                  CornerRadius="6">
            <ScrollViewer x:Name="PART_ContentHost"
                          Padding="{TemplateBinding Padding}"
                          VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsFocused" Value="True">
              <Setter Property="BorderBrush" Value="{StaticResource AccentBlue}"/>
              <Setter Property="BorderThickness" Value="1.5"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style x:Key="MultilineField" TargetType="TextBox" BasedOn="{StaticResource Field}">
    <Setter Property="AcceptsReturn" Value="True"/>
    <Setter Property="TextWrapping" Value="Wrap"/>
    <Setter Property="VerticalContentAlignment" Value="Top"/>
    <Setter Property="VerticalScrollBarVisibility" Value="Auto"/>
    <Setter Property="MinHeight" Value="80"/>
    <!-- Live spell check (OS dictionary): red squiggles + right-click
         suggestions on prose fields. Single-line Field/SearchField boxes
         deliberately omit it so names/search terms aren't flagged. -->
    <Setter Property="SpellCheck.IsEnabled" Value="True"/>
    <Setter Property="Language" Value="en-US"/>
  </Style>
  <Style x:Key="SearchField" TargetType="TextBox" BasedOn="{StaticResource Field}">
    <Setter Property="Background" Value="#F8FAFC"/>
    <Setter Property="MinHeight" Value="34"/>
  </Style>
  <Style x:Key="ComboField" TargetType="ComboBox">
    <Setter Property="MinHeight" Value="34"/>
    <Setter Property="Padding" Value="10,4"/>
    <Setter Property="FontSize" Value="13"/>
    <Setter Property="FontFamily" Value="Segoe UI"/>
    <Setter Property="Foreground" Value="{StaticResource TextBody}"/>
    <Setter Property="Background" Value="White"/>
    <Setter Property="BorderBrush" Value="#CBD5E1"/>
    <Setter Property="IsEditable" Value="False"/>
  </Style>

  <!-- =====  Buttons  ===== -->
  <Style x:Key="PrimaryBtn" TargetType="Button">
    <Setter Property="Foreground" Value="White"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
    <Setter Property="FontSize" Value="13"/>
    <Setter Property="FontFamily" Value="Segoe UI"/>
    <Setter Property="BorderThickness" Value="0"/>
    <Setter Property="Padding" Value="16,8"/>
    <Setter Property="Height" Value="36"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Background" Value="{StaticResource OrangeGradient}"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="ButtonBorder" CornerRadius="6"
                  Padding="{TemplateBinding Padding}"
                  Background="{TemplateBinding Background}">
            <Border.Effect>
              <DropShadowEffect Color="#3FE89923" BlurRadius="10" ShadowDepth="2" Opacity="0.5"/>
            </Border.Effect>
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter TargetName="ButtonBorder" Property="Opacity" Value="0.9"/>
            </Trigger>
            <Trigger Property="IsPressed" Value="True">
              <Setter TargetName="ButtonBorder" Property="Opacity" Value="0.76"/>
            </Trigger>
            <Trigger Property="IsEnabled" Value="False">
              <Setter TargetName="ButtonBorder" Property="Opacity" Value="0.4"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style x:Key="BlueBtn" TargetType="Button" BasedOn="{StaticResource PrimaryBtn}">
    <Setter Property="Background" Value="{StaticResource BlueGradient}"/>
  </Style>
  <Style x:Key="GhostBtn" TargetType="Button">
    <Setter Property="Foreground" Value="{StaticResource TextPrimary}"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
    <Setter Property="FontSize" Value="12.5"/>
    <Setter Property="FontFamily" Value="Segoe UI"/>
    <Setter Property="BorderThickness" Value="0"/>
    <Setter Property="Padding" Value="14,7"/>
    <Setter Property="Height" Value="34"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="GB" Background="White" BorderBrush="#CBD5E1"
                  BorderThickness="1" CornerRadius="6"
                  Padding="{TemplateBinding Padding}">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter TargetName="GB" Property="Background" Value="#F1F5FA"/>
            </Trigger>
            <Trigger Property="IsPressed" Value="True">
              <Setter TargetName="GB" Property="Background" Value="#E1EEF9"/>
            </Trigger>
            <Trigger Property="IsEnabled" Value="False">
              <Setter TargetName="GB" Property="Opacity" Value="0.4"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style x:Key="LinkBtn" TargetType="Button">
    <Setter Property="Foreground" Value="{StaticResource AccentBlue}"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
    <Setter Property="FontSize" Value="12"/>
    <Setter Property="FontFamily" Value="Segoe UI"/>
    <Setter Property="Background" Value="Transparent"/>
    <Setter Property="BorderThickness" Value="0"/>
    <Setter Property="Padding" Value="4,2"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border Background="Transparent" Padding="{TemplateBinding Padding}">
            <ContentPresenter HorizontalAlignment="Left" VerticalAlignment="Center"/>
          </Border>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style x:Key="IconBtn" TargetType="Button">
    <Setter Property="Background" Value="Transparent"/>
    <Setter Property="BorderThickness" Value="0"/>
    <Setter Property="Width" Value="28"/>
    <Setter Property="Height" Value="28"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Foreground" Value="{StaticResource TextMuted}"/>
    <Setter Property="FontFamily" Value="Segoe UI Symbol"/>
    <Setter Property="FontSize" Value="14"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="IB" Background="Transparent" CornerRadius="4">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter TargetName="IB" Property="Background" Value="#EEF3FA"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <!-- =====  Top nav tab buttons (the row of "Dashboard | Job Reqs | ..." chips) ===== -->
  <Style x:Key="NavTabBtn" TargetType="Button">
    <Setter Property="Foreground" Value="#CBDBEA"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
    <Setter Property="FontSize" Value="13"/>
    <Setter Property="FontFamily" Value="Segoe UI"/>
    <Setter Property="Background" Value="Transparent"/>
    <Setter Property="BorderThickness" Value="0"/>
    <Setter Property="Padding" Value="16,10"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="NavB" Background="{TemplateBinding Background}" CornerRadius="4"
                  Padding="{TemplateBinding Padding}">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter Property="Foreground" Value="White"/>
              <Setter TargetName="NavB" Property="Background" Value="#22FFFFFF"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
  <Style x:Key="NavTabBtnActive" TargetType="Button" BasedOn="{StaticResource NavTabBtn}">
    <Setter Property="Foreground" Value="White"/>
    <Setter Property="Background" Value="#33FFFFFF"/>
  </Style>

  <!-- =====  Status pills (Active / Draft / On Hold / Closed / Filled) ===== -->
  <Style x:Key="Pill" TargetType="Border">
    <Setter Property="CornerRadius" Value="10"/>
    <Setter Property="Padding" Value="8,2"/>
    <Setter Property="Height" Value="22"/>
    <Setter Property="VerticalAlignment" Value="Center"/>
    <Setter Property="HorizontalAlignment" Value="Left"/>
  </Style>
  <Style x:Key="PillText" TargetType="TextBlock">
    <Setter Property="FontSize" Value="11"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
    <Setter Property="VerticalAlignment" Value="Center"/>
    <Setter Property="FontFamily" Value="Segoe UI"/>
  </Style>

  <!-- =====  ListView cell defaults (Job Reqs grid) ===== -->
  <Style x:Key="GridHeaderText" TargetType="TextBlock">
    <Setter Property="FontSize" Value="11"/>
    <Setter Property="FontWeight" Value="Bold"/>
    <Setter Property="Foreground" Value="{StaticResource TextMuted}"/>
    <Setter Property="FontFamily" Value="Segoe UI"/>
  </Style>

</ResourceDictionary>
'@

function Register-MouseWheelRedirect {
    <#
    Fixes the dead mouse-wheel across the app.

    The shell wraps all content in an OUTER ScrollViewer (views/Shell.ps1) and
    every view paints its own INNER ScrollViewer into it. WPF hands an inner
    ScrollViewer unbounded height, so it has nothing to scroll - yet
    ScrollViewer.OnMouseWheel still marks the wheel event Handled even when it
    cannot move. The outer (real) scroller therefore never sees the wheel and
    nothing scrolls.

    This installs ONE class handler on ScrollViewer's *tunneling*
    PreviewMouseWheel. When the ScrollViewer under the pointer cannot consume
    the wheel in that direction (no scrollable extent, or already at the top/
    bottom edge), the event is re-raised as a bubbling MouseWheel on the
    ScrollViewer's visual parent, so an ancestor ScrollViewer (the shell
    content scroller) gets a chance to scroll. ScrollViewers that CAN scroll are
    left untouched and behave normally, including chaining to the parent once
    they hit their own edge.

    Registered once per process (class handlers are global per type); the guard
    flag and this function share Theme.ps1's script scope so the one-time check
    holds. Applies to every ScrollViewer in every window and dialog, including
    the ones rebuilt on each tab switch.
    #>
    if ($Script:_WheelRedirectInstalled) { return }

    $handler = [System.Windows.Input.MouseWheelEventHandler]{
        param($s, $e)
        try {
            if ($e.Handled) { return }
            $sv = $s

            # PreviewMouseWheel TUNNELS (outer -> inner), so this fires on every
            # ScrollViewer above the pointer too. Only the innermost ScrollViewer
            # actually under the pointer gets to decide - otherwise a
            # non-scrolling ancestor would hijack the wheel from a scrollable
            # descendant. Find the nearest ScrollViewer to the real target and
            # bail unless that's us.
            $nearest = $null
            $node = $e.OriginalSource
            while ($node) {
                if ($node -is [System.Windows.Controls.ScrollViewer]) { $nearest = $node; break }
                if ($node -is [System.Windows.Media.Visual] -or $node -is [System.Windows.Media.Media3D.Visual3D]) {
                    $node = [System.Windows.Media.VisualTreeHelper]::GetParent($node)
                } else { break }
            }
            if ($nearest -and $nearest -ne $sv) { return }

            # Can this ScrollViewer actually move in the wheeled direction?
            $consume = $false
            if ($sv.ScrollableHeight -gt 0) {
                if ($e.Delta -gt 0) { $consume = ($sv.VerticalOffset -gt 0) }                       # up   - room above
                elseif ($e.Delta -lt 0) { $consume = ($sv.VerticalOffset -lt $sv.ScrollableHeight) } # down - room below
            }
            if ($consume) { return }   # leave it to ScrollViewer's own handling

            # Dead end here: hand the wheel to the parent so an ancestor scroller
            # (e.g. the shell content ScrollViewer) can act on it.
            $e.Handled = $true
            $parent = [System.Windows.Media.VisualTreeHelper]::GetParent($sv)
            if ($parent -is [System.Windows.UIElement]) {
                $fwd = New-Object System.Windows.Input.MouseWheelEventArgs($e.MouseDevice, $e.Timestamp, $e.Delta)
                $fwd.RoutedEvent = [System.Windows.UIElement]::MouseWheelEvent
                $parent.RaiseEvent($fwd)
            }
        } catch { }
    }

    [System.Windows.EventManager]::RegisterClassHandler(
        [System.Windows.Controls.ScrollViewer],
        [System.Windows.UIElement]::PreviewMouseWheelEvent,
        $handler)

    $Script:_WheelRedirectInstalled = $true
}

function Initialize-TrueHireApp {
    if (-not [System.Windows.Application]::Current) {
        $app = New-Object System.Windows.Application
        $app.ShutdownMode = [System.Windows.ShutdownMode]::OnExplicitShutdown
    }
    $app = [System.Windows.Application]::Current
    [xml]$resDoc = $Script:WinResources
    $resReader = [System.Xml.XmlNodeReader]::new($resDoc)
    $resources = [System.Windows.Markup.XamlReader]::Load($resReader)
    foreach ($k in $resources.Keys) { $app.Resources[$k] = $resources[$k] }
    # One-time: make the mouse wheel reach the scroller that can actually move.
    Register-MouseWheelRedirect
}

function Get-TrueHireIcon {
    <#
    Returns a frozen BitmapFrame of the app icon, or $null if icon.ico isn't
    on disk. Cached on $Script:_CachedAppIcon so it's loaded once per session
    and reused across every window. Freezing the bitmap is required for
    cross-thread reuse and makes WPF cheap to assign it as Window.Icon.
    #>
    if ($Script:_CachedAppIcon) { return $Script:_CachedAppIcon }
    if (-not $Script:IconPath -or -not (Test-Path -LiteralPath $Script:IconPath)) { return $null }
    try {
        $uri = [System.Uri]::new((Resolve-Path -LiteralPath $Script:IconPath).Path)
        $img = New-Object System.Windows.Media.Imaging.BitmapImage
        $img.BeginInit()
        $img.UriSource   = $uri
        $img.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $img.EndInit()
        $img.Freeze()
        $Script:_CachedAppIcon = $img
        return $img
    } catch {
        if (Get-Command Write-TrueHireLog -ErrorAction SilentlyContinue) {
            Write-TrueHireLog -Level WARN -Source 'Get-TrueHireIcon' -Message $_.Exception.Message -Exception $_.Exception
        }
        return $null
    }
}

function Set-WindowUiScale {
    <#
    Magnifies a window's entire visual tree by $Script:UiScale and grows the
    window box by the same factor, so the on-screen layout is identical to 1.0x
    just rendered larger. The window box is clamped to the primary monitor work
    area so a scaled window never opens partly off-screen. Called by
    ConvertTo-Window before the window is shown. No-op when UiScale is unset/<=0/1.

    Note: the clamp uses the PRIMARY monitor work area; a dialog opened on a
    smaller secondary monitor may clamp looser than ideal. Acceptable here.
    #>
    param([System.Windows.Window]$Window)
    if (-not $Window) { return }
    $scale = $Script:UiScale
    if (-not $scale -or $scale -le 0 -or [Math]::Abs($scale - 1.0) -lt 0.0001) { return }

    # 1) Scale the content visual tree via a LayoutTransform on the root element.
    $root = $Window.Content
    if ($root -is [System.Windows.FrameworkElement]) {
        $root.LayoutTransform = New-Object System.Windows.Media.ScaleTransform($scale, $scale)
    }

    # 2) Grow the window box to match, clamped to the work area. Guard NaN/auto/0.
    $wa = [System.Windows.SystemParameters]::WorkArea
    $maxW = if ($wa.Width  -gt 0) { [double]$wa.Width }  else { [double]::PositiveInfinity }
    $maxH = if ($wa.Height -gt 0) { [double]$wa.Height } else { [double]::PositiveInfinity }

    $dims = @(
        @{ Prop = 'Width';     Max = $maxW },
        @{ Prop = 'Height';    Max = $maxH },
        @{ Prop = 'MinWidth';  Max = $maxW },
        @{ Prop = 'MinHeight'; Max = $maxH }
    )
    foreach ($d in $dims) {
        $cur = $Window.($d.Prop)
        if ($null -ne $cur -and
            -not [double]::IsNaN($cur) -and
            -not [double]::IsInfinity($cur) -and
            $cur -gt 0) {
            $Window.($d.Prop) = [Math]::Min($cur * $scale, $d.Max)
        }
    }
}

function ConvertTo-Window {
    param([string]$Xaml)
    Initialize-TrueHireApp
    [xml]$doc = $Xaml
    $reader = [System.Xml.XmlNodeReader]::new($doc)
    $w = [System.Windows.Markup.XamlReader]::Load($reader)
    # Brand the title-bar / taskbar with the app icon. Silently no-op if
    # icon.ico isn't present so a stripped deploy still launches.
    $icon = Get-TrueHireIcon
    if ($icon) { try { $w.Icon = $icon } catch { } }
    Set-WindowUiScale -Window $w
    return $w
}

function Set-WindowBanner {
    <#
    Paints the banner image. Two delivery paths:

      - If the window has an Image element named 'BannerImage' or 'HeroImage',
        the bitmap is plugged into its Source. The XAML controls Stretch
        (Uniform, so the whole image is visible without cropping) and the
        surrounding Border carries the letterbox background color.

      - Otherwise, legacy code path: paint an ImageBrush onto any Border
        named 'BannerHost' or 'HeroBorder'. Kept for any dialog window that
        hasn't been migrated to the Image-element pattern.

    Silently no-ops if the PNG isn't found - keeps the app running on
    machines where someone deleted the images folder.
    #>
    param([System.Windows.Window]$Window)
    if (-not $Window) { return }
    if (-not ($Script:BannerPath -and (Test-Path -LiteralPath $Script:BannerPath))) { return }
    try {
        $bImg = New-Object System.Windows.Media.Imaging.BitmapImage
        $bImg.BeginInit()
        $bImg.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bImg.UriSource   = [System.Uri]::new((Resolve-Path -LiteralPath $Script:BannerPath).Path)
        $bImg.EndInit()
        $bImg.Freeze()

        # Preferred path: an Image control whose Stretch is set in XAML.
        $imageSet = $false
        foreach ($n in 'BannerImage','HeroImage') {
            $el = $Window.FindName($n)
            if ($el) { $el.Source = $bImg; $imageSet = $true }
        }
        if ($imageSet) { return }

        # Legacy path: paint as ImageBrush on a Border. Stretch=Uniform so
        # the whole image is visible inside the Border, centered, with the
        # Border's own Background color showing through on the sides.
        $brush = New-Object System.Windows.Media.ImageBrush
        $brush.ImageSource = $bImg
        $brush.Stretch     = [System.Windows.Media.Stretch]::Uniform
        $brush.AlignmentX  = [System.Windows.Media.AlignmentX]::Center
        $brush.AlignmentY  = [System.Windows.Media.AlignmentY]::Center
        $brush.Freeze()
        foreach ($n in 'BannerHost','HeroBorder') {
            $el = $Window.FindName($n)
            if ($el) { $el.Background = $brush }
        }
    } catch { }
}
