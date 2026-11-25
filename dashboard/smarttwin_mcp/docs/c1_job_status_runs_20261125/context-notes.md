<!-- C-1 job_status runs 작업 중 결정과 근거 -->
# 컨텍스트 노트 — job_status `runs` (2026-11-25)

- 10-28 요청 접수 → 사용자 결정까지 받고 멈춰 있었다. 11-25 재개 시 main·다른 worktree·SmartTwinMCP 리포 어디에도 C-1 구현 없음 확인.
- live 트리(main 작업 트리)의 script.sh 는 고치는 즉시 :5013 호출에 쓰인다 → worktree 에서 만들고 시험한 뒤 병합.
- index 경로는 runner_config 의 `project.index_file` 대신 registry `output_dir` 기준으로 잡는다. runner_config 는 사용자 폴더 안이라
  고칠 수 있고, index_file 을 남의 캠페인으로 돌리면 남의 Run 폴더 이름이 샌다.
- index 의 `folder` 도 사용자 폴더 파일이라 `^Run_[A-Za-z0-9_]+$` 만 받는다(../ 로 남의 경로 stat 막기).
- 상태 값을 `done` 으로 바꾸지 않는다 — KooChainRun 값을 그대로 둬야 다른 도구(job_harvest 등)와 어휘가 같다.
- 재시도: KooChainRun 은 같은 별칭을 마지막 시도로 덮어쓴다. 앞 시도 Run 폴더는 runs 에 안 나온다(BindFix 캠페인 DOE1 폴더 3·index 1).
- 각도별 목록이 예외로 깨져도 job_status 의 상태 응답은 돌려준다(runs: [] + runs_note). 폴링이 이 기능 때문에 죽으면 안 된다.
- mode 는 index 값 우선, 없으면(pending) runner_config steps 의 step 별 mode.
- 시험은 SmartTwinMCP/.venv 파이썬 + PYTHONPATH=src 로 돌린다(이 리포 venv 에 pytest 없음 — 운영 venv 에 깔지 않음).
- 직접 도구(expose: direct)는 MCP inputSchema 가 일반 `args: object` 하나다. runs 는 inputSchema 가 아니라 설명문과 서버 쪽 args.schema 검사에 나타난다 — 확인은 catalog_describe·실호출로.
