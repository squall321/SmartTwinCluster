# GPU 원격 데스크톱 시각화 서버 개발 계획 (최종 전략판)

**작성일**: 2025-10-16
**버전**: 7.0 (계획 전략 중심, 코드 제외)
**프로젝트**: Slurm Cluster Dashboard - GPU Remote Desktop with SAML SSO
**목적**: SAML 통합 인증 + Apptainer 기반 GPU VNC 시각화 시스템 구축 전략

---

## 📋 목차

- [Part 0: 현황 분석 및 전제 조건](#part-0-현황-분석-및-전제-조건)
- [Part 1: 사전 준비 (Prerequisites)](#part-1-사전-준비-prerequisites)
- [Part 2: 통합 인증 시스템 (Auth Portal)](#part-2-통합-인증-시스템-auth-portal)
- [Part 3: VNC 시각화 시스템](#part-3-vnc-시각화-시스템)
- [Part 4: 보안 및 성능](#part-4-보안-및-성능)
- [Part 5: 모니터링 및 운영](#part-5-모니터링-및-운영)
- [Part 6: 개발 실행 계획](#part-6-개발-실행-계획)
- [Part 7: 즉시 실행 가이드](#part-7-즉시-실행-가이드)
- [Part 8: 위험 관리 및 트러블슈팅](#part-8-위험-관리-및-트러블슈팅)

---

## Part 0: 현황 분석 및 전제 조건

### 0.1 현재 시스템 현황

#### 기존 서비스 구성
현재 프로젝트에는 **8개의 서비스**가 이미 운영 중:

**관리 대시보드 시스템** (3개 서비스):
- `frontend_3010/` - 클러스터 관리 프론트엔드 (React)
- `backend_5010/` - Slurm API 백엔드 (Flask/Python)
- `websocket_5011/` - 실시간 모니터링 WebSocket

**CAE 자동화 시스템** (3개 서비스):
- `kooCAEWeb_5173/` - 자동화 워크플로우 프론트엔드 (React)
- `kooCAEWebServer_5000/` - 자동화 워크플로우 백엔드 (Flask)
- `kooCAEWebAutomationServer_5001/` - 자동화 프록시 서버

**모니터링 시스템** (2개 서비스):
- `prometheus_9090/` - 메트릭 수집
- `node_exporter_9100/` - 노드 메트릭

#### 기존 Slurm 클러스터 설정
- 설정 파일: `/home/koopark/claude/KooSlurmInstallAutomationRefactory/my_cluster.yaml`
- Slurm 버전: 22.05.8
- **현재 상태**:
  - `gpu_computing.nvidia.enabled: false` ← ⚠️ VNC를 위해 활성화 필요
  - VNC 전용 파티션 없음 ← ⚠️ vnc 파티션 추가 필요
  - `sandbox_path` 미정의 ← ⚠️ Apptainer 샌드박스 경로 추가 필요

#### 기존 Apptainer 환경
- 디렉토리: `/home/koopark/claude/KooSlurmInstallAutomationRefactory/apptainers/`
- 기존 이미지 정의: `ubuntu_python.def`
- Apptainer 버전: 1.2.5 이상 필요

### 0.2 개발 목표 및 범위

#### 핵심 목표
1. **통합 인증**: SAML 2.0 SSO를 통한 단일 인증 시스템 구축
2. **서비스 통합**: 기존 8개 서비스에 JWT 토큰 기반 인증 추가
3. **VNC 시각화**: GPU 가속 Ubuntu 데스크톱 원격 접속 기능 추가
4. **그룹 기반 권한**: HPC-Admins, HPC-Users, GPU-Users, Automation-Users 4개 그룹 RBAC

#### 개발 범위
- **새로 개발할 서비스**: 5개
  - Auth Portal Backend (4430)
  - Auth Portal Frontend (4431)
  - Nginx Reverse Proxy (443)
  - saml-idp (7000, 개발용)
  - Redis Session Store (6379)

- **수정할 서비스**: 5개
  - backend_5010 → JWT 미들웨어 추가
  - frontend_3010 → JWT 토큰 처리 추가
  - kooCAEWebServer_5000 → JWT 미들웨어 추가
  - kooCAEWeb_5173 → JWT 토큰 처리 추가
  - my_cluster.yaml → GPU 및 VNC 설정 추가

### 0.3 기술 스택 결정

#### 인증 스택
- **SAML 2.0**: SSO 프로토콜
- **ADFS**: 프로덕션 Identity Provider (향후 연동)
- **saml-idp**: 개발용 IdP (Node.js)
- **JWT (HS256)**: 서비스 간 인증 토큰
- **Redis 7+**: 세션 스토리지

#### VNC 스택
- **Apptainer 1.2.5+**: 컨테이너 런타임
- **TurboVNC 3.1+**: GPU 가속 VNC 서버
- **VirtualGL 3.1+**: OpenGL 리다이렉션
- **XFCE4**: 경량 데스크톱 환경
- **noVNC 1.4+**: 웹 기반 VNC 클라이언트
- **WebSockify**: VNC-WebSocket 프록시

#### 인프라 스택
- **Backend**: Python 3.10+, Flask 3.0+, python3-saml 1.15+, PyJWT 2.8+
- **Frontend**: React 18+, TypeScript 5+, Vite 5+
- **Proxy**: Nginx 1.24+
- **Monitoring**: Prometheus 2.45+, Grafana 10+

---

## Part 1: 사전 준비 (Prerequisites)

### 1.1 Slurm 클러스터 설정 검토 및 업데이트

#### 필수 수정 사항
`my_cluster.yaml` 파일에서 다음 3가지 변경 필요:

**변경 1: GPU Computing 활성화**
```yaml
# 현재 (Line 195-201)
gpu_computing:
  nvidia:
    enabled: false
    driver_version: "470.82.01"
    cuda_version: "11.4"

# → 변경 후
gpu_computing:
  nvidia:
    enabled: true  # ← false에서 true로 변경
    driver_version: "470.82.01"
    cuda_version: "11.4"
```

**변경 2: VNC 파티션 추가**
```yaml
# slurm_config.partitions 섹션에 추가 (Line 93-105 아래)
partitions:
  - name: "gpu"
    nodes: "compute01"
    default: true
    max_time: "7-00:00:00"
    max_nodes: 1
    state: "UP"
  - name: "debug"
    nodes: "compute01"
    default: false
    max_time: "00:30:00"
    max_nodes: 1
    state: "UP"
  # 아래 vnc 파티션 추가
  - name: "vnc"
    nodes: "compute01"
    default: false
    max_time: "24:00:00"
    max_nodes: 1
    state: "UP"
    exclusive: false  # 여러 VNC 세션 동시 실행 가능
```

**변경 3: Apptainer Sandbox 경로 추가**
```yaml
# slurm_config 섹션에 추가 (Line 76-82)
slurm_config:
  version: "22.05.8"
  install_path: "/usr/local/slurm"
  config_path: "/usr/local/slurm/etc"
  log_path: "/var/log/slurm"
  spool_path: "/var/spool/slurm"
  state_save_location: "/var/spool/slurm/state"
  sandbox_path: "/scratch/apptainer_sandboxes"  # ← 이 줄 추가
```

#### 업데이트 절차
1. `my_cluster.yaml` 백업 생성
2. 위 3가지 변경 사항 반영
3. Slurm 설정 재생성 스크립트 실행 (존재하는 경우)
4. slurmctld 재시작
5. `sinfo` 명령으로 vnc 파티션 확인

### 1.2 Apptainer 환경 검증

#### 검증 항목
1. **Apptainer 설치 확인**
   - 버전: `apptainer --version` (1.2.5 이상)
   - 권한: 일반 사용자 실행 가능 여부
   - Fakeroot: `apptainer config fakeroot --add <user>` 설정 여부

2. **샌드박스 디렉토리 준비**
   - 경로: `/scratch/apptainer_sandboxes/`
   - 권한: 755, slurm 사용자가 쓰기 가능
   - 공간: 최소 50GB 이상 권장

3. **GPU 접근 확인**
   - `apptainer exec --nv <image> nvidia-smi` 테스트
   - CUDA 라이브러리 마운트 확인
   - 드라이버 버전 호환성 확인

### 1.3 네트워크 및 방화벽 설정

#### 포트 할당 계획

| 포트 | 서비스 | 용도 | 상태 |
|------|--------|------|------|
| 443 | Nginx | HTTPS 진입점 | 신규 |
| 4430 | Auth Backend | SAML + JWT 발급 | 신규 |
| 4431 | Auth Frontend | SSO 로그인 UI | 신규 |
| 7000 | saml-idp | 개발용 IdP | 신규 |
| 6379 | Redis | 세션 저장소 | 신규 |
| 3010 | Dashboard Frontend | 관리 UI | 기존 |
| 5010 | Dashboard Backend | Slurm API | 기존 |
| 5011 | WebSocket | 실시간 모니터링 | 기존 |
| 5173 | CAE Frontend | 자동화 UI | 기존 |
| 5000 | CAE Backend | 워크플로우 API | 기존 |
| 5001 | CAE Proxy | 프록시 | 기존 |
| 9090 | Prometheus | 메트릭 수집 | 기존 |
| 9100 | Node Exporter | 노드 메트릭 | 기존 |
| 5900-6100 | VNC Sessions | 동적 할당 | 신규 범위 |

#### 방화벽 규칙
- 외부 접근: 443만 허용
- 내부 통신: 위 모든 포트 허용
- VNC 포트: 5900-6100 범위, 내부 전용
- Redis: 6379, localhost 바인딩

---

## Part 2: 통합 인증 시스템 (Auth Portal)

### 2.1 전체 아키텍처 설계

#### 인증 흐름 다이어그램
```
┌────────────────────────────────────────────────────────────────┐
│                       인증 플로우                                │
└────────────────────────────────────────────────────────────────┘

User Browser
    │
    ↓ (1) https://domain.com 접속
┌─────────────────────┐
│ Nginx (443)         │
│ - HTTPS 종료        │
│ - 라우팅            │
└──────┬──────────────┘
       │
       ↓ (2) /auth/* → 4431 프록시
┌─────────────────────┐
│ Auth Frontend       │
│ (React, 4431)       │
│ - 로그인 UI         │
│ - ServiceMenu UI    │
└──────┬──────────────┘
       │
       ↓ (3) SSO 로그인 버튼 클릭
┌─────────────────────┐
│ Auth Backend (4430) │
│ - SAML Request 생성 │
└──────┬──────────────┘
       │
       ↓ (4) SAML AuthnRequest
┌─────────────────────┐
│ saml-idp (7000)     │ ← 개발용, 나중에 ADFS로 교체
│ - 사용자 인증       │
│ - SAML Response     │
└──────┬──────────────┘
       │
       ↓ (5) SAML Response with Attributes
┌─────────────────────┐
│ Auth Backend (4430) │
│ - SAML 검증         │
│ - JWT 토큰 생성     │
│ - Redis 세션 저장   │
└──────┬──────────────┘
       │
       ↓ (6) JWT Token + ServiceMenu 리다이렉트
┌─────────────────────┐
│ Auth Frontend       │
│ - 토큰 localStorage │
│ - 서비스 목록 표시  │
└──────┬──────────────┘
       │
       ├─→ (7a) Dashboard 선택 → https://domain.com/dashboard?token=<JWT>
       │   ↓
       │   ┌─────────────────────┐
       │   │ frontend_3010       │
       │   │ - JWT 추출/저장     │
       │   │ - /api/* → 5010     │
       │   └──────┬──────────────┘
       │          ↓
       │   ┌─────────────────────┐
       │   │ backend_5010        │
       │   │ - JWT 검증 미들웨어 │
       │   │ - Slurm API 호출    │
       │   └─────────────────────┘
       │
       └─→ (7b) CAE 선택 → https://domain.com/cae?token=<JWT>
           ↓
           ┌─────────────────────┐
           │ kooCAEWeb_5173      │
           │ - JWT 추출/저장     │
           │ - /api/* → 5000     │
           └──────┬──────────────┘
                  ↓
           ┌─────────────────────┐
           │ kooCAEWebServer     │
           │ - JWT 검증 미들웨어 │
           │ - 워크플로우 실행   │
           └─────────────────────┘
```

### 2.2 Auth Portal 구조

#### 디렉토리 구조
```
dashboard/
├── auth_portal_4430/          # 신규 백엔드
│   ├── app.py                 # Flask 앱
│   ├── saml_handler.py        # SAML 인증 로직
│   ├── jwt_handler.py         # JWT 토큰 발급/검증
│   ├── redis_client.py        # Redis 세션 관리
│   ├── config.py              # 설정 (IdP 메타데이터 등)
│   ├── requirements.txt
│   └── saml/
│       ├── settings.json      # python3-saml 설정
│       ├── certs/
│       │   ├── sp.crt         # Service Provider 인증서
│       │   └── sp.key         # Service Provider 개인키
│       └── metadata/
│           └── idp_metadata.xml
│
├── auth_portal_4431/          # 신규 프론트엔드
│   ├── src/
│   │   ├── App.tsx
│   │   ├── pages/
│   │   │   ├── Login.tsx      # SSO 로그인 페이지
│   │   │   └── ServiceMenu.tsx # 서비스 선택 메뉴
│   │   ├── utils/
│   │   │   └── jwt.ts         # JWT 토큰 유틸리티
│   │   └── api/
│   │       └── auth.ts        # Auth API 클라이언트
│   ├── package.json
│   └── vite.config.ts
│
└── saml_idp_7000/             # 신규 개발용 IdP
    ├── server.js              # saml-idp 서버
    ├── users.json             # 테스트 사용자 DB
    └── package.json
```

#### JWT 토큰 페이로드 설계
```json
{
  "sub": "user01",              // 사용자 ID
  "email": "user01@hpc.local",  // 이메일
  "name": "홍길동",              // 표시 이름
  "groups": [                   // 그룹 목록
    "HPC-Users",
    "GPU-Users"
  ],
  "permissions": [              // 자동 계산된 권한
    "dashboard.view",
    "jobs.submit",
    "vnc.create"
  ],
  "iat": 1697123456,            // 발급 시각
  "exp": 1697127056,            // 만료 시각 (1시간 후)
  "iss": "auth-portal",         // 발급자
  "aud": ["dashboard", "cae"]   // 대상 서비스
}
```

### 2.3 인증 플로우

#### Phase 1: 초기 로그인
1. 사용자가 `https://domain.com` 접속
2. Nginx가 Auth Frontend (4431)로 라우팅
3. Login.tsx 렌더링 → "SSO 로그인" 버튼 표시
4. 버튼 클릭 → `GET /auth/saml/login` (4430)
5. Auth Backend가 SAML AuthnRequest 생성 → IdP로 리다이렉트
6. IdP (saml-idp:7000)에서 사용자 인증 (user/password)
7. IdP가 SAML Response 생성 → `POST /auth/saml/acs` (4430)
8. Auth Backend:
   - SAML Response 검증
   - 사용자 속성 추출 (email, name, groups)
   - JWT 토큰 생성 (HS256, 1시간 유효)
   - Redis에 세션 저장 (key: `session:{user_id}`, TTL: 1h)
9. ServiceMenu.tsx로 리다이렉트 + JWT 토큰 전달

#### Phase 2: 서비스 선택
1. ServiceMenu.tsx가 JWT 디코딩 → `groups` 확인
2. 그룹 기반 서비스 목록 표시:
   - `HPC-Admins`: Dashboard, CAE, VNC 모두
   - `HPC-Users`: Dashboard, VNC
   - `GPU-Users`: VNC만
   - `Automation-Users`: CAE만
3. 사용자가 서비스 선택 (예: Dashboard)
4. `https://domain.com/dashboard?token=<JWT>`로 리다이렉트

#### Phase 3: 서비스 접근
1. frontend_3010이 URL 파라미터에서 JWT 추출
2. `localStorage.setItem('jwt_token', token)`
3. 이후 모든 API 요청에 `Authorization: Bearer <JWT>` 헤더 포함
4. backend_5010의 JWT 미들웨어가 토큰 검증:
   - 서명 검증 (HS256 + SECRET_KEY)
   - 만료 시각 확인
   - `aud`에 "dashboard" 포함 여부 확인
5. 검증 성공 시 → `g.user` 객체에 사용자 정보 저장
6. 검증 실패 시 → 401 Unauthorized + 에러 메시지

### 2.4 그룹 기반 권한 관리

#### 그룹 정의
| 그룹 | 설명 | 권한 |
|------|------|------|
| HPC-Admins | 클러스터 관리자 | 모든 서비스 접근, 사용자 관리, 시스템 설정 |
| HPC-Users | 일반 HPC 사용자 | Job Submit, 모니터링, VNC 사용 |
| GPU-Users | GPU 전용 사용자 | VNC 세션만 생성 가능 |
| Automation-Users | 자동화 전용 사용자 | CAE 워크플로우만 사용 |

#### 권한 매트릭스
| 기능 | HPC-Admins | HPC-Users | GPU-Users | Automation-Users |
|------|-----------|-----------|-----------|------------------|
| Dashboard 접근 | ✓ | ✓ | ✗ | ✗ |
| Job Submit (수동) | ✓ | ✓ | ✗ | ✗ |
| Job 취소 (타인 것) | ✓ | ✗ | ✗ | ✗ |
| VNC 세션 생성 | ✓ | ✓ | ✓ | ✗ |
| VNC 세션 종료 (타인 것) | ✓ | ✗ | ✗ | ✗ |
| CAE 워크플로우 | ✓ | ✗ | ✗ | ✓ |
| 사용자 관리 | ✓ | ✗ | ✗ | ✗ |
| 시스템 설정 | ✓ | ✗ | ✗ | ✗ |

#### 권한 검증 전략
- **프론트엔드**: JWT의 `groups`로 UI 요소 표시/숨김 (보안 X, UX용)
- **백엔드**: JWT의 `groups` + `permissions`로 API 호출 허용/거부 (실제 보안)
- **미들웨어 체인**: `jwt_required → group_required(['HPC-Admins', 'HPC-Users'])`

---

## Part 3: VNC 시각화 시스템

### 3.1 Apptainer VNC 이미지 설계

#### 이미지 정의 파일 구조
`apptainers/ubuntu_vnc_gpu.def` 생성 필요:

**주요 구성 요소**:
1. **베이스 이미지**: Ubuntu 22.04
2. **GPU 지원**: NVIDIA CUDA 11.4, driver 470+
3. **VNC 서버**: TurboVNC 3.1+
4. **OpenGL**: VirtualGL 3.1+
5. **데스크톱**: XFCE4
6. **유틸리티**: Firefox, 터미널, 파일 관리자
7. **웹 클라이언트**: noVNC 1.4+
8. **프록시**: WebSockify

#### 빌드 전략
- **이미지 빌드**: `apptainer build ubuntu_vnc_gpu.sif ubuntu_vnc_gpu.def` (root 권한)
- **샌드박스 생성**: `apptainer build --sandbox /scratch/apptainer_sandboxes/vnc_template ubuntu_vnc_gpu.sif`
- **사용자별 복사**: 각 VNC 세션마다 `cp -r vnc_template vnc_user01_session01`

#### 샌드박스 vs SIF 비교
| 특징 | Sandbox | SIF (이미지) |
|------|---------|-------------|
| 쓰기 가능 | ✓ | ✗ |
| 디스크 공간 | 많음 (5-10GB/세션) | 적음 (2GB/이미지) |
| 시작 속도 | 빠름 | 약간 느림 |
| 사용자 데이터 | 내부 저장 | 외부 마운트 필요 |
| VNC 적합도 | ✓✓✓ | ✗ (읽기 전용) |

**결론**: VNC는 반드시 **Sandbox 모드** 사용

### 3.2 VNC 세션 관리 전략

#### 세션 생명주기
```
생성 → 시작 → 실행 중 → 일시정지 → 재개 → 종료 → 정리
  ↓      ↓       ↓         ↓        ↓      ↓      ↓
Slurm Slurm   VNC     VNC        VNC   Slurm  rm
sbatch squeue running stopped   running scancel sandbox
```

#### 세션 메타데이터 저장
각 VNC 세션의 정보를 Redis에 저장:

**Key 형식**: `vnc:session:{session_id}`
**Value (JSON)**:
```json
{
  "session_id": "vnc_user01_20251016_123456",
  "user": "user01",
  "slurm_job_id": "12345",
  "sandbox_path": "/scratch/apptainer_sandboxes/vnc_user01_20251016_123456",
  "vnc_port": 5901,
  "websocket_port": 6081,
  "vnc_password": "<encrypted>",
  "status": "running",
  "created_at": "2025-10-16T12:34:56Z",
  "gpu_id": 0,
  "partition": "vnc",
  "node": "compute01"
}
```

**TTL**: 세션 종료 시 삭제, 최대 24시간 자동 만료

#### Slurm Job 스크립트 구조
각 VNC 세션은 Slurm Job으로 실행:

**Job 파라미터**:
- Partition: `vnc`
- GPU: `--gres=gpu:1`
- 시간: `--time=08:00:00` (최대 24시간)
- 메모리: `--mem=8G`
- CPU: `--cpus-per-task=4`

**Job 스크립트 흐름**:
1. 환경 변수 설정 (VNC_PORT, DISPLAY 등)
2. Sandbox 디렉토리로 이동
3. `apptainer exec --nv --bind /home --writable` 실행
4. 컨테이너 내부에서:
   - VNC 서버 시작 (`vncserver :1 -geometry 1920x1080`)
   - WebSockify 시작 (`websockify 6081 localhost:5901`)
   - 무한 대기 (`while true; do sleep 60; done`)
5. Job 종료 시 cleanup (VNC 서버 중지)

### 3.3 Slurm Job 통합 전략

#### Job 제출 프로세스
1. **사전 검증**:
   - 사용자 권한 확인 (JWT의 `vnc.create` 권한)
   - GPU 가용성 확인 (`sinfo -p vnc -o %C`)
   - 동시 세션 수 제한 확인 (사용자당 최대 2개)

2. **Sandbox 준비**:
   - 템플릿 복사: `cp -r /scratch/.../vnc_template /scratch/.../vnc_{user}_{timestamp}`
   - 권한 설정: `chown -R {uid}:{gid} ...`
   - VNC 패스워드 파일 생성: `.vnc/passwd`

3. **Job 스크립트 생성**:
   - 템플릿에서 변수 치환 (USER, VNC_PORT, SANDBOX_PATH 등)
   - `/tmp/vnc_job_{session_id}.sh` 저장

4. **Job 제출**:
   - `sbatch /tmp/vnc_job_{session_id}.sh`
   - Job ID 반환
   - Redis에 세션 정보 저장

5. **Job 모니터링**:
   - `squeue -j {job_id}` 주기적 호출 (5초마다)
   - 상태: PENDING → RUNNING → COMPLETED/FAILED
   - VNC 서버 준비 확인: `nc -zv {node} {vnc_port}`

#### Job 종료 프로세스
1. **정상 종료 (사용자 요청)**:
   - `scancel {job_id}`
   - VNC 서버 자동 종료 (Job 종료 트리거)
   - Redis 세션 삭제
   - Sandbox 정리 (즉시 or 24시간 후)

2. **비정상 종료**:
   - Job 실패 (OOM, 노드 장애 등)
   - WebSocket 5011로 알림 전송
   - 프론트엔드에 에러 메시지 표시
   - Sandbox는 보존 (디버깅용)

3. **자동 종료**:
   - 24시간 타임아웃
   - 유휴 시간 2시간 초과 (선택 사항)
   - 클러스터 유지보수 모드 진입

### 3.4 API 설계

#### VNC 세션 API 엔드포인트

**1. 세션 목록 조회**
- **Endpoint**: `GET /api/vnc/sessions`
- **Authorization**: JWT (groups: HPC-Admins, HPC-Users, GPU-Users)
- **Query Params**:
  - `user`: 사용자 필터 (admin만 가능)
  - `status`: 상태 필터 (running, pending, stopped)
- **Response**:
```json
{
  "sessions": [
    {
      "session_id": "vnc_user01_20251016_123456",
      "user": "user01",
      "status": "running",
      "created_at": "2025-10-16T12:34:56Z",
      "node": "compute01",
      "gpu_id": 0,
      "vnc_url": "https://domain.com/vnc/vnc_user01_20251016_123456"
    }
  ]
}
```

**2. 세션 생성**
- **Endpoint**: `POST /api/vnc/sessions`
- **Authorization**: JWT (permissions: vnc.create)
- **Request Body**:
```json
{
  "gpu_count": 1,
  "memory_gb": 8,
  "time_hours": 8,
  "resolution": "1920x1080"
}
```
- **Response**:
```json
{
  "session_id": "vnc_user01_20251016_123456",
  "slurm_job_id": "12345",
  "status": "pending",
  "estimated_wait_time_sec": 30
}
```

**3. 세션 상세 조회**
- **Endpoint**: `GET /api/vnc/sessions/{session_id}`
- **Authorization**: JWT (소유자 or admin)
- **Response**:
```json
{
  "session_id": "vnc_user01_20251016_123456",
  "user": "user01",
  "status": "running",
  "slurm_job_id": "12345",
  "vnc_url": "https://domain.com/vnc/vnc_user01_20251016_123456",
  "vnc_password": "abc123",
  "node": "compute01",
  "gpu_id": 0,
  "created_at": "2025-10-16T12:34:56Z",
  "running_time_sec": 3600,
  "remaining_time_sec": 25200
}
```

**4. 세션 종료**
- **Endpoint**: `DELETE /api/vnc/sessions/{session_id}`
- **Authorization**: JWT (소유자 or admin)
- **Response**:
```json
{
  "message": "Session terminated successfully",
  "session_id": "vnc_user01_20251016_123456"
}
```

**5. VNC WebSocket 프록시**
- **Endpoint**: `GET /vnc/{session_id}`
- **Protocol**: WebSocket upgrade
- **Authorization**: JWT via query param `?token=<jwt>`
- **Flow**:
  1. WebSocket 5011이 JWT 검증
  2. Redis에서 세션 정보 조회
  3. `node:websocket_port`로 프록시 연결
  4. 양방향 데이터 전송

### 3.5 Frontend 통합 전략

#### Dashboard (frontend_3010) 수정 사항

**1. 새로운 페이지 추가**:
- `src/pages/VncSessions.tsx`
  - 세션 목록 테이블
  - "새 세션 생성" 버튼
  - 세션 상태 실시간 업데이트 (WebSocket)

- `src/pages/VncViewer.tsx`
  - noVNC 임베딩
  - 세션 정보 표시 (남은 시간, GPU ID 등)
  - 전체 화면 토글
  - 세션 종료 버튼

**2. API 클라이언트 추가**:
- `src/api/vnc.ts`
  - `getSessions()`, `createSession()`, `getSessionDetail()`, `deleteSession()`
  - Axios 인터셉터로 JWT 자동 포함

**3. 라우팅 업데이트**:
```typescript
// src/App.tsx
<Route path="/vnc" element={<VncSessions />} />
<Route path="/vnc/:sessionId" element={<VncViewer />} />
```

**4. 네비게이션 메뉴 추가**:
- "VNC Sessions" 메뉴 항목
- 그룹 기반 표시: `groups.includes('HPC-Users') || groups.includes('GPU-Users')`

#### noVNC 통합 방법

**npm 패키지 설치**:
```bash
npm install @novnc/novnc
```

**VncViewer 컴포넌트 구조**:
1. `useEffect`에서 noVNC RFB 객체 생성
2. WebSocket URL 구성: `wss://domain.com/vnc/{sessionId}?token={jwt}`
3. 연결 성공 시 → Canvas에 VNC 화면 렌더링
4. 연결 실패 시 → 에러 메시지 + 재연결 버튼
5. 언마운트 시 → RFB 객체 정리

**사용자 경험 최적화**:
- 로딩 스피너 (PENDING 상태)
- 연결 진행률 표시
- 자동 재연결 (3회 시도)
- 키보드 단축키 가이드 (Ctrl+Alt+Shift)

---

## Part 4: 보안 및 성능

### 4.1 보안 전략

#### 인증 보안
1. **SAML 검증**:
   - 서명 검증 (IdP 인증서)
   - 만료 시각 검증 (NotBefore, NotOnOrAfter)
   - Replay 공격 방지 (InResponseTo 체크)

2. **JWT 보안**:
   - HS256 알고리즘 (대칭키)
   - SECRET_KEY 512비트 이상, 환경 변수로 관리
   - 짧은 TTL (1시간)
   - Refresh Token 미지원 (재인증 필요)

3. **VNC 패스워드**:
   - 세션마다 랜덤 생성 (12자리 영숫자)
   - Redis에 암호화 저장 (AES-256)
   - API 응답에만 1회 노출, 이후 조회 불가

#### 네트워크 보안
1. **HTTPS 강제**:
   - Nginx에서 HTTP → HTTPS 리다이렉트
   - HSTS 헤더 (`Strict-Transport-Security`)

2. **CORS 정책**:
   - Auth Backend: `https://domain.com`만 허용
   - Dashboard Backend: 동일

3. **방화벽 규칙**:
   - 외부: 443만 허용
   - VNC 포트 (5900-6100): 내부 전용
   - Redis: localhost 바인딩 (`bind 127.0.0.1`)

#### 권한 검증
1. **API 레벨**:
   - 모든 API 엔드포인트에 JWT 미들웨어
   - 그룹 기반 접근 제어 (decorator)

2. **Slurm 레벨**:
   - Job은 항상 사용자 본인의 UID로 실행
   - Sandbox 디렉토리 권한: 사용자만 RWX

3. **감사 로깅**:
   - 모든 인증 시도 기록
   - VNC 세션 생성/종료 로그
   - Job 제출/취소 로그
   - 로그는 `/var/log/slurm_dashboard/audit.log`

### 4.2 성능 최적화 전략

#### VNC 성능
1. **네트워크 최적화**:
   - TurboVNC 압축 레벨: Medium (속도 vs 품질 균형)
   - noVNC 품질 설정: 75% (adjustable)
   - WebSocket 버퍼 크기: 64KB

2. **GPU 최적화**:
   - VirtualGL로 OpenGL 앱 GPU 가속
   - `vglrun` 래퍼 사용
   - EGL 백엔드 (headless 모드)

3. **해상도 전략**:
   - 기본: 1920x1080
   - 고해상도 옵션: 2560x1440 (GPU 사용자만)
   - 동적 조정: noVNC의 스케일링 기능

#### Backend 성능
1. **Redis 캐싱**:
   - 세션 정보: 메모리 캐시, TTL 1시간
   - Slurm 클러스터 상태: 캐시 5초
   - 사용자 권한: 캐시 10분

2. **비동기 처리**:
   - Job 제출: 백그라운드 태스크 (Celery)
   - Sandbox 생성: 비동기 (rsync)
   - 알림: WebSocket 푸시

3. **데이터베이스 최적화**:
   - SQLite WAL 모드 (동시 읽기 개선)
   - 인덱스: `user`, `session_id`, `slurm_job_id`

#### 리소스 제한
1. **사용자당 제한**:
   - 동시 VNC 세션: 2개
   - GPU: 1개/세션
   - 메모리: 8GB/세션
   - 시간: 최대 24시간

2. **전역 제한**:
   - 최대 VNC 세션: 10개 (GPU 노드 개수에 따라)
   - Sandbox 총 용량: 200GB
   - 자동 정리: 종료된 세션의 Sandbox는 24시간 후 삭제

### 4.3 리소스 관리 정책

#### Sandbox 정리 전략
1. **즉시 삭제**: 사용자가 명시적으로 요청한 경우
2. **24시간 후 삭제**: 정상 종료된 세션
3. **보존**: 비정상 종료 (디버깅용, 7일 후 삭제)
4. **쿼터 초과 시**: 가장 오래된 종료 세션부터 삭제

#### GPU 스케줄링
- Slurm의 GRES 플러그인 활용
- Fair-share 정책 (사용 이력 기반 우선순위)
- 장시간 대기 시 알림 (예상 대기 시간 표시)

---

## Part 5: 모니터링 및 운영

### 5.1 모니터링 전략

#### Prometheus 메트릭
기존 prometheus_9090과 통합:

**새로운 메트릭 추가**:
1. `vnc_sessions_total` (gauge) - 현재 활성 세션 수
2. `vnc_sessions_created_total` (counter) - 생성된 세션 총 수
3. `vnc_sessions_failed_total` (counter) - 실패한 세션 수
4. `vnc_session_duration_seconds` (histogram) - 세션 지속 시간
5. `auth_saml_requests_total` (counter) - SAML 요청 수
6. `auth_jwt_issued_total` (counter) - JWT 발급 수
7. `auth_jwt_validation_failures_total` (counter) - JWT 검증 실패 수

**Exporter 추가**:
- `auth_portal_4430/metrics.py` - Auth 메트릭
- `backend_5010/metrics.py` - VNC 메트릭 (기존 파일 확장)

#### Grafana 대시보드
기존 Grafana 인스턴스에 대시보드 추가:

**"VNC Sessions" 대시보드**:
1. **패널 1**: 현재 활성 세션 수 (Gauge)
2. **패널 2**: 시간별 세션 생성/종료 (Time Series)
3. **패널 3**: 사용자별 세션 수 (Bar Chart)
4. **패널 4**: GPU 사용률 (Time Series)
5. **패널 5**: 평균 세션 지속 시간 (Stat)

**"Auth System" 대시보드**:
1. **패널 1**: 인증 성공/실패율 (Pie Chart)
2. **패널 2**: 시간별 로그인 수 (Time Series)
3. **패널 3**: JWT 검증 실패 원인 (Table)

### 5.2 로깅 및 추적

#### 로그 구조
각 서비스는 구조화된 JSON 로그 생성:

```json
{
  "timestamp": "2025-10-16T12:34:56.789Z",
  "level": "INFO",
  "service": "auth_portal",
  "user": "user01",
  "action": "saml_login",
  "result": "success",
  "duration_ms": 234,
  "ip": "192.168.1.100",
  "trace_id": "abc123def456"
}
```

#### 로그 파일 위치
- Auth Portal: `/var/log/slurm_dashboard/auth_portal.log`
- Backend 5010: `/var/log/slurm_dashboard/backend.log`
- VNC Sessions: `/var/log/slurm_dashboard/vnc_sessions.log`
- Audit: `/var/log/slurm_dashboard/audit.log`

#### 로그 로테이션
- 일별 로테이션
- 압축: gzip
- 보존 기간: 30일

### 5.3 운영 자동화

#### Health Check 엔드포인트
모든 서비스에 `/health` 추가:

```json
{
  "status": "healthy",
  "version": "1.0.0",
  "checks": {
    "database": "ok",
    "redis": "ok",
    "slurm": "ok"
  },
  "uptime_sec": 86400
}
```

#### 자동 재시작 정책
Systemd 서비스 파일에 설정:
- `Restart=on-failure`
- `RestartSec=10s`
- `StartLimitInterval=5min`
- `StartLimitBurst=3`

#### Backup 전략
1. **설정 백업** (매일 3AM):
   - `/etc/nginx/`, `auth_portal_4430/saml/`, `my_cluster.yaml`
   - 보존: 30일

2. **데이터베이스 백업** (매일 3:30AM):
   - SQLite: `sqlite3 db.sqlite .dump > backup.sql`
   - 보존: 7일

3. **Redis 스냅샷** (매 6시간):
   - RDB 파일 자동 생성
   - 보존: 48시간

---

## Part 6: 개발 실행 계획

### 6.1 전체 로드맵 (8주)

| 주차 | Phase | 목표 | 주요 산출물 |
|------|-------|------|------------|
| **1주** | Phase 0 | 사전 준비 및 개발 환경 | my_cluster.yaml 업데이트, saml-idp 구동, Redis 설치 |
| **2-3주** | Phase 1 | Auth Portal 개발 | auth_portal_4430, auth_portal_4431, Nginx 설정 |
| **4주** | Phase 2 | 기존 서비스 통합 | backend_5010/frontend_3010 JWT 추가 |
| **5-6주** | Phase 3 | VNC 시스템 개발 | Apptainer 이미지, VNC API, 프론트엔드 |
| **7주** | Phase 4 | CAE 통합 및 모니터링 | kooCAEWeb JWT 추가, Grafana 대시보드 |
| **8주** | Phase 5 | 테스트 및 문서화 | 통합 테스트, 운영 매뉴얼, 사용자 가이드 |

### 6.2 Phase별 상세 계획

#### Phase 0: 사전 준비 (1주)

**목표**: 개발 환경 구축 및 Slurm 설정 업데이트

**작업 항목**:
1. my_cluster.yaml 업데이트 (GPU, VNC 파티션, sandbox_path)
2. Slurm 설정 재생성 및 재시작
3. Redis 7+ 설치 및 설정
4. saml-idp 설치 및 테스트 사용자 생성
5. SSL 인증서 발급 (Let's Encrypt or 자체 서명)
6. Apptainer 샌드박스 디렉토리 생성 및 권한 설정

**검증 기준**:
- `sinfo -p vnc` 실행 시 vnc 파티션 표시
- `redis-cli ping` 응답 확인
- saml-idp에서 SAML 메타데이터 다운로드 가능
- `/scratch/apptainer_sandboxes/` 생성 및 쓰기 가능

#### Phase 1: Auth Portal 개발 (2-3주)

**목표**: SAML SSO + JWT 발급 시스템 구축

**Week 1 (백엔드)**:
1. auth_portal_4430 프로젝트 생성
2. python3-saml 설정 (settings.json, SP 인증서)
3. SAML 핸들러 구현 (login, ACS)
4. JWT 발급 로직 (PyJWT)
5. Redis 세션 저장
6. Health check 엔드포인트

**Week 2 (프론트엔드)**:
1. auth_portal_4431 프로젝트 생성 (Vite + React + TS)
2. Login 페이지 (SSO 버튼)
3. ServiceMenu 페이지 (그룹 기반 필터링)
4. JWT 유틸리티 함수
5. Nginx 설정 (HTTPS, 리버스 프록시)

**검증 기준**:
- saml-idp로 로그인 → JWT 토큰 발급 확인
- ServiceMenu에서 그룹별 서비스 목록 올바르게 표시
- JWT 디코딩 시 올바른 페이로드 확인

#### Phase 2: 기존 서비스 통합 (1주)

**목표**: backend_5010, frontend_3010에 JWT 인증 추가

**Backend (backend_5010)**:
1. JWT 검증 미들웨어 추가
2. 권한 검증 데코레이터
3. 기존 API 엔드포인트에 적용
4. 에러 핸들링 (401, 403)

**Frontend (frontend_3010)**:
1. URL 파라미터에서 JWT 추출
2. localStorage 저장
3. Axios 인터셉터 (Authorization 헤더)
4. 토큰 만료 시 재로그인 유도

**검증 기준**:
- ServiceMenu에서 Dashboard 클릭 → JWT 전달 확인
- API 호출 시 JWT 없으면 401 에러
- 유효한 JWT로 모든 기존 기능 정상 작동

#### Phase 3: VNC 시스템 개발 (2주)

**Week 1 (Apptainer + Slurm)**:
1. ubuntu_vnc_gpu.def 작성
2. 이미지 빌드 및 샌드박스 생성
3. VNC 서버 테스트 (TurboVNC + VirtualGL)
4. Slurm Job 스크립트 템플릿 작성
5. Job 제출/모니터링 로직

**Week 2 (API + Frontend)**:
1. VNC 세션 API 4개 (생성, 조회, 상세, 종료)
2. Redis 세션 메타데이터 관리
3. VncSessions.tsx (목록 페이지)
4. VncViewer.tsx (noVNC 통합)
5. WebSocket 5011 VNC 프록시 추가

**검증 기준**:
- API로 VNC 세션 생성 → Slurm Job 제출 확인
- Job RUNNING 상태에서 noVNC로 접속 가능
- 데스크톱에서 `nvidia-smi` 실행 → GPU 인식 확인
- 세션 종료 → Slurm Job 취소 및 Redis 삭제 확인

#### Phase 4: CAE 통합 및 모니터링 (1주)

**CAE 서비스 통합**:
1. kooCAEWebServer_5000에 JWT 미들웨어 추가
2. kooCAEWeb_5173에 JWT 토큰 처리 추가
3. ServiceMenu에 CAE 서비스 링크 추가

**모니터링 구축**:
1. Prometheus 메트릭 추가 (auth, vnc)
2. Grafana 대시보드 2개 생성
3. 알림 규칙 설정 (세션 실패율 > 10%)

**검증 기준**:
- ServiceMenu에서 CAE 선택 → JWT 전달 및 정상 접근
- Grafana에서 VNC 세션 메트릭 확인
- 알림 테스트 (세션 강제 실패 시 알림 발생)

#### Phase 5: 테스트 및 문서화 (1주)

**테스트**:
1. 단위 테스트 (JWT 검증, SAML 파싱)
2. 통합 테스트 (전체 인증 플로우)
3. E2E 테스트 (Selenium: 로그인 → VNC 접속)
4. 부하 테스트 (동시 세션 10개)

**문서화**:
1. 아키텍처 다이어그램
2. API 문서 (Swagger/OpenAPI)
3. 운영 매뉴얼 (설치, 설정, 백업)
4. 사용자 가이드 (로그인 방법, VNC 사용법)
5. 트러블슈팅 가이드

**검증 기준**:
- 테스트 커버리지 > 80%
- 모든 문서 작성 완료 및 리뷰
- 프로덕션 배포 체크리스트 작성

---

## Part 7: 즉시 실행 가이드

### 7.1 Phase 0 실행 단계

#### Step 1: my_cluster.yaml 백업 및 수정
```bash
# 백업
cp my_cluster.yaml my_cluster.yaml.backup_$(date +%Y%m%d)

# 편집기로 열기
nano my_cluster.yaml

# 다음 3가지 수정:
# 1. Line 197: enabled: false → true
# 2. Line 105 아래에 vnc 파티션 추가
# 3. Line 82에 sandbox_path 추가

# 저장 후 검증
grep -A5 "gpu_computing:" my_cluster.yaml
grep "sandbox_path:" my_cluster.yaml
grep -A5 'name: "vnc"' my_cluster.yaml
```

#### Step 2: Slurm 설정 재생성
```bash
# Slurm 설정 파일 재생성 (프로젝트에 스크립트가 있다면)
./scripts/generate_slurm_config.sh

# 수동으로 slurm.conf 편집하는 경우
sudo nano /usr/local/slurm/etc/slurm.conf

# 다음 라인 추가:
# PartitionName=vnc Nodes=compute01 Default=NO MaxTime=24:00:00 State=UP

# slurmctld 재시작
sudo systemctl restart slurmctld

# 검증
sinfo -p vnc
```

#### Step 3: Redis 설치 및 설정
```bash
# Rocky Linux 8/CentOS 8
sudo dnf install redis -y

# 설정 편집
sudo nano /etc/redis/redis.conf

# 다음 설정 확인/수정:
# bind 127.0.0.1
# protected-mode yes
# port 6379
# maxmemory 512mb
# maxmemory-policy allkeys-lru

# 시작 및 자동 시작 설정
sudo systemctl enable --now redis

# 검증
redis-cli ping  # PONG 응답 확인
```

#### Step 4: saml-idp 설치 및 실행
```bash
# Node.js 18+ 설치 (없는 경우)
curl -fsSL https://rpm.nodesource.com/setup_18.x | sudo bash -
sudo dnf install nodejs -y

# saml-idp 글로벌 설치
sudo npm install -g saml-idp

# 설정 디렉토리 생성
mkdir -p ~/saml_idp_config
cd ~/saml_idp_config

# 테스트 사용자 파일 생성
cat > users.json << 'EOF'
{
  "user01@hpc.local": {
    "password": "password123",
    "email": "user01@hpc.local",
    "name": "테스트 사용자1",
    "groups": ["HPC-Users", "GPU-Users"]
  },
  "admin@hpc.local": {
    "password": "admin123",
    "email": "admin@hpc.local",
    "name": "관리자",
    "groups": ["HPC-Admins"]
  }
}
EOF

# saml-idp 시작
saml-idp --port 7000 --issuer "http://localhost:7000/metadata" \
  --acsUrl "http://localhost:4430/auth/saml/acs" \
  --audience "auth-portal" \
  --config users.json &

# 검증
curl http://localhost:7000/metadata
```

#### Step 5: Apptainer 샌드박스 디렉토리 준비
```bash
# 디렉토리 생성
sudo mkdir -p /scratch/apptainer_sandboxes

# 권한 설정 (slurm 사용자가 쓰기 가능하도록)
sudo chown slurm:slurm /scratch/apptainer_sandboxes
sudo chmod 755 /scratch/apptainer_sandboxes

# 검증
ls -ld /scratch/apptainer_sandboxes
su - slurm -c "touch /scratch/apptainer_sandboxes/test && rm /scratch/apptainer_sandboxes/test"
```

#### Step 6: SSL 인증서 준비
```bash
# 개발용 자체 서명 인증서 생성
sudo mkdir -p /etc/ssl/private
cd /etc/ssl/private

sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout nginx-selfsigned.key \
  -out /etc/ssl/certs/nginx-selfsigned.crt \
  -subj "/C=KR/ST=Seoul/L=Seoul/O=HPC Lab/CN=domain.com"

# 권한 설정
sudo chmod 600 /etc/ssl/private/nginx-selfsigned.key
sudo chmod 644 /etc/ssl/certs/nginx-selfsigned.crt

# 검증
sudo openssl x509 -in /etc/ssl/certs/nginx-selfsigned.crt -noout -text
```

### 7.2 Phase 1 실행 단계

#### Step 7: Auth Backend 프로젝트 생성
```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard
mkdir -p auth_portal_4430
cd auth_portal_4430

# 가상 환경 생성
python3 -m venv venv
source venv/bin/activate

# 필수 패키지 설치
pip install flask python3-saml PyJWT redis flask-cors

# requirements.txt 생성
pip freeze > requirements.txt
```

#### Step 8: Auth Backend SAML 설정
```bash
# SAML 디렉토리 구조 생성
mkdir -p saml/certs saml/metadata

# SP 인증서 생성
cd saml/certs
openssl req -x509 -newkey rsa:2048 -keyout sp.key -out sp.crt -days 365 -nodes \
  -subj "/CN=auth-portal-sp"

# IdP 메타데이터 다운로드
curl http://localhost:7000/metadata > ../metadata/idp_metadata.xml

# settings.json 생성
cd ..
cat > settings.json << 'EOF'
{
  "sp": {
    "entityId": "auth-portal",
    "assertionConsumerService": {
      "url": "http://localhost:4430/auth/saml/acs",
      "binding": "urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST"
    },
    "x509cert": "",
    "privateKey": ""
  },
  "idp": {
    "entityId": "http://localhost:7000/metadata",
    "singleSignOnService": {
      "url": "http://localhost:7000/saml/sso",
      "binding": "urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect"
    },
    "x509cert": ""
  }
}
EOF
```

#### Step 9: Auth Backend 핵심 파일 구조 설계

**app.py 구조**:
- Flask 앱 초기화
- CORS 설정
- 라우트 정의 (`/auth/saml/login`, `/auth/saml/acs`, `/auth/verify`)
- Health check 엔드포인트

**saml_handler.py 구조**:
- SAML 요청 생성 함수
- SAML 응답 파싱 및 검증 함수
- 사용자 속성 추출 함수

**jwt_handler.py 구조**:
- JWT 발급 함수 (페이로드 구성, 서명)
- JWT 검증 함수 (서명, 만료, 클레임)
- 권한 계산 함수 (그룹 → 권한 매핑)

**redis_client.py 구조**:
- Redis 연결 풀
- 세션 저장 함수
- 세션 조회/삭제 함수

#### Step 10: Auth Frontend 프로젝트 생성
```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard
npm create vite@latest auth_portal_4431 -- --template react-ts
cd auth_portal_4431
npm install
npm install axios react-router-dom jwt-decode
```

#### Step 11: Auth Frontend 페이지 구조 설계

**Login.tsx 구조**:
- SSO 로그인 버튼
- 버튼 클릭 시 → `window.location.href = 'http://localhost:4430/auth/saml/login'`
- 로딩 스피너

**ServiceMenu.tsx 구조**:
- URL 파라미터에서 JWT 추출 (`useSearchParams`)
- JWT 디코딩 → `groups` 추출
- 그룹 기반 서비스 카드 렌더링
- 카드 클릭 → 해당 서비스 URL + `?token=<JWT>`로 리다이렉트

**utils/jwt.ts 구조**:
- `decodeToken(token: string)` 함수
- `isTokenExpired(token: string)` 함수
- `getTokenGroups(token: string)` 함수

#### Step 12: Nginx 설정
```bash
sudo nano /etc/nginx/conf.d/auth_portal.conf

# 다음 내용 작성:
# server {
#   listen 443 ssl http2;
#   server_name domain.com;
#
#   ssl_certificate /etc/ssl/certs/nginx-selfsigned.crt;
#   ssl_certificate_key /etc/ssl/private/nginx-selfsigned.key;
#
#   location /auth/ {
#     proxy_pass http://localhost:4430/;
#   }
#
#   location / {
#     proxy_pass http://localhost:4431/;
#   }
# }

sudo nginx -t
sudo systemctl reload nginx
```

### 7.3 Phase 2 실행 단계

#### Step 13: backend_5010 JWT 미들웨어 추가

**파일 구조 파악**:
- 기존 `backend_5010/app.py` 확인
- 기존 라우트 목록 파악

**middleware.py 추가**:
- JWT 검증 데코레이터 구현
- 그룹 검증 데코레이터 구현
- 에러 핸들러 (401, 403)

**app.py 수정**:
- `from middleware import jwt_required, group_required` 추가
- 기존 라우트에 데코레이터 적용 (예: `@jwt_required`)

#### Step 14: frontend_3010 JWT 토큰 처리 추가

**App.tsx 수정**:
- URL 파라미터 확인: `const [searchParams] = useSearchParams()`
- JWT 추출 및 저장: `localStorage.setItem('jwt_token', token)`

**api/client.ts 수정** (또는 Axios 인스턴스):
- Axios 인터셉터 추가
- 모든 요청에 `Authorization: Bearer <token>` 헤더 포함

**에러 핸들링**:
- 401 응답 시 → localStorage 삭제 + Auth Portal로 리다이렉트

### 7.4 Phase 3 실행 단계

#### Step 15: Apptainer VNC 이미지 정의 작성
```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/apptainers
nano ubuntu_vnc_gpu.def

# 다음 섹션 포함:
# - Bootstrap: docker
# - From: ubuntu:22.04
# - %post: apt install turbovnc, virtualgl, xfce4, firefox, nvidia-driver
# - %environment: VNC_PORT, DISPLAY 변수
# - %runscript: vncserver 시작 스크립트
```

#### Step 16: Apptainer 이미지 빌드
```bash
# SIF 이미지 빌드 (root 권한 필요)
sudo apptainer build ubuntu_vnc_gpu.sif ubuntu_vnc_gpu.def

# 템플릿 샌드박스 생성
sudo apptainer build --sandbox /scratch/apptainer_sandboxes/vnc_template \
  ubuntu_vnc_gpu.sif

# 권한 설정
sudo chown -R slurm:slurm /scratch/apptainer_sandboxes/vnc_template
```

#### Step 17: VNC 세션 API 구현 (backend_5010)

**vnc_manager.py 추가**:
- `create_session(user, gpu_count, memory_gb, ...)` 함수
  - Sandbox 복사
  - VNC 패스워드 생성
  - Slurm Job 스크립트 생성
  - sbatch 제출
  - Redis 저장
- `get_sessions(user)` 함수
- `get_session_detail(session_id)` 함수
- `delete_session(session_id)` 함수

**routes/vnc.py 추가**:
- `POST /api/vnc/sessions` → `create_session()` 호출
- `GET /api/vnc/sessions` → `get_sessions()` 호출
- `GET /api/vnc/sessions/<id>` → `get_session_detail()` 호출
- `DELETE /api/vnc/sessions/<id>` → `delete_session()` 호출

#### Step 18: VNC Frontend 페이지 구현

**VncSessions.tsx**:
- `useEffect`로 세션 목록 가져오기 (`GET /api/vnc/sessions`)
- 테이블 렌더링 (session_id, status, node, created_at)
- "새 세션 생성" 버튼 → 모달 열기
- 모달에서 GPU, 메모리, 시간 입력 → `POST /api/vnc/sessions`
- WebSocket으로 실시간 상태 업데이트

**VncViewer.tsx**:
- `useParams`로 session_id 추출
- `GET /api/vnc/sessions/<id>`로 세션 정보 가져오기
- noVNC RFB 객체 생성
- WebSocket URL: `wss://domain.com/vnc/<id>?token=<JWT>`
- Canvas에 VNC 화면 렌더링

#### Step 19: WebSocket VNC 프록시 추가 (websocket_5011)

**파일 수정**:
- 기존 WebSocket 서버 확인
- VNC 프록시 핸들러 추가
- 클라이언트 WebSocket ↔ VNC 서버 양방향 프록시
- JWT 검증 (쿼리 파라미터)

### 7.5 Phase 4 실행 단계

#### Step 20: kooCAEWebServer JWT 미들웨어 추가
- backend_5010의 middleware.py 복사
- app.py에 적용

#### Step 21: kooCAEWeb JWT 토큰 처리 추가
- frontend_3010의 JWT 로직 복사
- api/client.ts 수정

#### Step 22: ServiceMenu CAE 링크 추가
- ServiceMenu.tsx에 CAE 카드 추가
- 그룹 필터링: `groups.includes('HPC-Admins') || groups.includes('Automation-Users')`

#### Step 23: Prometheus 메트릭 추가

**auth_portal_4430/metrics.py**:
- Prometheus client 초기화
- Counter: `auth_saml_requests_total`, `auth_jwt_issued_total`
- `/metrics` 엔드포인트 추가

**backend_5010/metrics.py 확장**:
- Gauge: `vnc_sessions_total`
- Counter: `vnc_sessions_created_total`, `vnc_sessions_failed_total`
- Histogram: `vnc_session_duration_seconds`

**prometheus_9090/prometheus.yml 수정**:
- 새로운 scrape 타겟 추가: `localhost:4430/metrics`

#### Step 24: Grafana 대시보드 생성
- Grafana 로그인 (http://localhost:3000)
- "VNC Sessions" 대시보드 생성
- 6개 패널 추가 (활성 세션, 시간별 추이, 사용자별, GPU 사용률, 평균 지속 시간, 실패율)
- "Auth System" 대시보드 생성
- 3개 패널 추가 (성공/실패율, 로그인 수, 검증 실패 원인)

### 7.6 Phase 5 실행 단계

#### Step 25: 단위 테스트 작성
- pytest 설치
- auth_portal_4430/tests/ 디렉토리 생성
- JWT 발급/검증 테스트
- SAML 파싱 테스트
- Redis 세션 테스트

#### Step 26: 통합 테스트 작성
- 전체 인증 플로우 테스트 (mock IdP)
- VNC 세션 생성/종료 플로우 테스트

#### Step 27: 문서화 작성
- README.md 업데이트 (아키텍처 다이어그램)
- API.md 작성 (Swagger YAML)
- OPERATIONS.md 작성 (설치, 설정, 백업 절차)
- USER_GUIDE.md 작성 (로그인, VNC 사용법, FAQ)
- TROUBLESHOOTING.md 작성 (일반적인 문제 및 해결책)

---

## Part 8: 위험 관리 및 트러블슈팅

### 8.1 예상 위험 요소

#### 위험 1: SAML 인증 실패
**원인**:
- IdP 메타데이터 불일치
- SP 인증서 만료
- 시간 동기화 문제 (NotBefore/NotOnOrAfter)

**완화 전략**:
- 개발 단계에서 saml-idp로 충분히 테스트
- ADFS 연동 전 메타데이터 교환 철저히 검증
- NTP 동기화 필수 (time_synchronization in my_cluster.yaml)

**감지 방법**:
- Auth Backend 로그에서 SAML 검증 에러 확인
- Prometheus 메트릭: `auth_saml_requests_total{status="failed"}`

#### 위험 2: VNC 세션 시작 실패
**원인**:
- GPU 리소스 부족
- Apptainer 샌드박스 복사 실패 (디스크 공간 부족)
- VNC 포트 충돌
- Slurm Job 제출 실패 (파티션 DOWN)

**완화 전략**:
- Job 제출 전 리소스 가용성 사전 확인
- 디스크 쿼터 모니터링 (알림 설정)
- 동적 포트 할당 (5900-6100 범위)
- Slurm 파티션 상태 주기적 체크

**감지 방법**:
- Job 상태 모니터링 (PENDING 5분 이상 → 알림)
- Prometheus 메트릭: `vnc_sessions_failed_total`

#### 위험 3: JWT 토큰 탈취
**원인**:
- HTTPS 미사용 (중간자 공격)
- localStorage XSS 취약점
- 토큰이 URL에 노출 (브라우저 히스토리)

**완화 전략**:
- HTTPS 강제 (HSTS 헤더)
- CSP 헤더 설정 (Content Security Policy)
- 짧은 TTL (1시간)
- URL 파라미터는 즉시 제거 (history.replaceState)

**감지 방법**:
- 비정상적인 JWT 검증 실패율 증가
- 동일 토큰으로 다른 IP에서 접근 시도

#### 위험 4: Sandbox 디스크 공간 고갈
**원인**:
- 종료된 세션의 Sandbox 미정리
- 사용자가 대용량 파일 생성

**완화 전략**:
- 24시간 후 자동 정리 cron job
- 사용자별 쿼터 설정 (10GB/세션)
- 디스크 사용량 90% 초과 시 알림

**감지 방법**:
- `df -h /scratch` 모니터링
- Prometheus node_exporter 디스크 메트릭

### 8.2 트러블슈팅 전략

#### 문제 1: "SAML Response validation failed"
**증상**: 로그인 시 에러 페이지

**진단 단계**:
1. Auth Backend 로그 확인: `/var/log/slurm_dashboard/auth_portal.log`
2. SAML Response 디코딩: Base64 디코드 후 XML 파싱
3. 인증서 검증: `openssl verify -CAfile idp.crt sp.crt`
4. 시간 동기화 확인: `timedatectl status`

**해결 방법**:
- 인증서 갱신: `openssl req -x509 -newkey rsa:2048 ...`
- 메타데이터 재다운로드: `curl http://idp/metadata > idp_metadata.xml`
- NTP 동기화: `sudo systemctl restart chronyd`

#### 문제 2: "VNC session stuck in PENDING"
**증상**: 세션이 계속 PENDING 상태

**진단 단계**:
1. Slurm 파티션 상태: `sinfo -p vnc`
2. Job 큐 확인: `squeue -p vnc`
3. 노드 상태: `scontrol show node compute01`
4. GPU 가용성: `sinfo -o "%N %G %C"`

**해결 방법**:
- 노드 DOWN → `scontrol update NodeName=compute01 State=RESUME`
- GPU 리소스 부족 → 기존 세션 종료 or 다른 노드 추가
- Job hold 상태 → `scontrol release <job_id>`

#### 문제 3: "JWT token expired"
**증상**: API 호출 시 401 에러

**진단 단계**:
1. 토큰 디코딩: jwt.io에서 `exp` 클레임 확인
2. 서버 시간 확인: `date -u` (UTC 시간)
3. Redis 세션 조회: `redis-cli GET "session:<user>"`

**해결 방법**:
- 토큰 재발급: Auth Portal로 리다이렉트
- TTL 연장 (1시간 → 2시간, 보안 검토 후)
- Refresh Token 도입 (추후 개선 항목)

#### 문제 4: "noVNC connection failed"
**증상**: VNC Viewer 페이지에서 연결 실패

**진단 단계**:
1. VNC 세션 상태: `GET /api/vnc/sessions/<id>`
2. WebSocket 연결 테스트: 브라우저 개발자 도구 Network 탭
3. VNC 서버 포트 확인: `ssh compute01 'netstat -tunlp | grep 590'`
4. WebSockify 프로세스 확인: `ssh compute01 'ps aux | grep websockify'`

**해결 방법**:
- VNC 서버 미시작 → Slurm Job 로그 확인 (`scontrol show job <id>`)
- 포트 충돌 → 다른 포트로 재시작
- 방화벽 차단 → `sudo firewall-cmd --add-port=5901/tcp`
- WebSocket 5011 재시작: `sudo systemctl restart websocket_5011`

### 8.3 롤백 계획

#### 시나리오 1: Auth Portal 장애
**영향**: 모든 서비스 로그인 불가

**즉시 조치**:
1. Auth Portal 서비스 재시작
2. Redis 연결 확인
3. Nginx 로그 확인

**롤백 방법**:
- Auth Portal을 이전 버전으로 복구
- 기존 서비스를 임시로 JWT 검증 우회 모드로 전환 (환경 변수)
- 공지: "인증 시스템 점검 중, 일시적으로 기본 인증 사용"

#### 시나리오 2: VNC 시스템 장애
**영향**: 새로운 VNC 세션 생성 불가, 기존 세션은 정상

**즉시 조치**:
1. backend_5010 로그 확인
2. Slurm 상태 확인
3. Apptainer 샌드박스 권한 확인

**롤백 방법**:
- VNC API 엔드포인트 비활성화 (503 응답)
- 프론트엔드에서 VNC 메뉴 숨김
- 공지: "VNC 서비스 점검 중, 빠른 시일 내 복구 예정"

#### 시나리오 3: JWT 미들웨어 오작동
**영향**: 기존 서비스 API 호출 실패

**즉시 조치**:
1. JWT 검증 로직 로그 확인
2. Redis 세션 데이터 확인
3. SECRET_KEY 환경 변수 확인

**롤백 방법**:
- JWT 미들웨어를 임시로 비활성화 (환경 변수 `BYPASS_JWT=true`)
- 이전 버전 코드로 복구 (git 태그 활용)
- 긴급 패치 배포 후 재활성화

---

## 결론

이 문서는 **SAML SSO 통합 인증** + **Apptainer 기반 GPU VNC 시각화 시스템** 구축을 위한 **전략 중심의 개발 계획**입니다.

### 핵심 원칙
1. **기존 시스템 존중**: 8개 운영 중인 서비스에 최소 침습적 통합
2. **단계적 접근**: 5개 Phase로 나누어 점진적 개발
3. **보안 우선**: SAML 2.0, JWT, HTTPS, 그룹 기반 RBAC
4. **운영 고려**: 모니터링, 로깅, 백업, 자동화 전략 포함

### 다음 단계
1. **즉시 시작**: Part 7의 Step 1부터 순차적 실행
2. **검증 철저**: 각 Phase 완료 후 검증 기준 충족 확인
3. **문서화 병행**: 개발과 동시에 운영 문서 작성
4. **프로덕션 준비**: Phase 5 완료 후 ADFS 연동 및 배포

### 성공 지표
- [ ] SAML SSO 로그인 성공률 > 99%
- [ ] JWT 토큰 발급/검증 성공률 > 99.9%
- [ ] VNC 세션 생성 성공률 > 95%
- [ ] VNC 세션 평균 시작 시간 < 30초
- [ ] API 응답 시간 P95 < 500ms
- [ ] 시스템 가용성 > 99.5%

---

**문서 종료**
