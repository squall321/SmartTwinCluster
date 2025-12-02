#!/bin/bash
# Phase 0: Apptainer Sandbox 디렉토리 설정 스크립트

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=== Phase 0: Apptainer Sandbox 디렉토리 설정 ==="
echo

# Apptainer 설치 확인
echo "Apptainer 설치 확인 중..."
if ! command -v apptainer &> /dev/null; then
    echo -e "${RED}✗${NC} Apptainer가 설치되어 있지 않습니다."
    echo "Apptainer 1.2.5+ 버전을 먼저 설치해주세요."
    echo "설치 가이드: https://apptainer.org/docs/admin/main/installation.html"
    exit 1
fi

APPTAINER_VERSION=$(apptainer --version | awk '{print $3}')
echo -e "${GREEN}✓${NC} Apptainer 설치됨: $APPTAINER_VERSION"

# Apptainer 버전 확인 (1.2.5 이상)
REQUIRED_VERSION="1.2.5"
if [ "$(printf '%s\n' "$REQUIRED_VERSION" "$APPTAINER_VERSION" | sort -V | head -n1)" != "$REQUIRED_VERSION" ]; then
    echo -e "${YELLOW}⚠${NC} Apptainer 버전이 $REQUIRED_VERSION 미만입니다. ($APPTAINER_VERSION)"
    echo "최신 버전 설치를 권장합니다."
fi

# Slurm 사용자 존재 확인
echo
echo "Slurm 사용자 확인 중..."
if ! id -u slurm &>/dev/null; then
    echo -e "${RED}✗${NC} slurm 사용자가 존재하지 않습니다."
    echo "Slurm이 설치되어 있는지 확인해주세요."
    exit 1
fi
echo -e "${GREEN}✓${NC} slurm 사용자 존재 확인"

# Sandbox 디렉토리 생성
SANDBOX_DIR="/scratch/apptainer_sandboxes"
echo
echo "Sandbox 디렉토리 생성 중: $SANDBOX_DIR"

if [ -d "$SANDBOX_DIR" ]; then
    echo -e "${YELLOW}⚠${NC} 디렉토리가 이미 존재합니다: $SANDBOX_DIR"
    echo "기존 디렉토리를 사용합니다."
else
    sudo mkdir -p "$SANDBOX_DIR"
    echo -e "${GREEN}✓${NC} 디렉토리 생성 완료"
fi

# 권한 설정
echo
echo "권한 설정 중..."
sudo chown slurm:slurm "$SANDBOX_DIR"
sudo chmod 755 "$SANDBOX_DIR"
echo -e "${GREEN}✓${NC} 소유자: slurm:slurm, 권한: 755"

# 권한 검증
OWNER=$(stat -c '%U:%G' "$SANDBOX_DIR")
PERMS=$(stat -c '%a' "$SANDBOX_DIR")

if [ "$OWNER" != "slurm:slurm" ]; then
    echo -e "${RED}✗${NC} 소유자가 올바르지 않습니다: $OWNER"
    exit 1
fi

if [ "$PERMS" != "755" ]; then
    echo -e "${RED}✗${NC} 권한이 올바르지 않습니다: $PERMS"
    exit 1
fi

echo -e "${GREEN}✓${NC} 권한 검증 완료"

# 쓰기 권한 테스트
echo
echo "Slurm 사용자 쓰기 권한 테스트 중..."
TEST_FILE="$SANDBOX_DIR/.test_write_$$"

if sudo -u slurm touch "$TEST_FILE" 2>/dev/null; then
    sudo -u slurm rm "$TEST_FILE"
    echo -e "${GREEN}✓${NC} Slurm 사용자 쓰기 권한 확인"
else
    echo -e "${RED}✗${NC} Slurm 사용자 쓰기 권한 없음"
    exit 1
fi

# GPU 접근 테스트 (NVIDIA GPU가 있는 경우)
echo
echo "GPU 접근 테스트 중..."

if command -v nvidia-smi &> /dev/null; then
    echo "NVIDIA GPU 감지됨. Apptainer GPU 접근 테스트 중..."

    if timeout 30s apptainer exec --nv docker://ubuntu:22.04 nvidia-smi &>/dev/null; then
        echo -e "${GREEN}✓${NC} Apptainer GPU 접근 성공"
    else
        echo -e "${YELLOW}⚠${NC} Apptainer GPU 접근 테스트 실패"
        echo "VNC GPU 세션 사용 시 문제가 발생할 수 있습니다."
        echo "nvidia-container-toolkit 설치 확인: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html"
    fi
else
    echo -e "${YELLOW}⚠${NC} nvidia-smi를 찾을 수 없습니다."
    echo "GPU가 없거나 NVIDIA 드라이버가 설치되지 않았습니다."
    echo "GPU 기능이 필요한 경우 NVIDIA 드라이버를 설치해주세요."
fi

# /scratch 디렉토리 정보 출력
echo
echo "디스크 공간 확인 중..."
df -h /scratch | tail -n 1 | awk '{print "사용 가능: "$4" / "$2" ("$5" 사용됨)"}'

AVAILABLE_GB=$(df -BG /scratch | tail -n 1 | awk '{print $4}' | sed 's/G//')
if [ "$AVAILABLE_GB" -lt 50 ]; then
    echo -e "${YELLOW}⚠${NC} /scratch 공간이 50GB 미만입니다. (${AVAILABLE_GB}GB)"
    echo "Apptainer sandbox는 이미지당 5-10GB를 사용할 수 있습니다."
fi

# my_cluster.yaml 업데이트 확인
echo
echo "my_cluster.yaml 설정 확인 중..."
CLUSTER_YAML="../my_cluster.yaml"

if [ -f "$CLUSTER_YAML" ]; then
    if grep -q "sandbox_path: /scratch/apptainer_sandboxes" "$CLUSTER_YAML"; then
        echo -e "${GREEN}✓${NC} my_cluster.yaml에 sandbox_path 설정됨"
    else
        echo -e "${YELLOW}⚠${NC} my_cluster.yaml에 sandbox_path 설정이 없습니다."
        echo "다음 설정을 추가해주세요:"
        echo "  sandbox_path: /scratch/apptainer_sandboxes"
    fi
else
    echo -e "${YELLOW}⚠${NC} my_cluster.yaml 파일을 찾을 수 없습니다: $CLUSTER_YAML"
fi

echo
echo -e "${GREEN}✓✓✓ Phase 0: Apptainer Sandbox 설정 완료! ✓✓✓${NC}"
echo
echo "Sandbox 디렉토리: $SANDBOX_DIR"
echo "소유자: slurm:slurm"
echo "권한: 755"
echo
echo "다음 단계: ./validate_phase0.sh"
