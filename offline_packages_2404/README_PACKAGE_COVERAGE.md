# Ubuntu 24.04 오프라인 패키지 커버리지 — 2026-04-18 업데이트

## 현재 상태

| 항목 | 22.04 | 24.04 | 비고 |
|------|-------|-------|------|
| APT .deb 파일 | 4,208개 (13GB) | 499개 (431MB) | **24.04 매우 부족** |
| Python wheels | 215MB | 359MB | 24.04 충분 |
| GPU 드라이버 | 4.5GB | 4.5GB | NVIDIA 550 (.run) |
| Slurm prebuilt | 108MB | 482MB | 23.11.10 빌드 완료 |
| Munge 키 | ✅ | ✅ | 동기화 완료 |
| Node.js | 56MB | 56MB | NodeSource 20.x |

24.04 .deb이 22.04의 **12%**밖에 안 됩니다. 디스크 부족으로 중단된 것이 원인.

---

## 추가된 카테고리 (이번 업데이트)

`collect_apt_packages_2404.sh`에 다음 패키지 그룹을 추가했습니다:

### 1. NFS_PACKAGES (공유 파일시스템)
- nfs-kernel-server, nfs-common, rpcbind, autofs

### 2. MONITORING_PACKAGES (Prometheus/Grafana)
- prometheus, prometheus-node-exporter, prometheus-alertmanager, prometheus-mysqld-exporter
- ⚠️ **Grafana**는 APT에 없음 → 별도 .deb 다운로드 필요 (아래 참조)

### 3. VNC_PACKAGES (대시보드 VNC 세션)
- tigervnc-standalone-server, tigervnc-common, novnc, websockify, xvfb, dbus-x11

### 4. UBUNTU_DESKTOP_PACKAGES (전체 데스크톱)
- ubuntu-desktop-minimal, gdm3, gnome-session, gnome-shell, nautilus
- xorg, xserver-xorg-* (전체)
- fonts-noto-cjk (한글 폰트 포함)

### 5. XFCE4_PACKAGES (경량 데스크톱 — Apptainer SIF용)
- xfce4, xfce4-goodies, xfce4-terminal, xfwm4

### 6. SYSTEM_TOOLS_PACKAGES (운영 도구)
- htop, iotop, tmux, screen, byobu, tree, ncdu, atop, sysstat, lsof, strace

### 7. NETWORK_TOOLS_PACKAGES
- nmap, tcpdump, traceroute, dnsutils, ethtool, bridge-utils, iptables, ufw

### 8. EXTRA_BUILD_DEPS (소스 빌드 확장)
- autoconf, automake, libtool, bison, flex, m4
- libffi-dev, zlib1g-dev, liblz4-dev, libzstd-dev
- libnl-3-dev, libcurl4-openssl-dev, libjson-c-dev, libyaml-dev
- libxmlsec1-dev (python3-saml 빌드용)

### 9. HPC_PACKAGES 보강
- libpmix-dev, libpmix2t64 (Slurm --with-pmix 빌드 필수)
- squashfuse, fuse-overlayfs, crun, uidmap (Apptainer 의존성)

---

## 별도 빌드/다운로드 필요 항목

### 빌드 완료 (이미 prebuilt 있음)
- ✅ **Slurm 23.11.10** — `offline_packages_2404/slurm/slurm-23.11.10-prebuilt.tar.gz` (482MB)
  - 빌드 스크립트: `offline_packages_2404/slurm/build_slurm_package.sh`
  - 24.04 KVM VM 안에서 PMIx 포함 빌드됨

### 다운로드 필요 (APT 외부)
- ❌ **Grafana** — apt 저장소에 없음
  - 다운로드: `wget https://dl.grafana.com/oss/release/grafana_10.4.0_amd64.deb`
- ❌ **NVIDIA RTX PRO 6000 드라이버** — 현재 550 계열 포함, 신규 GPU 호환성 확인 필요
  - 최신: NVIDIA-Linux-x86_64-580.x.run (RTX 50/PRO 6000 지원)
- ❌ **CUDA 12.8** — 현재 12.4 .run 포함, 12.8로 업그레이드 권장
  - cuda_12.8.0_*_linux.run

### Apptainer SIF 이미지 (별도 빌드)
오프라인 패키지가 아닌 **컨테이너 이미지**로, 별도 빌드가 필요합니다:
- vnc_xfce4.sif        — XFCE4 + TigerVNC + noVNC
- vnc_gnome.sif         — GNOME + TigerVNC + noVNC
- vnc_gnome_lsprepost.sif — GNOME + LS-PrePost CAE 도구
- sunshine_xfce4.sif    — Sunshine 스트리밍 + XFCE4
- sunshine_gnome.sif    — Sunshine 스트리밍 + GNOME

빌드 위치: `dashboard/MoonlightSunshine_8004/sunshine_*.def`

---

## 수집 워크플로우

### 1. 디스크 공간 확보

KooStableDiffusionManager(661GB)를 `/data/Projects`로 이동 중. 완료되면 /home에 600GB+ 여유 생기므로 추가 이동 불필요.

### 2. 24.04 KVM VM에서 APT 패키지 수집

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory
sudo ./offline_packages_2404/prepare_offline_packages_2404.sh --yes
```

VM 내부에서 자동으로:
1. Ubuntu 24.04 cloud image 다운로드
2. Apptainer/deadsnakes/NodeSource PPA 등록
3. `collect_apt_packages_2404.sh --service all` 실행 (이번 업데이트로 데스크톱/VNC/모니터링 포함)
4. apt-get install --download-only로 .deb 수집
5. dpkg-scanpackages로 로컬 APT repo 인덱스 생성
6. 호스트로 rsync

### 3. 별도 다운로드 (인터넷 연결된 24.04 머신에서)

```bash
# Grafana
cd /data/Projects/offline_packages_2404/apt_packages
wget https://dl.grafana.com/oss/release/grafana_10.4.0_amd64.deb

# 최신 NVIDIA 드라이버 (RTX PRO 6000용)
cd /data/Projects/offline_packages_2404/gpu/nvidia
wget https://us.download.nvidia.com/XFree86/Linux-x86_64/580.65.06/NVIDIA-Linux-x86_64-580.65.06.run

# CUDA 12.8
wget https://developer.download.nvidia.com/compute/cuda/12.8.0/local_installers/cuda_12.8.0_570.86.10_linux.run
```

### 4. Python wheels 수집 (이미 359MB 완료)
대시보드 6개 서비스의 requirements.txt 모두 수집됨. 추가 필요 시:

```bash
cd /data/Projects/offline_packages_2404/python_wheels
python3 -m pip download -r ../../dashboard/<NEW_SERVICE>/requirements.txt -d .
```

---

## 예상 최종 크기

| 카테고리 | 예상 크기 |
|---------|----------|
| APT (데스크톱 포함 전체) | ~13~15GB |
| Python wheels | ~400MB |
| GPU (NVIDIA 580 + CUDA 12.8) | ~6GB |
| Slurm prebuilt | 482MB |
| Munge | <1MB |
| Node.js | 56MB |
| **합계** | **~20~22GB** |

`/data`에 저장하면 6.6TB 여유 중 22GB 사용 → 문제없음.

---

## 빠진 부분 체크리스트

다음 항목은 추가 검토 필요:

- [x] FFmpeg → MEDIA_PACKAGES에 포함 (libavcodec60, libavformat60 등)
- [x] Wayland → X11_LIBS에 포함 (libwayland-client0, libwayland-server0)
- [x] LS-DYNA 런타임 → CAE_DEPS에 포함 (libgfortran5, libquadmath0, libomp-dev, tcl, tk)
- [x] Sunshine 스트리밍 → download_external_packages.sh --sunshine
- [x] cuda-keyring → download_external_packages.sh --cuda-keyring
- [x] CRITICAL_24_PACKAGES (libpmix2t64, libfuse2t64, squashfuse 등 22.04 CRITICAL의 24.04 대응)
- [ ] Apptainer 1.4.x .deb (PPA에서 자동 수집되는지 실제 실행 시 확인 필요)
- [ ] Intel MKL/OneAPI (필요 시 .run 별도, 현재 미포함)
- [ ] HDF5/NetCDF (시뮬레이션 결과 처리용 — 필요 시 SYSTEM_PACKAGES에 추가)

## 최종 패키지 카테고리 (27개)

### 기존 (10개)
1. SYSTEM_PACKAGES
2. SLURM_BUILD_DEPS
3. SLURM_RUNTIME_PACKAGES (deprecated)
4. GLUSTERFS_PACKAGES
5. MARIADB_PACKAGES
6. REDIS_PACKAGES
7. KEEPALIVED_PACKAGES
8. WEB_PACKAGES
9. PYTHON_PACKAGES
10. PYTHON_BUILD_DEPS

### 1차 추가 (8개)
11. HPC_PACKAGES (PMIx + Apptainer 의존성)
12. NFS_PACKAGES
13. MONITORING_PACKAGES
14. VNC_PACKAGES
15. UBUNTU_DESKTOP_PACKAGES
16. XFCE4_PACKAGES
17. SYSTEM_TOOLS_PACKAGES
18. NETWORK_TOOLS_PACKAGES

### 2차 추가 (9개) — SIF 빌드 + 22.04 패리티
19. EXTRA_BUILD_DEPS
20. **MEDIA_PACKAGES** — FFmpeg, PulseAudio, Boost, x264/x265
21. **X11_LIBS** — X11/XCB/Wayland/Mesa/Vulkan (33개)
22. **FONTS_EXTRAS** — Noto CJK, 나눔, 이모지
23. **DESKTOP_APPS** — Firefox, Gedit, Nautilus, Thunar, GVFS
24. **CAE_DEPS** — LS-DYNA 런타임, Tcl/Tk, OpenMP
25. **CRITICAL_24_PACKAGES** — 22.04 CRITICAL의 24.04 대응 명명
26. **SECURITY_TZ_PACKAGES** — ca-certificates, libssl3, locales, tzdata

### 새 service 옵션
- `desktop` — UBUNTU_DESKTOP + XFCE4 + VNC
- `vnc` — VNC만
- `nfs` — NFS만
- `monitoring` — Prometheus + Exporters
- `media` — Sunshine 스트리밍 의존성
- `x11` — X11 + 폰트
- `critical` — Slurm/Apptainer 핵심 라이브러리
- `cae` — CAE_DEPS + X11 + 미디어
