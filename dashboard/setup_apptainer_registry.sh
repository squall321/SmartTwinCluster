#!/bin/bash

# Apptainer 이미지 중앙 레지스트리 설정
# 헤드노드에서 실행하여 중앙 이미지 저장소 생성

set -e

REGISTRY_BASE="/shared/apptainer"
IMAGES_DIR="${REGISTRY_BASE}/images"
METADATA_DIR="${REGISTRY_BASE}/metadata"
SCRIPTS_DIR="${REGISTRY_BASE}/scripts"

echo "=========================================="
echo "Apptainer 중앙 레지스트리 설정"
echo "=========================================="
echo ""

# 1. 디렉토리 구조 생성
echo "1. 디렉토리 구조 생성 중..."

sudo mkdir -p "${IMAGES_DIR}/compute"
sudo mkdir -p "${IMAGES_DIR}/viz"
sudo mkdir -p "${IMAGES_DIR}/shared"
sudo mkdir -p "${METADATA_DIR}"
sudo mkdir -p "${SCRIPTS_DIR}"

# 2. 소유권 설정
echo "2. 소유권 설정 중..."
sudo chown -R koopark:koopark "${REGISTRY_BASE}"
sudo chmod -R 755 "${REGISTRY_BASE}"

# 3. 메타데이터 디렉토리에 README 생성
cat > "${METADATA_DIR}/README.md" << 'EOF'
# Apptainer 이미지 메타데이터

이 디렉토리는 각 Apptainer 이미지의 메타데이터를 JSON 형식으로 저장합니다.

## 파일 구조

```
metadata/
├── {image_id}.json          # 이미지 메타데이터
└── node_availability.json   # 노드별 이미지 가용성
```

## 이미지 메타데이터 형식

```json
{
  "id": "python_3.11",
  "name": "python_3.11.sif",
  "path": "/shared/apptainer/images/compute/python_3.11.sif",
  "type": "compute",
  "partition": "compute",
  "size": 1234567890,
  "created_at": "2025-11-06T00:00:00Z",
  "version": "3.11",
  "description": "Python 3.11 with scientific libraries",
  "apps": ["python", "pip", "ipython"],
  "labels": {
    "Author": "admin",
    "Version": "3.11.5"
  },
  "available_on_nodes": ["node01", "node02", "node03"]
}
```

## 노드별 가용성 형식

```json
{
  "compute": {
    "node01": ["python_3.11", "pytorch_2.0"],
    "node02": ["python_3.11", "tensorflow_2.14"],
    "node03": ["python_3.11", "pytorch_2.0", "tensorflow_2.14"]
  },
  "viz": {
    "viz01": ["paraview_5.11", "blender_3.6"]
  }
}
```
EOF

# 4. 이미지 디렉토리별 README 생성
cat > "${IMAGES_DIR}/compute/README.md" << 'EOF'
# Compute 파티션 Apptainer 이미지

이 디렉토리는 Compute 파티션 노드에서 사용할 Apptainer 이미지를 저장합니다.

## 이미지 배치 방법

1. 이미지를 이 디렉토리에 복사:
   ```bash
   cp my_image.sif /shared/apptainer/images/compute/
   ```

2. Dashboard에서 스캔:
   - Apptainer Images → Scan 버튼 클릭
   - 또는 Backend API 호출: `POST /api/v2/apptainer/scan`

3. 메타데이터 확인:
   ```bash
   cat /shared/apptainer/metadata/{image_id}.json
   ```

## 권장 이미지

- Python 계열: python_3.x.sif
- ML/DL: pytorch_x.x.sif, tensorflow_x.x.sif
- 과학계산: scipy_stack.sif, julia_x.x.sif
- CFD: openfoam_vXXXX.sif, ansys_fluent.sif
- 분자동역학: gromacs_x.x.sif, lammps.sif
EOF

cat > "${IMAGES_DIR}/viz/README.md" << 'EOF'
# Visualization 파티션 Apptainer 이미지

이 디렉토리는 Visualization 파티션 노드에서 사용할 Apptainer 이미지를 저장합니다.

## 이미지 배치 방법

1. 이미지를 이 디렉토리에 복사:
   ```bash
   cp my_viz_image.sif /shared/apptainer/images/viz/
   ```

2. Dashboard에서 스캔

## 권장 이미지

- ParaView: paraview_x.x.sif
- Blender: blender_x.x.sif
- VTK: vtk_x.x.sif
- VisIt: visit_x.x.sif
EOF

cat > "${IMAGES_DIR}/shared/README.md" << 'EOF'
# Shared Apptainer 이미지

이 디렉토리는 모든 파티션에서 공통으로 사용할 수 있는 이미지를 저장합니다.

## 용도

- 범용 도구 (htop, vim, etc.)
- 개발 환경 (gcc, cmake, etc.)
- 데이터 처리 도구 (awk, jq, etc.)
EOF

# 5. 노드별 가용성 초기 파일 생성
cat > "${METADATA_DIR}/node_availability.json" << 'EOF'
{
  "version": "1.0",
  "last_updated": "2025-11-06T00:00:00Z",
  "partitions": {
    "compute": {},
    "viz": {}
  }
}
EOF

# 6. 이미지 동기화 스크립트 생성
cat > "${SCRIPTS_DIR}/sync_to_nodes.sh" << 'EOF'
#!/bin/bash

# Apptainer 이미지를 컴퓨트 노드에 동기화
# Usage: ./sync_to_nodes.sh [image_name] [partition]

IMAGE_NAME=$1
PARTITION=${2:-compute}
SOURCE_DIR="/shared/apptainer/images/${PARTITION}"
TARGET_DIR="/scratch/apptainer/${PARTITION}"

if [ -z "$IMAGE_NAME" ]; then
    echo "Usage: $0 <image_name> [partition]"
    echo "Example: $0 python_3.11.sif compute"
    exit 1
fi

if [ ! -f "${SOURCE_DIR}/${IMAGE_NAME}" ]; then
    echo "Error: Image not found: ${SOURCE_DIR}/${IMAGE_NAME}"
    exit 1
fi

echo "Syncing ${IMAGE_NAME} to ${PARTITION} nodes..."

# Get list of nodes in partition
NODES=$(sinfo -p ${PARTITION} -h -N -o "%N" | sort -u)

for NODE in $NODES; do
    echo "  → ${NODE}"
    ssh $NODE "mkdir -p ${TARGET_DIR}"
    scp "${SOURCE_DIR}/${IMAGE_NAME}" "${NODE}:${TARGET_DIR}/"
done

echo "✅ Sync completed!"
EOF

chmod +x "${SCRIPTS_DIR}/sync_to_nodes.sh"

# 7. 이미지 검증 스크립트 생성
cat > "${SCRIPTS_DIR}/verify_image.sh" << 'EOF'
#!/bin/bash

# Apptainer 이미지 검증 및 메타데이터 추출
# Usage: ./verify_image.sh <image.sif>

IMAGE_PATH=$1

if [ -z "$IMAGE_PATH" ] || [ ! -f "$IMAGE_PATH" ]; then
    echo "Usage: $0 <image.sif>"
    exit 1
fi

echo "=========================================="
echo "Apptainer 이미지 검증"
echo "=========================================="
echo ""
echo "이미지: $(basename $IMAGE_PATH)"
echo "크기: $(du -h $IMAGE_PATH | cut -f1)"
echo ""

# 이미지 검증
if apptainer verify $IMAGE_PATH 2>/dev/null; then
    echo "✅ 서명 검증: 성공"
else
    echo "⚠️  서명 검증: 실패 (또는 서명되지 않음)"
fi

# 메타데이터 추출
echo ""
echo "메타데이터:"
apptainer inspect $IMAGE_PATH 2>/dev/null | head -20

# 사용 가능한 앱 목록
echo ""
echo "사용 가능한 앱:"
apptainer inspect --list-apps $IMAGE_PATH 2>/dev/null || echo "  (앱 정보 없음)"

# 정의 파일
echo ""
echo "정의 파일:"
apptainer inspect --deffile $IMAGE_PATH 2>/dev/null | head -30 || echo "  (정의 파일 없음)"

echo ""
echo "=========================================="
EOF

chmod +x "${SCRIPTS_DIR}/verify_image.sh"

# 8. 샘플 이미지 빌드 스크립트 생성
cat > "${SCRIPTS_DIR}/build_sample_images.sh" << 'EOF'
#!/bin/bash

# 샘플 Apptainer 이미지 빌드
# 테스트 및 데모용

IMAGES_DIR="/shared/apptainer/images"

echo "=========================================="
echo "샘플 Apptainer 이미지 빌드"
echo "=========================================="
echo ""
echo "⚠️  주의: 이미지 빌드는 시간이 오래 걸립니다 (각 5-10분)"
echo ""

# Python 3.11 (경량)
echo "1. Python 3.11 이미지 빌드 중..."
cd "${IMAGES_DIR}/compute"
apptainer build python_3.11.sif docker://python:3.11-slim

# Ubuntu 22.04 (기본)
echo ""
echo "2. Ubuntu 22.04 이미지 빌드 중..."
apptainer build ubuntu_22.04.sif docker://ubuntu:22.04

# 완료
echo ""
echo "=========================================="
echo "✅ 샘플 이미지 빌드 완료!"
echo "=========================================="
echo ""
echo "생성된 이미지:"
ls -lh "${IMAGES_DIR}/compute/"*.sif

echo ""
echo "다음 단계:"
echo "  1. Dashboard → Apptainer Images → Scan 버튼 클릭"
echo "  2. 이미지 목록 확인"
echo "  3. Job Submit에서 이미지 선택"
EOF

chmod +x "${SCRIPTS_DIR}/build_sample_images.sh"

# 9. 완료 메시지
echo ""
echo "=========================================="
echo "✅ Apptainer 중앙 레지스트리 설정 완료!"
echo "=========================================="
echo ""
echo "생성된 디렉토리:"
echo "  ${REGISTRY_BASE}/"
echo "  ├── images/"
echo "  │   ├── compute/      # Compute 파티션 이미지"
echo "  │   ├── viz/          # Viz 파티션 이미지"
echo "  │   └── shared/       # 공통 이미지"
echo "  ├── metadata/         # 이미지 메타데이터 (JSON)"
echo "  └── scripts/          # 관리 스크립트"
echo ""
echo "다음 단계:"
echo "  1. 샘플 이미지 빌드 (선택):"
echo "     ${SCRIPTS_DIR}/build_sample_images.sh"
echo ""
echo "  2. 또는 기존 이미지 복사:"
echo "     cp your_image.sif ${IMAGES_DIR}/compute/"
echo ""
echo "  3. Dashboard에서 스캔:"
echo "     Apptainer Images → Scan 버튼"
echo ""
echo "  4. 노드에 동기화 (선택):"
echo "     ${SCRIPTS_DIR}/sync_to_nodes.sh python_3.11.sif compute"
echo ""
