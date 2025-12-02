#!/bin/bash
# server_manager.sh - Flask 서버 백그라운드 관리

SERVER_NAME="KooCAE_Server"
PID_FILE="server.pid"
LOG_FILE="server.log"
ERROR_LOG="server_error.log"

start_server() {
    if [ -f "$PID_FILE" ] && kill -0 $(cat $PID_FILE) 2>/dev/null; then
        echo "⚠️  서버가 이미 실행 중입니다 (PID: $(cat $PID_FILE))"
        return 1
    fi

    echo "🚀 $SERVER_NAME 시작 중..."
    
    # MOCK 모드 설정 (기본값)
    export MOCK_SLURM=${MOCK_SLURM:-1}
    
    # 백그라운드로 서버 실행
    nohup python app.py > $LOG_FILE 2> $ERROR_LOG &
    SERVER_PID=$!
    
    # PID 저장
    echo $SERVER_PID > $PID_FILE
    
    # 서버 시작 확인
    sleep 2
    if kill -0 $SERVER_PID 2>/dev/null; then
        echo "✅ $SERVER_NAME 시작됨 (PID: $SERVER_PID)"
        echo "📋 로그 파일: $LOG_FILE"
        echo "🌐 서버 주소: http://localhost:5000"
        return 0
    else
        echo "❌ 서버 시작 실패"
        cat $ERROR_LOG
        rm -f $PID_FILE
        return 1
    fi
}

stop_server() {
    if [ ! -f "$PID_FILE" ]; then
        echo "❌ PID 파일을 찾을 수 없습니다. 서버가 실행 중이지 않을 수 있습니다."
        return 1
    fi

    PID=$(cat $PID_FILE)
    
    if kill -0 $PID 2>/dev/null; then
        echo "🛑 $SERVER_NAME 중지 중... (PID: $PID)"
        kill $PID
        
        # 정상 종료 대기 (최대 10초)
        for i in {1..10}; do
            if ! kill -0 $PID 2>/dev/null; then
                echo "✅ $SERVER_NAME 정상 종료됨"
                rm -f $PID_FILE
                return 0
            fi
            sleep 1
        done
        
        # 강제 종료
        echo "⚡ 강제 종료 중..."
        kill -9 $PID 2>/dev/null
        rm -f $PID_FILE
        echo "✅ $SERVER_NAME 강제 종료됨"
    else
        echo "❌ 프로세스 $PID를 찾을 수 없습니다."
        rm -f $PID_FILE
        return 1
    fi
}

restart_server() {
    echo "🔄 $SERVER_NAME 재시작 중..."
    stop_server
    sleep 1
    start_server
}

status_server() {
    if [ -f "$PID_FILE" ] && kill -0 $(cat $PID_FILE) 2>/dev/null; then
        PID=$(cat $PID_FILE)
        echo "✅ $SERVER_NAME 실행 중 (PID: $PID)"
        echo "🌐 서버 주소: http://localhost:5000"
        
        # 메모리 사용량 표시
        if command -v ps >/dev/null 2>&1; then
            MEM=$(ps -o pid,pmem,comm -p $PID | tail -n 1)
            echo "💾 메모리 사용량: $MEM"
        fi
        
        # 로그 파일 크기
        if [ -f "$LOG_FILE" ]; then
            LOG_SIZE=$(wc -c < $LOG_FILE)
            echo "📋 로그 크기: $LOG_SIZE bytes"
        fi
        
        return 0
    else
        echo "❌ $SERVER_NAME 실행 중이지 않음"
        return 1
    fi
}

show_logs() {
    echo "📋 서버 로그 (마지막 50줄):"
    echo "=================================================="
    if [ -f "$LOG_FILE" ]; then
        tail -n 50 $LOG_FILE
    else
        echo "로그 파일이 없습니다."
    fi
    
    if [ -f "$ERROR_LOG" ] && [ -s "$ERROR_LOG" ]; then
        echo ""
        echo "❌ 에러 로그:"
        echo "=================================================="
        tail -n 20 $ERROR_LOG
    fi
}

follow_logs() {
    if [ -f "$LOG_FILE" ]; then
        echo "📋 실시간 로그 보기 (Ctrl+C로 종료):"
        tail -f $LOG_FILE
    else
        echo "❌ 로그 파일을 찾을 수 없습니다."
    fi
}

test_server() {
    echo "🧪 서버 연결 테스트..."
    
    if command -v curl >/dev/null 2>&1; then
        response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:5000/api/job-templates)
        if [ "$response" = "200" ]; then
            echo "✅ 서버 연결 성공"
            
            # 간단한 기능 테스트
            if python check_all_features.py > /dev/null 2>&1; then
                echo "✅ 기본 기능 테스트 통과"
            else
                echo "⚠️  일부 기능에서 문제 발견"
            fi
        else
            echo "❌ 서버 연결 실패 (HTTP: $response)"
        fi
    else
        echo "❌ curl이 설치되지 않아 테스트를 건너뜁니다."
    fi
}

show_help() {
    echo "🛠️  $SERVER_NAME 관리 도구"
    echo ""
    echo "사용법: $0 [명령어]"
    echo ""
    echo "명령어:"
    echo "  start     - 서버 시작"
    echo "  stop      - 서버 중지"
    echo "  restart   - 서버 재시작"
    echo "  status    - 서버 상태 확인"
    echo "  logs      - 로그 보기"
    echo "  follow    - 실시간 로그 보기"
    echo "  test      - 서버 연결 테스트"
    echo "  help      - 도움말 보기"
    echo ""
    echo "환경변수:"
    echo "  MOCK_SLURM=0  - 실제 SLURM 모드"
    echo "  MOCK_SLURM=1  - MOCK 모드 (기본값)"
    echo ""
    echo "예시:"
    echo "  $0 start                # MOCK 모드로 시작"
    echo "  MOCK_SLURM=0 $0 start   # 실제 SLURM 모드로 시작"
    echo "  $0 stop                 # 서버 중지"
    echo "  $0 logs                 # 로그 확인"
}

# 메인 실행 부분
case "$1" in
    start)
        start_server
        ;;
    stop)
        stop_server
        ;;
    restart)
        restart_server
        ;;
    status)
        status_server
        ;;
    logs)
        show_logs
        ;;
    follow)
        follow_logs
        ;;
    test)
        test_server
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "❌ 알 수 없는 명령어: $1"
        echo ""
        show_help
        exit 1
        ;;
esac
