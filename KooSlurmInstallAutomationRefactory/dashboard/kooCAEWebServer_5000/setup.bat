@echo off
echo ========================================
echo KooCAE Project Auto-Setup
echo ========================================
echo Detecting platform and running appropriate initialization...
echo.

:: Check if we're on Windows
echo Platform: Windows
echo.

:: Show Python version options first
echo Would you like to check available Python versions first?
set /p "CHECK_PYTHON=Press 'y' to check Python versions, or Enter to proceed with setup: "

if /i "%CHECK_PYTHON%"=="y" (
    echo.
    call check_python_versions.bat
    echo.
    echo Now running full initialization...
    echo.
)

echo Running Windows initialization script...
call initialize_project.bat
