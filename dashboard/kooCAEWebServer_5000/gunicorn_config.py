# Gunicorn Configuration for CAE Backend (Port 5000)
# Based on resource_limits.yaml

import multiprocessing
import os

# Server socket
bind = "127.0.0.1:5000"
backlog = 2048

# Worker processes
workers = 4  # CPU quota: 200% (2 cores)
worker_class = "gthread"
threads = 2
worker_connections = 1000
max_requests = 500  # CAE tasks are heavy, restart workers more frequently
max_requests_jitter = 50
timeout = 300  # Longer timeout for CAE operations
graceful_timeout = 60
keepalive = 5

# Logging
accesslog = "logs/gunicorn_access.log"
errorlog = "logs/gunicorn_error.log"
loglevel = "info"
access_log_format = '%({X-Forwarded-For}i)s %(l)s %(u)s %(t)s "%(r)s" %(s)s %(b)s "%(f)s" "%(a)s" %(D)s'

# Process naming
proc_name = "cae_backend_5000"

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
    print(f"[CAE Backend] Starting Gunicorn server on {bind}")

def when_ready(server):
    """Called just after the server is started."""
    print(f"[CAE Backend] Gunicorn server is ready. PID: {os.getpid()}")

def on_exit(server):
    """Called just before exiting Gunicorn."""
    print("[CAE Backend] Shutting down Gunicorn server")
