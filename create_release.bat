@echo off
setlocal

:: ============================================================
:: FS25 AutomaticBaleStorage - Release Archive Builder
:: ============================================================

set MOD_NAME=FS25_AutomaticBaleStorage
set SCRIPT_DIR=%~dp0
set SCRIPT_DIR=%SCRIPT_DIR:~0,-1%

set ARCHIVE_NAME=%MOD_NAME%.zip
set OUTPUT_PATH=%SCRIPT_DIR%\%ARCHIVE_NAME%

echo ============================================================
echo  Building release: %ARCHIVE_NAME%
echo ============================================================

:: Remove existing archive if present
if exist "%OUTPUT_PATH%" (
    echo Removing existing %ARCHIVE_NAME%...
    del "%OUTPUT_PATH%"
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%\create_release.ps1" -Src "%SCRIPT_DIR%" -Dst "%OUTPUT_PATH%"

if exist "%OUTPUT_PATH%" (
    echo.
    echo SUCCESS: %ARCHIVE_NAME% created.
    for %%F in ("%OUTPUT_PATH%") do echo Size: %%~zF bytes
) else (
    echo.
    echo ERROR: Archive was not created.
    exit /b 1
)

echo.
pause
