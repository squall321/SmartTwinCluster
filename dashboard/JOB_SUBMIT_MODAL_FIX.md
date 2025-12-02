# Job Submit Modal - Partition Policy Integration

## Problem
Job Templates에서 "Use" 버튼을 클릭했을 때 나타나는 Job Submit 모달에서 예전 방식의 수동 입력 UI가 표시되는 문제

## Solution
JobManagement.tsx의 `JobSubmitModal` 컴포넌트에 TemplateEditor와 동일한 파티션 정책 기반 UI를 적용

## Key Changes

### `JobManagement.tsx` - JobSubmitModal 컴포넌트

#### 1. 파티션 정보 상태 추가
```typescript
const [partitions, setPartitions] = useState<Partition[]>([]);
const [loadingPartitions, setLoadingPartitions] = useState(true);
const [allowedConfigs, setAllowedConfigs] = useState<NodeConfig[]>([]);
const [selectedConfigIndex, setSelectedConfigIndex] = useState(0);
const [cpusPerNode, setCpusPerNode] = useState(128);
```

#### 2. 파티션 로드 로직 (템플릿 사용 여부 고려)
```typescript
useEffect(() => {
  const loadPartitions = async () => {
    const response = await apiGet('/api/groups/partitions');
    
    if (template) {
      // 템플릿 사용: 템플릿의 파티션과 구성 자동 선택
      const currentPartition = response.partitions.find(
        p => p.name === template.config.partition
      );
      const matchingIndex = findMatchingConfigIndex(
        currentPartition.allowedConfigs,
        template.config.nodes,
        template.config.cpus
      );
      setSelectedConfigIndex(matchingIndex);
    } else {
      // 템플릿 없음: 첫 번째 파티션의 첫 번째 구성 사용
      const firstPartition = response.partitions[0];
      const firstConfig = firstPartition.allowedConfigs[0];
      setFormData(prev => ({
        ...prev,
        partition: firstPartition.name,
        nodes: firstConfig.nodes,
        cpus: firstConfig.cpus_per_node
      }));
    }
  };
  
  loadPartitions();
}, [template]);
```

#### 3. 새로운 UI 컴포넌트
- **Partition Dropdown**: 파티션 선택
- **Resource Configuration Cards**: 라디오 버튼으로 구성 선택
- **Read-only Nodes & CPUs fields**: 자동 계산된 값 표시
- **Info Box**: 선택한 파티션의 정책 정보

## UI Layout

### Before (Old UI)
```
Partition: [dropdown - 수동 선택]
Nodes: [input - 수동 입력]
CPUs: [input - 수동 입력]
```

### After (New UI - Partition Policy Based)
```
Partition: [dropdown - 파티션 선택]
  └─> Group 6 (group6) ✓

Resource Configuration:
  ○ 8 Total Cores (1 node × 8 CPUs/node)
  ○ 16 Total Cores (1 node × 16 CPUs/node)
  ● 32 Total Cores (1 node × 32 CPUs/node) ✓ Selected
  ○ 64 Total Cores (1 node × 64 CPUs/node)

Nodes: 1 (Auto-calculated)
CPUs per Node: 32 (Auto-calculated)

ℹ️ Resource Policy for "group6"
• Each node has 128 CPU cores
• Partition allows 4 configurations
• Total cores selected: 32
```

## Use Cases

### Use Case 1: Template에서 "Use" 버튼 클릭
```
1. Job Templates에서 "LS-DYNA Single Job" 카드 찾기
2. "Use" 버튼 클릭
3. Job Submit Modal 열림

자동 설정:
✓ Job Name: LS-DYNA Single Job
✓ Partition: group6 (템플릿에서 가져옴)
✓ Resource Configuration: 32 cores 자동 선택됨
✓ Nodes: 1, CPUs per Node: 32
✓ Script: 템플릿의 스크립트 자동 입력됨

사용자 작업:
- Job Name 수정 (필요시)
- 다른 구성 선택 (필요시)
- Submit
```

### Use Case 2: Job Management에서 직접 Submit
```
1. Job Management 페이지의 "Submit Job" 버튼 클릭
2. Job Submit Modal 열림

자동 설정:
✓ Partition: group1 (첫 번째 파티션)
✓ Resource Configuration: 8192 cores (첫 번째 구성)
✓ Nodes: 64, CPUs per Node: 128

사용자 작업:
- Job Name 입력
- 파티션 선택 (필요시 변경)
- 구성 선택 (필요시 변경)
- Script 작성
- Submit
```

### Use Case 3: 파티션 변경
```
Submit Modal에서:
1. Partition 드롭다운에서 다른 파티션 선택
2. 자동으로:
   - 새 파티션의 구성 목록으로 변경
   - 첫 번째 구성 자동 선택
   - Nodes와 CPUs per Node 업데이트
```

## Benefits

✅ **일관된 UX**: Template Editor, Template Use, Direct Submit 모두 동일한 UI  
✅ **템플릿 연동**: 템플릿 사용 시 구성이 자동으로 선택됨  
✅ **정책 강제**: 모든 Job Submit에서 파티션 정책 적용  
✅ **오류 방지**: 잘못된 nodes/cpus 조합 입력 불가  
✅ **직관적**: 라디오 버튼으로 명확한 선택  

## Testing

### Test 1: Template Use Button
```bash
1. Job Templates 페이지 이동
2. LS-DYNA Single Job 템플릿의 "Use" 버튼 클릭
3. 확인:
   ✓ Partition이 group6로 설정되어 있는지
   ✓ Resource Configuration에서 32 cores가 선택되어 있는지
   ✓ Nodes: 1, CPUs per Node: 32로 표시되는지
   ✓ Script에 템플릿 내용이 들어있는지
```

### Test 2: Direct Submit
```bash
1. Job Management 페이지 이동
2. "Submit Job" 버튼 클릭
3. 확인:
   ✓ Partition이 첫 번째 파티션(group1)으로 설정되어 있는지
   ✓ Resource Configuration 목록이 표시되는지
   ✓ 첫 번째 구성이 자동 선택되어 있는지
   ✓ Nodes와 CPUs per Node가 올바르게 표시되는지
```

### Test 3: Partition Change
```bash
1. Submit Modal에서 Partition 변경 (예: group1 → group6)
2. 확인:
   ✓ Resource Configuration 목록이 새 파티션의 것으로 변경되는지
   ✓ 첫 번째 구성이 자동 선택되는지
   ✓ Nodes와 CPUs per Node가 업데이트되는지
```

### Test 4: Configuration Change
```bash
1. Submit Modal에서 다른 Resource Configuration 선택
2. 확인:
   ✓ 선택한 구성이 시각적으로 강조되는지
   ✓ Nodes와 CPUs per Node가 즉시 업데이트되는지
   ✓ Total cores selected가 올바르게 표시되는지
```

## File Changes

- `frontend_3010/src/components/JobManagement.tsx`
  - JobSubmitModal 컴포넌트 완전 개선
  - 파티션 정보 로드 로직 추가
  - 템플릿 사용 시 자동 구성 선택 로직 추가
  - 새로운 UI 컴포넌트 추가

## Integration Points

### 1. TemplateEditor와 동일한 로직
- `findMatchingConfigIndex()`: 구성 매칭 알고리즘
- 파티션 로드 및 구성 선택 로직
- UI 레이아웃 및 스타일

### 2. Template 연동
```typescript
// Template 사용 시
if (template) {
  // 템플릿의 파티션과 구성 자동 적용
  formData = {
    jobName: template.name,
    partition: template.config.partition,
    nodes: template.config.nodes,
    cpus: template.config.cpus,
    script: template.config.script,
    ...
  };
}
```

### 3. API 연동
```typescript
// 파티션 정보 가져오기
const response = await apiGet('/api/groups/partitions');

// Job 제출
const response = await apiPost('/api/jobs/submit', formData);
```

## Comparison with TemplateEditor

| Feature | TemplateEditor | JobSubmitModal |
|---------|---------------|----------------|
| Partition Selection | ✅ Dropdown | ✅ Dropdown |
| Resource Configuration | ✅ Radio Buttons | ✅ Radio Buttons |
| Auto-calculated Nodes/CPUs | ✅ Read-only | ✅ Read-only |
| Policy Info Box | ✅ Yes | ✅ Yes |
| Template Loading | ✅ Edit mode | ✅ Use button |
| File Upload | ❌ No | ✅ Yes |
| Script Editor | ✅ Yes | ✅ Yes |

## Notes

### Differences from TemplateEditor
1. **File Upload**: JobSubmitModal은 파일 업로드 기능 포함
2. **Script Auto-update**: 파일 업로드 시 스크립트 자동 업데이트
3. **Template Integration**: 템플릿의 "Use" 버튼으로 열릴 때 자동 구성

### Consistent Behavior
- 파티션 선택 시 허용된 구성만 선택 가능
- Nodes와 CPUs는 항상 읽기 전용
- 구성 변경 시 즉시 반영
- 파티션 정책 정보 실시간 표시

## Status
✅ **COMPLETE** - Job Submit Modal에 파티션 정책 완전 적용
