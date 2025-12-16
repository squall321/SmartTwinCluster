#!/bin/bash
# ========================================================================
# 성능 최적화 자동 적용 스크립트
# ========================================================================
# 작성일: 2025-12-06
# 설명: Frontend, Backend, Nginx 성능 최적화를 자동으로 적용합니다.
# ========================================================================

set -e  # 에러 발생 시 즉시 중단

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/performance_optimization.log"

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 로깅 함수
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

log_section() {
    echo -e "\n${BLUE}========== $1 ==========${NC}\n" | tee -a "$LOG_FILE"
}

# 초기화
> "$LOG_FILE"
log_info "성능 최적화 적용 시작: $(date)"

# ========================================================================
# 1. 환경 확인
# ========================================================================
log_section "환경 확인"

# Node.js 확인
if command -v node &> /dev/null; then
    NODE_VERSION=$(node -v)
    log_info "Node.js: $NODE_VERSION"
else
    log_error "Node.js가 설치되지 않았습니다."
    exit 1
fi

# Python 확인
if command -v python3 &> /dev/null; then
    PYTHON_VERSION=$(python3 --version)
    log_info "Python: $PYTHON_VERSION"
else
    log_error "Python3가 설치되지 않았습니다."
    exit 1
fi

# Redis 확인
if command -v redis-cli &> /dev/null; then
    if redis-cli ping &> /dev/null; then
        log_info "Redis: Running"
    else
        log_warn "Redis가 실행 중이지 않습니다. 캐싱 기능이 비활성화됩니다."
    fi
else
    log_warn "Redis가 설치되지 않았습니다. 캐싱 기능이 비활성화됩니다."
fi

# ========================================================================
# 2. Backend 최적화 적용
# ========================================================================
log_section "Backend 최적화 적용"

cd "$SCRIPT_DIR"

# 2.1 Redis Python 패키지 설치
log_info "[2.1] Redis Python 패키지 설치 중..."

if [ -f "backend_5010/requirements.txt" ]; then
    # requirements.txt에 redis가 있는지 확인
    if grep -q "^redis" backend_5010/requirements.txt; then
        log_info "  ✅ requirements.txt에 redis가 이미 포함되어 있습니다."
    else
        log_error "  ❌ requirements.txt에 redis가 없습니다. 수동으로 추가하세요."
        exit 1
    fi

    # venv에 설치
    if [ -d "backend_5010/venv" ]; then
        log_info "  Installing redis in venv..."
        cd backend_5010
        source venv/bin/activate
        pip install -q redis 2>&1 | tee -a "$LOG_FILE"
        deactivate
        cd "$SCRIPT_DIR"
        log_info "  ✅ Redis 패키지 설치 완료"
    else
        log_warn "  venv를 찾을 수 없습니다. 전역으로 설치를 시도합니다."
        pip3 install -q redis 2>&1 | tee -a "$LOG_FILE"
    fi
else
    log_error "backend_5010/requirements.txt를 찾을 수 없습니다."
    exit 1
fi

# 2.2 Gunicorn 설정 최적화
log_info "[2.2] Gunicorn 설정 최적화 중..."

if [ -f "backend_5010/gunicorn_config.optimized.py" ]; then
    # 백업
    if [ -f "backend_5010/gunicorn_config.py" ]; then
        cp backend_5010/gunicorn_config.py backend_5010/gunicorn_config.py.backup
        log_info "  ✅ 기존 gunicorn_config.py 백업 완료"
    fi

    # 최적화 버전 적용
    cp backend_5010/gunicorn_config.optimized.py backend_5010/gunicorn_config.py
    log_info "  ✅ 최적화된 Gunicorn 설정 적용 완료"
    log_info "     - Worker 자동 스케일링: (CPU * 2) + 1"
    log_info "     - Threads: 2 → 4"
    log_info "     - Max requests: 1000 → 2000"
else
    log_warn "  gunicorn_config.optimized.py를 찾을 수 없습니다. 건너뜁니다."
fi

# 2.3 Cache Decorator 확인
log_info "[2.3] Cache Decorator 확인 중..."

if [ -f "backend_5010/utils/cache_decorator_v2.py" ]; then
    log_info "  ✅ cache_decorator_v2.py 발견"
    log_info "     사용법: from utils.cache_decorator_v2 import cache, cache_invalidate"
else
    log_warn "  cache_decorator_v2.py를 찾을 수 없습니다."
fi

# ========================================================================
# 3. Frontend 빌드 최적화 확인
# ========================================================================
log_section "Frontend 빌드 최적화 확인"

# 3.1 Dashboard Frontend (3010)
log_info "[3.1] Dashboard Frontend (3010) 확인 중..."

if [ -f "frontend_3010/vite.config.ts" ]; then
    if grep -q "manualChunks" frontend_3010/vite.config.ts; then
        log_info "  ✅ vite.config.ts에 manualChunks 설정 적용됨"
    else
        log_warn "  ⚠️  vite.config.ts에 manualChunks 설정이 없습니다."
    fi

    if grep -q "terserOptions" frontend_3010/vite.config.ts; then
        log_info "  ✅ terserOptions 설정 적용됨 (console.log 제거)"
    else
        log_warn "  ⚠️  terserOptions 설정이 없습니다."
    fi
else
    log_warn "  frontend_3010/vite.config.ts를 찾을 수 없습니다."
fi

# 3.2 CAE Frontend (5173)
log_info "[3.2] CAE Frontend (5173) 확인 중..."

if [ -f "kooCAEWeb_5173/vite.config.ts" ]; then
    if grep -q "manualChunks" kooCAEWeb_5173/vite.config.ts; then
        log_info "  ✅ vite.config.ts에 manualChunks 설정 적용됨"
    else
        log_warn "  ⚠️  vite.config.ts에 manualChunks 설정이 없습니다."
    fi
else
    log_warn "  kooCAEWeb_5173/vite.config.ts를 찾을 수 없습니다."
fi

# 3.3 Moonlight Frontend (8003)
log_info "[3.3] Moonlight Frontend (8003) 확인 중..."

if [ -f "moonlight_frontend_8003/vite.config.ts" ]; then
    if grep -q "manualChunks" moonlight_frontend_8003/vite.config.ts; then
        log_info "  ✅ vite.config.ts에 manualChunks 설정 적용됨"
    else
        log_warn "  ⚠️  vite.config.ts에 manualChunks 설정이 없습니다."
    fi
else
    log_warn "  moonlight_frontend_8003/vite.config.ts를 찾을 수 없습니다."
fi

# ========================================================================
# 4. Frontend 재빌드 (선택사항)
# ========================================================================
log_section "Frontend 재빌드"

read -p "Frontend를 지금 재빌드하시겠습니까? (y/n): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    log_info "Frontend 재빌드 시작..."

    if [ -f "build_all_frontends.sh" ]; then
        bash build_all_frontends.sh 2>&1 | tee -a "$LOG_FILE"
        log_info "  ✅ Frontend 재빌드 완료"
    else
        log_error "build_all_frontends.sh를 찾을 수 없습니다."
    fi
else
    log_info "Frontend 재빌드를 건너뜁니다."
    log_info "나중에 수동으로 실행하세요: ./build_all_frontends.sh"
fi

# ========================================================================
# 5. Nginx 설정 확인
# ========================================================================
log_section "Nginx 설정 확인"

if [ -f "nginx_performance_optimization.conf" ]; then
    log_info "nginx_performance_optimization.conf 발견"
    log_warn "이 파일은 참고용입니다. 실제 적용은 아래 단계를 따르세요:"
    log_warn "  1. sudo cp nginx_performance_optimization.conf /etc/nginx/conf.d/performance.conf"
    log_warn "  2. sudo nginx -t  # 문법 검사"
    log_warn "  3. sudo systemctl reload nginx"
else
    log_warn "nginx_performance_optimization.conf를 찾을 수 없습니다."
fi

# ========================================================================
# 6. 환경 변수 설정 안내
# ========================================================================
log_section "환경 변수 설정"

log_info "Cache Decorator를 사용하려면 다음 환경 변수를 설정하세요:"
echo ""
echo "  export REDIS_HOST=localhost"
echo "  export REDIS_PORT=6379"
echo "  export REDIS_DB=0"
echo "  export CACHE_ENABLED=true"
echo ""
log_info "또는 backend_5010/.env 파일에 추가:"
echo ""
echo "  REDIS_HOST=localhost"
echo "  REDIS_PORT=6379"
echo "  REDIS_DB=0"
echo "  CACHE_ENABLED=true"
echo ""

# ========================================================================
# 7. Backend 재시작 안내
# ========================================================================
log_section "Backend 재시작"

log_info "Gunicorn 설정을 적용하려면 Backend를 재시작하세요:"
echo ""
echo "  cd backend_5010"
echo "  pkill -f 'gunicorn.*dashboard_backend_5010'"
echo "  nohup venv/bin/gunicorn -c gunicorn_config.py app:app > logs/gunicorn.log 2>&1 &"
echo ""
log_info "또는 전체 시스템 재시작:"
echo ""
echo "  cd $SCRIPT_DIR"
echo "  ./start_production.sh"
echo ""

# ========================================================================
# 완료
# ========================================================================
log_section "완료"

log_info "성능 최적화 적용 완료!"
log_info "로그 파일: $LOG_FILE"
log_info ""
log_info "다음 단계:"
log_info "  1. Frontend 재빌드 (선택 안 했다면): ./build_all_frontends.sh"
log_info "  2. Backend 재시작: ./start_production.sh"
log_info "  3. Nginx 설정 적용 (수동): sudo cp nginx_performance_optimization.conf /etc/nginx/conf.d/"
log_info "  4. 캐시 통계 확인: curl http://localhost:5010/api/cache/stats"
log_info ""
log_info "자세한 내용: PERFORMANCE_OPTIMIZATION_SUMMARY.md"
