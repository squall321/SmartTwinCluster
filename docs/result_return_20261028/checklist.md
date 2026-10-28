# 결과 귀환 선행(REQUEST-result-return.md A~D) — 체크리스트

요청서: [../REQUEST-result-return.md](../REQUEST-result-return.md) · 결정 근거: [context-notes.md](context-notes.md)

## A. 잡 파일 REST 인증·소유 검사 (`dashboard/backend_5010/job_logs_api.py`)
- [x] 8개 라우트 `@optional_jwt` → `@jwt_required` + 소유 검사(admin 전부, 그 밖엔 `job_submissions.user_id == 호출자`)
- [x] 경로 검사 `real == base or startswith(base + os.sep)`, 상대 경로는 잡 폴더 안만(LOGS_DIR 허용 제거)
- [x] download 의 `job_dir` 를 분기 전에 정함(`path=stdout` 500 해소)
- [x] 다운로드 버튼(`window.open`) — 단기 다운로드 티켓(`POST …/files/download-ticket`) + 프런트 수정
- [x] 테스트: 토큰 없음 401 · 남의 잡 403 · `A_12`→`../A_123/…` 403 · `path=stdout` 200 · 티켓 200/만료·다른 잡 401

## B. 귀환 매니페스트 (`output/return_manifest.json`)
- [x] 작성기 `return_manifest.py`(단일 정본) — 백엔드가 이를 부르는 템플릿 스크립트에 셸 함수로 심음
- [x] 두 템플릿 post_exec — 리포트 잡 id 추출 → 대기 → 매니페스트(임시 파일 + mv)
- [x] 겹침 해소: 리포트 잡이 있으면 post_exec `postprocess --all` 생략(리포트 잡이 정본)
- [x] 이른 종료(pre/main `exit 1`)에도 EXIT trap 으로 매니페스트
- [x] 테스트: 있음/없음·이유·err 꼬리, 원자적 쓰기, 생성 스크립트에 함수가 심기는지

## C. 끝난 잡에 후처리 잡을 거는 REST (`POST /api/jobs/<id>/postprocess`)
- [x] 소유 검사(A 와 같은 규칙) · KooChainRun 템플릿 잡만 · 원 잡/선행 후처리 잡이 돌고 있으면 409
- [x] sbatch 스크립트: `KooChainRun postprocess --<mode>` 뒤 매니페스트 갱신, 결과는 원 잡 폴더
- [x] 제출 기록(job_submissions)에 후처리 잡도 남김(소유 검사가 그 잡 로그에도 통하게)
- [x] 테스트: 남의 잡 403 · 돌고 있는 잡 409 · 성공 시 스크립트 내용·매니페스트 치움

## D. 드라이버 종료 상태
- [x] 리포트가 기대되는데 없으면 드라이버 `exit 3` (FAILED 3:0), 매니페스트에 rc·이유

## 마무리
- [x] 백엔드 테스트 통과(34건, `venv/bin/python -m unittest discover -s tests`), 프런트 타입 검사(`tsc --noEmit`)
- [x] 요청서에 회신 절(§6, 무엇이 어느 커밋에) · peer(kooremapper-4a)에 회신
- [x] 실제 Slurm 검증 — dev node001 에서 사본에 C(성공 COMPLETED·ok, 실패 FAILED 3:0), VM 끔
- [x] origin/main 푸시(10-28 23:34 UTC, `5f226d1f..7c280000`) — 사용자 결정 「지금 반영」
- [ ] icn401 에서 `git pull && sudo ./dashboard/start_production.sh` (백엔드 재시작·템플릿 cp -ru·frontend_3010 자동 재빌드) — 사용자 실행
- [ ] 운영 첫 실제 전각도 잡에서 `output/return_manifest.json` 생성 확인 — 안 생기면 C 로 다시 건다
