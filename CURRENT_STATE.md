# 현재 시스템 상태 (Phase 0)

생성 일시: 2025-10-20 01:52:15
수집 스크립트: collect_current_state.sh

---

## 1. 포트 사용 현황

| 포트 | 상태 | PID | 프로세스 | 서비스 |
|------|------|-----|---------|--------|
| 3010 | ⚪ 미사용 | - | - | - |
| 4430 | 🟢 사용 중 | 3516898
3516900 | unknown |  |
| 4431 | ⚪ 미사용 | - | - | - |
| 5000 | ⚪ 미사용 | - | - | - |
| 5001 | 🟢 사용 중 | 1208197
1208348 | unknown |  |
| 5010 | 🟢 사용 중 | 2787298 | python3 | app.py |
| 5011 | ⚪ 미사용 | - | - | - |
| 5173 | ⚪ 미사용 | - | - | - |
| 8002 | ⚪ 미사용 | - | - | - |
| 9090 | 🟢 사용 중 | 1207974 | prometheus |  |
| 9100 | 🟢 사용 중 | 1207936
1207974 | unknown |  |

## 2. Dashboard 디렉토리 구조

```
dashboard/
dashboard/auth_portal_4430
dashboard/auth_portal_4430/config
dashboard/auth_portal_4430/logs
dashboard/auth_portal_4430/__pycache__
dashboard/auth_portal_4430/saml
dashboard/auth_portal_4430/venv
dashboard/auth_portal_4431
dashboard/auth_portal_4431/node_modules
dashboard/auth_portal_4431/public
dashboard/auth_portal_4431/src
dashboard/backend_5010
dashboard/backend_5010/database
dashboard/backend_5010/logs
dashboard/backend_5010/middleware
dashboard/backend_5010/__pycache__
dashboard/backend_5010/venv
dashboard/backend_5010/venv2
dashboard/cae_service_8001
dashboard/database
dashboard/frontend_3010
dashboard/frontend_3010/logs
dashboard/frontend_3010/node_modules
dashboard/frontend_3010/src
dashboard/frontend_3010/tests
dashboard/frontend_3010/.vite
dashboard/kooCAEWeb_5173
dashboard/kooCAEWeb_5173/node_modules
dashboard/kooCAEWeb_5173/public
dashboard/kooCAEWeb_5173/src
dashboard/kooCAEWeb_5173/.vscode
dashboard/kooCAEWebAutomationServer_5001
dashboard/kooCAEWebAutomationServer_5001/app
dashboard/kooCAEWebAutomationServer_5001/Data
dashboard/kooCAEWebAutomationServer_5001/model
dashboard/kooCAEWebAutomationServer_5001/__pycache__
dashboard/kooCAEWebAutomationServer_5001/routes
dashboard/kooCAEWebAutomationServer_5001/services
dashboard/kooCAEWebAutomationServer_5001/venv
dashboard/kooCAEWebAutomationServer_5001/.vscode
dashboard/kooCAEWebServer_5000
dashboard/kooCAEWebServer_5000/build
dashboard/kooCAEWebServer_5000/db
dashboard/kooCAEWebServer_5000/job_templates
dashboard/kooCAEWebServer_5000/models
dashboard/kooCAEWebServer_5000/__pycache__
dashboard/kooCAEWebServer_5000/routes
dashboard/kooCAEWebServer_5000/services
dashboard/kooCAEWebServer_5000/source
dashboard/kooCAEWebServer_5000/uploads
dashboard/kooCAEWebServer_5000/utils
dashboard/kooCAEWebServer_5000/venv
dashboard/kooCAEWebServer_5000/venvWin
dashboard/kooCAEWebServer_5000/.vscode
dashboard/node_exporter_9100
dashboard/planning_phases
dashboard/prometheus_9090
dashboard/prometheus_9090/console_libraries
dashboard/prometheus_9090/consoles
dashboard/prometheus_9090/data
dashboard/saml_idp_7000
dashboard/saml_idp_7000/certs
dashboard/saml_idp_7000/config
dashboard/saml_idp_7000/logs
dashboard/vnc_sandbox
dashboard/vnc_service_8002
dashboard/vnc_service_8002/node_modules
dashboard/vnc_service_8002/public
dashboard/vnc_service_8002/src
dashboard/websocket_5011
dashboard/websocket_5011/database
dashboard/websocket_5011/__pycache__
dashboard/websocket_5011/venv
```

## 3. 서비스별 의존성

| 서비스 | Python venv | Node.js | requirements.txt | package.json |
|--------|-------------|---------|------------------|--------------|
| auth_portal_4430 | ✅ | ❌ | ✅ | ❌ |
| auth_portal_4431 | ❌ | ✅ | ❌ | ✅ |
| backend_5010 | ✅ | ❌ | ✅ | ❌ |
| frontend_3010 | ❌ | ✅ | ❌ | ✅ |
| websocket_5011 | ✅ | ❌ | ✅ | ❌ |
| vnc_service_8002 | ❌ | ✅ | ❌ | ✅ |
| kooCAEWeb_5173 | ❌ | ✅ | ❌ | ✅ |

## 4. 환경 변수 사용 현황

### Python (os.getenv)
```python
    CAE_URL = os.getenv('CAE_URL', 'https://localhost/cae/')
        check_cmd = f"ssh -o ConnectTimeout=1 -o StrictHostKeyChecking=no {os.getenv('USER')}@{node} 'lsof -i :{vnc_port} | grep LISTEN' 2>/dev/null"
        check_novnc_cmd = f"ssh -o ConnectTimeout=1 -o StrictHostKeyChecking=no {os.getenv('USER')}@{node} 'lsof -i :{novnc_port} | grep LISTEN' 2>/dev/null"
        current_mode = os.getenv('MOCK_MODE', 'true').lower() == 'true'
    DASHBOARD_URL = os.getenv('DASHBOARD_URL', 'https://localhost/dashboard/')
            date = os.getenv("SOURCE_DATE_EPOCH")
        db=int(os.getenv('REDIS_DB', 0)),
    DEBUG = os.getenv('FLASK_DEBUG', 'False') == 'True'
        elif os.getenv("DISPLAY"):
    env = {name: os.getenv(name) for name in env_names}
        for font_dir in (os.path.join(os.getenv("HOME"), 'Library/Fonts/'),
HAS_DISPLAY = os.getenv("DISPLAY")
    HOST = os.getenv('HOST', '0.0.0.0')
        host=os.getenv('REDIS_HOST', '127.0.0.1'),
    if env["MPLBACKEND"] == "gtk3cairo" and os.getenv("CI"):
    if os.getenv("ANDROID_DATA") == "/data" and os.getenv("ANDROID_ROOT") == "/system":
    if os.getenv("DISTUTILS_USE_SDK"):
        if os.getenv(env_var):
        if os.getenv("SHELL") or os.getenv("PREFIX"):
        if os.getenv("WAYLAND_DISPLAY"):
    JWT_ALGORITHM = os.getenv('JWT_ALGORITHM', 'HS256')
JWT_ALGORITHM = os.getenv('JWT_ALGORITHM', 'HS256')
    JWT_EXPIRATION_HOURS = int(os.getenv('JWT_EXPIRATION_HOURS', '8'))
    JWT_SECRET_KEY = os.getenv('JWT_SECRET_KEY', 'dev-jwt-secret-please-change')
JWT_SECRET_KEY = os.getenv('JWT_SECRET_KEY', 'dev-jwt-secret-please-change')
MOCK_MODE = os.getenv('MOCK_MODE', 'false').lower() == 'true'
MOCK_MODE = os.getenv('MOCK_MODE', 'true').lower() == 'true'
        or os.getenv("DATABRICKS_RUNTIME_VERSION")
        path = os.getenv('XDG_CACHE_HOME', os.path.expanduser('~/.cache'))
        path = os.getenv('XDG_CONFIG_DIRS', '/etc/xdg')
        path = os.getenv('XDG_CONFIG_HOME', os.path.expanduser("~/.config"))
        path = os.getenv('XDG_DATA_DIRS',
        path = os.getenv('XDG_DATA_HOME', os.path.expanduser("~/.local/share"))
        path = os.getenv('XDG_STATE_HOME', os.path.expanduser("~/.local/state"))
        paths = os.getenv('path').split(os.pathsep)
        policy = os.getenv("NUMPY_WARN_IF_NO_MEM_POLICY", "0") == "1"
    PORT = int(os.getenv('PORT', '4430'))
        port=int(os.getenv('REDIS_PORT', 6379)),
PROMETHEUS_URL = os.getenv('PROMETHEUS_URL', 'http://localhost:9090')
PSUTIL_DEBUG = bool(os.getenv('PSUTIL_DEBUG'))
    _psutil_debug_orig = bool(os.getenv('PSUTIL_DEBUG'))
    REDIS_DB = int(os.getenv('REDIS_DB', '0'))
    REDIS_HOST = os.getenv('REDIS_HOST', 'localhost')
    REDIS_PASSWORD = os.getenv('REDIS_PASSWORD', '')
    REDIS_PORT = int(os.getenv('REDIS_PORT', '6379'))
    """Replace all environment variables that can be retrieved via `os.getenv`.
    return os.getenv('MOCK_MODE', 'true').lower() == 'true'
    SAML_ACS_URL = os.getenv('SAML_ACS_URL', 'http://localhost:4430/auth/saml/acs')
    SAML_IDP_METADATA_URL = os.getenv('SAML_IDP_METADATA_URL', 'http://localhost:7000/metadata')
    SAML_SLS_URL = os.getenv('SAML_SLS_URL', 'http://localhost:4430/auth/saml/sls')
    SAML_SP_ENTITY_ID = os.getenv('SAML_SP_ENTITY_ID', 'auth-portal')
    SECRET_KEY = os.getenv('SECRET_KEY', 'dev-secret-key-please-change')
        skip_host_check = os.getenv('SKIP_SSH_HOST_KEY_CHECK', 'false').lower() == 'true'
SLURM_BIN_DIR = os.getenv('SLURM_BIN_DIR', '/usr/local/slurm/bin')
        so_ext = os.getenv('SETUPTOOLS_EXT_SUFFIX')
        source_date_epoch = os.getenv("SOURCE_DATE_EPOCH")
    source_date_epoch = os.getenv("SOURCE_DATE_EPOCH")
                ['sudo', 'chown', os.getenv('USER', 'koopark'), backup_path],
            value = os.getenv(var_name)
    VNC_URL = os.getenv('VNC_URL', 'http://localhost:4431/vnc')
```

### TypeScript/JavaScript (process.env)
```typescript
	Accepts an object of environment variables, like `process.env`, and modifies the PATH using the correct [PATH key](https://github.com/sindresorhus/path-key). Use this if you're modifying the PATH for use in the `child_process` options.
console.log(process.env.PATH);
const API_BASE_URL = import.meta.env.VITE_API_URL || '';
const AUTH_PORTAL_URL = import.meta.env.VITE_AUTH_PORTAL_URL || 'http://localhost:4431';
const isProduction: boolean = process.env.NODE_ENV === 'production';
	const PATH = process.env[key];
const PATH = process.env[key];
	@default process.env
	@default [process.env](https://nodejs.org/api/process.html#processenv)
	Default: [`process.env`](https://nodejs.org/api/process.html#process_process_env).
      } else if (process.env.NODE_ENV === 'development') {
	Environment key-value pairs. Extends automatically from `process.env`. Set `extendEnv` to `false` if you don't want this.
      if (process.env.CI === "true") {
        if (process.env.NODE_ENV === 'development') {
      if (process.env.NODE_ENV === 'development') {
    if (process.env.NODE_ENV === 'development') {
if (process.env.NODE_ENV === 'development') {
      if (process.env.NODE_ENV === 'development' && !event.defaultPrevented) {
  !isES && !process.env.ROLLUP_WATCH && filesizePlugin(),
  !isES && !process.env.ROLLUP_WATCH && terserPlugin(),
	"no-process-env": Linter.RuleEntry<[]>;
@returns The augmented [`process.env`](https://nodejs.org/api/process.html#process_process_env) object.
		typeof process !== 'undefined' && process.env['NODE_ENV'] === 'production'
		Use a custom environment variables object. Default: [`process.env`](https://nodejs.org/api/process.html#process_process_env).
```

## 5. Nginx 상태

- 설치됨: nginx/1.18.0
- 상태: 🟢 실행 중

### 현재 Nginx 설정 파일
```
total 8
drwxr-xr-x 2 root root 4096 10월 20 00:09 .
drwxr-xr-x 8 root root 4096 10월 16 13:36 ..
lrwxrwxrwx 1 root root   34 10월 16 13:36 default -> /etc/nginx/sites-available/default
lrwxrwxrwx 1 root root   48 10월 20 00:09 hpc_web_services.conf -> /etc/nginx/sites-available/hpc_web_services.conf
```

## 6. 하드코딩된 localhost URL

### Python 파일
```python
dashboard/auth_portal_4430/saml_handler.py:109:                'entityId': 'http://localhost:7000/metadata',
dashboard/auth_portal_4430/saml_handler.py:111:                    'url': 'http://localhost:7000/saml/sso',
dashboard/auth_portal_4430/saml_handler.py:115:                    'url': 'http://localhost:7000/saml/slo',
dashboard/auth_portal_4430/app.py:113:        frontend_url = f"http://localhost:4431/auth/callback"
dashboard/auth_portal_4430/config/config.py:30:    SAML_IDP_METADATA_URL = os.getenv('SAML_IDP_METADATA_URL', 'http://localhost:7000/metadata')
dashboard/auth_portal_4430/config/config.py:32:    SAML_ACS_URL = os.getenv('SAML_ACS_URL', 'http://localhost:4430/auth/saml/acs')
dashboard/auth_portal_4430/config/config.py:33:    SAML_SLS_URL = os.getenv('SAML_SLS_URL', 'http://localhost:4430/auth/saml/sls')
dashboard/auth_portal_4430/config/config.py:38:    VNC_URL = os.getenv('VNC_URL', 'http://localhost:4431/vnc')
```

### TypeScript 파일
```typescript
dashboard/auth_portal_4431/src/pages/VNCPage.tsx:33:  const API_URL = 'http://localhost:5010/api/vnc';
```


## 7. 시스템 정보

- OS: Ubuntu 22.04.5 LTS
- Kernel: 5.15.0-157-generic
- Python: Python 3.10.12
- Node.js: v20.19.5
- npm: 10.8.2
- Nginx: nginx/1.18.0

