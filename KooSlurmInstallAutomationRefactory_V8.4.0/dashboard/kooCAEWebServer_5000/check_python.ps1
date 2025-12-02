# PowerShell Python Environment Checker
Write-Host "========================================" -ForegroundColor Green
Write-Host "Python Environment Diagnostics" -ForegroundColor Green  
Write-Host "========================================" -ForegroundColor Green

$currentDir = Get-Location
Write-Host "Current directory: $currentDir"
Write-Host ""

Write-Host "Checking Python interpreters:" -ForegroundColor Yellow
Write-Host ""

# Check Scripts\python.exe
if (Test-Path "Scripts\python.exe") {
    Write-Host "[1] ✅ Found: Scripts\python.exe" -ForegroundColor Green
    try {
        $version1 = & "Scripts\python.exe" --version 2>&1
        Write-Host "    Version: $version1" -ForegroundColor Cyan
    } catch {
        Write-Host "    Error: Cannot run" -ForegroundColor Red
    }
} else {
    Write-Host "[1] ❌ Missing: Scripts\python.exe" -ForegroundColor Red
}

# Check venv\Scripts\python.exe  
if (Test-Path "venv\Scripts\python.exe") {
    Write-Host "[2] ✅ Found: venv\Scripts\python.exe" -ForegroundColor Green
    try {
        $version2 = & "venv\Scripts\python.exe" --version 2>&1
        Write-Host "    Version: $version2" -ForegroundColor Cyan
    } catch {
        Write-Host "    Error: Cannot run" -ForegroundColor Red
    }
} else {
    Write-Host "[2] ❌ Missing: venv\Scripts\python.exe" -ForegroundColor Red
}

Write-Host ""
Write-Host "Current active Python:" -ForegroundColor Yellow

try {
    $currentPython = python --version 2>&1
    Write-Host "✅ $currentPython" -ForegroundColor Green
    
    $pythonPath = Get-Command python -ErrorAction SilentlyContinue
    if ($pythonPath) {
        Write-Host "Location: $($pythonPath.Source)" -ForegroundColor Cyan
    }
} catch {
    Write-Host "❌ Python command not found" -ForegroundColor Red
}

Write-Host ""
Write-Host "Testing Flask:" -ForegroundColor Yellow

try {
    $flaskTest = python -c "import flask; print(f'Flask {flask.__version__} OK')" 2>&1
    Write-Host "✅ $flaskTest" -ForegroundColor Green
} catch {
    Write-Host "❌ Flask import failed" -ForegroundColor Red
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "SOLUTION: VS Code Python Interpreter Setup" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "1. Open VS Code" -ForegroundColor Yellow
Write-Host "2. Press Ctrl+Shift+P" -ForegroundColor Yellow  
Write-Host "3. Type: 'Python: Select Interpreter'" -ForegroundColor Yellow
Write-Host "4. Choose a working Python from the list above" -ForegroundColor Yellow
Write-Host "5. Try F5 debugging again" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Green

Read-Host "Press Enter to continue"
