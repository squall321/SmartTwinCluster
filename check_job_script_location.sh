#!/bin/bash
# Job 스크립트 위치 확인

echo "=========================================="
echo "Job 스크립트 위치 확인"
echo "=========================================="
echo ""

JOB_ID=${1:-""}

# 1. 헤드노드 /tmp에서 VNC job 스크립트 찾기
echo "=== 1. 헤드노드 /tmp에서 VNC job 스크립트 ==="
HEAD_SCRIPTS=$(find /tmp -name "vnc_job_*.sh" -mmin -120 2>/dev/null)

if [[ -n "$HEAD_SCRIPTS" ]]; then
    echo "발견된 스크립트:"
    ls -lh $HEAD_SCRIPTS
    echo ""

    LATEST=$(ls -t $HEAD_SCRIPTS | head -1)
    echo "최신 스크립트: $LATEST"
    echo ""
    echo "--- SBATCH 옵션 ---"
    grep "^#SBATCH" "$LATEST" | head -20
else
    echo "  최근 2시간 내 VNC job 스크립트 없음"
fi
echo ""

# 2. Job이 실행된 노드 확인
if [[ -n "$JOB_ID" ]]; then
    echo "=== 2. Job $JOB_ID 실행 노드 ==="
    NODE=$(sacct -j "$JOB_ID" -n -o NodeList -P 2>/dev/null | head -1 ||
           /usr/local/slurm/bin/sacct -j "$JOB_ID" -n -o NodeList -P 2>/dev/null | head -1)

    if [[ -n "$NODE" && "$NODE" != "None assigned" ]]; then
        echo "실행 노드: $NODE"
        echo ""

        echo "=== 3. $NODE 노드의 /tmp에서 스크립트 찾기 ==="
        ssh -o ConnectTimeout=5 "$NODE" "find /tmp -name 'vnc_job_*.sh' -o -name 'slurm-*.sh' -o -name '*${JOB_ID}*.sh' 2>/dev/null" 2>/dev/null || echo "  SSH 접속 실패 또는 스크립트 없음"
        echo ""

        echo "=== 4. $NODE 노드의 slurmd spool 디렉토리 ==="
        echo "Slurm은 job 스크립트를 spool 디렉토리에 저장합니다:"
        ssh -o ConnectTimeout=5 "$NODE" "ls -lh /var/spool/slurm/job${JOB_ID}/ 2>/dev/null || ls -lh /var/spool/slurmd/job${JOB_ID}/ 2>/dev/null || echo '  spool 디렉토리 없음'" 2>/dev/null
        echo ""

        echo "=== 5. $NODE 노드의 최근 실행 프로세스 ==="
        ssh -o ConnectTimeout=5 "$NODE" "ps aux | grep -E 'apptainer|vnc|slurm' | grep -v grep" 2>/dev/null || echo "  관련 프로세스 없음"
    else
        echo "  Job이 노드에 할당되지 않았습니다"
    fi
else
    echo "=== 2. 최근 Job 확인 ==="
    echo "최근 VNC Job (최근 1일):"
    sacct -S now-1day -n -o JobID,JobName,State,NodeList -P 2>/dev/null | grep "vnc-" | head -5 ||
        /usr/local/slurm/bin/sacct -S now-1day -n -o JobID,JobName,State,NodeList -P 2>/dev/null | grep "vnc-" | head -5
    echo ""
    echo "Job ID를 지정하여 다시 실행:"
    echo "  $0 <job_id>"
fi
echo ""

# 3. Slurm 설정에서 spool 디렉토리 확인
echo "=== 6. Slurm spool 디렉토리 설정 ==="
echo "SlurmdSpoolDir:"
grep "^SlurmdSpoolDir" /etc/slurm/slurm.conf 2>/dev/null || echo "  설정 없음 (기본: /var/spool/slurmd)"
echo ""

# 4. VNC API에서 스크립트 생성 경로 확인
echo "=== 7. VNC API 스크립트 생성 경로 ==="
if [[ -f dashboard/backend_5010/vnc_api.py ]]; then
    echo "vnc_api.py에서 스크립트 저장 경로:"
    grep "script_path = " dashboard/backend_5010/vnc_api.py | head -3 || echo "  못 찾음"
else
    echo "  vnc_api.py 파일 없음"
fi
echo ""

echo "=========================================="
echo "Job 스크립트 처리 과정"
echo "=========================================="
echo ""
echo "1. VNC API가 /tmp/vnc_job_<session_id>.sh 생성 (헤드노드)"
echo "2. sbatch /tmp/vnc_job_<session_id>.sh 실행"
echo "3. slurmctld가 스크립트를 viz 노드로 전송"
echo "4. viz 노드의 slurmd가 스크립트를 실행"
echo "   → 실행 위치: /var/spool/slurmd/job<job_id>/"
echo "5. 스크립트가 apptainer를 실행하여 VNC 시작"
echo ""
echo "Job이 빠르게 실패한 경우:"
echo "  - 스크립트가 viz 노드로 전송되지 못함"
echo "  - 또는 스크립트 실행 중 즉시 에러 발생"
echo ""
echo "확인 방법:"
echo "  1. viz 노드 slurmd 로그:"
echo "     ssh <viz-node> 'sudo tail -50 /var/log/slurm/slurmd.log'"
echo ""
echo "  2. viz 노드에서 직접 스크립트 실행:"
echo "     ssh <viz-node> 'bash /tmp/vnc_job_*.sh'"
echo ""
