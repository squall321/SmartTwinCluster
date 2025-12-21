# Virtual Environment Setup Notes

## Problem

When running the Job Template Manager from a standard venv, the following Qt XCB plugin error occurred:

```
qt.qpa.plugin: Could not load the Qt platform plugin "xcb" in "" even though it was found.
This application failed to start because no Qt platform plugin could be initialized.
Cannot mix incompatible Qt library (5.15.3) with this library (5.15.18)
```

**Root cause**: The venv's PyQt5 (5.15.11) was incompatible with the system Qt libraries (5.15.3), creating a version mismatch.

## Solution

Recreate the virtual environment with the `--system-site-packages` flag:

```bash
# Remove old venv
rm -rf venv

# Create new venv with system site packages access
python3 -m venv venv --system-site-packages
```

This allows the venv to use the system-installed PyQt5 (5.15.6) which is compatible with the system Qt libraries (5.15.3).

## Verification

After recreating the venv:

```bash
source venv/bin/activate

# Check Python executable (should be venv's python)
python -c "import sys; print(sys.executable)"
# Output: /home/koopark/claude/.../venv/bin/python

# Check PyQt5 version (should be system PyQt5)
python -c "import PyQt5.QtCore; print(PyQt5.QtCore.PYQT_VERSION_STR)"
# Output: 5.15.6

# Check Qt version
python -c "import PyQt5.QtCore; print(PyQt5.QtCore.QT_VERSION_STR)"
# Output: 5.15.3

# Run the app
python src/main.py
# ✓ Works perfectly!
```

## Benefits of --system-site-packages

1. **Compatibility**: Uses system PyQt5 that's already compatible with system Qt libraries
2. **Disk space**: Doesn't duplicate large PyQt5 packages in venv
3. **Stability**: System packages are tested and stable
4. **Isolation**: Still maintains venv isolation for other packages (PyYAML, requests, etc.)

## Important Notes

- All required dependencies (PyYAML, requests, python-dateutil) are available through system site-packages
- The venv still provides isolation for any additional packages installed via pip
- The run.sh script works correctly with this setup
- Comprehensive tests pass successfully from venv

## Testing

Run comprehensive tests to verify all functionality:

```bash
source venv/bin/activate
python test_comprehensive.py
```

All 7 phases should pass:
- ✓ Phase 1 - Project Structure
- ✓ Phase 2 - YAML Template Loading
- ✓ Phase 3 - Template Data Model
- ✓ Phase 4 - Script Generator
- ✓ Phase 5 - Job Submitter
- ✓ Phase 6 - File Upload Widget
- ✓ Phase 7 - Workflow Integration

## Alternative Solutions Considered

1. **Install all Qt dependencies in venv**: Too complex, many system dependencies
2. **Use PyQt5-bundled Qt libraries**: Would require rebuilding PyQt5 from source
3. **System Python only**: Works but loses venv benefits

The `--system-site-packages` approach is the simplest and most reliable solution.
