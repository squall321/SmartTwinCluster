#!/bin/bash
################################################################################
# LS-DYNA Job Submit Manager
# 다양한 LS-DYNA 작업 제출 패턴을 관리하는 통합 스크립트
################################################################################

# 색상 정의
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# 스크립트 디렉토리
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

################################################################################
# 사용법 출력
################################################################################

show_usage() {
    echo -e "${BLUE}================================================================"
    echo "LS-DYNA R16 Job Submit Manager"
    echo "================================================================${NC}"
    echo ""
    echo "Usage: $0 [옵션] <작업타입> <K파일>"
    echo ""
    echo -e "${GREEN}작업 타입:${NC}"
    echo "  basic          - 단일 노드 기본 해석 (1 node, 16 cores)"
    echo "  mpi            - 다중 노드 MPI 병렬 (4 nodes, 64 cores)"
    echo "  gpu            - GPU 가속 해석 (1 node, 2 GPUs)"
    echo "  restart        - 이전 해석에서 재시작"
    echo "  custom         - 사용자 정의 설정"
    echo ""
    echo -e "${GREEN}옵션:${NC}"
    echo "  -n, --nodes N          노드 수 지정"
    echo "  -c, --cores N          코어 수 지정"
    echo "  -p, --partition NAME   파티션 지정"
    echo "  -q, --qos NAME         QoS 지정"
    echo "  -t, --time HH:MM:SS    최대 실행 시간"
    echo "  -m, --mem SIZE         메모리 크기 (GB)"
    echo "  -g, --gpus N           GPU 수 (기본: 2)"
    echo "  -r, --restart-from ID  재시작할 Job ID"
    echo "  -j, --job-name NAME    작업 이름"
    echo "  -l, --list             작업 타입 목록 표시"
    echo "  -h, --help             도움말 표시"
    echo ""
    echo -e "${GREEN}사용 예시:${NC}"
    echo "  $0 basic input.k"
    echo "  $0 mpi large_model.k"
    echo "  $0 gpu implicit.k"
    echo "  $0 restart input.k -r 12345"
    echo "  $0 custom input.k -c 32 -p normal -q normal_qos"
    echo ""
}

show_job_types() {
    echo -e "${BLUE}================================================================"
    echo "사용 가능한 LS-DYNA 작업 타입"
    echo "================================================================${NC}"
    echo ""
    echo -e "${GREEN}1. basic${NC} - 기본 단일 노드 해석"
    echo "   Nodes: 1, Cores: 16, Memory: 32GB, Time: 24h"
    echo "   적합: 소규모 모델, 빠른 테스트"
    echo ""
    echo -e "${GREEN}2. mpi${NC} - MPI 다중 노드 병렬"
    echo "   Nodes: 4, Cores: 64, Memory: 128GB, Time: 48h"
    echo "   적합: 대규모 모델, 명시적 해석"
    echo ""
    echo -e "${GREEN}3. gpu${NC} - GPU 가속"
    echo "   CPUs: 8, GPUs: 2, Memory: 64GB, Time: 72h"
    echo "   적합: 암시적 해석, 비선형 해석"
    echo ""
    echo -e "${GREEN}4. restart${NC} - 재시작"
    echo "   Nodes: 1, Cores: 32, Memory: 64GB, Time: 48h"
    echo "   적합: 장시간 해석 재개"
    echo ""
    echo -e "${GREEN}5. custom${NC} - 사용자 정의"
    echo "   모든 옵션 사용자 지정 가능"
    echo ""
}

# 기본값
JOB_TYPE=""
INPUT_K_FILE=""
NODES=""
CORES=""
PARTITION=""
QOS=""
TIME=""
MEMORY=""
GPUS="2"
RESTART_FROM=""
JOB_NAME=""

# 인자 파싱
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) show_usage; exit 0 ;;
        -l|--list) show_job_types; exit 0 ;;
        -n|--nodes) NODES="$2"; shift 2 ;;
        -c|--cores) CORES="$2"; shift 2 ;;
        -p|--partition) PARTITION="$2"; shift 2 ;;
        -q|--qos) QOS="$2"; shift 2 ;;
        -t|--time) TIME="$2"; shift 2 ;;
        -m|--mem) MEMORY="$2"; shift 2 ;;
        -g|--gpus) GPUS="$2"; shift 2 ;;
        -r|--restart-from) RESTART_FROM="$2"; shift 2 ;;
        -j|--job-name) JOB_NAME="$2"; shift 2 ;;
        basic|mpi|gpu|restart|custom) JOB_TYPE="$1"; shift ;;
        *.k) INPUT_K_FILE="$1"; shift ;;
        *) echo -e "${RED}ERROR: Unknown option: $1${NC}"; show_usage; exit 1 ;;
    esac
done

# 입력 검증
if [ -z "$JOB_TYPE" ] || [ -z "$INPUT_K_FILE" ]; then
    echo -e "${RED}ERROR: 작업 타입과 K 파일을 지정하세요.${NC}"
    show_usage
    exit 1
fi

if [ ! -f "$INPUT_K_FILE" ]; then
    echo -e "${RED}ERROR: K 파일을 찾을 수 없습니다: $INPUT_K_FILE${NC}"
    exit 1
fi

if [ "$JOB_TYPE" = "restart" ] && [ -z "$RESTART_FROM" ]; then
    echo -e "${RED}ERROR: restart는 --restart-from 옵션이 필요합니다.${NC}"
    exit 1
fi

# 작업 제출
echo -e "${BLUE}================================================================"
echo "LS-DYNA R16 작업 제출"
echo "================================================================${NC}"
echo ""
echo "타입:    $JOB_TYPE"
echo "K파일:   $INPUT_K_FILE"
echo ""

case $JOB_TYPE in
    basic)
        echo "노드: 1, 코어: 16, 메모리: 32GB, 시간: 24h"
        sbatch ${SCRIPT_DIR}/submit_lsdyna_basic.sh "$INPUT_K_FILE"
        ;;
    mpi)
        echo "노드: 4, 코어: 64, 메모리: 128GB, 시간: 48h"
        sbatch ${SCRIPT_DIR}/submit_lsdyna_mpi.sh "$INPUT_K_FILE"
        ;;
    gpu)
        echo "GPU: $GPUS, CPU: 8, 메모리: 64GB, 시간: 72h"
        sbatch ${SCRIPT_DIR}/submit_lsdyna_gpu.sh "$INPUT_K_FILE"
        ;;
    restart)
        echo "재시작 from: Job $RESTART_FROM"
        sbatch ${SCRIPT_DIR}/submit_lsdyna_restart.sh "$INPUT_K_FILE" "$RESTART_FROM"
        ;;
    custom)
        if [ -z "$NODES" ] || [ -z "$CORES" ] || [ -z "$PARTITION" ] || [ -z "$QOS" ]; then
            echo -e "${RED}ERROR: custom은 -n, -c, -p, -q 옵션 필요${NC}"
            exit 1
        fi
        
        echo "노드: $NODES, 코어: $CORES, 파티션: $PARTITION"
        
        # 임시 custom 스크립트 생성
        CUSTOM_SCRIPT="/tmp/lsdyna_custom_$$.sh"
        cat > $CUSTOM_SCRIPT << 'EOFSCRIPT'
#!/bin/bash
#SBATCH --job-name=JOBNAME
#SBATCH --partition=PARTITION
#SBATCH --qos=QOS
#SBATCH --nodes=NODES
#SBATCH --ntasks=CORES
#SBATCH --cpus-per-task=1
#SBATCH --mem=MEMORYGB
#SBATCH --time=TIME
#SBATCH --output=lsdyna_custom_%j.out
#SBATCH --error=lsdyna_custom_%j.err

export OMP_NUM_THREADS=1
export OMP_PROC_BIND=true
export OMP_PLACES=cores
export LSTC_LICENSE=network
export LSTC_LICENSE_SERVER=10.0.0.1
export LD_LIBRARY_PATH=/opt/lsdyna/lib:$LD_LIBRARY_PATH

SLURM_USER=$(whoami)
JOB_ID=${SLURM_JOB_ID}
INPUT_K_FILE="KFILE"
INPUT_K_BASENAME=$(basename $INPUT_K_FILE)

SCRATCH_DIR="/scratch/${SLURM_USER}/${JOB_ID}"
RESULT_DIR="/Data/home/${SLURM_USER}/${JOB_ID}"

echo "LS-DYNA Custom Job Started: ${JOB_ID}"
mkdir -p ${SCRATCH_DIR}
cp ${INPUT_K_FILE} ${SCRATCH_DIR}/
for kfile in *.k; do
    [ -f "$kfile" ] && cp "$kfile" ${SCRATCH_DIR}/
done

cd ${SCRATCH_DIR}

numactl --interleave=all \
    LSDynaR16 \
    i=${INPUT_K_BASENAME} \
    ncpu=CORES \
    memory=auto \
    memory2=auto

LSDYNA_EXIT_CODE=$?

mkdir -p ${RESULT_DIR}
mv ${SCRATCH_DIR}/* ${RESULT_DIR}/
rm -rf ${SCRATCH_DIR}

echo "Job ${JOB_ID} completed: ${LSDYNA_EXIT_CODE}"
exit ${LSDYNA_EXIT_CODE}
EOFSCRIPT

        # 변수 치환
        sed -i "s|JOBNAME|${JOB_NAME:-lsdyna_custom}|g" $CUSTOM_SCRIPT
        sed -i "s|PARTITION|${PARTITION}|g" $CUSTOM_SCRIPT
        sed -i "s|QOS|${QOS}|g" $CUSTOM_SCRIPT
        sed -i "s|NODES|${NODES}|g" $CUSTOM_SCRIPT
        sed -i "s|CORES|${CORES}|g" $CUSTOM_SCRIPT
        sed -i "s|MEMORY|${MEMORY:-64}|g" $CUSTOM_SCRIPT
        sed -i "s|TIME|${TIME:-24:00:00}|g" $CUSTOM_SCRIPT
        sed -i "s|KFILE|${INPUT_K_FILE}|g" $CUSTOM_SCRIPT
        
        chmod +x $CUSTOM_SCRIPT
        sbatch $CUSTOM_SCRIPT
        rm -f $CUSTOM_SCRIPT
        ;;
esac

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ 작업이 성공적으로 제출되었습니다!${NC}"
    echo ""
    echo "작업 확인: squeue -u \$(whoami)"
    echo "작업 취소: scancel <job_id>"
else
    echo -e "${RED}❌ 작업 제출 실패${NC}"
    exit 1
fi
