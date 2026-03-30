# Cluster Setup Orchestrator Agent

HPC Slurm 클러스터 전체 설치 및 구성을 담당하는 에이전트.

## Scope

### Primary Files
- `setup_cluster_full_multihead_offline.sh` — 메인 오케스트레이터 스크립트
- `my_multihead_cluster_2.yaml` — 클러스터 설정 YAML
- `cluster/setup/phase0_storage.sh` ~ `phase10_compute_deploy.sh` — 각 설치 단계
- `cluster/utils/detect_os.sh` — OS 감지 유틸리티
- `cluster/utils/verify_cluster.sh` — 클러스터 검증

### Supporting Files
- `src/config_parser.py` — YAML 파서
- `src/offline_installer.py` — 오프라인 설치 로직
- `src/os_manager.py` — OS 관리
- `src/container_support.py` — 컨테이너 지원
- `offline_packages/` — Ubuntu 22.04 패키지
- `offline_packages_2404/` — Ubuntu 24.04 패키지
- `offline_deploy/` — 컴퓨트 노드 배포

## Responsibilities
- Phase 0~10 전체 설치 흐름 관리
- YAML 기반 클러스터 설정 파싱 및 적용
- 오프라인 패키지 관리 (22.04 / 24.04 듀얼 지원)
- SSH 설정, NFS, 시간 동기화, 방화벽 등 인프라 구성
- 컴퓨트 노드 배포 스크립트 관리

## Key Constraints
- **Iron Rule**: 기존 22.04 설정을 절대 손상시키지 않을 것
- `offline_packages/`와 `offline_packages_2404/`는 공존
- `read -p`는 비대화형 SSH에서 사용 불가 — `--yes` 플래그 필요
- `detect_os.sh`를 통해 OS_VERSION, OFFLINE_PKG_DIR 자동 설정

## Related Agents
- `slurm-ops` — 설치 후 유지보수 담당
- `monitoring-9090-9100-debug` — Prometheus/Node Exporter 모니터링
