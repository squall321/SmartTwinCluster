═══════════════════════════════════════════════════════════════
    오프라인 클러스터 설치 패키지
═══════════════════════════════════════════════════════════════

이 디렉토리에는 오프라인 환경에서 HPC 클러스터를 설치하기 위한
모든 필요한 패키지가 포함되어 있습니다.

디렉토리 구조:
───────────────────────────────────────────────────────────────
  slurm/               Slurm 프리빌드 패키지
    └─ slurm-*-prebuilt.tar.gz
    └─ build_slurm_package.sh

  apt_packages/        모든 APT .deb 패키지
    └─ *.deb (수백 개)
    └─ install_offline_packages.sh

  munge/               Munge 인증 키
    └─ munge.key
    └─ deploy_munge.sh

  apt_mirror/          로컬 APT 미러 (선택사항)
    └─ mirror/
    └─ setup_client.sh

  system_deps/         기타 시스템 의존성


설치 방법:
───────────────────────────────────────────────────────────────

【헤드 노드】

1. 전체 디렉토리를 헤드 노드로 복사:
   rsync -avz offline_packages/ user@headnode:/opt/offline_packages/

2. 메인 설치 스크립트 실행:
   cd /opt/offline_packages/..
   sudo ./setup_cluster_full_multihead_offline.sh

3. 또는 수동 설치:
   a. APT 패키지 설치:
      cd apt_packages/
      sudo bash install_offline_packages.sh

   b. Slurm 배포:
      cd slurm/
      tar -xzf slurm-*-prebuilt.tar.gz
      sudo bash deploy_slurm.sh

   c. Munge 배포:
      cd munge/
      sudo bash deploy_munge.sh


【계산 노드】

헤드 노드에서 자동 배포:
  cd /opt/offline_packages/..
  sudo ./offline_deploy/deploy_to_compute_node.sh --config my_multihead_cluster.yaml


로컬 APT 미러 사용 (선택):
───────────────────────────────────────────────────────────────

헤드 노드에서 APT 미러 서비스 시작:
  sudo systemctl start apache2

각 계산 노드에서:
  bash /opt/offline_packages/apt_mirror/setup_client.sh


문제 해결:
───────────────────────────────────────────────────────────────

1. 패키지 의존성 오류:
   sudo apt-get install -f

2. Munge 인증 실패:
   sudo systemctl restart munge
   munge -n | unmunge

3. Slurm 서비스 시작 실패:
   journalctl -u slurmctld -n 50

═══════════════════════════════════════════════════════════════
