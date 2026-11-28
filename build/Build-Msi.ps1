<#
.SYNOPSIS
    Builds dist\TrueHire-<version>.msi - an installer that supports both
    per-user and per-machine installs.

.DESCRIPTION
    Stages the runtime tree (TrueHire.ps1, icon.ico, lib, views, data, images,
    LICENSE) into dist\obj\msi-stage, adds installed.flag and a small
    TrueHire.exe launcher compiled from build\AppLauncher.cs, then runs WiX v5
    against build\TrueHire.wxs.

    Requires the .NET SDK plus the WiX v5 tool and UI extension:
        dotnet tool install --global wix --version 5.0.2
        wix extension add -g WixToolset.UI.wixext/5.0.2

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\build\Build-Msi.ps1 -Version 1.0.0
#>
[CmdletBinding()]
param(
    [string]$Version = '1.0.0',
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
if (-not $OutDir) { $OutDir = Join-Path $root 'dist' }
$objDir   = Join-Path $OutDir 'obj'
$stage    = Join-Path $objDir 'msi-stage'
$rtfPath  = Join-Path $objDir 'License.rtf'
$msiPath  = Join-Path $OutDir ('TrueHire-{0}.msi' -f $Version)
$include  = @('TrueHire.ps1', 'icon.ico', 'LICENSE', 'lib', 'views', 'data', 'images')

if (-not (Get-Command wix -ErrorAction SilentlyContinue)) {
    throw 'wix not found. Run: dotnet tool install --global wix --version 5.0.2'
}
$csc = @(
    $env:CSC_PATH,
    'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe',
    'C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe'
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
if (-not $csc) { throw 'csc.exe not found. Install .NET Framework 4.7.2+ or set $env:CSC_PATH.' }

# --- Stage the install tree ---
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage -Force | Out-Null
foreach ($item in $include) {
    Copy-Item -LiteralPath (Join-Path $root $item) -Destination $stage -Recurse
}
Set-Content -LiteralPath (Join-Path $stage 'installed.flag') -Value 'Installed by TrueHire.msi' -Encoding ASCII

& $csc /nologo /target:winexe /optimize+ "/out:$(Join-Path $stage 'TrueHire.exe')" `
    "/win32icon:$(Join-Path $root 'icon.ico')" (Join-Path $PSScriptRoot 'AppLauncher.cs')
if ($LASTEXITCODE -ne 0) { throw "csc.exe failed (exit $LASTEXITCODE)" }

# --- License page: plain LICENSE text as minimal RTF ---
$lic = [IO.File]::ReadAllText((Join-Path $root 'LICENSE'))
$lic = $lic.Replace('\', '\\').Replace('{', '\{').Replace('}', '\}') -replace "\r?\n", "\par`r`n"
[IO.File]::WriteAllText($rtfPath, "{\rtf1\ansi\deff0{\fonttbl{\f0 Segoe UI;}}\fs18`r`n$lic`r`n}", [Text.Encoding]::ASCII)

# --- Build ---
& wix build (Join-Path $PSScriptRoot 'TrueHire.wxs') `
    -ext WixToolset.UI.wixext `
    -arch x64 `
    -d "Version=$Version" -d "StageDir=$stage" -d "LicenseRtf=$rtfPath" `
    -o $msiPath
if ($LASTEXITCODE -ne 0) { throw "wix build failed (exit $LASTEXITCODE)" }

Remove-Item -LiteralPath ([IO.Path]::ChangeExtension($msiPath, '.wixpdb')) -ErrorAction SilentlyContinue
Write-Host "Built $msiPath"
