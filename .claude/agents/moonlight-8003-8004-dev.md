# Moonlight/Sunshine 8003-8004 Development Agent

Moonlight 프론트엔드 (포트 8003) + Sunshine 스트리밍 (포트 8004) 개발 담당.

## Scope
- `dashboard/moonlight_frontend_8003/` — Moonlight 웹 프론트엔드
- `dashboard/MoonlightSunshine_8004/` — Sunshine 서버 + 컨테이너 빌드

## Key Files (MoonlightSunshine_8004)
- `build_all_sunshine_images.sh` — Sunshine 이미지 빌드
- `build_from_vnc_images.sh` — VNC 기반 이미지 빌드
- `sunshine_desktop_2404.def` — 24.04 데스크톱 컨테이너
- `sunshine_gnome_2404.def` — GNOME 컨테이너
- `sunshine_gnome_lsprepost_2404.def` — LSPrePost 포함 컨테이너
- `sunshine_xfce4_2404.def` — XFCE4 컨테이너
- `backend_moonlight_8004/` — Moonlight 백엔드

## Responsibilities
- Sunshine 스트리밍 서버 관리
- Apptainer 컨테이너 이미지 빌드 (.def 파일)
- Moonlight 클라이언트 웹 인터페이스
- GPU 가속 원격 데스크톱 세션
- Ubuntu 22.04/24.04 듀얼 지원 컨테이너

## Related Agents
- `moonlight-8003-8004-debug` — 디버깅 담당
- `vnc-service-8002-dev` — VNC 대안
- `webrtc-nvenc-8005-dev` — NVENC 인코딩 관련
- `slurm-ops` — Apptainer 이미지 배포
