# App Framework 전체 요약 (Phase 1-5)

**프로젝트**: 리눅스 네이티브 앱 웹 임베딩 프레임워크
**기간**: 2025-10-20 ~ 2025-10-24
**상태**: ✅ Production Deployment 완료 (Phase 5)

---

## 🎯 프로젝트 목표

**핵심 질문**: "리눅스 네이티브 애플리케이션(GEdit, ParaView, VSCode 등)을 웹 브라우저에서 실행하려면?"

**답**:
1. Apptainer 컨테이너로 앱 패키징 (VNC 서버 포함)
2. Slurm으로 가시화 노드에 작업 제출
3. noVNC로 브라우저에서 VNC 연결
4. React 컴포넌트로 재사용 가능한 프레임워크 구축

---

## 📊 전체 아키텍처

```
┌──────────────────────────────────────────────────────────────────┐
│                        User Browser                               │
│  ┌────────────────────┐          ┌────────────────────────┐      │
│  │  Dashboard         │          │  App Framework         │      │
│  │  (React)           │◄────────►│  (React Component)     │      │
│  │  Port: 80/dashboard│          │  - AppContainer        │      │
│  └────────────────────┘          │  - DisplayFrame        │      │
│                                   │  - noVNC Client        │      │
│                                   └────────┬───────────────┘      │
└────────────────────────────────────────────┼──────────────────────┘
                                             │ HTTP/WebSocket
                                             │
                    ┌────────────────────────┼────────────────────────┐
                    │      Access Node (110.15.177.120)              │
                    │                        │                        │
                    │  ┌─────────────────────▼────────────────────┐  │
                    │  │  Backend (kooCAEWebServer_5000)          │  │
                    │  │  - AppSessionService                     │  │
                    │  │  - SlurmAppManager                       │  │
                    │  │  - Port: 5000                            │  │
                    │  └─────────────────────┬────────────────────┘  │
                    │                        │ sbatch                │
                    │  ┌─────────────────────▼────────────────────┐  │
                    │  │  Slurm Controller (slurmctld)            │  │
                    │  │  - Job Queue                             │  │
                    │  │  - Resource Allocation                   │  │
                    │  └──────────────────────────────────────────┘  │
                    └────────────────────────┬───────────────────────┘
                                             │ Job Dispatch
                                             │
                    ┌────────────────────────▼───────────────────────┐
                    │      Viz Node (viz-node001: 192.168.122.252)   │
                    │                                                 │
                    │  ┌──────────────────────────────────────────┐  │
                    │  │  Slurm Job (sbatch)                      │  │
                    │  │  ┌────────────────────────────────────┐  │  │
                    │  │  │  Apptainer Container               │  │  │
                    │  │  │  ┌──────────────┐  ┌────────────┐  │  │  │
                    │  │  │  │  VNC Server  │  │   GEdit    │  │  │  │
                    │  │  │  │  (TigerVNC)  │  │   (App)    │  │  │  │
                    │  │  │  └──────┬───────┘  └────────────┘  │  │  │
                    │  │  │         │                           │  │  │
                    │  │  │  ┌──────▼───────┐                  │  │  │
                    │  │  │  │ websockify   │                  │  │  │
                    │  │  │  │ (Port: 6080) │◄─────────────────┼──┼──┼─── noVNC Client
                    │  │  │  └──────────────┘  WebSocket       │  │  │
                    │  │  └────────────────────────────────────┘  │  │
                    │  │                                          │  │
                    │  │  /tmp/app_session_xxx.info               │  │
                    │  │  (NODE_IP, VNC_PORT, JOB_ID)            │  │
                    │  └──────────────────────────────────────────┘  │
                    └─────────────────────────────────────────────────┘
```

---

## 📈 Phase별 진행 상황

### ✅ Phase 1: Foundation (2025-10-20)

**목표**: 프로젝트 기반 구축

**성과**:
- Vite + React 19 + TypeScript 프로젝트 초기화
- 타입 정의 (app.types.ts, display.types.ts, embed.types.ts)
- API Service (kooCAEWebServer_5000 연동)
- 개발 스크립트 (dev.sh, test-standalone.sh, test-embed.sh)

**핵심 파일**:
- `/dashboard/app_5174/package.json`
- `/dashboard/app_5174/src/types/`
- `/dashboard/app_5174/src/services/api.ts`

📄 [Phase 1 상세 문서](../PHASE1_COMPLETE.md)

---

### ✅ Phase 2: BaseApp Framework (2025-10-21)

**목표**: 재사용 가능한 앱 프레임워크 구축

**성과**:

1. **Core Components**:
   - `AppContainer`: 최상위 앱 컨테이너
   - `DisplayFrame`: noVNC/Broadway 렌더링
   - `Toolbar`: 앱 컨트롤 (시작/중지/재시작)
   - `ControlPanel`: Display 품질 조정
   - `StatusBar`: 세션/연결 상태

2. **Custom Hooks**:
   - `useAppSession`: 세션 생명주기 관리
   - `useDisplay`: Display 연결 관리
   - `useWebSocket`: WebSocket 통신
   - `useAppLifecycle`: 통합 생명주기

3. **BaseApp Abstract Class**:
   ```typescript
   abstract class BaseApp extends React.Component {
     abstract onBeforeStart(): void
     abstract onAfterStart(): void
     abstract onBeforeStop(): void
     abstract renderToolbar(): ReactNode
     abstract renderStatusBar(): ReactNode
   }
   ```

4. **App Registry**:
   - 앱 등록/조회/검색 시스템
   - 동적 컴포넌트 로드

**핵심 파일**:
- `/dashboard/app_5174/src/core/components/AppContainer.tsx`
- `/dashboard/app_5174/src/core/hooks/useAppLifecycle.ts`
- `/dashboard/app_5174/src/core/BaseApp.tsx`

📄 [Phase 2 상세 문서](../PHASE2_COMPLETE.md)

---

### ✅ Phase 3: Apptainer Container & Deployment (2025-10-23)

**목표**: GEdit 앱을 Apptainer 컨테이너로 패키징

**성과**:

1. **Apptainer Container**:
   - Ubuntu 22.04 + GEdit + TigerVNC + websockify
   - 컨테이너 정의: `apptainer/gedit.def`
   - 빌드 스크립트: `build_gedit.sh`
   - 이미지 크기: ~250MB

2. **Deployment**:
   - Access Node: `/home/koopark/claude/.../app_5174/gedit.sif` (빌드)
   - Viz Nodes: `/opt/apptainers/apps/gedit/gedit.sif` (배포)
   - 자동 배포: `deploy_apptainers.sh`

3. **Slurm Job Template**:
   - `slurm_jobs/gedit_vnc_job.sh`
   - Partition: viz
   - Resources: 2 CPUs, 2GB RAM
   - 환경 변수: SESSION_ID, VNC_PORT
   - Job Info 파일: `/tmp/app_session_${SESSION_ID}.info`

**테스트 결과**:
```bash
sbatch --export SESSION_ID=test-001,VNC_PORT=6080 gedit_vnc_job.sh
# Submitted batch job 181
# ✅ GEdit 화면 정상 표시 (ws://192.168.122.252:6080)
```

**핵심 파일**:
- `/dashboard/app_5174/apptainer/gedit.def`
- `/dashboard/app_5174/slurm_jobs/gedit_vnc_job.sh`
- `/opt/apptainers/apps/gedit/gedit.sif` (viz 노드)

📄 [Phase 3 상세 문서](./PHASE3_COMPLETE.md)

---

### ✅ Phase 4: Slurm Integration (2025-10-24)

**목표**: Backend에서 Slurm으로 Job 제출 자동화

**배경**:
- **문제**: Access Node에서 Apptainer 직접 실행 시 VNC 포트 충돌
- **해결**: Slurm을 통해 가시화 노드로 작업 분산

**아키텍처 변경**:
```
Before: Frontend → Backend → ApptainerManager → 로컬 Apptainer 실행 (❌ 충돌)
After:  Frontend → Backend → SlurmAppManager → sbatch → Viz Node Apptainer (✅)
```

**성과**:

1. **SlurmAppManager 구현**:
   ```python
   class SlurmAppManager:
       def submit_app_job(session_id, app_id, vnc_port):
           cmd = ['sbatch', '--export', f'SESSION_ID={session_id},...', job_script]
           # Job ID 파싱, 반환

       def get_job_status_info(session_id):
           # /tmp/app_session_xxx.info 읽기
           # node_ip, vnc_port, status 반환

       def cancel_job(session_id):
           # scancel로 Job 취소
   ```

2. **AppSessionService 통합**:
   - `_start_real_session()`: Slurm Job 제출
   - `_monitor_job_for_session()`: Job 상태 모니터링 (백그라운드 스레드)
   - 세션 업데이트: `displayUrl = ws://node_ip:port`

3. **Session Flow**:
   ```
   Creating → (sbatch) → Pending → (Job 시작) → Running → (VNC 연결)
   ```

**핵심 파일**:
- `/dashboard/kooCAEWebServer_5000/services/slurm_app_manager.py`
- `/dashboard/kooCAEWebServer_5000/services/app_session_service.py`

📄 [Phase 4 상세 문서](./PHASE4_SLURM_INTEGRATION_COMPLETE.md)

---

### ✅ Phase 5: Production Deployment (2025-10-24)

**목표**: 전체 시스템 통합 및 자동화

**성과**:

1. **서비스 통합**:
   - Auth Backend (4430) + Frontend (4431)
   - Dashboard Backend (5010) + WebSocket (5011)
   - CAE Backend (5000) + Automation (5001)
   - Prometheus (9090) + Node Exporter (9100)
   - Nginx Reverse Proxy (80)

2. **자동 시작 스크립트**:
   ```bash
   ./start_complete.sh
   ```
   - 모든 기존 프로세스 종료
   - Snap Prometheus 자동 중지
   - 각 서비스 venv Python 사용
   - 포트 충돌 자동 해결

3. **Nginx 라우팅**:
   - `/` → Auth Portal (4431)
   - `/dashboard/` → Dashboard Frontend (static)
   - `/api/` → Dashboard Backend (5010)
   - `/cae/` → CAE Frontend (static)
   - `/cae/api` → CAE Backend (5000)

4. **Slurm 클러스터**:
   - Controller: access-node
   - Compute: node001, node002 (partition: normal)
   - Visualization: viz-node001 (partition: viz)

**접속 URL**:
- 메인 포털: http://110.15.177.120/
- Dashboard: http://110.15.177.120/dashboard/
- CAE: http://110.15.177.120/cae/

**핵심 파일**:
- `/dashboard/start_complete.sh`
- `/etc/nginx/sites-enabled/hpc-portal.conf`
- `/dashboard/kooCAEWebServer_5000/start.sh`

---

## 🔧 해결한 주요 문제들

### 1. Python Version Mismatch
**증상**: `ImportError: undefined symbol: PyThreadState_GetUnchecked`
**원인**: KooCAE.so (Python 3.13) vs system python3 (3.10)
**해결**: 각 서비스의 venv 사용 (`./venv/bin/python app.py`)

### 2. Nginx Routing 404
**증상**: `/auth/test/login` 호출 시 404 HTML 응답
**원인**: `location /` 블록이 `/auth`보다 먼저 매칭
**해결**: location 블록 순서 변경 (`/auth` → `/` 순서로)

### 3. Prometheus Port Conflict
**증상**: `bind: address already in use` (port 9090)
**원인**: Snap prometheus가 IPv6로 바인딩
**해결**: Snap prometheus 자동 중지/비활성화 (start_complete.sh)

### 4. Slurm Controller Down
**증상**: `Unable to contact slurm controller`
**원인**: `/run/slurm/` 디렉토리 미존재
**해결**: 디렉토리 생성 및 권한 설정

### 5. GEdit Memory Error
**증상**: `Memory specification can not be satisfied`
**원인**: viz-node001 (3.5GB) vs Job 요청 (4GB)
**해결**: `--mem=2G`로 조정

### 6. Missing Dependencies
**증상**: `ModuleNotFoundError: flask_socketio`, `paramiko`, `redis`
**원인**: backend_5010 venv에 미설치
**해결**: `pip install flask-socketio python-socketio paramiko redis`

---

## 📁 최종 디렉토리 구조

```
dashboard/
├── app_5174/                           # App Framework
│   ├── src/
│   │   ├── core/
│   │   │   ├── components/             # AppContainer, DisplayFrame, ...
│   │   │   ├── hooks/                  # useAppLifecycle, useAppSession, ...
│   │   │   └── BaseApp.tsx
│   │   ├── apps/
│   │   │   └── GEditApp/               # GEdit 예제 앱
│   │   └── registry/
│   │       └── AppRegistry.ts
│   ├── apptainer/
│   │   └── gedit.def                   # Apptainer 컨테이너 정의
│   ├── slurm_jobs/
│   │   └── gedit_vnc_job.sh            # Slurm 작업 템플릿
│   ├── docs/
│   │   ├── PHASE1_COMPLETE.md
│   │   ├── PHASE2_COMPLETE.md
│   │   ├── PHASE3_COMPLETE.md
│   │   ├── PHASE4_SLURM_INTEGRATION_COMPLETE.md
│   │   └── SUMMARY.md                  # 이 문서
│   └── README.md
│
├── kooCAEWebServer_5000/               # CAE Backend
│   ├── services/
│   │   ├── app_session_service.py      # 세션 생명주기 관리
│   │   └── slurm_app_manager.py        # Slurm Job 관리
│   ├── routes/
│   │   └── app_routes.py               # /api/app/* 엔드포인트
│   ├── venv/                           # Python 3.13
│   ├── start.sh
│   └── app.py
│
├── backend_5010/                       # Dashboard Backend
│   ├── venv/                           # Python 3.12
│   └── app.py
│
├── websocket_5011/                     # WebSocket Server
│   └── websocket_server_enhanced.py
│
├── auth_portal_4430/                   # Auth Backend
│   └── app.py
│
├── auth_portal_4431/                   # Auth Frontend (Dev)
│   └── vite.config.ts
│
├── frontend_3010/                      # Dashboard Frontend
│   └── dist/                           # Static files (Nginx)
│
├── vnc_service_8002/                   # VNC Service Frontend
│   └── dist/                           # Static files (Nginx)
│
├── kooCAEWeb_5173/                     # CAE Frontend
│   └── dist/                           # Static files (Nginx)
│
├── prometheus_9090/
├── node_exporter_9100/
├── start_complete.sh                   # 전체 시작 스크립트
├── stop_complete.sh                    # 전체 종료 스크립트
└── deploy_apptainers.sh                # Apptainer 이미지 배포
```

---

## 🧪 End-to-End 테스트 시나리오

### 시나리오: GEdit 앱 실행

1. **사용자 로그인**:
   ```
   브라우저 → http://110.15.177.120/
   Username: testuser / Password: testpass123
   ```

2. **Dashboard 접속**:
   ```
   로그인 후 → Dashboard 클릭
   → http://110.15.177.120/dashboard/
   ```

3. **GEdit 앱 실행** (예정 - 프론트엔드 통합 필요):
   ```
   Dashboard → App Launcher → GEdit 클릭
   POST /api/app/sessions { app_id: "gedit" }
   ```

4. **Backend 처리**:
   ```python
   # AppSessionService
   session_id = generate_id()
   vnc_port = allocate_port()  # 6080

   # SlurmAppManager
   sbatch --export SESSION_ID=xxx,VNC_PORT=6080 gedit_vnc_job.sh
   # Job 181 submitted to viz-node001
   ```

5. **Job 실행**:
   ```bash
   # viz-node001
   apptainer run gedit.sif
   # VNC server: :1 (5901)
   # websockify: 6080 → 5901
   # Job info: /tmp/app_session_xxx.info
   ```

6. **Session 업데이트**:
   ```python
   # Monitoring thread
   job_info = read('/tmp/app_session_xxx.info')
   session['displayUrl'] = 'ws://192.168.122.252:6080'
   session['status'] = 'running'
   ```

7. **noVNC 연결**:
   ```javascript
   // Frontend
   const session = await api.getSession(sessionId)
   // session.displayUrl = "ws://192.168.122.252:6080"

   const rfb = new RFB(canvas, session.displayUrl)
   // ✅ GEdit 화면 표시
   ```

---

## 📊 성능 및 제약사항

### 리소스 요구사항 (per session)

| 항목 | GEdit | 향후 ParaView (예상) |
|------|-------|----------------------|
| CPU | 2 cores | 4-8 cores |
| Memory | 2GB | 8-16GB |
| GPU | N/A | 1x GPU (NVIDIA) |
| Disk | 250MB | 500MB-1GB |
| Network | ~10Mbps | ~50Mbps (고화질) |

### Viz Node 용량

- **viz-node001**: 3.5GB RAM, 동시 세션 1-2개
- **확장 필요**: GPU 노드 추가 (ParaView, Blender 등)

### 네트워크 대역폭

- noVNC: 1-20Mbps (압축률에 따라)
- 동시 사용자 10명 가정: ~100Mbps 필요

---

## 🚀 향후 계획

### Phase 6: Embedding & Distribution (예정)

1. **iframe Embedding**:
   ```html
   <iframe src="http://110.15.177.120/app/gedit?embed=true"></iframe>
   ```

2. **Web Component**:
   ```html
   <app-container app-id="gedit" auto-start></app-container>
   ```

3. **React Component Export**:
   ```javascript
   import { GEditApp } from '@hpc-portal/app-framework'
   <GEditApp config={...} />
   ```

4. **NPM Package**:
   ```bash
   npm install @hpc-portal/app-framework
   ```

### 추가 앱 개발

- **ParaView**: 3D 가시화 (GPU 필요)
- **VSCode**: 웹 기반 IDE
- **Blender**: 3D 모델링
- **MATLAB**: 엔지니어링 계산

### 성능 최적화

- **H.264 인코딩**: 대역폭 절감 (websockify → WebRTC)
- **GPU 가속**: ParaView 등을 위한 GPU 노드 추가
- **세션 재연결**: 네트워크 끊김 시 자동 재연결
- **Multi-node 로드밸런싱**: viz 노드 여러 대 사용

---

## 📚 참고 자료

### 내부 문서
- [Phase 1 완료 보고서](../PHASE1_COMPLETE.md)
- [Phase 2 완료 보고서](../PHASE2_COMPLETE.md)
- [Phase 3 완료 보고서](./PHASE3_COMPLETE.md)
- [Phase 4 완료 보고서](./PHASE4_SLURM_INTEGRATION_COMPLETE.md)
- [README](../README.md)

### 외부 참고
- [Apptainer Documentation](https://apptainer.org/docs/)
- [Slurm Documentation](https://slurm.schedmd.com/documentation.html)
- [noVNC GitHub](https://github.com/novnc/noVNC)
- [TigerVNC](https://tigervnc.org/)
- [websockify](https://github.com/novnc/websockify)

---

## ✅ 프로젝트 체크리스트

### 기반 구축
- [x] React + TypeScript 프로젝트 초기화
- [x] 타입 정의 및 API 서비스
- [x] 개발 환경 구축

### 프레임워크 개발
- [x] Core Components (AppContainer, DisplayFrame, ...)
- [x] Custom Hooks (useAppLifecycle, ...)
- [x] BaseApp Abstract Class
- [x] App Registry System

### 컨테이너화
- [x] Apptainer 컨테이너 정의 (GEdit)
- [x] 컨테이너 빌드 스크립트
- [x] 이미지 배포 자동화
- [x] Slurm Job 템플릿

### Backend 통합
- [x] SlurmAppManager 구현
- [x] AppSessionService와 통합
- [x] Job 모니터링 스레드
- [x] Session 생명주기 관리

### Production 배포
- [x] 전체 서비스 자동 시작
- [x] Nginx 라우팅 설정
- [x] Python venv 통일
- [x] 포트 충돌 해결
- [x] Prometheus 모니터링
- [x] Slurm 클러스터 구성

### 문서화
- [x] Phase별 완료 보고서
- [x] README 업데이트
- [x] Troubleshooting 가이드
- [x] 전체 요약 문서 (이 문서)

### 미완료 (Phase 6)
- [ ] Frontend 앱 런처 UI 통합
- [ ] End-to-End 테스트 (브라우저)
- [ ] iframe Embedding
- [ ] Web Component
- [ ] React Component Export
- [ ] NPM Package 배포

---

## 🎓 학습 내용 및 인사이트

### 1. 아키텍처 설계의 중요성

**초기 문제**: Access Node에서 Apptainer 직접 실행 → VNC 포트 충돌

**해결**: Slurm을 활용한 분산 아키텍처
- Job을 가시화 노드로 분산
- 노드별 리소스 격리
- 확장 가능한 구조

**교훈**: HPC 환경에서는 워크로드 매니저 활용이 필수

### 2. Python 가상 환경 관리

**문제**: KooCAE.so가 Python 3.13으로 컴파일되어 있으나 시스템은 3.10

**해결**: 각 서비스마다 독립적인 venv 사용

**교훈**:
- C 확장 모듈은 Python 버전에 민감
- 프로덕션 환경은 venv 필수
- start 스크립트에 venv 활성화 포함

### 3. Nginx Reverse Proxy 라우팅

**문제**: location 블록 순서 문제로 /auth API가 404

**해결**: 구체적인 경로 (`/auth`)를 일반 경로 (`/`) 위에 배치

**교훈**:
- Nginx는 첫 번째 매칭되는 location 사용
- 경로 우선순위: 구체적 → 일반적

### 4. Slurm Job 정보 전달

**Challenge**: Backend가 Job의 실행 노드 IP를 어떻게 알 수 있나?

**Solution**: Job 내부에서 정보 파일 생성
```bash
cat > "/tmp/app_session_${SESSION_ID}.info" << EOF
NODE_IP=$(hostname -I | awk '{print $1}')
VNC_PORT=$VNC_PORT
EOF
```

**교훈**: Slurm Job과 외부 서비스 간 통신은 파일 시스템 활용

### 5. Apptainer vs Docker in HPC

**Apptainer 장점**:
- Rootless 실행 (보안)
- SIF 파일 포맷 (읽기 전용, 이동 용이)
- HPC 환경 최적화

**Docker와의 차이**:
- Docker: 개발/데브옵스 환경
- Apptainer: HPC/연구 환경

---

## 🏆 주요 성과

1. **재사용 가능한 프레임워크**:
   - BaseApp을 상속하여 새 앱 쉽게 추가
   - 공통 생명주기 관리 로직 캡슐화

2. **분산 아키텍처**:
   - Slurm을 통한 워크로드 분산
   - 확장 가능한 구조 (노드 추가 가능)

3. **자동화**:
   - 한 명령으로 전체 시스템 시작/중지
   - 컨테이너 이미지 자동 배포

4. **프로덕션 준비**:
   - Nginx 리버스 프록시
   - 서비스별 독립 venv
   - 모니터링 (Prometheus)

5. **문서화**:
   - Phase별 상세 보고서
   - Troubleshooting 가이드
   - 전체 아키텍처 다이어그램

---

## 📞 Contact & Support

**개발자**: KooSlurmInstallAutomation
**프로젝트 경로**: `/home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/app_5174/`
**최종 업데이트**: 2025-10-24
**버전**: 0.5.0 (Phase 5 완료)

---

**다음 단계**: Phase 6 - Embedding & Distribution 🚀
