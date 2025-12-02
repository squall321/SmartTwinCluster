#!/bin/bash

# ======================================
# KooCAE Project Initialization (Linux)
# ======================================

set -e  # Exit on error (but we'll handle errors manually)

echo "========================================"
echo "KooCAE Project Initialization (Linux)"
echo "========================================"
echo "This script will set up your development environment"
echo "Press any key to continue or Ctrl+C to cancel..."
read -n 1
echo ""

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

ERRORS=0

echo "[1/10] Platform Detection..."
echo "✅ Detected Platform: Linux ($(uname -s) $(uname -m))"
echo ""

echo "[2/10] Python Version Selection..."
echo ""
echo "🐍 Available Python versions:"

# Detect available Python versions
PYTHON_VERSIONS=()
PYTHON_COMMANDS=()
PYTHON_COUNT=0
DEFAULT_PYTHON=""
DEFAULT_INDEX=0

# Check for Python 3.13 (default preference)
if command -v python3.13 &> /dev/null; then
    PYTHON_COUNT=$((PYTHON_COUNT + 1))
    PYTHON_VERSIONS+=("3.13")
    PYTHON_COMMANDS+=("python3.13")
    if [ -z "$DEFAULT_PYTHON" ]; then
        DEFAULT_PYTHON="3.13"
        DEFAULT_INDEX=$PYTHON_COUNT
    fi
    VERSION_INFO=$(python3.13 --version 2>&1)
    echo "  [$PYTHON_COUNT] Python 3.13 ($VERSION_INFO) (Default ⭐)"
fi

# Check for Python 3.12
if command -v python3.12 &> /dev/null; then
    PYTHON_COUNT=$((PYTHON_COUNT + 1))
    PYTHON_VERSIONS+=("3.12")
    PYTHON_COMMANDS+=("python3.12")
    if [ -z "$DEFAULT_PYTHON" ]; then
        DEFAULT_PYTHON="3.12"
        DEFAULT_INDEX=$PYTHON_COUNT
    fi
    VERSION_INFO=$(python3.12 --version 2>&1)
    echo "  [$PYTHON_COUNT] Python 3.12 ($VERSION_INFO)"
fi

# Check for Python 3.11
if command -v python3.11 &> /dev/null; then
    PYTHON_COUNT=$((PYTHON_COUNT + 1))
    PYTHON_VERSIONS+=("3.11")
    PYTHON_COMMANDS+=("python3.11")
    if [ -z "$DEFAULT_PYTHON" ]; then
        DEFAULT_PYTHON="3.11"
        DEFAULT_INDEX=$PYTHON_COUNT
    fi
    VERSION_INFO=$(python3.11 --version 2>&1)
    echo "  [$PYTHON_COUNT] Python 3.11 ($VERSION_INFO)"
fi

# Check for Python 3.10
if command -v python3.10 &> /dev/null; then
    PYTHON_COUNT=$((PYTHON_COUNT + 1))
    PYTHON_VERSIONS+=("3.10")
    PYTHON_COMMANDS+=("python3.10")
    if [ -z "$DEFAULT_PYTHON" ]; then
        DEFAULT_PYTHON="3.10"
        DEFAULT_INDEX=$PYTHON_COUNT
    fi
    VERSION_INFO=$(python3.10 --version 2>&1)
    echo "  [$PYTHON_COUNT] Python 3.10 ($VERSION_INFO)"
fi

# Check for Python 3.9
if command -v python3.9 &> /dev/null; then
    PYTHON_COUNT=$((PYTHON_COUNT + 1))
    PYTHON_VERSIONS+=("3.9")
    PYTHON_COMMANDS+=("python3.9")
    if [ -z "$DEFAULT_PYTHON" ]; then
        DEFAULT_PYTHON="3.9"
        DEFAULT_INDEX=$PYTHON_COUNT
    fi
    VERSION_INFO=$(python3.9 --version 2>&1)
    echo "  [$PYTHON_COUNT] Python 3.9 ($VERSION_INFO)"
fi

# Check for Python 3.8
if command -v python3.8 &> /dev/null; then
    PYTHON_COUNT=$((PYTHON_COUNT + 1))
    PYTHON_VERSIONS+=("3.8")
    PYTHON_COMMANDS+=("python3.8")
    if [ -z "$DEFAULT_PYTHON" ]; then
        DEFAULT_PYTHON="3.8"
        DEFAULT_INDEX=$PYTHON_COUNT
    fi
    VERSION_INFO=$(python3.8 --version 2>&1)
    echo "  [$PYTHON_COUNT] Python 3.8 ($VERSION_INFO)"
fi

# Check for generic python3 command
if command -v python3 &> /dev/null; then
    PYTHON_COUNT=$((PYTHON_COUNT + 1))
    PYTHON_VERSIONS+=("system3")
    PYTHON_COMMANDS+=("python3")
    if [ -z "$DEFAULT_PYTHON" ]; then
        DEFAULT_PYTHON="system3"
        DEFAULT_INDEX=$PYTHON_COUNT
    fi
    VERSION_INFO=$(python3 --version 2>&1)
    echo "  [$PYTHON_COUNT] System Python3 ($VERSION_INFO)"
fi

# Check for generic python command
if command -v python &> /dev/null; then
    PYTHON_VERSION_CHECK=$(python --version 2>&1)
    if [[ $PYTHON_VERSION_CHECK == *"Python 3"* ]]; then
        PYTHON_COUNT=$((PYTHON_COUNT + 1))
        PYTHON_VERSIONS+=("system")
        PYTHON_COMMANDS+=("python")
        if [ -z "$DEFAULT_PYTHON" ]; then
            DEFAULT_PYTHON="system"
            DEFAULT_INDEX=$PYTHON_COUNT
        fi
        echo "  [$PYTHON_COUNT] System Python ($PYTHON_VERSION_CHECK)"
    fi
fi

echo ""

if [ $PYTHON_COUNT -eq 0 ]; then
    echo "❌ No Python 3.x installation found!"
    echo ""
    echo "Please install Python 3.8+ from one of these sources:"
    echo "  Ubuntu/Debian:"
    echo "    sudo apt update"
    echo "    sudo apt install python3.13 python3.13-venv python3.13-pip"
    echo "    # or: sudo apt install python3 python3-venv python3-pip"
    echo ""
    echo "  Fedora/RHEL:"
    echo "    sudo dnf install python3 python3-pip python3-venv"
    echo ""
    echo "  Arch Linux:"
    echo "    sudo pacman -S python python-pip"
    echo ""
    echo "  From source:"
    echo "    https://python.org/downloads/source/"
    echo ""
    ERRORS=1
    exit 1
fi

# Python version selection
if [[ "${PYTHON_VERSIONS[*]}" =~ "3.13" ]]; then
    echo "💡 Recommendation: Python 3.13 is recommended for this project"
else
    echo "💡 Note: Python 3.13 is recommended but not found"
fi
echo ""

while true; do
    read -p "Choose Python version [1-$PYTHON_COUNT] or press Enter for default ($DEFAULT_PYTHON): " CHOICE
    
    if [ -z "$CHOICE" ]; then
        SELECTED_INDEX=$DEFAULT_INDEX
        SELECTED_VERSION=$DEFAULT_PYTHON
        break
    fi
    
    if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le $PYTHON_COUNT ]; then
        SELECTED_INDEX=$CHOICE
        SELECTED_VERSION=${PYTHON_VERSIONS[$((CHOICE-1))]}
        break
    else
        echo "❌ Invalid choice. Please enter a number between 1 and $PYTHON_COUNT."
    fi
done

echo ""
echo "✅ Selected Python: $SELECTED_VERSION"

# Set Python command based on selection
PYTHON_CMD=${PYTHON_COMMANDS[$((SELECTED_INDEX-1))]}

# Verify selected Python works
echo "Testing selected Python..."
if ! $PYTHON_CMD --version &> /dev/null; then
    echo "❌ Failed to execute selected Python version"
    ERRORS=1
    exit 1
fi

FINAL_PYTHON_VERSION=$($PYTHON_CMD --version 2>&1)
echo "✅ Using $FINAL_PYTHON_VERSION"

echo ""
echo "[3/10] Making Scripts Executable..."
echo "Setting execute permissions on shell scripts..."
chmod +x *.sh 2>/dev/null || true
if [ -f "make_executable.sh" ]; then
    chmod +x make_executable.sh
    ./make_executable.sh >/dev/null 2>&1 || true
    echo "✅ All shell scripts are now executable"
else
    # Manual permission setting
    chmod +x build_and_deploy.sh check_python.sh fix_python_env.sh 2>/dev/null || true
    chmod +x install_requirements.sh quick_build.sh setup_and_build.sh 2>/dev/null || true
    chmod +x test_dependencies.sh test_environment.sh rebuild_cpp.sh 2>/dev/null || true
    chmod +x compileUbuntu.sh configure_vscode.sh setup.sh 2>/dev/null || true
    echo "✅ Shell scripts made executable"
fi

echo ""
echo "[4/10] Creating Virtual Environment..."
echo "Creating virtual environment with $FINAL_PYTHON_VERSION..."

if [ -d "venv" ]; then
    echo "Removing existing virtual environment..."
    rm -rf venv
fi

if $PYTHON_CMD -m venv venv; then
    echo "✅ Virtual environment created successfully"
else
    echo "❌ Failed to create virtual environment"
    echo ""
    echo "Try installing venv module:"
    echo "  Ubuntu/Debian: sudo apt install python3-venv"
    echo "  Fedora: sudo dnf install python3-venv"  
    echo "  Or: $PYTHON_CMD -m pip install --upgrade pip"
    ERRORS=1
    exit 1
fi

echo ""
echo "[5/10] Activating Virtual Environment..."
if [ -f "venv/bin/activate" ]; then
    source venv/bin/activate
    echo "✅ Virtual environment activated"
    
    # Verify Python in venv
    if python --version &> /dev/null; then
        VENV_PYTHON_VERSION=$(python --version 2>&1)
        echo "✅ Virtual environment Python: $VENV_PYTHON_VERSION"
    fi
    PYTHON_CMD="python"  # Use the venv python
else
    echo "❌ Virtual environment activation failed"
    ERRORS=1
    exit 1
fi

echo ""
echo "[6/10] Installing Python Dependencies..."
if [ -n "$PYTHON_CMD" ]; then
    echo "Upgrading pip..."
    $PYTHON_CMD -m pip install --upgrade pip --quiet 2>/dev/null || echo "Warning: pip upgrade failed"
    
    echo "Installing build essentials..."
    $PYTHON_CMD -m pip install --upgrade setuptools wheel --quiet 2>/dev/null || echo "Warning: setuptools/wheel install failed"
    
    echo "Installing requirements..."
    if [ -f "requirements.txt" ]; then
        if $PYTHON_CMD -m pip install -r requirements.txt --quiet; then
            echo "✅ Dependencies installed successfully"
        else
            echo "❌ Failed to install dependencies"
            echo "Trying with verbose output..."
            $PYTHON_CMD -m pip install -r requirements.txt
            ERRORS=1
        fi
    else
        echo "❌ requirements.txt not found!"
        ERRORS=1
    fi
fi

echo ""
echo "[7/10] Checking Build Tools..."
echo "Checking essential build tools..."

BUILD_TOOLS_MISSING=""

if ! command -v gcc &> /dev/null; then
    BUILD_TOOLS_MISSING="$BUILD_TOOLS_MISSING gcc"
fi

if ! command -v g++ &> /dev/null; then
    BUILD_TOOLS_MISSING="$BUILD_TOOLS_MISSING g++"
fi

if ! command -v cmake &> /dev/null; then
    BUILD_TOOLS_MISSING="$BUILD_TOOLS_MISSING cmake"
fi

if ! command -v ninja &> /dev/null; then
    BUILD_TOOLS_MISSING="$BUILD_TOOLS_MISSING ninja-build"
fi

if [ -n "$BUILD_TOOLS_MISSING" ]; then
    echo "❌ Missing build tools:$BUILD_TOOLS_MISSING"
    echo "Install with: sudo apt-get install build-essential cmake ninja-build"
    ERRORS=1
else
    echo "✅ All build tools found"
fi

echo ""
echo "[8/10] Configuring VS Code Settings..."
if [ -f "configure_vscode.sh" ]; then
    chmod +x configure_vscode.sh
    if ./configure_vscode.sh >/dev/null 2>&1; then
        echo "✅ VS Code configuration completed"
    else
        echo "❌ VS Code configuration failed"
        ERRORS=1
    fi
else
    echo "❌ VS Code configuration script not found"
    ERRORS=1
fi

echo ""
echo "[9/10] Updating VS Code Python Path..."
echo "Updating VS Code settings with selected Python..."

# Update .vscode/settings.json with correct Python path
if [ -f ".vscode/settings.json" ]; then
    echo "✅ Python path will be available for VS Code selection"
    echo "  Recommended path: \${workspaceFolder}/venv/bin/python"
fi

echo ""
echo "[10/10] Running Initial Tests..."
if [ -n "$PYTHON_CMD" ]; then
    echo "Testing Python environment..."
    if $PYTHON_CMD --version; then
        echo "✅ Python test passed"
    else
        echo "❌ Python test failed"
        ERRORS=1
    fi
    
    echo "Testing Flask dependencies..."
    if $PYTHON_CMD -c "import flask, flask_cors, flask_sqlalchemy; print('✅ Flask dependencies OK')" 2>/dev/null; then
        echo "✅ Flask test passed"
    else
        echo "❌ Flask dependencies test failed"
        ERRORS=1
    fi
    
    echo "Testing pybind11..."
    if $PYTHON_CMD -c "import pybind11; print('✅ pybind11 OK')" 2>/dev/null; then
        echo "✅ pybind11 test passed"
    else
        echo "❌ pybind11 test failed"
        ERRORS=1
    fi
fi

echo ""
echo "========================================"
echo "Initialization Summary"
echo "========================================"

if [ "$ERRORS" = "0" ]; then
    echo "🎉 SUCCESS: Project initialization completed!"
    echo ""
    echo "Your development environment is ready:"
    echo "  ✅ Python virtual environment: venv ($FINAL_PYTHON_VERSION)"
    echo "  ✅ Dependencies installed"
    echo "  ✅ VS Code configured for Linux"
    echo "  ✅ Build tools available"
    echo "  ✅ All tests passed"
    echo ""
    echo "Next steps:"
    echo "  1. Open this folder in VS Code"
    echo "  2. Select Python interpreter:"
    echo "     • Press Ctrl+Shift+P"
    echo "     • Type: \"Python: Select Interpreter\""
    echo "     • Choose: ./venv/bin/python"
    echo "  3. Build the C++ extension:"
    echo "     • Run: ./quick_build.sh"
    echo "     • Or: ./setup_and_build.sh"
    echo "  4. Start Flask server:"
    echo "     • Run: python app.py"
    echo "     • Or press F5 in VS Code"
    echo ""
    echo "Quick commands:"
    echo "  ./quick_build.sh           - Build C++ extension"
    echo "  ./test_environment.sh      - Test full environment"
    echo "  python app.py              - Start Flask server"
else
    echo "❌ ERRORS DETECTED: Initialization completed with issues"
    echo ""
    echo "Please resolve the errors above and run again:"
    echo "  ./initialize_project.sh"
    echo ""
    echo "Common solutions:"
    echo "  sudo apt-get update"
    echo "  sudo apt-get install python3.13 python3.13-venv python3.13-pip"
    echo "  sudo apt-get install build-essential cmake ninja-build"
    echo ""
    echo "For Ubuntu/Debian users:"
    echo "  sudo apt-get install python3-dev python3-setuptools"
fi

echo "========================================"
echo ""
read -p "Press any key to continue..."
