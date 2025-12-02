#!/bin/bash
################################################################################
# LS-DYNA R16 Job Submit Script (GPU Accelerated)
# Type: gpu_accelerated
# Description: GPU를 사용하는 LS-DYNA 해석 (암시적 해석에 유용)
################################################################################

#SBATCH --job-name=lsdyna_gpu
#SBATCH --partition=gpu              # GPU 파티션
#SBATCH --qos=gpu_qos                # GPU QoS
#SBATCH --nodes=1                    # 노드 수
#SBATCH --ntasks=8                   # CPU 태스크 수
#SBATCH --cpus-per-task=2            # 태스크당 CPU
#SBATCH --gres=gpu:2                 # GPU 수
#SBATCH --mem=64GB                   # 메모리
#SBATCH --time=72:00:00              # 최대 실행 시간
#SBATCH --output=lsdyna_gpu_%j.out   # 표준 출력
#SBATCH --error=lsdyna_gpu_%j.err    # 표준 에러

################################################################################
# GPU 및 NUMA 최적화 설정
################################################################################

# CUDA 환경변수
export CUDA_VISIBLE_DEVICES=0,1      # GPU 장치 선택
export CUDA_DEVICE_ORDER=PCI_BUS_ID

# OpenMP 설정
export OMP_NUM_THREADS=2
export OMP_PROC_BIND=true
export OMP_PLACES=cores

# LS-DYNA GPU 환경변수
export LSTC_LICENSE=network
export LSTC_LICENSE_SERVER=10.0.0.1
export LD_LIBRARY_PATH=/opt/lsdyna/lib:/usr/local/cuda/lib64:$LD_LIBRARY_PATH

################################################################################
# 디렉토리 설정
################################################################################

SLURM_USER=$(whoami)
JOB_ID=${SLURM_JOB_ID}
INPUT_K_FILE=$1

SCRATCH_DIR="/scratch/${SLURM_USER}/${JOB_ID}"
RESULT_DIR="/Data/home/${SLURM_USER}/${JOB_ID}"
SUBMIT_DIR=$(pwd)

if [ -z "$INPUT_K_FILE" ]; then
    echo "ERROR: K 파일이 지정되지 않았습니다."
    echo "Usage: sbatch submit_lsdyna_gpu.sh <input.k>"
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
echo "LS-DYNA R16 GPU Job Started"
echo "================================================================"
echo "Job ID:          ${JOB_ID}"
echo "User:            ${SLURM_USER}"
echo "Partition:       ${SLURM_JOB_PARTITION}"
echo "QoS:             ${SLURM_JOB_QOS}"
echo "CPUs:            ${SLURM_NTASKS}"
echo "GPUs:            ${SLURM_GPUS}"
echo "GPU Devices:     ${CUDA_VISIBLE_DEVICES}"
echo "Input K-file:    ${INPUT_K_FILE}"
echo "Start Time:      $(date)"
echo "================================================================"
echo ""

################################################################################
# GPU 정보 출력
################################################################################

echo ">> GPU Information:"
nvidia-smi --query-gpu=index,name,memory.total,compute_cap --format=csv,noheader
echo ""

echo ">> GPU Utilization before start:"
nvidia-smi --query-gpu=utilization.gpu,utilization.memory --format=csv,noheader
echo ""

################################################################################
# Scratch 디렉토리 준비
################################################################################

echo ">> Preparing scratch directory..."
mkdir -p ${SCRATCH_DIR}

echo ">> Copying input files..."
cp ${INPUT_K_FILE} ${SCRATCH_DIR}/
INPUT_K_BASENAME=$(basename ${INPUT_K_FILE})

for kfile in *.k; do
    if [ -f "$kfile" ] && [ "$kfile" != "$INPUT_K_BASENAME" ]; then
        cp "$kfile" ${SCRATCH_DIR}/
    fi
done

cd ${SCRATCH_DIR}
echo ">> Working directory: $(pwd)"
echo ""

################################################################################
# LS-DYNA GPU 실행
################################################################################

echo ">> Starting LS-DYNA R16 GPU calculation..."
echo ">> GPUs: ${SLURM_GPUS}, CPUs: ${SLURM_NTASKS}"
echo ""

# GPU 가속을 사용한 LS-DYNA 실행
# GPU는 주로 암시적 해석(Implicit)에 효과적
numactl --interleave=all \
    LSDynaR16 \
    i=${INPUT_K_BASENAME} \
    ncpu=${SLURM_NTASKS} \
    gpu=1 \
    gpun=2 \
    memory=auto \
    memory2=auto

LSDYNA_EXIT_CODE=$?

echo ""
echo ">> LS-DYNA GPU finished with exit code: ${LSDYNA_EXIT_CODE}"
echo ">> End Time: $(date)"
echo ""

echo ">> Final GPU Utilization:"
nvidia-smi --query-gpu=utilization.gpu,utilization.memory --format=csv,noheader
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
echo "LS-DYNA R16 GPU Job Completed"
echo "================================================================"
echo "Job ID:          ${JOB_ID}"
echo "GPUs Used:       ${SLURM_GPUS}"
echo "Exit Code:       ${LSDYNA_EXIT_CODE}"
echo "Result Location: ${RESULT_DIR}"
echo "Completion Time: $(date)"
echo "================================================================"

exit ${LSDYNA_EXIT_CODE}
