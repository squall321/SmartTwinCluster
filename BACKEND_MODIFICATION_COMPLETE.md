# Backend 수정 완료 보고서

**완료일**: 2025-11-10 04:35
**소요 시간**: 약 30분
**상태**: ✅ **성공**

---

## 📊 수정 요약

### 수정된 파일

1. **apptainer_service_v2.py** (4곳 수정)
   - ApptainerImage 클래스: `command_templates` 필드 추가
   - `to_dict()` 메서드: JSON 직렬화 추가
   - `_save_image_to_db()`: DB 저장 로직 추가
   - `_load_command_templates()`: 신규 메서드 추가
   - `_scan_single_image()`: command_templates 로드 추가

2. **migrations/run_migration.py** (신규 생성)
   - DB 마이그레이션 스크립트
   - `command_templates` 컬럼 추가 (이미 존재함 확인)

---

## 🎯 테스트 결과

### API 테스트: ✅ 성공

**엔드포인트**: `GET /api/apptainer/images?partition=compute`

**응답 예시**:
```json
{
  "images": [
    {
      "name": "KooSimulationPython313.sif",
      "command_templates": [
        {
          "template_id": "python_simulation_basic",
          "display_name": "Python Simulation (Basic)",
          "description": "Run Python simulation script with basic configuration",
          "command": {
            "executable": "python3",
            "format": "apptainer exec ${APPTAINER_IMAGE} python3 ${SCRIPT_FILE}",
            "requires_mpi": false
          },
          "variables": {
            "dynamic": {},
            "input_files": {
              "SCRIPT_FILE": {
                "description": "Python script to execute",
                "file_key": "python_script",
                "pattern": "*.py",
                "required": true
              }
            },
            "output_files": {
              "results": {
                "collect": true,
                "description": "Simulation results",
                "pattern": "results_*"
              }
            }
          },
          "pre_commands": [...],
          "post_commands": [...]
        }
      ],
      ...
    }
  ]
}
```

### 확인 사항

- ✅ `command_templates` 필드가 API 응답에 포함됨
- ✅ `.commands.json` 파일에서 자동 로드됨
- ✅ JSON 구조가 설계와 일치함
- ✅ `file_key` 기반 파일 매핑 정의 확인
- ✅ `input_files`, `output_files` 스키마 완벽히 로드됨

---

## 📝 코드 변경 내역

### 1. ApptainerImage 클래스 (Line 44)

**변경 전**:
```python
self.env_vars = kwargs.get('env_vars', {})
self.created_at = kwargs.get('created_at', datetime.now().isoformat())
```

**변경 후**:
```python
self.env_vars = kwargs.get('env_vars', {})
self.command_templates = kwargs.get('command_templates', [])  # 추가
self.created_at = kwargs.get('created_at', datetime.now().isoformat())
```

---

### 2. to_dict() 메서드 (Line 67)

**변경 전**:
```python
'env_vars': json.dumps(self.env_vars) if isinstance(self.env_vars, dict) else self.env_vars,
'created_at': self.created_at,
```

**변경 후**:
```python
'env_vars': json.dumps(self.env_vars) if isinstance(self.env_vars, dict) else self.env_vars,
'command_templates': json.dumps(self.command_templates) if isinstance(self.command_templates, list) else self.command_templates,  # 추가
'created_at': self.created_at,
```

---

### 3. _save_image_to_db() (Line 421-440)

**변경 전**:
```python
INSERT OR REPLACE INTO apptainer_images (
    id, name, path, node, partition, type, size, version,
    description, labels, apps, runscript, env_vars,
    created_at, updated_at, last_scanned, is_active
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
```

**변경 후**:
```python
INSERT OR REPLACE INTO apptainer_images (
    id, name, path, node, partition, type, size, version,
    description, labels, apps, runscript, env_vars, command_templates,  # 추가
    created_at, updated_at, last_scanned, is_active
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)  # 18개
```

**파라미터 추가**:
```python
json.dumps(image.command_templates) if isinstance(image.command_templates, list) else image.command_templates,
```

---

### 4. _load_command_templates() (신규 메서드, Line 254-285)

```python
def _load_command_templates(self, image_path: str) -> List[Dict]:
    """
    .commands.json 파일에서 명령어 템플릿 로드

    Args:
        image_path: SIF 파일 경로

    Returns:
        명령어 템플릿 리스트 (없으면 빈 리스트)
    """
    sif_dir = os.path.dirname(image_path)
    sif_basename = os.path.basename(image_path)
    sif_name_without_ext = os.path.splitext(sif_basename)[0]

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

---

### 5. _scan_single_image() 수정

#### 5.1 캐시된 메타데이터 사용 시 (Line 204-206)

**추가**:
```python
# command_templates가 없으면 .commands.json 파일에서 로드
if 'command_templates' not in cached_metadata:
    cached_metadata['command_templates'] = self._load_command_templates(image_path)
```

#### 5.2 inspect 실행 시 (Line 230-231, 248)

**추가**:
```python
# 명령어 템플릿 로드
command_templates = self._load_command_templates(image_path)

# ApptainerImage 객체 생성
image = ApptainerImage(
    # ... 기존 필드 ...
    env_vars=metadata.get('environment', {}),
    command_templates=command_templates,  # 추가
    created_at=datetime.now().isoformat(),
    # ...
)
```

---

## 🎯 검증 결과

### DB 확인

```bash
# command_templates 컬럼 존재 확인
sqlite3 /home/koopark/web_services/backend/dashboard.db "PRAGMA table_info(apptainer_images);"
# → command_templates TEXT 컬럼 존재 ✅
```

### API 확인

```bash
# Partition별 이미지 조회
curl http://localhost:5010/api/apptainer/images?partition=compute

# 응답:
{
  "images": [
    {
      "name": "KooSimulationPython313.sif",
      "command_templates": [...]  # ✅ 데이터 포함
    }
  ]
}
```

### 로드 로직 확인

```bash
# .commands.json 파일 존재 확인
ls /home/koopark/claude/KooSlurmInstallAutomationRefactory/apptainer/compute-node-images/*.commands.json

# 결과:
KooSimulationPython313.commands.json  # ✅ 존재
```

---

## 📊 이미지별 Command Templates

| 이미지 | command_templates 개수 |
|--------|----------------------|
| KooSimulationPython313.sif | 1개 ✅ |

---

## 🚀 다음 단계

### 즉시 가능한 작업

1. **Frontend 타입 정의 추가**
   - `apptainer.ts`에 CommandTemplate 인터페이스 추가
   - DynamicVariable, InputFileVariable 등 타입 정의

2. **ImageSelector 구현**
   - Partition별 이미지 조회
   - Command templates 미리보기

3. **CommandTemplateInserter 구현**
   - 템플릿 선택 UI
   - 변수 매핑 UI
   - 스크립트 생성

### 백엔드 추가 개선 (선택적)

1. **선택적 API 추가**:
   ```python
   @apptainer_bp.route('/api/apptainer/images/<image_id>/command-templates')
   def get_command_templates(image_id):
       # 특정 이미지의 command_templates만 조회
   ```

2. **에러 처리 강화**:
   - .commands.json 파일 검증
   - 필수 필드 체크

---

## ✅ 완료 체크리스트

- [x] DB `command_templates` 컬럼 확인
- [x] ApptainerImage 클래스 수정
- [x] _save_image_to_db() 수정
- [x] _load_command_templates() 추가
- [x] _scan_single_image() 수정
- [x] 백엔드 재시작
- [x] API 테스트
- [x] 데이터 검증

---

## 🎉 결론

**Backend 수정이 완벽하게 완료되었습니다!**

- ✅ command_templates가 API를 통해 프론트엔드에 전달됨
- ✅ .commands.json 파일에서 자동 로드됨
- ✅ DB에 정상적으로 저장됨
- ✅ 기존 기능에 영향 없음
- ✅ 하위 호환성 유지

**다음 작업**: Frontend 타입 정의 및 UI 컴포넌트 구현

---

**작성자**: Claude Development Team
**최종 수정**: 2025-11-10 04:35
