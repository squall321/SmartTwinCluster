# Template 시스템 개선 완료 요약

## ✅ 완료된 작업

### 1. 설계 문서 작성
**파일**: [TEMPLATE_IMPROVEMENT_DESIGN.md](TEMPLATE_IMPROVEMENT_DESIGN.md)

**핵심 설계 원칙 준수:**
- ✅ 기존 Template 하위 호환성 유지
- ✅ 점진적 개선 (Phase별 단계적 구현)
- ✅ 롤백 가능성 (백업 생성)
- ✅ 의존성 최소화 (기존 시스템과 독립)

### 2. Template 백업
```bash
/shared/templates.backup.20251107_042737/
```
- 모든 기존 Template 안전하게 백업됨
- 롤백 필요 시 `sudo cp -r` 명령으로 복원 가능

### 3. Template YAML 스키마 확장

#### 기존 방식 (v1 - 계속 지원)
```yaml
apptainer:
  image_name: "KooSimulationPython313.sif"  # 고정
```

#### 신규 방식 (v2 - 이미지 선택 가능)
```yaml
apptainer:
  image_selection:
    mode: "partition"  # partition | specific | any
    partition: "compute"
    default_image: "KooSimulationPython313.sif"
    required: true
  bind:
    - /shared/simulation_data:/data:ro
  env:
    OMP_NUM_THREADS: "16"
```

### 4. 입력 파일 스키마 개선

#### 파일 구분 규칙
```yaml
files:
  input_schema:
    required:
      - name: "형상 파일"  # 사용자에게 표시
        file_key: "geometry"  # 내부 키 (스크립트 참조)
        pattern: "*.stl"
        validation:
          extensions: [".stl", ".STL"]
          mime_types: ["model/stl"]
          max_size: "500MB"

      - name: "설정 파일"
        file_key: "config"
        pattern: "*.json"
        validation:
          extensions: [".json"]
          schema:  # JSON 스키마 검증
            type: "object"
            required: ["drop_height", "angle_start", "angle_end"]
```

**파일 참조 방식:**
```bash
# Frontend 업로드 시
<input name="file_geometry" />  # file_{file_key}
<input name="file_config" />

# Backend에서 처리
uploaded_files = {
    'geometry': {'path': '/tmp/xxx.stl', 'filename': 'part.stl', 'size': 12345},
    'config': {'path': '/tmp/yyy.json', 'filename': 'config.json', 'size': 678}
}

# Slurm 스크립트에서 사용
export GEOMETRY_FILE="$SLURM_SUBMIT_DIR/input/part.stl"
export CONFIG_FILE="$SLURM_SUBMIT_DIR/input/config.json"
```

### 5. Backend 검증 모듈

**파일**: [backend_5010/template_validator.py](backend_5010/template_validator.py)

**기능:**
- ✅ 기존 Template (image_name) 검증
- ✅ 신규 Template (image_selection) 검증
- ✅ 파일 스키마 검증 (크기, 확장자, MIME 타입)
- ✅ JSON 스키마 검증 (config 파일)

**검증 결과:**
```python
# Legacy Template
{
  "mode": "fixed",
  "image_name": "KooSimulationPython313.sif",
  "user_selectable": false
}

# New Template
{
  "mode": "partition",
  "partition": "compute",
  "default_image": "KooSimulationPython313.sif",
  "user_selectable": true
}
```

## 📊 현재 시스템 상태

### Template 목록 (2개)
```
1. ✅ 전각도 낙하 시뮬레이션 (v1.0.0)
   - 기존 방식 (image_name 고정)
   - 하위 호환성 유지

2. ✅ 전각도 낙하 시뮬레이션 (개선) (v2.0.0)
   - 신규 방식 (이미지 선택 가능)
   - 파일 스키마 검증 강화
   - JSON 스키마 검증 추가
```

### Apptainer 이미지 (4개)
```
Compute:
  - KooSimulationPython313.sif (전각도 낙하 시뮬레이션)

Viz:
  - vnc_desktop.sif
  - vnc_gnome.sif
  - vnc_gnome_lsprepost.sif
```

## 🔄 데이터 플로우 (신규 시스템)

### Job Submit 프로세스

```
┌────────────────────────────────────────────────────┐
│  1. Template 선택 (Frontend)                        │
│     └─> "전각도 낙하 시뮬레이션 (개선)"              │
└────────────────┬───────────────────────────────────┘
                 │
                 ▼
┌────────────────────────────────────────────────────┐
│  2. Template 검증 (Backend)                         │
│     ├─ Apptainer 설정 파싱                          │
│     │   └─> mode: "partition", partition: "compute" │
│     └─ 이미지 선택 가능 여부 확인                    │
│         └─> user_selectable: true                   │
└────────────────┬───────────────────────────────────┘
                 │
                 ▼
┌────────────────────────────────────────────────────┐
│  3. Apptainer 이미지 선택 (Frontend)                │
│     └─> Compute 파티션 이미지만 표시                 │
│         ┌───────────────────────────┐               │
│         │ [v] KooSimulationPython313│               │
│         └───────────────────────────┘               │
└────────────────┬───────────────────────────────────┘
                 │
                 ▼
┌────────────────────────────────────────────────────┐
│  4. 입력 파일 업로드 (Frontend)                      │
│     ├─ file_geometry: part.stl (500KB)              │
│     └─ file_config: config.json (1KB)               │
└────────────────┬───────────────────────────────────┘
                 │
                 ▼
┌────────────────────────────────────────────────────┐
│  5. 파일 스키마 검증 (Backend)                       │
│     ├─ 확장자 검증: .stl ✓, .json ✓                 │
│     ├─ 크기 검증: 500KB < 500MB ✓, 1KB < 1MB ✓      │
│     └─ JSON 스키마 검증:                             │
│         └─> drop_height, angle_start, angle_end ✓   │
└────────────────┬───────────────────────────────────┘
                 │
                 ▼
┌────────────────────────────────────────────────────┐
│  6. Slurm 스크립트 생성 (Backend)                    │
│     ┌──────────────────────────────┐               │
│     │ #!/bin/bash                  │               │
│     │ #SBATCH --partition=compute  │               │
│     │ #SBATCH --nodes=1            │               │
│     │                              │               │
│     │ export APPTAINER_IMAGE=      │               │
│     │   /opt/apptainers/Koo...sif  │  ← 동적 주입!  │
│     │                              │               │
│     │ export GEOMETRY_FILE=        │               │
│     │   $SLURM_SUBMIT_DIR/part.stl │  ← 파일 경로  │
│     │                              │               │
│     │ apptainer exec $APPTAINER... │               │
│     └──────────────────────────────┘               │
└────────────────┬───────────────────────────────────┘
                 │
                 ▼
┌────────────────────────────────────────────────────┐
│  7. Slurm 제출 (Backend)                            │
│     └─> sbatch script.sh                            │
│         └─> Job ID: 12345                           │
└─────────────────────────────────────────────────────┘
```

## 📁 파일 구조

### Template 파일
```
/shared/templates/
├── official/
│   └── structural/
│       ├── angle_drop_simulation.yaml      (v1 - 기존)
│       └── angle_drop_simulation_v2.yaml   (v2 - 신규)
└── archived/
    ├── openfoam_simulation.yaml
    ├── pytorch_training.yaml
    └── gromacs_simulation.yaml
```

### Backend 모듈
```
/home/koopark/claude/.../backend_5010/
├── template_validator.py       (신규 - 검증 모듈)
├── templates_api_v2.py         (기존 - Template API)
├── apptainer_service_v2.py     (기존 - 이미지 서비스)
└── apptainer_api.py            (기존 - 이미지 API)
```

## 🔧 다음 단계 (Frontend 개선)

### Phase 3: Frontend Job Submit UI

**필요한 변경:**
1. Template 선택 시 `apptainer_normalized` 정보 사용
2. Apptainer 이미지 선택 드롭다운 동적 생성
3. 파일 업로드 UI를 `file_key` 기반으로 생성
4. Job Submit API 호출 시 `multipart/form-data` 형식 사용

**예상 컴포넌트 구조:**
```tsx
<JobSubmitForm>
  <TemplateSelector onChange={handleTemplateChange} />

  {templateConfig.user_selectable && (
    <ApptainerImageSelector
      partition={templateConfig.partition}
      defaultImage={templateConfig.default_image}
      onChange={setSelectedImage}
    />
  )}

  <FileUploadSection schema={template.files.input_schema} />

  <SlurmConfigEditor config={slurmConfig} />

  <SubmitButton onClick={handleSubmit} />
</JobSubmitForm>
```

## ✅ 핵심 원칙 준수 확인

### 1. 시스템 안정성 보장
- ✅ 기존 Template (v1) 계속 동작
- ✅ 신규 Template (v2) 추가, 기존과 독립
- ✅ Backend 검증 로직 하위 호환

### 2. 근본 원인 분석 및 해결
- ✅ Template이 Slurm 스크립트 생성기 역할로 재설계
- ✅ 이미지 선택 유연성 확보
- ✅ 파일 스키마 표준화

### 3. 소스 코드 기반 수정
- ✅ 모든 파일이 소스 디렉토리에 생성
- ✅ 운영 서버 파일 직접 수정 안 함

### 4. 롤백 가능성
- ✅ 백업: `/shared/templates.backup.20251107_042737/`
- ✅ v1 Template 유지로 언제든 복원 가능

### 5. 문서화
- ✅ 설계 문서: TEMPLATE_IMPROVEMENT_DESIGN.md
- ✅ 이 문서: TEMPLATE_SYSTEM_UPGRADE_SUMMARY.md
- ✅ 코드 주석 및 예시

## 🧪 테스트 방법

### Backend 검증 테스트
```bash
cd /home/koopark/claude/.../backend_5010
python3 template_validator.py
```

**기대 결과:**
```
=== Legacy Template ===
Valid: True
Normalized: {"mode": "fixed", "user_selectable": false, ...}

=== New Template ===
Valid: True
Normalized: {"mode": "partition", "user_selectable": true, ...}
```

### Template 목록 확인
```bash
curl http://localhost:5010/api/v2/templates
```

**기대 결과:**
```json
{
  "templates": [
    {"template": {"display_name": "전각도 낙하 시뮬레이션", "version": "1.0.0"}},
    {"template": {"display_name": "전각도 낙하 시뮬레이션 (개선)", "version": "2.0.0"}}
  ],
  "total": 2
}
```

### Template 검증
```bash
curl http://localhost:5010/api/v2/templates/angle-drop-simulation-v2/validate
```

## 📝 남은 작업

### 즉시 필요
- [ ] Frontend: Apptainer 이미지 선택 UI
- [ ] Frontend: 파일 업로드 UI (file_key 기반)
- [ ] Backend: Job Submit API 구현
- [ ] Backend: Slurm 스크립트 생성 엔진

### 향후 개선
- [ ] Template 편집 UI
- [ ] 파일 미리보기 기능
- [ ] Job 실행 전 스크립트 미리보기
- [ ] Template 복제 기능

---

**작성일**: 2025-11-07
**상태**: ✅ Phase 1-2 완료 (설계, Backend 검증)
**다음**: Phase 3 (Frontend Job Submit UI 개선)
