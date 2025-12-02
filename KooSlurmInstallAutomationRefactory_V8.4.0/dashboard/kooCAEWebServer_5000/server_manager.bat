@echo off
REM server_manager.bat - Windows용 Flask 서버 백그라운드 관리

setlocal EnableDelayedExpansion

set SERVER_NAME=KooCAE_Server
set PID_FILE=server.pid
set LOG_FILE=server.log

if "%1"=="" (
    call :show_help
    exit /b 1
)

if "%1"=="start" call :start_server
if "%1"=="stop" call :stop_server
if "%1"=="restart" call :restart_server
if "%1"=="status" call :status_server
if "%1"=="logs" call :show_logs
if "%1"=="test" call :test_server
if "%1"=="help" call :show_help

goto :eof

:start_server
    echo 🚀 %SERVER_NAME% 시작 중...
    
    REM MOCK 모드 설정 (기본값)
    if not defined MOCK_SLURM set MOCK_SLURM=1
    
    REM 백그라운드로 서버 실행
    start /b python app.py > %LOG_FILE% 2>&1
    
    REM 잠시 대기 후 확인
    timeout /t 3 /nobreak > nul
    
    REM 서버 프로세스 찾기
    for /f "skip=3 tokens=2" %%i in ('tasklist /fi "imagename eq python.exe" /fo table') do (
        set PYTHON_PID=%%i
        goto found_pid
    )
    
    :found_pid
    if defined PYTHON_PID (
        echo ✅ %SERVER_NAME% 시작됨 (PID: !PYTHON_PID!)
        echo !PYTHON_PID! > %PID_FILE%
        echo 📋 로그 파일: %LOG_FILE%
        echo 🌐 서버 주소: http://localhost:5000
    ) else (
        echo ❌ 서버 시작 실패
        if exist %LOG_FILE% type %LOG_FILE%
    )
    goto :eof

:stop_server
    if not exist %PID_FILE% (
        echo ❌ PID 파일을 찾을 수 없습니다.
        goto :eof
    )
    
    set /p PID=<%PID_FILE%
    echo 🛑 %SERVER_NAME% 중지 중... (PID: !PID!)
    
    taskkill /PID !PID! /F > nul 2>&1
    
    if !ERRORLEVEL! equ 0 (
        echo ✅ %SERVER_NAME% 종료됨
        del %PID_FILE%
    ) else (
        echo ❌ 프로세스 종료 실패
        del %PID_FILE%
    )
    goto :eof

:restart_server
    echo 🔄 %SERVER_NAME% 재시작 중...
    call :stop_server
    timeout /t 2 /nobreak > nul
    call :start_server
    goto :eof

:status_server
    if not exist %PID_FILE% (
        echo ❌ %SERVER_NAME% 실행 중이지 않음
        goto :eof
    )
    
    set /p PID=<%PID_FILE%
    
    REM 프로세스 존재 확인
    tasklist /PID !PID! > nul 2>&1
    if !ERRORLEVEL! equ 0 (
        echo ✅ %SERVER_NAME% 실행 중 (PID: !PID!)
        echo 🌐 서버 주소: http://localhost:5000
        
        if exist %LOG_FILE% (
            for %%A in (%LOG_FILE%) do echo 📋 로그 크기: %%~zA bytes
        )
    ) else (
        echo ❌ %SERVER_NAME% 실행 중이지 않음
        del %PID_FILE%
    )
    goto :eof

:show_logs
    echo 📋 서버 로그:
    echo ==================================================
    if exist %LOG_FILE% (
        REM 마지막 50줄 표시
        powershell -command "Get-Content %LOG_FILE% | Select-Object -Last 50"
    ) else (
        echo 로그 파일이 없습니다.
    )
    goto :eof

:test_server
    echo 🧪 서버 연결 테스트...
    
    REM PowerShell을 사용한 연결 테스트
    powershell -command "try { $response = Invoke-WebRequest -Uri 'http://localhost:5000/api/job-templates' -UseBasicParsing; if ($response.StatusCode -eq 200) { Write-Host '✅ 서버 연결 성공' } else { Write-Host '❌ 서버 연결 실패' } } catch { Write-Host '❌ 서버에 연결할 수 없습니다' }"
    goto :eof

:show_help
    echo 🛠️  %SERVER_NAME% 관리 도구 (Windows)
    echo.
    echo 사용법: %0 [명령어]
    echo.
    echo 명령어:
    echo   start     - 서버 시작
    echo   stop      - 서버 중지
    echo   restart   - 서버 재시작
    echo   status    - 서버 상태 확인
    echo   logs      - 로그 보기
    echo   test      - 서버 연결 테스트
    echo   help      - 도움말 보기
    echo.
    echo 환경변수:
    echo   set MOCK_SLURM=0  - 실제 SLURM 모드
    echo   set MOCK_SLURM=1  - MOCK 모드 (기본값)
    echo.
    echo 예시:
    echo   %0 start                 # MOCK 모드로 시작
    echo   set MOCK_SLURM=0 ^& %0 start  # 실제 SLURM 모드로 시작
    echo   %0 stop                  # 서버 중지
    echo   %0 logs                  # 로그 확인
    goto :eof
