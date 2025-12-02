"""
/api/slurm/apply-config 엔드포인트 추가 코드

이 코드를 app.py의 적절한 위치에 추가하세요.
(다른 /api/slurm 라우트들 근처)
"""

@app.route('/api/slurm/apply-config', methods=['POST', 'OPTIONS'])
def apply_slurm_configuration():
    """
    Slurm 설정 적용
    - QoS 생성/업데이트
    - Partition 설정
    - slurm.conf 재설정
    """
    if request.method == 'OPTIONS':
        return '', 200
    
    try:
        data = request.json
        groups = data.get('groups', [])
        
        if not groups:
            return jsonify({
                'success': False,
                'message': 'No groups provided'
            }), 400
        
        # Mock 모드 체크
        mock_mode = os.getenv('MOCK_MODE', 'true').lower() == 'true'
        
        if mock_mode:
            # Mock 모드: 성공 시뮬레이션
            print(f"📝 [Mock] Would apply configuration for {len(groups)} groups")
            for group in groups:
                print(f"   - {group.get('name')} ({group.get('partitionName')})")
            
            return jsonify({
                'success': True,
                'mode': 'mock',
                'message': f'Configuration applied successfully (Mock)',
                'changes': {
                    'qos_created': [g.get('qosName') for g in groups if g.get('qosName')],
                    'partitions_updated': len(groups),
                }
            })
        
        # Production 모드: 실제 Slurm 설정 적용
        print(f"\n{'='*60}")
        print(f"🔧 Applying Slurm Configuration")
        print(f"{'='*60}")
        print(f"Groups to configure: {len(groups)}")
        
        # apply_full_configuration 호출 (slurm_config_manager.py)
        result = apply_full_configuration(groups, dry_run=False)
        
        if result['success']:
            return jsonify({
                'success': True,
                'mode': 'production',
                'message': 'Configuration applied successfully',
                'changes': {
                    'qos_created': result.get('qos_created', []),
                    'qos_failed': result.get('qos_failed', []),
                    'partitions_updated': result.get('partitions_updated', False),
                }
            })
        else:
            return jsonify({
                'success': False,
                'mode': 'production',
                'message': 'Failed to apply configuration',
                'errors': result.get('errors', [])
            }), 500
    
    except Exception as e:
        print(f"❌ Error in apply_slurm_configuration: {e}")
        import traceback
        traceback.print_exc()
        
        return jsonify({
            'success': False,
            'message': f'Internal server error: {str(e)}'
        }), 500
