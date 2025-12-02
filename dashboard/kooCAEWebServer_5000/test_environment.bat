@echo off
setlocal enabledelayedexpansion

echo ========================================
echo KooCAE Development Environment Test
echo ========================================
echo.

set "ROOT_DIR=%~dp0"
cd /d "%ROOT_DIR%"

set "ALL_TESTS_PASSED=1"

echo [1/6] Testing Python Environment...
python -c "import sys; print(f'Python version: {sys.version}')" 2>nul
if %ERRORLEVEL% neq 0 (
    echo ❌ Python not found or not working
    set "ALL_TESTS_PASSED=0"
) else (
    echo ✅ Python environment OK
)

echo [2/6] Testing Python Dependencies...
python -c "import flask, flask_cors, flask_sqlalchemy; print('Flask dependencies OK')" 2>nul
if %ERRORLEVEL% neq 0 (
    echo ❌ Flask dependencies missing
    echo    Run: pip install -r requirements.txt
    set "ALL_TESTS_PASSED=0"
) else (
    echo ✅ Flask dependencies OK
)

echo [3/6] Testing Python Extension Module...
if exist "services\KooCAE.pyd" (
    echo ✅ KooCAE.pyd exists
    python -c "import sys; sys.path.insert(0, 'services'); import KooCAE; print('KooCAE module import OK')" 2>nul
    if !ERRORLEVEL! equ 0 (
        echo ✅ KooCAE module loads successfully
    ) else (
        echo ❌ KooCAE module import failed
        set "ALL_TESTS_PASSED=0"
    )
) else (
    echo ❌ KooCAE.pyd not found
    echo    Run: .\setup_and_build.bat
    set "ALL_TESTS_PASSED=0"
)

echo [4/6] Testing C++ Test Runner...
if exist "build\cpp_only\Debug\test_runner.exe" (
    echo ✅ Debug test_runner.exe exists
) else (
    echo ❌ Debug test_runner.exe not found
    echo    Configure and build C++ project in VS Code
    set "ALL_TESTS_PASSED=0"
)

if exist "build\cpp_test\test.k" (
    echo ✅ Test K-file exists
) else (
    echo ❌ Test K-file not found
    set "ALL_TESTS_PASSED=0"
)

echo [5/6] Testing Visual Studio Environment...
for /f "usebackq tokens=*" %%i in (`"C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2^>nul`) do set VS_PATH=%%i
if "%VS_PATH%"=="" (
    echo ❌ Visual Studio 2022 not found
    echo    Install Visual Studio 2022 with C++ build tools
    set "ALL_TESTS_PASSED=0"
) else (
    echo ✅ Visual Studio 2022 found: %VS_PATH%
)

echo [6/6] Testing VS Code Configuration...
if exist ".vscode\launch.json" (
    echo ✅ VS Code launch configuration exists
) else (
    echo ❌ VS Code launch configuration missing
    set "ALL_TESTS_PASSED=0"
)

if exist ".vscode\tasks.json" (
    echo ✅ VS Code tasks configuration exists
) else (
    echo ❌ VS Code tasks configuration missing
    set "ALL_TESTS_PASSED=0"
)

echo.
echo ========================================
if "%ALL_TESTS_PASSED%"=="1" (
    echo ✅ ALL TESTS PASSED!
    echo.
    echo 🚀 Ready to develop! You can now:
    echo    1. Press F5 in VS Code for Flask debugging
    echo    2. Press F5 in VS Code for C++ debugging  
    echo    3. Use Command Palette tasks for building
    echo.
    echo 📖 See DEVELOPMENT_GUIDE.md for detailed instructions
) else (
    echo ❌ SOME TESTS FAILED!
    echo.
    echo 🔧 Fix the issues above and run this test again.
    echo.
    echo Quick fixes:
    echo    - Python deps: pip install -r requirements.txt
    echo    - Python extension: .\setup_and_build.bat
    echo    - C++ build: Open VS Code and run configure task
)
echo ========================================
echo.

pause
