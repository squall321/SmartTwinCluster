# Phase 2: 기존 서비스 통합 (JWT 인증 추가)

**기간**: 1주 (5일)
**목표**: backend_5010, frontend_3010에 JWT 토큰 기반 인증 추가
**선행 조건**: Phase 1 완료
**담당자**: Backend 개발자 + Frontend 개발자

---

## 📋 목차

1. [개요](#개요)
2. [Day 1-2: Backend JWT 미들웨어 구현](#day-1-2-backend-jwt-미들웨어-구현)
3. [Day 3-4: Frontend JWT 통합](#day-3-4-frontend-jwt-통합)
4. [Day 5: 테스트 및 검증](#day-5-테스트-및-검증)
5. [검증 체크리스트](#검증-체크리스트)
6. [트러블슈팅](#트러블슈팅)

---

## 개요

### 목적
Phase 2는 기존에 운영 중인 관리 대시보드 서비스(backend_5010, frontend_3010)에 JWT 기반 인증을 추가하는 단계입니다.

### 통합 플로우
```
ServiceMenu → Dashboard 선택 (token 전달)
    ↓
frontend_3010 (URL에서 token 추출, localStorage 저장)
    ↓
API 요청 (Authorization: Bearer <token>)
    ↓
backend_5010 (JWT 미들웨어 검증)
    ↓
Slurm API 호출 (권한 검증)
```

### 주요 작업
1. ✅ backend_5010에 JWT 검증 미들웨어 추가
2. ✅ 그룹 기반 권한 검증 데코레이터 구현
3. ✅ 기존 API 엔드포인트에 인증 적용
4. ✅ frontend_3010에 JWT 토큰 처리 로직 추가
5. ✅ Axios 인터셉터로 자동 토큰 포함
6. ✅ 토큰 만료 시 재로그인 처리

### 성공 기준
- [ ] ServiceMenu에서 Dashboard 선택 → JWT 전달 확인
- [ ] API 호출 시 JWT 없으면 401 에러
- [ ] 유효한 JWT로 모든 기존 기능 정상 작동
- [ ] 그룹별 권한 검증 정상 동작

---

## Day 1-2: Backend JWT 미들웨어 구현

### 🎯 목표
backend_5010에 JWT 검증 미들웨어 및 권한 검증 시스템 추가

### Step 1.1: 기존 프로젝트 구조 파악
```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/backend_5010

# 프로젝트 구조 확인
tree -L 2

# 기존 라우트 파일 확인
ls -la *.py routes/*.py 2>/dev/null || ls -la *.py

# 메인 앱 파일 확인
cat app.py | head -50
```

### Step 1.2: JWT 패키지 설치
```bash
# 가상 환경 활성화 (있는 경우)
source venv/bin/activate 2>/dev/null || python3 -m venv venv && source venv/bin/activate

# PyJWT 설치
pip install PyJWT==2.8.0

# requirements.txt 업데이트
pip freeze > requirements.txt
```

### Step 1.3: 환경 변수 추가
```bash
# .env 파일 업데이트 (또는 생성)
cat >> .env << 'EOF'

# JWT Configuration
JWT_SECRET_KEY=your_jwt_secret_key_must_be_512_bits_or_more_for_hs256
JWT_ALGORITHM=HS256
EOF
```

### Step 1.4: JWT 미들웨어 구현
```python
# middleware/jwt_middleware.py
from functools import wraps
from flask import request, jsonify, g
import jwt
import os

JWT_SECRET_KEY = os.getenv('JWT_SECRET_KEY', 'your-secret-key')
JWT_ALGORITHM = os.getenv('JWT_ALGORITHM', 'HS256')

def jwt_required(f):
    """JWT 토큰 검증 데코레이터"""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        # Authorization 헤더 확인
        auth_header = request.headers.get('Authorization')

        if not auth_header:
            return jsonify({'error': 'No authorization header'}), 401

        # Bearer 토큰 추출
        parts = auth_header.split()
        if len(parts) != 2 or parts[0].lower() != 'bearer':
            return jsonify({'error': 'Invalid authorization header'}), 401

        token = parts[1]

        try:
            # JWT 검증
            payload = jwt.decode(
                token,
                JWT_SECRET_KEY,
                algorithms=[JWT_ALGORITHM]
            )

            # Flask g 객체에 사용자 정보 저장
            g.user = {
                'username': payload.get('sub'),
                'email': payload.get('email'),
                'name': payload.get('name'),
                'groups': payload.get('groups', []),
                'permissions': payload.get('permissions', [])
            }

            return f(*args, **kwargs)

        except jwt.ExpiredSignatureError:
            return jsonify({'error': 'Token has expired'}), 401
        except jwt.InvalidTokenError as e:
            return jsonify({'error': f'Invalid token: {str(e)}'}), 401

    return decorated_function


def group_required(allowed_groups):
    """그룹 기반 권한 검증 데코레이터"""
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            # jwt_required가 먼저 실행되어야 함
            if not hasattr(g, 'user'):
                return jsonify({'error': 'User not authenticated'}), 401

            user_groups = g.user.get('groups', [])

            # 허용된 그룹 중 하나라도 있는지 확인
            if not any(group in user_groups for group in allowed_groups):
                return jsonify({
                    'error': 'Insufficient permissions',
                    'required_groups': allowed_groups,
                    'user_groups': user_groups
                }), 403

            return f(*args, **kwargs)

        return decorated_function
    return decorator


def permission_required(required_permissions):
    """권한 기반 검증 데코레이터"""
    def decorator(f):
        @wraps(f)
        def decorated_function(*args, **kwargs):
            if not hasattr(g, 'user'):
                return jsonify({'error': 'User not authenticated'}), 401

            user_permissions = g.user.get('permissions', [])

            # 필요한 모든 권한이 있는지 확인
            missing_permissions = [
                perm for perm in required_permissions
                if perm not in user_permissions
            ]

            if missing_permissions:
                return jsonify({
                    'error': 'Insufficient permissions',
                    'required': required_permissions,
                    'missing': missing_permissions
                }), 403

            return f(*args, **kwargs)

        return decorated_function
    return decorator


def optional_jwt(f):
    """JWT 토큰 검증 (선택적, 에러 없음)"""
    @wraps(f)
    def decorated_function(*args, **kwargs):
        auth_header = request.headers.get('Authorization')

        if auth_header:
            parts = auth_header.split()
            if len(parts) == 2 and parts[0].lower() == 'bearer':
                token = parts[1]
                try:
                    payload = jwt.decode(
                        token,
                        JWT_SECRET_KEY,
                        algorithms=[JWT_ALGORITHM]
                    )
                    g.user = {
                        'username': payload.get('sub'),
                        'email': payload.get('email'),
                        'groups': payload.get('groups', []),
                        'permissions': payload.get('permissions', [])
                    }
                except:
                    pass

        return f(*args, **kwargs)

    return decorated_function
```

### Step 1.5: 기존 라우트에 미들웨어 적용
```python
# app.py (예시 - 실제 파일 구조에 따라 수정)

# 기존 import에 추가
from middleware.jwt_middleware import jwt_required, group_required, permission_required

# 예시: Job 제출 API (HPC-Admins, HPC-Users만 허용)
@app.route('/api/jobs/submit', methods=['POST'])
@jwt_required
@group_required(['HPC-Admins', 'HPC-Users'])
def submit_job():
    user = g.user  # JWT 페이로드에서 추출한 사용자 정보

    # 기존 Job 제출 로직
    job_data = request.json

    # 사용자 정보 로깅
    print(f"Job submitted by: {user['username']} ({user['email']})")

    # ... 기존 코드 ...

    return jsonify({'status': 'success', 'job_id': 12345})


# 예시: Job 취소 API (관리자만 타인의 Job 취소 가능)
@app.route('/api/jobs/<job_id>/cancel', methods=['DELETE'])
@jwt_required
def cancel_job(job_id):
    user = g.user

    # Job 소유자 확인
    job_owner = get_job_owner(job_id)  # 가정된 함수

    # 본인 Job이거나 관리자인 경우만 허용
    if job_owner != user['username'] and 'HPC-Admins' not in user['groups']:
        return jsonify({'error': 'Cannot cancel other users jobs'}), 403

    # ... 기존 취소 로직 ...

    return jsonify({'status': 'success'})


# 예시: 시스템 설정 API (관리자만)
@app.route('/api/system/config', methods=['GET', 'PUT'])
@jwt_required
@permission_required(['system.config'])
def system_config():
    if request.method == 'GET':
        # 설정 조회
        return jsonify({'config': {}})
    else:
        # 설정 업데이트
        return jsonify({'status': 'updated'})


# 공개 엔드포인트 (JWT 불필요)
@app.route('/api/public/info', methods=['GET'])
def public_info():
    return jsonify({'info': 'Public information'})
```

### Step 1.6: 에러 핸들러 추가
```python
# app.py에 추가

@app.errorhandler(401)
def unauthorized(error):
    return jsonify({
        'error': 'Unauthorized',
        'message': 'Authentication required. Please login.',
        'auth_url': 'https://localhost/auth/saml/login'
    }), 401


@app.errorhandler(403)
def forbidden(error):
    return jsonify({
        'error': 'Forbidden',
        'message': 'You do not have permission to access this resource.'
    }), 403
```

### ✅ Day 1-2 완료 체크리스트
- [ ] JWT 미들웨어 구현
- [ ] 그룹 기반 권한 데코레이터 구현
- [ ] 권한 기반 권한 데코레이터 구현
- [ ] 기존 API 라우트에 데코레이터 적용
- [ ] 에러 핸들러 추가
- [ ] 테스트 API 호출 (JWT 없이 → 401 확인)

---

## Day 3-4: Frontend JWT 통합

### 🎯 목표
frontend_3010에 JWT 토큰 처리 및 Axios 인터셉터 추가

### Step 2.1: 기존 프로젝트 구조 파악
```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/frontend_3010

# 프로젝트 구조 확인
ls -la src/

# 기존 API 클라이언트 확인
cat src/api/*.ts src/api/*.js 2>/dev/null || ls src/
```

### Step 2.2: JWT 유틸리티 추가
```typescript
// src/utils/jwt.ts (또는 src/utils/jwt.js)
export const getToken = (): string | null => {
  return localStorage.getItem('jwt_token');
};

export const saveToken = (token: string): void => {
  localStorage.setItem('jwt_token', token);
};

export const removeToken = (): void => {
  localStorage.removeItem('jwt_token');
};

export const isTokenExpired = (): boolean => {
  const token = getToken();
  if (!token) return true;

  try {
    const payload = JSON.parse(atob(token.split('.')[1]));
    const now = Math.floor(Date.now() / 1000);
    return payload.exp < now;
  } catch {
    return true;
  }
};
```

### Step 2.3: App.tsx (또는 main 파일) 수정
```typescript
// src/App.tsx
import { useEffect } from 'react';
import { useSearchParams, useNavigate } from 'react-router-dom';
import { saveToken, isTokenExpired, getToken } from './utils/jwt';

function App() {
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();

  useEffect(() => {
    // URL 파라미터에서 토큰 추출
    const tokenFromUrl = searchParams.get('token');

    if (tokenFromUrl) {
      // 토큰 저장
      saveToken(tokenFromUrl);

      // URL에서 토큰 제거 (브라우저 히스토리 보안)
      window.history.replaceState({}, '', window.location.pathname);
    } else {
      // 기존 토큰 확인
      const token = getToken();

      if (!token || isTokenExpired()) {
        // 토큰이 없거나 만료됨 → Auth Portal로 리다이렉트
        window.location.href = 'https://localhost/';
        return;
      }
    }
  }, [searchParams, navigate]);

  // 나머지 앱 로직...
  return (
    <div>
      {/* 기존 컴포넌트 */}
    </div>
  );
}

export default App;
```

### Step 2.4: Axios 인터셉터 설정
```typescript
// src/api/client.ts (또는 axios 설정 파일)
import axios from 'axios';
import { getToken, removeToken } from '../utils/jwt';

// Axios 인스턴스 생성
const apiClient = axios.create({
  baseURL: 'http://localhost:5010/api',  // backend_5010
  timeout: 10000,
});

// Request 인터셉터: 모든 요청에 JWT 토큰 포함
apiClient.interceptors.request.use(
  (config) => {
    const token = getToken();
    if (token) {
      config.headers.Authorization = `Bearer ${token}`;
    }
    return config;
  },
  (error) => {
    return Promise.reject(error);
  }
);

// Response 인터셉터: 401 에러 시 재로그인
apiClient.interceptors.response.use(
  (response) => {
    return response;
  },
  (error) => {
    if (error.response?.status === 401) {
      // 토큰 만료 또는 인증 실패
      removeToken();

      // Auth Portal로 리다이렉트
      window.location.href = 'https://localhost/';
    }
    return Promise.reject(error);
  }
);

export default apiClient;
```

### Step 2.5: 기존 API 호출 코드 수정
```typescript
// src/api/jobs.ts (예시)
import apiClient from './client';

// 기존 코드 (fetch 사용)
// const response = await fetch('http://localhost:5010/api/jobs');

// 수정된 코드 (apiClient 사용, 자동으로 JWT 포함)
export const getJobs = async () => {
  const response = await apiClient.get('/jobs');
  return response.data;
};

export const submitJob = async (jobData: any) => {
  const response = await apiClient.post('/jobs/submit', jobData);
  return response.data;
};

export const cancelJob = async (jobId: string) => {
  const response = await apiClient.delete(`/jobs/${jobId}/cancel`);
  return response.data;
};
```

### Step 2.6: 사용자 정보 표시
```typescript
// src/components/UserInfo.tsx (새로 생성)
import { useState, useEffect } from 'react';
import { getToken } from '../utils/jwt';

interface UserInfo {
  username: string;
  email: string;
  name: string;
  groups: string[];
}

const UserInfo = () => {
  const [user, setUser] = useState<UserInfo | null>(null);

  useEffect(() => {
    const token = getToken();
    if (token) {
      try {
        const payload = JSON.parse(atob(token.split('.')[1]));
        setUser({
          username: payload.sub,
          email: payload.email,
          name: payload.name,
          groups: payload.groups
        });
      } catch (e) {
        console.error('Failed to parse token', e);
      }
    }
  }, []);

  if (!user) return null;

  return (
    <div className="user-info">
      <span>{user.name}</span>
      <span>({user.email})</span>
      <div>
        {user.groups.map(group => (
          <span key={group} className="badge">{group}</span>
        ))}
      </div>
    </div>
  );
};

export default UserInfo;
```

### ✅ Day 3-4 완료 체크리스트
- [ ] JWT 유틸리티 함수 추가
- [ ] App.tsx에서 URL 토큰 추출 및 저장
- [ ] Axios 인터셉터 설정
- [ ] 기존 API 호출 코드를 apiClient로 수정
- [ ] 사용자 정보 표시 컴포넌트 추가
- [ ] 401 에러 시 재로그인 동작 확인

---

## Day 5: 테스트 및 검증

### 🎯 목표
전체 통합 테스트 및 권한 검증

### Step 3.1: 통합 테스트 스크립트
```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard

cat > test_phase2_integration.sh << 'EOF'
#!/bin/bash

echo "=== Phase 2 통합 테스트 ==="
echo

# 1. ServiceMenu에서 토큰 생성
echo "1. Auth Portal에서 토큰 발급 테스트..."
echo "  수동: http://localhost:4431 → SSO 로그인 → ServiceMenu"

# 2. Dashboard API 테스트 (JWT 없이)
echo "2. Dashboard API 접근 (JWT 없이) - 401 예상..."
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:5010/api/jobs)
if [ "$RESPONSE" == "401" ]; then
    echo "✓ JWT 없이 401 에러 정상"
else
    echo "✗ 예상 401, 실제 $RESPONSE"
fi

# 3. Dashboard API 테스트 (잘못된 JWT)
echo "3. Dashboard API 접근 (잘못된 JWT) - 401 예상..."
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer invalid_token" \
  http://localhost:5010/api/jobs)
if [ "$RESPONSE" == "401" ]; then
    echo "✓ 잘못된 JWT로 401 에러 정상"
else
    echo "✗ 예상 401, 실제 $RESPONSE"
fi

echo
echo "=== 수동 테스트 절차 ==="
echo "1. Auth Portal에서 로그인 (http://localhost:4431)"
echo "2. ServiceMenu에서 '관리 대시보드' 선택"
echo "3. frontend_3010에서 JWT 자동 추출 확인"
echo "4. 브라우저 개발자 도구 → Application → Local Storage → jwt_token 확인"
echo "5. 기존 기능 테스트 (Job 조회, 제출 등)"
echo "6. 권한 없는 기능 테스트 (403 예상)"
echo "7. 1시간 후 토큰 만료 테스트 (재로그인)"
EOF

chmod +x test_phase2_integration.sh
```

### Step 3.2: 권한별 테스트 시나리오
```markdown
# Phase 2 테스트 시나리오

## 시나리오 1: HPC-Admins (관리자)
- 사용자: admin@hpc.local / admin123
- 기대 동작:
  - ✓ Dashboard 접근 가능
  - ✓ Job 조회 가능
  - ✓ 본인 Job 제출 가능
  - ✓ 타인 Job 취소 가능
  - ✓ 시스템 설정 접근 가능

## 시나리오 2: HPC-Users (일반 사용자)
- 사용자: user01@hpc.local / password123
- 기대 동작:
  - ✓ Dashboard 접근 가능
  - ✓ Job 조회 가능
  - ✓ 본인 Job 제출 가능
  - ✗ 타인 Job 취소 불가 (403)
  - ✗ 시스템 설정 접근 불가 (403)

## 시나리오 3: GPU-Users (GPU 전용)
- 사용자: gpu_user@hpc.local / password123
- 기대 동작:
  - ✗ Dashboard 접근 불가 (ServiceMenu에 표시 안 됨)
  - (Phase 3에서 VNC만 접근 가능)

## 시나리오 4: 토큰 만료
- 1시간 후 토큰 만료
- API 호출 시 401 에러
- 자동으로 Auth Portal로 리다이렉트
```

### Step 3.3: 실행 및 검증
```bash
# 테스트 스크립트 실행
./test_phase2_integration.sh

# 브라우저 테스트
firefox https://localhost/ &
```

### ✅ Day 5 완료 체크리스트
- [ ] JWT 없이 API 호출 시 401 확인
- [ ] 잘못된 JWT로 401 확인
- [ ] 유효한 JWT로 API 정상 호출 확인
- [ ] 그룹별 권한 검증 확인
- [ ] 토큰 만료 시 재로그인 확인

---

## 검증 체크리스트

### Backend 검증 (6개)
- [ ] JWT 미들웨어 정상 동작
- [ ] 그룹 기반 권한 검증 동작
- [ ] 권한 기반 권한 검증 동작
- [ ] 401 에러 핸들러 동작
- [ ] 403 에러 핸들러 동작
- [ ] g.user 객체에 사용자 정보 저장

### Frontend 검증 (6개)
- [ ] URL에서 토큰 추출
- [ ] localStorage에 토큰 저장
- [ ] Axios 인터셉터로 자동 토큰 포함
- [ ] 401 에러 시 재로그인
- [ ] 사용자 정보 표시
- [ ] 기존 기능 정상 동작

### 통합 검증 (5개)
- [ ] ServiceMenu → Dashboard 토큰 전달
- [ ] API 호출 시 JWT 자동 포함
- [ ] 그룹별 접근 제어 정상
- [ ] 토큰 만료 시 재인증
- [ ] 모든 기존 기능 정상 작동

---

## 트러블슈팅

### 문제: API 호출 시 계속 401 에러
```bash
# JWT_SECRET_KEY가 동일한지 확인
grep JWT_SECRET_KEY auth_portal_4430/.env
grep JWT_SECRET_KEY backend_5010/.env

# 키가 다르면 통일
# backend_5010/.env를 auth_portal_4430/.env와 동일하게 수정
```

### 문제: CORS 에러
```bash
# backend_5010/app.py에 CORS 설정 확인
# from flask_cors import CORS
# CORS(app, origins=['http://localhost:3010', 'https://localhost'])
```

### 문제: 토큰이 전달되지 않음
```javascript
// 브라우저 개발자 도구 → Console
localStorage.getItem('jwt_token')

// Axios 요청 헤더 확인
apiClient.interceptors.request.use(config => {
  console.log('Request headers:', config.headers);
  return config;
});
```

### 문제: 403 에러 (권한 부족)
```bash
# JWT 페이로드의 groups 확인
# jwt.io에서 토큰 디코딩
# groups 필드에 필요한 그룹이 있는지 확인

# 백엔드 로그 확인
tail -f backend_5010/logs/*.log
```

---

**Phase 2 완료!** 🎉

다음: **Phase 3 - VNC 시각화 시스템** (Apptainer + TurboVNC + noVNC)
