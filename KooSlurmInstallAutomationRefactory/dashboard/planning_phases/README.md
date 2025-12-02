# 개발 계획 실행 가이드

**프로젝트**: SAML SSO 통합 인증 + GPU VNC 시각화 시스템
**총 기간**: 8주
**최종 업데이트**: 2025-10-16

---

## 📚 문서 구조

이 디렉토리는 전체 개발 프로젝트를 **6개의 Phase**로 나누어 단계별 실행 계획을 제공합니다.

### 문서 목록

| Phase | 문서 | 기간 | 주요 작업 | 상태 |
|-------|------|------|----------|------|
| **Phase 0** | [Prerequisites](Phase0_Prerequisites.md) | 1주 | Slurm 설정, Redis, SAML-IdP, Nginx, Apptainer 환경 구축 | 📋 Ready |
| **Phase 1** | [Auth Portal](Phase1_Auth_Portal.md) | 2-3주 | SAML SSO + JWT 인증 시스템 구축 | 📋 Ready |
| **Phase 2** | [Service Integration](Phase2_Service_Integration.md) | 1주 | 기존 서비스(backend_5010, frontend_3010)에 JWT 추가 | 📋 Ready |
| **Phase 3** | [VNC System](Phase3_VNC_System.md) | 2주 | Apptainer VNC 이미지, Slurm 통합, noVNC 구현 | 📋 Ready |
| **Phase 4** | [CAE & Monitoring](Phase4_CAE_Monitoring.md) | 1주 | CAE 서비스 JWT 통합, Prometheus/Grafana 구축 | 📋 Ready |
| **Phase 5** | [Testing & Docs](Phase5_Testing_Docs.md) | 1주 | 통합 테스트, 부하 테스트, 운영 문서 작성 | 📋 Ready |

---

## 🚀 빠른 시작

### 1. Phase 0부터 순차적으로 시작
```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/planning_phases

# Phase 0 문서 확인
cat Phase0_Prerequisites.md

# Phase 0 실행
# (문서의 Day 1-5 단계 따라하기)
```

### 2. 각 Phase 완료 후 검증
- 각 Phase 문서 끝에 있는 **검증 체크리스트** 활용
- 모든 항목 체크 후 다음 Phase 진행

### 3. 트러블슈팅
- 각 Phase 문서에 **트러블슈팅 섹션** 포함
- 일반적인 문제와 해결 방법 제시

---

## 📊 전체 개발 로드맵

```
Week 1        Week 2-4           Week 5       Week 6-7      Week 8      Week 9
┌─────────┐  ┌──────────────┐  ┌─────────┐  ┌─────────┐  ┌────────┐  ┌────────┐
│ Phase 0 │→ │   Phase 1    │→ │ Phase 2 │→ │ Phase 3 │→ │Phase 4 │→ │Phase 5 │
│  준비   │  │  Auth Portal │  │ 서비스  │  │   VNC   │  │ 모니터 │  │ 테스트 │
│         │  │ (SAML + JWT) │  │  통합   │  │  시스템 │  │  링    │  │ & 문서 │
└─────────┘  └──────────────┘  └─────────┘  └─────────┘  └────────┘  └────────┘
    ↓              ↓               ↓            ↓           ↓           ↓
 인프라 준비    중앙 인증 구축   기존 통합   VNC 구현   CAE 통합    프로덕션
```

---

## 🎯 Phase별 주요 목표

### Phase 0: 사전 준비 (1주)
**목표**: 모든 개발의 기반이 되는 인프라 구축

**핵심 작업**:
- ✅ my_cluster.yaml 업데이트 (GPU, VNC 파티션)
- ✅ Redis 7+ 설치 및 설정
- ✅ SAML-IdP 개발 환경 구축
- ✅ Nginx HTTPS 설정
- ✅ Apptainer 샌드박스 환경 준비

**성공 기준**:
- `sinfo -p vnc` → vnc 파티션 확인
- `redis-cli ping` → PONG
- `curl http://localhost:7000/metadata` → SAML 메타데이터
- `curl -k https://localhost` → HTTPS 접속

**다음 단계**: Phase 1 (Auth Portal 개발)

---

### Phase 1: Auth Portal (2-3주)
**목표**: SAML 2.0 SSO + JWT 토큰 발급 시스템

**핵심 작업**:
- Week 1: Auth Backend (Flask + python3-saml + PyJWT)
- Week 2: Auth Frontend (React + TypeScript)
- Week 3: 통합 테스트

**아키텍처**:
```
User → SAML SSO → saml-idp → Auth Backend
                                 ↓
                            JWT 발급 + Redis 세션
                                 ↓
                            ServiceMenu (서비스 선택)
```

**성공 기준**:
- SSO 로그인 성공
- JWT 토큰 발급 및 검증
- ServiceMenu에서 그룹별 서비스 필터링

**다음 단계**: Phase 2 (기존 서비스 통합)

---

### Phase 2: 기존 서비스 통합 (1주)
**목표**: backend_5010, frontend_3010에 JWT 인증 추가

**핵심 작업**:
- Day 1-2: JWT 미들웨어 구현 (backend)
- Day 3-4: Axios 인터셉터 (frontend)
- Day 5: 통합 테스트

**통합 플로우**:
```
ServiceMenu → Dashboard 선택 (token=<JWT>)
    ↓
frontend_3010 (토큰 추출 → localStorage)
    ↓
API 요청 (Authorization: Bearer <token>)
    ↓
backend_5010 (JWT 검증 → g.user)
```

**성공 기준**:
- JWT 없이 API 호출 → 401
- 유효한 JWT → 정상 동작
- 그룹별 권한 검증 정상

**다음 단계**: Phase 3 (VNC 시스템)

---

### Phase 3: VNC 시각화 시스템 (2주)
**목표**: Apptainer + TurboVNC + GPU 원격 데스크톱

**핵심 작업**:
- Week 1: Apptainer VNC 이미지, Slurm Job 통합
- Week 2: VNC API, noVNC Frontend

**기술 스택**:
- Apptainer Sandbox (writable)
- TurboVNC 3.1+ (GPU 가속)
- VirtualGL 3.1+ (OpenGL)
- noVNC 1.4+ (웹 클라이언트)
- WebSockify (VNC-WebSocket 프록시)

**성공 기준**:
- VNC 세션 생성 API 동작
- Slurm Job으로 VNC 서버 시작
- noVNC로 데스크톱 접속
- 데스크톱에서 `nvidia-smi` 성공

**다음 단계**: Phase 4 (CAE & Monitoring)

---

### Phase 4: CAE 통합 및 모니터링 (1주)
**목표**: CAE 서비스 JWT 추가 + Prometheus/Grafana 대시보드

**핵심 작업**:
- Day 1-2: kooCAEWebServer_5000, kooCAEWeb_5173 JWT 통합
- Day 3-4: Prometheus 메트릭 추가
- Day 5: Grafana 대시보드 생성

**모니터링 메트릭**:
- `auth_saml_requests_total` - SAML 요청 수
- `auth_jwt_issued_total` - JWT 발급 수
- `vnc_sessions_total` - 활성 VNC 세션
- `vnc_sessions_created_total` - 생성된 세션 총 수

**성공 기준**:
- ServiceMenu에서 CAE 접근 가능
- Grafana 대시보드에서 메트릭 확인

**다음 단계**: Phase 5 (테스트 & 문서)

---

### Phase 5: 테스트 및 문서화 (1주)
**목표**: 통합 테스트, 부하 테스트, 운영 문서 작성

**핵심 작업**:
- Day 1-2: 단위/통합 테스트
- Day 3: 부하 테스트 (동시 VNC 세션 10개)
- Day 4-5: 문서 작성

**문서 목록**:
- API.md - API 문서 (Swagger)
- OPERATIONS.md - 운영 매뉴얼
- USER_GUIDE.md - 사용자 가이드
- TROUBLESHOOTING.md - 트러블슈팅

**성공 기준**:
- 테스트 커버리지 > 80%
- 부하 테스트 통과
- 모든 문서 작성 완료

**최종 결과**: 프로덕션 배포 준비 완료 🎉

---

## 📁 프로젝트 구조 (완성 후)

```
dashboard/
├── planning_phases/              # 📂 이 디렉토리
│   ├── README.md                 # 인덱스 (현재 파일)
│   ├── Phase0_Prerequisites.md
│   ├── Phase1_Auth_Portal.md
│   ├── Phase2_Service_Integration.md
│   ├── Phase3_VNC_System.md
│   ├── Phase4_CAE_Monitoring.md
│   └── Phase5_Testing_Docs.md
│
├── auth_portal_4430/             # Phase 1에서 생성
│   ├── app.py
│   ├── saml_handler.py
│   ├── jwt_handler.py
│   ├── redis_client.py
│   └── saml/
│
├── auth_portal_4431/             # Phase 1에서 생성
│   ├── src/
│   │   ├── pages/
│   │   │   ├── Login.tsx
│   │   │   └── ServiceMenu.tsx
│   │   └── utils/jwt.ts
│   └── package.json
│
├── saml_idp_7000/                # Phase 0에서 생성
│   ├── config/users.json
│   └── start_idp.sh
│
├── backend_5010/                 # Phase 2에서 수정
│   ├── middleware/jwt_middleware.py
│   ├── vnc_manager.py            # Phase 3에서 추가
│   └── routes/vnc.py             # Phase 3에서 추가
│
├── frontend_3010/                # Phase 2에서 수정
│   ├── src/utils/jwt.ts
│   ├── src/api/client.ts
│   └── src/pages/VncSessions.tsx # Phase 3에서 추가
│
├── kooCAEWebServer_5000/         # Phase 4에서 수정
├── kooCAEWeb_5173/               # Phase 4에서 수정
│
├── prometheus_9090/              # Phase 4에서 설정 추가
└── grafana/                      # Phase 4에서 대시보드 추가
```

---

## ✅ 전체 검증 체크리스트

### Phase 0 완료 확인
- [ ] Slurm vnc 파티션 생성
- [ ] Redis 실행 및 PING 응답
- [ ] SAML-IdP 메타데이터 접근
- [ ] Nginx HTTPS 접속
- [ ] Apptainer GPU 테스트 성공

### Phase 1 완료 확인
- [ ] SAML SSO 로그인 성공
- [ ] JWT 토큰 발급
- [ ] ServiceMenu 그룹 필터링
- [ ] Redis 세션 저장

### Phase 2 완료 확인
- [ ] JWT 미들웨어 동작
- [ ] Axios 인터셉터 동작
- [ ] API 호출 시 JWT 자동 포함
- [ ] 그룹별 권한 검증

### Phase 3 완료 확인
- [ ] Apptainer VNC 이미지 빌드
- [ ] Slurm Job 제출 성공
- [ ] VNC 서버 시작
- [ ] noVNC 접속 성공
- [ ] GPU 인식 (`nvidia-smi`)

### Phase 4 완료 확인
- [ ] CAE 서비스 JWT 통합
- [ ] Prometheus 메트릭 수집
- [ ] Grafana 대시보드 표시

### Phase 5 완료 확인
- [ ] 단위 테스트 > 80%
- [ ] 통합 테스트 통과
- [ ] 부하 테스트 성공
- [ ] 모든 문서 작성

---

## 🔧 트러블슈팅 가이드

### 일반적인 문제

#### 1. SAML 인증 실패
**증상**: 로그인 시 에러 페이지
**해결**: [Phase1_Auth_Portal.md](Phase1_Auth_Portal.md#트러블슈팅) 참조

#### 2. JWT 검증 실패
**증상**: API 호출 시 401 에러
**해결**: [Phase2_Service_Integration.md](Phase2_Service_Integration.md#트러블슈팅) 참조

#### 3. VNC 세션 시작 실패
**증상**: Job이 PENDING 상태로 멈춤
**해결**: [Phase3_VNC_System.md](Phase3_VNC_System.md#트러블슈팅) 참조

#### 4. 메트릭 수집 실패
**증상**: Grafana에서 데이터 표시 안 됨
**해결**: [Phase4_CAE_Monitoring.md](Phase4_CAE_Monitoring.md#트러블슈팅) 참조

---

## 📞 지원 및 문의

### 문서 관련
- 각 Phase 문서에 상세한 단계별 가이드 포함
- 코드 예제, 명령어, 설정 파일 모두 제공

### 기술 지원
- Phase별 트러블슈팅 섹션 확인
- 검증 체크리스트로 진행 상황 확인

---

## 📝 버전 이력

| 버전 | 날짜 | 변경 사항 |
|------|------|----------|
| 1.0 | 2025-10-16 | 초기 계획 문서 작성 (Phase 0-5) |

---

## 🎉 프로젝트 완료 후

### 최종 시스템 아키텍처
```
User Browser
    ↓ HTTPS (443)
Nginx Reverse Proxy
    ↓
Auth Portal (4430/4431)
    ↓ SAML SSO
saml-idp (7000) → JWT Token
    ↓
ServiceMenu (그룹별 필터링)
    ├─→ Dashboard (3010/5010) + VNC (Phase 2-3)
    ├─→ CAE Automation (5173/5000) (Phase 4)
    └─→ Monitoring (Grafana) (Phase 4)

All services: JWT 인증 적용
All APIs: 그룹/권한 기반 검증
All sessions: Redis 관리
All metrics: Prometheus 수집
```

### 성공 지표
- ✅ SAML SSO 로그인 성공률 > 99%
- ✅ JWT 토큰 발급/검증 성공률 > 99.9%
- ✅ VNC 세션 생성 성공률 > 95%
- ✅ VNC 세션 평균 시작 시간 < 30초
- ✅ API 응답 시간 P95 < 500ms
- ✅ 시스템 가용성 > 99.5%

---

**개발 시작 준비 완료!** 🚀

Phase 0부터 시작하세요: [Phase0_Prerequisites.md](Phase0_Prerequisites.md)
