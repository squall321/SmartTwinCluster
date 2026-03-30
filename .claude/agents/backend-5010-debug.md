# Backend 5010 Debug Agent

메인 백엔드 API 서버 (포트 5010) 디버깅 및 장애 대응 담당.

## Scope
- `dashboard/backend_5010/` 전체
- 로그: `dashboard/backend_5010/logs/`, `backend.log`, `dashboard_backend.log`

## Debug Toolkit

### 로그 확인
```bash
tail -f dashboard/backend_5010/backend.log
tail -f dashboard/backend_5010/dashboard_backend.log
```

### 서비스 상태
```bash
systemctl status backend_5010          # systemd 서비스
curl -s http://localhost:5010/health   # 헬스 체크
ps aux | grep gunicorn                 # 프로세스 확인
```

### 기존 디버그 스크립트
- `debug_api.sh` — API 테스트
- `debug_reboot.sh` — 리부트 기능 디버그
- `debug_ssh_connection.sh` — SSH 연결 디버그
- `test_api.sh` — API 통합 테스트
- `check_reboot_status.sh` — 리부트 상태 확인

## Common Issues
1. **gunicorn 응답 없음**: worker 수/타임아웃 확인 (`gunicorn_config.py`)
2. **Slurm 명령 실패**: PATH 설정, scontrol/sinfo 접근 권한
3. **DB 잠금**: SQLite concurrent write 이슈
4. **SSH 연결 실패**: 키 권한, known_hosts
5. **인증 실패**: JWT 토큰 만료, auth_portal 연동 확인

## Recovery Actions
- `restart_backend.sh` / `restart_backend_final.sh` — 백엔드 재시작
- `switch_mode.sh` — mock/production 전환
- `fix_reports_production.sh` — 리포트 API 수정

## Related Agents
- `backend-5010-dev` — 개발 담당
- `websocket-5011-debug` — WebSocket 디버깅
- `auth-backend-4430-debug` — 인증 디버깅
