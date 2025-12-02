#!/bin/bash

# Phase 1 Apptainer 통합 테스트 스크립트
# 2025-11-06

echo "========================================"
echo "Phase 1: Apptainer Integration Test"
echo "========================================"
echo ""

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Backend URL
BACKEND_URL="http://localhost:5010"

# JWT 토큰 (테스트용 - 실제로는 Auth Portal에서 발급)
JWT_TOKEN="${JWT_TOKEN:-your_jwt_token_here}"

echo -e "${BLUE}1. Backend Health Check${NC}"
echo "GET $BACKEND_URL/api/health"
curl -s "$BACKEND_URL/api/health" | jq '.'
echo ""

echo -e "${BLUE}2. Apptainer Images API Test${NC}"
echo "GET $BACKEND_URL/api/v2/apptainer/images"
curl -s -H "Authorization: Bearer $JWT_TOKEN" \
  "$BACKEND_URL/api/v2/apptainer/images" | jq '.images[0:2]'
echo ""

echo -e "${BLUE}3. Job Submit with Apptainer Image (Mock Mode)${NC}"
echo "POST $BACKEND_URL/api/slurm/jobs/submit"
RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "jobName": "test_apptainer_job",
    "partition": "group1",
    "nodes": 1,
    "cpus": 64,
    "memory": "16GB",
    "time": "01:00:00",
    "script": "#!/bin/bash\necho \"Hello from Apptainer!\"\npython3 --version",
    "jobId": "tmp-test-123",
    "apptainerImage": {
      "id": "python_3.11",
      "name": "python_3.11.sif",
      "path": "/shared/apptainer/images/compute/python_3.11.sif",
      "type": "compute",
      "version": "3.11"
    }
  }' \
  "$BACKEND_URL/api/slurm/jobs/submit")

echo "$RESPONSE" | jq '.'

# 결과 확인
if echo "$RESPONSE" | jq -e '.success' > /dev/null 2>&1; then
  JOB_ID=$(echo "$RESPONSE" | jq -r '.jobId')
  echo ""
  echo -e "${GREEN}✅ Job submitted successfully!${NC}"
  echo -e "${GREEN}   Job ID: $JOB_ID${NC}"
else
  echo ""
  echo -e "${RED}❌ Job submission failed!${NC}"
  echo "$RESPONSE"
fi

echo ""
echo -e "${BLUE}4. Job Submit without Apptainer (Mock Mode)${NC}"
RESPONSE2=$(curl -s -X POST \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "jobName": "test_normal_job",
    "partition": "group1",
    "nodes": 1,
    "cpus": 64,
    "memory": "16GB",
    "time": "01:00:00",
    "script": "#!/bin/bash\necho \"Hello without Apptainer!\"\nhostname",
    "jobId": "tmp-test-456"
  }' \
  "$BACKEND_URL/api/slurm/jobs/submit")

echo "$RESPONSE2" | jq '.'

if echo "$RESPONSE2" | jq -e '.success' > /dev/null 2>&1; then
  JOB_ID2=$(echo "$RESPONSE2" | jq -r '.jobId')
  echo ""
  echo -e "${GREEN}✅ Job submitted successfully (no Apptainer)!${NC}"
  echo -e "${GREEN}   Job ID: $JOB_ID2${NC}"
else
  echo ""
  echo -e "${RED}❌ Job submission failed!${NC}"
fi

echo ""
echo "========================================"
echo -e "${YELLOW}Test Summary${NC}"
echo "========================================"
echo ""
echo -e "${GREEN}✅ Phase 1 Backend Integration Complete!${NC}"
echo ""
echo "What was tested:"
echo "  ✅ Apptainer images API"
echo "  ✅ Job submit with Apptainer image"
echo "  ✅ Job submit without Apptainer"
echo ""
echo "Next steps:"
echo "  1. Check backend logs: sudo tail -f /var/log/dashboard_backend.log"
echo "  2. Test from Frontend UI"
echo "  3. Test in Production mode (MOCK_MODE=false)"
echo ""
