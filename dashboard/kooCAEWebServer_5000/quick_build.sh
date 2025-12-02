#!/bin/bash

# ======================================
# KooCAE Quick Build Script (Linux)
# ======================================

set -e  # Exit on error

echo "========================================"
echo "KooCAE Quick Build Script (Linux)"
echo "========================================"

# Check essential tools
if ! command -v cmake &> /dev/null; then
    echo "ERROR: CMake not found!"
    echo "Install with: sudo apt-get install cmake"
    exit 1
fi

if ! command -v ninja &> /dev/null; then
    echo "ERROR: Ninja not found!"
    echo "Install with: sudo apt-get install ninja-build"
    exit 1
fi

if ! command -v gcc &> /dev/null; then
    echo "ERROR: GCC not found!"
    echo "Install with: sudo apt-get install build-essential"
    exit 1
fi

echo "Found build tools: CMake, Ninja, GCC"

# Activate virtual environment
if [ -f "venv/bin/activate" ]; then
    source venv/bin/activate
    echo "Virtual environment activated"
else
    echo "ERROR: Virtual environment not found!"
    echo "Create with: python3 -m venv venv"
    exit 1
fi

# Install required Python packages
echo "Installing Python packages..."
python -m pip install --upgrade pip
pip install setuptools wheel pybind11 numpy

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to install Python packages!"
    exit 1
fi

# Verify packages
echo "Verifying packages..."
if ! python -c "import setuptools, pybind11; print('Packages OK')" 2>/dev/null; then
    echo "ERROR: Package verification failed!"
    exit 1
fi

# Build
cd build

# Clean old cache if needed
if [ -f "CMakeCache.txt" ]; then
    if grep -q "squal\|Windows\|MSVC" CMakeCache.txt 2>/dev/null; then
        echo "Cleaning old cache..."
        rm -f CMakeCache.txt
        rm -rf CMakeFiles
    fi
fi

# Clean old build files
rm -rf build 2>/dev/null || true
rm -f KooCAE*.so 2>/dev/null || true

echo "Building..."
python setup.py build_ext --inplace

if [ $? -ne 0 ]; then
    echo "Build failed! Trying with force..."
    python setup.py build_ext --inplace --force
    if [ $? -ne 0 ]; then
        echo "ERROR: Build failed completely!"
        exit 1
    fi
fi

cd ..

# Prepare services folder
if [ ! -d "services" ]; then
    mkdir services
fi

# Copy .so file
cd build
echo "Looking for .so files..."
ls -la KooCAE*.so 2>/dev/null || echo "No .so files found"

for f in KooCAE*.so; do
    if [ -f "$f" ]; then
        echo "Copying $f to services folder..."
        cp "$f" "../services/KooCAE.so"
        if [ $? -eq 0 ]; then
            echo "SUCCESS: $f copied!"
        fi
    fi
done
cd ..

# Test import
echo "Testing module..."
if python -c "import sys; sys.path.insert(0, 'services'); import KooCAE; print('SUCCESS: Module works!')" 2>/dev/null; then
    echo "========================================"
    echo "Build complete! You can now run:"
    echo "   python app.py"
    echo "========================================"
else
    echo "========================================"
    echo "Build completed but module test failed."
    echo "Check dependencies and try again."
    echo "========================================"
fi

read -p "Press any key to continue..."
