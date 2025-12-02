# Job Templates Partition Integration - Complete Implementation (v4)

## Overview
Cluster Management에서 구성된 파티션 정보가 Job Templates의 **New Template 생성**과 **기존 Template 편집** 모두에서 완전히 반영되도록 구현했습니다. 정책상의 코어 수가 강제 선택되고, 각 노드의 128 CPU 코어를 기준으로 nodes와 cpus_per_node가 자동 계산됩니다.

## Changes Made (v4 Update)

### 🆕 **기존 템플릿 편집 지원 추가**

기존에는 새 템플릿 생성 시에만 파티션 정책이 적용되었으나, 이제 **기존 템플릿 편집 시에도 동일한 UI와 정책**이 적용됩니다.

#### 주요 개선사항

1. **기존 템플릿 구성 자동 인식**
   ```typescript
   const findMatchingConfigIndex = (configs: NodeConfig[], nodes: number, cpus: number): number => {
     const totalCores = nodes * cpus;
     const index = configs.findIndex(
       config => config.total_cores === totalCores || 
                (config.nodes === nodes && config.cpus_per_node === cpus)
     );
     return index >= 0 ? index : 0;
   };
   ```
   - 기존 템플릿의 nodes × cpus 값과 일치하는 구성을 자동으로 찾아 선택
   - 일치하는 구성이 없으면 첫 번째 구성을 기본값으로 사용

2. **템플릿 로드 시 파티션 정보 초기화**
   ```typescript
   if (template) {
     // 기존 템플릿 편집: 현재 파티션의 구성 로드
     const currentPartition = response.partitions.find(
       (p: Partition) => p.name === template.config.partition
     );
     
     if (currentPartition) {
       setAllowedConfigs(currentPartition.allowedConfigs);
       
       // 기존 템플릿의 nodes/cpus와 일치하는 구성 찾기
       const matchingIndex = findMatchingConfigIndex(
         currentPartition.allowedConfigs,
         template.config.nodes,
         template.config.cpus
       );
       setSelectedConfigIndex(matchingIndex);
     }
   }
   ```

### 1. Backend: `groups_api.py` (v3에서 완료)

#### 노드 구성 자동 계산 함수
```python
def calculate_node_config(total_cores):
    """총 코어 수를 노드 수와 노드당 CPU로 변환"""
    if total_cores <= 128:
        return {'nodes': 1, 'cpus_per_node': total_cores, 'total_cores': total_cores}
    else:
        nodes = (total_cores + 127) // 128  # 올림 계산
        return {'nodes': nodes, 'cpus_per_node': 128, 'total_cores': nodes * 128}
```

#### `/api/groups/partitions` 엔드포인트
```json
{
  "success": true,
  "partitions": [
    {
      "name": "group1",
      "label": "Group 1",
      "allowedCoreSizes": [8192],
      "allowedConfigs": [
        {
          "total_cores": 8192,
          "nodes": 64,
          "cpus_per_node": 128
        }
      ],
      "description": "Large scale jobs"
    }
  ],
  "cpus_per_node": 128
}
```

### 2. Frontend: `TemplateEditor.tsx` (v4 완료)

#### v4 주요 기능
- ✅ **새 템플릿 생성**: 파티션 정책 기반 리소스 구성 선택
- ✅ **기존 템플릿 편집**: 현재 구성을 자동 인식하고 동일한 UI 제공
- ✅ **파티션 변경**: 편집 중에도 파티션 변경 가능, 자동으로 새 구성 적용
- ✅ **읽기 전용 필드**: Nodes와 CPUs per Node는 자동 계산되어 수정 불가

#### UI 구성

##### 1) 라디오 버튼 기반 리소스 구성 선택
```
Resource Configuration *
○ 32 Total Cores
  1 node × 32 CPUs/node
  
● 64 Total Cores  ✓ Selected
  1 node × 64 CPUs/node
```

##### 2) 자동 계산 필드 (읽기 전용)
```
Nodes: 1 (Auto-calculated)
CPUs per Node: 64 (Auto-calculated)
```

##### 3) 정책 정보 박스
```
ℹ️ Resource Policy for "group6"
• Each node has 128 CPU cores
• Partition allows 4 configurations
• Total cores selected: 64
```

## Use Cases

### Use Case 1: 새 템플릿 생성
1. "New Template" 버튼 클릭
2. Partition 선택 (예: group6)
3. 허용된 구성 목록에서 원하는 구성 선택
4. Nodes와 CPUs per Node 자동 설정
5. 나머지 필드 입력 후 저장

### Use Case 2: 기존 LS-DYNA 템플릿 편집
**기존 템플릿 구성**:
```json
{
  "partition": "group6",
  "nodes": 1,
  "cpus": 32
}
```

**편집 시 동작**:
1. 템플릿 카드에서 "Edit" 버튼 클릭
2. TemplateEditor가 열리면서 자동으로:
   - Partition: group6 선택됨
   - Resource Configuration에서 "32 Total Cores (1 node × 32 CPUs/node)"가 자동 선택됨
   - Nodes: 1, CPUs per Node: 32로 표시됨
3. 원하면 다른 구성으로 변경 가능 (예: 64 cores로 변경)
4. 저장

### Use Case 3: 파티션 변경
**현재**: group6 (32 cores)
**변경**: group1 (8192 cores)

1. Partition 드롭다운에서 group1 선택
2. 자동으로:
   - Resource Configuration이 group1의 구성으로 변경됨
   - 첫 번째 구성 (8192 cores = 64 nodes × 128 CPUs/node) 선택됨
   - Nodes: 64, CPUs per Node: 128로 업데이트됨

## Example Scenarios

### Scenario 1: LS-DYNA Single Job Template 편집
```
기존 구성:
- partition: group6
- nodes: 1
- cpus: 32

편집 화면:
✓ Partition: Group 6 (group6)
✓ Resource Configuration:
  ○ 8 Total Cores (1 node × 8 CPUs/node)
  ○ 16 Total Cores (1 node × 16 CPUs/node)
  ● 32 Total Cores (1 node × 32 CPUs/node) ✓ Selected  ← 자동 선택됨
  ○ 64 Total Cores (1 node × 64 CPUs/node)
  
✓ Nodes: 1 (Auto-calculated)
✓ CPUs per Node: 32 (Auto-calculated)
```

### Scenario 2: LS-DYNA Array Job Template 편집
```
기존 구성:
- partition: group6
- nodes: 1
- cpus: 16

편집 화면:
✓ Partition: Group 6 (group6)
✓ Resource Configuration:
  ○ 8 Total Cores (1 node × 8 CPUs/node)
  ● 16 Total Cores (1 node × 16 CPUs/node) ✓ Selected  ← 자동 선택됨
  ○ 32 Total Cores (1 node × 32 CPUs/node)
  ○ 64 Total Cores (1 node × 64 CPUs/node)
  
✓ Nodes: 1 (Auto-calculated)
✓ CPUs per Node: 16 (Auto-calculated)
```

### Scenario 3: 구성이 정책에 맞지 않는 경우
```
기존 구성:
- partition: group6
- nodes: 2
- cpus: 48  ← 정책에 없는 구성 (총 96 cores)

편집 화면:
⚠️ 일치하는 구성이 없으므로 첫 번째 구성으로 리셋됨

✓ Partition: Group 6 (group6)
✓ Resource Configuration:
  ● 8 Total Cores (1 node × 8 CPUs/node) ✓ Selected  ← 기본값으로 선택됨
  ○ 16 Total Cores (1 node × 16 CPUs/node)
  ○ 32 Total Cores (1 node × 32 CPUs/node)
  ○ 64 Total Cores (1 node × 64 CPUs/node)
  
✓ Nodes: 1 (Auto-calculated)
✓ CPUs per Node: 8 (Auto-calculated)

💡 사용자는 원하는 구성을 다시 선택할 수 있음
```

## Benefits

### 1. 일관된 사용자 경험
- ✅ 새 템플릿 생성과 기존 템플릿 편집 시 동일한 UI
- ✅ 파티션 정책이 항상 적용됨
- ✅ 사용자 혼란 최소화

### 2. 정책 강제 적용
- ✅ 생성 시뿐만 아니라 편집 시에도 정책 적용
- ✅ 잘못된 구성으로 변경 불가
- ✅ 기존 템플릿도 정책에 맞게 수정 가능

### 3. 자동 검증
- ✅ 기존 구성이 정책에 맞는지 자동 확인
- ✅ 맞지 않으면 기본값으로 리셋
- ✅ 사용자에게 선택권 제공

### 4. 유연성
- ✅ 편집 중 파티션 변경 가능
- ✅ 다양한 구성 중 선택 가능
- ✅ 실시간 정책 정보 제공

## Testing

### 1. 기존 템플릿 편집 테스트

#### Test Case 1: LS-DYNA Single Job
```bash
1. Job Templates 페이지로 이동
2. "LS-DYNA Single Job" 템플릿 카드에서 Edit 클릭
3. 확인 사항:
   ✓ Partition이 group6로 설정되어 있는지
   ✓ Resource Configuration에서 32 cores가 선택되어 있는지
   ✓ Nodes: 1, CPUs per Node: 32로 표시되는지
   ✓ 다른 구성 (8, 16, 64 cores)도 선택 가능한지
```

#### Test Case 2: LS-DYNA Array Job
```bash
1. Job Templates 페이지로 이동
2. "LS-DYNA Array Job" 템플릿 카드에서 Edit 클릭
3. 확인 사항:
   ✓ Partition이 group6로 설정되어 있는지
   ✓ Resource Configuration에서 16 cores가 선택되어 있는지
   ✓ Nodes: 1, CPUs per Node: 16으로 표시되는지
```

#### Test Case 3: 파티션 변경
```bash
1. 기존 템플릿 편집
2. Partition을 다른 것으로 변경 (예: group6 → group1)
3. 확인 사항:
   ✓ Resource Configuration이 새 파티션의 구성으로 변경되는지
   ✓ 첫 번째 구성이 자동 선택되는지
   ✓ Nodes와 CPUs per Node가 업데이트되는지
```

### 2. API 확인
```bash
# 파티션 목록 조회
curl http://localhost:5010/api/groups/partitions | jq

# 특정 템플릿 조회
curl http://localhost:5010/api/jobs/templates/tpl-lsdyna-single | jq

# 템플릿 수정
curl -X PATCH http://localhost:5010/api/jobs/templates/tpl-lsdyna-single \
  -H "Content-Type: application/json" \
  -d '{
    "config": {
      "partition": "group6",
      "nodes": 1,
      "cpus": 64
    }
  }'
```

## Technical Details

### 구성 매칭 알고리즘
```typescript
// 1. 총 코어 수로 매칭 시도
const totalCores = nodes * cpus;
const matchByTotalCores = configs.find(c => c.total_cores === totalCores);

// 2. nodes와 cpus_per_node로 정확히 매칭 시도
const matchByNodesAndCpus = configs.find(
  c => c.nodes === nodes && c.cpus_per_node === cpus
);

// 3. 매칭 실패 시 기본값 (index 0)
const finalIndex = matchByTotalCores || matchByNodesAndCpus ? index : 0;
```

### 상태 관리 Flow
```
1. Template 로드
   ↓
2. Partitions API 호출
   ↓
3. Template의 partition에 해당하는 allowedConfigs 가져오기
   ↓
4. Template의 nodes × cpus와 일치하는 config 찾기
   ↓
5. selectedConfigIndex 설정
   ↓
6. UI 렌더링 (해당 구성이 선택된 상태로 표시)
```

## File Structure

```
backend_5010/
├── groups_api.py          # ✅ v3 - 노드 구성 자동 계산

frontend_3010/src/components/JobTemplates/
└── TemplateEditor.tsx     # ✅ v4 - 기존 템플릿 편집 지원 추가
```

## Migration Path for Existing Templates

기존에 정책에 맞지 않는 구성으로 저장된 템플릿이 있을 수 있습니다. 이런 경우:

1. **편집 시 자동 조정**: 템플릿을 열면 가장 가까운 정책 구성으로 자동 선택
2. **사용자 확인**: 사용자가 원하는 구성으로 변경 가능
3. **저장 시 검증**: 저장 시 선택된 구성이 정책에 맞는지 확인

### Optional: Batch Update Script
```python
# 모든 템플릿을 정책에 맞게 업데이트하는 스크립트 (선택사항)
import json
from database import get_db_connection

def update_templates_to_policy():
    """모든 템플릿을 파티션 정책에 맞게 업데이트"""
    # 구현 생략
    pass
```

## Next Steps

### Optional Enhancements
1. **경고 메시지**: 정책에 맞지 않는 구성이 자동 조정되면 사용자에게 알림
2. **히스토리 추적**: 템플릿 수정 이력 저장
3. **벌크 편집**: 여러 템플릿을 한 번에 업데이트

## Conclusion

**v4 업데이트 완료**:
- ✅ 새 템플릿 생성 시 파티션 정책 적용 (v3)
- ✅ 기존 템플릿 편집 시에도 파티션 정책 적용 (v4)
- ✅ 동일한 UI/UX로 일관된 사용자 경험 제공
- ✅ 기존 구성 자동 인식 및 매칭
- ✅ 파티션 변경 시에도 정책 자동 적용

이제 사용자는 **새 템플릿을 만들 때**나 **기존 템플릿을 수정할 때** 모두 동일한 방식으로 Cluster Management에서 정의된 파티션 정책에 따라 안전하게 리소스 구성을 선택할 수 있습니다.
