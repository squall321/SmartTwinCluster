# HPC 웹 서비스 배포 가이드

## 📋 목차

- [신규 서버 배포](#신규-서버-배포)
- [환경별 설정](#환경별-설정)
- [SSL 인증서 설정](#ssl-인증서-설정)
- [방화벽 설정](#방화벽-설정)
- [모니터링 설정](#모니터링-설정)
- [백업 및 복구](#백업-및-복구)

---

## 신규 서버 배포

### 사전 요구사항

- **OS**: Ubuntu 20.04/22.04 LTS
- **최소 사양**: CPU 4코어, RAM 8GB, Disk 50GB
- **네트워크**: 공인 IP 또는 도메인 (프로덕션)
- **권한**: sudo 권한 보유

### ONE-COMMAND 배포 (개발 환경)

```bash
# 1. 레포지토리 클론
git clone <repository_url>
cd KooSlurmInstallAutomationRefactory

# 2. Phase 0: 시스템 상태 수집
chmod +x collect_current_state.sh create_directory_structure.sh verify_phase0.sh
./collect_current_state.sh
./create_directory_structure.sh
./verify_phase0.sh

# 3. Phase 1: 설정 파일 확인
chmod +x verify_phase1.sh
./verify_phase1.sh

# 4. Phase 2: 환경 변수 생성
pip3 install pyyaml jinja2
python3 web_services/scripts/generate_env_files.py development
chmod +x verify_phase2.sh
./verify_phase2.sh

# 5. Phase 3: ONE-COMMAND 설치 (핵심!)
./web_services/scripts/setup_web_services.sh development

# 6. Phase 4: Nginx 설정 (선택사항)
./web_services/scripts/setup_nginx.sh development

# 7. 서비스 시작
./start.sh

# 8. 헬스 체크
./web_services/scripts/health_check.sh

# 9. 서비스 중지 (필요시)
./stop.sh
```

**예상 소요 시간**: 10-15분

---

## 환경별 설정

### Development 환경

**특징**:
- HTTP만 사용 (포트 80)
- SSO 비활성화
- 디버그 모드 활성화
- localhost 도메인

**설정**:
```bash
# 개발 환경으로 전환
./web_services/scripts/reconfigure_web_services.sh development

# 확인
cat dashboard/auth_portal_4430/.env | grep -E "FLASK_ENV|SSO_ENABLED"
# 예상:
# FLASK_ENV=development
# SSO_ENABLED=false
```

### Production 환경

**특징**:
- HTTPS 사용 (포트 443)
- SSO 활성화
- 프로덕션 모드
- 실제 도메인

**설정 절차**:

#### 1. 도메인 설정
```bash
# web_services_config.yaml 수정
nano web_services_config.yaml
```

```yaml
environments:
  production:
    domain: "your-domain.com"  # 실제 도메인으로 변경
    sso_enabled: true
```

#### 2. SSL 인증서 발급

**옵션 A: Let's Encrypt (권장)**
```bash
./web_services/scripts/setup_letsencrypt.sh your-domain.com admin@your-domain.com

# 테스트용 (staging)
./web_services/scripts/setup_letsencrypt.sh your-domain.com admin@your-domain.com --staging
```

**사전 요구사항**:
- 도메인이 서버 공인 IP로 DNS 설정됨
- 방화벽에서 80, 443 포트 개방
- Nginx 설치됨

**옵션 B: 자체 서명 인증서 (개발/테스트)**
```bash
sudo ./web_services/scripts/generate_self_signed_cert.sh your-domain.com
```

#### 3. 환경 변수 생성
```bash
# JWT 시크릿 키 생성
export JWT_SECRET_KEY=$(openssl rand -base64 32)
export REDIS_PASSWORD=$(openssl rand -base64 16)

# SAML IdP 설정
export SAML_IDP_METADATA_URL="https://your-idp.com/metadata"

# 프로덕션 환경 변수 생성
python3 web_services/scripts/generate_env_files.py production
```

#### 4. Nginx 설정
```bash
./web_services/scripts/setup_nginx.sh production
```

#### 5. 서비스 재시작
```bash
./stop.sh
./start.sh
./web_services/scripts/health_check.sh
```

#### 6. 검증
```bash
# HTTPS 접속 테스트
curl -I https://your-domain.com/

# HTTP→HTTPS 리다이렉트 확인
curl -I http://your-domain.com/
# 예상: 301 Moved Permanently → https://your-domain.com/
```

---

## SSL 인증서 설정

### Let's Encrypt 자동 갱신

Let's Encrypt 인증서는 90일마다 만료되며, Certbot이 자동으로 갱신합니다.

**자동 갱신 확인**:
```bash
sudo systemctl status certbot.timer
```

**수동 갱신 (필요시)**:
```bash
sudo certbot renew
sudo systemctl reload nginx
```

**갱신 테스트**:
```bash
sudo certbot renew --dry-run
```

### 자체 서명 인증서 갱신

```bash
# 기존 인증서 백업 (자동)
sudo ./web_services/scripts/generate_self_signed_cert.sh your-domain.com

# 다른 유효기간 설정
sudo ./web_services/scripts/generate_self_signed_cert.sh your-domain.com --days 730

# Nginx 재시작
sudo systemctl reload nginx
```

---

## 방화벽 설정

### UFW (Ubuntu)

```bash
# UFW 설치 및 활성화
sudo apt install -y ufw

# 기본 정책: incoming 거부, outgoing 허용
sudo ufw default deny incoming
sudo ufw default allow outgoing

# SSH 허용 (필수!)
sudo ufw allow 22/tcp comment 'SSH'

# HTTP/HTTPS 허용
sudo ufw allow 80/tcp comment 'Nginx HTTP'
sudo ufw allow 443/tcp comment 'Nginx HTTPS'

# 방화벽 활성화
sudo ufw enable

# 상태 확인
sudo ufw status verbose
```

### 내부 포트 보호

프로덕션 환경에서는 내부 서비스 포트(4430, 4431, 5000 등)를 외부에서 직접 접근하지 못하도록 차단합니다. Nginx를 통해서만 접근 가능합니다.

```bash
# 내부 포트는 기본적으로 차단됨 (ufw deny incoming)
# 80, 443만 허용했으므로 자동으로 보호됨
```

---

## 모니터링 설정

### Prometheus

**프로덕션 환경에서 Basic Auth 설정**:

```bash
# .htpasswd 파일 생성
sudo apt install -y apache2-utils
sudo htpasswd -c /etc/nginx/.htpasswd admin

# Nginx에서 자동으로 적용됨 (production 설정 사용 시)
```

**접속**:
- 개발: http://localhost:9090
- 프로덕션: https://your-domain.com/prometheus (인증 필요)

### Node Exporter

시스템 메트릭 수집:
- 포트: 9100
- 자동 시작: `start_complete.sh`에 포함

### 로그 모니터링

```bash
# Nginx 로그
sudo tail -f /var/log/nginx/hpc_access.log
sudo tail -f /var/log/nginx/hpc_error.log

# 서비스 로그 (각 서비스별)
tail -f dashboard/auth_portal_4430/logs/app.log
tail -f dashboard/backend_5010/logs/app.log
```

---

## 백업 및 복구

### 설정 백업

**자동 백업**:
```bash
# 환경 전환 시 자동 백업
./web_services/scripts/reconfigure_web_services.sh production
# → backups/20241019_123456/ 생성

# 수동 백업
./web_services/scripts/rollback.sh --create-backup
```

**백업 보관**:
- 위치: `web_services/backups/`
- 최대 5개 자동 유지
- 오래된 백업 자동 삭제

### 롤백

```bash
# 최신 백업으로 롤백
./web_services/scripts/rollback.sh --latest

# 특정 백업으로 롤백
./web_services/scripts/rollback.sh --backup 20241019_123456

# 백업 목록 확인
./web_services/scripts/rollback.sh --list
```

**롤백 소요 시간**: 약 10초

### 전체 시스템 백업

```bash
# tar 백업
tar czf backup_$(date +%Y%m%d_%H%M%S).tar.gz \
  dashboard/ \
  web_services/ \
  *.sh \
  *.yaml \
  *.md \
  --exclude='*.pyc' \
  --exclude='node_modules' \
  --exclude='__pycache__'

# Git 백업 (사용자가 직접 수행)
git add .
git commit -m "Backup: $(date +%Y%m%d_%H%M%S)"
git push
```

---

## 프로덕션 체크리스트

### 배포 전

- [ ] DNS A 레코드 설정 완료
- [ ] 도메인이 서버 IP로 정상 연결
- [ ] SSL 인증서 발급 완료
- [ ] web_services_config.yaml 도메인 설정
- [ ] JWT_SECRET_KEY 생성 및 설정
- [ ] SAML IdP 메타데이터 URL 설정
- [ ] 방화벽 규칙 설정

### 배포 후

- [ ] 헬스 체크 11/11 정상
- [ ] HTTPS 접속 확인
- [ ] HTTP→HTTPS 리다이렉트 동작
- [ ] SSO 로그인 동작
- [ ] 각 서비스 페이지 접근 가능
- [ ] Prometheus 접속 (인증 확인)
- [ ] 로그 정상 기록
- [ ] 백업 시스템 동작 확인

---

## 환경별 비교표

| 항목 | Development | Production |
|------|------------|------------|
| 프로토콜 | HTTP | HTTPS |
| 포트 | 80 | 443 (+ 80 리다이렉트) |
| 도메인 | localhost | 실제 도메인 |
| SSO | 비활성화 | 활성화 |
| 디버그 | ON | OFF |
| SSL 인증서 | 불필요 | 필수 (Let's Encrypt) |
| 방화벽 | 선택사항 | 필수 |
| Prometheus | 공개 | Basic Auth |
| 로그 레벨 | DEBUG | INFO |

---

## 문제 발생 시

1. **배포 실패**
   ```bash
   # 로그 확인
   tail -f /tmp/setup_web_services.log

   # 단계별 재실행
   ./web_services/scripts/install_dependencies.sh
   python3 web_services/scripts/generate_env_files.py development
   ```

2. **HTTPS 접속 불가**
   ```bash
   # SSL 인증서 확인
   sudo openssl x509 -in /etc/ssl/certs/your-domain.crt -text -noout

   # Nginx 설정 검증
   sudo nginx -t

   # Nginx 로그 확인
   sudo tail -f /var/log/nginx/error.log
   ```

3. **서비스 다운**
   ```bash
   # 헬스 체크
   ./web_services/scripts/health_check.sh

   # 서비스 재시작
   ./stop_complete.sh
   ./start_complete.sh
   ```

자세한 문제 해결은 [TROUBLESHOOTING.md](TROUBLESHOOTING.md)를 참조하세요.

---

## 배포 시간 비교

| 작업 | 수동 (Before) | 자동 (After) | 절감률 |
|------|--------------|-------------|--------|
| 새 서버 설치 | 2-3시간 | **10-15분** | 90% |
| 환경 전환 | 30-60분 | **1-2분** | 95% |
| 설정 변경 | 15-30분 | **10초** | 99% |
| 롤백 | 10-20분 | **10초** | 99% |

---

**작성일**: 2025-10-19
**버전**: 1.0
**다음 문서**: [OPERATIONS.md](OPERATIONS.md)
