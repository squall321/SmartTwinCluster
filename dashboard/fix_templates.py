#!/usr/bin/env python3
"""
Fix LS-DYNA templates with proper JSON escaping
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
print("Fix LS-DYNA Template Configs")
print("=" * 60)
print()

# Delete all templates
cursor.execute("DELETE FROM templates")
print(f"🗑️  Deleted all existing templates")
print()

# LS-DYNA Single Job - proper config
single_config = {
    "partition": "compute",
    "nodes": 1,
    "cpus": 32,
    "memory": "64GB",
    "time": "24:00:00",
    "script": "#!/bin/bash\n#SBATCH --ntasks=32\n\n# LS-DYNA Single Job Submission\nmodule load lsdyna/R13.1.0\n\nNPROCS=32\nMEMORY=64000000\n\necho \"LS-DYNA Single Job\"\necho \"Job ID: $SLURM_JOB_ID\"\necho \"Node: $SLURM_NODELIST\"\necho \"Cores: $NPROCS\"\n\nif [ ! -f \"$K_FILE\" ]; then\n    echo \"Error: K file not found: $K_FILE\"\n    exit 1\nfi\n\nOUTPUT_DIR=$(dirname $K_FILE)/output\nmkdir -p $OUTPUT_DIR\ncd $OUTPUT_DIR\n\nmpirun -np $NPROCS ls-dyna_mpp I=$K_FILE MEMORY=$MEMORY NCPU=$NPROCS\n\nEXIT_CODE=$?\nif [ $EXIT_CODE -eq 0 ]; then\n    echo \"LS-DYNA simulation completed successfully\"\nelse\n    echo \"LS-DYNA simulation failed with exit code $EXIT_CODE\"\nfi\nexit $EXIT_CODE"
}

# LS-DYNA Array Job - proper config  
array_config = {
    "partition": "compute",
    "nodes": 1,
    "cpus": 16,
    "memory": "32GB",
    "time": "12:00:00",
    "script": "#!/bin/bash\n#SBATCH --ntasks=16\n\n# LS-DYNA Array Job Submission\nmodule load lsdyna/R13.1.0\n\nNPROCS=16\nMEMORY=32000000\n\necho \"LS-DYNA Array Job Submission\"\necho \"Parent Job ID: $SLURM_JOB_ID\"\necho \"Total K files: ${#K_FILES[@]}\"\n\nfor K_FILE in \"${K_FILES[@]}\"; do\n    if [ ! -f \"$K_FILE\" ]; then\n        echo \"Error: K file not found: $K_FILE\"\n        exit 1\n    fi\ndone\n\nJOB_IDS=()\nfor i in \"${!K_FILES[@]}\"; do\n    K_FILE=\"${K_FILES[$i]}\"\n    BASENAME=$(basename \"$K_FILE\" .k)\n    \n    echo \"[$((i+1))/${#K_FILES[@]}] Submitting job for: $BASENAME\"\n    \n    JOB_DIR=\"/data/results/lsdyna_${SLURM_JOB_ID}_${i}_${BASENAME}\"\n    mkdir -p $JOB_DIR/output\n    \n    SUBMITTED_JOB_ID=$(sbatch --parsable $JOB_DIR/run_lsdyna.sh)\n    JOB_IDS+=($SUBMITTED_JOB_ID)\n    \n    echo \"   -> Job ID: $SUBMITTED_JOB_ID\"\n    sleep 1\ndone\n\necho \"Total jobs submitted: ${#JOB_IDS[@]}\"\necho \"Job IDs: ${JOB_IDS[@]}\""
}

# Test JSON serialization
try:
    single_json = json.dumps(single_config)
    array_json = json.dumps(array_config)
    print("✅ JSON serialization test passed")
    print()
except Exception as e:
    print(f"❌ JSON serialization failed: {e}")
    exit(1)

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
    single_json,
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
    array_json,
    'system',
    8
))
print("✅ Inserted: LS-DYNA Array Job")

conn.commit()

# Verify
print()
print("Verifying...")
cursor.execute("SELECT id, name, config FROM templates")
templates = cursor.fetchall()

for tpl in templates:
    tpl_id, name, config_str = tpl
    try:
        config = json.loads(config_str)
        print(f"✅ {name}: JSON valid, keys={list(config.keys())}")
    except Exception as e:
        print(f"❌ {name}: JSON invalid - {e}")

conn.close()

print()
print("=" * 60)
print("✅ Templates fixed!")
print("=" * 60)
print()
print("Now restart backend:")
print("  cd backend_5010")
print("  ./restart_backend.sh")
