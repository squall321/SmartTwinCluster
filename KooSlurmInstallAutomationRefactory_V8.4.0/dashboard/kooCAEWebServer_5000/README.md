# 🚀 KooCAE Web Server

**Advanced CAE (Computer-Aided Engineering) Web Server with Python 3.13 Support**

## ⚡ Quick Start

### 🐍 First Time Setup (Automatic Python Version Selection)

```bash
# Windows
setup.bat

# Linux/macOS
./setup.sh
```

**That's it!** The setup script will:
- 🔍 Detect all available Python versions (3.8+)
- 💫 Recommend Python 3.13 (default choice)
- 🛠️ Set up virtual environment with your chosen version
- 📦 Install all dependencies automatically
- ⚙️ Configure VS Code for your platform
- ✅ Run tests to ensure everything works

### 🔍 Check Python Versions First

```bash
# Windows
check_python_versions.bat

# Linux/macOS  
./check_python_versions.sh
```

### 🏃‍♂️ Start Developing

1. Open project in VS Code
2. Press **F5** to start Flask server or C++ debugging
3. Visit http://localhost:5000

## 📁 What's Included

- **🌐 Flask Web Server**: RESTful API for CAE file processing
- **🔬 C++ Core Engine**: High-performance finite element processing
- **🎨 3D Visualization**: WebGL-based 3D model viewer
- **📄 File Conversion**: K-file → STL/GLB conversion
- **👥 User Management**: SQLite-based authentication
- **🎯 Job Template System**: User-defined SLURM job scheduler
- **⚡ SLURM Integration**: HPC cluster job management
- **📊 Job Monitoring**: Real-time job status and history
- **🔧 Cross-Platform**: Windows, Linux, macOS support

## 📖 Documentation

- **[SETUP_GUIDE.md](SETUP_GUIDE.md)** - Detailed setup instructions
- **[DEVELOPMENT_GUIDE.md](DEVELOPMENT_GUIDE.md)** - Development workflow

## 🐍 Python Version Support

| Version | Status | Notes |
|---------|--------|-------|
| 3.13 | ✅ **Recommended** | Best performance & latest features |
| 3.12 | ✅ Supported | Excellent compatibility |
| 3.11 | ✅ Supported | Good performance |
| 3.10 | ✅ Supported | Stable choice |
| 3.9 | ✅ Supported | Minimum for some features |
| 3.8 | ✅ Minimum | Basic compatibility |

## 🛠️ Development Commands

```bash
# Quick build C++ extension
./quick_build.sh        # Linux/macOS
quick_build.bat         # Windows

# Test environment
./test_environment.sh   # Linux/macOS
test_environment.bat    # Windows

# Start Flask server
python app.py
```

## 🔧 Platform-Specific Features

### Windows
- Visual Studio Build Tools auto-detection
- MSVC compiler optimization
- PowerShell integration

### Linux  
- GCC/Ninja build system
- Advanced package manager support
- Distribution-specific Python installation guides

### macOS
- Homebrew integration
- Apple Silicon compatibility

## 🤝 Contributing

1. Choose your Python version during setup
2. Follow the development guide
3. Test on your platform
4. Submit your improvements

## 📞 Support

If you encounter issues:
1. Run `./test_environment.sh` (or `.bat`) for diagnostics
2. Check the setup guide for common solutions
3. Ensure Python 3.8+ is installed

---

**Happy Coding! 🎉**
