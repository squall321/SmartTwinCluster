# Backend 검증 보고서

**검증일**: 2025-11-10
**목적**: Command Template 시스템 구현을 위한 Backend 코드 완전 검증

---

## 📊 Executive Summary

**결론**: 🟡 **대부분 준비되어 있으나, DB 마이그레이션 미실행으로 인한 데이터 누락**

### 핵심 발견 사항

✅ **잘 구현된 부분**:
- FILE_* 환경변수 주입 시스템 (완벽)
- 파일 업로드 API (완벽)
- API 엔드포인트 구조 (준비 완료)
- 메타데이터 JSON 파일 (완벽)

❌ **즉시 수정 필요**:
- DB `command_templates` 컬럼 없음 (마이그레이션 미실행)
- `ApptainerImage` 클래스에 필드 없음
- `_save_image_to_db()` 저장 로직 누락
- `_scan_single_image()`에 로드 로직 없음

---

## 1. 메타데이터 파일 구조 ✅

### 검증 결과: **완벽**

**파일 구조**:
```
apptainer/compute-node-images/
├── KooSimulationPython313.sif
├── KooSimulationPython313.json          ✅ command_templates 포함
└── KooSimulationPython313.commands.json ✅ 별도 파일 존재
```

**메타데이터 예시**:
```json
{
  "id": "d81d7b6d9e58dd96",
  "name": "KooSimulationPython313.sif",
  "command_templates": [
    {
      "template_id": "python_simulation_basic",
      "display_name": "Python Simulation (Basic)",
      "description": "Run Python simulation script",
      "command": {
        "format": "apptainer exec ${APPTAINER_IMAGE} python3 ${SCRIPT_FILE}"
      },
      "variables": {
        "input_files": {
          "SCRIPT_FILE": {
            "file_key": "python_script",
            "pattern": "*.py",
            "required": true
          }
        }
      }
    }
  ]
}
```

**결론**: 메타데이터 구조는 완벽하게 준비되어 있음.

---

## 2. 메타데이터 로딩 로직 ⚠️

### 검증 결과: **부분 구현**

**파일**: `apptainer/generate_metadata.py`

**구현 상태**:
```python
def load_command_templates(sif_path: str) -> Optional[List[Dict]]:
    """
    .commands.json 파일에서 명령어 템플릿 로드
    """
    sif_dir = os.path.dirname(sif_path)
    sif_name_without_ext = os.path.splitext(os.path.basename(sif_path))[0]
    commands_file = os.path.join(sif_dir, f"{sif_name_without_ext}.commands.json")

    if not os.path.exists(commands_file):
        return None

    with open(commands_file, 'r', encoding='utf-8') as f:
        commands_data = json.load(f)

    return commands_data.get('command_templates', [])

def generate_metadata(sif_path: str, partition: str = 'compute') -> Dict:
    # ... 메타데이터 생성 ...

    # ✅ 명령어 템플릿 로드 및 병합
    command_templates = load_command_templates(sif_path)
    if command_templates:
        metadata["command_templates"] = command_templates

    return metadata
```

**발견 사항**:
- ✅ `.commands.json` 자동 로드 구현됨
- ✅ 메타데이터 JSON에 자동 병합됨
- ❌ **하지만 `apptainer_service_v2.py`에서 사용하지 않음**

---

## 3. DB 스키마 vs 실제 DB ❌

### 검증 결과: **불일치**

**스키마 정의** (`database/schema.sql`):
```sql
CREATE TABLE IF NOT EXISTS apptainer_images (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    -- ... 기타 필드 ...
    env_vars TEXT,  -- JSON format
    command_templates TEXT,  -- ✅ JSON format: 명령어 템플릿 배열
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    -- ...
);
```

**실제 DB**:
```bash
sqlite> PRAGMA table_info(apptainer_images);
# id, name, path, ... env_vars, created_at, ...
# ❌ command_templates 컬럼 없음!
```

**문제**: 스키마 파일에는 정의되어 있으나 실제 DB에 마이그레이션되지 않음.

---

## 4. ApptainerImage 클래스 ❌

### 검증 결과: **필드 누락**

**파일**: `apptainer_service_v2.py:27-71`

**현재 코드**:
```python
class ApptainerImage:
    def __init__(self, **kwargs):
        self.id = kwargs.get('id', '')
        self.name = kwargs.get('name', '')
        # ... 기타 필드 ...
        self.env_vars = kwargs.get('env_vars', {})
        # ❌ self.command_templates = ... 없음!
        self.created_at = kwargs.get('created_at', datetime.now().isoformat())
```

**필요 수정**:
```python
self.command_templates = kwargs.get('command_templates', [])  # 추가
```

---

## 5. DB 저장 로직 ❌

### 검증 결과: **저장 누락**

**파일**: `apptainer_service_v2.py:400-451`

**현재 코드**:
```python
def _save_image_to_db(self, image: ApptainerImage) -> bool:
    cursor.execute('''
        INSERT OR REPLACE INTO apptainer_images (
            id, name, path, node, partition, type, size, version,
            description, labels, apps, runscript, env_vars,
            created_at, updated_at, last_scanned, is_active
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', (
        image.id,
        # ... 17개 필드만 저장 ...
        # ❌ command_templates가 빠져 있음!
    ))
```

**필요 수정**:
- INSERT 문에 `command_templates` 추가
- VALUES에 18번째 파라미터 추가

---

## 6. 이미지 스캔 로직 ❌

### 검증 결과: **로드 로직 없음**

**파일**: `apptainer_service_v2.py:148-250`

**현재 코드**:
```python
def _scan_single_image(self, image_path: str, partition: str) -> Optional[ApptainerImage]:
    # ... 메타데이터 로드 ...

    image = ApptainerImage(
        id=image_id,
        name=sif_basename,
        # ... 기타 필드 ...
        env_vars=metadata.get('environment', {}),
        # ❌ command_templates 로드 안 함!
        created_at=datetime.now().isoformat(),
    )

    return image
```

**필요 수정**:
- `_load_command_templates()` 메서드 추가
- `ApptainerImage` 생성 시 `command_templates` 전달

---

## 7. API 응답 구조 ✅

### 검증 결과: **구현 완료 (데이터만 추가하면 됨)**

**파일**: `apptainer_api.py`

**GET /api/apptainer/images**:
```python
@apptainer_bp.route('/api/apptainer/images', methods=['GET'])
def list_images():
    service = get_apptainer_service()
    images = service.get_images_by_partition(partition)

    return jsonify({
        'images': images,  # ✅ command_templates 포함될 예정
        'total': len(images)
    }), 200
```

**JSON 파싱 로직** (`apptainer_service_v2.py:481-486`):
```python
for field in ['labels', 'apps', 'env_vars', 'command_templates']:
    if field in image_dict and isinstance(image_dict[field], str):
        try:
            image_dict[field] = json.loads(image_dict[field])
        except:
            image_dict[field] = {} if field not in ['apps', 'command_templates'] else []
```

**결론**: API 로직은 이미 준비되어 있음. DB에 데이터만 있으면 자동으로 반환됨.

---

## 8. FILE_* 환경변수 주입 ✅

### 검증 결과: **완벽하게 구현됨**

**파일**: `job_submit_api.py:177-204`

**코드**:
```python
# 업로드된 파일 환경 변수 (file_key 기반)
if job_config['uploaded_files']:
    script += "# --- 업로드된 파일 경로 (file_key 기반) ---\n"

    file_groups = {}
    for file_key, file_info in job_config['uploaded_files'].items():
        if isinstance(file_info, list):
            file_groups[file_key] = file_info
        else:
            file_groups[file_key] = [file_info]

    for file_key, files in file_groups.items():
        var_name = f"FILE_{file_key.upper()}"  # ✅ FILE_PYTHON_SCRIPT

        if len(files) == 1:
            script += f"export {var_name}=\"$SLURM_SUBMIT_DIR/input/{files[0]['filename']}\"\n"
        else:
            # 복수 파일 - Bash 배열
            file_paths = " ".join([f"\"$SLURM_SUBMIT_DIR/input/{f['filename']}\"" for f in files])
            script += f"export {var_name}=({file_paths})\n"
            script += f"export {var_name}_COUNT={len(files)}\n"
```

**동작 예시**:
```bash
# command_templates:
# "file_key": "python_script"

# 생성되는 환경변수:
export FILE_PYTHON_SCRIPT="$SLURM_SUBMIT_DIR/input/simulation.py"

# 복수 파일:
export FILE_INPUT_DATA=("data1.csv" "data2.csv" "data3.csv")
export FILE_INPUT_DATA_COUNT=3
```

**결론**: ✅ **완벽**. Command template의 `${SCRIPT_FILE}` → `$FILE_PYTHON_SCRIPT` 치환 가능.

---

## 🎯 즉시 수정 필요 항목

### Priority 1: DB 마이그레이션 (5분)

**작업**:
```sql
-- migrations/add_command_templates_column.sql
ALTER TABLE apptainer_images
ADD COLUMN command_templates TEXT DEFAULT '[]';
```

**실행**:
```bash
sqlite3 /home/koopark/web_services/backend/dashboard.db < migrations/add_command_templates_column.sql
```

---

### Priority 2: ApptainerImage 클래스 수정 (5분)

**파일**: `dashboard/backend_5010/apptainer_service_v2.py`

**위치**: Line 27-71

**수정**:
```python
class ApptainerImage:
    def __init__(self, **kwargs):
        # ... 기존 필드 ...
        self.env_vars = kwargs.get('env_vars', {})
        self.command_templates = kwargs.get('command_templates', [])  # ✅ 추가
        self.created_at = kwargs.get('created_at', datetime.now().isoformat())
```

**위치**: Line 54-71 (to_dict)

```python
def to_dict(self) -> Dict:
    return {
        # ... 기존 필드 ...
        'env_vars': json.dumps(self.env_vars) if isinstance(self.env_vars, dict) else self.env_vars,
        'command_templates': json.dumps(self.command_templates) if isinstance(self.command_templates, list) else self.command_templates,  # ✅ 추가
        'created_at': self.created_at,
        # ...
    }
```

---

### Priority 3: _save_image_to_db() 수정 (5분)

**파일**: `dashboard/backend_5010/apptainer_service_v2.py`

**위치**: Line 400-451

**수정**:
```python
def _save_image_to_db(self, image: ApptainerImage) -> bool:
    cursor.execute('''
        INSERT OR REPLACE INTO apptainer_images (
            id, name, path, node, partition, type, size, version,
            description, labels, apps, runscript, env_vars,
            command_templates,  -- ✅ 추가
            created_at, updated_at, last_scanned, is_active
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)  -- ✅ 18개
    ''', (
        image.id,
        image.name,
        image.path,
        image.node,
        image.partition,
        image.type,
        image.size,
        image.version,
        image.description,
        json.dumps(image.labels) if isinstance(image.labels, dict) else image.labels,
        json.dumps(image.apps) if isinstance(image.apps, list) else image.apps,
        image.runscript,
        json.dumps(image.env_vars) if isinstance(image.env_vars, dict) else image.env_vars,
        json.dumps(image.command_templates) if isinstance(image.command_templates, list) else image.command_templates,  # ✅ 추가
        image.created_at,
        image.updated_at,
        image.last_scanned,
        image.is_active
    ))
```

---

### Priority 4: _scan_single_image() 수정 (10분)

**파일**: `dashboard/backend_5010/apptainer_service_v2.py`

**위치**: Line 148-250

**추가 메서드**:
```python
def _load_command_templates(self, image_path: str) -> List[Dict]:
    """
    .commands.json 파일에서 명령어 템플릿 로드

    Args:
        image_path: SIF 파일 경로

    Returns:
        명령어 템플릿 리스트
    """
    sif_dir = os.path.dirname(image_path)
    sif_basename = os.path.basename(image_path)
    sif_name_without_ext = os.path.splitext(sif_basename)[0]

    # .commands.json 파일 경로
    commands_file = os.path.join(sif_dir, f"{sif_name_without_ext}.commands.json")

    if not os.path.exists(commands_file):
        logger.debug(f"No command templates file found: {commands_file}")
        return []

    try:
        with open(commands_file, 'r', encoding='utf-8') as f:
            commands_data = json.load(f)

        templates = commands_data.get('command_templates', [])
        logger.info(f"Loaded {len(templates)} command templates from {commands_file}")
        return templates

    except Exception as e:
        logger.error(f"Error loading command templates from {commands_file}: {e}")
        return []
```

**_scan_single_image() 수정**:
```python
def _scan_single_image(self, image_path: str, partition: str) -> Optional[ApptainerImage]:
    # ... 기존 코드 ...

    # ✅ command_templates 로드
    command_templates = self._load_command_templates(image_path)

    image = ApptainerImage(
        id=image_id,
        name=sif_basename,
        path=image_path,
        node=self.node_name,
        partition=partition,
        type=self._detect_image_type(partition),
        size=size,
        version=version,
        description=description,
        labels=labels,
        apps=apps,
        runscript=runscript,
        env_vars=metadata.get('environment', {}),
        command_templates=command_templates,  # ✅ 추가
        created_at=datetime.now().isoformat(),
        updated_at=datetime.now().isoformat(),
        last_scanned=datetime.now().isoformat(),
        is_active=True
    )

    return image
```

---

## 📋 수정 체크리스트

```bash
# Phase 1: DB 마이그레이션 (5분)
[ ] 1. migrations/add_command_templates_column.sql 작성
[ ] 2. sqlite3 실행하여 컬럼 추가
[ ] 3. PRAGMA table_info로 확인

# Phase 2: 코드 수정 (20분)
[ ] 4. ApptainerImage.__init__에 command_templates 추가
[ ] 5. ApptainerImage.to_dict()에 command_templates 추가
[ ] 6. _save_image_to_db() INSERT문 수정
[ ] 7. _load_command_templates() 메서드 추가
[ ] 8. _scan_single_image()에서 _load_command_templates() 호출

# Phase 3: 테스트 (10분)
[ ] 9. 백엔드 재시작
[ ] 10. POST /api/apptainer/scan 실행 (재스캔)
[ ] 11. GET /api/apptainer/images?partition=compute 확인
[ ] 12. command_templates 데이터 확인

# Phase 4: Frontend 연동 (다음 단계)
[ ] 13. apptainer.ts 타입 정의 추가
[ ] 14. ImageSelector 구현
[ ] 15. CommandTemplateInserter 구현
```

---

## 📊 영향도 분석

| 항목 | 현재 상태 | 수정 후 | 영향도 |
|------|----------|--------|--------|
| 메타데이터 파일 | ✅ 준비 완료 | - | - |
| DB 스키마 | ❌ 컬럼 없음 | ✅ 컬럼 추가 | 낮음 |
| ApptainerImage 클래스 | ❌ 필드 없음 | ✅ 필드 추가 | 낮음 |
| _save_image_to_db() | ❌ 저장 안 함 | ✅ 저장 함 | 낮음 |
| _scan_single_image() | ❌ 로드 안 함 | ✅ 로드 함 | 낮음 |
| API 응답 | ❌ 빈 배열 | ✅ 데이터 반환 | **없음** |
| FILE_* 환경변수 | ✅ 정상 작동 | - | - |

**위험도**: 🟢 **매우 낮음**
- 기존 기능에 영향 없음 (필드 추가만)
- 하위 호환성 유지 (command_templates 없어도 작동)
- 롤백 간단 (컬럼 DROP으로 복구)

---

## 🎯 최종 결론

### 핵심 문제
**DB 스키마와 실제 DB가 불일치**
- `schema.sql`에는 정의되어 있음
- 실제 DB에는 컬럼 없음
- **마이그레이션만 실행하면 해결**

### 필요 작업
- **DB 마이그레이션**: 5분
- **코드 수정 4곳**: 20분
- **테스트 및 검증**: 10분
- **Total**: **35분**

### 작업 후 상태
✅ command_templates가 API를 통해 프론트엔드에 전달됨
✅ ImageSelector에서 명령어 템플릿 목록 표시 가능
✅ CommandTemplateInserter에서 템플릿 선택 가능
✅ FILE_* 환경변수와 연동하여 스크립트 자동 생성 가능

---

**검증자**: Claude Development Team
**최종 수정**: 2025-11-10 04:30
**다음 단계**: Backend 수정 즉시 시작
