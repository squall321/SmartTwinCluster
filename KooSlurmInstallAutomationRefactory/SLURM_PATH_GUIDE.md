# 🔧 Slurm PATH Configuration Guide

## ✅ Current Status: **WORKING**

All Slurm commands (`sinfo`, `sbatch`, `squeue`, `srun`, etc.) are **already available** in your current shell! 🎉

---

## 📋 How It Works

### 1. **Installation Location**
Slurm is installed at:
```
/usr/local/slurm/
├── bin/         ← User commands (sinfo, sbatch, squeue, srun, etc.)
├── sbin/        ← System commands (slurmctld, slurmd, etc.)
├── etc/         ← Configuration files
├── lib/         ← Libraries
└── share/man/   ← Manual pages
```

### 2. **PATH Setup**
The file `/etc/profile.d/slurm.sh` automatically adds Slurm to your PATH:
```bash
export PATH=/usr/local/slurm/bin:/usr/local/slurm/sbin:$PATH
export LD_LIBRARY_PATH=/usr/local/slurm/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
export MANPATH=/usr/local/slurm/share/man${MANPATH:+:${MANPATH}}
```

This file is **automatically loaded** when you:
- Start a new login shell
- SSH into the machine
- Open a new terminal (in most configurations)

---

## 🔍 Verification

### Quick Check
```bash
# Check if commands are available
which sinfo sbatch squeue

# Should show:
# /usr/local/slurm/bin/sinfo
# /usr/local/slurm/bin/sbatch
# /usr/local/slurm/bin/squeue
```

### Full Verification
```bash
cd /home/koopark/claude/KooSlurmInstallAutomation
./verify_slurm_commands.sh
```

This script checks:
- ✅ PATH configuration
- ✅ All Slurm commands availability
- ✅ Slurm version
- ✅ Cluster connectivity

---

## 🚀 Using Slurm Commands

You can now use all Slurm commands directly:

### Cluster Status
```bash
sinfo                 # Partition overview
sinfo -N              # Node list
sinfo -Nel            # Detailed node info
scontrol show node    # Full node details
```

### Job Management
```bash
# Submit a job
sbatch my_script.sh

# Interactive job
srun --pty bash

# Check queue
squeue

# Job details
scontrol show job <jobid>

# Cancel job
scancel <jobid>
```

### Accounting
```bash
sacct                         # Recent jobs
sacct -S 2025-10-01           # Jobs since date
sacct -j <jobid> --format=ALL # Detailed job info
```

### Diagnostics
```bash
sdiag                 # Scheduler diagnostics
scontrol ping         # Test controller
scontrol show config  # Show configuration
```

---

## 🔄 Different Shell Scenarios

### Current Shell ✅ **Working Now**
Your current shell already has Slurm in PATH. Commands work immediately!

### New Terminal/SSH Session ✅ **Auto-configured**
When you:
- SSH into the machine
- Open a new terminal
- Start a new login shell

The `/etc/profile.d/slurm.sh` script is **automatically sourced**, so commands work immediately.

### Non-login Shell (rare)
If you start a non-login shell (like `bash` without options), you might need to source the profile:
```bash
source /etc/profile.d/slurm.sh
```

### Scripts
In scripts, you have three options:

**Option 1: Use full paths**
```bash
#!/bin/bash
/usr/local/slurm/bin/sinfo
/usr/local/slurm/bin/sbatch my_job.sh
```

**Option 2: Source the profile**
```bash
#!/bin/bash
source /etc/profile.d/slurm.sh
sinfo
sbatch my_job.sh
```

**Option 3: Set PATH in script**
```bash
#!/bin/bash
export PATH=/usr/local/slurm/bin:$PATH
sinfo
sbatch my_job.sh
```

---

## 🛠️ Manual Setup (if needed)

If for some reason the automatic setup doesn't work, you can manually configure your shell:

### For Bash (add to `~/.bashrc`)
```bash
export PATH=/usr/local/slurm/bin:/usr/local/slurm/sbin:$PATH
export LD_LIBRARY_PATH=/usr/local/slurm/lib:$LD_LIBRARY_PATH
export MANPATH=/usr/local/slurm/share/man:$MANPATH
```

### For ZSH (add to `~/.zshrc`)
```bash
export PATH=/usr/local/slurm/bin:/usr/local/slurm/sbin:$PATH
export LD_LIBRARY_PATH=/usr/local/slurm/lib:$LD_LIBRARY_PATH
export MANPATH=/usr/local/slurm/share/man:$MANPATH
```

### Apply Changes
```bash
source ~/.bashrc   # or source ~/.zshrc
```

---

## 🧪 Testing

### Test 1: Basic Commands
```bash
# Should all work without errors
sinfo
squeue
scontrol version
sacct --help
```

### Test 2: Submit a Test Job
```bash
cat > test_slurm.sh <<'EOF'
#!/bin/bash
#SBATCH --job-name=path_test
#SBATCH --output=path_test_%j.out
#SBATCH --cpus-per-task=1
#SBATCH --mem=100M
#SBATCH --time=00:01:00

echo "Testing Slurm commands from within a job..."
echo "Node: $SLURMD_NODENAME"
echo "Job ID: $SLURM_JOB_ID"

# These should work without PATH setup
echo "which sbatch: $(which sbatch)"
echo "which scontrol: $(which scontrol)"

echo "PATH test successful!"
EOF

sbatch test_slurm.sh
squeue
```

### Test 3: Full Verification
```bash
./verify_slurm_commands.sh
```

---

## ❓ Troubleshooting

### Problem: "command not found"
**Solution 1: Source the profile**
```bash
source /etc/profile.d/slurm.sh
```

**Solution 2: Check if file exists**
```bash
ls -la /etc/profile.d/slurm.sh
cat /etc/profile.d/slurm.sh
```

**Solution 3: Check PATH**
```bash
echo $PATH | grep slurm
# Should show: /usr/local/slurm/bin
```

**Solution 4: Use full path**
```bash
/usr/local/slurm/bin/sinfo
```

### Problem: Commands work but no output
This usually means slurmctld is not running:
```bash
sudo systemctl status slurmctld
sudo systemctl start slurmctld
```

### Problem: "No such file or directory" when running commands
Library path might be missing:
```bash
export LD_LIBRARY_PATH=/usr/local/slurm/lib:$LD_LIBRARY_PATH
ldd /usr/local/slurm/bin/sinfo
```

---

## 📚 Reference

### Key Files
- `/etc/profile.d/slurm.sh` - Auto-loaded PATH configuration
- `/usr/local/slurm/bin/` - User command binaries
- `/usr/local/slurm/sbin/` - System daemon binaries
- `~/.bashrc` - User shell configuration (optional)

### Important Directories
```bash
ls /usr/local/slurm/bin/    # User commands
ls /usr/local/slurm/sbin/   # System daemons
ls /usr/local/slurm/etc/    # Configuration files
ls /usr/local/slurm/lib/    # Libraries
```

### All Available Commands
```bash
# List all Slurm commands
ls /usr/local/slurm/bin/

# Common commands:
sacct      # Accounting data
sacctmgr   # Accounting manager
salloc     # Allocate resources
sattach    # Attach to running job
sbatch     # Submit batch job
sbcast     # Broadcast file to nodes
scancel    # Cancel job
scontrol   # Control Slurm
scrontab   # Cron-like scheduling
sdiag      # Diagnostics
sinfo      # Cluster information
sprio      # Job priority
squeue     # Job queue
sreport    # Accounting reports
srun       # Run job
sshare     # Share information
```

---

## ✅ Summary

**Your current shell:** ✅ Slurm commands already working!  
**New shells:** ✅ Auto-configured via `/etc/profile.d/slurm.sh`  
**SSH sessions:** ✅ Auto-configured  
**Scripts:** ✅ Source profile or use full paths  

You don't need to create shortcuts - the PATH is already properly configured! 🎉

---

**Test it right now:**
```bash
sinfo        # Should show your cluster status
squeue       # Should show empty job queue
scontrol version  # Should show: slurm 23.11.10
```

All working? Great! You're all set! 🚀



