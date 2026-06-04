# VNC GPU 가속 (VirtualGL) — 빌드/배포/사용 가이드

기존 VNC(TigerVNC, 소프트웨어 렌더링)에 **VirtualGL**을 얹어 **OpenGL 앱을 GPU로 렌더**하는 이미지입니다.
데스크톱(2D)은 그대로 TigerVNC(우리가 고친 noVNC 파이프라인 동일), **GL 앱만 `vglrun`으로 GPU 가속**합니다.

## 동작 원리

```
브라우저(noVNC) ── TigerVNC(2D 데스크톱) ──┐
                                          ├─ XFCE4 세션
GL 앱  ── vglrun -d egl ── GPU(EGL) 렌더 ──┘  (렌더 결과를 VNC 화면으로)
```

- **호스트에 NVIDIA 드라이버(nvidia-smi) 설치되어 있으면 됨.** 컨테이너엔 드라이버를 넣지 않습니다.
- 런타임에 `apptainer --nv` 가 호스트 드라이버/EGL 라이브러리를 컨테이너로 주입합니다.
  → backend 는 **세션 생성 시 GPU 개수 ≥ 1** 이면 자동으로 `--nv` 를 붙입니다. (GPU 0이면 --nv 없음 = GPU 미사용)
- 컨테이너에는 **VirtualGL + EGL/GL 로더**만 설치(`vnc_desktop_gpu.def`).

## 구성 파일

| 파일 | 설명 |
|---|---|
| `vnc_desktop_gpu.def` | 22.04 빌드 정의 (TigerVNC + VirtualGL, `/opt/scripts/start_vnc.sh` 자체 생성) |
| `vnc_desktop_gpu_2404.def` | 24.04 변이 (베이스 이미지만 다름) |
| `build_vnc_gpu_sandbox.sh` | `.sif` 빌드 → `/opt/apptainers/vnc_desktop_gpu.sif` |
| (backend) `VNC_IMAGES['xfce4_gpu']` | 웹 이미지 목록에 "XFCE4 (GPU/VirtualGL)" 노출 (이미 반영됨) |

## 1) 빌드

빌드 노드(네트워크 필요 — 베이스 이미지 pull + apt + VirtualGL .deb)에서:

```bash
cd dashboard/vnc_sandbox
./build_vnc_gpu_sandbox.sh
# → /opt/apptainers/vnc_desktop_gpu.sif 생성
```

> **오프라인 빌드**: sif 빌드는 원래 nvidia/cuda 베이스 pull + apt 가 필요해 네트워크 전제입니다(기존 VNC sif 빌드와 동일).
> 완전 오프라인이면 네트워크 되는 곳에서 빌드 후 `.sif` 만 노드로 복사하세요.
> VirtualGL `.deb` 만 따로 준비하려면 `def` 의 `%post` wget 을 미리 받은 `dpkg -i` 로 바꾸면 됩니다.

## 2) 배포 (★ 필수)

`/opt/apptainers` 는 **노드-로컬**입니다. 빌드한 `.sif` 를 **모든 viz 노드**에 복사해야 합니다.
전용 배포 스크립트(viz노드 YAML 자동 enumerate + 키→sshpass 폴백 + 병렬 + md5 검증/스킵):

```bash
cd dashboard/vnc_sandbox
./deploy_vnc_image_to_viz.sh                 # 기본: vnc_desktop_gpu.sif → 모든 viz 노드 /opt/apptainers
#   옵션: --sif PATH  --parallel N  --config YAML  --nodes-file FILE
```

> **빌드+배포 한번에**: `./build_vnc_gpu_sandbox.sh --deploy`
> (root 소유 /opt/apptainers 라 /tmp 경유 후 sudo mv. NOPASSWD sudo 또는 ssh_password 사용.)

## 3) 백엔드 반영

```bash
sudo ./dashboard/start_production.sh    # 재기동하면 이미지 목록에 GPU 항목 노출
```
- 웹 `/vnc` 에서 **"XFCE4 (GPU/VirtualGL)"** 이미지 선택 + **GPU 개수 ≥ 1** 로 세션 생성.

## 4) GPU 사용 / 검증

데스크톱 터미널에서 GL 앱을 GPU로:
```bash
vgl glxgears            # = vglrun -d egl glxgears (편의 래퍼)
vglrun -d egl glxinfo | grep "OpenGL renderer"
#  → "OpenGL renderer string: NVIDIA ..."  면 GPU 렌더 성공
#  → "llvmpipe" 면 소프트웨어 (──nv 누락 또는 EGL 실패)
```

빌드 직후 노드에서 빠른 점검:
```bash
apptainer exec --nv /opt/apptainers/vnc_desktop_gpu.sif nvidia-smi
apptainer exec --nv /opt/apptainers/vnc_desktop_gpu.sif vglrun -d egl glxinfo | grep "OpenGL renderer"
```

## 트러블슈팅

- **renderer 가 llvmpipe**: `--nv` 가 안 붙음(GPU 개수 0으로 생성?) 또는 노드에 드라이버 없음 → `nvidia-smi` 확인.
- **vglrun: EGL 초기화 실패**: 노드 호스트 드라이버 버전과 EGL 라이브러리 불일치 / GPU 가시성(`CUDA_VISIBLE_DEVICES`) 확인.
- **이미지 선택 시 에러**: `.sif` 가 그 viz 노드에 아직 배포 안 됨(2단계 누락).
- VNC 자체(검은화면/Target closed 등)는 GPU 와 무관 — 기존 파이프라인 동일(TigerVNC).
