#!/bin/bash
################################################################################
# nginx 도메인 자동 구성 스크립트
#
# 설명:
#   IP + 도메인을 입력하면 nginx 설정의 server_name 을 도메인으로 갱신하고,
#   /etc/hosts 에 IP 도메인 매핑을 추가, 옵션으로 자체서명 SSL 인증서를
#   생성해서 HTTPS 까지 즉시 서빙되도록 한다.
#
# 사용법:
#   sudo ./configure_nginx_domain.sh --ip <서버IP> --domain <도메인> [옵션]
#
# 옵션:
#   --ip IP            서버 공인/사설 IP (필수)
#   --domain DOMAIN    DNS 도메인 (예: stcx.sec.samsung.net) (필수)
#   --conf PATH        nginx site 설정 파일 (기본: /etc/nginx/sites-available/hpc_web_services
#                                              또는 nginx_hpc_web_services.conf 자동 탐색)
#   --ssl              자체서명 SSL 인증서 생성 + 443 listen 추가
#   --ssl-cert PATH    기존 인증서 사용 (--ssl 자동)
#   --ssl-key PATH     기존 키 사용 (--ssl 자동)
#   --no-hosts         /etc/hosts 갱신 스킵
#   --dry-run          변경사항 미리보기만
#   --help             도움말
#
# 예시:
#   sudo ./configure_nginx_domain.sh --ip 10.228.132.74 --domain stcx.sec.samsung.net
#   sudo ./configure_nginx_domain.sh --ip 10.228.132.74 --domain stcx.sec.samsung.net --ssl
#
################################################################################

set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()   { echo -e "${GREEN}[OK]${NC}   $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 기본값
IP=""
DOMAIN=""
CONF_FILE=""
WITH_SSL=false
SSL_CERT=""
SSL_KEY=""
UPDATE_HOSTS=true
DRY_RUN=false

# 인자 파싱
while [[ $# -gt 0 ]]; do
    case $1 in
        --ip)         IP="$2"; shift 2 ;;
        --domain)     DOMAIN="$2"; shift 2 ;;
        --conf)       CONF_FILE="$2"; shift 2 ;;
        --ssl)        WITH_SSL=true; shift ;;
        --ssl-cert)   SSL_CERT="$2"; WITH_SSL=true; shift 2 ;;
        --ssl-key)    SSL_KEY="$2"; WITH_SSL=true; shift 2 ;;
        --no-hosts)   UPDATE_HOSTS=false; shift ;;
        --dry-run)    DRY_RUN=true; shift ;;
        --help|-h)
            # 헤더 주석 블록만 출력 (두 번째 ################ 라인까지)
            awk '
                /^#####/ { hash_count++; next }
                hash_count == 1 && /^#/ { sub(/^# ?/, ""); print }
                hash_count >= 2 { exit }
            ' "$0"
            exit 0
            ;;
        *)
            err "Unknown option: $1"; exit 1
            ;;
    esac
done

# 필수 인자 검증 — 누락 시 전체 도움말 출력
if [[ -z "$IP" || -z "$DOMAIN" ]]; then
    err "--ip 와 --domain 둘 다 필요"
    echo ""
    awk '
        /^#####/ { hash_count++; next }
        hash_count == 1 && /^#/ { sub(/^# ?/, ""); print }
        hash_count >= 2 { exit }
    ' "$0"
    exit 1
fi

# IP 형식 간단 검증
if [[ ! "$IP" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
    err "IP 형식 이상: $IP"
    exit 1
fi

# Root 권한 확인
if [[ $EUID -ne 0 && "$DRY_RUN" != "true" ]]; then
    err "root 권한 필요 (sudo)"
    exit 1
fi

# nginx 설치 확인
if ! command -v nginx &>/dev/null; then
    err "nginx 가 설치되지 않음. 먼저 'sudo apt install -y nginx'"
    exit 1
fi

# CONF_FILE 자동 탐색
if [[ -z "$CONF_FILE" ]]; then
    for candidate in \
        "/etc/nginx/sites-available/hpc_web_services" \
        "/etc/nginx/sites-available/stcx" \
        "/etc/nginx/conf.d/hpc_web_services.conf" \
        "${SCRIPT_DIR}/nginx_hpc_web_services.conf"; do
        if [[ -f "$candidate" ]]; then
            CONF_FILE="$candidate"
            break
        fi
    done
fi

if [[ -z "$CONF_FILE" || ! -f "$CONF_FILE" ]]; then
    err "nginx 설정 파일 못 찾음. --conf 로 지정"
    exit 1
fi

log "설정 정보:"
log "  IP:          $IP"
log "  Domain:      $DOMAIN"
log "  Conf file:   $CONF_FILE"
log "  SSL:         $WITH_SSL"
log "  Update hosts: $UPDATE_HOSTS"
log "  Dry-run:     $DRY_RUN"
echo ""

# ────────────────────────────────────────────────────────────
# 1. /etc/hosts 갱신 (호스트 자체에서 도메인 해석)
# ────────────────────────────────────────────────────────────
update_hosts() {
    local hosts_line="$IP $DOMAIN"
    if grep -qE "^[[:space:]]*$IP[[:space:]]+.*\b$DOMAIN\b" /etc/hosts 2>/dev/null; then
        ok "/etc/hosts 이미 등록됨"
        return
    fi
    # 기존 도메인 라인 있으면 IP 교체, 없으면 추가
    if grep -qE "[[:space:]]+$DOMAIN(\b|$)" /etc/hosts 2>/dev/null; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log "[dry-run] /etc/hosts: '$DOMAIN' 라인 IP 교체 → $IP"
        else
            sed -i.bak -E "s|^[[:space:]]*[0-9.]+([[:space:]]+.*\b$DOMAIN\b)|$IP\1|" /etc/hosts
            ok "/etc/hosts: $DOMAIN IP 교체"
        fi
    else
        if [[ "$DRY_RUN" == "true" ]]; then
            log "[dry-run] /etc/hosts에 추가: $hosts_line"
        else
            echo "$hosts_line" >> /etc/hosts
            ok "/etc/hosts: $hosts_line 추가"
        fi
    fi
}

# ────────────────────────────────────────────────────────────
# 2. nginx 설정의 server_name 갱신
# ────────────────────────────────────────────────────────────
update_server_name() {
    local backup="${CONF_FILE}.bak.$(date +%s)"
    if [[ "$DRY_RUN" != "true" ]]; then
        cp -p "$CONF_FILE" "$backup"
        log "백업: $backup"
    fi

    # server_name 라인 변환
    # - "server_name localhost;" → "server_name <DOMAIN> <IP> localhost;"
    # - "server_name <기존> localhost;" → "server_name <DOMAIN> <기존> localhost;" (중복 제거 후)
    # - 이미 DOMAIN 포함이면 IP만 추가
    local tmp=$(mktemp)
    python3 <<PYEOF > "$tmp"
import re

with open("$CONF_FILE") as f:
    src = f.read()

DOMAIN="$DOMAIN"
IP="$IP"

def fix(match):
    raw = match.group(1).strip().rstrip(';').strip()
    tokens = [t for t in raw.split() if t]
    # 기존 토큰 보존하고 앞에 DOMAIN/IP 추가 (중복 제거)
    final = []
    for t in [DOMAIN, IP] + tokens:
        if t not in final:
            final.append(t)
    return "server_name " + " ".join(final) + ";"

new = re.sub(r"server_name\s+([^;]+);", fix, src)
print(new, end='')
PYEOF

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[dry-run] server_name 변경 결과:"
        grep -n "server_name" "$tmp" | head -5
    else
        mv "$tmp" "$CONF_FILE"
        ok "server_name 에 $DOMAIN $IP 추가"
        grep -n "server_name" "$CONF_FILE" | head -5
    fi
    [[ -f "$tmp" ]] && rm -f "$tmp"
}

# ────────────────────────────────────────────────────────────
# 3. SSL 설정 (자체서명 또는 기존 인증서)
# ────────────────────────────────────────────────────────────
setup_ssl() {
    [[ "$WITH_SSL" != "true" ]] && return

    local cert_dir="/etc/nginx/ssl"
    local cert_path key_path
    if [[ -n "$SSL_CERT" && -n "$SSL_KEY" ]]; then
        cert_path="$SSL_CERT"; key_path="$SSL_KEY"
        log "기존 SSL 사용: $cert_path / $key_path"
    else
        cert_path="$cert_dir/$DOMAIN.crt"
        key_path="$cert_dir/$DOMAIN.key"
        if [[ "$DRY_RUN" == "true" ]]; then
            log "[dry-run] 자체서명 인증서 생성 예정: $cert_path"
        else
            mkdir -p "$cert_dir"
            openssl req -x509 -nodes -days 730 -newkey rsa:2048 \
                -keyout "$key_path" -out "$cert_path" \
                -subj "/CN=$DOMAIN" \
                -addext "subjectAltName=DNS:$DOMAIN,IP:$IP" 2>/dev/null
            chmod 600 "$key_path"; chmod 644 "$cert_path"
            ok "자체서명 인증서 생성: $cert_path (730일)"
        fi
    fi

    # nginx config에 443 listen 블록 보장
    if grep -qE "^[[:space:]]*listen[[:space:]]+443" "$CONF_FILE" 2>/dev/null; then
        ok "443 listen 이미 있음 — 인증서 경로만 확인"
        return
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[dry-run] 443 listen + SSL 블록 추가 예정"
        return
    fi

    # 가장 첫 번째 'listen 80;' 다음 줄에 443 listen + SSL 옵션 삽입
    sed -i "/^[[:space:]]*listen[[:space:]]\+80;/a\\
    listen 443 ssl;\\
    ssl_certificate $cert_path;\\
    ssl_certificate_key $key_path;\\
    ssl_protocols TLSv1.2 TLSv1.3;\\
    ssl_ciphers HIGH:!aNULL:!MD5;\\
    ssl_prefer_server_ciphers on;" "$CONF_FILE"
    ok "443 listen + SSL 블록 추가"
}

# ────────────────────────────────────────────────────────────
# 4. sites-enabled 심볼릭링크 + nginx 테스트/리로드
# ────────────────────────────────────────────────────────────
enable_and_reload() {
    # sites-available 에 있으면 sites-enabled 에 심링크
    if [[ "$CONF_FILE" =~ /sites-available/ ]]; then
        local base=$(basename "$CONF_FILE")
        local enabled="/etc/nginx/sites-enabled/$base"
        if [[ ! -L "$enabled" && "$DRY_RUN" != "true" ]]; then
            ln -sf "$CONF_FILE" "$enabled"
            ok "심볼릭링크: $enabled → $CONF_FILE"
        fi
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[dry-run] nginx -t 및 reload 스킵"
        return
    fi

    log "nginx 설정 검증 중..."
    if nginx -t 2>&1 | sed 's/^/  /'; then
        ok "nginx -t 통과"
    else
        err "nginx -t 실패 — 백업으로 복원 가능: $(ls -t "${CONF_FILE}".bak.* 2>/dev/null | head -1)"
        return 1
    fi

    log "nginx reload..."
    if systemctl reload nginx 2>/dev/null; then
        ok "nginx reload 완료"
    else
        warn "systemctl reload 실패 — restart 시도"
        systemctl restart nginx && ok "nginx restart 완료" || err "nginx restart 실패"
    fi
}

# ────────────────────────────────────────────────────────────
# 실행
# ────────────────────────────────────────────────────────────
[[ "$UPDATE_HOSTS" == "true" ]] && update_hosts
update_server_name
setup_ssl
enable_and_reload

echo ""
ok "구성 완료"
log "검증:"
log "  curl -k http://$DOMAIN/   (또는 https:// 사용 시)"
log "  curl -kI http://$IP/      (IP 직접)"
log "  systemctl status nginx"
[[ "$WITH_SSL" == "true" ]] && \
    log "  ⚠️  자체서명 인증서면 브라우저 경고 — '안전하지 않음' 진행으로 접속"
