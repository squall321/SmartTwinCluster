from flask import Blueprint, request, jsonify, stream_with_context, Response
import requests
from config import Config
from io import BytesIO

proxy_bp = Blueprint('proxy', __name__)
ALLOWED_METHODS = ['GET', 'POST', 'DELETE', 'PUT', 'PATCH', 'OPTIONS']

@proxy_bp.route('/api/proxy/<service>/<path:endpoint>', methods=ALLOWED_METHODS)
def dynamic_proxy(service: str, endpoint: str) -> Response:
    base_url = Config.BACKEND_MAP.get(service)
    if not base_url:
        return Response(
            jsonify({"error": f"Service {service} not found"}).data,
            status=404,
            mimetype='application/json'
        )

    url = f"{base_url}/{endpoint}"

    try:
        method = request.method
        headers = {k: v for k, v in request.headers if k.lower() != 'host'}

        # === GET 요청 (파일 다운로드 등 스트리밍)
        if method == 'GET':
            resp = requests.get(
                url,
                params=request.args.items(multi=True),
                headers=headers,
                stream=True,
            )

            def generate():
                for chunk in resp.iter_content(chunk_size=8192):
                    if chunk:
                        yield chunk

            content_disposition = resp.headers.get(
                'Content-Disposition',
                'attachment; filename="download.bin"'
            )

            return Response(
                stream_with_context(generate()),
                headers={
                    'Content-Type': resp.headers.get('Content-Type', 'application/octet-stream'),
                    'Content-Disposition': content_disposition,
                    'Access-Control-Expose-Headers': 'Content-Disposition',
                    'Access-Control-Allow-Origin': '*',
                },
                status=resp.status_code
            )

        elif method in ['POST', 'PUT', 'PATCH']:
            if request.files:
                files = []
                for key in request.files:
                    for file in request.files.getlist(key):
                        # file.stream을 직접 사용 (메모리 복사 불필요)
                        files.append((key, (file.filename, file.stream, file.mimetype)))

                # form field는 dict 형식으로 재구성
                data = dict(request.form)

                # Content-Type 헤더 제거 (requests가 multipart 헤더 자동 구성)
                clean_headers = {k: v for k, v in headers.items() if not k.lower().startswith("content-type")}

                resp = requests.request(
                    method,
                    url,
                    files=files,
                    data=data,
                    params=request.args.items(multi=True),
                    headers=clean_headers,
                )
            elif request.is_json:
                resp = requests.request(
                    method,
                    url,
                    json=request.get_json(),
                    params=request.args.items(multi=True),
                    headers=headers,
                )
            else:
                resp = requests.request(
                    method,
                    url,
                    data=request.form,
                    params=request.args.items(multi=True),
                    headers=headers,
                )

            return Response(
                resp.content,
                status=resp.status_code,
                content_type=resp.headers.get('Content-Type', 'application/json')
            )


        # === DELETE
        elif method == 'DELETE':
            resp = requests.delete(
                url,
                params=request.args.items(multi=True),
                headers=headers,
            )
            return Response(
                resp.content,
                status=resp.status_code,
                content_type=resp.headers.get('Content-Type', 'application/json')
            )

        # === OPTIONS (for CORS)
        elif method == 'OPTIONS':
            return Response(status=204, headers={
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': ', '.join(ALLOWED_METHODS),
                'Access-Control-Allow-Headers': '*'
            })

        else:
            return Response(
                jsonify({"error": "Unsupported method"}).data,
                status=405,
                mimetype='application/json'
            )

    except Exception as e:
        return Response(
            jsonify({"error": str(e)}).data,
            status=500,
            mimetype='application/json'
        )
