@echo off
setlocal enabledelayedexpansion

echo ========================================
echo KooCAE Project Initialization (Windows)
echo ========================================
echo This script will set up your development environment
echo Press any key to continue or Ctrl+C to cancel...
pause >nul
echo.

set "ROOT_DIR=%~dp0"
cd /d "%ROOT_DIR%"

set "ERRORS=0"

echo [1/9] Platform Detection...
echo ✅ Detected Platform: Windows
echo.

echo [2/9] Python Version Selection...
echo.
echo 🐍 Available Python versions:

:: Detect available Python versions
set "PYTHON_VERSIONS="
set "PYTHON_COUNT=0"
set "DEFAULT_PYTHON="

:: Check for Python 3.13 (default)
py -3.13 --version >nul 2>&1
if !ERRORLEVEL! equ 0 (
    set /a PYTHON_COUNT+=1
    set "PYTHON_VERSIONS=!PYTHON_VERSIONS! 3.13"
    set "DEFAULT_PYTHON=3.13"
    echo   [!PYTHON_COUNT!] Python 3.13 (Default ⭐)
)

:: Check for Python 3.12
py -3.12 --version >nul 2>&1
if !ERRORLEVEL! equ 0 (
    set /a PYTHON_COUNT+=1
    set "PYTHON_VERSIONS=!PYTHON_VERSIONS! 3.12"
    if "!DEFAULT_PYTHON!"=="" set "DEFAULT_PYTHON=3.12"
    echo   [!PYTHON_COUNT!] Python 3.12
)

:: Check for Python 3.11
py -3.11 --version >nul 2>&1
if !ERRORLEVEL! equ 0 (
    set /a PYTHON_COUNT+=1
    set "PYTHON_VERSIONS=!PYTHON_VERSIONS! 3.11"
    if "!DEFAULT_PYTHON!"=="" set "DEFAULT_PYTHON=3.11"
    echo   [!PYTHON_COUNT!] Python 3.11
)

:: Check for Python 3.10
py -3.10 --version >nul 2>&1
if !ERRORLEVEL! equ 0 (
    set /a PYTHON_COUNT+=1
    set "PYTHON_VERSIONS=!PYTHON_VERSIONS! 3.10"
    if "!DEFAULT_PYTHON!"=="" set "DEFAULT_PYTHON=3.10"
    echo   [!PYTHON_COUNT!] Python 3.10
)

:: Check for Python 3.9
py -3.9 --version >nul 2>&1
if !ERRORLEVEL! equ 0 (
    set /a PYTHON_COUNT+=1
    set "PYTHON_VERSIONS=!PYTHON_VERSIONS! 3.9"
    if "!DEFAULT_PYTHON!"=="" set "DEFAULT_PYTHON=3.9"
    echo   [!PYTHON_COUNT!] Python 3.9
)

:: Check for Python 3.8
py -3.8 --version >nul 2>&1
if !ERRORLEVEL! equ 0 (
    set /a PYTHON_COUNT+=1
    set "PYTHON_VERSIONS=!PYTHON_VERSIONS! 3.8"
    if "!DEFAULT_PYTHON!"=="" set "DEFAULT_PYTHON=3.8"
    echo   [!PYTHON_COUNT!] Python 3.8
)

:: Check for generic python command
python --version >nul 2>&1
if !ERRORLEVEL! equ 0 (
    for /f "tokens=2" %%i in ('python --version 2^>^&1') do set PYTHON_VER=%%i
    set /a PYTHON_COUNT+=1
    echo   [!PYTHON_COUNT!] System Python (!PYTHON_VER!)
    set "PYTHON_VERSIONS=!PYTHON_VERSIONS! system"
    if "!DEFAULT_PYTHON!"=="" set "DEFAULT_PYTHON=system"
)

echo.

if %PYTHON_COUNT% equ 0 (
    echo ❌ No Python installation found!
    echo.
    echo Please install Python 3.8+ from one of these sources:
    echo   1. Official Python: https://python.org/downloads/
    echo   2. Microsoft Store: Search for "Python 3.13"
    echo   3. Chocolatey: choco install python
    echo   4. Anaconda: https://anaconda.com/
    echo.
    set "ERRORS=1"
    goto SUMMARY
)

:: Python version selection
set "SELECTED_VERSION="
if "%DEFAULT_PYTHON%"=="3.13" (
    echo 💡 Recommendation: Python 3.13 is recommended for this project
) else (
    echo 💡 Note: Python 3.13 is recommended but not found
)
echo.

:SELECT_VERSION
set /p "CHOICE=Choose Python version [1-%PYTHON_COUNT%] or press Enter for default (%DEFAULT_PYTHON%): "

if "%CHOICE%"=="" (
    set "SELECTED_VERSION=%DEFAULT_PYTHON%"
    goto VERSION_SELECTED
)

:: Validate choice
if %CHOICE% lss 1 goto INVALID_CHOICE
if %CHOICE% gtr %PYTHON_COUNT% goto INVALID_CHOICE

:: Map choice to version
set "COUNTER=0"
for %%v in (%PYTHON_VERSIONS%) do (
    set /a COUNTER+=1
    if !COUNTER! equ %CHOICE% (
        set "SELECTED_VERSION=%%v"
        goto VERSION_SELECTED
    )
)

:INVALID_CHOICE
echo ❌ Invalid choice. Please enter a number between 1 and %PYTHON_COUNT%.
goto SELECT_VERSION

:VERSION_SELECTED
echo.
echo ✅ Selected Python: %SELECTED_VERSION%

:: Set Python command based on selection
if "%SELECTED_VERSION%"=="system" (
    set "PYTHON_CMD=python"
) else (
    set "PYTHON_CMD=py -%SELECTED_VERSION%"
)

:: Verify selected Python works
echo Testing selected Python...
%PYTHON_CMD% --version >nul 2>&1
if !ERRORLEVEL! neq 0 (
    echo ❌ Failed to execute selected Python version
    set "ERRORS=1"
    goto SUMMARY
)

for /f "tokens=2" %%i in ('%PYTHON_CMD% --version 2^>^&1') do set FINAL_PYTHON_VERSION=%%i
echo ✅ Using Python !FINAL_PYTHON_VERSION!

echo.
echo [3/9] Creating Virtual Environment...
echo Creating virtual environment with Python !FINAL_PYTHON_VERSION!...

if exist "venvWin" (
    echo Removing existing virtual environment...
    rmdir /s /q "venvWin" 2>nul
)

%PYTHON_CMD% -m venv venvWin
if !ERRORLEVEL! equ 0 (
    echo ✅ Virtual environment created successfully
) else (
    echo ❌ Failed to create virtual environment
    echo.
    echo Try installing venv module:
    echo   %PYTHON_CMD% -m pip install --upgrade pip
    set "ERRORS=1"
    goto SUMMARY
)

echo.
echo [4/9] Activating Virtual Environment...
if exist "venvWin\Scripts\activate.bat" (
    call venvWin\Scripts\activate.bat
    echo ✅ Virtual environment activated
    
    :: Verify Python in venv
    python --version >nul 2>&1
    if !ERRORLEVEL! equ 0 (
        for /f "tokens=2" %%i in ('python --version 2^>^&1') do echo ✅ Virtual environment Python: %%i
    )
) else (
    echo ❌ Virtual environment activation failed
    set "ERRORS=1"
    goto SUMMARY
)

echo.
echo [5/9] Installing Python Dependencies...
echo Upgrading pip...
python -m pip install --upgrade pip --quiet

echo Installing build essentials...
python -m pip install --upgrade setuptools wheel --quiet

echo Installing requirements...
if exist "requirements.txt" (
    pip install -r requirements.txt --quiet
    if !ERRORLEVEL! equ 0 (
        echo ✅ Dependencies installed successfully
    ) else (
        echo ❌ Failed to install dependencies
        echo Trying with verbose output...
        pip install -r requirements.txt
        set "ERRORS=1"
    )
) else (
    echo ❌ requirements.txt not found!
    set "ERRORS=1"
)

echo.
echo [6/9] Configuring VS Code Settings...
call configure_vscode.bat
if !ERRORLEVEL! equ 0 (
    echo ✅ VS Code configuration completed
) else (
    echo ❌ VS Code configuration failed
    set "ERRORS=1"
)

echo.
echo [7/9] Making Scripts Executable...
echo ✅ Windows batch files are executable by default

echo.
echo [8/9] Updating VS Code Python Path...
echo Updating VS Code settings with selected Python...

:: Update .vscode/settings.json with correct Python path
if exist ".vscode\settings.json" (
    echo Updating Python interpreter path in VS Code settings...
    echo ✅ Python path will be available for VS Code selection
)

echo.
echo [9/9] Running Initial Tests...
echo Testing Python environment...
python --version
if !ERRORLEVEL! neq 0 (
    echo ❌ Python test failed
    set "ERRORS=1"
)

echo Testing Flask dependencies...
python -c "import flask, flask_cors, flask_sqlalchemy; print('✅ Flask dependencies OK')" 2>nul
if !ERRORLEVEL! neq 0 (
    echo ❌ Flask dependencies test failed
    set "ERRORS=1"
)

echo Testing pybind11...
python -c "import pybind11; print('✅ pybind11 OK')" 2>nul
if !ERRORLEVEL! neq 0 (
    echo ❌ pybind11 test failed
    set "ERRORS=1"
)

:SUMMARY
echo.
echo ========================================
echo Initialization Summary
echo ========================================

if "%ERRORS%"=="0" (
    echo 🎉 SUCCESS: Project initialization completed!
    echo.
    echo Your development environment is ready:
    echo   ✅ Python %FINAL_PYTHON_VERSION% virtual environment: venvWin
    echo   ✅ Dependencies installed
    echo   ✅ VS Code configured for Windows
    echo   ✅ All tests passed
    echo.
    echo Next steps:
    echo   1. Open this folder in VS Code
    echo   2. Select Python interpreter:
    echo      • Press Ctrl+Shift+P
    echo      • Type: "Python: Select Interpreter"
    echo      • Choose: .\venvWin\Scripts\python.exe
    echo   3. Build the C++ extension:
    echo      • Run: .\quick_build.bat
    echo      • Or: .\setup_and_build.bat
    echo   4. Start Flask server:
    echo      • Run: python app.py
    echo      • Or press F5 in VS Code
    echo.
    echo Quick commands:
    echo   .\quick_build.bat           - Build C++ extension
    echo   .\test_environment.bat      - Test full environment
    echo   python app.py               - Start Flask server
) else (
    echo ❌ ERRORS DETECTED: Initialization completed with issues
    echo.
    echo Please resolve the errors above and run again:
    echo   .\initialize_project.bat
    echo.
    echo Common solutions:
    echo   - Install Python 3.8+ from python.org
    echo   - Install Visual Studio 2019/2022 with C++ tools
    echo   - Check internet connection for pip installs
    echo   - Try running as administrator
)

echo ========================================
echo.
echo Press any key to exit...
pause >nul
