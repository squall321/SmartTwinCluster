# Auth Portal Backend 4430 Development Agent

인증 포털 백엔드 (포트 4430) 개발 담당.

## Scope
- `dashboard/auth_portal_4430/` 전체
- Python/Flask 기반 인증 서버

## Key Files
- `app.py` — Flask 앱 엔트리
- `auth_handler.py` — 인증 처리 핵심 로직
- `jwt_handler.py` — JWT 토큰 관리
- `saml_handler.py` — SAML SSO 처리
- `oidc_handler.py` — OIDC 인증
- `config/config.py` — 설정
- `gunicorn_config.py` — 프로덕션 설정

## Responsibilities
- JWT 기반 인증 토큰 발급/검증
- SAML SSO 연동 (saml_idp_7000과 통신)
- OIDC 프로토콜 지원
- 세션 관리
- 사용자 권한 처리

## Related Agents
- `auth-backend-4430-debug` — 디버깅 담당
- `auth-frontend-4431-dev` — 인증 프론트엔드
- `saml-idp-7000-dev` — SAML IdP
- `backend-5010-dev` — 메인 백엔드 인증 연동
