#!/bin/bash

# ======================================
# VS Code Platform Configuration (Linux)
# ======================================

set -e  # Exit on error

echo "========================================"
echo "VS Code Platform Configuration (Linux)"
echo "========================================"
echo ""

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

echo "[1/4] Platform Detection..."
echo "✅ Detected Platform: Linux ($(uname -s) $(uname -m))"
echo ""

echo "[2/4] Configuring VS Code Settings..."

# Backup current settings if exists
if [ -f ".vscode/settings.json" ]; then
    echo "Creating backup of current settings..."
    cp ".vscode/settings.json" ".vscode/settings.json.backup"
    echo "✅ Backup created: settings.json.backup"
fi

# Copy Linux-specific settings
if [ -f ".vscode/settings.linux.json" ]; then
    echo "Applying Linux-specific settings..."
    cp ".vscode/settings.linux.json" ".vscode/settings.json"
    if [ $? -eq 0 ]; then
        echo "✅ Linux settings applied successfully"
    else
        echo "❌ Failed to apply Linux settings"
        exit 1
    fi
else
    echo "❌ Linux settings template not found!"
    exit 1
fi

echo ""
echo "[3/4] Checking Build Tools..."

# Check for essential build tools
BUILD_TOOLS_OK=1

if command -v gcc &> /dev/null; then
    GCC_VERSION=$(gcc --version | head -n1)
    echo "✅ GCC: $GCC_VERSION"
else
    echo "❌ GCC not found!"
    echo "   Install with: sudo apt-get install build-essential"
    BUILD_TOOLS_OK=0
fi

if command -v g++ &> /dev/null; then
    GPP_VERSION=$(g++ --version | head -n1)
    echo "✅ G++: $GPP_VERSION"
else
    echo "❌ G++ not found!"
    echo "   Install with: sudo apt-get install build-essential"
    BUILD_TOOLS_OK=0
fi

if command -v cmake &> /dev/null; then
    CMAKE_VERSION=$(cmake --version | head -n1)
    echo "✅ CMake: $CMAKE_VERSION"
else
    echo "❌ CMake not found!"
    echo "   Install with: sudo apt-get install cmake"
    BUILD_TOOLS_OK=0
fi

if command -v ninja &> /dev/null; then
    NINJA_VERSION=$(ninja --version)
    echo "✅ Ninja: $NINJA_VERSION"
else
    echo "❌ Ninja not found!"
    echo "   Install with: sudo apt-get install ninja-build"
    BUILD_TOOLS_OK=0
fi

if command -v gdb &> /dev/null; then
    GDB_VERSION=$(gdb --version | head -n1)
    echo "✅ GDB: $GDB_VERSION"
else
    echo "❌ GDB not found!"
    echo "   Install with: sudo apt-get install gdb"
    BUILD_TOOLS_OK=0
fi

echo ""
echo "[4/4] Checking Python Virtual Environment..."

# Check for virtual environment
PYTHON_PATH=""
if [ -f "venv/bin/python" ]; then
    PYTHON_PATH="venv/bin/python"
    PYTHON_VERSION=$(venv/bin/python --version)
    echo "✅ Found Python: $PYTHON_PATH ($PYTHON_VERSION)"
elif [ -f "venv/bin/python3" ]; then
    PYTHON_PATH="venv/bin/python3"
    PYTHON_VERSION=$(venv/bin/python3 --version)
    echo "✅ Found Python: $PYTHON_PATH ($PYTHON_VERSION)"
else
    echo "❌ Python virtual environment not found!"
    echo "   Expected locations:"
    echo "     - venv/bin/python"
    echo "     - venv/bin/python3"
    echo ""
    echo "   Create virtual environment:"
    echo "     python3 -m venv venv"
    echo "     source venv/bin/activate"
    echo "     pip install -r requirements.txt"
fi

echo ""
echo "========================================"
echo "Configuration Summary"
echo "========================================"
echo "Platform: Linux"
echo "VS Code Settings: ✅ Applied"

if [ "$BUILD_TOOLS_OK" = "1" ]; then
    echo "Build Tools: ✅ All Found"
    echo "  GCC/G++: ✅"
    echo "  CMake: ✅" 
    echo "  Ninja: ✅"
    echo "  GDB: ✅"
else
    echo "Build Tools: ❌ Missing Tools"
    echo "  Run: sudo apt-get install build-essential cmake ninja-build gdb"
fi

if [ -n "$PYTHON_PATH" ]; then
    echo "Python Env: ✅ Found"
    echo "  Path: $PYTHON_PATH"
else
    echo "Python Env: ❌ Not Found"
fi

echo "========================================"
echo ""

if [ "$BUILD_TOOLS_OK" = "1" ] && [ -n "$PYTHON_PATH" ]; then
    echo "🎉 Configuration completed successfully!"
    echo "   VS Code is now configured for Linux development."
    echo ""
    echo "Next steps:"
    echo "  1. Open this folder in VS Code"
    echo "  2. Press Ctrl+Shift+P"
    echo "  3. Run \"Python: Select Interpreter\""
    echo "  4. Choose: $PYTHON_PATH"
    echo "  5. Press F5 to start debugging"
else
    echo "⚠️  Configuration completed with warnings."
    echo "   Please install missing components and run again."
    echo ""
    if [ "$BUILD_TOOLS_OK" = "0" ]; then
        echo "Install build tools:"
        echo "  sudo apt-get update"
        echo "  sudo apt-get install build-essential cmake ninja-build gdb"
    fi
    if [ -z "$PYTHON_PATH" ]; then
        echo "Create virtual environment:"
        echo "  python3 -m venv venv"
        echo "  source venv/bin/activate"
        echo "  pip install -r requirements.txt"
    fi
fi

echo ""
read -p "Press any key to continue..."
