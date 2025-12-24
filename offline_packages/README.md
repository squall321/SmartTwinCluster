# Offline Packages for Dashboard Installation

이 디렉토리는 오프라인 환경에서 Dashboard 서비스들을 설치하기 위한 패키지들을 포함합니다.

## 📦 포함된 내용

### 1. Python Wheels (`python_wheels/`)

모든 Dashboard Python 서비스의 dependencies를 포함한 wheel 파일들입니다.

**Python 버전별 패키지:**
- `python3.10/`: 68 packages (auth_portal, websocket, backend_moonlight)
- `python3.12/`: 64 packages (backend_5010)
- `python3.13/`: 67 packages (kooCAEWebServer, kooCAEWebAutomationServer)

**압축 파일:**
- `python_wheels.tar.gz` (205MB) - 오프라인 서버로 전송용

## 🚀 사용 방법

### 1단계: Wheel 패키지 다운로드 (인터넷 있는 환경)

```bash
cd offline_packages
./download_python_wheels.sh
```

실행 결과:
```
✅ Found 6 requirements.txt files
✅ Python 3.10: 3 services, 68 wheels
✅ Python 3.12: 1 service, 64 wheels  
✅ Python 3.13: 2 services, 67 wheels
```

### 2단계: 압축 (선택사항)

```bash
tar -czf python_wheels.tar.gz python_wheels/
```

### 3단계: 오프라인 서버로 전송

```bash
# 방법 1: scp 사용
scp python_wheels.tar.gz user@target-server:/opt/offline_packages/

# 방법 2: USB 또는 물리적 전송
```

### 4단계: 오프라인 서버에서 압축 해제

```bash
cd /opt/offline_packages
tar -xzf python_wheels.tar.gz
```

### 5단계: 설치 (cluster setup 스크립트가 자동으로 수행)

`cluster/setup/phase5_web.sh`가 자동으로 오프라인 wheel을 감지하고 사용합니다:

```bash
# 자동 감지 로직:
if [ -d "/opt/offline_packages/python_wheels/python3.12" ]; then
    pip install --no-index --find-links=/opt/offline_packages/python_wheels/python3.12 -r requirements.txt
else
    pip install -r requirements.txt  # Fallback to online
fi
```

## 📊 서비스별 Python 버전

| 서비스 | Python 버전 | 패키지 수 |
|--------|------------|----------|
| auth_portal_4430 | 3.10 | 31 |
| websocket_5011 | 3.10 | 49 |
| backend_moonlight_8004 | 3.10 | 13 |
| backend_5010 | 3.12 | 64 |
| kooCAEWebServer_5000 | 3.13 | 35 |
| kooCAEWebAutomationServer_5001 | 3.13 | 49 |

## 🔧 수동 설치 (선택사항)

특정 서비스만 수동으로 설치할 경우:

```bash
# Python 3.10 서비스
cd dashboard/auth_portal_4430
source venv/bin/activate
pip install --no-index --find-links=/opt/offline_packages/python_wheels/python3.10 -r requirements_actual.txt

# Python 3.12 서비스
cd dashboard/backend_5010
source venv/bin/activate
pip install --no-index --find-links=/opt/offline_packages/python_wheels/python3.12 -r requirements_actual.txt

# Python 3.13 서비스
cd dashboard/kooCAEWebServer_5000
source venv/bin/activate
pip install --no-index --find-links=/opt/offline_packages/python_wheels/python3.13 -r requirements_actual.txt
```

## ✅ 검증

모든 공유 패키지가 통일된 버전을 사용합니다:
- PyJWT: 2.10.1
- Flask: 3.1.1
- Flask-Cors: 6.0.1
- redis: 7.0.1
- gunicorn: 21.2.0
- Werkzeug: 3.1.3~3.1.4 (호환 범위)

## 📝 주의사항

1. **Python 버전 매칭**: 각 서비스는 특정 Python 버전의 wheel만 사용해야 합니다
2. **requirements_actual.txt 우선**: 실제 설치된 패키지 목록 사용
3. **자동 fallback**: 오프라인 wheel이 없으면 자동으로 온라인 설치 시도
4. **JWT 호환성**: PyJWT 버전이 통일되어 있어 JWT 토큰 검증이 모든 서비스에서 동작합니다

## 🔄 업데이트

패키지를 업데이트해야 할 경우:

1. 인터넷 있는 환경에서 서비스의 venv 업데이트
2. `venv/bin/pip freeze > requirements_actual.txt` 실행
3. `./download_python_wheels.sh` 재실행
4. 새 압축 파일 생성 및 전송

---

생성일: 2025-12-24
작성자: Claude Code
