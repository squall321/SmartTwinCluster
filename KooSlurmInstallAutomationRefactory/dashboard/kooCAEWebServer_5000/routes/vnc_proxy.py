"""
VNC Proxy Routes
WebSocket과 HTTP 트래픽을 로컬 VNC 터널로 프록시
"""

from flask import Blueprint, request, Response
import requests
from flask_sock import Sock

vnc_proxy_bp = Blueprint('vnc_proxy', __name__)


@vnc_proxy_bp.route('/vnc/<int:port>/<path:path>', methods=['GET', 'POST'])
def proxy_vnc_http(port: int, path: str):
    """
    VNC HTTP 요청 프록시 (noVNC HTML, JS, CSS 등)
    """
    # 로컬 SSH 터널 포트로 프록시
    url = f'http://localhost:{port}/{path}'

    try:
        # Query string 포함
        if request.query_string:
            url += f'?{request.query_string.decode()}'

        # 요청 전달
        headers = {k: v for k, v in request.headers if k.lower() not in ['host', 'connection']}

        if request.method == 'GET':
            resp = requests.get(url, headers=headers, stream=True)
        else:
            resp = requests.post(url, headers=headers, data=request.data, stream=True)

        # 응답 반환
        def generate():
            for chunk in resp.iter_content(chunk_size=8192):
                if chunk:
                    yield chunk

        return Response(
            generate(),
            status=resp.status_code,
            headers=dict(resp.headers)
        )

    except Exception as e:
        return Response(f'Proxy error: {str(e)}', status=502)


def register_websocket_proxy(sock: Sock, app):
    """
    WebSocket 프록시 등록

    Args:
        sock: Flask-Sock 인스턴스
        app: Flask 앱
    """
    import socket
    import threading

    @sock.route('/vnc/<int:port>/websockify')
    def proxy_vnc_websocket(ws, port: int):
        """
        VNC WebSocket 프록시 (VNC 연결)
        """
        print(f"[VNC Proxy] WebSocket connection request for port {port}")

        # 로컬 SSH 터널에 연결
        try:
            vnc_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            vnc_socket.connect(('localhost', port))
            print(f"[VNC Proxy] Connected to localhost:{port}")
        except Exception as e:
            print(f"[VNC Proxy] Failed to connect to localhost:{port}: {e}")
            ws.close()
            return

        # 양방향 데이터 전송
        def forward_to_vnc():
            """브라우저 -> VNC"""
            try:
                while True:
                    data = ws.receive()
                    if data is None:
                        break
                    if isinstance(data, str):
                        data = data.encode('utf-8')
                    vnc_socket.sendall(data)
            except Exception as e:
                print(f"[VNC Proxy] Browser->VNC error: {e}")
            finally:
                vnc_socket.close()

        def forward_from_vnc():
            """VNC -> 브라우저"""
            try:
                while True:
                    data = vnc_socket.recv(8192)
                    if not data:
                        break
                    ws.send(data)
            except Exception as e:
                print(f"[VNC Proxy] VNC->Browser error: {e}")
            finally:
                ws.close()

        # 두 스레드로 양방향 전송
        t1 = threading.Thread(target=forward_to_vnc, daemon=True)
        t2 = threading.Thread(target=forward_from_vnc, daemon=True)

        t1.start()
        t2.start()

        t1.join()
        t2.join()

        print(f"[VNC Proxy] Connection closed for port {port}")
