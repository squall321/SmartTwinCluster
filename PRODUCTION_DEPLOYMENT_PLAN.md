# Production Deployment Plan

## 목표
- Flask dev 서버 → Gunicorn WSGI 서버로 전환
- 리소스 제한 설정 (CPU, Memory)
- **setup_cluster_multihead 기반 3-4대 PC N중화 배포**
- 오프라인 패키지 준비 (인터넷 없는 환경 대비)
- 설정 파일 기반 관리 (YAML)

---

## Phase 1: 오프라인 패키지 준비 ✅ (진행 중)

### 1.1 Gunicorn 오프라인 패키지 다운로드
- [ ] 각 백엔드의 requirements.txt에 gunicorn 추가
- [ ] 오프라인 패키지 다운로드
  ```bash
  pip download -r requirements.txt -d packages/
  ```
- [ ] 패키지 구조:
  ```
  offline_packages/
  ├── auth_backend/
  │   └── packages/
  ├── dashboard_backend/
  │   └── packages/
  ├── cae_backend/
  │   └── packages/
  └── cae_automation/
      └── packages/
  ```

### 1.2 설정 파일 준비
- [x] `dashboard/config/gunicorn_template.yaml` 생성
- [x] `dashboard/config/resource_limits.yaml` 생성
- [ ] 각 백엔드별 gunicorn 설정 생성
  - `auth_portal_4430/gunicorn_config.py`
  - `backend_5010/gunicorn_config.py`
  - `kooCAEWebServer_5000/gunicorn_config.py`
  - `kooCAEWebAutomationServer_5001/gunicorn_config.py`

### 1.3 requirements.txt 업데이트
- [ ] auth_portal_4430/requirements.txt
- [ ] backend_5010/requirements.txt
- [ ] kooCAEWebServer_5000/requirements.txt
- [ ] kooCAEWebAutomationServer_5001/requirements.txt

---

## Phase 2: start.sh 옵션 추가 (빌드 스크립트)

### 2.1 start.sh 수정
- [ ] `./start.sh --dev` → Development mode (Flask dev server)
- [ ] `./start.sh --production` → Production mode (Gunicorn)
- [ ] `./start.sh --help` → 도움말

### 2.2 dashboard/start_dev.sh 생성
- [ ] `start_complete.sh` → `start_dev.sh` 이름 변경
- [ ] Flask dev 서버로 실행

### 2.3 dashboard/start_production.sh 생성
- [ ] Gunicorn으로 모든 백엔드 실행
- [ ] gunicorn_config.py 읽어서 적용
- [ ] 리소스 제한 적용 (cgroups 또는 systemd)

---

## Phase 3: setup_cluster_multihead 통합

### 3.1 Gunicorn 배포 추가
- [ ] `setup_cluster_multihead.py` 수정
  - Gunicorn 패키지 배포 단계 추가
  - 설정 파일 배포
  - 오프라인 설치 지원

### 3.2 N중화 배포 설정
- [ ] `cluster_config.yaml` 확장
  ```yaml
  nodes:
    - hostname: pc1
      ip: 192.168.1.10
      services: [all]
      gunicorn_workers: 4
    - hostname: pc2
      ip: 192.168.1.11
      services: [all]
      gunicorn_workers: 4
  ```

### 3.3 원격 설치 스크립트
- [ ] `deploy_to_nodes.sh` 생성
  - rsync 또는 scp로 배포
  - 각 노드에서 setup_cluster 실행
  - 오프라인 패키지 설치

---

## Phase 4: 리소스 제한 설정

### 4.1 cgroups v2 기반 제한
- [ ] 각 서비스별 cgroup 생성
- [ ] CPU quota 설정 (resource_limits.yaml 기반)
- [ ] Memory limit 설정
- [ ] start_production.sh에서 cgexec로 실행

### 4.2 Systemd 서비스 파일 (선택사항)
- [ ] 각 백엔드별 systemd unit 생성
- [ ] CPUQuota, MemoryLimit 설정
- [ ] 자동 재시작 설정

---

## Phase 5: Nginx Load Balancing

### 5.1 Upstream 설정 자동 생성
- [ ] resource_limits.yaml 읽어서 nginx 설정 생성
- [ ] `/etc/nginx/conf.d/upstream.conf` 생성
  ```nginx
  upstream auth_backend {
      server 192.168.1.10:4430;
      server 192.168.1.11:4430;
  }
  ```

### 5.2 Health Check
- [ ] 각 백엔드에 `/health` 엔드포인트 추가
- [ ] Nginx health check 설정

---

## 현재 진행 상황

### ✅ 완료
- start_complete.sh 서비스 재시작 로직 수정
- 로그 파일 권한 문제 해결
- gunicorn_template.yaml 생성
- resource_limits.yaml 생성

### 🔄 진행 중
- Phase 1: 오프라인 패키지 준비
- Phase 2: start.sh 옵션 추가

### ⏳ 대기 중
- Phase 3: setup_cluster_multihead 통합
- Phase 4: 리소스 제한
- Phase 5: Nginx Load Balancing

---

## Phase 2: 리소스 제한 설정

### 2.1 Systemd 서비스 파일 생성 (선택사항)
- [ ] CPU 제한: `CPUQuota=50%`
- [ ] Memory 제한: `MemoryLimit=2G`
- [ ] 각 서비스별 systemd unit 파일

### 2.2 cgroups를 통한 리소스 제한 (대안)
- [ ] Docker 없이 cgroups 직접 사용
- [ ] 스크립트에서 cgcreate, cgexec 사용

### 2.3 Gunicorn 자체 제한
- [ ] `--worker-class` 설정
- [ ] `--workers` 수 제한 (CPU 코어 대비)
- [ ] `--threads` 수 제한
- [ ] `--max-requests` 설정 (메모리 누수 방지)

---

## Phase 3: N중화 배포 준비

### 3.1 설정 파일 중앙화
- [ ] `config/deployment.yaml` 생성
  ```yaml
  servers:
    - host: pc1.local
      ip: 192.168.1.10
      services: [auth, dashboard, cae]
    - host: pc2.local
      ip: 192.168.1.11
      services: [auth, dashboard, cae]
  ```

### 3.2 배포 스크립트
- [ ] `deploy.sh` - 원격 서버에 자동 배포
- [ ] rsync 또는 git pull 기반
- [ ] SSH 키 설정 가이드

### 3.3 로드 밸런싱
- [ ] Nginx upstream 설정
- [ ] Health check 엔드포인트 추가
- [ ] Failover 설정

---

## Phase 4: 모니터링 및 관리

### 4.1 Health Check
- [ ] 각 서비스에 `/health` 엔드포인트 추가
- [ ] Prometheus metrics 노출
- [ ] Grafana 대시보드

### 4.2 로그 관리
- [ ] 중앙화된 로그 수집
- [ ] 로그 로테이션 설정
- [ ] 에러 알림 (선택사항)

---

## 현재 진행 상황

### ✅ 완료
- start_complete.sh 서비스 재시작 로직 수정
- 로그 파일 권한 문제 해결

### 🔄 진행 중
- Phase 1.1: Gunicorn 설정 파일 생성
- Phase 1.2: 스크립트 분리

### ⏳ 대기 중
- Phase 2: 리소스 제한
- Phase 3: N중화 배포
- Phase 4: 모니터링

---

## 다음 단계

1. **Gunicorn 설정 YAML 생성** - 리소스 제한 포함
2. **start_production.sh 생성** - Gunicorn으로 실행
3. **테스트** - 단일 서비스부터
4. **전체 적용**
5. **문서화**

---

## 참고사항

### Gunicorn 권장 설정
```yaml
# CPU 4코어, RAM 16GB 기준
workers: 4  # (2 * CPU cores) + 1
threads: 2
worker_class: sync  # 또는 gthread
timeout: 120
max_requests: 1000  # 메모리 누수 방지
max_requests_jitter: 50
```

### 리소스 제한 예시
```yaml
resources:
  cpu_quota: "50%"  # CPU 사용률 50%로 제한
  memory_limit: "2G"  # 메모리 2GB로 제한
  workers: 2  # 워커 수 제한
```
