# Gunicorn Configuration for Dashboard Backend (Port 5010)
# Based on resource_limits.yaml

import multiprocessing
import os

# Server socket
bind = "127.0.0.1:5010"
backlog = 2048

# Worker processes
workers = 4  # CPU quota: 200% (2 cores)
worker_class = "gthread"
threads = 2
worker_connections = 1000
max_requests = 1000
max_requests_jitter = 50
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
worker_tmp_dir = "/dev/shm"
preload_app = True

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

def when_ready(server):
    """Called just after the server is started."""
    print(f"[Dashboard Backend] Gunicorn server is ready. PID: {os.getpid()}")

def on_exit(server):
    """Called just before exiting Gunicorn."""
    print("[Dashboard Backend] Shutting down Gunicorn server")
