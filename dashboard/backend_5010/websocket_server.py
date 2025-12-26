"""
WebSocket Server for Real-time Storage Updates
실시간 스토리지 정보 업데이트를 위한 WebSocket 서버

v4.4.1: JWT 인증 추가
"""

import asyncio
import json
import os
import sys
import yaml
from pathlib import Path
from datetime import datetime
from typing import Set, Dict, Any
from aiohttp import web
import aiohttp_cors
from storage_utils_async import (
    get_scratch_storage_stats,
    get_data_storage_stats_cached,
    clear_cache
)

# SSO 설정 로드
def _load_sso_config():
    """
    Load SSO configuration

    우선순위:
    1. 환경변수 SSO_ENABLED (true/false)
    2. YAML 파일 (my_multihead_cluster.yaml)
    3. 기본값: True (SSO enabled)
    """
    # 1. 환경변수 확인 (최우선)
    env_sso = os.getenv('SSO_ENABLED', '').lower()
    if env_sso in ('true', 'false'):
        enabled = env_sso == 'true'
        print(f"[WebSocket SSO] Loaded from environment: SSO_ENABLED={enabled}")
        return enabled

    # 2. YAML 파일 확인
    try:
        # 환경변수로 YAML 경로 지정 가능
        yaml_path_str = os.getenv('CLUSTER_CONFIG_PATH')
        if yaml_path_str:
            yaml_path = Path(yaml_path_str)
        else:
            yaml_path = Path(__file__).parent.parent.parent / 'my_multihead_cluster.yaml'

        if yaml_path.exists():
            with open(yaml_path) as f:
                config = yaml.safe_load(f)
                enabled = config.get('sso', {}).get('enabled', True)
                print(f"[WebSocket SSO] Loaded from YAML ({yaml_path}): sso.enabled={enabled}")
                return enabled
        else:
            print(f"[WebSocket SSO] YAML file not found: {yaml_path}")
    except Exception as e:
        print(f"[WebSocket SSO] Error loading YAML: {e}")

    # 3. 기본값
    print("[WebSocket SSO] Using default: SSO enabled")
    return True

SSO_ENABLED = _load_sso_config()

# JWT 인증 활성화 여부
# SSO가 비활성화되면 JWT 인증도 자동으로 비활성화
JWT_AUTH_ENABLED = SSO_ENABLED and (os.getenv('WEBSOCKET_JWT_AUTH', 'false').lower() == 'true')

# JWT 검증 함수 import (선택적)
if JWT_AUTH_ENABLED:
    try:
        # middleware 경로 추가
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        from middleware.jwt_middleware import verify_jwt_token
        print("✅ WebSocket JWT authentication enabled")
    except ImportError as e:
        print(f"⚠️  JWT middleware not available: {e}")
        print("⚠️  WebSocket running without authentication")
        JWT_AUTH_ENABLED = False

# 연결된 클라이언트 추적 (user_info 포함)
# {ws: {'username': str, 'email': str, 'groups': [], 'permissions': []}}
connected_clients: Dict[web.WebSocketResponse, Dict[str, Any]] = {}

# 브로드캐스트 설정
BROADCAST_INTERVAL = 30  # 30초마다 업데이트


async def websocket_handler(request):
    """WebSocket 연결 핸들러 (JWT 인증 선택적)"""
    ws = web.WebSocketResponse()
    await ws.prepare(request)

    client_id = id(ws)
    user_info = None

    # JWT 인증 (활성화된 경우에만)
    if JWT_AUTH_ENABLED:
        # 토큰 추출 (query parameter 또는 헤더)
        token = request.query.get('token') or request.headers.get('Authorization', '').replace('Bearer ', '')

        if not token:
            await ws.send_json({
                'type': 'error',
                'message': 'Authentication required. Please provide JWT token.',
                'code': 'AUTH_REQUIRED'
            })
            await ws.close()
            print(f"⚠️  Client {client_id} rejected: No token provided")
            return ws

        try:
            # JWT 검증
            user_info = verify_jwt_token(token)
            print(f"✅ Client {client_id} authenticated as {user_info['username']}")

        except Exception as e:
            await ws.send_json({
                'type': 'error',
                'message': f'Authentication failed: {str(e)}',
                'code': 'AUTH_FAILED'
            })
            await ws.close()
            print(f"⚠️  Client {client_id} rejected: {str(e)}")
            return ws
    else:
        # JWT 비활성화 (SSO false 모드): 전체 권한 사용자
        if not SSO_ENABLED:
            # SSO false 모드: 전체 권한 부여
            user_info = {
                'username': 'admin',
                'email': 'admin@local',
                'groups': ['admin', 'users', 'GPU-Users', 'HPC-Admins'],
                'permissions': ['admin', 'user', 'read', 'write', 'execute', 'delete']
            }
        else:
            # 호환성 유지: 익명 사용자
            user_info = {'username': f'anonymous_{client_id}', 'groups': [], 'permissions': []}

    # 클라이언트 추가 (user_info 포함)
    connected_clients[ws] = user_info
    print(f"✅ Client {client_id} ({user_info['username']}) connected. Total clients: {len(connected_clients)}")

    # 초기 데이터 전송 (사용자별 필터링)
    try:
        initial_data = await get_initial_storage_data(user_info)
        await ws.send_json({
            'type': 'initial_data',
            'data': initial_data,
            'user': user_info['username'],
            'timestamp': datetime.now().isoformat()
        })
    except Exception as e:
        print(f"Error sending initial data: {e}")
    
    try:
        # 메시지 수신 루프
        async for msg in ws:
            if msg.type == web.WSMsgType.TEXT:
                try:
                    data = json.loads(msg.data)
                    await handle_client_message(ws, data)
                except json.JSONDecodeError:
                    await ws.send_json({
                        'type': 'error',
                        'message': 'Invalid JSON'
                    })
            elif msg.type == web.WSMsgType.ERROR:
                print(f"WebSocket error: {ws.exception()}")
    except Exception as e:
        print(f"Error in websocket handler: {e}")
    finally:
        # 클라이언트 제거
        user_info = connected_clients.pop(ws, None)
        username = user_info['username'] if user_info else 'unknown'
        print(f"Client {client_id} ({username}) disconnected. Total clients: {len(connected_clients)}")
    
    return ws


async def handle_client_message(ws: web.WebSocketResponse, data: Dict[str, Any]):
    """클라이언트 메시지 처리"""
    msg_type = data.get('type')
    
    if msg_type == 'ping':
        # Ping-pong for connection health check
        await ws.send_json({
            'type': 'pong',
            'timestamp': datetime.now().isoformat()
        })
    
    elif msg_type == 'request_update':
        # 즉시 업데이트 요청
        storage_type = data.get('storage_type', 'all')
        update_data = await get_storage_update(storage_type, force_refresh=True)
        await ws.send_json({
            'type': 'update',
            'data': update_data,
            'timestamp': datetime.now().isoformat()
        })
    
    elif msg_type == 'clear_cache':
        # 캐시 초기화 요청
        prefix = data.get('prefix')
        clear_cache(prefix)
        await ws.send_json({
            'type': 'cache_cleared',
            'prefix': prefix,
            'timestamp': datetime.now().isoformat()
        })
    
    else:
        await ws.send_json({
            'type': 'error',
            'message': f'Unknown message type: {msg_type}'
        })


async def get_initial_storage_data(user_info: Dict[str, Any] = None) -> Dict[str, Any]:
    """
    초기 스토리지 데이터 가져오기

    Args:
        user_info: 사용자 정보 (JWT에서 추출, 선택적)

    Returns:
        dict: 스토리지 데이터 (사용자별 필터링 가능)
    """
    try:
        data_stats = get_data_storage_stats_cached(use_cache=True)
        scratch_stats = await get_scratch_storage_stats(use_cache=True)

        result = {
            'data_storage': data_stats,
            'scratch_storage': scratch_stats,
            'status': 'success'
        }

        # 관리자가 아닌 경우, 사용자별 필터링 가능 (향후 확장)
        if user_info and 'HPC-Admins' not in user_info.get('groups', []):
            # 일반 사용자: 전체 데이터 표시 (현재는 공개 정보)
            pass

        return result

    except Exception as e:
        print(f"Error getting initial storage data: {e}")
        return {
            'data_storage': {},
            'scratch_storage': {},
            'status': 'error',
            'error': str(e)
        }


async def get_storage_update(storage_type: str = 'all', force_refresh: bool = False) -> Dict[str, Any]:
    """스토리지 업데이트 데이터 가져오기"""
    try:
        result = {}
        
        if storage_type in ['all', 'data']:
            data_stats = get_data_storage_stats_cached(use_cache=not force_refresh)
            result['data_storage'] = data_stats
        
        if storage_type in ['all', 'scratch']:
            scratch_stats = await get_scratch_storage_stats(use_cache=not force_refresh)
            result['scratch_storage'] = scratch_stats
        
        result['status'] = 'success'
        return result
        
    except Exception as e:
        print(f"Error getting storage update: {e}")
        return {
            'status': 'error',
            'error': str(e)
        }


async def broadcast_message(message_type: str, data: Dict[str, Any]):
    """
    모든 클라이언트에게 메시지 브로드캐스트

    Args:
        message_type: 메시지 타입 (upload_progress, job_update, etc.)
        data: 전송할 데이터
    """
    if not connected_clients:
        return

    message = {
        'type': message_type,
        'data': data,
        'timestamp': datetime.now().isoformat()
    }

    disconnected_clients = set()
    for ws in connected_clients:
        try:
            await ws.send_json(message)
        except Exception as e:
            print(f"Error broadcasting message to client: {e}")
            disconnected_clients.add(ws)

    # 연결 끊긴 클라이언트 제거
    for ws in disconnected_clients:
        connected_clients.discard(ws)


async def broadcast_updates():
    """주기적으로 모든 클라이언트에게 업데이트 브로드캐스트"""
    while True:
        try:
            await asyncio.sleep(BROADCAST_INTERVAL)

            if not connected_clients:
                continue

            print(f"Broadcasting updates to {len(connected_clients)} clients...")

            # 업데이트 데이터 가져오기
            update_data = await get_storage_update('all', force_refresh=False)

            # 모든 클라이언트에게 전송
            await broadcast_message('periodic_update', update_data)

        except Exception as e:
            print(f"Error in broadcast loop: {e}")


async def health_handler(request):
    """Health check endpoint"""
    return web.json_response({
        'status': 'healthy',
        'connected_clients': len(connected_clients),
        'timestamp': datetime.now().isoformat()
    })


def create_app():
    """애플리케이션 생성"""
    app = web.Application()
    
    # CORS 설정
    cors = aiohttp_cors.setup(app, defaults={
        "*": aiohttp_cors.ResourceOptions(
            allow_credentials=True,
            expose_headers="*",
            allow_headers="*",
            allow_methods="*"
        )
    })
    
    # 라우트 추가
    app.router.add_get('/ws', websocket_handler)
    app.router.add_get('/health', health_handler)
    
    # CORS 적용
    for route in list(app.router.routes()):
        if not isinstance(route.resource, web.StaticResource):
            cors.add(route)
    
    # 백그라운드 태스크 시작
    app.on_startup.append(start_background_tasks)
    app.on_cleanup.append(cleanup_background_tasks)
    
    return app


async def start_background_tasks(app):
    """백그라운드 태스크 시작"""
    app['broadcast_task'] = asyncio.create_task(broadcast_updates())
    print("Background broadcast task started")


async def cleanup_background_tasks(app):
    """백그라운드 태스크 정리"""
    app['broadcast_task'].cancel()
    await app['broadcast_task']
    print("Background tasks cleaned up")


def run_server(host='0.0.0.0', port=5011):
    """WebSocket 서버 실행"""
    app = create_app()
    print(f"Starting WebSocket server on {host}:{port}")
    print(f"WebSocket endpoint: ws://{host}:{port}/ws")
    web.run_app(app, host=host, port=port)


if __name__ == '__main__':
    run_server()
