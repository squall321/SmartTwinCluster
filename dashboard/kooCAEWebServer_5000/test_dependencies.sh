#!/bin/bash

# ======================================
# Testing Python dependencies (Linux)
# ======================================

echo "Testing Python dependencies..."
echo ""

echo "[1] Testing Python version:"
python --version
if [ $? -ne 0 ]; then
    echo "ERROR: Python not found"
    exit 1
fi

echo "[2] Testing Flask:"
if python -c "import flask" 2>/dev/null; then
    echo "OK: Flask found"
else
    echo "ERROR: Flask not found"
    echo "Run: pip install flask"
fi

echo "[3] Testing Flask-CORS:"
if python -c "import flask_cors" 2>/dev/null; then
    echo "OK: Flask-CORS found"
else
    echo "ERROR: Flask-CORS not found"
    echo "Run: pip install flask-cors"
fi

echo "[4] Testing Flask-SQLAlchemy:"
if python -c "import flask_sqlalchemy" 2>/dev/null; then
    echo "OK: Flask-SQLAlchemy found"
else
    echo "ERROR: Flask-SQLAlchemy not found"
    echo "Run: pip install flask-sqlalchemy"
fi

echo "[5] Testing KooCAE module:"
if python -c "import sys; sys.path.insert(0, 'services'); import KooCAE" 2>/dev/null; then
    echo "OK: KooCAE module found"
else
    echo "ERROR: KooCAE module not found"
    echo "Run: ./setup_and_build.sh"
fi

echo ""
echo "========================================"
echo "All tests completed!"
echo "If any errors above, install missing packages"
echo "========================================"
read -p "Press any key to continue..."
