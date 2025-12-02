# Auth Portal 프로젝트 로드맵

**프로젝트**: Slurm Dashboard - Authentication & Service Integration
**시작일**: 2025-10-10
**현재 상태**: Phase 0-4 완료 ✅

---

## 📋 전체 개요

### 완료된 Phase (Phase 0-4) ✅

#### Phase 0: 사전 준비 (완료 ✅)
- ✅ Slurm 클러스터 설정 업데이트 (GPU, VNC 파티션)
- ✅ Redis 세션 스토리지 구축
- ✅ SAML-IdP 개발 환경 구축
- ✅ SSL 인증서 발급 및 Nginx 설정
- ✅ Apptainer 샌드박스 환경 검증

#### Phase 1: Auth Portal 개발 (완료 ✅)
- ✅ Auth Backend (Flask + python3-saml + PyJWT)
- ✅ Auth Frontend (React + TypeScript + Vite)
- ✅ SAML 2.0 SSO 인증 통합
- ✅ JWT 토큰 발급 및 검증
- ✅ Redis 세션 관리
- ✅ ServiceMenu (그룹 기반 서비스 선택)

#### Phase 2: JWT 인증 통합 - Test Login으로 변경 (완료 ✅)
- ✅ SAML SSO 버그로 인해 Test Login 구현
- ✅ backend_5010 Mock 모드 지원
- ✅ Test Login: `POST /auth/test-login` API
- ✅ 테스트 사용자: admin, user01, gpu_user, cae_user

#### Phase 3: Dashboard Frontend JWT 통합 (완료 ✅)
- ✅ frontend_3010에 JWT 토큰 처리 로직 추가
- ✅ `utils/api.ts`: JWT 토큰 관리 함수
- ✅ `App.tsx`: URL에서 토큰 추출 및 저장
- ✅ 자동 JWT 헤더 주입 (Authorization: Bearer)
- ✅ 401 에러 인터셉터 (재로그인 리다이렉트)

#### Phase 4: Production Mode 전환 (완료 ✅)
- ✅ backend_5010 MOCK_MODE=false 설정
- ✅ 실제 Slurm 클러스터 연결 (23.11.10, 2 nodes)
- ✅ 실제 Job 제출 테스트 (Job ID 2)
- ✅ Production 환경 검증 완료

#### 추가 개선사항 (완료 ✅)
- ✅ Service Menu 3단 그리드 레이아웃
- ✅ LS-DYNA HPC Cluster 브랜딩
- ✅ 서비스 이름 업데이트:
  - Smart Twin Flow (HPC Dashboard)
  - Smart Twin Cluster Extreme (CAE 자동화)
  - Smart Twin Desktop (VNC Desktop)
- ✅ kooCAEWeb_5173 서비스 연결

---

## 🚀 향후 계획 (Phase 5 이후)

### Phase 5: VNC 시각화 시스템 (2-3주, 선택사항)

**목표**: GPU 기반 원격 데스크톱 환경 구축

#### 주요 작업
1. **Apptainer 샌드박스 이미지**
   - Ubuntu 22.04 + NVIDIA Driver + X11
   - TurboVNC Server 설치
   - LS-PrePost, ParaView 등 시각화 도구

2. **VNC Backend API (backend_5010 확장)**
   ```python
   POST   /api/vnc/sessions         # VNC 세션 생성
   GET    /api/vnc/sessions         # 세션 목록 조회
   DELETE /api/vnc/sessions/<id>    # 세션 종료
   GET    /api/vnc/sessions/<id>    # 세션 상태 조회
   ```

3. **noVNC 웹 인터페이스**
   - 브라우저에서 직접 VNC 접속
   - WebSocket 기반 실시간 화면 전송

4. **Slurm Job 통합**
   - VNC 세션을 Slurm Job으로 제출
   - GPU 전용 파티션 (vnc) 활용
   - 자동 포트 할당 (5900+)

**예상 난이도**: ⭐⭐⭐⭐ (상)

---

### Phase 6: 모니터링 및 로깅 (1주)

**목표**: 시스템 운영 가시성 확보

#### 주요 작업
1. **중앙 로깅 시스템**
   - 모든 서비스 로그를 중앙 집중화
   - Elasticsearch + Kibana (선택사항)
   - 또는 파일 기반 로그 집계

2. **모니터링 대시보드**
   - 서비스 상태 모니터링
   - Redis 메모리 사용량
   - Slurm 클러스터 상태
   - 사용자 세션 통계

3. **알림 시스템**
   - 서비스 다운 알림
   - 디스크 용량 경고
   - Job 실패 알림

**예상 난이도**: ⭐⭐⭐ (중)

---

### Phase 7: 사용자 관리 및 권한 (1주, 선택사항)

**목표**: 웹 UI에서 사용자 및 권한 관리

#### 주요 작업
1. **Admin 페이지**
   - 사용자 목록 조회
   - 그룹 할당/해제
   - 권한 수정

2. **사용자 프로필**
   - 내 정보 조회
   - 비밀번호 변경 (SAML 제외)
   - 세션 관리

3. **감사 로그**
   - 사용자 행동 추적
   - 로그인 이력
   - 권한 변경 이력

**예상 난이도**: ⭐⭐⭐ (중)

---

### Phase 8: 문서화 및 배포 자동화 (1주)

**목표**: 운영 및 유지보수 용이성 향상

#### 주요 작업
1. **사용자 매뉴얼**
   - 로그인 가이드
   - 서비스별 사용법
   - FAQ

2. **관리자 가이드**
   - 설치 가이드
   - 설정 가이드
   - 트러블슈팅

3. **자동 배포 스크립트**
   - 일괄 설치 스크립트
   - 서비스 시작/중지 스크립트
   - 백업/복원 스크립트

4. **API 문서**
   - Swagger/OpenAPI 통합
   - 엔드포인트 문서화

**예상 난이도**: ⭐⭐ (하)

---

## 📊 전체 타임라인

```
Week 1-2   [Phase 0: 사전 준비]                    ✅ 완료
Week 3-5   [Phase 1: Auth Portal 개발]             ✅ 완료
Week 6     [Phase 2: Test Login 구현]              ✅ 완료
Week 7     [Phase 3: Dashboard JWT 통합]           ✅ 완료
Week 8     [Phase 4: Production 전환]              ✅ 완료
Week 9-11  [Phase 5: VNC 시각화] (선택)            ⬜ 대기
Week 12    [Phase 6: 모니터링 & 로깅]              ⬜ 대기
Week 13    [Phase 7: 사용자 관리] (선택)            ⬜ 대기
Week 14    [Phase 8: 문서화 & 배포 자동화]          ⬜ 대기
```

---

## 🎯 우선순위 평가

### HIGH (필수)
- ✅ Phase 0-4: 인증 및 기본 통합 (완료)

### MEDIUM (권장)
- ⬜ Phase 6: 모니터링 및 로깅 (운영 필수)
- ⬜ Phase 8: 문서화 (유지보수 필수)

### LOW (선택사항)
- ⬜ Phase 5: VNC 시각화 (GPU 사용자 필요 시)
- ⬜ Phase 7: 사용자 관리 (대규모 사용자 환경)

---

## ✅ 현재 시스템 상태 (2025-10-16)

### 실행 중인 서비스 (10개)
1. **SAML-IdP** (7000) - 개발/테스트용 ⚠️
2. **Auth Backend** (4430) - JWT 발급
3. **Auth Frontend** (4431) - Service Menu
4. **Backend** (5010) - Dashboard API (Production)
5. **Frontend** (3010) - Dashboard UI
6. **WebSocket** (5011) - 실시간 통신
7. **Redis** (6379) - 세션 스토리지
8. **kooCAEWeb** (5173) - CAE Frontend
9. **kooCAEWebServer** (5000) - CAE Backend
10. **kooCAEWebAutomation** (5001) - CAE Automation

### Slurm 클러스터
- **버전**: 23.11.10
- **노드**: node001, node002
- **Production Mode**: MOCK_MODE=false
- **최근 Job**: Job ID 2 (정상 실행)

### 인증 시스템
- **방식**: Test Login (SAML SSO는 버그로 비활성화)
- **JWT**: HS256, 8시간 TTL
- **세션**: Redis (TTL 동기화)

### 브랜딩
- **타이틀**: LS-DYNA HPC Cluster
- **서비스**: Smart Twin Flow, Cluster Extreme, Desktop

---

## 💡 다음 단계 추천

### 즉시 가능한 작업
1. **문서화 시작** (Phase 8)
   - 현재 시스템 사용 가이드 작성
   - API 엔드포인트 문서화
   - 트러블슈팅 가이드

2. **모니터링 구축** (Phase 6)
   - 서비스 Health Check 대시보드
   - 로그 집계 시스템
   - 알림 설정

### 중장기 작업
3. **VNC 시각화** (Phase 5) - GPU 시각화 필요 시
4. **사용자 관리** (Phase 7) - 사용자 증가 시

---

## 📁 프로젝트 구조

```
dashboard/
├── auth_portal_4430/          # Auth Backend (Flask)
├── auth_portal_4431/          # Auth Frontend (React)
├── backend_5010/              # Dashboard Backend (Flask)
├── frontend_3010/             # Dashboard Frontend (React)
├── websocket_5011/            # WebSocket Server
├── saml_idp_7000/             # SAML-IdP (개발용)
├── kooCAEWeb_5173/            # CAE Frontend
├── kooCAEWebServer_5000/      # CAE Backend
└── kooCAEWebAutomationServer_5001/  # CAE Automation
```

---

## 🚨 중요 참고사항

### Docker/Kubernetes 제외 이유
1. **Apptainer 사용**: HPC 환경에 최적화
2. **단일 서버 환경**: 현재 구성에서 불필요
3. **디버깅 편의성**: 로컬 프로세스가 디버깅 용이
4. **복잡도 증가**: 현재 시스템에 과도한 복잡성 추가

### 향후 Docker 고려 시점
- 멀티 서버 배포 필요 시
- 팀 협업 환경 구축 시
- Auto-scaling 필요 시 (Kubernetes)

---

**로드맵 최종 수정일**: 2025-10-16
**다음 리뷰**: Phase 5 시작 전

