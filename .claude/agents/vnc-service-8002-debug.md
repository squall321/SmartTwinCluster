# VNC Service 8002 Debug Agent

VNC 서비스 (포트 8002) 디버깅 담당.

## Scope
- `dashboard/vnc_service_8002/` 전체

## Debug Toolkit
```bash
curl -s http://localhost:8002/health
lsof -i :8002
# VNC 세션 상태 확인
squeue -o "%i %j %T %N" | grep vnc
```

## Common Issues
1. **VNC 세션 시작 안됨**: Slurm 잡 제출 실패, 파티션 설정
2. **화면 안보임**: VNC 서버 프로세스 확인, 디스플레이 번호
3. **연결 끊김**: 프록시 타임아웃, 네트워크
4. **권한 문제**: 사용자별 세션 격리
5. **잡 pending**: Slurm 리소스 부족, GRES 설정

## Related Agents
- `vnc-service-8002-dev` — 개발 담당
- `slurm-ops` — Slurm 잡 문제
- `moonlight-8003-8004-debug` — 대안 원격 데스크톱 디버깅
