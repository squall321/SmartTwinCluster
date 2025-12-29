# Gunicorn Configuration for CAE Automation Server (Port 5001)
# Based on resource_limits.yaml

import multiprocessing
import os

# Server socket
bind = "127.0.0.1:5001"
backlog = 2048

# Worker processes
workers = 4  # CPU quota: 200% (2 cores)
worker_class = "gthread"
threads = 2
worker_connections = 1000
max_requests = 500  # CAE automation tasks are heavy
max_requests_jitter = 50
timeout = 300  # Longer timeout for automation operations
graceful_timeout = 60
keepalive = 5

# Logging
accesslog = "logs/gunicorn_access.log"
errorlog = "logs/gunicorn_error.log"
loglevel = "info"
access_log_format = '%({X-Forwarded-For}i)s %(l)s %(u)s %(t)s "%(r)s" %(s)s %(b)s "%(f)s" "%(a)s" %(D)s'

# Process naming
proc_name = "cae_automation_5001"

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
    print(f"[CAE Automation] Starting Gunicorn server on {bind}")

def when_ready(server):
    """Called just after the server is started."""
    print(f"[CAE Automation] Gunicorn server is ready. PID: {os.getpid()}")

def on_exit(server):
    """Called just before exiting Gunicorn."""
    print("[CAE Automation] Shutting down Gunicorn server")
