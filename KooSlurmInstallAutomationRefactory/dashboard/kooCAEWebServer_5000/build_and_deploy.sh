#!/bin/bash

# ===========================================
# KooCAE Auto Build and Deploy Script (Linux)
# ===========================================

set -e  # Exit on any error

echo "========================================"
echo "KooCAE Auto Build and Deploy Script"
echo "========================================"
echo ""

# Save current directory
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

# ==============================
# 1. Check build tools
# ==============================

echo "[1/8] Checking build tools..."

# Check for essential build tools
if ! command -v cmake &> /dev/null; then
    echo "ERROR: CMake not found!"
    echo "Please install cmake: sudo apt-get install cmake"
    exit 1
fi

if ! command -v ninja &> /dev/null; then
    echo "ERROR: Ninja not found!"
    echo "Please install ninja: sudo apt-get install ninja-build"
    exit 1
fi

if ! command -v gcc &> /dev/null; then
    echo "ERROR: GCC not found!"
    echo "Please install build-essential: sudo apt-get install build-essential"
    exit 1
fi

echo "SUCCESS: Build tools found"
echo "  CMake: $(cmake --version | head -n1)"
echo "  Ninja: $(ninja --version)"
echo "  GCC: $(gcc --version | head -n1)"
echo ""

# ==============================
# 2. Setup Python environment
# ==============================

echo "[2/8] Setting up Python environment..."

# Activate virtual environment
if [ -f "venv/bin/activate" ]; then
    source venv/bin/activate
    echo "SUCCESS: Virtual environment activated"
else
    echo "ERROR: Virtual environment not found at venv/bin/activate"
    echo "Please create it first: python3 -m venv venv"
    exit 1
fi

echo ""

# ==============================
# 3. Install required Python packages
# ==============================

echo "[3/8] Installing required Python packages..."

# Upgrade pip first
echo "Upgrading pip..."
python -m pip install --upgrade pip

# Install setuptools
echo "Installing setuptools..."
pip install setuptools

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to install setuptools!"
    exit 1
fi

# Install wheel
echo "Installing wheel..."
pip install wheel

# Install pybind11
echo "Installing pybind11..."
pip install pybind11

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to install pybind11!"
    exit 1
fi

# Install numpy
echo "Installing numpy..."
pip install numpy

echo "SUCCESS: Python packages installed"
echo ""

# ==============================
# 4. Check Python environment
# ==============================

echo "[4/8] Verifying Python environment..."

# Verify packages
if ! python -c "import setuptools; print('setuptools:', setuptools.__version__)" 2>/dev/null; then
    echo "ERROR: setuptools not properly installed!"
    exit 1
fi

if ! python -c "import pybind11; print('pybind11:', pybind11.__version__)" 2>/dev/null; then
    echo "ERROR: pybind11 not properly installed!"
    exit 1
fi

echo "SUCCESS: Python environment verified"
echo ""

# ==============================
# 5. Clean previous builds
# ==============================

echo "[5/8] Cleaning previous builds..."

cd build

# Clean old .so files
if ls KooCAE*.so 1> /dev/null 2>&1; then
    echo "Cleaning old .so files..."
    rm -f KooCAE*.so
fi

# Clean CMake cache if it has wrong paths
if [ -f "CMakeCache.txt" ]; then
    if grep -q "squal\|Windows\|MSVC" CMakeCache.txt 2>/dev/null; then
        echo "Cleaning conflicting CMake cache..."
        rm -f CMakeCache.txt
        rm -rf CMakeFiles
    fi
fi

# Clean Python build artifacts
rm -rf build
rm -rf *.egg-info

echo "SUCCESS: Build environment cleaned"
echo ""

# ==============================
# 6. Build C++ extension module
# ==============================

echo "[6/8] Building C++ extension module..."
echo "Running: python setup.py build_ext --inplace"

python setup.py build_ext --inplace

if [ $? -ne 0 ]; then
    echo "ERROR: C++ build failed!"
    echo ""
    echo "Trying alternative build method..."
    python setup.py build_ext --inplace --force
    
    if [ $? -ne 0 ]; then
        echo "ERROR: Alternative build also failed!"
        echo "Please check the error messages above."
        exit 1
    fi
fi

echo "SUCCESS: C++ build completed"
echo ""

# ==============================
# 7. Prepare services folder
# ==============================

echo "[7/8] Preparing services folder..."

cd "$ROOT_DIR"

if [ ! -d "services" ]; then
    echo "Creating services folder..."
    mkdir services
fi

echo "SUCCESS: Services folder ready"
echo ""

# ==============================
# 8. Deploy built module
# ==============================

echo "[8/8] Deploying built module..."

cd build

COPIED=0
SO_FILE=""

# Find KooCAE .so files
echo "Looking for built .so files..."
ls -la KooCAE*.so 2>/dev/null || echo "No .so files found yet"

for f in KooCAE*.so; do
    if [ -f "$f" ]; then
        SO_FILE="$f"
        echo "Found module: $f"
        
        echo "Copying: $f to ../services/KooCAE.so"
        cp "$f" "../services/KooCAE.so"
        
        if [ $? -eq 0 ]; then
            COPIED=1
            echo "SUCCESS: Module copied successfully"
        else
            echo "ERROR: Module copy failed"
        fi
    fi
done

# Copy .pyi stub file if exists
if [ -f "KooCAE.pyi" ]; then
    echo "Copying stub file: KooCAE.pyi"
    cp "KooCAE.pyi" "../services/" 2>/dev/null || true
fi

cd "$ROOT_DIR"

# ==============================
# Verify results and test
# ==============================

echo ""
echo "========================================"

if [ "$COPIED" = "1" ]; then
    echo "SUCCESS: Build and deployment completed!"
    echo ""
    echo "Deployed files:"
    echo "   - services/KooCAE.so"
    if [ -f "services/KooCAE.pyi" ]; then
        echo "   - services/KooCAE.pyi"
    fi
    echo ""
    
    # Test module import in Python
    echo "Testing module import..."
    if python -c "import sys; sys.path.insert(0, 'services'); import KooCAE; print('SUCCESS: KooCAE module imported successfully!')" 2>/dev/null; then
        echo "SUCCESS: Module loads correctly!"
    else
        echo "WARNING: Module import test failed."
        echo "This might be due to missing dependencies."
    fi
    
    echo ""
    echo "You can now start the Flask server:"
    echo "   python app.py"
    
else
    echo "ERROR: No .so file found!"
    echo "Build process may have failed."
    echo ""
    echo "Contents of build folder:"
    ls -la build/*.so 2>/dev/null || echo "   No .so files found."
    echo ""
    echo "Full contents of build folder:"
    ls -la build/
fi

echo "========================================"
echo ""

# ==============================
# Completion
# ==============================

if [ "$COPIED" = "1" ]; then
    echo "All tasks completed successfully!"
    echo "Flask server is ready to start."
else
    echo "Issues occurred during the process."
    echo "Please check error messages and try again."
fi

echo ""
echo "Press any key to continue..."
read -n 1
