#!/bin/bash
################################################################################
# HPC 라이선스 관리 및 컨테이너 검증 스크립트
#
# Phase 1: SIF 컨테이너 구동 점검
# Phase 2: 라이선스 파일 업데이트 (호스트 + 컨테이너 내부)
# Phase 3: 컨테이너 이미지 배포
#
# 사용법:
#   sudo ./start_license_update.sh --phase 1              # 컨테이너 검증만
#   sudo ./start_license_update.sh --phase 2 --config license_config.yaml  # 라이선스 업데이트
#   sudo ./start_license_update.sh --phase 3              # 이미지 배포
#   sudo ./start_license_update.sh --all                  # 전체 실행
#
# 옵션:
#   --phase <1|2|3>     실행할 Phase 번호
#   --all               전체 Phase 실행 (1 → 2 → 3)
#   --config PATH       라이선스 설정 YAML 파일 (Phase 2 필수)
#   --cluster PATH      클러스터 설정 YAML 파일 (기본: my_multihead_cluster.yaml)
#   --dry-run           실제 실행 없이 미리보기
#   --help              도움말 표시
################################################################################

set -euo pipefail

# 색상 정의
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# 로그 함수
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 스크립트 디렉토리
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 기본값
PHASE=""
RUN_ALL=false
LICENSE_CONFIG=""
CLUSTER_CONFIG="$SCRIPT_DIR/my_multihead_cluster.yaml"
DRY_RUN=false

# SSH 옵션
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

################################################################################
# 도움말
################################################################################
show_help() {
    cat << EOF
╔════════════════════════════════════════════════════════════╗
║   HPC 라이선스 관리 및 컨테이너 검증 스크립트            ║
╚════════════════════════════════════════════════════════════╝

사용법:
  sudo $0 [OPTIONS]

옵션:
  --phase <1|2|3>     실행할 Phase 번호
                      1: SIF 컨테이너 구동 점검
                      2: 라이선스 파일 업데이트
                      3: 컨테이너 이미지 배포

  --all               전체 Phase 실행 (1 → 2 → 3)

  --config PATH       라이선스 설정 YAML 파일
                      (Phase 2 실행 시 필수)

  --cluster PATH      클러스터 설정 YAML 파일
                      (기본: my_multihead_cluster.yaml)

  --dry-run           실제 실행 없이 미리보기

  --help              이 도움말 표시

예시:
  # Phase 1: 모든 노드의 SIF 컨테이너 구동 테스트
  sudo $0 --phase 1

  # Phase 2: 라이선스 업데이트
  sudo $0 --phase 2 --config license_config.yaml

  # Phase 3: 컨테이너 이미지 배포
  sudo $0 --phase 3

  # 전체 실행
  sudo $0 --all --config license_config.yaml

EOF
}

################################################################################
# 인자 파싱
################################################################################
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --phase)
                PHASE="$2"
                if [[ ! "$PHASE" =~ ^[123]$ ]]; then
                    log_error "Invalid phase: $PHASE (must be 1, 2, or 3)"
                    exit 1
                fi
                shift 2
                ;;
            --all)
                RUN_ALL=true
                shift
                ;;
            --config)
                LICENSE_CONFIG="$2"
                shift 2
                ;;
            --cluster)
                CLUSTER_CONFIG="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # 검증
    if [[ "$RUN_ALL" == false && -z "$PHASE" ]]; then
        log_error "Either --phase or --all must be specified"
        show_help
        exit 1
    fi

    if [[ "$PHASE" == "2" || "$RUN_ALL" == true ]] && [[ -z "$LICENSE_CONFIG" ]]; then
        log_error "Phase 2 requires --config option"
        exit 1
    fi
}

################################################################################
# 클러스터 노드 정보 읽기
################################################################################
get_cluster_nodes() {
    if [[ ! -f "$CLUSTER_CONFIG" ]]; then
        log_error "Cluster config not found: $CLUSTER_CONFIG"
        exit 1
    fi

    log_info "Reading cluster nodes from: $CLUSTER_CONFIG"

    python3 << EOPY
import yaml
import sys

try:
    with open('$CLUSTER_CONFIG', 'r') as f:
        config = yaml.safe_load(f)

    nodes = []

    # Controller nodes
    for node in config.get('controllers', []):
        nodes.append({
            'hostname': node['hostname'],
            'ip': node['ip'],
            'user': node.get('user', 'hpcadmin')
        })

    # Compute nodes
    for node in config.get('compute_nodes', []):
        nodes.append({
            'hostname': node['hostname'],
            'ip': node['ip'],
            'user': node.get('user', 'hpcadmin')
        })

    # Visualization nodes
    for node in config.get('visualization', {}).get('nodes', []):
        nodes.append({
            'hostname': node['hostname'],
            'ip': node['ip'],
            'user': node.get('user', 'hpcadmin')
        })

    # 중복 제거
    unique_nodes = {node['ip']: node for node in nodes}

    # 출력 (bash에서 읽을 수 있는 형식)
    for node in unique_nodes.values():
        print(f"{node['hostname']}|{node['ip']}|{node['user']}")

except Exception as e:
    print(f"Error reading cluster config: {e}", file=sys.stderr)
    sys.exit(1)
EOPY
}

################################################################################
# Phase 1: SIF 컨테이너 구동 점검
################################################################################
phase1_verify_containers() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  Phase 1: SIF 컨테이너 구동 점검                         ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    log_info "Verifying Apptainer installation and SIF containers..."

    local nodes=$(get_cluster_nodes)
    local total_nodes=$(echo "$nodes" | wc -l)
    local current=0
    local success_count=0
    local fail_count=0

    while IFS='|' read -r hostname ip user; do
        ((current++))
        echo ""
        log_info "[$current/$total_nodes] Checking node: $hostname ($ip)"

        # 1. Apptainer 설치 확인
        if ! ssh $SSH_OPTS ${user}@${ip} "command -v apptainer" &>/dev/null; then
            log_error "  Apptainer not installed on $hostname"
            ((fail_count++))
            continue
        fi
        log_success "  ✓ Apptainer installed"

        # 2. SIF 이미지 경로 확인
        local sif_path="/opt/apptainer/images"
        if ! ssh $SSH_OPTS ${user}@${ip} "test -d $sif_path" &>/dev/null; then
            log_warning "  SIF directory not found: $sif_path"
            ((fail_count++))
            continue
        fi

        # 3. SIF 파일 목록
        local sif_files=$(ssh $SSH_OPTS ${user}@${ip} "ls -1 $sif_path/*.sif 2>/dev/null" || echo "")
        if [[ -z "$sif_files" ]]; then
            log_warning "  No SIF files found in $sif_path"
            ((fail_count++))
            continue
        fi

        local sif_count=$(echo "$sif_files" | wc -l)
        log_info "  Found $sif_count SIF images"

        # 4. 각 SIF 이미지 테스트
        local image_success=0
        local image_fail=0

        while IFS= read -r sif_file; do
            local sif_name=$(basename "$sif_file")
            echo -n "    Testing $sif_name... "

            if [[ "$DRY_RUN" == true ]]; then
                echo -e "${CYAN}[DRY-RUN] Would test: apptainer exec $sif_file /bin/true${NC}"
                ((image_success++))
            else
                # 간단한 실행 테스트 (timeout 10초)
                if timeout 10 ssh $SSH_OPTS ${user}@${ip} "apptainer exec $sif_file /bin/true" &>/dev/null; then
                    echo -e "${GREEN}✓${NC}"
                    ((image_success++))
                else
                    echo -e "${RED}✗${NC}"
                    ((image_fail++))
                fi
            fi
        done <<< "$sif_files"

        if [[ $image_fail -eq 0 ]]; then
            log_success "  All $image_success images passed"
            ((success_count++))
        else
            log_warning "  $image_success passed, $image_fail failed"
            ((fail_count++))
        fi

    done <<< "$nodes"

    echo ""
    echo "════════════════════════════════════════════════════════════"
    log_info "Phase 1 Summary: $success_count nodes OK, $fail_count nodes failed"
    echo "════════════════════════════════════════════════════════════"

    return 0
}

################################################################################
# Phase 2: 라이선스 파일 업데이트
################################################################################
phase2_update_licenses() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  Phase 2: 라이선스 파일 업데이트                         ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    if [[ ! -f "$LICENSE_CONFIG" ]]; then
        log_error "License config not found: $LICENSE_CONFIG"
        return 1
    fi

    log_info "Reading license configuration from: $LICENSE_CONFIG"

    # 라이선스 정보 읽기
    local license_data=$(python3 << EOPY
import yaml
import sys

try:
    with open('$LICENSE_CONFIG', 'r') as f:
        config = yaml.safe_load(f)

    licenses = config.get('licenses', [])
    for lic in licenses:
        name = lic.get('name', '')
        path = lic.get('license_file_path', '')
        ip = lic.get('license_server_ip', '')
        content = lic.get('license_content', '')

        # {LICENSE_IP} 치환
        content = content.replace('{LICENSE_IP}', ip)

        print(f"LICENSE_START|{name}|{path}|{ip}")
        print(content)
        print("LICENSE_END")

except Exception as e:
    print(f"Error reading license config: {e}", file=sys.stderr)
    sys.exit(1)
EOPY
)

    # 클러스터 노드 목록
    local nodes=$(get_cluster_nodes)

    # 각 라이선스 처리
    local current_license=""
    local current_path=""
    local current_ip=""
    local current_content=""

    while IFS= read -r line; do
        if [[ "$line" =~ ^LICENSE_START\|(.*)\|(.*)\|(.*)$ ]]; then
            current_license="${BASH_REMATCH[1]}"
            current_path="${BASH_REMATCH[2]}"
            current_ip="${BASH_REMATCH[3]}"
            current_content=""
            log_info "Processing license: $current_license"

        elif [[ "$line" == "LICENSE_END" ]]; then
            # 모든 노드에 라이선스 배포
            while IFS='|' read -r hostname ip user; do
                log_info "  Updating $current_license on $hostname..."

                if [[ "$DRY_RUN" == true ]]; then
                    echo -e "${CYAN}[DRY-RUN] Would create: $current_path${NC}"
                    echo -e "${CYAN}Content:${NC}"
                    echo "$current_content" | sed 's/^/    /'
                else
                    # 디렉토리 생성
                    local dir=$(dirname "$current_path")
                    ssh $SSH_OPTS ${user}@${ip} "sudo mkdir -p $dir" || log_warning "    Failed to create directory on $hostname"

                    # 라이선스 파일 생성
                    echo "$current_content" | ssh $SSH_OPTS ${user}@${ip} "sudo tee $current_path > /dev/null" && \
                        log_success "    ✓ License updated on $hostname" || \
                        log_error "    ✗ Failed to update license on $hostname"
                fi
            done <<< "$nodes"

            # SIF 이미지 내부 업데이트 (선택사항)
            update_sif_licenses_internal "$current_license" "$current_path" "$current_content"

        else
            current_content+="$line"$'\n'
        fi
    done <<< "$license_data"

    log_success "Phase 2 completed"
    return 0
}

################################################################################
# SIF 이미지 내부 라이선스 업데이트
################################################################################
update_sif_licenses_internal() {
    local license_name="$1"
    local license_path="$2"
    local license_content="$3"

    # YAML에서 container_update 설정 읽기
    local update_enabled=$(python3 -c "import yaml; config=yaml.safe_load(open('$LICENSE_CONFIG')); print(config.get('container_update', {}).get('update_sif_licenses', False))")

    if [[ "$update_enabled" != "True" ]]; then
        log_info "  SIF internal update disabled (skipping)"
        return 0
    fi

    log_info "  Updating SIF images for $license_name..."

    local nodes=$(get_cluster_nodes)
    local sif_path="/opt/apptainer/images"
    local sandbox_temp="/scratch/apptainer_sandbox_temp"

    while IFS='|' read -r hostname ip user; do
        log_info "    Processing SIF images on $hostname..."

        # SIF 파일 목록
        local sif_files=$(ssh $SSH_OPTS ${user}@${ip} "ls -1 $sif_path/*.sif 2>/dev/null" || echo "")
        if [[ -z "$sif_files" ]]; then
            log_warning "      No SIF files found"
            continue
        fi

        while IFS= read -r sif_file; do
            local sif_name=$(basename "$sif_file")
            log_info "      Updating $sif_name..."

            if [[ "$DRY_RUN" == true ]]; then
                echo -e "${CYAN}[DRY-RUN] Would update $sif_name${NC}"
                continue
            fi

            # 샌드박스 생성
            local sandbox_dir="$sandbox_temp/${sif_name%.sif}_sandbox"
            ssh $SSH_OPTS ${user}@${ip} << EOSSH
                set -e
                sudo rm -rf "$sandbox_dir"
                sudo apptainer build --sandbox "$sandbox_dir" "$sif_file"

                # 라이선스 파일 업데이트
                sudo mkdir -p "$sandbox_dir$(dirname $license_path)"
                echo '$license_content' | sudo tee "$sandbox_dir$license_path" > /dev/null

                # SIF로 재빌드
                sudo apptainer build --force "$sif_file" "$sandbox_dir"

                # 샌드박스 정리
                sudo rm -rf "$sandbox_dir"
EOSSH

            if [[ $? -eq 0 ]]; then
                log_success "        ✓ $sif_name updated"
            else
                log_error "        ✗ Failed to update $sif_name"
            fi
        done <<< "$sif_files"

    done <<< "$nodes"
}

################################################################################
# Phase 3: 컨테이너 이미지 배포
################################################################################
phase3_deploy_images() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  Phase 3: 컨테이너 이미지 배포                           ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    log_info "Deploying SIF images from apptainer/ directory..."

    # 소스 이미지 디렉토리
    local source_viz="$SCRIPT_DIR/apptainer/viz-node-images"
    local source_compute="$SCRIPT_DIR/apptainer/compute-node-images"

    if [[ ! -d "$source_viz" && ! -d "$source_compute" ]]; then
        log_error "No SIF images found in apptainer/ directory"
        return 1
    fi

    # phase8_containers.sh 재사용
    local phase8_script="$SCRIPT_DIR/cluster/setup/phase8_containers.sh"

    if [[ -f "$phase8_script" ]]; then
        log_info "Using existing phase8_containers.sh..."

        if [[ "$DRY_RUN" == true ]]; then
            sudo "$phase8_script" --config "$CLUSTER_CONFIG" --dry-run
        else
            sudo "$phase8_script" --config "$CLUSTER_CONFIG"
        fi
    else
        log_warning "phase8_containers.sh not found, deploying manually..."

        # 수동 배포
        local nodes=$(get_cluster_nodes)
        local target_path="/opt/apptainer/images"

        while IFS='|' read -r hostname ip user; do
            log_info "  Deploying to $hostname..."

            # 타겟 디렉토리 생성
            ssh $SSH_OPTS ${user}@${ip} "sudo mkdir -p $target_path"

            # SIF 파일 복사
            for source_dir in "$source_viz" "$source_compute"; do
                if [[ -d "$source_dir" ]]; then
                    for sif in "$source_dir"/*.sif; do
                        [[ -e "$sif" ]] || continue

                        local sif_name=$(basename "$sif")
                        log_info "    Copying $sif_name..."

                        if [[ "$DRY_RUN" == true ]]; then
                            echo -e "${CYAN}[DRY-RUN] Would copy: $sif → ${user}@${ip}:$target_path/${NC}"
                        else
                            scp $SSH_OPTS "$sif" ${user}@${ip}:/tmp/$sif_name && \
                            ssh $SSH_OPTS ${user}@${ip} "sudo mv /tmp/$sif_name $target_path/" && \
                            log_success "      ✓ $sif_name deployed" || \
                            log_error "      ✗ Failed to deploy $sif_name"
                        fi
                    done
                fi
            done
        done <<< "$nodes"
    fi

    log_success "Phase 3 completed"
    return 0
}

################################################################################
# 메인 함수
################################################################################
main() {
    # Root 권한 확인
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi

    parse_args "$@"

    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║   HPC 라이선스 관리 및 컨테이너 검증                     ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    if [[ "$DRY_RUN" == true ]]; then
        log_warning "DRY-RUN mode enabled (no actual changes will be made)"
        echo ""
    fi

    # Phase 실행
    if [[ "$RUN_ALL" == true ]]; then
        phase1_verify_containers
        phase2_update_licenses
        phase3_deploy_images
    else
        case "$PHASE" in
            1)
                phase1_verify_containers
                ;;
            2)
                phase2_update_licenses
                ;;
            3)
                phase3_deploy_images
                ;;
        esac
    fi

    echo ""
    log_success "All operations completed successfully!"
    echo ""
}

main "$@"
