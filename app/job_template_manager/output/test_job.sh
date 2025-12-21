#!/bin/bash

# =============================================================================
# SBATCH Configuration
# =============================================================================

#SBATCH --job-name=test_pytorch_training
#SBATCH --partition=compute
#SBATCH --nodes=1
#SBATCH --ntasks=4
#SBATCH --mem=32G
#SBATCH --time=02:00:00
#SBATCH --output=/shared/logs/%j.out
#SBATCH --error=/shared/logs/%j.err

# =============================================================================
# Environment Variables
# =============================================================================

# --- Slurm Configuration Variables ---
export JOB_PARTITION="compute"
export JOB_NODES=1
export JOB_NTASKS=4
export JOB_CPUS_PER_TASK=1
export JOB_MEMORY="32G"
export JOB_TIME="02:00:00"

# --- Apptainer Image ---
export APPTAINER_IMAGE="/opt/apptainers/KooSimulationPython313.sif"

# --- Work Directories ---
export SLURM_SUBMIT_DIR=/shared/jobs/$SLURM_JOB_ID
export WORK_DIR="$SLURM_SUBMIT_DIR"
export RESULT_DIR="$WORK_DIR/results"

# --- Apptainer Environment Variables ---
export PYTHONPATH="/app"
export OMP_NUM_THREADS="8"

# --- Uploaded File Paths ---
export FILE_TRAINING_SCRIPT="$SLURM_SUBMIT_DIR/input/train.py"
export FILE_DATASET="$SLURM_SUBMIT_DIR/input/dataset.tar.gz"

# =============================================================================

# =============================================================================
# Directory Setup
# =============================================================================

# Create directories
mkdir -p $SLURM_SUBMIT_DIR/input
mkdir -p $SLURM_SUBMIT_DIR/work
mkdir -p $SLURM_SUBMIT_DIR/output
mkdir -p $RESULT_DIR

# Change to work directory
cd $SLURM_SUBMIT_DIR

# =============================================================================
# Copy Input Files
# =============================================================================

echo "Copying train.py..."
cp "/tmp/train.py" "$SLURM_SUBMIT_DIR/input/train.py"
echo "Copying dataset.tar.gz..."
cp "/tmp/dataset.tar.gz" "$SLURM_SUBMIT_DIR/input/dataset.tar.gz"

# =============================================================================
# Execution Scripts
# =============================================================================

# --- Pre-Execution ---
echo "========================================"
echo "Python Data Processing"
echo "========================================"

# 추가 패키지 설치 (requirements가 있는 경우)
if [ -n "$FILE_REQUIREMENTS" ]; then
  echo "Installing additional packages..."
  pip install --user -r $FILE_REQUIREMENTS
fi

# --- Main Execution ---
apptainer exec $APPTAINER_IMAGE \
  python $FILE_SCRIPT \
    --input $FILE_INPUT_DATA \
    --output $RESULT_DIR

# --- Post-Execution ---
echo "========================================"
echo "Processing Completed"
echo "========================================"
du -sh $RESULT_DIR/*
echo "Output files:"
ls -lh $RESULT_DIR

# =============================================================================
# End of Script
# =============================================================================
