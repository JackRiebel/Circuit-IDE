@echo off
setlocal enabledelayedexpansion

title Circuit IDE - Windows Build

echo.
echo  ======================================================
echo             Circuit IDE - Windows Builder
echo  ======================================================
echo.

:: --------------------------------------------------------
:: Check prerequisites
:: --------------------------------------------------------

echo  [1/4] Checking prerequisites...
echo.

:: Check Flutter
where flutter >nul 2>&1
if %errorlevel% neq 0 (
    echo  [ERROR] Flutter is not installed or not in PATH.
    echo.
    echo          Install Flutter: https://docs.flutter.dev/get-started/install/windows
    echo          Then add it to your PATH and restart this script.
    echo.
    goto :fail
)

:: Show Flutter version
for /f "tokens=2" %%v in ('flutter --version 2^>nul ^| findstr /c:"Flutter"') do (
    echo    Flutter %%v .................. OK
)

:: Check Git
where git >nul 2>&1
if %errorlevel% neq 0 (
    echo  [ERROR] Git is not installed or not in PATH.
    echo          Install Git: https://git-scm.com/download/win
    goto :fail
)
echo    Git ........................... OK

:: Check Visual Studio / C++ build tools
where cl >nul 2>&1
if %errorlevel% neq 0 (
    :: cl.exe not in PATH - check if VS is installed via vswhere
    set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
    if exist "!VSWHERE!" (
        for /f "tokens=*" %%i in ('"!VSWHERE!" -latest -property installationPath 2^>nul') do (
            echo    Visual Studio ................. OK  ^(%%i^)
            set "VS_FOUND=1"
        )
    )
    if not defined VS_FOUND (
        echo  [WARNING] Visual Studio with C++ Desktop workload not detected.
        echo            Install Visual Studio 2022 with "Desktop development with C++".
        echo            https://visualstudio.microsoft.com/downloads/
        echo.
        echo            Or install just the Build Tools:
        echo            https://visualstudio.microsoft.com/visual-cpp-build-tools/
        echo.
        set /p "CONTINUE=  Continue anyway? (y/N): "
        if /i not "!CONTINUE!"=="y" goto :fail
    )
) else (
    echo    C++ Build Tools .............. OK
)

:: Check Windows desktop is enabled in Flutter
flutter config --list 2>nul | findstr /c:"enable-windows-desktop" | findstr /c:"true" >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo  Enabling Windows desktop support...
    flutter config --enable-windows-desktop
)
echo    Windows desktop support ....... OK
echo.

:: --------------------------------------------------------
:: Select build mode
:: --------------------------------------------------------

echo  [2/4] Select build mode:
echo.
echo    1) Release   (Optimized, smaller, recommended)
echo    2) Debug     (Includes debug symbols)
echo    3) Profile   (Performance profiling)
echo.
set /p "MODE=  Select mode [1]: "
if "%MODE%"=="" set MODE=1

if "%MODE%"=="1" (
    set BUILD_MODE=release
    set BUILD_FLAG=--release
) else if "%MODE%"=="2" (
    set BUILD_MODE=debug
    set BUILD_FLAG=--debug
) else if "%MODE%"=="3" (
    set BUILD_MODE=profile
    set BUILD_FLAG=--profile
) else (
    echo  Invalid choice, defaulting to Release.
    set BUILD_MODE=release
    set BUILD_FLAG=--release
)

echo.
echo  Building in %BUILD_MODE% mode...
echo.

:: --------------------------------------------------------
:: Get dependencies and build
:: --------------------------------------------------------

echo  [3/4] Fetching dependencies...
echo.

cd /d "%~dp0circuit-ide"
if %errorlevel% neq 0 (
    echo  [ERROR] Could not find circuit-ide directory.
    echo          Make sure this script is in the Circuit-IDE root folder.
    goto :fail
)

flutter pub get
if %errorlevel% neq 0 (
    echo.
    echo  [ERROR] Failed to fetch dependencies.
    goto :fail
)

echo.
echo  [4/4] Building Windows application...
echo.

flutter build windows %BUILD_FLAG% 2>&1
if %errorlevel% neq 0 (
    echo.
    echo  [ERROR] Build failed. Check the output above for details.
    echo.
    echo  Common fixes:
    echo    - Run from "Developer Command Prompt for VS 2022"
    echo    - Run: flutter doctor -v
    echo    - Run: flutter clean  then try again
    goto :fail
)

:: --------------------------------------------------------
:: Done
:: --------------------------------------------------------

set "OUTPUT_DIR=%cd%\build\windows\x64\runner\%BUILD_MODE%"
if not exist "%OUTPUT_DIR%" (
    set "OUTPUT_DIR=%cd%\build\windows\runner\%BUILD_MODE%"
)

echo.
echo  ======================================================
echo              Build Successful!
echo  ======================================================
echo.
echo  Output: %OUTPUT_DIR%
echo.
echo  To run Circuit IDE:
echo    %OUTPUT_DIR%\circuit_ide.exe
echo.

set /p "LAUNCH=  Launch Circuit IDE now? (Y/n): "
if /i "%LAUNCH%"=="n" goto :done

if exist "%OUTPUT_DIR%\circuit_ide.exe" (
    echo.
    echo  Launching Circuit IDE...
    start "" "%OUTPUT_DIR%\circuit_ide.exe"
) else (
    echo  [WARNING] Could not find circuit_ide.exe at expected path.
    echo            Check the build output directory manually.
)

goto :done

:fail
echo.
echo  Build aborted.
echo.
pause
exit /b 1

:done
echo.
pause
exit /b 0
