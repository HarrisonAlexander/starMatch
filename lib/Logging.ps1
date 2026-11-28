<#
Logging.ps1 - daily-rolling text log under .\logs\ next to TrueHire.ps1, plus
WPF dispatcher unhandled-exception capture so errors get logged + captioned
instead of crashing the app. Wire-up lives in TrueHire.ps1: dot-source this
file, call Register-TrueHireExceptionHandlers after Initialize-TrueHireApp.

Public surface:
  - Write-TrueHireLog -Level INFO|WARN|ERROR|FATAL -Message ... [-Exception ...]
  - Invoke-SafeAction   -Label X -Action { ... }       try/catch + log + caption
  - Register-TrueHireExceptionHandlers                global dispatcher hook
  - Open-TrueHireLog                                  opens today's log file
  - Get-TrueHireLogPath                               returns the daily path

Log format:
  yyyy-MM-dd HH:mm:ss.fff [LEVEL] Source                           Message
      -> ExceptionType: Exception.Message
      <indented stack trace if available>

The session boot writes a single "===== Session start =====" banner so
multiple runs in one day are visually separable.
#>

# Resolve the log directory. $Script:RootDir is set by TrueHire.ps1 before
# this file is dot-sourced in production; tests dot-source the libs
# independently, so fall back to walking up from $PSCommandPath.
$logBase = if ($Script:RootDir) { $Script:RootDir } else { Split-Path -Parent $PSCommandPath | Split-Path -Parent }
$Script:LogDir = Join-Path $logBase 'logs'
if (-not (Test-Path -LiteralPath $Script:LogDir)) {
    New-Item -ItemType Directory -Path $Script:LogDir -Force | Out-Null
}

# Severity threshold. Set to 'DEBUG' to capture chatty traces; default INFO
# strikes a balance between signal and noise for user reports.
$Script:LogLevels   = @{ DEBUG = 0; INFO = 1; WARN = 2; ERROR = 3; FATAL = 4 }
$Script:LogMinLevel = 'INFO'

function Get-TrueHireLogPath {
    Join-Path $Script:LogDir ("truehire-{0}.log" -f (Get-Date -Format 'yyyy-MM-dd'))
}

function Write-TrueHireLog {
    <#
    Append one line to today's log. Exceptions are dumped on follow-up lines,
    indented with 4 spaces so grep '^[0-9]' isolates entry headers cleanly.
    Failures inside the logger itself are swallowed (Write-Host fallback) so
    logging never cascades into a second crash.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('DEBUG','INFO','WARN','ERROR','FATAL')]
        [string]$Level = 'INFO',
        [Parameter(Mandatory)][string]$Message,
        [System.Exception]$Exception,
        [string]$Source
    )
    if ($Script:LogLevels[$Level] -lt $Script:LogLevels[$Script:LogMinLevel]) { return }

    if (-not $Source) {
        # Walk one frame up the call stack so the log shows who called us
        # rather than always "Write-TrueHireLog".
        $caller = (Get-PSCallStack)[1]
        if ($caller -and $caller.FunctionName -and $caller.FunctionName -ne '<ScriptBlock>') {
            $Source = $caller.FunctionName
        }
    }
    if (-not $Source) { $Source = '<root>' }

    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
    $line = "{0} [{1,-5}] {2,-32} {3}" -f $ts, $Level, $Source, $Message
    try {
        Add-Content -LiteralPath (Get-TrueHireLogPath) -Value $line -Encoding UTF8 -ErrorAction Stop
        if ($Exception) {
            $exType = $Exception.GetType().FullName
            $exLine = "    -> {0}: {1}" -f $exType, $Exception.Message
            Add-Content -LiteralPath (Get-TrueHireLogPath) -Value $exLine -Encoding UTF8
            if ($Exception.StackTrace) {
                # Re-indent each line for grep-ability without breaking on
                # platforms that emit `r`n vs `n line endings.
                $stack = ($Exception.StackTrace -split "`r?`n" |
                          ForEach-Object { "    " + $_ }) -join "`n"
                Add-Content -LiteralPath (Get-TrueHireLogPath) -Value $stack -Encoding UTF8
            }
        }
    } catch {
        # Disk full, file locked, permission denied - don't cascade. The
        # console message at least leaves a footprint if the user has one.
        Write-Host ("Logging failed: " + $_.Exception.Message) -ForegroundColor Yellow
    }
}

function Invoke-SafeAction {
    <#
    Wraps an event-handler scriptblock. On exception: logs at ERROR and shows
    the message in the shell status bar (if the shell exists). Returns the
    action's value on success, $null on failure. Use for handlers where you
    want the app to keep running even if the handler throws.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][scriptblock]$Action
    )
    try {
        return & $Action
    } catch {
        Write-TrueHireLog -Level ERROR -Source $Label -Message $_.Exception.Message -Exception $_.Exception
        if (Get-Command Set-ShellStatus -ErrorAction SilentlyContinue) {
            Set-ShellStatus -Text ("{0}: {1}" -f $Label, $_.Exception.Message) -Level ERROR
        }
        return $null
    }
}

function Register-TrueHireExceptionHandlers {
    <#
    Hooks Application.DispatcherUnhandledException so any exception escaping
    any event handler is logged FATAL and captioned in the status bar, AND
    the app survives (e.Handled = $true). Must be called AFTER
    Initialize-TrueHireApp so [Application]::Current is non-null.
    #>
    $app = [System.Windows.Application]::Current
    if (-not $app) {
        Write-TrueHireLog -Level WARN -Source 'Register-TrueHireExceptionHandlers' -Message 'No Application.Current yet; dispatcher hook skipped.'
        return
    }
    # The .NET event accessor visible from PowerShell. += is C# syntax and
    # does NOT work here; use add_<EventName> with a scriptblock.
    $app.add_DispatcherUnhandledException({
        param($sender, $e)
        Write-TrueHireLog -Level FATAL -Source 'Dispatcher' -Message $e.Exception.Message -Exception $e.Exception
        if (Get-Command Set-ShellStatus -ErrorAction SilentlyContinue) {
            Set-ShellStatus -Text ("Unhandled error: " + $e.Exception.Message) -Level ERROR
        }
        $e.Handled = $true   # keep the dispatcher alive
    })
    Write-TrueHireLog -Level INFO -Source 'Register-TrueHireExceptionHandlers' -Message 'DispatcherUnhandledException hook installed.'
}

function Open-TrueHireLog {
    <#
    Bound to the "Logs" link in the status bar. Opens today's log in Notepad,
    or the logs folder in Explorer if today's file doesn't exist yet (a fresh
    session that hasn't logged anything).
    #>
    $todays = Get-TrueHireLogPath
    try {
        if (Test-Path -LiteralPath $todays) {
            Start-Process notepad.exe -ArgumentList "`"$todays`""
        } else {
            Start-Process explorer.exe -ArgumentList "`"$Script:LogDir`""
        }
    } catch {
        Write-TrueHireLog -Level WARN -Source 'Open-TrueHireLog' -Message $_.Exception.Message -Exception $_.Exception
    }
}

function Write-TrueHireSessionBanner {
    <#
    One-shot banner line so multiple runs in the same calendar day are easy
    to find with a visual sweep down the log. Called once during boot.
    #>
    $sep = '=' * 60
    Add-Content -LiteralPath (Get-TrueHireLogPath) -Value '' -Encoding UTF8
    Add-Content -LiteralPath (Get-TrueHireLogPath) -Value $sep -Encoding UTF8
    Add-Content -LiteralPath (Get-TrueHireLogPath) -Value (
        "Session start  {0}  PID {1}  PSVersion {2}" -f `
        (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $PID, $PSVersionTable.PSVersion
    ) -Encoding UTF8
    Add-Content -LiteralPath (Get-TrueHireLogPath) -Value $sep -Encoding UTF8
}
