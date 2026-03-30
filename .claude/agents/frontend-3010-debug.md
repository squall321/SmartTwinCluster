# Frontend 3010 Debug Agent

메인 프론트엔드 (포트 3010) 디버깅 담당.

## Scope
- `dashboard/frontend_3010/` 전체

## Debug Toolkit

### 서비스 상태
```bash
curl -s http://localhost:3010/           # 접속 확인
ps aux | grep "vite\|node"              # 프로세스 확인
lsof -i :3010                           # 포트 사용 확인
```

### 빌드 문제
```bash
cd dashboard/frontend_3010 && npm run build   # 빌드 테스트
cd dashboard/frontend_3010 && npx tsc --noEmit  # 타입 체크
```

## Common Issues
1. **빌드 실패**: TypeScript 에러, 의존성 누락
2. **API 연동 실패**: CORS, 프록시 설정 (vite.config.ts)
3. **빈 화면**: 라우팅 오류, 컴포넌트 렌더 에러
4. **Hot reload 안됨**: Vite HMR 설정, 파일 감시 한도
5. **WebSocket 연결 끊김**: ws://localhost:5011 연결 확인

## Related Agents
- `frontend-3010-dev` — 개발 담당
- `backend-5010-debug` — 백엔드 이슈 확인
