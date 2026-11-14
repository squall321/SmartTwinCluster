<!-- 낙하 파이프라인 개선 1번(노드 SIF 배포 안전) 계획 — phase8 --image·deploy_apptainers.sh·phase3 -->
# 노드 SIF 배포 안전 (포털 요청 2026-11-12, KooSlurm 몫 1번)

가지 `feat/dropline-node-deploy`(worktree). cae00 판 고정이 풀릴 때까지 push·병합하지 않는다.
2·3번(읽기 전용 점검 스크립트, 해석기 없는 dev E2E)은 kooslurminstallautomationrefactory-35 세션 몫이다.

## 왜

- `cluster/setup/phase8_containers.sh --image`는 크기만 견줘 같으면 건너뛴다(L1155-1158). 크기가 같은 다른 빌드가
  실제로 있다(Post ff71b03·7bc1f78 둘 다 1,156,497,408 B) → 노드에 옛 빌드가 남는다.
- 같은 경로가 `/tmp`로 받아 `sudo mv`로 옮기는데, node001처럼 `/tmp`가 다른 파일시스템이면 mv가 이름 바꾸기가 아니라
  복사가 된다. 쓰는 중 덮어써 squashfs가 깨진 전례가 있다.
- `deploy_apptainers.sh`는 컨트롤러에 `sudo cp`로 무조건 덮어쓴다(--image L609-612, 일반 L536). cp는 같은 inode를
  잘라 다시 쓰므로 헤드에서 그 SIF를 쓰는 프로세스가 깨질 수 있다.
- `apptainer/deploy_compute_images.sh`는 아무도 읽지 않는 `/opt/apptainers/compute`에 쓰고 늘 '완료'를 찍는다.
  `phase3_slurm.sh` Step 16이 이걸 부른다.
- 조사 중 추가로 발견. phase8 일반 경로 L645가 정의되지 않은 `$SCP_OPTS`를 써서(`set -u`) 복사가 필요한 순간 죽고,
  `--image` 결과 집계(L1179)는 `set -e` + `((ok++))` 함정으로 첫 성공에서 스크립트가 끝나며, 마지막은 무조건 `exit 0`이다.

## 무엇을

1. **공용 라이브러리 `cluster/utils/sif_deploy_lib.sh`** — 두 배포 스크립트가 같이 쓴다.
   - `sif_atomic_install src dst mtime [sha256] [consume_src]` — 대상 디렉토리와 같은 파일시스템이면 `mv`, 아니면
     대상 디렉토리 안 `dst.part`로 `cp`한 뒤 소유권·권한·mtime(원본 시각)을 맞추고, 선택적으로 sha256을 확인하고,
     `mv -f dst.part dst`(rename, 새 inode)로 교체한다. 실패하면 `.part`를 지우고 기존 파일은 그대로 둔다.
     원격에서는 `declare -f`로 함수를 그대로 보내 실행한다(로컬·원격 구현이 하나).
   - `sif_pick_staging target_dir` — 원격에서 대상과 같은 장치에 있는 쓰기 가능 디렉토리(/scratch, $HOME, /tmp 순)를 고른다.
   - `sif_classify` — 같음 판정. 기본은 **크기와 mtime이 모두 같을 때**(설치 시 mtime을 원본 값으로 맞추므로 성립).
     sha256을 쓰면 크기+sha256으로 판정하고, 내용은 같은데 mtime만 다르면 복사 없이 mtime만 맞춘다.
2. **phase8 `--image`**
   - 판정을 위 규칙으로 바꾸고, 설치를 `sif_atomic_install`로.
   - `--verify-only` — 쓰지 않고 노드별 상태표(OK / MISSING / SIZE / MTIME / SHA256 / UNREACHABLE)를 내고 불일치가 있으면 exit 1.
   - `--sha256`(전 노드) / `--sha256-sample N`(무작위 N대) — 판정과 설치 후 검증에 sha256을 쓴다. 로컬 sha는 한 번만 잰다.
   - 결과 집계 함정 수정, 실패가 있으면 exit 1.
3. **phase8 일반 경로** — L645를 `$SCP_CMD`로(노드별 키→sshpass 폴백 사용), 설치를 `sif_atomic_install`로.
   같음 판정 규칙(`크기 같고 로컬 mtime ≤ 원격`)은 **바꾸지 않는다** — 바꾸면 기존 노드 사본의 mtime이 복사 시각이라
   356대 × 전 이미지가 한 번 다시 복사된다. 설치 때 mtime을 원본 값으로 맞추므로 이후 판정은 그대로 맞는다.
4. **deploy_apptainers.sh** — 컨트롤러 사본(일반·--image)을 "같으면 건너뜀 + 원자 교체"로, 노드 설치를 `sif_atomic_install`로.
   --image의 노드 판정도 1의 규칙(크기+mtime 일치)으로. 3번 E2E가 이 스크립트를 쓰므로 바꾸기 전에 -35 세션에 알린다.
5. **deploy_compute_images.sh 막기** — 파일은 gitignore된 `apptainer/` 안의 로컬 파일이라 git으로 지울 수 없다
   (git에 넣으면 운영 pull이 충돌한다). `phase3_slurm.sh` Step 16이 더는 부르지 않게 하고, 파일이 있으면 "레거시, 실행하지 않음 —
   phase8 사용, 삭제 권장" 경고만 남긴다. 각 호스트의 로컬 파일 삭제는 사람 몫으로 안내한다.

## 비범위

- phase3이 phase8을 자동으로 부르게 하는 것(동작 변화가 큼).
- phase8에 컨트롤러 SIF 사본을 새로 추가하는 것 — phase8은 원래 컨트롤러에 SIF를 두지 않는다(헤드노드에는 메타데이터 JSON만).
- 각 호스트에 남은 `deploy_compute_images.sh` 실제 삭제, 실 노드 배포(승인 후).

## 검증

- dev VM 4대가 꺼져 있고 호스트 여유 메모리 30 GiB 규칙 때문에 지금은 실노드 시험을 할 수 없다.
- `cluster/utils/test_sif_deploy.sh` — 로컬 임시 디렉토리로 라이브러리와 phase8 --image 흐름을 시험한다.
  가짜 ssh/scp(로컬 실행)를 써서 원격 명령 경로까지 탄다. 다른 파일시스템은 `/dev/shm`(장치가 다름)으로 재현한다.
- 실노드 검증(`--verify-only`부터)은 포털에 VM 켜기를 청하고 사용자 승인 뒤에 한다.
