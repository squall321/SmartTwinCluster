#!/bin/bash

# ========================================================================
# Sunshine Apptainer Images Build Script
# ========================================================================
# Purpose: Build all 3 Sunshine Apptainer images from-scratch
# Usage: sudo bash build_sunshine_images.sh
# Location: viz-node (NVIDIA GPU required)
# ========================================================================

set -e  # Exit on error

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
OUTPUT_DIR="/opt/apptainers"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 동적 IP 감지
YAML_PATH="${SCRIPT_DIR}/../../my_multihead_cluster.yaml"
if [ -f "$YAML_PATH" ]; then
    EXTERNAL_IP=$(python3 -c "import yaml; config=yaml.safe_load(open('$YAML_PATH')); print(config.get('network', {}).get('vip', {}).get('address', '') or config.get('web', {}).get('public_url', 'localhost'))" 2>/dev/null)
fi
if [ -z "$EXTERNAL_IP" ] || [ "$EXTERNAL_IP" = "localhost" ]; then
    EXTERNAL_IP=$(hostname -I | awk '{print $1}')
fi

# Image definitions
declare -A IMAGES=(
    ["sunshine_desktop.def"]="sunshine_desktop.sif:XFCE4 Desktop:~600MB"
    ["sunshine_gnome.def"]="sunshine_gnome.sif:GNOME Desktop:~900MB"
    ["sunshine_gnome_lsprepost.def"]="sunshine_gnome_lsprepost.sif:GNOME + LS-PrePost:~950MB"
)

# ========================================================================
# Helper Functions
# ========================================================================

print_header() {
    echo ""
    echo -e "${BLUE}=========================================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}=========================================================================${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# ========================================================================
# Pre-flight Checks
# ========================================================================

print_header "Pre-flight Checks"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run as root (sudo)"
    exit 1
fi

print_success "Running as root"

# Check if apptainer is installed
if ! command -v apptainer &> /dev/null; then
    print_error "Apptainer is not installed"
    exit 1
fi

print_success "Apptainer is installed: $(apptainer --version)"

# Check if NVIDIA GPU is available
if ! nvidia-smi &> /dev/null; then
    print_error "NVIDIA GPU not detected (nvidia-smi failed)"
    print_warning "You must run this script on a node with NVIDIA GPU (viz-node)"
    exit 1
fi

print_success "NVIDIA GPU detected:"
nvidia-smi --query-gpu=name,driver_version --format=csv,noheader

# Check if definition files exist
missing_files=0
for def_file in "${!IMAGES[@]}"; do
    if [ ! -f "$SCRIPT_DIR/$def_file" ]; then
        print_error "Definition file not found: $def_file"
        ((missing_files++))
    fi
done

if [ $missing_files -gt 0 ]; then
    print_error "$missing_files definition file(s) missing"
    exit 1
fi

print_success "All definition files found"

# Check output directory
if [ ! -d "$OUTPUT_DIR" ]; then
    print_warning "Output directory does not exist: $OUTPUT_DIR"
    print_info "Creating output directory..."
    mkdir -p "$OUTPUT_DIR"
fi

print_success "Output directory: $OUTPUT_DIR"

# Check disk space
available_space=$(df -BG "$OUTPUT_DIR" | awk 'NR==2 {print $4}' | sed 's/G//')
required_space=5  # GB

if [ "$available_space" -lt "$required_space" ]; then
    print_error "Insufficient disk space: ${available_space}GB available, ${required_space}GB required"
    exit 1
fi

print_success "Sufficient disk space: ${available_space}GB available"

# ========================================================================
# Build Images
# ========================================================================

print_header "Building Sunshine Images"

total_images=${#IMAGES[@]}
current=0

for def_file in "${!IMAGES[@]}"; do
    ((current++))

    IFS=':' read -r output_sif description size <<< "${IMAGES[$def_file]}"

    print_header "[$current/$total_images] Building $description ($size)"

    print_info "Definition: $def_file"
    print_info "Output: $OUTPUT_DIR/$output_sif"
    print_info "Estimated size: $size"

    # Check if image already exists
    if [ -f "$OUTPUT_DIR/$output_sif" ]; then
        print_warning "Image already exists: $output_sif"
        read -p "Overwrite? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Skipping $output_sif"
            continue
        fi
        print_info "Removing existing image..."
        rm -f "$OUTPUT_DIR/$output_sif"
    fi

    # Build image
    print_info "Starting build... (this may take 20-40 minutes)"

    start_time=$(date +%s)

    if apptainer build "$OUTPUT_DIR/$output_sif" "$SCRIPT_DIR/$def_file"; then
        end_time=$(date +%s)
        duration=$((end_time - start_time))

        # Get actual file size
        actual_size=$(du -h "$OUTPUT_DIR/$output_sif" | cut -f1)

        print_success "Build completed in $((duration / 60))m $((duration % 60))s"
        print_success "Image size: $actual_size"

        # Set permissions
        chmod 755 "$OUTPUT_DIR/$output_sif"
        chown root:root "$OUTPUT_DIR/$output_sif"

        print_success "Permissions set: 755, root:root"

        # Verify image
        print_info "Verifying image..."
        if apptainer inspect "$OUTPUT_DIR/$output_sif" > /dev/null 2>&1; then
            print_success "Image verification passed"
        else
            print_error "Image verification failed"
            continue
        fi

        # Test GPU access
        print_info "Testing GPU access..."
        if apptainer exec --nv "$OUTPUT_DIR/$output_sif" nvidia-smi > /dev/null 2>&1; then
            print_success "GPU access test passed"
        else
            print_warning "GPU access test failed (may work at runtime)"
        fi

        # Test Sunshine installation
        print_info "Testing Sunshine installation..."
        if apptainer exec "$OUTPUT_DIR/$output_sif" sunshine --version > /dev/null 2>&1; then
            version=$(apptainer exec "$OUTPUT_DIR/$output_sif" sunshine --version 2>&1 | head -1)
            print_success "Sunshine test passed: $version"
        else
            print_warning "Sunshine test failed"
        fi

    else
        print_error "Build failed for $output_sif"
        print_error "Check the build log above for details"
        continue
    fi

    echo ""
done

# ========================================================================
# Final Summary
# ========================================================================

print_header "Build Summary"

echo ""
print_info "Images in $OUTPUT_DIR:"
ls -lh "$OUTPUT_DIR"/sunshine_*.sif 2>/dev/null || print_warning "No Sunshine images found"

echo ""
print_info "Verification:"
for def_file in "${!IMAGES[@]}"; do
    IFS=':' read -r output_sif description size <<< "${IMAGES[$def_file]}"

    if [ -f "$OUTPUT_DIR/$output_sif" ]; then
        actual_size=$(du -h "$OUTPUT_DIR/$output_sif" | cut -f1)
        print_success "$output_sif ($actual_size)"
    else
        print_error "$output_sif (missing)"
    fi
done

echo ""
print_header "Next Steps"

echo ""
echo "1. Verify images are accessible from controller:"
echo "   ls -lh /opt/apptainers/sunshine_*.sif"
echo ""
echo "2. Create Slurm QoS:"
echo "   sudo sacctmgr add qos moonlight"
echo "   sudo sacctmgr modify qos moonlight set GraceTime=60 MaxWall=8:00:00 MaxTRESPerUser=gpu=2"
echo ""
echo "3. Update Nginx configuration (on controller):"
echo "   sudo vi /etc/nginx/conf.d/auth-portal.conf"
echo "   # Add Moonlight routes from nginx_config_addition.conf"
echo ""
echo "4. Test session creation:"
echo "   curl -X POST -k https://${EXTERNAL_IP}/api/moonlight/sessions \\"
echo "        -H 'Content-Type: application/json' \\"
echo "        -H 'X-Username: testuser' \\"
echo "        -d '{\"image_id\": \"desktop\"}'"
echo ""

print_success "Build script completed!"
