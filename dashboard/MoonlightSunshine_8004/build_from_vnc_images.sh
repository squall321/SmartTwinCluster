#!/bin/bash

# ========================================================================
# Build Sunshine Images from Existing VNC Images
# ========================================================================
# Purpose: Add Sunshine to existing VNC images (재사용 방식)
# Usage: bash build_from_vnc_images.sh
# ========================================================================

set -e  # Exit on error

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
VNC_IMAGES_DIR="/home/koopark/claude/KooSlurmInstallAutomationRefactory/apptainer/viz-node-images"
OUTPUT_DIR="/opt/apptainers"
TMP_DIR="/tmp/sunshine_build_$$"

# Image mapping: VNC → Sunshine
declare -A IMAGE_MAP=(
    ["vnc_desktop.sif"]="sunshine_desktop.sif:XFCE4 Desktop"
    ["vnc_gnome.sif"]="sunshine_gnome.sif:GNOME Desktop"
    ["vnc_gnome_lsprepost.sif"]="sunshine_gnome_lsprepost.sif:GNOME + LS-PrePost"
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

# Check if apptainer is installed
if ! command -v apptainer &> /dev/null; then
    print_error "Apptainer is not installed"
    exit 1
fi

print_success "Apptainer: $(apptainer --version)"

# Check VNC images
for vnc_sif in "${!IMAGE_MAP[@]}"; do
    if [ ! -f "$VNC_IMAGES_DIR/$vnc_sif" ]; then
        print_error "VNC image not found: $VNC_IMAGES_DIR/$vnc_sif"
        exit 1
    fi
    size=$(du -h "$VNC_IMAGES_DIR/$vnc_sif" | cut -f1)
    print_success "Found $vnc_sif ($size)"
done

# Create temp directory
mkdir -p "$TMP_DIR"
print_success "Temp directory: $TMP_DIR"

# ========================================================================
# Build Images
# ========================================================================

print_header "Building Sunshine Images from VNC Images"

total=${#IMAGE_MAP[@]}
current=0

for vnc_sif in "${!IMAGE_MAP[@]}"; do
    ((current++))

    IFS=':' read -r sunshine_sif description <<< "${IMAGE_MAP[$vnc_sif]}"

    print_header "[$current/$total] Building $description"

    print_info "Source: $VNC_IMAGES_DIR/$vnc_sif"
    print_info "Output: $OUTPUT_DIR/$sunshine_sif"

    # Create sandbox from VNC image
    SANDBOX="$TMP_DIR/sandbox_${sunshine_sif%.sif}"

    print_info "Step 1: Creating sandbox from VNC image..."
    if [ -d "$SANDBOX" ]; then
        rm -rf "$SANDBOX"
    fi

    apptainer build --sandbox "$SANDBOX" "$VNC_IMAGES_DIR/$vnc_sif"
    print_success "Sandbox created"

    # Install Sunshine into sandbox
    print_info "Step 2: Installing Sunshine..."

    apptainer exec --writable "$SANDBOX" /bin/bash <<'INSTALL_SUNSHINE'
#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive

# Update package list
apt-get update

# Install Sunshine dependencies
apt-get install -y \
    wget \
    libssl3 \
    libavcodec58 \
    libavformat58 \
    libavutil56 \
    libswscale5 \
    libboost-filesystem1.74.0 \
    libboost-log1.74.0 \
    libboost-program-options1.74.0 \
    libboost-thread1.74.0 \
    libpulse0 \
    libopus0 \
    libevdev2 \
    libxtst6 \
    libx11-6 \
    libxrandr2 \
    libxfixes3 \
    libdrm2 \
    libwayland-client0 \
    libnuma1 \
    libcap2

# Download and install Sunshine
SUNSHINE_VERSION="0.23.1"
wget -O /tmp/sunshine.deb \
    https://github.com/LizardByte/Sunshine/releases/download/v${SUNSHINE_VERSION}/sunshine-ubuntu-22.04-amd64.deb

apt-get install -y /tmp/sunshine.deb || {
    echo "Trying with --fix-broken..."
    apt-get install -f -y
    dpkg -i /tmp/sunshine.deb
}

rm /tmp/sunshine.deb

# Verify installation
if ! command -v sunshine &> /dev/null; then
    echo "ERROR: Sunshine installation failed!"
    exit 1
fi

echo "Sunshine installed: $(sunshine --version 2>&1 | head -1)"

# Clean up
apt-get clean
rm -rf /var/lib/apt/lists/*

exit 0
INSTALL_SUNSHINE

    if [ $? -eq 0 ]; then
        print_success "Sunshine installed successfully"
    else
        print_error "Sunshine installation failed"
        rm -rf "$SANDBOX"
        continue
    fi

    # Build SIF from sandbox
    print_info "Step 3: Building SIF image..."

    if [ -f "$OUTPUT_DIR/$sunshine_sif" ]; then
        print_warning "Output image already exists"
        read -p "Overwrite? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Skipping $sunshine_sif"
            rm -rf "$SANDBOX"
            continue
        fi
        rm -f "$OUTPUT_DIR/$sunshine_sif"
    fi

    # Need sudo for building to /opt
    if [ -w "$OUTPUT_DIR" ]; then
        apptainer build "$OUTPUT_DIR/$sunshine_sif" "$SANDBOX"
    else
        print_info "Need sudo to write to $OUTPUT_DIR"
        sudo apptainer build "$OUTPUT_DIR/$sunshine_sif" "$SANDBOX"
    fi

    if [ $? -eq 0 ]; then
        actual_size=$(du -h "$OUTPUT_DIR/$sunshine_sif" | cut -f1)
        print_success "SIF built successfully ($actual_size)"

        # Set permissions
        sudo chmod 755 "$OUTPUT_DIR/$sunshine_sif" 2>/dev/null || chmod 755 "$OUTPUT_DIR/$sunshine_sif"
        print_success "Permissions set: 755"

        # Test image
        print_info "Testing image..."
        if apptainer exec "$OUTPUT_DIR/$sunshine_sif" sunshine --version > /dev/null 2>&1; then
            version=$(apptainer exec "$OUTPUT_DIR/$sunshine_sif" sunshine --version 2>&1 | head -1)
            print_success "Test passed: $version"
        else
            print_warning "Sunshine test failed"
        fi
    else
        print_error "SIF build failed"
    fi

    # Cleanup sandbox
    print_info "Cleaning up sandbox..."
    rm -rf "$SANDBOX"

    echo ""
done

# ========================================================================
# Cleanup
# ========================================================================

print_info "Cleaning up temporary directory..."
rm -rf "$TMP_DIR"

# ========================================================================
# Final Summary
# ========================================================================

print_header "Build Summary"

echo ""
print_info "Built images in $OUTPUT_DIR:"
ls -lh "$OUTPUT_DIR"/sunshine_*.sif 2>/dev/null || print_warning "No Sunshine images found"

echo ""
print_header "Comparison with VNC Images"

for vnc_sif in "${!IMAGE_MAP[@]}"; do
    IFS=':' read -r sunshine_sif description <<< "${IMAGE_MAP[$vnc_sif]}"

    vnc_size=$(du -h "$VNC_IMAGES_DIR/$vnc_sif" | cut -f1)
    if [ -f "$OUTPUT_DIR/$sunshine_sif" ]; then
        sunshine_size=$(du -h "$OUTPUT_DIR/$sunshine_sif" | cut -f1)
        print_success "$description: VNC=$vnc_size → Sunshine=$sunshine_size"
    else
        print_error "$description: Build failed"
    fi
done

echo ""
print_header "Next Steps"

echo ""
echo "1. Verify Sunshine images:"
echo "   apptainer exec sunshine_desktop.sif sunshine --version"
echo ""
echo "2. Test GPU access:"
echo "   apptainer exec --nv sunshine_desktop.sif nvidia-smi"
echo ""
echo "3. Create Slurm QoS:"
echo "   sudo sacctmgr add qos moonlight"
echo ""
echo "4. Start Moonlight backend:"
echo "   cd backend_moonlight_8004"
echo "   venv/bin/gunicorn -c gunicorn_config.py app:app"
echo ""

print_success "Build completed!"
