<!-- SM 묶음 체크리스트 -->
# 체크리스트 — SM-04 → 01 → 02 → 03 (2026-11-25)

- [x] 접수·차례 회신(hwaxportal-71), SM 커밋 없음 확인
- [x] worktree `feat/sm-security-1125`
- [x] SM-04 backend jwt_middleware 순서·auth 칸, /api/me auth
- [x] SM-04 MCP caller_identity — kst_·auth==pat·금지 이름 + REST PatVerifier 도 auth==pat
- [x] SM-04 시험 — backend tests/test_sm04_pat_before_sso_off.py 5건(전체 56 통과) · MCP tests/test_sm04_caller_identity.py 8건(전체 352 통과, 실패 3 은 main 과 같은 카탈로그 밀림)
- [ ] SM-04 병합·push·dashboard_backend 재시작 → smarttwin-mcp 재시작 → 확인
- [ ] SM-01
- [ ] SM-02
- [ ] SM-03
- [ ] hwaxportal-71 에 착지 넷(push 해시·Drive·SIF sha256/캐시 열쇠·운영 수작업)
