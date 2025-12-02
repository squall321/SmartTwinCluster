#!/bin/bash
################################################################################
# LS-DYNA R16 Job Submit Script (Basic - Single K-file)
# Type: basic_single_k
# Description: 단일 K 파일을 사용하는 기본 LS-DYNA 해석
################################################################################

#SBATCH --job-name=lsdyna_basic
#SBATCH --partition=normal           # 파티션 선택
#SBATCH --qos=normal_qos             # QoS 선택
#SBATCH --nodes=1                    # 노드 수
#SBATCH --ntasks=16                  # 총 태스크 수 (코어 수)
#SBATCH --cpus-per-task=1            # 태스크당 CPU
#SBATCH --mem=32GB                   # 메모리
#SBATCH --time=24:00:00              # 최대 실행 시간
#SBATCH --output=lsdyna_%j.out       # 표준 출력
#SBATCH --error=lsdyna_%j.err        # 표준 에러

################################################################################
# NUMA 최적화 설정
################################################################################

# CPU 바인딩 설정 (NUMA 최적화)
export OMP_NUM_THREADS=1
export OMP_PROC_BIND=true
export OMP_PLACES=cores

# LS-DYNA 환경변수
export LSTC_LICENSE=network
export LSTC_LICENSE_SERVER=10.0.0.1  # 라이선스 서버 IP 수정 필요
export LD_LIBRARY_PATH=/opt/lsdyna/lib:$LD_LIBRARY_PATH

################################################################################
# 디렉토리 설정
################################################################################

# 변수 설정
SLURM_USER=$(whoami)
JOB_ID=${SLURM_JOB_ID}
INPUT_K_FILE=$1  # 첫 번째 인자: K 파일 경로

# 작업 디렉토리
SCRATCH_DIR="/scratch/${SLURM_USER}/${JOB_ID}"
RESULT_DIR="/Data/home/${SLURM_USER}/${JOB_ID}"
SUBMIT_DIR=$(pwd)

# 입력 파일 체크
if [ -z "$INPUT_K_FILE" ]; then
    echo "ERROR: K 파일이 지정되지 않았습니다."
    echo "Usage: sbatch submit_lsdyna_basic.sh <input.k>"
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
echo "LS-DYNA R16 Job Started"
echo "================================================================"
echo "Job ID:          ${JOB_ID}"
echo "User:            ${SLURM_USER}"
echo "Partition:       ${SLURM_JOB_PARTITION}"
echo "QoS:             ${SLURM_JOB_QOS}"
echo "Nodes:           ${SLURM_JOB_NUM_NODES}"
echo "Cores:           ${SLURM_NTASKS}"
echo "Memory:          ${SLURM_MEM_PER_NODE}"
echo "Input K-file:    ${INPUT_K_FILE}"
echo "Scratch Dir:     ${SCRATCH_DIR}"
echo "Result Dir:      ${RESULT_DIR}"
echo "Submit Dir:      ${SUBMIT_DIR}"
echo "Start Time:      $(date)"
echo "================================================================"
echo ""

################################################################################
# Scratch 디렉토리 준비
################################################################################

echo ">> Preparing scratch directory..."
mkdir -p ${SCRATCH_DIR}

# 입력 파일 복사
echo ">> Copying input files to scratch..."
cp ${INPUT_K_FILE} ${SCRATCH_DIR}/
INPUT_K_BASENAME=$(basename ${INPUT_K_FILE})

# 추가 입력 파일이 있으면 복사 (include 파일 등)
# 현재 디렉토리의 모든 .k 파일 복사
for kfile in *.k; do
    if [ -f "$kfile" ] && [ "$kfile" != "$INPUT_K_BASENAME" ]; then
        echo "   Copying: $kfile"
        cp "$kfile" ${SCRATCH_DIR}/
    fi
done

# 작업 디렉토리로 이동
cd ${SCRATCH_DIR}
echo ">> Working directory: $(pwd)"
echo ""

################################################################################
# NUMA 정보 출력
################################################################################

echo ">> NUMA Configuration:"
numactl --hardware | grep -E "available|node.*cpus"
echo ""

################################################################################
# LS-DYNA 실행
################################################################################

echo ">> Starting LS-DYNA R16 calculation..."
echo ">> Command: LSDynaR16 i=${INPUT_K_BASENAME} ncpu=${SLURM_NTASKS}"
echo ""

# NUMA 최적화를 사용한 LS-DYNA 실행
# numactl로 메모리 정책 설정
numactl --interleave=all \
    LSDynaR16 \
    i=${INPUT_K_BASENAME} \
    ncpu=${SLURM_NTASKS} \
    memory=auto \
    memory2=auto

LSDYNA_EXIT_CODE=$?

echo ""
echo ">> LS-DYNA finished with exit code: ${LSDYNA_EXIT_CODE}"
echo ">> End Time: $(date)"
echo ""

################################################################################
# 결과 파일 정리 및 이동
################################################################################

echo ">> Collecting results..."

# 결과 디렉토리 생성
mkdir -p ${RESULT_DIR}

# 모든 결과 파일을 Result 디렉토리로 이동
echo ">> Moving results to: ${RESULT_DIR}"
mv ${SCRATCH_DIR}/* ${RESULT_DIR}/

# Scratch 디렉토리 삭제
echo ">> Cleaning up scratch directory..."
rm -rf ${SCRATCH_DIR}

echo ">> Results saved to: ${RESULT_DIR}"
echo ""

################################################################################
# 작업 완료 로그
################################################################################

echo "================================================================"
echo "LS-DYNA R16 Job Completed"
echo "================================================================"
echo "Job ID:          ${JOB_ID}"
echo "Exit Code:       ${LSDYNA_EXIT_CODE}"
echo "Result Location: ${RESULT_DIR}"
echo "Completion Time: $(date)"
echo "================================================================"

# 이메일 알림 (선택사항)
# echo "LS-DYNA job ${JOB_ID} completed" | mail -s "Job ${JOB_ID} Done" user@example.com

exit ${LSDYNA_EXIT_CODE}
