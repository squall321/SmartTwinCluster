# 📋 Dashboard 프로젝트 개선 계획 (Phase 1-6)

> **프로젝트:** Slurm Cluster Management Dashboard
> **버전:** v4.0 → v5.0
> **작성일:** 2025-11-05
> **목표:** Apptainer 통합, Template 체계화, 보안/인프라 강화

---

## ⚠️ 개발 규칙 및 가이드라인

### 🔒 핵심 원칙 (MUST FOLLOW)

#### 1. 시스템 안정성 보장
- ✅ **기존 시스템 보호**: 현재 잘 동작하는 시스템에 영향을 주지 않도록 최대한 주의
- ✅ **점진적 개선**: 한 번에 하나의 기능만 수정하고 철저히 테스트
- ✅ **롤백 가능성**: 모든 변경사항은 롤백 가능하도록 백업 유지
- ✅ **의존성 최소화**: 새로운 기능이 기존 기능에 의존하지 않도록 독립적으로 설계

#### 2. 근본 원인 분석 및 해결
- ❌ **임시방편 금지**: "빨리 돌아가게" 하는 임시 해법 금지
- ✅ **근본 원인 분석**: 문제의 근본 원인을 파악하고 근본적으로 해결
- ✅ **문서화**: 문제 발생 원인과 해결 방법을 상세히 문서화
- ✅ **재발 방지**: 동일한 문제가 다시 발생하지 않도록 구조적 개선

#### 3. 소스 코드 기반 수정
- ❌ **운영 서버 직접 수정 금지**: 배포된 서버의 파일을 직접 수정하지 말것
- ✅ **소스 코드 수정**: 빌드 전 소스 코드 수정 (frontend_3010, backend_5010, websocket_5011)
- ✅ **Setup 스크립트 수정**: 배포 과정 변경은 setup 스크립트 수정 (phase*.sh)
- ✅ **버전 관리**: 모든 변경사항은 Git으로 관리

#### 4. 자동 배포 시스템 통합
- ✅ **setup_cluster_full_multihead.sh 통합**: 모든 변경사항이 자동 배포 스크립트에 반영
- ✅ **멱등성 보장**: 스크립트를 여러 번 실행해도 동일한 결과 보장
- ✅ **에러 핸들링**: 각 Phase에서 실패 시 적절한 exit code 반환 및 롤백
- ✅ **의존성 검증**: 스크립트 실행 전 필수 의존성 검증

#### 5. 신규 서버 배포 대응
- ✅ **헤드노드 독립성**: 헤드노드 설정도 setup 파일에 포함하여 자동화
- ✅ **환경 설정 파일화**: 하드코딩된 경로/포트/IP 대신 환경 변수 또는 설정 파일 사용
- ✅ **의존성 자동 설치**: 필요한 패키지, 라이브러리 자동 설치
- ✅ **초기 데이터 생성**: DB 초기화, 샘플 데이터, 기본 템플릿 자동 생성

#### 6. Job Submit 개선 우선순위
- ⚠️ **현재 상태**: Job submit을 제외한 대부분의 기능은 정상 동작
- ✅ **영향 범위 파악**: 수정이 다른 시스템에 미칠 영향 사전 분석
- ✅ **단계적 검증**: 각 단계마다 Job submit 기능이 제대로 동작하는지 검증
- ✅ **통합 테스트**: Template → File Upload → Job Submit → Monitoring 전체 플로우 테스트

---

### 📐 개발 워크플로우

#### Phase 시작 전
```bash
# 1. 현재 시스템 상태 백업
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory
git add -A
git commit -m "Backup before Phase X implementation"

# 2. 개발 브랜치 생성
git checkout -b phase-X-feature-name

# 3. 현재 시스템 동작 확인
./cluster/tests/verify_system_health.sh  # 추후 생성
```

#### Phase 개발 중
```bash
# 1. 소스 코드 수정 (frontend/backend/websocket)
# 2. Setup 스크립트 수정 (필요 시)
# 3. 로컬 빌드 테스트
cd dashboard/frontend_3010 && npm run build
cd dashboard/backend_5010 && python -m pytest tests/

# 4. 변경사항 커밋
git add modified_files
git commit -m "Phase X: Implement feature Y"
```

#### Phase 배포 전 검증
```bash
# 1. 자동 배포 스크립트 테스트 (Dry-run)
sudo ./cluster/setup/setup_cluster_full_multihead.sh --dry-run

# 2. 단일 Phase만 테스트 (예: Phase 5)
sudo ./cluster/setup/phase5_web_services.sh

# 3. 전체 시스템 배포
sudo ./cluster/setup/setup_cluster_full_multihead.sh

# 4. 배포 후 검증
./cluster/tests/verify_system_health.sh
curl http://192.168.0.201:5010/api/health
curl http://192.168.0.201:3010/
```

#### 롤백 프로세스
```bash
# 문제 발생 시 이전 버전으로 롤백
git checkout main
sudo ./cluster/setup/setup_cluster_full_multihead.sh
```

---

### 🗂️ 파일 수정 가이드라인

#### Frontend 수정 시 (frontend_3010)
```
✅ 수정해야 할 위치:
  - /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/frontend_3010/src/

❌ 수정하면 안되는 위치:
  - /home/koopark/web_services/frontend/  (배포된 빌드 파일)

✅ 배포 방법:
  1. frontend_3010에서 소스 수정
  2. npm run build
  3. phase5_web_services.sh 실행 (자동으로 /home/koopark/web_services/frontend/ 로 복사)
```

#### Backend 수정 시 (backend_5010)
```
✅ 수정해야 할 위치:
  - /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/backend_5010/

❌ 수정하면 안되는 위치:
  - /home/koopark/web_services/backend/  (배포된 서비스 파일)

✅ 배포 방법:
  1. backend_5010에서 소스 수정
  2. requirements.txt 업데이트 (필요 시)
  3. phase5_web_services.sh 실행 (자동으로 /home/koopark/web_services/backend/ 로 복사)
  4. sudo systemctl restart auth_backend (또는 해당 서비스)
```

#### Setup 스크립트 수정 시
```
✅ 수정해야 할 위치:
  - /home/koopark/claude/KooSlurmInstallAutomationRefactory/cluster/setup/phase*.sh

✅ 수정 가이드:
  1. 에러 핸들링 추가 (set -euo pipefail)
  2. 로그 함수 사용 (log_info, log_success, log_error)
  3. 실패 시 exit 1 반환
  4. 멱등성 보장 (이미 설치된 경우 스킵)
```

#### DB Schema 수정 시
```
✅ 수정 위치:
  - dashboard/backend_5010/migrations/ (새 마이그레이션 파일 생성)

✅ 마이그레이션 생성:
  1. migrations/vX.X.X_feature_name.sql 생성
  2. UP migration (테이블 생성/수정)
  3. DOWN migration (롤백 쿼리)
  4. phase5_web_services.sh에 마이그레이션 자동 실행 추가
```

---

### 🧪 테스트 가이드라인

#### 필수 테스트 항목
```bash
# 1. API 엔드포인트 테스트
curl -X GET http://192.168.0.201:5010/api/health
curl -X GET http://192.168.0.201:5010/api/nodes
curl -X POST http://192.168.0.201:5010/api/jobs/submit \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d @test_job.json

# 2. WebSocket 연결 테스트
wscat -c ws://192.168.0.201:5011

# 3. Frontend 접속 테스트
curl http://192.168.0.201:3010/

# 4. 서비스 상태 확인
sudo systemctl status auth_backend
sudo systemctl status prometheus

# 5. 로그 확인
tail -f /var/log/web_services/auth_backend/app.log
tail -f /var/log/web_services/prometheus/prometheus.log
```

#### Phase별 검증 체크리스트
```markdown
Phase 1 (Apptainer Discovery):
- [ ] Compute Node 이미지 스캔 정상 동작
- [ ] 이미지 메타데이터 추출 정상
- [ ] DB에 이미지 정보 저장 확인
- [ ] API 엔드포인트 응답 확인
- [ ] 기존 Job Submit 기능 정상 동작

Phase 2 (Template Management):
- [ ] 템플릿 디렉토리 생성 확인 (/shared/templates)
- [ ] YAML 템플릿 파일 파싱 정상
- [ ] DB와 파일 시스템 동기화 확인
- [ ] Hot Reload 동작 확인
- [ ] 기존 Job Submit 기능 정상 동작

Phase 3 (File Upload API):
- [ ] 청크 업로드 정상 동작
- [ ] 파일 분류 (data/config) 정상
- [ ] 대용량 파일 (5GB+) 업로드 성공
- [ ] 업로드 진행률 WebSocket 전송 확인
- [ ] 기존 Job Submit 기능 정상 동작

... (각 Phase마다 체크리스트 작성)
```

---

### 📝 문서화 규칙

#### 코드 주석
```python
# ✅ Good: 왜(Why) 이렇게 했는지 설명
def scan_apptainer_images(node: str):
    """
    특정 노드의 Apptainer 이미지를 스캔합니다.

    SSH 연결 실패 시 재시도를 3번 수행하는 이유:
    - 네트워크 일시적 장애 대응
    - Compute Node의 부팅 중일 가능성

    Args:
        node: 스캔할 노드 호스트명 (예: compute-node001)

    Returns:
        List[ApptainerImage]: 발견된 이미지 목록

    Raises:
        SSHConnectionError: 3번 재시도 후에도 연결 실패
    """
```

#### Git 커밋 메시지
```bash
# ✅ Good: 구조화된 커밋 메시지
git commit -m "Phase 2: Add external template storage system

- Create /shared/templates directory structure
- Implement TemplateLoader with YAML parsing
- Add hot reload with watchdog
- Update phase5_web_services.sh to initialize template storage

Fixes: #123
Related: Phase 2.2 in DASHBOARD_IMPROVEMENT_PLAN.md"

# ❌ Bad: 모호한 커밋 메시지
git commit -m "update files"
git commit -m "fix bug"
```

#### 변경 로그 (CHANGELOG.md)
```markdown
## [v4.1.0] - 2025-11-05

### Added
- External template storage system at /shared/templates
- TemplateLoader service for YAML template management
- Hot reload functionality for template changes

### Changed
- phase5_web_services.sh now initializes template directories
- Template API endpoints updated to v2

### Fixed
- Job submit failure when template contains special characters

### Migration Guide
1. Run: sudo ./cluster/setup/init_template_storage.sh
2. Restart backend: sudo systemctl restart auth_backend
3. Verify: curl http://192.168.0.201:5010/api/v2/templates/scan
```

---

## 🎯 개선 목표 요약

### 핵심 개선 사항
1. **Apptainer 통합** - Compute Node의 .sif 이미지를 동적으로 스크립트에 활용
2. **Template 관리 체계화** - 시뮬레이션 파일, 옵션 파일 분류 및 관리
3. **파일 업로드 API 체계화** - 다양한 프론트엔드에서 사용 가능한 통합 API
4. **보안 강화** - CORS, JWT Refresh, Rate Limiting, Input Validation
5. **인프라 개선** - Redis 캐싱, Nginx 최적화, 로깅 체계
6. **성능 최적화** - 비동기 처리, 캐싱 전략, 코드 스플리팅

---

## 📊 Phase별 개선 계획

### Phase 1: Apptainer Discovery & Integration (2주)
**목표:** Compute Node의 Apptainer 이미지를 자동으로 발견하고 작업 스크립트에 통합

#### 1.1 Apptainer Discovery Service (Backend)
**새 파일:** `backend_5010/apptainer_service.py`

```python
"""
Apptainer Discovery Service
Compute Node의 .sif 이미지를 스캔하고 메타데이터를 관리
"""

class ApptainerService:
    def scan_node_images(self, node: str) -> List[ApptainerImage]:
        """노드의 /opt/apptainers/ 스캔"""

    def get_image_metadata(self, image_path: str) -> dict:
        """이미지 메타데이터 추출 (apptainer inspect)"""

    def list_available_images(self, partition: str = None) -> List[ApptainerImage]:
        """파티션별 사용 가능한 이미지 목록"""

    def validate_image(self, image_path: str) -> bool:
        """이미지 유효성 검증"""

    def get_image_apps(self, image_path: str) -> List[str]:
        """이미지 내부 앱 목록 조회"""
```

**주요 기능:**
- ✅ SSH를 통한 원격 노드 이미지 스캔
- ✅ Apptainer inspect 명령으로 메타데이터 추출
- ✅ 이미지 분류 (viz, compute, custom)
- ✅ 이미지 캐싱 (Redis, TTL 1시간)
- ✅ 이미지 버전 관리

**API 엔드포인트:** `apptainer_api.py`
```
GET  /api/apptainer/images              # 모든 이미지 목록
GET  /api/apptainer/images/{node}       # 특정 노드 이미지
GET  /api/apptainer/images/{id}/metadata # 이미지 상세 정보
GET  /api/apptainer/images/{id}/apps    # 이미지 내부 앱 목록
POST /api/apptainer/scan                # 전체 노드 스캔 트리거
```

#### 1.2 Database Schema 확장
**테이블:** `apptainer_images`

```sql
CREATE TABLE apptainer_images (
    id TEXT PRIMARY KEY,                      -- UUID
    name TEXT NOT NULL,                       -- vnc_gnome.sif
    path TEXT NOT NULL,                       -- /opt/apptainers/vnc_gnome.sif
    node TEXT NOT NULL,                       -- viz-node001
    partition TEXT,                           -- viz, compute
    type TEXT CHECK(type IN ('viz', 'compute', 'custom')),
    size INTEGER,                             -- bytes
    version TEXT,                             -- 1.0.0
    description TEXT,
    labels TEXT,                              -- JSON: {"gpu": "required", "mpi": "true"}
    apps TEXT,                                -- JSON: ["python", "jupyter", "gedit"]
    runscript TEXT,                           -- Default runscript
    env_vars TEXT,                            -- JSON: environment variables
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_scanned DATETIME,
    is_active BOOLEAN DEFAULT 1
);

CREATE INDEX idx_images_node ON apptainer_images(node);
CREATE INDEX idx_images_partition ON apptainer_images(partition);
CREATE INDEX idx_images_type ON apptainer_images(type);
CREATE INDEX idx_images_active ON apptainer_images(is_active);
```

#### 1.3 Frontend Integration
**새 컴포넌트:** `frontend_3010/src/components/ApptainerSelector.tsx`

```typescript
interface ApptainerImage {
  id: string;
  name: string;
  path: string;
  node: string;
  partition: string;
  type: 'viz' | 'compute' | 'custom';
  apps: string[];
  description?: string;
  labels?: Record<string, string>;
}

interface ApptainerSelectorProps {
  partition?: string;
  onSelect: (image: ApptainerImage, app?: string) => void;
  selectedImage?: ApptainerImage;
}

export const ApptainerSelector: React.FC<ApptainerSelectorProps> = ({
  partition,
  onSelect,
  selectedImage
}) => {
  // 이미지 목록 조회
  // 파티션 필터링
  // 앱 선택 UI
  // 이미지 메타데이터 표시
};
```

**주요 기능:**
- ✅ 파티션별 이미지 필터링
- ✅ 이미지 내부 앱 선택 (dropdown)
- ✅ 이미지 메타데이터 툴팁
- ✅ GPU 요구사항 표시
- ✅ 최근 사용 이미지 우선 표시

#### 1.4 Slurm Script Template 통합
**수정:** `backend_5010/templates_api.py`

```python
class JobScriptGenerator:
    def generate_script(self, template: dict, apptainer_image: str = None, app: str = None) -> str:
        """
        Slurm 작업 스크립트 생성 (Apptainer 통합)
        """
        script = "#!/bin/bash\n"
        script += f"#SBATCH --job-name={template['job_name']}\n"
        # ... 기타 SBATCH 옵션

        if apptainer_image:
            script += f"\n# Apptainer Container\n"
            script += f"CONTAINER={apptainer_image}\n"

            if app:
                # 특정 앱 실행
                script += f"apptainer exec $CONTAINER {app} $@\n"
            else:
                # Runscript 실행
                script += f"apptainer run $CONTAINER $@\n"
        else:
            # 일반 명령어 실행
            script += template['command']

        return script
```

**스크립트 예시:**
```bash
#!/bin/bash
#SBATCH --job-name=simulation_job
#SBATCH --partition=compute
#SBATCH --nodes=1
#SBATCH --ntasks=8
#SBATCH --time=01:00:00

# Apptainer Container
CONTAINER=/opt/apptainers/KooSimulationPython313.sif

# 입력 파일 복사
cp input_files/* $SLURM_SUBMIT_DIR/

# 시뮬레이션 실행
apptainer exec $CONTAINER python simulation.py \
  --config config.json \
  --input input.dat \
  --output results/

# 결과 파일 복사
cp results/* /shared/results/$SLURM_JOB_ID/
```

---

### Phase 2: Template Management System (2주)
**목표:** 체계적인 Template 관리 및 파일 분류 시스템 구축

#### 2.1 Template Schema 확장
**테이블:** `job_templates_v2`

```sql
CREATE TABLE job_templates_v2 (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    display_name TEXT NOT NULL,           -- 사용자 친화적 이름
    description TEXT,
    category TEXT CHECK(category IN ('ml', 'cfd', 'structural', 'molecular', 'data', 'custom')),
    tags TEXT,                             -- JSON: ["gpu", "mpi", "openfoam"]

    -- Slurm 설정
    partition TEXT,
    nodes INTEGER DEFAULT 1,
    ntasks INTEGER DEFAULT 1,
    cpus_per_task INTEGER DEFAULT 1,
    mem TEXT,                              -- "4G", "8G", etc.
    time TEXT DEFAULT "01:00:00",
    gres TEXT,                             -- "gpu:1"
    constraint TEXT,                       -- Node constraints

    -- Apptainer 설정
    apptainer_image_id TEXT,               -- FK to apptainer_images
    apptainer_app TEXT,                    -- 특정 앱 (optional)
    apptainer_bind TEXT,                   -- JSON: bind mounts

    -- 파일 분류
    input_file_schema TEXT,                -- JSON: 입력 파일 스키마
    option_file_schema TEXT,               -- JSON: 옵션 파일 스키마
    output_file_pattern TEXT,              -- 출력 파일 패턴

    -- 스크립트
    pre_script TEXT,                       -- 실행 전 스크립트
    main_script TEXT,                      -- 메인 실행 스크립트 (템플릿)
    post_script TEXT,                      -- 실행 후 스크립트

    -- 메타데이터
    created_by TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    usage_count INTEGER DEFAULT 0,
    is_public BOOLEAN DEFAULT 0,
    version TEXT DEFAULT "1.0.0",

    FOREIGN KEY (apptainer_image_id) REFERENCES apptainer_images(id)
);

CREATE INDEX idx_templates_v2_category ON job_templates_v2(category);
CREATE INDEX idx_templates_v2_tags ON job_templates_v2(tags);
CREATE INDEX idx_templates_v2_public ON job_templates_v2(is_public);
```

#### 2.2 External Template Storage
**목표:** 프론트엔드 빌드와 독립적으로 템플릿을 외부에서 관리

**템플릿 저장 위치:**
```
/shared/templates/
├── official/              # 공식 템플릿 (관리자만 수정)
│   ├── ml/
│   │   ├── pytorch_training.yaml
│   │   ├── tensorflow_training.yaml
│   │   └── jupyter_notebook.yaml
│   ├── cfd/
│   │   ├── openfoam_simulation.yaml
│   │   └── fluent_simulation.yaml
│   ├── structural/
│   │   ├── abaqus_analysis.yaml
│   │   └── ansys_mechanical.yaml
│   └── molecular/
│       └── gromacs_simulation.yaml
├── community/             # 커뮤니티 템플릿 (공유된 사용자 템플릿)
│   └── user_shared_*.yaml
├── private/               # 개인 템플릿
│   ├── user1/
│   │   └── my_template.yaml
│   └── user2/
│       └── custom_workflow.yaml
└── archived/              # 아카이브된 템플릿
    └── old_templates/
```

**템플릿 파일 형식 (YAML):**
```yaml
# /shared/templates/official/ml/pytorch_training.yaml
template:
  id: pytorch-training-v1
  name: pytorch_training
  display_name: "PyTorch 모델 학습"
  description: "PyTorch를 이용한 딥러닝 모델 학습 템플릿"
  category: ml
  tags: [gpu, pytorch, ml, deep-learning]
  version: "1.0.0"
  author: admin
  is_public: true

slurm:
  partition: gpu
  nodes: 1
  ntasks: 1
  cpus_per_task: 8
  mem: 32G
  time: "04:00:00"
  gres: gpu:1
  constraint: "gpu_v100|gpu_a100"

apptainer:
  image_name: "pytorch_cuda.sif"  # 이미지 이름으로 자동 매칭
  app: python                      # 특정 앱 실행 (optional)
  bind:
    - /shared/datasets:/datasets:ro
    - /shared/models:/models:rw

files:
  input_schema:
    required:
      - name: training_script
        pattern: "*.py"
        description: "학습 스크립트"
        type: code
        max_size: 10MB
      - name: dataset
        pattern: "*.tar.gz"
        description: "데이터셋 아카이브"
        type: data
        max_size: 10GB
    optional:
      - name: pretrained_model
        pattern: "*.pth"
        description: "사전 학습된 모델"
        type: model
        max_size: 2GB

  config_schema:
    required:
      - name: config
        pattern: config.yaml
        format: yaml
        schema:
          type: object
          properties:
            learning_rate: {type: number, minimum: 0.0001, maximum: 1}
            batch_size: {type: integer, minimum: 1, maximum: 1024}
            epochs: {type: integer, minimum: 1}
            optimizer: {type: string, enum: [adam, sgd, rmsprop]}
          required: [learning_rate, batch_size, epochs]

  output_pattern: "checkpoints/*.pth"

script:
  pre_exec: |
    #!/bin/bash
    # 데이터셋 압축 해제
    mkdir -p $SLURM_SUBMIT_DIR/data
    tar -xzf dataset.tar.gz -C $SLURM_SUBMIT_DIR/data

    # 환경 변수 설정
    export CUDA_VISIBLE_DEVICES=$SLURM_LOCALID

  main_exec: |
    #!/bin/bash
    # PyTorch 학습 실행
    apptainer exec --nv $APPTAINER_IMAGE \
      python training_script.py \
        --config config.yaml \
        --data $SLURM_SUBMIT_DIR/data \
        --output $SLURM_SUBMIT_DIR/checkpoints

  post_exec: |
    #!/bin/bash
    # 결과 파일 정리
    mkdir -p /shared/results/$SLURM_JOB_ID
    cp -r checkpoints /shared/results/$SLURM_JOB_ID/

    # 임시 파일 정리
    rm -rf $SLURM_SUBMIT_DIR/data

validation:
  pre_submit:
    - check_gpu_availability
    - validate_dataset_size
  post_submit:
    - notify_user
    - log_submission
```

**Template Loader Service:**
```python
# backend_5010/template_loader.py
import os
import yaml
import glob
from pathlib import Path
from typing import List, Dict, Optional
import hashlib

class TemplateLoader:
    def __init__(self, base_path: str = "/shared/templates"):
        self.base_path = Path(base_path)
        self.cache = {}  # 메모리 캐시
        self.cache_ttl = 300  # 5분

    def scan_templates(self, category: str = None) -> List[Dict]:
        """템플릿 디렉토리 스캔"""
        templates = []

        # Official templates
        templates.extend(self._scan_directory(self.base_path / "official", "official"))

        # Community templates
        templates.extend(self._scan_directory(self.base_path / "community", "community"))

        if category:
            templates = [t for t in templates if t['category'] == category]

        return templates

    def _scan_directory(self, path: Path, source: str) -> List[Dict]:
        """디렉토리 내 YAML 템플릿 스캔"""
        templates = []

        for yaml_file in path.rglob("*.yaml"):
            try:
                template = self.load_template_file(yaml_file)
                template['source'] = source
                template['file_path'] = str(yaml_file)
                templates.append(template)
            except Exception as e:
                print(f"Failed to load template {yaml_file}: {e}")

        return templates

    def load_template_file(self, file_path: Path) -> Dict:
        """YAML 템플릿 파일 로드 및 파싱"""
        with open(file_path, 'r', encoding='utf-8') as f:
            data = yaml.safe_load(f)

        # 필수 필드 검증
        if 'template' not in data:
            raise ValueError("Missing 'template' section")

        # 파일 해시 (버전 관리)
        data['file_hash'] = self._calculate_hash(file_path)
        data['last_modified'] = file_path.stat().st_mtime

        return data

    def _calculate_hash(self, file_path: Path) -> str:
        """파일 해시 계산"""
        with open(file_path, 'rb') as f:
            return hashlib.sha256(f.read()).hexdigest()

    def get_template(self, template_id: str) -> Optional[Dict]:
        """템플릿 ID로 조회"""
        templates = self.scan_templates()
        for template in templates:
            if template['template']['id'] == template_id:
                return template
        return None

    def save_template(self, template_data: Dict, user_id: str, is_public: bool = False):
        """새 템플릿 저장"""
        category = template_data['template']['category']

        if is_public:
            # Community 템플릿
            save_path = self.base_path / "community" / f"{template_data['template']['id']}.yaml"
        else:
            # Private 템플릿
            user_dir = self.base_path / "private" / user_id
            user_dir.mkdir(parents=True, exist_ok=True)
            save_path = user_dir / f"{template_data['template']['id']}.yaml"

        with open(save_path, 'w', encoding='utf-8') as f:
            yaml.dump(template_data, f, default_flow_style=False, allow_unicode=True)

        return str(save_path)

    def update_template(self, template_id: str, template_data: Dict):
        """기존 템플릿 업데이트"""
        template = self.get_template(template_id)
        if not template:
            raise ValueError(f"Template {template_id} not found")

        file_path = Path(template['file_path'])

        with open(file_path, 'w', encoding='utf-8') as f:
            yaml.dump(template_data, f, default_flow_style=False, allow_unicode=True)

    def delete_template(self, template_id: str, user_id: str):
        """템플릿 삭제 (아카이브로 이동)"""
        template = self.get_template(template_id)
        if not template:
            raise ValueError(f"Template {template_id} not found")

        file_path = Path(template['file_path'])

        # Official 템플릿은 삭제 불가
        if 'official' in str(file_path):
            raise PermissionError("Cannot delete official templates")

        # 아카이브로 이동
        archive_path = self.base_path / "archived" / file_path.name
        archive_path.parent.mkdir(parents=True, exist_ok=True)
        file_path.rename(archive_path)

    def sync_to_database(self):
        """파일 시스템의 템플릿을 DB와 동기화"""
        templates = self.scan_templates()

        # DB에 있는 템플릿 목록
        db_templates = get_all_templates_from_db()
        db_template_ids = {t['id'] for t in db_templates}

        # 파일에 있는 템플릿 목록
        file_template_ids = {t['template']['id'] for t in templates}

        # 새로 추가된 템플릿
        new_templates = file_template_ids - db_template_ids
        for template in templates:
            if template['template']['id'] in new_templates:
                insert_template_to_db(template)

        # 삭제된 템플릿
        deleted_templates = db_template_ids - file_template_ids
        for template_id in deleted_templates:
            mark_template_as_deleted_in_db(template_id)

        # 수정된 템플릿
        for template in templates:
            template_id = template['template']['id']
            if template_id in db_template_ids:
                db_template = get_template_from_db(template_id)
                if db_template['file_hash'] != template['file_hash']:
                    update_template_in_db(template)
```

**API 엔드포인트 추가:**
```python
# backend_5010/templates_api_v2.py

from template_loader import TemplateLoader

template_loader = TemplateLoader()

@app.route('/api/v2/templates/scan', methods=['POST'])
@jwt_required
def scan_templates():
    """템플릿 디렉토리 스캔 및 DB 동기화"""
    try:
        template_loader.sync_to_database()
        templates = template_loader.scan_templates()
        return jsonify({
            'message': 'Templates scanned successfully',
            'count': len(templates)
        }), 200
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/v2/templates/export/{id}', methods=['GET'])
@jwt_required
def export_template(id):
    """템플릿을 YAML 파일로 내보내기"""
    template = template_loader.get_template(id)
    if not template:
        return jsonify({'error': 'Template not found'}), 404

    yaml_content = yaml.dump(template, default_flow_style=False, allow_unicode=True)

    return Response(
        yaml_content,
        mimetype='application/x-yaml',
        headers={'Content-Disposition': f'attachment;filename={id}.yaml'}
    )

@app.route('/api/v2/templates/import', methods=['POST'])
@jwt_required
def import_template():
    """YAML 파일을 업로드하여 템플릿 가져오기"""
    if 'file' not in request.files:
        return jsonify({'error': 'No file provided'}), 400

    file = request.files['file']
    is_public = request.form.get('is_public', 'false').lower() == 'true'

    try:
        template_data = yaml.safe_load(file.read())
        file_path = template_loader.save_template(
            template_data,
            g.user_id,
            is_public
        )

        return jsonify({
            'message': 'Template imported successfully',
            'file_path': file_path
        }), 201
    except Exception as e:
        return jsonify({'error': str(e)}), 400
```

**Template Hot Reload:**
```python
# backend_5010/template_watcher.py
import time
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

class TemplateFileHandler(FileSystemEventHandler):
    def __init__(self, template_loader: TemplateLoader):
        self.template_loader = template_loader

    def on_modified(self, event):
        if event.src_path.endswith('.yaml'):
            print(f"Template modified: {event.src_path}")
            self.template_loader.sync_to_database()

    def on_created(self, event):
        if event.src_path.endswith('.yaml'):
            print(f"New template: {event.src_path}")
            self.template_loader.sync_to_database()

    def on_deleted(self, event):
        if event.src_path.endswith('.yaml'):
            print(f"Template deleted: {event.src_path}")
            self.template_loader.sync_to_database()

def start_template_watcher():
    """템플릿 디렉토리 변경 감지"""
    event_handler = TemplateFileHandler(template_loader)
    observer = Observer()
    observer.schedule(event_handler, "/shared/templates", recursive=True)
    observer.start()

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        observer.stop()

    observer.join()

# Flask 앱 시작 시 백그라운드로 실행
import threading
watcher_thread = threading.Thread(target=start_template_watcher, daemon=True)
watcher_thread.start()
```

**디렉토리 구조 초기화 스크립트:**
```bash
#!/bin/bash
# cluster/setup/init_template_storage.sh

TEMPLATE_DIR="/shared/templates"

echo "Initializing template storage at $TEMPLATE_DIR"

# 디렉토리 생성
sudo mkdir -p $TEMPLATE_DIR/{official,community,private,archived}
sudo mkdir -p $TEMPLATE_DIR/official/{ml,cfd,structural,molecular,data,custom}

# 권한 설정
sudo chown -R slurm:slurm $TEMPLATE_DIR
sudo chmod 755 $TEMPLATE_DIR
sudo chmod 755 $TEMPLATE_DIR/official
sudo chmod 777 $TEMPLATE_DIR/community
sudo chmod 777 $TEMPLATE_DIR/private
sudo chmod 755 $TEMPLATE_DIR/archived

# Official 템플릿은 읽기 전용
sudo chmod 644 $TEMPLATE_DIR/official/**/*.yaml 2>/dev/null || true

echo "Template storage initialized successfully"
echo "  - Official: $TEMPLATE_DIR/official (read-only)"
echo "  - Community: $TEMPLATE_DIR/community (shared)"
echo "  - Private: $TEMPLATE_DIR/private (user-specific)"
```

**장점:**
- ✅ 프론트엔드 빌드 없이 템플릿 수정/추가 가능
- ✅ Git으로 템플릿 버전 관리 가능
- ✅ 다양한 프론트엔드에서 동일한 템플릿 사용
- ✅ 관리자가 SSH로 템플릿 직접 수정 가능
- ✅ 파일 시스템 감시로 실시간 동기화
- ✅ YAML 형식으로 가독성 높음
- ✅ Import/Export로 템플릿 공유 가능

#### 2.3 File Schema Definition
**파일 분류 JSON 스키마:**

```json
{
  "input_file_schema": {
    "required_files": [
      {
        "name": "input_data",
        "pattern": "*.dat",
        "description": "시뮬레이션 입력 데이터",
        "type": "data",
        "max_size": "100MB",
        "validation": "validate_dat_format"
      },
      {
        "name": "mesh_file",
        "pattern": "*.msh",
        "description": "메쉬 파일",
        "type": "data",
        "max_size": "500MB"
      }
    ],
    "optional_files": [
      {
        "name": "initial_condition",
        "pattern": "init_*.dat",
        "description": "초기 조건 파일",
        "type": "data"
      }
    ]
  },
  "option_file_schema": {
    "required_files": [
      {
        "name": "config",
        "pattern": "config.json",
        "description": "시뮬레이션 설정",
        "type": "config",
        "format": "json",
        "schema": {
          "type": "object",
          "properties": {
            "timestep": {"type": "number"},
            "iterations": {"type": "integer"},
            "solver": {"type": "string", "enum": ["gmres", "cg"]}
          },
          "required": ["timestep", "iterations"]
        }
      }
    ],
    "optional_files": [
      {
        "name": "parameters",
        "pattern": "params.yaml",
        "description": "추가 파라미터",
        "type": "config",
        "format": "yaml"
      }
    ]
  },
  "output_file_pattern": "results_*.vtk"
}
```

#### 2.4 Template Manager API
**새 파일:** `backend_5010/template_manager.py`

```python
class TemplateManager:
    def create_template(self, template_data: dict) -> str:
        """템플릿 생성 및 파일 스키마 검증"""

    def validate_input_files(self, template_id: str, files: List[FileUpload]) -> dict:
        """업로드된 파일이 스키마와 일치하는지 검증"""

    def classify_files(self, files: List[FileUpload]) -> dict:
        """파일을 data/config로 분류"""

    def generate_job_script(self, template_id: str, files: dict, options: dict) -> str:
        """파일과 옵션을 기반으로 작업 스크립트 생성"""

    def get_template_by_category(self, category: str) -> List[Template]:
        """카테고리별 템플릿 조회"""

    def clone_template(self, template_id: str, new_name: str) -> str:
        """템플릿 복제"""
```

**API 엔드포인트:** `templates_api_v2.py`
```
# Template CRUD
GET    /api/v2/templates                  # 템플릿 목록
GET    /api/v2/templates/{id}             # 템플릿 상세
POST   /api/v2/templates                  # 템플릿 생성
PUT    /api/v2/templates/{id}             # 템플릿 수정
DELETE /api/v2/templates/{id}             # 템플릿 삭제

# Template Operations
POST   /api/v2/templates/{id}/clone       # 템플릿 복제
POST   /api/v2/templates/{id}/validate    # 파일 검증
POST   /api/v2/templates/{id}/generate    # 스크립트 생성

# File Management
POST   /api/v2/templates/{id}/files       # 파일 업로드
GET    /api/v2/templates/{id}/files       # 파일 목록
DELETE /api/v2/templates/{id}/files/{name} # 파일 삭제

# Categories & Tags
GET    /api/v2/templates/categories       # 카테고리 목록
GET    /api/v2/templates/tags             # 태그 목록
GET    /api/v2/templates/search?q=openfoam # 검색
```

#### 2.5 Frontend Template Manager
**새 컴포넌트:** `frontend_3010/src/components/TemplateManager/`

```typescript
// TemplateEditor.tsx - 템플릿 생성/수정
interface TemplateEditorProps {
  templateId?: string;
  onSave: (template: Template) => void;
}

// FileSchemaEditor.tsx - 파일 스키마 정의
interface FileSchemaEditorProps {
  schema: FileSchema;
  onChange: (schema: FileSchema) => void;
}

// TemplatePreview.tsx - 생성될 스크립트 미리보기
interface TemplatePreviewProps {
  template: Template;
  files: File[];
  options: Record<string, any>;
}

// TemplateLibrary.tsx - 템플릿 라이브러리 (카테고리별 브라우징)
interface TemplateLibraryProps {
  onSelect: (template: Template) => void;
}
```

**주요 기능:**
- ✅ Drag & Drop 파일 스키마 빌더
- ✅ JSON Schema 기반 옵션 파일 검증
- ✅ 실시간 스크립트 미리보기
- ✅ 템플릿 버전 관리
- ✅ 템플릿 공유 (public/private)

---

### Phase 3: Unified File Upload API (1.5주)
**목표:** 다양한 프론트엔드에서 사용 가능한 통합 파일 업로드 API 구축

#### 3.1 File Upload Service
**새 파일:** `backend_5010/file_upload_service.py`

```python
class FileUploadService:
    def __init__(self):
        self.storage_root = "/shared/uploads"
        self.temp_dir = "/tmp/uploads"
        self.max_file_size = 5 * 1024 * 1024 * 1024  # 5GB

    def create_upload_session(self, user_id: str, template_id: str = None) -> str:
        """업로드 세션 생성 (UUID 반환)"""

    def upload_chunk(self, session_id: str, chunk: bytes, chunk_index: int) -> dict:
        """청크 업로드 (대용량 파일 지원)"""

    def finalize_upload(self, session_id: str) -> List[UploadedFile]:
        """업로드 완료 및 파일 병합"""

    def validate_files(self, session_id: str, template_id: str) -> dict:
        """템플릿 스키마와 파일 검증"""

    def organize_files(self, session_id: str) -> dict:
        """파일 분류 (data/config)"""

    def get_upload_status(self, session_id: str) -> dict:
        """업로드 진행 상태"""

    def cleanup_session(self, session_id: str):
        """세션 정리 (임시 파일 삭제)"""
```

#### 3.2 Upload API Endpoints
**새 파일:** `backend_5010/upload_api_v2.py`

```python
# Session Management
POST   /api/v2/upload/sessions
    → { "session_id": "uuid", "expires_at": "timestamp" }

GET    /api/v2/upload/sessions/{session_id}
    → { "status": "active", "files": [...], "progress": 75 }

DELETE /api/v2/upload/sessions/{session_id}
    → { "message": "Session cleaned up" }

# File Upload
POST   /api/v2/upload/sessions/{session_id}/files
    Content-Type: multipart/form-data
    Body: { "file": File, "file_type": "data|config" }
    → { "file_id": "uuid", "name": "file.dat", "size": 1024 }

POST   /api/v2/upload/sessions/{session_id}/chunks
    Content-Type: application/octet-stream
    Headers: {
        "X-Chunk-Index": 0,
        "X-Total-Chunks": 10,
        "X-File-Name": "large_file.dat",
        "X-File-Type": "data"
    }
    → { "chunk_id": "uuid", "received": true }

POST   /api/v2/upload/sessions/{session_id}/finalize
    → { "files": [...], "total_size": 1024000 }

# Validation
POST   /api/v2/upload/sessions/{session_id}/validate
    Body: { "template_id": "uuid" }
    → {
        "valid": true,
        "classified_files": {
            "data": ["input.dat", "mesh.msh"],
            "config": ["config.json"]
        },
        "errors": []
    }

# External Frontend Support
POST   /api/v2/upload/external
    Headers: { "Authorization": "Bearer <JWT>" }
    Body: {
        "template_id": "uuid",
        "files": [
            { "name": "file1.dat", "url": "https://..." },
            { "name": "config.json", "content": "{...}" }
        ]
    }
    → { "job_id": "uuid", "status": "submitted" }
```

#### 3.3 Upload Progress WebSocket
**추가:** `websocket_5011/upload_events.py`

```python
# WebSocket 이벤트
{
    "type": "upload_progress",
    "session_id": "uuid",
    "file_name": "large_file.dat",
    "progress": 45,  # 0-100
    "uploaded_bytes": 450000000,
    "total_bytes": 1000000000,
    "speed": "10 MB/s",
    "eta": "00:05:30"
}

{
    "type": "upload_complete",
    "session_id": "uuid",
    "files": [...]
}

{
    "type": "upload_error",
    "session_id": "uuid",
    "error": "File validation failed"
}
```

#### 3.4 Frontend Upload Component
**새 컴포넌트:** `frontend_3010/src/components/FileUpload/`

```typescript
// UnifiedUploader.tsx
interface UnifiedUploaderProps {
  templateId?: string;
  onComplete: (files: UploadedFile[]) => void;
  maxFileSize?: number;
  acceptedTypes?: string[];
}

export const UnifiedUploader: React.FC<UnifiedUploaderProps> = ({
  templateId,
  onComplete,
  maxFileSize = 5 * 1024 * 1024 * 1024, // 5GB
  acceptedTypes
}) => {
  // Drag & Drop 지원
  // 다중 파일 업로드
  // 대용량 파일 청크 업로드
  // 실시간 진행률 표시 (WebSocket)
  // 파일 분류 UI (data/config)
  // 파일 미리보기
  // 업로드 취소/재시도
};

// ChunkUploader.ts - 대용량 파일 청크 업로드 유틸리티
class ChunkUploader {
  async uploadFile(file: File, sessionId: string, onProgress: (progress: number) => void) {
    const chunkSize = 10 * 1024 * 1024; // 10MB chunks
    const totalChunks = Math.ceil(file.size / chunkSize);

    for (let i = 0; i < totalChunks; i++) {
      const chunk = file.slice(i * chunkSize, (i + 1) * chunkSize);
      await this.uploadChunk(sessionId, chunk, i, totalChunks, file.name);
      onProgress((i + 1) / totalChunks * 100);
    }
  }
}
```

#### 3.5 External Frontend Integration Example
**외부 프론트엔드 (React/Vue/Angular)에서 사용:**

```javascript
// Example: External App Integration
const uploadFiles = async (files, templateId, jwtToken) => {
  // 1. Create upload session
  const sessionResponse = await fetch('http://api.example.com/api/v2/upload/sessions', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${jwtToken}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ template_id: templateId })
  });
  const { session_id } = await sessionResponse.json();

  // 2. Upload files
  for (const file of files) {
    const formData = new FormData();
    formData.append('file', file);
    formData.append('file_type', detectFileType(file.name));

    await fetch(`http://api.example.com/api/v2/upload/sessions/${session_id}/files`, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${jwtToken}` },
      body: formData
    });
  }

  // 3. Validate and submit
  const validateResponse = await fetch(`http://api.example.com/api/v2/upload/sessions/${session_id}/validate`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${jwtToken}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ template_id: templateId })
  });

  return validateResponse.json();
};
```

---

### Phase 4: Security & Infrastructure (2주)
**목표:** 보안 강화 및 인프라 최적화

#### 4.1 JWT Refresh Token System
**새 파일:** `auth_portal_4430/token_service.py`

```python
class TokenService:
    def generate_access_token(self, user_id: str, permissions: List[str]) -> str:
        """Access Token (15분 유효)"""
        return jwt.encode({
            'user_id': user_id,
            'permissions': permissions,
            'type': 'access',
            'exp': datetime.utcnow() + timedelta(minutes=15)
        }, SECRET_KEY, algorithm='HS256')

    def generate_refresh_token(self, user_id: str) -> str:
        """Refresh Token (7일 유효, Redis 저장)"""
        token = jwt.encode({
            'user_id': user_id,
            'type': 'refresh',
            'exp': datetime.utcnow() + timedelta(days=7)
        }, SECRET_KEY, algorithm='HS256')

        # Redis에 저장 (token revocation 지원)
        redis_client.setex(f"refresh_token:{user_id}", 7*24*3600, token)
        return token

    def refresh_access_token(self, refresh_token: str) -> str:
        """Refresh Token으로 새 Access Token 발급"""
        payload = jwt.decode(refresh_token, SECRET_KEY, algorithms=['HS256'])
        user_id = payload['user_id']

        # Redis에서 검증
        stored_token = redis_client.get(f"refresh_token:{user_id}")
        if stored_token != refresh_token:
            raise InvalidTokenError("Token revoked or invalid")

        return self.generate_access_token(user_id, get_user_permissions(user_id))

    def revoke_refresh_token(self, user_id: str):
        """Refresh Token 무효화 (로그아웃)"""
        redis_client.delete(f"refresh_token:{user_id}")
```

**API 엔드포인트:**
```
POST /api/auth/refresh
    Body: { "refresh_token": "..." }
    → { "access_token": "...", "expires_in": 900 }

POST /api/auth/logout
    Headers: { "Authorization": "Bearer <access_token>" }
    → { "message": "Logged out successfully" }
```

#### 4.2 CORS Configuration (Production)
**수정:** `backend_5010/app.py`

```python
from flask_cors import CORS

# Development
if os.getenv('FLASK_ENV') == 'development':
    CORS(app, origins='*')
else:
    # Production - 특정 origin만 허용
    CORS(app,
         origins=[
             'https://dashboard.example.com',
             'https://cae.example.com',
             'https://auth.example.com'
         ],
         supports_credentials=True,
         allow_headers=['Content-Type', 'Authorization'],
         expose_headers=['X-Total-Count', 'X-Page-Count'],
         max_age=3600)  # Preflight cache 1시간
```

**Nginx CORS 설정:**
```nginx
# /etc/nginx/sites-available/dashboard
location /api/ {
    # Preflight OPTIONS 처리
    if ($request_method = 'OPTIONS') {
        add_header 'Access-Control-Allow-Origin' 'https://dashboard.example.com';
        add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, DELETE, OPTIONS';
        add_header 'Access-Control-Allow-Headers' 'Authorization, Content-Type';
        add_header 'Access-Control-Max-Age' 3600;
        add_header 'Content-Length' 0;
        add_header 'Content-Type' 'text/plain';
        return 204;
    }

    proxy_pass http://localhost:5010;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
}
```

#### 4.3 Rate Limiting
**새 파일:** `backend_5010/middleware/rate_limiter.py`

```python
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address

limiter = Limiter(
    app,
    key_func=get_remote_address,
    storage_uri="redis://localhost:6379",
    default_limits=["200 per day", "50 per hour"]
)

# API별 제한
@app.route('/api/jobs/submit')
@limiter.limit("10 per minute")  # 작업 제출: 분당 10회
def submit_job():
    pass

@app.route('/api/nodes/<node>/reboot')
@limiter.limit("5 per hour")  # 노드 재부팅: 시간당 5회
def reboot_node(node):
    pass

@app.route('/api/upload/sessions/<session_id>/files')
@limiter.limit("100 per hour")  # 파일 업로드: 시간당 100개
def upload_file(session_id):
    pass
```

#### 4.4 Input Validation
**새 파일:** `backend_5010/validators.py`

```python
from marshmallow import Schema, fields, validate, ValidationError

class JobSubmitSchema(Schema):
    job_name = fields.Str(required=True, validate=validate.Length(min=1, max=100))
    partition = fields.Str(required=True, validate=validate.OneOf(['compute', 'gpu', 'viz']))
    nodes = fields.Int(required=True, validate=validate.Range(min=1, max=100))
    ntasks = fields.Int(validate=validate.Range(min=1, max=1000))
    time = fields.Str(validate=validate.Regexp(r'^\d{2}:\d{2}:\d{2}$'))
    script = fields.Str(required=True, validate=validate.Length(min=1, max=10000))

class NodeActionSchema(Schema):
    action = fields.Str(required=True, validate=validate.OneOf(['drain', 'resume', 'reboot']))
    reason = fields.Str(validate=validate.Length(max=500))

# 사용 예시
@app.route('/api/jobs/submit', methods=['POST'])
@jwt_required
def submit_job():
    schema = JobSubmitSchema()
    try:
        data = schema.load(request.json)
    except ValidationError as err:
        return jsonify({'errors': err.messages}), 400

    # 안전한 데이터 사용
    job_id = submit_slurm_job(data)
    return jsonify({'job_id': job_id}), 201
```

#### 4.5 Redis Caching Strategy
**새 파일:** `backend_5010/cache_manager.py`

```python
import redis
import json
from functools import wraps

redis_client = redis.Redis(
    host=os.getenv('REDIS_HOST', 'localhost'),
    port=int(os.getenv('REDIS_PORT', 6379)),
    password=os.getenv('REDIS_PASSWORD'),
    decode_responses=True
)

def cache_result(key_prefix: str, ttl: int = 300):
    """Redis 캐싱 데코레이터"""
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            # 캐시 키 생성
            cache_key = f"{key_prefix}:{':'.join(map(str, args))}"

            # 캐시 확인
            cached = redis_client.get(cache_key)
            if cached:
                return json.loads(cached)

            # 함수 실행
            result = func(*args, **kwargs)

            # 캐시 저장
            redis_client.setex(cache_key, ttl, json.dumps(result))
            return result
        return wrapper
    return decorator

# 사용 예시
@cache_result('sinfo', ttl=10)  # 10초 캐싱
def get_node_info():
    return subprocess.check_output(['sinfo', '-o', '%N,%C,%m,%t'], text=True)

@cache_result('squeue', ttl=5)  # 5초 캐싱
def get_job_queue():
    return subprocess.check_output(['squeue', '-o', '%i,%j,%u,%t,%M'], text=True)

@cache_result('apptainer_images', ttl=3600)  # 1시간 캐싱
def get_apptainer_images(partition):
    return scan_apptainer_images(partition)
```

#### 4.6 Nginx Optimization
**Nginx 설정:** `/etc/nginx/sites-available/dashboard`

```nginx
# Gzip 압축
gzip on;
gzip_vary on;
gzip_proxied any;
gzip_comp_level 6;
gzip_types text/plain text/css text/xml text/javascript
           application/json application/javascript application/xml+rss;

# 정적 파일 캐싱
location /assets/ {
    alias /var/www/html/dashboard_3010/assets/;
    expires 1y;
    add_header Cache-Control "public, immutable";
    access_log off;
}

location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
    expires 30d;
    add_header Cache-Control "public, immutable";
    access_log off;
}

# API 프록시 (캐싱 없음)
location /api/ {
    proxy_pass http://localhost:5010;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    # 타임아웃 설정
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;

    # 버퍼링
    proxy_buffering on;
    proxy_buffer_size 4k;
    proxy_buffers 8 4k;
}

# WebSocket 프록시
location /ws {
    proxy_pass http://localhost:5011;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;

    # WebSocket 타임아웃
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
}

# 업로드 크기 제한
client_max_body_size 5G;
client_body_buffer_size 128k;
client_body_timeout 300s;
```

#### 4.7 Logging System
**새 파일:** `backend_5010/logger_config.py`

```python
import logging
import logging.handlers
import json
from datetime import datetime

class JSONFormatter(logging.Formatter):
    def format(self, record):
        log_data = {
            'timestamp': datetime.utcnow().isoformat(),
            'level': record.levelname,
            'logger': record.name,
            'message': record.getMessage(),
            'module': record.module,
            'function': record.funcName,
            'line': record.lineno
        }

        if record.exc_info:
            log_data['exception'] = self.formatException(record.exc_info)

        return json.dumps(log_data)

def setup_logging():
    # 루트 로거
    logger = logging.getLogger()
    logger.setLevel(logging.DEBUG if os.getenv('FLASK_DEBUG') else logging.INFO)

    # 콘솔 핸들러
    console_handler = logging.StreamHandler()
    console_handler.setFormatter(JSONFormatter())
    logger.addHandler(console_handler)

    # 파일 핸들러 (일별 로테이션)
    file_handler = logging.handlers.TimedRotatingFileHandler(
        '/var/log/dashboard/app.log',
        when='midnight',
        interval=1,
        backupCount=30
    )
    file_handler.setFormatter(JSONFormatter())
    logger.addHandler(file_handler)

    # API별 로거
    api_logger = logging.getLogger('api')
    api_file_handler = logging.handlers.TimedRotatingFileHandler(
        '/var/log/dashboard/api.log',
        when='midnight',
        interval=1,
        backupCount=30
    )
    api_file_handler.setFormatter(JSONFormatter())
    api_logger.addHandler(api_file_handler)

    return logger

# 사용 예시
logger = setup_logging()
api_logger = logging.getLogger('api')

@app.route('/api/jobs/submit', methods=['POST'])
def submit_job():
    api_logger.info('Job submission request', extra={
        'user_id': g.user_id,
        'ip': request.remote_addr,
        'template_id': request.json.get('template_id')
    })

    try:
        job_id = submit_slurm_job(request.json)
        api_logger.info('Job submitted successfully', extra={'job_id': job_id})
        return jsonify({'job_id': job_id}), 201
    except Exception as e:
        api_logger.error('Job submission failed', extra={'error': str(e)}, exc_info=True)
        return jsonify({'error': str(e)}), 500
```

---

### Phase 5: Performance Optimization (1.5주)
**목표:** 백엔드/프론트엔드 성능 최적화

#### 5.1 Backend Async Processing
**수정:** `backend_5010/slurm_utils.py`

```python
import asyncio
import asyncssh

class AsyncSlurmClient:
    async def get_node_info_async(self, nodes: List[str]) -> dict:
        """병렬 노드 정보 조회"""
        tasks = [self._query_node(node) for node in nodes]
        results = await asyncio.gather(*tasks, return_exceptions=True)

        return {
            node: result if not isinstance(result, Exception) else None
            for node, result in zip(nodes, results)
        }

    async def _query_node(self, node: str) -> dict:
        """단일 노드 정보 조회"""
        async with asyncssh.connect(node, username='slurm') as conn:
            result = await conn.run('sinfo -n {} -o "%C,%m,%t"'.format(node))
            return self._parse_sinfo(result.stdout)

    async def submit_multiple_jobs(self, jobs: List[dict]) -> List[str]:
        """병렬 작업 제출"""
        tasks = [self._submit_job(job) for job in jobs]
        job_ids = await asyncio.gather(*tasks)
        return job_ids

    async def _submit_job(self, job: dict) -> str:
        """단일 작업 제출"""
        script = generate_job_script(job)
        async with asyncssh.connect('slurmctld', username='slurm') as conn:
            result = await conn.run(f'sbatch', input=script)
            return extract_job_id(result.stdout)

# Flask에서 사용
@app.route('/api/nodes/status', methods=['GET'])
async def get_nodes_status():
    client = AsyncSlurmClient()
    nodes = ['node001', 'node002', 'viz-node001', 'viz-node002']
    results = await client.get_node_info_async(nodes)
    return jsonify(results)
```

#### 5.2 Database Optimization
**인덱스 추가 및 쿼리 최적화:**

```sql
-- 복합 인덱스
CREATE INDEX idx_notifications_user_read ON notifications(created_by, read, timestamp DESC);
CREATE INDEX idx_templates_category_public ON job_templates_v2(category, is_public);
CREATE INDEX idx_jobs_user_status ON job_history(user_id, status, submit_time DESC);

-- 쿼리 최적화
EXPLAIN QUERY PLAN
SELECT * FROM notifications
WHERE created_by = 'user123' AND read = 0
ORDER BY timestamp DESC
LIMIT 20;

-- 파티션 추가 (대용량 데이터)
-- job_history 테이블을 월별로 파티션
```

#### 5.3 Frontend Code Splitting
**수정:** `frontend_3010/vite.config.ts`

```typescript
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  build: {
    rollupOptions: {
      output: {
        manualChunks: {
          // Vendor chunks
          'react-vendor': ['react', 'react-dom', 'react-router-dom'],
          'ui-vendor': ['lucide-react', '@heroicons/react'],
          'state-vendor': ['zustand'],
          'chart-vendor': ['recharts'],
          '3d-vendor': ['three', '@react-three/fiber', '@react-three/drei'],

          // Feature chunks
          'job-management': [
            './src/components/JobManagement.tsx',
            './src/components/JobTemplates'
          ],
          'node-management': ['./src/components/NodeManagement'],
          'ssh-vnc': [
            './src/components/SSHSessionManager.tsx',
            './src/components/VNCSessionManager.tsx'
          ],
          'data-management': ['./src/components/DataManagement'],
          'reports': ['./src/components/Reports']
        }
      }
    },
    chunkSizeWarningLimit: 1000
  }
});
```

**Lazy Loading:**
```typescript
// frontend_3010/src/App.tsx
import { lazy, Suspense } from 'react';

const Dashboard = lazy(() => import('./components/Dashboard'));
const JobManagement = lazy(() => import('./components/JobManagement'));
const NodeManagement = lazy(() => import('./components/NodeManagement'));
const SSHSessionManager = lazy(() => import('./components/SSHSessionManager'));
const VNCSessionManager = lazy(() => import('./components/VNCSessionManager'));

function App() {
  return (
    <Suspense fallback={<LoadingSpinner />}>
      <Routes>
        <Route path="/" element={<Dashboard />} />
        <Route path="/jobs" element={<JobManagement />} />
        <Route path="/nodes" element={<NodeManagement />} />
        <Route path="/ssh" element={<SSHSessionManager />} />
        <Route path="/vnc" element={<VNCSessionManager />} />
      </Routes>
    </Suspense>
  );
}
```

#### 5.4 React Performance
**최적화 예시:**

```typescript
// Memoization
import { memo, useMemo, useCallback } from 'react';

export const JobCard = memo<JobCardProps>(({ job }) => {
  const formattedTime = useMemo(() => formatTime(job.time), [job.time]);

  const handleCancel = useCallback(() => {
    cancelJob(job.id);
  }, [job.id]);

  return (
    <div>
      <h3>{job.name}</h3>
      <p>{formattedTime}</p>
      <button onClick={handleCancel}>Cancel</button>
    </div>
  );
});

// Virtual Scrolling (react-window)
import { FixedSizeList } from 'react-window';

const JobList: React.FC<{ jobs: Job[] }> = ({ jobs }) => {
  const Row = ({ index, style }) => (
    <div style={style}>
      <JobCard job={jobs[index]} />
    </div>
  );

  return (
    <FixedSizeList
      height={600}
      itemCount={jobs.length}
      itemSize={80}
      width="100%"
    >
      {Row}
    </FixedSizeList>
  );
};
```

#### 5.5 WebSocket Optimization
**수정:** `websocket_5011/websocket_server.py`

```python
# 메시지 배칭
class MessageBatcher:
    def __init__(self, interval=1.0):
        self.buffer = []
        self.interval = interval

    async def add_message(self, message: dict):
        self.buffer.append(message)

        if len(self.buffer) >= 10:  # 10개 모이면 즉시 전송
            await self.flush()

    async def flush(self):
        if not self.buffer:
            return

        batch = {
            'type': 'batch',
            'messages': self.buffer,
            'timestamp': datetime.now().isoformat()
        }

        await broadcast_to_all(batch)
        self.buffer = []

# 선택적 브로드캐스트 (채널 기반)
subscriptions = {}  # {client_id: Set[channel]}

async def broadcast_to_channel(channel: str, message: dict):
    """특정 채널 구독자에게만 메시지 전송"""
    for client_id, channels in subscriptions.items():
        if channel in channels:
            await send_to_client(client_id, message)

# 압축 전송 (대용량 데이터)
import zlib

async def send_compressed(ws: web.WebSocketResponse, data: dict):
    json_str = json.dumps(data)
    compressed = zlib.compress(json_str.encode('utf-8'))

    await ws.send_bytes(compressed)
```

---

### Phase 6: Testing & Documentation (1주)
**목표:** 테스트 코드 작성 및 문서화

#### 6.1 Backend Tests
**새 디렉토리:** `backend_5010/tests/`

```python
# tests/test_apptainer_service.py
import pytest
from apptainer_service import ApptainerService

@pytest.fixture
def apptainer_service():
    return ApptainerService()

def test_scan_node_images(apptainer_service):
    images = apptainer_service.scan_node_images('node001')
    assert len(images) > 0
    assert all(img.path.endswith('.sif') for img in images)

def test_get_image_metadata(apptainer_service):
    metadata = apptainer_service.get_image_metadata('/opt/apptainers/test.sif')
    assert 'name' in metadata
    assert 'size' in metadata

# tests/test_template_manager.py
def test_create_template():
    template_data = {
        'name': 'test_template',
        'category': 'ml',
        'input_file_schema': {...}
    }
    template_id = template_manager.create_template(template_data)
    assert template_id is not None

def test_validate_input_files():
    files = [...]
    result = template_manager.validate_input_files('template_id', files)
    assert result['valid'] == True

# tests/test_upload_service.py
def test_create_upload_session():
    session_id = upload_service.create_upload_session('user123')
    assert len(session_id) == 36  # UUID

def test_upload_chunk():
    chunk = b'test data'
    result = upload_service.upload_chunk('session_id', chunk, 0)
    assert result['received'] == True
```

**실행:**
```bash
cd backend_5010
pytest tests/ --cov=. --cov-report=html
```

#### 6.2 Frontend Tests
**새 디렉토리:** `frontend_3010/src/__tests__/`

```typescript
// __tests__/ApptainerSelector.test.tsx
import { render, screen, fireEvent } from '@testing-library/react';
import { ApptainerSelector } from '../components/ApptainerSelector';

describe('ApptainerSelector', () => {
  it('renders image list', async () => {
    render(<ApptainerSelector partition="compute" onSelect={jest.fn()} />);

    const images = await screen.findAllByRole('listitem');
    expect(images.length).toBeGreaterThan(0);
  });

  it('filters by partition', () => {
    const { rerender } = render(
      <ApptainerSelector partition="compute" onSelect={jest.fn()} />
    );

    expect(screen.queryByText('vnc_gnome.sif')).not.toBeInTheDocument();

    rerender(<ApptainerSelector partition="viz" onSelect={jest.fn()} />);
    expect(screen.getByText('vnc_gnome.sif')).toBeInTheDocument();
  });

  it('calls onSelect when image is selected', () => {
    const onSelect = jest.fn();
    render(<ApptainerSelector onSelect={onSelect} />);

    const firstImage = screen.getAllByRole('button')[0];
    fireEvent.click(firstImage);

    expect(onSelect).toHaveBeenCalledWith(expect.objectContaining({
      name: expect.any(String),
      path: expect.any(String)
    }));
  });
});

// __tests__/UnifiedUploader.test.tsx
describe('UnifiedUploader', () => {
  it('uploads files successfully', async () => {
    const onComplete = jest.fn();
    render(<UnifiedUploader onComplete={onComplete} />);

    const file = new File(['test'], 'test.dat', { type: 'application/octet-stream' });
    const input = screen.getByLabelText('Upload files');

    fireEvent.change(input, { target: { files: [file] } });

    await waitFor(() => {
      expect(onComplete).toHaveBeenCalled();
    });
  });
});
```

#### 6.3 E2E Tests
**새 디렉토리:** `frontend_3010/e2e/`

```typescript
// e2e/job-submission.spec.ts
import { test, expect } from '@playwright/test';

test.describe('Job Submission Flow', () => {
  test('complete job submission with apptainer', async ({ page }) => {
    await page.goto('http://localhost:3010');

    // Login
    await page.fill('input[name="username"]', 'testuser');
    await page.fill('input[name="password"]', 'password');
    await page.click('button[type="submit"]');

    // Navigate to job submission
    await page.click('text=Submit Job');

    // Select template
    await page.click('text=ML Training');

    // Select apptainer image
    await page.click('[data-testid="apptainer-selector"]');
    await page.click('text=KooSimulationPython313.sif');

    // Upload files
    await page.setInputFiles('input[type="file"]', ['test-files/input.dat']);

    // Fill job options
    await page.fill('input[name="job_name"]', 'test_job');
    await page.selectOption('select[name="partition"]', 'compute');

    // Submit
    await page.click('button:has-text("Submit")');

    // Verify success
    await expect(page.locator('text=Job submitted successfully')).toBeVisible();
  });
});
```

#### 6.4 API Documentation
**새 파일:** `backend_5010/docs/API_REFERENCE.md`

```markdown
# API Reference

## Apptainer APIs

### List Apptainer Images
\`\`\`http
GET /api/apptainer/images?partition={partition}
\`\`\`

**Query Parameters:**
- `partition` (optional): Filter by partition (compute, viz)
- `type` (optional): Filter by type (viz, compute, custom)

**Response:**
\`\`\`json
{
  "images": [
    {
      "id": "uuid",
      "name": "KooSimulationPython313.sif",
      "path": "/opt/apptainers/KooSimulationPython313.sif",
      "node": "node001",
      "partition": "compute",
      "type": "compute",
      "size": 453000000,
      "apps": ["python", "jupyter"],
      "created_at": "2025-11-05T12:00:00Z"
    }
  ],
  "total": 10
}
\`\`\`

## Template APIs

### Create Template
\`\`\`http
POST /api/v2/templates
\`\`\`

**Request Body:**
\`\`\`json
{
  "name": "ml_training",
  "display_name": "ML Training Template",
  "category": "ml",
  "partition": "compute",
  "apptainer_image_id": "uuid",
  "input_file_schema": { ... },
  "main_script": "#!/bin/bash\n..."
}
\`\`\`

## Upload APIs

### Create Upload Session
\`\`\`http
POST /api/v2/upload/sessions
\`\`\`

**Request Body:**
\`\`\`json
{
  "template_id": "uuid"
}
\`\`\`

**Response:**
\`\`\`json
{
  "session_id": "uuid",
  "expires_at": "2025-11-05T13:00:00Z"
}
\`\`\`
```

#### 6.5 User Documentation
**새 파일:** `frontend_3010/docs/USER_GUIDE.md`

```markdown
# User Guide

## Job Submission with Apptainer

### Step 1: Select Template
1. Navigate to "Submit Job" page
2. Browse templates by category
3. Select a template (e.g., "ML Training")

### Step 2: Select Apptainer Image
1. Click "Select Container"
2. Choose an image from the list
3. (Optional) Select a specific app within the container

### Step 3: Upload Files
1. Drag & drop files or click "Browse"
2. Files are automatically classified:
   - **Data files**: .dat, .csv, .msh
   - **Config files**: .json, .yaml, .xml
3. Wait for upload to complete

### Step 4: Configure Job
1. Set job name
2. Select partition
3. Adjust resources (nodes, CPUs, memory)
4. Set time limit

### Step 5: Submit
1. Review script preview
2. Click "Submit Job"
3. Monitor job status in Dashboard
```

---

## 📊 Implementation Timeline

### Phase 1: Apptainer Integration (2주)
- Week 1: Backend service + Database schema
- Week 2: Frontend components + Integration tests

### Phase 2: Template Management (2주)
- Week 1: Template schema + API
- Week 2: Frontend template manager

### Phase 3: File Upload API (1.5주)
- Week 1: Upload service + Chunking
- Week 2: Frontend uploader + External integration

### Phase 4: Security & Infrastructure (2주)
- Week 1: JWT refresh + CORS + Rate limiting
- Week 2: Redis caching + Nginx optimization + Logging

### Phase 5: Performance Optimization (1.5주)
- Week 1: Backend async + Database optimization
- Week 2: Frontend code splitting + React optimization

### Phase 6: Testing & Documentation (1주)
- Days 1-3: Backend tests
- Days 4-5: Frontend tests
- Days 6-7: Documentation

**Total Duration: 10 weeks (~2.5 months)**

---

## 🚀 Deployment Strategy

### Phase 별 배포 전략

#### Phase 1-3: Feature Branches
```bash
git checkout -b feature/apptainer-integration
git checkout -b feature/template-management
git checkout -b feature/file-upload-api
```

#### Phase 4-5: Staging Environment
```bash
# Staging 배포
./deploy.sh staging

# 성능 테스트
ab -n 1000 -c 100 http://staging.example.com/api/nodes

# 부하 테스트
locust -f loadtest.py --host=http://staging.example.com
```

#### Phase 6: Production Rollout
```bash
# Blue-Green Deployment
./deploy.sh production --strategy=blue-green

# Canary Release (10% traffic)
./deploy.sh production --strategy=canary --traffic=10

# Full rollout
./deploy.sh production --strategy=canary --traffic=100
```

---

## 📈 Success Metrics

### Performance Metrics
- API 응답 시간: < 200ms (P95)
- WebSocket 지연: < 50ms
- 페이지 로드: < 2초
- 대용량 파일 업로드: > 50 MB/s

### Reliability Metrics
- API 가용성: > 99.9%
- WebSocket 연결 성공률: > 99%
- 작업 제출 성공률: > 99.5%

### Security Metrics
- JWT 토큰 무효화 응답: < 100ms
- Rate limit 적용률: 100%
- Input validation 성공률: 100%

### User Metrics
- Template 사용률: > 80% (작업의 80%가 템플릿 사용)
- Apptainer 사용률: > 70%
- 평균 파일 업로드 실패율: < 1%

---

## 🔧 Migration Guide

### 기존 시스템에서 마이그레이션

#### 1. Database Migration
```bash
# 백업
sqlite3 dashboard.db ".backup dashboard.db.backup"

# 스키마 마이그레이션
python migrate_database.py --from v3.0 --to v4.0

# 검증
python verify_migration.py
```

#### 2. API 마이그레이션
```bash
# v1 API → v2 API
# v1은 6개월간 유지 (Deprecation Period)
# 클라이언트에게 경고 헤더 전송
X-API-Version: v1 (deprecated, use v2)
X-Deprecation-Date: 2026-05-01
```

#### 3. Frontend 마이그레이션
```bash
# 기존 컴포넌트 유지하며 새 컴포넌트 추가
# Feature Flag로 점진적 롤아웃
VITE_ENABLE_APPTAINER=true
VITE_ENABLE_V2_TEMPLATES=true
VITE_ENABLE_UNIFIED_UPLOAD=true
```

---

## 📝 Notes

### 주의사항
1. **Redis 필수**: Phase 4부터 Redis 필수 의존성
2. **Breaking Changes**: v2 API는 v1과 호환되지 않음 (6개월 deprecation 기간 제공)
3. **Database Migration**: 다운타임 최소화를 위해 점진적 마이그레이션 권장
4. **Apptainer 버전**: Apptainer 1.0+ 필요

### 추가 개선 고려사항
- **GraphQL API**: REST API 대신 GraphQL 도입 검토
- **gRPC**: 노드 간 통신을 gRPC로 전환 검토
- **Kubernetes**: 컨테이너 오케스트레이션 도입 검토
- **Service Mesh**: Istio/Linkerd 도입 검토

---

## 🚀 Phase-by-Phase 실행 가이드 (Quick Reference)

### Phase 1: Apptainer Discovery & Integration

#### 실행 순서
```bash
# 1. 백업
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory
git add -A && git commit -m "Backup before Phase 1"

# 2. Backend 구현
# - backend_5010/apptainer_service.py 생성
# - backend_5010/apptainer_api.py 생성
# - backend_5010/migrations/v4.1.0_apptainer_images.sql 생성

# 3. Frontend 구현
# - frontend_3010/src/components/ApptainerSelector.tsx 생성
# - frontend_3010/src/hooks/useApptainerImages.ts 생성

# 4. 빌드 및 배포
cd dashboard/frontend_3010 && npm run build
sudo ./cluster/setup/phase5_web_services.sh

# 5. 검증
curl http://192.168.0.201:5010/api/apptainer/images
curl http://192.168.0.201:5010/api/health
```

#### 체크리스트
- [ ] `backend_5010/apptainer_service.py` 생성 완료
- [ ] `backend_5010/apptainer_api.py` 생성 완료
- [ ] DB 마이그레이션 스크립트 생성 완료
- [ ] Frontend ApptainerSelector 컴포넌트 생성 완료
- [ ] phase5_web_services.sh에 마이그레이션 추가 완료
- [ ] 빌드 성공 확인
- [ ] API 엔드포인트 정상 응답 확인
- [ ] 기존 Job Submit 기능 정상 동작 확인

---

### Phase 2: Template Management System

#### 실행 순서
```bash
# 1. 백업
git add -A && git commit -m "Backup before Phase 2"

# 2. Template Storage 초기화
sudo ./cluster/setup/init_template_storage.sh

# 3. Backend 구현
# - backend_5010/template_loader.py 생성
# - backend_5010/template_watcher.py 생성
# - backend_5010/templates_api_v2.py 생성
# - backend_5010/template_manager.py 생성
# - backend_5010/migrations/v4.2.0_templates_v2.sql 생성

# 4. requirements.txt 업데이트
# watchdog>=3.0.0 추가

# 5. Frontend 구현
# - frontend_3010/src/components/TemplateManager/ 디렉토리 생성
# - TemplateEditor.tsx, TemplateList.tsx, TemplateImportExport.tsx 생성

# 6. 빌드 및 배포
cd dashboard/frontend_3010 && npm run build
sudo ./cluster/setup/phase5_web_services.sh

# 7. 검증
curl http://192.168.0.201:5010/api/v2/templates
curl http://192.168.0.201:5010/api/v2/templates/scan -X POST
ls -la /shared/templates/official/
```

#### 체크리스트
- [ ] `/shared/templates/` 디렉토리 구조 생성 완료
- [ ] `template_loader.py` 구현 완료
- [ ] `template_watcher.py` 구현 완료
- [ ] `templates_api_v2.py` 구현 완료
- [ ] DB 마이그레이션 완료
- [ ] Frontend TemplateManager 컴포넌트 구현 완료
- [ ] requirements.txt 업데이트 완료
- [ ] YAML 템플릿 파일 파싱 정상 동작 확인
- [ ] Hot Reload 동작 확인
- [ ] 기존 Job Submit 기능 정상 동작 확인

---

### Phase 3: Unified File Upload API

#### 실행 순서
```bash
# 1. 백업
git add -A && git commit -m "Backup before Phase 3"

# 2. Backend 구현
# - backend_5010/file_upload_api.py 생성
# - backend_5010/file_classifier.py 생성
# - backend_5010/migrations/v4.3.0_file_uploads.sql 생성

# 3. WebSocket 업데이트
# - websocket_5011/websocket_server.py 업데이트 (progress 채널 추가)

# 4. Frontend 구현
# - frontend_3010/src/components/UnifiedUploader.tsx 생성
# - frontend_3010/src/hooks/useFileUpload.ts 생성

# 5. 빌드 및 배포
cd dashboard/frontend_3010 && npm run build
sudo ./cluster/setup/phase5_web_services.sh
sudo systemctl restart websocket_5011

# 6. 검증
# - 작은 파일 업로드 테스트
# - 대용량 파일 (1GB+) 업로드 테스트
curl http://192.168.0.201:5010/api/v2/files/upload -X POST -F "file=@test.dat"
```

#### 체크리스트
- [ ] `file_upload_api.py` 구현 완료
- [ ] `file_classifier.py` 구현 완료
- [ ] DB 마이그레이션 완료
- [ ] WebSocket progress 채널 추가 완료
- [ ] Frontend UnifiedUploader 컴포넌트 구현 완료
- [ ] 청크 업로드 정상 동작 확인
- [ ] 파일 분류 (data/config) 정상 동작 확인
- [ ] 대용량 파일 업로드 성공 확인
- [ ] 업로드 진행률 실시간 표시 확인
- [ ] 기존 Job Submit 기능 정상 동작 확인

---

### Phase 4: Security & Infrastructure

#### 실행 순서
```bash
# 1. 백업
git add -A && git commit -m "Backup before Phase 4"

# 2. Redis 설치 및 설정
sudo apt-get install redis-server -y
sudo systemctl enable redis-server
sudo systemctl start redis-server

# 3. Backend 보안 강화
# - backend_5010/security/jwt_refresh.py 생성
# - backend_5010/security/rate_limiter.py 생성
# - backend_5010/security/input_validator.py 생성
# - backend_5010/security/cors_config.py 생성

# 4. requirements.txt 업데이트
# redis>=4.5.0, flask-limiter>=3.3.0, marshmallow>=3.19.0 추가

# 5. Nginx 설정
# - cluster/setup/config/nginx_dashboard.conf 생성
# - phase5_web_services.sh 업데이트 (Nginx 설정 추가)

# 6. 빌드 및 배포
cd dashboard/frontend_3010 && npm run build
sudo ./cluster/setup/phase5_web_services.sh

# 7. 검증
redis-cli ping
curl -I http://192.168.0.201:5010/api/health
# Rate limit 테스트 (100번 반복 요청)
```

#### 체크리스트
- [ ] Redis 설치 및 실행 확인
- [ ] JWT Refresh Token 구현 완료
- [ ] Rate Limiter 구현 완료
- [ ] Input Validator 구현 완료
- [ ] CORS 설정 업데이트 완료
- [ ] Nginx 설정 파일 생성 완료
- [ ] requirements.txt 업데이트 완료
- [ ] 빌드 및 배포 성공 확인
- [ ] Rate limiting 정상 동작 확인
- [ ] JWT refresh 정상 동작 확인
- [ ] 기존 Job Submit 기능 정상 동작 확인

---

### Phase 5: Performance Optimization

#### 실행 순서
```bash
# 1. 백업
git add -A && git commit -m "Backup before Phase 5"

# 2. Backend 최적화
# - backend_5010/cache/redis_cache.py 생성
# - backend_5010/async_tasks.py 업데이트 (비동기 개선)

# 3. Frontend 최적화
# - React.lazy(), Suspense 적용
# - Code Splitting 설정 (vite.config.ts 업데이트)
# - 컴포넌트 메모이제이션 (React.memo, useMemo 적용)

# 4. 빌드 및 배포
cd dashboard/frontend_3010
npm run build
npm run build:check  # TypeScript 체크
sudo ./cluster/setup/phase5_web_services.sh

# 5. 성능 측정
# - Lighthouse 실행
# - API 응답 시간 측정
```

#### 체크리스트
- [ ] Redis 캐싱 레이어 구현 완료
- [ ] Backend 비동기 처리 개선 완료
- [ ] Frontend Code Splitting 적용 완료
- [ ] React 컴포넌트 최적화 완료
- [ ] 빌드 크기 감소 확인
- [ ] API 응답 시간 < 200ms (P95) 확인
- [ ] 페이지 로드 시간 < 2초 확인
- [ ] WebSocket 지연 < 50ms 확인
- [ ] 기존 Job Submit 기능 정상 동작 확인

---

### Phase 6: Testing & Documentation

#### 실행 순서
```bash
# 1. 백업
git add -A && git commit -m "Backup before Phase 6"

# 2. Backend 테스트 작성
# - backend_5010/tests/ 디렉토리에 테스트 추가
cd dashboard/backend_5010
python -m pytest tests/ -v

# 3. Frontend 테스트 작성
# - frontend_3010/src/__tests__/ 디렉토리에 테스트 추가
cd dashboard/frontend_3010
npm run test:run

# 4. E2E 테스트 작성
# - frontend_3010/e2e/ 디렉토리에 E2E 테스트 추가
npm run test:e2e  # Playwright 실행

# 5. API 문서 생성
# - backend_5010/docs/API_REFERENCE.md 생성
# - Swagger/OpenAPI 스펙 생성

# 6. 사용자 가이드 작성
# - dashboard/USER_GUIDE.md 생성
# - dashboard/ADMIN_GUIDE.md 생성

# 7. 최종 배포
sudo ./cluster/setup/setup_cluster_full_multihead.sh
```

#### 체크리스트
- [ ] Backend 유닛 테스트 작성 완료 (커버리지 > 80%)
- [ ] Frontend 유닛 테스트 작성 완료 (커버리지 > 70%)
- [ ] E2E 테스트 작성 완료
- [ ] API 문서 생성 완료
- [ ] 사용자 가이드 작성 완료
- [ ] 관리자 가이드 작성 완료
- [ ] 전체 시스템 배포 성공 확인
- [ ] 모든 테스트 통과 확인
- [ ] Job Submit 전체 플로우 정상 동작 확인

---

## 🔍 전체 시스템 검증 스크립트

### verify_system_health.sh
```bash
#!/bin/bash
# cluster/tests/verify_system_health.sh

set -e

echo "=========================================="
echo "System Health Check"
echo "=========================================="

# 1. 서비스 상태 확인
echo -e "\n[1/8] Checking services..."
sudo systemctl is-active --quiet auth_backend && echo "✅ auth_backend running" || echo "❌ auth_backend stopped"
sudo systemctl is-active --quiet prometheus && echo "✅ prometheus running" || echo "❌ prometheus stopped"
sudo systemctl is-active --quiet websocket_5011 && echo "✅ websocket_5011 running" || echo "❌ websocket_5011 stopped"

# 2. API 응답 확인
echo -e "\n[2/8] Checking API endpoints..."
curl -s -o /dev/null -w "%{http_code}" http://192.168.0.201:5010/api/health | grep -q "200" && echo "✅ Backend API responding" || echo "❌ Backend API error"
curl -s -o /dev/null -w "%{http_code}" http://192.168.0.201:3010/ | grep -q "200" && echo "✅ Frontend serving" || echo "❌ Frontend error"

# 3. WebSocket 연결 확인
echo -e "\n[3/8] Checking WebSocket..."
timeout 5 nc -zv 192.168.0.201 5011 2>&1 | grep -q "succeeded" && echo "✅ WebSocket port open" || echo "❌ WebSocket port closed"

# 4. Redis 연결 확인
echo -e "\n[4/8] Checking Redis..."
redis-cli ping | grep -q "PONG" && echo "✅ Redis responding" || echo "❌ Redis error"

# 5. DB 확인
echo -e "\n[5/8] Checking Database..."
if [ -f /home/koopark/web_services/backend/dashboard.db ]; then
    echo "✅ Database file exists"
    # 테이블 존재 확인
    sqlite3 /home/koopark/web_services/backend/dashboard.db "SELECT name FROM sqlite_master WHERE type='table' AND name='apptainer_images';" | grep -q "apptainer_images" && echo "✅ apptainer_images table exists" || echo "⚠️  apptainer_images table missing"
else
    echo "❌ Database file missing"
fi

# 6. Template Storage 확인
echo -e "\n[6/8] Checking Template Storage..."
[ -d /shared/templates/official ] && echo "✅ Template storage exists" || echo "❌ Template storage missing"

# 7. Apptainer 이미지 확인
echo -e "\n[7/8] Checking Apptainer Images..."
ssh compute-node001 "ls /opt/apptainers/*.sif" &>/dev/null && echo "✅ Compute node images accessible" || echo "❌ Compute node images not accessible"
ssh viz-node001 "ls /opt/apptainers/*.sif" &>/dev/null && echo "✅ Viz node images accessible" || echo "❌ Viz node images not accessible"

# 8. 디스크 공간 확인
echo -e "\n[8/8] Checking Disk Space..."
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -lt 90 ]; then
    echo "✅ Disk space OK ($DISK_USAGE% used)"
else
    echo "⚠️  Disk space high ($DISK_USAGE% used)"
fi

echo -e "\n=========================================="
echo "Health Check Complete"
echo "=========================================="
```

### 사용 방법
```bash
# 실행 권한 부여
chmod +x cluster/tests/verify_system_health.sh

# Phase 시작 전 검증
./cluster/tests/verify_system_health.sh

# Phase 배포 후 검증
sudo ./cluster/setup/phase5_web_services.sh
./cluster/tests/verify_system_health.sh
```

---

## 📋 전체 Phase 진행 상황 트래킹

### Phase 진행 상황표
```
┌──────────┬───────────────────────────────┬──────────┬──────────┬──────────┐
│ Phase    │ 기능                          │ 상태     │ 시작일   │ 완료일   │
├──────────┼───────────────────────────────┼──────────┼──────────┼──────────┤
│ Phase 1  │ Apptainer Discovery           │ ⬜ TODO  │          │          │
│          │ - apptainer_service.py        │ ⬜ TODO  │          │          │
│          │ - apptainer_api.py            │ ⬜ TODO  │          │          │
│          │ - ApptainerSelector.tsx       │ ⬜ TODO  │          │          │
│          │ - DB Migration                │ ⬜ TODO  │          │          │
├──────────┼───────────────────────────────┼──────────┼──────────┼──────────┤
│ Phase 2  │ Template Management           │ ⬜ TODO  │          │          │
│          │ - init_template_storage.sh    │ ⬜ TODO  │          │          │
│          │ - template_loader.py          │ ⬜ TODO  │          │          │
│          │ - template_watcher.py         │ ⬜ TODO  │          │          │
│          │ - TemplateManager components  │ ⬜ TODO  │          │          │
│          │ - DB Migration                │ ⬜ TODO  │          │          │
├──────────┼───────────────────────────────┼──────────┼──────────┼──────────┤
│ Phase 3  │ File Upload API               │ ⬜ TODO  │          │          │
│          │ - file_upload_api.py          │ ⬜ TODO  │          │          │
│          │ - file_classifier.py          │ ⬜ TODO  │          │          │
│          │ - UnifiedUploader.tsx         │ ⬜ TODO  │          │          │
│          │ - WebSocket progress          │ ⬜ TODO  │          │          │
│          │ - DB Migration                │ ⬜ TODO  │          │          │
├──────────┼───────────────────────────────┼──────────┼──────────┼──────────┤
│ Phase 4  │ Security & Infrastructure     │ ⬜ TODO  │          │          │
│          │ - Redis setup                 │ ⬜ TODO  │          │          │
│          │ - JWT Refresh                 │ ⬜ TODO  │          │          │
│          │ - Rate Limiter                │ ⬜ TODO  │          │          │
│          │ - Input Validator             │ ⬜ TODO  │          │          │
│          │ - Nginx config                │ ⬜ TODO  │          │          │
├──────────┼───────────────────────────────┼──────────┼──────────┼──────────┤
│ Phase 5  │ Performance Optimization      │ ⬜ TODO  │          │          │
│          │ - Redis Cache Layer           │ ⬜ TODO  │          │          │
│          │ - Backend Async Optimization  │ ⬜ TODO  │          │          │
│          │ - Frontend Code Splitting     │ ⬜ TODO  │          │          │
│          │ - React Optimization          │ ⬜ TODO  │          │          │
├──────────┼───────────────────────────────┼──────────┼──────────┼──────────┤
│ Phase 6  │ Testing & Documentation       │ ⬜ TODO  │          │          │
│          │ - Backend Tests               │ ⬜ TODO  │          │          │
│          │ - Frontend Tests              │ ⬜ TODO  │          │          │
│          │ - E2E Tests                   │ ⬜ TODO  │          │          │
│          │ - API Documentation           │ ⬜ TODO  │          │          │
│          │ - User Guide                  │ ⬜ TODO  │          │          │
└──────────┴───────────────────────────────┴──────────┴──────────┴──────────┘

범례: ⬜ TODO | 🟦 IN PROGRESS | ✅ DONE | ❌ BLOCKED
```

---

## 📚 References

- [Apptainer Documentation](https://apptainer.org/docs/)
- [Slurm Documentation](https://slurm.schedmd.com/)
- [Flask Best Practices](https://flask.palletsprojects.com/)
- [React Performance](https://react.dev/learn/render-and-commit)
- [Redis Caching Strategies](https://redis.io/docs/manual/patterns/)

---

**문서 버전:** 1.1
**최종 수정일:** 2025-11-05
**작성자:** Dashboard Development Team
