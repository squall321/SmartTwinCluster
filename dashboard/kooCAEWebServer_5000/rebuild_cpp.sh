#!/bin/bash

# ===============================================
# C++ Project Complete Rebuild Script (Linux)
# ===============================================

set -e  # Exit on error

echo "========================================"
echo "C++ Project Complete Rebuild (Linux)"
echo "========================================"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

echo "Current directory: $PWD"

echo "1. Cleaning existing build files..."
rm -rf build/cpp_only/CMakeFiles
rm -rf build/cpp_only/Debug
rm -rf build/cpp_only/Release
rm -rf build/cpp_only/build
rm -f build/cpp_only/CMakeCache.txt
rm -f build/cpp_only/*.ninja*
rm -f build/cpp_only/cmake_install.cmake
rm -f build/cpp_only/test_runner

echo "2. Moving to cpp_only directory..."
cd build/cpp_only

echo "3. Checking available build tools..."
echo "CMake: $(cmake --version | head -n1)"
echo "Ninja: $(ninja --version)"
echo "GCC: $(gcc --version | head -n1)"

echo ""
echo "4. Configuring CMake project..."

# Try Ninja first (recommended for Linux)
echo "4-1. Trying Ninja generator..."
if cmake . -G "Ninja"; then
    echo "SUCCESS: Configured with Ninja!"
    BUILD_SUCCESS=1
else
    echo "Ninja configuration failed, trying Unix Makefiles..."
    # Clean up any partial files
    rm -f CMakeCache.txt
    rm -rf CMakeFiles
    
    echo "4-2. Trying Unix Makefiles..."
    if cmake . -G "Unix Makefiles"; then
        echo "SUCCESS: Configured with Unix Makefiles!"
        BUILD_SUCCESS=1
    else
        echo "Unix Makefiles failed, trying default generator..."
        rm -f CMakeCache.txt
        rm -rf CMakeFiles
        
        echo "4-3. Trying default generator..."
        if cmake .; then
            echo "SUCCESS: Configured with default generator!"
            BUILD_SUCCESS=1
        else
            echo "ERROR: All generators failed"
            exit 1
        fi
    fi
fi

if [ "$BUILD_SUCCESS" = "1" ]; then
    echo ""
    echo "5. Building Debug configuration..."
    
    # Check if we're using Ninja
    if [ -f "build.ninja" ]; then
        echo "Using Ninja build system..."
        ninja
    else
        echo "Using Make build system..."
        make
    fi
    
    if [ $? -eq 0 ]; then
        echo "SUCCESS: Build completed!"
        
        # Look for the executable
        if [ -f "test_runner" ]; then
            echo "test_runner executable created: test_runner"
        elif [ -f "Debug/test_runner" ]; then
            echo "test_runner executable created: Debug/test_runner"
        else
            echo "Warning: test_runner executable not found in expected location"
            echo "Looking for any executables..."
            find . -name "test_runner*" -type f -executable 2>/dev/null || echo "No test_runner found"
        fi
    else
        echo "ERROR: Build failed"
        exit 1
    fi
else
    echo "ERROR: Configuration failed"
    exit 1
fi

cd "$ROOT_DIR"
echo "=== Completed ==="
