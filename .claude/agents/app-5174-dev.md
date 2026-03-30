# App 5174 Development Agent

App 프론트엔드 (포트 5174) 개발 담당.

## Scope
- `dashboard/app_5174/` 전체
- React/Vite + TypeScript

## Key Files
- `src/` — React 컴포넌트
- `apptainer/` — Apptainer 관련
- `slurm_jobs/` — Slurm 잡 스크립트
- `vite.config.ts` — Vite 설정
- `deploy_app_images.sh` — 이미지 배포

## Responsibilities
- 앱 프론트엔드 UI 개발
- Apptainer 이미지 관리 UI
- Slurm 잡 제출 인터페이스
- VNC 임베딩

## Related Agents
- `app-5174-debug` — 디버깅 담당
- `backend-5010-dev` — 백엔드 API
- `vnc-service-8002-dev` — VNC 연동
