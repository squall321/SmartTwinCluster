# Phase 2 실행 가이드: 기존 코드 최소 수정

## 📋 개요

**목표**: 하드코딩된 localhost URL을 환경 변수로 변경 (5개 파일만 수정)
**예상 소요 시간**: 2-3시간
**의존성**: Phase 1 완료 필수

---

## ✅ 사전 확인

Phase 2 시작 전 확인사항:

```bash
# Phase 1 완료 여부 확인
./verify_phase1.sh

# 백업 (사용자가 직접 수행)
# Git commit 또는 파일 복사 등
```

**⚠️ 중요**: Phase 2에서는 **기존 코드를 수정**합니다. 반드시 백업하세요!

---

## 📅 타임라인

| 단계 | 작업 | 예상 시간 |
|------|------|-----------|
| 1 | Python 패키지 설치 | 10분 |
| 2 | generate_env_files.py 스크립트 작성 | 40분 |
| 3 | Python 백엔드 코드 수정 (2개 파일) | 30분 |
| 4 | TypeScript 프론트엔드 코드 수정 (3개 파일) | 40분 |
| 5 | 환경 변수 파일 생성 테스트 | 20분 |
| 6 | 검증 | 20분 |

**총 예상 시간: 2시간 40분**

---

## 🎯 Phase 2 상세 실행 단계

### 1️⃣ Python 패키지 설치 (10분)

#### 필수 패키지 설치

```bash
# PyYAML과 Jinja2 설치
pip3 install pyyaml jinja2

# 또는
python3 -m pip install pyyaml jinja2

# 설치 확인
python3 -c "import yaml; import jinja2; print('✅ 패키지 설치 완료')"
```

---

### 2️⃣ generate_env_files.py 스크립트 작성 (40분)

#### 목표
`web_services_config.yaml`과 Jinja2 템플릿을 사용하여 `.env` 파일 자동 생성

#### 실행

```bash
# 스크립트 생성
nano web_services/scripts/generate_env_files.py
```

**파일 위치**: `web_services/scripts/generate_env_files.py`

**기능**:
- 명령줄 인자로 환경 선택 (development/production)
- `web_services_config.yaml` 파싱
- 각 서비스별로 Jinja2 템플릿 렌더링
- 각 서비스 디렉토리에 `.env` 파일 생성
- 생성된 파일 목록 출력

**사용 예시**:
```bash
# 개발 환경 .env 파일 생성
python3 web_services/scripts/generate_env_files.py development

# 프로덕션 환경 .env 파일 생성
python3 web_services/scripts/generate_env_files.py production
```

**생성될 .env 파일 위치**:
```
dashboard/auth_portal_4430/.env
dashboard/auth_portal_4431/.env
dashboard/backend_5010/.env
dashboard/frontend_3010/.env
dashboard/kooCAEWebServer_5000/.env
dashboard/kooCAEWebAutomationServer_5001/.env
dashboard/kooCAEWeb_5173/.env
dashboard/vnc_service_8002/.env
```

> **Note**: 스크립트 전체 코드는 아래 섹션 참조

---

### 3️⃣ Python 백엔드 코드 수정 (30분)

#### 3-1. Auth Portal Backend - config.py 수정

**파일**: `dashboard/auth_portal_4430/config/config.py`

**수정 내용**:
```python
# 기존 코드에서 os.getenv()를 사용하는 부분 확인
# 이미 환경 변수를 사용하고 있으므로 추가 변경 최소화

# 확인이 필요한 변수들:
# - DASHBOARD_URL
# - CAE_URL
# - VNC_URL

# .env 파일에서 읽어오도록 확인
```

**검증**:
```bash
# config.py에서 환경 변수 사용 확인
grep -n "os.getenv" dashboard/auth_portal_4430/config/config.py
```

#### 3-2. Auth Portal Backend - saml_handler.py 수정

**파일**: `dashboard/auth_portal_4430/saml_handler.py`

**수정 대상**:
- Line 113: `http://localhost:4431/auth/callback` → 환경 변수 사용

**수정 전**:
```python
# 하드코딩된 URL
callback_url = "http://localhost:4431/auth/callback"
```

**수정 후**:
```python
# 환경 변수 사용
from config.config import Config
callback_url = f"{os.getenv('AUTH_FRONTEND_URL', 'http://localhost:4431')}/auth/callback"
```

**검증**:
```bash
# localhost 하드코딩 확인
grep -n "localhost:4431" dashboard/auth_portal_4430/saml_handler.py
```

---

### 4️⃣ TypeScript 프론트엔드 코드 수정 (40분)

#### 4-1. Auth Portal Frontend - ServiceMenuPage.tsx

**파일**: `dashboard/auth_portal_4431/src/pages/ServiceMenuPage.tsx`

**수정 대상**:
- Line 87: `window.location.href = ${service.url}?token=${token}`

**문제**: 절대 URL과 상대 URL 처리 필요

**수정 전**:
```typescript
window.location.href = `${service.url}?token=${token}`;
```

**수정 후**:
```typescript
// 절대 URL이면 그대로, 상대 URL이면 도메인 추가
const url = service.url.startsWith('http')
  ? service.url
  : `${window.location.origin}${service.url}`;
window.location.href = `${url}?token=${token}`;
```

**검증**:
```bash
# 수정 확인
grep -A 2 "window.location.href" dashboard/auth_portal_4431/src/pages/ServiceMenuPage.tsx
```

#### 4-2. Auth Portal Frontend - VNCPage.tsx

**파일**: `dashboard/auth_portal_4431/src/pages/VNCPage.tsx`

**수정 내용**:
- 환경 변수 사용 확인 (`import.meta.env.VITE_API_URL`)
- 이미 환경 변수를 사용 중이면 추가 수정 불필요

**검증**:
```bash
# 환경 변수 사용 확인
grep -n "import.meta.env" dashboard/auth_portal_4431/src/pages/VNCPage.tsx
grep -n "localhost" dashboard/auth_portal_4431/src/pages/VNCPage.tsx
```

#### 4-3. VNC Service - App.tsx

**파일**: `dashboard/vnc_service_8002/src/App.tsx`

**수정 대상**:
- Line 377: Footer link `http://localhost:4431` → 상대 경로

**수정 전**:
```typescript
<a href="http://localhost:4431">Back to Home</a>
```

**수정 후**:
```typescript
<a href="/">Back to Home</a>
```

**검증**:
```bash
# localhost 하드코딩 확인
grep -n "localhost:4431" dashboard/vnc_service_8002/src/App.tsx
```

---

### 5️⃣ 환경 변수 파일 생성 테스트 (20분)

#### 개발 환경 .env 파일 생성

```bash
# generate_env_files.py 실행
python3 web_services/scripts/generate_env_files.py development

# 생성 확인
ls -la dashboard/auth_portal_4430/.env
ls -la dashboard/auth_portal_4431/.env
ls -la dashboard/backend_5010/.env
ls -la dashboard/frontend_3010/.env
ls -la dashboard/kooCAEWebServer_5000/.env
ls -la dashboard/kooCAEWebAutomationServer_5001/.env
ls -la dashboard/kooCAEWeb_5173/.env
ls -la dashboard/vnc_service_8002/.env
```

#### .env 파일 내용 확인

```bash
# Auth Portal Backend .env 확인
cat dashboard/auth_portal_4430/.env

# 예상 출력:
# FLASK_ENV=development
# FLASK_DEBUG=True
# JWT_SECRET_KEY=dev-jwt-secret-please-change
# DASHBOARD_URL=http://localhost:3010
# ...
```

#### 프로덕션 환경 테스트 (dry-run)

```bash
# 프로덕션 설정으로 생성 (테스트)
python3 web_services/scripts/generate_env_files.py production

# .env 파일 확인
cat dashboard/auth_portal_4430/.env | grep DASHBOARD_URL

# 예상 출력:
# DASHBOARD_URL=https://hpc.example.com/dashboard
```

---

### 6️⃣ 검증 (20분)

#### 자동 검증

```bash
# Phase 2 검증 스크립트 실행
./verify_phase2.sh
```

#### 수동 검증 체크리스트

- [ ] `generate_env_files.py` 스크립트 생성 완료
- [ ] Python 패키지 설치 (pyyaml, jinja2)
- [ ] 5개 파일 수정 완료:
  - [ ] `dashboard/auth_portal_4430/config/config.py` (또는 확인)
  - [ ] `dashboard/auth_portal_4430/saml_handler.py`
  - [ ] `dashboard/auth_portal_4431/src/pages/ServiceMenuPage.tsx`
  - [ ] `dashboard/auth_portal_4431/src/pages/VNCPage.tsx` (또는 확인)
  - [ ] `dashboard/vnc_service_8002/src/App.tsx`
- [ ] 8개 서비스의 `.env` 파일 생성 성공
- [ ] `.env` 파일에 올바른 값 포함 확인
- [ ] localhost 하드코딩 제거 확인

---

## 📝 generate_env_files.py 전체 코드

```python
#!/usr/bin/env python3
"""
웹 서비스 환경 변수 파일 생성기

사용법:
    python3 generate_env_files.py development
    python3 generate_env_files.py production
"""

import os
import sys
import yaml
from jinja2 import Template
from pathlib import Path

# 프로젝트 루트 디렉토리
PROJECT_ROOT = Path(__file__).parent.parent.parent
CONFIG_FILE = PROJECT_ROOT / "web_services_config.yaml"
TEMPLATE_DIR = PROJECT_ROOT / "web_services" / "templates" / "env"

# 서비스별 디렉토리 및 템플릿 매핑
SERVICE_MAPPING = {
    "auth_portal_backend": {
        "dir": "dashboard/auth_portal_4430",
        "template": "auth_portal_4430.env.j2"
    },
    "auth_portal_frontend": {
        "dir": "dashboard/auth_portal_4431",
        "template": "auth_portal_4431.env.j2"
    },
    "dashboard_backend": {
        "dir": "dashboard/backend_5010",
        "template": "backend_5010.env.j2"
    },
    "dashboard_frontend": {
        "dir": "dashboard/frontend_3010",
        "template": "frontend_3010.env.j2"
    },
    "cae_backend": {
        "dir": "dashboard/kooCAEWebServer_5000",
        "template": "cae_backend_5000.env.j2"
    },
    "cae_automation": {
        "dir": "dashboard/kooCAEWebAutomationServer_5001",
        "template": "cae_automation_5001.env.j2"
    },
    "cae_frontend": {
        "dir": "dashboard/kooCAEWeb_5173",
        "template": "cae_frontend_5173.env.j2"
    },
    "vnc_service": {
        "dir": "dashboard/vnc_service_8002",
        "template": "vnc_service_8002.env.j2"
    }
}


def load_config(config_file):
    """YAML 설정 파일 로드"""
    with open(config_file, 'r', encoding='utf-8') as f:
        return yaml.safe_load(f)


def prepare_template_context(config, environment, service_key):
    """Jinja2 템플릿에 전달할 컨텍스트 준비"""
    service_config = config['services'][service_key]
    env_config = service_config.get('environment', {}).get(environment, {})

    # 공통 설정
    common_config = config.get('common', {})

    # 환경별 설정
    env_settings = config['environments'][environment]

    context = {
        'environment': environment,
        'service_name': service_config['name'],
        **env_config,  # 서비스별 환경 변수
        # 추가 변수 (필요 시)
        'domain': env_settings['domain'],
        'protocol': env_settings['protocol'],
        'sso_enabled': str(env_settings['sso_enabled']).lower(),
        'log_level': env_settings['log_level'],
    }

    return context


def generate_env_file(config, environment, service_key, service_info):
    """개별 서비스의 .env 파일 생성"""
    template_path = TEMPLATE_DIR / service_info['template']
    service_dir = PROJECT_ROOT / service_info['dir']
    env_file_path = service_dir / '.env'

    # 템플릿 로드
    if not template_path.exists():
        print(f"❌ 템플릿 없음: {template_path}")
        return False

    with open(template_path, 'r', encoding='utf-8') as f:
        template = Template(f.read())

    # 컨텍스트 준비
    context = prepare_template_context(config, environment, service_key)

    # 렌더링
    rendered = template.render(**context)

    # .env 파일 생성
    service_dir.mkdir(parents=True, exist_ok=True)
    with open(env_file_path, 'w', encoding='utf-8') as f:
        f.write(rendered)

    print(f"✅ {env_file_path.relative_to(PROJECT_ROOT)}")
    return True


def main():
    """메인 함수"""
    if len(sys.argv) < 2:
        print("사용법: python3 generate_env_files.py <environment>")
        print("환경: development | production")
        sys.exit(1)

    environment = sys.argv[1]

    if environment not in ['development', 'production']:
        print(f"❌ 잘못된 환경: {environment}")
        print("사용 가능한 환경: development, production")
        sys.exit(1)

    print(f"🔧 환경 변수 파일 생성: {environment}")
    print("=" * 60)

    # 설정 파일 로드
    if not CONFIG_FILE.exists():
        print(f"❌ 설정 파일 없음: {CONFIG_FILE}")
        sys.exit(1)

    config = load_config(CONFIG_FILE)

    # 각 서비스별로 .env 파일 생성
    success_count = 0
    for service_key, service_info in SERVICE_MAPPING.items():
        if generate_env_file(config, environment, service_key, service_info):
            success_count += 1

    print("=" * 60)
    print(f"✅ 완료: {success_count}/{len(SERVICE_MAPPING)} 파일 생성")

    if success_count == len(SERVICE_MAPPING):
        print(f"\n📋 다음 단계:")
        print(f"   각 서비스 디렉토리의 .env 파일을 확인하세요")
        print(f"   예: cat dashboard/auth_portal_4430/.env")
        return 0
    else:
        print(f"\n⚠️  일부 파일 생성 실패")
        return 1


if __name__ == '__main__':
    sys.exit(main())
```

---

## ⚠️ 주의사항

### ❌ 하지 말아야 할 것

1. **Slurm 관련 파일 수정 금지**
   - `my_cluster.yaml`
   - `setup_cluster_full.sh`
   - 기타 Slurm 설정 파일

2. **기존 start/stop 스크립트 수정 금지**
   - `start_complete.sh`
   - `stop_complete.sh`
   - 기타 실행 스크립트

3. **.env 파일을 Git에 커밋하지 말 것**
   - `.env` 파일은 `.gitignore`에 추가
   - 환경 변수에 민감한 정보 포함 가능

### ✅ 반드시 해야 할 것

1. **백업**
   ```bash
   # 수정할 5개 파일 백업 (사용자가 직접 수행)
   ```

2. **코드 수정 전 현재 동작 확인**
   ```bash
   # 서비스가 현재 정상 동작하는지 확인
   ./start_complete.sh
   # 브라우저에서 접속 테스트
   ./stop_complete.sh
   ```

3. **수정 후 동작 확인**
   ```bash
   # .env 파일 생성
   python3 web_services/scripts/generate_env_files.py development

   # 서비스 재시작 (기존 스크립트 사용)
   ./start_complete.sh

   # 브라우저에서 접속 테스트
   ```

---

## 🔧 트러블슈팅

### 문제 1: PyYAML 또는 Jinja2 설치 실패

**증상**:
```
ModuleNotFoundError: No module named 'yaml'
```

**해결**:
```bash
# pip 업그레이드
python3 -m pip install --upgrade pip

# 패키지 재설치
python3 -m pip install --user pyyaml jinja2
```

### 문제 2: .env 파일 생성 실패

**증상**:
```
❌ 템플릿 없음: web_services/templates/env/auth_portal_4430.env.j2
```

**해결**:
```bash
# Phase 1 완료 확인
./verify_phase1.sh

# 템플릿 파일 존재 확인
ls -la web_services/templates/env/
```

### 문제 3: TypeScript 빌드 에러

**증상**:
```
error TS2304: Cannot find name 'import'
```

**해결**:
```bash
# Node.js 버전 확인 (v16 이상 권장)
node --version

# npm 패키지 재설치
cd dashboard/auth_portal_4431
npm install
npm run build
```

### 문제 4: 코드 수정 후 서비스 시작 실패

**해결**:
```bash
# .env 파일 생성 확인
ls -la dashboard/*/. env

# .env 파일 내용 확인
cat dashboard/auth_portal_4430/.env

# 로그 확인
tail -f /var/log/hpc_web_services/*.log
```

---

## 📈 진행 상황 체크

### Phase 2 완료 기준

- [x] Phase 1 완료 확인
- [ ] Python 패키지 설치 (pyyaml, jinja2)
- [ ] `generate_env_files.py` 스크립트 작성
- [ ] 5개 파일 코드 수정 완료
- [ ] 8개 서비스의 `.env` 파일 생성 성공
- [ ] `verify_phase2.sh` 통과

### 완료 후 다음 단계

```bash
# Phase 2 완료 확인
./verify_phase2.sh

# 성공 시 출력 예상:
# ✅✅✅ Phase 2 완료!
#
# 📋 다음 단계:
#    cat PHASE3_GUIDE.md
```

---

## 🎓 Phase 2에서 수정된 파일 목록

### 신규 생성 파일 (1개)

```
web_services/scripts/generate_env_files.py    # .env 생성 스크립트
```

### 수정된 기존 파일 (5개)

```
dashboard/auth_portal_4430/config/config.py             # 환경 변수 확인
dashboard/auth_portal_4430/saml_handler.py              # localhost URL 제거
dashboard/auth_portal_4431/src/pages/ServiceMenuPage.tsx  # URL 처리 개선
dashboard/auth_portal_4431/src/pages/VNCPage.tsx        # 환경 변수 확인
dashboard/vnc_service_8002/src/App.tsx                  # 상대 경로 사용
```

### 생성될 파일 (.env - Git 제외)

```
dashboard/auth_portal_4430/.env
dashboard/auth_portal_4431/.env
dashboard/backend_5010/.env
dashboard/frontend_3010/.env
dashboard/kooCAEWebServer_5000/.env
dashboard/kooCAEWebAutomationServer_5001/.env
dashboard/kooCAEWeb_5173/.env
dashboard/vnc_service_8002/.env
```

---

## ⏭️ Phase 3 준비사항

Phase 2 완료 후 Phase 3에서는:

1. **설치 자동화 스크립트 작성**
   - `setup_web_services.sh` - 전체 설치
   - `reconfigure_web_services.sh` - 구성만 변경

2. **헬퍼 스크립트 작성**
   - `install_dependencies.sh` - 의존성 설치
   - `health_check.sh` - 서비스 상태 확인
   - `rollback.sh` - 설정 롤백

3. **서비스별 재구성 스크립트**
   - `reconfigure_service.sh` - 개별 서비스 재구성

---

## 💬 질문 및 지원

Phase 2 진행 중 문제 발생 시:

1. `verify_phase2.sh` 실행하여 누락 확인
2. 트러블슈팅 섹션 참조
3. 백업에서 복원 후 재시도

**예상 소요 시간: 2-3시간**
**난이도: 중급 (Python, TypeScript 기본 지식 필요)**
