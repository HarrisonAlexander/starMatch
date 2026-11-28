# Candidate Ordinal Rank Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the candidate cards' numeric `%` match (ring + bar) with a per-job ordinal rank ("2nd of 8", medal accent for top 3), keeping the 0–100 score as the internal ranking engine.

**Architecture:** Add two pure helpers to `lib/Helpers.ps1` — `ConvertTo-Ordinal` and `Get-CandidateRankInfo` (ranks a candidate against others sharing its `jobReqId`, shared-place ties, rated-only denominator). Swap the card and detail-dialog display to a drawn rank badge. `Get-CandidateScore` is untouched. Excel, Dashboard, Analytics untouched.

**Tech Stack:** Windows PowerShell 5.1 + WPF (controls built in code). No test framework — `test/smoke.ps1` is a run-all script; each "test" is an assertion line that prints `OK`/`FAIL`. The repo mirrors source into `.tools/stage/` and ships a rebuilt `TrueHire.exe`.

**Branch:** `4.3` (already checked out).

**Per-task convention:** Every code task edits the **root** file only; the final task mirrors all changed files into `.tools/stage/` and rebuilds the exe. Run the gate with:
`powershell -NoProfile -ExecutionPolicy Bypass -File .\test\smoke.ps1`

---

### Task 1: `ConvertTo-Ordinal` helper

**Files:**
- Modify: `lib/Helpers.ps1` (add function immediately above `Get-CandidateScore`, currently line 386)
- Test: `test/smoke.ps1` (add a new section just before the final `Write-Host 'Smoke test complete.'`)

- [ ] **Step 1: Write the failing test**

In `test/smoke.ps1`, immediately before these final two lines:

```powershell
Write-Host ''
Write-Host 'Smoke test complete.'
```

insert:

```powershell
# ============================================================
# Candidate ranking (lib/Helpers.ps1 - ConvertTo-Ordinal / Get-CandidateRankInfo)
# ============================================================
Write-Host ''
Write-Host 'Candidate ranking:' -ForegroundColor Cyan

# ConvertTo-Ordinal: English ordinal suffixes incl. the 11-13 exceptions.
$ordCases = @{ 1='1st'; 2='2nd'; 3='3rd'; 4='4th'; 11='11th'; 12='12th'; 13='13th'; 21='21st'; 22='22nd'; 23='23rd' }
$ordOk = $true
foreach ($k in ($ordCases.Keys | Sort-Object)) {
    $got = ConvertTo-Ordinal $k
    if ($got -ne $ordCases[$k]) { $ordOk = $false; Write-Host ("  FAIL ConvertTo-Ordinal {0} = '{1}' expected '{2}'" -f $k, $got, $ordCases[$k]) -ForegroundColor Red }
}
if ($ordOk) { Write-Host '  OK   ConvertTo-Ordinal covers 1st..23rd incl. 11/12/13th' }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File .\test\smoke.ps1`
Expected: the run aborts/errors at the new section with a "term 'ConvertTo-Ordinal' is not recognized" error (function not defined yet).

- [ ] **Step 3: Write minimal implementation**

In `lib/Helpers.ps1`, directly above `function Get-CandidateScore {` (line 386), insert:

```powershell
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File .\test\smoke.ps1`
Expected: `OK   ConvertTo-Ordinal covers 1st..23rd incl. 11/12/13th`, and the script reaches `Smoke test complete.`

- [ ] **Step 5: Commit**

```bash
git add lib/Helpers.ps1 test/smoke.ps1
git commit -m "feat(rank): add ConvertTo-Ordinal helper"
```

---

### Task 2: `Get-CandidateRankInfo` helper

**Files:**
- Modify: `lib/Helpers.ps1` (add function directly below `ConvertTo-Ordinal`, above `Get-CandidateScore`)
- Test: `test/smoke.ps1` (extend the "Candidate ranking" section from Task 1)

**Interface (referenced by later tasks):**
`Get-CandidateRankInfo $Candidate $Data` returns `@{ Place=[int]; Pool=[int]; Display=[string] }` or `$null` when the candidate has no Submitted score.

- [ ] **Step 1: Write the failing test**

In `test/smoke.ps1`, inside the "Candidate ranking" section, after the `ConvertTo-Ordinal` block, append:

```powershell
# Get-CandidateRankInfo: per-job ranking, shared place on ties, rated-only pool.
# Reuse the smoke _SmkCand helper (defined in the weighted-scoring section above)
# to build candidates with one Submitted entry. With no kit in $rkData every
# weight is 1, so each candidate's score is the equal mean of its category
# anchors * 20. Scores below: A=100, B=80, C=80, D=60 -> places 1,2,2,4; plus
# one unrated candidate (no raterEntries) which must rank $null.
$rkJob = 'req-rank'
# A: tech=5,comm=5 => 100 ; B: tech=4,comm=4 => 80 ; C: tech=4,comm=4 => 80 ; D: tech=3,comm=3 => 60
$rkA = _SmkCand $rkJob @{ tech = 5; comm = 5 }; $rkA.id = 'rk-A'
$rkB = _SmkCand $rkJob @{ tech = 4; comm = 4 }; $rkB.id = 'rk-B'
$rkC = _SmkCand $rkJob @{ tech = 4; comm = 4 }; $rkC.id = 'rk-C'
$rkD = _SmkCand $rkJob @{ tech = 3; comm = 3 }; $rkD.id = 'rk-D'
$rkU = New-Candidate; $rkU.jobReqId = $rkJob; $rkU.id = 'rk-U'   # unrated (no raterEntries)
$rkData = @{ Jobs=@(); Kits=@(); Candidates=@($rkA,$rkB,$rkC,$rkD,$rkU); Catalog=$Script:ShellData.Catalog; Settings=$null }

$riA = Get-CandidateRankInfo $rkA $rkData
$riB = Get-CandidateRankInfo $rkB $rkData
$riC = Get-CandidateRankInfo $rkC $rkData
$riD = Get-CandidateRankInfo $rkD $rkData
$riU = Get-CandidateRankInfo $rkU $rkData

$rankOk = $true
if ($riA.Place -ne 1 -or $riA.Display -ne '1st of 4') { $rankOk=$false; Write-Host ("  FAIL A place={0} disp='{1}' expected 1 / '1st of 4'" -f $riA.Place,$riA.Display) -ForegroundColor Red }
if ($riB.Place -ne 2 -or $riC.Place -ne 2)            { $rankOk=$false; Write-Host ("  FAIL tie B={0} C={1} expected 2/2" -f $riB.Place,$riC.Place) -ForegroundColor Red }
if ($riD.Place -ne 4 -or $riD.Display -ne '4th of 4') { $rankOk=$false; Write-Host ("  FAIL D place={0} disp='{1}' expected 4 / '4th of 4'" -f $riD.Place,$riD.Display) -ForegroundColor Red }
if ($null -ne $riU)                                   { $rankOk=$false; Write-Host '  FAIL unrated candidate should rank $null' -ForegroundColor Red }
if ($rankOk) { Write-Host '  OK   Get-CandidateRankInfo: 1st/2nd/2nd/4th, pool 4, unrated -> null' }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File .\test\smoke.ps1`
Expected: error "term 'Get-CandidateRankInfo' is not recognized" (or the section aborts before printing its OK line).

- [ ] **Step 3: Write minimal implementation**

In `lib/Helpers.ps1`, directly below the `ConvertTo-Ordinal` function (and above `Get-CandidateScore`), insert:

```powershell
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File .\test\smoke.ps1`
Expected: `OK   Get-CandidateRankInfo: 1st/2nd/2nd/4th, pool 4, unrated -> null`

- [ ] **Step 5: Commit**

```bash
git add lib/Helpers.ps1 test/smoke.ps1
git commit -m "feat(rank): add Get-CandidateRankInfo (per-job ordinal, shared ties)"
```

---

### Task 3: Rank badge control + card swap

**Files:**
- Modify: `views/Candidates.ps1` — add `_CandRankBadge` (above `_CandCard`, currently line 106); replace the score-row block in `_CandCard` (lines 170–201)
- Test: `test/smoke.ps1` (extend the "Candidate ranking" section)

**Interface:** `_CandRankBadge $RankInfo` takes the `Get-CandidateRankInfo` hashtable (or `$null`) and returns a WPF `Border`.

- [ ] **Step 1: Write the failing test**

In `test/smoke.ps1`, at the end of the "Candidate ranking" section (just before the final `Write-Host 'Smoke test complete.'`), append:

```powershell
# _CandRankBadge renders a Border for a ranked and an unrated candidate.
$badge1 = _CandRankBadge @{ Place=1; Pool=4; Display='1st of 4' }
$badgeU = _CandRankBadge $null
$badgeText = { param($b) (@($b.Child.Children) | Where-Object { $_ -is [System.Windows.Controls.TextBlock] } | ForEach-Object { $_.Text }) -join '' }
if ($badge1 -is [System.Windows.Controls.Border] -and (& $badgeText $badge1) -match '1st of 4' -and (& $badgeText $badgeU) -match 'Not yet rated') {
    Write-Host '  OK   _CandRankBadge renders ranked + unrated badges'
} else {
    Write-Host ("  FAIL _CandRankBadge ranked='{0}' unrated='{1}'" -f (& $badgeText $badge1), (& $badgeText $badgeU)) -ForegroundColor Red
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File .\test\smoke.ps1`
Expected: error "term '_CandRankBadge' is not recognized".

- [ ] **Step 3a: Add the `_CandRankBadge` function**

In `views/Candidates.ps1`, directly above `function _CandCard {` (line 106), insert:

```powershell
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
```

- [ ] **Step 3b: Replace the score-row block in `_CandCard`**

In `views/Candidates.ps1`, replace this entire block (lines 170–201):

```powershell
    # Match score ring + label
    $scoreRow = New-Object System.Windows.Controls.Grid
    $scoreRow.Margin = '0,10,0,0'
    $r1 = New-Object System.Windows.Controls.ColumnDefinition; $r1.Width = 'Auto'
    $r2 = New-Object System.Windows.Controls.ColumnDefinition; $r2.Width = '*'
    [void]$scoreRow.ColumnDefinitions.Add($r1); [void]$scoreRow.ColumnDefinitions.Add($r2)

    # Derived score from Submitted rater anchors (lib/Helpers.ps1).
    # $null means "no Submitted ratings yet" -> ring renders gray with "--".
    $candScore = Get-CandidateScore $Cand $Script:ShellData
    $ringColor = if ($null -eq $candScore) { '#94A3B8' }
                 elseif ($candScore -ge 80) { '#2A8E54' }
                 elseif ($candScore -ge 60) { '#F5A623' }
                 else                        { '#B23A3A' }
    $ring = New-MetricRing -Percent $candScore -ColorHex $ringColor -Size 50
    [System.Windows.Controls.Grid]::SetColumn($ring, 0)
    [void]$scoreRow.Children.Add($ring)

    $lblBox = New-Object System.Windows.Controls.StackPanel
    $lblBox.Margin = '12,0,0,0'
    $lblBox.VerticalAlignment = 'Center'
    $lbl = New-Object System.Windows.Controls.TextBlock
    $lbl.Text = 'Match Score'
    $lbl.FontSize = 11
    $lbl.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#6B7B8C')))
    [void]$lblBox.Children.Add($lbl)
    $bar = New-MatchScoreBar -Score $candScore -Width 150 -Height 6
    $bar.Margin = '0,6,0,0'
    [void]$lblBox.Children.Add($bar)
    [System.Windows.Controls.Grid]::SetColumn($lblBox, 1)
    [void]$scoreRow.Children.Add($lblBox)
    [void]$s.Children.Add($scoreRow)
```

with:

```powershell
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File .\test\smoke.ps1`
Expected: `OK   _CandRankBadge renders ranked + unrated badges` AND `OK   Candidates renders (1 child elements)` (the card render path now uses the badge).

- [ ] **Step 5: Commit**

```bash
git add views/Candidates.ps1 test/smoke.ps1
git commit -m "feat(rank): show ordinal rank badge on candidate cards"
```

---

### Task 4: Candidate detail dialog — RANK field

**Files:**
- Modify: `views/Candidates.ps1` — dialog XAML label/tooltip (lines 550–556) and the `TbScore` assignment (line 945–946)

No new test (covered by the dialog XAML parse already in smoke's `$dialogs` list and the helper tests above).

- [ ] **Step 1: Update the dialog XAML label + tooltip**

In `views/Candidates.ps1`, replace this block (lines 549–557):

```powershell
          <StackPanel Margin="4,0,4,0">
            <TextBlock Style="{StaticResource MicroLabel}" Text="MATCH SCORE" Margin="0,0,0,4"/>
            <Border BorderBrush="#CBD5E1" BorderThickness="1" CornerRadius="6"
                    Background="#F8FAFC" Padding="10,7" Height="34"
                    ToolTip="Derived from Submitted rater anchor evaluations. Anchor 5 = 100, 4 = 80, 3 = 60, 2 = 40, 1 = 20. Anchor 0 (insufficient evidence) is excluded. Shows -- when no Submitted ratings exist.">
              <TextBlock x:Name="TbScore" VerticalAlignment="Center" FontSize="13"
                         Foreground="{StaticResource TextBody}" Text=""/>
            </Border>
          </StackPanel>
```

with:

```powershell
          <StackPanel Margin="4,0,4,0">
            <TextBlock Style="{StaticResource MicroLabel}" Text="RANK" Margin="0,0,0,4"/>
            <Border BorderBrush="#CBD5E1" BorderThickness="1" CornerRadius="6"
                    Background="#F8FAFC" Padding="10,7" Height="34"
                    ToolTip="This candidate's place among the rated candidates for the same job, by derived match score (higher score = higher place). Ties share a place. Shows 'Not yet rated' until a Submitted evaluation exists.">
              <TextBlock x:Name="TbScore" VerticalAlignment="Center" FontSize="13"
                         Foreground="{StaticResource TextBody}" Text=""/>
            </Border>
          </StackPanel>
```

- [ ] **Step 2: Update the `TbScore` assignment**

In `views/Candidates.ps1`, replace these two lines (944–946):

```powershell
    # Score is derived from Submitted rater anchors. Read-only display.
    $cScore = Get-CandidateScore $c $Script:ShellData
    ($w.FindName('TbScore')).Text = if ($null -eq $cScore) { '--  (not yet rated)' } else { "$cScore%" }
```

with:

```powershell
    # Per-job ordinal rank (read-only). Underlying score still drives placement.
    $cRank = Get-CandidateRankInfo $c $Script:ShellData
    ($w.FindName('TbScore')).Text = if ($null -eq $cRank) { 'Not yet rated' } else { [string]$cRank.Display }
```

- [ ] **Step 3: Run the gate**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File .\test\smoke.ps1`
Expected: `OK   dialog CandDetailXaml XAML parses` still passes, no FAIL lines.

- [ ] **Step 4: Commit**

```bash
git add views/Candidates.ps1
git commit -m "feat(rank): show RANK instead of % in candidate detail dialog"
```

---

### Task 5: Relabel the sort from "Match Score" to "Rank"

**Files:**
- Modify: `views/Candidates.ps1` — sort ComboBox (line 64), default `SortBy` (line 89), sort switch case (line 361)

No new test; the smoke Candidates render uses the default `SortBy` and must still resolve a sort case.

- [ ] **Step 1: Rename the ComboBox item**

In `views/Candidates.ps1` line 64, change:

```powershell
        <ComboBoxItem Content="Match Score" IsSelected="True"/>
```

to:

```powershell
        <ComboBoxItem Content="Rank" IsSelected="True"/>
```

- [ ] **Step 2: Update the default `SortBy`**

In `views/Candidates.ps1` line 89, change:

```powershell
    SortBy       = 'Match Score'
```

to:

```powershell
    SortBy       = 'Rank'
```

- [ ] **Step 3: Update the sort switch case**

In `views/Candidates.ps1`, change the case label (line 361) from:

```powershell
        'Match Score'  {
```

to:

```powershell
        'Rank'         {
```

(Leave the body unchanged — it still sorts by `Get-CandidateScore` descending, which is rank order. The comment below it about `$null` falling to the end remains correct.)

- [ ] **Step 4: Run the gate**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File .\test\smoke.ps1`
Expected: `OK   Candidates renders (1 child elements)`, no FAIL lines.

- [ ] **Step 5: Commit**

```bash
git add views/Candidates.ps1
git commit -m "feat(rank): relabel candidate sort 'Match Score' -> 'Rank'"
```

---

### Task 6: Remove orphaned `New-MetricRing` / `New-MatchScoreBar`

**Files:**
- Modify: `lib/Helpers.ps1` — delete `New-MatchScoreBar` (lines 155–182) and `New-MetricRing` (lines 184–247)

These were the only consumers of those two functions (verified: after Task 3 nothing references them; the Dashboard "Overall Match" ring KPI was removed earlier).

- [ ] **Step 1: Confirm there are no remaining references**

Run: `powershell -NoProfile -Command "Select-String -Path .\lib\*.ps1, .\views\*.ps1 -Pattern 'New-MetricRing|New-MatchScoreBar'"`
Expected: only the two `function` definition lines in `lib/Helpers.ps1` print (no call sites).

- [ ] **Step 2: Delete the two functions**

In `lib/Helpers.ps1`, delete the entire `function New-MatchScoreBar { ... }` block (lines 155–182) and the entire `function New-MetricRing { ... }` block (lines 184–247), including the blank line between them. Leave `function New-MiniBarChart {` (currently line 249) and everything after it intact.

- [ ] **Step 3: Run the gate**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File .\test\smoke.ps1`
Expected: full run reaches `Smoke test complete.` with no FAIL lines and no "term not recognized" errors.

- [ ] **Step 4: Commit**

```bash
git add lib/Helpers.ps1
git commit -m "refactor(rank): remove now-unused New-MetricRing/New-MatchScoreBar"
```

---

### Task 7: Mirror to `.tools/stage` + rebuild exe

**Files:**
- Overwrite: `.tools/stage/lib/Helpers.ps1`, `.tools/stage/views/Candidates.ps1`, `.tools/stage/test/smoke.ps1`
- Regenerate: `TrueHire.exe`, `.tools/Launcher.cs`, `.tools/bundle.zip`

- [ ] **Step 1: Mirror the three changed source files into stage**

```powershell
Copy-Item .\lib\Helpers.ps1        .\.tools\stage\lib\Helpers.ps1        -Force
Copy-Item .\views\Candidates.ps1   .\.tools\stage\views\Candidates.ps1   -Force
Copy-Item .\test\smoke.ps1         .\.tools\stage\test\smoke.ps1         -Force
```

- [ ] **Step 2: Verify the stage copies are byte-identical**

```powershell
foreach ($f in 'lib\Helpers.ps1','views\Candidates.ps1','test\smoke.ps1') {
    $same = (Get-FileHash ".\$f").Hash -eq (Get-FileHash ".\.tools\stage\$f").Hash
    Write-Output "$f identical: $same"
}
```
Expected: all three print `identical: True`.

- [ ] **Step 3: Run the staged gate**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File .\.tools\stage\test\smoke.ps1`
Expected: reaches `Smoke test complete.` with the ranking `OK` lines and no FAIL.

- [ ] **Step 4: Rebuild the exe** (excludes prevent the 10x bloat — see project memory)

```powershell
& "$HOME\.claude\skills\build-exe\scripts\Build-Exe.ps1" `
    -SourceDir 'M:\VAULT-X\Projects\TrueHire\truehire.portable' `
    -EntryScript 'TrueHire.ps1' `
    -ExcludePattern 'TrueHire.zip','demo\*','outputs\*'
```
Expected: "Built: ...TrueHire.exe" at ~10 MB (not ~100 MB).

- [ ] **Step 5: Commit**

```bash
git add lib/Helpers.ps1 views/Candidates.ps1 test/smoke.ps1 .tools/stage TrueHire.exe .tools/Launcher.cs .tools/bundle.zip
git commit -m "build(rank): mirror to stage + rebuild TrueHire.exe with ordinal rank"
```

---

## Done criteria

- Candidate cards show a tinted rank badge ("2nd of 8", gold/silver/bronze for top 3, "Not yet rated" muted) instead of the `%` ring + bar.
- The detail dialog "RANK" field shows the same ordinal.
- The sort dropdown reads "Rank"; ordering is unchanged.
- `New-MetricRing` / `New-MatchScoreBar` are gone; no dangling references.
- `test/smoke.ps1` (root and staged) reach `Smoke test complete.` with the three new ranking `OK` lines and no FAIL.
- `TrueHire.exe` rebuilt at ~10 MB.
- Excel export, Dashboard, Analytics, and `Get-CandidateScore` are unchanged.
