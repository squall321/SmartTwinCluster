#!/bin/bash
# VNC Job 로그 파일 생성 안되는 문제 진단

echo "=========================================="
echo "VNC Job 로그 파일 미생성 문제 진단"
echo "=========================================="
echo ""

# Job ID 인자 받기
JOB_ID=${1:-"2"}

echo "진단 대상 Job ID: $JOB_ID"
echo ""

# 1. Job 상태 확인
echo "=== 1. Job $JOB_ID 상태 ==="
squeue -j "$JOB_ID" 2>/dev/null || sacct -j "$JOB_ID" --format=JobID,JobName,State,ExitCode,Start,End -P 2>/dev/null || echo "Job을 찾을 수 없습니다"
echo ""

# 2. Job 상세 정보
echo "=== 2. Job $JOB_ID 상세 정보 ==="
scontrol show job "$JOB_ID" 2>/dev/null || echo "Job이 큐에 없습니다 (완료/실패했을 수 있음)"
echo ""

# 3. 로그 디렉토리 확인
echo "=== 3. 로그 디렉토리 상태 ==="
echo "/mnt/gluster/logs:"
ls -la /mnt/gluster/logs 2>/dev/null || echo "  ✗ /mnt/gluster/logs 디렉토리가 없습니다!"
echo ""
echo "/shared/logs:"
ls -la /shared/logs 2>/dev/null || echo "  ✗ /shared/logs 디렉토리가 없습니다!"
echo ""

# 4. 심볼릭 링크 확인
echo "=== 4. /shared/logs 심볼릭 링크 확인 ==="
if [[ -L /shared/logs ]]; then
    echo "  ✓ /shared/logs는 심볼릭 링크입니다"
    echo "  Target: $(readlink -f /shared/logs)"
else
    echo "  ✗ /shared/logs는 심볼릭 링크가 아닙니다"
    if [[ -d /shared/logs ]]; then
        echo "  → 일반 디렉토리입니다"
    else
        echo "  → 존재하지 않습니다"
    fi
fi
echo ""

# 5. GlusterFS 마운트 확인
echo "=== 5. GlusterFS 마운트 확인 ==="
mount | grep gluster || echo "  ✗ GlusterFS가 마운트되지 않았습니다!"
echo ""

# 6. 디렉토리 권한 확인
echo "=== 6. 로그 디렉토리 권한 확인 ==="
for dir in "/mnt/gluster/logs" "/shared/logs"; do
    if [[ -e "$dir" ]]; then
        echo "$dir:"
        ls -ld "$dir"
        echo "  쓰기 가능 테스트:"
        touch "$dir/test_write_$$" 2>&1 && rm -f "$dir/test_write_$$" && echo "    ✓ 쓰기 가능" || echo "    ✗ 쓰기 불가"
    fi
done
echo ""

# 7. Job 스크립트 확인
echo "=== 7. Job 스크립트 확인 ==="
SCRIPT_FILE=$(find /tmp -name "vnc_job_*.sh" -o -name "slurm-${JOB_ID}.sh" 2>/dev/null | head -1)
if [[ -n "$SCRIPT_FILE" ]]; then
    echo "발견된 스크립트: $SCRIPT_FILE"
    echo "--- 스크립트 내용 (처음 50줄) ---"
    head -50 "$SCRIPT_FILE"
else
    echo "  Job 스크립트를 찾을 수 없습니다"
fi
echo ""

# 8. 실행 노드에서 로그 찾기
echo "=== 8. 다른 위치에서 로그 파일 찾기 ==="
echo "전체 시스템에서 job $JOB_ID 관련 로그 찾기..."
find /tmp /scratch /home -name "*${JOB_ID}*" -type f 2>/dev/null | grep -E "\\.out|\\.err|slurm" | head -10 || echo "  로그 파일을 찾을 수 없습니다"
echo ""

# 9. slurmd 로그 확인 (실행 노드)
echo "=== 9. slurmd 로그 (job 실행 관련 에러) ==="
if [[ -f /var/log/slurm/slurmd.log ]]; then
    echo "최근 에러 (최근 30줄에서):"
    tail -30 /var/log/slurm/slurmd.log | grep -i "job $JOB_ID\|error\|failed" | tail -10 || echo "  관련 에러 없음"
else
    echo "  /var/log/slurm/slurmd.log가 없습니다 (이 노드가 compute 노드가 아닐 수 있음)"
fi
echo ""

# 10. Job이 실행된 노드 확인
echo "=== 10. Job 실행 노드 확인 ==="
NODE_LIST=$(sacct -j "$JOB_ID" --format=NodeList -P -n 2>/dev/null | head -1)
if [[ -n "$NODE_LIST" && "$NODE_LIST" != "None assigned" ]]; then
    echo "실행 노드: $NODE_LIST"
    echo ""
    echo "실행 노드에서 로그 확인 필요:"
    echo "  ssh $NODE_LIST 'ls -la /mnt/gluster/logs/${JOB_ID}.*'"
    echo "  ssh $NODE_LIST 'cat /var/log/slurm/slurmd.log | grep \"job $JOB_ID\"'"
else
    echo "  Job이 아직 노드에 할당되지 않았거나 이미 완료되었습니다"
fi
echo ""

echo "=========================================="
echo "진단 완료"
echo "=========================================="
echo ""
echo "문제 해결 방법:"
echo ""
echo "1. /mnt/gluster/logs가 없으면:"
echo "   sudo mkdir -p /mnt/gluster/logs"
echo "   sudo chmod 1777 /mnt/gluster/logs"
echo ""
echo "2. /shared/logs 심볼릭 링크가 없으면:"
echo "   sudo ln -sf /mnt/gluster/logs /shared/logs"
echo ""
echo "3. GlusterFS가 마운트 안 되어 있으면:"
echo "   sudo mount -a"
echo "   # 또는"
echo "   sudo mount -t glusterfs head-node:/shared_data /mnt/gluster"
echo ""
echo "4. 쓰기 권한이 없으면:"
echo "   sudo chmod 1777 /mnt/gluster/logs"
echo "   sudo chmod 1777 /shared/logs"
echo ""
echo "5. Job이 PENDING 상태면:"
echo "   ./diagnose_vnc_pending.sh"
echo ""
echo "6. Job이 FAILED 상태면:"
echo "   ./diagnose_vnc_failed.sh $JOB_ID"
echo ""
