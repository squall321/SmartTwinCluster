#!/bin/bash
###################################################################################
# Post-Setup Fixes Script
#
# This script applies all manual fixes discovered during troubleshooting:
# 1. Redis password configuration for dashboard backend
# 2. Nginx CAE backend proxy path fix
# 3. Nginx CAE frontend alias path fix
# 4. Nginx CAE index.html no-cache headers
# 5. VNC service novnc_url to use nginx proxy path
# 6. Add nginx WebSocket support for VNC
# 7. Add nginx VNC proxy location block
#
# Run this after phase5_web.sh completes
###################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Load SSO configuration from YAML to determine which nginx config to use
CONFIG_FILE="${CONFIG_FILE:-$PROJECT_ROOT/my_multihead_cluster.yaml}"
if [[ -f "$CONFIG_FILE" ]]; then
    SSO_ENABLED=$(python3 -c "import yaml; c=yaml.safe_load(open('$CONFIG_FILE')); print(str(c.get('sso', {}).get('enabled', True)).lower())" 2>/dev/null || echo "true")
    log_info "Loaded SSO configuration: enabled=$SSO_ENABLED"

    # Determine which nginx config file to use
    if [[ "$SSO_ENABLED" == "false" ]]; then
        NGINX_CONF="/etc/nginx/conf.d/hpc-portal.conf"
        log_info "Using HTTP-only nginx config: $NGINX_CONF"
    else
        NGINX_CONF="/etc/nginx/conf.d/auth-portal.conf"
        log_info "Using HTTPS nginx config: $NGINX_CONF"
    fi
else
    log_warning "Config file not found: $CONFIG_FILE, defaulting to auth-portal.conf"
    NGINX_CONF="/etc/nginx/conf.d/auth-portal.conf"
    SSO_ENABLED="true"
fi

###################################################################################
# Fix 8: Update App Session Service to use nginx proxy paths
# (Defined early to be available for other functions)
###################################################################################
fix_app_session_urls() {
    log_info "=== Fix 8: Updating App Session displayUrl to use nginx proxy ==="

    local APP_SERVICE="$PROJECT_ROOT/dashboard/kooCAEWebServer_5000/services/app_session_service.py"

    if [[ ! -f "$APP_SERVICE" ]]; then
        log_error "App session service file not found: $APP_SERVICE"
        return 1
    fi

    # Check if already fixed (using /vncproxy/)
    if grep -q "displayUrl.*f'/vncproxy/" "$APP_SERVICE"; then
        log_info "App session displayUrl already using nginx proxy path"
    else
        # Fix: change http://{backend_host}:{local_port} to /vncproxy/{local_port}
        sed -i "s|f'http://.*:{local_port}/vnc.html|f'/vncproxy/{local_port}/vnc.html|g" "$APP_SERVICE"
        sed -i "s|f'ws://.*:{local_port}/websockify'|f'/vncproxy/{local_port}/websockify'|g" "$APP_SERVICE"
        sed -i "s|f'http://localhost:{vnc_port}/vnc.html|f'/vncproxy/{vnc_port}/vnc.html|g" "$APP_SERVICE"
        sed -i "s|f'ws://localhost:{vnc_port}'|f'/vncproxy/{vnc_port}/websockify'|g" "$APP_SERVICE"
        log_info "Updated App session URLs to use /vncproxy/ path"
    fi
}

###################################################################################
# Fix 1: Add Redis password to dashboard backend .env
###################################################################################
fix_redis_password() {
    log_info "=== Fix 1: Adding Redis password to dashboard backend .env ==="

    local ENV_FILE="$PROJECT_ROOT/dashboard/backend_5010/.env"

    if [[ ! -f "$ENV_FILE" ]]; then
        log_error ".env file not found: $ENV_FILE"
        return 1
    fi

    # Get Redis password from environment or use fallback
    # REDIS_PASSWORD should be set by phase5_web.sh before calling this script
    local redis_pass="${REDIS_PASSWORD:-changeme}"

    # Check if REDIS_PASSWORD already exists
    if grep -q "^REDIS_PASSWORD=" "$ENV_FILE"; then
        log_info "REDIS_PASSWORD already exists in .env"
    else
        # Add REDIS_PASSWORD
        echo "" >> "$ENV_FILE"
        echo "REDIS_PASSWORD=${redis_pass}" >> "$ENV_FILE"
        log_info "Added REDIS_PASSWORD to $ENV_FILE"
    fi
}

###################################################################################
# Fix 2: Update Nginx CAE backend proxy path
###################################################################################
fix_nginx_cae_proxy() {
    log_info "=== Fix 2: Updating Nginx CAE backend proxy path ==="

    if [[ ! -f "$NGINX_CONF" ]]; then
        log_warning "Nginx config not found: $NGINX_CONF (will be created by configure_nginx)"
        return 0
    fi

    # Check if already fixed
    if grep -q "proxy_pass http://localhost:5000/api/" "$NGINX_CONF"; then
        log_info "Nginx CAE backend proxy already configured correctly"
    else
        # Fix: Change /cae/api/ → http://localhost:5000/ to http://localhost:5000/api/
        sudo sed -i 's|proxy_pass http://localhost:5000/;|proxy_pass http://localhost:5000/api/;|' "$NGINX_CONF"
        log_info "Updated Nginx CAE backend proxy path"
    fi
}

###################################################################################
# Fix 3: Update Nginx CAE frontend alias path
###################################################################################
fix_nginx_cae_alias() {
    log_info "=== Fix 3: Updating Nginx CAE frontend alias path ==="

    # Check current alias
    local current_alias=$(grep -A1 "location /cae {" "$NGINX_CONF" | grep "alias" | awk '{print $2}' | tr -d ';')

    if [[ "$current_alias" == "/var/www/html/cae" ]]; then
        log_info "Nginx CAE frontend alias already correct"
    else
        # Fix: Change alias to /var/www/html/cae
        sudo sed -i 's|alias /var/www/html/kooCAEWeb_5173;|alias /var/www/html/cae;|' "$NGINX_CONF"
        log_info "Updated Nginx CAE frontend alias to /var/www/html/cae"
    fi
}

###################################################################################
# Fix 4: Add no-cache headers for CAE index.html
###################################################################################
fix_nginx_cae_nocache() {
    log_info "=== Fix 4: Adding no-cache headers for CAE index.html ==="

    # Check if no-cache location already exists
    if grep -q "location = /cae/index.html" "$NGINX_CONF"; then
        log_info "No-cache headers for CAE index.html already configured"
    else
        # Add no-cache location block
        sudo sed -i '/location \/cae {/,/^    }/ {
            /gzip_types.*/a\
\
        # Prevent caching of index.html\
        location = /cae/index.html {\
            add_header Cache-Control "no-cache, no-store, must-revalidate";\
            add_header Pragma "no-cache";\
            add_header Expires "0";\
        }
        }' "$NGINX_CONF"
        log_info "Added no-cache headers for CAE index.html"
    fi
}

###################################################################################
# Fix 5: Update VNC API to use nginx proxy paths
###################################################################################
fix_vnc_novnc_url() {
    log_info "=== Fix 5: Updating VNC novnc_url to use nginx proxy ==="

    local VNC_API="$PROJECT_ROOT/dashboard/backend_5010/vnc_api.py"

    if [[ ! -f "$VNC_API" ]]; then
        log_error "VNC API file not found: $VNC_API"
        return 1
    fi

    # Check if already fixed (using /vncproxy/)
    if grep -q 'session\[.novnc_url.\] = f"/vncproxy/' "$VNC_API"; then
        log_info "VNC novnc_url already using nginx proxy path"
    else
        # Fix both occurrences: change from {protocol}://{EXTERNAL_IP}:{novnc_port} to /vncproxy/{novnc_port}
        sed -i 's|session\[.novnc_url.\] = f"{protocol}://{EXTERNAL_IP}:{novnc_port}/vnc.html|session["novnc_url"] = f"/vncproxy/{novnc_port}/vnc.html|g' "$VNC_API"
        log_info "Updated VNC novnc_url to use /vncproxy/ path"
    fi
}

###################################################################################
# Fix 6: Add WebSocket support map to nginx.conf
###################################################################################
fix_nginx_websocket_map() {
    log_info "=== Fix 6: Adding WebSocket support map to nginx.conf ==="

    local NGINX_CONF="/etc/nginx/nginx.conf"

    if [[ ! -f "$NGINX_CONF" ]]; then
        log_warning "Nginx main config not found: $NGINX_CONF"
        return 0
    fi

    # Check if map already exists
    if grep -q "map.*http_upgrade.*connection_upgrade" "$NGINX_CONF"; then
        log_info "WebSocket map already exists in nginx.conf"
    else
        # Add map after http { line
        sudo sed -i '/^http {$/a\\\n\t# WebSocket support\n\tmap $http_upgrade $connection_upgrade {\n\t\tdefault upgrade;\n\t\t'"''"' close;\n\t}\n' "$NGINX_CONF"
        log_info "Added WebSocket support map to nginx.conf"
    fi
}

###################################################################################
# Fix 7: Add VNC proxy location to nginx
###################################################################################
fix_nginx_vnc_proxy() {
    echo ""

    fix_app_session_urls
    log_info "=== Fix 7: Adding VNC proxy location to nginx ==="

    # Check if VNC proxy location already exists
    if grep -q "location.*vncproxy" "$NGINX_CONF"; then
        log_info "VNC proxy location already exists in nginx config"
    else
        # Add VNC proxy location block before the closing }
        sudo bash -c "cat >> $NGINX_CONF" << 'EOF'

    # VNC noVNC WebSocket Proxy (Dynamic Ports 6901-6999)
    # Proxies /vncproxy/<port>/ to localhost:<port>/
    location ~ ^/vncproxy/([0-9]+)/(.*)$ {
        proxy_pass http://127.0.0.1:$1/$2$is_args$args;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket specific settings
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_buffering off;

        # Allow larger message sizes for VNC
        client_max_body_size 100M;
    }
}
EOF
        log_info "Added VNC proxy location to nginx config"
    fi
}

###################################################################################
# Restart services
###################################################################################
restart_services() {
    log_info "=== Restarting services ==="

    # Test nginx config
    sudo nginx -t || {
        log_error "Nginx configuration test failed"
        return 1
    }

    # Reload nginx
    sudo systemctl reload nginx
    log_info "Nginx reloaded"

    # Restart dashboard backend
    sudo systemctl restart dashboard_backend
    sudo systemctl restart cae_backend
    log_info "CAE backend restarted"
    log_info "Dashboard backend restarted"

    sleep 2

    # Check service status
    if systemctl is-active --quiet dashboard_backend; then
        log_info "Dashboard backend is running"
    else
        log_error "Dashboard backend failed to start"
        return 1
    fi
}

###################################################################################
# Fix 9: Fix GEdit WebSocket URL construction
###################################################################################
fix_gedit_websocket() {
    log_info "=== Fix 9: Fixing GEdit WebSocket URL construction ==="

    local GEDIT_HTML="$PROJECT_ROOT/dashboard/app_5174/public/apps/gedit/index.html"

    if [[ ! -f "$GEDIT_HTML" ]]; then
        log_error "GEdit HTML not found: $GEDIT_HTML"
        return 1
    fi

    # Check if already fixed (has WebSocket URL conversion logic)
    if grep -q "If wsUrl is a relative path" "$GEDIT_HTML"; then
        log_info "GEdit WebSocket URL construction already fixed"
    else
        # Add WebSocket URL conversion logic before "try {" for WebSocket creation
        # This converts relative paths like "/vncproxy/8006/websockify" to absolute "wss://host/vncproxy/8006/websockify"
        sed -i '/const wsUrl = session\.websocketUrl.*$/a\\n                                // Convert relative WebSocket URL to absolute if needed\n                                if (wsUrl.startsWith('"'"'/'"'"')) {\n                                    const protocol = window.location.protocol === '"'"'https:'"'"' ? '"'"'wss:'"'"' : '"'"'ws:'"'"';\n                                    wsUrl = `${protocol}//${window.location.host}${wsUrl}`;\n                                }' "$GEDIT_HTML"
        log_info "Fixed GEdit WebSocket URL construction"
    fi
}

###################################################################################
# Main
###################################################################################
main() {
    log_info "=========================================="
    log_info "Applying Post-Setup Fixes"
    log_info "=========================================="
    echo ""

    fix_redis_password
    echo ""

    fix_nginx_cae_proxy
    echo ""

    fix_nginx_cae_alias
    echo ""

    fix_nginx_cae_nocache
    echo ""

    fix_vnc_novnc_url
    echo ""

    fix_nginx_websocket_map
    echo ""

    fix_nginx_vnc_proxy
    echo ""

    fix_app_session_urls
    echo ""

    fix_gedit_websocket
    echo ""

    restart_services
    echo ""

    log_info "=========================================="
    log_info "All fixes applied successfully!"
    log_info "=========================================="
}

main "$@"
