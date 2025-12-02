# 🚀 App Framework (app_5174)

리눅스 네이티브 애플리케이션을 웹 브라우저에서 실행 가능한 임베딩 프레임워크

---

## 📋 프로젝트 개요

### 목표
- Apptainer 컨테이너 기반 리눅스 앱을 웹에서 실행
- 재사용 가능한 컴포넌트 프레임워크  
- 다양한 웹페이지에 임베딩 가능 (iframe, Web Component, React)

### 기술 스택
- **Frontend**: React 19 + TypeScript + Vite
- **Backend**: kooCAEWebServer_5000 (기존)
- **Container**: Apptainer (apptainer/app/)
- **Display**: noVNC / GTK Broadway / WebRTC

---

## 🚀 빠른 시작

### 개발 서버 시작

\`\`\`bash
# 간단한 방법
./dev.sh

# 또는 직접
npm run dev
\`\`\`

**접속**: http://localhost:5174

### 다른 프론트엔드에서 통합하기

다른 프론트엔드 프로젝트에서 이 App Framework를 사용하려면:

📘 **[통합 가이드 보기](./INTEGRATION_GUIDE.md)**

- REST API 직접 호출 (모든 프론트엔드)
- React 컴포넌트 임베딩 (React 전용)
- iframe 임베딩 (모든 프론트엔드)
- 실전 예시 및 코드

---

## 📦 Development Progress

### ✅ Phase 1: Foundation (완료)

1. **프로젝트 구조**
   - Vite + React + TypeScript 초기화
   - 디렉토리 구조 구축

2. **타입 정의**
   - app.types.ts, display.types.ts, embed.types.ts

3. **API Service**
   - kooCAEWebServer_5000 연동

4. **개발 스크립트**
   - dev.sh, test-standalone.sh, test-embed.sh

📄 [Phase 1 완료 보고서](./PHASE1_COMPLETE.md)

---

### ✅ Phase 2: BaseApp Framework (완료)

1. **Core Components**
   - AppContainer: 최상위 앱 컨테이너
   - DisplayFrame: noVNC/Broadway 렌더링
   - Toolbar: 앱 컨트롤 툴바
   - ControlPanel: Display 품질/압축 조정
   - StatusBar: 세션/연결 상태 표시

2. **Custom Hooks**
   - useAppSession: 세션 생명주기 관리
   - useDisplay: Display 연결 관리
   - useWebSocket: WebSocket 통신
   - useAppLifecycle: 통합 생명주기 관리

3. **BaseApp Abstract Class**
   - 모든 앱의 베이스 클래스
   - 생명주기 훅 제공
   - 커스터마이징 가능한 렌더링

4. **App Registry System**
   - 앱 등록/조회/검색
   - 동적 컴포넌트 로드

📄 [Phase 2 완료 보고서](./PHASE2_COMPLETE.md)

**🎨 Demo**: http://localhost:5174 접속 후 "View Phase 2 Demo" 버튼 클릭

---

### ✅ Phase 3: Apptainer Container & Deployment (완료)

1. **Apptainer Container Build**
   - GEdit + VNC 컨테이너 정의 (gedit.def)
   - TigerVNC + websockify 통합
   - noVNC 웹 클라이언트 내장

2. **Container Deployment**
   - 이미지 빌드: `/opt/apptainers/apps/gedit/gedit.sif`
   - 자동 배포 스크립트 (deploy_apptainers.sh)
   - 가시화 노드 동기화 (viz-node001)

3. **Slurm Job Template**
   - gedit_vnc_job.sh: 가시화 노드에서 실행
   - VNC 포트 동적 할당
   - 세션 정보 파일 생성 (/tmp/app_session_*.info)

📄 [Phase 3 완료 보고서](./docs/PHASE3_COMPLETE.md) _(예정)_

---

### ✅ Phase 4: Slurm Integration (완료)

1. **Architecture Redesign**
   - 직접 Apptainer 실행 → Slurm 작업 제출로 변경
   - Access Node에서 VNC 충돌 문제 해결
   - 가시화 노드 분산 처리 아키텍처

2. **SlurmAppManager Implementation**
   - Slurm job 제출 및 모니터링
   - Job 상태 추적 (PENDING → RUNNING)
   - 노드 IP 자동 탐지 및 세션 업데이트

3. **Session Lifecycle Integration**
   - AppSessionService와 SlurmAppManager 통합
   - 백그라운드 Job 모니터링 스레드
   - noVNC displayUrl 동적 생성 (ws://node_ip:port)

4. **Production System Integration**
   - 전체 시스템 자동 시작 (start_complete.sh)
   - Snap Prometheus 충돌 해결
   - 모든 서비스 venv Python 사용 통일

📄 [Phase 4 완료 보고서](./docs/PHASE4_SLURM_INTEGRATION_COMPLETE.md)

---

### 🚀 Phase 5: Production Deployment (완료)

**전체 시스템 시작**:
```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard
./start_complete.sh
```

**서비스 구성**:
- Auth Backend (4430) + Frontend (4431)
- Dashboard Backend (5010) + WebSocket (5011)
- CAE Backend (5000) + Automation (5001)
- Prometheus (9090) + Node Exporter (9100)
- Nginx Reverse Proxy (80)

**접속 URL**:
- 메인 포털: http://110.15.177.120/
- Dashboard: http://110.15.177.120/dashboard/
- CAE: http://110.15.177.120/cae/

**Slurm 클러스터**:
- Controller: access-node (110.15.177.120)
- Compute: node001, node002 (partition: normal)
- Visualization: viz-node001 (partition: viz)

---

### ⏳ Phase 6: Embedding & Distribution (예정)

- iframe 임베딩
- Web Component 구현
- React Component Export
- NPM 패키지 배포

---

## 🎯 사용 예시

### AppContainer 사용

```typescript
import { AppContainer } from '@core/components'

<AppContainer
  metadata={{ id: 'gedit', name: 'GEdit', version: '1.0.0' }}
  config={{ resources: { cpus: 2, memory: '4Gi' }, ... }}
  displayConfig={{ type: 'novnc', quality: 6 }}
  autoStart={true}
  onReady={() => console.log('Ready!')}
/>
```

### useAppLifecycle 사용

```typescript
import { useAppLifecycle } from '@core/hooks'

const lifecycle = useAppLifecycle({
  appId: 'gedit',
  config: appConfig,
  displayConfig: displayConfig,
  autoStart: true,
})

// lifecycle.session, lifecycle.display, lifecycle.websocket
```

자세한 사용법은 [PHASE2_COMPLETE.md](./PHASE2_COMPLETE.md) 참조

---

---

## 🔧 Troubleshooting

### Python Version Mismatch
**증상**: `ImportError: undefined symbol: PyThreadState_GetUnchecked`
**원인**: KooCAE.so가 Python 3.13으로 컴파일되었으나 시스템 python3 (3.10) 사용
**해결**: 각 서비스의 venv 사용
```bash
cd kooCAEWebServer_5000
./venv/bin/python app.py  # system python3이 아님!
```

### Nginx 404 on /auth
**증상**: 로그인 API 호출 시 404 HTML 응답
**원인**: location / 블록이 /auth보다 먼저 매칭됨
**해결**: /etc/nginx/sites-enabled/hpc-portal.conf에서 location /auth를 location / 위로 이동

### Prometheus Port Conflict
**증상**: `bind: address already in use` (port 9090)
**원인**: Snap prometheus가 IPv6로 바인딩되어 있음
**해결**:
```bash
sudo snap stop prometheus
sudo snap disable prometheus
cd prometheus_9090 && ./start.sh
```

### Slurm Controller Down
**증상**: `Unable to contact slurm controller`
**원인**: /run/slurm/ 디렉토리 미존재
**해결**:
```bash
sudo mkdir -p /run/slurm
sudo chown slurm:slurm /run/slurm
sudo systemctl start slurmctld
```

### GEdit Job Memory Error
**증상**: `Memory specification can not be satisfied`
**원인**: viz-node001은 3.5GB RAM, 작업은 4GB 요청
**해결**: slurm_jobs/gedit_vnc_job.sh에서 `--mem=2G`로 조정

---

**Author**: KooSlurmInstallAutomation
**Version**: 0.5.0 (Phase 5 완료 - Production Deployment)
**Updated**: 2025-10-24
