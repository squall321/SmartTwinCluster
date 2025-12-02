@echo off
chcp 65001 >nul
echo === C++ Project Complete Rebuild ===

cd /d "%~dp0"
echo Current directory: %CD%

echo 1. Cleaning existing build files...
rmdir /s /q "build\cpp_only\CMakeFiles" 2>nul
rmdir /s /q "build\cpp_only\Debug" 2>nul
rmdir /s /q "build\cpp_only\Release" 2>nul
rmdir /s /q "build\cpp_only\x64" 2>nul
rmdir /s /q "build\cpp_only\build" 2>nul
rmdir /s /q "build\cpp_only\test_runner.dir" 2>nul
del /q "build\cpp_only\CMakeCache.txt" 2>nul
del /q "build\cpp_only\*.vcxproj*" 2>nul
del /q "build\cpp_only\*.sln" 2>nul
del /q "build\cpp_only\cmake_install.cmake" 2>nul

echo 2. Moving to cpp_only directory...
cd "build\cpp_only"

echo 3. Checking available CMake generators...
cmake --help | findstr "Visual Studio"

echo.
echo 4. Configuring CMake project...

echo 4-1. Trying Visual Studio 2022...
cmake . -G "Visual Studio 17 2022" -A x64
if %errorlevel% equ 0 (
    echo SUCCESS: Configured with Visual Studio 2022!
    goto BUILD
)

echo 4-2. Trying Visual Studio 2019...
cmake . -G "Visual Studio 16 2019" -A x64
if %errorlevel% equ 0 (
    echo SUCCESS: Configured with Visual Studio 2019!
    goto BUILD
)

echo 4-3. Trying MinGW Makefiles...
cmake . -G "MinGW Makefiles"
if %errorlevel% equ 0 (
    echo SUCCESS: Configured with MinGW Makefiles!
    goto BUILD
)

echo 4-4. Trying default generator...
cmake .
if %errorlevel% equ 0 (
    echo SUCCESS: Configured with default generator!
    goto BUILD
)

echo ERROR: All generators failed
goto END

:BUILD
echo.
echo 5. Building Debug configuration...
cmake --build . --config Debug

if %errorlevel% equ 0 (
    echo SUCCESS: Build completed!
    echo test_runner.exe has been created.
    if exist "Debug\test_runner.exe" (
        echo Location: Debug\test_runner.exe
    )
) else (
    echo ERROR: Build failed. Please check source code.
)

:END
cd ..\..
echo === Completed ===
pause
