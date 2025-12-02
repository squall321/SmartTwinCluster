#!/bin/bash
################################################################################
# LS-DYNA R16 Job Submit Script (Restart Job)
# Type: restart
# Description: 이전 해석 결과에서 재시작하는 LS-DYNA 해석
################################################################################

#SBATCH --job-name=lsdyna_restart
#SBATCH --partition=normal           
#SBATCH --qos=normal_qos             
#SBATCH --nodes=1                    
#SBATCH --ntasks=32                  
#SBATCH --cpus-per-task=1            
#SBATCH --mem=64GB                   
#SBATCH --time=48:00:00              
#SBATCH --output=lsdyna_restart_%j.out
#SBATCH --error=lsdyna_restart_%j.err

################################################################################
# NUMA 최적화 설정
################################################################################

export OMP_NUM_THREADS=1
export OMP_PROC_BIND=true
export OMP_PLACES=cores

export LSTC_LICENSE=network
export LSTC_LICENSE_SERVER=10.0.0.1
export LD_LIBRARY_PATH=/opt/lsdyna/lib:$LD_LIBRARY_PATH

################################################################################
# 디렉토리 및 파일 설정
################################################################################

SLURM_USER=$(whoami)
JOB_ID=${SLURM_JOB_ID}
INPUT_K_FILE=$1
PREVIOUS_JOB_ID=$2  # 이전 Job ID (필수)

SCRATCH_DIR="/scratch/${SLURM_USER}/${JOB_ID}"
RESULT_DIR="/Data/home/${SLURM_USER}/${JOB_ID}"
PREVIOUS_RESULT_DIR="/Data/home/${SLURM_USER}/${PREVIOUS_JOB_ID}"
SUBMIT_DIR=$(pwd)

# 입력 파일 및 이전 작업 체크
if [ -z "$INPUT_K_FILE" ]; then
    echo "ERROR: K 파일이 지정되지 않았습니다."
    echo "Usage: sbatch submit_lsdyna_restart.sh <input.k> <previous_job_id>"
    exit 1
fi

if [ -z "$PREVIOUS_JOB_ID" ]; then
    echo "ERROR: 이전 Job ID가 지정되지 않았습니다."
    echo "Usage: sbatch submit_lsdyna_restart.sh <input.k> <previous_job_id>"
    exit 1
fi

if [ ! -f "$INPUT_K_FILE" ]; then
    echo "ERROR: K 파일을 찾을 수 없습니다: $INPUT_K_FILE"
    exit 1
fi

if [ ! -d "$PREVIOUS_RESULT_DIR" ]; then
    echo "ERROR: 이전 작업 결과 디렉토리를 찾을 수 없습니다: $PREVIOUS_RESULT_DIR"
    exit 1
fi

################################################################################
# 작업 시작 로그
################################################################################

echo "================================================================"
echo "LS-DYNA R16 Restart Job Started"
echo "================================================================"
echo "Job ID:          ${JOB_ID}"
echo "Previous Job ID: ${PREVIOUS_JOB_ID}"
echo "User:            ${SLURM_USER}"
echo "Cores:           ${SLURM_NTASKS}"
echo "Input K-file:    ${INPUT_K_FILE}"
echo "Previous Result: ${PREVIOUS_RESULT_DIR}"
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
    if [ -f "$kfile" ]; then
        cp "$kfile" ${SCRATCH_DIR}/
    fi
done

# 이전 작업의 restart 파일 복사
echo ">> Copying restart files from previous job..."
if [ -f "${PREVIOUS_RESULT_DIR}/d3dump" ]; then
    cp ${PREVIOUS_RESULT_DIR}/d3dump ${SCRATCH_DIR}/
    echo "   Copied: d3dump"
else
    echo "   WARNING: d3dump not found in previous result directory"
fi

# d3dump01, d3dump02 등의 파일도 복사
for dumpfile in ${PREVIOUS_RESULT_DIR}/d3dump*; do
    if [ -f "$dumpfile" ]; then
        cp "$dumpfile" ${SCRATCH_DIR}/
        echo "   Copied: $(basename $dumpfile)"
    fi
done

cd ${SCRATCH_DIR}
echo ">> Working directory: $(pwd)"
echo ""

# Restart 파일 확인
echo ">> Restart files in scratch directory:"
ls -lh d3dump*
echo ""

################################################################################
# LS-DYNA Restart 실행
################################################################################

echo ">> Starting LS-DYNA R16 restart calculation..."
echo ">> Command: LSDynaR16 i=${INPUT_K_BASENAME} r=d3dump ncpu=${SLURM_NTASKS}"
echo ""

# Restart 옵션으로 LS-DYNA 실행
numactl --interleave=all \
    LSDynaR16 \
    i=${INPUT_K_BASENAME} \
    r=d3dump \
    ncpu=${SLURM_NTASKS} \
    memory=auto \
    memory2=auto

LSDYNA_EXIT_CODE=$?

echo ""
echo ">> LS-DYNA restart finished with exit code: ${LSDYNA_EXIT_CODE}"
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
echo "LS-DYNA R16 Restart Job Completed"
echo "================================================================"
echo "Job ID:          ${JOB_ID}"
echo "Previous Job ID: ${PREVIOUS_JOB_ID}"
echo "Exit Code:       ${LSDYNA_EXIT_CODE}"
echo "Result Location: ${RESULT_DIR}"
echo "Completion Time: $(date)"
echo "================================================================"

exit ${LSDYNA_EXIT_CODE}
