# SAML IdP 7000 Debug Agent

SAML Identity Provider (포트 7000) 디버깅 담당.

## Scope
- `dashboard/saml_idp_7000/` 전체

## Debug Toolkit
```bash
curl -s http://localhost:7000/metadata    # 메타데이터 확인
curl -s http://localhost:7000/health      # 헬스 체크
lsof -i :7000                            # 포트 확인
```

## Common Issues
1. **메타데이터 로드 실패**: 인증서 파일 경로
2. **사용자 인증 실패**: `config/users.json` 형식
3. **SP 등록 실패**: 메타데이터 URL 불일치
4. **인증서 만료**: SAML 서명 인증서 갱신

## Related Agents
- `saml-idp-7000-dev` — 개발 담당
- `auth-backend-4430-debug` — SP 측 디버깅
