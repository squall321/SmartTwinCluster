# HPC 웹 서비스 자동화 마이그레이션 계획

## 📊 변경 범위 요약

| 카테고리 | 변경 여부 | 파일 수 | Phase |
|---------|----------|---------|-------|
| Slurm 설정 | ❌ 변경 없음 | 0 | - |
| 서비스 시작/종료 스크립트 | ❌ 변경 없음 | 0 | - |
| Python 백엔드 설정 | ✏️ 최소 변경 | 2 | Phase 2 |
| TypeScript 프론트엔드 | ✏️ 최소 변경 | 3 | Phase 2 |
| 자동화 스크립트 | 🆕 신규 생성 | 10+ | Phase 3 |
| Nginx 설정 | 🆕 신규 생성 | 2 | Phase 4 |

## 🔴 절대 수정 금지 (Slurm 관련)

```
❌ my_cluster.yaml
❌ setup_cluster_full.sh
❌ validate_config.py
❌ test_connection.py
❌ setup_ssh_passwordless.sh
```

## 🔴 절대 수정 금지 (서비스 스크립트)

```
❌ dashboard/*/start.sh
❌ dashboard/*/stop.sh
❌ dashboard/start_all.sh
❌ dashboard/stop_all.sh
❌ dashboard/start_complete.sh
❌ dashboard/stop_complete.sh
❌ dashboard/start_all_mock.sh
```

## ✏️ 최소 변경 (Phase 2)

### Python 백엔드
```
📝 dashboard/auth_portal_4430/config/config.py
   - 하드코딩 URL → 환경 변수
   - 30-40줄 수정

📝 dashboard/auth_portal_4430/saml_handler.py
   - SAML IDP URL → 환경 변수
   - 10-15줄 수정
```

### TypeScript 프론트엔드
```
📝 dashboard/auth_portal_4431/src/pages/ServiceMenuPage.tsx
   - handleServiceClick 함수 개선
   - 15-20줄 수정

📝 dashboard/auth_portal_4431/src/pages/VNCPage.tsx
   - API_URL 상수 → 환경 변수
   - 1줄 수정

📝 dashboard/vnc_service_8002/src/App.tsx
   - Footer 링크 수정
   - 1줄 수정
```

## 🆕 신규 생성 (Phase 1-4)

### Phase 1: 설정 파일
```
🆕 web_services_config.yaml              (150-200줄)
🆕 web_services/docs/port_mapping.yaml   (100줄)
🆕 CURRENT_STATE.md                      (자동 생성)
```

### Phase 2: 환경 변수 템플릿
```
🆕 web_services/templates/env/auth_portal.env.j2
🆕 web_services/templates/env/frontend.env.j2
🆕 dashboard/auth_portal_4430/.env.template
🆕 dashboard/auth_portal_4431/.env.template
```

### Phase 3: 자동화 스크립트
```
🆕 setup_web_services.sh                 (200-250줄)
🆕 reconfigure_web_services.sh           (250-300줄)
🆕 web_services/scripts/install_dependencies.sh
🆕 web_services/scripts/generate_env_files.py
🆕 web_services/scripts/setup_nginx.sh
🆕 web_services/scripts/reconfigure_service.sh
🆕 web_services/scripts/health_check.sh
🆕 web_services/scripts/rollback.sh
🆕 verify_phase*.sh                      (각 Phase별)
```

### Phase 4: Nginx 설정
```
🆕 web_services/templates/nginx/main.conf.j2
🆕 web_services/scripts/generate_nginx_config.sh
```

## 📅 Phase별 진행 계획

### Phase 0 (1일)
- [x] 현재 상태 문서화
- [x] 디렉토리 구조 생성
- [x] 변경 범위 확정

### Phase 1 (2일)
- [ ] web_services_config.yaml 작성
- [ ] 템플릿 구조 설계
- [ ] 포트 매핑 정의

### Phase 2 (2-3일)
- [ ] config.py 환경 변수화
- [ ] Frontend URL 처리 개선
- [ ] .env 파일 생성 자동화

### Phase 3 (3-4일)
- [ ] setup_web_services.sh 구현
- [ ] reconfigure_web_services.sh 구현
- [ ] 헬스 체크 구현

### Phase 4 (2일)
- [ ] Nginx 템플릿 작성
- [ ] Nginx 자동 설정 구현
- [ ] SSL 설정

### Phase 5 (2일)
- [ ] 통합 테스트
- [ ] 새 서버 배포 시뮬레이션
- [ ] 문서화

## 🎯 성공 기준

### 기능적 요구사항
- ✅ 단일 명령어로 전체 설치: `./setup_web_services.sh development`
- ✅ 환경 전환 자동화: `./reconfigure_web_services.sh production`
- ✅ 기존 방식 하위 호환: `./start_complete.sh` 정상 동작
- ✅ SSO 자동 토글: 환경별 자동 활성화/비활성화

### 비기능적 요구사항
- ✅ Slurm 설정 무손상
- ✅ 기존 서비스 스크립트 무손상
- ✅ 롤백 가능
- ✅ 새 서버 배포 10분 이내

## 📊 예상 소요 시간

| Phase | 예상 시간 | 주요 작업 |
|-------|----------|----------|
| Phase 0 | 1일 | 준비 및 문서화 |
| Phase 1 | 2일 | 설정 파일 구조화 |
| Phase 2 | 2-3일 | 환경 변수 도입 |
| Phase 3 | 3-4일 | 자동화 스크립트 |
| Phase 4 | 2일 | Nginx 리버스 프록시 |
| Phase 5 | 2일 | 테스트 및 검증 |
| **합계** | **12-15일** | |
