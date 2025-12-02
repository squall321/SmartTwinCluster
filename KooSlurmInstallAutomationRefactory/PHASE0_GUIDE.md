# Phase 0 실행 가이드

## 🎯 목표
- 현재 상태 완전 문서화
- 변경 범위 최종 확정
- 디렉토리 구조 준비

## ⏱️ 예상 소요 시간
**총 2시간**

## 📋 실행 순서

### 1. 현재 상태 수집 (1시간)

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory

# 자동 수집 스크립트 실행
bash collect_current_state.sh

# 결과 확인
cat CURRENT_STATE.md
```

### 2. 디렉토리 구조 생성 (30분)

```bash
# 디렉토리 생성
mkdir -p web_services/{scripts,templates/{env,nginx,systemd},config,docs}
mkdir -p backups

# README 생성 스크립트 실행
bash create_directory_structure.sh

# 구조 확인
tree -L 3 web_services/ || find web_services/ -type d | sort
```

### 3. 포트 매핑 문서화 (30분)

```bash
# 포트 매핑 파일 생성
cat > web_services/docs/port_mapping.yaml << 'EOF'
# (내용은 별도 파일 참조)
EOF

# 확인
cat web_services/docs/port_mapping.yaml
```

### 4. 검증 (10분)

```bash
# Phase 0 검증 실행
bash verify_phase0.sh

# 기대 출력:
# ✅ 디렉토리 구조 생성 완료
# ✅ 문서화 완료
# ✅✅✅ Phase 0 완료! Phase 1 진행 가능
```

## ✅ 완료 체크리스트

- [ ] web_services/ 디렉토리 구조 생성
- [ ] MIGRATION_PLAN.md 작성 완료
- [ ] CURRENT_STATE.md 생성 완료
- [ ] web_services/docs/port_mapping.yaml 작성
- [ ] verify_phase0.sh 실행 성공

## 🚫 주의사항

1. **기존 서비스 영향 없음**
   - Phase 0은 조회만 수행
   - 실행 중인 서비스에 영향 없음

2. **롤백 불필요**
   - 설정 변경 없음
   - 문서만 생성

## 📝 다음 단계

Phase 0 완료 후:
```bash
cat PHASE1_GUIDE.md
```
