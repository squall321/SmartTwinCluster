<!-- 노드 SIF 배포 안전 작업 체크리스트 -->
# 체크리스트 — 노드 SIF 배포 안전

## 라이브러리
- [x] `cluster/utils/sif_deploy_lib.sh` — sif_atomic_install, sif_pick_staging, sif_classify, sif_remote
- [x] 같은 FS(mv) / 다른 FS(cp→.part→rename) 두 경로
- [x] mtime을 원본 값으로 맞춤, 선택 sha256 확인, 실패 시 .part 정리
- [x] 컨트롤러용: 원본을 지우지 않는 모드, src와 dst가 같은 파일이면 건너뜀

## phase8 --image
- [x] 판정 크기+mtime 일치(기본) / 크기+sha256(--sha256, --sha256-sample N)
- [x] 설치를 sif_atomic_install로, 스테이징은 대상과 같은 FS 우선
- [x] --verify-only 상태표 + 불일치 시 exit 1
- [x] 결과 집계 `set -e`+`((ok++))` 함정 수정, 실패 시 exit 1
- [x] 도움말·헤더 주석 갱신

## phase8 일반 경로
- [x] L645 `$SCP_OPTS`(미정의) → `$SCP_CMD`
- [x] 설치를 sif_atomic_install로(판정 규칙은 유지)

## deploy_apptainers.sh
- [x] 바꾸기 전 -35 세션에 동작 변화 알림
- [x] 컨트롤러 사본(--image, 일반 viz) 같으면 건너뜀 + 원자 교체
- [x] 노드 설치 sif_atomic_install, --image 판정 크기+mtime 일치

## deploy_compute_images.sh
- [x] phase3_slurm.sh Step 16 호출 제거 + 레거시 경고

## 검증
- [x] `bash -n` 전 파일
- [x] `cluster/utils/test_sif_deploy.sh` 통과(62개 — 같은 FS, 다른 FS, 롤백 판정, 열린 fd 보존, sha 불일치 중단, 컨트롤러 모드, phase8 --image·--verify-only·--sha256, phase8 일반 경로, deploy_apptainers 도우미)
- [ ] (승인 후) dev VM에서 --verify-only, 이어서 실배포

## 마무리
- [ ] 논리 단위로 커밋(가지에만)
- [ ] 포털·-35에 결과 알림, 각 호스트 로컬 deploy_compute_images.sh 삭제 안내
