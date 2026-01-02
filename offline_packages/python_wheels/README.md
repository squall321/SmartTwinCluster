# Python Wheels for Offline Installation

This directory contains all Python package wheels needed for offline dashboard installation.

## Directory Structure

```
python_wheels/
├── python3.10/          # Wheels for Python 3.10 (auth_portal, websocket, moonlight)
│   ├── *.whl
│   └── *.tar.gz
├── python3.12/          # Wheels for Python 3.12 (backend_5010)
│   ├── *.whl
│   └── *.tar.gz
├── python3.13/          # Wheels for Python 3.13 (CAE servers)
│   ├── *.whl
│   └── *.tar.gz
├── install_offline.sh   # Auto-detect Python version installer
└── README.md            # This file
```

## Python Version Mapping

- **Python 3.10**: auth_portal_4430, websocket_5011, backend_moonlight_8004
- **Python 3.12**: backend_5010
- **Python 3.13**: kooCAEWebServer_5000, kooCAEWebAutomationServer_5001

## Usage

### Method 1: Using the helper script (Recommended)

The script automatically detects your Python version and uses the correct wheels:

```bash
cd /path/to/service
/opt/offline_packages/python_wheels/install_offline.sh requirements.txt
```

### Method 2: Manual pip install

For Python 3.10:
```bash
pip install --no-index --find-links=/opt/offline_packages/python_wheels/python3.10 -r requirements.txt
```

For Python 3.12:
```bash
pip install --no-index --find-links=/opt/offline_packages/python_wheels/python3.12 -r requirements.txt
```

For Python 3.13:
```bash
pip install --no-index --find-links=/opt/offline_packages/python_wheels/python3.13 -r requirements.txt
```

## Generated

Created by: `download_python_wheels.sh`
Date: $(date)

All packages from dashboard services' requirements.txt are included.
