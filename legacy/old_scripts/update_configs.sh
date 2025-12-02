#!/bin/bash
# 모든 설정 파일에 누락된 섹션을 추가하는 스크립트

echo "======================================"
echo "설정 파일 업데이트 스크립트"
echo "======================================"
echo ""

# 템플릿 디렉토리
TEMPLATE_DIR="templates"
EXAMPLE_DIR="examples"

# 추가할 섹션들
INSTALLATION_SECTION='
# 설치 방법 설정
installation:
  install_method: "package"  # package (권장) 또는 source
  offline_mode: false
  package_cache_path: "/var/cache/slurm_packages"
  compile_options: "--with-pmix --with-hwloc"
'

TIME_SYNC_SECTION='
# 시간 동기화 설정
time_synchronization:
  enabled: true
  ntp_servers:
    - "time.google.com"
    - "pool.ntp.org"
  timezone: "Asia/Seoul"
'

echo "✅ 누락된 섹션을 찾아 추가합니다..."
echo ""

# 백업 디렉토리 생성
BACKUP_DIR="config_backups_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "📁 백업 디렉토리: $BACKUP_DIR"
echo ""

# 모든 YAML 파일 처리
for file in "$TEMPLATE_DIR"/*.yaml "$EXAMPLE_DIR"/*.yaml; do
    if [ -f "$file" ]; then
        echo "🔍 처리 중: $file"
        
        # 백업 생성
        cp "$file" "$BACKUP_DIR/"
        
        # installation 섹션 확인
        if ! grep -q "^installation:" "$file"; then
            echo "  ➕ installation 섹션 추가"
            # cluster_info 뒤에 추가
            sed -i '/^cluster_info:/,/^[^ ]/{
                /^[^ ]/i\
'"$INSTALLATION_SECTION"'
            }' "$file" 2>/dev/null || {
                # sed -i가 실패하면 다른 방법 시도
                echo "  ⚠️  자동 추가 실패 - 수동 확인 필요"
            }
        else
            echo "  ✓ installation 섹션 존재"
        fi
        
        # time_synchronization 섹션 확인
        if ! grep -q "^time_synchronization:" "$file"; then
            echo "  ➕ time_synchronization 섹션 추가"
            # network 섹션 뒤에 추가
            sed -i '/^network:/,/^[^ ]/{
                /^[^ ]/i\
'"$TIME_SYNC_SECTION"'
            }' "$file" 2>/dev/null || {
                echo "  ⚠️  자동 추가 실패 - 수동 확인 필요"
            }
        else
            echo "  ✓ time_synchronization 섹션 존재"
        fi
        
        # node_type 필드 확인 및 추가
        if grep -q "controller:" "$file" && ! grep -A 10 "controller:" "$file" | grep -q "node_type:"; then
            echo "  ➕ controller node_type 추가"
            sed -i '/controller:/a\    node_type: "controller"' "$file" 2>/dev/null
        fi
        
        # munge_user 필드 확인
        if ! grep -q "munge_user:" "$file"; then
            echo "  ➕ munge_user 필드 추가"
            sed -i '/slurm_gid:/a\  munge_user: "munge"\n  munge_uid: 1002\n  munge_gid: 1002' "$file" 2>/dev/null
        fi
        
        echo ""
    fi
done

echo "======================================"
echo "✅ 업데이트 완료!"
echo "======================================"
echo ""
echo "백업 위치: $BACKUP_DIR"
echo ""
echo "다음 명령으로 변경사항을 확인하세요:"
echo "  diff -u $BACKUP_DIR/2node_example.yaml examples/2node_example.yaml"
echo ""
echo "검증:"
echo "  ./validate_config.py examples/2node_example.yaml"
echo "  ./validate_config.py examples/4node_research_cluster.yaml"
