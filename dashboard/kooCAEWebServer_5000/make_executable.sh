#!/bin/bash

# ===============================================
# Make all shell scripts executable
# ===============================================

echo "Making all shell scripts executable..."

chmod +x build_and_deploy.sh
chmod +x check_python.sh
chmod +x fix_python_env.sh
chmod +x install_requirements.sh
chmod +x quick_build.sh
chmod +x setup_and_build.sh
chmod +x test_dependencies.sh
chmod +x test_environment.sh
chmod +x rebuild_cpp.sh
chmod +x compileUbuntu.sh
chmod +x initialize_project.sh
chmod +x configure_vscode.sh
chmod +x setup.sh
chmod +x check_python_versions.sh

echo "All shell scripts are now executable!"
echo ""
echo "Available scripts:"
echo "  🚀 Quick Start:"
echo "    ./setup.sh               - Auto-setup with version selection"
echo "    ./initialize_project.sh   - Complete project initialization"
echo "    ./check_python_versions.sh - Check available Python versions"
echo ""
echo "  🔧 Build Scripts:"
echo "    ./build_and_deploy.sh    - Complete build and deployment"
echo "    ./quick_build.sh         - Quick C++ extension build"
echo "    ./setup_and_build.sh     - Full environment setup"
echo "    ./rebuild_cpp.sh         - Rebuild C++ project"
echo "    ./compileUbuntu.sh       - Original Ubuntu compile script"
echo ""
echo "  ⚙️ Configuration:"
echo "    ./configure_vscode.sh     - Configure VS Code settings"
echo "    ./check_python.sh        - Check Python environment"
echo "    ./fix_python_env.sh      - Diagnose Python issues"
echo ""
echo "  📦 Dependencies:"
echo "    ./install_requirements.sh - Install Python dependencies"
echo "    ./test_dependencies.sh   - Test Python dependencies"
echo "    ./test_environment.sh    - Complete environment test"
