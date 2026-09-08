@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================================
REM MedTRx Database Bloat & Prescription Diagnostic Scanner (1-Click Runner)
REM ============================================================================

title MedTRx DB Bloat Scanner
color 0B

echo ============================================================================
echo         MedTRx Database Bloat & Data Health Diagnostic Scanner
echo ============================================================================
echo.

set "SCRIPT_DIR=%~dp0"
set "SCANNER_PS1=%SCRIPT_DIR%db_scanner.ps1"

if not exist "%SCANNER_PS1%" (
    echo [ERROR] db_scanner.ps1 not found in "%SCRIPT_DIR%"
    pause
    exit /b 1
)

REM Execute PowerShell scanner
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCANNER_PS1%"

set "EXIT_CODE=%ERRORLEVEL%"
exit /b %EXIT_CODE%
