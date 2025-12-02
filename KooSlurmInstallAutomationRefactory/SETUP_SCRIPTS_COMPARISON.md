# Setup 스크립트 비교 가이드

## 개요

이 프로젝트에는 **두 가지 완전 자동화 스크립트**가 있습니다:

1. **setup_cluster_full.sh** - 기존 단일 컨트롤러 클러스터
2. **setup_cluster_full_multihead.sh** - 신규 멀티헤드 클러스터 (N중화)

## 상세 비교

### 1. setup_cluster_full.sh (기존)

**용도**: 단일 컨트롤러 + 계산 노드 클러스터 구성

**사용 설정 파일**: `my_cluster.yaml`

**설치 항목**:
- ✅ Python 가상환경
- ✅ YAML 검증
- ✅ SSH 키 설정 및 /etc/hosts
- ✅ RebootProgram 설정 (웹 재부팅 기능)
- ✅ Munge 인증
- ✅ Slurm 23.11.x + cgroup v2 (컨트롤러)
- ✅ systemd 서비스 파일
- ✅ slurmdbd (Accounting)
- ✅ 계산 노드 Slurm 배포
- ✅ 설정 파일 배포
- ✅ Slurm 서비스 시작
- ✅ PATH 영구 설정
- ✅ MPI 라이브러리 (선택)
- ✅ Apptainer 동기화 (선택)

**특징**:
- 단일 컨트롤러 아키텍처
- 전통적인 HPC 클러스터 구성
- slurmdbd를 통한 Accounting 지원
- QoS (Quality of Service) 기능

**실행 방법**:
```bash
sudo ./setup_cluster_full.sh
```

**실행 위치**: 컨트롤러 노드 1개

---

### 2. setup_cluster_full_multihead.sh (신규)

**용도**: 멀티 컨트롤러 (N중화) + 계산 노드 클러스터 구성

**사용 설정 파일**: `my_multihead_cluster.yaml`

**설치 항목**:

**Part 1: 기본 시스템 설정**
- ✅ Python 가상환경
- ✅ YAML 검증 (멀티헤드 스키마)
- ✅ SSH 키 설정 (모든 컨트롤러 간)
- ✅ /etc/hosts 설정 (모든 컨트롤러)
- ✅ Munge 인증
- ✅ Slurm 23.11.x + cgroup v2
- ✅ systemd 서비스 파일
- ✅ PATH 영구 설정

**Part 2: 멀티헤드 클러스터 서비스** (cluster/start_multihead.sh 호출)
- ✅ Phase 0: 사전 준비 (패키지, 네트워크)
- ✅ Phase 1: GlusterFS 분산 스토리지 (3-way 복제)
- ✅ Phase 2: MariaDB Galera 클러스터 (멀티 마스터)
- ✅ Phase 3: Redis 클러스터/센티넬
- ✅ Phase 4: Slurm 멀티 마스터
- ✅ Phase 5: Keepalived VIP 관리 (VRRP)
- ✅ Phase 6: 웹 서비스 (8개)
  - Frontend: Dashboard, Monitoring, Admin Portal
  - Backend: Auth, Job API, File, Metrics
  - Realtime: WebSocket, File WebSocket
- ✅ Phase 7: 검증 및 헬스체크

**특징**:
- N중화 아키텍처 (모든 컨트롤러가 모든 역할 수행)
- 고가용성 (HA) - 단일 장애점 없음
- VIP 기반 자동 Failover
- 분산 스토리지 (GlusterFS)
- 멀티 마스터 데이터베이스 (Galera)
- 프로덕션급 웹 서비스 스택

**실행 방법**:
```bash
# 1. YAML 파일 편집 (environment 섹션에서 비밀번호 설정)
vim my_multihead_cluster.yaml

# 2. 파일 권한 설정
chmod 600 my_multihead_cluster.yaml

# 3. Controller 1에서 실행 (Bootstrap)
sudo ./setup_cluster_full_multihead.sh

# 5분 대기

# 4. Controller 2에서 실행
sudo ./setup_cluster_full_multihead.sh

# 5분 대기

# 5. Controller 3에서 실행
sudo ./setup_cluster_full_multihead.sh
```

**참고**: 환경변수 설정 불필요! YAML에서 자동 로드됩니다.

**실행 위치**: 각 컨트롤러 노드에서 순차적으로 실행

---

## 비교표

| 항목 | setup_cluster_full.sh | setup_cluster_full_multihead.sh |
|------|----------------------|--------------------------------|
| **설정 파일** | my_cluster.yaml | my_multihead_cluster.yaml |
| **컨트롤러 수** | 1개 (단일) | N개 (3개 권장) |
| **고가용성 (HA)** | ❌ 없음 | ✅ 완전 HA |
| **GlusterFS** | ❌ | ✅ 3-way 복제 |
| **MariaDB** | 단일 인스턴스 | ✅ Galera 멀티 마스터 |
| **Redis** | ❌ | ✅ 클러스터/센티넬 |
| **Slurm** | 단일 slurmctld | ✅ 멀티 slurmctld |
| **VIP** | ❌ | ✅ Keepalived VRRP |
| **웹 서비스** | ❌ | ✅ 8개 서비스 |
| **Nginx** | ❌ | ✅ 리버스 프록시 |
| **SSL/TLS** | ❌ | ✅ Let's Encrypt |
| **slurmdbd** | ✅ 선택 설치 | ❌ (멀티헤드 특성상 불필요) |
| **MPI** | ✅ 선택 설치 | ❌ (별도 설치 필요) |
| **Apptainer** | ✅ 선택 배포 | ❌ (별도 배포 필요) |
| **환경변수 필요** | ❌ | ❌ (YAML에서 자동 로드) ⭐ |
| **설정 방법** | 대화형 프롬프트 | YAML 파일 편집 |
| **실행 횟수** | 1회 (컨트롤러) | N회 (각 컨트롤러) |
| **예상 시간** | ~30분 | ~45분 (첫 컨트롤러), ~20분 (이후) |

---

## 선택 가이드

### setup_cluster_full.sh를 선택하세요:

✅ 단일 컨트롤러로 충분한 경우
✅ 고가용성이 필요 없는 경우
✅ 기존 시스템과 호환성이 중요한 경우
✅ QoS 및 Accounting 기능이 필요한 경우
✅ 간단한 구성을 원하는 경우

**예시 시나리오**:
- 연구실 소규모 클러스터
- 개발/테스트 환경
- 단일 관리자 운영

---

### setup_cluster_full_multihead.sh를 선택하세요:

✅ 고가용성 (HA)이 필수인 경우
✅ 단일 장애점(SPOF)을 제거하고 싶은 경우
✅ 프로덕션 환경에서 24/7 운영이 필요한 경우
✅ 웹 기반 관리 인터페이스가 필요한 경우
✅ 자동 Failover가 필요한 경우
✅ 분산 스토리지가 필요한 경우

**예시 시나리오**:
- 기업 프로덕션 HPC 클러스터
- 대학 공용 클러스터
- 상업용 컴퓨팅 서비스
- 미션 크리티컬 워크로드

---

## 마이그레이션 경로

### 단일 → 멀티헤드로 마이그레이션

기존에 `setup_cluster_full.sh`로 구성된 클러스터를 멀티헤드로 전환하려면:

**Option 1: 완전 재구성 (권장)**
```bash
# 1. 데이터 백업
# 2. 기존 클러스터 중지
# 3. 새로운 컨트롤러 노드 준비 (최소 3대)
# 4. my_multihead_cluster.yaml 작성
# 5. setup_cluster_full_multihead.sh 실행
```

**Option 2: 점진적 전환 (복잡)**
```bash
# 1. 기본 시스템 설정은 유지 (--skip-base)
sudo ./setup_cluster_full_multihead.sh --skip-base

# 2. 멀티헤드 서비스만 추가 설치
```

⚠️ **주의**: 마이그레이션은 복잡하며 다운타임이 발생합니다.

---

## 유틸리티 스크립트

두 방식 모두 다음 유틸리티를 사용할 수 있습니다:

### 공통
- `start_slurm_cluster.sh` - Slurm 서비스 시작
- `stop_slurm_cluster.sh` - Slurm 서비스 중지

### 멀티헤드 전용
- `cluster/start_multihead.sh` - 멀티헤드 클러스터 시작
- `cluster/stop_multihead.sh` - 멀티헤드 클러스터 중지
- `cluster/status_multihead.sh` - 클러스터 상태 확인
- `cluster/test_cluster.sh` - 자동화 테스트
- `cluster/utils/web_health_check.sh` - 웹 서비스 헬스체크

---

## 문제 해결

### setup_cluster_full.sh 문제

**Q: slurmdbd가 시작되지 않습니다**
```bash
# 로그 확인
sudo journalctl -u slurmdbd -n 50

# 설정 확인
sudo vim /usr/local/slurm/etc/slurmdbd.conf

# DbdHost가 올바른지 확인
sudo sed -i "s/DbdHost=.*/DbdHost=$(hostname -f)/" /usr/local/slurm/etc/slurmdbd.conf
sudo systemctl restart slurmdbd
```

**Q: 노드가 DOWN 상태입니다**
```bash
sinfo
scontrol update NodeName=node001 State=RESUME
```

---

### setup_cluster_full_multihead.sh 문제

**Q: 환경변수 로드 오류가 발생합니다**
```bash
# YAML 파일의 environment 섹션 확인
grep -A 10 "^environment:" my_multihead_cluster.yaml

# Python YAML 모듈 확인
python3 -c "import yaml; print('OK')"

# 없으면 설치
pip3 install pyyaml

# YAML 권한 확인
ls -l my_multihead_cluster.yaml
```

**Q: GlusterFS 볼륨이 생성되지 않습니다**
```bash
# 상태 확인
sudo gluster peer status
sudo gluster volume status

# 수동 생성
sudo gluster volume create data_volume replica 3 \
  server1:/data/gluster/data_volume/brick \
  server2:/data/gluster/data_volume/brick \
  server3:/data/gluster/data_volume/brick force
```

**Q: VIP가 할당되지 않습니다**
```bash
# Keepalived 상태 확인
sudo systemctl status keepalived

# VIP 확인
ip addr show | grep 192.168.1.100

# 로그 확인
sudo journalctl -u keepalived -n 50
```

---

## 참고 문서

- [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) - 멀티헤드 배포 가이드
- [QUICKSTART.md](QUICKSTART.md) - 빠른 시작 가이드
- [README_PHASE6.md](cluster/README_PHASE6.md) - 웹 서비스 상세
- [README_PHASE8.md](cluster/README_PHASE8.md) - 통합 오케스트레이션

---

## 요약

| 상황 | 권장 스크립트 |
|------|--------------|
| 소규모 연구실 클러스터 | setup_cluster_full.sh |
| 개발/테스트 환경 | setup_cluster_full.sh |
| 프로덕션 환경 | **setup_cluster_full_multihead.sh** |
| 고가용성 필요 | **setup_cluster_full_multihead.sh** |
| 웹 인터페이스 필요 | **setup_cluster_full_multihead.sh** |
| QoS/Accounting 필요 | setup_cluster_full.sh |
| 24/7 무중단 운영 | **setup_cluster_full_multihead.sh** |

---

**작성일**: 2025-10-27
**버전**: 1.0
