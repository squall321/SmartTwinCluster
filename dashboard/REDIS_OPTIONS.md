# Redis yaml 옵션 — 풀버전 + 설명

`setup_redis_from_yaml.sh` 가 yaml 을 보고 Redis 를 (재)셋업할 때 읽는 **모든 옵션**.
여기 적은 값은 전부 **실제 redis.conf / sentinel.conf 에 반영**된다(yaml = 단일소스).
생략 시 각 항목의 **기본값**이 적용된다.

---

## 풀버전 yaml (복사해서 운영 my_*.yaml 에)

```yaml
# ============================================================================
# Redis Configuration (Primary + Replica + Sentinel HA)
# ============================================================================
redis:
  enabled: true               # [읽힘] Redis 사용 여부
  type: sentinel              # [읽힘] sentinel | standalone
                              #   sentinel  = controllers[0]=Primary, 나머지=Replica, 전노드 Sentinel
                              #   standalone= 단일 Redis (replica/sentinel 없음)

  options:                    # 튜닝 옵션 — 전부 redis.conf/sentinel.conf 에 반영됨
    # ---- 메모리 ----
    maxmemory: 4gb            # [읽힘] 최대 메모리. 초과 시 maxmemory_policy 로 제거.
                              #   기본값(생략 시): 무제한. 단위 mb/gb.
    maxmemory_policy: allkeys-lru
                              # [읽힘] 메모리 초과 시 키 제거 정책. 기본 allkeys-lru.
                              #   allkeys-lru   : 전체 키 중 LRU(가장 오래 안 쓴 것) 제거 — 캐시용 권장
                              #   volatile-lru  : TTL 있는 키만 LRU 제거
                              #   allkeys-lfu   : 전체 키 중 LFU(가장 적게 쓴 것) 제거
                              #   noeviction    : 제거 안 함, 메모리 차면 쓰기 거부(데이터 유실 방지)

    # ---- 영속성 (AOF: append-only file) ----
    appendonly: yes          # [읽힘] AOF 영속성. 기본 yes. 모든 쓰기를 파일에 기록 → 재시작 후 복구.
    appendfsync: everysec    # [읽힘] AOF 디스크 동기화 주기. 기본 everysec.
                              #   always   : 매 쓰기마다 fsync — 가장 안전, 가장 느림
                              #   everysec : 1초마다 fsync — 균형(권장), 최대 1초 데이터 손실
                              #   no       : OS 에 맡김 — 가장 빠름, 손실 위험 큼
    save: "900 1 300 10 60 10000"
                              # [읽힘] RDB 스냅샷 규칙 "초 변경수 ...". 기본(생략 시) Redis 기본값 유지.
                              #   예: 900초내 1개 변경 OR 300초내 10개 OR 60초내 10000개 변경 시 저장.
                              #   "" (빈값) 으로 두면 RDB 스냅샷 비활성(AOF 만 사용).

    # ---- 연결 ----
    maxclients: 10000        # [읽힘] 동시 클라이언트 최대 수. 기본 10000.
    timeout: 0               # [읽힘] idle 클라이언트 끊기까지 초. 기본 0(안 끊음).
    tcp_keepalive: 300       # [읽힘] TCP keepalive 초. 기본 300. 죽은 연결 감지.

    # ---- Sentinel (type: sentinel 일 때만) ----
    sentinel_port: 26379     # [읽힘] Sentinel 리스닝 포트. 기본 26379. 노드간 개방 필요.
    master_name: mymaster    # [읽힘] 모니터링할 master 이름. 기본 mymaster.
                              #   ★ 클라이언트의 environment.REDIS_MASTER_NAME 과 반드시 일치 ★
    quorum: 2                # [읽힘] failover 동의 정족수. 기본(생략 시) 노드수/2+1 자동.
                              #   3노드면 2 = 과반. sentinel 2개 이상 동의해야 failover.
    down_after_ms: 5000      # [읽힘] master 무응답 N ms 면 down 판정. 기본 5000(5초).
    failover_timeout_ms: 10000
                              # [읽힘] failover 타임아웃 ms. 기본 10000(10초).
    parallel_syncs: 1        # [읽힘] failover 후 새 master 와 동시 재동기화할 replica 수.
                              #   기본 1 (한 번에 1개씩 — 동기화 중 서비스 영향 최소).

# ============================================================================
# environment — 클라이언트(대시보드)가 읽는 값
# ============================================================================
environment:
  REDIS_PASSWORD: "SmartTwinCluster321!"   # [읽힘] Redis 비번 (requirepass/masterauth/sentinel auth-pass 공용)
  REDIS_SENTINEL_HOSTS: "10.179.100.25:26379,10.179.100.24:26379,10.179.100.50:26379"
                                           # [읽힘] 있으면 클라가 Sentinel 로 연결, 없으면 단일 Redis
  REDIS_MASTER_NAME: "mymaster"            # [읽힘] master_name 과 일치해야 함

# ============================================================================
# nodes — 어느 노드가 Redis 인지 (이미 설정돼 있음)
# ============================================================================
nodes:
  controllers:
    - { ip_address: 10.179.100.25, services: { redis: true } }  # → Primary (services.redis:true 첫 노드)
    - { ip_address: 10.179.100.24, services: { redis: true } }  # → Replica
    - { ip_address: 10.179.100.50, services: { redis: true } }  # → Replica
```

---

## 옵션 위치 — 어디 둬도 읽힘 (폴백 순서)

`setup_redis_from_yaml.sh` 는 각 옵션을 아래 순서로 찾아 **처음 발견한 값**을 쓴다:

```
redis.options.<키>  →  redis.<키>  →  redis.cluster.<키>  →  redis.sentinel.<키>
```

따라서 기존 `redis.cluster:` 아래 `maxmemory: 4gb` 가 있으면 **옮기지 않아도** 그대로 적용된다.
새로 쓸 때는 `redis.options:` 아래로 모으는 걸 권장(type 무관하게 일관).

---

## 자동 결정 (yaml 에 안 써도 됨)

| 항목 | 결정 방식 |
|------|-----------|
| Primary 노드 | `services.redis:true` 인 **첫 controller** |
| Replica 노드 | 나머지 redis 노드 |
| requirepass / masterauth | `environment.REDIS_PASSWORD` |
| bind / protected-mode | `0.0.0.0` / `no` (멀티노드 접근용, requirepass 로 보호) |
| cluster-enabled | `no` (sentinel/standalone 이므로) |
| sentinel announce-ip | 각 노드 자기 IP |

`quorum` 만 yaml 로 덮어쓸 수 있고(생략 시 자동), 나머지 자동 항목은 토폴로지에서 결정된다.

---

## 표: 옵션별 한눈에

| yaml 옵션 | 기본값 | redis.conf/sentinel.conf 지시어 |
|-----------|--------|--------------------------------|
| `maxmemory` | 무제한 | `maxmemory` |
| `maxmemory_policy` | allkeys-lru | `maxmemory-policy` |
| `appendonly` | yes | `appendonly` |
| `appendfsync` | everysec | `appendfsync` |
| `save` | Redis 기본 | `save` |
| `maxclients` | 10000 | `maxclients` |
| `timeout` | 0 | `timeout` |
| `tcp_keepalive` | 300 | `tcp-keepalive` |
| `sentinel_port` | 26379 | sentinel `port` |
| `master_name` | mymaster | `sentinel monitor <name>` |
| `quorum` | N/2+1 | `sentinel monitor ... <quorum>` |
| `down_after_ms` | 5000 | `sentinel down-after-milliseconds` |
| `failover_timeout_ms` | 10000 | `sentinel failover-timeout` |
| `parallel_syncs` | 1 | `sentinel parallel-syncs` |

전체 적용 순서는 [REDIS_SENTINEL.md](REDIS_SENTINEL.md) 참고.
