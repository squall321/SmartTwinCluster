#!/bin/bash
################################################################################
# KooSlurmInstallAutomation - 통합 설정 스크립트
# 모든 초기 설정을 한 번에 처리합니다
################################################################################

set -e  # 에러 발생시 즉시 종료

# 색상 정의
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 로고 출력
echo -e "${BLUE}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║   KooSlurmInstallAutomation 통합 설정 도구                 ║
║                                                           ║
║   Slurm 클러스터 자동 설치를 위한 환경을 준비합니다        ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_ROOT"

echo ""
echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}  1단계: Python 확인 및 설치${NC}"
echo -e "${BLUE}================================${NC}"
echo ""

# Python 버전 확인 함수
check_python_version() {
    local python_cmd=$1
    if command -v $python_cmd &> /dev/null; then
        local version=$($python_cmd --version 2>&1 | awk '{print $2}')
        local major=$(echo $version | cut -d. -f1)
        local minor=$(echo $version | cut -d. -f2)
        echo "$major.$minor"
        return 0
    fi
    return 1
}

# Python 3.12 우선 확인
PYTHON_CMD=""
PYTHON_VERSION=""

echo "Python 3.12 확인 중..."
if version=$(check_python_version "python3.12"); then
    PYTHON_CMD="python3.12"
    PYTHON_VERSION=$version
    echo -e "${GREEN}✓${NC} Python 3.12 발견: $PYTHON_VERSION"
elif version=$(check_python_version "python3.11"); then
    PYTHON_CMD="python3.11"
    PYTHON_VERSION=$version
    echo -e "${YELLOW}⚠${NC} Python 3.12를 찾을 수 없어 3.11 사용: $PYTHON_VERSION"
elif version=$(check_python_version "python3.10"); then
    PYTHON_CMD="python3.10"
    PYTHON_VERSION=$version
    echo -e "${YELLOW}⚠${NC} Python 3.12를 찾을 수 없어 3.10 사용: $PYTHON_VERSION"
elif version=$(check_python_version "python3"); then
    PYTHON_CMD="python3"
    PYTHON_VERSION=$version
    echo -e "${YELLOW}⚠${NC} Python 3.12를 찾을 수 없어 기본 python3 사용: $PYTHON_VERSION"
else
    echo -e "${RED}✗${NC} Python 3가 설치되지 않았습니다"
    echo ""
    echo "Python 3.12 설치가 필요합니다. 설치 방법:"
    echo ""
    echo "Ubuntu/Debian:"
    echo "  sudo add-apt-repository ppa:deadsnakes/ppa"
    echo "  sudo apt update"
    echo "  sudo apt install python3.12 python3.12-venv python3.12-dev"
    echo ""
    echo "CentOS/RHEL (EPEL 필요):"
    echo "  sudo yum install python3.12 python3.12-devel"
    echo ""
    echo "또는 기존 Python 3.6+ 사용:"
    echo "  sudo yum install python3 python3-devel"
    echo "  sudo apt install python3 python3-venv python3-dev"
    echo ""
    read -p "Python 3.12 설치를 시도하시겠습니까? (Ubuntu/Debian만 지원) (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Python 3.12 설치 시도 중..."
        sudo add-apt-repository ppa:deadsnakes/ppa -y
        sudo apt update
        sudo apt install -y python3.12 python3.12-venv python3.12-dev python3.12-distutils
        
        if command -v python3.12 &> /dev/null; then
            PYTHON_CMD="python3.12"
            PYTHON_VERSION=$(python3.12 --version | awk '{print $2}')
            echo -e "${GREEN}✓${NC} Python 3.12 설치 완료: $PYTHON_VERSION"
        else
            echo -e "${RED}✗${NC} Python 3.12 설치 실패"
            exit 1
        fi
    else
        exit 1
    fi
fi

# Python 버전 체크 (3.6 이상 필요)
version_major=$(echo $PYTHON_VERSION | cut -d. -f1)
version_minor=$(echo $PYTHON_VERSION | cut -d. -f2)

if [ "$version_major" -lt 3 ] || ([ "$version_major" -eq 3 ] && [ "$version_minor" -lt 6 ]); then
    echo -e "${RED}✗${NC} Python 3.6 이상이 필요합니다 (현재: $PYTHON_VERSION)"
    exit 1
fi

echo ""
echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}  2단계: pip 확인 및 설치${NC}"
echo -e "${BLUE}================================${NC}"
echo ""

# pip 명령어 확인
PIP_CMD=""

# Python 버전에 맞는 pip 확인
if [ "$PYTHON_CMD" = "python3.12" ]; then
    if command -v pip3.12 &> /dev/null; then
        PIP_CMD="pip3.12"
        echo -e "${GREEN}✓${NC} pip3.12 발견"
    fi
elif [ "$PYTHON_CMD" = "python3.11" ]; then
    if command -v pip3.11 &> /dev/null; then
        PIP_CMD="pip3.11"
        echo -e "${GREEN}✓${NC} pip3.11 발견"
    fi
elif [ "$PYTHON_CMD" = "python3.10" ]; then
    if command -v pip3.10 &> /dev/null; then
        PIP_CMD="pip3.10"
        echo -e "${GREEN}✓${NC} pip3.10 발견"
    fi
fi

# 일반 pip3 확인
if [ -z "$PIP_CMD" ] && command -v pip3 &> /dev/null; then
    PIP_CMD="pip3"
    echo -e "${GREEN}✓${NC} pip3 발견"
fi

# pip가 없으면 설치 시도
if [ -z "$PIP_CMD" ]; then
    echo -e "${YELLOW}⚠${NC} pip가 설치되지 않았습니다"
    echo "pip 설치 시도 중..."
    
    # 방법 1: ensurepip 시도
    if $PYTHON_CMD -m ensurepip --upgrade 2>/dev/null; then
        echo -e "${GREEN}✓${NC} pip 설치 완료 (ensurepip)"
        PIP_CMD="$PYTHON_CMD -m pip"
    # 방법 2: get-pip.py 다운로드
    elif command -v curl &> /dev/null; then
        echo "get-pip.py 다운로드 중..."
        curl -sS https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py
        $PYTHON_CMD /tmp/get-pip.py --user
        rm -f /tmp/get-pip.py
        echo -e "${GREEN}✓${NC} pip 설치 완료 (get-pip.py)"
        PIP_CMD="$PYTHON_CMD -m pip"
    elif command -v wget &> /dev/null; then
        echo "get-pip.py 다운로드 중..."
        wget -q https://bootstrap.pypa.io/get-pip.py -O /tmp/get-pip.py
        $PYTHON_CMD /tmp/get-pip.py --user
        rm -f /tmp/get-pip.py
        echo -e "${GREEN}✓${NC} pip 설치 완료 (get-pip.py)"
        PIP_CMD="$PYTHON_CMD -m pip"
    # 방법 3: 패키지 매니저로 설치
    else
        echo -e "${YELLOW}⚠${NC} 자동 설치 실패. 수동 설치가 필요합니다:"
        echo ""
        if [ "$PYTHON_CMD" = "python3.12" ]; then
            echo "Ubuntu/Debian:"
            echo "  sudo apt install python3.12-pip"
            echo ""
            echo "CentOS/RHEL:"
            echo "  sudo yum install python3.12-pip"
        else
            echo "Ubuntu/Debian:"
            echo "  sudo apt install python3-pip"
            echo ""
            echo "CentOS/RHEL:"
            echo "  sudo yum install python3-pip"
        fi
        echo ""
        read -p "pip 설치를 시도하시겠습니까? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if command -v apt &> /dev/null; then
                if [ "$PYTHON_CMD" = "python3.12" ]; then
                    sudo apt install -y python3.12-pip python3.12-distutils
                else
                    sudo apt install -y python3-pip
                fi
            elif command -v yum &> /dev/null; then
                if [ "$PYTHON_CMD" = "python3.12" ]; then
                    sudo yum install -y python3.12-pip
                else
                    sudo yum install -y python3-pip
                fi
            fi
            
            # 재확인
            if command -v pip3 &> /dev/null; then
                PIP_CMD="pip3"
                echo -e "${GREEN}✓${NC} pip 설치 완료"
            else
                PIP_CMD="$PYTHON_CMD -m pip"
            fi
        else
            echo -e "${RED}✗${NC} pip 설치가 필요합니다"
            exit 1
        fi
    fi
fi

# venv 모듈 확인
echo ""
echo "venv 모듈 확인 중..."
if $PYTHON_CMD -m venv --help &> /dev/null; then
    echo -e "${GREEN}✓${NC} venv 모듈 사용 가능"
else
    echo -e "${RED}✗${NC} venv 모듈이 없습니다"
    echo ""
    echo "venv 설치 방법:"
    if [ "$PYTHON_CMD" = "python3.12" ]; then
        echo "  sudo apt install python3.12-venv  (Ubuntu/Debian)"
        echo "  sudo yum install python3.12-venv  (CentOS/RHEL)"
    else
        echo "  sudo apt install python3-venv  (Ubuntu/Debian)"
        echo "  sudo yum install python3-venv  (CentOS/RHEL)"
    fi
    echo ""
    read -p "venv 설치를 시도하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if command -v apt &> /dev/null; then
            if [ "$PYTHON_CMD" = "python3.12" ]; then
                sudo apt install -y python3.12-venv
            else
                sudo apt install -y python3-venv
            fi
        elif command -v yum &> /dev/null; then
            if [ "$PYTHON_CMD" = "python3.12" ]; then
                sudo yum install -y python3.12-venv
            else
                sudo yum install -y python3-venv
            fi
        fi
    else
        exit 1
    fi
fi

echo ""
echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}  3단계: 가상환경 설정${NC}"
echo -e "${BLUE}================================${NC}"
echo ""

# 기존 가상환경 확인
if [ -d "venv" ]; then
    echo -e "${YELLOW}⚠${NC} 기존 가상환경이 존재합니다"
    
    # 기존 가상환경의 Python 버전 확인
    if [ -f "venv/bin/python" ]; then
        VENV_PY_VERSION=$(venv/bin/python --version 2>&1 | awk '{print $2}')
        echo "  기존 가상환경 Python 버전: $VENV_PY_VERSION"
        echo "  새로 생성할 Python 버전: $PYTHON_VERSION"
    fi
    
    read -p "  삭제하고 새로 생성하시겠습니까? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf venv
        echo -e "${GREEN}✓${NC} 기존 가상환경 삭제됨"
    else
        echo -e "${BLUE}→${NC} 기존 가상환경 사용"
    fi
fi

# 가상환경 생성
if [ ! -d "venv" ]; then
    echo "가상환경 생성 중 ($PYTHON_CMD)..."
    $PYTHON_CMD -m venv venv
    echo -e "${GREEN}✓${NC} 가상환경 생성 완료"
fi

# 가상환경 활성화
source venv/bin/activate
echo -e "${GREEN}✓${NC} 가상환경 활성화됨 (Python $(python --version 2>&1 | awk '{print $2}'))"

echo ""
echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}  4단계: 의존성 패키지 설치${NC}"
echo -e "${BLUE}================================${NC}"
echo ""

# pip 업그레이드
echo "pip 업그레이드 중..."
python -m pip install --upgrade pip --quiet
echo -e "${GREEN}✓${NC} pip 업그레이드 완료"

# requirements.txt가 있는 경우 설치
if [ -f "requirements.txt" ]; then
    echo "의존성 패키지 설치 중..."
    if pip install -r requirements.txt; then
        echo -e "${GREEN}✓${NC} 의존성 패키지 설치 완료"
    else
        echo -e "${RED}✗${NC} 일부 패키지 설치 실패"
        echo "필수 패키지만 설치 시도 중..."
        pip install paramiko PyYAML colorama tqdm psutil rich
        echo -e "${GREEN}✓${NC} 필수 패키지 설치 완료"
    fi
else
    echo -e "${YELLOW}⚠${NC} requirements.txt 파일이 없습니다"
    echo "  필수 패키지 설치 중..."
    pip install paramiko PyYAML colorama tqdm psutil rich
    echo -e "${GREEN}✓${NC} 필수 패키지 설치 완료"
fi

echo ""
echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}  5단계: 실행 권한 설정${NC}"
echo -e "${BLUE}================================${NC}"
echo ""

# Python 스크립트 실행 권한
chmod +x install_slurm.py 2>/dev/null && echo -e "${GREEN}✓${NC} install_slurm.py" || true
chmod +x generate_config.py 2>/dev/null && echo -e "${GREEN}✓${NC} generate_config.py" || true
chmod +x validate_config.py 2>/dev/null && echo -e "${GREEN}✓${NC} validate_config.py" || true
chmod +x test_connection.py 2>/dev/null && echo -e "${GREEN}✓${NC} test_connection.py" || true
chmod +x view_performance_report.py 2>/dev/null && echo -e "${GREEN}✓${NC} view_performance_report.py" || true
chmod +x run_tests.py 2>/dev/null && echo -e "${GREEN}✓${NC} run_tests.py" || true

# 쉘 스크립트 실행 권한
chmod +x pre_install_check.sh 2>/dev/null && echo -e "${GREEN}✓${NC} pre_install_check.sh" || true

echo ""
echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}  6단계: 디렉토리 구조 확인${NC}"
echo -e "${BLUE}================================${NC}"
echo ""

# 필수 디렉토리 생성
mkdir -p logs && echo -e "${GREEN}✓${NC} logs/"
mkdir -p configs && echo -e "${GREEN}✓${NC} configs/"
mkdir -p performance_logs && echo -e "${GREEN}✓${NC} performance_logs/"

# 템플릿 및 예시 확인
if [ -d "templates" ]; then
    echo -e "${GREEN}✓${NC} templates/ ($(ls templates/*.yaml 2>/dev/null | wc -l)개 템플릿)"
fi

if [ -d "examples" ]; then
    echo -e "${GREEN}✓${NC} examples/ ($(ls examples/*.yaml 2>/dev/null | wc -l)개 예시)"
fi

echo ""
echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}  7단계: 설치 테스트${NC}"
echo -e "${BLUE}================================${NC}"
echo ""

# Python 모듈 import 테스트
echo "Python 모듈 테스트 중..."
python << 'PYEOF'
try:
    import paramiko
    import yaml
    import colorama
    from tqdm import tqdm
    import psutil
    print("✓ 모든 필수 모듈 import 성공")
except ImportError as e:
    print(f"✗ 모듈 import 실패: {e}")
    exit(1)
PYEOF

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Python 모듈 테스트 통과"
else
    echo -e "${RED}✗${NC} Python 모듈 테스트 실패"
    exit 1
fi

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                           ║${NC}"
echo -e "${GREEN}║   ✅  설정이 완료되었습니다!                                ║${NC}"
echo -e "${GREEN}║                                                           ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${BLUE}📋 설정 요약:${NC}"
echo "  • Python: $PYTHON_CMD ($PYTHON_VERSION)"
echo "  • pip: $PIP_CMD"
echo "  • 가상환경: venv/ (Python $(python --version 2>&1 | awk '{print $2}'))"
echo ""

echo -e "${BLUE}📋 다음 단계:${NC}"
echo ""
echo "1. 시스템 사전 점검 (선택사항)"
echo -e "   ${YELLOW}./pre_install_check.sh${NC}"
echo ""
echo "2. 설정 파일 생성"
echo -e "   ${YELLOW}./generate_config.py${NC}"
echo -e "   또는 예시 파일 복사:"
echo -e "   ${YELLOW}cp examples/2node_example.yaml my_cluster.yaml${NC}"
echo ""
echo "3. 설정 파일 편집"
echo -e "   ${YELLOW}vim my_cluster.yaml${NC}"
echo ""
echo "4. 설정 파일 검증"
echo -e "   ${YELLOW}./validate_config.py my_cluster.yaml${NC}"
echo ""
echo "5. SSH 연결 테스트"
echo -e "   ${YELLOW}./test_connection.py my_cluster.yaml${NC}"
echo ""
echo "6. Slurm 설치 시작"
echo -e "   ${YELLOW}./install_slurm.py -c my_cluster.yaml${NC}"
echo ""

echo -e "${BLUE}💡 도움말:${NC}"
echo "  • 전체 문서: cat README.md"
echo "  • 빠른 시작: cat QUICKSTART.md"
echo "  • 가상환경 활성화: source venv/bin/activate"
echo "  • 가상환경 비활성화: deactivate"
echo ""

echo -e "${BLUE}🔗 추가 리소스:${NC}"
echo "  • 문서: docs/"
echo "  • 예시: examples/"
echo ""

echo "Happy Computing! 🚀"
echo ""
