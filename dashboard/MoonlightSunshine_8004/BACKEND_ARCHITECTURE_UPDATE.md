# Backend Architecture Update - 2025-12-06

## 변경 사항 요약

사용자 요구사항:
> "백엔드를 이거 용의 이름_포트로 따로 폴더를 또 생성해서 두개가 있으면 사용 가능하게끔 해야해. 그리고 이미지도 새로 만드는 방향으로 생각해야 하고."

## 1. 백엔드 디렉토리 구조 변경

### 기존 (잘못된 구조)
```
MoonlightSunshine_8004/
└── backend/
    ├── server.js           # Node.js 서버 (계획만 있음)
    └── moonlight_api.py    # 파일만 있음
```

### 신규 (올바른 구조) ✅
```
MoonlightSunshine_8004/
└── backend_moonlight_8004/     # ← {purpose}_{port} 패턴
    ├── app.py                  # ✅ Flask 메인 앱
    ├── moonlight_api.py        # ✅ Moonlight API Blueprint
    ├── requirements.txt        # ✅ Python 의존성
    ├── gunicorn_config.py      # ✅ Gunicorn 설정 (Port 8004)
    ├── README.md               # ✅ 백엔드 문서
    ├── logs/                   # 독립 로그 디렉토리 (생성 예정)
    └── venv/                   # 독립 가상환경 (설치 시 생성)
```

### 기존 백엔드들과의 일관성

| 백엔드 | 디렉토리 | 포트 | 목적 |
|--------|----------|------|------|
| **VNC Backend** | `backend_5010/` | 5010 | VNC Session API |
| **CAE Web Server** | `kooCAEWebServer_5000/` | 5000 | CAE 웹 서비스 |
| **CAE Automation** | `kooCAEWebAutomationServer_5001/` | 5001 | CAE 자동화 |
| **Moonlight Backend** ✅ | `backend_moonlight_8004/` | 8004 | Moonlight Session API |

---

## 2. 생성된 파일

### 2.1. `backend_moonlight_8004/app.py`
```python
"""
Moonlight/Sunshine Backend Server (Port 8004)
완전히 독립된 Flask 애플리케이션
"""

from flask import Flask, jsonify
from flask_cors import CORS
from moonlight_api import moonlight_bp

app = Flask(__name__)
CORS(app)

# Register blueprints
app.register_blueprint(moonlight_bp)

# Health check endpoint
@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({'status': 'healthy', 'service': 'moonlight_backend', 'port': 8004}), 200

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8004, debug=False)
```

**역할**: Flask 메인 애플리케이션 (Blueprint 등록, CORS 설정, Health Check)

---

### 2.2. `backend_moonlight_8004/moonlight_api.py`
```python
"""
Moonlight/Sunshine Session Management API
❌ backend_5010/vnc_api.py를 수정하지 않음!
✅ 완전히 독립된 새 파일
"""

from flask import Blueprint, request, jsonify
import redis
import subprocess

moonlight_bp = Blueprint('moonlight', __name__, url_prefix='/api/moonlight')

# Moonlight 전용 설정
SUNSHINE_IMAGES_DIR = "/opt/apptainers"
SUNSHINE_SANDBOXES_DIR = "/scratch/sunshine_sandboxes"  # ✅ VNC와 분리
SUNSHINE_SESSIONS_DIR = "/scratch/sunshine_sessions"
SUNSHINE_LOG_DIR = "/scratch/sunshine_logs"

# Sunshine 이미지 목록 (VNC와 완전 독립)
SUNSHINE_IMAGES = {
    "xfce4": {
        "name": "XFCE4 Desktop (Sunshine)",
        "sif_path": f"{SUNSHINE_IMAGES_DIR}/sunshine_xfce4.sif",
        "icon": "🌞",
        "default": True
    }
}

@moonlight_bp.route('/sessions', methods=['GET', 'POST'])
def manage_sessions():
    # Session management logic
    pass

def submit_moonlight_job(...):
    # Slurm job submission with QoS isolation
    pass
```

**역할**:
- Moonlight 세션 관리 API (생성/조회/삭제)
- Slurm Job 제출 (QoS `moonlight` 사용)
- Redis 세션 저장 (`moonlight:session:*` 키 패턴)

**기존 VNC와의 차이**:
1. 디렉토리: `/scratch/sunshine_*` (VNC는 `/scratch/vnc_*`)
2. Redis 키: `moonlight:session:*` (VNC는 `vnc:session:*`)
3. Display: `:10+` (VNC는 `:1-:9`)
4. QoS: `moonlight` (VNC는 QoS 없음)
5. 포트: `47989-48010` (VNC는 `5900-5999`, `6900-6999`)
6. 프로토콜: GameStream/WebRTC (VNC는 RFB/WebSocket)

---

### 2.3. `backend_moonlight_8004/requirements.txt`
```
Flask==3.1.1
flask-cors==6.0.1
gunicorn==21.2.0
redis==5.0.1
python-dotenv==1.1.1
```

**역할**: Python 의존성 정의 (VNC와 독립된 가상환경 사용)

---

### 2.4. `backend_moonlight_8004/gunicorn_config.py`
```python
# Server socket
bind = "127.0.0.1:8004"  # ✅ VNC(5010)와 다른 포트

# Worker processes
workers = 2
worker_class = "gthread"
threads = 2

# Logging
accesslog = "logs/gunicorn_access.log"
errorlog = "logs/gunicorn_error.log"
pidfile = "logs/gunicorn.pid"

# Process naming
proc_name = "moonlight_8004"  # ✅ VNC(backend_5010)와 다른 이름
```

**역할**: Gunicorn Production 설정 (Port 8004, 독립 로그, 독립 PID)

---

### 2.5. `backend_moonlight_8004/README.md`
```markdown
# Moonlight/Sunshine Backend API (Port 8004)

## 기존 VNC Backend와 완전 분리

| 항목 | 기존 VNC (backend_5010) | 신규 Moonlight (backend_moonlight_8004) |
|------|------------------------|----------------------------------------|
| **디렉토리** | `backend_5010/` | `backend_moonlight_8004/` ✅ |
| **포트** | 5010 | 8004 ✅ |
| **API 경로** | `/api/vnc/*` | `/api/moonlight/*` ✅ |
| **프로세스** | Gunicorn (backend_5010) | Gunicorn (backend_moonlight_8004) ✅ |
| **PID 파일** | `backend_5010/logs/gunicorn.pid` | `backend_moonlight_8004/logs/gunicorn.pid` ✅ |
```

**역할**: 백엔드 문서화 (설치 방법, 기존 VNC와의 차이점)

---

## 3. IMPLEMENTATION_PLAN.md 수정 사항

### 3.1. 프로세스 격리 섹션 업데이트 (Line 227-230)
**기존**:
```bash
# 신규 Moonlight Gateway (독립 프로세스, Node.js, Port 8004)
node MoonlightSunshine_8004/backend/server.js
```

**수정 후**:
```bash
# 신규 Moonlight Backend (완전 독립 디렉토리, Gunicorn, Port 8004)
# backend_moonlight_8004/ ← backend_5010/과 완전 분리
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/MoonlightSunshine_8004/backend_moonlight_8004
venv/bin/gunicorn -c gunicorn_config.py app:app  # moonlight_api.py 포함
```

---

### 3.2. Phase 1.1 - Alternative Method 제거 (Line 319-356)

**삭제된 내용**:
```bash
**대안: 기존 이미지 복사 후 Sunshine 추가 (더 빠름)**
# ... 기존 VNC 이미지 복사 방법 (38줄)
```

**대체 내용**:
```
⚠️ **중요**: 기존 VNC 이미지를 **절대 수정하거나 복사하지 않음**
- 오직 **Definition 파일로부터 처음부터 새로 빌드**
- 이렇게 하면 완전한 격리가 보장됨
```

**이유**:
- 사용자 요구: "이미지도 새로 만드는 방향으로 생각해야 하고"
- 기존 VNC 이미지와의 완전한 격리 보장
- 복사 방법은 혼란을 줄 수 있음

---

### 3.3. Phase 5.1 - 백엔드 디렉토리 구조 반영 (Line 1117-1125)

**기존**:
```bash
# 새 파일 생성 위치
MoonlightSunshine_8004/backend/moonlight_api.py  # ✅ 새 파일
```

**수정 후**:
```bash
# 새 백엔드 디렉토리 구조 ({purpose}_{port} 패턴)
backend_moonlight_8004/              # ✅ backend_5010/과 완전 분리
├── app.py                           # Flask 메인 앱
├── moonlight_api.py                 # Moonlight API Blueprint
├── requirements.txt                 # Python 의존성
├── gunicorn_config.py               # Gunicorn 설정 (Port 8004)
├── logs/                            # 독립 로그 디렉토리
└── venv/                            # 독립 가상환경
```

---

## 4. 완전한 격리 확인

### 4.1. 디렉토리 격리 ✅
```
backend_5010/               # VNC Backend (건드리지 않음)
backend_moonlight_8004/     # Moonlight Backend (완전 독립)
```

### 4.2. 프로세스 격리 ✅
```bash
# VNC Backend
cd /home/.../dashboard/backend_5010
venv/bin/gunicorn -c gunicorn_config.py app:app  # Port 5010

# Moonlight Backend (독립 실행)
cd /home/.../dashboard/MoonlightSunshine_8004/backend_moonlight_8004
venv/bin/gunicorn -c gunicorn_config.py app:app  # Port 8004
```

### 4.3. 가상환경 격리 ✅
```
backend_5010/venv/              # VNC 의존성
backend_moonlight_8004/venv/    # Moonlight 의존성 (독립)
```

### 4.4. 로그 격리 ✅
```
backend_5010/logs/gunicorn.pid              # VNC PID
backend_moonlight_8004/logs/gunicorn.pid    # Moonlight PID (독립)
```

### 4.5. API 경로 격리 ✅
```
/api/vnc/*                  # VNC API (backend_5010)
/api/moonlight/*            # Moonlight API (backend_moonlight_8004)
```

---

## 5. 설치 방법

### Step 1: 가상환경 생성
```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/MoonlightSunshine_8004/backend_moonlight_8004

python3 -m venv venv
```

### Step 2: 의존성 설치
```bash
venv/bin/pip install -r requirements.txt
```

### Step 3: 로그 디렉토리 생성
```bash
mkdir -p logs
```

### Step 4: 실행 (개발 모드)
```bash
venv/bin/python app.py
```

### Step 5: 실행 (프로덕션 모드)
```bash
venv/bin/gunicorn -c gunicorn_config.py app:app
```

### Step 6: 확인
```bash
# Health Check
curl http://localhost:8004/health

# 프로세스 확인
ps aux | grep "moonlight_8004"

# 포트 확인
lsof -i :8004
```

---

## 6. 최종 검증

### 6.1. 기존 VNC 서비스 무결성 ✅
```bash
# VNC 백엔드 파일이 수정되지 않았는지 확인
ls -lh /home/.../dashboard/backend_5010/
# vnc_api.py가 그대로 있어야 함
```

### 6.2. 독립성 확인 ✅
```bash
# 두 백엔드가 서로 다른 디렉토리에 있는지 확인
ls -lh /home/.../dashboard/backend_5010/
ls -lh /home/.../dashboard/MoonlightSunshine_8004/backend_moonlight_8004/
```

### 6.3. 동시 실행 가능성 ✅
```bash
# VNC Backend (Port 5010)
lsof -i :5010

# Moonlight Backend (Port 8004)
lsof -i :8004

# 두 프로세스가 서로 다른 포트에서 독립 실행되어야 함
```

---

## 7. 결론

✅ **백엔드 아키텍처 변경 완료**

1. **디렉토리 패턴 준수**: `backend_moonlight_8004/` (기존 `backend_5010/`과 일관성)
2. **완전한 격리**: 디렉토리, 프로세스, 가상환경, 로그, API 경로 모두 분리
3. **이미지 빌드 전략 명확화**: Definition 파일로부터 **처음부터 새로 빌드**만 허용
4. **기존 시스템 안전**: VNC Backend (`backend_5010/`)를 전혀 건드리지 않음

**다음 단계**:
- Phase 1-5를 순차적으로 진행
- ISOLATION_CHECKLIST.md를 준수하며 구현
- 각 Phase 완료 후 기존 VNC 서비스 정상 동작 확인
