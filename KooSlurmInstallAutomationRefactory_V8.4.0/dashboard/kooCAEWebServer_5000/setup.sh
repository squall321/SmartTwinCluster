#!/bin/bash

echo "========================================"
echo "KooCAE Project Auto-Setup"
echo "========================================"
echo "Detecting platform and running appropriate initialization..."
echo ""

# Detect platform
PLATFORM=$(uname -s)
case $PLATFORM in
    Linux*)
        echo "Platform: Linux"
        ;;
    Darwin*)
        echo "Platform: macOS"
        ;;
    *)
        echo "Platform: $PLATFORM (Unknown)"
        ;;
esac
echo ""

# Make scripts executable first
chmod +x *.sh 2>/dev/null || true

# Show Python version options first
read -p "Would you like to check available Python versions first? (y/N): " CHECK_PYTHON

if [[ "$CHECK_PYTHON" =~ ^[Yy]$ ]]; then
    echo ""
    chmod +x check_python_versions.sh
    ./check_python_versions.sh
    echo ""
    echo "Now running full initialization..."
    echo ""
fi

echo "Running initialization script..."
chmod +x initialize_project.sh
./initialize_project.sh
