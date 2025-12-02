# HPC 클러스터 인증 포털 사용 가이드

SSO 인증 기반 HPC 클러스터 관리 시스템 사용법

---

## 📚 목차

1. [시스템 개요](#시스템-개요)
2. [빠른 시작](#빠른-시작)
3. [사용자 로그인 흐름](#사용자-로그인-흐름)
4. [서비스 접근 권한](#서비스-접근-권한)
5. [Dashboard 사용법](#dashboard-사용법)
6. [문제 해결](#문제-해결)
7. [관리자 가이드](#관리자-가이드)

---

## 🎯 시스템 개요

### 전체 아키텍처

```
┌─────────────────┐
│  사용자 브라우저  │
└────────┬────────┘
         │
         ├─────────────────────────────────────────┐
         │                                         │
         v                                         v
┌────────────────────┐                  ┌─────────────────────┐
│   Auth Portal      │                  │   Services (인증됨) │
│  (포트 4431)       │                  │                     │
│  - SSO 로그인      │──JWT Token──────→│  • Dashboard (3010) │
│  - 서비스 메뉴     │                  │  • CAE Portal       │
│  - 권한 관리       │                  │  • VNC Sessions     │
└────────────────────┘                  └─────────────────────┘
         │
         v
┌────────────────────┐
│   Auth Backend     │
│   (포트 4430)      │
│  - JWT 발급        │
│  - 토큰 검증       │
│  - SAML 처리       │
└────────────────────┘
```

### 주요 컴포넌트

| 컴포넌트 | 포트 | 역할 |
|---------|------|------|
| **Auth Portal Frontend** | 4431 | SSO 로그인 UI, 서비스 선택 메뉴 |
| **Auth Portal Backend** | 4430 | JWT 발급, 토큰 검증, SAML 인증 |
| **Dashboard Frontend** | 3010 | Slurm 작업 관리 UI |
| **Dashboard Backend** | 5010 | Slurm API (JWT 인증 필요) |
| **Redis** | 6379 | 세션 저장소 |
| **Nginx** | 443 | HTTPS 리버스 프록시 |

---

## 🚀 빠른 시작

### 1. 시스템 시작

```bash
# 전체 디렉토리로 이동
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard

# Phase 0 검증 (인프라 확인)
./validate_phase0.sh

# Phase 1 시작 (Auth Portal)
./start_phase1.sh

# 상태 확인
# - Auth Portal Frontend: http://localhost:4431
# - Auth Portal Backend: http://localhost:4430/health
# - Dashboard Backend: http://localhost:5010/api/health
```

### 2. 첫 로그인

1. 브라우저에서 **http://localhost:4431** 접속
2. "Login with SSO" 버튼 클릭
3. SAML IdP 로그인 화면에서 인증 (개발 환경에서는 `/auth/test/login` 사용)
4. 로그인 성공 시 **서비스 메뉴** 페이지로 이동
5. 접근 가능한 서비스 목록 확인 및 선택

### 3. Dashboard 접근

서비스 메뉴에서 "HPC Dashboard" 선택하면:
- JWT 토큰이 URL 파라미터로 전달됨 (`?token=...`)
- Dashboard가 토큰을 검증하고 로그인 처리
- 작업 제출, 모니터링 등 사용 가능

---

## 🔐 사용자 로그인 흐름

### 전체 인증 플로우

```
[1] 사용자 → Auth Portal Frontend (http://localhost:4431)
     │
     └─ "Login with SSO" 클릭
     │
[2] Auth Portal → SAML IdP 리다이렉트
     │
     └─ IdP 로그인 페이지에서 인증
     │
[3] IdP → Auth Portal Backend (/auth/saml/acs)
     │
     └─ SAML Response 검증
     │
[4] Auth Backend → JWT 토큰 생성
     │
     └─ Redis에 세션 저장 (8시간 유효)
     │
[5] Auth Frontend → 서비스 메뉴 페이지
     │
     └─ 사용자 권한에 따른 서비스 목록 표시
     │
[6] 사용자 → 서비스 선택 (예: Dashboard)
     │
     └─ Dashboard URL + JWT 토큰으로 리다이렉트
     │
[7] Dashboard → JWT 검증 후 접근 허용
```

### 토큰 만료 처리

- JWT 유효기간: **8시간**
- 만료 시: Dashboard에서 자동으로 Auth Portal로 리다이렉트
- 재로그인 후 작업 계속 가능

---

## 🎫 서비스 접근 권한

### 사용자 그룹별 권한

| 그룹 | Dashboard | CAE Portal | VNC | Admin |
|------|-----------|-----------|-----|-------|
| **HPC-Admins** | ✅ | ✅ | ✅ | ✅ |
| **HPC-Users** | ✅ | ❌ | ✅ | ❌ |
| **GPU-Users** | ❌ | ❌ | ✅ | ❌ |
| **Automation-Users** | ❌ | ✅ | ❌ | ❌ |

### 권한 확인 방법

서비스 메뉴 페이지에서:
- ✅ **접근 가능**: 서비스 카드가 활성화되어 클릭 가능
- ❌ **접근 불가**: 서비스 카드가 표시되지 않음

---

## 💻 Dashboard 사용법

### Dashboard 기능

Dashboard(포트 3010)에서 사용 가능한 기능:

#### 1. 작업 제출 (Job Submission)
```
필요 권한: dashboard
사용 가능 그룹: HPC-Admins, HPC-Users

작업 제출 양식:
- Job Name: 작업 이름
- Partition: 파티션 선택 (group1, group2, ...)
- Nodes: 노드 수
- CPUs: CPU 코어 수
- Memory: 메모리 크기
- Time: 실행 시간 제한
- Script: 실행할 스크립트
```

#### 2. 작업 관리
```
• 작업 목록 조회 (권한 불필요)
• 작업 취소 (dashboard 권한)
• 작업 홀드 (dashboard 권한)
• 작업 릴리즈 (dashboard 권한)
```

#### 3. 클러스터 모니터링
```
• 실시간 노드 상태
• CPU/GPU/메모리 사용률
• 파티션 상태
• 큐 현황
```

#### 4. 클러스터 설정 (Admin 전용)
```
필요 권한: dashboard + admin
사용 가능 그룹: HPC-Admins만

• QoS 설정
• 파티션 관리
• 노드 그룹 구성
```

### JWT 토큰 관리

Dashboard 내부에서 JWT 토큰은:
- **localStorage**에 자동 저장됨
- 모든 API 요청에 `Authorization: Bearer <token>` 헤더로 포함
- 만료 시 401 에러 발생 → Auth Portal로 자동 리다이렉트

---

## 🔧 문제 해결

### 문제 1: "No authorization header" 에러

**증상**: Dashboard API 호출 시 401 에러

**원인**:
- JWT 토큰이 localStorage에 없음
- 토큰이 만료됨
- 브라우저가 토큰을 전송하지 않음

**해결책**:
```bash
# 1. Auth Portal에서 재로그인
http://localhost:4431

# 2. 브라우저 콘솔에서 토큰 확인
localStorage.getItem('jwt_token')

# 3. 토큰이 없으면 서비스 메뉴에서 Dashboard 재선택
```

### 문제 2: "Forbidden (403)" 에러

**증상**: 특정 API 호출 시 403 에러

**원인**: 사용자 그룹에 필요한 권한이 없음

**해결책**:
```bash
# 1. 현재 사용자 권한 확인
curl http://localhost:4430/auth/user \
  -H "Authorization: Bearer <your_token>"

# 2. 필요한 권한 확인 (예: 작업 제출은 'dashboard' 권한 필요)

# 3. 관리자에게 그룹 변경 요청
```

### 문제 3: 토큰 만료

**증상**: 8시간 후 모든 API 호출이 실패

**원인**: JWT 토큰의 기본 유효기간 8시간 경과

**해결책**:
```bash
# Auth Portal에서 재로그인
# 새 토큰이 자동으로 발급됨
```

### 문제 4: 서비스가 시작되지 않음

**증상**: start_phase1.sh 실행 시 에러

**해결책**:
```bash
# Phase 0 인프라 확인
./validate_phase0.sh

# 결과:
# - Redis: PASS 확인
# - Nginx: PASS 확인

# 서비스 재시작
./stop_phase1.sh
./start_phase1.sh

# 로그 확인
tail -f /tmp/phase1_*.log
```

---

## 👨‍💼 관리자 가이드

### 사용자 그룹 관리

현재 사용자의 그룹은 SAML IdP에서 관리됩니다.

#### 개발/테스트 환경에서 테스트 사용자 생성

```bash
# HPC-Admins 권한으로 테스트
curl -X POST http://localhost:4430/auth/test/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "test_admin",
    "email": "admin@hpc.local",
    "groups": ["HPC-Admins"]
  }'

# HPC-Users 권한으로 테스트
curl -X POST http://localhost:4430/auth/test/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "test_user",
    "email": "user@hpc.local",
    "groups": ["HPC-Users"]
  }'

# GPU-Users 권한으로 테스트
curl -X POST http://localhost:4430/auth/test/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "gpu_user",
    "email": "gpu@hpc.local",
    "groups": ["GPU-Users"]
  }'
```

### JWT Secret Key 변경

**중요**: Production 환경에서는 반드시 JWT_SECRET_KEY를 변경하세요!

```bash
# 1. 랜덤 Secret Key 생성
openssl rand -hex 32

# 2. Auth Portal 설정
vim auth_portal_4430/.env
# JWT_SECRET_KEY=<new_secret_key>

# 3. Dashboard Backend 설정
vim backend_5010/.env
# JWT_SECRET_KEY=<new_secret_key>  (같은 값!)

# 4. 서비스 재시작
./stop_phase1.sh
./start_phase1.sh
```

### 세션 관리

Redis에 저장된 세션 확인:

```bash
# Redis CLI 접속
redis-cli

# 모든 JWT 세션 확인
KEYS jwt:*

# 특정 사용자 세션 확인
GET jwt:admin

# 사용자 강제 로그아웃 (세션 삭제)
DEL jwt:admin

# 모든 세션 삭제 (모든 사용자 로그아웃)
FLUSHDB
```

### 로그 확인

```bash
# Auth Portal Backend 로그
tail -f /tmp/phase1_auth_backend.log

# Auth Portal Frontend 로그
tail -f /tmp/phase1_auth_frontend.log

# SAML IdP 로그
tail -f /tmp/phase1_saml_idp.log

# Dashboard Backend 로그 (실시간)
# backend_5010에서 직접 실행 시 터미널에 출력됨
```

### 권한 설정 커스터마이징

그룹별 권한은 Auth Portal Backend 설정에서 변경 가능합니다:

```bash
# 설정 파일 수정
vim auth_portal_4430/config/config.py
```

```python
# 그룹별 권한 매핑
GROUP_PERMISSIONS = {
    'HPC-Admins': ['dashboard', 'cae', 'vnc', 'admin'],
    'HPC-Users': ['dashboard', 'vnc'],
    'GPU-Users': ['vnc'],
    'Automation-Users': ['cae'],

    # 새 그룹 추가 예시
    'Data-Scientists': ['dashboard', 'cae'],
}
```

수정 후 Auth Portal Backend 재시작:
```bash
# Backend만 재시작
pkill -f "auth_portal_4430.*python"
cd auth_portal_4430
source venv/bin/activate
python3 app.py &
```

---

## 📊 시스템 상태 확인

### Health Check 엔드포인트

```bash
# Auth Portal Backend
curl http://localhost:4430/health

# Dashboard Backend
curl http://localhost:5010/api/health

# Redis
redis-cli PING
```

### 전체 시스템 검증

```bash
# Phase 0 검증 (인프라)
./validate_phase0.sh

# 결과 예시:
# [PASS] Redis is running
# [PASS] Nginx is running
# [PASS] Apptainer sandbox ready
# ...
```

---

## 🔗 관련 문서

- [Phase 0 설치 가이드](setup_phase0_all.sh)
- [Phase 1 개발 문서](PHASE1_README.md)
- [Phase 2 JWT 통합](PHASE2_README.md)
- [배포 가이드](DEPLOYMENT.md)

---

## 📞 지원

문제가 발생하거나 질문이 있으시면:

1. **로그 확인**: `/tmp/phase1_*.log` 파일 검토
2. **Health Check**: 각 서비스의 헬스체크 엔드포인트 확인
3. **Phase 0 검증**: `./validate_phase0.sh` 실행하여 인프라 상태 확인

---

**작성일**: 2025-10-16
**버전**: v1.0 (Phase 0-2 완료)
