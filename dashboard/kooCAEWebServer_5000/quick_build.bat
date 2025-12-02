@echo off

echo ========================================
echo KooCAE Quick Build Script (Fixed)
echo ========================================

:: Find Visual Studio
for /f "usebackq tokens=*" %%i in (`"C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2^>nul`) do set VS_PATH=%%i

if "%VS_PATH%"=="" (
    echo ERROR: Visual Studio not found!
    pause
    exit /b 1
)

echo Found Visual Studio: %VS_PATH%

:: Setup MSVC environment
call "%VS_PATH%\VC\Auxiliary\Build\vcvarsall.bat" x64

:: Install required Python packages
echo Installing Python packages...
python -m pip install --upgrade pip
pip install setuptools wheel pybind11 numpy

if %ERRORLEVEL% neq 0 (
    echo ERROR: Failed to install Python packages!
    pause
    exit /b 1
)

:: Verify packages
echo Verifying packages...
python -c "import setuptools, pybind11; print('Packages OK')"
if %ERRORLEVEL% neq 0 (
    echo ERROR: Package verification failed!
    pause
    exit /b 1
)

:: Build
cd build

:: Clean old cache if needed
if exist "CMakeCache.txt" (
    findstr /c:"squal" CMakeCache.txt >nul 2>&1
    if %ERRORLEVEL% equ 0 (
        echo Cleaning old cache...
        del /f CMakeCache.txt
        if exist CMakeFiles rmdir /s /q CMakeFiles
    )
)

:: Clean old build files
if exist "build" rmdir /s /q build 2>nul
if exist "KooCAE*.pyd" del /q KooCAE*.pyd 2>nul

echo Building...
python setup.py build_ext --inplace

if %ERRORLEVEL% neq 0 (
    echo Build failed! Trying with force...
    python setup.py build_ext --inplace --force
    if %ERRORLEVEL% neq 0 (
        echo ERROR: Build failed completely!
        pause
        exit /b 1
    )
)

cd ..

:: Prepare services folder
if not exist services mkdir services

:: Copy pyd file
cd build
echo Looking for .pyd files...
dir KooCAE*.pyd

for %%f in (KooCAE*.pyd) do (
    echo Copying %%f to services folder...
    copy /Y %%f ..\services\KooCAE.pyd
    if %ERRORLEVEL% equ 0 (
        echo SUCCESS: %%f copied!
    )
)
cd ..

:: Test import
echo Testing module...
python -c "import sys; sys.path.insert(0, 'services'); import KooCAE; print('SUCCESS: Module works!')"

if %ERRORLEVEL% equ 0 (
    echo ========================================
    echo Build complete! You can now run:
    echo    python app.py
    echo ========================================
) else (
    echo ========================================
    echo Build completed but module test failed.
    echo Check dependencies and try again.
    echo ========================================
)

pause
