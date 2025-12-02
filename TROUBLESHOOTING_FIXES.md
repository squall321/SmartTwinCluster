# Troubleshooting Fixes Applied

This document describes all manual fixes that were discovered during troubleshooting and have been automated in the setup scripts.

## Summary of Issues and Fixes

### 1. CAE Frontend Token Exposure in URL
**Problem:** When navigating from Auth Portal to CAE service, the JWT token remained visible in the URL, creating a security risk.

**Root Cause:** CAE Dashboard component didn't check for URL token parameter and remove it after saving to localStorage.

**Solution:**
- Modified `dashboard/kooCAEWeb_5173/src/pages/Dashboard.tsx` to:
  - Check for `token` parameter in URL
  - Save token to localStorage
  - Decode JWT and extract user info
  - Remove token from URL using `window.history.replaceState()`

**Files Modified:**
- `dashboard/kooCAEWeb_5173/src/pages/Dashboard.tsx` (lines 17-64)
- `dashboard/kooCAEWeb_5173/src/pages/Login.tsx` (line 30)

---

### 2. Mixed Content Errors (HTTP requests on HTTPS page)
**Problem:** CAE frontend made HTTP requests to `http://110.15.177.120:5000` from HTTPS page, causing browser to block requests.

**Root Cause:** CAE frontend components used absolute paths starting with `/api/proxy/automation/` which bypassed axios baseURL configuration.

**Solution:**
- Modified file tree components to use automation API with proper baseURL
- Updated nginx configuration to fix CAE backend proxy path

**Files Modified:**
- `dashboard/kooCAEWeb_5173/src/components/common/FileTreeExplorer.tsx`
  - Changed baseUrl from `/api/proxy/automation/api/files/${username}` to `/api/files/${username}`
  - Created dedicated axios instance with `API_CONFIG.AUTOMATION_URL` as baseURL
  - Changed all `api.*` calls to `automationApi.*`

- `dashboard/kooCAEWeb_5173/src/components/common/FileTreeTextBox.tsx`
  - Same changes as FileTreeExplorer.tsx

- `/etc/nginx/conf.d/auth-portal.conf`
  - Fixed CAE backend proxy: `/cae/api/` now proxies to `http://localhost:5000/api/` (not just `/`)
  - Fixed CAE frontend alias: `alias /var/www/html/cae;` (not `kooCAEWeb_5173`)
  - Added no-cache headers for CAE `index.html` to prevent browser caching issues

---

### 3. Redis Authentication Error for VNC Service
**Problem:** Dashboard backend VNC API returned 500 errors due to Redis authentication failure.

**Root Cause:** Redis server had password `changeme` configured, but backend code didn't include password parameter when connecting.

**Solution:**
- Added `password` parameter to Redis client initialization
- Added `REDIS_PASSWORD` to backend .env file

**Files Modified:**
- `dashboard/backend_5010/vnc_api.py` (line 23)
  - Added: `password=os.getenv('REDIS_PASSWORD', None),`

- `dashboard/backend_5010/performance.py` (lines 20-23)
  - Added: `import os`
  - Added: `password=os.getenv('REDIS_PASSWORD', None),`
  - Changed hardcoded values to use environment variables

- `dashboard/backend_5010/.env`
  - Added: `REDIS_PASSWORD=changeme`

---

### 4. CAE Backend Mock Mode
**Problem:** CAE backend was running in mock mode instead of using real Slurm commands.

**Root Cause:** CAE backend uses `MOCK_SLURM` environment variable (not `MOCK_MODE`), and systemd services had wrong variable name.

**Solution:**
- Updated systemd service files to use `MOCK_SLURM=0`
- Fixed CAE backend `slurm_utils.py` to call real commands when not in mock mode

**Files Modified:**
- `/etc/systemd/system/cae_backend.service`
  - Changed: `Environment="MOCK_MODE=false"` to `Environment="MOCK_SLURM=0"`

- `/etc/systemd/system/cae_automation.service`
  - Same change as above

- `dashboard/kooCAEWebServer_5000/utils/slurm_utils.py`
  - Added real Slurm command calls in `get_sinfo()` and `get_squeue()` when `MOCK_MODE=False`

---

### 5. App Service Landing Page
**Problem:** App service showed React test page instead of the proper gedit launcher page.

**Root Cause:** The vite build creates a React app index.html, but the production landing page should be `landing.html` which shows the app launcher with gedit.

**Solution:**
- Copy `landing.html` to `dist/index.html` after building app_5174
- This ensures the production app shows the launcher page instead of test page

**Files Modified:**
- `cluster/setup/phase5_web.sh` (lines 659-663)
  - Added special handling for app_5174 to copy landing.html after build
  - Ensures gedit launcher page is deployed to production

- `dashboard/build_all_frontends.sh` (line 125)
  - Already had: `cp landing.html dist/index.html 2>/dev/null || true`
  - This ensures local builds also use landing page

**Manual Fix Applied:**
```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/app_5174
cp landing.html dist/index.html
sudo cp -r dist/* /var/www/html/app_5174/
sudo chown -R www-data:www-data /var/www/html/app_5174
sudo chmod -R 755 /var/www/html/app_5174
```

---

### 6. App Service (GEdit) Mixed Content Errors
**Problem:** GEdit app showed Mixed Content errors - HTTPS page making HTTP requests.

**Root Cause:**
- `app_5174/public/apps/gedit/index.html` had hardcoded HTTP URLs
- Line 248: `http://localhost:5000` for localhost development
- Line 414: WebSocket URL conversion only handled `http://` not `https://`

**Solution:**
- Always use relative paths through nginx proxy
- Handle both HTTP and HTTPS → WebSocket protocol conversion

**Files Modified:**
- `dashboard/app_5174/public/apps/gedit/index.html` (lines 243-246, 411)
  - Changed API_BASE to always use `${window.location.protocol}//${window.location.host}/cae`
  - Fixed WebSocket URL to handle both `http://` → `ws://` and `https://` → `wss://`

**Before:**
```javascript
const API_BASE = window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1'
    ? 'http://localhost:5000'
    : `${window.location.protocol}//${window.location.host}/cae`;

const wsUrl = session.websocketUrl || session.displayUrl.replace('http://', 'ws://').replace('/vnc.html?autoconnect=true&resize=scale', '/websockify');
```

**After:**
```javascript
const API_BASE = `${window.location.protocol}//${window.location.host}/cae`;

const wsUrl = session.websocketUrl || session.displayUrl.replace(/^https?:\/\//, (match) => match.startsWith('https') ? 'wss://' : 'ws://').replace('/vnc.html?autoconnect=true&resize=scale', '/websockify');
```

**Manual Fix Applied:**
```bash
sudo cp /home/koopark/claude/KooSlurmInstallAutomationRefactory/dashboard/app_5174/public/apps/gedit/index.html /var/www/html/app_5174/apps/gedit/index.html
sudo chown www-data:www-data /var/www/html/app_5174/apps/gedit/index.html
sudo chmod 644 /var/www/html/app_5174/apps/gedit/index.html
```

---

### 7. App Service (GEdit) Connection Error
**Problem:** GEdit app sessions created but couldn't connect - same ERR_CONNECTION_CLOSED as VNC service.

**Root Cause:**
- CAE backend generated direct port URLs like `http://110.15.177.120:8000/vnc.html`
- Same issue as VNC service - direct port access blocked by firewall

**Solution:**
- Change CAE backend to generate nginx proxy paths
- Use same `/vncproxy/<port>/` pattern as VNC service

**Files Modified:**
- `dashboard/kooCAEWebServer_5000/services/app_session_service.py` (lines 106-107, 214-215)
  - Changed from: `f'http://{backend_host}:{local_port}/vnc.html'`
  - Changed to: `f'/vncproxy/{local_port}/vnc.html'`
  - Changed websocketUrl similarly

**Before:**
```python
self.sessions[session_id]['displayUrl'] = f'http://{backend_host}:{local_port}/vnc.html?autoconnect=true&resize=scale'
self.sessions[session_id]['websocketUrl'] = f'ws://{backend_host}:{local_port}/websockify'
```

**After:**
```python
self.sessions[session_id]['displayUrl'] = f'/vncproxy/{local_port}/vnc.html?autoconnect=true&resize=scale'
self.sessions[session_id]['websocketUrl'] = f'/vncproxy/{local_port}/websockify'
```

**Manual Fix Applied:**
- Edited app_session_service.py
- Restarted cae_backend service

---

### 8. VNC Service Connection Error (ERR_CONNECTION_CLOSED)
**Problem:** VNC sessions created successfully but "연결하기" button resulted in ERR_CONNECTION_CLOSED error.

**Root Cause:**
- Backend generated direct port URLs like `https://110.15.177.120:6901/vnc.html`
- nginx only had port 443 open, couldn't access ports 6901-6999 directly
- No proxy configuration for VNC noVNC ports

**Solution:**
- Change backend to generate relative URLs through nginx proxy
- Add dynamic port proxying in nginx for VNC WebSocket connections
- Add WebSocket support map in nginx.conf

**Files Modified:**
- `dashboard/backend_5010/vnc_api.py` (lines 650, 705)
  - Changed from: `f"{protocol}://{EXTERNAL_IP}:{novnc_port}/vnc.html"`
  - Changed to: `f"/vncproxy/{novnc_port}/vnc.html"`

- `/etc/nginx/nginx.conf`
  - Added WebSocket support map:
  ```nginx
  map $http_upgrade $connection_upgrade {
      default upgrade;
      '' close;
  }
  ```

- `/etc/nginx/conf.d/auth-portal.conf`
  - Added dynamic VNC proxy location block:
  ```nginx
  location ~ ^/vncproxy/([0-9]+)/(.*)$ {
      proxy_pass http://127.0.0.1:$1/$2$is_args$args;
      proxy_http_version 1.1;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection $connection_upgrade;
      # ... WebSocket headers
  }
  ```

**Manual Fix Applied:**
- Edited vnc_api.py to use relative URLs
- Added WebSocket map to nginx.conf
- Added VNC proxy location to auth-portal.conf
- Restarted dashboard_backend service
- Reloaded nginx

---

## Automation

All these fixes have been automated in:

### `cluster/setup/apply_post_setup_fixes.sh`
This script applies all fixes automatically and is called by `phase5_web.sh` after web services setup.

The script includes:
1. Redis password addition to dashboard backend .env
2. Nginx CAE backend proxy path fix
3. Nginx CAE frontend alias path fix
4. Nginx CAE index.html no-cache headers
5. Service restarts with verification

### Integration with Setup Scripts
`cluster/setup/phase5_web.sh` now automatically calls `apply_post_setup_fixes.sh` after deploying web services, ensuring all fixes are applied during initial setup.

---

## How to Apply Fixes Manually

If you need to apply these fixes to an existing installation:

```bash
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory
sudo ./cluster/setup/apply_post_setup_fixes.sh
```

---

## Verification

After applying fixes, verify everything works:

### 1. CAE Service
```bash
# Open browser to https://YOUR_IP/cae/
# Check that:
# - URL token disappears after page load
# - No mixed content errors in console
# - File tree loads successfully
```

### 2. VNC Service
```bash
# Open browser to https://YOUR_IP/vnc/
# Check that:
# - VNC sessions list loads (no 500 error)
# - Can create new VNC sessions
```

### 3. Dashboard Service
```bash
# Open browser to https://YOUR_IP/dashboard/
# Check that:
# - Node list shows all 4 nodes
# - Slurm commands work (not mock data)
```

---

## Notes for Future Setup

- **Code fixes** (*.tsx, *.py files) are permanent and will be included in future builds
- **Configuration fixes** (nginx, systemd, .env) are applied by `apply_post_setup_fixes.sh`
- **Setup scripts** (`phase5_web.sh`) automatically call the fixes script
- **Clean reinstall** will include all fixes automatically

---

Last Updated: 2025-10-30
