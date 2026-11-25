<!-- SM 묶음 작업 중 결정과 근거 -->
# 컨텍스트 노트 — SM 묶음 (2026-11-25)

- SM-04: 이름으로 admin 을 막지 않는다 — 실제 웹 사용자 admin 이 있다(/data/single/admin 캠페인). SSO 꺼짐으로 풀린 admin 은
  /api/me 의 auth=sso_off 로 가린다(요청서 대안안). MCP 는 auth==pat 만 받는다 → backend 를 먼저 올려야 MCP 가 산다(배포 순서).
- 운영 박스(cae00)의 backend_5010 도 같이 올라가야 그쪽 MCP 가 산다 — 운영 수작업에 적을 것.
- REST PatVerifier 도 /api/me 로만 확인하던 관문이라 같은 auth==pat 을 건다(SSO 꺼짐이면 아무 Bearer 나 admin 으로 통과했다).
- job_helpers.backend_submit·submit_job/1.2.0 의 /api/me 는 backend 가 제출을 허가한 뒤 결과 폴더 이름만 읽는 것 — backend 신원과 같은 값이라 그대로 둠.
- 위임 PAT 의 권한은 DELEGATE_IDENTITY(role user, permissions [dashboard]). MCP 가 부르는 /api/jobs/submit·preview·rerun 은 dashboard 만 요구 → 고친 뒤에도 막히지 않는다.
- dev backend 는 dashboard_backend.service, SSO_ENABLED=false(.env) — 이 결함이 실제로 걸린 상태였다.
