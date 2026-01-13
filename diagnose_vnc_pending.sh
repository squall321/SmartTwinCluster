#!/bin/bash
# VNC Job Pending 원인 진단 스크립트

echo "=========================================="
echo "VNC Job Pending 원인 진단"
echo "=========================================="
echo ""

# 1. viz 파티션 확인
echo "=== 1. viz 파티션 상태 ==="
sinfo -p viz -o "%P|%a|%l|%D|%T|%N" 2>/dev/null || /usr/local/slurm/bin/sinfo -p viz -o "%P|%a|%l|%D|%T|%N" 2>/dev/null || echo "ERROR: viz 파티션이 없습니다!"
echo ""

# 2. viz 노드 상세 정보
echo "=== 2. viz 노드 상세 정보 ==="
sinfo -N -p viz -o "%N|%T|%C|%G" 2>/dev/null || /usr/local/slurm/bin/sinfo -N -p viz -o "%N|%T|%C|%G" 2>/dev/null
echo ""

# 3. GPU 리소스 확인
echo "=== 3. GPU (GRES) 설정 확인 ==="
sinfo -N -p viz -o "%N|%G" 2>/dev/null || /usr/local/slurm/bin/sinfo -N -p viz -o "%N|%G" 2>/dev/null
echo ""

# 4. Pending 중인 VNC job 확인
echo "=== 4. Pending 중인 VNC Job 확인 ==="
PENDING_JOBS=$(squeue -t PENDING -o "%i|%u|%P|%j|%r" 2>/dev/null | grep "vnc-" || true)
if [[ -z "$PENDING_JOBS" ]]; then
    echo "현재 pending 중인 VNC job이 없습니다."
else
    echo "Job ID | User | Partition | Job Name | Reason"
    echo "$PENDING_JOBS"

    # 첫 번째 pending job의 상세 이유 확인
    FIRST_JOB=$(echo "$PENDING_JOBS" | head -1 | cut -d'|' -f1)
    if [[ -n "$FIRST_JOB" ]]; then
        echo ""
        echo "=== Job $FIRST_JOB 상세 정보 ==="
        scontrol show job "$FIRST_JOB" 2>/dev/null | grep -E "JobId|Reason|Partition|TRES" || true
    fi
fi
echo ""

# 5. slurm.conf에서 viz 파티션 설정 확인
echo "=== 5. slurm.conf - viz 파티션 설정 ==="
grep -A2 "^PartitionName=viz" /etc/slurm/slurm.conf 2>/dev/null || echo "ERROR: viz 파티션 설정이 없습니다!"
echo ""

# 6. slurm.conf에서 viz 노드 GRES 설정 확인
echo "=== 6. slurm.conf - viz 노드 GRES 설정 ==="
grep "^NodeName=viz" /etc/slurm/slurm.conf | head -5 2>/dev/null || echo "ERROR: viz 노드 설정이 없습니다!"
echo ""

# 7. gres.conf 확인
echo "=== 7. gres.conf 설정 확인 ==="
if [[ -f /etc/slurm/gres.conf ]]; then
    cat /etc/slurm/gres.conf
else
    echo "WARNING: /etc/slurm/gres.conf 파일이 없습니다!"
fi
echo ""

# 8. 최근 VNC job 로그 확인
echo "=== 8. 최근 VNC Job 로그 (최근 1시간) ==="
find /tmp -name "vnc_job_*.sh" -mmin -60 -exec echo "File: {}" \; -exec head -20 {} \; 2>/dev/null || echo "VNC job 스크립트를 찾을 수 없습니다."
echo ""

echo "=========================================="
echo "진단 완료"
echo "=========================================="
echo ""
echo "문제 해결 가이드:"
echo ""
echo "1. viz 파티션이 없으면:"
echo "   → slurm.conf에 viz 파티션 추가 필요"
echo ""
echo "2. viz 노드가 idle* 또는 down 상태면:"
echo "   → 노드 상태 복구 필요 (scontrol update nodename=... state=resume)"
echo ""
echo "3. GRES가 (null) 또는 없으면:"
echo "   → slurm.conf에 Gres=gpu:X 설정 필요"
echo "   → gres.conf 설정 필요"
echo ""
echo "4. Reason이 'Resources' 또는 'PartitionConfig'면:"
echo "   → GPU 요청 개수가 노드의 GPU 개수보다 많음"
echo "   → 또는 파티션 설정 오류"
echo ""
