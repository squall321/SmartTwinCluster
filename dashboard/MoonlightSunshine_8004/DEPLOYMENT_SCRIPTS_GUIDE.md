# Moonlight/Sunshine 배포 스크립트 가이드

**작성일**: 2025-12-06
**버전**: 1.0.0
**목적**: 자동화된 배포 스크립트 사용 가이드

---

## 📦 배포 스크립트 목록

### 1. 전체 자동 배포

```bash
./deploy_all.sh
```

**설명**: 3단계 배포를 자동으로 순차 실행
**소요시간**: 75-105분
**필요 권한**: sudo, viz-node SSH

**실행 흐름**:
1. Step 1: viz-node로 SSH 연결 → 이미지 빌드 (60-90분)
2. Step 2: Controller에서 Slurm QoS 생성 (5분)
3. Step 3: Controller에서 Nginx 설정 적용 (10분)

---

### 2. 단계별 수동 배포

각 단계를 개별적으로 실행 가능:

#### Step 1: Apptainer 이미지 빌드

```bash
# viz-node001에서 실행
ssh viz-node001
cd /tmp
scp controller:/path/to/MoonlightSunshine_8004/deploy_step1_build_images.sh .
sudo bash deploy_step1_build_images.sh
```

**소요시간**: 60-90분 (from-scratch) or 30-40분 (VNC 재사용)
**위치**: viz-node001
**필요 권한**: sudo

**기능**:
- 환경 확인 (NVIDIA GPU, Apptainer)
- 빌드 전략 선택 (from-scratch vs VNC 재사용)
- 3개 이미지 빌드 (desktop, gnome, gnome_lsprepost)
- GPU 및 Sunshine 버전 검증
- /opt/apptainers/로 복사

---

#### Step 2: Slurm QoS 생성

```bash
# Controller에서 실행
cd /path/to/MoonlightSunshine_8004
./deploy_step2_create_qos.sh
```

**소요시간**: 5분
**위치**: Controller
**필요 권한**: sudo (sacctmgr)

**기능**:
- 기존 QoS 확인 및 백업
- moonlight QoS 생성 또는 업데이트
- QoS 파라미터 설정:
  - Priority: 100
  - GraceTime: 60초
  - MaxWall: 8시간
  - MaxTRESPerUser: gpu=2
- 사용자 QoS 권한 확인 및 추가
- 테스트 Job 제출 (선택사항)

---

#### Step 3: Nginx 설정 적용

```bash
# Controller에서 실행
cd /path/to/MoonlightSunshine_8004
./deploy_step3_nginx.sh
```

**소요시간**: 10분
**위치**: Controller
**필요 권한**: sudo (nginx)

**기능**:
- 기존 Nginx 설정 자동 백업
- Moonlight upstream 정의 추가
- /api/moonlight/ location 추가 (/api/ 위에)
- Nginx 문법 검사
- Nginx 재시작
- API 엔드포인트 테스트

---

## 🚀 사용 시나리오

### 시나리오 1: 완전 자동 배포 (권장)

**조건**:
- Controller에서 viz-node로 패스워드 없이 SSH 가능
- sudo 권한 보유

**실행**:
```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/MoonlightSunshine_8004
./deploy_all.sh
```

**예상 출력**:
```
========================================
  Moonlight/Sunshine 전체 배포
========================================

배포 단계:
  Step 1: Apptainer 이미지 빌드 (viz-node)
  Step 2: Slurm QoS 생성 (Controller)
  Step 3: Nginx 설정 적용 (Controller)

배포를 시작하시겠습니까? (y/N): y

[INFO] 배포 시작: 2025-12-06 14:30:00
...
[SUCCESS] ✅ Step 1 완료: Apptainer 이미지 빌드 성공
[SUCCESS] ✅ Step 2 완료: Slurm QoS 생성 성공
[SUCCESS] ✅ Step 3 완료: Nginx 설정 적용 성공

========================================
  🎉 배포 완료!
========================================

총 소요시간: 75분
```

---

### 시나리오 2: 단계별 수동 배포

**조건**:
- viz-node SSH 패스워드 필요
- 각 단계를 수동으로 확인하고 싶은 경우

**실행**:

**1단계: 이미지 빌드**
```bash
# Controller에서
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/MoonlightSunshine_8004

scp deploy_step1_build_images.sh viz-node001:/tmp/
scp build_sunshine_images.sh viz-node001:/tmp/
scp sunshine_*.def viz-node001:/tmp/

# viz-node로 이동
ssh viz-node001
cd /tmp
sudo bash deploy_step1_build_images.sh
# 빌드 전략 선택: 1 (from-scratch) 또는 2 (VNC 재사용)
```

**2단계: QoS 생성**
```bash
# Controller로 돌아옴
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/MoonlightSunshine_8004
./deploy_step2_create_qos.sh
```

**3단계: Nginx 설정**
```bash
# Controller에서
./deploy_step3_nginx.sh
# Nginx 재시작: y
```

---

### 시나리오 3: 특정 단계만 재실행

#### Apptainer 이미지 재빌드
```bash
ssh viz-node001
cd /tmp
sudo bash deploy_step1_build_images.sh
```

#### Slurm QoS 재설정
```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/MoonlightSunshine_8004
./deploy_step2_create_qos.sh
```

#### Nginx 설정 재적용
```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/MoonlightSunshine_8004
./deploy_step3_nginx.sh
```

---

## 🔍 스크립트 상세 기능

### deploy_all.sh

**주요 기능**:
- 사전 확인
  - 필요한 스크립트 파일 존재 여부
  - sudo 권한
  - viz-node SSH 접근
  - Backend 실행 상태 (Port 8004)

- Step 1: Apptainer 이미지 빌드
  - viz-node로 SSH 연결
  - 스크립트 및 Definition 파일 복사
  - 원격 실행 (interactive)

- Step 2: Slurm QoS 생성
  - deploy_step2_create_qos.sh 실행

- Step 3: Nginx 설정 적용
  - deploy_step3_nginx.sh 실행

- 배포 완료 보고
  - 총 소요시간
  - 각 단계별 소요시간
  - 다음 단계 안내

**에러 처리**:
- 각 단계 실패 시 즉시 중단
- 에러 메시지 출력 및 수동 실행 가이드 제공

---

### deploy_step1_build_images.sh

**주요 기능**:
1. 환경 확인
   - NVIDIA GPU: `nvidia-smi`
   - Apptainer: `apptainer --version`
   - sudo 권한

2. 빌드 전략 선택 (Interactive)
   ```
   1) From-scratch 빌드 (권장)
      - 소요시간: 60-90분
      - 장점: 깨끗한 구성, 최신 패키지

   2) VNC 이미지 재사용
      - 소요시간: 30-40분
      - 장점: 빠름, 기존 환경 재사용
   ```

3. 빌드 실행
   - 작업 디렉토리: `/tmp/sunshine_build_YYYYMMDD_HHMMSS`
   - 빌드 스크립트 실행 (선택된 전략)
   - 진행 상황 로그 출력

4. 이미지 검증
   - GPU 접근 테스트: `apptainer exec --nv <image> nvidia-smi`
   - Sunshine 버전 확인: `apptainer exec <image> sunshine --version`

5. /opt/apptainers/로 복사
   - 권한 설정: 755
   - 소유자: root:root

6. 정리
   - 작업 디렉토리 삭제 (선택사항)

**출력 예시**:
```
[INFO] Step 1: 환경 확인 시작
[INFO] 현재 노드: viz-node001
[INFO] ✅ NVIDIA GPU 확인 완료
NVIDIA A100 80GB PCIe, Driver Version: 535.129.03, 80GB

[INFO] Step 2: 빌드 전략 선택
빌드 전략을 선택하세요 (1 or 2): 1
[INFO] 선택: From-scratch 빌드 (예상 60-90분)

[INFO] Step 4: 이미지 빌드 시작
[INFO] 빌드 시작: 2025-12-06 14:30:00
...
[INFO] ✅ 이미지 빌드 성공!
[INFO] 소요시간: 75분

[INFO] Step 5: 빌드된 이미지 확인
[INFO] ✅ sunshine_desktop.sif (600M)
[INFO] ✅ sunshine_gnome.sif (900M)
[INFO] ✅ sunshine_gnome_lsprepost.sif (1.5G)

[INFO] Step 6: 이미지 검증
[INFO] 검증 중: sunshine_desktop.sif
[INFO]   ✅ GPU 접근 성공
[INFO]   ✅ Sunshine: 0.23.1

[INFO] Step 7: 이미지를 /opt/apptainers/로 복사
[INFO] ✅ 복사 완료

[INFO] 🎉 Step 1: Apptainer 이미지 빌드 완료!
```

---

### deploy_step2_create_qos.sh

**주요 기능**:
1. Slurm 설치 확인
   - `sacctmgr` 명령어 존재 확인
   - Slurm 버전 출력

2. 기존 QoS 확인
   - `sacctmgr show qos` 실행
   - moonlight QoS 존재 여부 확인
   - 기존 QoS 삭제 또는 업데이트 선택

3. Moonlight QoS 생성
   ```bash
   sudo sacctmgr add qos moonlight
   sudo sacctmgr modify qos moonlight set \
       Priority=100 \
       GraceTime=60 \
       MaxWall=8:00:00 \
       MaxTRESPerUser=gpu=2
   ```

4. QoS 확인
   - 설정값 검증
   - 파라미터 출력

5. 사용자 QoS 권한 확인
   - 현재 사용자의 QoS 목록 확인
   - moonlight QoS 추가 (선택사항)

6. 테스트 Job 제출 (선택사항)
   - 5분짜리 테스트 Job 생성
   - moonlight QoS로 제출
   - Job 상태 확인

**출력 예시**:
```
[INFO] Step 2: Slurm QoS 생성 시작
[INFO] ✅ Slurm 버전: slurm 23.02.6

[INFO] 기존 QoS 목록 확인 중...
==========================================
Name|Priority|MaxWall|MaxTRESPU|GraceTime|
normal|0|||0|
==========================================

[INFO] Moonlight QoS 생성 중...
[INFO] ✅ QoS 생성 완료

[INFO] 생성된 QoS 확인
==========================================
Name|Priority|MaxWall|MaxTRESPU|GraceTime|
moonlight|100|08:00:00|gpu=2|00:01:00|
==========================================

[INFO] ✅ 사용자 koopark는 moonlight QoS 사용 가능

[INFO] 🎉 Step 2: Slurm QoS 생성 완료!
```

---

### deploy_step3_nginx.sh

**주요 기능**:
1. Nginx 설치 확인
   - `nginx -v` 실행
   - 설정 파일 존재 확인: `/etc/nginx/conf.d/auth-portal.conf`

2. 현재 설정 백업
   - 백업 파일: `auth-portal.conf.backup_YYYYMMDD_HHMMSS`
   - 최근 5개 백업 파일 목록 출력

3. Moonlight 설정 파일 확인
   - `nginx_config_addition.conf` 존재 확인
   - 설정 내용 미리보기

4. 기존 설정 검색
   - `moonlight_backend` 키워드 검색
   - 기존 설정 덮어쓰기 또는 건너뛰기 선택

5. Nginx 설정 자동 추가
   - 기존 moonlight 설정 제거 (있다면)
   - Upstream 정의 추가 (server 블록 위)
   - /api/moonlight/ location 추가 (/api/ 위)

6. Nginx 문법 검사
   - `sudo nginx -t` 실행
   - 실패 시 백업 파일로 복원

7. Nginx 재시작
   - `sudo systemctl reload nginx` 실행 (선택사항)

8. API 테스트
   - Backend 실행 확인 (Port 8004)
   - 로컬 테스트: `curl http://localhost:8004/health`
   - Nginx 테스트: `curl -k https://localhost/api/moonlight/images`

**출력 예시**:
```
[INFO] Step 3: Nginx 설정 적용 시작
[INFO] ✅ Nginx 버전: 1.18.0
[INFO] ✅ Nginx 설정 파일: /etc/nginx/conf.d/auth-portal.conf

[INFO] Nginx 설정 백업
[INFO] 백업 파일: /etc/nginx/conf.d/auth-portal.conf.backup_20251206_143000
[INFO] ✅ 백업 완료

[INFO] Nginx 설정 자동 추가 시작
[INFO] 1. Upstream 정의 추가 중...
[INFO] ✅ Upstream 정의 추가 완료
[INFO] 2. /api/moonlight/ location 추가 중...
[INFO] ✅ /api/moonlight/ location 추가 완료 (Line 102 위)

[INFO] Nginx 설정 문법 검사
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
[INFO] ✅ Nginx 설정 문법 검사 통과

[INFO] Nginx 재시작
Nginx를 재시작하시겠습니까? (y/N): y
[INFO] ✅ Nginx 재시작 성공

[INFO] Moonlight API 테스트
[INFO] ✅ Moonlight Backend 실행 중 (Port 8004)

로컬 테스트 (http://localhost:8004/health):
{"status": "healthy", "service": "moonlight_backend", "port": 8004}

Nginx를 통한 테스트 (https://localhost/api/moonlight/images):
{"images": [...]}

[INFO] 🎉 Step 3: Nginx 설정 적용 완료!
```

---

## 🛠️ 문제 해결

### Step 1 실패: NVIDIA GPU 없음

**증상**:
```
[ERROR] nvidia-smi를 찾을 수 없습니다
```

**원인**: Controller에서 실행 (viz-node가 아님)

**해결**:
```bash
ssh viz-node001
sudo bash /tmp/deploy_step1_build_images.sh
```

---

### Step 1 실패: Apptainer 빌드 실패

**증상**:
```
[ERROR] ❌ 이미지 빌드 실패
```

**원인**:
- 네트워크 문제 (Sunshine 다운로드 실패)
- 디스크 공간 부족
- Definition 파일 오류

**해결**:
```bash
# 작업 디렉토리 확인
cd /tmp/sunshine_build_*/

# 로그 확인
cat build.log

# 디스크 공간 확인
df -h /tmp

# 수동 빌드 시도
sudo apptainer build sunshine_desktop.sif sunshine_desktop.def
```

---

### Step 2 실패: QoS 이미 존재

**증상**:
```
[WARN] ⚠️  'moonlight' QoS가 이미 존재합니다
```

**해결**:
1. 기존 QoS 삭제 후 재생성 선택: `y`
2. 또는 수동 삭제:
   ```bash
   sudo sacctmgr delete qos moonlight
   ```

---

### Step 3 실패: Nginx 문법 오류

**증상**:
```
[ERROR] ❌ Nginx 설정 문법 오류 발생
[ERROR] ✅ 백업 파일 복원 완료
```

**원인**: 설정 파일 충돌 또는 문법 오류

**해결**:
```bash
# 백업 파일 확인
ls -lh /etc/nginx/conf.d/auth-portal.conf.backup_*

# 수동 복원
sudo cp /etc/nginx/conf.d/auth-portal.conf.backup_YYYYMMDD_HHMMSS \
        /etc/nginx/conf.d/auth-portal.conf

# 문법 검사
sudo nginx -t
```

---

### deploy_all.sh: viz-node SSH 실패

**증상**:
```
[WARN] ⚠️  viz-node SSH 접근 실패 (패스워드 필요하거나 접근 불가)
[WARN] Step 1을 수동으로 실행해야 합니다
```

**해결**:
1. SSH 키 기반 인증 설정:
   ```bash
   ssh-copy-id viz-node001
   ```

2. 또는 Step 1 수동 실행:
   ```bash
   ssh viz-node001
   # 패스워드 입력
   sudo bash /tmp/deploy_step1_build_images.sh
   ```

---

## 📊 배포 체크리스트

### 배포 전

- [ ] Backend 실행 중 (Port 8004)
- [ ] Redis 실행 중 (Port 6379)
- [ ] sudo 권한 보유
- [ ] viz-node SSH 접근 가능 (패스워드 없이)
- [ ] 디스크 공간 충분 (최소 10GB)

### 배포 중

- [ ] Step 1: Apptainer 이미지 빌드 (60-90분)
  - [ ] sunshine_desktop.sif (600MB)
  - [ ] sunshine_gnome.sif (900MB)
  - [ ] sunshine_gnome_lsprepost.sif (1.5GB)

- [ ] Step 2: Slurm QoS 생성 (5분)
  - [ ] moonlight QoS 존재
  - [ ] Priority: 100
  - [ ] MaxWall: 8:00:00
  - [ ] MaxTRESPerUser: gpu=2

- [ ] Step 3: Nginx 설정 적용 (10분)
  - [ ] upstream moonlight_backend
  - [ ] location /api/moonlight/
  - [ ] Nginx 재시작 성공

### 배포 후

- [ ] 이미지 확인: `ls -lh /opt/apptainers/sunshine_*.sif`
- [ ] QoS 확인: `sacctmgr show qos moonlight`
- [ ] Nginx 확인: `sudo nginx -t`
- [ ] API 테스트: `curl -k https://110.15.177.120/api/moonlight/images`
- [ ] 세션 생성 테스트

---

## 📚 참고 자료

### 관련 문서

- [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) - 전체 배포 가이드
- [IMPLEMENTATION_STATUS.md](IMPLEMENTATION_STATUS.md) - 현재 구현 상태
- [BUILD_INSTRUCTIONS.md](BUILD_INSTRUCTIONS.md) - Apptainer 빌드 가이드
- [SLURM_QOS_SETUP.md](SLURM_QOS_SETUP.md) - Slurm QoS 설정
- [NGINX_INTEGRATION_GUIDE.md](NGINX_INTEGRATION_GUIDE.md) - Nginx 통합 가이드

### 스크립트 위치

```
MoonlightSunshine_8004/
├── deploy_all.sh                    # 전체 자동 배포
├── deploy_step1_build_images.sh     # Step 1: 이미지 빌드
├── deploy_step2_create_qos.sh       # Step 2: QoS 생성
├── deploy_step3_nginx.sh            # Step 3: Nginx 설정
├── build_sunshine_images.sh         # From-scratch 빌드
├── build_from_vnc_images.sh         # VNC 재사용 빌드
├── sunshine_desktop.def             # XFCE4 Definition
├── sunshine_gnome.def               # GNOME Definition
└── sunshine_gnome_lsprepost.def     # GNOME+LS-PrePost Definition
```

---

**최종 업데이트**: 2025-12-06
**버전**: 1.0.0
