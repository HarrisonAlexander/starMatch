# Design: Global 20% UI scale

**Date:** 2026-06-01
**Branch:** `upgrades`
**Status:** Approved (design), pending implementation plan

## Goal

Make the entire TrueHire UI render ~20% larger, proportionally, across the board.
The current UI is too small. Every element — text, controls, spacing, charts —
should be magnified uniformly. Today's layout (wrapping, column proportions, what
fits on screen) must be preserved exactly; this is a magnification, not a redesign.

## Decisions (locked)

- **Zoom model:** baked-in fixed 20% via a single constant. No runtime zoom control,
  no settings UI, no persistence. Retuning later = change one number and rebuild.
- **Screen fit:** scale each window 20% but clamp to the monitor work area so no
  window opens partly off-screen.

## Mechanism

### Single source of truth

```powershell
$Script:UiScale = 1.2   # top of lib/Theme.ps1
```

Defined in `lib/Theme.ps1` because `ConvertTo-Window` (same file) reads it, and per
the codebase invariant that `$Script:` state does not cross files (CLAUDE.md
"PowerShell + WPF gotchas" #4), the constant must live in that file's scope.

### One chokepoint: `ConvertTo-Window`

All seven views and every modal dialog are constructed through `ConvertTo-Window`
(`lib/Theme.ps1:410`). Extend that function so that, immediately after
`XamlReader.Load` and before the window is shown, it does two things to every window:

1. **Scale content.** Apply `ScaleTransform($UiScale, $UiScale)` as the
   `LayoutTransform` of the window's root element (`$w.Content`). This magnifies the
   whole visual tree 1.2× — typography, padding, buttons, pills, avatars, and the
   PowerShell-drawn `ArcSegment` / `PathGeometry` charts (they live inside the same
   tree, so no chart-specific code is needed).

2. **Scale the window box.** Multiply `Width`, `Height`, `MinWidth`, `MinHeight`
   (and `MaxWidth` / `MaxHeight` if set) by `$UiScale`. Guard every assignment
   against `NaN` / auto values (`[double]::IsNaN(...)`).

Scaling **both** the content transform and the window dimensions is what produces a
true "magnify the whole thing": the window's client area grows 1.2× and the content
lays out into `clientArea / 1.2` (i.e. the original layout space) then renders 1.2×
larger. Scaling only one would clip or reflow the content.

### Screen-fit clamp

After computing the scaled dimensions, cap them to the usable desktop:

```powershell
$wa = [System.Windows.SystemParameters]::WorkArea   # excludes taskbar
$w.Width  = [Math]::Min($scaledWidth,  $wa.Width)
$w.Height = [Math]::Min($scaledHeight, $wa.Height)
```

- Roomy monitor: shell grows `1280x820 -> 1536x984`; everything faithfully 20% larger.
- Cramped display (e.g. `1366x768`): window caps at the work area; content transform
  stays 1.2×, so controls/text are still larger, with the only trade-off being
  slightly tighter internal spacing instead of an off-screen window.
- Resizing happens before the window is shown, so `WindowStartupLocation`
  (`CenterScreen` / `CenterOwner`) still centers correctly.

**Caveat:** the clamp uses the **primary** monitor's work area. A dialog opened on a
smaller secondary monitor could clamp looser than ideal. Acceptable for this app.

## Scope boundaries (explicit non-goals)

- No find-and-replace of sizes across view XAML — the transform makes it unnecessary
  and would still miss chart geometry computed in PowerShell.
- No runtime zoom control, settings, or persistence.
- No re-layout or visual redesign — pure proportional magnification.

## Affected files

- `lib/Theme.ps1` — add `$Script:UiScale`; extend `ConvertTo-Window`. (Only source
  file that changes.)
- `TrueHire.exe` + `.tools/stage` mirror — rebuilt artifacts (per repo commit
  convention).

## Verification

1. `test\smoke.ps1` stays green. It builds the shell through `ConvertTo-Window`
   (line 116), so the new scaling path is exercised headlessly; every view/dialog
   still parses and renders.
2. Run from source (`TrueHire.ps1`); eyeball shell + every tab + a couple of
   dialogs — uniformly ~20% larger, nothing clipped.
3. Rebuild `TrueHire.exe` via the `build-exe` skill; refresh `.tools/stage`.
4. Commit to `upgrades`.

## Risks

- **Text crispness:** `LayoutTransform` scaling at a non-integer factor (1.2) can
  marginally soften ClearType vs. native font sizes. Acceptable and far better than a
  `RenderTransform`; revisit only if visibly objectionable.
- **Headless `SystemParameters.WorkArea`:** available under the WPF assemblies the
  smoke test already loads; if it ever returns an empty rect, guard by skipping the
  clamp when work-area dimensions are non-positive.
