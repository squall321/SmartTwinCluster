# Legacy Files

이 디렉토리에는 더 이상 사용하지 않는 레거시 파일들이 보관되어 있습니다.

## 디렉토리 구조

- **old_scripts/**: 통합되거나 대체된 구버전 스크립트들
- **old_docs/**: 개발 과정에서 생성된 임시 문서들
- **old_configs/**: 사용하지 않는 구버전 설정 파일들

## 파일별 설명

### old_scripts/

| 파일명 | 대체된 기능 | 비고 |
|--------|------------|------|
| make_executable.sh | setup.sh | 통합됨 |
| make_scripts_executable.sh | setup.sh | 통합됨 |
| setup_venv.sh | setup.sh | 통합됨 |
| setup_dashboard_permissions.sh | setup.sh | 통합됨 |
| setup_performance_monitoring.sh | setup.sh | 통합됨 |
| verify_fixes.sh | validate_config.py | 기능 통합 |
| update_configs.sh | 자동 처리 | 더 이상 불필요 |

### old_docs/

개발 과정에서 생성된 체크리스트, 리포트, 요약 문서들입니다.
최종 문서는 다음과 같습니다:

- **README.md**: 전체 프로젝트 문서
- **QUICKSTART.md**: 빠른 시작 가이드
- **docs/**: 상세 기술 문서

## 복원이 필요한 경우

```bash
# 특정 파일 복원
cp legacy/old_scripts/파일명 ./

# 전체 복원 (권장하지 않음)
cp -r legacy/old_scripts/* ./
```

## 삭제 시점

이 파일들은 다음 마일스톤 이후 완전히 삭제될 예정입니다:
- v2.0.0 릴리스 이후
- 3개월간 이슈가 없는 경우

---

마지막 업데이트: $(date +%Y-%m-%d)
