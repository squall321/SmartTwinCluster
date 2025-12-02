@echo off

echo ========================================
echo Python Environment Check
echo ========================================

cd /d "%~dp0"

echo Current directory: %CD%
echo.

echo This script now redirects to the enhanced version.
echo Running comprehensive Python version detection...
echo.

call check_python_versions.bat

echo.
echo ========================================
echo SOLUTION: Use VS Code Python selector
echo ========================================
echo 1. Open VS Code
echo 2. Press Ctrl+Shift+P
echo 3. Type: Python: Select Interpreter
echo 4. Choose working Python from above
echo ========================================

pause
