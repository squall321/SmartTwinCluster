#!/bin/bash
# VNC Job 스크립트 및 로그 생성 확인

echo "=========================================="
echo "VNC Job 스크립트 및 로그 생성 확인"
echo "=========================================="
echo ""

# 1. 최근 생성된 VNC job 스크립트 찾기
echo "=== 1. 최근 VNC Job 스크립트 (최근 1시간) ==="
SCRIPTS=$(find /tmp -name "vnc_job_*.sh" -mmin -60 2>/dev/null | sort -r)
if [[ -n "$SCRIPTS" ]]; then
    for script in $SCRIPTS; do
        echo "발견: $script"
        echo "  생성 시간: $(stat -c '%y' "$script" 2>/dev/null || stat -f '%Sm' "$script")"
        echo ""
        echo "--- SBATCH 옵션 확인 ---"
        grep "^#SBATCH" "$script" | head -15
        echo ""
    done
else
    echo "  최근 1시간 내 VNC job 스크립트가 없습니다"
fi
echo ""

# 2. Job 로그 경로 확인
echo "=== 2. Job 스크립트에 설정된 로그 경로 ==="
if [[ -n "$SCRIPTS" ]]; then
    LATEST_SCRIPT=$(echo "$SCRIPTS" | head -1)
    echo "최신 스크립트: $LATEST_SCRIPT"
    echo ""
    grep "^#SBATCH.*output\|^#SBATCH.*error" "$LATEST_SCRIPT"
    echo ""

    # 로그 디렉토리 추출
    LOG_DIR=$(grep "^#SBATCH.*output" "$LATEST_SCRIPT" | sed 's/.*output=//;s/\/[^\/]*$//' | head -1)
    if [[ -n "$LOG_DIR" ]]; then
        echo "로그 디렉토리: $LOG_DIR"
        echo ""
        echo "디렉토리 상태:"
        ls -la "$LOG_DIR" 2>/dev/null || echo "  ✗ 디렉토리가 존재하지 않습니다!"
    fi
fi
echo ""

# 3. Slurm 설정에서 기본 로그 경로 확인
echo "=== 3. Slurm 기본 출력 경로 설정 ==="
echo "SlurmdLogFile:"
grep "^SlurmdLogFile" /etc/slurm/slurm.conf 2>/dev/null || echo "  설정 없음 (기본: /var/log/slurm/slurmd.log)"
echo ""
echo "SlurmctldLogFile:"
grep "^SlurmctldLogFile" /etc/slurm/slurm.conf 2>/dev/null || echo "  설정 없음 (기본: /var/log/slurm/slurmctld.log)"
echo ""

# 4. 최근 Job 목록 및 로그 파일 매칭
echo "=== 4. 최근 VNC Job 목록 (최근 24시간) ==="
RECENT_JOBS=$(sacct -S now-1day -n -o JobID,JobName,State,NodeList -P 2>/dev/null | grep "vnc-" ||
              /usr/local/slurm/bin/sacct -S now-1day -n -o JobID,JobName,State,NodeList -P 2>/dev/null | grep "vnc-")

if [[ -n "$RECENT_JOBS" ]]; then
    echo "Job ID | Job Name | State | NodeList"
    echo "$RECENT_JOBS"
    echo ""

    # 각 Job의 로그 파일 찾기
    while IFS='|' read -r job_id job_name state node_list; do
        [[ -z "$job_id" ]] && continue

        echo "--- Job $job_id ---"

        # 가능한 로그 경로들
        LOG_PATHS=(
            "/mnt/gluster/logs/${job_id}.out"
            "/mnt/gluster/logs/${job_name}-${job_id}.out"
            "/mnt/gluster/logs/vnc-*-${job_id}.out"
            "/shared/logs/${job_id}.out"
            "/shared/logs/${job_name}-${job_id}.out"
            "/shared/logs/vnc-*-${job_id}.out"
        )

        FOUND=0
        for path_pattern in "${LOG_PATHS[@]}"; do
            for file in $path_pattern 2>/dev/null; do
                if [[ -f "$file" ]]; then
                    echo "  ✓ 로그 파일 발견: $file"
                    echo "    크기: $(stat -c '%s bytes' "$file" 2>/dev/null || stat -f '%z bytes' "$file")"
                    FOUND=1
                fi
            done
        done

        if [[ $FOUND -eq 0 ]]; then
            echo "  ✗ 로그 파일을 찾을 수 없습니다"
        fi
        echo ""
    done <<< "$RECENT_JOBS"
else
    echo "  최근 24시간 내 VNC job이 없습니다"
fi
echo ""

# 5. slurmd 로그에서 로그 파일 생성 실패 에러 확인
echo "=== 5. slurmd 로그 - 로그 파일 생성 실패 에러 ==="
if [[ -f /var/log/slurm/slurmd.log ]]; then
    echo "최근 에러 (최근 50줄):"
    tail -50 /var/log/slurm/slurmd.log | grep -i "unable to open\|failed to open\|permission denied\|no such file" | tail -10 || echo "  관련 에러 없음"
else
    echo "  /var/log/slurm/slurmd.log 없음"
fi
echo ""

# 6. Job 스크립트의 mkdir 명령 확인
echo "=== 6. Job 스크립트의 로그 디렉토리 생성 명령 ==="
if [[ -n "$LATEST_SCRIPT" ]]; then
    grep -A2 "mkdir.*logs" "$LATEST_SCRIPT" || echo "  로그 디렉토리 생성 명령 없음"
fi
echo ""

# 7. 실행 노드에서 확인 필요 사항 안내
echo "=========================================="
echo "진단 완료"
echo "=========================================="
echo ""
echo "다음 단계:"
echo ""
echo "1. 로그 디렉토리가 없으면:"
echo "   sudo mkdir -p /mnt/gluster/logs"
echo "   sudo chmod 1777 /mnt/gluster/logs"
echo ""
echo "2. Job이 실행된 노드에서 로그 확인:"
if [[ -n "$RECENT_JOBS" ]]; then
    FIRST_NODE=$(echo "$RECENT_JOBS" | head -1 | cut -d'|' -f4)
    FIRST_JOB=$(echo "$RECENT_JOBS" | head -1 | cut -d'|' -f1)
    if [[ -n "$FIRST_NODE" && "$FIRST_NODE" != "None assigned" ]]; then
        echo "   ssh $FIRST_NODE 'ls -la /mnt/gluster/logs/${FIRST_JOB}*'"
        echo "   ssh $FIRST_NODE 'cat /var/log/slurm/slurmd.log | tail -50'"
    fi
fi
echo ""
echo "3. Job이 시작도 안 했으면:"
echo "   ./diagnose_vnc_pending.sh"
echo ""
echo "4. Job 스크립트에 문제가 있으면:"
echo "   cat $LATEST_SCRIPT"
echo ""
