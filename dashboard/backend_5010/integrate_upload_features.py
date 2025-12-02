#!/usr/bin/env python3
"""
app.py에 업로드/다운로드 및 성능 최적화 기능을 통합하는 스크립트
"""

import os
import sys

APP_PY_PATH = "/home/koopark/claude/KooSlurmInstallAutomation/dashboard/backend/app.py"
BACKUP_PATH = f"{APP_PY_PATH}.backup_before_upload_integration"

# 추가할 코드
INTEGRATION_CODE = '''
# ==================== 파일 업로드/다운로드 통합 ====================

from upload_api import upload_bp

# Blueprint 등록
app.register_blueprint(upload_bp)

print("  📤 Upload/Download API enabled")

# ==================== 성능 최적화 통합 ====================

try:
    from storage_api_optimized import (
        get_data_stats_cached,
        get_slurm_nodes_cached,
        get_scratch_info_parallel,
        get_scratch_directories_parallel,
        invalidate_storage_cache,
        warm_storage_cache
    )
    from performance import get_cache_stats
    
    PERFORMANCE_ENABLED = True
    print("  ⚡ Performance optimizations enabled (Redis caching + parallel SSH)")
except ImportError as e:
    print(f"  ⚠️  Performance optimizations not available: {e}")
    PERFORMANCE_ENABLED = False

# 캐시 통계 엔드포인트
if PERFORMANCE_ENABLED:
    @app.route('/api/cache/stats', methods=['GET'])
    def get_cache_statistics():
        """캐시 통계 조회"""
        try:
            stats = get_cache_stats()
            return jsonify({
                'success': True,
                'data': stats
            })
        except Exception as e:
            return jsonify({
                'success': False,
                'error': str(e)
            }), 500

    @app.route('/api/cache/invalidate', methods=['POST'])
    def invalidate_cache_endpoint():
        """캐시 무효화"""
        try:
            invalidate_storage_cache()
            return jsonify({
                'success': True,
                'message': 'Storage cache invalidated'
            })
        except Exception as e:
            return jsonify({
                'success': False,
                'error': str(e)
            }), 500

    # 앱 시작 시 캐시 워밍 (Production 모드만)
    if not MOCK_MODE:
        import threading
        
        def warm_cache_background():
            import time
            time.sleep(2)  # 앱 시작 후 2초 대기
            print("🔥 Warming up cache...")
            try:
                warm_storage_cache()
                print("✅ Cache warming completed")
            except Exception as e:
                print(f"⚠️  Cache warming failed: {e}")
        
        # 백그라운드 스레드로 실행
        warming_thread = threading.Thread(target=warm_cache_background, daemon=True)
        warming_thread.start()
'''

def main():
    print("=" * 60)
    print("app.py 통합 스크립트")
    print("=" * 60)
    print()
    
    # 1. 파일 존재 확인
    if not os.path.exists(APP_PY_PATH):
        print(f"❌ {APP_PY_PATH} 파일을 찾을 수 없습니다.")
        sys.exit(1)
    
    # 2. 파일 읽기
    print(f"📖 {APP_PY_PATH} 읽는 중...")
    with open(APP_PY_PATH, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 3. 이미 적용되었는지 확인
    if 'upload_bp' in content:
        print("✅ 패치가 이미 적용되어 있습니다.")
        sys.exit(0)
    
    # 4. 백업 생성
    if not os.path.exists(BACKUP_PATH):
        print(f"💾 백업 생성: {BACKUP_PATH}")
        with open(BACKUP_PATH, 'w', encoding='utf-8') as f:
            f.write(content)
    else:
        print(f"ℹ️  백업 파일이 이미 존재합니다: {BACKUP_PATH}")
    
    # 5. if __name__ == '__main__' 찾기
    main_marker = "if __name__ == '__main__':"
    if main_marker not in content:
        print(f"❌ '{main_marker}'를 찾을 수 없습니다.")
        sys.exit(1)
    
    # 6. 통합 코드 삽입
    print("🔧 통합 코드 삽입 중...")
    parts = content.split(main_marker)
    new_content = parts[0].rstrip() + '\n\n' + INTEGRATION_CODE.strip() + '\n\n' + main_marker + parts[1]
    
    # 7. 파일 쓰기
    print(f"💾 {APP_PY_PATH} 저장 중...")
    with open(APP_PY_PATH, 'w', encoding='utf-8') as f:
        f.write(new_content)
    
    print()
    print("✅ 통합 완료!")
    print()
    print("추가된 기능:")
    print("  1. 📤 업로드/다운로드 API (/api/upload/*, /api/download/*)")
    print("  2. 💾 캐시 통계 (/api/cache/stats)")
    print("  3. 🔄 캐시 무효화 (/api/cache/invalidate)")
    print("  4. 🔥 자동 캐시 워밍 (Production 모드)")
    print()
    print("서비스 재시작 필요:")
    print("  ./stop.sh && ./start_production.sh")
    print()

if __name__ == '__main__':
    main()
