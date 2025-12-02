@echo off
setlocal enabledelayedexpansion

echo ========================================
echo Python Environment Diagnostics
echo ========================================
echo.

set "ROOT_DIR=%~dp0"
cd /d "%ROOT_DIR%"

echo [1] Current Working Directory:
echo    %CD%
echo.

echo [2] Checking Python Interpreters:

:: Check main Scripts folder
if exist "Scripts\python.exe" (
    echo ✅ Found: .\Scripts\python.exe
    Scripts\python.exe --version 2>nul
    if !ERRORLEVEL! equ 0 (
        echo    Status: Working
    ) else (
        echo    Status: Not working
    )
) else (
    echo ❌ Not found: .\Scripts\python.exe
)

:: Check venv Scripts folder  
if exist "venv\Scripts\python.exe" (
    echo ✅ Found: .\venv\Scripts\python.exe
    venv\Scripts\python.exe --version 2>nul
    if !ERRORLEVEL! equ 0 (
        echo    Status: Working
    ) else (
        echo    Status: Not working
    )
) else (
    echo ❌ Not found: .\venv\Scripts\python.exe
)

echo.
echo [3] Current Active Python:
python --version 2>nul
if %ERRORLEVEL% equ 0 (
    echo ✅ Python command works
    where python
) else (
    echo ❌ Python command not found
)

echo.
echo [4] Environment Variables:
echo    VIRTUAL_ENV: %VIRTUAL_ENV%
echo    PATH: %PATH%

echo.
echo [5] Testing Flask Dependencies:
python -c "import flask; print(f'Flask version: {flask.__version__}')" 2>nul
if %ERRORLEVEL% equ 0 (
    echo ✅ Flask import successful
) else (
    echo ❌ Flask import failed
)

echo.
echo ========================================
echo VS Code Python Configuration
echo ========================================

:: Generate VS Code workspace settings
echo Creating .vscode\settings.json.backup...
if exist ".vscode\settings.json" copy ".vscode\settings.json" ".vscode\settings.json.backup" >nul

echo.
echo Recommended Python interpreter paths:
if exist "Scripts\python.exe" (
    echo    1. ${workspaceFolder}/Scripts/python.exe  ^(CURRENT^)
)
if exist "venv\Scripts\python.exe" (
    echo    2. ${workspaceFolder}/venv/Scripts/python.exe  ^(ALTERNATIVE^)
)

echo.
echo ========================================
echo Manual VS Code Setup Instructions:
echo ========================================
echo 1. Open VS Code
echo 2. Press Ctrl+Shift+P
echo 3. Type: "Python: Select Interpreter"
echo 4. Choose one of the interpreters listed above
echo 5. Try running Flask again
echo ========================================

pause
