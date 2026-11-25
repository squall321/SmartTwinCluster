<!-- C-1: job_status 에 전각도 낙하 잡의 각도별 run 폴더·d3plot 경로를 싣는 계획 -->
# 계획 — job_status `runs` (낙하 트윈 계약 C-1, 2026-11-25)

## 요청
DynaForge(KooRemapper) `docs/requests/smarttwinmcp-c1-run-paths-2026-10-28.md` — 전각도 낙하 잡 결과에 각도마다
run 폴더·d3plot 경로·상태를 실어 달라. 실패한 각도도 상태와 함께. 꼴은 제안이고 정하는 것은 이쪽.

## 사용자 결정 (10-28)
- 싣는 곳: `job_status` 의 선택 인자 `runs: true` 일 때만. 기본 응답은 그대로(KR-10 이 고정하려는 상태 칸·폴링 크기 보호).
- 지금 구현.

## 출처 (파일 둘, run 폴더를 하나씩 열지 않는다)
- `runner_config.json` → `scenario.doe_angles[DOE][step] = {angle_name, roll, pitch, yaw}` — 계획된 모든 각도.
- `<registry output_dir>/simulation_index.json` → `scenarios[0].runs[별칭] = {run_id, status, folder, condition, error}`.
  별칭 `<project>_CUM<n>_DOE<ddd>_S<sss>_<MODE>_<condition>` 에서 DOE·step 을 뽑아 잇는다.

## 꼴
`runs: [{doe, step, mode, case_key, angle{name,roll,pitch,yaw}, run_dir, d3plot, status, error?}]` (doe·step 순)
- `status`: KooChainRun 값 그대로(running/completed/failed). index 에 없으면 `pending`.
- `d3plot`: `<run_dir>/Output/d3plot` 이 있을 때만 경로, 없으면 null.
- `states` 는 싣지 않는다(d3plot 가족 파일을 읽어야 함 — 요청서도 모르면 빼라 함).
- 각도 DOE 가 아닌 잡(doe_angles 없음)·index 없음은 `runs: []` + `runs_note`.

## 범위 밖
runs.json 파일 쓰기, states, 재시도 이전 Run 폴더(index 가 마지막 시도로 덮어씀), KR-10(저쪽 첫 stcx 제출 원문 필요).
