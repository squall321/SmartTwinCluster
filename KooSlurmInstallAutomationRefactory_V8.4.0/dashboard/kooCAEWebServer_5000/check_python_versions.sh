#!/bin/bash

# ======================================
# Python Version Detection (Linux)
# ======================================

echo "========================================"
echo "Python Version Detection (Linux)"
echo "========================================"
echo ""

echo "🐍 Scanning for Python installations..."
echo ""

FOUND_VERSIONS=0

echo "[1] Checking Specific Python Versions..."

# Check for Python 3.13
if command -v python3.13 &> /dev/null; then
    VERSION_INFO=$(python3.13 --version 2>&1)
    echo "✅ Python 3.13: $VERSION_INFO ⭐ RECOMMENDED"
    echo "   Path: $(which python3.13)"
    FOUND_VERSIONS=$((FOUND_VERSIONS + 1))
else
    echo "❌ Python 3.13 not found"
fi

# Check for Python 3.12
if command -v python3.12 &> /dev/null; then
    VERSION_INFO=$(python3.12 --version 2>&1)
    echo "✅ Python 3.12: $VERSION_INFO"
    echo "   Path: $(which python3.12)"
    FOUND_VERSIONS=$((FOUND_VERSIONS + 1))
else
    echo "❌ Python 3.12 not found"
fi

# Check for Python 3.11
if command -v python3.11 &> /dev/null; then
    VERSION_INFO=$(python3.11 --version 2>&1)
    echo "✅ Python 3.11: $VERSION_INFO"
    echo "   Path: $(which python3.11)"
    FOUND_VERSIONS=$((FOUND_VERSIONS + 1))
else
    echo "❌ Python 3.11 not found"
fi

# Check for Python 3.10
if command -v python3.10 &> /dev/null; then
    VERSION_INFO=$(python3.10 --version 2>&1)
    echo "✅ Python 3.10: $VERSION_INFO"
    echo "   Path: $(which python3.10)"
    FOUND_VERSIONS=$((FOUND_VERSIONS + 1))
else
    echo "❌ Python 3.10 not found"
fi

# Check for Python 3.9
if command -v python3.9 &> /dev/null; then
    VERSION_INFO=$(python3.9 --version 2>&1)
    echo "✅ Python 3.9: $VERSION_INFO"
    echo "   Path: $(which python3.9)"
    FOUND_VERSIONS=$((FOUND_VERSIONS + 1))
else
    echo "❌ Python 3.9 not found"
fi

# Check for Python 3.8
if command -v python3.8 &> /dev/null; then
    VERSION_INFO=$(python3.8 --version 2>&1)
    echo "✅ Python 3.8: $VERSION_INFO"
    echo "   Path: $(which python3.8)"
    FOUND_VERSIONS=$((FOUND_VERSIONS + 1))
else
    echo "❌ Python 3.8 not found"
fi

echo ""
echo "[2] Checking Generic Python Commands..."

# Check for python3
if command -v python3 &> /dev/null; then
    VERSION_INFO=$(python3 --version 2>&1)
    echo "✅ System python3: $VERSION_INFO"
    echo "   Path: $(which python3)"
    FOUND_VERSIONS=$((FOUND_VERSIONS + 1))
else
    echo "❌ python3 command not found"
fi

# Check for python
if command -v python &> /dev/null; then
    VERSION_INFO=$(python --version 2>&1)
    if [[ $VERSION_INFO == *"Python 3"* ]]; then
        echo "✅ System python: $VERSION_INFO"
        echo "   Path: $(which python)"
        FOUND_VERSIONS=$((FOUND_VERSIONS + 1))
    else
        echo "⚠️  System python: $VERSION_INFO (Python 2 - not suitable)"
    fi
else
    echo "❌ python command not found"
fi

echo ""
echo "[3] Checking Package Manager Installations..."

# Check if we can find python installations through package managers
if command -v dpkg &> /dev/null; then
    echo "Debian/Ubuntu packages:"
    dpkg -l | grep -E "python3\.[0-9]+" | awk '{print "  " $2 " (" $3 ")"}' || echo "  No Python packages found via dpkg"
elif command -v rpm &> /dev/null; then
    echo "RPM packages:"
    rpm -qa | grep -E "python3[0-9]+" | head -5 || echo "  No Python packages found via rpm"
elif command -v pacman &> /dev/null; then
    echo "Arch packages:"
    pacman -Q | grep python | head -5 || echo "  No Python packages found via pacman"
fi

echo ""
echo "[4] Python Development Tools..."

# Check for pip
if command -v pip3 &> /dev/null; then
    PIP_VERSION=$(pip3 --version 2>&1)
    echo "✅ pip3: $PIP_VERSION"
else
    echo "❌ pip3 not found"
fi

# Check for venv capability
if python3 -m venv --help &> /dev/null; then
    echo "✅ venv module available"
else
    echo "❌ venv module not available (install python3-venv)"
fi

echo ""
echo "========================================"
echo "Summary"
echo "========================================"

if [ $FOUND_VERSIONS -gt 0 ]; then
    echo "✅ Found $FOUND_VERSIONS Python installation(s)"
    echo ""
    echo "💡 Recommendations:"
    echo "  • Python 3.13 is recommended for KooCAE project"
    echo "  • Python 3.8+ is minimum requirement"
    echo ""
    echo "Ready to run initialization:"
    echo "  ./initialize_project.sh"
else
    echo "❌ No suitable Python installations found!"
    echo ""
    echo "📥 Install Python 3.13:"
    
    # Detect distribution and give specific instructions
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case $ID in
            ubuntu|debian)
                echo "  Ubuntu/Debian:"
                echo "    sudo apt update"
                echo "    sudo apt install python3.13 python3.13-venv python3.13-pip"
                echo "    # If 3.13 not available:"
                echo "    sudo apt install python3 python3-venv python3-pip"
                ;;
            fedora)
                echo "  Fedora:"
                echo "    sudo dnf install python3.13 python3.13-pip"
                echo "    # If 3.13 not available:"
                echo "    sudo dnf install python3 python3-pip"
                ;;
            centos|rhel)
                echo "  CentOS/RHEL:"
                echo "    sudo yum install python3 python3-pip"
                echo "    # Or build from source: https://python.org/downloads/source/"
                ;;
            arch|manjaro)
                echo "  Arch Linux:"
                echo "    sudo pacman -S python python-pip"
                ;;
            *)
                echo "  Generic Linux:"
                echo "    Use your package manager to install python3"
                echo "    Or build from source: https://python.org/downloads/source/"
                ;;
        esac
    else
        echo "  Use your package manager to install python3"
        echo "  Or build from source: https://python.org/downloads/source/"
    fi
    
    echo ""
    echo "After installation, run:"
    echo "  ./check_python_versions.sh"
fi

echo "========================================"
echo ""
read -p "Press any key to continue..."
