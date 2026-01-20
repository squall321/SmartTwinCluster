#!/bin/bash
# WTERMSIG 에러 진단 스크립트

echo "=========================================="
echo "Job WTERMSIG 에러 진단"
echo "=========================================="
echo ""

# Job ID 인자
JOB_ID=${1:-""}
if [[ -z "$JOB_ID" ]]; then
    echo "사용법: $0 <job_id>"
    echo ""
    echo "최근 실패한 Job 찾기..."
    FAILED_JOBS=$(sacct -S now-1day -n -o JobID,JobName,State,ExitCode -P 2>/dev/null | grep -E "FAILED|CANCELLED" | head -5 ||
                  /usr/local/slurm/bin/sacct -S now-1day -n -o JobID,JobName,State,ExitCode -P 2>/dev/null | grep -E "FAILED|CANCELLED" | head -5)

    if [[ -n "$FAILED_JOBS" ]]; then
        echo "=== 최근 실패한 Jobs ==="
        echo "Job ID | Job Name | State | ExitCode"
        echo "$FAILED_JOBS"
        echo ""

        JOB_ID=$(echo "$FAILED_JOBS" | head -1 | cut -d'|' -f1)
        echo "자동 선택: Job $JOB_ID"
        echo ""
    else
        echo "ERROR: 최근 실패한 job이 없습니다."
        exit 1
    fi
fi

# 1. Job 상세 정보
echo "=== 1. Job $JOB_ID 상세 정보 ==="
sacct -j "$JOB_ID" --format=JobID,JobName,State,ExitCode,DerivedExitCode -P 2>/dev/null ||
    /usr/local/slurm/bin/sacct -j "$JOB_ID" --format=JobID,JobName,State,ExitCode,DerivedExitCode -P 2>/dev/null
echo ""

# ExitCode 해석
echo "=== 2. ExitCode 해석 ==="
EXIT_INFO=$(sacct -j "$JOB_ID" --format=ExitCode -P -n 2>/dev/null | head -1 ||
            /usr/local/slurm/bin/sacct -j "$JOB_ID" --format=ExitCode -P -n 2>/dev/null | head -1)

if [[ "$EXIT_INFO" =~ ([0-9]+):([0-9]+) ]]; then
    EXIT_CODE="${BASH_REMATCH[1]}"
    SIGNAL="${BASH_REMATCH[2]}"

    echo "Exit Code: $EXIT_CODE:$SIGNAL"
    echo "  - Exit Status: $EXIT_CODE"
    echo "  - Signal: $SIGNAL"
    echo ""

    # Signal 해석
    case $SIGNAL in
        0) echo "  → 정상 종료" ;;
        1) echo "  → SIGHUP (Hangup)" ;;
        2) echo "  → SIGINT (Interrupt)" ;;
        9) echo "  → SIGKILL (강제 종료)" ;;
        15) echo "  → SIGTERM (정상 종료 요청)" ;;
        53) echo "  → Signal 53 (비정상 종료 - 스크립트 에러 가능성)" ;;
        *) echo "  → Signal $SIGNAL" ;;
    esac
else
    echo "Exit Code: $EXIT_INFO"
fi
echo ""

# 3. Job 실행 노드
echo "=== 3. Job 실행 노드 ==="
NODE_LIST=$(sacct -j "$JOB_ID" --format=NodeList -P -n 2>/dev/null | head -1 ||
            /usr/local/slurm/bin/sacct -j "$JOB_ID" --format=NodeList -P -n 2>/dev/null | head -1)
echo "실행 노드: $NODE_LIST"
echo ""

# 4. Job 스크립트 찾기
echo "=== 4. Job 스크립트 확인 ==="
SCRIPT_FILES=$(find /tmp -name "vnc_job_*.sh" -o -name "*${JOB_ID}*.sh" 2>/dev/null | head -5)

if [[ -n "$SCRIPT_FILES" ]]; then
    for script in $SCRIPT_FILES; do
        echo "발견: $script"
    done
    echo ""

    LATEST_SCRIPT=$(echo "$SCRIPT_FILES" | head -1)
    echo "최신 스크립트: $LATEST_SCRIPT"
    echo ""
    echo "--- 스크립트 처음 50줄 ---"
    head -50 "$LATEST_SCRIPT"
    echo ""

    # Bash 문법 체크
    echo "=== 5. Bash 문법 체크 ==="
    if bash -n "$LATEST_SCRIPT" 2>&1; then
        echo "  ✓ 문법 에러 없음"
    else
        echo "  ✗ 문법 에러 발견!"
    fi
else
    echo "  Job 스크립트를 찾을 수 없습니다"
fi
echo ""

# 6. Job 로그 파일 찾기
echo "=== 6. Job 로그 파일 ==="
LOG_PATHS=(
    "/mnt/gluster/logs/${JOB_ID}.out"
    "/mnt/gluster/logs/${JOB_ID}.err"
    "/mnt/gluster/logs/vnc-*-${JOB_ID}.out"
    "/mnt/gluster/logs/vnc-*-${JOB_ID}.err"
    "/shared/logs/${JOB_ID}.out"
    "/shared/logs/${JOB_ID}.err"
    "/shared/logs/vnc-*-${JOB_ID}.out"
    "/shared/logs/vnc-*-${JOB_ID}.err"
)

FOUND_LOGS=()
for path_pattern in "${LOG_PATHS[@]}"; do
    for file in $path_pattern 2>/dev/null; do
        if [[ -f "$file" ]]; then
            FOUND_LOGS+=("$file")
            echo "  ✓ 발견: $file"
        fi
    done
done
echo ""

if [[ ${#FOUND_LOGS[@]} -gt 0 ]]; then
    echo "=== 7. 로그 내용 (최근 100줄) ==="
    for log in "${FOUND_LOGS[@]}"; do
        echo "━━━ $log ━━━"
        tail -100 "$log"
        echo ""
    done
else
    echo "=== 7. 로그 파일 없음 ==="
    echo "  로그 파일을 찾을 수 없습니다"
    echo ""

    # 실행 노드에서 로그 확인 안내
    if [[ -n "$NODE_LIST" && "$NODE_LIST" != "None assigned" ]]; then
        echo "  실행 노드에서 로그 확인:"
        echo "    ssh $NODE_LIST 'ls -la /mnt/gluster/logs/${JOB_ID}*'"
        echo "    ssh $NODE_LIST 'cat /shared/logs/vnc-*-${JOB_ID}.out'"
    fi
fi
echo ""

# 8. slurmd 로그에서 Job 관련 에러
echo "=== 8. slurmd 로그 (Job $JOB_ID 관련) ==="
if [[ -n "$NODE_LIST" && "$NODE_LIST" != "None assigned" ]]; then
    echo "실행 노드 $NODE_LIST에서 확인:"
    echo "  ssh $NODE_LIST 'sudo tail -100 /var/log/slurm/slurmd.log | grep \"job $JOB_ID\"'"
    echo ""

    # 로컬에서도 확인 (헤드노드)
    if [[ -f /var/log/slurm/slurmd.log ]]; then
        echo "헤드노드 slurmd 로그:"
        sudo tail -100 /var/log/slurm/slurmd.log 2>/dev/null | grep -i "job $JOB_ID" | tail -10 || echo "  관련 로그 없음"
    fi
else
    echo "  실행 노드 정보가 없습니다"
fi
echo ""

# 9. 흔한 WTERMSIG 원인
echo "=========================================="
echo "WTERMSIG 53 흔한 원인"
echo "=========================================="
echo ""
echo "1. 스크립트 실행 중 에러 발생:"
echo "   - 명령어가 없음 (command not found)"
echo "   - 파일/디렉토리 접근 불가"
echo "   - 권한 부족"
echo ""
echo "2. 리소스 부족:"
echo "   - 메모리 부족 (OOM Killer)"
echo "   - 디스크 공간 부족"
echo ""
echo "3. Job 스크립트 문법 에러:"
echo "   - Bash 문법 오류"
echo "   - 변수 확장 에러"
echo ""
echo "4. 외부 프로그램 실패:"
echo "   - apptainer 실행 실패"
echo "   - vncserver 시작 실패"
echo ""
echo "해결 방법:"
echo "  1. 위의 로그 파일 확인"
echo "  2. 실행 노드에서 직접 스크립트 실행해보기:"
echo "     ssh $NODE_LIST 'bash $LATEST_SCRIPT'"
echo "  3. 리소스 확인:"
echo "     ssh $NODE_LIST 'free -h && df -h'"
echo ""
