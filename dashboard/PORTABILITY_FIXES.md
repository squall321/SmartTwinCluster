# Dashboard Portability Fixes

## 개요

대시보드 시스템을 다른 서버에 배포할 때 발생하는 문제들을 해결하기 위한 수정 사항입니다.
모든 설정이 `my_multihead_cluster.yaml` 파일에서 자동으로 생성되도록 개선했습니다.

## 해결한 문제들

### 1. ERR_TUNNEL_CONNECTION_FAILED
**문제**: Frontend가 하드코딩된 IP 주소로 API 요청
**원인**: `.env` 파일에 개발 서버의 IP 주소가 하드코딩됨
**해결**:
- `phase5_web.sh`가 YAML에서 `public_url`을 읽어서 `.env` 파일 자동 생성
- 프로토콜도 `sso.enabled` 설정에 따라 자동 선택 (http/https, ws/wss)

### 2. 포트 번호 vs 프록시 경로
**문제**: Frontend가 직접 포트 번호로 접근 (예: `http://IP:5010`)
**원인**: 포트 기반 URL 사용
**해결**:
- 모든 Frontend를 Nginx 프록시 경로 사용으로 변경
- `VITE_API_URL=http://IP/api` (NOT `:5010`)
- `VITE_WS_URL=ws://IP/ws` (NOT `:5011`)
- `VITE_AUTH_URL=http://IP/auth` (NOT `:4430`)

### 3. SSO 설정에 따른 HTTP/HTTPS 자동 전환
**문제**: 개발 환경(HTTP)과 운영 환경(HTTPS) 설정이 달라야 함
**원인**: 프로토콜이 하드코딩됨
**해결**:
- `sso.enabled: false` → HTTP only, `hpc-portal.conf` 사용
- `sso.enabled: true` → HTTPS 강제, `auth-portal.conf` 사용
- Frontend .env 파일 생성 시 프로토콜 자동 선택

### 4. Nginx 설정 파일 오류 (location directive)
**문제**: `"location" directive is not allowed here` 에러
**원인**: `apply_post_setup_fixes.sh`가 VNC proxy location을 server 블록 밖에 추가
**해결**:
- `cat >>` 방식을 `sed -i` 방식으로 변경하여 server 블록 안에 삽입
- `hpc-portal.conf` 템플릿에 VNC proxy 설정 미리 포함

### 5. CORS 설정 하드코딩
**문제**: CAE backend의 CORS 설정에 하드코딩된 IP
**원인**: `config.py`가 고정된 값 사용
**해결**:
- `config.py`가 YAML에서 `public_url`과 `sso.enabled` 읽도록 수정
- CORS origins 동적 생성

### 6. 테스트 스크립트 하드코딩
**문제**: `test_startup.sh`가 하드코딩된 IP로 테스트
**원인**: 스크립트에 고정된 URL
**해결**:
- YAML에서 `public_url`과 프로토콜 읽어서 테스트

## 수정된 파일 목록

### 1. `/cluster/setup/phase5_web.sh`
```bash
# SSO 설정 로드
SSO_ENABLED=$(python3 -c "import yaml; ...")

# 프로토콜 선택
PROTOCOL="http"
WS_PROTOCOL="ws"
if [[ "$SSO_ENABLED" == "true" ]]; then
    PROTOCOL="https"
    WS_PROTOCOL="wss"
fi

# Frontend .env 생성 (프록시 경로 사용)
VITE_API_URL=${PROTOCOL}://${PUBLIC_URL}/api
VITE_WS_URL=${WS_PROTOCOL}://${PUBLIC_URL}/ws
VITE_AUTH_URL=${PROTOCOL}://${PUBLIC_URL}/auth

# Nginx 설정 파일 선택
if [[ "$SSO_ENABLED" == "false" ]]; then
    nginx_conf="/etc/nginx/conf.d/hpc-portal.conf"
else
    nginx_conf="/etc/nginx/conf.d/auth-portal.conf"
fi
```

### 2. `/cluster/setup/apply_post_setup_fixes.sh`
```bash
# SSO 설정에 따라 nginx 설정 파일 선택
if [[ "$SSO_ENABLED" == "false" ]]; then
    NGINX_CONF="/etc/nginx/conf.d/hpc-portal.conf"
else
    NGINX_CONF="/etc/nginx/conf.d/auth-portal.conf"
fi

# VNC proxy location 삽입 (server 블록 안에)
local last_brace_line=$(grep -n "^}" "$NGINX_CONF" | tail -1 | cut -d: -f1)
sudo sed -i "${last_brace_line}i\..." "$NGINX_CONF"
```

### 3. `/dashboard/nginx/hpc-portal.conf`
- VNC proxy location 블록 추가 (템플릿에 미리 포함)
- SocketIO location 이미 포함되어 있음

### 4. `/dashboard/kooCAEWebServer_5000/config.py`
```python
def _load_public_url():
    yaml_path = Path(BASE_DIR).parent.parent / 'my_multihead_cluster.yaml'
    config = yaml.safe_load(yaml_path.read_text())
    public_url = config.get('web', {}).get('public_url', 'localhost')
    sso_enabled = config.get('sso', {}).get('enabled', True)
    protocol = 'https' if sso_enabled else 'http'
    return public_url, protocol

PUBLIC_URL, PROTOCOL = _load_public_url()

class Config:
    CORS_ORIGINS = [
        f"{PROTOCOL}://{PUBLIC_URL}",
        f"{PROTOCOL}://{PUBLIC_URL}:5173",
        f"{PROTOCOL}://{PUBLIC_URL}:5174"
    ]
```

### 5. `/dashboard/test_startup.sh`
```bash
# YAML에서 설정 로드
PUBLIC_URL=$(python3 -c "import yaml; ...")
SSO_ENABLED=$(python3 -c "import yaml; ...")
PROTOCOL=$([[ "$SSO_ENABLED" == "true" ]] && echo "https" || echo "http")

# 동적 URL로 테스트
curl -I ${PROTOCOL}://${PUBLIC_URL}/
```

### 6. `/dashboard/check_http_setup.sh` (신규)
- SSO 비활성화 환경에서 HTTP 설정 점검
- Frontend .env 파일 검증
- Nginx 설정 검증
- HTTPS 리다이렉트 검사

## 배포 프로세스

### 새 서버에 배포하기

1. **YAML 설정 업데이트:**
   ```bash
   vi my_multihead_cluster.yaml
   ```
   ```yaml
   web:
     public_url: "새서버IP"  # 예: 10.198.112.201

   sso:
     enabled: false  # 개발/테스트는 false, 운영은 true
   ```

2. **Phase 5 실행:**
   ```bash
   sudo ./cluster/setup/phase5_web.sh --config my_multihead_cluster.yaml
   ```

3. **검증:**
   ```bash
   # HTTP 설정 점검 (SSO disabled인 경우)
   ./dashboard/check_http_setup.sh

   # 또는 수동 테스트
   curl http://새서버IP/
   curl http://새서버IP/dashboard/
   ```

### 자동으로 처리되는 것들

✅ Frontend .env 파일 생성 (public_url, protocol)
✅ Nginx 설정 파일 선택 및 생성
✅ Frontend 빌드 및 배포
✅ 서비스 시작
✅ 백업 파일 생성

### 수동으로 확인해야 할 것들

⚠️ 방화벽 설정 (포트 80 또는 443 열기)
⚠️ 서비스 상태 확인
⚠️ 브라우저 캐시 삭제

## 검증 체크리스트

```bash
# 1. YAML 설정 확인
grep "public_url:" my_multihead_cluster.yaml
grep "enabled:" my_multihead_cluster.yaml | grep -A1 "^sso:"

# 2. Frontend .env 파일 확인
cat dashboard/frontend_3010/.env
# → VITE_API_URL이 /api 경로를 사용하는지 확인 (NOT :5010)

# 3. Nginx 설정 확인
sudo nginx -t
grep "server_name" /etc/nginx/conf.d/hpc-portal.conf

# 4. 서비스 상태 확인
systemctl status nginx dashboard_backend auth_backend

# 5. 포트 리스닝 확인
netstat -tln | grep -E ':80|:4430|:5010'

# 6. 접속 테스트
curl http://PUBLIC_URL/
curl http://PUBLIC_URL/dashboard/
```

## 주요 개선 사항 요약

1. **완전한 YAML 기반 설정**: 단일 설정 파일로 모든 환경 관리
2. **SSO 기반 자동 전환**: HTTP/HTTPS 자동 선택
3. **프록시 경로 사용**: 포트 번호 노출 제거
4. **Nginx 설정 자동화**: 템플릿 기반 생성, 수동 수정 불필요
5. **검증 도구 제공**: 배포 후 자동 점검 스크립트

## 이전 vs 개선 후

| 항목 | 이전 | 개선 후 |
|------|------|---------|
| IP 설정 | 하드코딩 | YAML에서 자동 로드 |
| Frontend URL | 포트 번호 사용 | Nginx 프록시 경로 |
| 프로토콜 | 고정 | SSO 설정에 따라 자동 |
| Nginx 설정 | 수동 수정 필요 | 템플릿 자동 생성 |
| 배포 절차 | 여러 파일 수정 | YAML 하나만 수정 |
| 검증 | 수동 테스트 | 자동 점검 스크립트 |

## 문제 발생 시

1. **ERR_CONNECTION_REFUSED**: 방화벽 확인 또는 nginx 상태 확인
2. **location directive error**: phase5_web.sh 재실행 (기존 config 자동 백업됨)
3. **CORS error**: CAE backend 재시작으로 새 YAML 설정 로드
4. **404 on /api**: Frontend 재빌드 필요 (.env 변경 후)

더 자세한 내용은 [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) 참조.
