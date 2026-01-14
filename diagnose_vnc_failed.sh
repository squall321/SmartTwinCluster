#!/bin/bash
# VNC Job Failed 원인 진단 스크립트

echo "=========================================="
echo "VNC Job Failed 원인 진단"
echo "=========================================="
echo ""

# Job ID 인자 받기
JOB_ID=${1:-""}
if [[ -z "$JOB_ID" ]]; then
    echo "사용법: $0 <job_id>"
    echo ""
    echo "최근 실패한 VNC job 찾기..."
    FAILED_JOBS=$(sacct -S now-1day -n -o JobID,JobName,State -P 2>/dev/null | grep "vnc-" | grep "FAILED" | head -5 || \
                  /usr/local/slurm/bin/sacct -S now-1day -n -o JobID,JobName,State -P 2>/dev/null | grep "vnc-" | grep "FAILED" | head -5)

    if [[ -n "$FAILED_JOBS" ]]; then
        echo "=== 최근 실패한 VNC Jobs ==="
        echo "Job ID | Job Name | State"
        echo "$FAILED_JOBS"
        echo ""

        # 첫 번째 실패 job 자동 선택
        JOB_ID=$(echo "$FAILED_JOBS" | head -1 | cut -d'|' -f1)
        echo "자동 선택: Job $JOB_ID"
        echo ""
    else
        echo "ERROR: 최근 24시간 내 실패한 VNC job이 없습니다."
        exit 1
    fi
fi

# 1. Job 기본 정보
echo "=== 1. Job $JOB_ID 기본 정보 ==="
sacct -j "$JOB_ID" --format=JobID,JobName,State,ExitCode,Start,End,Elapsed -P 2>/dev/null || \
    /usr/local/slurm/bin/sacct -j "$JOB_ID" --format=JobID,JobName,State,ExitCode,Start,End,Elapsed -P 2>/dev/null
echo ""

# 2. Job 상세 정보 (TRES, 메모리, CPU)
echo "=== 2. Job $JOB_ID 리소스 요청 ==="
sacct -j "$JOB_ID" --format=JobID,ReqMem,ReqCPUS,ReqTRES,AllocTRES -P 2>/dev/null || \
    /usr/local/slurm/bin/sacct -j "$JOB_ID" --format=JobID,ReqMem,ReqCPUS,ReqTRES,AllocTRES -P 2>/dev/null
echo ""

# 3. 실행 노드 및 작업 디렉토리
echo "=== 3. Job $JOB_ID 실행 위치 ==="
sacct -j "$JOB_ID" --format=JobID,NodeList,WorkDir -P 2>/dev/null || \
    /usr/local/slurm/bin/sacct -j "$JOB_ID" --format=JobID,NodeList,WorkDir -P 2>/dev/null
echo ""

# 4. 로그 파일 위치 확인
echo "=== 4. 로그 파일 확인 ==="

# 가능한 로그 경로들
LOG_PATHS=(
    "/mnt/gluster/logs/$JOB_ID.out"
    "/mnt/gluster/logs/$JOB_ID.err"
    "/mnt/gluster/logs/vnc-*-$JOB_ID.out"
    "/mnt/gluster/logs/vnc-*-$JOB_ID.err"
    "/scratch/vnc_logs/vnc-*-$JOB_ID.out"
    "/scratch/vnc_logs/vnc-*-$JOB_ID.err"
    "/shared/logs/$JOB_ID.out"
    "/shared/logs/$JOB_ID.err"
    "/tmp/slurm-$JOB_ID.out"
)

FOUND_LOGS=()
for path in "${LOG_PATHS[@]}"; do
    # 와일드카드 확장
    for file in $path; do
        if [[ -f "$file" ]]; then
            FOUND_LOGS+=("$file")
            echo "  ✓ 발견: $file"
        fi
    done
done

if [[ ${#FOUND_LOGS[@]} -eq 0 ]]; then
    echo "  ✗ 로그 파일을 찾을 수 없습니다!"
    echo ""
    echo "  가능한 원인:"
    echo "  - 로그 디렉토리(/mnt/gluster/logs)가 존재하지 않음"
    echo "  - 로그 디렉토리 쓰기 권한 없음"
    echo "  - Job이 시작되기 전에 실패함"
fi
echo ""

# 5. 로그 디렉토리 상태 확인
echo "=== 5. 로그 디렉토리 상태 ==="
for dir in "/mnt/gluster/logs" "/scratch/vnc_logs" "/shared/logs"; do
    if [[ -d "$dir" ]]; then
        echo "  ✓ $dir (존재)"
        ls -ld "$dir"
    else
        echo "  ✗ $dir (없음)"
    fi
done
echo ""

# 6. GlusterFS 마운트 확인
echo "=== 6. GlusterFS 마운트 확인 ==="
mount | grep gluster || echo "  ✗ GlusterFS 마운트 없음"
echo ""

# 7. Job 스크립트 확인
echo "=== 7. Job 스크립트 확인 (최근 1시간) ==="
SCRIPT_FILES=$(find /tmp -name "vnc_job_*.sh" -mmin -60 2>/dev/null)
if [[ -n "$SCRIPT_FILES" ]]; then
    for script in $SCRIPT_FILES; do
        echo "File: $script"
        echo "--- 첫 30줄 ---"
        head -30 "$script"
        echo ""
    done
else
    echo "  최근 VNC job 스크립트를 찾을 수 없습니다."
fi
echo ""

# 8. 로그 파일 내용 (에러)
if [[ ${#FOUND_LOGS[@]} -gt 0 ]]; then
    echo "=== 8. 로그 파일 내용 (마지막 50줄) ==="
    for log in "${FOUND_LOGS[@]}"; do
        if [[ "$log" == *.err ]]; then
            echo "--- $log ---"
            tail -50 "$log"
            echo ""
        fi
    done

    echo "=== 9. 로그 파일 내용 (표준 출력, 마지막 50줄) ==="
    for log in "${FOUND_LOGS[@]}"; do
        if [[ "$log" == *.out ]]; then
            echo "--- $log ---"
            tail -50 "$log"
            echo ""
        fi
    done
fi

echo "=========================================="
echo "진단 완료"
echo "=========================================="
echo ""
echo "주요 확인 사항:"
echo ""
echo "1. 로그 디렉토리가 없으면:"
echo "   → sudo mkdir -p /mnt/gluster/logs"
echo "   → sudo chmod 777 /mnt/gluster/logs (또는 slurm:slurm 소유권)"
echo ""
echo "2. GlusterFS 마운트 안 되어 있으면:"
echo "   → 로그 경로를 /shared/logs로 변경 고려"
echo "   → 또는 GlusterFS 마운트 설정 필요"
echo ""
echo "3. 메모리 부족이면 (이미 128G로 수정됨):"
echo "   → 백엔드 재시작 필요: sudo systemctl restart dashboard_backend"
echo ""
echo "4. gres.conf 없으면:"
echo "   → ./generate_gres_conf.sh 실행"
echo "   → viz 노드에 배포 필요"
echo ""
