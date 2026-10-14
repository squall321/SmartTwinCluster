<!-- KooRemapper 정본(platform/core/kooremapper_core) 의 벤더링 사본 — 손대지 말고 동기화할 것 -->
# kooremapper_core (벤더링 사본)

remap_* 도구가 op 스키마·argv/config 생성에 쓰는 KooRemapper 정본의 **바이트 동일 사본**이다.
운영 헤드에는 KooRemapper 리포가 없어서 여기 둔다. 이 폴더 파일을 직접 고치지 말 것.

- 원본: `KooRemapper/platform/core/kooremapper_core/` (복사 시점 커밋 0db8d64)
- 동기화: `cp -p <KooRemapper>/platform/core/kooremapper_core/{__init__,catalog,argbuild}.py <KooRemapper>/platform/core/kooremapper_core/catalog_data.json .`
  후 `tools/_gen/generate_smarttwin_tools.py` 재실행(remap_* 생성물 갱신)
- 시험: `tests/test_smarttwin_coverage.py::test_vendored_kooremapper_core_matches_source` 가 원본과 바이트 비교(원본 없으면 skip)
- 의존: PyYAML·jsonschema (서비스 venv 에 있음). AGENT_GUIDE §9.5 의 "stdlib only" 예외 — local transport 전용.
