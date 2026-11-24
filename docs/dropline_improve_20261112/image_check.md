# 읽기 전용 이미지 점검 — `cluster/utils/image_version_check.sh`

**읽는 사람** cae00 에서 stcx(운영 헤드) 이미지 판을 확인하는 운영자·포털 세션.
**하는 일** 헤드·표본 노드·NFS 의 SmartTwin Pre/Post 판을 기대값과 대조해 markdown 표로 낸다. **아무것도 설치·변경하지 않는다.**

## 붙여넣기(현재 목표: Pre v141 · Post v54 — cae00 에 깔라고 안내한 판)

```bash
ssh stcx 'EXPECT_PRE_SHA=9b81405bbc1fd2cc870af2ee1b219c793e5bc07dfcc85353e77547425406efcc \
          EXPECT_POST_SHA=bbaa491b45cc07d99ca1551338e47f8aaf692f7b75f16ccc47e2a31cd3c3b368 \
          EXPECT_POST_VERSION=da81ad3 \
          EXPECT_REMAPPER_COMMIT=faf758b8770e9e515170afbae825b2578fa1baad \
          EXPECT_KCR_SHA=1170561e80a4181a58696cd2eb75a2f148bdfd05fa69ea6eda191bf881287888 \
          bash -s' < cluster/utils/image_version_check.sh
```

기대값 출처(2026-11-24): Pre·Post SIF sha256 과 Post VERSION 은 포털이 준 v141·v54 값이고, dev 헤드(smarttwincluster) 실측과 같다.
KooRemapper 커밋·KooChainRun.bin sha256 은 dev 헤드 v141 실측(NFS 사본과 SIF 안 사본이 같다, KooChainRun md5 `03eae3654ce29acbc7ceaf2766abd388`).
Post GUI SIF(`SmartTwinPostprocessorGUI.sif`, 스크립트가 보지 않음)는 `6025f32f23c293031b4695c95b83452bc24f6184272dd0d789d19c53701bab6a` 로 포털 값과 같다.
판이 바뀌면 이 다섯 값만 바꾼다. 앞 판(v136·v51, 11-12)은 Pre `1c973c25…`·Post `32997e9b…`·VERSION `226eca7` 이었다.
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
  11-24 v141·v54 값으로 다시 돌려 헤드·NFS 전 항목 OK.
- MCP 에서도 부를 수 있다 — smarttwin_mcp `image_version_check` 도구(같은 스크립트를 감싼다, 인자 `expect_*`·`nodes`·`node_sha`).
