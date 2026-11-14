#!/bin/bash
# SIF 이미지를 노드·컨트롤러에 안전하게 까는 공용 함수 — 같은 FS 스테이징 + rename 원자 교체 (phase8·deploy_apptainers.sh 가 source)
#
# 왜 원자 교체인가:
#   cp 로 기존 SIF 를 덮어쓰면 같은 inode 를 잘라 다시 쓰므로, 그 SIF 를 열거나 마운트한 프로세스의 squashfs 가 깨진다.
#   대상 디렉토리 안의 <dst>.part 를 다 만든 뒤 mv -f(rename) 로 바꾸면 새 inode 가 되고, 기존 사용자는 옛 inode 를 계속 본다.
#   스테이징이 다른 파일시스템이면 mv 가 복사로 바뀌므로, 그때는 대상 디렉토리 안으로 cp 해서 .part 를 만든다.
#
# 같음 판정 (sif_classify):
#   기본은 크기와 mtime 이 모두 같을 때. sif_atomic_install 이 mtime 을 원본 값으로 맞추므로 설치 뒤에는 성립한다.
#   "로컬 mtime ≤ 원격" 규칙은 같은 크기의 더 오래된 빌드로 되돌릴 때(롤백) 건너뛰어 쓰지 않는다.
#   sha256 을 쓰면 크기+sha256 으로 판정하고, 내용은 같은데 mtime 만 다르면 SHA_OK_MTIME 을 돌려준다(복사 불필요).
#
# 원격 실행:
#   sif_remote "$SSH_CMD" user ip <함수> <인자...>
#   함수 정의를 declare -f 로 그대로 보내 원격 bash 에서 실행한다(ssh -n 이라 stdin 으로 스크립트를 못 보냄).
#   원격 로그인 셸은 bash 여야 한다(클러스터 계정은 /bin/bash).

# 원격·로컬 공통 함수 목록 — sif_remote 가 이 함수들을 원격으로 보낸다.
SIF_REMOTE_FUNCS=(sif_fingerprint sif_pick_staging sif_atomic_install sif_set_mtime)

# 파일의 "크기 mtime [sha256]" 를 출력. 없으면 "MISSING". want_sha=yes 면 sha256 도.
sif_fingerprint() {
    local path="$1" want_sha="${2:-no}" st sha
    st=$(sudo stat -c '%s %Y' -- "$path" 2>/dev/null) || { echo "MISSING"; return 0; }
    if [ "$want_sha" = yes ]; then
        sha=$(sudo sha256sum -- "$path" 2>/dev/null | cut -d' ' -f1)
        echo "$st ${sha:-?}"
    else
        echo "$st"
    fi
}

# 대상 디렉토리와 같은 장치에 있는 쓰기 가능 스테이징 디렉토리를 골라 출력한다(/scratch, $HOME, /tmp 순).
# 같은 장치가 없으면 첫 쓰기 가능 후보 — /scratch 를 앞에 둬서 NFS 일 수 있는 홈보다 로컬 디스크를 먼저 쓴다.
# 스테이징이 노드 간 공유 FS 일 수 있으므로 호출부는 파일 이름에 대상 노드 이름을 넣는다. need_bytes 가 주어지면 여유 공간을 확인한다 —
# 교체 순간에는 옛 사본과 새 사본이 대상 FS 에 같이 있으므로 대상 FS 에 need_bytes 가 더 필요하다.
sif_pick_staging() {
    local target_dir="$1" need="${2:-0}" tdev c pick="" fallback="" tavail savail
    sudo mkdir -p -- "$target_dir" || { echo "sif_pick_staging: 대상 디렉토리 생성 실패: $target_dir" >&2; return 1; }
    tdev=$(stat -c %d -- "$target_dir" 2>/dev/null || sudo stat -c %d -- "$target_dir")
    for c in /scratch "$HOME" /tmp; do
        [ -n "$c" ] && [ -d "$c" ] && [ -w "$c" ] || continue
        [ -z "$fallback" ] && fallback="$c"
        if [ "$(stat -c %d -- "$c")" = "$tdev" ]; then pick="$c"; break; fi
    done
    [ -z "$pick" ] && pick="$fallback"
    [ -n "$pick" ] || { echo "sif_pick_staging: 쓰기 가능한 스테이징 디렉토리 없음" >&2; return 1; }
    if [ "$need" -gt 0 ] 2>/dev/null; then
        tavail=$(df --output=avail -B1 -- "$target_dir" 2>/dev/null | tail -1 | tr -d ' ')
        if [ -n "$tavail" ] && [ "$tavail" -lt "$need" ]; then
            echo "sif_pick_staging: 대상 FS 여유 부족 ($target_dir 여유 ${tavail}B < 필요 ${need}B)" >&2
            return 2
        fi
        if [ "$(stat -c %d -- "$pick")" != "$tdev" ]; then
            savail=$(df --output=avail -B1 -- "$pick" 2>/dev/null | tail -1 | tr -d ' ')
            if [ -n "$savail" ] && [ "$savail" -lt "$need" ]; then
                echo "sif_pick_staging: 스테이징 FS 여유 부족 ($pick 여유 ${savail}B < 필요 ${need}B)" >&2
                return 2
            fi
        fi
    fi
    echo "$pick"
}

# src 를 dst 로 원자 교체한다. 실패하면 dst 는 그대로이고 <dst>.part 는 지운다.
#   mtime       설치본에 맞출 원본 mtime(epoch 초)
#   want_sha    비어 있지 않으면 .part 의 sha256 을 확인하고 다르면 중단
#   consume_src yes(기본) — 스테이징 사본이라 옮기거나 지워도 됨 / no — 원본 보존(컨트롤러)
sif_atomic_install() {
    local src="$1" dst="$2" mtime="$3" want_sha="${4:-}" consume="${5:-yes}" dir part got
    dir=$(dirname -- "$dst")
    part="${dst}.part"
    [ -f "$src" ] || { echo "sif_atomic_install: 원본 없음: $src" >&2; return 10; }
    if [ -e "$dst" ] && [ "$src" -ef "$dst" ]; then return 0; fi
    sudo mkdir -p -- "$dir" || return 11
    sudo rm -f -- "$part"
    if [ "$consume" = yes ] && [ "$(stat -c %d -- "$src")" = "$(stat -c %d -- "$dir" 2>/dev/null || sudo stat -c %d -- "$dir")" ]; then
        sudo mv -f -- "$src" "$part" || return 12
    else
        sudo cp -- "$src" "$part" || { sudo rm -f -- "$part"; return 13; }
        [ "$consume" = yes ] && rm -f -- "$src"
    fi
    if ! { sudo chown root:root -- "$part" && sudo chmod 755 -- "$part" && sudo touch -m -d "@${mtime}" -- "$part"; }; then
        sudo rm -f -- "$part"; return 14
    fi
    if [ -n "$want_sha" ]; then
        got=$(sudo sha256sum -- "$part" | cut -d' ' -f1)
        if [ "$got" != "$want_sha" ]; then
            echo "sif_atomic_install: sha256 불일치 (기대 $want_sha, 실제 $got)" >&2
            sudo rm -f -- "$part"; return 15
        fi
    fi
    sudo mv -f -- "$part" "$dst" || { sudo rm -f -- "$part"; return 16; }
}

# 내용은 같고 mtime 만 다를 때 복사 없이 mtime 만 맞춘다.
sif_set_mtime() {
    local path="$1" mtime="$2"
    sudo touch -m -d "@${mtime}" -- "$path"
}

# 로컬 파일의 "크기 mtime" 출력.
sif_local_stat() {
    stat -c '%s %Y' -- "$1"
}

# 로컬 지문(크기 mtime [sha])과 원격 지문(sif_fingerprint 출력)을 견줘 상태를 출력한다.
#   OK            같음
#   SHA_OK_MTIME  sha256 은 같고 mtime 만 다름(복사 불필요, mtime 만 맞추면 됨)
#   MISSING       원격에 없음
#   SIZE          크기 다름
#   MTIME         크기는 같고 mtime 다름(sha 를 안 쟀으므로 다른 빌드일 수 있음)
#   SHA256        크기는 같고 sha256 다름
sif_classify() {
    local lsize="$1" lmtime="$2" lsha="$3" remote="$4" rsize rmtime rsha
    if [ "$remote" = "MISSING" ] || [ -z "$remote" ]; then echo MISSING; return; fi
    read -r rsize rmtime rsha <<< "$remote"
    if [ "$lsize" != "$rsize" ]; then echo SIZE; return; fi
    if [ -n "$lsha" ]; then
        if [ "$lsha" != "${rsha:-}" ]; then echo SHA256; return; fi
        if [ "$lmtime" != "$rmtime" ]; then echo SHA_OK_MTIME; return; fi
        echo OK; return
    fi
    if [ "$lmtime" != "$rmtime" ]; then echo MTIME; return; fi
    echo OK
}

# 원격에서 라이브러리 함수를 실행한다. ssh_cmd 는 공백으로 나뉘는 명령 문자열(기존 스크립트의 $SSH_CMD 그대로).
#   sif_remote "$SSH_CMD" stcx 10.0.0.5 sif_fingerprint /opt/apptainers/x.sif yes
sif_remote() {
    local ssh_cmd="$1" user="$2" ip="$3" fn="$4"
    shift 4
    local script
    script="$(declare -f "${SIF_REMOTE_FUNCS[@]}"); $fn $(printf '%q ' "$@")"
    # shellcheck disable=SC2086  # ssh_cmd 는 의도적으로 단어 분리
    # 스크립트는 인자로 보내므로 stdin 은 막는다 — 호출부의 while-read 입력을 ssh 가 먹지 않게
    $ssh_cmd "${user}@${ip}" "$script" </dev/null
}
