# 도메인 전환 가이드 — YAML 수정 한 줄로 자동 적용

NAT IP 운영 → 사내 도메인 (예: `stcx.sec.samsung.net`) 전환 시 변경할 곳.
스크립트가 대부분 자동 처리하므로 **사용자가 직접 수정할 곳은 YAML 1~3 줄**.

---

## 1. 단계별 시나리오

| 단계 | 상황 | YAML 수정 |
|------|------|-----------|
| A | NAT IP만 사용 (현재) | `public_url: "10.198.143.130"` |
| B | 도메인 발급됨, 인증서 아직 | `public_url: "stcx.sec.samsung.net"` |
| C | 도메인 + 정식 인증서 모두 | + `ssl.cert_path`, `ssl.key_path` 채우기 |

각 단계에서 `start_all.sh` 한 번이면 자동 적용.

---

## 2. YAML 수정 (필수)

### 위치: `my_multihead_cluster.yaml` 의 `web:` 섹션

```yaml
web:
  # 단계별로 이 한 줄만 바꾸면 됨
  public_url: "10.198.143.130"
  # 단계 B → public_url: "stcx.sec.samsung.net"

  ssl:
    mode: self_signed
    domain: ""
    email: ""
    # 단계 C에서만 채움 (정식 인증서 받은 후)
    cert_path: ""    # 예: "/etc/ssl/certs/stcx.sec.samsung.net.crt"
    key_path:  ""    # 예: "/etc/ssl/private/stcx.sec.samsung.net.key"
```

---

## 3. 자동 처리되는 항목 (스크립트가 알아서)

`sudo ./dashboard/start_all.sh --config my_multihead_cluster.yaml` 실행 시:

| 항목 | 자동 처리 내용 |
|------|----------------|
| 도메인/IP 자동 판별 | 정규식 + `getent ahosts` 로 실제 IP 해석 |
| 자체서명 인증서 | CN=`public_url`, SAN=DNS+IP+localhost 모두 포함 |
| 정식 인증서 | `ssl.cert_path/key_path` 있으면 그것 사용 |
| nginx `server_name` | 도메인+실IP+`_` (default_server 유지) |
| 프론트엔드 `.env.production` | `VITE_PUBLIC_URL` 자동 작성 |
| auth_portal_4430 `.env` | `SAML_ACS_URL`, `SAML_SLS_URL`, `CORS_ALLOWED_ORIGINS`, `PUBLIC_URL` |
| auth_portal app.py redirect | `PUBLIC_URL` env 읽어서 절대/상대 URL 자동 |
| 프론트엔드 자동 재빌드 | `.env.production` 변경 감지하면 빌드 |
| 인증서 CN 불일치 감지 | `public_url` 바뀌면 자체 인증서 자동 재발급 |

---

## 4. 사용자가 직접 해야 할 일 (단계별)

### A → B (도메인 발급 후)

```bash
# 1. YAML 수정
vim my_multihead_cluster.yaml
# public_url: "stcx.sec.samsung.net"  로 변경

# 2. (옵션) hosts 등록 — DNS가 사내망에서 작동하기 전에 임시
sudo sh -c 'echo "10.198.143.130 stcx.sec.samsung.net" >> /etc/hosts'

# 3. 실행
git pull && sudo ./dashboard/start_all.sh --config my_multihead_cluster.yaml

# 4. 검증
sudo openssl x509 -in /etc/ssl/certs/nginx-selfsigned.crt -noout -ext subjectAltName
# DNS:stcx.sec.samsung.net, DNS:localhost, IP:10.198.143.130, IP:127.0.0.1
curl -kIL --noproxy "*" https://stcx.sec.samsung.net/auth_portal/
```

### B → C (인증서 발급 후)

```bash
# 1. 받은 인증서 파일 배치
sudo mkdir -p /etc/ssl/certs /etc/ssl/private
sudo cp received.crt /etc/ssl/certs/stcx.sec.samsung.net.crt
sudo cp received.key /etc/ssl/private/stcx.sec.samsung.net.key
sudo chmod 644 /etc/ssl/certs/stcx.sec.samsung.net.crt
sudo chmod 600 /etc/ssl/private/stcx.sec.samsung.net.key

# 2. YAML 의 ssl 섹션에 경로 추가
vim my_multihead_cluster.yaml
# ssl:
#   cert_path: "/etc/ssl/certs/stcx.sec.samsung.net.crt"
#   key_path:  "/etc/ssl/private/stcx.sec.samsung.net.key"

# 3. 실행
sudo ./dashboard/start_all.sh --config my_multihead_cluster.yaml
# → 자체서명 무시하고 정식 인증서 사용

# 4. 검증 — 브라우저 인증서 경고 없음
curl -IL https://stcx.sec.samsung.net/auth_portal/   # -k 불필요
```

---

## 5. SSO/SAML 활성화 (도메인 단계에서 같이)

`public_url` 이 도메인이면 SSO도 활성화 권장:

```yaml
sso:
  enabled: true
  type: saml
  saml:
    idp_metadata_url: "https://saml.samsung.com/idp/metadata"
    sp:
      entity_id: "stcx.sec.samsung.net"        # 도메인 또는 회사 규칙
  attribute_mapping:
    username: uid
    email: mail
    groups: memberOf
  group_permissions:
    HPC-Admins: [dashboard, cae, vnc, app, admin]
    DX-Users:   [dashboard, vnc, app]
    CAEG-Users: [dashboard, cae, vnc, app]
```

`SAML_ACS_URL` 등은 `start_all.sh` 가 `PUBLIC_URL` 기반으로 자동 작성. IdP 측에 등록할 SP metadata URL:
```
https://stcx.sec.samsung.net/auth/saml/metadata
```

---

## 6. 검증 한 줄

YAML 수정 후 어디까지 적용됐는지:

```bash
# 도메인 모드인지
grep public_url my_multihead_cluster.yaml

# 인증서 CN/SAN
sudo openssl x509 -in $(grep -E "ssl_certificate " /etc/nginx/sites-enabled/hpc-portal.conf | head -1 | awk '{print $2}' | tr -d ';') \
    -noout -subject -ext subjectAltName

# nginx server_name
grep server_name /etc/nginx/sites-enabled/hpc-portal.conf | head -3

# 프론트엔드 빌드 환경변수
cat dashboard/frontend_3010/.env.production 2>/dev/null
cat dashboard/auth_portal_4431/.env.production 2>/dev/null

# auth_portal_4430 SAML URL
grep -E "PUBLIC_URL|SAML_ACS|CORS_ALLOWED" dashboard/auth_portal_4430/.env

# 외부 접속 테스트 (서버 안 또는 PC)
curl -kIL --noproxy "*" https://stcx.sec.samsung.net/auth_portal/
curl -kIL --noproxy "*" https://10.198.143.130/auth_portal/    # IP 직접도 유지됨
```

---

## 7. 롤백 (도메인 → IP)

YAML 한 줄 되돌리면 모두 자동 롤백:

```yaml
public_url: "10.198.143.130"   # 다시 IP로
ssl:
  cert_path: ""                 # 정식 인증서도 사용 안 함
  key_path: ""
```

```bash
sudo ./dashboard/start_all.sh --config my_multihead_cluster.yaml
```

---

## 8. 영향 안 받는 것들 (참고)

다음은 도메인 변경과 무관 — 그대로 둬도 OK:
- 내부 노드 간 SSH (IP 기반)
- Slurm `NodeAddr` (IP)
- GlusterFS 마운트 서버 IP
- Redis localhost
- Munge 키 동기화 (IP)

---

## 9. 트러블슈팅

| 증상 | 원인 | 해결 |
|------|------|------|
| 브라우저 인증서 경고 | 자체서명 (단계 B) | 정상. 정식 인증서 적용 시 사라짐 |
| `Empty reply from server` | 회사 PAC가 도메인 미허용 | IRP 예외 신청, 또는 SSH 터널 |
| 도메인 접속 시 404 | `server_name` 매칭 안 됨 | `start_all.sh` 재실행 (server_name 자동 추가) |
| SAML 로그인 후 ERR | `SAML_ACS_URL` 옛 값 | `auth_portal_4430/.env` 확인, `start_all.sh` 가 자동 갱신 |
| 프론트가 옛 IP로 API 호출 | 빌드 캐시 | `sudo ./dashboard/start_all.sh --force-build` |
