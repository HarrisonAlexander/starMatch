@echo off
rem ---------------------------------------------------------------
rem  TrueHire - portable launcher
rem
rem  Prepends the bundled .\Modules folder to PSModulePath so the
rem  Analytics "Export Report" button (ImportExcel) works on a box
rem  that has never installed the module from PSGallery, then runs
rem  TrueHire.ps1 with ExecutionPolicy Bypass for the current
rem  process only (no system change).
rem ---------------------------------------------------------------
setlocal
set "ROOT=%~dp0"
set "PSModulePath=%ROOT%Modules;%PSModulePath%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%TrueHire.ps1" %*
endlocal
