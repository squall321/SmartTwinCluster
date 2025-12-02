#!/usr/bin/env python3
"""
Manually insert LS-DYNA templates into database
"""
import sqlite3
import json
import os

db_path = 'backend_5010/database/dashboard.db'

if not os.path.exists(db_path):
    print(f"❌ Database not found: {db_path}")
    exit(1)

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

print("=" * 60)
print("Insert LS-DYNA Templates")
print("=" * 60)
print()

# Delete old templates first
cursor.execute("DELETE FROM templates")
deleted = cursor.rowcount
print(f"🗑️  Deleted {deleted} existing templates")
print()

# LS-DYNA Single Job Template
single_config = {
    "partition": "compute",
    "nodes": 1,
    "cpus": 32,
    "memory": "64GB",
    "time": "24:00:00",
    "script": """#!/bin/bash
#SBATCH --ntasks=32

# LS-DYNA Single Job Submission
module load lsdyna/R13.1.0

NPROCS=32
MEMORY=64000000

echo "LS-DYNA Single Job"
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $SLURM_NODELIST"
echo "Cores: $NPROCS"

if [ ! -f "$K_FILE" ]; then
    echo "Error: K file not found: $K_FILE"
    exit 1
fi

OUTPUT_DIR=$(dirname $K_FILE)/output
mkdir -p $OUTPUT_DIR
cd $OUTPUT_DIR

mpirun -np $NPROCS ls-dyna_mpp I=$K_FILE MEMORY=$MEMORY NCPU=$NPROCS

EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ LS-DYNA simulation completed successfully"
else
    echo "❌ LS-DYNA simulation failed with exit code $EXIT_CODE"
fi
exit $EXIT_CODE"""
}

# LS-DYNA Array Job Template  
array_config = {
    "partition": "compute",
    "nodes": 1,
    "cpus": 16,
    "memory": "32GB",
    "time": "12:00:00",
    "script": """#!/bin/bash
#SBATCH --ntasks=16

# LS-DYNA Array Job Submission
module load lsdyna/R13.1.0

NPROCS=16
MEMORY=32000000

echo "LS-DYNA Array Job Submission"
echo "Parent Job ID: $SLURM_JOB_ID"
echo "Total K files: ${#K_FILES[@]}"

for K_FILE in "${K_FILES[@]}"; do
    if [ ! -f "$K_FILE" ]; then
        echo "Error: K file not found: $K_FILE"
        exit 1
    fi
done

JOB_IDS=()
for i in "${!K_FILES[@]}"; do
    K_FILE="${K_FILES[$i]}"
    BASENAME=$(basename "$K_FILE" .k)
    
    echo "[$((i+1))/${#K_FILES[@]}] Submitting job for: $BASENAME"
    
    JOB_DIR="/data/results/lsdyna_${SLURM_JOB_ID}_${i}_${BASENAME}"
    mkdir -p $JOB_DIR/output
    
    # Create and submit individual job
    SUBMITTED_JOB_ID=$(sbatch --parsable $JOB_DIR/run_lsdyna.sh)
    JOB_IDS+=($SUBMITTED_JOB_ID)
    
    echo "   → Job ID: $SUBMITTED_JOB_ID"
    sleep 1
done

echo "Total jobs submitted: ${#JOB_IDS[@]}"
echo "Job IDs: ${JOB_IDS[@]}" """
}

# Insert LS-DYNA Single Job
cursor.execute("""
    INSERT INTO templates (id, name, description, category, shared, config, created_by, usage_count)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
""", (
    'tpl-lsdyna-single',
    'LS-DYNA Single Job',
    'LS-DYNA simulation with single K-file input. Upload one K file and it will be automatically configured for MPP solver.',
    'simulation',
    1,
    json.dumps(single_config),
    'system',
    15
))
print("✅ Inserted: LS-DYNA Single Job")

# Insert LS-DYNA Array Job
cursor.execute("""
    INSERT INTO templates (id, name, description, category, shared, config, created_by, usage_count)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
""", (
    'tpl-lsdyna-array',
    'LS-DYNA Array Job',
    'LS-DYNA array job for multiple K-files. Upload multiple K files and each will be run as a separate job with dedicated resources and output directory.',
    'simulation',
    1,
    json.dumps(array_config),
    'system',
    8
))
print("✅ Inserted: LS-DYNA Array Job")

conn.commit()
conn.close()

print()
print("=" * 60)
print("✅ LS-DYNA templates inserted successfully!")
print("=" * 60)
print()
print("Run check_db.py to verify")
