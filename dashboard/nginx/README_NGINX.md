# Nginx 성능 최적화 설정 가이드

## 파일 구조

```
nginx/
├── http_block_performance.conf      # HTTP 블록 설정
├── server_block_performance.conf    # Server 블록 설정
└── README_NGINX.md                  # 이 파일
```

---

## 적용 방법

### Option 1: 새 파일로 추가 (권장)

#### 1. HTTP 블록 설정 적용

```bash
# 파일 복사
sudo cp nginx/http_block_performance.conf /etc/nginx/conf.d/00-performance-http.conf

# 문법 검사
sudo nginx -t

# 적용
sudo systemctl reload nginx
```

#### 2. Server 블록 설정 적용

**방법 A: 기존 server 블록에 include**

`/etc/nginx/conf.d/auth-portal.conf` 편집:

```nginx
server {
    listen 80;
    server_name _;

    # 성능 최적화 설정 포함
    include /etc/nginx/performance/server_block_performance.conf;

    # ... 기존 설정 ...
}
```

**방법 B: 직접 복사**

```bash
sudo mkdir -p /etc/nginx/performance
sudo cp nginx/server_block_performance.conf /etc/nginx/performance/

# auth-portal.conf에 include 추가
sudo nano /etc/nginx/conf.d/auth-portal.conf
```

---

### Option 2: 기존 파일 수정

기존 `nginx.conf` 또는 `auth-portal.conf`를 직접 편집하여 설정 추가

```bash
sudo nano /etc/nginx/nginx.conf
```

**HTTP 블록에 추가**:
- Gzip 설정
- Open file cache
- Proxy buffering
- Upstream 정의

**Server 블록에 추가**:
- 정적 파일 캐싱
- 보안 헤더
- Rate limiting (선택적)

---

## 캐시 디렉토리 생성

```bash
sudo mkdir -p /var/cache/nginx/api
sudo chown www-data:www-data /var/cache/nginx/api
```

---

## 설정 확인

### 1. 문법 검사

```bash
sudo nginx -t
```

**예상 출력**:
```
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

### 2. Nginx 재시작

```bash
sudo systemctl reload nginx
# 또는
sudo systemctl restart nginx
```

### 3. 상태 확인

```bash
sudo systemctl status nginx
```

---

## 기능 검증

### 1. Gzip 압축 확인

```bash
curl -I -H "Accept-Encoding: gzip" http://localhost/dashboard/assets/index.js
```

**확인 항목**:
```
Content-Encoding: gzip
```

### 2. 캐시 헤더 확인

```bash
curl -I http://localhost/dashboard/assets/index.js
```

**확인 항목**:
```
Cache-Control: public, immutable
Expires: <1년 후 날짜>
```

### 3. HTML 캐싱 비활성화 확인

```bash
curl -I http://localhost/dashboard/index.html
```

**확인 항목**:
```
Cache-Control: no-cache, no-store, must-revalidate
Pragma: no-cache
```

### 4. API 캐시 확인 (설정했다면)

```bash
# 첫 요청
curl -I http://localhost/api/nodes
# X-Cache-Status: MISS

# 두 번째 요청 (5초 이내)
curl -I http://localhost/api/nodes
# X-Cache-Status: HIT
```

---

## 성능 측정

### Before/After 비교

```bash
# 정적 파일 로딩 시간 (Chrome DevTools Network 탭)
# Before: 200-500ms
# After: 10-50ms (캐시 히트 시 < 10ms)

# Gzip 압축률
# Before: 1.2MB (압축 안 됨)
# After: 300KB (75% 감소)
```

### Apache Bench 테스트

```bash
# 정적 파일
ab -n 1000 -c 10 http://localhost/dashboard/assets/index.js

# API (캐시 없음)
ab -n 100 -c 5 http://localhost/api/nodes
```

---

## 문제 해결

### 1. Nginx 시작 실패

**증상**: `nginx -t` 실패

**해결**:
- 설정 파일 경로 확인
- upstream 이름 중복 확인
- 캐시 디렉토리 권한 확인

```bash
# upstream 중복 확인
sudo nginx -T | grep "upstream"

# 캐시 디렉토리 권한
sudo chown -R www-data:www-data /var/cache/nginx
```

### 2. 캐시가 작동하지 않음

**확인 사항**:
1. 캐시 디렉토리 존재 여부
2. 캐시 디렉토리 권한
3. proxy_cache_path 설정

```bash
ls -la /var/cache/nginx/api/
```

### 3. Rate Limiting 오류 (429 Too Many Requests)

**조정**:
- `limit_req_zone` rate 값 증가
- `burst` 값 증가

```nginx
limit_req_zone $binary_remote_addr zone=api_limit:10m rate=200r/s;  # 100 → 200

location /api/ {
    limit_req zone=api_limit burst=50 nodelay;  # 20 → 50
}
```

---

## 롤백 방법

### 설정 파일 제거

```bash
# HTTP 블록 설정 제거
sudo rm /etc/nginx/conf.d/00-performance-http.conf

# Server 블록 설정 제거
sudo rm /etc/nginx/performance/server_block_performance.conf

# Nginx 재시작
sudo systemctl reload nginx
```

### 백업 복원

```bash
# 백업이 있다면
sudo cp /etc/nginx/nginx.conf.backup /etc/nginx/nginx.conf
sudo systemctl reload nginx
```

---

## 추가 최적화 (선택적)

### HTTP/2 활성화

```nginx
listen 443 ssl http2;
listen [::]:443 ssl http2;
```

**필요 조건**: SSL 인증서

### Brotli 압축 (Gzip보다 효율적)

```bash
# 모듈 설치 (Ubuntu)
sudo apt install nginx-module-brotli

# nginx.conf 최상단에 추가
load_module modules/ngx_http_brotli_filter_module.so;
load_module modules/ngx_http_brotli_static_module.so;

# HTTP 블록에 추가
brotli on;
brotli_comp_level 6;
brotli_types text/plain text/css application/json application/javascript;
```

---

## 모니터링

### Nginx 상태 확인

```bash
# 접속 수, 요청 수 등
sudo nginx -V 2>&1 | grep --with-stub_status

# stub_status 활성화
location /nginx_status {
    stub_status;
    allow 127.0.0.1;
    deny all;
}

# 확인
curl http://localhost/nginx_status
```

### 로그 분석

```bash
# 가장 많이 요청된 URL
awk '{print $7}' /var/log/nginx/access.log | sort | uniq -c | sort -rn | head -10

# 응답 시간 분석
awk '{print $NF}' /var/log/nginx/access.log | grep "rt=" | cut -d'=' -f2 | sort -n
```

---

## 요약

✅ **적용 완료 체크리스트**:
- [ ] HTTP 블록 설정 복사 및 적용
- [ ] Server 블록 설정 복사 및 적용
- [ ] 캐시 디렉토리 생성 및 권한 설정
- [ ] `nginx -t` 문법 검사 통과
- [ ] Nginx reload/restart
- [ ] Gzip 압축 동작 확인
- [ ] 정적 파일 캐시 헤더 확인
- [ ] HTML 캐싱 비활성화 확인
- [ ] 성능 측정 (Before/After)

**예상 성능 향상**:
- 정적 파일 전송 속도: **10배 ↑**
- 네트워크 대역폭: **60-70% ↓**
- 동시 연결 처리: **2-3배 ↑**
