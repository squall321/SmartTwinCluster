# Phase 1 실행 가이드: 구성 파일 및 문서 생성

## 📋 개요

**목표**: 전체 웹 서비스 자동화를 위한 핵심 구성 파일 및 템플릿 생성
**예상 소요 시간**: 3-4시간
**의존성**: Phase 0 완료 필수

---

## ✅ 사전 확인

Phase 1 시작 전 확인사항:

```bash
# Phase 0 완료 여부 확인
./verify_phase0.sh

# 디렉토리 구조 확인
ls -la web_services/
```

**Phase 0가 완료되지 않았다면 Phase 1을 진행하지 마세요!**

---

## 📅 타임라인

| 단계 | 작업 | 예상 시간 |
|------|------|-----------|
| 1 | 마스터 구성 파일 생성 | 60분 |
| 2 | 포트 매핑 문서 작성 | 30분 |
| 3 | 환경 변수 템플릿 생성 | 90분 |
| 4 | README 업데이트 | 20분 |
| 5 | 검증 | 20분 |

**총 예상 시간: 3시간 20분**

---

## 🎯 Phase 1 상세 실행 단계

### 1️⃣ 마스터 구성 파일 생성 (60분)

#### 목표
모든 서비스의 중앙 구성을 관리할 `web_services_config.yaml` 생성

#### 실행
```bash
# 구성 파일 생성 (아래 파일 내용 참조)
nano web_services_config.yaml
```

**파일 위치**: `/home/koopark/claude/KooSlurmInstallAutomationRefactory/web_services_config.yaml`

**내용**:
- 환경 정의 (development, production)
- 서비스별 포트, 경로, 의존성 정보
- SSO 설정 (SAML IdP URL 등)
- Nginx 설정 (도메인, SSL 등)
- 시스템 설정 (로그 경로, 백업 정책 등)

> **Note**: 파일 내용은 별도로 생성됩니다 (`web_services_config.yaml`)

#### 검증
```bash
# YAML 문법 검증
python3 -c "import yaml; yaml.safe_load(open('web_services_config.yaml'))"

# 파일 존재 확인
ls -lh web_services_config.yaml
```

---

### 2️⃣ 포트 매핑 문서 작성 (30분)

#### 목표
모든 서비스의 포트 할당을 명확히 문서화

#### 실행
```bash
# 포트 매핑 파일 생성
nano web_services/docs/port_mapping.yaml
```

**파일 위치**: `web_services/docs/port_mapping.yaml`

**포함 정보**:
- 각 서비스별 포트 번호
- 프로토콜 (HTTP/HTTPS/WebSocket)
- 외부 노출 여부
- Nginx reverse proxy 경로 매핑
- 방화벽 규칙 참조

#### 검증
```bash
# 현재 사용 중인 포트와 비교
sudo lsof -i -P -n | grep LISTEN | grep -E ":(3010|4430|4431|5000|5001|5010|5011|5173|8002|9090|9100)"

# YAML 문법 검증
python3 -c "import yaml; yaml.safe_load(open('web_services/docs/port_mapping.yaml'))"
```

---

### 3️⃣ 환경 변수 템플릿 생성 (90분)

#### 목표
각 서비스별 `.env` 템플릿을 Jinja2 형식으로 생성

#### 3-1. Auth Portal Backend (4430) 템플릿

```bash
nano web_services/templates/env/auth_portal_4430.env.j2
```

**주요 변수**:
- `FLASK_ENV`, `FLASK_DEBUG`
- `JWT_SECRET_KEY`, `JWT_ALGORITHM`, `JWT_EXPIRATION_HOURS`
- `REDIS_HOST`, `REDIS_PORT`
- `SAML_IDP_METADATA_URL`, `SAML_SP_ENTITY_ID`
- `SAML_ACS_URL`, `SAML_SLS_URL`
- `DASHBOARD_URL`, `CAE_URL`, `VNC_URL`

#### 3-2. Auth Portal Frontend (4431) 템플릿

```bash
nano web_services/templates/env/auth_portal_4431.env.j2
```

**주요 변수**:
- `VITE_API_URL` (백엔드 4430 URL)
- `VITE_ENVIRONMENT` (development/production)
- `VITE_SSO_ENABLED` (true/false)

#### 3-3. Dashboard Backend (5010) 템플릿

```bash
nano web_services/templates/env/backend_5010.env.j2
```

**주요 변수**:
- `FLASK_ENV`, `FLASK_DEBUG`
- `JWT_SECRET_KEY` (Auth Portal과 동일)
- `SLURM_CONTROL_NODE`
- `PROMETHEUS_URL`
- `WEBSOCKET_URL` (5011)

#### 3-4. Dashboard Frontend (3010) 템플릿

```bash
nano web_services/templates/env/frontend_3010.env.j2
```

**주요 변수**:
- `VITE_API_URL` (백엔드 5010 URL)
- `VITE_WS_URL` (웹소켓 5011 URL)
- `VITE_AUTH_URL` (Auth Portal 4430 URL)

#### 3-5. CAE Backend (5000) 템플릿

```bash
nano web_services/templates/env/cae_backend_5000.env.j2
```

#### 3-6. CAE Automation (5001) 템플릿

```bash
nano web_services/templates/env/cae_automation_5001.env.j2
```

#### 3-7. CAE Frontend (5173) 템플릿

```bash
nano web_services/templates/env/cae_frontend_5173.env.j2
```

#### 3-8. VNC Service (8002) 템플릿

```bash
nano web_services/templates/env/vnc_service_8002.env.j2
```

**주요 변수**:
- `VITE_API_URL` (Dashboard Backend 5010)
- `VITE_AUTH_URL` (Auth Portal 4430)
- `VITE_VNC_PROXY_URL`

#### 검증
```bash
# 모든 템플릿 파일 생성 확인
ls -la web_services/templates/env/

# 예상 파일 수: 8개
# auth_portal_4430.env.j2
# auth_portal_4431.env.j2
# backend_5010.env.j2
# frontend_3010.env.j2
# cae_backend_5000.env.j2
# cae_automation_5001.env.j2
# cae_frontend_5173.env.j2
# vnc_service_8002.env.j2
```

---

### 4️⃣ README 업데이트 (20분)

#### 목표
Phase 1 완료 내용을 문서화

```bash
nano web_services/docs/README.md
```

**추가 내용**:
- Phase 1 완료 사항
- 구성 파일 설명
- 환경 변수 템플릿 사용법
- 다음 Phase 준비사항

---

### 5️⃣ 검증 (20분)

#### 자동 검증 스크립트 실행

```bash
# Phase 1 검증
./verify_phase1.sh
```

#### 수동 검증 체크리스트

- [ ] `web_services_config.yaml` 존재 및 YAML 문법 정상
- [ ] `web_services/docs/port_mapping.yaml` 존재 및 11개 포트 정의
- [ ] 환경 변수 템플릿 8개 파일 생성 확인
- [ ] 모든 템플릿에 Jinja2 변수 문법 사용 ({{ variable }})
- [ ] README.md 업데이트 완료

---

## 🎓 Phase 1에서 생성된 파일 목록

### 신규 생성 파일 (10개)

```
/home/koopark/claude/KooSlurmInstallAutomationRefactory/
├── web_services_config.yaml                              # 마스터 구성 파일
├── web_services/
│   ├── docs/
│   │   ├── port_mapping.yaml                             # 포트 매핑 문서
│   │   └── README.md (업데이트)                          # 문서 설명
│   └── templates/
│       └── env/
│           ├── auth_portal_4430.env.j2                   # Auth Backend 템플릿
│           ├── auth_portal_4431.env.j2                   # Auth Frontend 템플릿
│           ├── backend_5010.env.j2                       # Dashboard Backend 템플릿
│           ├── frontend_3010.env.j2                      # Dashboard Frontend 템플릿
│           ├── cae_backend_5000.env.j2                   # CAE Backend 템플릿
│           ├── cae_automation_5001.env.j2                # CAE Automation 템플릿
│           ├── cae_frontend_5173.env.j2                  # CAE Frontend 템플릿
│           └── vnc_service_8002.env.j2                   # VNC Service 템플릿
└── verify_phase1.sh                                       # Phase 1 검증 스크립트
```

---

## ⚠️ 주의사항

### ❌ 하지 말아야 할 것

1. **기존 서비스 파일 수정 금지**
   - 이 Phase에서는 템플릿만 생성
   - 실제 코드 수정은 Phase 2에서 진행

2. **현재 실행 중인 서비스 중단 금지**
   - 이 Phase는 파일 생성만 수행
   - 서비스 재시작 불필요

3. **절대 경로 하드코딩 금지**
   - 템플릿에서는 반드시 Jinja2 변수 사용
   - 예: `http://localhost:4430` ❌
   - 예: `{{ auth_backend_url }}` ✅

### ✅ 반드시 해야 할 것

1. **YAML 문법 검증**
   ```bash
   python3 -c "import yaml; yaml.safe_load(open('web_services_config.yaml'))"
   ```

2. **포트 충돌 확인**
   ```bash
   sudo lsof -i -P -n | grep LISTEN
   ```

3. **Jinja2 변수 일관성 확인**
   - 모든 템플릿에서 동일한 변수명 사용
   - `web_services_config.yaml`에 정의된 변수만 사용

---

## 🔧 트러블슈팅

### 문제 1: YAML 파싱 에러

**증상**:
```
yaml.scanner.ScannerError: mapping values are not allowed here
```

**해결**:
- 들여쓰기 확인 (공백 2칸 일관성)
- 콜론(`:`) 뒤에 공백 필수
- 문자열에 특수문자 있으면 따옴표로 감싸기

### 문제 2: 템플릿 변수 미정의

**증상**:
```
jinja2.exceptions.UndefinedError: 'variable_name' is undefined
```

**해결**:
- `web_services_config.yaml`에 해당 변수 정의 확인
- 변수명 오타 확인 (대소문자 구분)

### 문제 3: 포트 매핑 문서 불일치

**해결**:
```bash
# 실제 사용 중인 포트 확인
sudo lsof -i -P -n | grep LISTEN | grep -E ":(3010|4430|4431|5000|5001|5010|5011|5173|8002|9090|9100)"

# CURRENT_STATE.md와 비교
diff <(grep "Port" CURRENT_STATE.md) <(grep "port" web_services/docs/port_mapping.yaml)
```

---

## 📈 진행 상황 체크

### Phase 1 완료 기준

- [x] Phase 0 완료 확인
- [ ] `web_services_config.yaml` 생성 및 검증
- [ ] `port_mapping.yaml` 생성 및 검증
- [ ] 8개 환경 변수 템플릿 생성
- [ ] README.md 업데이트
- [ ] `verify_phase1.sh` 통과

### 완료 후 다음 단계

```bash
# Phase 1 완료 확인
./verify_phase1.sh

# 성공 시 출력 예상:
# ✅✅✅ Phase 1 완료!
#
# 📋 다음 단계:
#    cat PHASE2_GUIDE.md
```

---

## 📚 참고 자료

### Jinja2 템플릿 문법

```jinja2
# 변수 치환
{{ variable_name }}

# 조건문
{% if environment == 'production' %}
FLASK_DEBUG=False
{% else %}
FLASK_DEBUG=True
{% endif %}

# 반복문
{% for service in services %}
{{ service.name }}={{ service.url }}
{% endfor %}
```

### YAML 문법 기본

```yaml
# 키-값 쌍
key: value

# 리스트
services:
  - auth_portal
  - dashboard
  - cae

# 중첩 객체
auth_portal:
  backend:
    port: 4430
  frontend:
    port: 4431

# 다중 라인 문자열
description: |
  This is a
  multi-line
  string
```

---

## ⏭️ Phase 2 준비사항

Phase 1 완료 후 Phase 2에서는:

1. **기존 코드 수정** (5개 파일)
   - `dashboard/auth_portal_4430/config/config.py`
   - `dashboard/auth_portal_4430/saml_handler.py`
   - `dashboard/auth_portal_4431/src/pages/ServiceMenuPage.tsx`
   - `dashboard/auth_portal_4431/src/pages/VNCPage.tsx`
   - `dashboard/vnc_service_8002/src/App.tsx`

2. **Python 스크립트 생성**
   - `generate_env_files.py` (템플릿 → .env 파일 생성)

3. **Git 작업** (사용자가 직접 수행)
   - Phase 1 변경사항 커밋
   - Phase 2 시작 전 백업

---

## 💬 질문 및 지원

Phase 1 진행 중 문제 발생 시:

1. `verify_phase1.sh` 실행하여 누락 확인
2. `CURRENT_STATE.md` 참조하여 현재 상태 비교
3. 트러블슈팅 섹션 참조

**예상 소요 시간: 3-4시간**
**난이도: 중급 (YAML, Jinja2 기본 지식 필요)**
