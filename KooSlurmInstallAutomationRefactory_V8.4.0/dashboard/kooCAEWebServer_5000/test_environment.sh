#!/bin/bash

# ======================================
# KooCAE Development Environment Test (Linux)
# ======================================

echo "========================================"
echo "KooCAE Development Environment Test"
echo "========================================"
echo ""

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

ALL_TESTS_PASSED=1

echo "[1/6] Testing Python Environment..."
if python -c "import sys; print(f'Python version: {sys.version}')" 2>/dev/null; then
    echo "✅ Python environment OK"
else
    echo "❌ Python not found or not working"
    ALL_TESTS_PASSED=0
fi

echo "[2/6] Testing Python Dependencies..."
if python -c "import flask, flask_cors, flask_sqlalchemy; print('Flask dependencies OK')" 2>/dev/null; then
    echo "✅ Flask dependencies OK"
else
    echo "❌ Flask dependencies missing"
    echo "   Run: pip install -r requirements.txt"
    ALL_TESTS_PASSED=0
fi

echo "[3/6] Testing Python Extension Module..."
if [ -f "services/KooCAE.so" ]; then
    echo "✅ KooCAE.so exists"
    if python -c "import sys; sys.path.insert(0, 'services'); import KooCAE; print('KooCAE module import OK')" 2>/dev/null; then
        echo "✅ KooCAE module loads successfully"
    else
        echo "❌ KooCAE module import failed"
        ALL_TESTS_PASSED=0
    fi
else
    echo "❌ KooCAE.so not found"
    echo "   Run: ./setup_and_build.sh"
    ALL_TESTS_PASSED=0
fi

echo "[4/6] Testing C++ Test Runner..."
if [ -f "build/cpp_only/Debug/test_runner" ] || [ -f "build/cpp_only/test_runner" ]; then
    echo "✅ test_runner executable exists"
else
    echo "❌ test_runner executable not found"
    echo "   Configure and build C++ project in VS Code"
    ALL_TESTS_PASSED=0
fi

if [ -f "build/cpp_test/test.k" ]; then
    echo "✅ Test K-file exists"
else
    echo "❌ Test K-file not found"
    ALL_TESTS_PASSED=0
fi

echo "[5/6] Testing Build Environment..."
if command -v cmake &> /dev/null; then
    echo "✅ CMake found: $(cmake --version | head -n1)"
else
    echo "❌ CMake not found"
    echo "   Install with: sudo apt-get install cmake"
    ALL_TESTS_PASSED=0
fi

if command -v ninja &> /dev/null; then
    echo "✅ Ninja found: $(ninja --version)"
else
    echo "❌ Ninja not found"
    echo "   Install with: sudo apt-get install ninja-build"
    ALL_TESTS_PASSED=0
fi

if command -v gcc &> /dev/null; then
    echo "✅ GCC found: $(gcc --version | head -n1)"
else
    echo "❌ GCC not found"
    echo "   Install with: sudo apt-get install build-essential"
    ALL_TESTS_PASSED=0
fi

echo "[6/6] Testing VS Code Configuration..."
if [ -f ".vscode/launch.json" ]; then
    echo "✅ VS Code launch configuration exists"
else
    echo "❌ VS Code launch configuration missing"
    ALL_TESTS_PASSED=0
fi

if [ -f ".vscode/tasks.json" ]; then
    echo "✅ VS Code tasks configuration exists"
else
    echo "❌ VS Code tasks configuration missing"
    ALL_TESTS_PASSED=0
fi

echo ""
echo "========================================"
if [ "$ALL_TESTS_PASSED" = "1" ]; then
    echo "✅ ALL TESTS PASSED!"
    echo ""
    echo "🚀 Ready to develop! You can now:"
    echo "   1. Press F5 in VS Code for Flask debugging"
    echo "   2. Press F5 in VS Code for C++ debugging"
    echo "   3. Use Command Palette tasks for building"
    echo ""
    echo "📖 See DEVELOPMENT_GUIDE.md for detailed instructions"
else
    echo "❌ SOME TESTS FAILED!"
    echo ""
    echo "🔧 Fix the issues above and run this test again."
    echo ""
    echo "Quick fixes:"
    echo "   - Python deps: pip install -r requirements.txt"
    echo "   - Python extension: ./setup_and_build.sh"
    echo "   - C++ build: Open VS Code and run configure task"
    echo "   - Build tools: sudo apt-get install cmake ninja-build build-essential"
fi
echo "========================================"
echo ""

read -p "Press any key to continue..."
