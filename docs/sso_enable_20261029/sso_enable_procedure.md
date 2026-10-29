# 운영 SSO 켜기 절차서 (icn401)

**읽는 사람** icn401 에서 SSO 를 켜는 운영자. **켤 시각은 사용자 결정**이다. 영향 조사는 [callers.md](callers.md).
**지금 상태** SSO 꺼짐 — 대시보드의 모든 요청이 토큰과 무관하게 `admin` 으로 통과한다. 남의 잡 파일이 열리고, 결과 귀환의 소유 검사(A)도 효과가 없다.
모든 명령은 icn401 헤드, 리포 루트 `$R` 기준.

## 0. 켜기 전 조건 — 하나라도 아니면 켜지 않는다

| # | 조건 | 확인 |
|---|---|---|
| 1 | **IdP 가 설정돼 있다.** 저장소의 운영 YAML 은 `sso.saml.idp.sso_url` 이 비어 있다 — 비어 있으면 아무도 로그인하지 못한다 | `python3 -c "import yaml;s=yaml.safe_load(open('$R/my_multihead_cluster.yaml'))['sso'];print(bool((s.get('saml') or {}).get('idp',{}).get('sso_url') or (s.get('oidc') or {}).get('issuer')))"` → `True` |
| 2 | 사용자 이름 = IdP `uid` = 이메일 @ 앞부분(사용자 확인 10-29) | `sso.attribute_mapping.username: uid` |
| 3 | 쓰는 사람의 그룹에 `dashboard` 권한 — 없으면 잡 제출·업로드·결과 조회가 403 | `sso.group_permissions` 의 HPC-Admins·DX-Users·CAEG-Users 는 모두 있음. 다른 그룹 사용자가 있으면 추가 |
| 4 | **걸린 DynaForge 예약이 없다** — 켜기 전 잡은 전부 `admin` 명의라 켠 뒤 일반 사용자 토큰으로 403 | DynaForge 쪽에 확인 |
| 5 | DynaForge 덱 업로드가 위임 토큰을 싣는다(KooRemapper 작업 중) · 운영 `HEAX_GATEWAY_SECRET` 이 들어가 있다 | [icn401_apply_check.md](icn401_apply_check.md) §3 의 11 → `204` |
| 6 | 화면 JWT 수정(`f267c127`)과 결과 귀환이 반영돼 있다 | icn401_apply_check.md §2 의 1 → `포함` |

## 1. 바꿀 것

```bash
# (1) YAML — start_production.sh 가 이것으로 nginx 정본 conf·saml_idp 기동을 정한다
sed -i.bak_$(date +%m%d) '/^sso:/,/^[^ ]/ s/^  enabled: false/  enabled: true/' $R/my_multihead_cluster.yaml
python3 -c "import yaml;print(yaml.safe_load(open('$R/my_multihead_cluster.yaml'))['sso']['enabled'])"   # → True

# (2) 인증 포털 env — YAML 의 sso 블록(IdP·속성·그룹 권한)으로 다시 만든다
cp $R/dashboard/auth_portal_4430/.env $R/dashboard/auth_portal_4430/.env.bak_$(date +%m%d) 2>/dev/null
python3 $R/dashboard/auth_portal_4430/generate_sso_env.py --config $R/my_multihead_cluster.yaml \
        --output $R/dashboard/auth_portal_4430/.env

# (3) 유닛 env — 셋업 때 YAML 값으로 박힌 SSO_ENABLED=false 다섯 개. 미들웨어는 env 를 YAML 보다 먼저 본다
for u in dashboard_backend auth_backend cae_backend cae_automation websocket_service; do
  f=/etc/systemd/system/$u.service; [ -f $f ] || continue
  sudo cp $f $f.bak_$(date +%m%d) && sudo sed -i 's/SSO_ENABLED=false/SSO_ENABLED=true/' $f
done
sudo systemctl daemon-reload
# EnvironmentFile(.env)가 Environment= 를 덮으므로 .env 안의 SSO_ENABLED 도 본다 — false 가 있으면 true 로
grep -n '^SSO_ENABLED' $R/dashboard/backend_5010/.env $R/dashboard/auth_portal_4430/.env 2>/dev/null

# (4) 반영 — nginx 정본 conf 를 auth-portal.conf 로 바꾸고(반대편은 .disabled_*), saml_idp 를 기동 대상에 넣는다
sudo ./dashboard/start_production.sh 2>&1 | tee /tmp/sso_on_$(date +%m%d_%H%M).log
```

## 2. 켠 직후 — SSO 꺼짐 시절 PAT 정리(필수)

PAT 는 발급 순간의 신원을 저장한다. SSO 꺼짐 동안 대시보드 'MCP 토큰' 화면에서 발급한 `kst_` 는 전부
**username `admin` · role `admin`** 으로 저장돼 있다 — 켠 뒤 그대로 두면 관리자 토큰이다.

```bash
DB="${DATABASE_PATH:-/home/koopark/web_services/backend/dashboard.db}"   # backend_5010/.env 의 DATABASE_PATH
sqlite3 "$DB" "SELECT id, username, role, name, created_at FROM personal_access_tokens WHERE username='admin' OR role='admin'"
# 목록을 보고 실제 관리자가 쓰는 것이 아니면 지운다(사용자는 SSO 로그인 뒤 다시 발급)
sqlite3 "$DB" "DELETE FROM personal_access_tokens WHERE username='admin'"
```

위임 창구가 낸 토큰(`위임: <client>`)은 실제 사용자 이름이라 그대로 둔다. Claude 클라이언트·게이트웨이 설정에 박힌 옛 `kst_`
(예: `~/.claude.json` 의 smarttwin)도 SSO 로그인 뒤 다시 발급해 바꾼다.

## 3. 켠 뒤 확인

| # | 명령 | 기대값 |
|---|---|---|
| 1 | `grep -n '→ SSO=' /tmp/sso_on_*.log \| tail -1` | `→ SSO=true → 정본 conf: auth-portal.conf` |
| 2 | `curl -s http://127.0.0.1:5010/api/auth/config` | `"sso_enabled":true` |
| 3 | `curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:5010/api/jobs/1/files` | `401`(토큰 없음) |
| 4 | `curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:5010/api/health` | `200`(헬스는 열려 있다) |
| 5 | 브라우저로 대시보드 접속 | IdP 로그인 → 대시보드. 잡 목록·로그 뷰어·다운로드 버튼(티켓)·노드 관리 동작 |
| 6 | 위임 토큰(icn401_apply_check §3 의 13) → `curl -H "Authorization: Bearer <kst_>" .../api/jobs/<본인 잡>/files` / `<남의 잡>` | `200` / `403` |
| 7 | 'MCP 토큰' 화면에서 새로 발급한 `kst_` 로 `curl -H "Authorization: Bearer <kst_>" http://127.0.0.1:5010/api/me` | 본인 username·실제 role |
| 8 | DynaForge 덱 업로드·결과 귀환 1건 | 업로드 200, 매니페스트 200 |

## 4. 되돌리기

켠 동안 생긴 잡은 실제 사용자 명의로 남지만, 끄면 다시 모두 `admin` 으로 열리므로 데이터는 잃지 않는다.

```bash
cp $R/my_multihead_cluster.yaml.bak_<날짜> $R/my_multihead_cluster.yaml          # 또는 enabled: true → false
cp $R/dashboard/auth_portal_4430/.env.bak_<날짜> $R/dashboard/auth_portal_4430/.env
for u in dashboard_backend auth_backend cae_backend cae_automation websocket_service; do
  f=/etc/systemd/system/$u.service; [ -f $f ] && sudo sed -i 's/SSO_ENABLED=true/SSO_ENABLED=false/' $f
done
sudo systemctl daemon-reload && sudo ./dashboard/start_production.sh   # → SSO=false → hpc-portal.conf
```

## 5. 켜도 남는 것(별도 과제)

- 인증 없는 쓰기 라우트 10개(callers.md §5)는 켜도 열려 있다.
- 게이트웨이의 smart-twin 두 항목은 헤더가 없다 — 사람별 위임은 포털이 보류 중(callers.md §3).
