@echo off

echo ========================================
echo KooCAE Environment Setup and Build
echo ========================================

:: Check if we're in virtual environment
python -c "import sys; print('Virtual env:', hasattr(sys, 'real_prefix') or (hasattr(sys, 'base_prefix') and sys.base_prefix != sys.prefix))"

:: Install all requirements first
echo Installing all requirements...
python -m pip install --upgrade pip setuptools wheel

:: Install from requirements.txt
if exist "requirements.txt" (
    echo Installing from requirements.txt...
    pip install -r requirements.txt
) else (
    echo requirements.txt not found, installing manually...
    pip install setuptools wheel pybind11 numpy flask flask-cors flask-sqlalchemy
)

:: Verify key packages
echo Verifying installation...
python -c "import setuptools; print('setuptools version:', setuptools.__version__)"
python -c "import pybind11; print('pybind11 version:', pybind11.__version__)"

:: Find Visual Studio
for /f "usebackq tokens=*" %%i in (`"C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2^>nul`) do set VS_PATH=%%i

if "%VS_PATH%"=="" (
    echo ERROR: Visual Studio not found!
    pause
    exit /b 1
)

:: Setup MSVC environment
call "%VS_PATH%\VC\Auxiliary\Build\vcvarsall.bat" x64

:: Build
cd build

:: Clean everything
echo Cleaning build directory...
if exist "build" rmdir /s /q build
if exist "*.egg-info" rmdir /s /q *.egg-info
if exist "KooCAE*.pyd" del /q KooCAE*.pyd
if exist "CMakeCache.txt" del /f CMakeCache.txt
if exist "CMakeFiles" rmdir /s /q CMakeFiles

echo Building C++ extension...
python setup.py clean --all
python setup.py build_ext --inplace

if %ERRORLEVEL% neq 0 (
    echo Build failed! Check error messages above.
    pause
    exit /b 1
)

cd ..

:: Deploy
if not exist services mkdir services

cd build
for %%f in (KooCAE*.pyd) do (
    copy /Y %%f ..\services\KooCAE.pyd
    echo Deployed: %%f
)
cd ..

:: Test
python -c "import sys; sys.path.insert(0, 'services'); import KooCAE; print('SUCCESS: Ready to run Flask!')"

echo ========================================
echo Setup complete! Run: python app.py
echo ========================================
pause
