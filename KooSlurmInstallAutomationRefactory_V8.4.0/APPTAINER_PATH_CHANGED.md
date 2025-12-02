# Apptainer 경로 변경: /opt/containers 사용

## 📂 경로 변경 사항

**이전**: `/scratch/apptainers`  
**변경**: `/opt/containers`

### 🎯 변경 이유

1. **표준 규격**: `/opt`는 선택적 소프트웨어 패키지의 표준 위치
2. **직관성**: `containers`라는 이름이 용도를 명확히 표현
3. **안정성**: `/opt`는 시스템 디렉토리로 더 안정적
4. **권한 관리**: 일반적으로 755 권한으로 충분 (1777 불필요)

### 📋 새로운 디렉토리 구조

```
/opt/
└── containers/              # 컨테이너 이미지 저장소
    ├── *.def               # Apptainer definition 파일
    └── *.sif               # Apptainer image 파일
```

### ✅ 자동으로 처리되는 것들

`sync_apptainers_to_nodes.sh` 실행 시:

1. `/opt` 디렉토리 확인
2. 없으면 `sudo mkdir -p /opt && sudo chmod 755 /opt`
3. `/opt/containers` 디렉토리 생성
4. 권한 문제 시 sudo로 재시도
5. 파일 동기화

### 🔧 사용법 (변경 없음)

```bash
# 기존과 동일하게 사용
./sync_apptainers_to_nodes.sh

# 옵션도 동일
./sync_apptainers_to_nodes.sh --force
./sync_apptainers_to_nodes.sh --dry-run
```

### 💻 Slurm 작업에서 사용

```bash
#!/bin/bash
#SBATCH --job-name=my_job
#SBATCH --nodes=1

# 새 경로 사용
apptainer exec /opt/containers/myapp.sif ./my_program
```

### 📝 YAML 설정 업데이트 (권장)

`my_cluster.yaml`에서도 경로를 업데이트하는 것이 좋습니다:

```yaml
container_support:
  apptainer:
    enabled: true
    version: 1.2.5
    install_path: /usr/local
    image_path: /opt/containers        # 업데이트
    cache_path: /tmp/apptainer
    scratch_image_path: /opt/containers # 업데이트
    bind_paths:
    - /home
    - /share
    - /opt/containers                  # 추가
    - /tmp
    auto_sync_images: true
```

### 🔄 기존 파일 마이그레이션

만약 이미 `/scratch/apptainers`에 파일이 있다면:

```bash
# 각 노드에서 실행
for node in node001 node002; do
    echo "==> $node"
    ssh $node 'if [ -d /scratch/apptainers ]; then \
        sudo mkdir -p /opt/containers && \
        sudo cp -r /scratch/apptainers/* /opt/containers/ && \
        sudo chmod 755 /opt/containers && \
        echo "Migration complete"; \
    fi'
done
```

### ✨ 장점

| 항목 | /scratch/apptainers | /opt/containers |
|------|-------------------|-----------------|
| 표준성 | ✗ | ✅ (FHS 표준) |
| 직관성 | △ | ✅ |
| 권한 | 1777 (복잡) | 755 (단순) |
| 안정성 | △ (임시용) | ✅ (영구용) |
| 백업 | 제외될 수 있음 | 포함됨 |

### 📌 주의사항

- **기존 경로 사용 중**: 마이그레이션 후 동기화 재실행
- **문서 참조**: 이전 문서에서 `/scratch/apptainers` → `/opt/containers`로 읽으시면 됩니다
- **자동화**: 스크립트가 모든 것을 자동으로 처리하므로 추가 작업 불필요

### 🚀 바로 시작

```bash
# 새 경로로 동기화
./sync_apptainers_to_nodes.sh

# 확인
ssh node001 'ls -lh /opt/containers'
```

---

**업데이트 날짜**: 2025-10-13  
**버전**: 2.1 (경로 변경)
