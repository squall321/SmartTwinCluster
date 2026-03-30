# Auth Portal Frontend 4431 Debug Agent

인증 포털 프론트엔드 (포트 4431) 디버깅 담당.

## Scope
- `dashboard/auth_portal_4431/` 전체
- 로그: `dashboard/auth_portal_4431/logs/`

## Debug Toolkit
```bash
curl -s http://localhost:4431/
lsof -i :4431
cd dashboard/auth_portal_4431 && npm run build  # 빌드 테스트
```

## Common Issues
1. **로그인 화면 안뜸**: 라우팅, 빌드 에러
2. **SSO 리다이렉트 실패**: 리다이렉트 URL 설정
3. **토큰 저장 실패**: localStorage/cookie 정책
4. **CORS 에러**: auth_portal_4430 백엔드 설정

## Related Agents
- `auth-frontend-4431-dev` — 개발 담당
- `auth-backend-4430-debug` — 백엔드 디버깅
