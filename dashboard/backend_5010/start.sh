#!/bin/bash
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 포트 번호
PORT=5010

echo -e "${YELLOW}전 Step: 포트 ${PORT} 체크 및 정리...${NC}"

# 해당 포트를 사용 중인 프로세스 강제 종료
PID=$(lsof -ti:$PORT 2>/dev/null)
if [ ! -z "$PID" ]; then
    echo -e "${YELLOW}⚠️  포트 ${PORT}에서 실행 중인 프로세스 발견 (PID: $PID)${NC}"
    kill -9 $PID 2>/dev/null
    sleep 1
    echo -e "${GREEN}✅ 포트 ${PORT} 정리 완료${NC}"
fi

# PID 파일로 기록된 프로세스도 종료
[ -f ".backend.pid" ] && kill $(cat .backend.pid) 2>/dev/null && rm -f .backend.pid

[ ! -f "venv/bin/activate" ] && echo -e "${RED}❌ venv 없음. ./setup.sh 실행${NC}" && exit 1

source venv/bin/activate
export FLASK_APP=app.py FLASK_ENV=production

# 🔧 FIX: MOCK_MODE 환경변수 강제 설정
# 부모 스크립트(start_all_mock.sh)에서 export MOCK_MODE=true를 하더라도
# nohup으로 실행되면서 환경변수가 유실될 수 있음
# 따라서 여기서 명시적으로 다시 설정
if [ -z "$MOCK_MODE" ]; then
    # 환경변수가 없으면 기본값 사용 (false = Production)
    export MOCK_MODE=false
    echo -e "${YELLOW}⚠️  MOCK_MODE 환경변수 없음. 기본값(false) 사용${NC}"
else
    # 환경변수가 있으면 사용
    echo -e "${GREEN}✓ MOCK_MODE 환경변수 감지: ${MOCK_MODE}${NC}"
fi

# 🔧 FIX: Python 실행 시 환경변수 전달 보장
mkdir -p logs

# nohup 실행 시 env를 사용하여 환경변수 명시적 전달
nohup env MOCK_MODE=$MOCK_MODE python app.py > logs/backend.log 2>&1 &
echo $! > .backend.pid
sleep 2

# 시작 확인
if ps -p $(cat .backend.pid) > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Backend 시작 성공!${NC}"
    echo -e "   PID: $(cat .backend.pid)"
    echo -e "   URL: http://localhost:${PORT}"
    echo -e "   Mode: ${MOCK_MODE}"
    echo ""
    echo -e "${BLUE}📝 로그 확인:${NC}"
    echo -e "   tail -f logs/backend.log"
    echo ""
    # 시작 로그 출력
    sleep 1
    echo -e "${BLUE}=== Backend 시작 로그 ===${NC}"
    tail -20 logs/backend.log

    # 🆕 YAML 노드 그룹 초기화 (Production 모드에서만)
    if [ "$MOCK_MODE" != "true" ]; then
        echo ""
        echo -e "${YELLOW}🔄 YAML 기반 노드 그룹 초기화 중...${NC}"

        # 서버가 완전히 준비될 때까지 대기
        MAX_WAIT=30
        WAIT_COUNT=0
        while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
            HEALTH_CHECK=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:${PORT}/api/health 2>/dev/null)
            if [ "$HEALTH_CHECK" = "200" ]; then
                break
            fi
            sleep 1
            WAIT_COUNT=$((WAIT_COUNT + 1))
        done

        if [ "$HEALTH_CHECK" = "200" ]; then
            # YAML 노드 그룹 초기화 API 호출 (localhost 전용 엔드포인트)
            # 이 API는 DB 그룹 저장 + Slurm 파티션 동기화를 함께 수행
            INIT_RESULT=$(curl -s -X POST http://localhost:${PORT}/api/yaml/init-startup \
                -H "Content-Type: application/json" 2>/dev/null)

            if echo "$INIT_RESULT" | grep -q '"success": true\|"success":true'; then
                echo -e "${GREEN}✅ YAML 노드 그룹 초기화 완료${NC}"
                # 결과에서 그룹 수와 노드 수 추출
                GROUPS_COUNT=$(echo "$INIT_RESULT" | grep -o '"groups_count":[0-9]*' | grep -o '[0-9]*')
                COMPUTE_NODES=$(echo "$INIT_RESULT" | grep -o '"compute_nodes":[0-9]*' | grep -o '[0-9]*')
                VIZ_NODES=$(echo "$INIT_RESULT" | grep -o '"viz_nodes":[0-9]*' | grep -o '[0-9]*')
                echo -e "   📊 DB 그룹: ${GROUPS_COUNT:-0}개"
                echo -e "   💻 Compute 노드: ${COMPUTE_NODES:-0}개"
                echo -e "   🖥️  Viz 노드: ${VIZ_NODES:-0}개"

                # Slurm 파티션 동기화 결과 표시
                if echo "$INIT_RESULT" | grep -q '"slurm_available": true\|"slurm_available":true'; then
                    echo -e "${GREEN}   ✅ Slurm 파티션 동기화 완료${NC}"
                    # 파티션별 상태 표시
                    if echo "$INIT_RESULT" | grep -q '"compute"'; then
                        echo -e "      - compute 파티션: ${COMPUTE_NODES:-0} 노드"
                    fi
                    if echo "$INIT_RESULT" | grep -q '"viz"'; then
                        echo -e "      - viz 파티션: ${VIZ_NODES:-0} 노드"
                    fi
                else
                    echo -e "${YELLOW}   ⚠️  Slurm 미설치 - 파티션 동기화 건너뜀${NC}"
                fi
            else
                echo -e "${YELLOW}⚠️  YAML 노드 그룹 초기화 건너뜀${NC}"
                # 오류 메시지 출력
                ERROR_MSG=$(echo "$INIT_RESULT" | grep -o '"error"[^,}]*' | head -1)
                if [ ! -z "$ERROR_MSG" ]; then
                    echo -e "   ${ERROR_MSG}"
                fi
                echo -e "   힌트: my_multihead_cluster.yaml 파일이 있는지 확인하세요"
            fi
        else
            echo -e "${RED}⚠️  서버 준비 대기 시간 초과${NC}"
        fi
    else
        echo ""
        echo -e "${YELLOW}📝 Mock 모드 - YAML 노드 초기화 건너뜀${NC}"
    fi
else
    echo -e "${RED}❌ Backend 시작 실패${NC}"
    echo -e "${RED}=== 에러 로그 ===${NC}"
    tail -20 logs/backend.log
fi

deactivate
