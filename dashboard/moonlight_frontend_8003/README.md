# Moonlight/Sunshine Frontend

React + TypeScript + Vite frontend for Moonlight/Sunshine ultra-low latency streaming.

## 기술 스택

- **React 19** + **TypeScript**
- **Vite** - Build tool  
- **Material-UI (MUI)** - UI components
- **Axios** - HTTP client

## 프로젝트 구조

```
moonlight_frontend_8003/
├── src/
│   ├── api/
│   │   └── moonlight.ts          # Backend API client
│   ├── components/
│   │   ├── ImageSelector.tsx     # 이미지 선택 카드
│   │   └── SessionList.tsx       # 세션 목록 테이블
│   ├── App.tsx                   # Main app
│   ├── main.tsx                  # Entry point
│   └── index.css
├── vite.config.ts                # Vite 설정 (Port 8003)
├── .env                          # 환경 변수
└── package.json
```

## 개발 시작

### 1. 의존성 설치

```bash
npm install
```

### 2. 개발 서버 실행

```bash
npm run dev
```

- Frontend: http://localhost:8003
- Backend API: http://localhost:8004 (proxy 설정됨)

### 3. 빌드

```bash
npm run build
```

빌드 결과: `dist/` 디렉토리

## 주요 기능

### 1. 이미지 선택 (ImageSelector)

- 사용 가능한 Sunshine 이미지 목록 표시
- 이미지 상태 (Available/Not Built)
- 카드 클릭으로 선택
- "Start Session" 버튼으로 세션 생성

### 2. 세션 관리 (SessionList)

- 현재 활성 세션 목록
- 세션 상태 실시간 업데이트 (5초마다)
- 세션 중지 기능
- 연결 정보 표시

### 3. Backend 연동

- Health check
- 이미지 목록 조회 (`GET /api/moonlight/images`)
- 세션 목록 조회 (`GET /api/moonlight/sessions`)
- 세션 생성 (`POST /api/moonlight/sessions`)
- 세션 중지 (`DELETE /api/moonlight/sessions/:id`)

## 배포

### Nginx 배포

1. 빌드:
   ```bash
   npm run build
   ```

2. dist/ 복사:
   ```bash
   sudo cp -r dist/* /var/www/html/moonlight/
   ```

3. Nginx 설정 (/etc/nginx/conf.d/auth-portal.conf):
   ```nginx
   location /moonlight/ {
       alias /var/www/html/moonlight/;
       try_files $uri $uri/ /moonlight/index.html;
       index index.html;
   }
   ```

## 버전

**버전**: 1.0.0
**최종 업데이트**: 2025-12-06
