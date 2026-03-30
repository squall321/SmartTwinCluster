# App 5174 Debug Agent

App 프론트엔드 (포트 5174) 디버깅 담당.

## Scope
- `dashboard/app_5174/` 전체

## Debug Toolkit
```bash
curl -s http://localhost:5174/
lsof -i :5174
cd dashboard/app_5174 && npm run build   # 빌드 확인
```

## Common Issues
1. **빌드 실패**: TypeScript 에러, 의존성 충돌
2. **VNC 임베딩 안됨**: iframe/WebSocket 설정
3. **Apptainer 이미지 목록 안뜸**: API 연동
4. **Slurm 잡 제출 실패**: 파라미터 검증

## Related Agents
- `app-5174-dev` — 개발 담당
- `backend-5010-debug` — 백엔드 API 디버깅
- `vnc-service-8002-debug` — VNC 디버깅
