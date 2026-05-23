#!/bin/bash

################################################################################
# Apptainer Image Sync Script
# 
# 이 스크립트는 로컬의 apptainers 디렉토리에 있는 .def와 .sif 파일을
# 모든 계산 노드의 /opt/containers 디렉토리로 복사합니다.
#
# 자동으로 수행하는 작업:
#   1. /opt 디렉토리 존재 및 권한 체크
#   2. 권한 문제 시 자동 수정 (sudo 사용)
#   3. /opt/containers 디렉토리 생성
#   4. 파일 동기화
#
# 사용법:
#   ./sync_apptainers_to_nodes.sh [options]
#
# 옵션:
#   --config FILE    YAML 설정 파일 (기본: my_multihead_cluster.yaml)
#   --force          기존 파일 덮어쓰기
#   --dry-run        실제 복사 없이 시뮬레이션만 수행
#   --help           도움말 출력
################################################################################

set -e

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 기본 설정
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/my_multihead_cluster.yaml"
LOCAL_APPTAINER_DIR="${SCRIPT_DIR}/apptainers"
REMOTE_APPTAINER_DIR="/opt/containers"
FORCE_OVERWRITE=false
DRY_RUN=false

# 로그 함수
log_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "\n${MAGENTA}==>${NC} ${BLUE}$1${NC}\n"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# 도움말 출력
show_help() {
    cat << EOF
사용법: $0 [옵션]

Apptainer 이미지 동기화 스크립트

이 스크립트는 자동으로:
  - /opt 디렉토리 존재 및 권한 확인
  - 쓰기 권한이 없으면 자동으로 수정 (sudo)
  - /opt/containers 디렉토리 생성
  - .def 및 .sif 파일을 모든 노드에 동기화

옵션:
    --config FILE    YAML 설정 파일 지정 (기본: my_multihead_cluster.yaml)
    --force          기존 파일을 강제로 덮어쓰기
    --dry-run        실제 복사 없이 시뮬레이션만 수행
    --help           이 도움말 출력

예제:
    $0                           # 기본 설정으로 동기화
    $0 --force                   # 강제 덮어쓰기
    $0 --dry-run                 # 시뮬레이션
    $0 --config dev_cluster.yaml # 다른 설정 파일 사용

EOF
    exit 0
}

# 명령줄 인자 파싱
while [[ $# -gt 0 ]]; do
    case $1 in
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --force)
            FORCE_OVERWRITE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            show_help
            ;;
        *)
            log_error "알 수 없는 옵션: $1"
            echo "도움말을 보려면 --help를 사용하세요."
            exit 1
            ;;
    esac
done

# 필수 도구 확인
check_requirements() {
    log_step "필수 도구 확인"
    
    local missing_tools=()
    
    if ! command -v python3 &> /dev/null; then
        missing_tools+=("python3")
    fi
    
    if ! command -v ssh &> /dev/null; then
        missing_tools+=("ssh")
    fi
    
    if ! command -v rsync &> /dev/null; then
        missing_tools+=("rsync")
    fi
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "다음 도구가 필요합니다: ${missing_tools[*]}"
        exit 1
    fi
    
    # Python yaml 모듈 확인
    if ! python3 -c "import yaml" 2>/dev/null; then
        log_error "Python yaml 모듈이 설치되어 있지 않습니다"
        log_info "설치 방법: pip3 install pyyaml"
        log_info "또는: sudo apt-get install python3-yaml"
        log_info "또는: ./install_pyyaml.sh (자동 설치)"
        exit 1
    fi
    
    log_success "모든 필수 도구가 설치되어 있습니다"
}

# YAML 파일 확인
check_config_file() {
    log_step "설정 파일 확인"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "설정 파일을 찾을 수 없습니다: $CONFIG_FILE"
        exit 1
    fi
    
    log_info "설정 파일: $CONFIG_FILE"
    log_success "설정 파일 확인 완료"
}

# 로컬 apptainers 디렉토리 확인
check_local_directory() {
    log_step "로컬 Apptainer 디렉토리 확인"
    
    if [ ! -d "$LOCAL_APPTAINER_DIR" ]; then
        log_error "로컬 apptainers 디렉토리가 없습니다: $LOCAL_APPTAINER_DIR"
        exit 1
    fi
    
    # .def 및 .sif 파일 개수 확인
    local def_count=$(find "$LOCAL_APPTAINER_DIR" -type f -name "*.def" 2>/dev/null | wc -l)
    local sif_count=$(find "$LOCAL_APPTAINER_DIR" -type f -name "*.sif" 2>/dev/null | wc -l)
    
    log_info "발견된 파일:"
    log_info "  - Definition 파일 (.def): $def_count"
    log_info "  - Image 파일 (.sif): $sif_count"
    
    if [ $def_count -eq 0 ] && [ $sif_count -eq 0 ]; then
        log_warning "복사할 apptainer 파일이 없습니다"
        log_info "apptainers/ 디렉토리에 .def 또는 .sif 파일을 추가하세요"
        exit 0
    fi
    
    log_success "로컬 디렉토리 확인 완료"
}

# YAML에서 계산 노드 정보 추출
get_compute_nodes() {
    local config_file="$1"
    python3 << EOF
import yaml
import sys

try:
    with open('${config_file}', 'r') as f:
        config = yaml.safe_load(f)
    
    if not config:
        print("ERROR: YAML 파일을 읽을 수 없습니다", file=sys.stderr)
        sys.exit(1)
    
    nodes = config.get('nodes', {})
    if not nodes:
        print("ERROR: 'nodes' 섹션을 찾을 수 없습니다", file=sys.stderr)
        sys.exit(1)
    
    compute_nodes = nodes.get('compute_nodes', [])
    
    if not compute_nodes:
        print("ERROR: 'compute_nodes'가 비어있거나 없습니다", file=sys.stderr)
        sys.exit(1)
    
    for node in compute_nodes:
        hostname = node.get('hostname', '')
        ip = node.get('ip_address', '')
        ssh_user = node.get('ssh_user', 'koopark')
        ssh_port = node.get('ssh_port', 22)
        ssh_key = node.get('ssh_key_path', '~/.ssh/id_rsa')
        
        if hostname and ip:
            print(f"{hostname}|{ip}|{ssh_user}|{ssh_port}|{ssh_key}")
            
except yaml.YAMLError as e:
    print(f"ERROR: YAML 파싱 오류: {e}", file=sys.stderr)
    sys.exit(1)
except FileNotFoundError:
    print(f"ERROR: 파일을 찾을 수 없습니다: ${config_file}", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
EOF
}

# SSH 연결 테스트
test_ssh_connection() {
    local user=$1
    local host=$2
    local port=$3
    local key=$4
    
    if [ "$DRY_RUN" = true ]; then
        return 0
    fi
    
    # SSH 키 경로 확장
    key=$(eval echo "$key")
    
    ssh -o BatchMode=yes \
        -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=no \
        -p "$port" \
        -i "$key" \
        "${user}@${host}" \
        "exit" 2>/dev/null
    
    return $?
}

# /opt 디렉토리 권한 체크 및 수정
check_and_fix_opt_permissions() {
    local user=$1
    local host=$2
    local port=$3
    local key=$4
    local hostname=$5
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] /opt 권한 체크 시뮬레이션"
        return 0
    fi
    
    # SSH 키 경로 확장
    key=$(eval echo "$key")
    
    log_debug "[$hostname] /opt 디렉토리 확인 중..."
    
    # 1. /opt 존재 여부 및 권한 확인
    local opt_status=$(ssh -o StrictHostKeyChecking=no \
        -p "$port" \
        -i "$key" \
        "${user}@${host}" \
        "ls -ld /opt 2>&1" 2>/dev/null)
    
    if echo "$opt_status" | grep -q "No such file or directory"; then
        log_warning "[$hostname] /opt 디렉토리가 없습니다. 생성합니다..."
        
        ssh -o StrictHostKeyChecking=no \
            -p "$port" \
            -i "$key" \
            "${user}@${host}" \
            "sudo mkdir -p /opt && sudo chmod 755 /opt" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            log_success "[$hostname] /opt 디렉토리 생성 완료"
        else
            log_error "[$hostname] /opt 디렉토리 생성 실패"
            return 1
        fi
    else
        log_debug "[$hostname] /opt 존재: $opt_status"
    fi
    
    return 0
}

# 원격 디렉토리 생성
create_remote_directory() {
    local user=$1
    local host=$2
    local port=$3
    local key=$4
    local remote_dir=$5
    local hostname=$6
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] 원격 디렉토리 생성 시뮬레이션: $remote_dir"
        return 0
    fi
    
    # SSH 키 경로 확장
    key=$(eval echo "$key")
    
    log_debug "[$hostname] $remote_dir 디렉토리 생성 중..."
    
    # apptainers 디렉토리 생성
    local create_result=$(ssh -o StrictHostKeyChecking=no \
        -p "$port" \
        -i "$key" \
        "${user}@${host}" \
        "mkdir -p $remote_dir 2>&1 && chmod 755 $remote_dir 2>&1 && echo 'SUCCESS'" 2>&1)
    
    if echo "$create_result" | grep -q "SUCCESS"; then
        return 0
    elif echo "$create_result" | grep -qi "permission denied"; then
        # 권한 문제 - sudo로 재시도
        log_warning "[$hostname] 권한 문제 발생. sudo로 재시도합니다..."
        
        ssh -o StrictHostKeyChecking=no \
            -p "$port" \
            -i "$key" \
            "${user}@${host}" \
            "sudo mkdir -p $remote_dir && sudo chown ${user}:${user} $remote_dir && sudo chmod 755 $remote_dir" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            log_success "[$hostname] 디렉토리 생성 완료 (sudo)"
            return 0
        else
            log_error "[$hostname] sudo로도 디렉토리 생성 실패"
            return 1
        fi
    else
        log_error "[$hostname] 디렉토리 생성 실패: $create_result"
        return 1
    fi
}

# Apptainer 파일 동기화
sync_apptainers() {
    local user=$1
    local host=$2
    local port=$3
    local key=$4
    local hostname=$5
    
    log_info "[$hostname] Apptainer 파일 동기화 시작..."
    
    # 1. SSH 연결 테스트
    if ! test_ssh_connection "$user" "$host" "$port" "$key"; then
        log_error "[$hostname] SSH 연결 실패"
        return 1
    fi
    
    log_success "[$hostname] SSH 연결 성공"
    
    # 2. /opt 권한 체크 및 수정
    if ! check_and_fix_opt_permissions "$user" "$host" "$port" "$key" "$hostname"; then
        log_error "[$hostname] /opt 권한 설정 실패"
        return 1
    fi
    
    # 3. 원격 디렉토리 생성
    if ! create_remote_directory "$user" "$host" "$port" "$key" "$REMOTE_APPTAINER_DIR" "$hostname"; then
        log_error "[$hostname] 원격 디렉토리 생성 실패"
        return 1
    fi
    
    log_success "[$hostname] 원격 디렉토리 준비 완료: $REMOTE_APPTAINER_DIR"
    
    # 4. rsync 옵션 설정
    local rsync_opts="-avz --progress"
    
    if [ "$FORCE_OVERWRITE" = false ]; then
        rsync_opts="$rsync_opts --ignore-existing"
    fi
    
    if [ "$DRY_RUN" = true ]; then
        rsync_opts="$rsync_opts --dry-run"
        log_info "[$hostname] DRY-RUN 모드: 실제 파일 전송 없음"
    fi
    
    # SSH 키 경로 확장
    key=$(eval echo "$key")
    
    # 5. 샌드박스 디렉토리 tar 압축 및 전송 (효율적)
    log_info "[$hostname] 샌드박스 압축 중 (sudo 권한)..."

    # 임시 tar 파일 생성
    local tar_file="/tmp/apptainers_$(date +%Y%m%d_%H%M%S).tar.gz"

    # 샌드박스 디렉토리를 tar.gz로 압축 (sudo로 모든 파일 접근)
    sudo tar czf "$tar_file" \
        --exclude='*/var/cache/apt/*' \
        --exclude='*/var/lib/colord/*' \
        --exclude='*/var/lib/saned/*' \
        --exclude='*/var/lib/snapd/void/*' \
        --exclude='compute' \
        -C "$LOCAL_APPTAINER_DIR" \
        . 2>/dev/null

    if [ $? -ne 0 ]; then
        log_error "[$hostname] 샌드박스 압축 실패"
        sudo rm -f "$tar_file"
        return 1
    fi

    # tar 파일 소유권 변경 (전송을 위해)
    sudo chown $USER:$USER "$tar_file"

    local tar_size=$(du -h "$tar_file" | cut -f1)
    log_info "[$hostname] 압축 완료 ($tar_size), 전송 중..."

    # tar 파일 전송
    scp -o StrictHostKeyChecking=no -o ConnectTimeout=10 -P "$port" -i "$key" \
        "$tar_file" "${user}@${host}:/tmp/" 2>&1

    local scp_exit=$?

    if [ $scp_exit -ne 0 ]; then
        log_error "[$hostname] tar 파일 전송 실패 (exit code: $scp_exit)"
        rm -f "$tar_file"
        return 1
    fi

    log_info "[$hostname] 전송 완료, 원격지에서 압축 해제 중..."

    # 원격지에서 압축 해제
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p "$port" -i "$key" "${user}@${host}" \
        "sudo mkdir -p ${REMOTE_APPTAINER_DIR} && \
         sudo tar xzf /tmp/$(basename $tar_file) -C ${REMOTE_APPTAINER_DIR} && \
         rm -f /tmp/$(basename $tar_file)" 2>&1

    local extract_exit=$?

    # 로컬 tar 파일 삭제
    rm -f "$tar_file"

    if [ $extract_exit -eq 0 ]; then
        log_success "[$hostname] Apptainer 샌드박스 배포 완료 (tar: $tar_size → 압축 해제)"
        return 0
    else
        log_error "[$hostname] 압축 해제 실패 (exit code: $extract_exit)"
        return 1
    fi
}

# 메인 동기화 프로세스
main_sync() {
    log_step "계산 노드로 Apptainer 이미지 동기화"
    
    local node_data=$(get_compute_nodes "$CONFIG_FILE")
    
    if [ -z "$node_data" ]; then
        log_error "YAML 파일에서 계산 노드 정보를 찾을 수 없습니다"
        exit 1
    fi
    
    local total_nodes=0
    local success_nodes=0
    local failed_nodes=0
    
    while IFS='|' read -r hostname ip ssh_user ssh_port ssh_key; do
        total_nodes=$((total_nodes + 1))
        
        echo ""
        log_step "노드 처리: $hostname ($ip)"
        
        if sync_apptainers "$ssh_user" "$ip" "$ssh_port" "$ssh_key" "$hostname"; then
            success_nodes=$((success_nodes + 1))
        else
            failed_nodes=$((failed_nodes + 1))
        fi
        
    done <<< "$node_data"
    
    # 결과 요약
    echo ""
    log_step "동기화 결과 요약"
    log_info "총 노드 수: $total_nodes"
    log_success "성공: $success_nodes"
    
    if [ $failed_nodes -gt 0 ]; then
        log_error "실패: $failed_nodes"
        return 1
    fi
    
    return 0
}

# 스크립트 시작
main() {
    echo ""
    log_step "🚀 Apptainer 이미지 동기화 시작"
    
    if [ "$DRY_RUN" = true ]; then
        log_warning "DRY-RUN 모드: 실제 파일 전송은 수행되지 않습니다"
    fi
    
    if [ "$FORCE_OVERWRITE" = true ]; then
        log_warning "강제 덮어쓰기 모드: 기존 파일을 덮어씁니다"
    fi
    
    check_requirements
    check_config_file
    check_local_directory
    
    if main_sync; then
        echo ""
        log_step "✅ 모든 작업이 성공적으로 완료되었습니다"
        
        if [ "$DRY_RUN" = false ]; then
            echo ""
            log_info "다음 명령으로 노드에서 이미지를 확인할 수 있습니다:"
            log_info "  ssh node001 'ls -lh $REMOTE_APPTAINER_DIR'"
            log_info "  ssh node002 'ls -lh $REMOTE_APPTAINER_DIR'"
        fi
        
        exit 0
    else
        echo ""
        log_error "일부 작업이 실패했습니다"
        log_info "문제 해결을 위해 다음을 실행하세요:"
        log_info "  ./debug_apptainer_sync.sh"
        exit 1
    fi
}

# 스크립트 실행
main "$@"
