# Template 시스템 개선 설계서

## 📋 목표

**현재 문제**: Template YAML에 Apptainer 이미지가 하드코딩되어 있어 유연성 부족
**개선 목표**: Template을 Slurm 스크립트 생성기로 만들어 이미지 선택 가능하게 함

## 🔒 핵심 원칙 준수

### 1. 시스템 안정성 보장
- ✅ **기존 Template 유지**: 새로운 필드만 추가, 기존 필드는 그대로 유지
- ✅ **하위 호환성**: 기존 Template도 계속 동작하도록 설계
- ✅ **백업**: 모든 Template 파일 백업 후 수정

### 2. 점진적 개선
```
Phase 1: Template YAML 스키마 확장 (기존 호환)
  └─> Phase 2: Backend 검증 로직 추가
      └─> Phase 3: Frontend 이미지 선택 UI
          └─> Phase 4: Slurm 스크립트 생성 엔진
```

## 📐 설계 상세

### Part 1: Template YAML 스키마 확장

#### 기존 구조 (유지)
```yaml
apptainer:
  image_name: "KooSimulationPython313.sif"
  bind:
    - /shared/simulation_data:/data:ro
    - /shared/results:/results:rw
```

#### 확장된 구조 (선택적)
```yaml
apptainer:
  # 방식 1: 기본 이미지 지정 (기존 방식 호환)
  image_name: "KooSimulationPython313.sif"

  # 방식 2: 이미지 선택 허용 (신규)
  image_required: true  # 이미지 선택 필수 여부
  image_selection:
    mode: "partition"  # partition | specific | any
    partition: "compute"  # mode=partition일 때 필터링
    allowed_images:  # mode=specific일 때만 사용
      - "KooSimulationPython313.sif"
      - "python_3.11.sif"
    default_image: "KooSimulationPython313.sif"  # 기본 선택값

  bind:
    - /shared/simulation_data:/data:ro
    - /shared/results:/results:rw

  env:  # 환경 변수
    OMP_NUM_THREADS: "16"
```

#### 입력 파일 스키마 개선
```yaml
files:
  input_schema:
    required:
      - name: input_geometry  # 필드 이름 (사용자에게 표시)
        file_key: "geometry"  # 파일 키 (스크립트에서 참조)
        pattern: "*.stl"  # 허용 패턴
        description: "입력 형상 파일 (STL)"
        type: "file"  # file | directory
        max_size: "500MB"
        validation:  # 선택적 검증
          mime_types: ["model/stl", "application/octet-stream"]
          extensions: [".stl", ".STL"]

      - name: simulation_config
        file_key: "config"
        pattern: "*.json"
        description: "시뮬레이션 설정 파일"
        type: "file"
        max_size: "1MB"
        validation:
          mime_types: ["application/json"]
          extensions: [".json"]
          schema:  # JSON 스키마 검증 (선택적)
            type: "object"
            required: ["drop_height", "angle_start", "angle_end"]

    optional:  # 선택적 파일
      - name: initial_conditions
        file_key: "initial"
        pattern: "*.dat"
        description: "초기 조건 파일 (선택)"
        type: "file"
        max_size: "100MB"

  output_pattern: "results/**/*"
```

### Part 2: Backend 검증 로직

#### Template 로드 및 검증
```python
class TemplateValidator:
    """Template 유효성 검증 클래스"""

    def validate_apptainer_config(self, template: dict) -> dict:
        """Apptainer 설정 검증 및 정규화"""
        apptainer = template.get('apptainer', {})

        # 기존 방식 (image_name만 있음)
        if 'image_name' in apptainer and 'image_selection' not in apptainer:
            return {
                'mode': 'fixed',
                'image_name': apptainer['image_name'],
                'user_selectable': False
            }

        # 신규 방식 (image_selection 있음)
        if 'image_selection' in apptainer:
            selection = apptainer['image_selection']
            return {
                'mode': selection.get('mode', 'partition'),
                'partition': selection.get('partition'),
                'allowed_images': selection.get('allowed_images', []),
                'default_image': selection.get('default_image'),
                'user_selectable': True
            }

        # 설정 없음 (에러)
        raise ValueError("Apptainer configuration missing")

    def validate_file_schema(self, template: dict, uploaded_files: dict) -> list:
        """업로드된 파일이 스키마를 만족하는지 검증"""
        errors = []
        schema = template.get('files', {}).get('input_schema', {})

        # 필수 파일 체크
        for required_file in schema.get('required', []):
            file_key = required_file['file_key']

            if file_key not in uploaded_files:
                errors.append(f"Required file missing: {required_file['name']}")
                continue

            # 파일 크기 검증
            uploaded = uploaded_files[file_key]
            max_size = self._parse_size(required_file.get('max_size', '1GB'))

            if uploaded['size'] > max_size:
                errors.append(f"File too large: {required_file['name']}")

            # 확장자 검증
            validation = required_file.get('validation', {})
            if 'extensions' in validation:
                ext = os.path.splitext(uploaded['filename'])[1]
                if ext not in validation['extensions']:
                    errors.append(f"Invalid file type: {required_file['name']}")

        return errors
```

### Part 3: Slurm 스크립트 생성 엔진

#### 스크립트 템플릿
```python
class SlurmScriptGenerator:
    """Slurm 배치 스크립트 생성기"""

    def generate_script(self, template: dict, job_config: dict) -> str:
        """
        Args:
            template: Template YAML 데이터
            job_config: {
                'apptainer_image_path': '/opt/apptainers/KooSimulationPython313.sif',
                'uploaded_files': {
                    'geometry': {'path': '/tmp/upload/xxx.stl', 'filename': 'part.stl'},
                    'config': {'path': '/tmp/upload/yyy.json', 'filename': 'config.json'}
                },
                'slurm_overrides': {'mem': '64G'}  # 선택적
            }
        """

        # Slurm 헤더 생성
        slurm_config = self._merge_slurm_config(
            template['slurm'],
            job_config.get('slurm_overrides', {})
        )

        script = self._generate_header(template, slurm_config)

        # 환경 변수 설정
        script += self._generate_environment(
            template,
            job_config['apptainer_image_path']
        )

        # 파일 복사 섹션
        script += self._generate_file_copy(
            template,
            job_config['uploaded_files']
        )

        # Pre-exec
        script += "\n# Pre-execution\n"
        script += template['script']['pre_exec']

        # Main-exec
        script += "\n# Main execution\n"
        script += template['script']['main_exec']

        # Post-exec
        script += "\n# Post-execution\n"
        script += template['script']['post_exec']

        return script

    def _generate_header(self, template: dict, slurm_config: dict) -> str:
        """Slurm 헤더 생성"""
        header = "#!/bin/bash\n"
        header += f"#SBATCH --job-name={template['template']['name']}\n"
        header += f"#SBATCH --partition={slurm_config['partition']}\n"
        header += f"#SBATCH --nodes={slurm_config['nodes']}\n"
        header += f"#SBATCH --ntasks={slurm_config['ntasks']}\n"
        header += f"#SBATCH --mem={slurm_config['mem']}\n"
        header += f"#SBATCH --time={slurm_config['time']}\n"
        header += f"#SBATCH --output=/shared/logs/%j.out\n"
        header += f"#SBATCH --error=/shared/logs/%j.err\n\n"
        return header

    def _generate_environment(self, template: dict, image_path: str) -> str:
        """환경 변수 설정 생성"""
        env = "# Environment setup\n"
        env += f"export APPTAINER_IMAGE=\"{image_path}\"\n"
        env += "export SLURM_SUBMIT_DIR=/shared/jobs/$SLURM_JOB_ID\n"

        # Template의 추가 환경 변수
        apptainer_env = template.get('apptainer', {}).get('env', {})
        for key, value in apptainer_env.items():
            env += f"export {key}=\"{value}\"\n"

        env += "\n"
        return env

    def _generate_file_copy(self, template: dict, uploaded_files: dict) -> str:
        """파일 복사 섹션 생성"""
        copy = "# Setup work directory\n"
        copy += "mkdir -p $SLURM_SUBMIT_DIR\n"
        copy += "cd $SLURM_SUBMIT_DIR\n\n"
        copy += "# Copy input files\n"

        # Template 스키마 기반으로 파일 복사
        schema = template.get('files', {}).get('input_schema', {})
        for required in schema.get('required', []):
            file_key = required['file_key']
            if file_key in uploaded_files:
                src = uploaded_files[file_key]['path']
                dst = uploaded_files[file_key]['filename']
                copy += f"cp \"{src}\" \"$SLURM_SUBMIT_DIR/{dst}\"\n"

        copy += "\n"
        return copy
```

### Part 4: API 엔드포인트 설계

#### POST /api/jobs/submit
```python
@jobs_bp.route('/api/jobs/submit', methods=['POST'])
def submit_job():
    """
    Job 제출

    Request:
        - multipart/form-data
        - template_id: str
        - apptainer_image_id: str (선택적, template 설정에 따라)
        - file_<file_key>: File (예: file_geometry, file_config)
        - slurm_overrides: JSON string (선택적)
    """
    try:
        # 1. Template 로드
        template_id = request.form.get('template_id')
        template = load_template(template_id)

        # 2. Apptainer 이미지 결정
        apptainer_config = validate_apptainer_config(template)

        if apptainer_config['user_selectable']:
            # 사용자가 선택한 이미지 사용
            image_id = request.form.get('apptainer_image_id')
            if not image_id:
                return jsonify({'error': 'Apptainer image required'}), 400
            image = get_apptainer_image(image_id)
        else:
            # Template에 고정된 이미지 사용
            image = get_apptainer_image_by_name(apptainer_config['image_name'])

        # 3. 업로드된 파일 처리
        uploaded_files = {}
        for key, file in request.files.items():
            if key.startswith('file_'):
                file_key = key[5:]  # 'file_' 제거
                temp_path = save_uploaded_file(file)
                uploaded_files[file_key] = {
                    'path': temp_path,
                    'filename': file.filename,
                    'size': os.path.getsize(temp_path)
                }

        # 4. 파일 스키마 검증
        errors = validate_file_schema(template, uploaded_files)
        if errors:
            return jsonify({'errors': errors}), 400

        # 5. Slurm 스크립트 생성
        slurm_overrides = json.loads(request.form.get('slurm_overrides', '{}'))

        script = generate_slurm_script(
            template=template,
            job_config={
                'apptainer_image_path': image['path'],
                'uploaded_files': uploaded_files,
                'slurm_overrides': slurm_overrides
            }
        )

        # 6. Slurm에 제출
        job_id = submit_to_slurm(script)

        # 7. DB에 Job 정보 저장
        save_job_info(
            job_id=job_id,
            template_id=template_id,
            user_id=get_current_user_id(),
            image_id=image['id'],
            files=uploaded_files
        )

        return jsonify({
            'job_id': job_id,
            'message': 'Job submitted successfully'
        }), 201

    except Exception as e:
        logger.error(f"Job submit failed: {e}")
        return jsonify({'error': str(e)}), 500
```

## 🔄 마이그레이션 전략

### Step 1: Template 백업
```bash
cp -r /shared/templates /shared/templates.backup.$(date +%Y%m%d)
```

### Step 2: Template 점진적 업그레이드
```yaml
# 기존 Template (그대로 동작)
apptainer:
  image_name: "KooSimulationPython313.sif"

# 업그레이드된 Template (이미지 선택 가능)
apptainer:
  image_selection:
    mode: "partition"
    partition: "compute"
    default_image: "KooSimulationPython313.sif"
```

### Step 3: Backend 검증 로직 추가 (하위 호환)
```python
# 두 가지 방식 모두 지원
if 'image_selection' in apptainer:
    # 신규 방식
    ...
else:
    # 기존 방식 (image_name만 있음)
    ...
```

### Step 4: Frontend 점진적 업그레이드
```tsx
// Template 설정에 따라 UI 동적 변경
{template.apptainer.user_selectable ? (
  <ApptainerImageSelector />
) : (
  <div>이미지: {template.apptainer.image_name}</div>
)}
```

## 📊 입력 파일 구분 규칙

### 규칙 1: file_key 기반 매핑
```yaml
files:
  input_schema:
    required:
      - name: "형상 파일"  # 사용자에게 표시되는 이름
        file_key: "geometry"  # 내부적으로 사용하는 키
        pattern: "*.stl"
```

```python
# Frontend에서 업로드 시
<input name="file_geometry" type="file" />

# Backend에서 처리
uploaded_files['geometry'] = request.files['file_geometry']
```

### 규칙 2: 파일 타입별 검증
```yaml
validation:
  extensions: [".stl", ".STL"]
  mime_types: ["model/stl", "application/octet-stream"]
  max_size: "500MB"

  # JSON 파일의 경우 스키마 검증
  schema:
    type: "object"
    required: ["drop_height", "angle_start"]
```

### 규칙 3: 파일 저장 경로 표준화
```
/shared/jobs/{job_id}/
├── input/
│   ├── geometry.stl  (원본 파일명 유지)
│   └── config.json
├── work/  (작업 디렉토리)
└── output/  (결과 파일)
```

## ✅ 테스트 계획

### 1. 단위 테스트
- [ ] Template YAML 파싱 테스트
- [ ] Apptainer 설정 검증 테스트
- [ ] 파일 스키마 검증 테스트
- [ ] Slurm 스크립트 생성 테스트

### 2. 통합 테스트
- [ ] Template 선택 → 이미지 선택 → 파일 업로드 → 제출
- [ ] 기존 Template (image_name만 있음) 동작 확인
- [ ] 신규 Template (image_selection 있음) 동작 확인

### 3. 롤백 테스트
- [ ] 신규 코드 → 기존 코드 롤백 시 정상 동작 확인

## 📝 문서화

- [ ] Template YAML 작성 가이드
- [ ] 파일 스키마 정의 가이드
- [ ] Slurm 스크립트 변수 참조 가이드
- [ ] 트러블슈팅 가이드

---

**작성일**: 2025-11-07
**상태**: 설계 완료, 구현 대기
**우선순위**: Phase 1 먼저 구현 (Template YAML 스키마 확장)
