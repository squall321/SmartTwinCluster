#!/bin/bash
################################################################################
# apt_packages에서 각 패키지의 최신 버전만 골라 1GB 분할 tar.gz로 압축
#
# 사용:
#   sudo ./pack_latest_only.sh                 # apt_packages 전체에서 최신만
#   sudo ./pack_latest_only.sh --updated-only  # 같은 패키지에 2개 이상 버전 있는 것만
################################################################################
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; RED='\033[0;31m'; NC='\033[0m'
[[ $EUID -ne 0 ]] && { echo -e "${RED}sudo 필요${NC}"; exit 1; }

UPDATED_ONLY=false
[[ "$1" == "--updated-only" ]] && UPDATED_ONLY=true

APT_DIR="${SCRIPT_DIR}/apt_packages"
[ ! -d "$APT_DIR" ] && { echo -e "${RED}apt_packages 없음${NC}"; exit 1; }

TS=$(date +%Y%m%d_%H%M%S)
OUT_DIR="${SCRIPT_DIR}/dist"
mkdir -p "$OUT_DIR"
FILELIST="${OUT_DIR}/latest_only_${TS}.txt"

# 각 .deb 파일명 → "패키지명_아키" 그룹화, 그룹 내 최신 버전(dpkg --compare-versions)만 선택
echo -e "${BLUE}🔍 패키지별 최신 버전 선별 중 (총 $(ls "$APT_DIR"/*.deb 2>/dev/null | wc -l)개)...${NC}"

python3 - "$APT_DIR" "$FILELIST" "$UPDATED_ONLY" <<'PYEOF'
import os, sys, subprocess, re
from collections import defaultdict

apt_dir, out_file, updated_only_str = sys.argv[1], sys.argv[2], sys.argv[3]
updated_only = updated_only_str == "true"

# 패턴: <pkg>_<version>_<arch>.deb
pat = re.compile(r'^(.+?)_([^_]+)_([^_]+)\.deb$')
groups = defaultdict(list)  # (pkg, arch) -> [(version, fname), ...]

for f in os.listdir(apt_dir):
    m = pat.match(f)
    if not m: continue
    pkg, ver, arch = m.group(1), m.group(2), m.group(3)
    ver = ver.replace('%3a', ':')  # URL-encoded epoch
    groups[(pkg, arch)].append((ver, f))

def vcmp(a, b):
    # dpkg --compare-versions a gt b → return 1 if a>b
    r = subprocess.run(['dpkg', '--compare-versions', a, 'gt', b], capture_output=True)
    return r.returncode == 0

selected = []
for (pkg, arch), vlist in groups.items():
    if updated_only and len(vlist) < 2:
        continue
    # 최신 버전 찾기
    best = vlist[0]
    for v in vlist[1:]:
        if vcmp(v[0], best[0]):
            best = v
    selected.append(f"apt_packages/{best[1]}")

selected.sort()
with open(out_file, 'w') as f:
    f.write('\n'.join(selected) + '\n')
print(f"선별: {len(selected)}개 (전체 그룹 {len(groups)}개)")
PYEOF

COUNT=$(wc -l < "$FILELIST")
TOTAL=$(du -cb $(sed 's|^|'"$SCRIPT_DIR"/'|' "$FILELIST" 2>/dev/null) 2>/dev/null | tail -1 | awk '{print $1}')
echo -e "${YELLOW}  → 최종 ${COUNT}개, $(numfmt --to=iec ${TOTAL:-0})${NC}"
[ "$COUNT" -eq 0 ] && { echo "대상 없음"; exit 0; }

# 패치 적용 스크립트(tar에 포함될 것) 생성
PATCH_SH="${SCRIPT_DIR}/apt_packages/apply_patch.sh"
cat > "$PATCH_SH" <<'PATCHEOF'
#!/bin/bash
# 패치 tar 풀고 난 뒤 실행: 로컬 APT 저장소 인덱스 재생성 + apt update
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
[[ $EUID -ne 0 ]] && { echo "❌ sudo 필요: sudo $0"; exit 1; }
echo "📂 위치: $SCRIPT_DIR"
echo "🔧 dpkg-dev 확인..."
command -v dpkg-scanpackages >/dev/null || apt-get install -y --no-download --ignore-missing dpkg-dev 2>/dev/null \
    || dpkg -i $(ls /var/cache/apt/archives/dpkg-dev*.deb 2>/dev/null | tail -1) 2>/dev/null || true
echo "📦 Packages 인덱스 재생성..."
dpkg-scanpackages . /dev/null > Packages
gzip -9c Packages > Packages.gz
chmod 644 Packages Packages.gz
echo "🔄 apt-get update..."
REPO_LIST="/etc/apt/sources.list.d/offline-local.list"
if [ ! -f "$REPO_LIST" ]; then
    echo "deb [trusted=yes] file://$SCRIPT_DIR ./" | tee "$REPO_LIST" >/dev/null
fi
apt-get update -o Dir::Etc::sourcelist="$REPO_LIST" \
    -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" 2>/dev/null \
    || apt-get update
echo "✅ 패치 적용 완료. 이제 apt install <pkg> 시 최신 버전 .deb 사용 가능"
echo ""
echo "예시 검증:"
echo "  apt-cache policy libcurl4t64 libc6 python3.12 | grep -A1 ^[a-z]"
PATCHEOF
chmod +x "$PATCH_SH"

# 파일 목록에 패치 스크립트 추가
echo "apt_packages/apply_patch.sh" >> "$FILELIST"

PREFIX="${OUT_DIR}/offline_2404_latest_${TS}.tar.gz.part-"
echo -e "${BLUE}📦 압축 → ${PREFIX}*${NC}"
tar -C "$SCRIPT_DIR" -cf - -T "$FILELIST" \
    | gzip -1 \
    | split --bytes=1G --numeric-suffixes=0 --suffix-length=3 - "$PREFIX"

( cd "$OUT_DIR" && sha256sum offline_2404_latest_${TS}.tar.gz.part-* > "offline_2404_latest_${TS}.sha256" )

ORIG_USER="${SUDO_USER:-koopark}"
chown -R "$ORIG_USER":"$ORIG_USER" "$OUT_DIR" 2>/dev/null || true

echo ""
echo -e "${GREEN}✅ 완료${NC}"
ls -lh "$OUT_DIR"/offline_2404_latest_${TS}*
cat <<INFO

🔗 오프라인 서버에서:
   cd offline_packages_2404
   cat dist/offline_2404_latest_${TS}.tar.gz.part-* | tar -xzf -
   sudo ./apt_packages/apply_patch.sh    # Packages.gz 재생성 + apt update
   # 이후 sudo apt install <pkg> 가 최신 .deb 자동 사용
INFO
