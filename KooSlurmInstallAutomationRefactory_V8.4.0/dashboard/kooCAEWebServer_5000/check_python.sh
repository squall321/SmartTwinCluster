#!/bin/bash

# ======================================
# Python Environment Check (Linux)
# ======================================

echo "========================================"
echo "Python Environment Check"
echo "========================================"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

echo "Current directory: $PWD"
echo ""

echo "This script now redirects to the enhanced version."
echo "Running comprehensive Python version detection..."
echo ""

chmod +x check_python_versions.sh
./check_python_versions.sh

echo ""
echo "========================================"
echo "SOLUTION: Use VS Code Python selector"
echo "========================================"
echo "1. Open VS Code"
echo "2. Press Ctrl+Shift+P"
echo "3. Type: Python: Select Interpreter"
echo "4. Choose working Python from above"
echo "========================================"

read -p "Press any key to continue..."
