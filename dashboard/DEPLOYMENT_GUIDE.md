# Dashboard Deployment Guide

## 개요

대시보드 시스템은 `my_multihead_cluster.yaml`을 참조하여 모든 설정 파일을 자동 생성합니다.
이를 통해 다른 서버에 쉽게 배포할 수 있으며, IP 주소나 경로 하드코딩 문제를 방지합니다.

## 작동 방식

### 1. 설정 파일 생성

`cluster/setup/phase5_web.sh` 스크립트가 실행될 때 다음 파일들이 자동으로 생성됩니다:

#### Frontend .env 파일
- `dashboard/frontend_3010/.env` - 메인 대시보드
- `dashboard/auth_portal_4431/.env` - 인증 포털
- `dashboard/vnc_service_8002/.env` - VNC 서비스
- `dashboard/kooCAEWeb_5173/.env` - CAE 웹

모든 `.env` 파일은 `my_multihead_cluster.yaml`의 `web.public_url` 값을 사용합니다.

#### Nginx 설정
- `/etc/nginx/conf.d/hpc-portal.conf`

Nginx 설정도 `public_url`과 프로젝트 경로를 자동으로 참조합니다.

### 2. YAML 설정 위치

`my_multihead_cluster.yaml` 파일의 관련 설정:

```yaml
web:
  # 외부 접속 주소 (브라우저에서 접속할 주소)
  # - 공인 IP 또는 도메인
  # - 내부 접속만 하려면 VIP 주소 사용: 10.179.100.100
  # - 외부 접속이 필요하면 공인 IP 또는 도메인 입력: 110.15.177.120 또는 cluster.example.com
  public_url: "10.198.112.201"  # 여기를 새 서버 IP로 변경

sso:
  enabled: false  # true = HTTPS 강제 (SSO 사용), false = HTTP only (Mock IdP)
```

**중요**: `sso.enabled` 설정에 따라 자동으로 다음이 변경됩니다:
- **enabled: false** (개발/테스트 환경)
  - HTTP only (포트 80)
  - nginx: `hpc-portal.conf` 사용
  - frontend .env: `http://`, `ws://`
- **enabled: true** (운영 환경)
  - HTTPS 강제 (포트 443)
  - nginx: `auth-portal.conf` 사용 (HTTP→HTTPS 리다이렉트)
  - frontend .env: `https://`, `wss://`

## 새 서버에 배포하기

### 방법 1: 전체 재설정 (권장)

1. **YAML 설정 업데이트**
   ```bash
   vi my_multihead_cluster.yaml
   ```
   `web.public_url`을 새 서버의 IP 주소로 변경

2. **Phase 5 (웹 서비스) 재실행**
   ```bash
   sudo ./cluster/setup/phase5_web.sh --config my_multihead_cluster.yaml
   ```

   이 스크립트는 다음을 자동으로 수행합니다:
   - YAML에서 public_url 읽기
   - 모든 frontend .env 파일 생성 (기존 파일 백업)
   - Frontend 빌드
   - Nginx 설정 생성 (public_url 및 프로젝트 경로 자동 적용)
   - 서비스 재시작

### 방법 2: 수동 설정 업데이트 (빠른 방법)

이미 설치된 시스템의 IP만 변경하는 경우:

1. **YAML 설정 업데이트**
   ```bash
   vi my_multihead_cluster.yaml
   # web.public_url을 새 IP로 변경
   ```

2. **설정 파일 재생성**
   ```bash
   # Frontend .env 파일 재생성
   python3 <<EOF
   import yaml
   from pathlib import Path
   from datetime import datetime

   # Load YAML
   yaml_file = Path('my_multihead_cluster.yaml')
   config = yaml.safe_load(yaml_file.read_text())
   public_url = config.get('web', {}).get('public_url', '127.0.0.1')

   # Generate frontend .env files
   dashboard_dir = Path('dashboard')
   timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')

   envs = {
       'frontend_3010/.env': f"""# Dashboard Frontend Environment
# Generated from my_multihead_cluster.yaml on {timestamp}
VITE_API_URL=http://{public_url}:5010
VITE_WS_URL=ws://{public_url}:5011/ws
VITE_AUTH_URL=http://{public_url}:4430
VITE_ENVIRONMENT=production
""",
       'auth_portal_4431/.env': f"""# Auth Portal Frontend Environment
# Generated from my_multihead_cluster.yaml on {timestamp}
VITE_AUTH_URL=http://{public_url}:4430
VITE_API_URL=http://{public_url}:5010
""",
       'vnc_service_8002/.env': f"""# VNC Service Frontend Environment
# Generated from my_multihead_cluster.yaml on {timestamp}
VITE_API_URL=http://{public_url}:5010
VITE_AUTH_URL=http://{public_url}:4430
""",
       'kooCAEWeb_5173/.env': f"""# CAE Web Frontend Environment
# Generated from my_multihead_cluster.yaml on {timestamp}
VITE_API_URL=http://{public_url}:5000
VITE_AUTH_URL=http://{public_url}:4430
""",
   }

   for env_file, content in envs.items():
       env_path = dashboard_dir / env_file
       if env_path.parent.exists():
           env_path.write_text(content)
           print(f"✓ Generated {env_file}")

   print(f"\n✓ All .env files updated with PUBLIC_URL={public_url}")
   EOF
   ```

3. **Frontend 재빌드**
   ```bash
   ./build_all_frontends.sh
   ```

4. **Nginx 설정 업데이트**
   ```bash
   # YAML에서 public_url과 프로젝트 경로 가져오기
   PUBLIC_URL=$(python3 -c "import yaml; print(yaml.safe_load(open('my_multihead_cluster.yaml')).get('web', {}).get('public_url', '127.0.0.1'))")
   PROJECT_ROOT=$(pwd)

   # hpc-portal.conf 업데이트
   sudo sed -i.backup_$(date +%Y%m%d_%H%M%S) \
       -e "s|server_name [0-9.]\+ localhost|server_name $PUBLIC_URL localhost|g" \
       -e "s|alias /home/[^/]\+/claude/KooSlurmInstallAutomationRefactory/|alias $PROJECT_ROOT/|g" \
       /etc/nginx/conf.d/hpc-portal.conf

   echo "✓ Nginx config updated with PUBLIC_URL=$PUBLIC_URL"
   ```

5. **Nginx 재시작**
   ```bash
   sudo nginx -t && sudo systemctl reload nginx
   ```

## 생성되는 파일 목록

### Frontend .env 파일
```
dashboard/frontend_3010/.env
dashboard/auth_portal_4431/.env
dashboard/vnc_service_8002/.env
dashboard/kooCAEWeb_5173/.env
```

### Nginx 설정
```
/etc/nginx/conf.d/hpc-portal.conf
```

### 빌드 결과물
```
/var/www/html/dashboard/       # frontend_3010 빌드
/var/www/html/auth_portal/     # auth_portal_4431 빌드
/var/www/html/vnc/             # vnc_service_8002 빌드
/var/www/html/cae/             # kooCAEWeb_5173 빌드
/var/www/html/app/             # app_5174 빌드
```

## 백업 정책

- 기존 `.env` 파일은 `.env.backup_YYYYMMDD_HHMMSS` 형식으로 백업됩니다
- Nginx 설정 파일도 동일하게 백업됩니다
- 빌드 결과물은 덮어쓰기됩니다 (백업 안 함)

## 문제 해결

### ERR_TUNNEL_CONNECTION_FAILED 에러

이 에러는 frontend가 잘못된 IP 주소로 API 요청을 시도할 때 발생합니다.

**해결 방법:**

1. `my_multihead_cluster.yaml`의 `web.public_url`이 올바른지 확인
2. Frontend .env 파일이 올바른 URL을 가지고 있는지 확인:
   ```bash
   cat dashboard/frontend_3010/.env
   # VITE_API_URL이 nginx 프록시 경로를 사용하는지 확인: http://IP/api (NOT http://IP:5010)
   ```
3. Frontend를 재빌드했는지 확인 (`.env` 변경 후 반드시 재빌드 필요)
4. 브라우저 캐시 삭제

### ERR_CONNECTION_REFUSED 에러

브라우저에서 접속 시 연결이 거부되는 경우:

**점검 방법:**

1. **서버에서 로컬 접속 테스트:**
   ```bash
   curl http://localhost/
   ```
   - 성공하면 nginx는 정상이고 방화벽 문제
   - 실패하면 nginx 설정 또는 서비스 문제

2. **서비스 상태 확인:**
   ```bash
   systemctl status nginx
   systemctl status dashboard_backend
   systemctl status auth_backend
   ```

3. **포트 리스닝 확인:**
   ```bash
   netstat -tln | grep -E ':80|:4430|:5010'
   ```

4. **방화벽 설정:**
   ```bash
   # Ubuntu/Debian
   sudo ufw status
   sudo ufw allow 80/tcp

   # CentOS/RHEL
   sudo firewall-cmd --list-all
   sudo firewall-cmd --permanent --add-port=80/tcp
   sudo firewall-cmd --reload
   ```

### Nginx 설정 오류

```bash
# Nginx 설정 테스트
sudo nginx -t

# 설정 파일 확인
sudo cat /etc/nginx/conf.d/hpc-portal.conf | grep server_name
sudo cat /etc/nginx/conf.d/hpc-portal.conf | grep alias

# location 블록 구조 확인 (closing brace가 제대로 있는지)
grep -n "^}" /etc/nginx/conf.d/hpc-portal.conf
```

**흔한 에러:**

1. **"location" directive is not allowed here**
   - 원인: location 블록이 server 블록 밖에 있음
   - 해결: 템플릿이 완전한지 확인, post-setup 스크립트가 올바르게 삽입하는지 확인

2. **Duplicate location blocks**
   - 원인: 같은 location이 여러 번 정의됨
   - 해결: phase5_web.sh 재실행 전 기존 config 삭제

## 주의사항

1. **Frontend는 빌드 타임에 환경 변수를 포함합니다**
   - `.env` 파일 변경 후 반드시 `npm run build` 필요
   - Runtime에는 변경할 수 없음

2. **Backend는 런타임에 환경 변수를 읽습니다**
   - `.env` 파일 변경 후 서비스 재시작만 필요

3. **Nginx는 절대 경로를 사용합니다**
   - 프로젝트 경로가 변경되면 nginx 설정도 업데이트 필요

## 자동화된 배포 프로세스

Phase 5 스크립트는 다음 순서로 실행됩니다:

1. **load_config()** - YAML에서 설정 읽기
   - `PUBLIC_URL` 변수 설정
   - 비밀번호, DB 설정 등 로드

2. **create_web_user()** - 웹 서비스 사용자 생성

3. **create_directories()** - 디렉토리 구조 생성

4. **deploy_web_services()**
   - **generate_frontend_env_files()** ⭐ Frontend .env 생성
   - setup_auth_portal_groups()
   - setup_saml_idp_users()
   - setup_redis_session_management()
   - setup_jwt_authentication()

5. **build_all_frontends()** - Frontend 빌드

6. **configure_nginx()** ⭐ Nginx 설정 생성

7. **start_services()** - 서비스 시작

이 과정을 통해 모든 하드코딩이 제거되고, YAML 파일 하나로 전체 시스템을 관리할 수 있습니다.
