"""
WebSocket Server for Real-time Storage Updates
실시간 스토리지 정보 업데이트를 위한 WebSocket 서버
"""

import asyncio
import json
from datetime import datetime
from typing import Set, Dict, Any
from aiohttp import web
import aiohttp_cors
from storage_utils_async import (
    get_scratch_storage_stats,
    get_data_storage_stats_cached,
    clear_cache
)

# 연결된 클라이언트 추적
connected_clients: Set[web.WebSocketResponse] = set()

# 브로드캐스트 설정
BROADCAST_INTERVAL = 30  # 30초마다 업데이트


async def websocket_handler(request):
    """WebSocket 연결 핸들러"""
    ws = web.WebSocketResponse()
    await ws.prepare(request)
    
    # 클라이언트 추가
    connected_clients.add(ws)
    client_id = id(ws)
    print(f"Client {client_id} connected. Total clients: {len(connected_clients)}")
    
    # 초기 데이터 전송
    try:
        initial_data = await get_initial_storage_data()
        await ws.send_json({
            'type': 'initial_data',
            'data': initial_data,
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
        connected_clients.discard(ws)
        print(f"Client {client_id} disconnected. Total clients: {len(connected_clients)}")
    
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


async def get_initial_storage_data() -> Dict[str, Any]:
    """초기 스토리지 데이터 가져오기"""
    try:
        data_stats = get_data_storage_stats_cached(use_cache=True)
        scratch_stats = await get_scratch_storage_stats(use_cache=True)
        
        return {
            'data_storage': data_stats,
            'scratch_storage': scratch_stats,
            'status': 'success'
        }
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
            disconnected_clients = set()
            for ws in connected_clients:
                try:
                    await ws.send_json({
                        'type': 'periodic_update',
                        'data': update_data,
                        'timestamp': datetime.now().isoformat()
                    })
                except Exception as e:
                    print(f"Error broadcasting to client: {e}")
                    disconnected_clients.add(ws)
            
            # 연결 끊긴 클라이언트 제거
            for ws in disconnected_clients:
                connected_clients.discard(ws)
            
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
