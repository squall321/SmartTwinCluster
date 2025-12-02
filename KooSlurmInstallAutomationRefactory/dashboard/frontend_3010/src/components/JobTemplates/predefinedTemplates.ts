// 사전 정의 템플릿 라이브러리
// 10개의 프로페셔널 작업 템플릿

export interface TemplateConfig {
  partition: string;
  nodes: number;
  cpus: number;
  memory: string;
  time: string;
  gpu?: number;
  script: string;
}

export interface Template {
  id: string;
  name: string;
  description: string;
  category: 'ml' | 'simulation' | 'data' | 'custom' | 'compute' | 'container';
  shared: boolean;
  config: TemplateConfig;
  created_by: string;
  created_at: string;
  updated_at: string;
  usage_count: number;
  tags: string[];
}

// 10개 사전 정의 템플릿 (Mock Mode용)
export const PREDEFINED_TEMPLATES: Template[] = [
  {
    id: 'template-001',
    name: 'PyTorch Distributed Training',
    description: 'Multi-GPU PyTorch training with DDP (DistributedDataParallel) support',
    category: 'ml',
    shared: true,
    config: {
      partition: 'gpu',
      nodes: 2,
      cpus: 16,
      memory: '64GB',
      time: '48:00:00',
      gpu: 4,
      script: `#!/bin/bash
#SBATCH --ntasks-per-node=4
#SBATCH --gres=gpu:4

# PyTorch Distributed Training
module load cuda/11.8
module load python/3.10

source ~/venv/bin/activate

# Set environment variables for distributed training
export MASTER_ADDR=$(scontrol show hostnames $SLURM_JOB_NODELIST | head -n 1)
export MASTER_PORT=29500
export WORLD_SIZE=$SLURM_NTASKS
export RANK=$SLURM_PROCID
export LOCAL_RANK=$SLURM_LOCALID

# Run distributed training
python -m torch.distributed.launch \\
    --nproc_per_node=4 \\
    --nnodes=2 \\
    --node_rank=$SLURM_NODEID \\
    --master_addr=$MASTER_ADDR \\
    --master_port=$MASTER_PORT \\
    train.py \\
    --epochs 100 \\
    --batch-size 128 \\
    --lr 0.001 \\
    --data-dir /data/imagenet

echo "Training completed at $(date)"`
    },
    created_by: 'system',
    created_at: '2025-01-01',
    updated_at: '2025-01-01',
    usage_count: 0,
    tags: ['pytorch', 'distributed', 'gpu', 'deep-learning']
  },

  {
    id: 'template-002',
    name: 'TensorFlow GPU Training',
    description: 'Single-node multi-GPU TensorFlow 2.x model training',
    category: 'ml',
    shared: true,
    config: {
      partition: 'gpu',
      nodes: 1,
      cpus: 8,
      memory: '32GB',
      time: '24:00:00',
      gpu: 2,
      script: `#!/bin/bash
#SBATCH --gres=gpu:2

# TensorFlow GPU Training
module load cuda/11.8
module load cudnn/8.6
module load python/3.10

source ~/venv/bin/activate

# Enable GPU memory growth
export TF_FORCE_GPU_ALLOW_GROWTH=true

# Run training
python train.py \\
    --model resnet50 \\
    --epochs 50 \\
    --batch-size 64 \\
    --gpus 2 \\
    --data-dir /data/cifar10 \\
    --output-dir /results/$SLURM_JOB_ID

# Save model checkpoint
cp /results/$SLURM_JOB_ID/final_model.h5 /checkpoints/

echo "Training completed at $(date)"`
    },
    created_by: 'system',
    created_at: '2025-01-01',
    updated_at: '2025-01-01',
    usage_count: 0,
    tags: ['tensorflow', 'gpu', 'deep-learning', 'image-classification']
  },

  {
    id: 'template-003',
    name: 'Data Preprocessing Pipeline',
    description: 'Large-scale parallel data preprocessing with Dask',
    category: 'data',
    shared: true,
    config: {
      partition: 'cpu',
      nodes: 4,
      cpus: 128,
      memory: '512GB',
      time: '12:00:00',
      script: `#!/bin/bash

# Data Preprocessing Pipeline
module load python/3.10

source ~/venv/bin/activate

# Install Dask if needed
# pip install dask distributed

# Start Dask scheduler on first node
if [ $SLURM_PROCID -eq 0 ]; then
    dask-scheduler --scheduler-file scheduler.json &
    sleep 10
fi

# Start Dask workers
dask-worker --scheduler-file scheduler.json \\
    --nthreads \$SLURM_CPUS_PER_TASK \\
    --memory-limit 128GB &

# Wait for workers to start
sleep 5

# Run preprocessing
if [ $SLURM_PROCID -eq 0 ]; then
    python preprocess.py \\
        --input /data/raw \\
        --output /data/processed \\
        --scheduler scheduler.json \\
        --format parquet
fi

wait
echo "Preprocessing completed at $(date)"`
    },
    created_by: 'system',
    created_at: '2025-01-01',
    updated_at: '2025-01-01',
    usage_count: 0,
    tags: ['data-processing', 'dask', 'parallel', 'etl']
  },

  {
    id: 'template-004',
    name: 'GROMACS Molecular Dynamics',
    description: 'Molecular dynamics simulation using GROMACS with MPI parallelization',
    category: 'simulation',
    shared: true,
    config: {
      partition: 'cpu',
      nodes: 8,
      cpus: 256,
      memory: '1TB',
      time: '72:00:00',
      script: `#!/bin/bash
#SBATCH --ntasks-per-node=32

# GROMACS Molecular Dynamics Simulation
module load gromacs/2023.3
module load openmpi/4.1.4

# Set number of OpenMP threads
export OMP_NUM_THREADS=1

# Prepare system
gmx grompp -f md.mdp -c em.gro -p topol.top -o md_0_1.tpr

# Run MD simulation
mpirun -np $SLURM_NTASKS gmx_mpi mdrun \\
    -v \\
    -deffnm md_0_1 \\
    -ntomp $OMP_NUM_THREADS \\
    -pin on \\
    -pinstride 1

# Analysis
gmx energy -f md_0_1.edr -o energy.xvg
gmx rms -s md_0_1.tpr -f md_0_1.xtc -o rmsd.xvg

echo "Simulation completed at $(date)"
echo "Output files in: $(pwd)"`
    },
    created_by: 'system',
    created_at: '2025-01-01',
    updated_at: '2025-01-01',
    usage_count: 0,
    tags: ['gromacs', 'molecular-dynamics', 'simulation', 'mpi']
  },

  {
    id: 'template-005',
    name: 'Jupyter Notebook Interactive',
    description: 'Interactive Jupyter notebook with GPU support',
    category: 'custom',
    shared: true,
    config: {
      partition: 'gpu',
      nodes: 1,
      cpus: 4,
      memory: '16GB',
      time: '08:00:00',
      gpu: 1,
      script: `#!/bin/bash
#SBATCH --gres=gpu:1

# Jupyter Notebook with GPU
module load cuda/11.8
module load python/3.10

source ~/venv/bin/activate

# Install Jupyter if needed
pip install jupyter jupyterlab ipywidgets

# Get the hostname
HOSTNAME=$(hostname)
PORT=8888

# Start Jupyter Lab
jupyter lab \\
    --no-browser \\
    --ip=$HOSTNAME \\
    --port=$PORT \\
    --NotebookApp.token='' \\
    --NotebookApp.password=''

echo ""
echo "=========================================="
echo "Jupyter Lab is running on:"
echo "  http://$HOSTNAME:$PORT"
echo "=========================================="
echo ""
echo "To access from your local machine:"
echo "  ssh -L $PORT:$HOSTNAME:$PORT $(whoami)@cluster-login"
echo "  Then open: http://localhost:$PORT"
echo "=========================================="

# Keep job alive
wait`
    },
    created_by: 'system',
    created_at: '2025-01-01',
    updated_at: '2025-01-01',
    usage_count: 0,
    tags: ['jupyter', 'interactive', 'gpu', 'notebook']
  },

  {
    id: 'template-006',
    name: 'R Statistical Analysis',
    description: 'Parallel R computation with doParallel',
    category: 'data',
    shared: true,
    config: {
      partition: 'cpu',
      nodes: 1,
      cpus: 32,
      memory: '128GB',
      time: '06:00:00',
      script: `#!/bin/bash

# R Statistical Analysis
module load r/4.3.0

# Run R script with parallel processing
Rscript --vanilla << 'EOF'
library(doParallel)
library(foreach)

# Setup parallel backend
cl <- makeCluster(\${SLURM_CPUS_PER_TASK})
registerDoParallel(cl)

# Load data
data <- read.csv("/data/input.csv")

# Parallel computation
results <- foreach(i = 1:nrow(data), .combine = rbind) %dopar% {
  # Your analysis here
  analyze_row(data[i, ])
}

# Save results
write.csv(results, "/data/output.csv", row.names = FALSE)

# Cleanup
stopCluster(cl)

cat("Analysis completed\\n")
EOF

echo "R analysis completed at $(date)"`
    },
    created_by: 'system',
    created_at: '2025-01-01',
    updated_at: '2025-01-01',
    usage_count: 0,
    tags: ['r', 'statistics', 'parallel', 'data-analysis']
  },

  {
    id: 'template-007',
    name: 'MATLAB Parallel Computing',
    description: 'MATLAB computation with Parallel Computing Toolbox',
    category: 'simulation',
    shared: true,
    config: {
      partition: 'cpu',
      nodes: 1,
      cpus: 16,
      memory: '64GB',
      time: '24:00:00',
      script: `#!/bin/bash

# MATLAB Parallel Computing
module load matlab/R2023b

# Run MATLAB script
matlab -nodisplay -nosplash -r "
    % Set number of workers
    maxNumCompThreads(\$SLURM_CPUS_PER_TASK);
    
    % Create parallel pool
    parpool('local', \$SLURM_CPUS_PER_TASK);
    
    % Your computation
    parfor i = 1:1000
        result(i) = expensive_computation(i);
    end
    
    % Save results
    save('results.mat', 'result');
    
    % Cleanup
    delete(gcp('nocreate'));
    exit;
"

echo "MATLAB computation completed at \$(date)"`
    },
    created_by: 'system',
    created_at: '2025-01-01',
    updated_at: '2025-01-01',
    usage_count: 0,
    tags: ['matlab', 'parallel', 'simulation', 'numerical']
  },

  {
    id: 'template-008',
    name: 'OpenMPI Parallel Application',
    description: 'General MPI application with multi-node support',
    category: 'compute',
    shared: true,
    config: {
      partition: 'cpu',
      nodes: 16,
      cpus: 512,
      memory: '2TB',
      time: '96:00:00',
      script: `#!/bin/bash
#SBATCH --ntasks-per-node=32

# OpenMPI Parallel Application
module load openmpi/4.1.4
module load gcc/11.2.0

# Compile (if needed)
# mpicc -O3 -o myapp myapp.c

# Set environment variables
export OMP_NUM_THREADS=1
export I_MPI_PIN=1
export I_MPI_PIN_DOMAIN=auto

# Run MPI application
mpirun -np \$SLURM_NTASKS \\
    --map-by node:PE=1 \\
    --bind-to core \\
    --report-bindings \\
    ./myapp input.dat

# Post-processing
echo "Job completed at \$(date)"
echo "Total tasks: \$SLURM_NTASKS"
echo "Nodes used: \$SLURM_NNODES"
echo "CPUs per task: \$SLURM_CPUS_PER_TASK"`
    },
    created_by: 'system',
    created_at: '2025-01-01',
    updated_at: '2025-01-01',
    usage_count: 0,
    tags: ['mpi', 'parallel', 'hpc', 'c/c++']
  },

  {
    id: 'template-009',
    name: 'Docker Container Job',
    description: 'Run containerized application with Singularity/Apptainer',
    category: 'container',
    shared: true,
    config: {
      partition: 'cpu',
      nodes: 1,
      cpus: 8,
      memory: '32GB',
      time: '12:00:00',
      script: `#!/bin/bash

# Docker Container Job (using Singularity)
module load singularity/3.11.0

# Pull container (if not exists)
if [ ! -f container.sif ]; then
    singularity pull container.sif docker://myrepo/myimage:latest
fi

# Run containerized application
singularity exec \\
    --bind /data:/data \\
    --bind /scratch:/scratch \\
    container.sif \\
    python /app/main.py \\
        --input /data/input \\
        --output /scratch/output_\$SLURM_JOB_ID

# Copy results back
cp -r /scratch/output_\$SLURM_JOB_ID /results/

echo "Container job completed at \$(date)"`
    },
    created_by: 'system',
    created_at: '2025-01-01',
    updated_at: '2025-01-01',
    usage_count: 0,
    tags: ['docker', 'singularity', 'container', 'reproducibility']
  },

  {
    id: 'template-010',
    name: 'Array Job - Parameter Sweep',
    description: 'Job array for parameter sweeps and batch processing',
    category: 'compute',
    shared: true,
    config: {
      partition: 'cpu',
      nodes: 1,
      cpus: 4,
      memory: '16GB',
      time: '02:00:00',
      script: `#!/bin/bash
#SBATCH --array=1-100

# Array Job - Parameter Sweep
module load python/3.10

source ~/venv/bin/activate

# Define parameter ranges
LEARNING_RATES=(0.001 0.01 0.1)
BATCH_SIZES=(32 64 128)
DROPOUT_RATES=(0.1 0.2 0.3 0.5)

# Calculate parameters from array task ID
NUM_LR=\${#LEARNING_RATES[@]}
NUM_BS=\${#BATCH_SIZES[@]}
NUM_DR=\${#DROPOUT_RATES[@]}

IDX=\$((SLURM_ARRAY_TASK_ID - 1))
LR_IDX=\$((IDX / (NUM_BS * NUM_DR) % NUM_LR))
BS_IDX=\$((IDX / NUM_DR % NUM_BS))
DR_IDX=\$((IDX % NUM_DR))

LR=\${LEARNING_RATES[$LR_IDX]}
BS=\${BATCH_SIZES[$BS_IDX]}
DR=\${DROPOUT_RATES[$DR_IDX]}

echo "Task \$SLURM_ARRAY_TASK_ID: LR=\$LR, BS=\$BS, DR=\$DR"

# Run experiment
python train.py \\
    --lr \$LR \\
    --batch-size \$BS \\
    --dropout \$DR \\
    --output-dir /results/sweep_\$SLURM_ARRAY_JOB_ID/\$SLURM_ARRAY_TASK_ID

echo "Task completed at \$(date)"`
    },
    created_by: 'system',
    created_at: '2025-01-01',
    updated_at: '2025-01-01',
    usage_count: 0,
    tags: ['array-job', 'parameter-sweep', 'batch', 'hyperparameter-tuning']
  },

  // LS-DYNA Single K-File Template
  {
    id: 'template-lsdyna-single',
    name: 'LS-DYNA Single Job',
    description: 'LS-DYNA simulation with single K-file input. Upload one K file and it will be automatically configured for MPP solver.',
    category: 'simulation',
    shared: true,
    config: {
      partition: 'compute',
      nodes: 1,
      cpus: 32,
      memory: '64GB',
      time: '24:00:00',
      script: `#!/bin/bash
#SBATCH --ntasks=32

# LS-DYNA Single Job Submission
# This script will be automatically updated when you upload a K file

module load lsdyna/R13.1.0

# Job configuration
NPROCS=32
MEMORY=64000000  # 64GB in words (8 bytes per word)

# K file will be automatically set here by file upload
# K_FILE="/data/results/\${JOB_ID}/your_input.k"

echo "========================================"
echo "LS-DYNA Single Job"
echo "========================================"
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $SLURM_NODELIST"
echo "Cores: $NPROCS"
echo "K File: $K_FILE"
echo "Start Time: $(date)"
echo ""

# Check if K file exists
if [ ! -f "$K_FILE" ]; then
    echo "Error: K file not found: $K_FILE"
    exit 1
fi

# Create output directory
OUTPUT_DIR=$(dirname $K_FILE)/output
mkdir -p $OUTPUT_DIR
cd $OUTPUT_DIR

# Run LS-DYNA MPP solver
echo "Running LS-DYNA..."
mpirun -np $NPROCS ls-dyna_mpp \\
    I=$K_FILE \\
    MEMORY=$MEMORY \\
    NCPU=$NPROCS

EXIT_CODE=$?

echo ""
echo "========================================"
echo "Job Completed"
echo "========================================"
echo "Exit Code: $EXIT_CODE"
echo "End Time: $(date)"
echo ""

if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ LS-DYNA simulation completed successfully"
    echo "Output files in: $OUTPUT_DIR"
    ls -lh $OUTPUT_DIR
else
    echo "❌ LS-DYNA simulation failed with exit code $EXIT_CODE"
    echo "Check error messages above"
fi

exit $EXIT_CODE`
    },
    created_by: 'system',
    created_at: '2025-01-10',
    updated_at: '2025-01-10',
    usage_count: 0,
    tags: ['lsdyna', 'simulation', 'mpp', 'crash', 'fem']
  },

  // LS-DYNA Array Job Template
  {
    id: 'template-lsdyna-array',
    name: 'LS-DYNA Array Job',
    description: 'LS-DYNA array job for multiple K-files. Upload multiple K files and each will be run as a separate job with dedicated resources and output directory.',
    category: 'simulation',
    shared: true,
    config: {
      partition: 'compute',
      nodes: 1,
      cpus: 16,
      memory: '32GB',
      time: '12:00:00',
      script: `#!/bin/bash
#SBATCH --ntasks=16

# LS-DYNA Array Job Submission
# This script will submit multiple LS-DYNA jobs, one for each uploaded K file

module load lsdyna/R13.1.0

# Job configuration
NPROCS=16
MEMORY=32000000  # 32GB in words

# K files will be automatically populated here by file upload
# K_FILES array will contain paths to all uploaded K files
# Example:
# K_FILES=(
#   "/data/results/\${PARENT_JOB_ID}/model1.k"
#   "/data/results/\${PARENT_JOB_ID}/model2.k"
#   "/data/results/\${PARENT_JOB_ID}/model3.k"
# )

echo "========================================"
echo "LS-DYNA Array Job Submission"
echo "========================================"
echo "Parent Job ID: $SLURM_JOB_ID"
echo "Node: $SLURM_NODELIST"
echo "Cores per job: $NPROCS"
echo "Total K files: \${#K_FILES[@]}"
echo "Start Time: $(date)"
echo ""

# Validate K files
for K_FILE in "\${K_FILES[@]}"; do
    if [ ! -f "$K_FILE" ]; then
        echo "Error: K file not found: $K_FILE"
        exit 1
    fi
done

# Submit individual jobs for each K file
JOB_IDS=()
for i in "\${!K_FILES[@]}"; do
    K_FILE="\${K_FILES[$i]}"
    BASENAME=$(basename "$K_FILE" .k)
    
    echo "[$((i+1))/\${#K_FILES[@]}] Submitting job for: $BASENAME"
    
    # Create unique job directory
    JOB_DIR="/data/results/lsdyna_\${SLURM_JOB_ID}_\${i}_\${BASENAME}"
    mkdir -p $JOB_DIR/output
    
    # Create individual job script
    cat > $JOB_DIR/run_lsdyna.sh << 'EOFSCRIPT'
#!/bin/bash
#SBATCH --job-name=JOBNAME_PLACEHOLDER
#SBATCH --ntasks=NPROCS_PLACEHOLDER
#SBATCH --mem=MEMORY_PLACEHOLDER
#SBATCH --time=TIME_PLACEHOLDER
#SBATCH --output=OUTPUT_DIR_PLACEHOLDER/slurm-%j.out

module load lsdyna/R13.1.0

K_FILE="K_FILE_PLACEHOLDER"
NPROCS=NPROCS_PLACEHOLDER
MEMORY=MEMORY_VALUE_PLACEHOLDER
OUTPUT_DIR="OUTPUT_DIR_PLACEHOLDER"

echo "========================================"
echo "LS-DYNA Job: JOBNAME_PLACEHOLDER"
echo "========================================"
echo "Job ID: $SLURM_JOB_ID"
echo "K File: $K_FILE"
echo "Cores: $NPROCS"
echo "Start: $(date)"
echo ""

cd $OUTPUT_DIR

mpirun -np $NPROCS ls-dyna_mpp \\
    I=$K_FILE \\
    MEMORY=$MEMORY \\
    NCPU=$NPROCS

EXIT_CODE=$?

echo ""
echo "Exit Code: $EXIT_CODE"
echo "End: $(date)"

if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ Completed successfully"
else
    echo "❌ Failed with exit code $EXIT_CODE"
fi

exit $EXIT_CODE
EOFSCRIPT

    # Replace placeholders
    sed -i "s|JOBNAME_PLACEHOLDER|lsdyna_$BASENAME|g" $JOB_DIR/run_lsdyna.sh
    sed -i "s|NPROCS_PLACEHOLDER|$NPROCS|g" $JOB_DIR/run_lsdyna.sh
    sed -i "s|MEMORY_PLACEHOLDER|32GB|g" $JOB_DIR/run_lsdyna.sh
    sed -i "s|TIME_PLACEHOLDER|12:00:00|g" $JOB_DIR/run_lsdyna.sh
    sed -i "s|K_FILE_PLACEHOLDER|$K_FILE|g" $JOB_DIR/run_lsdyna.sh
    sed -i "s|MEMORY_VALUE_PLACEHOLDER|$MEMORY|g" $JOB_DIR/run_lsdyna.sh
    sed -i "s|OUTPUT_DIR_PLACEHOLDER|$JOB_DIR/output|g" $JOB_DIR/run_lsdyna.sh
    
    # Submit job
    SUBMITTED_JOB_ID=$(sbatch --parsable $JOB_DIR/run_lsdyna.sh)
    JOB_IDS+=($SUBMITTED_JOB_ID)
    
    echo "   → Job ID: $SUBMITTED_JOB_ID"
    echo "   → Output: $JOB_DIR/output"
    echo ""
    
    # Optional: Add delay between submissions to avoid overwhelming scheduler
    sleep 1
done

echo "========================================"
echo "Array Job Submission Complete"
echo "========================================"
echo "Total jobs submitted: \${#JOB_IDS[@]}"
echo "Job IDs: \${JOB_IDS[@]}"
echo ""
echo "Monitor jobs:"
echo "  squeue -j $(IFS=,; echo "\${JOB_IDS[*]}")"
echo ""
echo "Cancel all jobs:"
echo "  scancel $(IFS=' '; echo "\${JOB_IDS[*]}")"
echo ""`
    },
    created_by: 'system',
    created_at: '2025-01-10',
    updated_at: '2025-01-10',
    usage_count: 0,
    tags: ['lsdyna', 'array-job', 'simulation', 'mpp', 'batch', 'parametric']
  }
];

// 카테고리 정의
export interface Category {
  name: string;
  label: string;
  description: string;
  icon: string;
  color: string;
}

export const TEMPLATE_CATEGORIES: Category[] = [
  {
    name: 'ml',
    label: 'Machine Learning',
    description: 'Deep learning and ML model training',
    icon: '🤖',
    color: 'blue'
  },
  {
    name: 'data',
    label: 'Data Processing',
    description: 'ETL, preprocessing, and data analysis',
    icon: '📊',
    color: 'green'
  },
  {
    name: 'simulation',
    label: 'Simulation',
    description: 'Scientific simulations and modeling',
    icon: '🧪',
    color: 'purple'
  },
  {
    name: 'compute',
    label: 'HPC Compute',
    description: 'High-performance parallel computing',
    icon: '⚡',
    color: 'yellow'
  },
  {
    name: 'container',
    label: 'Container',
    description: 'Containerized applications',
    icon: '📦',
    color: 'indigo'
  },
  {
    name: 'custom',
    label: 'Custom',
    description: 'User-defined templates',
    icon: '⚙️',
    color: 'gray'
  }
];

// 템플릿 검색 헬퍼
export function searchTemplates(
  templates: Template[],
  query: string,
  category?: string
): Template[] {
  let filtered = templates;

  // 카테고리 필터
  if (category && category !== 'all') {
    filtered = filtered.filter(t => t.category === category);
  }

  // 검색 필터
  if (query) {
    const q = query.toLowerCase();
    filtered = filtered.filter(t =>
      t.name.toLowerCase().includes(q) ||
      t.description.toLowerCase().includes(q) ||
      t.tags.some(tag => tag.toLowerCase().includes(q))
    );
  }

  return filtered;
}

// 인기 템플릿 정렬
export function sortTemplatesByPopularity(templates: Template[]): Template[] {
  return [...templates].sort((a, b) => b.usage_count - a.usage_count);
}

// 최근 템플릿 정렬
export function sortTemplatesByRecent(templates: Template[]): Template[] {
  return [...templates].sort((a, b) => 
    new Date(b.updated_at).getTime() - new Date(a.updated_at).getTime()
  );
}
