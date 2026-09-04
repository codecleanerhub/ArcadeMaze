@echo off
REM ===========================================================================
REM build_and_run.bat - Wrapper CMD per lo script PowerShell
REM
REM USO (CMD o doppio-click):
REM   build_and_run.bat              -- build + run
REM   build_and_run.bat build        -- solo build
REM   build_and_run.bat run           -- solo run
REM   build_and_run.bat clean         -- pulisci
REM
REM Lancia lo script PowerShell build_and_run.ps1 con ExecutionPolicy Bypass
REM per evitare problemi di policy aziendali.
REM ===========================================================================

setlocal

set ACTION=%1
if "%ACTION%"=="" set ACTION=all

REM Verifica che PowerShell sia installato
where powershell >nul 2>nul
if errorlevel 1 (
    echo ERROR: PowerShell non trovato. Installa Windows Management Framework.
    exit /b 1
)

REM Lancia lo script PowerShell
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0build_and_run.ps1" -Action %ACTION%
set EXITCODE=%ERRORLEVEL%

endlocal
exit /b %EXITCODE%
