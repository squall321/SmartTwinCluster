# 운영 SSO 켜기·위임 창구 — 체크리스트

결정 근거는 [context-notes.md](context-notes.md).

## 호출자 조사
- [x] 토큰 없이 대시보드를 부르는 호출자 목록 — [callers.md](callers.md) `19b45273`
- [x] 화면 raw fetch 3곳에 JWT — `f267c127`

## 위임 창구
- [x] `mcp_token.rotate_token` — 같은 (사람, 이름) 직전 토큰 삭제 + 새 발급을 한 트랜잭션으로, 초 단위 수명
- [x] `sso_delegate_api.py` — `POST /api/auth/sso`·`/api/auth/sso/verify`, app.py 등록
- [x] 테스트: 비밀 없음 404·틀림 401·맞음 204, 발급 200(access_token·expires_in), 이메일 규칙·거절 이름·클라이언트 400,
      같은 클라이언트 재발급이 직전 것 무효화·다른 클라이언트는 그대로, 위임 헤더 우선, 발급 토큰으로 보호 라우트 통과(SSO 켜짐)
- [x] callers.md 에 창구 반영, peer 회신(주소·변수·규칙·클라이언트·수명·권한)

## SSO 켜는 날(사용자 결정 대기)
- [ ] 걸린 DynaForge 예약 없음 확인
- [ ] 유닛 env SSO_ENABLED·YAML sso.enabled·nginx 정본 conf
- [ ] `HEAX_GATEWAY_SECRET` 운영 반영(포털 sso-set-app.sh 점검 204)
