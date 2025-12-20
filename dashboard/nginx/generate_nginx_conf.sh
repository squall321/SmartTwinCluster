#!/bin/bash
################################################################################
# Nginx 설정 파일 동적 생성 스크립트
#
# YAML에서 VIP 주소와 설정을 읽어 nginx 설정 파일을 생성합니다.
#
# 사용법:
#   ./generate_nginx_conf.sh [--yaml PATH] [--output PATH]
#
# 예제:
#   ./generate_nginx_conf.sh
#   ./generate_nginx_conf.sh --yaml ../../my_multihead_cluster.yaml
################################################################################

set -euo pipefail

# 기본값
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YAML_PATH="../../my_multihead_cluster.yaml"
OUTPUT_PATH="$SCRIPT_DIR/hpc-portal.conf"
TEMPLATE_PATH="$SCRIPT_DIR/hpc-portal.conf.template"

# 인자 파싱
while [[ $# -gt 0 ]]; do
    case $1 in
        --yaml)
            YAML_PATH="$2"
            shift 2
            ;;
        --output)
            OUTPUT_PATH="$2"
            shift 2
            ;;
        --help)
            echo "사용법: $0 [--yaml PATH] [--output PATH]"
            exit 0
            ;;
        *)
            echo "알 수 없는 옵션: $1"
            exit 1
            ;;
    esac
done

# YAML 파일 확인
if [ ! -f "$YAML_PATH" ]; then
    echo "❌ YAML 파일을 찾을 수 없습니다: $YAML_PATH"
    exit 1
fi

# 외부 접속 주소 읽기 (public_url 우선, 없으면 VIP 사용)
PUBLIC_URL=$(python3 -c "
import yaml
with open('$YAML_PATH') as f:
    config = yaml.safe_load(f)
# 외부 접속 주소 우선
public_url = config.get('web', {}).get('public_url', '')
if public_url:
    print(public_url)
else:
    # 없으면 VIP 사용 (내부 접속용)
    print(config.get('network', {}).get('vip', {}).get('address', 'localhost'))
" 2>/dev/null)

if [ -z "$PUBLIC_URL" ]; then
    echo "⚠️  YAML에서 접속 주소를 찾을 수 없습니다. localhost를 사용합니다."
    PUBLIC_URL="localhost"
fi

echo "📝 Nginx 설정 파일 생성 중..."
echo "  - 외부 접속 주소: $PUBLIC_URL"
echo "  - 출력 경로: $OUTPUT_PATH"

# 기존 설정 백업
if [ -f "$OUTPUT_PATH" ]; then
    BACKUP_PATH="${OUTPUT_PATH}.backup_$(date +%Y%m%d_%H%M%S)"
    cp "$OUTPUT_PATH" "$BACKUP_PATH"
    echo "  - 기존 설정 백업: $BACKUP_PATH"
fi

# 템플릿 파일이 있으면 사용, 없으면 기존 파일에서 IP만 교체
if [ -f "$TEMPLATE_PATH" ]; then
    # 템플릿 사용
    sed "s/{{PUBLIC_URL}}/$PUBLIC_URL/g" "$TEMPLATE_PATH" > "$OUTPUT_PATH"
else
    # 기존 파일에서 IP 교체
    sed "s/110\.15\.177\.120/$PUBLIC_URL/g" "$OUTPUT_PATH" > "${OUTPUT_PATH}.tmp"
    sed "s/10\.179\.100\.100/$PUBLIC_URL/g" "${OUTPUT_PATH}.tmp" > "${OUTPUT_PATH}.tmp2"
    sed "s/server_name [0-9.]\+ localhost/server_name $PUBLIC_URL localhost/" "${OUTPUT_PATH}.tmp2" > "${OUTPUT_PATH}"
    rm -f "${OUTPUT_PATH}.tmp" "${OUTPUT_PATH}.tmp2"
fi

echo "✅ Nginx 설정 파일 생성 완료!"
echo ""
echo "📋 다음 명령으로 Nginx 설정을 적용하세요:"
echo "  sudo nginx -t && sudo systemctl reload nginx"
