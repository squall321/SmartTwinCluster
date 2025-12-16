# Moonlight/Sunshine 배포 가이드

**작성일**: 2025-12-06
**버전**: 1.0.0
**상태**: 개발 환경 준비 완료 ✅

---

## 📋 현재 진행 상황

| Phase | 항목 | 상태 | 비고 |
|-------|------|------|------|
| 1.1 | Apptainer Definition 파일 생성 | ✅ 완료 | `sunshine_xfce4.def` |
| 1.2 | Apptainer 이미지 빌드 | ⏳ 대기 | viz-node 접근 필요 |
| 2 | Slurm QoS 설정 문서화 | ✅ 완료 | `SLURM_QOS_SETUP.md` |
| 3 | Backend 가상환경 설정 | ✅ 완료 | venv 생성, 의존성 설치 |
| 4 | Nginx 설정 준비 | ✅ 완료 | `nginx_config_addition.conf` |
| 5 | 테스트 스크립트 작성 | ✅ 완료 | `test_all_services.sh` |
| 6 | 문서화 | ✅ 완료 | 이 파일 |

---

## 🎯 배포 전 필수 작업

### 1. Apptainer 이미지 빌드 (viz-node에서)

```bash
# 1. Definition 파일을 viz-node로 복사
scp /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/MoonlightSunshine_8004/sunshine_xfce4.def \
    viz-node001:/tmp/

# 2. viz-node에 SSH 접속
ssh viz-node001

# 3. 이미지 빌드 (약 20-30분 소요)
cd /tmp
sudo apptainer build sunshine_xfce4.sif sunshine_xfce4.def

# 4. 이미지 검증
apptainer inspect sunshine_xfce4.sif
apptainer exec --nv sunshine_xfce4.sif nvidia-smi
apptainer exec sunshine_xfce4.sif sunshine --version

# 5. /opt/apptainers/로 복사
sudo cp sunshine_xfce4.sif /opt/apptainers/
sudo chmod 755 /opt/apptainers/sunshine_xfce4.sif

# 6. 확인
ls -lh /opt/apptainers/sunshine_xfce4.sif
```

**참고**: [BUILD_INSTRUCTIONS.md](BUILD_INSTRUCTIONS.md)

### 2. Slurm QoS 생성

```bash
# QoS 추가
sudo sacctmgr add qos moonlight

# QoS 파라미터 설정
sudo sacctmgr modify qos moonlight set \
    GraceTime=60 \
    MaxWall=8:00:00 \
    MaxTRESPerUser=gpu=2 \
    Priority=100

# 확인
sacctmgr show qos moonlight format=Name,Priority,MaxWall,MaxTRESPerUser,GraceTime -p
```

**참고**: [SLURM_QOS_SETUP.md](SLURM_QOS_SETUP.md)

### 3. Nginx 설정 업데이트

```bash
# 1. 기존 설정 백업
sudo cp /etc/nginx/conf.d/auth-portal.conf \
     /etc/nginx/conf.d/auth-portal.conf.backup_$(date +%Y%m%d_%H%M%S)

# 2. 설정 파일 편집
sudo vi /etc/nginx/conf.d/auth-portal.conf

# 3. nginx_config_addition.conf 내용을 다음 위치에 추가:
#    - Upstream 정의: 파일 최상단
#    - /api/moonlight/: Line 102 위 (/api/ 보다 먼저!)
#    - /moonlight/signaling: Line 133 근처
#    - /moonlight/: Line 220 근처

# 4. 문법 검사
sudo nginx -t

# 5. Nginx 재시작
sudo systemctl reload nginx
```

**참고**: [NGINX_INTEGRATION_GUIDE.md](NGINX_INTEGRATION_GUIDE.md)

---

## 🚀 서비스 시작

### 1. Backend 시작 (Gunicorn)

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/MoonlightSunshine_8004/backend_moonlight_8004

# 개발 모드
venv/bin/python app.py

# 프로덕션 모드 (Gunicorn)
venv/bin/gunicorn -c gunicorn_config.py app:app

# 백그라운드 실행
nohup venv/bin/gunicorn -c gunicorn_config.py app:app > logs/backend.log 2>&1 &

# 프로세스 확인
ps aux | grep gunicorn | grep moonlight
lsof -i :8004
```

### 2. 서비스 확인

```bash
# Health check
curl http://localhost:8004/health

# 예상 출력:
# {"status": "healthy", "service": "moonlight_backend", "port": 8004}

# Images API
curl http://localhost:8004/api/moonlight/images

# 예상 출력:
# {"images": [{"id": "xfce4", "name": "XFCE4 Desktop (Sunshine)", ...}]}
```

---

## 🧪 테스트

### 자동 테스트 실행

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/MoonlightSunshine_8004

./test_all_services.sh
```

**테스트 항목**:
1. ✅ 기존 서비스 포트 확인 (Auth, CAE, VNC, etc.)
2. ✅ Moonlight Backend 포트 확인 (8004)
3. ✅ 기존 API 엔드포인트 테스트
4. ✅ Moonlight API 엔드포인트 테스트
5. ✅ Redis 연결 테스트
6. ✅ Apptainer 이미지 확인
7. ✅ Slurm QoS 확인
8. ✅ Nginx 설정 확인
9. ✅ 디렉토리 구조 확인
10. ✅ 프로세스 확인

### 수동 테스트

```bash
# 1. Backend API 테스트
curl -k https://110.15.177.120/api/moonlight/images

# 2. 기존 VNC API 테스트 (무영향 확인)
curl -k https://110.15.177.120/api/vnc/images

# 3. Redis 키 확인
redis-cli KEYS "moonlight:session:*"  # 비어있어야 함
redis-cli KEYS "vnc:session:*"        # 기존 키 유지

# 4. Slurm QoS 테스트
sbatch /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/MoonlightSunshine_8004/test_moonlight_qos.sh
```

---

## 📊 생성된 파일 목록

### 1. 코어 파일 (이미 생성됨)

```
MoonlightSunshine_8004/
├── backend_moonlight_8004/
│   ├── app.py                   ✅ Flask 메인 앱
│   ├── moonlight_api.py         ✅ Moonlight API Blueprint
│   ├── requirements.txt         ✅ Python 의존성
│   ├── gunicorn_config.py       ✅ Gunicorn 설정
│   ├── README.md                ✅ 백엔드 문서
│   ├── venv/                    ✅ 가상환경 (설치 완료)
│   └── logs/                    ✅ 로그 디렉토리
├── sunshine_xfce4.def           ✅ Apptainer Definition
├── sunshine.conf.template       ✅ Sunshine 설정 템플릿
├── nginx_config_addition.conf   ✅ Nginx 설정 추가본
└── test_all_services.sh         ✅ 테스트 스크립트
```

### 2. 문서 파일

```
├── IMPLEMENTATION_PLAN.md       ✅ 전체 구현 계획
├── ISOLATION_CHECKLIST.md       ✅ 격리 체크리스트
├── FINAL_REVIEW_REPORT.md       ✅ 최종 검토 보고서
├── BACKEND_ARCHITECTURE_UPDATE.md  ✅ 백엔드 구조 변경
├── COMPLETE_SYSTEM_ISOLATION_AUDIT.md  ✅ 시스템 격리 감사
├── NGINX_INTEGRATION_GUIDE.md   ✅ Nginx 통합 가이드
├── BUILD_INSTRUCTIONS.md        ✅ 빌드 가이드
├── SLURM_QOS_SETUP.md           ✅ Slurm QoS 설정
└── DEPLOYMENT_GUIDE.md          ✅ 이 파일
```

---

## ⚠️ 배포 체크리스트

### Phase 1: Apptainer 이미지 준비

- [ ] viz-node001에 SSH 접속
- [ ] `sunshine_xfce4.def` 복사
- [ ] `sudo apptainer build sunshine_xfce4.sif sunshine_xfce4.def` 실행
- [ ] 빌드 완료 확인 (20-30분)
- [ ] `apptainer exec --nv sunshine_xfce4.sif nvidia-smi` 실행 (GPU 확인)
- [ ] `/opt/apptainers/sunshine_xfce4.sif`로 복사
- [ ] 권한 설정 (755, root:root)
- [ ] 기존 VNC 이미지 무결성 확인

### Phase 2: Slurm QoS 설정

- [ ] `sacctmgr show qos` 실행
- [ ] `sudo sacctmgr add qos moonlight` 실행
- [ ] QoS 파라미터 설정
- [ ] `sacctmgr show qos moonlight` 확인
- [ ] Test Job 제출 및 확인

### Phase 3: Nginx 설정

- [ ] 기존 설정 백업
- [ ] `nginx_config_addition.conf` 내용 추가
- [ ] **⚠️ 중요**: `/api/moonlight/`를 `/api/` **위에** 추가
- [ ] `sudo nginx -t` 실행 (문법 검사)
- [ ] `sudo systemctl reload nginx` 실행

### Phase 4: Backend 시작

- [ ] `venv/bin/gunicorn -c gunicorn_config.py app:app` 실행
- [ ] `lsof -i :8004` 확인
- [ ] `curl http://localhost:8004/health` 테스트

### Phase 5: 테스트 및 검증

- [ ] `./test_all_services.sh` 실행
- [ ] 모든 테스트 통과 확인
- [ ] 기존 VNC 서비스 정상 동작 확인
- [ ] Moonlight API 정상 동작 확인

---

## 🔧 문제 해결

### 1. Backend 실행 오류

```bash
# 로그 확인
tail -f /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/MoonlightSunshine_8004/backend_moonlight_8004/logs/gunicorn_error.log

# Redis 연결 확인
redis-cli ping

# 포트 충돌 확인
lsof -i :8004
```

### 2. Nginx 설정 오류

```bash
# 백업 복원
sudo cp /etc/nginx/conf.d/auth-portal.conf.backup_YYYYMMDD_HHMMSS \
     /etc/nginx/conf.d/auth-portal.conf

# 문법 검사
sudo nginx -t

# Nginx 재시작
sudo systemctl reload nginx
```

### 3. Apptainer 빌드 실패

```bash
# Controller에서 빌드하지 말고 viz-node에서 빌드!
# NVIDIA 드라이버가 있는 노드에서만 빌드 가능

# viz-node에서 NVIDIA 확인
nvidia-smi
```

---

## 📈 다음 단계

### 단기 (완료 후)

1. **Frontend 개발** (React + Moonlight Web Client)
2. **WebRTC Signaling Server** (Port 8005)
3. **Session 관리** (Redis + Slurm Job 통합)
4. **모니터링** (Prometheus + Grafana)

### 장기

1. **성능 벤치마크** (VNC vs Moonlight 지연시간 비교)
2. **다중 GPU 지원**
3. **HEVC 코덱 지원**
4. **오디오 스트리밍**

---

## 📞 지원

### 문서 참조

- **전체 구현 계획**: [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md)
- **시스템 격리 감사**: [COMPLETE_SYSTEM_ISOLATION_AUDIT.md](COMPLETE_SYSTEM_ISOLATION_AUDIT.md)
- **Nginx 설정**: [NGINX_INTEGRATION_GUIDE.md](NGINX_INTEGRATION_GUIDE.md)
- **빌드 가이드**: [BUILD_INSTRUCTIONS.md](BUILD_INSTRUCTIONS.md)

### 로그 위치

```
backend_moonlight_8004/logs/gunicorn_error.log   # Backend 에러
backend_moonlight_8004/logs/gunicorn_access.log  # Backend 액세스
/var/log/nginx/auth-portal-error.log             # Nginx 에러
/scratch/sunshine_logs/                          # Slurm Job 로그
```

---

**배포 준비 완료 ✅**

다음 작업: viz-node에서 Apptainer 이미지 빌드 → Slurm QoS 생성 → Nginx 설정 적용
