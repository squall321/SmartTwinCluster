# 읽기 전용 이미지 점검 — `cluster/utils/image_version_check.sh`

**읽는 사람** cae00 에서 stcx(운영 헤드) 이미지 판을 확인하는 운영자·포털 세션.
**하는 일** 헤드·표본 노드·NFS 의 SmartTwin Pre/Post 판을 기대값과 대조해 markdown 표로 낸다. **아무것도 설치·변경하지 않는다.**

## 붙여넣기(현재 목표: Pre v136 · Post v51)

```bash
ssh stcx 'EXPECT_PRE_SHA=1c973c25dc140dd934567d20033469632e89673246a96241a8d281716a8be70a \
          EXPECT_POST_SHA=32997e9b6efb1fdc36737a1f9706a3156bee0a7256a6fe9382135495182ada24 \
          EXPECT_POST_VERSION=226eca7 \
          EXPECT_REMAPPER_COMMIT=e6407dcda8d02727c978c55143608878098d1acd \
          EXPECT_KCR_SHA=35511107d417d202ffdf6f3fd19d9646752f39e3c6ce36f59429705097af289b \
          bash -s' < cluster/utils/image_version_check.sh
```

기대값은 dev 헤드(smarttwincluster)의 v136·v51 실물에서 읽었다(2026-11-12). 판이 바뀌면 이 다섯 값만 바꾼다.
앞 8자 이상이면 접두 일치로 판정한다.

| 변수 | 무엇 | 어디서 |
|---|---|---|
| `EXPECT_PRE_SHA` | `SmartTwinPreprocessor.sif` sha256 | 헤드·노드 `/opt/apptainers/` |
| `EXPECT_POST_SHA` | `SmartTwinPostprocessor.sif` sha256 | 헤드·노드 `/opt/apptainers/` |
| `EXPECT_POST_VERSION` | KooD3plotReader 커밋(`Version:`) | Post SIF 안 `/opt/kood3plot/VERSION`, NFS `/data/SmartTwinPostprocessor/VERSION` |
| `EXPECT_REMAPPER_COMMIT` | KooRemapper 소스 커밋 | Pre SIF 안 `/opt/kooremapper/bin/KooRemapper.BUILD_INFO.txt` |
| `EXPECT_KCR_SHA` | `KooChainRun.bin` sha256 | Pre SIF 안 `/opt/SmartTwinPreprocessor/lib/KooChainRun/`, NFS `/data/SmartTwinPreprocessor/lib/KooChainRun/` |

## 출력

`| 위치 | 항목 | 실제 | 기대 | 판정 |` 표 한 장과 끝줄 요약. 판정은 `OK` · `DIFF`(기대와 다름) · `ERR`(읽지 못함 — 파일 없음, ssh 불가) · `-`(기대값 없음).
종료 코드는 DIFF·ERR 가 하나라도 있으면 1. KooChainRun 은 md5 도 함께 보인다(옛 메모가 md5 `c556a678` 꼴로 적은 판이 있다).

## 선택

| 변수 | 기본 | 뜻 |
|---|---|---|
| `NODES` | (비움) | 표본 노드를 직접 준다(`"icn401-0101-h01 icn401-0201-h01"`). 비우면 `sinfo -t idle,mix,alloc` 로 파티션마다 하나 |
| `SAMPLE_PER_PARTITION` | 1 | 자동 표본 수(파티션당) |
| `SSH_USER` | 현재 사용자 | 노드 ssh 사용자. 운영 YAML(346)은 노드 전부 `koopark` |
| `NODE_SHA` | 1 | 0 이면 노드 SIF 는 크기·시각만(빠름). sha256 은 노드당 두 SIF 에 수십 초 |

## 알아 둘 것

- 표준입력으로 도는 스크립트라 안의 `ssh`·`apptainer` 는 모두 `-n`/`</dev/null` 로 막았다 — 그러지 않으면 스크립트 나머지를 먹는다.
- `/data/apptainers/SmartTwinPreprocessor.sif` 는 7월 사본이라 보지 않는다(쓰는 스크립트가 없다).
- SIF 안에는 v 번호가 없다(v136·v51 은 tar 이름에만 있다) — 판은 sha·커밋으로 본다.
- dev 박스에서 돌려 보았다: 표준입력 실행 모든 항목 OK(6초), 틀린 기대값 → DIFF·종료 1, 닿지 않는 노드 → ERR·종료 1.
