@echo off
setlocal

:: Get the current directory and strip the trailing backslash to prevent escaping quotes
set "CURRENT_DIR=%~dp0"
if "%CURRENT_DIR:~-1%"=="\" set "CURRENT_DIR=%CURRENT_DIR:~0,-1%"

:: Run PowerShell with the safe, unescaped directory path
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%CURRENT_DIR%\install.ps1" -SourceDirectory "%CURRENT_DIR%" %*
set "EXIT_CODE=%ERRORLEVEL%"

:: Keep the window open if the script fails or returns an error
if %EXIT_CODE% neq 0 (
    echo.
    echo Installation failed with exit code %EXIT_CODE%.
    pause
)

exit /b %EXIT_CODE%
