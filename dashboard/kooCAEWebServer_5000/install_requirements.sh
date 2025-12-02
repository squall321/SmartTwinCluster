#!/bin/bash

# ======================================
# Installing Python Dependencies (Linux)
# ======================================

echo "========================================"
echo "Installing Python Dependencies"
echo "========================================"
echo ""

echo "[1/4] Checking virtual environment..."
if [ -n "$VIRTUAL_ENV" ]; then
    echo "OK: Virtual environment active"
else
    echo "WARNING: Virtual environment not active"
    echo "Activating virtual environment..."
    if [ -f "venv/bin/activate" ]; then
        source venv/bin/activate
        echo "OK: Activated venv environment"
    else
        echo "ERROR: No virtual environment found!"
        echo "Create one with: python3 -m venv venv"
        exit 1
    fi
fi

echo ""
echo "[2/4] Upgrading pip..."
python -m pip install --upgrade pip

echo ""
echo "[3/4] Installing requirements.txt..."
if [ -f "requirements.txt" ]; then
    pip install -r requirements.txt
else
    echo "ERROR: requirements.txt not found!"
    exit 1
fi

echo ""
echo "[4/4] Verifying installation..."
python -c "import flask; print('Flask OK')" || echo "Flask verification failed"
python -c "import flask_cors; print('Flask-CORS OK')" || echo "Flask-CORS verification failed"
python -c "import flask_sqlalchemy; print('Flask-SQLAlchemy OK')" || echo "Flask-SQLAlchemy verification failed"

echo ""
echo "========================================"
echo "Installation completed!"
echo "========================================"
read -p "Press any key to continue..."
