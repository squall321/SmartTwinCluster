#!/bin/bash
################################################################################
# HPC Cluster Production 시작 스크립트 (Gunicorn)
# - 프론트엔드: Nginx를 통한 static 파일 서빙
# - 백엔드: Gunicorn WSGI 서버로 실행
#
# 사용법:
#   ./start_production.sh                  # 기본: 빌드 건너뛰기
#   ./start_production.sh --rebuild        # 모든 프론트엔드 재빌드
#   ./start_production.sh --skip-build     # 명시적으로 빌드 건너뛰기
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo ""
echo "============================================"
echo "  start_production.sh 실행됨"
echo "  시작 시간: $(date '+%Y-%m-%d %H:%M:%S')"
echo "  스크립트 위치: $SCRIPT_DIR"
echo "============================================"
echo ""

# sudo로 실행 시 실제 사용자 찾기
RUN_USER="${SUDO_USER:-$(whoami)}"
RUN_GROUP=$(id -gn "$RUN_USER" 2>/dev/null || echo "$RUN_USER")

echo "실행 사용자: $RUN_USER (그룹: $RUN_GROUP)"
echo ""

# ============================================================================
# PID 파일 강제 정리 (stale PID 문제 방지)
# ============================================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧹 기존 PID 파일 강제 정리..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

PID_FILES=(
    "auth_portal_4430/logs/gunicorn.pid"
    "backend_5010/logs/gunicorn.pid"
    "kooCAEWebServer_5000/logs/gunicorn.pid"
    "kooCAEWebAutomationServer_5001/logs/gunicorn.pid"
    "MoonlightSunshine_8004/backend_moonlight_8004/logs/gunicorn.pid"
    "websocket_5011/.websocket.pid"
)

CLEANED=0
for pid_file in "${PID_FILES[@]}"; do
    if [[ -f "$SCRIPT_DIR/$pid_file" ]]; then
        rm -f "$SCRIPT_DIR/$pid_file" 2>/dev/null || sudo rm -f "$SCRIPT_DIR/$pid_file" 2>/dev/null || true
        echo "  🗑️  삭제: $pid_file"
        ((CLEANED++))
    fi
done

if [[ $CLEANED -eq 0 ]]; then
    echo "  ✅ 정리할 PID 파일 없음"
else
    echo "  ✅ $CLEANED 개 PID 파일 정리 완료"
fi
echo ""

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0;33m'

# 인자 파싱
REBUILD_FRONTENDS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --rebuild)
            REBUILD_FRONTENDS=true
            shift
            ;;
        --skip-build)
            REBUILD_FRONTENDS=false
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--rebuild | --skip-build]"
            exit 1
            ;;
    esac
done

echo "=========================================="
echo "🚀 HPC Cluster Production 모드 시작 (Gunicorn)"
echo "=========================================="
echo ""

# ==================== 0. 프론트엔드 빌드 ====================
echo -e "${BLUE}[0/9] 프론트엔드 빌드 확인 중...${NC}"
if [ "$REBUILD_FRONTENDS" = true ]; then
    echo "  → 프론트엔드 재빌드 진행 (--rebuild 플래그 사용)"
    if [ -f "./build_all_frontends.sh" ]; then
        ./build_all_frontends.sh
        if [ $? -ne 0 ]; then
            echo -e "${RED}❌ 프론트엔드 빌드 실패. 계속 진행합니다...${NC}"
        fi
    else
        echo -e "${RED}❌ build_all_frontends.sh를 찾을 수 없습니다${NC}"
    fi
else
    echo "  → 프론트엔드 빌드 건너뛰기 (기존 빌드 파일 사용)"
    echo "  → 재빌드가 필요하면: ./start_production.sh --rebuild"
fi
echo ""

# ==================== 1. 기존 서비스 종료 ====================
echo -e "${BLUE}[1/9] 기존 서비스 종료 중...${NC}"

# Dev 서버 포트 강제 종료
echo "  → Dev 서버 포트 강제 종료 (3010, 8002, 5173, 5174, 8003)..."
fuser -k 3010/tcp 2>/dev/null
fuser -k 8002/tcp 2>/dev/null
fuser -k 5173/tcp 2>/dev/null
fuser -k 5174/tcp 2>/dev/null
fuser -k 8003/tcp 2>/dev/null  # Moonlight Frontend Dev Server

# Snap prometheus 종료
if command -v snap &> /dev/null; then
    echo "  → Snap Prometheus 종료 중..."
    snap stop prometheus 2>/dev/null || true
    echo "    ✓ Snap Prometheus 중지됨"
fi

echo -e "${GREEN}✅ 기존 서비스 종료 완료${NC}"
echo ""

# ==================== 2. Redis 확인 및 강제 설정 ====================
echo -e "${BLUE}[2/9] Redis 확인 및 설정 중...${NC}"

# YAML에서 Redis 비밀번호 읽기
YAML_CONFIG="$SCRIPT_DIR/../my_multihead_cluster.yaml"
if [ -f "$YAML_CONFIG" ]; then
    REDIS_PASSWORD=$(python3 -c "
import yaml
with open('$YAML_CONFIG') as f:
    config = yaml.safe_load(f)
    password = config.get('redis', {}).get('cluster', {}).get('password', '') or config.get('redis', {}).get('password', '')
    print(password if password else '')
" 2>/dev/null)
    echo -e "${BLUE}  → YAML에서 Redis 비밀번호 로드됨${NC}"
else
    REDIS_PASSWORD=""
    echo -e "${YELLOW}  → YAML 파일 없음, Redis 비밀번호 없이 진행${NC}"
fi

# Redis 설정 파일 업데이트 (비밀번호 강제 설정)
REDIS_CONF="/etc/redis/redis.conf"
if [ -f "$REDIS_CONF" ] && [ -n "$REDIS_PASSWORD" ]; then
    echo -e "${BLUE}  → Redis 비밀번호 설정 업데이트 중...${NC}"
    # 기존 requirepass 라인 제거 및 새로 추가
    sudo sed -i '/^requirepass /d' "$REDIS_CONF" 2>/dev/null || true
    sudo sed -i '/^# requirepass /d' "$REDIS_CONF" 2>/dev/null || true
    echo "requirepass $REDIS_PASSWORD" | sudo tee -a "$REDIS_CONF" > /dev/null 2>&1 || true
fi

# Redis 상태 확인 및 시작/재시작
if pgrep -x redis-server > /dev/null; then
    echo -e "${YELLOW}  → Redis 재시작 중 (비밀번호 설정 적용)...${NC}"
    sudo systemctl restart redis-server 2>/dev/null || {
        # systemd 실패 시 수동 재시작
        pkill redis-server 2>/dev/null || true
        sleep 1
        if [ -n "$REDIS_PASSWORD" ]; then
            redis-server --daemonize yes --requirepass "$REDIS_PASSWORD" 2>/dev/null
        else
            redis-server --daemonize yes 2>/dev/null
        fi
    }
    sleep 2
else
    echo -e "${YELLOW}  → Redis 시작 중...${NC}"
    # systemd로 시작 시도
    if sudo systemctl start redis-server 2>/dev/null; then
        sleep 2
        echo -e "${GREEN}  → Redis (systemd) 시작됨${NC}"
    else
        # 수동 시작 (비밀번호 포함)
        if [ -n "$REDIS_PASSWORD" ]; then
            redis-server --daemonize yes --requirepass "$REDIS_PASSWORD" 2>/dev/null
        else
            redis-server --daemonize yes 2>/dev/null
        fi
        sleep 1
    fi
fi

# Redis 연결 테스트
if [ -n "$REDIS_PASSWORD" ]; then
    if redis-cli -a "$REDIS_PASSWORD" ping 2>/dev/null | grep -q "PONG"; then
        echo -e "${GREEN}✅ Redis 연결 확인됨 (인증 성공)${NC}"
    else
        echo -e "${RED}❌ Redis 연결 실패 - 수동 확인 필요${NC}"
    fi
else
    if redis-cli ping 2>/dev/null | grep -q "PONG"; then
        echo -e "${GREEN}✅ Redis 연결 확인됨 (비밀번호 없음)${NC}"
    else
        echo -e "${RED}❌ Redis 연결 실패${NC}"
    fi
fi

# REDIS_PASSWORD를 전역으로 export (다른 서비스들이 사용)
export REDIS_PASSWORD
echo ""

# ==================== 3. SAML-IdP 시작 ====================
echo -e "${BLUE}[3/9] SAML-IdP 시작 중...${NC}"
if [ -d "saml_idp_8080" ]; then
    cd saml_idp_8080
    if [ -f "start.sh" ]; then
        if pgrep -f "saml_idp.*8080" > /dev/null; then
            echo -e "${YELLOW}⚠  SAML-IdP가 이미 실행 중입니다.${NC}"
        else
            ./start.sh > /dev/null 2>&1 &
            sleep 2
            echo -e "${GREEN}✅ SAML-IdP 시작됨 (Port: 8080)${NC}"
        fi
    fi
    cd "$SCRIPT_DIR"
fi
echo ""

# ==================== 4. Auth Backend (Gunicorn) ====================
echo -e "${BLUE}[4/9] Auth Backend 시작 중 (Gunicorn)...${NC}"

# 기존 Auth Backend 프로세스 정리
echo -e "${YELLOW}  → 기존 Auth Backend 프로세스 정리 중...${NC}"

# 1. Gunicorn 프로세스 종료
pkill -9 -f "gunicorn.*auth_portal_4430" 2>/dev/null || true
sleep 1

# 2. 포트 4430 사용 중인 프로세스 강제 종료
fuser -k -9 4430/tcp 2>/dev/null || true
sleep 1

# 3. PID 파일 확인 및 정리
if [ -f "auth_portal_4430/logs/gunicorn.pid" ]; then
    OLD_PID=$(cat auth_portal_4430/logs/gunicorn.pid 2>/dev/null)
    if [ -n "$OLD_PID" ] && kill -0 $OLD_PID 2>/dev/null; then
        echo -e "${YELLOW}  → PID 파일의 프로세스($OLD_PID) 종료 중...${NC}"
        kill -9 $OLD_PID 2>/dev/null || true
        sleep 1
    fi
    # Stale PID 파일 삭제 (프로세스 유무와 관계없이)
    rm -f auth_portal_4430/logs/gunicorn.pid
fi

# 4. 포트가 완전히 해제될 때까지 대기 (최대 5초)
for i in {1..5}; do
    if ! fuser 4430/tcp >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

cd auth_portal_4430
echo "  [DEBUG] 현재 디렉토리: $(pwd)"
echo "  [DEBUG] 사용자: $(whoami), RUN_USER=$RUN_USER"
mkdir -p logs

# Python 캐시 삭제
find . -type f -name "*.pyc" -delete 2>/dev/null || true
find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true

# 기존 로그 백업
if [ -f "logs/gunicorn.log" ]; then
    mv logs/gunicorn.log logs/gunicorn_prev.log 2>/dev/null || true
fi

# 환경 검사
echo "  [DEBUG] === 환경 검사 ==="
echo "  [DEBUG] venv 존재: $([ -d 'venv' ] && echo 'YES' || echo 'NO')"
echo "  [DEBUG] venv/bin/python 존재: $([ -f 'venv/bin/python' ] && echo 'YES' || echo 'NO')"
echo "  [DEBUG] venv/bin/gunicorn 존재: $([ -f 'venv/bin/gunicorn' ] && echo 'YES' || echo 'NO')"
echo "  [DEBUG] gunicorn_config.py 존재: $([ -f 'gunicorn_config.py' ] && echo 'YES' || echo 'NO')"
echo "  [DEBUG] app.py 존재: $([ -f 'app.py' ] && echo 'YES' || echo 'NO')"
echo "  [DEBUG] logs 디렉토리 쓰기 가능: $([ -w 'logs' ] && echo 'YES' || echo 'NO')"
if [ -d "venv" ]; then
    echo "  [DEBUG] Python 버전: $(venv/bin/python --version 2>&1)"
    echo "  [DEBUG] gunicorn 버전: $(venv/bin/gunicorn --version 2>&1 || echo 'NOT INSTALLED')"
fi
echo "  [DEBUG] =================="

# Python import 테스트
if [ -d "venv" ]; then
    echo "  → Python import 테스트 중..."
    if ! venv/bin/python -c "from app import app; print('OK')" 2>logs/import_error.log; then
        echo -e "${RED}   ❌ Python import 실패:${NC}"
        cat logs/import_error.log
    else
        echo "  [DEBUG] Python import 성공"
    fi
fi

# Auth Backend 시작 (REDIS_PASSWORD 환경변수 전달)
echo "  [DEBUG] === gunicorn 실행 시작 ==="
echo "  [DEBUG] REDIS_PASSWORD 설정: $([ -n \"$REDIS_PASSWORD\" ] && echo 'YES' || echo 'NO')"

# 포트 사용 확인
echo "  [DEBUG] 포트 4430 사용 상태:"
fuser 4430/tcp 2>/dev/null && echo "  [DEBUG]   포트 사용 중!" || echo "  [DEBUG]   포트 사용 안함 (OK)"

if [ -d "venv" ]; then
    GUNICORN_CMD="venv/bin/gunicorn -c gunicorn_config.py --pid logs/gunicorn.pid app:app"
    echo "  [DEBUG] 실행 명령: REDIS_PASSWORD=*** $GUNICORN_CMD"

    # 먼저 포그라운드로 테스트 실행 (에러 확인용, 1초 타임아웃)
    echo "  [DEBUG] === 포그라운드 테스트 실행 (에러 확인) ==="
    timeout 2 bash -c "REDIS_PASSWORD='$REDIS_PASSWORD' venv/bin/gunicorn -c gunicorn_config.py app:app --check-config" 2>&1 || true
    echo "  [DEBUG] === 테스트 완료 ==="

    echo "  [DEBUG] 백그라운드 실행 시작..."

    # 실행 전 상태
    echo "  [DEBUG] 실행 전 gunicorn 프로세스: $(pgrep -f 'gunicorn.*auth_portal_4430' | wc -l)개"

    # 백그라운드 실행 (stderr도 캡처)
    REDIS_PASSWORD="$REDIS_PASSWORD" venv/bin/gunicorn -c gunicorn_config.py --pid logs/gunicorn.pid app:app > logs/gunicorn.log 2>&1 &
    GUNICORN_BG_PID=$!
    echo "  [DEBUG] 백그라운드 PID: $GUNICORN_BG_PID"

    # 프로세스 상태 확인
    echo "  [DEBUG] 프로세스 $GUNICORN_BG_PID 상태:"
    ps -p $GUNICORN_BG_PID -o pid,stat,command 2>/dev/null || echo "  [DEBUG]   프로세스가 이미 종료됨"

    # wait로 종료 코드 확인 (비블로킹)
    if ! kill -0 $GUNICORN_BG_PID 2>/dev/null; then
        echo "  [DEBUG] ⚠ 프로세스가 즉시 종료됨! wait로 종료 코드 확인..."
        wait $GUNICORN_BG_PID 2>/dev/null
        EXIT_CODE=$?
        echo "  [DEBUG] 종료 코드: $EXIT_CODE"
    fi

    # 잠시 대기
    echo "  [DEBUG] 3초 대기 중..."
    sleep 3

    # 실행 후 상태
    echo "  [DEBUG] 실행 후 gunicorn 프로세스: $(pgrep -f 'gunicorn.*auth_portal_4430' | wc -l)개"
    echo "  [DEBUG] 프로세스 목록:"
    pgrep -af "gunicorn.*auth_portal_4430" 2>/dev/null || echo "  [DEBUG]   (없음)"

    # PID 파일 확인
    echo "  [DEBUG] PID 파일 존재: $([ -f 'logs/gunicorn.pid' ] && echo 'YES' || echo 'NO')"
    if [ -f "logs/gunicorn.pid" ]; then
        PID_CONTENT=$(cat logs/gunicorn.pid)
        echo "  [DEBUG] PID 파일 내용: $PID_CONTENT"
        echo "  [DEBUG] PID $PID_CONTENT 프로세스 상태:"
        ps -p $PID_CONTENT -o pid,stat,command 2>/dev/null || echo "  [DEBUG]   해당 PID 프로세스 없음"
    fi

    BACKEND_PID=$(pgrep -f "gunicorn.*auth_portal_4430" | head -1)
    echo "  [DEBUG] 최종 PID: ${BACKEND_PID:-없음}"

    # 로그 파일 소유권 수정
    chown "$RUN_USER:$RUN_GROUP" logs/*.log logs/*.pid 2>/dev/null || true

    # 로그 파일 확인
    echo "  [DEBUG] gunicorn.log 존재: $([ -f 'logs/gunicorn.log' ] && echo 'YES' || echo 'NO')"
    if [ -f "logs/gunicorn.log" ]; then
        LOG_SIZE=$(wc -c < logs/gunicorn.log)
        echo "  [DEBUG] gunicorn.log 크기: ${LOG_SIZE}바이트"
        if [ "$LOG_SIZE" -gt 0 ]; then
            echo "  [DEBUG] === gunicorn.log 내용 (전체) ==="
            cat logs/gunicorn.log
            echo "  [DEBUG] ==================================="
        else
            echo "  [DEBUG] ⚠ 로그가 비어있음 - gunicorn이 시작 직후 죽었을 가능성"
        fi
    fi

    # gunicorn_prev.log도 확인
    if [ -f "logs/gunicorn_prev.log" ]; then
        echo "  [DEBUG] === 이전 gunicorn.log (참고용) ==="
        tail -10 logs/gunicorn_prev.log
        echo "  [DEBUG] =================================="
    fi
else
    echo "  [DEBUG] venv 없음, 시스템 gunicorn 사용"
    REDIS_PASSWORD="$REDIS_PASSWORD" gunicorn -c gunicorn_config.py --pid logs/gunicorn.pid app:app > logs/gunicorn.log 2>&1 &
    sleep 3
    BACKEND_PID=$(pgrep -f "gunicorn.*auth_portal_4430" | head -1)
fi
echo "  [DEBUG] === gunicorn 실행 완료 ==="
cd "$SCRIPT_DIR"

# 시작 확인
sleep 3
if pgrep -f "gunicorn.*auth_portal_4430" > /dev/null; then
    HEALTH_STATUS=$(curl -s http://localhost:4430/health 2>/dev/null | grep -o '"status":"healthy"' || echo "")
    if [ -n "$HEALTH_STATUS" ]; then
        echo -e "${GREEN}✅ Auth Backend 시작됨 (Gunicorn, PID: $BACKEND_PID, Port: 4430)${NC}"
        echo -e "${GREEN}   API 상태: 정상${NC}"
    else
        echo -e "${YELLOW}⚠  Auth Backend 시작됨 but API 응답 없음${NC}"
    fi
else
    echo -e "${RED}❌ Auth Backend 시작 실패${NC}"
    echo -e "${RED}   로그 파일: $SCRIPT_DIR/auth_portal_4430/logs/gunicorn.log${NC}"
    if [ -f "$SCRIPT_DIR/auth_portal_4430/logs/gunicorn.log" ]; then
        echo -e "${YELLOW}   === 최근 로그 (마지막 20줄) ===${NC}"
        tail -20 "$SCRIPT_DIR/auth_portal_4430/logs/gunicorn.log" 2>/dev/null || echo "   (로그 읽기 실패)"
        echo -e "${YELLOW}   ================================${NC}"
    else
        echo -e "${YELLOW}   로그 파일이 없습니다. venv 또는 gunicorn 설치 확인 필요${NC}"
        # venv 존재 확인
        if [ ! -d "$SCRIPT_DIR/auth_portal_4430/venv" ]; then
            echo -e "${RED}   ⚠ venv 디렉토리가 없습니다!${NC}"
        fi
        # gunicorn 설치 확인
        if [ -d "$SCRIPT_DIR/auth_portal_4430/venv" ]; then
            if ! "$SCRIPT_DIR/auth_portal_4430/venv/bin/pip" show gunicorn > /dev/null 2>&1; then
                echo -e "${RED}   ⚠ gunicorn이 설치되지 않았습니다!${NC}"
            fi
        fi
    fi
fi
echo ""

# ==================== 5. Auth Frontend (정적 파일 서빙) ====================
echo -e "${BLUE}[5/9] Auth Frontend 확인 중...${NC}"
# Auth Portal은 이제 Nginx가 /var/www/html/auth_portal에서 정적 파일로 서빙합니다.
# Dev 서버(npm run dev)는 더 이상 사용하지 않습니다.

# 혹시 실행 중인 dev 서버가 있다면 종료
if pgrep -f "vite.*auth_portal_4431" > /dev/null; then
    echo -e "${YELLOW}  → 기존 Auth Frontend Dev 서버 종료 중...${NC}"
    pkill -f "vite.*auth_portal_4431"
    sleep 1
fi

# 정적 파일 존재 확인
if [ -d "/var/www/html/auth_portal" ] && [ -f "/var/www/html/auth_portal/index.html" ]; then
    echo -e "${GREEN}✅ Auth Frontend 정적 파일 확인됨 (/var/www/html/auth_portal)${NC}"
    echo "  → Nginx가 정적 파일로 서빙합니다 (Port 80/443, Path: /)"
else
    echo -e "${YELLOW}⚠  Auth Frontend 빌드 파일이 없습니다${NC}"
    echo "  → 빌드 필요: ./build_all_frontends.sh --frontend auth_portal_4431"
fi
echo ""

# ==================== 6. Dashboard Backend (Gunicorn) ====================
echo -e "${BLUE}[6/9] Dashboard Backend + WebSocket 시작 중...${NC}"

# YAML 파일에서 SSO 및 Redis 설정 읽기
YAML_CONFIG="$SCRIPT_DIR/../my_multihead_cluster.yaml"
if [ -f "$YAML_CONFIG" ]; then
    SSO_ENABLED=$(python3 -c "
import yaml
with open('$YAML_CONFIG') as f:
    config = yaml.safe_load(f)
    sso_enabled = config.get('sso', {}).get('enabled', True)
    print('true' if sso_enabled else 'false')
" 2>/dev/null)
    REDIS_PASSWORD=$(python3 -c "
import yaml
with open('$YAML_CONFIG') as f:
    config = yaml.safe_load(f)
    # redis.cluster.password 또는 redis.password 사용
    password = config.get('redis', {}).get('cluster', {}).get('password', '') or config.get('redis', {}).get('password', '')
    print(password if password else 'changeme')
" 2>/dev/null)
    echo -e "${BLUE}  → SSO 설정: SSO_ENABLED=$SSO_ENABLED (from YAML)${NC}"
    echo -e "${BLUE}  → Redis 설정: REDIS_PASSWORD 로드됨 (from YAML)${NC}"
else
    SSO_ENABLED="true"
    REDIS_PASSWORD="changeme"
    echo -e "${YELLOW}  → YAML 파일 없음, 기본값 사용${NC}"
fi

# 기존 Dashboard Backend 프로세스 정리
echo -e "${YELLOW}  → 기존 Dashboard Backend 프로세스 정리 중...${NC}"

# 1. Gunicorn 프로세스 종료
pkill -9 -f "gunicorn.*backend_5010" 2>/dev/null || true
sleep 1

# 2. 포트 5010 사용 중인 프로세스 강제 종료
fuser -k -9 5010/tcp 2>/dev/null || true
sleep 1

# 3. PID 파일 확인 및 정리
if [ -f "backend_5010/logs/gunicorn.pid" ]; then
    OLD_PID=$(cat backend_5010/logs/gunicorn.pid 2>/dev/null)
    if [ -n "$OLD_PID" ] && kill -0 $OLD_PID 2>/dev/null; then
        echo -e "${YELLOW}  → PID 파일의 프로세스($OLD_PID) 종료 중...${NC}"
        kill -9 $OLD_PID 2>/dev/null || true
        sleep 1
    fi
    # Stale PID 파일 삭제 (프로세스 유무와 관계없이)
    rm -f backend_5010/logs/gunicorn.pid
fi

# 4. 포트가 완전히 해제될 때까지 대기 (최대 5초)
for i in {1..5}; do
    if ! fuser 5010/tcp >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

cd backend_5010
mkdir -p logs

# Python 캐시 삭제
find . -type f -name "*.pyc" -delete 2>/dev/null || true
find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true

# 기존 로그 백업
if [ -f "logs/gunicorn.log" ]; then
    mv logs/gunicorn.log logs/gunicorn_prev.log 2>/dev/null || true
fi

# Python import 테스트
if [ -d "venv" ]; then
    echo "  → Python import 테스트 중..."
    if ! venv/bin/python -c "from app import app; print('OK')" 2>logs/import_error.log; then
        echo -e "${RED}   ❌ Python import 실패:${NC}"
        cat logs/import_error.log
    fi
fi

# Dashboard Backend 시작
# venv/bin/gunicorn 직접 실행 (activate 불필요)
if [ -d "venv" ]; then
    MOCK_MODE=false SSO_ENABLED="$SSO_ENABLED" REDIS_PASSWORD="$REDIS_PASSWORD" nohup venv/bin/gunicorn -c gunicorn_config.py --pid logs/gunicorn.pid app:app > logs/gunicorn.log 2>&1 &
    sleep 1
    DB_BACKEND_PID=$(pgrep -f "gunicorn.*backend_5010" | head -1)
    chown "$RUN_USER:$RUN_GROUP" logs/*.log logs/*.pid 2>/dev/null || true
else
    MOCK_MODE=false SSO_ENABLED="$SSO_ENABLED" REDIS_PASSWORD="$REDIS_PASSWORD" nohup gunicorn -c gunicorn_config.py --pid logs/gunicorn.pid app:app > logs/gunicorn.log 2>&1 &
    sleep 1
    DB_BACKEND_PID=$(pgrep -f "gunicorn.*backend_5010" | head -1)
fi
cd "$SCRIPT_DIR"

# 시작 확인
sleep 3
if pgrep -f "gunicorn.*backend_5010" > /dev/null; then
    HEALTH_STATUS=$(curl -s http://localhost:5010/api/health 2>/dev/null | grep -o '"status":"healthy"' || echo "")
    if [ -n "$HEALTH_STATUS" ]; then
        echo -e "${GREEN}✅ Dashboard Backend 시작됨 (Gunicorn, PID: $DB_BACKEND_PID, Port: 5010)${NC}"
        echo -e "${GREEN}   API 상태: 정상${NC}"
    else
        echo -e "${YELLOW}⚠  Dashboard Backend 시작됨 but API 응답 없음${NC}"
    fi
else
    echo -e "${RED}❌ Dashboard Backend 시작 실패${NC}"
    echo -e "${RED}   로그 파일: $SCRIPT_DIR/backend_5010/logs/gunicorn.log${NC}"
    if [ -f "$SCRIPT_DIR/backend_5010/logs/gunicorn.log" ]; then
        echo -e "${YELLOW}   === 최근 로그 (마지막 20줄) ===${NC}"
        tail -20 "$SCRIPT_DIR/backend_5010/logs/gunicorn.log" 2>/dev/null || echo "   (로그 읽기 실패)"
        echo -e "${YELLOW}   ================================${NC}"
    else
        echo -e "${YELLOW}   로그 파일이 없습니다. venv 또는 gunicorn 설치 확인 필요${NC}"
        if [ ! -d "$SCRIPT_DIR/backend_5010/venv" ]; then
            echo -e "${RED}   ⚠ venv 디렉토리가 없습니다!${NC}"
        fi
    fi
fi

# WebSocket Server (Flask dev - WebSocket용)
if pgrep -f "websocket_5011.*python" > /dev/null; then
    echo -e "${YELLOW}  → WebSocket Server 재시작 중...${NC}"
    pkill -f "websocket_5011.*python"
    sleep 1
fi

cd websocket_5011
mkdir -p logs
rm -f websocket.log
# venv/bin/python 직접 실행 (activate 불필요)
if [ -d "venv" ]; then
    SSO_ENABLED="$SSO_ENABLED" REDIS_PASSWORD="$REDIS_PASSWORD" nohup venv/bin/python websocket_server_enhanced.py > websocket.log 2>&1 &
else
    SSO_ENABLED="$SSO_ENABLED" REDIS_PASSWORD="$REDIS_PASSWORD" nohup python3 websocket_server_enhanced.py > websocket.log 2>&1 &
fi
sleep 1
WS_PID=$(pgrep -f "websocket_5011.*python" | head -1)
echo $WS_PID > .websocket.pid
chown "$RUN_USER:$RUN_GROUP" websocket.log .websocket.pid 2>/dev/null || true
cd "$SCRIPT_DIR"
echo -e "${GREEN}✅ WebSocket Server 시작됨 (PID: $WS_PID, Port: 5011)${NC}"

# Prometheus (선택사항)
if [ -d "prometheus_9090" ] && [ -f "prometheus_9090/start.sh" ]; then
    cd prometheus_9090
    ./start.sh > /dev/null 2>&1
    cd "$SCRIPT_DIR"
    echo -e "${GREEN}✅ Prometheus 시작됨 (Port: 9090)${NC}"
fi

# Node Exporter (선택사항)
if [ -d "node_exporter_9100" ] && [ -f "node_exporter_9100/start.sh" ]; then
    cd node_exporter_9100
    ./start.sh > /dev/null 2>&1
    cd "$SCRIPT_DIR"
    echo -e "${GREEN}✅ Node Exporter 시작됨 (Port: 9100)${NC}"
fi
echo ""

# ==================== 7. Backend 설정 확인 ====================
echo -e "${BLUE}[7/9] Backend 설정 확인 중...${NC}"
if [ ! -f "backend_5010/.env" ]; then
    echo "MOCK_MODE=false" > backend_5010/.env
    echo -e "${GREEN}✅ .env 파일 생성 완료${NC}"
fi
echo ""

# ==================== 8. Moonlight Backend (Gunicorn) ====================
echo -e "${BLUE}[8/10] Moonlight Backend 시작 중 (Gunicorn)...${NC}"

# 기존 Moonlight 프로세스 정리
echo -e "${YELLOW}  → 기존 Moonlight Backend 프로세스 정리 중...${NC}"

# 1. Gunicorn 프로세스 종료
pkill -9 -f "gunicorn.*backend_moonlight_8004" 2>/dev/null || true
sleep 1

# 2. 포트 8004 사용 중인 프로세스 강제 종료
fuser -k -9 8004/tcp 2>/dev/null || true
sleep 1

# 3. PID 파일 확인 및 정리
if [ -f "MoonlightSunshine_8004/backend_moonlight_8004/logs/gunicorn.pid" ]; then
    OLD_PID=$(cat MoonlightSunshine_8004/backend_moonlight_8004/logs/gunicorn.pid 2>/dev/null)
    if [ -n "$OLD_PID" ] && kill -0 $OLD_PID 2>/dev/null; then
        echo -e "${YELLOW}  → PID 파일의 프로세스($OLD_PID) 종료 중...${NC}"
        kill -9 $OLD_PID 2>/dev/null || true
        sleep 1
    fi
    # Stale PID 파일 삭제 (프로세스 유무와 관계없이)
    rm -f MoonlightSunshine_8004/backend_moonlight_8004/logs/gunicorn.pid
fi

# 4. 포트가 완전히 해제될 때까지 대기 (최대 5초)
for i in {1..5}; do
    if ! fuser 8004/tcp >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

if [ -d "MoonlightSunshine_8004/backend_moonlight_8004" ]; then
    cd MoonlightSunshine_8004/backend_moonlight_8004
    mkdir -p logs

    # Python 캐시 삭제 (코드 변경사항 즉시 반영 위해)
    echo -e "${YELLOW}  → Python 캐시 삭제 중...${NC}"
    find . -type f -name "*.pyc" -delete 2>/dev/null || true
    find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true

    # 기존 로그 백업
    if [ -f "logs/gunicorn.log" ]; then
        mv logs/gunicorn.log logs/gunicorn_prev.log 2>/dev/null || true
    fi

    # Python import 테스트
    if [ -d "venv" ]; then
        echo "  → Python import 테스트 중..."
        if ! venv/bin/python -c "from app import app; print('OK')" 2>logs/import_error.log; then
            echo -e "${RED}   ❌ Python import 실패:${NC}"
            cat logs/import_error.log
        fi
    fi

    # Moonlight Backend 시작
    # venv/bin/gunicorn 직접 실행 (activate 불필요)
    if [ -d "venv" ]; then
        REDIS_PASSWORD="$REDIS_PASSWORD" nohup venv/bin/gunicorn -c gunicorn_config.py --pid logs/gunicorn.pid app:app > logs/gunicorn.log 2>&1 &
        sleep 1
        MOONLIGHT_PID=$(pgrep -f "gunicorn.*backend_moonlight_8004" | head -1)
        chown "$RUN_USER:$RUN_GROUP" logs/*.log logs/*.pid 2>/dev/null || true
    else
        REDIS_PASSWORD="$REDIS_PASSWORD" nohup gunicorn -c gunicorn_config.py --pid logs/gunicorn.pid app:app > logs/gunicorn.log 2>&1 &
        sleep 1
        MOONLIGHT_PID=$(pgrep -f "gunicorn.*backend_moonlight_8004" | head -1)
    fi

    # 시작 확인 (프로세스 + API 테스트)
    sleep 3
    if pgrep -f "gunicorn.*backend_moonlight_8004" > /dev/null; then
        # API Health Check
        HEALTH_STATUS=$(curl -s http://localhost:8004/health 2>/dev/null | grep -o '"status":"healthy"' || echo "")
        if [ -n "$HEALTH_STATUS" ]; then
            echo -e "${GREEN}✅ Moonlight Backend 시작됨 (Gunicorn, PID: $MOONLIGHT_PID, Port: 8004)${NC}"
            echo -e "${GREEN}   API 상태: 정상${NC}"
        else
            echo -e "${YELLOW}⚠  Moonlight Backend 시작됨 but API 응답 없음 - 확인 필요${NC}"
        fi
    else
        echo -e "${RED}❌ Moonlight Backend 시작 실패${NC}"
        echo -e "${RED}   로그 파일: $SCRIPT_DIR/MoonlightSunshine_8004/backend_moonlight_8004/logs/gunicorn.log${NC}"
        if [ -f "logs/gunicorn.log" ]; then
            echo -e "${YELLOW}   === 최근 로그 (마지막 15줄) ===${NC}"
            tail -15 logs/gunicorn.log 2>/dev/null || echo "   (로그 읽기 실패)"
            echo -e "${YELLOW}   ================================${NC}"
        else
            echo -e "${YELLOW}   로그 파일이 없습니다. venv 또는 gunicorn 설치 확인 필요${NC}"
            if [ ! -d "venv" ]; then
                echo -e "${RED}   ⚠ venv 디렉토리가 없습니다!${NC}"
            fi
        fi
    fi
    cd "$SCRIPT_DIR"
else
    echo -e "${YELLOW}⚠  Moonlight Backend 디렉토리 없음${NC}"
fi
echo ""

# ==================== 9. CAE Services (Gunicorn) ====================
echo -e "${BLUE}[9/10] CAE Services 시작 중 (Gunicorn)...${NC}"

# ===== CAE Backend (5000) =====
echo -e "${YELLOW}  → 기존 CAE Backend 프로세스 정리 중...${NC}"

# 1. Gunicorn 프로세스 종료
pkill -9 -f "gunicorn.*kooCAEWebServer_5000" 2>/dev/null || true
sleep 1

# 2. 포트 5000 사용 중인 프로세스 강제 종료
fuser -k -9 5000/tcp 2>/dev/null || true
sleep 1

# 3. PID 파일 확인 및 정리
if [ -f "kooCAEWebServer_5000/logs/gunicorn.pid" ]; then
    OLD_PID=$(cat kooCAEWebServer_5000/logs/gunicorn.pid 2>/dev/null)
    if [ -n "$OLD_PID" ] && kill -0 $OLD_PID 2>/dev/null; then
        echo -e "${YELLOW}  → PID 파일의 프로세스($OLD_PID) 종료 중...${NC}"
        kill -9 $OLD_PID 2>/dev/null || true
        sleep 1
    fi
    # Stale PID 파일 삭제 (프로세스 유무와 관계없이)
    rm -f kooCAEWebServer_5000/logs/gunicorn.pid
fi

# 4. 포트가 완전히 해제될 때까지 대기 (최대 5초)
for i in {1..5}; do
    if ! fuser 5000/tcp >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

if [ -d "kooCAEWebServer_5000" ]; then
    cd kooCAEWebServer_5000
    mkdir -p logs

    # Python 캐시 삭제
    find . -type f -name "*.pyc" -delete 2>/dev/null || true
    find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true

    # 기존 로그 백업
    if [ -f "logs/gunicorn.log" ]; then
        mv logs/gunicorn.log logs/gunicorn_prev.log 2>/dev/null || true
    fi

    # Python import 테스트
    if [ -d "venv" ]; then
        echo "  → Python import 테스트 중..."
        if ! venv/bin/python -c "from app import create_app; print('OK')" 2>logs/import_error.log; then
            echo -e "${RED}   ❌ Python import 실패:${NC}"
            cat logs/import_error.log
        fi
    fi

    # CAE Backend 시작 (create_app() 팩토리 패턴)
    # venv/bin/gunicorn 직접 실행 (activate 불필요)
    if [ -d "venv" ]; then
        REDIS_PASSWORD="$REDIS_PASSWORD" nohup venv/bin/gunicorn -c gunicorn_config.py --pid logs/gunicorn.pid 'app:create_app()' > logs/gunicorn.log 2>&1 &
        sleep 1
        CAE_BACKEND_PID=$(pgrep -f "gunicorn.*kooCAEWebServer_5000" | head -1)
        chown "$RUN_USER:$RUN_GROUP" logs/*.log logs/*.pid 2>/dev/null || true
    else
        REDIS_PASSWORD="$REDIS_PASSWORD" nohup gunicorn -c gunicorn_config.py --pid logs/gunicorn.pid 'app:create_app()' > logs/gunicorn.log 2>&1 &
        sleep 1
        CAE_BACKEND_PID=$(pgrep -f "gunicorn.*kooCAEWebServer_5000" | head -1)
    fi
    cd "$SCRIPT_DIR"

    # 시작 확인
    sleep 3
    if pgrep -f "gunicorn.*kooCAEWebServer_5000" > /dev/null; then
        echo -e "${GREEN}✅ CAE Backend 시작됨 (Gunicorn, PID: $CAE_BACKEND_PID, Port: 5000)${NC}"
    else
        echo -e "${RED}❌ CAE Backend 시작 실패${NC}"
        echo -e "${RED}   로그 파일: $SCRIPT_DIR/kooCAEWebServer_5000/logs/gunicorn.log${NC}"
        if [ -f "$SCRIPT_DIR/kooCAEWebServer_5000/logs/gunicorn.log" ]; then
            echo -e "${YELLOW}   === 최근 로그 (마지막 15줄) ===${NC}"
            tail -15 "$SCRIPT_DIR/kooCAEWebServer_5000/logs/gunicorn.log" 2>/dev/null || echo "   (로그 읽기 실패)"
            echo -e "${YELLOW}   ================================${NC}"
        else
            echo -e "${YELLOW}   로그 파일이 없습니다. venv 또는 gunicorn 설치 확인 필요${NC}"
            if [ ! -d "$SCRIPT_DIR/kooCAEWebServer_5000/venv" ]; then
                echo -e "${RED}   ⚠ venv 디렉토리가 없습니다!${NC}"
            fi
        fi
    fi
fi

# ===== CAE Automation (5001) =====
echo -e "${YELLOW}  → 기존 CAE Automation 프로세스 정리 중...${NC}"

# 1. Gunicorn 프로세스 종료
pkill -9 -f "gunicorn.*kooCAEWebAutomationServer_5001" 2>/dev/null || true
sleep 1

# 2. 포트 5001 사용 중인 프로세스 강제 종료
fuser -k -9 5001/tcp 2>/dev/null || true
sleep 1

# 3. PID 파일 확인 및 정리
if [ -f "kooCAEWebAutomationServer_5001/logs/gunicorn.pid" ]; then
    OLD_PID=$(cat kooCAEWebAutomationServer_5001/logs/gunicorn.pid 2>/dev/null)
    if [ -n "$OLD_PID" ] && kill -0 $OLD_PID 2>/dev/null; then
        echo -e "${YELLOW}  → PID 파일의 프로세스($OLD_PID) 종료 중...${NC}"
        kill -9 $OLD_PID 2>/dev/null || true
        sleep 1
    fi
    # Stale PID 파일 삭제 (프로세스 유무와 관계없이)
    rm -f kooCAEWebAutomationServer_5001/logs/gunicorn.pid
fi

# 4. 포트가 완전히 해제될 때까지 대기 (최대 5초)
for i in {1..5}; do
    if ! fuser 5001/tcp >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

if [ -d "kooCAEWebAutomationServer_5001" ]; then
    cd kooCAEWebAutomationServer_5001
    mkdir -p logs

    # Python 캐시 삭제
    find . -type f -name "*.pyc" -delete 2>/dev/null || true
    find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true

    # 기존 로그 백업
    if [ -f "logs/gunicorn.log" ]; then
        mv logs/gunicorn.log logs/gunicorn_prev.log 2>/dev/null || true
    fi

    # Python import 테스트
    if [ -d "venv" ]; then
        echo "  → Python import 테스트 중..."
        if ! venv/bin/python -c "from app import app; print('OK')" 2>logs/import_error.log; then
            echo -e "${RED}   ❌ Python import 실패:${NC}"
            cat logs/import_error.log
        fi
    fi

    # CAE Automation 시작
    # venv/bin/gunicorn 직접 실행 (activate 불필요)
    if [ -d "venv" ]; then
        nohup venv/bin/gunicorn -c gunicorn_config.py --pid logs/gunicorn.pid app:app > logs/gunicorn.log 2>&1 &
        sleep 1
        CAE_AUTO_PID=$(pgrep -f "gunicorn.*kooCAEWebAutomationServer_5001" | head -1)
        chown "$RUN_USER:$RUN_GROUP" logs/*.log logs/*.pid 2>/dev/null || true
    else
        nohup gunicorn -c gunicorn_config.py --pid logs/gunicorn.pid app:app > logs/gunicorn.log 2>&1 &
        sleep 1
        CAE_AUTO_PID=$(pgrep -f "gunicorn.*kooCAEWebAutomationServer_5001" | head -1)
    fi
    cd "$SCRIPT_DIR"

    # 시작 확인
    sleep 3
    if pgrep -f "gunicorn.*kooCAEWebAutomationServer_5001" > /dev/null; then
        echo -e "${GREEN}✅ CAE Automation 시작됨 (Gunicorn, PID: $CAE_AUTO_PID, Port: 5001)${NC}"
    else
        echo -e "${RED}❌ CAE Automation 시작 실패${NC}"
        echo -e "${RED}   로그 파일: $SCRIPT_DIR/kooCAEWebAutomationServer_5001/logs/gunicorn.log${NC}"
        if [ -f "$SCRIPT_DIR/kooCAEWebAutomationServer_5001/logs/gunicorn.log" ]; then
            echo -e "${YELLOW}   === 최근 로그 (마지막 15줄) ===${NC}"
            tail -15 "$SCRIPT_DIR/kooCAEWebAutomationServer_5001/logs/gunicorn.log" 2>/dev/null || echo "   (로그 읽기 실패)"
            echo -e "${YELLOW}   ================================${NC}"
        else
            echo -e "${YELLOW}   로그 파일이 없습니다. venv 또는 gunicorn 설치 확인 필요${NC}"
            if [ ! -d "$SCRIPT_DIR/kooCAEWebAutomationServer_5001/venv" ]; then
                echo -e "${RED}   ⚠ venv 디렉토리가 없습니다!${NC}"
            fi
        fi
    fi
fi
echo ""

# ==================== 9. Nginx 재시작 ====================
echo -e "${BLUE}[10/10] Nginx 재시작 중...${NC}"
sudo nginx -t && sudo systemctl reload nginx
echo -e "${GREEN}✅ Nginx 재시작 완료${NC}"
echo ""

echo "=========================================="
echo -e "${GREEN}✅ Production 모드 시작 완료! (Gunicorn)${NC}"
echo "=========================================="
echo ""

# 외부 접속 주소를 YAML에서 동적으로 읽기
YAML_PATH="$SCRIPT_DIR/../my_multihead_cluster.yaml"
if [ -f "$YAML_PATH" ]; then
    # web.public_url 우선, 없으면 network.vip.address 사용
    PUBLIC_URL=$(python3 -c "
import yaml
with open('$YAML_PATH') as f:
    config = yaml.safe_load(f)
# 외부 접속 주소 (public_url) 우선
public_url = config.get('web', {}).get('public_url', '')
if public_url:
    print(public_url)
else:
    # 없으면 VIP 사용 (내부 접속용)
    print(config.get('network', {}).get('vip', {}).get('address', 'localhost'))
" 2>/dev/null)
    if [ -z "$PUBLIC_URL" ]; then
        PUBLIC_URL="localhost"
    fi
else
    # YAML이 없으면 현재 서버 IP 사용
    PUBLIC_URL=$(hostname -I | awk '{print $1}')
fi

echo "🔗 접속 정보 (Nginx Reverse Proxy):"
echo ""
echo "  ● 메인 포털:        http://$PUBLIC_URL/"
echo "  ● Dashboard:        http://$PUBLIC_URL/dashboard/"
echo "  ● VNC Service:      http://$PUBLIC_URL/vnc/"
echo "  ● CAE Frontend:     http://$PUBLIC_URL/cae/"
echo "  ● Moonlight:        http://$PUBLIC_URL/moonlight/"
echo ""
echo "📊 Backend Services (Gunicorn):"
echo "  ● Auth Backend:     http://localhost:4430 (Gunicorn)"
echo "  ● Dashboard API:    http://localhost:5010 (Gunicorn)"
echo "  ● WebSocket:        ws://localhost:5011/ws"
echo "  ● CAE Backend:      http://localhost:5000 (Gunicorn)"
echo "  ● CAE Automation:   http://localhost:5001 (Gunicorn)"
echo "  ● Moonlight API:    http://localhost:8004 (Gunicorn)"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
