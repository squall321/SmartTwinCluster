# 운영 SSO 켜기·위임 창구 — 컨텍스트 노트

호출자 목록은 [callers.md](callers.md). 진행은 [checklist.md](checklist.md).

## 위임 창구(2026-10-29) — 사용자 결정 「위임 창구로 바꾼다」(kooremapper-4a 전달)

kst_token 을 도구 인자로 나르면 포털 절차 원장·백업·실행 화면·LLM 문맥에 평문으로 남는다. 그래서 KooSlurm 이
공유 비밀을 쥔 쪽(HWAX 게이트웨이 per_user_sso, DynaForge)에 그 사람의 kst_ 를 내주는 창구를 만든다.
규격은 게이트웨이가 이미 부르는 꼴(HWAXMcpGateway gateway.py `_sso_headers`·`_mint_user_pat`)과
DynaForge 참고 구현(KooRemapper platform/backend/app/modules/auth/routes.py `/auth/sso`·`/auth/sso/verify`)을 따른다.

### 결정

- **주소** — `POST /api/auth/sso`(발급), `POST /api/auth/sso/verify`(비밀 점검). nginx 가 `/api/` 를 백엔드로 넘기므로
  `/api/` 아래에 둔다. 기존 `/api/auth/*` 는 `/api/auth/config` 하나뿐이라 겹치지 않는다.
- **비밀 변수** — `HEAX_GATEWAY_SECRET`(DynaForge `KOORM_HEAX_GATEWAY_SECRET`, 게이트웨이 `per_user_sso.<app>.secret` 과 같은 관례).
  요청마다 env 에서 읽는다. 비어 있으면 두 길 모두 404(구성 없음). 대조는 `hmac.compare_digest`.
  운영에서는 `backend_5010/.env`(git 밖) 또는 유닛 env 에 둔다 — YAML(git) 에 두지 않는다.
- **위임 대상 이메일** — `X-Hwax-Delegate-Email` 이 정본(Caddy 경로에서 `X-Heax-User-Email` 이 덮일 수 있다), 없으면 `X-Heax-User-Email`.
- **사용자 이름 규칙** — 이메일을 소문자로 바꾼 뒤 `@` 앞부분. `[a-z0-9._-]{1,32}` 이고 `.` 로 시작하지 않아야 한다. 아니면 400.
  가정: 운영 SAML 의 `uid`(JWT sub)가 이메일 앞부분과 같다(auth_portal config `username: uid`). 다르면 위임 토큰과 그 사람의 웹
  신원이 어긋나 자기 잡이 안 보인다 — 그때는 대응표가 필요하다. 이 가정은 운영 사용자 하나로 확인할 것.
- **모르는 사람** — KooSlurm 에는 사용자 테이블이 없다(PAT 가 발급 때 신원 스냅샷을 담는다). 그래서 JIT 와 같다 — 형식이 맞는
  이메일이면 발급한다. 대신 `admin`·`anonymous`·`root` 로 풀리는 이메일은 거절한다. SSO 꺼짐 동안의 잡·결과·업로드가 전부
  `admin` 명의라, 그 이름으로 발급하면 그 전부가 열린다.
- **발급 신원** — role `user`, permissions `["dashboard"]`, groups `[]`(최소 권한). 업로드·제출·rerun·postprocess·잡 파일에 충분하다.
  그 사람이 웹에서 admin 이어도 위임 토큰은 user 다 — 위임은 "그 사람의 잡을 그 사람 대신" 이지 관리 권한이 아니다.
  role user 의 파티션 제한(YAML roles.definitions.user)을 받는다.
- **수명** — `expires_in` 3600초. 발급은 같은 (사람, 클라이언트) 의 직전 토큰을 지우고 새로 낸다(한 트랜잭션) — 사람·클라이언트당 활성 1개.
  클라이언트가 다르면 건드리지 않는다. 토큰 이름은 `위임: <client>` — 사용자의 'MCP 토큰' 화면에 보이고 사용자가 지울 수 있다.
- **클라이언트 허용 목록** — env `SSO_DELEGATE_CLIENTS`, 기본 `dynaforge,gateway`. 이름은 포털이 정하므로 env 로 늘린다.
  목록 밖이면 400(임의 이름을 받으면 회수 안 되는 토큰이 쌓인다 — 참고 구현과 같은 이유).
- **비밀 하나** — 게이트웨이와 DynaForge 가 같은 비밀을 쥔다(다른 앱 넷과 같은 방식, 사용자 결정의 전제). 클라이언트 이름은
  비밀에 묶이지 않으므로 비밀을 쥔 쪽은 어느 허용 이름으로도 발급할 수 있다 — 클라이언트별 비밀은 포털 `sso-set-app.sh` 와 맞지 않아 고르지 않았다.
- **속도 제한·감사** — `rate_limit_by_ip(120/분)`(nginx 뒤라 사실상 전체 합계). 발급마다 audit_log `token.delegate`
  (행위자 `delegate:<client>`, 대상 사용자 이름, 이메일).
