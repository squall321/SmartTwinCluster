# Ubuntu 24.04 (Noble) 마이그레이션 감사 보고서

> 작성일: 2026-03-06
> 목적: 22.04(jammy) → 24.04(noble) 오프라인 설치 지원 시 변경/확인 필요 항목 전수 조사

---

## 1. 즉시 깨지는 항목 (CRITICAL - 24.04에서 설치 실패)

### 1.1 Apptainer 컨테이너 정의 (.def) — 베이스 이미지 `ubuntu:22.04` 하드코딩

24.04 호스트에서 빌드 시 패키지 호환성 문제 발생.

| 파일 | 라인 | 현재 값 |
|------|------|---------|
| `dashboard/MoonlightSunshine_8004/sunshine_gnome.def` | 2 | `From: ubuntu:22.04` |
| `dashboard/MoonlightSunshine_8004/sunshine_desktop.def` | 2 | `From: ubuntu:22.04` |
| `dashboard/MoonlightSunshine_8004/sunshine_xfce4.def` | 2 | `From: ubuntu:22.04` |
| `dashboard/MoonlightSunshine_8004/sunshine_gnome_lsprepost.def` | 2 | `From: ubuntu:22.04` |
| `dashboard/vnc_sandbox/vnc_desktop.def` | 2 | `From: nvidia/cuda:11.8.0-devel-ubuntu22.04` |
| `dashboard/app_5174/apptainer/app/gedit/gedit.def` | ~2 | `From: ubuntu:22.04` |

### 1.2 Boost 라이브러리 버전 — 24.04에 존재하지 않음

22.04: `libboost*1.74.0` / 24.04: `libboost*1.83.0` → **패키지 이름 자체가 다름**

| 파일 | 라인 | 영향받는 패키지 |
|------|------|----------------|
| `sunshine_gnome.def` | 57-60 | `libboost-filesystem1.74.0`, `-log`, `-program-options`, `-thread` |
| `sunshine_desktop.def` | 56-59 | 동일 |
| `sunshine_xfce4.def` | 58-61 | 동일 |
| `sunshine_gnome_lsprepost.def` | 58-61 | 동일 |
| `build_from_vnc_images.sh` | 136-139 | 동일 |

### 1.3 FFmpeg 라이브러리 버전 — 24.04에서 메이저 버전 변경

22.04: `libavcodec58`, `libavformat58`, `libavutil56`, `libswscale5`
24.04: `libavcodec60`, `libavformat60`, `libavutil58`, `libswscale7`

| 파일 | 라인 |
|------|------|
| `sunshine_gnome.def` | 53-56 |
| `sunshine_desktop.def` | 52-55 |
| `sunshine_xfce4.def` | 54-57 |
| `sunshine_gnome_lsprepost.def` | 54-57 |
| `build_from_vnc_images.sh` | 131-135 |

### 1.4 Sunshine deb 패키지 — `sunshine-ubuntu-22.04-amd64.deb` 하드코딩

24.04용은 `sunshine-ubuntu-24.04-amd64.deb`으로 별도 제공됨.

| 파일 | 라인 | 현재 값 |
|------|------|---------|
| `sunshine_gnome.def` | 82 | `sunshine-ubuntu-22.04-amd64.deb` |
| `sunshine_desktop.def` | 81 | 동일 |
| `sunshine_xfce4.def` | 79 | 동일 |
| `sunshine_gnome_lsprepost.def` | 83 | 동일 |
| `build_all_sunshine_images.sh` | 23 | 동일 |
| `build_from_vnc_images.sh` | 155 | 동일 |

### 1.5 NVIDIA 라이브러리 버전 — 드라이버 535 → 550+ 필요

| 파일 | 라인 | 현재 값 | 24.04 필요 |
|------|------|---------|-----------|
| `sunshine_gnome.def` | 46-48 | `libnvidia-encode-535`, `-decode-535`, `-gl-535` | `550` 이상 |
| `sunshine_desktop.def` | 44-47 | 동일 | 동일 |
| `sunshine_xfce4.def` | 34-35 | `nvidia-driver-535`, `cuda-toolkit-12-3` | `550+`, `12-4+` |
| `sunshine_gnome_lsprepost.def` | 46-49 | 동일 | 동일 |

### 1.6 CUDA 저장소 URL — `ubuntu2204` 하드코딩

| 파일 | 라인 | 현재 값 |
|------|------|---------|
| `sunshine_xfce4.def` | 27 | `cuda/repos/ubuntu2204/x86_64/cuda-keyring` |
| `offline_packages/gpu/download_gpu_packages.sh` | 45 | 동일 URL |

### 1.7 Apptainer deb 파일명 — `~jammy` 하드코딩

| 파일 | 라인 | 현재 값 |
|------|------|---------|
| `install_apptainer_only.sh` | 157 | `apptainer_1.4.5-1~jammy_amd64.deb` |
| `install_apptainer_viz.sh` | 12, 119, 134 | 동일 |
| `offline_deploy/deploy_to_compute_node.sh` | 935 | 동일 |

---

## 2. 높은 확률로 문제되는 항목 (HIGH)

### 2.1 MariaDB Galera WSREP 프로바이더 경로

22.04(MariaDB 10.6): `/usr/lib/galera/libgalera_smm.so`
24.04(MariaDB 10.11): 경로가 `/usr/lib/galera/` 또는 `/usr/lib/x86_64-linux-gnu/galera/`로 변경될 수 있음.

| 파일 | 라인 | 현재 값 |
|------|------|---------|
| `cluster/setup/phase1_database.sh` | 355 | `/usr/lib/galera/libgalera_smm.so` (OS별 분기는 있으나 버전별 없음) |

**해결:** `find /usr/lib -name "libgalera_smm.so"` 동적 탐색 추가.

### 2.2 dashboard/systemd/install_services.sh — offline_packages 경로 + Python 버전

| 라인 | 항목 | 문제 |
|------|------|------|
| 32-33 | `$PROJECT_ROOT/offline_packages/python_wheels.tar.gz` | 24.04에서 `offline_packages_2404` 사용해야 함 |
| 35 | `tar -xzf ... -C "$PROJECT_ROOT/offline_packages/"` | 동일 |
| 50 | `auth_backend: 3.10` | 24.04에서 3.12로 변경 필요 |
| 52 | `websocket_service: 3.10` | 동일 |

### 2.3 AMD GPU 드라이버 URL — `jammy` 코드명

| 파일 | 라인 | 현재 값 |
|------|------|---------|
| `cluster/setup/phase6_gpu.sh` | 401 | `ubuntu/jammy/amdgpu-install_6.0.60002-1_all.deb` |
| `offline_packages/gpu/download_gpu_packages.sh` | 201 | 동일 |

---

## 3. `offline_packages` 하드코딩 경로 — 전체 목록

24.04에서는 `offline_packages_2404/`를 사용해야 하므로 모든 참조를 변수화 필요.

### 3.1 Phase 스크립트

| 파일 | 참조 수 | 주요 라인 |
|------|---------|----------|
| `cluster/setup/phase3_slurm.sh` | 14 | 162, 233, 306, 392, 426, 480-500, 1088, 1587, 2983, 3033, 3102 |
| `cluster/setup/phase5_web.sh` | 3 | 1410, 1598, 1628 |
| `cluster/setup/phase1_database.sh` | 1 | 422 |
| `cluster/setup/phase2_redis.sh` | 1 | 366 |
| `cluster/setup/phase4_keepalived.sh` | 1 | 276 |
| `cluster/setup/phase6_gpu.sh` | 3 | 213, 332, 376 |
| `cluster/setup/phase10_compute_deploy.sh` | 5 | 135, 244, 275, 327, 352 |

### 3.2 배포 및 설치 스크립트

| 파일 | 참조 수 | 주요 라인 |
|------|---------|----------|
| `setup_cluster_full_multihead_offline.sh` | 3 | 64, 289, 505 |
| `offline_deploy/deploy_to_compute_node.sh` | 10+ | 43, 324, 416-442, 595, 711, 935 |
| `install_apptainer_only.sh` | 1 | 50 |
| `install_apptainer_viz.sh` | 1 | 12 |
| `dashboard/systemd/install_services.sh` | 3 | 32, 33, 35 |

### 3.3 Python 소스코드 (YAML 검증)

| 파일 | 라인 | 변경 |
|------|------|------|
| `src/config_parser.py` | 179 | `valid_os`에 `'ubuntu24'` 추가 |
| `src/os_manager.py` | 432 | `UbuntuManager` 분기에 `'ubuntu24'` 추가 |
| `src/offline_installer.py` | 359 | `_install_deb_offline` 분기에 `'ubuntu24'` 추가 |

---

## 4. Python 버전 매핑 이슈

22.04 기본: Python 3.10 / 24.04 기본: Python 3.12

### 4.1 서비스별 Python 버전

| 서비스 | 22.04 버전 | 24.04 계획 | 파일 |
|--------|-----------|-----------|------|
| auth_portal_4430 | 3.10 | **3.12** | `phase5_web.sh`, `install_services.sh:50` |
| auth_portal_4431 | 3.10 | **3.12** | `phase5_web.sh` |
| websocket_5011 | 3.10 | **3.12** | `phase5_web.sh`, `install_services.sh:52` |
| backend_moonlight_8004 | 3.10 | **3.12** | `phase5_web.sh` |
| backend_5010 | 3.12 | 3.12 (유지) | `install_services.sh:51` |
| kooCAEWebServer_5000 | 3.13 | 3.13 (deadsnakes) | `install_services.sh:53` |
| kooCAEWebAutomationServer_5001 | 3.13 | 3.13 (deadsnakes) | `install_services.sh:54` |

### 4.2 Python 버전 하드코딩 위치

| 파일 | 라인 | 내용 |
|------|------|------|
| `offline_packages/download_python_wheels.sh` | 44 | `PYTHON_VERSIONS=("3.10" "3.12" "3.13")` |
| `dashboard/systemd/install_services.sh` | 49-54 | 서비스별 Python 매핑 |
| `cluster/setup/phase5_web.sh` | ~1416 | `service_python_map` 정의 |

---

## 5. 컨테이너 이미지 빌드 관련 (MoonlightSunshine)

`.def` 파일은 컨테이너 빌드 시에만 영향. 24.04 호스트에서 빌드할 경우 24.04용 `.def` 별도 필요.

### 5.1 변경 필요 파일 목록

| 파일 | 변경 항목 |
|------|----------|
| `sunshine_gnome.def` | base image, boost, ffmpeg, nvidia, sunshine-deb |
| `sunshine_desktop.def` | 동일 |
| `sunshine_xfce4.def` | 동일 + CUDA keyring URL |
| `sunshine_gnome_lsprepost.def` | 동일 |
| `vnc_desktop.def` | base image (nvidia/cuda ubuntu22.04) |
| `gedit.def` | base image |
| `build_all_sunshine_images.sh` | sunshine-deb URL |
| `build_from_vnc_images.sh` | boost, ffmpeg, sunshine-deb |

### 5.2 권장 접근법

`.def` 파일을 24.04용으로 복사하여 별도 관리:
```
dashboard/MoonlightSunshine_8004/
├── sunshine_gnome.def          # 22.04용 (기존)
├── sunshine_gnome_2404.def     # 24.04용 (신규)
├── ...
```
또는 빌드 스크립트에서 OS 감지 후 변수 치환.

---

## 6. 잠재적 이슈 (확인 필요)

### 6.1 systemd 255+ 엄격한 서비스 파일 검증

24.04는 systemd 255+를 사용. `Type=forking` + `PIDFile` 조합이 deprecated.

**확인 파일:**
- `cluster/setup/phase10_compute_deploy.sh` (~493행, slurmd.service 생성)
- `cluster/setup/phase3_slurm.sh` (slurmctld.service 생성)

### 6.2 OpenSSH 9.x — `ssh-rsa` 알고리즘 비활성화

24.04 기본 OpenSSH 9.x에서 `ssh-rsa` 비활성화됨. RSA 키로 SSH 연결 시 실패 가능.

**영향:** 모든 SSH 기반 노드 배포 스크립트

### 6.3 GlusterFS 버전 차이

22.04: GlusterFS 9.x / 24.04: GlusterFS 11.x
마운트 옵션이나 볼륨 프로토콜 호환성 확인 필요.

### 6.4 apt-key deprecated

24.04에서 `apt-key` 완전 제거. GPG 키는 `/usr/share/keyrings/`에 별도 저장 필요.

**영향 파일:**
- `offline_packages/collect_apt_packages.sh` (외부 PPA 추가 시)
- `cluster/setup/phase5_web.sh:174` (NodeSource 설정)

### 6.5 libmunge 패키지명 변경 가능성

22.04: `libmunge2` / 24.04: 패키지명 확인 필요 (`libmunge2` 유지 또는 변경)

---

## 7. 변경 불필요 항목 (확인 완료)

| 항목 | 이유 |
|------|------|
| NVIDIA `.run` 파일 | 자체 포함 설치 파일, OS 무관 |
| Prometheus / node_exporter 바이너리 | Go 정적 링크, OS 무관 |
| Munge 키 파일 | 바이너리 키, OS 무관 |
| NPM 패키지 (node_modules) | 플랫폼 독립적 |
| cgroup v2 설정 | 22.04, 24.04 모두 cgroup v2 기본 |
| `phase9_software.sh` Apptainer 설치 | 이미 `*.deb` glob 사용 |
| nginx 설정 파일 | 경로 동일 |
| Redis/Keepalived 설정 | 프로토콜 호환 |

---

## 8. 전체 변경 파일 수 요약

| 구분 | 파일 수 |
|------|---------|
| 신규 생성 (offline_packages_2404/) | ~10 |
| 신규 생성 (detect_os.sh) | 1 |
| 스크립트 경로 변수화 | 12 |
| Python 소스 수정 | 3 |
| 컨테이너 .def 파일 (24.04용 생성) | 6 |
| Sunshine 빌드 스크립트 | 2 |
| **총계** | **~34** |
