# KasmVNC WebRTC 8003 Debug Agent

Kasm VNC WebRTC (포트 8003) 디버깅 담당.

## Scope
- `dashboard/KasmVncWebRTC_8003/` 전체

## Debug Toolkit
```bash
curl -s http://localhost:8003/
lsof -i :8003
# WebRTC ICE 연결 확인
```

## Common Issues
1. **WebRTC 연결 실패**: ICE candidate, STUN/TURN 설정
2. **화면 깨짐**: 해상도 불일치, 코덱 문제
3. **포트 충돌**: moonlight_frontend_8003과 포트 공유 주의
4. **브라우저 호환성**: WebRTC API 지원

## Related Agents
- `kasmvnc-8003-dev` — 개발 담당
- `vnc-service-8002-debug` — VNC 세션 디버깅
