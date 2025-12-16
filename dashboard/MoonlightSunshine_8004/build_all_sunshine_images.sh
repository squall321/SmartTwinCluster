#!/bin/bash

# ==============================================================================
# Sunshine Apptainer Images Builder
# ==============================================================================
# 목적: 기존 VNC 이미지를 기반으로 Sunshine 이미지 생성
# 실행 위치: viz-node001 (GPU가 있는 노드)
# 권한: sudo 필요
# ==============================================================================

set -e  # Exit on error

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BASE_DIR="/opt/apptainers"
SUNSHINE_VERSION="v0.23.1"
SUNSHINE_URL="https://github.com/LizardByte/Sunshine/releases/download/${SUNSHINE_VERSION}/sunshine-ubuntu-22.04-amd64.deb"
TMP_DIR="/tmp/sunshine_build_$$"

# VNC → Sunshine 이미지 매핑
declare -A IMAGE_MAP=(
    ["vnc_desktop.sif"]="sunshine_desktop.sif:XFCE4 Desktop"
    ["vnc_gnome.sif"]="sunshine_gnome.sif:GNOME Desktop"
    ["vnc_gnome_lsprepost.sif"]="sunshine_gnome_lsprepost.sif:GNOME + LS-PrePost"
)

# ==============================================================================
# Helper Functions
# ==============================================================================

print_header() {
    echo ""
    echo -e "${BLUE}======================================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}======================================================================${NC}"
}

print_step() {
    echo -e "${GREEN}➜ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ ERROR: $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warn() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# ==============================================================================
# Pre-flight Checks
# ==============================================================================

print_header "Pre-flight Checks"

# Check if running on viz-node
if ! hostname | grep -q "viz-node"; then
    print_error "This script must run on viz-node (GPU node)!"
    echo "Current host: $(hostname)"
    exit 1
fi
print_success "Running on viz-node: $(hostname)"

# Check sudo
if [ "$EUID" -ne 0 ]; then
    print_error "This script must be run with sudo!"
    echo "Usage: sudo $0"
    exit 1
fi
print_success "Running with sudo"

# Check apptainer
if ! command -v apptainer &> /dev/null; then
    print_error "Apptainer is not installed!"
    exit 1
fi
print_success "Apptainer found: $(apptainer --version)"

# Check NVIDIA GPU
if ! nvidia-smi &> /dev/null; then
    print_warn "NVIDIA GPU not detected (nvidia-smi failed)"
    print_warn "Sunshine may not have NVENC support!"
else
    print_success "NVIDIA GPU detected"
    nvidia-smi --query-gpu=name --format=csv,noheader | while read -r gpu; do
        echo "   GPU: $gpu"
    done
fi

# Check base directory
if [ ! -d "$BASE_DIR" ]; then
    print_error "Base directory not found: $BASE_DIR"
    exit 1
fi
print_success "Base directory exists: $BASE_DIR"

# Check VNC images
print_step "Checking VNC source images..."
missing_count=0
for vnc_image in "${!IMAGE_MAP[@]}"; do
    if [ -f "$BASE_DIR/$vnc_image" ]; then
        size=$(du -h "$BASE_DIR/$vnc_image" | cut -f1)
        echo "   ✓ $vnc_image ($size)"
    else
        echo "   ✗ $vnc_image (NOT FOUND)"
        ((missing_count++))
    fi
done

if [ $missing_count -gt 0 ]; then
    print_error "$missing_count VNC images missing!"
    exit 1
fi

# Create temp directory
mkdir -p "$TMP_DIR"
print_success "Temporary directory created: $TMP_DIR"

echo ""
read -p "Continue with Sunshine image build? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warn "Build cancelled by user"
    rm -rf "$TMP_DIR"
    exit 0
fi

# ==============================================================================
# Build Images
# ==============================================================================

total_images=${#IMAGE_MAP[@]}
current=0
success_count=0
fail_count=0

for vnc_image in "${!IMAGE_MAP[@]}"; do
    ((current++))
    IFS=':' read -r sunshine_image description <<< "${IMAGE_MAP[$vnc_image]}"

    print_header "[$current/$total_images] Building: $sunshine_image"
    echo "Description: $description"
    echo "Source: $vnc_image"
    echo ""

    # Check if sunshine image already exists
    if [ -f "$BASE_DIR/$sunshine_image" ]; then
        print_warn "Sunshine image already exists: $sunshine_image"
        read -p "Overwrite? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_warn "Skipping $sunshine_image"
            continue
        fi
        # Backup existing
        backup_name="${sunshine_image}.backup_$(date +%Y%m%d_%H%M%S)"
        print_step "Backing up existing image to $backup_name"
        cp "$BASE_DIR/$sunshine_image" "$BASE_DIR/$backup_name"
    fi

    # Step 1: Build sandbox
    sandbox_dir="$TMP_DIR/sandbox_${sunshine_image%.sif}"
    print_step "Step 1/6: Building sandbox from $vnc_image..."
    if apptainer build --sandbox "$sandbox_dir" "$BASE_DIR/$vnc_image" 2>&1 | tee "$TMP_DIR/build_${sunshine_image}.log"; then
        print_success "Sandbox created"
    else
        print_error "Failed to create sandbox"
        ((fail_count++))
        continue
    fi

    # Step 2: Install Sunshine
    print_step "Step 2/6: Installing Sunshine $SUNSHINE_VERSION..."
    if apptainer exec --writable "$sandbox_dir" /bin/bash << EOF
set -e
export DEBIAN_FRONTEND=noninteractive

# Download Sunshine
echo "Downloading Sunshine..."
wget -q -O /tmp/sunshine.deb "$SUNSHINE_URL"

# Install
echo "Installing Sunshine..."
apt-get update -qq
apt-get install -y /tmp/sunshine.deb 2>&1 | grep -v "^Get:" | grep -v "^Fetched"

# Cleanup
rm /tmp/sunshine.deb

# Create config directory
mkdir -p /root/.config/sunshine

# Verify
echo "Verifying Sunshine installation..."
sunshine --version

echo "Sunshine installed successfully!"
EOF
    then
        print_success "Sunshine installed"
    else
        print_error "Failed to install Sunshine"
        rm -rf "$sandbox_dir"
        ((fail_count++))
        continue
    fi

    # Step 3: Verify installation
    print_step "Step 3/6: Verifying Sunshine installation..."
    sunshine_version=$(apptainer exec "$sandbox_dir" sunshine --version 2>&1 | head -1)
    if [ -n "$sunshine_version" ]; then
        print_success "Sunshine version: $sunshine_version"
    else
        print_error "Sunshine verification failed"
        rm -rf "$sandbox_dir"
        ((fail_count++))
        continue
    fi

    # Step 4: Build SIF
    print_step "Step 4/6: Building SIF image..."
    if apptainer build "$BASE_DIR/$sunshine_image" "$sandbox_dir" 2>&1 | tee -a "$TMP_DIR/build_${sunshine_image}.log"; then
        print_success "SIF image created"
    else
        print_error "Failed to build SIF image"
        rm -rf "$sandbox_dir"
        ((fail_count++))
        continue
    fi

    # Step 5: Set permissions
    print_step "Step 5/6: Setting permissions..."
    chmod 755 "$BASE_DIR/$sunshine_image"
    chown root:root "$BASE_DIR/$sunshine_image"
    print_success "Permissions set (755, root:root)"

    # Step 6: Cleanup sandbox
    print_step "Step 6/6: Cleaning up sandbox..."
    rm -rf "$sandbox_dir"
    print_success "Sandbox cleaned up"

    # Final verification
    echo ""
    print_success "Image built successfully: $sunshine_image"
    echo "   Size: $(du -h "$BASE_DIR/$sunshine_image" | cut -f1)"
    echo "   Sunshine: $(apptainer exec "$BASE_DIR/$sunshine_image" sunshine --version 2>&1 | head -1)"

    ((success_count++))
done

# ==============================================================================
# Summary
# ==============================================================================

print_header "Build Summary"

echo ""
echo "Total images: $total_images"
echo -e "${GREEN}Succeeded: $success_count${NC}"
echo -e "${RED}Failed: $fail_count${NC}"
echo ""

if [ $success_count -gt 0 ]; then
    print_step "Built Sunshine images:"
    ls -lh "$BASE_DIR"/sunshine_*.sif | awk '{print "   " $9, "(" $5 ")"}'
fi

echo ""
print_step "VNC images (original, should be unchanged):"
ls -lh "$BASE_DIR"/vnc_*.sif | awk '{print "   " $9, "(" $5 ")"}'

# Cleanup temp directory
echo ""
print_step "Cleaning up temporary directory..."
rm -rf "$TMP_DIR"
print_success "Cleanup complete"

echo ""
if [ $fail_count -eq 0 ]; then
    print_header "✓ All images built successfully!"
    exit 0
else
    print_header "⚠ Some images failed to build"
    echo "Check logs in $BASE_DIR/*.log for details"
    exit 1
fi
