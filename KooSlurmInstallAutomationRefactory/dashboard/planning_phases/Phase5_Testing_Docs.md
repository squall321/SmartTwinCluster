# Phase 5: 테스트 및 문서화

**기간**: 1주 (5일)
**목표**: 통합 테스트, 부하 테스트, 운영 문서 작성
**선행 조건**: Phase 0-4 완료
**담당자**: 전체 팀

---

## Day 1-2: 단위 및 통합 테스트

### 단위 테스트
```python
# auth_portal_4430/tests/test_jwt.py
import pytest
from jwt_handler import JWTHandler

def test_create_token():
    user_info = {
        'username': 'test_user',
        'email': 'test@hpc.local',
        'groups': ['HPC-Users']
    }
    token = JWTHandler.create_token(user_info)
    assert token is not None

def test_verify_token():
    token = JWTHandler.create_token({...})
    payload, error = JWTHandler.verify_token(token)
    assert error is None
    assert payload['sub'] == 'test_user'
```

### 통합 테스트
```bash
# E2E 테스트 스크립트
cat > test_e2e.sh << 'EOF'
#!/bin/bash
# 1. SAML 로그인
# 2. JWT 토큰 발급 확인
# 3. Dashboard API 호출
# 4. VNC 세션 생성
# 5. 모니터링 메트릭 확인
EOF
```

---

## Day 3: 부하 테스트

### 동시 세션 테스트
```bash
# 10개 VNC 세션 동시 생성
for i in {1..10}; do
    curl -X POST http://localhost:5010/api/vnc/sessions \
      -H "Authorization: Bearer $TOKEN" \
      -d '{"gpu_count":1}' &
done
```

---

## Day 4-5: 문서화

### 운영 매뉴얼 (OPERATIONS.md)
- 서비스 시작/중지 절차
- 백업 및 복구
- 로그 확인 방법
- 일반적인 문제 해결

### 사용자 가이드 (USER_GUIDE.md)
- SSO 로그인 방법
- VNC 세션 생성 및 사용
- 서비스 선택 가이드

### API 문서 (API.md)
- Swagger/OpenAPI 스펙
- 엔드포인트 목록
- 권한 요구사항

### 아키텍처 문서
- 전체 시스템 다이어그램
- 인증 플로우
- 데이터 흐름

---

## 검증 체크리스트

- [ ] 단위 테스트 커버리지 > 80%
- [ ] 통합 테스트 통과
- [ ] 부하 테스트 (동시 세션 10개) 성공
- [ ] 모든 문서 작성 완료
- [ ] 프로덕션 배포 체크리스트 작성

---

**Phase 5 완료!** 전체 개발 완료 🎉
