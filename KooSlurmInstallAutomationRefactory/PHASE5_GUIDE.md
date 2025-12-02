# Phase 5 실행 가이드: 통합 테스트 및 최종 검증

## 📋 개요

**목표**: 전체 시스템 통합 테스트 및 프로덕션 배포 준비 완료
**예상 소요 시간**: 3-4시간
**의존성**: Phase 0~4 완료 필수

---

## ✅ 사전 확인

Phase 5 시작 전 확인사항:

```bash
# 모든 Phase 완료 확인
./verify_phase0.sh
./verify_phase1.sh
./verify_phase2.sh
./verify_phase3.sh
./verify_phase4.sh
```

---

## 📅 타임라인

| 단계 | 작업 | 예상 시간 |
|------|------|-----------|
| 1 | 개발 환경 통합 테스트 | 60분 |
| 2 | 프로덕션 환경 시뮬레이션 | 60분 |
| 3 | 새 서버 배포 테스트 | 40분 |
| 4 | 최종 문서 작성 | 40분 |
| 5 | 전체 검증 | 20분 |

**총 예상 시간: 3시간 40분**

---

## 🎯 Phase 5 상세 실행 단계

### 1️⃣ 개발 환경 통합 테스트 (60분)

#### 목표
모든 컴포넌트가 개발 환경에서 정상 동작하는지 확인

#### 테스트 1-1: 전체 설치 테스트

```bash
# 1. 현재 상태 백업
./web_services/scripts/rollback.sh --create-backup

# 2. 모든 서비스 중지
./stop_complete.sh
pkill -f "python3.*dashboard"
pkill -f "vite"

# 3. 전체 설치
./web_services/scripts/setup_web_services.sh development

# 예상 결과:
# - 의존성 설치 완료
# - .env 파일 8개 생성
# - Python 가상환경 생성
# - Node.js 패키지 설치
# - 프론트엔드 빌드 완료
```

#### 테스트 1-2: 서비스 시작 및 헬스 체크

```bash
# 1. 서비스 시작
./start_complete.sh

# 2. 헬스 체크
./web_services/scripts/health_check.sh

# 예상 결과:
# ✅ Auth Portal Backend (4430) - Running
# ✅ Auth Portal Frontend (4431) - Running
# ✅ Dashboard Backend (5010) - Running
# ✅ Dashboard Frontend (3010) - Running
# ✅ CAE Backend (5000) - Running
# ✅ CAE Automation (5001) - Running
# ✅ CAE Frontend (5173) - Running
# ✅ VNC Service (8002) - Running
# ✅ Prometheus (9090) - Running
# ✅ Node Exporter (9100) - Running
```

#### 테스트 1-3: Nginx 설정 및 Reverse Proxy 테스트

```bash
# 1. Nginx 설정
./web_services/scripts/setup_nginx.sh development

# 2. Nginx 상태 확인
sudo systemctl status nginx
sudo nginx -t

# 3. Reverse Proxy 동작 확인
curl -I http://localhost/auth/health
curl -I http://localhost/api/health
curl -I http://localhost/cae/api/health
```

#### 테스트 1-4: 브라우저 접속 테스트

**체크리스트**:
- [ ] http://localhost/ → Auth Portal 메인 페이지 표시
- [ ] http://localhost/dashboard → Dashboard 페이지 표시
- [ ] http://localhost/cae → CAE 페이지 표시
- [ ] http://localhost/vnc → VNC 페이지 표시
- [ ] SSO 로그인 스킵됨 (개발 환경)
- [ ] 테스트 로그인 버튼 동작
- [ ] 서비스 메뉴에서 각 서비스 이동 가능

#### 테스트 1-5: 환경 전환 테스트

```bash
# development → production
./web_services/scripts/reconfigure_web_services.sh production

# .env 파일 확인
cat dashboard/auth_portal_4430/.env | grep FLASK_ENV
# 예상: FLASK_ENV=production

# Nginx 재설정
./web_services/scripts/setup_nginx.sh production

# 롤백 테스트
./web_services/scripts/rollback.sh --latest

# .env 파일 확인
cat dashboard/auth_portal_4430/.env | grep FLASK_ENV
# 예상: FLASK_ENV=development (롤백됨)
```

---

### 2️⃣ 프로덕션 환경 시뮬레이션 (60분)

#### 목표
실제 프로덕션 배포 시나리오 검증

#### 테스트 2-1: SSL 인증서 생성 (자체 서명)

```bash
# 1. 자체 서명 인증서 생성
sudo ./web_services/scripts/generate_self_signed_cert.sh hpc.example.com

# 2. 인증서 확인
ls -la /etc/ssl/certs/hpc.example.com.crt
ls -la /etc/ssl/private/hpc.example.com.key

# 3. 인증서 유효성 확인
openssl x509 -in /etc/ssl/certs/hpc.example.com.crt -text -noout | grep Subject
```

#### 테스트 2-2: 프로덕션 환경 설정

```bash
# 1. web_services_config.yaml 도메인 설정 확인
grep "domain:" web_services_config.yaml
# 필요 시 수정: domain: "hpc.example.com"

# 2. 프로덕션 환경 변수 생성
python3 web_services/scripts/generate_env_files.py production

# 3. .env 파일 확인
cat dashboard/auth_portal_4430/.env | grep -E "FLASK_ENV|DASHBOARD_URL"
# 예상:
# FLASK_ENV=production
# DASHBOARD_URL=https://hpc.example.com/dashboard
```

#### 테스트 2-3: 프로덕션 Nginx 설정

```bash
# 1. Nginx 설정 생성
./web_services/scripts/setup_nginx.sh production

# 2. Nginx 설정 검증
sudo nginx -t

# 3. Nginx 설정 파일 확인
sudo cat /etc/nginx/sites-enabled/hpc_web_services.conf | grep -E "listen|ssl|server_name"

# 예상:
# listen 443 ssl http2;
# server_name hpc.example.com;
# ssl_certificate /etc/ssl/certs/hpc.example.com.crt;
```

#### 테스트 2-4: HTTPS 접속 테스트

```bash
# /etc/hosts에 도메인 추가 (테스트용)
echo "127.0.0.1 hpc.example.com" | sudo tee -a /etc/hosts

# 서비스 재시작
./stop_complete.sh
./start_complete.sh

# Nginx 재시작
sudo systemctl restart nginx

# HTTPS 접속 테스트
curl -k -I https://hpc.example.com/
curl -k -I https://hpc.example.com/auth/health
curl -k -I https://hpc.example.com/api/health

# 브라우저 접속
# https://hpc.example.com/
# (자체 서명 인증서 경고 무시하고 진행)
```

#### 테스트 2-5: 방화벽 설정 (프로덕션)

```bash
# 1. ufw 설치 확인
sudo ufw status

# 2. 방화벽 규칙 추가 (시뮬레이션)
sudo ufw allow 80/tcp comment 'Nginx HTTP'
sudo ufw allow 443/tcp comment 'Nginx HTTPS'

# 3. 내부 포트 차단 확인 (실제로는 차단하지 않음 - 시뮬레이션만)
# sudo ufw deny 4430/tcp
# sudo ufw deny 4431/tcp
# ... (개발 환경이므로 실제로는 실행 안 함)

# 4. 방화벽 상태 확인
sudo ufw status verbose
```

---

### 3️⃣ 새 서버 배포 테스트 (40분)

#### 목표
완전히 새로운 서버에 ONE-COMMAND 배포가 가능한지 검증

#### 시나리오: 신규 서버 초기 설정

**가정**: Ubuntu 20.04/22.04 서버, 아무것도 설치 안 됨

```bash
# ============================================================================
# 새 서버에서 실행할 명령어 (순서대로)
# ============================================================================

# 1. Git 클론 (이미 있다고 가정)
# git clone <repository_url>
# cd KooSlurmInstallAutomationRefactory

# 2. Phase 0 실행
./collect_current_state.sh
./create_directory_structure.sh
./verify_phase0.sh

# 3. Phase 1 실행 (파일 이미 존재)
./verify_phase1.sh

# 4. Phase 2 실행 (코드 이미 수정됨)
pip3 install pyyaml jinja2
python3 web_services/scripts/generate_env_files.py development
./verify_phase2.sh

# 5. Phase 3 - 전체 설치 (ONE COMMAND!)
./web_services/scripts/setup_web_services.sh development

# 6. Phase 4 - Nginx 설정 (선택사항, 개발 환경에서는 불필요)
# ./web_services/scripts/setup_nginx.sh development

# 7. 서비스 시작
./start_complete.sh

# 8. 헬스 체크
./web_services/scripts/health_check.sh

# 예상 총 소요 시간: 10-15분
```

#### 테스트 3-1: 타이머로 측정

```bash
# 시작 시간 기록
echo "테스트 시작: $(date)"
START_TIME=$(date +%s)

# ONE-COMMAND 설치
./web_services/scripts/setup_web_services.sh development

# 종료 시간 기록
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
echo "소요 시간: $DURATION 초 ($(($DURATION / 60)) 분)"

# 목표: 15분 이내 완료
```

#### 테스트 3-2: 설치 후 즉시 사용 가능 확인

```bash
# 서비스 시작
./start_complete.sh

# 즉시 헬스 체크
sleep 5  # 서비스 시작 대기
./web_services/scripts/health_check.sh

# 브라우저 접속 테스트
# http://localhost:4431/
```

---

### 4️⃣ 최종 문서 작성 (40분)

#### 문서 4-1: README.md 업데이트

```bash
nano README.md
```

**포함 내용**:
- 프로젝트 개요
- 아키텍처 다이어그램
- 빠른 시작 가이드
- Phase별 실행 가이드 링크
- 트러블슈팅
- FAQ

#### 문서 4-2: DEPLOYMENT.md 작성

```bash
nano DEPLOYMENT.md
```

**포함 내용**:
- 신규 서버 배포 절차
- 환경별 설정 차이 (development vs production)
- SSL 인증서 설정
- 방화벽 설정
- 모니터링 설정
- 백업 및 복구

#### 문서 4-3: OPERATIONS.md 작성

```bash
nano OPERATIONS.md
```

**포함 내용**:
- 일상 운영 작업
- 로그 확인 방법
- 서비스 재시작 절차
- 환경 전환 절차
- 롤백 절차
- 성능 모니터링

#### 문서 4-4: TROUBLESHOOTING.md 작성

```bash
nano TROUBLESHOOTING.md
```

**포함 내용**:
- 자주 발생하는 문제
- 로그 분석 방법
- 서비스별 문제 해결
- 네트워크 문제 해결
- SSL 인증서 문제
- 연락처 및 지원

---

### 5️⃣ 전체 검증 (20분)

#### 최종 검증 스크립트 실행

```bash
# 전체 Phase 검증
./verify_phase0.sh && \
./verify_phase1.sh && \
./verify_phase2.sh && \
./verify_phase3.sh && \
./verify_phase4.sh && \
./verify_phase5.sh

# 모두 통과 시:
# ✅✅✅ 모든 Phase 완료!
```

#### 최종 체크리스트

**파일 생성 확인**:
- [ ] Phase 0: 4개 파일
- [ ] Phase 1: 12개 파일 (config, templates)
- [ ] Phase 2: generate_env_files.py, 수정된 코드 5개
- [ ] Phase 3: 6개 자동화 스크립트
- [ ] Phase 4: Nginx 템플릿 및 스크립트
- [ ] Phase 5: 최종 문서

**기능 확인**:
- [ ] ONE-COMMAND 설치 동작
- [ ] 환경 전환 (development ↔ production)
- [ ] Nginx reverse proxy 동작
- [ ] SSL 인증서 설정
- [ ] 헬스 체크 동작
- [ ] 롤백 기능 동작
- [ ] 기존 start/stop 스크립트 호환성

**문서 확인**:
- [ ] README.md 완성
- [ ] DEPLOYMENT.md 작성
- [ ] OPERATIONS.md 작성
- [ ] TROUBLESHOOTING.md 작성
- [ ] 각 Phase 가이드 존재

---

## ⚠️ 주의사항

### ❌ 하지 말아야 할 것

1. **Slurm 설정 절대 수정 금지**
   - `my_cluster.yaml`
   - `setup_cluster_full.sh`
   - 기타 Slurm 관련 파일

2. **프로덕션 데이터베이스 테스트 금지**
   - 실제 프로덕션 DB 연결 안 함
   - 테스트는 개발 환경에서만

3. **민감 정보 Git 커밋 금지**
   - `.env` 파일
   - SSL 개인키 (`.key`)
   - 비밀번호, API 키

### ✅ 반드시 해야 할 것

1. **전체 백업**
   ```bash
   # Git 커밋 (사용자가 직접 수행)
   # 또는 파일 백업
   tar czf backup_$(date +%Y%m%d_%H%M%S).tar.gz \
     dashboard/ web_services/ *.sh *.yaml *.md
   ```

2. **문서 검토**
   - README.md 읽어보기
   - DEPLOYMENT.md 검토
   - TROUBLESHOOTING.md 확인

3. **최종 테스트**
   - 모든 Phase 검증 스크립트 통과
   - 브라우저 접속 테스트
   - 각 서비스 기능 테스트

---

## 🔧 트러블슈팅

### 문제 1: 전체 설치 중 실패

**해결**:
```bash
# 로그 확인
tail -f /tmp/setup_web_services.log

# 특정 단계만 재실행
./web_services/scripts/install_dependencies.sh
python3 web_services/scripts/generate_env_files.py development
```

### 문제 2: Nginx 설정 후 502 Bad Gateway

**해결**:
```bash
# 백엔드 서비스 확인
./web_services/scripts/health_check.sh

# 서비스 재시작
./stop_complete.sh
./start_complete.sh

# Nginx 로그 확인
sudo tail -f /var/log/nginx/error.log
```

### 문제 3: SSL 인증서 오류

**해결**:
```bash
# 인증서 재생성
sudo ./web_services/scripts/generate_self_signed_cert.sh hpc.example.com

# Nginx 재시작
sudo systemctl restart nginx
```

---

## 📈 진행 상황 체크

### Phase 5 완료 기준

- [x] Phase 0~4 모두 완료
- [ ] 개발 환경 통합 테스트 통과
- [ ] 프로덕션 환경 시뮬레이션 통과
- [ ] 새 서버 배포 테스트 통과 (15분 이내)
- [ ] README.md 작성
- [ ] DEPLOYMENT.md 작성
- [ ] OPERATIONS.md 작성
- [ ] TROUBLESHOOTING.md 작성
- [ ] `verify_phase5.sh` 통과

### 완료 후

```bash
# Phase 5 완료 확인
./verify_phase5.sh

# 성공 시 출력 예상:
# ✅✅✅ Phase 5 완료!
# ✅✅✅ 전체 프로젝트 완료!
#
# 🎉 축하합니다! HPC 웹 서비스 자동화 구축 완료!
```

---

## 🎓 전체 프로젝트 요약

### 달성한 목표

1. **✅ ONE-COMMAND 배포**
   ```bash
   ./web_services/scripts/setup_web_services.sh development
   ```

2. **✅ 환경 자동 전환**
   ```bash
   ./web_services/scripts/reconfigure_web_services.sh production
   ```

3. **✅ 최소 코드 수정**
   - 5개 파일만 수정 (2 Python, 3 TypeScript)
   - Slurm 설정 완전 분리

4. **✅ Nginx Reverse Proxy**
   - 자동 설정 생성
   - SSL 지원
   - WebSocket 지원

5. **✅ 롤백 기능**
   ```bash
   ./web_services/scripts/rollback.sh --latest
   ```

### 생성된 파일 통계

```
총 파일 수: 40+ 개

Phase 0: 4개
  - 가이드, 스크립트, 검증

Phase 1: 12개
  - 설정 파일, 템플릿 8개, 문서

Phase 2: 7개
  - 스크립트 1개, 수정된 코드 5개, .env 8개 (자동생성)

Phase 3: 7개
  - 자동화 스크립트 6개, 검증

Phase 4: 5개
  - Nginx 템플릿, 스크립트 4개

Phase 5: 5개
  - 최종 문서 4개, 검증
```

### 배포 시간 비교

| 작업 | 수동 (Before) | 자동 (After) |
|------|--------------|-------------|
| 새 서버 설치 | 2-3시간 | **10-15분** |
| 환경 전환 | 30-60분 | **1-2분** |
| 설정 변경 | 15-30분 | **10초** |
| 롤백 | 10-20분 | **10초** |

---

## 🚀 프로덕션 배포 가이드

### 실제 프로덕션 배포 절차

```bash
# 1. 서버 준비
# - Ubuntu 20.04/22.04
# - 도메인 설정 (DNS A 레코드)
# - 방화벽 설정

# 2. 레포지토리 클론
git clone <repository_url>
cd KooSlurmInstallAutomationRefactory

# 3. web_services_config.yaml 수정
nano web_services_config.yaml
# domain: "실제도메인.com" 으로 변경

# 4. Let's Encrypt 인증서 발급
./web_services/scripts/setup_letsencrypt.sh 실제도메인.com admin@실제도메인.com

# 5. 환경 변수에 JWT 시크릿 설정
export JWT_SECRET_KEY=$(openssl rand -base64 32)
export REDIS_PASSWORD=$(openssl rand -base64 16)
export SAML_IDP_METADATA_URL="https://실제IdP.com/metadata"

# 6. 전체 설치
./web_services/scripts/setup_web_services.sh production

# 7. Nginx 설정
./web_services/scripts/setup_nginx.sh production

# 8. 방화벽 설정
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable

# 9. 서비스 시작
./start_complete.sh

# 10. 헬스 체크
./web_services/scripts/health_check.sh

# 11. 브라우저 접속
# https://실제도메인.com/
```

---

## 💬 지원 및 문의

### 문제 발생 시

1. **검증 스크립트 실행**
   ```bash
   ./verify_phase5.sh
   ```

2. **로그 확인**
   ```bash
   tail -f /var/log/hpc_web_services/*.log
   sudo tail -f /var/log/nginx/error.log
   ```

3. **헬스 체크**
   ```bash
   ./web_services/scripts/health_check.sh
   ```

4. **문서 참조**
   - TROUBLESHOOTING.md
   - 각 Phase 가이드
   - OPERATIONS.md

---

## 🎉 완료!

**예상 총 소요 시간 (전체 Phase)**:
- Phase 0: 2시간
- Phase 1: 3-4시간
- Phase 2: 2-3시간
- Phase 3: 4-5시간
- Phase 4: 3-4시간
- Phase 5: 3-4시간

**총: 17-22시간** (약 3-4일)

하지만 한 번 구축하면:
- **새 서버 배포: 10-15분**
- **환경 전환: 1-2분**
- **설정 변경: 10초**

**투자 대비 효율: 90% 이상 시간 절감!**

---

**난이도: 고급 (전체 시스템 통합 및 테스트)**
**완료 시 달성: 완전 자동화된 HPC 웹 서비스 배포 시스템**
