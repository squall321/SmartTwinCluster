@echo off
echo ========================================
echo Python Version Detection (Windows)
echo ========================================
echo.

echo 🐍 Scanning for Python installations...
echo.

set "FOUND_VERSIONS=0"

echo [1] Checking Python Launcher (py.exe)...
py --version >nul 2>&1
if %ERRORLEVEL% equ 0 (
    echo ✅ Python Launcher available
    echo.
    echo Available versions via py launcher:
    
    py -3.13 --version >nul 2>&1
    if !ERRORLEVEL! equ 0 (
        for /f "tokens=2" %%i in ('py -3.13 --version 2^>^&1') do echo   • Python 3.13 (%%i) ⭐ RECOMMENDED
        set /a FOUND_VERSIONS+=1
    )
    
    py -3.12 --version >nul 2>&1
    if !ERRORLEVEL! equ 0 (
        for /f "tokens=2" %%i in ('py -3.12 --version 2^>^&1') do echo   • Python 3.12 (%%i)
        set /a FOUND_VERSIONS+=1
    )
    
    py -3.11 --version >nul 2>&1
    if !ERRORLEVEL! equ 0 (
        for /f "tokens=2" %%i in ('py -3.11 --version 2^>^&1') do echo   • Python 3.11 (%%i)
        set /a FOUND_VERSIONS+=1
    )
    
    py -3.10 --version >nul 2>&1
    if !ERRORLEVEL! equ 0 (
        for /f "tokens=2" %%i in ('py -3.10 --version 2^>^&1') do echo   • Python 3.10 (%%i)
        set /a FOUND_VERSIONS+=1
    )
    
    py -3.9 --version >nul 2>&1
    if !ERRORLEVEL! equ 0 (
        for /f "tokens=2" %%i in ('py -3.9 --version 2^>^&1') do echo   • Python 3.9 (%%i)
        set /a FOUND_VERSIONS+=1
    )
    
    py -3.8 --version >nul 2>&1
    if !ERRORLEVEL! equ 0 (
        for /f "tokens=2" %%i in ('py -3.8 --version 2^>^&1') do echo   • Python 3.8 (%%i)
        set /a FOUND_VERSIONS+=1
    )
) else (
    echo ❌ Python Launcher not available
)

echo.
echo [2] Checking System PATH...
python --version >nul 2>&1
if %ERRORLEVEL% equ 0 (
    for /f "tokens=2" %%i in ('python --version 2^>^&1') do echo ✅ System Python: %%i
    where python
    set /a FOUND_VERSIONS+=1
) else (
    echo ❌ No 'python' command in PATH
)

echo.
echo [3] Checking Common Installation Paths...

set "COMMON_PATHS="
set "COMMON_PATHS=%COMMON_PATHS% "C:\Python313""
set "COMMON_PATHS=%COMMON_PATHS% "C:\Python312""
set "COMMON_PATHS=%COMMON_PATHS% "C:\Python311""
set "COMMON_PATHS=%COMMON_PATHS% "C:\Python310""
set "COMMON_PATHS=%COMMON_PATHS% "%LOCALAPPDATA%\Programs\Python\Python313""
set "COMMON_PATHS=%COMMON_PATHS% "%LOCALAPPDATA%\Programs\Python\Python312""
set "COMMON_PATHS=%COMMON_PATHS% "%LOCALAPPDATA%\Programs\Python\Python311""
set "COMMON_PATHS=%COMMON_PATHS% "%LOCALAPPDATA%\Programs\Python\Python310""

for %%p in (%COMMON_PATHS%) do (
    if exist "%%~p\python.exe" (
        echo ✅ Found: %%~p\python.exe
        "%%~p\python.exe" --version 2>nul
        set /a FOUND_VERSIONS+=1
    )
)

echo.
echo ========================================
echo Summary
echo ========================================

if %FOUND_VERSIONS% gtr 0 (
    echo ✅ Found %FOUND_VERSIONS% Python installation(s)
    echo.
    echo 💡 Recommendations:
    echo   • Python 3.13 is recommended for KooCAE project
    echo   • Python 3.8+ is minimum requirement
    echo.
    echo Ready to run initialization:
    echo   .\initialize_project.bat
) else (
    echo ❌ No Python installations found!
    echo.
    echo 📥 Install Python from:
    echo   1. Official: https://python.org/downloads/
    echo   2. Microsoft Store: Search "Python 3.13"
    echo   3. Chocolatey: choco install python
    echo   4. Anaconda: https://anaconda.com/
    echo.
    echo After installation, run:
    echo   .\check_python_versions.bat
)

echo ========================================
pause
