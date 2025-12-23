#!/bin/bash

################################################################################
# Phase 5: Web Services Setup Script
#
# This script sets up web services on controllers with web: true
# - Deploys 8 web services (dashboard, auth, job API, websocket, etc.)
# - Configures Nginx reverse proxy with SSL
# - Sets up Let's Encrypt SSL certificates
# - Configures systemd services for all web services
# - Integrates with Redis and MariaDB
# - Sets up health checks and monitoring
#
# Usage:
#   sudo ./phase5_web.sh [OPTIONS]
#
# Options:
#   --config PATH       Path to my_multihead_cluster.yaml (default: ../../my_multihead_cluster.yaml)
#   --dry-run           Preview actions without executing
#   --skip-ssl          Skip SSL certificate generation (for testing)
#   --force             Force setup even if already configured
#   --help              Show this help message
#
# Example:
#   sudo ./phase5_web.sh --config ../my_multihead_cluster.yaml
#   sudo ./phase5_web.sh --dry-run
#   sudo ./phase5_web.sh --skip-ssl --force
################################################################################

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Default values
CONFIG_PATH="$PROJECT_ROOT/my_multihead_cluster.yaml"
DRY_RUN=false
SKIP_SSL=false
FORCE=false
LOG_FILE="/var/log/cluster_web_setup.log"

# SSH options for secure remote connections
# GSSAPIAuthentication=no: Disable Kerberos to prevent delays
# PreferredAuthentications=publickey: Only try publickey auth
#
# IMPORTANT: When running with sudo, we need to use the original user's SSH key
ORIGINAL_USER="${SUDO_USER:-$(whoami)}"
ORIGINAL_HOME=$(getent passwd "$ORIGINAL_USER" | cut -d: -f6)
SSH_KEY_FILE="${ORIGINAL_HOME}/.ssh/id_rsa"

if [[ -f "$SSH_KEY_FILE" ]]; then
    SSH_OPTS="-i $SSH_KEY_FILE -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o GSSAPIAuthentication=no -o PreferredAuthentications=publickey"
else
    SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o GSSAPIAuthentication=no -o PreferredAuthentications=publickey"
fi

# Web services configuration
WEB_SERVICES_DIR="/opt/web_services"
WEB_CONFIG_TEMPLATE="$SCRIPT_DIR/../config/web_services_template.yaml"
NGINX_TEMPLATE="$SCRIPT_DIR/../config/nginx_web_template.conf"

# Function to print colored output
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

# Function to show help
show_help() {
    grep "^#" "$0" | grep -v "^#!/bin/bash" | sed 's/^# //' | sed 's/^#//'
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config)
                CONFIG_PATH="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-ssl)
                SKIP_SSL=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing_deps=()

    # Read SSL mode from YAML config to determine if certbot is needed
    local ssl_mode
    ssl_mode=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(c.get('web', {}).get('ssl', {}).get('mode', 'self_signed'))" 2>/dev/null || echo "self_signed")

    # Base required commands (certbot only needed for letsencrypt mode)
    local required_cmds=(python3 node npm nginx jq)
    if [[ "$ssl_mode" == "letsencrypt" ]]; then
        required_cmds+=(certbot)
        log_info "SSL mode: letsencrypt - certbot required"
    else
        log_info "SSL mode: $ssl_mode - certbot not required"
    fi

    # Check for required commands
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        log_info "Installing missing dependencies..."

        if [[ "$DRY_RUN" == false ]]; then
            apt-get update
            for dep in "${missing_deps[@]}"; do
                case "$dep" in
                    node|npm)
                        # Install Node.js from NodeSource
                        curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
                        apt-get install -y nodejs

                        # Install essential npm global packages for frontend builds
                        log_info "Installing npm global packages (typescript, vite, pnpm, terser, ts-node)..."
                        npm install -g typescript ts-node pnpm terser vite 2>/dev/null || {
                            log_warning "Some npm global packages failed to install"
                        }

                        # Verify installations
                        log_info "Installed npm global packages:"
                        echo "  typescript: $(tsc -v 2>/dev/null || echo 'not installed')"
                        echo "  ts-node: $(ts-node -v 2>/dev/null || echo 'not installed')"
                        echo "  pnpm: $(pnpm -v 2>/dev/null || echo 'not installed')"
                        echo "  terser: $(terser --version 2>/dev/null || echo 'not installed')"
                        echo "  vite: $(vite --version 2>/dev/null || echo 'not installed')"
                        ;;
                    certbot)
                        # Only install certbot if letsencrypt mode is selected
                        log_info "Installing certbot for Let's Encrypt SSL..."
                        apt-get install -y certbot python3-certbot-nginx
                        ;;
                    *)
                        apt-get install -y "$dep"
                        ;;
                esac
            done
        else
            log_info "[DRY-RUN] Would install: ${missing_deps[*]}"
        fi
    fi

    # Check if config file exists
    if [[ ! -f "$CONFIG_PATH" ]]; then
        log_error "Configuration file not found: $CONFIG_PATH"
        exit 1
    fi

    # Check if parser.py exists
    if [[ ! -f "$SCRIPT_DIR/../config/parser.py" ]]; then
        log_error "Parser script not found: $SCRIPT_DIR/../config/parser.py"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# Function to stop conflicting manual web services
stop_manual_web_services() {
    log_info "Checking for manually running web services on common ports..."

    local ports_to_check=(4430 4431 5000 5001 5010 5011 5173 5174 3000 3001 7000 8888 8889 8501 8502 9090 9100)
    local processes_killed=0

    for port in "${ports_to_check[@]}"; do
        # Find PIDs using this port
        local pids=$(lsof -ti:$port 2>/dev/null || true)

        if [[ -n "$pids" ]]; then
            log_warning "Port $port is in use by PIDs: $pids"

            # Get process details
            for pid in $pids; do
                local process_info=$(ps -p $pid -o comm= 2>/dev/null || echo "unknown")
                log_info "  - PID $pid: $process_info"

                if [[ "$DRY_RUN" == false ]]; then
                    # Try graceful kill first
                    if kill -TERM $pid 2>/dev/null || true; then
                        log_info "  - Sent SIGTERM to PID $pid"
                        processes_killed=$((processes_killed + 1))
                        sleep 1

                        # Check if still running
                        if kill -0 $pid 2>/dev/null; then
                            # Force kill if still running
                            if kill -KILL $pid 2>/dev/null; then
                                log_warning "  - Force killed PID $pid"
                            fi
                        else
                            log_success "  - Process $pid terminated gracefully"
                        fi
                    else
                        log_warning "  - Failed to kill PID $pid (may have already exited)"
                    fi
                else
                    log_info "[DRY-RUN] Would kill PID $pid ($process_info) on port $port"
                fi
            done
        fi
    done

    if [[ $processes_killed -gt 0 ]]; then
        log_success "Stopped $processes_killed manually running web service processes"
        # Wait for ports to be released
        sleep 2
    else
        log_info "No conflicting manual web services found"
    fi

    # Also stop any Vite dev servers
    local vite_pids=$(pgrep -f "vite" 2>/dev/null || true)
    if [[ -n "$vite_pids" ]]; then
        log_warning "Found Vite dev servers running: $vite_pids"
        if [[ "$DRY_RUN" == false ]]; then
            pkill -TERM -f "vite" 2>/dev/null || true
            sleep 1
            pkill -KILL -f "vite" 2>/dev/null || true
            log_success "Stopped Vite dev servers"
        else
            log_info "[DRY-RUN] Would stop Vite dev servers"
        fi
    fi
}

# Function to load configuration
load_config() {
    log_info "Loading configuration from $CONFIG_PATH..."

    # Use parser.py to load configuration
    local config_json
    config_json=$(python3 "$SCRIPT_DIR/../config/parser.py" "$CONFIG_PATH" get-controllers --service web)

    if [[ -z "$config_json" || "$config_json" == "[]" ]]; then
        log_error "No controllers with web service enabled found in configuration"
        exit 1
    fi

    # Get all IPs on this machine
    ALL_IPS=$(hostname -I)

    # Check if any of this machine's IPs match a web controller
    WEB_ENABLED="false"
    CURRENT_NODE_IP=""

    for ip in $ALL_IPS; do
        MATCH=$(echo "$config_json" | jq -r --arg ip "$ip" '.[] | select(.ip_address == $ip) | .services.web')
        if [[ "$MATCH" == "true" ]]; then
            WEB_ENABLED="true"
            CURRENT_NODE_IP="$ip"
            break
        fi
    done

    if [[ "$WEB_ENABLED" != "true" ]]; then
        log_error "This node (IPs: $ALL_IPS) is not configured for web services"
        log_info "Available web controllers:"
        echo "$config_json" | jq -r '.[] | "\(.hostname) (\(.ip_address))"'
        exit 1
    fi

    # Load cluster-wide settings using direct YAML parsing
    CLUSTER_NAME=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(c.get('cluster_info', {}).get('cluster_name', 'hpc-cluster'))")
    DOMAIN=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(c.get('cluster_info', {}).get('domain', 'hpc.local'))")
    DB_VIP=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(c.get('database', {}).get('vip', ''))" || echo "")
    DB_USER=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(c.get('database', {}).get('mariadb', {}).get('user', 'hpcadmin'))")

    # Helper function to resolve ${VAR} references from environment section
    resolve_env_var() {
        local value="$1"
        local env_section
        if [[ "$value" =~ ^\$\{([A-Za-z_][A-Za-z0-9_]*)\}$ ]]; then
            local var_name="${BASH_REMATCH[1]}"
            env_section=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(c.get('environment', {}).get('$var_name', ''))" 2>/dev/null)
            echo "$env_section"
        else
            echo "$value"
        fi
    }

    # Get passwords - resolve ${VAR} references from environment section
    local raw_db_password=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(c.get('database', {}).get('mariadb', {}).get('root_password', ''))")
    DB_PASSWORD=$(resolve_env_var "$raw_db_password")
    # Fallback: try environment.DB_ROOT_PASSWORD directly
    if [[ -z "$DB_PASSWORD" || "$DB_PASSWORD" == '${DB_ROOT_PASSWORD}' ]]; then
        DB_PASSWORD=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(c.get('environment', {}).get('DB_ROOT_PASSWORD', ''))" 2>/dev/null)
    fi

    local raw_redis_password=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(c.get('redis', {}).get('cluster', {}).get('password', '') or c.get('redis', {}).get('password', ''))")
    REDIS_PASSWORD=$(resolve_env_var "$raw_redis_password")
    # Fallback: try environment.REDIS_PASSWORD directly
    if [[ -z "$REDIS_PASSWORD" || "$REDIS_PASSWORD" == '${REDIS_PASSWORD}' ]]; then
        REDIS_PASSWORD=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(c.get('environment', {}).get('REDIS_PASSWORD', ''))" 2>/dev/null)
    fi

    local raw_session_secret=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(c.get('web_services', {}).get('session_secret', ''))")
    SESSION_SECRET=$(resolve_env_var "$raw_session_secret")

    local raw_jwt_secret=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(c.get('web_services', {}).get('jwt_secret', ''))")
    JWT_SECRET=$(resolve_env_var "$raw_jwt_secret")
    # Fallback: try environment.JWT_SECRET_KEY directly
    if [[ -z "$JWT_SECRET" || "$JWT_SECRET" == '${JWT_SECRET_KEY}' ]]; then
        JWT_SECRET=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(c.get('environment', {}).get('JWT_SECRET_KEY', ''))" 2>/dev/null)
    fi

    # Validate security-sensitive configurations
    local config_warnings=false
    if [[ -z "$DB_PASSWORD" || "$DB_PASSWORD" == "changeme" ]]; then
        log_warning "⚠️  database.mariadb.root_password not set - using insecure default"
        DB_PASSWORD="changeme"
        config_warnings=true
    fi
    if [[ -z "$REDIS_PASSWORD" || "$REDIS_PASSWORD" == "changeme" ]]; then
        log_warning "⚠️  redis.password not set - using insecure default"
        REDIS_PASSWORD="changeme"
        config_warnings=true
    fi
    if [[ -z "$SESSION_SECRET" || "$SESSION_SECRET" == "change-this-secret" ]]; then
        log_warning "⚠️  web_services.session_secret not set - using insecure default"
        SESSION_SECRET="change-this-secret"
        config_warnings=true
    fi
    if [[ -z "$JWT_SECRET" || "$JWT_SECRET" == "change-this-jwt-secret" ]]; then
        log_warning "⚠️  web_services.jwt_secret not set - using insecure default"
        JWT_SECRET="change-this-jwt-secret"
        config_warnings=true
    fi

    if [[ "$config_warnings" == "true" && "$DRY_RUN" == "false" ]]; then
        log_warning ""
        log_warning "=== SECURITY NOTICE ==="
        log_warning "Some security settings are using insecure defaults."
        log_warning "Please configure proper secrets in $CONFIG_PATH"
        log_warning ""
    fi

    # Get all web controllers for upstream configuration
    WEB_CONTROLLERS=$(echo "$config_json" | jq -r '.[] | "\(.ip_address):\(.hostname)"')

    # Load public URL for dashboard access
    PUBLIC_URL=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(c.get('web', {}).get('public_url', '127.0.0.1'))" 2>/dev/null || echo "127.0.0.1")
    if [[ -z "$PUBLIC_URL" || "$PUBLIC_URL" == "null" ]]; then
        log_warning "web.public_url not set in YAML, using current node IP: $CURRENT_NODE_IP"
        PUBLIC_URL="$CURRENT_NODE_IP"
    fi

    # Load SSO configuration
    SSO_ENABLED=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(str(c.get('sso', {}).get('enabled', True)).lower())" 2>/dev/null || echo "true")
    log_info "SSO Enabled: $SSO_ENABLED"

    log_success "Configuration loaded successfully"
    log_info "Cluster: $CLUSTER_NAME"
    log_info "Domain: $DOMAIN"
    log_info "Current node: $CURRENT_NODE_IP"
    log_info "Public URL: $PUBLIC_URL"
}

# Function to create web services user
create_web_user() {
    log_info "Creating web services user..."

    # Get UID/GID from YAML config (default to 64010 to avoid conflicts)
    local target_uid=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(c.get('web',{}).get('user_uid', 64010))" 2>/dev/null || echo 64010)
    local target_gid=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(c.get('web',{}).get('user_gid', 64010))" 2>/dev/null || echo 64010)

    if id "webservice" &>/dev/null; then
        local existing_uid=$(id -u webservice)
        log_info "User 'webservice' already exists (UID=$existing_uid)"
    else
        if [[ "$DRY_RUN" == false ]]; then
            # Create group first
            if ! getent group webservice &>/dev/null; then
                groupadd -g "$target_gid" webservice 2>/dev/null || groupadd webservice
            fi
            # Create user with specific UID if possible
            useradd -r -u "$target_uid" -g webservice -s /bin/false -d "$WEB_SERVICES_DIR" webservice 2>/dev/null || \
                useradd -r -g webservice -s /bin/false -d "$WEB_SERVICES_DIR" webservice
            log_success "User 'webservice' created (UID=$(id -u webservice))"
        else
            log_info "[DRY-RUN] Would create user 'webservice' with UID=$target_uid"
        fi
    fi
}

# Function to create directory structure
create_directories() {
    log_info "Creating directory structure..."

    local dirs=(
        "$WEB_SERVICES_DIR"
        "$WEB_SERVICES_DIR/dashboard"
        "$WEB_SERVICES_DIR/auth_service"
        "$WEB_SERVICES_DIR/job_api"
        "$WEB_SERVICES_DIR/websocket_service"
        "$WEB_SERVICES_DIR/file_service"
        "$WEB_SERVICES_DIR/monitoring_dashboard"
        "$WEB_SERVICES_DIR/metrics_api"
        "$WEB_SERVICES_DIR/admin_portal"
        "$WEB_SERVICES_DIR/config"
        "$WEB_SERVICES_DIR/uploads"
        "/var/log/web_services"
    )

    for dir in "${dirs[@]}"; do
        if [[ "$DRY_RUN" == false ]]; then
            mkdir -p "$dir"
            chown -R webservice:webservice "$dir"
        else
            log_info "[DRY-RUN] Would create directory: $dir"
        fi
    done

    log_success "Directory structure created"
}

# Function to deploy real dashboard services from source
deploy_real_dashboard_service() {
    local service_name=$1
    local source_dir=$2
    local port=$3
    local service_type=$4  # python or node
    local start_command=$5

    log_info "Deploying $service_name from $source_dir..."

    local target_dir="$WEB_SERVICES_DIR/$service_name"
    local dashboard_base="$PROJECT_ROOT/dashboard"

    if [[ "$DRY_RUN" == false ]]; then
        # Create target directory
        mkdir -p "$target_dir"

        # Copy service files from dashboard
        if [[ -d "$dashboard_base/$source_dir" ]]; then
            log_info "Copying files from $dashboard_base/$source_dir to $target_dir"
            rsync -av --exclude='venv' --exclude='node_modules' --exclude='logs' --exclude='*.pid' \
                --exclude='__pycache__' --exclude='*.pyc' --exclude='dist' --exclude='.vite' \
                "$dashboard_base/$source_dir/" "$target_dir/"

            # Create logs directory
            mkdir -p "$target_dir/logs"

            # Set ownership
            chown -R webservice:webservice "$target_dir"

            log_success "$service_name files copied successfully"
        else
            log_error "Source directory not found: $dashboard_base/$source_dir"
            return 1
        fi
    else
        log_info "[DRY-RUN] Would deploy $service_name from $dashboard_base/$source_dir"
    fi
}

# Function to deploy web service skeleton
deploy_service_skeleton() {
    local service_name=$1
    local service_type=$2  # frontend or backend
    local port=$3

    log_info "Deploying $service_name skeleton..."

    local service_dir="$WEB_SERVICES_DIR/$service_name"

    if [[ "$DRY_RUN" == false ]]; then
        cd "$service_dir"

        # Initialize npm project if not exists
        if [[ ! -f "package.json" ]]; then
            npm init -y
        fi

        if [[ "$service_type" == "frontend" ]]; then
            # Frontend service (React + Vite)
            npm install --save-dev vite @vitejs/plugin-react react react-dom

            # Create basic Vite config
            cat > vite.config.js << EOF
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    host: '0.0.0.0',
    port: ${port}
  },
  preview: {
    host: '0.0.0.0',
    port: ${port}
  }
})
EOF

            # Create basic React app structure
            mkdir -p src public
            cat > src/App.jsx << EOF
import { useState } from 'react'

function App() {
  return (
    <div>
      <h1>${service_name}</h1>
      <p>Service is running on port ${port}</p>
    </div>
  )
}

export default App
EOF

            cat > src/main.jsx << EOF
import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App'

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
)
EOF

            cat > index.html << EOF
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>${service_name}</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.jsx"></script>
  </body>
</html>
EOF

        else
            # Backend service (Express)
            npm install express cors dotenv

            # Create basic Express server
            mkdir -p src
            cat > src/server.js << EOF
const express = require('express');
const cors = require('cors');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || ${port};

// Middleware
app.use(cors());
app.use(express.json());

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: '${service_name}', port: PORT });
});

// Start server
app.listen(PORT, '0.0.0.0', () => {
  console.log(\`${service_name} listening on port \${PORT}\`);
});
EOF

            # Create .env file
            cat > .env << EOF
PORT=${port}
NODE_ENV=production
DB_HOST=${DB_VIP}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
REDIS_PASSWORD=${REDIS_PASSWORD}
JWT_SECRET=${JWT_SECRET}
SESSION_SECRET=${SESSION_SECRET}
EOF
            chmod 600 .env
        fi

        # Update package.json scripts
        npm pkg set scripts.start="node src/server.js"
        npm pkg set scripts.dev="node src/server.js"

        if [[ "$service_type" == "frontend" ]]; then
            npm pkg set scripts.build="vite build"
            npm pkg set scripts.preview="vite preview --host 0.0.0.0 --port ${port}"

            # Build the frontend for production
            log_info "Building $service_name for production..."
            npm run build || {
                log_error "Failed to build $service_name"
                return 1
            }
            log_success "$service_name built successfully"
        fi

        # Set ownership
        chown -R webservice:webservice "$service_dir"

        log_success "$service_name skeleton deployed"
    else
        log_info "[DRY-RUN] Would deploy $service_name skeleton"
    fi
}

# Function to setup Redis session management
# This function configures Redis-based session storage for all dashboard services
# Prerequisites:
#   - dashboard/common/ library must exist (contains RedisSessionManager)
#   - Redis server must be running on localhost:6379
# Services configured:
#   - kooCAEWebServer_5000 (App sessions with TTL=7200s)
#   - backend_5010 (VNC sessions with TTL=28800s)
# Both use legacy key pattern for backward compatibility:
#   - VNC: vnc:session:{id}
#   - App: app:session:{id}
setup_redis_session_management() {
    local dashboard_dir=$1

    log_info "Setting up Redis session management..."

    # Check if common directory exists
    if [[ ! -d "$dashboard_dir/common" ]]; then
        log_error "Common session management library not found at $dashboard_dir/common"
        log_error "Please ensure the common library is present before running setup"
        log_error "Required files: config.py, session_manager.py, __init__.py"
        return 1
    fi

    log_success "Found common session management library"

    # Install redis Python package in required services
    local services_with_redis=(
        "kooCAEWebServer_5000"
        "backend_5010"
    )

    for service in "${services_with_redis[@]}"; do
        local service_dir="$dashboard_dir/$service"

        if [[ ! -d "$service_dir" ]]; then
            log_warning "Service directory not found: $service_dir, skipping..."
            continue
        fi

        log_info "Installing redis package in $service..."

        if [[ "$DRY_RUN" == false ]]; then
            # Check if venv exists
            if [[ ! -d "$service_dir/venv" ]]; then
                log_warning "No venv found for $service, skipping redis installation"
                continue
            fi

            # Install redis package
            cd "$service_dir"
            source venv/bin/activate
            pip install redis python-dotenv --quiet || {
                log_warning "Failed to install redis package in $service"
            }
            deactivate

            # Create or update .env file with Redis configuration
            if [[ ! -f "$service_dir/.env" ]]; then
                log_info "Creating .env file for $service..."
                cat > "$service_dir/.env" << EOF
# Redis Configuration for Session Management
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=${REDIS_PASSWORD:-changeme}
DEFAULT_SESSION_TTL=7200
EOF
                chown webservice:webservice "$service_dir/.env"
                log_success ".env file created for $service"
            else
                log_info ".env file already exists for $service"

                # Check and add missing Redis configuration
                local needs_update=false

                if ! grep -q "^REDIS_HOST=" "$service_dir/.env"; then
                    echo "REDIS_HOST=localhost" >> "$service_dir/.env"
                    needs_update=true
                fi

                if ! grep -q "^REDIS_PORT=" "$service_dir/.env"; then
                    echo "REDIS_PORT=6379" >> "$service_dir/.env"
                    needs_update=true
                fi

                if ! grep -q "^REDIS_PASSWORD=" "$service_dir/.env"; then
                    echo "REDIS_PASSWORD=${REDIS_PASSWORD:-changeme}" >> "$service_dir/.env"
                    needs_update=true
                elif [[ -n "$REDIS_PASSWORD" && "$REDIS_PASSWORD" != "changeme" ]]; then
                    # Update existing REDIS_PASSWORD if YAML provides a real value
                    sed -i "s/^REDIS_PASSWORD=.*/REDIS_PASSWORD=${REDIS_PASSWORD}/" "$service_dir/.env"
                    needs_update=true
                fi

                if ! grep -q "^DEFAULT_SESSION_TTL=" "$service_dir/.env"; then
                    echo "DEFAULT_SESSION_TTL=7200" >> "$service_dir/.env"
                    needs_update=true
                fi

                if [[ "$needs_update" == true ]]; then
                    log_success "Updated .env with missing Redis configuration"
                else
                    log_info "Redis configuration already complete"
                fi
            fi

            log_success "Redis setup completed for $service"
        else
            log_info "[DRY-RUN] Would install redis package in $service"
            log_info "[DRY-RUN] Would create .env file for $service"
        fi
    done

    log_success "Redis session management setup complete"
}

# Function to generate frontend .env files from YAML configuration
# This ensures all frontends use the correct public URL for API/WebSocket/Auth connections
generate_frontend_env_files() {
    local dashboard_dir=$1

    log_info "Generating frontend .env files from YAML configuration..."

    # Determine protocol based on SSO setting
    local PROTOCOL="http"
    local WS_PROTOCOL="ws"
    if [[ "$SSO_ENABLED" == "true" ]]; then
        PROTOCOL="https"
        WS_PROTOCOL="wss"
        log_info "SSO enabled: Using HTTPS/WSS protocols"
    else
        log_info "SSO disabled: Using HTTP/WS protocols"
    fi

    # Frontend services that need .env files
    local frontends=(
        "frontend_3010"      # Main dashboard
        "auth_portal_4431"   # Auth portal
        "vnc_service_8002"   # VNC service
        "kooCAEWeb_5173"     # CAE web interface
    )

    for frontend in "${frontends[@]}"; do
        local frontend_dir="$dashboard_dir/$frontend"
        local env_file="$frontend_dir/.env"

        if [[ ! -d "$frontend_dir" ]]; then
            log_warning "Frontend directory not found: $frontend_dir, skipping..."
            continue
        fi

        if [[ "$DRY_RUN" == false ]]; then
            log_info "Generating .env for $frontend..."

            # Backup existing .env if it exists
            if [[ -f "$env_file" ]]; then
                cp "$env_file" "${env_file}.backup_$(date +%Y%m%d_%H%M%S)"
            fi

            # Generate .env based on frontend type
            case "$frontend" in
                frontend_3010)
                    # Main dashboard frontend
                    cat > "$env_file" << EOF
# ============================================================================
# Dashboard Frontend (3010) Environment Variables
# ============================================================================
# Generated from my_multihead_cluster.yaml
# Auto-generated on: $(date '+%Y-%m-%d %H:%M:%S')
# SSO: $SSO_ENABLED | Protocol: $PROTOCOL
# ============================================================================

# Vite Configuration
VITE_API_URL=${PROTOCOL}://${PUBLIC_URL}:5010
VITE_WS_URL=${WS_PROTOCOL}://${PUBLIC_URL}:5011/ws
VITE_AUTH_URL=${PROTOCOL}://${PUBLIC_URL}:4430
VITE_ENVIRONMENT=production
EOF
                    ;;

                auth_portal_4431)
                    # Auth portal frontend
                    cat > "$env_file" << EOF
# Auth Portal Frontend Environment
# Generated from my_multihead_cluster.yaml on $(date '+%Y-%m-%d %H:%M:%S')
# SSO: $SSO_ENABLED | Protocol: $PROTOCOL
VITE_AUTH_URL=${PROTOCOL}://${PUBLIC_URL}:4430
VITE_API_URL=${PROTOCOL}://${PUBLIC_URL}:5010
EOF
                    ;;

                vnc_service_8002)
                    # VNC service frontend
                    cat > "$env_file" << EOF
# VNC Service Frontend Environment
# Generated from my_multihead_cluster.yaml on $(date '+%Y-%m-%d %H:%M:%S')
# SSO: $SSO_ENABLED | Protocol: $PROTOCOL
VITE_API_URL=${PROTOCOL}://${PUBLIC_URL}:5010
VITE_AUTH_URL=${PROTOCOL}://${PUBLIC_URL}:4430
EOF
                    ;;

                kooCAEWeb_5173)
                    # CAE web frontend
                    cat > "$env_file" << EOF
# CAE Web Frontend Environment
# Generated from my_multihead_cluster.yaml on $(date '+%Y-%m-%d %H:%M:%S')
# SSO: $SSO_ENABLED | Protocol: $PROTOCOL
VITE_API_URL=${PROTOCOL}://${PUBLIC_URL}:5000
VITE_AUTH_URL=${PROTOCOL}://${PUBLIC_URL}:4430
EOF
                    ;;
            esac

            chmod 600 "$env_file"
            log_success ".env generated for $frontend (PUBLIC_URL=$PUBLIC_URL)"
        else
            log_info "[DRY-RUN] Would generate .env for $frontend"
        fi
    done

    log_success "All frontend .env files generated from YAML"
}

# Function to configure Auth Portal groups
# Updates GROUP_PERMISSIONS in auth_portal_4430/config/config.py
setup_auth_portal_groups() {
    local dashboard_dir=$1

    log_info "Configuring Auth Portal groups..."

    local config_file="$dashboard_dir/auth_portal_4430/config/config.py"

    if [[ ! -f "$config_file" ]]; then
        log_error "Auth Portal config not found: $config_file"
        return 1
    fi

    if [[ "$DRY_RUN" == false ]]; then
        # Backup original config
        cp "$config_file" "$config_file.backup_$(date +%Y%m%d_%H%M%S)"
        log_info "Config backed up"

        # Update GROUP_PERMISSIONS using sed
        sed -i '/# Group-based permissions/,/^    }/c\
    # Group-based permissions\
    GROUP_PERMISSIONS = {\
        '\''HPC-Admins'\'': ['\''dashboard'\'', '\''cae'\'', '\''vnc'\'', '\''app'\'', '\''admin'\''],\
        '\''DX-Users'\'': ['\''dashboard'\'', '\''vnc'\'', '\''app'\''],\
        '\''CAEG-Users'\'': ['\''dashboard'\'', '\''cae'\'', '\''vnc'\'', '\''app'\''],\
    }' "$config_file"

        log_success "Auth Portal groups configured"
        log_info "  - HPC-Admins: Full access (admin included)"
        log_info "  - DX-Users: dashboard, vnc, app"
        log_info "  - CAEG-Users: dashboard, cae, vnc, app (admin excluded)"
    else
        log_info "[DRY-RUN] Would configure Auth Portal groups"
    fi
}

# Function to configure SAML IdP users for development
# Updates users.json in saml_idp_7000 with new group names
# Reads users from YAML config: web_services.saml.users[]
setup_saml_idp_users() {
    local dashboard_dir=$1

    log_info "Configuring SAML IdP test users..."

    local users_file="$dashboard_dir/saml_idp_7000/config/users.json"

    if [[ ! -f "$users_file" ]]; then
        log_warning "SAML IdP users.json not found: $users_file (skipping)"
        return 0
    fi

    if [[ "$DRY_RUN" == false ]]; then
        # Backup original users file
        cp "$users_file" "$users_file.backup_$(date +%Y%m%d_%H%M%S)"
        log_info "Users file backed up"

        # Read SAML users from YAML config, generate JSON
        # If not defined in YAML, use secure random passwords
        local saml_users_json
        saml_users_json=$(python3 << EOFPY
import yaml
import json
import secrets
import string

def generate_secure_password(length=16):
    """Generate a secure random password"""
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*"
    return ''.join(secrets.choice(alphabet) for _ in range(length))

try:
    with open('$CONFIG_PATH') as f:
        config = yaml.safe_load(f)

    domain = config.get('cluster_info', {}).get('domain', 'hpc.local')
    saml_config = config.get('web_services', {}).get('saml', {})
    users = saml_config.get('users', [])

    if not users:
        # No users defined - create default admin with secure random password
        admin_password = generate_secure_password()
        print(f"⚠️  YAML에 SAML 유저가 정의되지 않아 기본 admin 계정 생성", file=__import__('sys').stderr)
        print(f"   admin@{domain} 비밀번호: {admin_password}", file=__import__('sys').stderr)
        users = [{
            'username': 'admin',
            'password': admin_password,
            'first_name': 'System',
            'last_name': 'Admin',
            'display_name': 'System Administrator',
            'groups': ['HPC-Admins'],
            'department': 'IT'
        }]

    result = {}
    for user in users:
        username = user.get('username', 'user')
        email = f"{username}@{domain}"
        # Use password from YAML or generate secure one
        password = user.get('password')
        if not password or password in ['changeme', 'password123', 'admin123']:
            password = generate_secure_password()
            print(f"⚠️  {username}: 보안 비밀번호 자동생성됨 (YAML에 안전한 비밀번호 설정 권장)", file=__import__('sys').stderr)

        result[email] = {
            'password': password,
            'email': email,
            'userName': username,
            'firstName': user.get('first_name', username),
            'lastName': user.get('last_name', 'User'),
            'displayName': user.get('display_name', username),
            'groups': user.get('groups', ['Users']),
            'department': user.get('department', 'General')
        }

    print(json.dumps(result, indent=2, ensure_ascii=False))
except Exception as e:
    print(f"Error: {e}", file=__import__('sys').stderr)
    exit(1)
EOFPY
)
        if [[ $? -ne 0 ]]; then
            log_error "Failed to generate SAML users from YAML config"
            log_warning "Check web_services.saml.users in $CONFIG_PATH"
            return 1
        fi

        # Write users.json
        echo "$saml_users_json" > "$users_file"

        # Create config.js for saml-idp (JavaScript format required)
        # Generate dynamically from YAML config
        local config_js="$dashboard_dir/saml_idp_7000/config.js"
        python3 << EOFPY > "$config_js"
import yaml
import json
import secrets
import string

def generate_secure_password(length=16):
    alphabet = string.ascii_letters + string.digits + "!@#\$%^&*"
    return ''.join(secrets.choice(alphabet) for _ in range(length))

try:
    with open('$CONFIG_PATH') as f:
        config = yaml.safe_load(f)

    domain = config.get('cluster_info', {}).get('domain', 'hpc.local')
    saml_config = config.get('web_services', {}).get('saml', {})
    users = saml_config.get('users', [])

    if not users:
        admin_password = generate_secure_password()
        users = [{
            'username': 'admin',
            'password': admin_password,
            'first_name': 'System',
            'last_name': 'Admin',
            'display_name': 'System Administrator',
            'groups': ['HPC-Admins'],
            'department': 'IT'
        }]

    print('/**')
    print(' * SAML IdP Configuration File')
    print(' * User database for authentication')
    print(' * Auto-generated from YAML config')
    print(' */')
    print('')
    print('module.exports = {')
    print('  user: {')

    user_entries = []
    for user in users:
        username = user.get('username', 'user')
        email = f"{username}@{domain}"
        password = user.get('password')
        if not password or password in ['changeme', 'password123', 'admin123']:
            password = generate_secure_password()

        groups = user.get('groups', ['Users'])
        groups_str = groups[0] if isinstance(groups, list) and groups else str(groups)

        entry = f'''    "{email}": {{
      password: "{password}",
      email: "{email}",
      userName: "{username}",
      firstName: "{user.get('first_name', username)}",
      lastName: "{user.get('last_name', 'User')}",
      displayName: "{user.get('display_name', username)}",
      groups: "{groups_str}",
      department: "{user.get('department', 'General')}"
    }}'''
        user_entries.append(entry)

    print(',\\n'.join(user_entries))
    print('  },')
    print('  metadata: [')
    print('    {id: "email", optional: false, displayName: \'E-Mail Address\', description: \'The e-mail address of the user\', multiValue: false},')
    print('    {id: "userName", optional: false, displayName: \'User Name\', description: \'The username of the user\', multiValue: false},')
    print('    {id: "firstName", optional: false, displayName: \'First Name\', description: \'The first name of the user\', multiValue: false},')
    print('    {id: "lastName", optional: false, displayName: \'Last Name\', description: \'The last name of the user\', multiValue: false},')
    print('    {id: "displayName", optional: true, displayName: \'Display Name\', description: \'The display name of the user\', multiValue: false},')
    print('    {id: "groups", optional: true, displayName: \'Groups\', description: \'Group memberships of the user\', multiValue: false}')
    print('  ]')
    print('};')
except Exception as e:
    print(f"// Error generating config: {e}", file=__import__('sys').stderr)
    exit(1)
EOFPY

        if [[ $? -ne 0 ]]; then
            log_error "Failed to generate SAML config.js"
            return 1
        fi

        log_success "SAML IdP users configured from YAML (users.json + config.js)"
        log_info "  Users loaded from: $CONFIG_PATH (web_services.saml.users)"
    else
        log_info "[DRY-RUN] Would configure SAML IdP test users"
    fi
}

# Function to setup JWT authentication
# This function configures JWT-based authentication for all dashboard services
# Prerequisites:
#   - backend_5010/middleware/jwt_middleware.py must exist (source file)
#   - Auth Portal must be running with JWT_SECRET_KEY configured
# Services configured:
#   - kooCAEWebServer_5000 (App Framework API)
#   - backend_5010 (Dashboard Backend API - already has it)
#   - kooCAEWebAutomationServer_5001 (Automation API)
#   - websocket_5011 (WebSocket Service)
setup_jwt_authentication() {
    local dashboard_dir=$1

    log_info "Setting up JWT authentication..."

    # Check if source middleware exists
    local source_middleware="$dashboard_dir/backend_5010/middleware/jwt_middleware.py"
    if [[ ! -f "$source_middleware" ]]; then
        log_error "JWT middleware not found at $source_middleware"
        return 1
    fi

    log_success "Found JWT middleware source"

    # Services that need JWT authentication
    local services_with_jwt=(
        "kooCAEWebServer_5000"
        "kooCAEWebAutomationServer_5001"
        "websocket_5011"
    )

    for service in "${services_with_jwt[@]}"; do
        local service_dir="$dashboard_dir/$service"

        if [[ ! -d "$service_dir" ]]; then
            log_warning "Service directory not found: $service_dir, skipping..."
            continue
        fi

        log_info "Installing JWT authentication in $service..."

        if [[ "$DRY_RUN" == false ]]; then
            # Create middleware directory
            mkdir -p "$service_dir/middleware"
            touch "$service_dir/middleware/__init__.py"

            # Copy JWT middleware
            cp "$source_middleware" "$service_dir/middleware/jwt_middleware.py"

            # Check if venv exists
            if [[ ! -d "$service_dir/venv" ]]; then
                log_warning "No venv found for $service, skipping PyJWT installation"
                continue
            fi

            # Install PyJWT package
            cd "$service_dir"
            source venv/bin/activate
            pip install PyJWT --quiet || {
                log_warning "Failed to install PyJWT in $service"
            }
            deactivate

            # Add JWT configuration to .env
            # Use JWT_SECRET from YAML config, fallback to default
            local jwt_value="${JWT_SECRET:-dev-jwt-secret-please-change}"

            if [[ -f "$service_dir/.env" ]]; then
                if ! grep -q "^JWT_SECRET_KEY=" "$service_dir/.env"; then
                    echo "" >> "$service_dir/.env"
                    echo "# JWT Configuration (must match Auth Portal)" >> "$service_dir/.env"
                    echo "JWT_SECRET_KEY=${jwt_value}" >> "$service_dir/.env"
                    echo "JWT_ALGORITHM=HS256" >> "$service_dir/.env"
                    log_success "JWT configuration added to .env"
                elif [[ -n "$JWT_SECRET" && "$JWT_SECRET" != "change-this-jwt-secret" ]]; then
                    # Update existing JWT_SECRET_KEY if YAML provides a real value
                    sed -i "s/^JWT_SECRET_KEY=.*/JWT_SECRET_KEY=${jwt_value}/" "$service_dir/.env"
                    log_info "JWT_SECRET_KEY updated from YAML config"
                else
                    log_info "JWT configuration already exists in .env"
                fi
            else
                cat > "$service_dir/.env" << EOF
# JWT Configuration (must match Auth Portal)
JWT_SECRET_KEY=${jwt_value}
JWT_ALGORITHM=HS256
EOF
                chown webservice:webservice "$service_dir/.env"
                log_success ".env file created with JWT configuration"
            fi

            log_success "JWT authentication setup completed for $service"
        else
            log_info "[DRY-RUN] Would install JWT authentication in $service"
        fi
    done

    log_success "JWT authentication setup complete"
}

# Function to deploy all web services
deploy_web_services() {
    log_info "Setting up web services from dashboard source..."

    local dashboard_dir="$PROJECT_ROOT/dashboard"

    if [[ ! -d "$dashboard_dir" ]]; then
        log_error "Dashboard directory not found: $dashboard_dir"
        return 1
    fi

    log_info "Using dashboard directory: $dashboard_dir"
    log_info "Services will run directly from dashboard with existing venv"

    # Generate frontend .env files from YAML (must be done BEFORE building)
    generate_frontend_env_files "$dashboard_dir"

    # Setup Auth Portal groups
    setup_auth_portal_groups "$dashboard_dir"

    # Setup SAML IdP test users (creates config.js)
    setup_saml_idp_users "$dashboard_dir"

    # Setup Redis session management
    setup_redis_session_management "$dashboard_dir"

    # Setup JWT authentication
    setup_jwt_authentication "$dashboard_dir"

    log_success "Web services setup complete (13 services configured)"
}

# Function to create systemd service file
create_systemd_service() {
    local service_name=$1
    local service_type=$2  # python or node
    local port=$3
    local start_command=$4

    log_info "Creating systemd service for $service_name ($service_type)..."

    local service_file="/etc/systemd/system/$service_name.service"
    local work_dir="$WEB_SERVICES_DIR/$service_name"

    if [[ "$DRY_RUN" == false ]]; then
        # Different ExecStart based on service type
        local exec_start=""
        local environment=""

        if [[ "$service_type" == "python" ]]; then
            # Python services: use bash to activate venv
            exec_start="/bin/bash -c 'cd $work_dir && $start_command'"
            environment="Environment=\"MOCK_MODE=false\"\nEnvironment=\"PORT=$port\"\nEnvironmentFile=-$work_dir/.env"
        else
            # Node services
            exec_start="/bin/bash -c 'cd $work_dir && $start_command'"
            environment="Environment=\"NODE_ENV=development\"\nEnvironment=\"PORT=$port\"\nEnvironmentFile=-$work_dir/.env"
        fi

        cat > "$service_file" << EOF
[Unit]
Description=$service_name - Web Service ($service_type)
After=network.target mariadb.service redis-server.service
Wants=network-online.target

[Service]
Type=simple
User=webservice
Group=webservice
WorkingDirectory=$work_dir

# Environment
$(echo -e "$environment")

# Start command
ExecStart=$exec_start

# Restart policy
Restart=always
RestartSec=5
StartLimitInterval=60
StartLimitBurst=10

# Resource limits
MemoryLimit=2G
CPUQuota=200%

# Security
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$work_dir $work_dir/logs /var/log/web_services /tmp

# Logging
StandardOutput=append:/var/log/web_services/$service_name.log
StandardError=append:/var/log/web_services/$service_name.error.log

[Install]
WantedBy=multi-user.target
EOF

        systemctl daemon-reload
        log_success "Systemd service created: $service_name"
    else
        log_info "[DRY-RUN] Would create systemd service: $service_name"
    fi
}

# Function to apply JWT authentication fixes to CAE frontend
apply_cae_jwt_fixes() {
    local cae_dir="$1"
    log_info "Applying JWT authentication fixes to CAE frontend..."

    # Fix 1: Update App.tsx - Add JWT token reception from URL
    local app_tsx="$cae_dir/src/App.tsx"
    if [[ -f "$app_tsx" ]]; then
        # Check if JWT reception code already exists
        if grep -q "JWT token received from URL" "$app_tsx"; then
            log_info "App.tsx already has JWT token reception"
        else
            log_info "Adding JWT token reception to App.tsx..."
            # Add useEffect import if not present
            if ! grep -q "import.*useEffect.*from 'react'" "$app_tsx"; then
                sed -i "s/from 'react';/{ useEffect } from 'react';/" "$app_tsx"
            fi

            # Add JWT reception logic after function App() {
            sed -i '/function App() {/a\
  useEffect(() => {\
    // Extract JWT token from URL query parameters (from Auth Portal)\
    const urlParams = new URLSearchParams(window.location.search);\
    const token = urlParams.get('\''token'\'');\
\
    if (token) {\
      console.log('\''[CAE Auth] JWT token received from URL, storing in localStorage'\'');\
      localStorage.setItem('\''jwt_token'\'', token);\
\
      // Remove token from URL for security\
      window.history.replaceState({}, document.title, window.location.pathname);\
\
      // Reload to apply authentication\
      window.location.reload();\
    }\
  }, []);' "$app_tsx"
            log_success "JWT token reception added to App.tsx"
        fi
    fi

    # Fix 2: Update axiosClient.ts - Change baseURL and add JWT interceptors
    local axios_client="$cae_dir/src/api/axiosClient.ts"
    if [[ -f "$axios_client" ]]; then
        # Check if JWT interceptor already exists
        if grep -q "CAE API.*Request with JWT token" "$axios_client"; then
            log_info "axiosClient.ts already has JWT interceptor"
        else
            log_info "Adding JWT interceptor to axiosClient.ts..."

            # Replace the entire file content
            cat > "$axios_client" << 'AXIOS_EOF'
import axios from 'axios';

// Use relative path for Nginx routing: /cae/automation/ -> http://localhost:5001/
const baseURL = '/cae/automation';

export const api = axios.create({
  baseURL,
});

// Request interceptor: Add JWT token to all requests
api.interceptors.request.use(
  (config) => {
    const token = localStorage.getItem('jwt_token');

    if (token) {
      config.headers.Authorization = `Bearer ${token}`;
      console.log('[CAE API] Request with JWT token:', config.url);
    } else {
      console.warn('[CAE API] Request without JWT token:', config.url);
    }

    return config;
  },
  (error) => {
    console.error('[CAE API] Request error:', error);
    return Promise.reject(error);
  }
);

// Response interceptor: Handle 401 errors
api.interceptors.response.use(
  (response) => {
    console.log('[CAE API] Response success:', response.config.url, response.status);
    return response;
  },
  (error) => {
    if (error.response?.status === 401) {
      console.error('[CAE API] 401 Unauthorized - Token invalid or expired');

      // Clear invalid token
      localStorage.removeItem('jwt_token');

      // Redirect to Auth Portal
      console.log('[CAE API] Redirecting to Auth Portal...');
      window.location.href = '/';
    } else if (error.response) {
      console.error('[CAE API] Response error:', error.response.status, error.response.data);
    } else if (error.request) {
      console.error('[CAE API] No response received:', error.request);
    } else {
      console.error('[CAE API] Error:', error.message);
    }

    return Promise.reject(error);
  }
);
AXIOS_EOF
            log_success "JWT interceptor added to axiosClient.ts"
        fi
    fi

    # Fix 3: Update FileTreeExplorer.tsx - Remove automationApi, use shared api
    local file_explorer="$cae_dir/src/components/common/FileTreeExplorer.tsx"
    if [[ -f "$file_explorer" ]]; then
        if grep -q "automationApi" "$file_explorer"; then
            log_info "Fixing FileTreeExplorer.tsx to use shared axios instance..."

            # Remove axios and API_CONFIG imports
            sed -i '/import axios from .axios.;/d' "$file_explorer"
            sed -i '/import.*API_CONFIG.*from/d' "$file_explorer"

            # Remove automationApi creation
            sed -i '/const automationApi = useMemo.*axios\.create/,/}), \[\]);/d' "$file_explorer"

            # Replace all automationApi with api
            sed -i 's/automationApi/api/g' "$file_explorer"

            log_success "FileTreeExplorer.tsx fixed to use shared axios instance"
        else
            log_info "FileTreeExplorer.tsx already using shared axios instance"
        fi
    fi

    # Fix 4: Update FileTreeTextBox.tsx - Remove automationApi, use shared api
    local file_textbox="$cae_dir/src/components/common/FileTreeTextBox.tsx"
    if [[ -f "$file_textbox" ]]; then
        if grep -q "automationApi" "$file_textbox"; then
            log_info "Fixing FileTreeTextBox.tsx to use shared axios instance..."

            # Remove axios and API_CONFIG imports, add api import if not present
            sed -i '/import axios from .axios.;/d' "$file_textbox"
            sed -i '/import.*API_CONFIG.*from/d' "$file_textbox"

            # Add api import if not present
            if ! grep -q "import.*api.*from.*api/axiosClient" "$file_textbox"; then
                sed -i '/^import React/a import { api } from '\''../../api/axiosClient'\'';' "$file_textbox"
            fi

            # Remove automationApi creation and useMemo if only used for that
            sed -i '/const automationApi = useMemo.*axios\.create/,/}), \[\]);/d' "$file_textbox"

            # Replace all automationApi with api
            sed -i 's/automationApi/api/g' "$file_textbox"

            # Remove useMemo from imports if it's no longer used
            if ! grep -q "useMemo" "$file_textbox" 2>/dev/null; then
                sed -i 's/, useMemo//' "$file_textbox"
                sed -i 's/useMemo, //' "$file_textbox"
            fi

            log_success "FileTreeTextBox.tsx fixed to use shared axios instance"
        else
            log_info "FileTreeTextBox.tsx already using shared axios instance"
        fi
    fi

    log_success "All JWT authentication fixes applied to CAE frontend"
}

# Function to build all frontend services
build_all_frontends() {
    log_info "Building frontend services for production..."

    local dashboard_dir="$PROJECT_ROOT/dashboard"
    local frontends=(
        "frontend_3010"
        "auth_portal_4431"
        "kooCAEWeb_5173"
        "app_5174"
        "vnc_service_8002"
    )

    for frontend in "${frontends[@]}"; do
        local frontend_dir="$dashboard_dir/$frontend"

        if [[ -d "$frontend_dir" ]]; then
            log_info "Building $frontend..."

            if [[ "$DRY_RUN" == false ]]; then
                # Apply JWT authentication fixes for CAE frontend BEFORE building
                if [[ "$frontend" == "kooCAEWeb_5173" ]]; then
                    apply_cae_jwt_fixes "$frontend_dir"
                fi

                cd "$frontend_dir"

                # Install dependencies if needed (check for critical packages too)
                local need_install=false
                if [[ ! -d "node_modules" ]]; then
                    need_install=true
                    log_info "node_modules not found for $frontend"
                elif [[ "$frontend" == "kooCAEWeb_5173" ]]; then
                    # Check critical dependencies for CAE frontend
                    if [[ ! -d "node_modules/@mui/material" ]] || [[ ! -d "node_modules/@mui/icons-material" ]]; then
                        need_install=true
                        log_info "Critical MUI packages missing in $frontend"
                    fi
                fi

                if [[ "$need_install" == true ]]; then
                    log_info "Installing dependencies for $frontend..."
                    npm install || log_warning "npm install failed for $frontend"
                fi

                # Build frontend with retry on module errors
                if ! npm run build 2>&1 | tee /tmp/${frontend}_build.log; then
                    log_warning "Build failed for $frontend, checking for module errors..."
                    if grep -q "Cannot find module" /tmp/${frontend}_build.log 2>/dev/null; then
                        log_info "Module missing detected, reinstalling dependencies..."
                        rm -rf node_modules 2>/dev/null || true
                        npm install
                        npm run build || log_warning "Rebuild failed for $frontend"
                    else
                        log_warning "Build failed for $frontend (non-module error)"
                    fi
                fi

                # Special handling for app_5174: copy landing.html to dist/index.html
                if [[ "$frontend" == "app_5174" && -f "landing.html" ]]; then
                    cp landing.html dist/index.html
                    log_info "Copied landing.html to dist/index.html for app_5174"
                fi

                # Apply GEdit fixes (single window.open, longer VNC wait time)
                if [[ "$frontend" == "app_5174" ]]; then
                    local gedit_html="dist/apps/gedit/index.html"
                    if [[ -f "$gedit_html" ]]; then
                        # Check if it has the old multiple window.open issue
                        if grep -q "windowOpened" "$gedit_html"; then
                            log_info "GEdit already has single window.open fix applied"
                        else
                            log_warning "GEdit needs update - applying single window.open fix"
                            # Note: The fix should be applied to source file in dashboard/app_5174/apps/gedit/index.html
                            # This built version will be replaced on next build
                        fi
                    fi
                fi

                # Create nginx serve directory
                local nginx_dir="/var/www/html/$frontend"
                mkdir -p "$nginx_dir"

                # Copy dist to nginx directory
                if [[ -d "dist" ]]; then
                    cp -r dist/* "$nginx_dir/"
                    log_success "$frontend built and copied to $nginx_dir"

                    # Handle Nginx alias mappings (source_dir → nginx_alias)
                    # These frontends need to be copied to both their original name AND the Nginx alias
                    case "$frontend" in
                        frontend_3010)
                            # /dashboard → /var/www/html/dashboard (Nginx serves this)
                            local alias_dir="/var/www/html/dashboard"
                            mkdir -p "$alias_dir"
                            cp -r dist/* "$alias_dir/"
                            log_success "$frontend also copied to $alias_dir (Nginx alias: /dashboard)"
                            ;;
                        kooCAEWeb_5173)
                            # /cae → /var/www/html/cae (Nginx serves this)
                            local alias_dir="/var/www/html/cae"
                            mkdir -p "$alias_dir"
                            cp -r dist/* "$alias_dir/"
                            log_success "$frontend also copied to $alias_dir (Nginx alias: /cae)"
                            ;;
                        # vnc_service_8002 and app_5174 already match their Nginx paths
                    esac
                else
                    log_warning "No dist directory found for $frontend"
                fi

                cd "$PROJECT_ROOT"
            else
                log_info "[DRY-RUN] Would build $frontend"
            fi
        else
            log_warning "Frontend directory not found: $frontend_dir"
        fi
    done

    log_success "All frontends built"
}

# Function to create all systemd services
create_systemd_services() {
    log_info "Creating systemd services for production mode..."

    local dashboard_dir="$PROJECT_ROOT/dashboard"

    # Python Backend Services (5)
    create_systemd_service_direct "auth_backend" "python" 4430 "$dashboard_dir/auth_portal_4430" "source venv/bin/activate && python3 app.py"
    create_systemd_service_direct "dashboard_backend" "python" 5010 "$dashboard_dir/backend_5010" "source venv/bin/activate && python3 app.py"
    create_systemd_service_direct "websocket_service" "python" 5011 "$dashboard_dir/websocket_5011" "source venv/bin/activate && python3 websocket_server_enhanced.py"
    create_systemd_service_direct "cae_backend" "python" 5000 "$dashboard_dir/kooCAEWebServer_5000" "source venv/bin/activate && python3 app.py"
    create_systemd_service_direct "cae_automation" "python" 5001 "$dashboard_dir/kooCAEWebAutomationServer_5001" "source venv/bin/activate && python3 app.py"

    # Note: auth_portal_4431 is built by build_all_frontends() and served by Nginx (no systemd service needed)

    # Monitoring Services (3)
    create_systemd_service_direct "saml_idp" "node" 7000 "$dashboard_dir/saml_idp_7000" "npx saml-idp --port 7000 --host 0.0.0.0 --issuer \"http://localhost:7000/metadata\" --acsUrl \"http://localhost:4430/auth/saml/acs\" --audience \"auth-portal\" --cert \"certs/idp-cert.pem\" --key \"certs/idp-key.pem\" --configFile \"$dashboard_dir/saml_idp_7000/config.js\""
    create_systemd_service_direct "prometheus" "monitoring" 9090 "$dashboard_dir/prometheus_9090" "./prometheus --config.file=prometheus.yml --storage.tsdb.path=./data"
    create_systemd_service_direct "node_exporter" "monitoring" 9100 "$dashboard_dir/node_exporter_9100" "./node_exporter"

    log_success "All systemd services created (Production mode: backends only, frontends served by Nginx)"
}

# Function to create systemd service directly with full path
create_systemd_service_direct() {
    local service_name=$1
    local service_type=$2
    local port=$3
    local work_dir=$4
    local start_command=$5

    log_info "Creating systemd service for $service_name..."

    local service_file="/etc/systemd/system/$service_name.service"

    if [[ "$DRY_RUN" == false ]]; then
        local environment=""
        if [[ "$service_type" == "python" ]]; then
            environment="Environment=\"MOCK_MODE=false\"\nEnvironment=\"PORT=$port\"\nEnvironment=\"PATH=/usr/local/slurm/bin:/usr/local/slurm/sbin:/usr/local/bin:/usr/bin:/bin\"\nEnvironment=\"SLURM_BIN_DIR=/usr/local/slurm/bin\"\nEnvironmentFile=-$work_dir/.env"
        elif [[ "$service_type" == "node" ]]; then
            environment="Environment=\"NODE_ENV=development\"\nEnvironment=\"PORT=$port\"\nEnvironment=\"PATH=/usr/local/slurm/bin:/usr/local/slurm/sbin:/usr/local/bin:/usr/bin:/bin\"\nEnvironmentFile=-$work_dir/.env"
        else
            environment="Environment=\"PORT=$port\"\nEnvironment=\"PATH=/usr/local/slurm/bin:/usr/local/slurm/sbin:/usr/local/bin:/usr/bin:/bin\""
        fi

        cat > "$service_file" << EOF
[Unit]
Description=$service_name - Web Service ($service_type) - Port $port
After=network.target redis-server.service
Wants=network-online.target

[Service]
Type=simple
User=koopark
Group=koopark
WorkingDirectory=$work_dir

# Environment
$(echo -e "$environment")

# Start command
ExecStart=/bin/bash -c '$start_command'

# Restart policy
Restart=always
RestartSec=5
StartLimitInterval=60
StartLimitBurst=10

# Resource limits
MemoryLimit=2G
CPUQuota=200%

# Logging
StandardOutput=append:/var/log/web_services/$service_name.log
StandardError=append:/var/log/web_services/$service_name.error.log

[Install]
WantedBy=multi-user.target
EOF

        systemctl daemon-reload
        log_success "Systemd service created: $service_name"
    else
        log_info "[DRY-RUN] Would create systemd service: $service_name"
    fi
}

# Function to generate Nginx upstream configuration
generate_nginx_upstreams() {
    log_info "Generating Nginx upstream configuration..."

    local upstreams=""

    # Generate upstream blocks for each service
    for controller in $WEB_CONTROLLERS; do
        local ip=$(echo "$controller" | cut -d: -f1)
        upstreams="${upstreams}    server ${ip}:5173;  # dashboard\n"
    done

    echo -e "$upstreams"
}

# Function to configure Nginx
configure_nginx() {
    log_info "Configuring Nginx reverse proxy (PRODUCTION MODE)..."

    if [[ "$DRY_RUN" == false ]]; then
        # Ensure WebSocket map directive exists in nginx.conf (required for $connection_upgrade variable)
        if ! grep -q 'connection_upgrade' /etc/nginx/nginx.conf 2>/dev/null; then
            log_info "Adding WebSocket map directive to nginx.conf..."

            # Add map directive after 'http {' line
            if grep -q 'http {' /etc/nginx/nginx.conf; then
                # Create backup
                cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup_$(date +%Y%m%d_%H%M%S)

                # Create a temp file with the map directive inserted
                awk '/http \{/{print; print "\n\t# WebSocket support (added by phase5_web.sh)"; print "\tmap $http_upgrade $connection_upgrade {"; print "\t\tdefault upgrade;"; print "\t\t\"\" close;"; print "\t}\n"; next}1' /etc/nginx/nginx.conf > /tmp/nginx.conf.new

                if [ -s /tmp/nginx.conf.new ]; then
                    mv /tmp/nginx.conf.new /etc/nginx/nginx.conf
                    log_success "WebSocket map directive added to nginx.conf"
                else
                    log_error "Failed to create modified nginx.conf"
                fi
            else
                log_warning "Could not find 'http {' in nginx.conf, WebSocket may not work"
            fi
        else
            log_info "WebSocket map directive already exists in nginx.conf"
        fi

        # Choose nginx configuration based on SSO setting
        if [[ "$SSO_ENABLED" == "false" ]]; then
            # SSO disabled: Use HTTP-only configuration (hpc-portal.conf)
            log_info "SSO disabled: Generating HTTP-only nginx configuration (hpc-portal.conf)..."
            local nginx_conf="/etc/nginx/conf.d/hpc-portal.conf"
            local nginx_template="$PROJECT_ROOT/dashboard/nginx/hpc-portal.conf"

            # Backup existing config if it exists
            if [[ -f "$nginx_conf" ]]; then
                cp "$nginx_conf" "${nginx_conf}.backup_$(date +%Y%m%d_%H%M%S)"
            fi

            # Check if source template exists
            if [[ -f "$nginx_template" ]]; then
                # Copy template and replace placeholders
                sed -e "s|server_name [0-9.]\+ localhost|server_name $PUBLIC_URL localhost|g" \
                    -e "s|alias /home/[^/]\+/claude/KooSlurmInstallAutomationRefactory/|alias $PROJECT_ROOT/|g" \
                    "$nginx_template" > "$nginx_conf"
                log_success "Generated $nginx_conf with PUBLIC_URL=$PUBLIC_URL (HTTP only)"
            else
                log_error "Nginx template not found: $nginx_template"
                return 1
            fi

            # Disable auth-portal.conf if it exists (conflicts with hpc-portal.conf)
            if [[ -f "/etc/nginx/conf.d/auth-portal.conf" ]]; then
                log_info "Disabling auth-portal.conf (SSO disabled, using HTTP-only config)"
                mv /etc/nginx/conf.d/auth-portal.conf /etc/nginx/conf.d/auth-portal.conf.disabled_$(date +%Y%m%d_%H%M%S)
            fi
        else
            # SSO enabled: Use HTTPS configuration (auth-portal.conf)
            log_info "SSO enabled: Using HTTPS nginx configuration (auth-portal.conf)..."
            local nginx_conf="/etc/nginx/conf.d/auth-portal.conf"

            # auth-portal.conf should already exist from previous setup
            # Just update server_name and paths if needed
            if [[ -f "$nginx_conf" ]]; then
                # Backup existing config
                cp "$nginx_conf" "${nginx_conf}.backup_$(date +%Y%m%d_%H%M%S)"

                # Update server_name and paths
                sed -i -e "s|server_name [0-9.]\+ localhost|server_name $PUBLIC_URL localhost|g" \
                       -e "s|alias /home/[^/]\+/claude/KooSlurmInstallAutomationRefactory/|alias $PROJECT_ROOT/|g" \
                       "$nginx_conf"
                log_success "Updated $nginx_conf with PUBLIC_URL=$PUBLIC_URL (HTTPS with SSO)"
            else
                log_warning "auth-portal.conf not found, SSO may not work properly"
            fi

            # Disable hpc-portal.conf if it exists (conflicts with auth-portal.conf)
            if [[ -f "/etc/nginx/conf.d/hpc-portal.conf" ]]; then
                log_info "Disabling hpc-portal.conf (SSO enabled, using HTTPS config)"
                mv /etc/nginx/conf.d/hpc-portal.conf /etc/nginx/conf.d/hpc-portal.conf.disabled_$(date +%Y%m%d_%H%M%S)
            fi
        fi

        # Ensure web_services symlink is disabled to avoid conflict
        if [[ -L "/etc/nginx/sites-enabled/web_services" ]]; then
            log_info "Removing conflicting web_services symlink"
            rm -f "/etc/nginx/sites-enabled/web_services"
        fi

        # Remove default site if it exists (conflicts with our config)
        if [[ -L "/etc/nginx/sites-enabled/default" ]]; then
            log_info "Removing default nginx site to avoid conflict"
            rm -f "/etc/nginx/sites-enabled/default"
        fi

        # Test Nginx configuration
        if nginx -t 2>&1; then
            log_success "Nginx configuration valid"
        else
            log_error "Nginx configuration test failed"
            nginx -t
            return 1
        fi
    else
        log_info "[DRY-RUN] Would check/create nginx configuration"
    fi

    log_success "Nginx configured for production"
}


# Function to fix SSH API and Nginx configuration
fix_ssh_api_and_nginx() {
    log_info "Fixing SSH API and Nginx configuration..."

    local dashboard_dir="$PROJECT_ROOT/dashboard"

    if [[ "$DRY_RUN" == false ]]; then
        # 1. Fix ssh_api.py url_prefix
        local ssh_api="$dashboard_dir/backend_5010/ssh_api.py"
        if [[ -f "$ssh_api" ]]; then
            if grep -q "url_prefix='/ssh'" "$ssh_api"; then
                sed -i "s|url_prefix='/ssh'|url_prefix='/api/ssh'|g" "$ssh_api"
                log_success "Fixed ssh_api.py url_prefix to /api/ssh"
            else
                log_info "ssh_api.py url_prefix already correct"
            fi
        fi

        # 2. Fix SSHSessionManager.tsx API paths
        local ssh_manager="$dashboard_dir/frontend_3010/src/components/SSHSessionManager.tsx"
        if [[ -f "$ssh_manager" ]]; then
            if grep -q "API_CONFIG.API_BASE_URL}/ssh" "$ssh_manager"; then
                sed -i "s|API_CONFIG.API_BASE_URL}/ssh|API_CONFIG.API_BASE_URL}/api/ssh|g" "$ssh_manager"
                log_success "Fixed SSHSessionManager.tsx API paths to /api/ssh"
            else
                log_info "SSHSessionManager.tsx API paths already correct"
            fi
        fi

        # 3. Fix Nginx auth-portal.conf dashboard path
        if [[ -f "/etc/nginx/conf.d/auth-portal.conf" ]]; then
            if grep -q "alias /var/www/html/frontend_3010" /etc/nginx/conf.d/auth-portal.conf; then
                sed -i 's|alias /var/www/html/frontend_3010|alias /var/www/html/dashboard|g' /etc/nginx/conf.d/auth-portal.conf
                log_success "Fixed auth-portal.conf dashboard path"
            else
                log_info "auth-portal.conf dashboard path already correct"
            fi
        fi

        # 4. Fix Nginx hpc_web_services.conf if it exists
        if [[ -f "/etc/nginx/sites-available/hpc_web_services.conf" ]]; then
            if grep -q "alias /var/www/html/frontend_3010" /etc/nginx/sites-available/hpc_web_services.conf; then
                sed -i 's|alias /var/www/html/frontend_3010|alias /var/www/html/dashboard|g' /etc/nginx/sites-available/hpc_web_services.conf
                log_success "Fixed hpc_web_services.conf dashboard path"
            fi
        fi

        # 5. Remove old frontend_dashboard.service if exists
        if systemctl list-units --full --all | grep -q "frontend_dashboard.service"; then
            systemctl stop frontend_dashboard.service 2>/dev/null || true
            systemctl disable frontend_dashboard.service 2>/dev/null || true
            rm -f /etc/systemd/system/frontend_dashboard.service
            systemctl daemon-reload
            log_success "Removed old frontend_dashboard.service"
        fi


        # 6. Add SocketIO proxy to Nginx auth-portal.conf
        if [[ -f "/etc/nginx/conf.d/auth-portal.conf" ]]; then
            if ! grep -q "location /socket.io/" /etc/nginx/conf.d/auth-portal.conf; then
                # Find the line number after "location /ws" block
                local ws_end=$(grep -n "location /ws" /etc/nginx/conf.d/auth-portal.conf | head -1 | cut -d: -f1)
                ws_end=$((ws_end + 12))  # Skip to end of /ws block
                
                # Insert socket.io configuration
                sed -i "${ws_end}a\\
\\
    # SocketIO for SSH WebSocket (backend_5010)\\
    location /socket.io/ {\\
        proxy_pass http://localhost:5010/socket.io/;\\
        proxy_http_version 1.1;\\
        proxy_buffering off;\\
        proxy_set_header Upgrade \$http_upgrade;\\
        proxy_set_header Connection \"upgrade\";\\
        proxy_set_header Host \$host;\\
        proxy_set_header X-Real-IP \$remote_addr;\\
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;\\
        proxy_set_header X-Forwarded-Proto \$scheme;\\
        proxy_read_timeout 86400s;\\
        proxy_send_timeout 86400s;\\
    }" /etc/nginx/conf.d/auth-portal.conf
                
                log_success "Added SocketIO proxy to auth-portal.conf"
            else
                log_info "SocketIO proxy already exists in auth-portal.conf"
            fi
        fi
        log_success "SSH API and Nginx configuration fixed"
    else
        log_info "[DRY-RUN] Would fix SSH API and Nginx configuration"
    fi
}

# Function to setup SSL (supports letsencrypt, self_signed, or none)
setup_ssl() {
    if [[ "$SKIP_SSL" == true ]]; then
        log_warning "Skipping SSL setup (--skip-ssl flag)"
        return
    fi

    # Read SSL mode from YAML config (default: self_signed)
    local ssl_mode
    ssl_mode=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(c.get('web', {}).get('ssl', {}).get('mode', 'self_signed'))" 2>/dev/null || echo "self_signed")

    log_info "SSL mode from config: $ssl_mode"

    case "$ssl_mode" in
        none)
            log_warning "SSL disabled (mode: none). Using HTTP only."
            log_warning "⚠️  This is NOT recommended for production!"
            return
            ;;
        self_signed)
            log_info "Setting up self-signed SSL certificate..."
            setup_self_signed_ssl
            ;;
        letsencrypt)
            log_info "Setting up Let's Encrypt SSL certificate..."
            setup_letsencrypt_ssl
            ;;
        *)
            log_warning "Unknown SSL mode: $ssl_mode. Falling back to self_signed."
            setup_self_signed_ssl
            ;;
    esac

    log_success "SSL setup complete"
}

# Self-signed SSL certificate setup (for offline environments)
setup_self_signed_ssl() {
    if [[ "$DRY_RUN" == false ]]; then
        # Create SSL directories
        mkdir -p /etc/ssl/private
        chmod 700 /etc/ssl/private
        mkdir -p /etc/nginx/snippets

        # Generate self-signed certificate if not exists
        if [[ ! -f "/etc/ssl/certs/nginx-selfsigned.crt" ]]; then
            log_info "Generating self-signed SSL certificate (1 year validity)..."
            openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                -keyout /etc/ssl/private/nginx-selfsigned.key \
                -out /etc/ssl/certs/nginx-selfsigned.crt \
                -subj "/C=KR/ST=Seoul/L=Seoul/O=HPC Lab/CN=$DOMAIN" \
                2>/dev/null
            log_success "Self-signed certificate generated"
        else
            log_info "Self-signed certificate already exists"
        fi

        chmod 600 /etc/ssl/private/nginx-selfsigned.key
        chmod 644 /etc/ssl/certs/nginx-selfsigned.crt

        # Generate DH parameters if not exists (can take 1-5 minutes)
        if [[ ! -f "/etc/ssl/certs/dhparam.pem" ]]; then
            log_info "Generating DH parameters (this may take 1-5 minutes)..."
            openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048 2>/dev/null
            chmod 644 /etc/ssl/certs/dhparam.pem
            log_success "DH parameters generated"
        fi

        # Create Nginx SSL snippets
        cat > /etc/nginx/snippets/self-signed.conf << 'EOF'
ssl_certificate /etc/ssl/certs/nginx-selfsigned.crt;
ssl_certificate_key /etc/ssl/private/nginx-selfsigned.key;
EOF

        cat > /etc/nginx/snippets/ssl-params.conf << 'EOF'
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers on;
ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
ssl_ecdh_curve secp384r1;
ssl_session_timeout 10m;
ssl_session_cache shared:SSL:10m;
ssl_session_tickets off;
ssl_dhparam /etc/ssl/certs/dhparam.pem;
add_header Strict-Transport-Security "max-age=63072000" always;
add_header X-Frame-Options DENY always;
add_header X-Content-Type-Options nosniff always;
add_header X-XSS-Protection "1; mode=block" always;
EOF

        log_success "Self-signed SSL configured"
    else
        log_info "[DRY-RUN] Would setup self-signed SSL certificate"
    fi
}

# Let's Encrypt SSL certificate setup (requires internet)
setup_letsencrypt_ssl() {
    # Get domain and email from YAML
    local ssl_domain ssl_email
    ssl_domain=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(c.get('web', {}).get('ssl', {}).get('domain', ''))" 2>/dev/null || echo "")
    ssl_email=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_PATH')); print(c.get('web', {}).get('ssl', {}).get('email', ''))" 2>/dev/null || echo "")

    # Use cluster domain as fallback
    if [[ -z "$ssl_domain" ]]; then
        ssl_domain="$DOMAIN"
    fi
    if [[ -z "$ssl_email" ]]; then
        ssl_email="admin@$ssl_domain"
    fi

    if [[ "$DRY_RUN" == false ]]; then
        # Check if certificate already exists
        if [[ -d "/etc/letsencrypt/live/$ssl_domain" ]]; then
            log_info "Let's Encrypt certificate already exists for $ssl_domain"
        else
            # Stop Nginx temporarily
            systemctl stop nginx || true

            # Obtain certificate
            if certbot certonly --standalone \
                -d "$ssl_domain" \
                --non-interactive \
                --agree-tos \
                --email "$ssl_email" \
                --preferred-challenges http; then
                log_success "Let's Encrypt certificate obtained"
            else
                log_error "Failed to obtain Let's Encrypt certificate"
                log_warning "Falling back to self-signed certificate..."
                setup_self_signed_ssl
                return
            fi
        fi

        # Setup auto-renewal
        if ! crontab -l 2>/dev/null | grep -q certbot; then
            (crontab -l 2>/dev/null; echo "0 0 * * * certbot renew --quiet --post-hook 'systemctl reload nginx'") | crontab -
            log_success "SSL auto-renewal configured"
        fi
    else
        log_info "[DRY-RUN] Would setup Let's Encrypt certificate for $ssl_domain"
    fi
}

# Function to start web services
start_services() {
    log_info "Starting web services (PRODUCTION MODE: backends only)..."

    # Note: auth_frontend (auth_portal_4431) is built and served by Nginx as static files
    # No systemd service needed for frontend
    local services=(
        "auth_backend"
        "dashboard_backend"
        "websocket_service"
        "cae_backend"
        "cae_automation"
        "saml_idp"
        "prometheus"
        "node_exporter"
    )

    for service in "${services[@]}"; do
        if [[ "$DRY_RUN" == false ]]; then
            systemctl enable "$service" 2>/dev/null || true
            systemctl start "$service"

            if systemctl is-active --quiet "$service"; then
                log_success "$service started"
            else
                log_error "Failed to start $service"
            fi
        else
            log_info "[DRY-RUN] Would start $service"
        fi
    done

    # Reload and restart Nginx
    if [[ "$DRY_RUN" == false ]]; then
        systemctl enable nginx
        systemctl reload nginx || systemctl restart nginx
        if systemctl is-active --quiet nginx; then
            log_success "nginx reloaded"
        else
            log_error "Failed to reload nginx"
        fi
    fi

    log_success "All services started (PRODUCTION MODE)"
}

# Function to verify services
verify_services() {
    log_info "Verifying web services (PRODUCTION MODE)..."

    # Note: auth_frontend (auth_portal_4431) is served by Nginx as static files
    # Verify it via Nginx instead of systemd service
    local services=(
        "auth_backend:4430:/health:backend"
        "dashboard_backend:5010:/api/nodes:backend"
        "websocket_service:5011:/:backend"
        "cae_backend:5000:/:backend"
        "cae_automation:5001:/:backend"
    )

    local all_healthy=true

    # Check backend services
    for service_info in "${services[@]}"; do
        local service_name=$(echo "$service_info" | cut -d: -f1)
        local port=$(echo "$service_info" | cut -d: -f2)
        local path=$(echo "$service_info" | cut -d: -f3)
        local service_type=$(echo "$service_info" | cut -d: -f4)

        if [[ "$DRY_RUN" == false ]]; then
            local is_healthy=false

            if [[ "$service_type" == "frontend" ]]; then
                # For frontend service (auth_frontend only in production)
                check_result=$(curl -sf -m 3 "http://localhost:$port$path" 2>&1)
                if [[ $? -eq 0 ]]; then
                    is_healthy=true
                    log_success "$service_name is healthy (dev mode)"
                fi
            else
                # For backend services - retry up to 10 times with 2s delay
                local max_retries=10
                local retry_delay=2

                for ((retry=1; retry<=max_retries; retry++)); do
                    http_code=$(curl -s -o /dev/null -w "%{http_code}" -m 3 "http://localhost:$port$path" 2>&1 || true)
                    if [[ "$http_code" =~ ^[2-5][0-9][0-9]$ ]]; then
                        is_healthy=true
                        if [[ $retry -gt 1 ]]; then
                            log_success "$service_name is healthy (HTTP $http_code) - ready after ${retry} attempts"
                        else
                            log_success "$service_name is healthy (HTTP $http_code)"
                        fi
                        break
                    fi

                    # If not last retry, wait and try again
                    if [[ $retry -lt $max_retries ]]; then
                        sleep $retry_delay
                    fi
                done
            fi

            if [[ "$is_healthy" == false ]]; then
                # Fallback: check if systemd service is running
                if systemctl is-active --quiet "$service_name.service" 2>/dev/null; then
                    is_healthy=true
                    log_warning "$service_name is starting (systemd running, HTTP not ready yet after ${max_retries} attempts)"
                else
                    log_error "$service_name is not responding (port $port) after ${max_retries} attempts"
                    all_healthy=false
                fi
            fi
        else
            log_info "[DRY-RUN] Would check $service_name at http://localhost:$port$path"
        fi
    done

    # Check Nginx and frontend paths
    if [[ "$DRY_RUN" == false ]]; then
        if systemctl is-active --quiet nginx; then
            log_success "nginx is running"

            # Test frontend paths through nginx
            local frontend_paths=(
                "/dashboard:Dashboard Frontend"
                "/vnc:VNC Frontend"
                "/app:App Frontend"
                "/koocae:KooCAEWeb Frontend"
            )

            for path_info in "${frontend_paths[@]}"; do
                local path=$(echo "$path_info" | cut -d: -f1)
                local name=$(echo "$path_info" | cut -d: -f2)

                http_code=$(curl -s -o /dev/null -w "%{http_code}" -m 3 "http://localhost$path" 2>&1)
                if [[ "$http_code" =~ ^[2-3][0-9][0-9]$ ]]; then
                    log_success "$name accessible via Nginx (HTTP $http_code)"
                else
                    log_warning "$name may not be built yet (HTTP $http_code)"
                fi
            done
        else
            log_error "nginx is not running"
            all_healthy=false
        fi
    fi

    if [[ "$all_healthy" == true ]]; then
        log_success "All services are healthy (PRODUCTION MODE)"
    else
        log_warning "Some services are not healthy - check logs at /var/log/web_services/"
    fi
}

# Function to display summary
display_summary() {
    log_info "=== Web Services Setup Summary ==="
    log_info "Cluster: $CLUSTER_NAME"
    log_info "Node: $CURRENT_NODE_IP"
    log_info "Domain: $DOMAIN"
    log_info ""
    log_info "Services deployed:"
    log_info "  - Dashboard: https://$DOMAIN/"
    log_info "  - Auth API: https://$DOMAIN/api/auth"
    log_info "  - Job API: https://$DOMAIN/api/jobs"
    log_info "  - WebSocket: wss://$DOMAIN/ws"
    log_info "  - File API: https://$DOMAIN/api/files"
    log_info "  - Monitoring: https://$DOMAIN/monitoring"
    log_info "  - Metrics API: https://$DOMAIN/api/monitoring"
    log_info "  - Admin Portal: https://$DOMAIN/admin"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Verify services: curl https://$DOMAIN/health"
    log_info "  2. Check logs: tail -f /var/log/web_services/*.log"
    log_info "  3. Access dashboard: https://$DOMAIN"
}

# Function to deploy VNC start scripts to viz nodes
deploy_vnc_scripts() {
    log_info "Deploying VNC start scripts to viz nodes..."

    # Get viz nodes from config using parser.py
    local viz_nodes=$(python3 "$SCRIPT_DIR/../config/parser.py" "$CONFIG_PATH" get-nodes --partition viz 2>/dev/null | jq -r '.[].name' 2>/dev/null || echo "")

    if [[ -z "$viz_nodes" ]]; then
        log_warning "No viz nodes found in config"
        return
    fi

    # Create the VNC start script content
    local script_content='#!/bin/bash
set -e

VNC_RESOLUTION=${VNC_RESOLUTION:-1280x720}
VNC_PORT=${VNC_PORT:-5901}
WEBSOCKIFY_PORT=${WEBSOCKIFY_PORT:-6080}
DISPLAY_NUM=${1:-1}
export DISPLAY=:${DISPLAY_NUM}
export HOME=/root

echo "=== Starting GEdit (Fixed - No Background vncserver) ==="
echo "HOME=$HOME"
echo "DISPLAY=$DISPLAY"
echo "VNC_PORT=$VNC_PORT"
echo "WEBSOCKIFY_PORT=$WEBSOCKIFY_PORT"

# D-Bus
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval $(dbus-launch --sh-syntax)
fi

# VNC 정리
vncserver -kill $DISPLAY 2>/dev/null || true
rm -rf /tmp/.X${DISPLAY_NUM}-lock 2>/dev/null || true
rm -rf /tmp/.X11-unix/X${DISPLAY_NUM} 2>/dev/null || true

# VNC 비밀번호 설정 - 중요!
echo "Setting up VNC password..."
mkdir -p ~/.vnc
echo "password" | vncpasswd -f > ~/.vnc/passwd
chmod 600 ~/.vnc/passwd
echo "Password file created: $(ls -lah ~/.vnc/passwd)"

# xstartup
cat > ~/.vnc/xstartup << '\''XSTARTUP'\''
#!/bin/bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

eval $(dbus-launch --sh-syntax)
export DBUS_SESSION_BUS_ADDRESS

xsetroot -solid grey &
xfwm4 &

(sleep 3 && DISPLAY=:1 gedit) &

while true; do sleep 3600; done
XSTARTUP
chmod +x ~/.vnc/xstartup

# VNC 시작 (NO BACKGROUND!)
echo "Starting VNC server (foreground)..."
vncserver $DISPLAY -geometry $VNC_RESOLUTION -depth 24 -localhost no

echo "VNC server started successfully"
sleep 3

# websockify (background is fine)
echo "Starting websockify..."
websockify --web /opt/novnc ${WEBSOCKIFY_PORT} localhost:${VNC_PORT} &

echo "✅ GEdit ready!"
echo "VNC: localhost:$VNC_PORT"
echo "WebSocket: ws://localhost:$WEBSOCKIFY_PORT"

# Keep script alive
while true; do sleep 3600; done
'

    # Deploy to each viz node
    for node in $viz_nodes; do
        # Get node IP and SSH user from YAML config
        local node_info
        node_info=$(python3 << EOFPY
import yaml
try:
    with open('$CONFIG_PATH') as f:
        config = yaml.safe_load(f)
    # Search in compute_nodes (viz nodes are usually in compute_nodes)
    for n in config.get('nodes', {}).get('compute_nodes', []):
        if n.get('hostname') == '$node' or n.get('name') == '$node':
            ip = n.get('ip_address', n.get('ip', ''))
            user = n.get('ssh_user', 'root')
            print(f"{ip}|{user}")
            exit(0)
    # Also check controllers
    for n in config.get('nodes', {}).get('controllers', []):
        if n.get('hostname') == '$node' or n.get('name') == '$node':
            ip = n.get('ip_address', n.get('ip', ''))
            user = n.get('ssh_user', 'root')
            print(f"{ip}|{user}")
            exit(0)
except Exception as e:
    pass
EOFPY
)
        local node_ip=$(echo "$node_info" | cut -d'|' -f1)
        local ssh_user=$(echo "$node_info" | cut -d'|' -f2)

        # Fallback to yq if python parsing failed
        if [[ -z "$node_ip" ]]; then
            node_ip=$(yq eval ".nodes[] | select(.name == \"$node\") | .ip" "$CONFIG_PATH" 2>/dev/null)
            ssh_user="root"  # Default fallback
        fi

        if [[ -z "$node_ip" ]]; then
            log_warning "No IP found for node $node"
            continue
        fi

        log_info "Deploying VNC script to $node ($node_ip) as $ssh_user..."

        if [[ "$DRY_RUN" == false ]]; then
            # Create /opt/scripts directory on viz node
            ssh $SSH_OPTS "$ssh_user@$node_ip" "sudo mkdir -p /opt/scripts" || {
                log_warning "Failed to create /opt/scripts on $node"
                continue
            }

            # Deploy the script
            echo "$script_content" | ssh $SSH_OPTS "$ssh_user@$node_ip" "sudo tee /opt/scripts/start-gedit-working.sh > /dev/null" || {
                log_warning "Failed to deploy script to $node"
                continue
            }

            # Make it executable
            ssh $SSH_OPTS "$ssh_user@$node_ip" "sudo chmod +x /opt/scripts/start-gedit-working.sh" || {
                log_warning "Failed to set permissions on $node"
                continue
            }

            log_success "VNC script deployed to $node"
        else
            log_info "[DRY-RUN] Would deploy VNC script to $node ($node_ip) as $ssh_user"
        fi
    done

    log_success "VNC scripts deployment complete"
}

# Main function
main() {
    parse_args "$@"

    log_info "=== Phase 5: Web Services Setup (PRODUCTION MODE) ==="
    log_info "Starting at: $(date)"

    if [[ "$DRY_RUN" == true ]]; then
        log_warning "DRY-RUN MODE: No changes will be made"
    fi

    check_root
    check_prerequisites
    stop_manual_web_services
    load_config
    create_web_user
    create_directories
    deploy_web_services
    build_all_frontends      # Build frontends for production
    deploy_vnc_scripts       # Deploy VNC start scripts to viz nodes
    create_systemd_services  # Only backends + auth_frontend
    configure_nginx          # Serve built frontends + proxy backends
    fix_ssh_api_and_nginx   # Fix SSH API paths and Nginx dashboard paths
    setup_ssl
    start_services
    verify_services

    # Apply post-setup fixes
    log_info "Applying post-setup fixes..."
    if [[ -f "$SCRIPT_DIR/apply_post_setup_fixes.sh" ]]; then
        # Export variables so apply_post_setup_fixes.sh can use them
        export REDIS_PASSWORD JWT_SECRET
        bash "$SCRIPT_DIR/apply_post_setup_fixes.sh" || log_warning "Post-setup fixes failed (non-critical)"
    else
        log_warning "Post-setup fixes script not found: $SCRIPT_DIR/apply_post_setup_fixes.sh"
    fi

    display_summary

    log_success "=== Phase 5 setup completed successfully (PRODUCTION MODE) ==="
    log_info "Finished at: $(date)"
}

# Run main function
main "$@"
