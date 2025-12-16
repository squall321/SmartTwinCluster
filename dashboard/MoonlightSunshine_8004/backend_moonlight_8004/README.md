# Moonlight/Sunshine Backend API (Port 8004)

## 디렉토리 구조

```
backend_moonlight_8004/
├── app.py                      # Flask 앱 메인 (Port 8004)
├── moonlight_api.py           # Moonlight Session API
├── requirements.txt           # Python 의존성
├── gunicorn_config.py         # Gunicorn 설정
├── logs/                      # 로그 디렉토리
│   ├── gunicorn.log
│   ├── gunicorn.pid
│   └── access.log
└── venv/                      # 가상환경 (설치 후)
```

## 기존 VNC Backend와 완전 분리

| 항목 | 기존 VNC (backend_5010) | 신규 Moonlight (backend_moonlight_8004) |
|------|------------------------|----------------------------------------|
| **디렉토리** | `backend_5010/` | `backend_moonlight_8004/` ✅ |
| **포트** | 5010 | 8004 ✅ |
| **API 경로** | `/api/vnc/*` | `/api/moonlight/*` ✅ |
| **프로세스** | Gunicorn (backend_5010) | Gunicorn (backend_moonlight_8004) ✅ |
| **PID 파일** | `backend_5010/logs/gunicorn.pid` | `backend_moonlight_8004/logs/gunicorn.pid` ✅ |

## 설치 방법

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/backend_moonlight_8004

# 가상환경 생성
python3 -m venv venv

# 의존성 설치
venv/bin/pip install -r requirements.txt

# Gunicorn으로 실행
venv/bin/gunicorn -c gunicorn_config.py app:app
```

## 주의사항

⚠️ **기존 backend_5010을 절대 수정하지 않음!**
- 완전히 독립된 디렉토리
- 독립된 venv
- 독립된 포트
- 독립된 프로세스
