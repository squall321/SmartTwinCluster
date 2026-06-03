# Redis Sentinel (HA) 전환 가이드

3노드 Redis 를 **1 Primary + 2 Replica + 3 Sentinel** 로 구성한다.
(기존 깨진 cluster — `cluster_state:fail`, `slots_assigned:0` — 를 대체)

## 왜 Sentinel 인가
- 데이터 규모가 작아(세션 수십~수백 키, <10MB) **샤딩(cluster) 불필요**
- 모든 클라이언트가 단일 `redis.Redis` → cluster 면 코드 대수술 필요, **Sentinel 은 연결부만 분기**
- 3노드를 **HA(자동 failover)** 에 제대로 활용 (cluster `replicas:0` 은 HA 도 없었음)

---

## 1. yaml 수정 (운영서버의 my_*.yaml)

**코드가 실제로 읽는 yaml 키는 4개뿐**이다. sentinel 세부값(quorum/master/포트)은
스크립트가 노드 수로 자동 계산하므로 yaml 에 적지 않아도 된다.

| yaml 키 | 용도 | 자동결정값 |
|---------|------|-----------|
| `redis.type` | sentinel / standalone 선택 | — |
| `environment.REDIS_PASSWORD` | Redis 비번 | — |
| `nodes.controllers[].services.redis: true` | Redis 노드 지정 | controllers[0]=master, 나머지=replica |
| `environment.REDIS_SENTINEL_HOSTS` | 클라이언트 Sentinel 연결 | (없으면 단일모드) |
| `environment.REDIS_MASTER_NAME` | master 이름 | 기본 `mymaster` |

### (A) `redis:` 섹션 — `type` 만 `sentinel` 로

**Before:**
```yaml
redis:
  enabled: true
  type: cluster
  cluster:
    maxmemory: 4gb
    appendonly: yes
    ...
```

**After:**
```yaml
redis:
  enabled: true
  type: sentinel        # ← cluster 에서 이것만 바꾸면 됨
  options:              # 튜닝 옵션(선택) — setup_redis 스크립트가 redis.conf 에 반영
    maxmemory: 4gb
    maxmemory_policy: allkeys-lru
    appendonly: yes
    appendfsync: everysec
```
> **튜닝 옵션은 어디 둬도 읽힘** (폴백 순서: `redis.options.X` → `redis.X` →
> `redis.cluster.X` → `redis.sentinel.X`). 기존 `cluster:` 아래 값도 그대로 적용되므로
> 굳이 옮기지 않아도 됨. 생략 시 기본값(maxmemory 무제한, allkeys-lru, appendonly yes,
> everysec) 적용. **이 옵션들은 이제 실제 redis.conf 에 반영된다(yaml=단일소스).**
> master/replica/quorum 은 스크립트가 자동 결정:
> - **master = controllers[0]** (services.redis:true 첫 노드 = 10.179.100.25)
> - **replica = 나머지** redis 노드 (10.179.100.24, 10.179.100.50)
> - **quorum = 노드수/2+1 = 2**, sentinel 포트 26379, master_name `mymaster`

### (B) `environment:` 섹션 — 클라이언트가 읽을 키 2개 추가

```yaml
environment:
  ...
  REDIS_PASSWORD: "SmartTwinCluster321!"     # 운영 실제 Redis 비번 (이미 있음, 값 확인)
  REDIS_SENTINEL_HOSTS: "10.179.100.25:26379,10.179.100.24:26379,10.179.100.50:26379"
  REDIS_MASTER_NAME: "mymaster"              # (생략 가능 — 기본 mymaster)
  ...
```
> `REDIS_SENTINEL_HOSTS` 가 **있으면** 클라이언트가 Sentinel 로 연결,
> **없으면** 기존 단일 Redis(`REDIS_HOST`)로 동작 (하위호환 — 개발머신은 안 건드림).
> 노드 IP/포트(26379)는 운영서버 redis 노드에 맞게 작성.

---

## 2. Redis 노드 구성 (각 노드에서 실행)

전체 재설치 없이 **Redis 만** yaml 보고 (재)셋업. master 노드부터:

```bash
cd ~/claude/KooSlurmInstallAutomationRefactory

# 1) Primary 노드(.25)에서
sudo ./cluster/setup/setup_redis_from_yaml.sh --config my_multihead_cluster.yaml --reset

# 2) Replica 노드(.24, .50) 각각에서
sudo ./cluster/setup/setup_redis_from_yaml.sh --config my_multihead_cluster.yaml --reset
```
> `--reset` = 기존 cluster 잔재(cluster-enabled yes, nodes.conf) 정리 후 전환.
> `--dry-run` 으로 먼저 확인 가능.

**26379 포트 개방** (노드간 sentinel 통신):
```bash
sudo ufw allow from 10.179.100.0/24 to any port 26379 proto tcp   # 각 노드
```

---

## 3. 클라이언트 .env 갱신 + 재시작

```bash
# yaml environment → .env 에 REDIS_SENTINEL_HOSTS 반영
./dashboard/regenerate_env_from_yaml.sh    # (REDIS_PASSWORD 갱신)
# 또는 phase5_web 재실행 시 자동 반영됨

sudo systemctl restart dashboard_backend auth_backend websocket_service
```
> 클라이언트는 `.env` 의 `REDIS_SENTINEL_HOSTS` 를 보고 자동으로 Sentinel 모드.

---

## 4. 검증

```bash
PW='SmartTwinCluster321!'

# Sentinel quorum (각 노드)
redis-cli -p 26379 -a "$PW" --no-auth-warning SENTINEL ckquorum mymaster
# → "OK 3 usable Sentinels..."

# master + replica 수
redis-cli -p 26379 -a "$PW" --no-auth-warning SENTINEL master mymaster | grep -E 'ip|num-slaves|num-other-sentinels'
# → ip .25, num-slaves 2, num-other-sentinels 2

# 복제 상태 (master 노드)
redis-cli -h 10.179.100.25 -a "$PW" --no-auth-warning INFO replication | grep -E 'role|connected_slaves'
# → role:master, connected_slaves:2

# failover 테스트
redis-cli -p 26379 -a "$PW" --no-auth-warning SENTINEL failover mymaster
# ~10초 후 SENTINEL master mymaster 의 ip 가 바뀜 (자동 승격 확인)
```

그 다음 `sudo ./dashboard/start_production.sh` → `[11]` 토큰 발급 + VNC 잡 정상.

---

## 롤백 (문제 시 단일 Redis 로)

```bash
# yaml environment 에서 REDIS_SENTINEL_HOSTS 줄 제거(또는 빈값)
# → 클라이언트가 단일 redis.Redis(REDIS_HOST) 로 복귀 (코드 분기의 else)
sudo ./cluster/setup/setup_redis_from_yaml.sh --config my_*.yaml   # type:standalone 으로 바꾼 뒤
sudo systemctl restart dashboard_backend auth_backend websocket_service
```
모든 클라이언트 수정은 `if REDIS_SENTINEL_HOSTS: ... else: <기존코드>` 라
환경변수만 비우면 기존 동작으로 즉시 복귀.
