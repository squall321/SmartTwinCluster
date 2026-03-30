# Auth Portal Backend 4430 Debug Agent

인증 포털 백엔드 (포트 4430) 디버깅 담당.

## Scope
- `dashboard/auth_portal_4430/` 전체
- 로그: `dashboard/auth_portal_4430/logs/`

## Debug Toolkit

### 서비스 상태
```bash
curl -s http://localhost:4430/health
systemctl status auth_portal_4430
```

### 인증 테스트
```bash
# JWT 토큰 발급 테스트
curl -X POST http://localhost:4430/auth/login -d '{"username":"test","password":"test"}'
# SAML 메타데이터 확인
curl -s http://localhost:4430/saml/metadata
```

## Common Issues
1. **JWT 발급 실패**: 비밀키 설정, config.py 확인
2. **SAML 연동 실패**: IdP 메타데이터, 인증서 만료
3. **세션 만료 빈번**: 토큰 TTL 설정
4. **CORS 에러**: 프론트엔드(4431) 도메인 허용 목록
5. **config backup 파일 과다**: `.env.backup_*` 정리 필요

## Related Agents
- `auth-backend-4430-dev` — 개발 담당
- `saml-idp-7000-debug` — SAML IdP 디버깅
- `auth-frontend-4431-debug` — 프론트엔드 디버깅
