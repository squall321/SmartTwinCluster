# SM-04 시험 — 호출자는 backend 가 PAT(kst_)로 푼 신원만 — SSO 꺼짐 admin·auth 없음·사람 아닌 이름·PAT 아닌 토큰은 거절
"""SSO 꺼진 backend 는 PAT 가 아니어도 전체 권한 admin 으로 풀어 줬다. caller_identity 는
토큰이 kst_ 이고 /api/me 의 auth 가 pat 일 때만 받는다. 가짜 backend 토큰은 conftest.TOKENS.
"""
from __future__ import annotations

import pytest

from conftest import USER


@pytest.mark.parametrize("token", ["kst_ssooff", "kst_noauth", "kst_root", "notapat"])
def test_non_pat_identities_are_refused(registry, run_as, token):
    out = run_as("my_jobs", {}, token=token)
    assert out["ok"] is False and "호출자 확인 실패" in out["reason"], out


def test_pat_identity_is_the_caller(registry, run_as):
    out = run_as("my_jobs", {})
    assert out["ok"] is True and out["caller"] == USER, out


@pytest.mark.parametrize("token,status", [("kst_user", 200), ("kst_ssooff", 401), ("kst_noauth", 401)])
def test_rest_verifier_accepts_only_pat_identities(backend, token, status):
    from smarttwin_mcp.rest import PatVerifier
    code, ident = PatVerifier(base_url=backend)(f"Bearer {token}")
    assert code == status and (ident is not None) == (status == 200), (code, ident)
