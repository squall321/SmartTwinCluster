# WebSocket 5011 Debug Agent

WebSocket 서비스 (포트 5011) 디버깅 담당.

## Scope
- `dashboard/websocket_5011/` 전체

## Debug Toolkit
```bash
lsof -i :5011
# WebSocket 연결 테스트
curl -i -N -H "Connection: Upgrade" -H "Upgrade: websocket" http://localhost:5011/
```

## Common Issues
1. **연결 수립 실패**: WebSocket handshake, 프록시 설정
2. **메시지 수신 안됨**: 이벤트 구독 누락
3. **연결 끊김**: 타임아웃, heartbeat 설정
4. **메모리 누수**: 연결 풀 관리, 해제 안된 핸들러
5. **nginx 프록시**: WebSocket upgrade 헤더 전달 설정

## Related Agents
- `websocket-5011-dev` — 개발 담당
- `backend-5010-debug` — 데이터 소스 디버깅
- `frontend-3010-debug` — 클라이언트 측 디버깅
