# Phase 4: Slurm Integration - COMPLETE

## Overview
Completed integration of Slurm workload manager for proper execution of app containers on visualization nodes instead of the access node.

## Date: 2025-10-24

## Problem Identified
- Initial implementation ran Apptainer containers directly on the backend server (access node)
- This caused VNC conflicts and resource issues when backend server is accessed via VNC
- **Correct approach**: Use Slurm to submit jobs to visualization nodes

## Solution Implemented

### 1. Slurm Job Manager (`services/slurm_app_manager.py`)
**Created**: Manages Slurm job lifecycle for app sessions

Key features:
- Submit jobs via `sbatch` with environment variables
- Monitor job status (PENDING → RUNNING → COMPLETED/FAILED)
- Extract node information from Slurm
- Cancel jobs via `scancel`
- Map node names to IP addresses

Key methods:
- `submit_app_job(session_id, app_id, vnc_port)` - Submit Slurm job
- `cancel_job(session_id)` - Cancel running job
- `get_job_status_info(session_id)` - Get job status
- `_get_job_status(job_id)` - Query Slurm for job state
- `_get_node_ip(node_name)` - Map node name to IP

### 2. Updated Session Service (`services/app_session_service.py`)
**Modified**: Replaced `ApptainerManager` with `SlurmAppManager`

Changes:
- Import `SlurmAppManager` instead of `ApptainerManager`
- `_start_real_session()` - Now submits Slurm job instead of starting local container
- `_monitor_job_for_session()` - New method to monitor job status and update session with node info
- `delete_session()` - Calls `slurm_manager.cancel_job()` instead of stopping local container
- `restart_session()` - Cancels old job and submits new one

Session lifecycle:
1. `creating` - Initial session creation
2. `pending` - Slurm job submitted, waiting for node assignment
3. `running` - Job running on viz node, VNC accessible
4. `stopped` - Job completed/cancelled

### 3. Slurm Job Script (`slurm_jobs/gedit_vnc_job.sh`)
**Created**: Batch script for running GEdit with VNC on viz nodes

SBATCH directives:
- `--partition=viz` - Run on visualization partition
- `--nodes=1` - Single node
- `--cpus-per-task=2` - 2 CPU cores
- `--mem=4G` - 4GB RAM
- `--time=02:00:00` - 2 hour time limit

Environment variables (passed from backend):
- `SESSION_ID` - Unique session identifier
- `VNC_PORT` - WebSocket/noVNC port (e.g., 6080)

Apptainer execution:
- Image path: `/opt/apptainers/apps/gedit/gedit.sif`
- VNC always runs on port 5901 inside container
- Websockify proxies to external port `$VNC_PORT`

Job info file:
- Writes `/tmp/app_session_${SESSION_ID}.info` with node details
- Contains: `JOB_ID`, `NODE`, `VNC_PORT`, `NODE_IP`, `STATUS`, `START_TIME`

### 4. Image Deployment (`deploy_app_images.sh`)
**Created**: Script to deploy Apptainer images to viz nodes

Deployment target:
- Viz nodes: `/opt/apptainers/apps/<app_name>/`
- Example: `/opt/apptainers/apps/gedit/gedit.sif`

Process:
1. SSH to each viz node
2. Create app directory if needed
3. Copy .sif file from local build directory
4. Verify deployment

Successfully deployed:
- `gedit.sif` (796MB) to viz-node001

### 5. Test Script (`test_slurm_integration.py`)
**Created**: Standalone test for Slurm integration

Tests:
- Job submission
- Status monitoring (PENDING → RUNNING)
- Node information extraction
- Job cancellation

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Frontend (React, port 5174)                                 │
│  - App Launcher UI                                           │
│  - noVNC Viewer                                              │
└────────────────────┬────────────────────────────────────────┘
                     │ HTTP/WS
┌────────────────────▼────────────────────────────────────────┐
│  Backend (Flask, port 5000) - Access Node                    │
│  - REST API (app_routes.py)                                  │
│  - Session Service (app_session_service.py)                  │
│  - Slurm Manager (slurm_app_manager.py)                      │
└────────────────────┬────────────────────────────────────────┘
                     │ sbatch
┌────────────────────▼────────────────────────────────────────┐
│  Slurm Controller                                            │
└────────────────────┬────────────────────────────────────────┘
                     │ slurmctld
┌────────────────────▼────────────────────────────────────────┐
│  Visualization Node (viz-node001: 192.168.122.252)          │
│  - Slurmd (Slurm daemon)                                     │
│  - Apptainer runtime                                         │
│  - App images: /opt/apptainers/apps/*/                       │
│    ├─ gedit/gedit.sif                                        │
│    └─ (future apps)                                          │
│                                                              │
│  Running container:                                          │
│  ┌────────────────────────────────────────────────────┐     │
│  │ Apptainer Container (gedit.sif)                    │     │
│  │ - VNC Server (5901)                                │     │
│  │ - Websockify (6080)                                │     │
│  │ - XFCE Desktop                                     │     │
│  │ - GEdit Application                                │     │
│  └────────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────┘
```

## Session Flow

1. **User Creates Session** (Frontend)
   - User clicks "Launch App" → gedit
   - Frontend calls `POST /api/app/sessions`

2. **Backend Creates Session** (Access Node)
   - `app_routes.create_session()` receives request
   - `app_session_service.create_session()` allocates VNC port
   - Session status: `creating`
   - Calls `_start_real_session()`

3. **Slurm Job Submission** (Background Thread)
   - `slurm_manager.submit_app_job()` runs `sbatch`
   - Job script: `/dashboard/app_5174/slurm_jobs/gedit_vnc_job.sh`
   - Passes `SESSION_ID` and `VNC_PORT` as env vars
   - Slurm assigns job ID
   - Session status: `pending`

4. **Job Monitoring** (Background Thread)
   - `_monitor_job_for_session()` polls job status every 1s
   - Waits for status: `RUNNING`
   - Extracts node name and IP from Slurm
   - Updates session:
     - `status`: `running`
     - `node`: `viz-node001`
     - `node_ip`: `192.168.122.252`
     - `displayUrl`: `ws://192.168.122.252:6080`

5. **Container Starts** (Viz Node)
   - Job runs on assigned viz node
   - Writes job info to `/tmp/app_session_<SESSION_ID>.info`
   - Starts Apptainer container:
     - VNC server on :1 (port 5901)
     - Websockify on port 6080
     - Launches XFCE + GEdit

6. **User Connects** (Frontend)
   - Polls `GET /api/app/sessions/<id>` for status
   - When status=`running`, gets `displayUrl`
   - noVNC connects to `ws://192.168.122.252:6080`
   - User sees GEdit in browser

7. **Session Termination**
   - User clicks "Stop Session"
   - Frontend calls `DELETE /api/app/sessions/<id>`
   - Backend calls `slurm_manager.cancel_job()`
   - Slurm runs `scancel <job_id>`
   - Container stops, session deleted

## Key Differences from Initial Implementation

| Aspect | Initial (Wrong) | Current (Correct) |
|--------|----------------|-------------------|
| **Execution Location** | Access node (backend server) | Viz node (Slurm job) |
| **Manager Class** | `ApptainerManager` | `SlurmAppManager` |
| **Start Method** | `apptainer run` directly | `sbatch` job script |
| **Stop Method** | `apptainer instance stop` | `scancel <job_id>` |
| **Node Info** | Always `localhost` | Actual viz node IP from Slurm |
| **Resource Conflicts** | ❌ VNC conflicts on access node | ✅ Isolated on viz node |
| **Scalability** | ❌ Limited to 1 server | ✅ Multiple viz nodes |

## Testing

### Prerequisites
- Slurm controller must be running
- Viz partition must be available
- Viz nodes must have image: `/opt/apptainers/apps/gedit/gedit.sif`

### Test Slurm Integration
```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/kooCAEWebServer_5000
python3 test_slurm_integration.py
```

Expected output:
```
=== Testing Slurm App Manager ===
Session ID: test-session-001
App ID: gedit
VNC Port: 6080

Submitting Slurm job...
✅ Job submitted successfully!
   Job ID: 12345
   Status: PENDING

Waiting for job to start (max 30 seconds)...
   [5s] Status: RUNNING on viz-node001

✅ Job is RUNNING!
   Node: viz-node001
   Node IP: 192.168.122.252
   VNC URL: ws://192.168.122.252:6080

Cancelling job...
✅ Job cancelled successfully

=== Test Complete ===
```

### End-to-End Test
1. Start backend server (once KooCAE.so issue is resolved)
2. Start frontend: `npm run dev`
3. Navigate to app launcher
4. Click "Launch GEdit"
5. Wait for session status to change to `running`
6. noVNC should display XFCE desktop with GEdit

## Files Modified/Created

### Created
- `/dashboard/kooCAEWebServer_5000/services/slurm_app_manager.py` - Slurm job manager
- `/dashboard/app_5174/slurm_jobs/gedit_vnc_job.sh` - Job script template
- `/dashboard/app_5174/deploy_app_images.sh` - Image deployment script
- `/dashboard/kooCAEWebServer_5000/test_slurm_integration.py` - Test script
- `/dashboard/app_5174/docs/PHASE4_SLURM_INTEGRATION_COMPLETE.md` - This document

### Modified
- `/dashboard/kooCAEWebServer_5000/services/app_session_service.py`
  - Replaced `ApptainerManager` → `SlurmAppManager`
  - Updated `_start_real_session()` to submit Slurm jobs
  - Added `_monitor_job_for_session()` for status tracking
  - Updated `delete_session()` and `restart_session()`

## Known Issues

### 1. Backend Server Won't Start
**Error**: `ImportError: undefined symbol: PyThreadState_GetUnchecked`

**Cause**: KooCAE.so C extension incompatibility

**Workaround**: Test using standalone test script

**Solution**: Rebuild KooCAE.so or use proper Python version/environment

### 2. Slurm Controller Not Running
**Error**: `slurm_load_partitions: Unable to contact slurm controller`

**Cause**: Slurm services not started

**Solution**: Start Slurm controller and slurmd daemons

## Next Steps

1. **Fix Backend Dependencies**
   - Resolve KooCAE.so import issue
   - Ensure Flask server can start

2. **Test End-to-End**
   - Submit real Slurm job
   - Verify container starts on viz node
   - Test noVNC connection from browser

3. **Add More Apps**
   - Create additional app definitions (ParaView, LS-PrePost, etc.)
   - Build and deploy more Apptainer images
   - Create corresponding Slurm job templates

4. **Implement WebSocket Updates**
   - Real-time session status updates via WebSocket
   - Eliminate need for polling

5. **Error Handling**
   - Handle Slurm queue wait times
   - Display meaningful errors to users
   - Implement retry logic

6. **Security**
   - Validate user permissions for app access
   - Implement resource quotas
   - Audit job submissions

## Progress Summary

- **Phase 1**: Mock UI/UX (COMPLETE)
- **Phase 2**: Real noVNC Integration (COMPLETE)
- **Phase 3**: Apptainer Container Build (COMPLETE)
- **Phase 4**: Slurm Integration (COMPLETE) ← **Current**
- **Phase 5**: End-to-End Testing (PENDING)
- **Phase 6**: Production Deployment (PENDING)

## Conclusion

The app framework now properly integrates with Slurm to execute containers on visualization nodes, avoiding resource conflicts on the access node. This follows the same pattern as the existing VNC service and enables scalable, multi-user app sessions.

All core functionality is implemented. Next step is end-to-end testing once the backend server dependency issues are resolved.
