#!/bin/bash
################################################################################
# Offline Package Installation Script (Local APT Repository Method)
# Target: Ubuntu 24.04 (Noble Numbat)
#
# This script uses apt instead of dpkg to install packages.
# apt automatically resolves dependencies, making it safer than dpkg.
#
# Usage:
#   sudo ./install_offline_packages.sh [PACKAGE...]
#
# Examples:
#   sudo ./install_offline_packages.sh                # Install all packages
#   sudo ./install_offline_packages.sh nginx nodejs   # Install specific packages
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_NAME="offline-local"
REPO_LIST="/etc/apt/sources.list.d/${REPO_NAME}.list"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Root privilege check
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (sudo)"
    exit 1
fi

echo ""
echo "================================================================"
echo "   Offline Package Installation (APT Repository Method)"
echo "   Target OS: Ubuntu 24.04 (Noble Numbat)"
echo "================================================================"
echo ""

log_info "Package directory: $SCRIPT_DIR"

# Count .deb files
DEB_COUNT=$(find "$SCRIPT_DIR" -name "*.deb" | wc -l)
log_info "Found $DEB_COUNT .deb files"

if [[ $DEB_COUNT -eq 0 ]]; then
    log_error "No .deb files found in $SCRIPT_DIR"
    exit 1
fi

# Check for Packages.gz (create if missing)
if [[ ! -f "$SCRIPT_DIR/Packages.gz" ]]; then
    log_warning "Packages.gz not found. Creating repository index..."

    if ! command -v dpkg-scanpackages &> /dev/null; then
        log_info "Installing dpkg-dev for dpkg-scanpackages..."
        # Check if dpkg-dev is available locally
        if ls "$SCRIPT_DIR"/dpkg-dev*.deb &>/dev/null; then
            dpkg -i "$SCRIPT_DIR"/dpkg-dev*.deb 2>/dev/null || apt-get install -f -y
        else
            log_error "dpkg-dev not found. Please ensure dpkg-dev is in the package collection."
            exit 1
        fi
    fi

    cd "$SCRIPT_DIR"
    dpkg-scanpackages . /dev/null > Packages
    gzip -k -f Packages
    cd - > /dev/null
    log_success "Repository index created"
fi

echo ""
log_info "Step 1: Setting up local APT repository..."

# Backup existing sources.list
if [[ -f /etc/apt/sources.list ]]; then
    if [[ ! -f /etc/apt/sources.list.backup-offline ]]; then
        cp /etc/apt/sources.list /etc/apt/sources.list.backup-offline
        log_info "  Backed up /etc/apt/sources.list"
    fi
fi

# Add local repository
echo "deb [trusted=yes] file://$SCRIPT_DIR ./" > "$REPO_LIST"
log_success "  Local repository configured: $REPO_LIST"

echo ""
log_info "Step 2: Updating APT cache..."
apt-get update -o Dir::Etc::sourcelist="$REPO_LIST" \
               -o Dir::Etc::sourceparts="-" \
               -o APT::Get::List-Cleanup="0" 2>/dev/null || apt-get update

log_success "  APT cache updated"

echo ""
log_info "Step 3: Installing packages..."

# Check if specific packages are specified
if [[ $# -gt 0 ]]; then
    # Install only specified packages
    PACKAGES_TO_INSTALL=("$@")
    log_info "  Installing specified packages: ${PACKAGES_TO_INSTALL[*]}"
else
    # Install all packages (using package_list.txt)
    if [[ -f "$SCRIPT_DIR/package_list.txt" ]]; then
        # Extract package names from .deb filenames
        PACKAGES_TO_INSTALL=()
        while IFS= read -r deb_file; do
            # Extract package name from filename (name_version_architecture.deb)
            pkg_name=$(echo "$deb_file" | sed 's/_.*$//')
            PACKAGES_TO_INSTALL+=("$pkg_name")
        done < "$SCRIPT_DIR/package_list.txt"
        log_info "  Installing all ${#PACKAGES_TO_INSTALL[@]} packages from package_list.txt"
    else
        log_error "No package list found and no packages specified"
        log_info "Usage: $0 [PACKAGE...]"
        exit 1
    fi
fi

# Remove duplicates
PACKAGES_TO_INSTALL=($(printf '%s\n' "${PACKAGES_TO_INSTALL[@]}" | sort -u))

# Run apt install (automatic dependency resolution)
log_info "  Running: apt-get install -y ${#PACKAGES_TO_INSTALL[@]} packages..."
apt-get install -y --no-install-recommends "${PACKAGES_TO_INSTALL[@]}" 2>&1 || {
    log_warning "Some packages may have failed. Retrying with -f flag..."
    apt-get install -f -y
}

echo ""
log_info "Step 4: Cleanup..."

# Keep local repository configuration (allows installing additional packages later)
# To remove, uncomment below:
# rm -f "$REPO_LIST"
# apt-get update

log_info "  Local repository kept at: $REPO_LIST"
log_info "  To remove: sudo rm $REPO_LIST && sudo apt-get update"

echo ""
echo "================================================================"
echo "   Offline Package Installation Complete!"
echo "   Ubuntu 24.04 (Noble Numbat)"
echo "================================================================"
echo ""
log_info "Installed packages summary:"
echo "  Total installed: $(dpkg -l | grep "^ii" | wc -l)"
echo ""
log_info "Tips:"
echo "  - To restore online repos: sudo mv /etc/apt/sources.list.backup-offline /etc/apt/sources.list"
echo "  - To install more packages: sudo apt-get install <package-name>"
echo "  - Repository will use local .deb files first"
echo ""
