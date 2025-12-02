#!/bin/bash
################################################################################
# Phase 0 - 디렉토리 구조 생성
################################################################################

echo "📁 디렉토리 구조 생성 중..."
echo ""

cd /home/koopark/claude/KooSlurmInstallAutomationRefactory

# 1. 메인 디렉토리 생성
echo "1️⃣ 메인 디렉토리 생성..."
mkdir -p web_services/{scripts,templates,config,docs}
mkdir -p web_services/templates/{env,nginx,systemd}
mkdir -p backups

# 2. 각 디렉토리별 README 생성
echo "2️⃣ README 파일 생성..."

# web_services/README.md
cat > web_services/README.md << 'EOF'
# HPC 웹 서비스 자동화

## 디렉토리 구조

```
web_services/
├── scripts/          # 자동화 스크립트
│   ├── install_dependencies.sh
│   ├── generate_env_files.py
│   ├── setup_nginx.sh
│   ├── reconfigure_service.sh
│   ├── health_check.sh
│   └── rollback.sh
├── templates/        # 설정 파일 템플릿
│   ├── env/         # 환경 변수 템플릿 (.env.j2)
│   ├── nginx/       # Nginx 설정 템플릿
│   └── systemd/     # Systemd 서비스 템플릿 (선택)
├── config/          # 기본 설정값
│   └── defaults.yaml
└── docs/            # 문서
    ├── port_mapping.yaml
    └── architecture.md
```

## Phase별 진행 상황

- [x] Phase 0: 준비 및 문서화
- [ ] Phase 1: 설정 파일 구조화
- [ ] Phase 2: 환경 변수 도입
- [ ] Phase 3: 자동화 스크립트 구현
- [ ] Phase 4: Nginx 리버스 프록시
- [ ] Phase 5: 테스트 및 검증
EOF

# web_services/scripts/README.md
cat > web_services/scripts/README.md << 'EOF'
# 자동화 스크립트

## 스크립트 목록

| 스크립트 | 용도 | Phase |
|---------|------|-------|
| install_dependencies.sh | 시스템 의존성 자동 설치 | 3 |
| generate_env_files.py | .env 파일 자동 생성 | 2 |
| setup_nginx.sh | Nginx 설정 자동 배포 | 4 |
| reconfigure_service.sh | 개별 서비스 재구성 | 3 |
| health_check.sh | 서비스 헬스 체크 | 3 |
| rollback.sh | 설정 롤백 | 3 |

## 사용 예시

```bash
# 전체 설치
cd ../..
./setup_web_services.sh development

# 재구성만
./reconfigure_web_services.sh production

# 개별 서비스
bash web_services/scripts/reconfigure_service.sh auth_portal
```
EOF

# web_services/templates/README.md
cat > web_services/templates/README.md << 'EOF'
# 설정 파일 템플릿

## Jinja2 템플릿

모든 템플릿은 Jinja2 문법을 사용합니다.

### 환경 변수 템플릿 (env/)
- `auth_portal.env.j2`: Auth Portal 환경 변수
- `frontend.env.j2`: Frontend 공통 환경 변수

### Nginx 템플릿 (nginx/)
- `main.conf.j2`: 메인 Nginx 설정

### Systemd 템플릿 (systemd/) - 선택적
- `*.service.j2`: Systemd 서비스 파일 템플릿
EOF

# web_services/docs/README.md
cat > web_services/docs/README.md << 'EOF'
# 문서

## 문서 목록

- `port_mapping.yaml`: 서비스별 포트 매핑
- `architecture.md`: 시스템 아키텍처 (Phase 5에서 작성)
EOF

# 3. .gitkeep 파일 생성 (빈 디렉토리 유지)
echo "3️⃣ .gitkeep 파일 생성..."
touch web_services/config/.gitkeep
touch backups/.gitkeep

# 4. 구조 확인
echo "4️⃣ 생성된 구조 확인..."
echo ""
tree -L 3 web_services/ 2>/dev/null || find web_services/ -type f -o -type d | sort

echo ""
echo "✅ 디렉토리 구조 생성 완료"
