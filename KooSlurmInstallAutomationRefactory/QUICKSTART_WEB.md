# HPC 웹 서비스 빠른 시작 가이드

## 🚀 5분 안에 시작하기

### 사전 요구사항
- Ubuntu 20.04/22.04 LTS
- Python 3.8+
- Node.js 16+

---

## 📋 신규 서버 설치 (Development)

프로젝트 루트 디렉토리에서 **순서대로** 실행하세요:

```bash
# 1. 초기 설정
./collect_current_state.sh
./create_directory_structure.sh

# 2. Python 의존성 설치
pip3 install pyyaml jinja2

# 3. 환경 변수 생성
./generate_env_files.sh development

# 4. ONE-COMMAND 설치 + 자동 시작 (10-15분 소요)
./setup_web_services.sh development --auto-start

# 또는 수동으로 시작하려면:
# ./setup_web_services.sh development
# ./start.sh

# 5. 헬스 체크
./health_check.sh
```

**예상 결과**:
```
🔍 웹 서비스 헬스 체크
====================
✅ Dashboard Frontend             (3010) - HEALTHY
✅ Auth Portal Backend            (4430) - HEALTHY
✅ Auth Portal Frontend           (4431) - HEALTHY
...
✅ 전체: 11/11 서비스 정상
```

**브라우저 접속**: http://localhost:4431/

---

## 🎯 주요 명령어

### 서비스 제어

```bash
# 시작
./start.sh

# 중지
./stop.sh

# 상태 확인
./health_check.sh
```

### 환경 전환

```bash
# Development → Production
./web_services/scripts/reconfigure_web_services.sh production
./web_services/scripts/setup_nginx.sh production
./stop.sh && ./start.sh

# Production → Development
./web_services/scripts/reconfigure_web_services.sh development
./web_services/scripts/setup_nginx.sh development
./stop.sh && ./start.sh
```

### 롤백

```bash
# 최신 백업으로 복구
./web_services/scripts/rollback.sh --latest
./stop.sh && ./start.sh
```

---

## 📝 설정 파일

사용자가 **수정해야 하는 파일**은 단 하나입니다:

### web_services_config.yaml

프로덕션 배포 전 수정:

```yaml
environments:
  production:
    domain: "hpc.example.com"  # ← 실제 도메인으로 변경
    sso_enabled: true

services:
  auth_portal_backend:
    environment:
      production:
        SAML_IDP_METADATA_URL: "https://your-idp.com/metadata"  # ← IdP URL 변경
```

**나머지는 모두 자동 생성됩니다!**

---

## 🔧 프로덕션 배포

### 1. SSL 인증서 설정

**Let's Encrypt (권장)**:
```bash
./web_services/scripts/setup_letsencrypt.sh your-domain.com admin@example.com
```

**자체 서명 (테스트용)**:
```bash
sudo ./web_services/scripts/generate_self_signed_cert.sh your-domain.com
```

### 2. 프로덕션 환경으로 전환

```bash
# web_services_config.yaml 수정 후
python3 web_services/scripts/generate_env_files.py production
./web_services/scripts/setup_nginx.sh production
./stop.sh && ./start.sh
```

### 3. 방화벽 설정

```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

---

## 🌐 지원 서비스

| 서비스 | 포트 | 접속 경로 |
|--------|------|-----------|
| Auth Portal | 4431 | / |
| Dashboard | 3010 | /dashboard |
| CAE | 5173 | /cae |
| VNC | 8002 | /vnc |
| Prometheus | 9090 | /prometheus |

---

## ❓ 문제 해결

### 서비스가 시작되지 않음

```bash
# 로그 확인
tail -f dashboard/*/logs/app.log

# 포트 충돌 확인
./health_check.sh

# 의존성 재설치
./web_services/scripts/install_dependencies.sh
```

### Nginx 502 오류

```bash
# 백엔드 서비스 확인
./health_check.sh

# 서비스 재시작
./stop.sh && ./start.sh
```

### 환경 전환 후 문제

```bash
# 롤백
./web_services/scripts/rollback.sh --latest
./stop.sh && ./start.sh
```

---

## 📚 자세한 문서

- **배포**: [DEPLOYMENT.md](DEPLOYMENT.md) - 상세 배포 절차
- **운영**: [OPERATIONS.md](OPERATIONS.md) - 일상 운영 작업
- **문제 해결**: [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - 문제 해결 가이드
- **Phase 가이드**: PHASE0_GUIDE.md ~ PHASE5_GUIDE.md

---

## 💡 핵심 개념

### ONE-COMMAND 배포
단 한 번의 명령으로 모든 서비스 설치 및 시작:
```bash
# 완전 자동화: 설치 + 자동 시작
./setup_web_services.sh development --auto-start

# 또는 설치만 (수동 시작)
./setup_web_services.sh development
./start.sh
```

**자동화 내용**:
- ✅ 시스템 의존성 자동 설치 (Python3, Node.js, Redis 등)
- ✅ Python venv 자동 생성 및 패키지 설치
- ✅ Node.js node_modules 자동 설치
- ✅ .env 파일 자동 생성
- ✅ 서비스 자동 시작 (--auto-start 옵션)

### 환경별 자동 설정
Development와 Production 환경 자동 전환:
- Development: HTTP, SSO 비활성화, localhost
- Production: HTTPS, SSO 활성화, 실제 도메인

### 최소 코드 수정
기존 서비스 코드는 **거의 수정하지 않음** (5개 파일만)

### 자동 롤백
설정 변경 실패 시 10초만에 이전 상태로 복구

---

## 📊 성능

| 작업 | 수동 | 자동 | 절감 |
|------|------|------|------|
| 신규 설치 | 2-3시간 | 10-15분 | 90% |
| 환경 전환 | 30-60분 | 1-2분 | 95% |
| 롤백 | 10-20분 | 10초 | 99% |

---

**작성일**: 2025-10-20
**버전**: 1.0
**문의**: 시스템 관리자
