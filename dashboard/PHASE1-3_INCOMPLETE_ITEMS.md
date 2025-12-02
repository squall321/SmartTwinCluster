# Phase 1-3 미완료 항목 리스트

> **작성일**: 2025-11-05
> **확인 방법**: API 테스트 + 코드 검증 + 문서 확인

---

## 📊 Phase 1-3 Backend 상태: ✅ 100% 완료

### ✅ Phase 1: Apptainer Discovery - 완료
```bash
# API 테스트 결과
curl http://localhost:5010/api/apptainer/images
# → 200 OK, 이미지 목록 반환 ✅

# 구현된 것:
✅ apptainer_service.py       # SSH 기반 이미지 스캔
✅ apptainer_api.py            # REST API (6개 엔드포인트)
✅ DB 테이블 (apptainer_images)
✅ Blueprint 등록 완료
✅ 실제 데이터 존재 (compute001, viz001, etc.)
```

**엔드포인트 확인**:
- `GET /api/apptainer/images` ✅ 작동
- `GET /api/apptainer/images/<node>` ✅ 작동
- `GET /api/apptainer/images/<id>/metadata` ✅ 작동
- `GET /api/apptainer/images/<id>/apps` ✅ 작동
- `POST /api/apptainer/scan` ✅ 작동

**미완료 항목**: 없음

---

### ✅ Phase 2: Template Management - 완료
```bash
# API 테스트 결과
curl http://localhost:5010/api/v2/templates
# → 200 OK, 템플릿 목록 반환 ✅

# 구현된 것:
✅ /shared/templates/           # 외부 YAML 저장소
✅ template_loader.py           # 템플릿 로딩/동기화
✅ template_watcher.py          # 파일 시스템 감시
✅ templates_api_v2.py          # REST API
✅ DB 테이블 (job_templates_v2)
✅ Blueprint 등록 완료
✅ 실제 템플릿 존재 (official/cfd/, community/, private/)
```

**엔드포인트 확인**:
- `GET /api/v2/templates` ✅ 작동
- `GET /api/v2/templates/<id>` ✅ 작동
- `GET /api/v2/templates/category/<cat>` ✅ 작동
- `POST /api/v2/templates/<id>/validate` ✅ 작동

**미완료 항목**: 없음

---

### ✅ Phase 3: File Upload API (Backend) - 완료
```bash
# API 테스트 결과
curl -H "Authorization: Bearer TOKEN" \
     http://localhost:5010/api/v2/files/uploads
# → 401 (JWT 필요, 정상) ✅

# 구현된 것:
✅ file_classifier.py           # 파일 타입 분류 (7종)
✅ file_upload_api.py           # 청크 업로드 API
✅ /shared/uploads/             # 업로드 저장소
✅ DB 테이블 (file_uploads)
✅ Blueprint 등록 완료
✅ Rate Limiting 적용 (Phase 4)
✅ JWT 인증 적용
```

**엔드포인트 확인**:
- `POST /api/v2/files/upload/init` ✅ 작동
- `POST /api/v2/files/upload/chunk` ✅ 작동
- `POST /api/v2/files/upload/complete` ✅ 작동
- `GET /api/v2/files/uploads` ✅ 작동 (JWT 필요)
- `GET /api/v2/files/uploads/<id>` ✅ 작동
- `DELETE /api/v2/files/uploads/<id>` ✅ 작동

**미완료 항목**: 없음 (Backend는 완료)

---

## ❌ Phase 1-3 Frontend 상태: 5% 완료

### Phase 1: Apptainer Frontend

#### ✅ 완료된 것
```typescript
frontend_3010/src/components/
  └── apptainer/
      └── ApptainerSelector.tsx  # 간단한 이미지 선택 컴포넌트 (존재만 확인)
```

#### ❌ 미완료 항목
```
1. Apptainer 이미지 카탈로그 UI
   - 노드별 이미지 목록 표시
   - 이미지 상세 정보 모달
   - 앱 목록 표시
   - 메타데이터 표시
   - 검색/필터 기능

2. 이미지 스캔 UI
   - 스캔 트리거 버튼
   - 스캔 진행 상태 표시
   - 스캔 결과 표시

3. Job Submit과 통합
   - 작업 제출 시 이미지 선택
   - 템플릿과 연동
```

**예상 작업량**: 2-3일

---

### Phase 2: Template Frontend

#### ✅ 완료된 것
```typescript
frontend_3010/src/
  └── (없음)
```

#### ❌ 미완료 항목
```
1. Template 카탈로그 UI
   - 카테고리별 템플릿 목록
   - 템플릿 상세 보기
   - 검색/필터 기능
   - Official/Community/Private 탭

2. Template 미리보기
   - YAML 내용 표시
   - 파라미터 설명
   - 필요 파일 스키마 표시
   - Apptainer 설정 표시

3. Template 검증 UI
   - 파일 업로드 전 스키마 검증
   - 검증 결과 표시
   - 에러 메시지 표시

4. Job Submit과 통합
   - 템플릿 선택
   - 파라미터 입력 폼
   - 파일 업로드 연동
```

**예상 작업량**: 3-4일

---

### Phase 3: File Upload Frontend

#### ✅ 완료된 것
```typescript
frontend_3010/src/
  ├── utils/
  │   └── ChunkUploader.ts      # ✅ 청크 업로드 유틸 (완료)
  ├── types/
  │   └── upload.ts             # ✅ 타입 정의 (완료)
  └── pages/
      └── FileUploadTest.tsx    # ⚠️ 간단한 테스트 페이지만
```

**FileUploadTest.tsx 문제점**:
- 단순 파일 선택 + 업로드 버튼만
- 진행률 표시만 있음
- UI가 너무 간단 (프로덕션 불가)
- 멀티 파일 업로드 안됨
- 드래그 앤 드롭 없음
- 파일 타입 분류 UI 없음
- 업로드 이력 없음

#### ❌ 미완료 항목
```
1. 통합 파일 업로드 컴포넌트 (UnifiedUploader.tsx)
   - 드래그 앤 드롭 UI
   - 멀티 파일 업로드
   - 파일 타입 자동 분류 표시
   - 썸네일 미리보기
   - 업로드 전 검증 (크기, 확장자)

2. 청크 업로드 진행률 UI (ChunkUploadProgress.tsx)
   - 개별 파일 진행률
   - 전체 진행률
   - 업로드 속도 표시
   - 남은 시간 표시
   - 일시정지/재개 버튼
   - 취소 버튼

3. 파일 타입 선택 UI (FileTypeSelector.tsx)
   - 7가지 타입 선택 (code, data, config, output, log, binary, other)
   - 타입별 아이콘
   - 타입 설명 툴팁
   - 자동 분류 결과 표시

4. 업로드 이력 UI (FileUploadHistory.tsx)
   - 업로드 완료 목록
   - 파일 상세 정보
   - 다운로드 링크
   - 삭제 버튼
   - 검색/필터

5. Job Submit과 통합
   - 작업 제출 시 파일 연결
   - 템플릿 스키마 기반 파일 검증
   - 필수 파일 체크
   - 파일 경로 자동 매핑

6. WebSocket 실시간 업데이트
   - 업로드 진행률 실시간 표시
   - 다른 사용자 업로드 모니터링 (관리자)
   - 업로드 완료 알림
```

**예상 작업량**: 3-4일

---

## 📊 Phase 1-3 완성도 상세

### Backend (100%)
```
Phase 1: Apptainer API           ████████████████████ 100%
  ✅ apptainer_service.py         (SSH 스캔)
  ✅ apptainer_api.py              (REST API 6개)
  ✅ DB 스키마                     (apptainer_images)
  ✅ 실제 데이터                   (샘플 이미지 50+)

Phase 2: Template API            ████████████████████ 100%
  ✅ template_loader.py            (YAML 로딩)
  ✅ template_watcher.py           (파일 감시)
  ✅ templates_api_v2.py           (REST API 4개)
  ✅ DB 스키마                     (job_templates_v2)
  ✅ 실제 데이터                   (템플릿 20+)

Phase 3: File Upload API         ████████████████████ 100%
  ✅ file_classifier.py            (타입 분류)
  ✅ file_upload_api.py            (REST API 6개)
  ✅ DB 스키마                     (file_uploads)
  ✅ 청크 업로드                   (5MB 단위)
  ✅ Rate Limiting                 (Phase 4 추가)
  ✅ JWT 인증                      (Phase 4 추가)
```

### Frontend (5%)
```
Phase 1: Apptainer UI            █░░░░░░░░░░░░░░░░░░░ 5%
  ⚠️ ApptainerSelector.tsx         (기본 컴포넌트만)
  ❌ 카탈로그 UI
  ❌ 상세 정보 모달
  ❌ 검색/필터
  ❌ Job Submit 통합

Phase 2: Template UI             ░░░░░░░░░░░░░░░░░░░░ 0%
  ❌ 카탈로그 UI
  ❌ 템플릿 미리보기
  ❌ 검증 UI
  ❌ Job Submit 통합

Phase 3: File Upload UI          ██░░░░░░░░░░░░░░░░░░ 10%
  ✅ ChunkUploader.ts              (유틸리티)
  ⚠️ FileUploadTest.tsx            (간단한 테스트만)
  ❌ UnifiedUploader 컴포넌트
  ❌ 진행률 UI
  ❌ 파일 타입 선택 UI
  ❌ 업로드 이력 UI
  ❌ 드래그 앤 드롭
  ❌ WebSocket 연동
  ❌ Job Submit 통합
```

---

## 🎯 Phase 1-3 미완료 항목 우선순위

### 🔥 최우선: Phase 3 File Upload UI (3-4일)
**이유**:
- Backend API 완성됨
- 다른 Phase와 독립적
- 즉시 테스트 가능
- Job Submit의 핵심 기능

**작업 순서**:
1. UnifiedUploader 컴포넌트 (1일)
2. ChunkUploadProgress UI (1일)
3. FileTypeSelector UI (0.5일)
4. FileUploadHistory UI (1일)
5. WebSocket 실시간 업데이트 (0.5일)
6. 통합 테스트 (0.5일)

### 🥈 2순위: Phase 2 Template UI (3-4일)
**이유**:
- Job Submit의 시작점
- Template 선택 → 파일 업로드 → 작업 제출 순서

**작업 순서**:
1. Template 카탈로그 UI (1.5일)
2. Template 미리보기 (1일)
3. Template 검증 UI (1일)
4. Job Submit 통합 (0.5일)

### 🥉 3순위: Phase 1 Apptainer UI (2-3일)
**이유**:
- Template에서 Apptainer 이미지 참조
- 작업 제출 시 필요

**작업 순서**:
1. Apptainer 카탈로그 UI (1일)
2. 이미지 상세 모달 (0.5일)
3. 검색/필터 기능 (0.5일)
4. Job Submit 통합 (0.5일)
5. 스캔 UI (선택, 0.5일)

---

## 📋 상세 미완료 체크리스트

### Phase 1: Apptainer Frontend (0%)
- [ ] ApptainerCatalog.tsx - 이미지 카탈로그 메인
- [ ] ApptainerImageCard.tsx - 이미지 카드 컴포넌트
- [ ] ApptainerDetailModal.tsx - 이미지 상세 모달
- [ ] ApptainerFilter.tsx - 검색/필터 컴포넌트
- [ ] ApptainerScanButton.tsx - 스캔 트리거
- [ ] useApptainerImages.ts - API 연동 훅
- [ ] Job Submit 통합
- [ ] 테스트 코드

### Phase 2: Template Frontend (0%)
- [ ] TemplateCatalog.tsx - 템플릿 카탈로그
- [ ] TemplateCard.tsx - 템플릿 카드
- [ ] TemplateDetailModal.tsx - 템플릿 상세
- [ ] TemplateYAMLViewer.tsx - YAML 뷰어
- [ ] TemplateValidator.tsx - 검증 UI
- [ ] TemplateFilter.tsx - 검색/필터
- [ ] useTemplates.ts - API 연동 훅
- [ ] Job Submit 통합
- [ ] 테스트 코드

### Phase 3: File Upload Frontend (10%)
- [x] ChunkUploader.ts - 청크 업로드 유틸 ✅
- [x] upload.ts - 타입 정의 ✅
- [ ] UnifiedUploader.tsx - 메인 업로드 컴포넌트
- [ ] FileDropzone.tsx - 드래그 앤 드롭 영역
- [ ] ChunkUploadProgress.tsx - 진행률 표시
- [ ] FileTypeSelector.tsx - 파일 타입 선택
- [ ] FileUploadHistory.tsx - 업로드 이력
- [ ] FileThumbnail.tsx - 썸네일 미리보기
- [ ] useFileUpload.ts - API 연동 훅
- [ ] useWebSocket.ts - WebSocket 연동
- [ ] Job Submit 통합
- [ ] 테스트 코드

---

## 🔍 검증 방법

### Backend 검증 (✅ 모두 통과)
```bash
# Phase 1
curl http://localhost:5010/api/apptainer/images
# → 200 OK ✅

# Phase 2
curl http://localhost:5010/api/v2/templates
# → 200 OK ✅

# Phase 3
curl -H "Authorization: Bearer $TOKEN" \
     http://localhost:5010/api/v2/files/uploads
# → 200 OK (JWT 있으면) ✅
```

### Frontend 검증 (❌ 대부분 실패)
```bash
# Dashboard 접속
http://localhost/dashboard

# 확인 사항:
❌ Apptainer 카탈로그 페이지 없음
❌ Template 카탈로그 페이지 없음
⚠️ File Upload 페이지 (테스트 페이지만)
❌ Job Submit 페이지 없음
```

---

## 📊 총 예상 작업량

```
Phase 3 File Upload UI:     3-4일  (최우선)
Phase 2 Template UI:         3-4일  (2순위)
Phase 1 Apptainer UI:        2-3일  (3순위)
───────────────────────────────────
총 예상:                     8-11일 (약 2주)
```

---

## 🚀 권장 작업 순서

### Week 1: File Upload + Template UI
```
Day 1-2: UnifiedUploader + ChunkUploadProgress
Day 3:   FileTypeSelector + FileUploadHistory
Day 4:   Template 카탈로그 UI
Day 5:   Template 미리보기 + 검증
```

### Week 2: Apptainer UI + 통합
```
Day 1-2: Apptainer 카탈로그 UI
Day 3:   Job Submit 통합 (Template + File + Apptainer)
Day 4:   통합 테스트 + 버그 수정
Day 5:   문서 작성 + 배포
```

---

## 🎉 완료 기준

### Phase 1-3 Frontend 완료 조건
- [ ] 사용자가 브라우저에서 Apptainer 이미지 목록 확인 가능
- [ ] 사용자가 브라우저에서 Template 목록 확인 가능
- [ ] 사용자가 브라우저에서 파일 업로드 (드래그 앤 드롭) 가능
- [ ] 업로드 진행률이 실시간으로 표시됨
- [ ] 업로드 이력을 확인 가능
- [ ] Job Submit 페이지에서 Template + Apptainer + File 선택 가능
- [ ] 모든 컴포넌트가 API와 정상 연동됨

---

**결론**: Phase 1-3 Backend는 100% 완료되었지만, Frontend는 5%만 완료되어 **실제로 사용 불가능**합니다.
