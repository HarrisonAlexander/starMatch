<#
.SYNOPSIS
    Builds dist\TrueHire.exe - a self-extracting launcher for the TrueHire scripts.

.DESCRIPTION
    Zips the runtime source tree (TrueHire.ps1, lib, views, data, images, icon),
    stamps a content hash into build\Launcher.cs, and compiles it with the
    csc.exe that ships with .NET Framework 4.x, embedding the zip as a resource.

    At runtime the exe extracts to %LOCALAPPDATA%\TrueHire\<hash>\ (once per
    build) and launches powershell.exe against the extracted TrueHire.ps1.
    User data is written to <exe folder>\userdata\ via TRUEHIRE_DATA_ROOT.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\build\Build-Exe.ps1
#>
[CmdletBinding()]
param(
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root     = Split-Path -Parent $PSScriptRoot
if (-not $OutDir) { $OutDir = Join-Path $root 'dist' }
$include  = @('TrueHire.ps1', 'icon.ico', 'lib', 'views', 'data', 'images')
$objDir   = Join-Path $OutDir 'obj'
$zipPath  = Join-Path $objDir 'bundle.zip'
$csPath   = Join-Path $objDir 'Launcher.cs'
$exePath  = Join-Path $OutDir 'TrueHire.exe'

$csc = @(
    $env:CSC_PATH,
    'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe',
    'C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe'
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
if (-not $csc) { throw 'csc.exe not found. Install .NET Framework 4.7.2+ or set $env:CSC_PATH.' }

New-Item -ItemType Directory -Path $objDir -Force | Out-Null
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }

# --- Bundle the runtime tree ---
$zip = [System.IO.Compression.ZipFile]::Open($zipPath, 'Create')
try {
    foreach ($item in $include) {
        $full = Join-Path $root $item
        $files = if (Test-Path -LiteralPath $full -PathType Container) {
            Get-ChildItem -LiteralPath $full -Recurse -File
        } else { Get-Item -LiteralPath $full }
        foreach ($f in $files) {
            $rel = $f.FullName.Substring($root.Length + 1).Replace('\', '/')
            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $f.FullName, $rel)
        }
    }
} finally { $zip.Dispose() }

$sha  = [System.Security.Cryptography.SHA256]::Create()
$hash = [BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($zipPath))).Replace('-', '').Substring(0, 16).ToLower()
Write-Host ("Bundle: {0:N2} MB  hash={1}" -f ((Get-Item $zipPath).Length / 1MB), $hash)

# --- Stamp the hash and compile ---
$cs = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Launcher.cs')).Replace('__BUNDLE_HASH__', $hash)
[IO.File]::WriteAllText($csPath, $cs)

$fx   = Split-Path -Parent $csc
$refs = (Join-Path $fx 'System.IO.Compression.dll') + ',' + (Join-Path $fx 'System.IO.Compression.FileSystem.dll')
& $csc /nologo /target:winexe /optimize+ "/out:$exePath" "/resource:$zipPath,bundle.zip" `
    "/win32icon:$(Join-Path $root 'icon.ico')" "/reference:$refs" $csPath
if ($LASTEXITCODE -ne 0) { throw "csc.exe failed (exit $LASTEXITCODE)" }

Write-Host "Built $exePath"
