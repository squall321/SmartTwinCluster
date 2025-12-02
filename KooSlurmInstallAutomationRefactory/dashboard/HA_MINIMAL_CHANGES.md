# 사중화를 위한 최소 수정사항

**결론부터**: 코드 수정은 **거의 없고**, 대부분 **설정 파일만 수정**하면 됩니다.

---

## 🎯 실제로 수정해야 하는 것 (매우 적음)

### **1. Nginx 설정 파일 (1개 파일)**

**파일**: `dashboard/nginx/hpc-portal.conf`

**현재 (127.0.0.1 → 단일 서버)**
```nginx
upstream dashboard_backend {
    server 127.0.0.1:5010;
}

upstream auth_backend {
    server 127.0.0.1:4430;
}

upstream cae_backend {
    server 127.0.0.1:5000;
}

upstream dashboard_websocket {
    server 127.0.0.1:5011;
}
```

**변경 후 (여러 서버 추가)**
```nginx
upstream dashboard_backend {
    server 192.168.100.11:5010;  # App Server 1
    server 192.168.100.12:5010;  # App Server 2
    server 192.168.100.13:5010;  # App Server 3
}

upstream auth_backend {
    server 192.168.100.11:4430;
    server 192.168.100.12:4430;
    server 192.168.100.13:4430;
}

upstream cae_backend {
    server 192.168.100.11:5000;
    server 192.168.100.12:5000;
    server 192.168.100.13:5000;
}

upstream dashboard_websocket {
    server 192.168.100.11:5011;
    server 192.168.100.12:5011;
    server 192.168.100.13:5011;
    hash $remote_addr consistent;  # Sticky session
}
```

**변경 내용**: IP만 바꾸고 서버 줄만 추가! 끝!

---

### **2. Redis 연결 정보 (환경 변수 또는 설정 파일)**

**현재 코드 (예상)**
```python
redis_client = Redis(host='127.0.0.1', port=6379)
```

**변경 방법 1: 환경 변수 사용 (권장)**
```python
# 코드 수정 (1줄)
redis_client = Redis(
    host=os.getenv('REDIS_HOST', '127.0.0.1'),
    port=int(os.getenv('REDIS_PORT', 6379))
)
```

**변경 방법 2: Sentinel 사용 (조금 더 안전)**
```python
# 코드 수정 (3줄)
from redis.sentinel import Sentinel

sentinel = Sentinel([('sentinel1', 26379), ('sentinel2', 26379)])
redis_client = sentinel.master_for('mymaster', socket_timeout=0.1)
```

**영향 받는 파일**:
- `auth_portal_4430/app.py` (Redis 세션)
- 기타 Redis 사용하는 곳 (아마 2-3개 파일)

---

### **3. Database 연결 정보 (환경 변수)**

**현재**
```python
SQLALCHEMY_DATABASE_URI = 'sqlite:///database/dashboard.db'
```

**변경 후**
```python
SQLALCHEMY_DATABASE_URI = os.getenv(
    'DATABASE_URL',
    'mysql+pymysql://user:pass@db-vip:3306/dashboard'
)
```

**영향 받는 파일**:
- `backend_5010/app.py`
- `kooCAEWebServer_5000/app.py`
- 기타 SQLite 사용하는 곳 (아마 3-4개 파일)

---

### **4. Health Check 엔드포인트 추가 (선택 사항)**

각 백엔드에 간단한 엔드포인트 추가:

```python
@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({'status': 'healthy'}), 200
```

**영향 받는 파일**:
- `backend_5010/app.py`
- `auth_portal_4430/app.py`
- `kooCAEWebServer_5000/app.py`
- `websocket_5011/websocket_server.py`

각 파일에 3줄만 추가하면 됨!

---

## 📊 수정 범위 요약

### 코드 수정
```
✏️ Redis 연결 부분: 2-3개 파일, 각 1-3줄
✏️ Database 연결 부분: 3-4개 파일, 각 1-2줄
✏️ Health Check 추가: 4개 파일, 각 3줄

총 합계: 약 10개 파일, 각 1-5줄 정도
```

### 설정 파일 수정
```
📝 Nginx 설정: 1개 파일 (upstream 부분만)
📝 환경 변수 파일: .env 파일 생성 (신규)
```

### 인프라 작업 (코드 수정 아님)
```
🔧 Redis Sentinel 설치 및 설정
🔧 MariaDB Galera 설치 및 설정
🔧 HAProxy/Keepalived 설치 및 설정
🔧 서버 3-4대 준비
```

---

## ✅ 실제 작업 순서 (간단 버전)

### Phase 1: 인프라만 준비 (코드 수정 0)
1. 서버 3-4대 준비
2. Redis Sentinel 3-node 구성
3. MariaDB Galera 3-node 구성
4. 네트워크 설정

### Phase 2: 설정만 변경 (코드 수정 거의 없음)
1. `.env` 파일 만들기
   ```bash
   REDIS_HOST=redis-vip
   DATABASE_URL=mysql+pymysql://...
   ```

2. Nginx upstream에 서버 추가 (1개 파일)

3. 코드에서 환경 변수 읽도록 수정 (10개 파일, 각 1-5줄)

4. Health check 추가 (4개 파일, 각 3줄)

### Phase 3: 배포 및 테스트
1. 각 서버에 같은 코드 배포
2. `.env`만 각 서버별로 다르게 설정
3. Nginx reload
4. 테스트

---

## 🎯 왜 수정이 적은가?

### 1. **이미 좋은 아키텍처**
```
✅ 프론트엔드와 백엔드 분리
✅ Nginx upstream 구조 사용 중
✅ 각 서비스가 독립 프로세스
✅ Stateless 설계
```

### 2. **하드코딩이 많지 않음**
```
✅ 대부분 localhost/127.0.0.1만 사용
   → IP만 바꾸면 됨
✅ 복잡한 서버 간 통신 로직 없음
✅ 파일 시스템 의존도 낮음
```

### 3. **Python/Flask의 유연성**
```
✅ 환경 변수 쉽게 사용 가능
✅ SQLAlchemy → DB 변경 쉬움
✅ Redis 클라이언트 교체 쉬움
```

---

## 🔍 구체적 예시: backend_5010 수정

**변경 전 (가정)**
```python
# app.py (일부)

app = Flask(__name__)
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///database/dashboard.db'

redis_client = Redis(host='127.0.0.1', port=6379)
```

**변경 후 (단 3줄 수정)**
```python
# app.py (일부)

app = Flask(__name__)
app.config['SQLALCHEMY_DATABASE_URI'] = os.getenv(
    'DATABASE_URL',
    'sqlite:///database/dashboard.db'  # 기본값 유지
)

redis_client = Redis(
    host=os.getenv('REDIS_HOST', '127.0.0.1'),
    port=int(os.getenv('REDIS_PORT', 6379))
)

# Health check 추가 (신규 3줄)
@app.route('/health', methods=['GET'])
def health():
    return jsonify({'status': 'ok'}), 200
```

**끝!** 이게 전부입니다!

---

## 💡 더 간단하게 하는 방법

### 옵션 1: 환경 변수 없이 설정 파일만
```python
# config.py 파일 하나만 수정

class Config:
    REDIS_HOST = '192.168.100.20'  # Redis VIP
    DATABASE_URL = 'mysql://...'
```

각 서버별로 `config.py`만 다르게 배포!

### 옵션 2: Nginx에서만 처리
```
애플리케이션 코드는 그대로 두고,
Nginx upstream만 수정해서 로드밸런싱

단, Redis/DB는 여전히 HA 구성 필요
```

---

## 🚨 실제로 복잡한 부분

### 복잡한 건 인프라뿐!
```
❌ 코드 수정은 별로 안 복잡함
✅ 인프라 구성이 복잡함:
   - Redis Sentinel 설정
   - MariaDB Galera 설정
   - HAProxy 설정
   - 네트워크 설정
   - 모니터링 설정
```

---

## 📝 체크리스트: 정말 수정해야 하는 것

### 필수 (코드)
- [ ] Redis host를 환경 변수로 (2-3개 파일)
- [ ] DB URL을 환경 변수로 (3-4개 파일)
- [ ] Health check 추가 (4개 파일)

### 필수 (설정)
- [ ] Nginx upstream 수정 (1개 파일)
- [ ] `.env` 파일 생성

### 선택 (개선)
- [ ] 로그를 표준 출력으로 (Docker 친화적)
- [ ] Graceful shutdown 구현
- [ ] 메트릭 노출 (Prometheus)

---

## 결론

**수정해야 하는 건 매우 적습니다!**

```
코드 수정: 약 10개 파일, 총 20-30줄 정도
         (대부분 localhost → 환경변수로 변경)

설정 수정: Nginx upstream 1개 파일

인프라: 복잡하지만 코드와는 무관
       (Redis/DB HA, Load Balancer 등)
```

**핵심**: 현재 시스템이 이미 잘 설계되어 있어서, **인프라만 추가하면 거의 바로 작동합니다!**

---

**작성자**: Claude AI Assistant
**작성일**: 2025-10-26
