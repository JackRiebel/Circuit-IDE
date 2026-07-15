@echo off
setlocal enabledelayedexpansion

title Circuit IDE - Windows Installer

echo.
echo  ======================================================
echo           Circuit IDE - Windows Installer
echo  ======================================================
echo.

:: --------------------------------------------------------
:: Check Python
:: --------------------------------------------------------

echo  [1/3] Checking prerequisites...
echo.

where python >nul 2>&1
if %errorlevel% neq 0 (
    where python3 >nul 2>&1
    if %errorlevel% neq 0 (
        echo  [ERROR] Python is not installed or not in PATH.
        echo.
        echo          Download Python 3.11+: https://www.python.org/downloads/
        echo          IMPORTANT: Check "Add Python to PATH" during install.
        echo.
        goto :fail
    )
    set PYTHON=python3
) else (
    set PYTHON=python
)

:: Check Python version
for /f "tokens=2" %%v in ('%PYTHON% --version 2^>^&1') do set PYVER=%%v
echo    Python %PYVER% ................. OK

:: Check pip
%PYTHON% -m pip --version >nul 2>&1
if %errorlevel% neq 0 (
    echo  [ERROR] pip is not available.
    echo          Run: %PYTHON% -m ensurepip --upgrade
    goto :fail
)
echo    pip ........................... OK

:: Check Git (optional)
where git >nul 2>&1
if %errorlevel% neq 0 (
    echo    Git ........................... NOT FOUND (optional, needed for Git features)
) else (
    echo    Git ........................... OK
)

echo.

:: --------------------------------------------------------
:: Install dependencies
:: --------------------------------------------------------

echo  [2/3] Installing dependencies...
echo.

%PYTHON% -m pip install --upgrade pip >nul 2>&1

echo    Installing PySide6, httpx, pygments...
%PYTHON% -m pip install PySide6>=6.6.0 httpx>=0.25.0 pygments>=2.17.0 certifi>=2023.0.0
if %errorlevel% neq 0 (
    echo.
    echo  [ERROR] Failed to install dependencies.
    echo          Try running this script as Administrator.
    goto :fail
)

echo.
echo    Installing optional dependencies...
%PYTHON% -m pip install anthropic>=0.18.0 2>nul
if %errorlevel% neq 0 (
    echo    anthropic ..................... SKIPPED (optional, for Claude support)
) else (
    echo    anthropic ..................... OK
)

echo.

:: --------------------------------------------------------
:: Create launch script
:: --------------------------------------------------------

echo  [3/3] Creating launcher...
echo.

:: Create run-circuit-ide.bat in the project root
set "SCRIPT_DIR=%~dp0"
(
echo @echo off
echo title Circuit IDE
echo cd /d "%SCRIPT_DIR%"
echo %PYTHON% -m circuit_ide_gui.main %%*
echo if %%errorlevel%% neq 0 pause
) > "%SCRIPT_DIR%run-circuit-ide.bat"

echo    Created: run-circuit-ide.bat
echo.

:: --------------------------------------------------------
:: Done
:: --------------------------------------------------------

echo  ======================================================
echo              Installation Complete!
echo  ======================================================
echo.
echo  To launch Circuit IDE:
echo.
echo    Option 1:  Double-click  run-circuit-ide.bat
echo    Option 2:  Run:  %PYTHON% -m circuit_ide_gui.main
echo.
echo  On first launch, open Settings to configure your
echo  AI provider (Cisco Circuit or Claude/Anthropic).
echo.

set /p "LAUNCH=  Launch Circuit IDE now? (Y/n): "
if /i "%LAUNCH%"=="n" goto :done

echo.
echo  Launching Circuit IDE...
cd /d "%SCRIPT_DIR%"
start "" %PYTHON% -m circuit_ide_gui.main

goto :done

:fail
echo.
echo  Installation aborted.
echo.
pause
exit /b 1

:done
echo.
pause
exit /b 0
