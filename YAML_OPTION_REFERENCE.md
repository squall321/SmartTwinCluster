# YAML 옵션 위치 레퍼런스 — 스크립트 호환표

`my_multihead_cluster*.yaml` 작성 시 **스크립트가 어디서 어떤 키를 읽는지** 정리.
새 YAML 작성하거나 기존 YAML 마이그레이션 시 이 문서 참조.

---

## 1. SAML 사용자 (가장 흔한 mismatch)

### 스크립트 읽기 위치
[`cluster/setup/phase5_web.sh`](cluster/setup/phase5_web.sh) `setup_saml_idp_users()` — 3개 경로 호환:
1. `web_services.saml.users` (권장)
2. `saml.test_users` (옛 스키마, 자동 인식)
3. `saml.users` (옛 스키마, 자동 인식)

### 권장 (신규 YAML)

```yaml
web_services:
  saml:
    users:
      - username: admin
        password: "강한비밀번호"
        email: "admin@hpc.local"
        groups: ["HPC-Admins"]
      - username: dxuser
        password: "비번"
        email: "dxuser@hpc.local"
        groups: ["DX-Users"]
```

### 옛 위치 (`my_multihead_cluster_346.yaml` 같은 형식)

`roles` → `groups` 자동 매핑됨:

```yaml
saml:
  test_users:
    - username: koopark
      password: "Soseks314!"
      email: koopark@hpc.local
      roles: [admin, user]     # → HPC-Admins, DX-Users
```

| `roles` 값 | 매핑되는 `groups` |
|------------|-------------------|
| `admin` | `HPC-Admins` |
| `user` | `DX-Users` |
| `cae` | `CAEG-Users` |

---

## 2. SSO 설정

### 스크립트 읽기 위치
[`dashboard/auth_portal_4430/generate_sso_env.py`](dashboard/auth_portal_4430/generate_sso_env.py): **최상위 `sso`**

```yaml
sso:
  enabled: false                # SSO 끄면 mock 인증
  type: saml                    # saml | oidc
  saml:
    idp_metadata_url: ""
    idp:
      entity_id: ""
      sso_url: ""
      slo_url: ""
      certificate: ""
    sp:
      entity_id: "hpc-dashboard"
  oidc:
    issuer: ""
    client_id: ""
    client_secret: ""
    scopes: [openid, profile, email, groups]
  attribute_mapping:
    username: uid
    email: mail
    groups: memberOf
  group_permissions:
    HPC-Admins: [dashboard, cae, vnc, app, admin]
    DX-Users:   [dashboard, vnc, app]
    CAEG-Users: [dashboard, cae, vnc, app]
```

❌ `web_services.sso.*` 에 넣으면 무시됨. 반드시 최상위 `sso:`.

---

## 3. 외부 접속 IP / 도메인

### 스크립트 읽기 위치
- [`dashboard/start_all.sh`](dashboard/start_all.sh): `access.public_url` → `public_url` → `hostname -I`
- [`dashboard/start_production.sh`](dashboard/start_production.sh): `web.public_url`
- 인증서 CN 도 이 값 사용

### 권장 (모두 호환)

```yaml
# 최상위 (start_all.sh 가 인식)
public_url: "10.198.143.130"

# web.* (start_production.sh 등 호환)
web:
  public_url: "10.198.143.130"
  ssl:
    enabled: true
    domain: ""              # 정식 도메인 (Let's Encrypt)
    email: ""
```

---

## 4. Slurm 파티션

### 스크립트 읽기 위치
[`phase5_web.sh`](cluster/setup/phase5_web.sh): `slurm_config.partitions` → `slurm.partitions` (fallback)

### 권장

```yaml
slurm_config:
  partitions:
    - name: compute
      nodes: "icn401-[0101-0411]-h[01-12]"
      default: true
      max_time: "infinite"
    - name: viz
      nodes: "viz-node[001-002]"
      max_time: "24:00:00"
```

---

## 5. 노드 정의

### 스크립트 읽기 위치
[`cluster/setup/phase*.sh`, `cluster/start_multihead.sh`, `cluster/check_all_nodes.py`]: 최상위 `nodes`

```yaml
nodes:
  controllers:
    - hostname: icn401-0401-h06
      ip_address: 10.228.4.74
      ssh_user: koopark           # 컨트롤러 간 SSH 계정
      priority: 100               # keepalived VIP priority
      vip_owner: true             # MASTER (1대만 true)
      services:
        slurmctld: true
        slurmdbd: true
        mariadb: true
        glusterd: true
        keepalived: true
        nginx: true
        redis: true

  compute_nodes:
    - hostname: icn401-0101-h01
      ip_address: 10.179.100.11
      ssh_user: stcx              # 컴퓨트 배포 계정 (배포 후 slurmd 운영)
      node_type: compute
      gpu: false

  viz_nodes:                       # 옵션 (viz 파티션용)
    - hostname: viz-node001
      ip_address: 10.179.100.201
      ssh_user: stcx
      node_type: viz
      gpu: true
```

### 필드 주의

| 필드 | 필수 | 비고 |
|------|------|------|
| `ssh_user` | ✓ | 노드 접속 계정. 권장: controller=koopark, compute=stcx |
| `ip_address` | ✓ | 내부 클러스터 IP |
| `priority` | controller만 | keepalived VRRP 우선순위 |
| `vip_owner` | controller만 | true=MASTER, false=BACKUP |
| `node_type` | compute_nodes | compute / viz |

---

## 6. SSH 비밀번호 (sshpass fallback)

### 스크립트 읽기 위치
[`cluster/utils/ssh_helpers.sh`](cluster/utils/ssh_helpers.sh): `cluster_info.ssh_password`

```yaml
cluster_info:
  name: "my-cluster"
  domain: "hpc.local"
  admin_user: "koopark"
  ssh_password: "비번"     # 키 인증 실패 시 sshpass로 fallback
```

> 평문이라 `chmod 600 my_multihead_cluster*.yaml`. git 커밋 금지.

---

## 7. Redis

### 스크립트 읽기 위치
[`dashboard/*/start.sh`, `phase2_redis.sh`]: 최상위 `redis`

```yaml
redis:
  host: localhost
  port: 6379
  password: ""        # 비워두면 인증 없음
  db: 0
```

---

## 8. 리눅스 사용자 / UID

### 스크립트 읽기 위치
[`phase*.sh`]: 최상위 `users`

```yaml
users:
  admin_user: koopark
  slurm_user: slurm
  slurm_uid: 64001
  slurm_gid: 64001
  munge_user: munge
  munge_uid: 502
  munge_gid: 502
  cluster_users:
    - username: hpcuser1
      uid: 10001
      gid: 10001
      shell: /bin/bash
      home: /home/hpcuser1
      groups: [users, hpc]
```

---

## 9. 환경변수 / 시크릿

### 스크립트 읽기 위치
[`dashboard/auth_portal_4430/generate_sso_env.py`]: 최상위 `environment`

```yaml
environment:
  debug: false
  secret_key: "긴-랜덤-문자열-32자이상"
  jwt_secret_key: "JWT-시크릿"
  jwt_expiration_hours: 8
```

---

## 10. GlusterFS

### 스크립트 읽기 위치
[`phase3_slurm.sh`, others]: 최상위 `shared_storage.glusterfs`

```yaml
shared_storage:
  glusterfs:
    enabled: true
    mount_point: /mnt/gluster
    server: 10.228.132.74     # primary controller IP
    volume: shared_data
    autofs_timeout: 300       # 5분 idle 후 unmount
```

---

## 11. 컨테이너 (Apptainer)

### 스크립트 읽기 위치
[`phase8_containers.sh`]: 최상위 `container_support.apptainer`

```yaml
container_support:
  apptainer:
    enabled: true
    version: "1.5.0"
    images:
      - name: "compute-base"
        path: /opt/apptainers/compute-base.sif
```

---

## 12. Keepalived VIP & 방화벽

### 스크립트 읽기 위치
[`phase4_keepalived` or `phase3_slurm`]: 최상위 `network`

```yaml
network:
  cluster_network: 10.228.0.0/16
  compute_network: 10.179.100.0/24
  vip:
    address: 10.179.100.100     # 내부 클러스터용 VIP (외부 X)
    netmask: 24
    interface: ens18
    vrrp_router_id: 51
    auth_password: "vrrp_password"
  firewall:
    enabled: true
    ports:
      slurmd: 6818
      slurmctld: 6817
      slurmdbd: 6819
      auth_backend: 4430
      auth_frontend: 4431
      dashboard: 3010
      backend: 5010
      websocket: 5011
      https: 443
      http: 80
```

---

## 13. 작성 체크리스트

새 YAML 작성 시 누락 점검:

```
☐ cluster_info.{name, domain, admin_user, ssh_password}
☐ nodes.{controllers, compute_nodes, viz_nodes}    각 ssh_user 명시
☐ network.{cluster_network, vip, firewall}
☐ shared_storage.glusterfs.{server, mount_point, volume}
☐ database (mariadb 설정)
☐ redis.{host, port, password, db}
☐ slurm_config.partitions                          ← slurm.partitions 아님!
☐ web.public_url 또는 최상위 public_url            ← NAT IP/도메인
☐ web_services.saml.users 또는 saml.test_users    ← 호환
☐ sso.{enabled, type, saml/oidc, group_permissions}  ← 최상위
☐ users.{admin_user, slurm_*, cluster_users}
☐ environment.{secret_key, jwt_secret_key}
☐ container_support.apptainer
```

---

## 14. 검증 스크립트

```bash
# YAML 문법 + 필수 키 일괄 점검
python3 << 'PY'
import yaml, sys, os
path = 'my_multihead_cluster.yaml'   # 본인 YAML 경로로
c = yaml.safe_load(open(path))

def get(keys, default=None):
    cur = c
    for k in keys.split('.'):
        if not isinstance(cur, dict): return default
        cur = cur.get(k, default)
    return cur

checks = {
    'cluster_info.domain': get('cluster_info.domain'),
    'cluster_info.ssh_password': '<set>' if get('cluster_info.ssh_password') else 'MISSING',
    'nodes.controllers count': len(get('nodes.controllers') or []),
    'nodes.compute_nodes count': len(get('nodes.compute_nodes') or []),
    'sso.enabled': get('sso.enabled'),
    'sso.group_permissions': list((get('sso.group_permissions') or {}).keys()),
    'SAML users (any path)': len(
        (get('web_services.saml.users') or get('saml.test_users') or get('saml.users') or [])
    ),
    'slurm_config.partitions': len(get('slurm_config.partitions') or get('slurm.partitions') or []),
    'public_url (any path)':
        get('access.public_url') or get('public_url') or get('web.public_url') or 'MISSING',
    'redis.host': get('redis.host'),
    'shared_storage.glusterfs.server': get('shared_storage.glusterfs.server'),
    'environment.secret_key': '<set>' if get('environment.secret_key') else 'MISSING',
}
for k, v in checks.items():
    mark = '❌' if v in (None, 'MISSING', 0, []) else '✓'
    print(f"  {mark} {k}: {v}")
PY
```

---

## 15. 향후 변경 정책

새 스크립트가 다른 YAML 키 위치를 기대하게 되면:

1. **이 문서 즉시 갱신** — 해당 섹션에 변경/추가
2. **스크립트도 옛 위치 호환 fallback** 추가:
   ```python
   value = config.get('new_path') or config.get('old_path')
   ```
3. **변경 commit 메시지에 명시**: "YAML 키 위치 변경: old → new"

이렇게 하면 여러 형식의 YAML이 공존해도 깨지지 않음.
