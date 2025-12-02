# Phase 6: Web Services Integration

Phase 6 implements comprehensive web services deployment for the HPC cluster, providing user-facing interfaces, APIs, and real-time monitoring capabilities.

## Overview

**Components:**
- 8 web services (4 frontend + 4 backend)
- Nginx reverse proxy with SSL
- Let's Encrypt SSL certificate automation
- Systemd service management
- Health check monitoring
- Redis and MariaDB integration

**Services:**
1. **Dashboard** (React + Vite) - Main user interface
2. **Auth Service** (Express) - Authentication and authorization
3. **Job API** (Express) - Slurm job management
4. **WebSocket Service** (Socket.IO) - Real-time updates
5. **File Service** (Express) - File upload/download
6. **Monitoring Dashboard** (React + Vite) - Cluster monitoring
7. **Metrics API** (Express) - Prometheus-compatible metrics
8. **Admin Portal** (React + Vite) - Administrative interface

## Architecture

### Service Stack

```
┌─────────────────────────────────────────────────────────────┐
│                         Internet                            │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
            ┌──────────────────────┐
            │   Let's Encrypt      │
            │   SSL Certificate    │
            └──────────┬───────────┘
                       │
                       ▼
            ┌──────────────────────┐
            │   Nginx (443/80)     │
            │   Reverse Proxy      │
            │   Load Balancer      │
            └──────────┬───────────┘
                       │
        ┌──────────────┼──────────────┐
        │              │              │
        ▼              ▼              ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│ Controller 1 │ │ Controller 2 │ │ Controller 3 │
│              │ │              │ │              │
│ Frontend:    │ │ Frontend:    │ │ Frontend:    │
│ - Dashboard  │ │ - Dashboard  │ │ - Dashboard  │
│ - Monitoring │ │ - Monitoring │ │ - Monitoring │
│ - Admin      │ │ - Admin      │ │ - Admin      │
│              │ │              │ │              │
│ Backend:     │ │ Backend:     │ │ Backend:     │
│ - Auth :5000 │ │ - Auth :5000 │ │ - Auth :5000 │
│ - Jobs :5001 │ │ - Jobs :5001 │ │ - Jobs :5001 │
│ - WS   :5010 │ │ - WS   :5010 │ │ - WS   :5010 │
│ - Files:5002 │ │ - Files:5002 │ │ - Files:5002 │
│ - Metrics:   │ │ - Metrics:   │ │ - Metrics:   │
│       :5003  │ │       :5003  │ │       :5003  │
└──────┬───────┘ └──────┬───────┘ └──────┬───────┘
       │                │                │
       └────────────────┼────────────────┘
                        │
        ┌───────────────┴───────────────┐
        │                               │
        ▼                               ▼
┌──────────────────┐          ┌──────────────────┐
│  MariaDB Galera  │          │  Redis Cluster   │
│  (Database)      │          │  (Cache/Session) │
└──────────────────┘          └──────────────────┘
```

### Port Allocation

| Service | Port | Protocol | Purpose |
|---------|------|----------|---------|
| Nginx | 80 | HTTP | Redirect to HTTPS |
| Nginx | 443 | HTTPS | Main entry point |
| Dashboard | 5173 | HTTP | React frontend |
| Auth Service | 5000 | HTTP | Authentication API |
| Job API | 5001 | HTTP | Job management API |
| File Service | 5002 | HTTP | File transfer API |
| Metrics API | 5003 | HTTP | Monitoring API |
| WebSocket | 5010 | HTTP/WS | Real-time updates |
| Monitoring | 5174 | HTTP | Monitoring frontend |
| Admin Portal | 5175 | HTTP | Admin frontend |

### URL Routing

| URL Path | Service | Description |
|----------|---------|-------------|
| `/` | Dashboard | Main user interface |
| `/api/auth` | Auth Service | Login, logout, user management |
| `/api/jobs` | Job API | Submit, query, cancel jobs |
| `/api/files` | File Service | Upload, download files |
| `/api/monitoring` | Metrics API | Cluster metrics and stats |
| `/ws` | WebSocket | Real-time job updates |
| `/monitoring` | Monitoring Dashboard | Grafana-like interface |
| `/admin` | Admin Portal | Administrative tools |
| `/health` | Nginx | Health check endpoint |

## Installation

### Prerequisites

**Required Software:**
- Node.js 20.x or later
- npm 10.x or later
- Nginx 1.18 or later
- Certbot (Let's Encrypt client)
- Python 3.8+ (for config parser)
- jq (for JSON processing)

**Required Services:**
- MariaDB Galera cluster (from Phase 2)
- Redis cluster (from Phase 3)
- GlusterFS (from Phase 1, optional for file storage)

**YAML Configuration:**

Add web service configuration to `my_multihead_cluster.yaml`:

```yaml
# Web services configuration
web:
  domain: cluster.example.com
  session_secret: ${SESSION_SECRET}
  jwt_secret: ${JWT_SECRET}

# Mark controllers with web service enabled
controllers:
  - hostname: server1
    ip: 192.168.1.101
    services:
      glusterfs: true
      mariadb: true
      redis: true
      slurm: true
      web: true  # Enable web services
      keepalived: true
    vip_owner: true
    priority: 100

  - hostname: server2
    ip: 192.168.1.102
    services:
      glusterfs: true
      mariadb: true
      redis: true
      slurm: true
      web: true  # Enable web services
      keepalived: true
    vip_owner: false
    priority: 90
```

### Setup Process

#### Step 1: Install Dependencies

```bash
# Run on all web-enabled controllers
sudo apt-get update
sudo apt-get install -y nginx certbot python3-certbot-nginx jq

# Install Node.js 20.x
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo bash -
sudo apt-get install -y nodejs

# Verify installations
node --version  # Should be v20.x
npm --version   # Should be 10.x
nginx -v        # Should be 1.18+
certbot --version
```

#### Step 2: Run Setup Script

```bash
# Navigate to cluster directory
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/cluster

# Run web services setup
sudo ./setup/phase5_web.sh --config ../my_multihead_cluster.yaml

# Or dry-run first to preview
sudo ./setup/phase5_web.sh --config ../my_multihead_cluster.yaml --dry-run

# Skip SSL for testing (use HTTP only)
sudo ./setup/phase5_web.sh --skip-ssl
```

#### Step 3: Verify Services

```bash
# Check service status
systemctl status dashboard
systemctl status auth_service
systemctl status job_api
systemctl status websocket_service
systemctl status file_service
systemctl status monitoring_dashboard
systemctl status metrics_api
systemctl status admin_portal
systemctl status nginx

# Check all services at once
./utils/web_health_check.sh

# Check with JSON output
./utils/web_health_check.sh --format json

# Check all nodes
./utils/web_health_check.sh --all-nodes
```

#### Step 4: Access Web Interface

```bash
# Via VIP (recommended)
https://cluster.example.com

# Via direct node IP (for testing)
https://192.168.1.101

# Check health endpoint
curl https://cluster.example.com/health
```

## Setup Script Details

### phase5_web.sh

The main setup script performs these steps:

1. **Check Prerequisites**
   - Verify root privileges
   - Check for Node.js, npm, Nginx, Certbot
   - Install missing dependencies

2. **Load Configuration**
   - Parse `my_multihead_cluster.yaml`
   - Verify current node has `web: true`
   - Load database and Redis credentials

3. **Create System User**
   - Create `webservice` user for running services
   - Set up home directory and permissions

4. **Create Directory Structure**
   ```
   /opt/web_services/
   ├── dashboard/
   ├── auth_service/
   ├── job_api/
   ├── websocket_service/
   ├── file_service/
   ├── monitoring_dashboard/
   ├── metrics_api/
   ├── admin_portal/
   ├── config/
   └── uploads/
   ```

5. **Deploy Service Skeletons**
   - Initialize npm projects
   - Install dependencies
   - Create basic Express/React apps
   - Configure environment variables

6. **Create Systemd Services**
   - Generate service files for all 8 services
   - Configure restart policies
   - Set resource limits
   - Enable automatic startup

7. **Configure Nginx**
   - Generate reverse proxy configuration
   - Set up upstream load balancing
   - Configure SSL termination
   - Enable rate limiting

8. **Setup SSL Certificates**
   - Obtain Let's Encrypt certificate
   - Configure auto-renewal (cron job)
   - Install certificate in Nginx

9. **Start Services**
   - Enable and start all systemd services
   - Reload Nginx configuration
   - Verify service health

### Command Options

```bash
# Basic usage
sudo ./setup/phase5_web.sh

# Specify config file
sudo ./setup/phase5_web.sh --config /path/to/config.yaml

# Dry-run mode (preview changes)
sudo ./setup/phase5_web.sh --dry-run

# Skip SSL certificate generation
sudo ./setup/phase5_web.sh --skip-ssl

# Force re-setup even if already configured
sudo ./setup/phase5_web.sh --force

# Show help
./setup/phase5_web.sh --help
```

## Service Details

### 1. Dashboard (Port 5173)

**Purpose:** Main user interface for cluster interaction

**Technology:** React + Vite

**Features:**
- Job submission and monitoring
- Resource usage visualization
- User profile management
- Real-time job updates (via WebSocket)

**Endpoints:**
- `/` - Main dashboard
- `/jobs` - Job list
- `/submit` - Job submission form
- `/profile` - User profile

**Environment Variables:**
```
VITE_API_URL=https://cluster.example.com/api
VITE_WS_URL=wss://cluster.example.com/ws
```

### 2. Auth Service (Port 5000)

**Purpose:** Authentication and authorization

**Technology:** Node.js + Express + JWT

**Features:**
- User login/logout
- JWT token generation
- Session management (Redis)
- Password hashing (bcrypt)
- Role-based access control

**Endpoints:**
- `POST /api/auth/login` - User login
- `POST /api/auth/logout` - User logout
- `POST /api/auth/register` - User registration
- `GET /api/auth/me` - Get current user
- `POST /api/auth/refresh` - Refresh JWT token
- `GET /health` - Health check

**Database Tables:**
```sql
CREATE DATABASE IF NOT EXISTS auth_db;
USE auth_db;

CREATE TABLE users (
    id INT PRIMARY KEY AUTO_INCREMENT,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role VARCHAR(20) DEFAULT 'user',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP NULL
);

CREATE TABLE sessions (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    token VARCHAR(255) UNIQUE NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);
```

### 3. Job API (Port 5001)

**Purpose:** Slurm job management

**Technology:** Node.js + Express + MariaDB

**Features:**
- Submit jobs via Slurm commands
- Query job status
- Cancel jobs
- Job history and statistics
- Integration with Slurm accounting database

**Endpoints:**
- `POST /api/jobs` - Submit new job
- `GET /api/jobs` - List jobs (with filters)
- `GET /api/jobs/:id` - Get job details
- `DELETE /api/jobs/:id` - Cancel job
- `GET /api/jobs/:id/output` - Get job output
- `GET /api/jobs/stats` - Job statistics
- `GET /health` - Health check

**Request Example:**
```bash
curl -X POST https://cluster.example.com/api/jobs \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "script": "#!/bin/bash\n#SBATCH --job-name=test\n#SBATCH --time=00:10:00\n#SBATCH --ntasks=1\n\necho \"Hello from Slurm\""
  }'
```

### 4. WebSocket Service (Port 5010)

**Purpose:** Real-time job updates and notifications

**Technology:** Socket.IO + Redis Pub/Sub

**Features:**
- Real-time job status updates
- Broadcast notifications to all users
- Private messages to specific users
- WebSocket authentication via JWT
- Horizontal scaling via Redis adapter

**Events:**
- `job:submitted` - New job submitted
- `job:started` - Job started running
- `job:completed` - Job completed
- `job:failed` - Job failed
- `job:cancelled` - Job cancelled
- `system:alert` - System-wide alert

**Client Example:**
```javascript
import io from 'socket.io-client';

const socket = io('wss://cluster.example.com/ws', {
  auth: { token: jwtToken }
});

socket.on('job:started', (data) => {
  console.log('Job started:', data.jobId);
});
```

### 5. File Service (Port 5002)

**Purpose:** File upload/download for job inputs and outputs

**Technology:** Node.js + Express + Multer

**Features:**
- Multi-file upload (up to 10GB per file)
- Resume interrupted uploads
- Download job output files
- File metadata tracking
- Storage on GlusterFS (if available)

**Endpoints:**
- `POST /api/files/upload` - Upload files
- `GET /api/files/:id` - Download file
- `DELETE /api/files/:id` - Delete file
- `GET /api/files` - List user files
- `GET /api/files/:id/metadata` - Get file metadata
- `GET /health` - Health check

**Upload Example:**
```bash
curl -X POST https://cluster.example.com/api/files/upload \
  -H "Authorization: Bearer $TOKEN" \
  -F "file=@input_data.txt" \
  -F "description=Input data for job 12345"
```

### 6. Monitoring Dashboard (Port 5174)

**Purpose:** Real-time cluster monitoring and visualization

**Technology:** React + Vite + Chart.js

**Features:**
- Real-time resource usage graphs
- Node status overview
- Job queue visualization
- Historical metrics
- Customizable dashboards

**Metrics Displayed:**
- CPU usage per node
- Memory usage per node
- GPU usage (if available)
- Job queue length
- Running/pending/completed jobs
- Network I/O
- Disk I/O

### 7. Metrics API (Port 5003)

**Purpose:** Prometheus-compatible metrics endpoint

**Technology:** Node.js + Express + prom-client

**Features:**
- Expose Prometheus metrics
- Aggregate data from Slurm accounting
- Custom metrics from MariaDB and Redis
- Node exporter integration

**Endpoints:**
- `GET /metrics` - Prometheus metrics
- `GET /api/monitoring/nodes` - Node statistics
- `GET /api/monitoring/jobs` - Job statistics
- `GET /api/monitoring/users` - User statistics
- `GET /health` - Health check

**Metrics Example:**
```
# HELP slurm_jobs_total Total number of jobs
# TYPE slurm_jobs_total counter
slurm_jobs_total{state="running"} 42
slurm_jobs_total{state="pending"} 15
slurm_jobs_total{state="completed"} 1234

# HELP node_cpu_usage CPU usage percentage
# TYPE node_cpu_usage gauge
node_cpu_usage{node="server1"} 45.2
node_cpu_usage{node="server2"} 67.8
```

### 8. Admin Portal (Port 5175)

**Purpose:** Administrative interface for cluster management

**Technology:** React + Vite

**Features:**
- User management
- Node management
- Job management (admin view)
- System configuration
- Logs and diagnostics
- Backup and restore

**Admin Functions:**
- Create/edit/delete users
- Add/remove nodes
- Hold/release jobs
- Set resource limits
- View system logs
- Trigger backups

## Health Checks

### web_health_check.sh

Comprehensive health check utility for all web services.

**Usage:**
```bash
# Check local node services
./utils/web_health_check.sh

# Check all web-enabled nodes
./utils/web_health_check.sh --all-nodes

# Check specific service
./utils/web_health_check.sh --service dashboard

# JSON output
./utils/web_health_check.sh --format json

# Compact output
./utils/web_health_check.sh --format compact

# Verbose mode
./utils/web_health_check.sh --verbose
```

**Output Example (Table):**
```
Node                 Service                   Type       Port   Status        HTTP   Time (s)   Systemd         Message
------------------------------------------------------------------------------------------------------------------------------------
localhost            dashboard                 frontend   5173   healthy       200    0.045      running         OK
localhost            auth_service              backend    5000   healthy       200    0.023      running         OK
localhost            job_api                   backend    5001   healthy       200    0.031      running         OK
localhost            websocket_service         backend    5010   healthy       200    0.018      running         OK
localhost            file_service              backend    5002   healthy       200    0.027      running         OK
localhost            monitoring_dashboard      frontend   5174   healthy       200    0.052      running         OK
localhost            metrics_api               backend    5003   healthy       200    0.029      running         OK
localhost            admin_portal              frontend   5175   healthy       200    0.041      running         OK
```

**Output Example (JSON):**
```json
{
  "timestamp": "2025-10-27T12:00:00Z",
  "checks": [
    {
      "node": "localhost",
      "service": "dashboard",
      "type": "frontend",
      "port": 5173,
      "status": "healthy",
      "http_code": 200,
      "response_time": 0.045,
      "systemd_status": "running",
      "message": "OK"
    }
  ]
}
```

### Keepalived Integration

Health checks can be integrated with Keepalived for VIP failover:

```bash
# /etc/keepalived/check_web_services.sh
#!/bin/bash
/path/to/cluster/utils/web_health_check.sh --format compact
exit $?
```

Add to `keepalived.conf`:
```
vrrp_script check_web_services {
    script "/etc/keepalived/check_web_services.sh"
    interval 10
    weight -20
    fall 3
    rise 2
}
```

## SSL/TLS Configuration

### Let's Encrypt Setup

The setup script automatically configures Let's Encrypt SSL certificates.

**Manual Setup:**
```bash
# Stop Nginx temporarily
sudo systemctl stop nginx

# Obtain certificate
sudo certbot certonly --standalone \
  -d cluster.example.com \
  --non-interactive \
  --agree-tos \
  --email admin@example.com

# Start Nginx
sudo systemctl start nginx
```

**Certificate Locations:**
- Certificate: `/etc/letsencrypt/live/cluster.example.com/fullchain.pem`
- Private Key: `/etc/letsencrypt/live/cluster.example.com/privkey.pem`

**Auto-Renewal:**
```bash
# Add to crontab
0 0 * * * certbot renew --quiet --post-hook 'systemctl reload nginx'

# Test renewal
sudo certbot renew --dry-run
```

### Self-Signed Certificates (Testing)

For testing without a real domain:

```bash
# Generate self-signed certificate
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/selfsigned.key \
  -out /etc/ssl/certs/selfsigned.crt \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=cluster.local"

# Update Nginx config to use self-signed cert
sudo sed -i 's|/etc/letsencrypt/live/.*|/etc/ssl/certs/selfsigned.crt|' /etc/nginx/sites-available/web_services
sudo sed -i 's|/etc/letsencrypt/live/.*/privkey.pem|/etc/ssl/private/selfsigned.key|' /etc/nginx/sites-available/web_services

# Reload Nginx
sudo systemctl reload nginx
```

## Load Balancing

Nginx distributes requests across all web-enabled controllers.

**Load Balancing Algorithms:**

1. **Round-robin (default):**
   ```nginx
   upstream dashboard_backend {
       server 192.168.1.101:5173;
       server 192.168.1.102:5173;
       server 192.168.1.103:5173;
   }
   ```

2. **Least connections:**
   ```nginx
   upstream dashboard_backend {
       least_conn;
       server 192.168.1.101:5173;
       server 192.168.1.102:5173;
   }
   ```

3. **IP hash (sticky sessions):**
   ```nginx
   upstream websocket_backend {
       ip_hash;  # Required for WebSocket
       server 192.168.1.101:5010;
       server 192.168.1.102:5010;
   }
   ```

4. **Weighted:**
   ```nginx
   upstream dashboard_backend {
       server 192.168.1.101:5173 weight=3;
       server 192.168.1.102:5173 weight=2;
       server 192.168.1.103:5173 weight=1;
   }
   ```

## Monitoring and Logging

### Service Logs

Each service logs to its own file:

```bash
# Service logs
tail -f /var/log/web_services/dashboard.log
tail -f /var/log/web_services/auth_service.log
tail -f /var/log/web_services/job_api.log
tail -f /var/log/web_services/websocket_service.log
tail -f /var/log/web_services/file_service.log
tail -f /var/log/web_services/monitoring_dashboard.log
tail -f /var/log/web_services/metrics_api.log
tail -f /var/log/web_services/admin_portal.log

# Service error logs
tail -f /var/log/web_services/*.error.log

# Nginx logs
tail -f /var/log/nginx/web_services_access.log
tail -f /var/log/nginx/web_services_error.log
```

### Systemd Journal

```bash
# Follow specific service
journalctl -u dashboard -f

# Show last 100 lines
journalctl -u auth_service -n 100

# Show errors only
journalctl -u job_api -p err

# All web services
journalctl -u dashboard -u auth_service -u job_api -f
```

### Prometheus Integration

Metrics API exposes Prometheus-compatible metrics:

```yaml
# /etc/prometheus/prometheus.yml
scrape_configs:
  - job_name: 'cluster_web_services'
    static_configs:
      - targets:
        - '192.168.1.101:5003'
        - '192.168.1.102:5003'
        - '192.168.1.103:5003'
    scrape_interval: 15s
```

## Troubleshooting

### Issue: Services fail to start

**Check service status:**
```bash
systemctl status dashboard
journalctl -u dashboard -n 50
```

**Common causes:**
1. Port already in use
2. Missing dependencies
3. Incorrect environment variables
4. Permission issues

**Solutions:**
```bash
# Check port usage
sudo lsof -i :5173

# Reinstall dependencies
cd /opt/web_services/dashboard
sudo -u webservice npm install

# Check environment file
cat /opt/web_services/dashboard/.env

# Fix permissions
sudo chown -R webservice:webservice /opt/web_services/dashboard
```

### Issue: Nginx configuration test fails

```bash
# Test configuration
sudo nginx -t

# Common errors:
# - Upstream server unreachable
# - SSL certificate not found
# - Syntax error in config

# Fix and reload
sudo nano /etc/nginx/sites-available/web_services
sudo nginx -t && sudo systemctl reload nginx
```

### Issue: SSL certificate generation fails

```bash
# Check DNS resolution
dig cluster.example.com

# Check firewall
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Check if port 80 is available
sudo lsof -i :80

# Try standalone mode
sudo systemctl stop nginx
sudo certbot certonly --standalone -d cluster.example.com
sudo systemctl start nginx
```

### Issue: WebSocket connection fails

**Check:**
1. Nginx WebSocket configuration
2. Firewall rules
3. JWT token validity

**Fix Nginx WebSocket:**
```nginx
location /ws {
    proxy_pass http://websocket_backend;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 86400s;
    proxy_send_timeout 86400s;
}
```

### Issue: High memory usage

**Check resource usage:**
```bash
# Memory usage by service
ps aux | grep node | awk '{print $2, $4, $11}'

# Systemd memory limits
systemctl show dashboard | grep Memory
```

**Reduce memory:**
```bash
# Edit systemd service
sudo systemctl edit dashboard

# Add memory limit
[Service]
MemoryLimit=512M
Environment="NODE_OPTIONS=--max-old-space-size=512"

# Restart service
sudo systemctl daemon-reload
sudo systemctl restart dashboard
```

## Security

### Authentication

All API endpoints require JWT authentication:

```bash
# Login
curl -X POST https://cluster.example.com/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"user","password":"pass"}'

# Response
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user": {"id": 1, "username": "user", "role": "user"}
}

# Use token
curl https://cluster.example.com/api/jobs \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
```

### CORS Configuration

CORS is configured to allow only the cluster domain:

```javascript
// Express CORS config
app.use(cors({
  origin: 'https://cluster.example.com',
  credentials: true
}));
```

### Rate Limiting

Nginx rate limiting protects against abuse:

```nginx
# General rate limit: 10 req/s per IP
limit_req_zone $binary_remote_addr zone=general:10m rate=10r/s;

# Auth rate limit: 5 req/s per IP
limit_req_zone $binary_remote_addr zone=auth:10m rate=5r/s;

# API rate limit: 20 req/s per IP
limit_req_zone $binary_remote_addr zone=api:10m rate=20r/s;
```

### Security Headers

```nginx
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
```

### Firewall Configuration

```bash
# Allow HTTP/HTTPS
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Block direct access to service ports from external
sudo ufw deny from any to any port 5000:5200 proto tcp

# Allow internal network
sudo ufw allow from 192.168.1.0/24 to any port 5000:5200 proto tcp
```

## Backup and Restore

### Backup Web Services

```bash
# Backup configuration and uploads
sudo tar czf /var/backups/web_services_$(date +%Y%m%d).tar.gz \
  /opt/web_services/config \
  /opt/web_services/uploads \
  /etc/nginx/sites-available/web_services \
  /etc/letsencrypt

# Backup with cluster backup system
sudo ./cluster/backup/backup.sh --services config
```

### Restore Web Services

```bash
# Extract backup
sudo tar xzf /var/backups/web_services_20251027.tar.gz -C /

# Restart services
sudo systemctl restart dashboard auth_service job_api \
  websocket_service file_service monitoring_dashboard \
  metrics_api admin_portal nginx
```

## Performance Tuning

### Node.js Optimization

```bash
# Increase memory limit
export NODE_OPTIONS="--max-old-space-size=2048"

# Enable cluster mode (PM2)
npm install -g pm2
pm2 start src/server.js -i max --name auth_service
```

### Nginx Optimization

```nginx
# Worker processes
worker_processes auto;

# Worker connections
events {
    worker_connections 4096;
}

# Gzip compression
gzip on;
gzip_types text/plain text/css application/json application/javascript;

# Caching
proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=my_cache:10m;
```

### Database Connection Pooling

```javascript
// MySQL connection pool
const pool = mysql.createPool({
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  connectionLimit: 10,
  queueLimit: 0
});
```

## Next Steps

After completing Phase 6:

1. **Test all services**
   ```bash
   ./utils/web_health_check.sh --all-nodes
   ```

2. **Access web interface**
   ```bash
   firefox https://cluster.example.com
   ```

3. **Configure monitoring**
   - Set up Prometheus scraping
   - Configure Grafana dashboards

4. **Setup backups**
   ```bash
   sudo crontab -e
   # Add: 0 2 * * * /path/to/backup.sh
   ```

5. **Proceed to Phase 8: Main Integration Script**

## Summary

Phase 6 provides:
- ✅ 8 production-ready web services
- ✅ Nginx reverse proxy with SSL
- ✅ Automatic SSL certificate management
- ✅ Systemd service management
- ✅ Health check monitoring
- ✅ Load balancing across controllers
- ✅ Real-time WebSocket updates
- ✅ RESTful APIs for all cluster functions
- ✅ Admin and user interfaces

The cluster now has a complete web-based interface for user interaction!

## References

- [Phase 0: Basic Infrastructure](README_PHASE0.md)
- [Phase 1: GlusterFS](README_PHASE1.md)
- [Phase 2: MariaDB Galera](README_PHASE2.md)
- [Phase 3: Redis Cluster](README_PHASE3.md)
- [Phase 4: Slurm Multi-Master](README_PHASE4.md)
- [Phase 5: Keepalived VIP](README_PHASE5.md)
- [Phase 7: Backup and Restore](README_PHASE7.md)
- [my_multihead_cluster.yaml Configuration](../../my_multihead_cluster.yaml)
- [MULTIHEAD_IMPLEMENTATION_PLAN.md](../../MULTIHEAD_IMPLEMENTATION_PLAN.md)
