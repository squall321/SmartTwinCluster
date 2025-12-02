# Data Management Module v2.0

## 📁 개요

Slurm 클러스터의 스토리지를 효율적으로 관리하는 모듈입니다. 대형 공유 스토리지(/Data)와 로컬 스크래치 스토리지(/scratch)를 분리하여 관리하며, **파일 브라우저 기능**을 통해 직관적인 데이터 탐색이 가능합니다.

---

## ✨ v2.0 주요 업데이트

### 🆕 새로운 기능
- **파일 브라우저**: 디렉토리 탐색 및 파일 관리
- **Transfer Manager**: 실시간 전송 진행률 모니터링
- **Browse 버튼**: 데이터셋/노드에서 파일 시스템 직접 탐색
- **파일 타입별 아이콘**: 직관적인 시각적 표시
- **정렬 가능한 파일 목록**: 이름, 크기, 날짜 등으로 정렬
- **Breadcrumb 네비게이션**: 현재 경로 표시 및 빠른 이동

---

## 🏗️ 스토리지 아키텍처

### 1. **/Data - 공유 스토리지**
- **마운트**: 모든 노드 (관리 노드 + 계산 노드)
- **용도**: 장기 데이터 보관, 데이터셋 관리
- **특징**: 모든 노드에서 접근 가능, 분석 자동화 SW 연동

### 2. **/scratch - 로컬 스토리지**
- **마운트**: 각 계산 노드 개별
- **용도**: 작업 실행 중 임시 데이터
- **특징**: 고속 로컬 I/O, 노드별 독립 관리

---

## 📂 컴포넌트 구조

```
DataManagement/
├── index.tsx                 # 메인 (탭 네비게이션)
├── SharedStorageView.tsx     # /Data 뷰
├── ScratchStorageView.tsx    # /scratch 뷰
├── FileBrowser.tsx           # 파일 브라우저
├── FileList.tsx              # 파일 목록 테이블
├── FileToolbar.tsx           # 파일 작업 툴바
├── TransferManager.tsx       # 전송 관리자
└── README.md                 # 이 문서
```

---

## 🎯 주요 기능

### File Browser (파일 브라우저)
- ✅ 디렉토리 탐색
- ✅ Breadcrumb 네비게이션
- ✅ 파일/폴더 목록 (정렬 가능)
- ✅ 다중 선택 (체크박스)
- ✅ 파일 타입별 아이콘
- ✅ 상세 정보 표시
- ✅ 검색 및 필터

### Shared Storage (/Data)
- ✅ 스토리지 통계 (4개 카드)
- ✅ 데이터셋 목록
- ✅ 검색 및 상태 필터
- ✅ **Browse 버튼**으로 파일 탐색
- ✅ 분석 자동화 통합 배너

### Scratch Storage (/scratch)
- ✅ 노드별 통계 (4개 카드)
- ✅ 노드 목록 (확장/축소)
- ✅ 디렉토리 다중 선택
- ✅ **Browse 버튼**으로 파일 탐색
- ✅ Move to /Data / Delete
- ✅ 사용률 색상 표시

### Transfer Manager
- ✅ 실시간 진행률
- ✅ 작업 큐 관리
- ✅ 속도 및 ETA 표시
- ✅ 취소/재시도
- ✅ 완료/실패 목록

---

## 🎯 사용 시나리오

### 1. 데이터셋 파일 탐색
1. Shared Storage 탭 → 데이터셋에서 **Browse** 클릭
2. 파일 브라우저로 내부 탐색
3. 폴더 클릭하여 하위 이동
4. 파일 정렬 및 검색
5. 필요한 파일 선택하여 다운로드

### 2. 작업 완료 후 데이터 보관
1. Scratch Storage 탭 → 노드 확장
2. 작업 출력 디렉토리 선택
3. "Move to /Data" 클릭
4. 대상 경로 지정
5. Transfer Manager에서 진행률 확인

### 3. /scratch 공간 확보
1. Scratch Storage 탭 → High Usage 노드 확인
2. 오래된 디렉토리 선택
3. "Delete" 클릭 → 확인
4. 사용률 즉시 감소

### 4. 노드 파일 시스템 탐색
1. Scratch Storage 탭 → 노드에서 **Browse** 클릭
2. 파일 브라우저로 /scratch 전체 탐색
3. 디렉토리별 파일 확인
4. 필요한 파일 선택 및 작업

---

## 🎨 디자인

### 색상 테마
- **Shared Storage**: 보라색 (#A855F7)
- **Scratch Storage**: 파란색 (#3B82F6)
- **경고**: 주황색 (75%+), 빨간색 (90%+)

### 파일 아이콘
- 📁 폴더: 파란색
- 🖼️ 이미지: 녹색
- 💻 코드: 보라색
- 📊 데이터: 노란색
- 📦 압축: 주황색

---

## 🔌 Mock 데이터

현재 모든 데이터는 `src/data/mockStorageData.ts`에서 생성됩니다:

```typescript
import { 
  mockStorageStats,
  mockDatasets,
  mockScratchNodes,
  generateMockFiles
} from '../../data/mockStorageData';
```

---

## 🚀 다음 단계 (백엔드 연동)

### Phase 2: API 연동
- [ ] 실제 파일 시스템 스캔
- [ ] 이동/복사/삭제 구현
- [ ] 실시간 용량 업데이트
- [ ] 파일 업로드/다운로드
- [ ] WebSocket 실시간 알림

### Phase 3: 고급 기능
- [ ] 파일 미리보기
- [ ] 압축/해제
- [ ] 권한 관리
- [ ] 쿼터 관리
- [ ] 배치 작업
- [ ] 스케줄링

---

## 📝 변경 이력

### v2.0.0 (2024-10-07)
- ✨ 파일 브라우저 추가
- ✨ Transfer Manager 추가
- ✨ Browse 버튼
- ✨ 파일 타입별 아이콘
- ✨ 정렬 가능한 파일 목록
- ✨ 다중 작업 지원
- 🎨 UI/UX 전반적 개선

### v1.0.0 (2024-01-10)
- ✨ 초기 릴리즈
- ✨ Shared/Scratch Storage 뷰
- ✨ Move to /Data, Delete
- ✨ 검색 및 필터링

---

**Happy Data Management! 🚀**

마지막 업데이트: 2024-10-07  
버전: 2.0.0
