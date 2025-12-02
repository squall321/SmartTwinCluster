#!/bin/bash
################################################################################
# MPI + Apptainer Job Submit Script
# 여러 노드에서 Apptainer 컨테이너로 감싼 MPI 프로그램 실행
################################################################################

#SBATCH --job-name=mpi_apptainer
#SBATCH --partition=normal           # 파티션 선택
#SBATCH --nodes=2                    # 노드 수
#SBATCH --ntasks=4                   # 총 태스크 수
#SBATCH --ntasks-per-node=2          # 노드당 태스크 수
#SBATCH --cpus-per-task=1            # 태스크당 CPU
#SBATCH --mem-per-cpu=2GB            # CPU당 메모리
#SBATCH --time=01:00:00              # 최대 실행 시간
#SBATCH --output=mpi_apptainer_%j.out   # 표준 출력
#SBATCH --error=mpi_apptainer_%j.err    # 표준 에러

################################################################################
# 사용법:
# sbatch submit_mpi_apptainer.sh <image_name.sif> <program> [args...]
#
# 예시:
# sbatch submit_mpi_apptainer.sh myapp.sif /usr/bin/myprogram --input data.txt
# sbatch submit_mpi_apptainer.sh ubuntu.sif /bin/bash -c "hostname && date"
################################################################################

################################################################################
# OpenMPI 및 환경 설정
################################################################################

# OpenMP 설정
export OMP_NUM_THREADS=1
export OMP_PROC_BIND=true
export OMP_PLACES=cores

# MPI 설정
export OMPI_MCA_btl=^openib
export OMPI_MCA_pml=ob1

# Apptainer 경로 설정
SCRATCH_IMAGE_DIR="/scratch/apptainer/images"
CENTRAL_IMAGE_DIR="/share/apptainer/images"

################################################################################
# 인자 확인
################################################################################

if [ $# -lt 2 ]; then
    echo "ERROR: 인자가 부족합니다."
    echo "사용법: sbatch $0 <image_name.sif> <program> [args...]"
    echo ""
    echo "예시:"
    echo "  sbatch $0 myapp.sif /usr/bin/myprogram --input data.txt"
    echo "  sbatch $0 ubuntu.sif /bin/bash -c 'hostname && date'"
    exit 1
fi

IMAGE_NAME=$1
shift
PROGRAM=$@

################################################################################
# 이미지 경로 확인
################################################################################

# 1순위: Scratch의 로컬 이미지 (빠름)
if [ -f "${SCRATCH_IMAGE_DIR}/${IMAGE_NAME}" ]; then
    CONTAINER_IMAGE="${SCRATCH_IMAGE_DIR}/${IMAGE_NAME}"
    echo "✅ 로컬 이미지 사용: ${CONTAINER_IMAGE}"
# 2순위: 중앙 저장소의 이미지 (느림, 네트워크 부담)
elif [ -f "${CENTRAL_IMAGE_DIR}/${IMAGE_NAME}" ]; then
    CONTAINER_IMAGE="${CENTRAL_IMAGE_DIR}/${IMAGE_NAME}"
    echo "⚠️  중앙 저장소 이미지 사용: ${CONTAINER_IMAGE}"
    echo "💡 성능 향상을 위해 이미지를 로컬로 복사하는 것을 권장합니다:"
    echo "   python3 sync_apptainer_images.py"
else
    echo "❌ ERROR: 이미지를 찾을 수 없습니다: ${IMAGE_NAME}"
    echo "사용 가능한 이미지:"
    echo "--- Scratch (로컬) ---"
    ls -lh ${SCRATCH_IMAGE_DIR}/*.sif 2>/dev/null || echo "  (없음)"
    echo "--- Central (중앙) ---"
    ls -lh ${CENTRAL_IMAGE_DIR}/*.sif 2>/dev/null || echo "  (없음)"
    exit 1
fi

################################################################################
# 작업 시작 로그
################################################################################

echo "================================================================"
echo "MPI + Apptainer Job Started"
echo "================================================================"
echo "Job ID:          ${SLURM_JOB_ID}"
echo "User:            $(whoami)"
echo "Partition:       ${SLURM_JOB_PARTITION}"
echo "Nodes:           ${SLURM_JOB_NUM_NODES}"
echo "Node list:       ${SLURM_JOB_NODELIST}"
echo "Tasks:           ${SLURM_NTASKS}"
echo "Tasks per node:  ${SLURM_NTASKS_PER_NODE}"
echo "Container:       ${CONTAINER_IMAGE}"
echo "Program:         ${PROGRAM}"
echo "Start Time:      $(date)"
echo "================================================================"
echo ""

################################################################################
# MPI + Apptainer 실행
################################################################################

echo ">> Starting MPI + Apptainer execution..."
echo ">> MPI Command: mpirun -np ${SLURM_NTASKS}"
echo ""

# MPI를 사용한 Apptainer 실행
mpirun -np ${SLURM_NTASKS} \
    --bind-to core \
    --map-by socket:PE=1 \
    apptainer exec \
    --bind /home:/home \
    --bind /scratch:/scratch \
    --bind /tmp:/tmp \
    ${CONTAINER_IMAGE} \
    ${PROGRAM}

EXIT_CODE=$?

echo ""
echo ">> Execution finished with exit code: ${EXIT_CODE}"
echo ">> End Time: $(date)"
echo ""

################################################################################
# 작업 완료 로그
################################################################################

echo "================================================================"
echo "MPI + Apptainer Job Completed"
echo "================================================================"
echo "Job ID:          ${SLURM_JOB_ID}"
echo "Nodes Used:      ${SLURM_JOB_NUM_NODES}"
echo "Total Tasks:     ${SLURM_NTASKS}"
echo "Exit Code:       ${EXIT_CODE}"
echo "Completion Time: $(date)"
echo "================================================================"

exit ${EXIT_CODE}
