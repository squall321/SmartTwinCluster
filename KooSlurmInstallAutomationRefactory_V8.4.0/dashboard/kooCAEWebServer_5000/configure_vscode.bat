@echo off
setlocal enabledelayedexpansion

echo ========================================
echo VS Code Platform Configuration (Windows)
echo ========================================
echo.

set "ROOT_DIR=%~dp0"
cd /d "%ROOT_DIR%"

echo [1/4] Platform Detection...
echo ✅ Detected Platform: Windows
echo.

echo [2/4] Configuring VS Code Settings...

:: Backup current settings if exists
if exist ".vscode\settings.json" (
    echo Creating backup of current settings...
    copy ".vscode\settings.json" ".vscode\settings.json.backup" >nul 2>&1
    echo ✅ Backup created: settings.json.backup
)

:: Copy Windows-specific settings
if exist ".vscode\settings.windows.json" (
    echo Applying Windows-specific settings...
    copy ".vscode\settings.windows.json" ".vscode\settings.json" >nul 2>&1
    if !ERRORLEVEL! equ 0 (
        echo ✅ Windows settings applied successfully
    ) else (
        echo ❌ Failed to apply Windows settings
        goto ERROR_EXIT
    )
) else (
    echo ❌ Windows settings template not found!
    goto ERROR_EXIT
)

echo.
echo [3/4] Detecting Visual Studio Installation...

:: Find Visual Studio using vswhere
set "VS_PATH="
for /f "usebackq tokens=*" %%i in (`"C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2^>nul`) do set VS_PATH=%%i

if "%VS_PATH%"=="" (
    echo ❌ Visual Studio not found!
    echo   Please install Visual Studio 2019/2022 with C++ build tools
) else (
    echo ✅ Found Visual Studio: %VS_PATH%
    
    :: Update C++ compiler paths in settings.json
    echo Updating compiler paths in VS Code settings...
    
    :: Find MSVC tools path
    for /f "delims=" %%i in ('dir "%VS_PATH%\VC\Tools\MSVC\" /b /ad 2^>nul ^| sort /r') do (
        set "MSVC_VERSION=%%i"
        goto FOUND_MSVC
    )
    
    :FOUND_MSVC
    if defined MSVC_VERSION (
        set "MSVC_PATH=%VS_PATH%\VC\Tools\MSVC\!MSVC_VERSION!\bin\Hostx64\x64"
        echo ✅ MSVC Tools: !MSVC_VERSION!
    )
)

echo.
echo [4/4] Checking Python Virtual Environment...

:: Check for virtual environment
set "PYTHON_PATH="
if exist "venvWin\Scripts\python.exe" (
    set "PYTHON_PATH=venvWin\Scripts\python.exe"
    echo ✅ Found Python: venvWin\Scripts\python.exe
) else if exist "Scripts\python.exe" (
    set "PYTHON_PATH=Scripts\python.exe"
    echo ✅ Found Python: Scripts\python.exe
) else (
    echo ❌ Python virtual environment not found!
    echo   Expected locations:
    echo     - venvWin\Scripts\python.exe
    echo     - Scripts\python.exe
    echo.
    echo   Create virtual environment:
    echo     python -m venv venvWin
)

echo.
echo ========================================
echo Configuration Summary
echo ========================================
echo Platform: Windows
echo VS Code Settings: ✅ Applied
if defined VS_PATH (
    echo Visual Studio: ✅ Found
    echo   Path: %VS_PATH%
) else (
    echo Visual Studio: ❌ Not Found
)
if defined PYTHON_PATH (
    echo Python Env: ✅ Found
    echo   Path: %PYTHON_PATH%
) else (
    echo Python Env: ❌ Not Found
)
echo ========================================
echo.

if defined VS_PATH if defined PYTHON_PATH (
    echo 🎉 Configuration completed successfully!
    echo    VS Code is now configured for Windows development.
    echo.
    echo Next steps:
    echo   1. Open this folder in VS Code
    echo   2. Press Ctrl+Shift+P
    echo   3. Run "Python: Select Interpreter"
    echo   4. Choose: %PYTHON_PATH%
    echo   5. Press F5 to start debugging
) else (
    echo ⚠️  Configuration completed with warnings.
    echo   Please install missing components and run again.
)

goto END

:ERROR_EXIT
echo ❌ Configuration failed!
echo Please check the errors above and try again.
exit /b 1

:END
echo.
pause
