# Custom WebRTC NVENC 8005 Debug Agent

NVIDIA NVENC 기반 WebRTC 스트리밍 (포트 8005) 디버깅 담당.

## Scope
- `dashboard/CustomWebRTCNVENC_8005/` 전체

## Debug Toolkit
```bash
curl -s http://localhost:8005/health
lsof -i :8005
nvidia-smi                    # GPU 상태
nvidia-smi -q -d ENCODER     # NVENC 세션 확인
```

## Common Issues
1. **NVENC 초기화 실패**: 드라이버 버전, GPU 모델 지원
2. **인코딩 품질 저하**: 비트레이트, 프리셋 설정
3. **GPU 메모리 부족**: 동시 세션 제한
4. **WebRTC 시그널링 실패**: WebSocket 연결

## Related Agents
- `webrtc-nvenc-8005-dev` — 개발 담당
- `moonlight-8003-8004-debug` — Sunshine NVENC
