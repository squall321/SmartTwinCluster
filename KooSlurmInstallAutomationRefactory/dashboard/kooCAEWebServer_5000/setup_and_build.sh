#!/bin/bash

# ======================================
# KooCAE Environment Setup and Build (Linux)
# ======================================

set -e  # Exit on error

echo "========================================"
echo "KooCAE Environment Setup and Build"
echo "========================================"

# Check if we're in virtual environment
python -c "import sys; print('Virtual env:', hasattr(sys, 'real_prefix') or (hasattr(sys, 'base_prefix') and sys.base_prefix != sys.prefix))"

# Activate virtual environment if not active
if [ -z "$VIRTUAL_ENV" ]; then
    if [ -f "venv/bin/activate" ]; then
        source venv/bin/activate
        echo "Virtual environment activated"
    else
        echo "ERROR: Virtual environment not found!"
        echo "Create with: python3 -m venv venv"
        exit 1
    fi
fi

# Install all requirements first
echo "Installing all requirements..."
python -m pip install --upgrade pip setuptools wheel

# Install from requirements.txt
if [ -f "requirements.txt" ]; then
    echo "Installing from requirements.txt..."
    pip install -r requirements.txt
else
    echo "requirements.txt not found, installing manually..."
    pip install setuptools wheel pybind11 numpy flask flask-cors flask-sqlalchemy
fi

# Verify key packages
echo "Verifying installation..."
python -c "import setuptools; print('setuptools version:', setuptools.__version__)"
python -c "import pybind11; print('pybind11 version:', pybind11.__version__)"

# Check build tools
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

# Build
cd build

# Clean everything
echo "Cleaning build directory..."
rm -rf build
rm -rf *.egg-info
rm -f KooCAE*.so
rm -f CMakeCache.txt
rm -rf CMakeFiles

echo "Building C++ extension..."
python setup.py clean --all
python setup.py build_ext --inplace

if [ $? -ne 0 ]; then
    echo "Build failed! Check error messages above."
    exit 1
fi

cd ..

# Deploy
if [ ! -d "services" ]; then
    mkdir services
fi

cd build
for f in KooCAE*.so; do
    if [ -f "$f" ]; then
        cp "$f" "../services/KooCAE.so"
        echo "Deployed: $f"
    fi
done
cd ..

# Test
if python -c "import sys; sys.path.insert(0, 'services'); import KooCAE; print('SUCCESS: Ready to run Flask!')" 2>/dev/null; then
    echo "========================================"
    echo "Setup complete! Run: python app.py"
    echo "========================================"
else
    echo "ERROR: Module test failed!"
    exit 1
fi

read -p "Press any key to continue..."
