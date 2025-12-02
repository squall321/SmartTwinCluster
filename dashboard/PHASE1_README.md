# Phase 1: Auth Portal

SAML SSO 인증 및 JWT 토큰 발급 시스템

## 🚀 빠른 시작

### 1. Phase 1 서비스 시작
```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard
./start_phase1.sh
```

시작되는 서비스:
- **SAML-IdP** (포트 7000): 테스트용 Identity Provider
- **Auth Backend** (포트 4430): Flask + SAML + JWT
- **Auth Frontend** (포트 4431): React + TypeScript

### 2. Phase 1 서비스 종료
```bash
./stop_phase1.sh
```

모든 Phase 1 프로세스를 종료합니다.

---

## 📂 디렉토리 구조

```
dashboard/
├── auth_portal_4430/          # Auth Backend (Flask)
│   ├── app.py                 # 메인 애플리케이션
│   ├── jwt_handler.py         # JWT 토큰 관리
│   ├── saml_handler.py        # SAML 인증 처리
│   ├── config/                # 설정 파일
│   ├── saml/                  # SAML 인증서 및 메타데이터
│   ├── logs/                  # 로그 파일
│   └── venv/                  # Python 가상 환경
│
├── auth_portal_4431/          # Auth Frontend (React)
│   ├── src/
│   │   ├── pages/
│   │   │   ├── LoginPage.tsx        # SSO 로그인 페이지
│   │   │   ├── CallbackPage.tsx     # SAML 콜백 처리
│   │   │   └── ServiceMenuPage.tsx  # 서비스 선택 화면
│   │   └── styles/                  # CSS 스타일
│   └── node_modules/
│
├── saml_idp_7000/             # SAML Identity Provider
│   ├── start_idp.sh           # IdP 시작 스크립트
│   ├── stop_idp.sh            # IdP 종료 스크립트
│   ├── config/                # IdP 설정 (users.json)
│   ├── certs/                 # IdP 인증서
│   └── logs/                  # IdP 로그
│
├── start_phase1.sh            # Phase 1 시작 스크립트
└── stop_phase1.sh             # Phase 1 종료 스크립트
```

---

## 🔑 API 엔드포인트

### Auth Backend (http://localhost:4430)

#### 인증 관련
- `GET  /auth/saml/login` - SAML SSO 로그인 시작
- `POST /auth/saml/acs` - SAML 응답 처리 (Assertion Consumer Service)
- `GET  /auth/saml/sls` - 로그아웃 (Single Logout Service)
- `GET  /auth/saml/metadata` - SP 메타데이터

#### JWT 토큰 관리
- `POST /auth/verify` - JWT 토큰 검증
- `POST /auth/refresh` - JWT 토큰 갱신
- `POST /auth/logout` - 로그아웃 (토큰 무효화)

#### 사용자 정보
- `GET /auth/user` - 현재 사용자 정보 조회
- `GET /auth/services` - 사용 가능한 서비스 목록

#### 개발/테스트
- `GET  /health` - 헬스 체크
- `POST /auth/test/login` - 테스트 로그인 (SAML 우회)

---

## 🧪 테스트

### 1. 헬스 체크
```bash
curl http://localhost:4430/health
```

### 2. 테스트 로그인 (SAML 우회)
```bash
curl -X POST http://localhost:4430/auth/test/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "admin",
    "email": "admin@hpc.local",
    "groups": ["HPC-Admins", "GPU-Users"]
  }'
```

### 3. JWT 토큰 검증
```bash
TOKEN="your_jwt_token_here"
curl -X POST http://localhost:4430/auth/verify \
  -H "Authorization: Bearer $TOKEN"
```

### 4. 사용자 정보 조회
```bash
curl http://localhost:4430/auth/user \
  -H "Authorization: Bearer $TOKEN"
```

### 5. 사용 가능 서비스 조회
```bash
curl http://localhost:4430/auth/services \
  -H "Authorization: Bearer $TOKEN"
```

---

## 👥 테스트 사용자

SAML-IdP에 설정된 테스트 사용자:

| Username | Email | Password | Groups | 접근 가능 서비스 |
|----------|-------|----------|--------|-----------------|
| admin | admin@hpc.local | admin123 | HPC-Admins | Dashboard, CAE, VNC |
| user01 | user01@hpc.local | password123 | HPC-Users, GPU-Users | Dashboard, VNC |
| user02 | user02@hpc.local | password123 | HPC-Users | Dashboard |
| gpu_user | gpu_user@hpc.local | password123 | GPU-Users | VNC |
| cae_user | cae_user@hpc.local | password123 | Automation-Users | CAE |

---

## 🔐 그룹 기반 권한

| 그룹 | 권한 | 접근 가능 서비스 |
|------|------|-----------------|
| HPC-Admins | dashboard, cae, vnc, admin | 모든 서비스 |
| HPC-Users | dashboard, vnc | Dashboard, VNC |
| GPU-Users | vnc | VNC |
| Automation-Users | cae | CAE |

---

## 📝 로그 파일

```bash
# Auth Backend 로그
tail -f auth_portal_4430/logs/backend.log

# Auth Frontend 로그
tail -f auth_portal_4430/logs/frontend.log

# SAML-IdP 로그
tail -f saml_idp_7000/logs/idp.log

# Auth Portal 애플리케이션 로그
tail -f auth_portal_4430/logs/auth_portal.log
```

---

## 🔧 트러블슈팅

### 서비스가 시작되지 않을 때

1. **Redis 확인**
```bash
redis-cli ping  # PONG 응답 확인
sudo systemctl status redis-server
```

2. **포트 충돌 확인**
```bash
# 4430, 4431, 7000 포트 사용 확인
lsof -i :4430
lsof -i :4431
lsof -i :7000
```

3. **프로세스 강제 종료**
```bash
pkill -9 -f auth_portal
pkill -9 -f saml-idp
```

### 로그 확인
```bash
# 최근 에러 확인
grep -i error auth_portal_4430/logs/*.log
```

---

## 🌐 웹 접속

- **Auth Frontend**: http://localhost:4431
- **Auth Backend API**: http://localhost:4430
- **SAML-IdP**: http://localhost:7000

---

## ✅ 검증 체크리스트

- [ ] Redis 실행 중 (`redis-cli ping`)
- [ ] SAML-IdP 실행 중 (http://localhost:7000)
- [ ] Auth Backend 실행 중 (http://localhost:4430/health)
- [ ] Auth Frontend 실행 중 (http://localhost:4431)
- [ ] JWT 토큰 발급 가능
- [ ] JWT 토큰 검증 가능
- [ ] 그룹별 서비스 필터링 동작
- [ ] Redis에 세션 저장 확인

---

## 📦 의존성

### Python (Backend)
- Flask 3.0.0
- python3-saml 1.15.0
- PyJWT 2.8.0
- redis 5.0.0
- flask-cors 4.0.0

### Node.js (Frontend)
- React 18
- TypeScript 5
- Vite 7
- react-router-dom 6

### System
- Redis 6.0+
- Node.js 18+
- Python 3.10+
- xmlsec1 (시스템 라이브러리)

---

## 🚧 알려진 이슈

### SAML-IdP 메타데이터 생성 실패
- `saml-idp` npm 패키지의 `/metadata` 엔드포인트가 500 에러 반환
- **해결 방법**: Auth Backend에서 IdP 설정을 하드코딩하여 우회
- **테스트**: `/auth/test/login` 엔드포인트 사용
- **실제 운영**: 실제 IdP(Keycloak, Azure AD 등) 사용 시 문제 없음

---

## 📚 다음 단계

Phase 1 완료 후:
- **Phase 2**: 기존 서비스 (Dashboard, CAE)에 JWT 인증 통합
- **Phase 3**: VNC 시스템 구현
- **Phase 4**: CAE 통합 및 모니터링
- **Phase 5**: 테스트 및 문서화

---

**작성일**: 2025-10-16
**버전**: Phase 1.0
