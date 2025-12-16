# Gunicorn Configuration for Dashboard Backend (Port 5010)
# Performance Optimized Version

import multiprocessing
import os

# Server socket
bind = "127.0.0.1:5010"
backlog = 2048

# Worker processes (자동 CPU 스케일링)
cpu_count = multiprocessing.cpu_count()
workers = min((cpu_count * 2) + 1, 8)  # 최대 8 workers
worker_class = "gthread"
threads = 4  # 2 → 4로 증가 (더 많은 동시 요청 처리)
worker_connections = 1000
max_requests = 2000  # 1000 → 2000 (재시작 빈도 감소)
max_requests_jitter = 100
timeout = 120
graceful_timeout = 30
keepalive = 5

# Logging
accesslog = "logs/gunicorn_access.log"
errorlog = "logs/gunicorn_error.log"
loglevel = "info"
access_log_format = '%({X-Forwarded-For}i)s %(l)s %(u)s %(t)s "%(r)s" %(s)s %(b)s "%(f)s" "%(a)s" %(D)s'

# Process naming
proc_name = "dashboard_backend_5010"

# Server mechanics
daemon = False
pidfile = "logs/gunicorn.pid"
user = None
group = None
tmp_upload_dir = None

# Performance
worker_tmp_dir = "/dev/shm"  # 메모리 기반 임시 디렉토리
preload_app = True  # 앱을 미리 로드하여 메모리 절약

# Security
limit_request_line = 4096
limit_request_fields = 100
limit_request_field_size = 8190

# Development / Production
reload = False  # Set to True for development

# Hooks
def on_starting(server):
    """Called just before the master process is initialized."""
    print(f"[Dashboard Backend] Starting Gunicorn server on {bind}")
    print(f"[Dashboard Backend] Workers: {workers}, Threads: {threads}")
    print(f"[Dashboard Backend] CPU cores: {cpu_count}")

def when_ready(server):
    """Called just after the server is started."""
    print(f"[Dashboard Backend] Gunicorn server is ready. PID: {os.getpid()}")

def on_exit(server):
    """Called just before exiting Gunicorn."""
    print("[Dashboard Backend] Shutting down Gunicorn server")

def worker_int(worker):
    """Called when worker receives INT or QUIT signal."""
    print(f"[Dashboard Backend] Worker {worker.pid} received INT/QUIT signal")

def worker_abort(worker):
    """Called when worker times out."""
    print(f"[Dashboard Backend] Worker {worker.pid} aborted (timeout)")
