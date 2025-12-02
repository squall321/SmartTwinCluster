# 시스템 관리 기능 구현 로드맵

## 📋 전체 개요

**프로젝트**: Slurm Dashboard - System Management Features  
**기간**: 약 8주  
**현재 상태**: Phase 1 완료 ✅  

---

## ✅ Phase 1: Health Check 시스템 (완료)

**기간**: 완료  
**상태**: ✅ 100% 완료 및 통합됨

### 완성된 기능
- ✅ 7개 서비스 모니터링 (Backend, WebSocket, Prometheus, Node Exporter, Slurm, Database, Storage)
- ✅ Auto-heal 기능 (3개 서비스)
- ✅ 실시간 상태 업데이트 (30초 자동 갱신)
- ✅ 반응형 UI (4열 그리드)
- ✅ 다크 모드 지원
- ✅ Mock/Production 모드 완벽 지원

### 파일
- `backend_5010/health_check_api.py`
- `frontend_3010/src/components/HealthCheck/index.tsx`
- `backend_5010/app.py` (통합됨)
- `frontend_3010/src/components/Dashboard.tsx` (통합됨)

---

## ✅ Phase 2: 노드 관리 기본 (완료)

**기간**: 2025-10-10 (완료)  
**상태**: ✅ 100% 완료 및 통합됨

### 완성된 기능
- ✅ 6개 API 엔드포인트 (Drain, Resume, Reboot, 노드 목록, 노드 상세, 이력 조회)
- ✅ Mock 모드 지원 (4개 노드: cn01~cn04)
- ✅ 실시간 노드 목록 (상태, CPU, 메모리)
- ✅ 노드 행 수준 제어 (Drain/Resume/Reboot 버튼)
- ✅ 노드 상세 정보 패널
- ✅ 확인 모달 및 이유 입력
- ✅ Auto Refresh (10초 간격, 토글 가능)
- ✅ Stats Summary (상태별 노드 수)
- ✅ 반응형 UI 및 다크 모드 지원

### 파일
- `backend_5010/node_management_api.py`
- `frontend_3010/src/components/NodeManagement/index.tsx`
- `backend_5010/app.py` (통합됨)
- `frontend_3010/src/components/Dashboard.tsx` (통합됨)
- `PHASE1_2_NODE_MANAGEMENT_COMPLETE.md` (문서)

---

## 🎨 Phase 3: 설정 관리 UI - QoS (2주)

**예상 기간**: 2025-10-26 ~ 2025-11-08  
**우선순위**: HIGH  
**의존성**: Phase 2 완료

### 목표
QoS(Quality of Service)를 웹 UI에서 관리

### 구현 항목

#### 3.1 Backend API 확장 (`system_config_api.py`)

**엔드포인트**:
```python
GET    /api/system/qos                 # QoS 목록
GET    /api/system/qos/<name>          # QoS 상세
POST   /api/system/qos                 # QoS 생성
PUT    /api/system/qos/<name>          # QoS 수정
DELETE /api/system/qos/<name>          # QoS 삭제
POST   /api/system/qos/<name>/test     # QoS 검증 (Dry-run)
```

**주요 기능**:
- `sacctmgr` 명령 래핑
- QoS 파라미터 검증
- 변경 사항 백업
- Dry-run 모드 지원

**구현 난이도**: ⭐⭐⭐ (중)

#### 3.2 Frontend Component (`SystemSettings/QoSManager/`)

**컴포넌트 구조**:
```
SystemSettings/
└── QoSManager/
    ├── index.tsx              # 메인
    ├── QoSList.tsx            # QoS 목록 테이블
    ├── QoSCard.tsx            # QoS 카드
    ├── QoSForm.tsx            # 생성/수정 폼
    └── QoSPreview.tsx         # 미리보기 (적용 전)
```

**UI 기능**:
- QoS 목록 (이름, 우선순위, MaxCPU, MaxMemory 등)
- 생성/수정 폼 (모달)
- 파라미터 검증 (프론트엔드)
- 미리보기 및 확인
- 삭제 확인 모달

**구현 난이도**: ⭐⭐⭐⭐ (중상)

#### 3.3 통합

**Dashboard.tsx 수정**:
- 'system-settings' 탭 추가
- Settings (⚙️) 아이콘 사용

**예상 작업량**: 2주

---

## 🔧 Phase 4: 설정 관리 UI - 고급 (2주)

**예상 기간**: 2025-11-09 ~ 2025-11-22  
**우선순위**: MEDIUM  
**의존성**: Phase 3 완료

### 목표
Slurm 설정 파일을 웹에서 직접 편집

### 구현 항목

#### 4.1 Backend API 확장

**엔드포인트**:
```python
GET  /api/system/config/slurm.conf        # slurm.conf 내용
PUT  /api/system/config/slurm.conf        # slurm.conf 수정
POST /api/system/config/slurm.conf/validate  # 검증
GET  /api/system/config/backups           # 백업 목록
POST /api/system/config/restore           # 백업에서 복원
```

**주요 기능**:
- 설정 파일 읽기/쓰기
- 문법 검증 (`scontrol` 사용)
- 자동 백업 (타임스탬프)
- 복원 기능
- 변경 사항 추적

**구현 난이도**: ⭐⭐⭐⭐⭐ (고)

#### 4.2 Frontend Component

**컴포넌트**:
```
SystemSettings/
└── ConfigEditor/
    ├── index.tsx              # 메인
    ├── CodeEditor.tsx         # Monaco Editor
    ├── SyntaxHighlight.tsx    # 구문 강조
    ├── ValidationPanel.tsx    # 검증 결과
    └── BackupList.tsx         # 백업 목록
```

**UI 기능**:
- Monaco Editor 통합 (VS Code 에디터)
- 구문 강조
- 실시간 검증 (타이핑 시)
- Diff 뷰 (변경 사항 비교)
- 백업 목록 및 복원

**구현 난이도**: ⭐⭐⭐⭐⭐ (고)

**예상 작업량**: 2주

---

## 🤖 Phase 5: 자동 스케일링 (옵션, 4주)

**예상 기간**: 2025-11-23 ~ 2025-12-20  
**우선순위**: LOW  
**의존성**: Phase 4 완료

### 목표
부하에 따라 자동으로 노드를 추가/제거

### 구현 항목

#### 5.1 Backend API (`autoscaling_api.py`)

**엔드포인트**:
```python
GET    /api/autoscaling/policies          # 정책 목록
POST   /api/autoscaling/policies          # 정책 생성
PUT    /api/autoscaling/policies/<id>     # 정책 수정
DELETE /api/autoscaling/policies/<id>     # 정책 삭제
POST   /api/autoscaling/policies/<id>/toggle  # 활성화/비활성화
POST   /api/autoscaling/scale             # 수동 스케일링
GET    /api/autoscaling/history           # 스케일링 히스토리
GET    /api/autoscaling/metrics           # 현재 메트릭
```

**주요 기능**:
- 스케일링 정책 관리
- 메트릭 기반 트리거 (CPU, 메모리, 큐 길이)
- 클라우드 통합 (AWS/Azure/GCP)
- 쿨다운 메커니즘
- 백그라운드 모니터링 스레드

**구현 난이도**: ⭐⭐⭐⭐⭐ (최고)

#### 5.2 Frontend Component

**컴포넌트**:
```
AutoScaling/
├── index.tsx                 # 메인
├── PolicyList.tsx            # 정책 목록
├── PolicyForm.tsx            # 정책 생성/수정
├── MetricsChart.tsx          # 메트릭 차트
├── ScalingHistory.tsx        # 히스토리
└── ManualScale.tsx           # 수동 스케일링
```

**UI 기능**:
- 정책 목록 (트리거 조건, 액션)
- 정책 생성 폼 (트리거 설정, 노드 수)
- 메트릭 실시간 차트
- 스케일링 히스토리 타임라인
- 수동 스케일 버튼

**구현 난이도**: ⭐⭐⭐⭐⭐ (최고)

**예상 작업량**: 4주

**참고**: 이 기능은 클라우드 환경이 필요하므로 선택적으로 구현

---

## 📊 전체 타임라인

```
Week 1-2   [Phase 1-1: Health Check]            ✅ 완료
Week 2     [Phase 1-2: 노드 관리 기본]          ✅ 완료
Week 3-4   [Phase 2-1: 설정 관리 UI]             ⬜ 다음
Week 5     [Phase 2-2: 노드 관리 확장]          ⬜
Week 6-9   [Phase 3: 자동 스케일링] (옵션)       ⬜
```

---

## 🎯 각 Phase별 체크리스트

### Phase 1-2: 노드 관리 기본 (완료) ✅

- [x] Backend API 생성
  - [x] `node_management_api.py` 파일 생성
  - [x] Drain 엔드포인트 구현
  - [x] Resume 엔드포인트 구현
  - [x] Reboot 엔드포인트 구현
  - [x] 노드 목록 조회 구현
  - [x] 노드 상세 조회 구현
  - [x] 이력 조회 구현
  - [x] Mock Mode 지원
  - [x] `app.py`에 Blueprint 등록

- [x] Frontend 컴포넌트 생성
  - [x] `NodeManagement/` 폴더 생성
  - [x] `index.tsx` 구현 (노드 목록 테이블)
  - [x] 노드 상세 패널 구현
  - [x] Drain/Resume/Reboot 버튼 구현
  - [x] API 연동
  - [x] 에러 핸들링
  - [x] 로딩 상태 표시
  - [x] Auto Refresh 기능
  - [x] Stats Summary

- [x] Dashboard 통합
  - [x] 'nodes' 탭 추가
  - [x] Server 아이콘 설정
  - [x] 탭 라우팅 설정

- [x] 테스트
  - [x] Mock Mode 테스트 시나리오 6개 작성
  - [x] API curl 테스트 6개 작성
  - [x] UI/UX 확인
  - [x] 다크 모드 확인

- [x] 문서화
  - [x] API 문서 작성
  - [x] 사용 가이드 작성
  - [x] 완료 보고서 작성 (PHASE1_2_NODE_MANAGEMENT_COMPLETE.md)

### Phase 2-1: 설정 관리 UI (다음 단계)

- [ ] Partition 관리
- [ ] QoS 관리
- [ ] 노드별 설정 변경

---

## 💡 구현 팁

### Backend 개발 시
1. 항상 Mock Mode를 먼저 구현
2. Slurm 명령어는 subprocess로 래핑
3. 에러 핸들링 철저히 (try-except)
4. 로깅 추가 (print 또는 logging 모듈)

### Frontend 개발 시
1. 기존 컴포넌트 스타일 재사용 (ClusterStats, GroupPanel 등)
2. Tailwind CSS 클래스 사용
3. lucide-react 아이콘 사용
4. 다크 모드 항상 고려
5. 로딩 상태 반드시 표시
6. 에러 메시지 사용자 친화적으로

### 통합 시
1. 기존 코드 최소 수정
2. 새 파일만 추가하는 방식 선호
3. 통합 가이드 문서 작성
4. 테스트 후 커밋

---

## 📁 예상 파일 구조 (최종)

```
dashboard_refactory/
├── backend_5010/
│   ├── health_check_api.py           ✅ Phase 1
│   ├── node_management_api.py        ⬜ Phase 2
│   ├── system_config_api.py          ⬜ Phase 3-4
│   ├── autoscaling_api.py            ⬜ Phase 5
│   └── app.py                        (통합됨)
├── frontend_3010/
│   └── src/
│       └── components/
│           ├── HealthCheck/          ✅ Phase 1
│           ├── NodeManagement/       ⬜ Phase 2
│           ├── SystemSettings/       ⬜ Phase 3-4
│           │   ├── QoSManager/
│           │   └── ConfigEditor/
│           ├── AutoScaling/          ⬜ Phase 5
│           └── Dashboard.tsx         (통합됨)
└── docs/
    ├── PHASE1_COMPLETE.md            ✅
    ├── PHASE2_COMPLETE.md            ⬜
    ├── PHASE3_COMPLETE.md            ⬜
    ├── PHASE4_COMPLETE.md            ⬜
    └── PHASE5_COMPLETE.md            ⬜
```

---

## 🚀 지금 시작하기

Phase 1이 완료되었으므로, **Phase 2: 노드 관리**를 시작할 수 있습니다!

다음 명령으로 확인하시면 됩니다:

```bash
# Phase 1 테스트
curl http://localhost:5010/api/health/status | jq

# 브라우저에서 Health Check 탭 확인
# http://localhost:3010
```

**Phase 2 시작 준비가 되셨나요?** 🎯
