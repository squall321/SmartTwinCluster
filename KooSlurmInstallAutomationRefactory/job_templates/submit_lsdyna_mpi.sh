#!/bin/bash
################################################################################
# LS-DYNA R16 Job Submit Script (Multi-Node MPI)
# Type: mpi_multi_node
# Description: 여러 노드를 사용하는 MPI 병렬 LS-DYNA 해석
################################################################################

#SBATCH --job-name=lsdyna_mpi
#SBATCH --partition=normal           # 파티션 선택
#SBATCH --qos=normal_qos             # QoS 선택
#SBATCH --nodes=4                    # 노드 수 (다중 노드)
#SBATCH --ntasks=64                  # 총 태스크 수 (노드당 16코어 × 4노드)
#SBATCH --ntasks-per-node=16         # 노드당 태스크 수
#SBATCH --cpus-per-task=1            # 태스크당 CPU
#SBATCH --mem-per-cpu=2GB            # CPU당 메모리
#SBATCH --time=48:00:00              # 최대 실행 시간
#SBATCH --output=lsdyna_mpi_%j.out   # 표준 출력
#SBATCH --error=lsdyna_mpi_%j.err    # 표준 에러

################################################################################
# NUMA 및 MPI 최적화 설정
################################################################################

# OpenMP 설정 (하이브리드 MPI+OpenMP)
export OMP_NUM_THREADS=1
export OMP_PROC_BIND=true
export OMP_PLACES=cores

# MPI 설정
export OMPI_MCA_btl=^openib          # InfiniBand 사용 시 주석 해제
export OMPI_MCA_pml=ob1

# LS-DYNA 환경변수
export LSTC_LICENSE=network
export LSTC_LICENSE_SERVER=10.0.0.1  # 라이선스 서버 IP
export LD_LIBRARY_PATH=/opt/lsdyna/lib:$LD_LIBRARY_PATH

################################################################################
# 디렉토리 설정
################################################################################

SLURM_USER=$(whoami)
JOB_ID=${SLURM_JOB_ID}
INPUT_K_FILE=$1

SCRATCH_DIR="/scratch/${SLURM_USER}/${JOB_ID}"
RESULT_DIR="/Data/home/${SLURM_USER}/${JOB_ID}"
SUBMIT_DIR=$(pwd)

# 입력 파일 체크
if [ -z "$INPUT_K_FILE" ]; then
    echo "ERROR: K 파일이 지정되지 않았습니다."
    echo "Usage: sbatch submit_lsdyna_mpi.sh <input.k>"
    exit 1
fi

if [ ! -f "$INPUT_K_FILE" ]; then
    echo "ERROR: K 파일을 찾을 수 없습니다: $INPUT_K_FILE"
    exit 1
fi

################################################################################
# 작업 시작 로그
################################################################################

echo "================================================================"
echo "LS-DYNA R16 MPI Job Started"
echo "================================================================"
echo "Job ID:          ${JOB_ID}"
echo "User:            ${SLURM_USER}"
echo "Partition:       ${SLURM_JOB_PARTITION}"
echo "QoS:             ${SLURM_JOB_QOS}"
echo "Nodes:           ${SLURM_JOB_NUM_NODES}"
echo "Tasks:           ${SLURM_NTASKS}"
echo "Tasks per node:  ${SLURM_NTASKS_PER_NODE}"
echo "Total Cores:     ${SLURM_NTASKS}"
echo "Input K-file:    ${INPUT_K_FILE}"
echo "Nodelist:        ${SLURM_JOB_NODELIST}"
echo "Start Time:      $(date)"
echo "================================================================"
echo ""

################################################################################
# Scratch 디렉토리 준비
################################################################################

echo ">> Preparing scratch directory..."
mkdir -p ${SCRATCH_DIR}

echo ">> Copying input files..."
cp ${INPUT_K_FILE} ${SCRATCH_DIR}/
INPUT_K_BASENAME=$(basename ${INPUT_K_FILE})

# 모든 .k 파일 복사
for kfile in *.k; do
    if [ -f "$kfile" ] && [ "$kfile" != "$INPUT_K_BASENAME" ]; then
        cp "$kfile" ${SCRATCH_DIR}/
    fi
done

cd ${SCRATCH_DIR}
echo ">> Working directory: $(pwd)"
echo ""

################################################################################
# MPI 노드 정보 출력
################################################################################

echo ">> MPI Configuration:"
echo "   Number of nodes: ${SLURM_JOB_NUM_NODES}"
echo "   Node list: ${SLURM_JOB_NODELIST}"
echo "   Tasks per node: ${SLURM_NTASKS_PER_NODE}"
echo ""

echo ">> NUMA Configuration on master node:"
numactl --hardware | grep -E "available|node.*cpus"
echo ""

################################################################################
# LS-DYNA MPI 실행
################################################################################

echo ">> Starting LS-DYNA R16 MPI calculation..."
echo ">> MPI Command: mpirun -np ${SLURM_NTASKS}"
echo ""

# MPI를 사용한 LS-DYNA 실행
# NUMA 인터리브 메모리 정책 사용
mpirun -np ${SLURM_NTASKS} \
    --bind-to core \
    --map-by socket:PE=1 \
    numactl --interleave=all \
    LSDynaR16 \
    i=${INPUT_K_BASENAME} \
    ncpu=${SLURM_NTASKS} \
    memory=auto \
    memory2=auto

LSDYNA_EXIT_CODE=$?

echo ""
echo ">> LS-DYNA MPI finished with exit code: ${LSDYNA_EXIT_CODE}"
echo ">> End Time: $(date)"
echo ""

################################################################################
# 결과 수집 및 이동
################################################################################

echo ">> Collecting results..."
mkdir -p ${RESULT_DIR}

echo ">> Moving results to: ${RESULT_DIR}"
mv ${SCRATCH_DIR}/* ${RESULT_DIR}/

echo ">> Cleaning up scratch directory..."
rm -rf ${SCRATCH_DIR}

echo ">> Results saved to: ${RESULT_DIR}"
echo ""

################################################################################
# 작업 완료 로그
################################################################################

echo "================================================================"
echo "LS-DYNA R16 MPI Job Completed"
echo "================================================================"
echo "Job ID:          ${JOB_ID}"
echo "Nodes Used:      ${SLURM_JOB_NUM_NODES}"
echo "Total Cores:     ${SLURM_NTASKS}"
echo "Exit Code:       ${LSDYNA_EXIT_CODE}"
echo "Result Location: ${RESULT_DIR}"
echo "Completion Time: $(date)"
echo "================================================================"

exit ${LSDYNA_EXIT_CODE}
