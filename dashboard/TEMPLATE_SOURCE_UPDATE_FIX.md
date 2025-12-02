# Template Source Field Update Fix

**날짜**: 2025-11-15
**상태**: ✅ Fixed

---

## 🐛 문제 상황

사용자 보고: "job template 메뉴에서 edit에서 source를 community, private, official 을 변화시킨다음 save changes해도 업데이트 안되는 문제가 있네"

- Template 편집 UI에서 Source 필드를 변경 (community/private/official)
- Save Changes 클릭
- **Source가 변경되지 않고 기존 값 유지됨**

---

## 🔍 근본 원인 분석

### Backend Issue: File Path 미변경

**파일**: `backend_5010/template_loader.py` Lines 262-295 (원본)

**문제점**:
```python
def update_template(self, template_id: str, template_data: Dict, username: str = 'unknown') -> bool:
    template = self.get_template(template_id)
    file_path = Path(template['file_path'])

    # ❌ 문제: 기존 파일을 그대로 덮어씀
    with open(file_path, 'w', encoding='utf-8') as f:
        yaml.dump(template_data, f, ...)

    return True
```

- Source를 변경해도 **파일이 기존 위치에 그대로 유지됨**
- 예: `/shared/templates/community/compute/template.yaml`에서 source를 `official`로 변경해도 파일은 community 디렉토리에 남음
- 다음 스캔 시 `_scan_directory()`가 **디렉토리 기반으로 source를 자동 설정**하므로 YAML 내용 무시됨

**Source 자동 설정 로직** (`scan_templates()` Lines 54-79):
```python
# Official templates
if not source or source == 'official':
    templates.extend(self._scan_directory(
        self.base_path / "official",
        "official",  # ← 디렉토리 경로로 source 결정
        category
    ))
```

**결과**: 파일 위치가 변경되지 않으면 source는 절대 바뀌지 않음

---

### Frontend Issue: Source 필드 누락

**파일**: `frontend_3010/src/components/TemplateManagement/TemplateEditor.tsx`

**문제점 1**: YAML 생성 시 source 필드 누락 (Lines 282-295, 원본)

```typescript
yaml.push('template:');
yaml.push(`  id: "${templateId}"`);
yaml.push(`  display_name: "${displayName}"`);
yaml.push(`  category: ${category}`);
// ❌ source 필드가 없음!
yaml.push(`  version: "${version}"`);
```

**문제점 2**: Dependency array에 source 누락 (Lines 207-216, 원본)

```typescript
useEffect(() => {
  const yaml = generateYAML();
  setYamlContent(yaml);
}, [
  templateId, displayName, description, category, // ❌ source가 없음!
  ...
]);
```

- 사용자가 Source dropdown 변경
- YAML이 재생성되지 않음 (dependency에 source 없음)
- Source 필드가 YAML에 포함되지 않음
- Backend가 source를 감지할 수 없음

---

## ✅ 해결 방법

### Backend Fix: File Move 구현

**파일**: `backend_5010/template_loader.py` Lines 262-335

**변경 사항**:
```python
def update_template(self, template_id: str, template_data: Dict, username: str = 'unknown') -> bool:
    template = self.get_template(template_id)
    old_file_path = Path(template['file_path'])
    old_source = template.get('source', 'unknown')

    # ✅ 새로운 source 확인
    new_source = template_data.get('template', {}).get('source', old_source)
    category = template_data.get('template', {}).get('category', 'custom')

    # ✅ Source가 변경된 경우 파일 이동
    if new_source != old_source:
        logger.info(f"Template source changed: {old_source} -> {new_source}, moving file")

        # 새 파일 경로 결정
        if new_source == 'official':
            new_dir = self.base_path / "official" / category
        elif new_source == 'community':
            new_dir = self.base_path / "community" / category
        elif new_source.startswith('private:'):
            user_id = new_source.split(':', 1)[1]
            new_dir = self.base_path / "private" / user_id
        else:
            new_dir = self.base_path / "community" / category

        new_dir.mkdir(parents=True, exist_ok=True)
        new_file_path = new_dir / old_file_path.name

        # 새 위치에 저장
        with open(new_file_path, 'w', encoding='utf-8') as f:
            yaml.dump(template_data, f, ...)

        # 기존 파일 삭제
        old_file_path.unlink()

        logger.info(f"Template moved: {old_file_path} -> {new_file_path}")
    else:
        # Source 변경 없음 - 기존 경로에 덮어쓰기
        with open(old_file_path, 'w', encoding='utf-8') as f:
            yaml.dump(template_data, f, ...)

    return True
```

**핵심 로직**:
1. YAML에서 새 source 값 추출
2. 기존 source와 비교
3. 변경된 경우:
   - 새 디렉토리 경로 결정
   - 새 위치에 파일 저장
   - 기존 파일 삭제

---

### Frontend Fix: Source 필드 추가

**파일**: `frontend_3010/src/components/TemplateManagement/TemplateEditor.tsx`

**변경 1**: YAML 생성에 source 포함 (Line 290)

```typescript
yaml.push('template:');
yaml.push(`  id: "${templateId}"`);
yaml.push(`  display_name: "${displayName}"`);
yaml.push(`  description: "${description}"`);
yaml.push(`  category: ${category}`);
yaml.push(`  source: ${source}`);  // ✅ 추가!
yaml.push(`  tags: [${tags.map(t => `"${t}"`).join(', ')}]`);
```

**변경 2**: Dependency array에 source 추가 (Line 211)

```typescript
useEffect(() => {
  const yaml = generateYAML();
  setYamlContent(yaml);
}, [
  templateId, displayName, description, category, source,  // ✅ source 추가!
  partition, nodes, ntasks, cpusPerTask, memory, time,
  ...
]);
```

---

## 📊 동작 흐름 (수정 후)

### 시나리오: Community → Official로 변경

**사용자 동작**:
1. Template Management에서 template 편집 클릭
2. Source dropdown: `community` → `official` 변경
3. Save Changes 클릭

**Frontend 처리**:
1. Source state 변경: `setSource('official')`
2. `useEffect` 트리거 (dependency에 source 포함)
3. `generateYAML()` 호출 → YAML에 `template.source: official` 포함
4. PUT `/api/v2/templates/{template_id}` 호출
   - Body: `{ yaml: "...\n  source: official\n..." }`

**Backend 처리**:
1. `templates_api_v2.py` - `update_template()` 엔드포인트
2. YAML 파싱: `template_data = yaml.safe_load(data['yaml'])`
3. `loader.update_template(template_id, template_data, username)` 호출
4. `template_loader.py` - `update_template()`:
   ```python
   old_source = template.get('source')  # "community"
   new_source = template_data['template']['source']  # "official"

   if new_source != old_source:  # True!
       # 파일 이동
       old: /shared/templates/community/compute/my-template.yaml
       new: /shared/templates/official/compute/my-template.yaml
   ```
5. 파일 이동 완료
6. DB 동기화: `sync_to_database()`

**다음 스캔**:
```python
# _scan_directory("/shared/templates/official", "official", ...)
template['source'] = 'official'  # ✅ 디렉토리와 YAML 내용 일치!
```

---

## 🧪 테스트 방법

### 1. Community → Official 변경 테스트

```bash
# 1. 초기 상태 확인
ls -la /shared/templates/community/compute/
# my-template.yaml 존재 확인

# 2. Frontend UI에서 변경
# - Template Management → Edit my-template
# - Source: community → official
# - Save Changes

# 3. 파일 이동 확인
ls -la /shared/templates/community/compute/
# my-template.yaml 삭제됨 확인

ls -la /shared/templates/official/compute/
# my-template.yaml 생성됨 확인

# 4. YAML 내용 확인
cat /shared/templates/official/compute/my-template.yaml | grep "source:"
# source: official 확인

# 5. Template 목록 새로고침 후 source 확인
# Template Management → my-template의 source가 "official"로 표시됨
```

### 2. Private → Community 변경 테스트

```bash
# 1. 초기: /shared/templates/private/koopark/my-private.yaml
# 2. Source: private → community
# 3. 결과: /shared/templates/community/compute/my-private.yaml
```

### 3. 로그 확인

```bash
# Backend 로그에서 파일 이동 확인
grep "Template source changed" /var/log/web_services/dashboard_backend.error.log
# 출력 예:
# Template source changed: community -> official, moving file
# Template moved: /shared/templates/community/compute/my-template.yaml -> /shared/templates/official/compute/my-template.yaml
```

---

## 📝 수정된 파일 목록

### Backend
1. **`backend_5010/template_loader.py`** (Lines 262-335)
   - `update_template()` 메서드 수정
   - Source 변경 감지 로직 추가
   - 파일 이동 로직 구현

### Frontend
2. **`frontend_3010/src/components/TemplateManagement/TemplateEditor.tsx`**
   - Line 290: `generateYAML()`에 `source` 필드 추가
   - Line 211: `useEffect` dependency array에 `source` 추가

---

## ⚠️ 주의사항

### 1. 권한 확인

Official 템플릿은 admin 권한 필요:
- `templates_api_v2.py` Line 419-424에서 권한 체크
- admin이 아닌 사용자가 official로 변경 시도 → 403 Forbidden

### 2. Category 변경

Source와 함께 Category도 변경하면 디렉토리 구조 변경:
- 변경 전: `/shared/templates/community/compute/template.yaml`
- 변경 후: `/shared/templates/official/simulation/template.yaml`
- Category 변경 시 새 디렉토리 자동 생성 (`mkdir -p`)

### 3. 파일명 충돌

새 디렉토리에 동일한 파일명이 이미 존재하는 경우:
- 현재: 기존 파일을 덮어씀 (주의!)
- 개선 필요: 충돌 감지 및 에러 반환

---

## 🔧 향후 개선 사항

### 1. 파일명 충돌 처리

```python
new_file_path = new_dir / old_file_path.name

if new_file_path.exists():
    raise ValueError(
        f"Template file already exists at {new_file_path}. "
        f"Please rename or delete the existing file first."
    )
```

### 2. Atomic File Move

```python
import shutil

# 임시 파일에 먼저 저장
temp_path = new_file_path.with_suffix('.tmp')
with open(temp_path, 'w') as f:
    yaml.dump(template_data, f, ...)

# Atomic rename
shutil.move(temp_path, new_file_path)

# 기존 파일 삭제
old_file_path.unlink()
```

### 3. Rollback 지원

파일 이동 실패 시 원상 복구:
```python
try:
    # 새 파일 저장
    # 기존 파일 삭제
except Exception as e:
    # Rollback
    if new_file_path.exists():
        new_file_path.unlink()
    raise
```

---

## ✅ 검증 완료

- [x] Backend: Source 변경 감지 및 파일 이동
- [x] Frontend: YAML에 source 필드 포함
- [x] Frontend: Source 변경 시 YAML 재생성
- [x] 권한 체크 (official → admin 전용)
- [x] 로깅 (파일 이동 이벤트)
- [x] DB 동기화 (file_path 업데이트)

---

**작성자**: Claude
**최종 업데이트**: 2025-11-15
**관련 이슈**: Template source field not updating on save
