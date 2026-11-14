#!/bin/bash
# sif_deploy_lib.sh · phase8 --image · deploy_apptainers.sh 도우미를 실제 노드 없이 로컬 임시 디렉토리로 시험한다(가짜 ssh/scp/sudo)
#
# 사용: bash cluster/utils/test_sif_deploy.sh     (root 불필요, 노드·네트워크 불필요)
# 다른 파일시스템은 /dev/shm 으로 재현한다(작업 디렉토리와 장치 번호가 달라야 함).

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/sifdeploy.XXXXXX")
SHM=$(mktemp -d /dev/shm/sifdeploy.XXXXXX)
trap 'rm -rf "$WORK" "$SHM"' EXIT

PASS=0
FAIL=0
ok() { PASS=$((PASS + 1)); echo "  ✓ $1"; }
ng() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; }
expect() { local name="$1"; shift; if "$@"; then ok "$name"; else ng "$name"; fi; }
eq() { [ "$1" = "$2" ] || { echo "      기대 [$2] 실제 [$1]" >&2; return 1; }; }

# 임시 파일이라 root 소유로 바꿀 수 없다 — chown 만 건너뛰고 나머지는 그대로 실행
sudo() { if [ "$1" = chown ]; then return 0; fi; "$@"; }
export -f sudo

# 가짜 ssh/scp — user@host 앞의 옵션은 버리고 로컬에서 실행
mkdir -p "$WORK/bin"
cat > "$WORK/bin/fake_ssh" <<'EOF'
#!/bin/bash
while [ $# -gt 0 ] && [[ "$1" != *@* ]]; do shift; done
shift
exec bash -c "$*"
EOF
cat > "$WORK/bin/fake_scp" <<'EOF'
#!/bin/bash
args=()
for a in "$@"; do case "$a" in -C) ;; -o) skip=1 ;; *) if [ "${skip:-0}" = 1 ]; then skip=0; else args+=("$a"); fi ;; esac; done
exec cp "${args[0]}" "${args[1]#*:}"
EOF
chmod +x "$WORK/bin/fake_ssh" "$WORK/bin/fake_scp"
FAKE_SSH="$WORK/bin/fake_ssh"
FAKE_SCP="$WORK/bin/fake_scp"

[ "$(stat -c %d "$WORK")" != "$(stat -c %d "$SHM")" ] || { echo "WORK 와 /dev/shm 이 같은 장치 — 다른 FS 시험 불가"; exit 2; }

# 같은 크기, 다른 내용의 두 빌드 (포털이 짚은 Post ff71b03·7bc1f78 상황)
mkbuild() { head -c 65536 /dev/zero | tr '\0' "$2" > "$1"; touch -m -d "@$3" "$1"; }

# shellcheck source=sif_deploy_lib.sh
source "$HERE/sif_deploy_lib.sh"

echo "[1] sif_classify"
expect "원격 없음 → MISSING"            eq "$(sif_classify 10 100 "" MISSING)" MISSING
expect "크기 다름 → SIZE"               eq "$(sif_classify 10 100 "" "11 100")" SIZE
expect "크기 같고 mtime 다름 → MTIME"   eq "$(sif_classify 10 100 "" "10 200")" MTIME
expect "크기·mtime 같음 → OK"           eq "$(sif_classify 10 100 "" "10 100")" OK
expect "sha 다름 → SHA256"              eq "$(sif_classify 10 100 aaa "10 100 bbb")" SHA256
expect "sha 같고 mtime 다름 → SHA_OK_MTIME" eq "$(sif_classify 10 100 aaa "10 999 aaa")" SHA_OK_MTIME
# 롤백: 원격에 더 새 빌드(mtime 큼), 로컬은 같은 크기의 옛 빌드 — 옛 규칙(로컬 ≤ 원격이면 같음)은 건너뛰었다
expect "롤백(로컬이 더 오래됨)도 같음이 아님" eq "$(sif_classify 10 100 "" "10 500")" MTIME

echo "[2] sif_atomic_install — 같은 FS, 스테이징 사본 소비"
mkdir -p "$WORK/opt" "$WORK/stage"
mkbuild "$WORK/opt/x.sif" A 1000              # 노드의 기존 사본
mkbuild "$WORK/stage/x.sif" B 2000            # 새 빌드(같은 크기)
old_inode=$(stat -c %i "$WORK/opt/x.sif")
exec 3< "$WORK/opt/x.sif"                     # 교체 전에 열어 둔 사용자
expect "설치 성공"                      sif_atomic_install "$WORK/stage/x.sif" "$WORK/opt/x.sif" 2000
expect "새 내용"                        eq "$(head -c1 "$WORK/opt/x.sif")" B
expect "mtime 을 원본 값으로"           eq "$(stat -c %Y "$WORK/opt/x.sif")" 2000
expect "새 inode (rename 교체)"         test "$(stat -c %i "$WORK/opt/x.sif")" != "$old_inode"
expect "열어 둔 사용자는 옛 내용 그대로" eq "$(head -c1 <&3)" A
exec 3<&-
expect "스테이징 사본 소비됨"           test ! -e "$WORK/stage/x.sif"
expect ".part 남지 않음"                test ! -e "$WORK/opt/x.sif.part"

echo "[3] sif_atomic_install — 다른 FS(/dev/shm → 작업 디렉토리)"
mkbuild "$SHM/x.sif" C 3000
expect "설치 성공"                      sif_atomic_install "$SHM/x.sif" "$WORK/opt/x.sif" 3000
expect "새 내용"                        eq "$(head -c1 "$WORK/opt/x.sif")" C
expect "다른 FS 스테이징 사본도 정리"   test ! -e "$SHM/x.sif"
expect ".part 남지 않음"                test ! -e "$WORK/opt/x.sif.part"

echo "[4] sif_atomic_install — sha256 불일치면 중단, 기존 유지"
mkbuild "$WORK/stage/x.sif" D 4000
t_sha_mismatch() { ! sif_atomic_install "$WORK/stage/x.sif" "$WORK/opt/x.sif" 4000 deadbeef 2>/dev/null; }
expect "실패를 돌려줌"                  t_sha_mismatch
expect "기존 내용 유지"                 eq "$(head -c1 "$WORK/opt/x.sif")" C
expect ".part 정리"                     test ! -e "$WORK/opt/x.sif.part"
mkbuild "$WORK/stage/x.sif" D 4000            # 실패한 스테이징 사본은 소비되므로 다시 받는다
good_sha=$(sha256sum "$WORK/stage/x.sif" | cut -d' ' -f1)
expect "맞는 sha256 이면 설치"          sif_atomic_install "$WORK/stage/x.sif" "$WORK/opt/x.sif" 4000 "$good_sha"
expect "새 내용"                        eq "$(head -c1 "$WORK/opt/x.sif")" D

echo "[5] sif_atomic_install — 컨트롤러 모드(원본 보존), 같은 파일"
mkbuild "$WORK/src.sif" E 5000
expect "설치 성공"                      sif_atomic_install "$WORK/src.sif" "$WORK/opt/x.sif" 5000 "" no
expect "원본 보존"                      test -f "$WORK/src.sif"
expect "새 내용"                        eq "$(head -c1 "$WORK/opt/x.sif")" E
expect "src 와 dst 가 같은 파일이면 그대로 성공" sif_atomic_install "$WORK/opt/x.sif" "$WORK/opt/x.sif" 5000 "" no

echo "[6] sif_pick_staging"
mkdir -p "$WORK/home"
picked=$(HOME="$WORK/home" sif_pick_staging "$WORK/opt")
t_picked_same_fs() { [ "$(stat -c %d "$picked")" = "$(stat -c %d "$WORK/opt")" ]; }
expect "대상과 같은 FS 의 후보 선택"    t_picked_same_fs
picked=$(HOME="$SHM" sif_pick_staging "$WORK/opt")
t_same_fs_first() { [ "$(stat -c %d "$picked")" = "$(stat -c %d "$WORK/opt")" ] || [ "$picked" = "$SHM" ]; }
expect "\$HOME 이 다른 FS 면 같은 FS 후보 우선(없으면 첫 후보)" t_same_fs_first
t_no_space() { local rc=0; HOME="$WORK/home" sif_pick_staging "$WORK/opt" 999999999999999 >/dev/null 2>&1 || rc=$?; [ $rc -eq 2 ]; }
expect "대상 FS 여유가 모자라면 실패(2)" t_no_space

echo "[7] sif_remote (declare -f 로 원격 실행)"
fp=$(sif_remote "$FAKE_SSH" u 127.0.0.1 sif_fingerprint "$WORK/opt/x.sif" no)
expect "크기 mtime"                     eq "$fp" "65536 5000"
fp=$(sif_remote "$FAKE_SSH" u 127.0.0.1 sif_fingerprint "$WORK/opt/x.sif" yes)
expect "sha256 포함"                    eq "${fp##* }" "$(sha256sum "$WORK/opt/x.sif" | cut -d' ' -f1)"
expect "없는 파일 → MISSING"            eq "$(sif_remote "$FAKE_SSH" u 127.0.0.1 sif_fingerprint "$WORK/nope.sif" no)" MISSING
mkdir -p "$WORK/a b"; head -c 3 /dev/zero > "$WORK/a b/c.sif"
expect "공백 들어간 경로도 원격 인자로 전달" eq "$(sif_remote "$FAKE_SSH" u h sif_fingerprint "$WORK/a b/c.sif" no | cut -d' ' -f1)" 3

echo "[8] phase8 --image 흐름 (가짜 노드 1대)"
run_phase8() {
    # phase8 을 source 하면 set -euo pipefail 이 켜지므로 서브셸에서 돌리고 e 는 끈다
    (
        source "$ROOT/cluster/setup/phase8_containers.sh"
        set +e
        LOG_FILE="$WORK/phase8.log"
        CONFIG_PATH="$WORK/cluster.yaml"
        COMPUTE_IMAGES_SOURCE="$WORK/images"
        VIZ_IMAGES_SOURCE="$WORK/no_viz"
        IMAGE_TARGET_DIR="$WORK/node_opt"
        TARGET_IMAGE="p.sif"
        PARALLEL=1
        IMAGE_VERIFY_ONLY="$1"
        IMAGE_SHA_MODE="$2"
        DRY_RUN=false
        setup_node_ssh() { SSH_CMD="$FAKE_SSH"; SCP_CMD="$FAKE_SCP"; return 0; }
        HOME="$WORK/home"
        deploy_single_image > "$WORK/phase8.out" 2>&1
    )
}
status_of() { awk '$1=="nodeA"{print $2}' "$WORK/phase8.out"; }
mkdir -p "$WORK/images" "$WORK/node_opt"
cat > "$WORK/cluster.yaml" <<'EOF'
nodes:
  compute_nodes:
    - hostname: nodeA
      ip_address: 127.0.0.1
      ssh_user: tester
EOF
mkbuild "$WORK/images/p.sif" P 6000

run_phase8 true ""; rc=$?
expect "verify-only: 원격에 없으면 MISSING" eq "$(status_of)" MISSING
expect "verify-only: 불일치면 exit 1"   test $rc -eq 1
expect "verify-only: 아무것도 쓰지 않음" test ! -e "$WORK/node_opt/p.sif"

run_phase8 false ""; rc=$?
expect "배포: DEPLOYED"                 eq "$(status_of)" DEPLOYED
expect "배포: exit 0"                   test $rc -eq 0
expect "배포: mtime 을 원본 값으로"     eq "$(stat -c %Y "$WORK/node_opt/p.sif")" 6000
expect "배포: 스테이징 흔적 없음"       test -z "$(find "$WORK/home" /tmp -maxdepth 1 -name '.p.sif.*incoming' 2>/dev/null)"

run_phase8 false ""
expect "다시 배포: 같으면 SKIP"         eq "$(status_of)" SKIP

mkbuild "$WORK/images/p.sif" Q 5000           # 같은 크기의 옛 빌드로 롤백
run_phase8 true ""; rc=$?
expect "롤백 verify-only: MTIME 으로 잡힘" eq "$(status_of)" MTIME
run_phase8 false ""
expect "롤백 배포: DEPLOYED"            eq "$(status_of)" DEPLOYED
expect "롤백 배포: 내용이 옛 빌드로"    eq "$(head -c1 "$WORK/node_opt/p.sif")" Q

touch -m -d @7777 "$WORK/node_opt/p.sif"      # 내용은 같고 mtime 만 다른 노드 사본(scp -p 없이 복사된 경우)
inode_before=$(stat -c %i "$WORK/node_opt/p.sif")
run_phase8 false all
expect "--sha256: 내용 같으면 MTIME_FIXED" eq "$(status_of)" MTIME_FIXED
expect "--sha256: 복사 없음(inode 그대로)" eq "$(stat -c %i "$WORK/node_opt/p.sif")" "$inode_before"
expect "--sha256: mtime 을 원본 값으로" eq "$(stat -c %Y "$WORK/node_opt/p.sif")" 5000
run_phase8 true all; rc=$?
expect "--sha256 verify-only: OK"       eq "$(status_of)" OK
expect "--sha256 verify-only: exit 0"   test $rc -eq 0

echo "[8b] phase8 일반 경로 deploy_to_node (update 모드, 가짜 노드)"
run_phase8_general() {
    (
        source "$ROOT/cluster/setup/phase8_containers.sh"
        set +e
        LOG_FILE="$WORK/phase8g.log"
        SKIP_INSTALL=true
        DRY_RUN=false
        SIF_DEPLOYMENT_MODE=update
        setup_node_ssh() { SSH_CMD="$FAKE_SSH"; SCP_CMD="$FAKE_SCP"; return 0; }
        setup_node_dirs() { mkdir -p "$4"; }
        HOME="$WORK/home"
        deploy_to_node nodeG 127.0.0.1 tester "$WORK/gsrc" "$WORK/gnode_opt" compute > "$WORK/phase8g.out" 2>&1
    )
}
mkdir -p "$WORK/gsrc"
mkbuild "$WORK/gsrc/g.sif" G 9000
run_phase8_general; rc=$?
expect "일반 경로: 성공(exit 0)"        test $rc -eq 0
expect "일반 경로: 설치됨"              eq "$(head -c1 "$WORK/gnode_opt/g.sif" 2>/dev/null)" G
expect "일반 경로: mtime 원본 값"       eq "$(stat -c %Y "$WORK/gnode_opt/g.sif" 2>/dev/null)" 9000
expect "일반 경로: SCP_OPTS 미정의로 죽지 않음" bash -c '! grep -q "unbound variable" "$1"' _ "$WORK/phase8g.out"
run_phase8_general
expect "일반 경로: 다시 돌리면 up-to-date 로 건너뜀" grep -q "up-to-date" "$WORK/phase8g.out"

echo "[9] deploy_apptainers.sh 도우미 (함수만 떼어 시험)"
source <(sed -n '/^install_image_on_node() {/,/^}/p; /^install_image_on_controller() {/,/^}/p' "$ROOT/deploy_apptainers.sh")
RED="" GREEN="" YELLOW="" NC=""
SSH_OPTS="-o StrictHostKeyChecking=no" SSH_TIMEOUT="-o ConnectTimeout=10" SSH_USER=tester
ssh() { "$FAKE_SSH" "$@"; }
scp() { "$FAKE_SCP" "$@"; }
NODE_IMAGE_PATH="$WORK/ctl_opt"
mkdir -p "$NODE_IMAGE_PATH"
mkbuild "$WORK/images/c.sif" R 8000
t_ctl_deploy() { [[ "$(install_image_on_controller "$WORK/images/c.sif" "")" == DEPLOYED* ]]; }
expect "컨트롤러: 없으면 DEPLOYED"      t_ctl_deploy
expect "컨트롤러: 원본 보존"            test -f "$WORK/images/c.sif"
expect "컨트롤러: 같으면 SKIP"          eq "$(install_image_on_controller "$WORK/images/c.sif" "")" SKIP
touch -m -d @1234 "$NODE_IMAGE_PATH/c.sif"
c_sha=$(sha256sum "$WORK/images/c.sif" | cut -d' ' -f1)
expect "컨트롤러 --sha256: 내용 같으면 MTIME_FIXED" eq "$(install_image_on_controller "$WORK/images/c.sif" "$c_sha")" MTIME_FIXED
NODE_IMAGE_PATH="$WORK/node2_opt"
mkdir -p "$NODE_IMAGE_PATH"
t_node_install() { HOME="$WORK/home" install_image_on_node n1 127.0.0.1 "$WORK/images/c.sif" >/dev/null; }
expect "노드: 원자 교체로 설치"         t_node_install
expect "노드: mtime 원본 값"            eq "$(stat -c %Y "$WORK/node2_opt/c.sif")" 8000
expect "노드: 원본 보존(로컬)"          test -f "$WORK/images/c.sif"

echo ""
echo "결과: 통과 ${PASS}, 실패 ${FAIL}"
[ "$FAIL" -eq 0 ]
