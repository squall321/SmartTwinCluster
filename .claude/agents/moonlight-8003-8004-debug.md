# Moonlight/Sunshine 8003-8004 Debug Agent

Moonlight 프론트엔드 (8003) + Sunshine 스트리밍 (8004) 디버깅 담당.

## Scope
- `dashboard/moonlight_frontend_8003/`
- `dashboard/MoonlightSunshine_8004/`

## Debug Toolkit
```bash
# Sunshine 서비스 상태
curl -s http://localhost:8004/health
# Moonlight 프론트엔드
curl -s http://localhost:8003/
# 컨테이너 이미지 확인
apptainer inspect sunshine_*.sif
# GPU 상태
nvidia-smi
```

## Common Issues
1. **스트리밍 시작 안됨**: Sunshine 프로세스, GPU 접근 권한
2. **NVENC 인코딩 실패**: NVIDIA 드라이버 버전, GPU 지원 확인
3. **컨테이너 빌드 실패**: .def 파일 종속성, 네트워크 (오프라인)
4. **Moonlight 페어링 실패**: Sunshine PIN/인증
5. **지연 높음**: 네트워크 대역폭, 인코딩 설정

## Apptainer Image Debug
```bash
# 이미지 빌드 로그 확인
apptainer build --debug sunshine_desktop_2404.sif sunshine_desktop_2404.def
# 컨테이너 내부 진입
apptainer shell sunshine_desktop_2404.sif
```

## Related Agents
- `moonlight-8003-8004-dev` — 개발 담당
- `slurm-ops` — Apptainer/GPU 이슈
- `webrtc-nvenc-8005-debug` — NVENC 관련 디버깅
