#!/bin/bash
################################################################################
# Storage API Production Mode Test
# DataManagement 기능의 Production 모드 동작 확인
################################################################################

BACKEND_URL="http://localhost:5010"

echo "================================================================================"
echo "🧪 Storage API Production Mode Test"
echo "================================================================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# Helper Functions
################################################################################

test_endpoint() {
    local name=$1
    local endpoint=$2
    local expected_mode=$3
    
    echo -e "${BLUE}Testing:${NC} $name"
    echo "  Endpoint: $endpoint"
    
    response=$(curl -s "${BACKEND_URL}${endpoint}")
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}  ✗ Failed to connect${NC}"
        return 1
    fi
    
    # Check if response contains 'success'
    if echo "$response" | jq -e '.success' > /dev/null 2>&1; then
        success=$(echo "$response" | jq -r '.success')
        mode=$(echo "$response" | jq -r '.mode // "unknown"')
        
        if [ "$success" = "true" ]; then
            if [ "$mode" = "$expected_mode" ]; then
                echo -e "${GREEN}  ✓ Success (Mode: $mode)${NC}"
                echo "$response" | jq '.' 2>/dev/null | head -20
                return 0
            else
                echo -e "${YELLOW}  ! Success but unexpected mode: $mode (expected: $expected_mode)${NC}"
                return 1
            fi
        else
            error=$(echo "$response" | jq -r '.error // "Unknown error"')
            echo -e "${RED}  ✗ Failed: $error${NC}"
            return 1
        fi
    else
        echo -e "${RED}  ✗ Invalid response format${NC}"
        echo "$response" | head -20
        return 1
    fi
}

################################################################################
# Pre-checks
################################################################################

echo "📋 Pre-checks"
echo "--------------------------------------------------------------------------------"

# Check if backend is running
if ! curl -s "${BACKEND_URL}/api/health" > /dev/null; then
    echo -e "${RED}❌ Backend is not running on $BACKEND_URL${NC}"
    echo ""
    echo "Start backend with:"
    echo "  ./start_production.sh"
    exit 1
fi

# Check backend mode
mode_check=$(curl -s "${BACKEND_URL}/api/health" | jq -r '.mode')
echo -e "Backend Mode: ${GREEN}$mode_check${NC}"

if [ "$mode_check" != "production" ]; then
    echo -e "${YELLOW}⚠️  Warning: Backend is running in '$mode_check' mode${NC}"
    echo "   Some tests may use mock data instead of real data"
fi

echo ""

################################################################################
# Test 1: Shared Storage Stats
################################################################################

echo "================================================================================"
echo "Test 1: Shared Storage Stats (/Data)"
echo "================================================================================"
echo ""

# Check if /Data directory exists
if [ ! -d "/Data" ]; then
    echo -e "${YELLOW}⚠️  /Data directory does not exist${NC}"
    echo "   Create it with: sudo mkdir -p /Data/datasets"
    echo ""
    echo "Test will continue with mock data..."
else
    echo -e "${GREEN}✓ /Data directory exists${NC}"
    du -sh /Data 2>/dev/null || echo "  Unable to calculate size"
fi

echo ""

test_endpoint "Shared Storage Stats" "/api/storage/data/stats" "production"

echo ""
echo ""

################################################################################
# Test 2: Datasets List
################################################################################

echo "================================================================================"
echo "Test 2: Datasets List"
echo "================================================================================"
echo ""

if [ -d "/Data/datasets" ]; then
    dataset_count=$(ls -1 /Data/datasets 2>/dev/null | wc -l)
    echo -e "${GREEN}✓ /Data/datasets exists${NC}"
    echo "  Found $dataset_count directories"
    ls -lh /Data/datasets 2>/dev/null | head -10
else
    echo -e "${YELLOW}⚠️  /Data/datasets does not exist${NC}"
    echo "   Create it with: sudo mkdir -p /Data/datasets"
fi

echo ""

test_endpoint "Datasets" "/api/storage/data/datasets" "production"

echo ""
echo ""

################################################################################
# Test 3: File Listing
################################################################################

echo "================================================================================"
echo "Test 3: File Listing"
echo "================================================================================"
echo ""

# Test listing /Data
test_path="/Data"
echo "Testing path: $test_path"
echo ""

test_endpoint "File List" "/api/storage/files?path=$(echo -n "$test_path" | jq -sRr @uri)&type=data" "production"

echo ""
echo ""

################################################################################
# Test 4: Scratch Nodes
################################################################################

echo "================================================================================"
echo "Test 4: Scratch Storage Nodes"
echo "================================================================================"
echo ""

# Check if Slurm is available
if command -v sinfo &> /dev/null; then
    echo -e "${GREEN}✓ Slurm commands available${NC}"
    node_count=$(sinfo -N -h | wc -l)
    echo "  Slurm reports $node_count nodes"
    sinfo -N | head -10
else
    echo -e "${YELLOW}⚠️  Slurm commands not available${NC}"
    echo "   Test will use mock data"
fi

echo ""

test_endpoint "Scratch Nodes" "/api/storage/scratch/nodes" "production"

echo ""
echo ""

################################################################################
# Test 5: File Search
################################################################################

echo "================================================================================"
echo "Test 5: File Search"
echo "================================================================================"
echo ""

search_query="data"
echo "Searching for: '$search_query'"
echo ""

test_endpoint "File Search" "/api/storage/search?q=$search_query&path=/Data&type=data&limit=10" "production"

echo ""
echo ""

################################################################################
# Summary
################################################################################

echo "================================================================================"
echo "📊 Test Summary"
echo "================================================================================"
echo ""

if [ "$mode_check" = "production" ]; then
    echo -e "${GREEN}✓ Backend is running in Production mode${NC}"
    echo ""
    echo "Required for full functionality:"
    echo "  1. /Data directory exists and is accessible"
    echo "  2. /Data/datasets directory for dataset management"
    echo "  3. SSH access to compute nodes for scratch management"
    echo "  4. Slurm commands available for node information"
    echo ""
    
    if [ ! -d "/Data" ]; then
        echo -e "${YELLOW}⚠️  Action Required:${NC}"
        echo "   sudo mkdir -p /Data/datasets"
        echo "   sudo chown $(whoami):$(whoami) /Data"
    else
        echo -e "${GREEN}✓ /Data directory ready${NC}"
    fi
    
    if ! command -v sinfo &> /dev/null; then
        echo -e "${YELLOW}⚠️  Action Required:${NC}"
        echo "   source /etc/profile.d/slurm.sh"
        echo "   or"
        echo "   export PATH=/usr/local/slurm/bin:\$PATH"
    else
        echo -e "${GREEN}✓ Slurm commands available${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  Backend is running in Mock mode${NC}"
    echo ""
    echo "To enable Production mode:"
    echo "  ./start_production.sh"
    echo ""
    echo "Or set environment variable:"
    echo "  export MOCK_MODE=false"
    echo "  cd backend && source venv/bin/activate && python app.py"
fi

echo ""
echo "================================================================================"
echo ""
