# Frontend 3010 Development Agent

메인 프론트엔드 (포트 3010) 개발 담당.

## Scope
- `dashboard/frontend_3010/` 전체
- React/Vite 기반 SPA

## Key Structure
```
frontend_3010/
├── src/
│   ├── components/    # React 컴포넌트
│   ├── pages/         # 페이지 컴포넌트
│   ├── hooks/         # 커스텀 훅
│   ├── services/      # API 클라이언트
│   ├── utils/         # 유틸리티
│   └── App.tsx        # 앱 엔트리
├── package.json
├── vite.config.ts
└── tsconfig.json
```

## Development Guidelines
- Backend API (5010)와 통신하는 프론트엔드
- Vite dev server (포트 3010)
- TypeScript + React
- API 호출은 services/ 디렉토리에서 관리

## Related Agents
- `frontend-3010-debug` — 디버깅 담당
- `backend-5010-dev` — 백엔드 API
- `websocket-5011-dev` — 실시간 데이터
- `auth-frontend-4431-dev` — 인증 UI 참고
