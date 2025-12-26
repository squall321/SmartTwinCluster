# 오프라인 서버 "Access Denied" 디버깅 체크리스트

## 1. SSO 설정 파일 확인

### 확인 명령어:
```bash
# 설치된 위치에서 실행
cd /path/to/installed/cluster

# my_multihead_cluster.yaml 파일 존재 확인
ls -la my_multihead_cluster.yaml

# SSO 설정 확인
cat my_multihead_cluster.yaml | grep -A 3 "^sso:"
```

### 기대 결과:
```yaml
sso:
  enabled: false    # ← 이것이 false여야 함!
```

---

## 2. Backend 서비스 SSO 설정 로드 확인

### 확인 명령어:
```bash
# Backend 로그 확인
journalctl -u backend_5010 -n 100 --no-pager

# 또는 직접 로그 파일 확인
tail -f /var/log/backend_5010.log
```

### 기대 결과:
```
[INFO] SSO_ENABLED: False
```

---

## 3. API 엔드포인트로 직접 확인

### 확인 명령어:
```bash
# SSO 설정 조회
curl http://localhost:5010/api/auth/config

# 기대 결과:
# {
#   "sso_enabled": false,
#   "jwt_required": false,
#   "timestamp": "2025-12-26T..."
# }
```

---

## 4. 가능한 문제 원인과 해결책

### 원인 1: my_multihead_cluster.yaml 파일이 없음
**해결책:**
```bash
# 파일 복사
cp my_multihead_cluster.yaml /path/to/installed/cluster/

# 또는 새로 생성
cat > my_multihead_cluster.yaml << 'EOF'
sso:
  enabled: false
  type: saml
EOF
```

---

### 원인 2: YAML 파일 경로가 잘못됨
**해결책:** 환경변수로 경로 지정

dashboard/backend_5010/middleware/jwt_middleware.py 수정:
```python
# 환경변수로 YAML 경로 지정 가능하도록 개선
YAML_CONFIG_PATH = os.getenv('CLUSTER_CONFIG_PATH',
    str(Path(__file__).parent.parent.parent.parent / 'my_multihead_cluster.yaml'))

def _load_sso_config():
    try:
        yaml_path = Path(YAML_CONFIG_PATH)
        if yaml_path.exists():
            with open(yaml_path) as f:
                config = yaml.safe_load(f)
                return config.get('sso', {}).get('enabled', True)
    except Exception as e:
        print(f"[WARNING] Failed to load SSO config from {YAML_CONFIG_PATH}: {e}")
    return True
```

그리고 systemd 서비스 파일에 환경변수 추가:
```ini
[Service]
Environment="CLUSTER_CONFIG_PATH=/opt/cluster/my_multihead_cluster.yaml"
```

---

### 원인 3: PyYAML이 설치되지 않음
**해결책:**
```bash
# PyYAML 설치 확인
dashboard/backend_5010/venv/bin/pip list | grep -i yaml

# 없으면 설치
dashboard/backend_5010/venv/bin/pip install PyYAML
```

---

### 원인 4: 서비스 재시작 안함
**해결책:**
```bash
# Backend 서비스 재시작 (코드 변경사항 적용)
sudo systemctl restart backend_5010

# 상태 확인
sudo systemctl status backend_5010
```

---

### 원인 5: Frontend가 SSO 설정을 못 가져옴
**확인:**
브라우저 콘솔(F12)에서:
```javascript
// 예상되는 로그:
[Auth] SSO config loaded: {sso_enabled: false, jwt_required: false}
[Auth] SSO disabled - granting full admin permissions

// 만약 이 로그가 없으면 Frontend에서 backend API 연결 실패
```

**해결책:**
```bash
# Backend API 연결 확인
curl http://localhost:5010/api/health

# Frontend 재시작
cd dashboard/frontend_3010
npm run build
# 또는 개발 모드
npm run dev
```

---

## 5. 네트워크/방화벽 문제

### 확인 명령어:
```bash
# 포트 열림 확인
sudo netstat -tlnp | grep -E "3010|4431|5010"

# 방화벽 설정 확인
sudo ufw status
sudo firewall-cmd --list-all
```

### 해결책:
```bash
# 필요한 포트 열기
sudo ufw allow 3010/tcp
sudo ufw allow 5010/tcp

# 또는
sudo firewall-cmd --add-port=3010/tcp --permanent
sudo firewall-cmd --add-port=5010/tcp --permanent
sudo firewall-cmd --reload
```

---

## 6. 빠른 임시 해결책: 환경변수로 SSO 강제 비활성화

만약 YAML 파일 문제가 계속되면, 환경변수로 우회:

### jwt_middleware.py 수정:
```python
# 최우선: 환경변수
SSO_ENABLED = os.getenv('SSO_ENABLED', '').lower() != 'false'

# 환경변수가 없으면 YAML 로드
if 'SSO_ENABLED' not in os.environ:
    SSO_ENABLED = _load_sso_config()
```

### systemd 서비스 파일에 추가:
```ini
[Service]
Environment="SSO_ENABLED=false"
```

---

## 디버깅 스크립트

아래 스크립트를 오프라인 서버에서 실행하세요:

```bash
#!/bin/bash
echo "=== SSO Configuration Debug ==="

echo ""
echo "1. YAML 파일 확인:"
if [ -f "my_multihead_cluster.yaml" ]; then
    echo "✓ my_multihead_cluster.yaml 존재"
    cat my_multihead_cluster.yaml | grep -A 3 "^sso:"
else
    echo "✗ my_multihead_cluster.yaml 없음!"
fi

echo ""
echo "2. Backend API 응답:"
curl -s http://localhost:5010/api/auth/config | jq .

echo ""
echo "3. Backend 서비스 상태:"
systemctl status backend_5010 | grep Active

echo ""
echo "4. Backend 프로세스 확인:"
ps aux | grep backend_5010 | grep -v grep

echo ""
echo "5. 포트 확인:"
netstat -tlnp 2>/dev/null | grep -E "3010|5010"

echo ""
echo "=== Debug Complete ==="
```

---

## 체크리스트

오프라인 서버에서 다음을 확인하세요:

- [ ] my_multihead_cluster.yaml 파일 존재 확인
- [ ] sso.enabled: false 설정 확인
- [ ] Backend 서비스 실행 중
- [ ] curl http://localhost:5010/api/auth/config 응답 확인
- [ ] Frontend 실행 중 (포트 3010)
- [ ] 브라우저 콘솔에서 SSO 로그 확인
- [ ] PyYAML 패키지 설치 확인

---

## 최종 해결책 (가장 확실한 방법)

환경변수 방식으로 변경하여 YAML 파일 의존성 제거:

1. **Backend 서비스 설정에 환경변수 추가**
2. **코드 수정하여 환경변수 우선 확인**
3. **서비스 재시작**

이렇게 하면 오프라인 환경에서도 안정적으로 작동합니다.
