# Apptainer Registry System - Changes Summary

## Overview

Refactored the Apptainer image management system to use a **central registry pattern** instead of SSH-based node scanning. This ensures that only real, existing images are displayed and used in the dashboard.

## Key Changes

### 1. Central Registry Infrastructure

Created `/shared/apptainer/` directory structure:

```
/shared/apptainer/
├── images/           # Actual .sif image files
│   ├── compute/     # Compute partition images
│   ├── viz/         # Visualization partition images
│   └── shared/      # Common images
├── metadata/        # Image metadata (JSON)
└── scripts/         # Management scripts
    ├── sync_to_nodes.sh       # Sync images to compute nodes
    ├── verify_image.sh        # Verify image integrity
    └── build_sample_images.sh # Build test images
```

**Setup Script**: [dashboard/setup_apptainer_registry.sh](dashboard/setup_apptainer_registry.sh)

### 2. New Backend Service: ApptainerRegistryService

**File**: [dashboard/backend_5010/apptainer_service_v2.py](backend_5010/apptainer_service_v2.py)

**Key Features**:
- Scans local filesystem (`/shared/apptainer/images/`) instead of SSH to nodes
- Extracts metadata using `apptainer inspect` commands
- Supports partition-based organization (compute, viz, shared)
- Stores metadata in SQLite database
- Only shows images that actually exist

**Architecture Changes**:
```python
# OLD: SSH to each node
for node in compute_nodes:
    ssh_execute(node, "ls /opt/apptainers/*.sif")

# NEW: Local filesystem scan
for partition in ['compute', 'viz', 'shared']:
    scan_partition_images(partition)
```

### 3. Updated API Endpoints

**File**: [dashboard/backend_5010/apptainer_api.py](backend_5010/apptainer_api.py)

**Modified Endpoints**:
- `POST /api/apptainer/scan` - Now scans central registry by partition
- `GET /api/apptainer/images` - Returns images from registry
- `GET /api/apptainer/validate/<image_id>` - Checks local file existence

**New API Behavior**:
```bash
# Scan central registry
curl -X POST http://localhost:5010/api/apptainer/scan \
  -H "Content-Type: application/json" \
  -d '{"partitions": ["compute", "viz", "shared"]}'

# Response:
{
  "message": "Scan completed",
  "stats": {
    "compute": 2,
    "viz": 0,
    "shared": 0
  }
}
```

### 4. Template Validation Endpoint

**File**: [dashboard/backend_5010/templates_api_v2.py](backend_5010/templates_api_v2.py)

**New Endpoint**: `GET /api/v2/templates/<template_id>/validate`

**Purpose**: Check if a template's referenced Apptainer image exists in the registry

**Example**:
```bash
curl -X GET http://localhost:5010/api/v2/templates/openfoam-cfd-v1/validate

# Response (image exists):
{
  "template_id": "openfoam-cfd-v1",
  "valid": true,
  "image_name": "openfoam_v2312.sif",
  "image_exists": true,
  "image_path": "/opt/apptainers/openfoam_v2312.sif",
  "image_partition": "compute",
  "message": "Image \"openfoam_v2312.sif\" is available in compute partition"
}

# Response (image missing):
{
  "template_id": "some-template",
  "valid": false,
  "image_name": "missing_image.sif",
  "image_exists": false,
  "message": "Image \"missing_image.sif\" not found in registry",
  "available_images": ["alpine_latest.sif", "python_3.11.sif", ...]
}
```

## Sample Images Created

Created two test images in `/shared/apptainer/images/compute/`:

1. **alpine_latest.sif** (3.6 MB)
   - Minimal Alpine Linux container
   - ID: `alpine_latest`
   - Type: compute

2. **python_3.11.sif** (43 MB)
   - Python 3.11 slim environment
   - ID: `python_3.11`
   - Type: compute
   - Version: 3.11

## Database Schema

No changes to the existing `apptainer_images` table schema. The service continues to use the same table structure but with different data sources.

## Node Distribution Strategy (Future)

The central registry pattern supports multi-node distribution:

1. **Headnode**: Stores master copies in `/shared/apptainer/images/`
2. **Compute Nodes**: Pull images to local cache `/scratch/apptainer/`
3. **Sync Script**: `/shared/apptainer/scripts/sync_to_nodes.sh`

```bash
# Sync image to compute nodes
/shared/apptainer/scripts/sync_to_nodes.sh python_3.11.sif compute
```

## Multi-Headnode Redundancy (Future)

For HA architecture:
- Use shared storage (NFS, CephFS) for `/shared/apptainer/`
- Multiple headnodes access the same registry
- Metadata stored in distributed database (Redis Cluster, PostgreSQL)

## Migration Path

### Current State
- Old dummy data still in database (compute001, compute002, viz001, viz002)
- New real images added (alpine_latest, python_3.11)

### Next Steps
1. Build all required production images (OpenFOAM, GROMACS, ParaView, etc.)
2. Run full registry scan: `POST /api/apptainer/scan`
3. Update templates to reference real image names
4. Remove old dummy data from database
5. Deploy to production

## Testing

### 1. Verify Registry Scan
```bash
# Scan registry
curl -X POST http://localhost:5010/api/apptainer/scan \
  -H "Content-Type: application/json" \
  -d '{"partitions": ["compute", "viz", "shared"]}'

# Check results
curl http://localhost:5010/api/apptainer/images?partition=compute
```

### 2. Validate Template
```bash
# Check if template's image exists
curl http://localhost:5010/api/v2/templates/openfoam-cfd-v1/validate
```

### 3. Check Image Metadata
```bash
# Get image details
curl http://localhost:5010/api/apptainer/images/alpine_latest/metadata
```

## Files Modified

1. ✅ **dashboard/setup_apptainer_registry.sh** - Registry setup script
2. ✅ **dashboard/backend_5010/apptainer_service_v2.py** - New registry service
3. ✅ **dashboard/backend_5010/apptainer_api.py** - Updated to use v2 service
4. ✅ **dashboard/backend_5010/templates_api_v2.py** - Added validation endpoint
5. ✅ **/shared/apptainer/scripts/build_test_images.sh** - Sample image builder
6. ✅ **/shared/apptainer/scripts/sync_to_nodes.sh** - Node sync script
7. ✅ **/shared/apptainer/scripts/verify_image.sh** - Image verification

## Benefits

1. **No SSH Required**: Scans local filesystem, faster and more reliable
2. **Real Images Only**: Only displays images that actually exist
3. **Partition Support**: Organized by compute/viz/shared
4. **Template Validation**: Can check if image exists before job submit
5. **Scalable**: Central registry supports multi-node distribution
6. **HA Ready**: Supports multi-headnode redundancy architecture

## Known Issues

None at this time. System is ready for production image deployment.

## Next Phase

**Phase 2: Production Image Deployment**
1. Build production Apptainer images:
   - OpenFOAM v2312
   - GROMACS
   - LAMMPS
   - ParaView + VNC
   - PyTorch + CUDA
2. Update all templates to reference real images
3. Deploy to compute nodes
4. Enable template validation in frontend

---

**Date**: 2025-11-06
**Author**: Claude
**Status**: ✅ Completed
