# 규격 시나리오 추가 기능 구현 계획 v2

## 📋 개요

기존의 "빈 시나리오 추가" 외에 **"규격 시나리오 추가"** 기능을 구현하여, 사전 정의된 표준 시험 규격을 선택하여 시나리오를 추가할 수 있도록 합니다.

## 🎯 목표

1. **메인 백엔드**에 표준 규격 시나리오 JSON 파일 저장소 구축
2. 프론트엔드에서 규격 시나리오 목록 조회 및 선택 UI 추가
3. 선택한 규격 시나리오를 현재 시나리오 포맷으로 자동 변환하여 추가

## 🏗️ 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                    Frontend (CAE Web)                        │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  SimulationAutomationComponent                       │   │
│  │  ┌────────────────┐  ┌──────────────────────────┐   │   │
│  │  │ 빈 시나리오    │  │ 규격 시나리오 추가      │   │   │
│  │  │ 추가 (기존)    │  │ (NEW)                    │   │   │
│  │  │                │  │ - 규격 목록 조회         │   │   │
│  │  │                │  │ - 규격 선택 모달         │   │   │
│  │  │                │  │ - 자동 변환 및 추가      │   │   │
│  │  └────────────────┘  └──────────────────────────┘   │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                           │ HTTP GET
                           ↓
┌─────────────────────────────────────────────────────────────┐
│              Main Backend (FastAPI - port 5000)              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  /api/standard-scenarios                             │   │
│  │  - GET: 규격 시나리오 목록 조회                      │   │
│  │  - GET /{scenario_id}: 특정 규격 시나리오 상세 조회  │   │
│  └──────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  File Storage: /data/standard_scenarios/*.json       │   │
│  │  - frontal_full_angle.json                           │   │
│  │  - frontal_angle_fall.json                           │   │
│  │  - side_pole_impact.json                             │   │
│  │  - ... (추가 규격 시나리오)                          │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## 📁 디렉토리 구조

```
dashboard/
├── kooCAEWeb_5173/
│   └── src/
│       ├── components/
│       │   └── StandardScenarioModal.tsx          # NEW: 규격 시나리오 선택 모달
│       ├── pages/
│       │   └── SimulationAutomationComponent.tsx  # UPDATE: 규격 시나리오 추가 버튼
│       └── types/
│           └── standardScenario.ts                # NEW: 규격 시나리오 타입 정의
│
└── main_backend_5000/
    ├── routers/
    │   └── standard_scenarios.py                  # NEW: 규격 시나리오 API 라우터
    ├── data/
    │   └── standard_scenarios/                    # NEW: 규격 시나리오 JSON 저장소
    │       ├── frontal_full_angle.json
    │       ├── frontal_angle_fall.json
    │       ├── frontal_cumulative_fall.json
    │       ├── multiple_cumulative_fall.json
    │       ├── drop_weight_impact.json
    │       ├── predefined_fall_attitudes.json
    │       └── edge_axis_rotation.json
    └── models/
        └── standard_scenario.py                   # NEW: 규격 시나리오 모델
```

## 📝 데이터 포맷

### 규격 시나리오 JSON 구조

```json
{
  "id": "frontal_full_angle",
  "name": "전각도 다물체동역학 낙하",
  "category": "standard_test",
  "description": "정면 전각도에서 다물체 동역학을 고려한 낙하 시험",
  "version": "1.0.0",
  "created_at": "2025-12-03T00:00:00Z",
  "parameters": {
    "analysisType": "multibody",
    "targetAngle": 90.0,
    "dropHeight": 1.5,
    "mass": 80.0,
    "impactSurface": "rigid",
    "includeGravity": true,
    "simulationTime": 0.15,
    "outputInterval": 0.001
  },
  "angles": [
    {
      "name": "정면 0도",
      "phi": 0.0,
      "theta": 0.0,
      "psi": 0.0
    },
    {
      "name": "정면 15도",
      "phi": 15.0,
      "theta": 0.0,
      "psi": 0.0
    },
    {
      "name": "정면 30도",
      "phi": 30.0,
      "theta": 0.0,
      "psi": 0.0
    }
  ],
  "metadata": {
    "standardReference": "KS M 3150",
    "testMethod": "Free Drop",
    "requiredEquipment": ["Drop Tower", "Impact Surface", "High-Speed Camera"],
    "safetyRequirements": ["Protective Gear Required", "Controlled Environment"]
  }
}
```

### 프론트엔드 시나리오 포맷 (기존)

```typescript
interface SimulationScenario {
  id: string;
  name: string;
  analysisType: 'multibody' | 'fall' | 'cumulative' | 'weightImpact' | 'predefined' | 'edgeRotation';
  angles: Array<{
    phi: number;
    theta: number;
    psi: number;
  }>;
  parameters: {
    dropHeight?: number;
    mass?: number;
    impactSurface?: string;
    // ... 기타 파라미터
  };
}
```

## 🔧 구현 단계

### Phase 1: 백엔드 구현 (Main Backend - port 5000)

#### 1.1 데이터 모델 정의
**파일**: `main_backend_5000/models/standard_scenario.py`

```python
from pydantic import BaseModel
from typing import List, Dict, Any, Optional
from datetime import datetime

class AngleDefinition(BaseModel):
    name: str
    phi: float
    theta: float
    psi: float

class ScenarioMetadata(BaseModel):
    standardReference: Optional[str] = None
    testMethod: Optional[str] = None
    requiredEquipment: Optional[List[str]] = None
    safetyRequirements: Optional[List[str]] = None

class StandardScenario(BaseModel):
    id: str
    name: str
    category: str
    description: str
    version: str
    created_at: datetime
    parameters: Dict[str, Any]
    angles: List[AngleDefinition]
    metadata: Optional[ScenarioMetadata] = None

class StandardScenarioSummary(BaseModel):
    id: str
    name: str
    category: str
    description: str
    version: str
    angleCount: int
```

#### 1.2 규격 시나리오 JSON 파일 생성
**디렉토리**: `main_backend_5000/data/standard_scenarios/`

7개 표준 규격 파일 생성:
1. `frontal_full_angle.json` - 전각도 다물체동역학 낙하
2. `frontal_angle_fall.json` - 전각도 낙하
3. `frontal_cumulative_fall.json` - 전각도 누적 낙하
4. `multiple_cumulative_fall.json` - 다회 누적 낙하
5. `drop_weight_impact.json` - 낙하 중량 충격
6. `predefined_fall_attitudes.json` - 사전 정의 낙하 자세
7. `edge_axis_rotation.json` - 엣지 축 회전

#### 1.3 API 라우터 구현
**파일**: `main_backend_5000/routers/standard_scenarios.py`

```python
from fastapi import APIRouter, HTTPException
from typing import List
import json
import os
from pathlib import Path

router = APIRouter(prefix="/api/standard-scenarios", tags=["standard-scenarios"])

SCENARIOS_DIR = Path(__file__).parent.parent / "data" / "standard_scenarios"

@router.get("/", response_model=List[StandardScenarioSummary])
async def get_standard_scenarios():
    """모든 규격 시나리오 목록 조회"""
    scenarios = []
    for file_path in SCENARIOS_DIR.glob("*.json"):
        with open(file_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
            scenarios.append(StandardScenarioSummary(
                id=data['id'],
                name=data['name'],
                category=data['category'],
                description=data['description'],
                version=data['version'],
                angleCount=len(data['angles'])
            ))
    return scenarios

@router.get("/{scenario_id}", response_model=StandardScenario)
async def get_standard_scenario(scenario_id: str):
    """특정 규격 시나리오 상세 조회"""
    file_path = SCENARIOS_DIR / f"{scenario_id}.json"
    if not file_path.exists():
        raise HTTPException(status_code=404, detail="Scenario not found")

    with open(file_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    return StandardScenario(**data)
```

#### 1.4 메인 앱에 라우터 등록
**파일**: `main_backend_5000/main.py`

```python
from routers import standard_scenarios

app.include_router(standard_scenarios.router)
```

### Phase 2: 프론트엔드 구현

#### 2.1 타입 정의
**파일**: `kooCAEWeb_5173/src/types/standardScenario.ts`

```typescript
export interface AngleDefinition {
  name: string;
  phi: number;
  theta: number;
  psi: number;
}

export interface ScenarioMetadata {
  standardReference?: string;
  testMethod?: string;
  requiredEquipment?: string[];
  safetyRequirements?: string[];
}

export interface StandardScenario {
  id: string;
  name: string;
  category: string;
  description: string;
  version: string;
  created_at: string;
  parameters: Record<string, any>;
  angles: AngleDefinition[];
  metadata?: ScenarioMetadata;
}

export interface StandardScenarioSummary {
  id: string;
  name: string;
  category: string;
  description: string;
  version: string;
  angleCount: number;
}
```

#### 2.2 규격 시나리오 선택 모달 컴포넌트
**파일**: `kooCAEWeb_5173/src/components/StandardScenarioModal.tsx`

주요 기능:
- 규격 시나리오 목록 표시 (카드 형태)
- 카테고리별 필터링
- 시나리오 상세 정보 미리보기
- 선택 후 현재 포맷으로 변환하여 추가

#### 2.3 SimulationAutomationComponent 업데이트
**파일**: `kooCAEWeb_5173/src/pages/SimulationAutomationComponent.tsx`

추가 사항:
- "규격 시나리오 추가" 버튼 추가
- StandardScenarioModal 통합
- 규격 시나리오 → 내부 포맷 변환 로직

### Phase 3: 통합 및 테스트

#### 3.1 API 통합 테스트
- 백엔드 API 엔드포인트 테스트
- JSON 파일 로딩 검증
- 에러 처리 테스트

#### 3.2 프론트엔드 통합 테스트
- 규격 시나리오 목록 로딩
- 모달 UI/UX 테스트
- 시나리오 변환 로직 검증
- 기존 시나리오와 통합 작동 확인

#### 3.3 엔드투엔드 테스트
- 전체 워크플로우 테스트
- 여러 규격 시나리오 추가 후 시뮬레이션 제출
- 성능 테스트

## 🎨 UI/UX 설계

### 시나리오 추가 버튼 레이아웃

```
┌────────────────────────────────────────────────────┐
│  시나리오 목록              [빈 시나리오 추가]  │
│                            [규격 시나리오 추가]  │  ← NEW
└────────────────────────────────────────────────────┘
```

### 규격 시나리오 선택 모달

```
┌─────────────────────────────────────────────────────────┐
│  규격 시나리오 선택                              [X]    │
├─────────────────────────────────────────────────────────┤
│  [전체] [낙하 시험] [충격 시험] [회전 시험]             │
│                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
│  │ 전각도       │  │ 전각도       │  │ 낙하 중량    │ │
│  │ 다물체동역학 │  │ 낙하         │  │ 충격         │ │
│  │              │  │              │  │              │ │
│  │ 📐 18개 각도 │  │ 📐 12개 각도 │  │ 📐 8개 각도  │ │
│  │ v1.0.0       │  │ v1.0.0       │  │ v1.0.0       │ │
│  └──────────────┘  └──────────────┘  └──────────────┘ │
│                                                          │
│  ┌──────────────────────────────────────────────────┐  │
│  │ 선택한 규격: 전각도 다물체동역학 낙하            │  │
│  │                                                   │  │
│  │ 설명: 정면 전각도에서 다물체 동역학을 고려한     │  │
│  │       낙하 시험                                   │  │
│  │                                                   │  │
│  │ 각도 수: 18개                                     │  │
│  │ 표준 참조: KS M 3150                             │  │
│  │ 시험 방법: Free Drop                             │  │
│  └──────────────────────────────────────────────────┘  │
│                                                          │
│                              [취소]  [시나리오 추가]    │
└─────────────────────────────────────────────────────────┘
```

## ✅ 체크리스트

### 백엔드
- [ ] 데이터 모델 정의 (`standard_scenario.py`)
- [ ] 7개 규격 시나리오 JSON 파일 생성
- [ ] API 라우터 구현 (`standard_scenarios.py`)
- [ ] 메인 앱에 라우터 등록
- [ ] API 테스트

### 프론트엔드
- [ ] 타입 정의 (`standardScenario.ts`)
- [ ] 규격 시나리오 선택 모달 구현 (`StandardScenarioModal.tsx`)
- [ ] SimulationAutomationComponent 업데이트
- [ ] 변환 로직 구현
- [ ] UI/UX 테스트

### 통합
- [ ] 엔드투엔드 테스트
- [ ] 문서 업데이트
- [ ] 사용자 가이드 작성

## 📚 참고 문서

- 기존 구현: `SimulationAutomationComponent.tsx`
- 시나리오 포맷: `SimulationAutomatedPagePlan_update.md`
- API 문서: 생성 예정 (`/docs` 엔드포인트)

## 🚀 배포 전략

1. 로컬 개발 환경에서 테스트
2. 규격 시나리오 JSON 검증
3. 프론트엔드 빌드 및 배포
4. 백엔드 재시작
5. 통합 테스트
6. 프로덕션 배포

## 🔮 향후 개선 사항

1. 규격 시나리오 편집 기능 (관리자)
2. 커스텀 규격 시나리오 생성 및 저장
3. 규격 시나리오 버전 관리
4. 시나리오 템플릿 공유 기능
5. 시나리오 검색 및 필터링 고도화
