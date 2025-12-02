# Phase 3 실행 가이드: 자동화 스크립트 작성

## 📋 개요

**목표**: 웹 서비스 설치 및 재구성 자동화 스크립트 작성
**예상 소요 시간**: 4-5시간
**의존성**: Phase 2 완료 필수

---

## ✅ 사전 확인

Phase 3 시작 전 확인사항:

```bash
# Phase 2 완료 여부 확인
./verify_phase2.sh

# 현재 서비스 상태 확인
./start_complete.sh
ps aux | grep -E "python3.*4430|vite.*4431"
./stop_complete.sh
```

---

## 📅 타임라인

| 단계 | 작업 | 예상 시간 |
|------|------|-----------|
| 1 | setup_web_services.sh 작성 | 90분 |
| 2 | reconfigure_web_services.sh 작성 | 60분 |
| 3 | 헬퍼 스크립트 작성 (4개) | 90분 |
| 4 | 테스트 및 검증 | 40분 |

**총 예상 시간: 4시간 40분**

---

## 🎯 Phase 3 상세 실행 단계

### 1️⃣ setup_web_services.sh 작성 (90분)

#### 목표
새 서버에 웹 서비스를 ONE-COMMAND로 전체 설치

#### 기능
- 명령줄 인자로 환경 선택 (development/production)
- 시스템 의존성 자동 설치
- Python 가상환경 생성 및 패키지 설치
- Node.js 패키지 설치
- .env 파일 자동 생성
- 서비스 헬스 체크
- 설치 로그 저장

#### 실행

```bash
nano web_services/scripts/setup_web_services.sh
chmod +x web_services/scripts/setup_web_services.sh
```

**사용 예시**:
```bash
# 개발 환경 전체 설치
./web_services/scripts/setup_web_services.sh development

# 프로덕션 환경 전체 설치
./web_services/scripts/setup_web_services.sh production

# 옵션:
# --skip-system-deps : 시스템 패키지 설치 스킵
# --skip-health-check : 헬스 체크 스킵
```

#### 주요 단계

```bash
#!/bin/bash
# setup_web_services.sh

# 1. 환경 파라미터 파싱
# 2. 시스템 의존성 설치 (python3, nodejs, redis, nginx)
# 3. Python 가상환경 생성 (각 서비스별)
# 4. Python 패키지 설치 (requirements.txt)
# 5. Node.js 패키지 설치 (npm install)
# 6. .env 파일 생성 (generate_env_files.py)
# 7. 빌드 (Vite 프론트엔드)
# 8. 헬스 체크
# 9. 설치 완료 메시지
```

---

### 2️⃣ reconfigure_web_services.sh 작성 (60분)

#### 목표
설치 없이 구성만 빠르게 변경 (환경 전환, 설정 업데이트)

#### 기능
- 환경 전환 (development ↔ production)
- .env 파일만 재생성
- 특정 서비스만 재구성 옵션
- Nginx 설정만 업데이트 옵션
- Dry-run 모드
- 서비스 재시작 스킵 옵션
- 롤백 지점 생성

#### 실행

```bash
nano web_services/scripts/reconfigure_web_services.sh
chmod +x web_services/scripts/reconfigure_web_services.sh
```

**사용 예시**:
```bash
# 환경 전환 (development → production)
./web_services/scripts/reconfigure_web_services.sh production

# Dry-run (실제 변경 없이 확인만)
./web_services/scripts/reconfigure_web_services.sh production --dry-run

# 특정 서비스만 재구성
./web_services/scripts/reconfigure_web_services.sh development --service auth_portal

# Nginx만 재구성
./web_services/scripts/reconfigure_web_services.sh production --nginx-only

# 재시작 스킵
./web_services/scripts/reconfigure_web_services.sh development --skip-restart

# 롤백
./web_services/scripts/reconfigure_web_services.sh --rollback
```

#### 주요 단계

```bash
#!/bin/bash
# reconfigure_web_services.sh

# 1. 환경 파라미터 및 옵션 파싱
# 2. 롤백 지점 생성 (현재 .env 파일 백업)
# 3. .env 파일 재생성
# 4. Nginx 설정 업데이트 (필요 시)
# 5. 서비스 재시작 (--skip-restart 없으면)
# 6. 헬스 체크
# 7. 완료 메시지
```

---

### 3️⃣ 헬퍼 스크립트 작성 (90분)

#### 3-1. install_dependencies.sh

**목표**: 시스템 의존성 자동 설치

```bash
nano web_services/scripts/install_dependencies.sh
chmod +x web_services/scripts/install_dependencies.sh
```

**기능**:
- Python3, pip, venv 설치
- Node.js, npm 설치
- Redis 설치
- Nginx 설치 (프로덕션)
- 기타 시스템 패키지

**사용 예시**:
```bash
./web_services/scripts/install_dependencies.sh
```

---

#### 3-2. health_check.sh

**목표**: 모든 서비스 상태 확인

```bash
nano web_services/scripts/health_check.sh
chmod +x web_services/scripts/health_check.sh
```

**기능**:
- 각 서비스 포트 체크
- HTTP 엔드포인트 체크 (/health)
- 프로세스 실행 확인
- 결과를 컬러풀하게 출력

**사용 예시**:
```bash
# 전체 서비스 헬스 체크
./web_services/scripts/health_check.sh

# 특정 서비스만 체크
./web_services/scripts/health_check.sh auth_portal

# JSON 출력
./web_services/scripts/health_check.sh --json
```

**출력 예시**:
```
🔍 웹 서비스 헬스 체크
====================

✅ Auth Portal Backend (4430)    - Running
✅ Auth Portal Frontend (4431)   - Running
✅ Dashboard Backend (5010)      - Running
❌ Dashboard Frontend (3010)     - Not Running
...

전체: 8/11 서비스 정상
```

---

#### 3-3. rollback.sh

**목표**: 설정 롤백

```bash
nano web_services/scripts/rollback.sh
chmod +x web_services/scripts/rollback.sh
```

**기능**:
- 백업된 .env 파일 복원
- 이전 버전 목록 표시
- 특정 버전으로 롤백

**사용 예시**:
```bash
# 백업 목록 확인
./web_services/scripts/rollback.sh --list

# 최신 백업으로 롤백
./web_services/scripts/rollback.sh --latest

# 특정 버전으로 롤백
./web_services/scripts/rollback.sh --version 20251019_143022
```

**백업 디렉토리 구조**:
```
backups/
├── 20251019_143022/
│   ├── auth_portal_4430.env
│   ├── auth_portal_4431.env
│   └── ...
├── 20251019_150030/
│   └── ...
└── rollback_history.log
```

---

#### 3-4. reconfigure_service.sh

**목표**: 개별 서비스 재구성

```bash
nano web_services/scripts/reconfigure_service.sh
chmod +x web_services/scripts/reconfigure_service.sh
```

**기능**:
- 특정 서비스의 .env 파일만 재생성
- 해당 서비스만 재시작
- 빠른 부분 재구성

**사용 예시**:
```bash
# Auth Portal 재구성
./web_services/scripts/reconfigure_service.sh auth_portal_backend development

# CAE Backend 재구성
./web_services/scripts/reconfigure_service.sh cae_backend production
```

---

### 4️⃣ 테스트 및 검증 (40분)

#### 테스트 1: 전체 설치 테스트

```bash
# 개발 환경 설치 테스트
./web_services/scripts/setup_web_services.sh development

# 서비스 시작 (기존 스크립트 사용)
./start_complete.sh

# 헬스 체크
./web_services/scripts/health_check.sh

# 서비스 중지
./stop_complete.sh
```

#### 테스트 2: 환경 전환 테스트

```bash
# development → production
./web_services/scripts/reconfigure_web_services.sh production

# .env 파일 확인
cat dashboard/auth_portal_4430/.env | grep FLASK_ENV
# 예상: FLASK_ENV=production

# production → development
./web_services/scripts/reconfigure_web_services.sh development

# .env 파일 확인
cat dashboard/auth_portal_4430/.env | grep FLASK_ENV
# 예상: FLASK_ENV=development
```

#### 테스트 3: Dry-run 테스트

```bash
# Dry-run 모드 테스트
./web_services/scripts/reconfigure_web_services.sh production --dry-run

# 실제 .env 파일이 변경되지 않았는지 확인
cat dashboard/auth_portal_4430/.env | grep FLASK_ENV
# 여전히 development 값이어야 함
```

#### 테스트 4: 롤백 테스트

```bash
# 현재 상태 확인
cat dashboard/auth_portal_4430/.env | head -n 5

# 환경 변경
./web_services/scripts/reconfigure_web_services.sh production

# 롤백
./web_services/scripts/rollback.sh --latest

# 원래대로 돌아왔는지 확인
cat dashboard/auth_portal_4430/.env | head -n 5
```

#### 테스트 5: 헬스 체크 테스트

```bash
# 서비스 시작
./start_complete.sh

# 헬스 체크
./web_services/scripts/health_check.sh

# 특정 서비스만 체크
./web_services/scripts/health_check.sh auth_portal

# JSON 출력
./web_services/scripts/health_check.sh --json
```

---

## ⚠️ 주의사항

### ❌ 하지 말아야 할 것

1. **기존 start/stop 스크립트 수정 금지**
   - `start_complete.sh` - 그대로 사용
   - `stop_complete.sh` - 그대로 사용
   - 새 스크립트는 설정 관리만 담당

2. **서비스 실행 로직 변경 금지**
   - Phase 3는 설정 자동화만
   - 서비스 시작/중지는 기존 방식 유지

3. **Slurm 설정 건드리지 말 것**
   - `my_cluster.yaml` - 절대 수정 금지
   - `setup_cluster_full.sh` - 절대 수정 금지

### ✅ 반드시 해야 할 것

1. **스크립트 실행 권한 설정**
   ```bash
   chmod +x web_services/scripts/*.sh
   ```

2. **백업 정책 확인**
   ```bash
   # 백업 디렉토리 존재 확인
   ls -la backups/
   ```

3. **기존 서비스 호환성 확인**
   ```bash
   # 새 스크립트 사용 후에도 기존 방식 동작 확인
   ./start_complete.sh
   ./stop_complete.sh
   ```

---

## 🔧 트러블슈팅

### 문제 1: setup_web_services.sh 실행 중 권한 오류

**증상**:
```
E: Could not open lock file /var/lib/dpkg/lock-frontend
```

**해결**:
```bash
# sudo 권한으로 실행
sudo ./web_services/scripts/setup_web_services.sh development

# 또는 --skip-system-deps 옵션 사용
./web_services/scripts/setup_web_services.sh development --skip-system-deps
```

### 문제 2: Node.js 버전 충돌

**증상**:
```
npm ERR! engine Unsupported engine
```

**해결**:
```bash
# Node.js 버전 확인
node --version

# nvm으로 버전 관리
nvm install 18
nvm use 18
```

### 문제 3: 헬스 체크 실패

**증상**:
```
❌ Auth Portal Backend (4430) - Not Running
```

**해결**:
```bash
# 서비스 로그 확인
tail -f dashboard/auth_portal_4430/logs/app.log

# 포트 사용 확인
sudo lsof -i :4430

# .env 파일 확인
cat dashboard/auth_portal_4430/.env
```

### 문제 4: 롤백 실패

**증상**:
```
❌ 백업 파일 없음
```

**해결**:
```bash
# 백업 디렉토리 확인
ls -la backups/

# 수동으로 .env 파일 복원
cp backups/20251019_143022/auth_portal_4430.env dashboard/auth_portal_4430/.env
```

---

## 📈 진행 상황 체크

### Phase 3 완료 기준

- [x] Phase 2 완료 확인
- [ ] `setup_web_services.sh` 작성 및 테스트
- [ ] `reconfigure_web_services.sh` 작성 및 테스트
- [ ] `install_dependencies.sh` 작성
- [ ] `health_check.sh` 작성
- [ ] `rollback.sh` 작성
- [ ] `reconfigure_service.sh` 작성
- [ ] 모든 테스트 시나리오 통과
- [ ] `verify_phase3.sh` 통과

### 완료 후 다음 단계

```bash
# Phase 3 완료 확인
./verify_phase3.sh

# 성공 시 출력 예상:
# ✅✅✅ Phase 3 완료!
#
# 📋 다음 단계:
#    cat PHASE4_GUIDE.md
```

---

## 🎓 Phase 3에서 생성된 파일 목록

### 신규 생성 스크립트 (6개)

```
web_services/scripts/
├── setup_web_services.sh           # 전체 설치
├── reconfigure_web_services.sh     # 재구성
├── install_dependencies.sh         # 의존성 설치
├── health_check.sh                 # 헬스 체크
├── rollback.sh                     # 롤백
└── reconfigure_service.sh          # 개별 서비스 재구성
```

### 백업 디렉토리

```
backups/
├── YYYYMMDD_HHMMSS/
│   ├── *.env
│   └── ...
└── rollback_history.log
```

---

## 📊 스크립트 기능 비교

| 스크립트 | 용도 | 실행 시간 | 사용 시나리오 |
|---------|------|-----------|--------------|
| setup_web_services.sh | 전체 설치 | 10-15분 | 새 서버 초기 설치 |
| reconfigure_web_services.sh | 재구성 | 1-2분 | 환경 전환, 설정 변경 |
| reconfigure_service.sh | 개별 재구성 | 10초 | 특정 서비스만 수정 |
| health_check.sh | 상태 확인 | 5초 | 서비스 동작 확인 |
| rollback.sh | 롤백 | 10초 | 설정 복원 |

---

## 🚀 사용 시나리오 예시

### 시나리오 1: 새 서버에 개발 환경 설치

```bash
# 1. 전체 설치
./web_services/scripts/setup_web_services.sh development

# 2. 서비스 시작
./start_complete.sh

# 3. 헬스 체크
./web_services/scripts/health_check.sh
```

### 시나리오 2: 개발 → 프로덕션 배포

```bash
# 1. 프로덕션 환경으로 재구성
./web_services/scripts/reconfigure_web_services.sh production

# 2. 서비스 재시작
./stop_complete.sh
./start_complete.sh

# 3. 헬스 체크
./web_services/scripts/health_check.sh
```

### 시나리오 3: 설정 변경 후 문제 발생 시 롤백

```bash
# 1. 문제 발견
./web_services/scripts/health_check.sh
# ❌ 일부 서비스 실패

# 2. 롤백
./web_services/scripts/rollback.sh --latest

# 3. 서비스 재시작
./stop_complete.sh
./start_complete.sh

# 4. 재확인
./web_services/scripts/health_check.sh
# ✅ 모두 정상
```

### 시나리오 4: Auth Portal만 재구성

```bash
# 1. Auth Portal Backend만 재구성
./web_services/scripts/reconfigure_service.sh auth_portal_backend development

# 2. Auth Portal만 재시작
pkill -f "auth_portal_4430"
cd dashboard/auth_portal_4430 && python3 app.py &

# 3. 헬스 체크
./web_services/scripts/health_check.sh auth_portal
```

---

## ⏭️ Phase 4 준비사항

Phase 3 완료 후 Phase 4에서는:

1. **Nginx 설정 자동화**
   - Nginx 설정 템플릿 작성
   - SSL 인증서 설정
   - Reverse proxy 라우팅 자동 구성

2. **setup_nginx.sh 스크립트**
   - Nginx 설치 및 설정
   - 설정 검증 및 리로드

3. **통합 테스트**
   - Nginx를 통한 전체 서비스 접근 테스트

---

## 💬 질문 및 지원

Phase 3 진행 중 문제 발생 시:

1. `verify_phase3.sh` 실행하여 누락 확인
2. 트러블슈팅 섹션 참조
3. 헬스 체크로 서비스 상태 확인

**예상 소요 시간: 4-5시간**
**난이도: 중상급 (Bash 스크립팅, 시스템 관리 지식 필요)**
