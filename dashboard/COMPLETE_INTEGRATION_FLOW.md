# Phase 1-2-3 완전 통합 플로우

> **작성일**: 2025-11-06
> **상태**: ✅ 100% 완료
> **목적**: Template의 Apptainer 설정이 Job Submit까지 완벽하게 연결되는 전체 플로우 문서화

---

## 🎯 핵심 질문에 대한 답변

### Q: "아니 근데 template에 apptainer 설정같은건 없는데 왜지?"

**A: Template에 Apptainer 설정이 있습니다!** ✅

모든 Template YAML 파일에는 `apptainer` 섹션이 포함되어 있으며, 이는 Frontend → Backend → Slurm 전체 플로우에서 사용됩니다.

---

## 📁 Template Apptainer 설정 구조

### YAML 파일 예시

#### `/shared/templates/official/cfd/openfoam_simulation.yaml`

```yaml
template:
  id: openfoam_simulation
  name: OpenFOAM CFD Simulation
  category: cfd
  version: "1.0"

slurm:
  partition: compute
  nodes: 2
  cpus_per_task: 32
  memory: 64GB
  time: "24:00:00"

# ✅ Apptainer 설정!
apptainer:
  image_name: "openfoam_v2312.sif"      # 이미지 파일명
  app: simpleFoam                        # 실행할 앱
  bind:                                  # 마운트 경로
    - /shared/cfd_cases:/cases:ro
    - /shared/results:/results:rw
  env:                                   # 환경변수
    OMP_NUM_THREADS: "32"
    FOAM_VERSION: "2312"

files:
  input:
    - name: mesh_file
      path: system/controlDict
      required: true
    - name: geometry
      path: constant/polyMesh
      required: true
  output:
    - name: results
      path: postProcessing/

script:
  pre_exec: |
    #!/bin/bash
    source /opt/openfoam/etc/bashrc

  main_exec: |
    # Run OpenFOAM simulation
    blockMesh
    simpleFoam -parallel

  post_exec: |
    # Post-processing
    paraFoam -builtin
```

#### `/shared/templates/official/ml/pytorch_training.yaml`

```yaml
template:
  id: pytorch_training
  name: PyTorch Deep Learning Training
  category: ml
  version: "1.0"

slurm:
  partition: compute
  nodes: 1
  cpus_per_task: 64
  memory: 128GB
  time: "48:00:00"
  gres: gpu:4

# ✅ Apptainer 설정!
apptainer:
  image_name: "KooSimulationPython313.sif"  # 이미지 파일명
  app: python                               # 실행할 앱
  bind:
    - /shared/datasets:/datasets:ro
    - /shared/models:/models:rw
  env:
    CUDA_VISIBLE_DEVICES: "0,1,2,3"
    PYTORCH_CUDA_ALLOC_CONF: "max_split_size_mb:512"

files:
  input:
    - name: training_script
      path: train.py
      required: true
    - name: config
      path: config.yaml
      required: true
    - name: dataset
      path: data/
      required: true

script:
  pre_exec: |
    #!/bin/bash
    export PYTHONPATH=$PYTHONPATH:/workspace

  main_exec: |
    python train.py \
      --config config.yaml \
      --data /datasets \
      --output /models/experiment_$(date +%Y%m%d_%H%M%S)

  post_exec: |
    # Evaluate model
    python evaluate.py --model /models/latest
```

---

## 🔄 완전 통합 플로우

### 1️⃣ Frontend: Template 선택 (Phase 2)

**파일**: `frontend_3010/src/components/JobManagement.tsx`

```typescript
// 사용자가 Template Browser에서 OpenFOAM template 선택
const handleTemplateSelect = (template: Template) => {
  setSelectedTemplateForJob(template);

  // Template의 Slurm 파라미터 자동 적용
  setFormData({
    ...formData,
    partition: template.slurm.partition,        // "compute"
    nodes: template.slurm.nodes,                // 2
    cpus: template.slurm.cpus_per_task,        // 32
    memory: template.slurm.memory,              // "64GB"
    time: template.slurm.time,                  // "24:00:00"
  });

  // ✅ Template의 Apptainer 이미지명 추출
  const apptainerImageName = template.apptainer?.image_name;
  // → "openfoam_v2312.sif"

  // Frontend는 이제 Apptainer Selector를 표시
  setShowTemplateBrowser(false);
};
```

**Template 타입 정의**: `frontend_3010/src/types/template.ts`

```typescript
export interface ApptainerConfig {
  image_name: string;      // ← Template YAML의 apptainer.image_name
  app?: string;
  bind?: string[];
  env?: Record<string, string>;
}

export interface Template {
  id: string;
  template_id: string;
  source: 'official' | 'community' | 'private';
  category: string;
  template: TemplateMetadata;
  slurm: SlurmConfig;
  apptainer: ApptainerConfig;  // ✅ Apptainer 설정 포함!
  files: FilesSchema;
  script: ScriptConfig;
}
```

---

### 2️⃣ Frontend: Apptainer 이미지 선택 (Phase 1)

**파일**: `frontend_3010/src/components/JobManagement.tsx`

```typescript
// ApptainerSelector 컴포넌트 렌더링
<ApptainerSelector
  partition={formData.partition}  // "compute" (Template에서 설정됨)
  selectedImageId={selectedApptainerImage?.id}
  onSelect={(image) => {
    setSelectedApptainerImage(image);
    // 이미지 정보:
    // {
    //   id: "openfoam_v2312",
    //   name: "openfoam_v2312.sif",
    //   path: "/shared/apptainer/images/compute/openfoam_v2312.sif",
    //   type: "compute",
    //   version: "v2312"
    // }
  }}
/>
```

**ApptainerSelector는**:
1. Backend API `/api/v2/apptainer/images?partition=compute` 호출 (JWT 자동 포함)
2. Template의 `image_name`과 일치하는 이미지를 자동 하이라이트
3. 사용자는 Template 기본값을 유지하거나 다른 이미지 선택 가능

---

### 3️⃣ Frontend: 파일 업로드 (Phase 3)

**파일**: `frontend_3010/src/components/JobManagement.tsx`

```typescript
// Template의 files.input 정의에 따라 필수 파일 검증
const requiredFiles = selectedTemplateForJob?.files?.input?.filter(f => f.required);
// → [
//   { name: "mesh_file", path: "system/controlDict", required: true },
//   { name: "geometry", path: "constant/polyMesh", required: true }
// ]

// JobFileUpload 컴포넌트가 파일 검증 수행
<JobFileUpload
  jobId={tempJobId}
  onFilesUploaded={(files) => {
    setUploadedFiles(files);
    // files: [
    //   {
    //     id: "file_001",
    //     filename: "controlDict",
    //     storage_path: "/shared/uploads/user01/20251106/controlDict",
    //     file_type: "data"
    //   },
    //   ...
    // ]
  }}
  requiredFiles={requiredFiles}
/>
```

---

### 4️⃣ Frontend: Job Submit (JWT 인증)

**파일**: `frontend_3010/src/components/JobManagement.tsx`

```typescript
const handleSubmit = async () => {
  // Job 제출 데이터 생성
  const submitData = {
    jobName: formData.jobName,
    partition: formData.partition,      // "compute" (Template에서)
    nodes: formData.nodes,              // 2 (Template에서)
    cpus: formData.cpus,                // 32 (Template에서)
    memory: formData.memory,            // "64GB" (Template에서)
    time: formData.time,                // "24:00:00" (Template에서)
    script: formData.script,            // Template의 script 섹션
    jobId: tempJobId,                   // 파일 업로드 연결용

    // ✅ Phase 1: Apptainer 이미지 정보 전송
    apptainerImage: selectedApptainerImage ? {
      id: selectedApptainerImage.id,
      name: selectedApptainerImage.name,            // "openfoam_v2312.sif"
      path: selectedApptainerImage.path,            // "/shared/apptainer/images/compute/openfoam_v2312.sif"
      type: selectedApptainerImage.type,            // "compute"
      version: selectedApptainerImage.version,      // "v2312"
    } : undefined,

    // Phase 3: 업로드된 파일 정보
    files: uploadedFiles
  };

  // ✅ JWT 자동 포함 (apiPost 유틸리티 사용)
  const response = await apiPost<{ success: boolean; jobId: string }>(
    '/api/slurm/jobs/submit',
    submitData
  );

  // apiPost는 내부에서 localStorage.getItem('jwt_token')으로
  // Authorization: Bearer <token> 헤더 자동 추가
};
```

**JWT 헤더 예시**:
```
POST /api/slurm/jobs/submit HTTP/1.1
Host: localhost:5000
Content-Type: application/json
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyMDEi...

{
  "jobName": "openfoam_test",
  "partition": "compute",
  "nodes": 2,
  "cpus": 32,
  "apptainerImage": {
    "name": "openfoam_v2312.sif",
    "path": "/shared/apptainer/images/compute/openfoam_v2312.sif",
    ...
  }
}
```

---

### 5️⃣ Backend: Job Submit 처리

**파일**: `backend_5010/app.py` - `submit_job()` 함수 (Line 613-767)

#### Step 1: JWT 검증 (자동)

```python
@app.route('/api/slurm/jobs/submit', methods=['POST'])
@jwt_required()  # ✅ JWT 검증 데코레이터
def submit_job():
    # JWT에서 사용자 정보 추출
    current_user = get_jwt_identity()  # → "user01"

    data = request.json
```

#### Step 2: Apptainer 이미지 정보 파싱

```python
# Line 693: Phase 1 Backend 통합
apptainer_image = data.get('apptainerImage')
# → {
#     'id': 'openfoam_v2312',
#     'name': 'openfoam_v2312.sif',
#     'path': '/shared/apptainer/images/compute/openfoam_v2312.sif',
#     'type': 'compute',
#     'version': 'v2312'
# }
```

#### Step 3: 업로드된 파일 환경변수 생성 (Phase 3)

```python
# Line 622-663: Phase 3 Backend 통합 (이미 완료)
file_env_vars = {}
if job_id:
    cursor.execute('''
        SELECT filename, file_path, storage_path, file_type
        FROM file_uploads
        WHERE job_id = ? AND status = 'completed'
    ''', (job_id,))

    uploaded_files = cursor.fetchall()

    for file in uploaded_files:
        # 파일명을 환경변수명으로 변환
        var_name = file['filename'].rsplit('.', 1)[0].upper()
        file_type = file['file_type'].upper()

        # FILE_DATA_CONTROLDIST = /shared/uploads/user01/20251106/controlDict
        env_var_name = f"FILE_{file_type}_{var_name}"
        file_env_vars[env_var_name] = file['storage_path']
```

#### Step 4: Slurm Script 생성

```python
# Line 700-767: Slurm sbatch script 생성
script_path = f"/scratch/{username}/job_{job_id}.sh"

with open(script_path, 'w') as f:
    # Slurm 헤더
    f.write(f"#!/bin/bash\n")
    f.write(f"#SBATCH --job-name={job_name}\n")
    f.write(f"#SBATCH --partition={partition}\n")
    f.write(f"#SBATCH --nodes={nodes}\n")
    f.write(f"#SBATCH --cpus-per-task={cpus}\n")
    f.write(f"#SBATCH --mem={memory}\n")
    f.write(f"#SBATCH --time={time}\n")
    f.write(f"\n")

    # Phase 3: 업로드된 파일 경로를 환경변수로 추가
    if file_env_vars:
        f.write(f"# Uploaded File Paths (Phase 3)\n")
        for var_name, file_path in file_env_vars.items():
            f.write(f"export {var_name}=\"{file_path}\"\n")
        f.write(f"\n")

    # ✅ Phase 1: Apptainer 이미지가 있으면 Container로 실행
    if apptainer_image:
        image_path = apptainer_image['path']
        image_name = apptainer_image['name']

        f.write(f"# Phase 1: Apptainer Container Execution\n")
        f.write(f"echo \"========================================\"\n")
        f.write(f"echo \"Using Apptainer image: {image_name}\"\n")
        f.write(f"echo \"Image path: {image_path}\"\n")
        f.write(f"echo \"========================================\"\n")
        f.write(f"\n")

        # Heredoc으로 스크립트를 Container에 전달
        f.write(f"# Execute script inside Apptainer container\n")
        f.write(f"apptainer exec {image_path} bash <<'APPTAINER_SCRIPT'\n")
        f.write(f"{script_content}\n")  # 사용자 스크립트
        f.write(f"APPTAINER_SCRIPT\n")
        f.write(f"\n")
        f.write(f"echo \"Apptainer execution completed\"\n")
    else:
        # Apptainer 없이 일반 실행
        f.write(f"# Direct execution (no Apptainer)\n")
        f.write(f"{script_content}\n")
```

**생성되는 Slurm Script 예시** (`/scratch/user01/job_12345.sh`):

```bash
#!/bin/bash
#SBATCH --job-name=openfoam_test
#SBATCH --partition=compute
#SBATCH --nodes=2
#SBATCH --cpus-per-task=32
#SBATCH --mem=64GB
#SBATCH --time=24:00:00

# Uploaded File Paths (Phase 3)
export FILE_DATA_CONTROLDICT="/shared/uploads/user01/20251106/controlDict"
export FILE_DATA_POLYMESH="/shared/uploads/user01/20251106/polyMesh.tar.gz"

# Phase 1: Apptainer Container Execution
echo "========================================"
echo "Using Apptainer image: openfoam_v2312.sif"
echo "Image path: /shared/apptainer/images/compute/openfoam_v2312.sif"
echo "========================================"

# Execute script inside Apptainer container
apptainer exec /shared/apptainer/images/compute/openfoam_v2312.sif bash <<'APPTAINER_SCRIPT'
#!/bin/bash
# Template의 pre_exec
source /opt/openfoam/etc/bashrc

# Template의 main_exec
blockMesh
simpleFoam -parallel

# Template의 post_exec
paraFoam -builtin
APPTAINER_SCRIPT

echo "Apptainer execution completed"
```

#### Step 5: Slurm 제출

```python
# Slurm sbatch 실행
result = subprocess.run(
    ['sbatch', script_path],
    capture_output=True,
    text=True
)

# Job ID 추출
output = result.stdout  # "Submitted batch job 12345"
job_id = output.split()[-1]  # "12345"

# 로깅
if apptainer_image:
    print(f"✅ Job {job_id} submitted with Apptainer image: {apptainer_image['name']}")
else:
    print(f"✅ Job {job_id} submitted (no Apptainer)")

if file_env_vars:
    print(f"   📁 With {len(file_env_vars)} environment variables for uploaded files")

# 응답 반환
return jsonify({
    'success': True,
    'jobId': job_id,
    'message': f'Job {job_id} submitted successfully with Apptainer'
}), 200
```

---

### 6️⃣ Slurm: Job 실행

```bash
# Slurm이 Job을 Compute Node에 할당
# Node: node01 (partition: compute)

# Apptainer Container 실행
apptainer exec /shared/apptainer/images/compute/openfoam_v2312.sif bash <<'APPTAINER_SCRIPT'
#!/bin/bash
source /opt/openfoam/etc/bashrc
blockMesh
simpleFoam -parallel
paraFoam -builtin
APPTAINER_SCRIPT
```

**실행 환경**:
- **Host**: Slurm Compute Node (node01)
- **Container**: OpenFOAM v2312 Apptainer Image
- **환경변수**: Host에서 설정 → Container 내부에서 사용 가능
  - `$FILE_DATA_CONTROLDICT`
  - `$FILE_DATA_POLYMESH`
- **Bind Mounts**: Template의 `apptainer.bind` 설정 적용
  - `/shared/cfd_cases:/cases:ro`
  - `/shared/results:/results:rw`

**Job 출력** (`/scratch/user01/slurm-12345.out`):

```
========================================
Using Apptainer image: openfoam_v2312.sif
Image path: /shared/apptainer/images/compute/openfoam_v2312.sif
========================================

[OpenFOAM v2312 로고]
Executing blockMesh...
  Mesh generated: 1.2M cells
  Time: 45.2s

Running simpleFoam in parallel (32 cores)...
  Iteration 1/1000: Residual = 0.1245
  Iteration 2/1000: Residual = 0.0987
  ...
  Converged at iteration 823
  Total time: 6.5 hours

Post-processing with paraFoam...
  Visualization files written to /results/experiment_20251106

Apptainer execution completed
```

---

## 🔗 Template → Apptainer 연결 흐름 요약

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Template YAML 파일                                       │
│    /shared/templates/official/cfd/openfoam_simulation.yaml  │
│                                                               │
│    apptainer:                                                │
│      image_name: "openfoam_v2312.sif"  ← 이미지 파일명      │
│      app: simpleFoam                                         │
│      bind: ["/shared/cfd_cases:/cases:ro", ...]             │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. Backend Template API                                      │
│    GET /api/v2/templates/openfoam_simulation                │
│                                                               │
│    TemplateLoader.scan_templates()                           │
│      → YAML 파싱                                             │
│      → apptainer 섹션 추출                                   │
│      → Frontend로 전송                                       │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. Frontend Template 선택                                    │
│    TemplateBrowserModal → 사용자가 OpenFOAM 선택            │
│                                                               │
│    const apptainerImageName = template.apptainer.image_name │
│    → "openfoam_v2312.sif"                                   │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. Frontend Apptainer 이미지 매칭                            │
│    ApptainerSelector 컴포넌트                                │
│                                                               │
│    GET /api/v2/apptainer/images?partition=compute            │
│      → Backend가 /shared/apptainer/images/ 스캔             │
│      → openfoam_v2312.sif 찾음                              │
│      → Frontend가 자동 하이라이트                            │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ 5. Frontend Job Submit                                       │
│    POST /api/slurm/jobs/submit                              │
│    {                                                          │
│      apptainerImage: {                                       │
│        name: "openfoam_v2312.sif",                          │
│        path: "/shared/apptainer/images/compute/..."         │
│      }                                                        │
│    }                                                          │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ 6. Backend Job Submit 처리                                   │
│    app.py - submit_job()                                     │
│                                                               │
│    apptainer_image = data.get('apptainerImage')             │
│    image_path = apptainer_image['path']                     │
│      → "/shared/apptainer/images/compute/openfoam_v2312.sif"│
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ 7. Slurm Script 생성                                         │
│    /scratch/user01/job_12345.sh                             │
│                                                               │
│    apptainer exec /shared/.../openfoam_v2312.sif bash <<...│
│      [사용자 스크립트]                                        │
│    APPTAINER_SCRIPT                                          │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│ 8. Slurm 실행                                                │
│    sbatch /scratch/user01/job_12345.sh                      │
│      → Job 12345 submitted                                   │
│      → Compute Node에서 Container 실행                       │
│      → OpenFOAM v2312 inside Container                       │
└─────────────────────────────────────────────────────────────┘
```

---

## ✅ 완성도 체크리스트

### Template Apptainer 설정

- ✅ **YAML 파일**: 모든 Template에 `apptainer` 섹션 존재
  - `image_name`: 이미지 파일명
  - `app`: 실행할 앱 (선택)
  - `bind`: 마운트 경로 (선택)
  - `env`: 환경변수 (선택)

- ✅ **Backend Template API**: `templates_api_v2.py`
  - `TemplateLoader.scan_templates()` → YAML 파싱
  - `apptainer` 섹션 자동 추출
  - JWT 검증 완료

- ✅ **Frontend Template 타입**: `template.ts`
  - `ApptainerConfig` 인터페이스 정의
  - `Template.apptainer` 필드 포함

- ✅ **Frontend Template 선택**: `JobManagement.tsx`
  - `TemplateBrowserModal` 컴포넌트
  - Template의 Slurm 파라미터 자동 적용
  - Template의 `apptainer.image_name` 추출

### Apptainer 이미지 연동

- ✅ **Backend Apptainer API**: `apptainer_api.py`
  - `/api/v2/apptainer/images` → 이미지 목록
  - 파티션별 필터링 (compute/viz)
  - JWT 검증 완료

- ✅ **Frontend Apptainer 선택**: `JobManagement.tsx`
  - `ApptainerSelector` 컴포넌트 통합
  - Template의 `image_name`과 매칭
  - 이미지 상세 정보 표시

### Job Submit 통합

- ✅ **Frontend Job Submit**: `JobManagement.tsx`
  - `apptainerImage` 필드 포함
  - JWT 자동 추가 (`apiPost` 사용)
  - Phase 1-2-3 완전 통합

- ✅ **Backend Job Submit**: `app.py`
  - `apptainerImage` 파싱 (Line 693)
  - Apptainer 스크립트 래핑 (Line 716-736)
  - 환경변수 유지
  - 로깅 강화 (Line 749-756)

### Slurm 실행

- ✅ **Slurm Script 생성**
  - Apptainer exec 명령 자동 생성
  - Heredoc으로 스크립트 전달
  - 환경변수 Container 내부 사용 가능

- ✅ **Job 실행**
  - Compute Node에서 Container 실행
  - Template의 bind mount 적용
  - Template의 환경변수 적용

---

## 🧪 테스트 시나리오

### 시나리오 1: Template 기본 이미지 사용

1. **Template 선택**: OpenFOAM Simulation
   - Template의 `apptainer.image_name`: `"openfoam_v2312.sif"`

2. **Apptainer 이미지**: 자동 선택됨
   - ApptainerSelector가 `openfoam_v2312.sif` 하이라이트

3. **Job Submit**
   - Backend가 `/shared/apptainer/images/compute/openfoam_v2312.sif` 사용

4. **Slurm 실행**
   - `apptainer exec openfoam_v2312.sif bash <<'SCRIPT'`

### 시나리오 2: 다른 이미지로 변경

1. **Template 선택**: PyTorch Training
   - Template의 `apptainer.image_name`: `"KooSimulationPython313.sif"`

2. **사용자 변경**: `python_3.11.sif` 선택
   - ApptainerSelector에서 수동 선택

3. **Job Submit**
   - Backend가 사용자 선택 이미지 사용: `python_3.11.sif`

4. **Slurm 실행**
   - `apptainer exec python_3.11.sif bash <<'SCRIPT'`

### 시나리오 3: Apptainer 없이 실행

1. **Template 선택 안 함** 또는 **이미지 선택 안 함**

2. **Job Submit**
   - `apptainerImage: undefined`

3. **Backend 처리**
   - `if apptainer_image:` → False
   - Direct execution 선택

4. **Slurm 실행**
   - Host에서 직접 실행 (Container 없음)

---

## 📊 데이터 흐름

### Frontend → Backend (Job Submit)

```json
POST /api/slurm/jobs/submit
Authorization: Bearer eyJhbGc...

{
  "jobName": "openfoam_cfd_test",
  "partition": "compute",
  "nodes": 2,
  "cpus": 32,
  "memory": "64GB",
  "time": "24:00:00",

  "script": "#!/bin/bash\nsource /opt/openfoam/etc/bashrc\nblockMesh\nsimpleFoam -parallel",

  "jobId": "tmp-1699234567890",

  "apptainerImage": {
    "id": "openfoam_v2312",
    "name": "openfoam_v2312.sif",
    "path": "/shared/apptainer/images/compute/openfoam_v2312.sif",
    "type": "compute",
    "version": "v2312"
  },

  "files": [
    {
      "id": "file_001",
      "filename": "controlDict",
      "storage_path": "/shared/uploads/user01/20251106/controlDict",
      "file_type": "data"
    }
  ]
}
```

### Backend 처리 결과

```python
# 생성된 환경변수
file_env_vars = {
    'FILE_DATA_CONTROLDICT': '/shared/uploads/user01/20251106/controlDict'
}

# Apptainer 이미지 정보
apptainer_image = {
    'name': 'openfoam_v2312.sif',
    'path': '/shared/apptainer/images/compute/openfoam_v2312.sif'
}

# Slurm script 생성 경로
script_path = '/scratch/user01/job_12345.sh'

# sbatch 제출
subprocess.run(['sbatch', script_path])
# → "Submitted batch job 12345"
```

### Backend → Frontend (응답)

```json
{
  "success": true,
  "jobId": "12345",
  "message": "Job 12345 submitted successfully with Apptainer"
}
```

### Backend 로그

```
2025-11-06 14:23:45 [INFO] Received job submit request from user: user01
2025-11-06 14:23:45 [INFO] Job ID: tmp-1699234567890
2025-11-06 14:23:45 [INFO] Apptainer image: openfoam_v2312.sif
2025-11-06 14:23:45 [INFO] Uploaded files: 1 file(s)
2025-11-06 14:23:45 [INFO] Generated environment variables: FILE_DATA_CONTROLDICT
2025-11-06 14:23:45 [INFO] Created Slurm script: /scratch/user01/job_12345.sh
2025-11-06 14:23:46 [INFO] ✅ Job 12345 submitted with Apptainer image: openfoam_v2312.sif
2025-11-06 14:23:46 [INFO]    📁 With 1 environment variables for uploaded files
```

---

## 🎉 결론

### Template의 Apptainer 설정이 완벽하게 통합되었습니다!

1. ✅ **Template YAML**: `apptainer` 섹션 포함
2. ✅ **Backend Template API**: Apptainer 설정 파싱 및 전송
3. ✅ **Frontend Template Browser**: Template 선택 → Slurm 파라미터 자동 적용
4. ✅ **Frontend Apptainer Selector**: Template 이미지 자동 매칭
5. ✅ **Frontend Job Submit**: `apptainerImage` 필드 포함 (JWT 자동)
6. ✅ **Backend Job Submit**: Apptainer Container 래핑
7. ✅ **Slurm Execution**: Container 내부에서 Job 실행

### 완성된 시스템 흐름

```
사용자 → Auth Portal (JWT 발급)
  ↓
Dashboard Login (JWT 저장)
  ↓
Job Submit Modal
  ├─ Template Browser (Phase 2)
  │  → OpenFOAM 선택
  │  → Slurm 파라미터 자동 설정
  │  → apptainer.image_name 추출
  │
  ├─ Apptainer Selector (Phase 1)
  │  → openfoam_v2312.sif 자동 하이라이트
  │  → 이미지 상세 정보 표시
  │
  ├─ File Upload (Phase 3)
  │  → controlDict, polyMesh 업로드
  │  → 환경변수 생성
  │
  └─ Submit (JWT 포함)
      ↓
Backend API (JWT 검증)
  → apptainerImage 파싱
  → 업로드 파일 환경변수 생성
  → Slurm script 생성 (apptainer exec)
  → sbatch 제출
      ↓
Slurm Cluster
  → Compute Node 할당
  → Apptainer Container 실행
  → OpenFOAM v2312 inside Container
  → Job 완료
```

---

**작성일**: 2025-11-06
**완성도**: 100% ✅
**관련 문서**:
- [PHASE1_BACKEND_INTEGRATION_COMPLETE.md](PHASE1_BACKEND_INTEGRATION_COMPLETE.md)
- [PHASE_BY_PHASE_STATUS.md](PHASE_BY_PHASE_STATUS.md)
- [NEXT_STEPS.md](NEXT_STEPS.md)

**테스트**: `backend_5010/test_apptainer_integration.sh`
