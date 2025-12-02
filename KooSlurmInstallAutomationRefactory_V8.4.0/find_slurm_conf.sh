#!/bin/bash

echo "========================================"
echo "🔍 Slurm 설정 파일 위치 찾기"
echo "========================================"
echo ""

# 1. scontrol로 설정 파일 위치 확인
echo "1️⃣ scontrol로 설정 파일 위치 확인:"
scontrol show config | grep SLURM_CONF 2>/dev/null || echo "   ⚠️ scontrol 명령어 실패"
echo ""

# 2. 시스템에서 slurm.conf 파일 검색
echo "2️⃣ 시스템에서 slurm.conf 파일 검색:"
echo "   /etc 디렉토리:"
find /etc -name "slurm.conf" 2>/dev/null | while read file; do
    echo "   ✅ $file"
    ls -lh "$file"
done

echo ""
echo "   /usr/local 디렉토리:"
find /usr/local -name "slurm.conf" 2>/dev/null | while read file; do
    echo "   ✅ $file"
    ls -lh "$file"
done

echo ""
echo "   /opt 디렉토리:"
find /opt -name "slurm.conf" 2>/dev/null | while read file; do
    echo "   ✅ $file"
    ls -lh "$file"
done

echo ""

# 3. Slurm 프로세스가 사용 중인 파일 확인
echo "3️⃣ Slurm 프로세스가 사용 중인 파일 확인:"
if command -v lsof &> /dev/null; then
    sudo lsof -c slurmctld 2>/dev/null | grep -i conf || echo "   ⚠️ slurmctld 프로세스 없음"
else
    echo "   ⚠️ lsof 명령어 없음"
fi
echo ""

# 4. 환경변수 확인
echo "4️⃣ 환경변수 확인:"
if [ -n "$SLURM_CONF" ]; then
    echo "   SLURM_CONF=$SLURM_CONF"
else
    echo "   ⚠️ SLURM_CONF 환경변수 설정 안 됨"
fi
echo ""

# 5. 일반적인 위치 확인
echo "5️⃣ 일반적인 위치 확인:"
COMMON_PATHS=(
    "/etc/slurm/slurm.conf"
    "/etc/slurm-llnl/slurm.conf"
    "/usr/local/etc/slurm.conf"
    "/usr/local/slurm/etc/slurm.conf"
    "/opt/slurm/etc/slurm.conf"
)

for path in "${COMMON_PATHS[@]}"; do
    if [ -f "$path" ]; then
        echo "   ✅ $path"
        ls -lh "$path"
        echo "      첫 10줄:"
        head -10 "$path" | sed 's/^/         /'
    else
        echo "   ❌ $path (없음)"
    fi
done
echo ""

# 6. Slurm 설치 위치 확인
echo "6️⃣ Slurm 명령어 위치:"
which sinfo 2>/dev/null && echo "   sinfo: $(which sinfo)" || echo "   ⚠️ sinfo 없음"
which scontrol 2>/dev/null && echo "   scontrol: $(which scontrol)" || echo "   ⚠️ scontrol 없음"
which slurmctld 2>/dev/null && echo "   slurmctld: $(which slurmctld)" || echo "   ⚠️ slurmctld 없음"
echo ""

# 7. Slurm 서비스 파일 확인
echo "7️⃣ Slurm 서비스 파일 확인:"
if [ -f "/etc/systemd/system/slurmctld.service" ]; then
    echo "   ✅ /etc/systemd/system/slurmctld.service"
    grep -i "ExecStart" /etc/systemd/system/slurmctld.service | sed 's/^/      /'
elif [ -f "/usr/lib/systemd/system/slurmctld.service" ]; then
    echo "   ✅ /usr/lib/systemd/system/slurmctld.service"
    grep -i "ExecStart" /usr/lib/systemd/system/slurmctld.service | sed 's/^/      /'
else
    echo "   ⚠️ systemd service 파일 없음"
fi
echo ""

# 8. 현재 사용 중인 설정 확인
echo "8️⃣ 현재 Slurm 설정에서 RebootProgram 확인:"
if command -v scontrol &> /dev/null; then
    REBOOT_PROG=$(scontrol show config 2>/dev/null | grep -i "RebootProgram")
    if [ -n "$REBOOT_PROG" ]; then
        echo "   $REBOOT_PROG"
    else
        echo "   ❌ RebootProgram 설정 없음"
    fi
else
    echo "   ⚠️ scontrol 명령어 없음"
fi
echo ""

echo "========================================"
echo "✅ 확인 완료!"
echo "========================================"
