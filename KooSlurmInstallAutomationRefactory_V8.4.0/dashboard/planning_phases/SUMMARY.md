# 개발 계획 요약

## 📊 전체 구조

총 **7개의 문서**로 구성된 단계별 개발 계획:

1. **[README.md](README.md)** - 전체 인덱스 및 시작 가이드 (12KB)
2. **[Phase0_Prerequisites.md](Phase0_Prerequisites.md)** - 사전 준비 (38KB)
3. **[Phase1_Auth_Portal.md](Phase1_Auth_Portal.md)** - Auth Portal 개발 (45KB)
4. **[Phase2_Service_Integration.md](Phase2_Service_Integration.md)** - 서비스 통합 (20KB)
5. **[Phase3_VNC_System.md](Phase3_VNC_System.md)** - VNC 시스템 (8KB)
6. **[Phase4_CAE_Monitoring.md](Phase4_CAE_Monitoring.md)** - CAE & 모니터링 (2KB)
7. **[Phase5_Testing_Docs.md](Phase5_Testing_Docs.md)** - 테스트 & 문서화 (2KB)

**총 문서 크기**: ~127KB

---

## 🚀 빠른 시작

```bash
# 1. 인덱스 문서 확인
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/planning_phases
cat README.md

# 2. Phase 0부터 시작
cat Phase0_Prerequisites.md

# 3. Day 1 작업 시작
# my_cluster.yaml 백업 및 수정...
```

---

## 📅 타임라인

| 주차 | Phase | 일수 | 핵심 작업 |
|------|-------|------|----------|
| 1 | Phase 0 | 5일 | Slurm, Redis, SAML-IdP, Nginx, Apptainer |
| 2-4 | Phase 1 | 10-15일 | Auth Portal (Backend + Frontend) |
| 5 | Phase 2 | 5일 | 기존 서비스 JWT 통합 |
| 6-7 | Phase 3 | 10일 | VNC 시스템 구축 |
| 8 | Phase 4 | 5일 | CAE 통합, Prometheus/Grafana |
| 9 | Phase 5 | 5일 | 테스트 & 문서화 |

**총 기간**: 약 8-9주

---

## ✅ 각 Phase 완료 체크리스트

### Phase 0 ✓
- [ ] Slurm vnc 파티션 생성
- [ ] Redis 실행
- [ ] SAML-IdP 구동
- [ ] Nginx HTTPS 설정
- [ ] Apptainer 환경 검증

### Phase 1 ✓
- [ ] Auth Backend 구현
- [ ] Auth Frontend 구현
- [ ] SAML SSO 로그인 성공
- [ ] JWT 토큰 발급

### Phase 2 ✓
- [ ] JWT 미들웨어 추가
- [ ] Axios 인터셉터 설정
- [ ] 기존 서비스 정상 동작

### Phase 3 ✓
- [ ] Apptainer VNC 이미지 빌드
- [ ] Slurm Job 통합
- [ ] noVNC 접속 성공

### Phase 4 ✓
- [ ] CAE JWT 통합
- [ ] Prometheus 메트릭 추가
- [ ] Grafana 대시보드 생성

### Phase 5 ✓
- [ ] 통합 테스트 통과
- [ ] 부하 테스트 성공
- [ ] 운영 문서 작성

---

## 🎯 최종 목표

**통합 인증 시스템**:
- SAML 2.0 SSO 로그인
- JWT 토큰 기반 서비스 접근
- 그룹별 권한 관리 (4개 그룹)

**VNC 시각화**:
- GPU 가속 Ubuntu 데스크톱
- 웹 브라우저에서 접속
- Slurm Job으로 리소스 관리

**모니터링**:
- Prometheus 메트릭 수집
- Grafana 대시보드
- 실시간 세션 모니터링

---

## 📁 생성될 주요 파일

```
dashboard/
├── auth_portal_4430/          # Phase 1
│   ├── app.py
│   ├── saml_handler.py
│   ├── jwt_handler.py
│   └── redis_client.py
├── auth_portal_4431/          # Phase 1
│   └── src/pages/
│       ├── Login.tsx
│       └── ServiceMenu.tsx
├── backend_5010/              # Phase 2-3
│   ├── middleware/jwt_middleware.py
│   └── vnc_manager.py
└── apptainers/                # Phase 3
    └── ubuntu_vnc_gpu.def
```

---

**시작하기**: [README.md](README.md) → [Phase0_Prerequisites.md](Phase0_Prerequisites.md)
