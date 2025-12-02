#!/bin/bash

# ======================================
# Python Environment Diagnostics (Linux)
# ======================================

echo "========================================"
echo "Python Environment Diagnostics"
echo "========================================"
echo ""

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

echo "[1] Current Working Directory:"
echo "   $PWD"
echo ""

echo "[2] Checking Python Interpreters:"

# Check venv folder
if [ -f "venv/bin/python" ]; then
    echo "✅ Found: ./venv/bin/python"
    if venv/bin/python --version 2>/dev/null; then
        echo "   Status: Working"
    else
        echo "   Status: Not working"
    fi
else
    echo "❌ Not found: ./venv/bin/python"
fi

# Check venv python3
if [ -f "venv/bin/python3" ]; then
    echo "✅ Found: ./venv/bin/python3"
    if venv/bin/python3 --version 2>/dev/null; then
        echo "   Status: Working"
    else
        echo "   Status: Not working"
    fi
else
    echo "❌ Not found: ./venv/bin/python3"
fi

echo ""
echo "[3] Current Active Python:"
if python --version 2>/dev/null; then
    echo "✅ Python command works"
    which python
else
    echo "❌ Python command not found"
fi

echo ""
echo "[4] Environment Variables:"
echo "   VIRTUAL_ENV: ${VIRTUAL_ENV:-Not set}"
echo "   PATH: $PATH"

echo ""
echo "[5] Testing Flask Dependencies:"
if python -c "import flask; print(f'Flask version: {flask.__version__}')" 2>/dev/null; then
    echo "✅ Flask import successful"
else
    echo "❌ Flask import failed"
fi

echo ""
echo "========================================"
echo "VS Code Python Configuration"
echo "========================================"

# Backup existing settings
if [ -f ".vscode/settings.json" ]; then
    echo "Creating .vscode/settings.json.backup..."
    cp ".vscode/settings.json" ".vscode/settings.json.backup"
fi

echo ""
echo "Recommended Python interpreter paths:"
if [ -f "venv/bin/python" ]; then
    echo "   1. \${workspaceFolder}/venv/bin/python  (RECOMMENDED)"
fi
if [ -f "venv/bin/python3" ]; then
    echo "   2. \${workspaceFolder}/venv/bin/python3  (ALTERNATIVE)"
fi

echo ""
echo "========================================"
echo "Manual VS Code Setup Instructions:"
echo "========================================"
echo "1. Open VS Code"
echo "2. Press Ctrl+Shift+P"
echo "3. Type: \"Python: Select Interpreter\""
echo "4. Choose one of the interpreters listed above"
echo "5. Try running Flask again"
echo "========================================"

read -p "Press any key to continue..."
