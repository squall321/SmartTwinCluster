#!/bin/bash

# Make all newly created scripts executable
chmod +x setup.sh
chmod +x initialize_project.sh  
chmod +x configure_vscode.sh
chmod +x check_python_versions.sh

echo "✅ All new scripts are now executable!"
echo ""
echo "🚀 Quick Start Commands:"
echo "  ./setup.sh                   - Complete auto-setup with Python version selection"
echo "  ./check_python_versions.sh   - Check available Python versions only"
echo "  ./initialize_project.sh      - Manual project initialization"
echo "  ./configure_vscode.sh        - Configure VS Code settings only"
