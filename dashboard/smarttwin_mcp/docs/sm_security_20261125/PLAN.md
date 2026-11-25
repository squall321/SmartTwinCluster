<!-- SmartTwin MCP 보안 묶음 SM-04·01·02·03 계획 (HWAXPortal request-1125 3-10절) -->
# 계획 — SM-04 → SM-01 → SM-02 → SM-03 (2026-11-25)

원문: HWAXPortal `docs/request-1125/request.md` 3-10절, hwaxportal-71 이 이 세션에 맡김(11-25).
사용자 결정(11-25): SM 묶음 전부 먼저(카탈로그 재생성은 그 뒤), 항목마다 시험 통과 시 main 병합·push·재시작.

## SM-04 (P1) — SSO 꺼짐이면 무엇이든 admin
- backend `jwt_required`·`optional_jwt`: Bearer kst_ 확인을 SSO 꺼짐 확인보다 앞에. 틀린 kst_ → 401(required) / None(optional).
- g.user 에 `auth`(pat|jwt|sso_off), `/api/me` 가 그대로 싣는다(요청서의 대안안).
- MCP `caller_identity`: 토큰이 kst_ 가 아니면 거절, `/api/me` 의 auth 가 pat 이 아니면 거절, root·anonymous 류 이름 거절.
- 확인: 위임 kst_ → 그 사람 이름 / 머리 없음 → 웹 admin, MCP 거절 / 틀린 kst_ → 401.

## SM-01 (P1) — 직접 sbatch 도구 3개(train_pytorch_gpu·submit_distributed_train·submit_lsdyna_remote 1.1.0)
- sbatch 파일 쓰기 전에 caller_name() + check_under(work_dir, work_roots(caller)), 잡 comment 에 호출자.

## SM-02 (P2) — readOnlyHint
- meta.yaml 에 읽기 칸을 따로 두고 annotations 를 거기서(mode-* 태그는 시야 구분이라 쓰지 않음). catalog_* 는 서버에서 직접.

## SM-03 (P3) — 설치 스크립트·유닛 예시 고정 경로, wheel SHA256SUMS
