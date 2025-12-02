@echo off
echo ========================================
echo Installing Python Dependencies
echo ========================================
echo.

echo [1/4] Checking virtual environment...
if defined VIRTUAL_ENV (
    echo OK: Virtual environment active
) else (
    echo WARNING: Virtual environment not active
    echo Activating virtual environment...
    if exist "Scripts\activate.bat" (
        call Scripts\activate.bat
        echo OK: Activated Scripts environment
    ) else if exist "venv\Scripts\activate.bat" (
        call venv\Scripts\activate.bat
        echo OK: Activated venv environment
    ) else (
        echo ERROR: No virtual environment found!
        pause
        exit /b 1
    )
)

echo.
echo [2/4] Upgrading pip...
python -m pip install --upgrade pip

echo.
echo [3/4] Installing requirements.txt...
if exist "requirements.txt" (
    pip install -r requirements.txt
) else (
    echo ERROR: requirements.txt not found!
    pause
    exit /b 1
)

echo.
echo [4/4] Verifying installation...
python -c "import flask; print('Flask OK')"
python -c "import flask_cors; print('Flask-CORS OK')"
python -c "import flask_sqlalchemy; print('Flask-SQLAlchemy OK')"

echo.
echo ========================================
echo Installation completed!
echo ========================================
pause