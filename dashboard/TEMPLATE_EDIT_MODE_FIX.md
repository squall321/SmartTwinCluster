# Job Templates - Edit Mode Fix Summary

## Problem
기존 템플릿(LS-DYNA Single/Array Job 등)을 편집할 때 새로운 파티션 정책 기반 UI가 적용되지 않고 예전 방식의 입력 필드가 표시되는 문제

## Solution (v4)
기존 템플릿 편집 시에도 새 템플릿 생성과 동일한 파티션 정책 기반 UI를 적용

## Key Changes

### `TemplateEditor.tsx`

#### 1. 기존 템플릿 구성 자동 인식 함수 추가
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

#### 2. 파티션 로드 시 템플릿 타입 구분 처리
```typescript
if (template) {
  // 기존 템플릿 편집
  const currentPartition = response.partitions.find(
    p => p.name === template.config.partition
  );
  
  if (currentPartition) {
    setAllowedConfigs(currentPartition.allowedConfigs);
    
    // 기존 구성과 일치하는 것 찾아서 선택
    const matchingIndex = findMatchingConfigIndex(
      currentPartition.allowedConfigs,
      template.config.nodes,
      template.config.cpus
    );
    setSelectedConfigIndex(matchingIndex);
  }
} else {
  // 새 템플릿 생성
  // ... 기존 로직
}
```

## Test Scenarios

### LS-DYNA Single Job 편집 테스트
```
Before Edit:
- partition: group6
- nodes: 1
- cpus: 32

After Opening Editor:
✓ Partition: Group 6 (group6) - 자동 선택됨
✓ Resource Configuration:
  ● 32 Total Cores (1 node × 32 CPUs/node) ✓ Selected
✓ Nodes: 1 (Auto-calculated)
✓ CPUs per Node: 32 (Auto-calculated)
```

### LS-DYNA Array Job 편집 테스트
```
Before Edit:
- partition: group6
- nodes: 1
- cpus: 16

After Opening Editor:
✓ Partition: Group 6 (group6) - 자동 선택됨
✓ Resource Configuration:
  ● 16 Total Cores (1 node × 16 CPUs/node) ✓ Selected
✓ Nodes: 1 (Auto-calculated)
✓ CPUs per Node: 16 (Auto-calculated)
```

## Benefits

✅ **일관된 UX**: 생성/편집 모두 동일한 UI  
✅ **자동 매칭**: 기존 구성을 자동으로 찾아 선택  
✅ **정책 강제**: 편집 시에도 파티션 정책 적용  
✅ **유연성**: 편집 중 다른 구성으로 변경 가능  

## Files Changed

- `frontend_3010/src/components/JobTemplates/TemplateEditor.tsx` (v4)

## How to Test

1. Production mode에서 Job Templates 페이지 이동
2. LS-DYNA Single Job 또는 LS-DYNA Array Job 템플릿 카드 찾기
3. Edit 버튼 클릭
4. 확인:
   - Resource Configuration에서 현재 구성이 자동 선택되어 있는지
   - Nodes와 CPUs per Node가 읽기 전용으로 올바르게 표시되는지
   - 다른 구성 선택 시 자동으로 업데이트되는지
   - 파티션 변경 시 새 정책이 적용되는지

## Status
✅ **COMPLETE** - v4 업데이트 완료
