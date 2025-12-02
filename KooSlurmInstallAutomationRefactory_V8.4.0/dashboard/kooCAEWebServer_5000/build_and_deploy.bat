@echo off
setlocal enabledelayedexpansion

echo ========================================
echo KooCAE Auto Build and Deploy Script
echo ========================================
echo.

:: Save current directory
set "ROOT_DIR=%~dp0"
cd /d "%ROOT_DIR%"

:: ==============================
:: 1. Find Visual Studio BuildTools
:: ==============================

echo [1/8] Searching for Visual Studio BuildTools...

:: Find latest installation path using vswhere
for /f "usebackq tokens=*" %%i in (`"C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2^>nul`) do set VS_PATH=%%i

if "%VS_PATH%"=="" (
    echo ERROR: Visual Studio Build Tools not found!
    echo Please install Visual Studio 2019/2022 with C++ build tools.
    pause
    exit /b 1
)

echo SUCCESS: Found Visual Studio at: %VS_PATH%
echo.

:: ==============================
:: 2. Set up MSVC build environment
:: ==============================

echo [2/8] Setting up MSVC build environment...
call "%VS_PATH%\VC\Auxiliary\Build\vcvarsall.bat" x64 >nul 2>&1

if %ERRORLEVEL% neq 0 (
    echo ERROR: Failed to setup MSVC environment!
    pause
    exit /b 1
)

echo SUCCESS: MSVC x64 environment ready
echo.

:: ==============================
:: 3. Install required Python packages
:: ==============================

echo [3/8] Installing required Python packages...

:: Upgrade pip first
echo Upgrading pip...
python -m pip install --upgrade pip

:: Install setuptools
echo Installing setuptools...
pip install setuptools

if %ERRORLEVEL% neq 0 (
    echo ERROR: Failed to install setuptools!
    pause
    exit /b 1
)

:: Install wheel (helpful for builds)
echo Installing wheel...
pip install wheel

:: Install pybind11
echo Installing pybind11...
pip install pybind11

if %ERRORLEVEL% neq 0 (
    echo ERROR: Failed to install pybind11!
    pause
    exit /b 1
)

:: Install numpy (often needed)
echo Installing numpy...
pip install numpy

echo SUCCESS: Python packages installed
echo.

:: ==============================
:: 4. Check Python environment
:: ==============================

echo [4/8] Verifying Python environment...

:: Verify all packages
python -c "import setuptools; print('setuptools:', setuptools.__version__)" 2>nul
if %ERRORLEVEL% neq 0 (
    echo ERROR: setuptools not properly installed!
    pause
    exit /b 1
)

python -c "import pybind11; print('pybind11:', pybind11.__version__)" 2>nul
if %ERRORLEVEL% neq 0 (
    echo ERROR: pybind11 not properly installed!
    pause
    exit /b 1
)

echo SUCCESS: Python environment verified
echo.

:: ==============================
:: 5. Clean previous builds
:: ==============================

echo [5/8] Cleaning previous builds...

cd build

:: Clean old .pyd files
if exist "KooCAE*.pyd" (
    echo Cleaning old .pyd files...
    del /q KooCAE*.pyd 2>nul
)

:: Check and clean CMake cache conflicts
if exist "CMakeCache.txt" (
    findstr /c:"squal" CMakeCache.txt >nul 2>&1
    if !ERRORLEVEL! equ 0 (
        echo Cleaning conflicting CMake cache...
        del /f CMakeCache.txt 2>nul
        if exist CMakeFiles rmdir /s /q CMakeFiles 2>nul
    )
)

:: Clean Python build artifacts
if exist "build" rmdir /s /q build 2>nul
if exist "*.egg-info" rmdir /s /q *.egg-info 2>nul

echo SUCCESS: Build environment cleaned
echo.

:: ==============================
:: 6. Build C++ extension module
:: ==============================

echo [6/8] Building C++ extension module...
echo Running: python setup.py build_ext --inplace

python setup.py build_ext --inplace

if %ERRORLEVEL% neq 0 (
    echo ERROR: C++ build failed!
    echo.
    echo Trying alternative build method...
    python setup.py build_ext --inplace --force
    
    if !ERRORLEVEL! neq 0 (
        echo ERROR: Alternative build also failed!
        echo Please check the error messages above.
        pause
        exit /b 1
    )
)

echo SUCCESS: C++ build completed
echo.

:: ==============================
:: 7. Prepare services folder
:: ==============================

echo [7/8] Preparing services folder...

cd "%ROOT_DIR%"

if not exist "services" (
    echo Creating services folder...
    mkdir services
)

echo SUCCESS: Services folder ready
echo.

:: ==============================
:: 8. Deploy built module
:: ==============================

echo [8/8] Deploying built module...

cd build

set "COPIED=0"
set "PYD_FILE="

:: Find KooCAE .pyd files
echo Looking for built .pyd files...
dir KooCAE*.pyd 2>nul

for %%f in (KooCAE*.pyd) do (
    set "PYD_FILE=%%f"
    echo Found module: %%f
    
    echo Copying: %%f to ..\services\KooCAE.pyd
    copy /Y "%%f" "..\services\KooCAE.pyd" >nul
    
    if !ERRORLEVEL! equ 0 (
        set "COPIED=1"
        echo SUCCESS: Module copied successfully
    ) else (
        echo ERROR: Module copy failed
    )
)

:: Copy .pyi stub file if exists
if exist "KooCAE.pyi" (
    echo Copying stub file: KooCAE.pyi
    copy /Y "KooCAE.pyi" "..\services\" >nul 2>&1
)

cd "%ROOT_DIR%"

:: ==============================
:: Verify results and test
:: ==============================

echo.
echo ========================================

if "%COPIED%"=="1" (
    echo SUCCESS: Build and deployment completed!
    echo.
    echo Deployed files:
    echo    - services\KooCAE.pyd
    if exist "services\KooCAE.pyi" echo    - services\KooCAE.pyi
    echo.
    
    :: Test module import in Python
    echo Testing module import...
    python -c "import sys; sys.path.insert(0, 'services'); import KooCAE; print('SUCCESS: KooCAE module imported successfully!')" 2>nul
    if !ERRORLEVEL! equ 0 (
        echo SUCCESS: Module loads correctly!
    ) else (
        echo WARNING: Module import test failed.
        echo This might be due to missing dependencies.
    )
    
    echo.
    echo You can now start the Flask server:
    echo    python app.py
    
) else (
    echo ERROR: No .pyd file found!
    echo Build process may have failed.
    echo.
    echo Contents of build folder:
    dir build\*.pyd 2>nul
    if !ERRORLEVEL! neq 0 echo    No .pyd files found.
    echo.
    echo Contents of build folder:
    dir build\
)

echo ========================================
echo.

:: ==============================
:: Completion
:: ==============================

if "%COPIED%"=="1" (
    echo All tasks completed successfully!
    echo Flask server is ready to start.
) else (
    echo Issues occurred during the process.
    echo Please check error messages and try again.
)

echo.
echo Press any key to exit...
pause >nul
