# Frontend-Backend Compatibility Analysis

**작성일**: 2025-11-15
**상태**: ⚠️ **Compatibility Issue Found**

---

## 🔍 문제 발견

사용자 질문: "아니 그런데 job template과 job submit할때 나오는 양식이 완전 호환되는 양식이야?그래보이지 않는데"

→ **정확한 지적입니다.** Frontend UI와 Backend API 사이에 **데이터 불일치**가 존재합니다.

---

## ❌ 호환성 문제 상세

### Frontend가 UI에서 보여주는 필드 (JobManagement.tsx)

| 필드 | UI 위치 | formData 저장 | Backend 전송 여부 | 비고 |
|------|---------|--------------|-----------------|------|
| **Job Name** | Line 873-883 | `formData.jobName` | ✅ 전송됨 | `job_name` 파라미터 |
| **Partition** | Line 925-953 | `formData.partition` | ❌ **전송 안됨** | **문제!** |
| **Resource Config (nodes × cpus)** | Line 956-999 | `formData.nodes`, `formData.cpus` | ❌ **전송 안됨** | **문제!** |
| **Memory** | (formData) | `formData.memory` | ✅ 전송됨 | `slurm_overrides.memory` |
| **Time** | (formData) | `formData.time` | ✅ 전송됨 | `slurm_overrides.time` |

### Frontend가 실제로 Backend에 전송하는 데이터

**코드 위치**: `JobManagement.tsx` Lines 776-783

```javascript
// Slurm overrides (선택적)
const slurmOverrides = {
  memory: formData.memory,  // ✅
  time: formData.time,      // ✅
  // ❌ partition이 없음!
  // ❌ nodes가 없음!
  // ❌ ntasks/cpus가 없음!
};
formDataToSend.append('slurm_overrides', JSON.stringify(slurmOverrides));
```

### Backend가 기대하는 데이터

**코드 위치**: `job_submit_api.py` Lines 385-399

```python
# Template의 기본값을 slurm_overrides로 덮어씀
slurm_config = template['slurm'].copy()
slurm_config.update(job_config.get('slurm_overrides', {}))

# Slurm 스크립트 생성 시 사용되는 필드들:
script += f"#SBATCH --partition={slurm_config['partition']}\n"      # ❌ override 안됨
script += f"#SBATCH --nodes={slurm_config['nodes']}\n"              # ❌ override 안됨
script += f"#SBATCH --ntasks={slurm_config['ntasks']}\n"            # ❌ override 안됨
script += f"#SBATCH --cpus-per-task={slurm_config['cpus_per_task']}\n"  # ❌ override 안됨
script += f"#SBATCH --mem={slurm_config.get('mem', ...)}\n"         # ✅ override 됨
script += f"#SBATCH --time={slurm_config['time']}\n"                # ✅ override 됨
```

---

## 🚨 실제 영향

### 시나리오: 사용자가 Job Submit UI에서 설정을 변경하는 경우

**사용자 행동**:
1. Template 선택: `my-simulation-v1` (기본값: partition=normal, nodes=1, ntasks=4)
2. **UI에서 Partition을 "normal"에서 "group1"로 변경**
3. **UI에서 Resource Config를 "1 node × 128 CPUs"에서 "2 nodes × 64 CPUs"로 변경**
4. Memory를 "4G"에서 "8G"로 변경
5. Time을 "01:00:00"에서 "02:00:00"로 변경
6. Submit 버튼 클릭

**실제 Backend가 받는 데이터**:
```json
{
  "template_id": "my-simulation-v1",
  "job_name": "test-job",
  "apptainer_image_id": "KooSimulationPython313",
  "slurm_overrides": {
    "memory": "8G",     // ✅ 사용자 변경 반영됨
    "time": "02:00:00"  // ✅ 사용자 변경 반영됨
    // partition: 없음! Template 기본값 "normal" 사용됨
    // nodes: 없음! Template 기본값 1 사용됨
    // ntasks: 없음! Template 기본값 4 사용됨
  }
}
```

**생성된 Slurm 스크립트**:
```bash
#!/bin/bash
#SBATCH --job-name=test-job
#SBATCH --partition=normal           # ❌ 사용자가 "group1"로 변경했지만 Template 기본값 사용
#SBATCH --nodes=1                    # ❌ 사용자가 2로 변경했지만 Template 기본값 사용
#SBATCH --ntasks=4                   # ❌ 사용자가 128로 변경했지만 Template 기본값 사용
#SBATCH --cpus-per-task=1            # ❌ Template 기본값 사용
#SBATCH --mem=8G                     # ✅ 사용자 변경 반영됨
#SBATCH --time=02:00:00              # ✅ 사용자 변경 반영됨
```

### 결과

- **메모리, 시간**: 사용자 변경 반영 ✅
- **파티션, 노드 수, CPU 수**: 사용자 변경 무시, Template 기본값 사용 ❌

→ **사용자는 UI에서 설정을 변경했지만, 실제로는 적용되지 않음!**

---

## 🔧 해결 방안

### Option 1: Frontend에서 모든 Slurm 필드 전송 (권장)

**변경 위치**: `JobManagement.tsx` Lines 776-780

**현재 코드**:
```javascript
const slurmOverrides = {
  memory: formData.memory,
  time: formData.time,
};
```

**수정 코드**:
```javascript
const slurmOverrides = {
  partition: formData.partition,  // 추가
  nodes: formData.nodes,          // 추가
  ntasks: formData.cpus,          // 추가 (Frontend는 cpus로 저장, Backend는 ntasks로 사용)
  memory: formData.memory,
  time: formData.time,
};
```

**장점**:
- ✅ 사용자 UI 변경사항이 모두 반영됨
- ✅ Backend 코드 변경 불필요
- ✅ Template의 기본값을 사용자가 완전히 override 가능

**단점**:
- Template이 partition을 고정하고 싶은 경우에도 사용자가 변경 가능 (보안/정책 문제 가능성)

---

### Option 2: Frontend UI에서 변경 불가능한 필드 제거

**변경 방안**:
- Partition 선택 UI 제거 (Template의 partition 고정)
- Resource Configuration 선택 UI 제거 (Template의 nodes/ntasks 고정)
- Memory, Time만 사용자가 변경 가능하도록 제한

**장점**:
- ✅ Template 정책 강제 (보안/일관성)
- ✅ 사용자 혼란 방지 ("변경했는데 적용 안 됨" 문제 해결)
- ✅ Backend 코드 변경 불필요

**단점**:
- ❌ 사용자 자유도 감소
- ❌ 기존 UI 대폭 변경 필요

---

### Option 3: Template에 override 가능 필드 명시 (가장 유연)

**Backend에 Template 스키마 확장**:

```yaml
template:
  id: "my-simulation-v1"
  name: angle_drop_simulation

slurm:
  partition: normal
  nodes: 1
  ntasks: 4
  mem: 4G
  time: "01:00:00"

  # 새로운 필드: 사용자가 override 가능한 필드 명시
  user_overridable:
    - mem
    - time
    - partition  # 선택적
    - nodes      # 선택적
```

**Frontend 변경**:
- Template의 `user_overridable` 필드를 확인
- 해당 필드만 UI에서 편집 가능하도록 표시
- 나머지는 읽기 전용으로 표시

**Backend 변경**:
- slurm_overrides를 받을 때 user_overridable 필드만 허용
- 나머지는 무시 (보안)

**장점**:
- ✅ Template마다 정책 다르게 설정 가능
- ✅ 보안과 유연성 모두 확보
- ✅ 사용자 혼란 최소화 (변경 가능한 것만 UI에 표시)

**단점**:
- ❌ Backend + Frontend 모두 수정 필요
- ❌ Template 스키마 확장 필요

---

## 📋 권장 조치

### 단기 해결책 (즉시 적용 가능)

**→ Option 1 적용**: Frontend에서 모든 Slurm 필드 전송

**변경 파일**: `frontend_3010/src/components/JobManagement.tsx`

**변경 내용**:
```diff
  const slurmOverrides = {
+   partition: formData.partition,
+   nodes: formData.nodes,
+   ntasks: formData.cpus,
    memory: formData.memory,
    time: formData.time,
  };
```

**테스트 방법**:
1. UI에서 Partition을 변경
2. Resource Configuration 변경
3. Memory, Time 변경
4. Submit 후 생성된 Slurm 스크립트 확인
5. 모든 변경사항이 반영되었는지 확인

---

### 중기 해결책 (보안 강화)

**→ Option 3 적용**: Template에 override 가능 필드 명시

**Phase 1**: Backend Template 스키마 확장
- `template_validator.py`에 `user_overridable` 필드 추가
- `job_submit_api.py`에서 override 검증 로직 추가

**Phase 2**: Frontend UI 동적 생성
- Template의 `user_overridable` 필드 확인
- 편집 가능/불가능 필드 구분하여 UI 렌더링

**Phase 3**: 기존 Templates 마이그레이션
- 모든 Template YAML에 `user_overridable` 필드 추가

---

## 📊 현재 상태 요약

| 항목 | 상태 | 비고 |
|------|------|------|
| **GET API (Template 정규화)** | ✅ 완료 | apptainer_normalized 반환 |
| **POST API (Job 제출)** | ✅ 완료 | sbatch 실제 제출 |
| **Job History DB** | ✅ 완료 | job_submissions 테이블 |
| **에러 처리** | ✅ 완료 | ErrorCode, 구조화된 로깅 |
| **Frontend UI** | ✅ 완료 | Template 선택, 파일 업로드, 설정 변경 |
| **Frontend-Backend 데이터 호환** | ❌ **문제 발견** | **partition, nodes, ntasks 미전송** |

---

## ✅ 다음 단계

1. **즉시**: 사용자에게 발견된 호환성 문제 보고
2. **단기**: Option 1 적용 (Frontend 수정)
3. **중기**: Option 3 검토 (보안 강화)
4. **장기**: Template 정책 관리 시스템 구축

---

**작성자**: Claude
**최종 업데이트**: 2025-11-15
