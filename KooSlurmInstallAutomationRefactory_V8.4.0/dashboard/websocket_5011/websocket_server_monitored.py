"""
WebSocket Server with Monitoring (Enhanced)
실시간 스토리지 정보 업데이트 + Prometheus 모니터링
"""

import asyncio
import json
import time
from datetime import datetime
from typing import Set, Dict, Any
from aiohttp import web
import aiohttp_cors
from prometheus_client import generate_latest, CONTENT_TYPE_LATEST
from storage_utils_async import (
    get_scratch_storage_stats,
    get_data_storage_stats_cached,
    clear_cache
)

# 모니터링 임포트
from monitoring import (
    set_websocket_connections,
    record_websocket_message_sent,
    record_websocket_message_received,
    record_websocket_broadcast,
    collect_system_metrics,
    update_app_uptime,
    set_app_info,
    health_check
)

# 연결된 클라이언트 추적
connected_clients: Set[web.WebSocketResponse] = set()

# 브로드캐스트 설정
BROADCAST_INTERVAL = 30  # 30초마다 업데이트

# 애플리케이션 정보 설정
set_app_info(version='2.0.1', mode='websocket')

async def websocket_handler(request):
    """WebSocket 연결 핸들러 (모니터링 포함)"""
    ws = web.WebSocketResponse()
    await ws.prepare(request)
    
    # 클라이언트 추가
    connected_clients.add(ws)
    client_id = id(ws)
    
    # 메트릭 업데이트
    set_websocket_connections(len(connected_clients))
    
    print(f"Client {client_id} connected. Total clients: {len(connected_clients)}")
    
    # 초기 데이터 전송
    try:
        initial_data = await get_initial_storage_data()
        await ws.send_json({
            'type': 'initial_data',
            'data': initial_data,
            'timestamp': datetime.now().isoformat()
        })
        record_websocket_message_sent('initial_data')
    except Exception as e:
        print(f"Error sending initial data: {e}")
    
    try:
        # 메시지 수신 루프
        async for msg in ws:
            if msg.type == web.WSMsgType.TEXT:
                try:
                    data = json.loads(msg.data)
                    msg_type = data.get('type', 'unknown')
                    record_websocket_message_received(msg_type)
                    await handle_client_message(ws, data)
                except json.JSONDecodeError:
                    await ws.send_json({
                        'type': 'error',
                        'message': 'Invalid JSON'
                    })
                    record_websocket_message_sent('error')
            elif msg.type == web.WSMsgType.ERROR:
                print(f"WebSocket error: {ws.exception()}")
    except Exception as e:
        print(f"Error in websocket handler: {e}")
    finally:
        # 클라이언트 제거
        connected_clients.discard(ws)
        set_websocket_connections(len(connected_clients))
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
        record_websocket_message_sent('pong')
    
    elif msg_type == 'request_update':
        # 즉시 업데이트 요청
        storage_type = data.get('storage_type', 'all')
        update_data = await get_storage_update(storage_type, force_refresh=True)
        await ws.send_json({
            'type': 'update',
            'data': update_data,
            'timestamp': datetime.now().isoformat()
        })
        record_websocket_message_sent('update')
    
    elif msg_type == 'clear_cache':
        # 캐시 초기화 요청
        prefix = data.get('prefix')
        clear_cache(prefix)
        await ws.send_json({
            'type': 'cache_cleared',
            'prefix': prefix,
            'timestamp': datetime.now().isoformat()
        })
        record_websocket_message_sent('cache_cleared')
    
    else:
        await ws.send_json({
            'type': 'error',
            'message': f'Unknown message type: {msg_type}'
        })
        record_websocket_message_sent('error')


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
    """주기적으로 모든 클라이언트에게 업데이트 브로드캐스트 (모니터링 포함)"""
    error_count = 0
    max_errors = 5
    
    while True:
        try:
            await asyncio.sleep(BROADCAST_INTERVAL)
            
            if not connected_clients:
                error_count = 0
                continue
            
            print(f"Broadcasting updates to {len(connected_clients)} clients...")
            
            # 브로드캐스트 시작 시간
            start_time = time.time()
            
            # 업데이트 데이터 가져오기
            update_data = await get_storage_update('all', force_refresh=False)
            
            # 모든 클라이언트에게 전송
            disconnected_clients = set()
            sent_count = 0
            
            for ws in connected_clients:
                try:
                    await ws.send_json({
                        'type': 'periodic_update',
                        'data': update_data,
                        'timestamp': datetime.now().isoformat()
                    })
                    sent_count += 1
                except Exception as e:
                    print(f"Error broadcasting to client: {e}")
                    disconnected_clients.add(ws)
            
            # 메트릭 기록
            if sent_count > 0:
                for _ in range(sent_count):
                    record_websocket_message_sent('periodic_update')
            
            # 연결 끊긴 클라이언트 제거
            for ws in disconnected_clients:
                connected_clients.discard(ws)
            
            # 연결 수 업데이트
            set_websocket_connections(len(connected_clients))
            
            # 브로드캐스트 시간 기록
            duration = time.time() - start_time
            record_websocket_broadcast(duration)
            
            print(f"Broadcast completed in {duration:.3f}s to {sent_count} clients")
            
            error_count = 0  # 성공 시 에러 카운트 리셋
            
        except Exception as e:
            error_count += 1
            print(f"Error in broadcast loop (count: {error_count}): {e}")
            
            if error_count >= max_errors:
                print(f"Too many errors in broadcast loop ({error_count}), stopping...")
                break
            
            await asyncio.sleep(5)


async def metrics_collection_loop():
    """시스템 메트릭 주기적 수집"""
    while True:
        try:
            await asyncio.sleep(15)  # 15초마다
            collect_system_metrics()
            update_app_uptime()
        except Exception as e:
            print(f"Error in metrics collection: {e}")


async def health_handler(request):
    """Health check endpoint (enhanced)"""
    health_data = health_check()
    health_data['websocket'] = {
        'connected_clients': len(connected_clients),
        'broadcast_interval': BROADCAST_INTERVAL
    }
    
    status_code = 200 if health_data['status'] == 'healthy' else 503
    return web.json_response(health_data, status=status_code)


async def metrics_handler(request):
    """Prometheus metrics endpoint"""
    # 메트릭 업데이트
    collect_system_metrics()
    update_app_uptime()
    set_websocket_connections(len(connected_clients))
    
    # Prometheus 형식으로 반환
    metrics_data = generate_latest()
    return web.Response(body=metrics_data, content_type=CONTENT_TYPE_LATEST)


async def stats_handler(request):
    """WebSocket 통계 endpoint"""
    return web.json_response({
        'connected_clients': len(connected_clients),
        'broadcast_interval': BROADCAST_INTERVAL,
        'uptime_seconds': time.time() - start_time,
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
    app.router.add_get('/metrics', metrics_handler)
    app.router.add_get('/stats', stats_handler)
    
    # CORS 적용
    for route in list(app.router.routes()):
        if not isinstance(route.resource, web.StaticResource):
            cors.add(route)
    
    # 백그라운드 태스크 시작
    app.on_startup.append(start_background_tasks)
    app.on_cleanup.append(cleanup_background_tasks)
    
    return app


# 시작 시간 기록
start_time = time.time()


async def start_background_tasks(app):
    """백그라운드 태스크 시작"""
    app['broadcast_task'] = asyncio.create_task(broadcast_updates())
    app['metrics_task'] = asyncio.create_task(metrics_collection_loop())
    print("Background tasks started (broadcast + metrics)")


async def cleanup_background_tasks(app):
    """백그라운드 태스크 정리"""
    app['broadcast_task'].cancel()
    app['metrics_task'].cancel()
    
    try:
        await app['broadcast_task']
    except asyncio.CancelledError:
        pass
    
    try:
        await app['metrics_task']
    except asyncio.CancelledError:
        pass
    
    print("Background tasks cleaned up")


def run_server(host='0.0.0.0', port=5011):
    """WebSocket 서버 실행"""
    app = create_app()
    print(f"Starting WebSocket server on {host}:{port}")
    print(f"WebSocket endpoint: ws://{host}:{port}/ws")
    print(f"Health check:       http://{host}:{port}/health")
    print(f"Metrics:            http://{host}:{port}/metrics")
    print(f"Stats:              http://{host}:{port}/stats")
    web.run_app(app, host=host, port=port)


if __name__ == '__main__':
    run_server()
