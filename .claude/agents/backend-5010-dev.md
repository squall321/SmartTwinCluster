# Backend 5010 Development Agent

메인 백엔드 API 서버 (포트 5010) 개발 담당.

## Scope
- `dashboard/backend_5010/` 전체
- Python/Flask 기반 REST API

## Key Files
- `app.py` — Flask 앱 엔트리포인트
- `database.py` — DB 연결 및 모델
- `*_api.py` — 각 도메인 API 모듈 (node_management, job_submit, templates, reports 등)
- `slurm_commands.py` / `slurm_utils.py` — Slurm CLI 래퍼
- `slurm_config_manager.py` — Slurm 설정 관리
- `gunicorn_config.py` — 프로덕션 서버 설정
- `requirements.txt` — Python 의존성

## API Modules
| Module | Description |
|--------|-------------|
| `node_management_api.py` | 노드 상태 관리 |
| `job_submit_api.py` | 작업 제출 |
| `templates_api.py` | 작업 템플릿 |
| `reports_api.py` | 리포트 생성 |
| `apptainer_api.py` | 컨테이너 관리 |
| `dashboard_api.py` | 대시보드 데이터 |
| `storage_api_optimized.py` | 파일 스토리지 |
| `ssh_api.py` | SSH 연결 |
| `prometheus_api.py` | Prometheus 연동 |
| `health_check_api.py` | 헬스 체크 |

## Development Guidelines
- 새 API 추가 시 `app.py`에 Blueprint 등록
- Slurm 명령어는 `slurm_commands.py` 통해 호출
- 프로덕션은 gunicorn, 개발은 Flask dev server
- DB는 SQLite (`slurm_dashboard.db`)

## Related Agents
- `backend-5010-debug` — 디버깅 담당
- `frontend-3010-dev` — 프론트엔드 연동
- `websocket-5011-dev` — WebSocket 실시간 통신
- `auth-backend-4430-dev` — 인증 연동
