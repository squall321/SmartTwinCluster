@echo off
echo Testing Python dependencies...
echo.

echo [1] Testing Python version:
python --version
if %ERRORLEVEL% neq 0 (
    echo ERROR: Python not found
    exit /b 1
)

echo [2] Testing Flask:
python -c "import flask" 2>nul
if %ERRORLEVEL% equ 0 (
    echo OK: Flask found
) else (
    echo ERROR: Flask not found
    echo Run: pip install flask
)

echo [3] Testing Flask-CORS:
python -c "import flask_cors" 2>nul  
if %ERRORLEVEL% equ 0 (
    echo OK: Flask-CORS found
) else (
    echo ERROR: Flask-CORS not found
    echo Run: pip install flask-cors
)

echo [4] Testing Flask-SQLAlchemy:
python -c "import flask_sqlalchemy" 2>nul
if %ERRORLEVEL% equ 0 (
    echo OK: Flask-SQLAlchemy found
) else (
    echo ERROR: Flask-SQLAlchemy not found  
    echo Run: pip install flask-sqlalchemy
)

echo [5] Testing KooCAE module:
python -c "import sys; sys.path.insert(0, 'services'); import KooCAE" 2>nul
if %ERRORLEVEL% equ 0 (
    echo OK: KooCAE module found
) else (
    echo ERROR: KooCAE module not found
    echo Run: .\setup_and_build.bat
)

echo.
echo ========================================
echo All tests completed!
echo If any errors above, install missing packages
echo ========================================
pause
