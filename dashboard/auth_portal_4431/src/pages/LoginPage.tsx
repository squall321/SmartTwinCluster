import React, { useState, useEffect } from 'react';
import '../styles/LoginPage.css';

const LoginPage: React.FC = () => {
  const [showTestLogin, setShowTestLogin] = useState(false);
  const [username, setUsername] = useState('koopark');
  const [group, setGroup] = useState('HPC-Admins');
  const [ssoEnabled, setSsoEnabled] = useState<boolean | null>(null);
  const [autoLoginInProgress, setAutoLoginInProgress] = useState(false);

  // Check SSO configuration and auto-login if SSO is disabled
  useEffect(() => {
    const checkSsoAndAutoLogin = async () => {
      // Already have token? Verify it first
      const existingToken = localStorage.getItem('jwt_token');
      if (existingToken) {
        try {
          // Verify token is still valid
          const verifyResponse = await fetch('/auth/services', {
            headers: { 'Authorization': `Bearer ${existingToken}` }
          });
          if (verifyResponse.ok) {
            // Token is valid, go to services
            window.location.href = '/auth_portal/services';
            return;
          } else {
            // Token is invalid, clear localStorage
            console.log('[Auth] Existing token is invalid, clearing...');
            localStorage.removeItem('jwt_token');
            localStorage.removeItem('user_info');
          }
        } catch (error) {
          console.error('[Auth] Token verification failed:', error);
          localStorage.removeItem('jwt_token');
          localStorage.removeItem('user_info');
        }
      }

      try {
        // Check SSO configuration from backend
        const response = await fetch('/auth/info');
        const data = await response.json();

        setSsoEnabled(data.sso_enabled);

        // If SSO is disabled, automatically perform test login
        if (!data.sso_enabled && !autoLoginInProgress) {
          setAutoLoginInProgress(true);
          console.log('[Auth] SSO disabled - performing automatic admin login');

          // Perform auto login with admin credentials
          const loginResponse = await fetch('/auth/test/login', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              username: 'admin',
              email: 'admin@hpc.local',
              groups: ['HPC-Admins', 'GPU-Users', 'admin']
            })
          });

          const loginData = await loginResponse.json();
          if (loginData.success && loginData.token) {
            // Store token and user info
            localStorage.setItem('jwt_token', loginData.token);
            localStorage.setItem('user_info', JSON.stringify({
              sub: loginData.user.username,
              email: loginData.user.email,
              groups: loginData.user.groups,
              permissions: ['admin', 'user', 'read', 'write', 'execute', 'delete']
            }));
            // Redirect to service menu
            window.location.href = '/auth_portal/services';
          } else {
            console.error('[Auth] Auto login failed:', loginData);
            setAutoLoginInProgress(false);
          }
        }
      } catch (error) {
        console.error('[Auth] Error checking SSO config:', error);
        setSsoEnabled(true); // Default to SSO enabled on error
      }
    };

    checkSsoAndAutoLogin();
  }, [autoLoginInProgress]);

  const handleLogin = () => {
    // Redirect to SAML SSO login
    window.location.href = '/auth/saml/login';
  };

  const handleTestLogin = async () => {
    try {
      const response = await fetch('/auth/test/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          username,
          email: `${username}@hpc.local`,
          groups: [group]
        })
      });

      const data = await response.json();
      if (data.success && data.token) {
        // Store token
        localStorage.setItem('jwt_token', data.token);
        // Redirect to service menu
        window.location.href = '/auth_portal/services';
      } else {
        alert('Test login failed');
      }
    } catch (error) {
      console.error('Test login error:', error);
      alert('Test login error');
    }
  };

  // Show loading screen during auto-login for SSO disabled mode
  if (autoLoginInProgress || ssoEnabled === null) {
    return (
      <div className="login-container">
        <div className="login-card">
          <div className="login-header">
            <h1>HPC Cluster Portal</h1>
            <p className="subtitle">Initializing...</p>
          </div>
          <div className="login-body" style={{ textAlign: 'center', padding: '40px' }}>
            <div style={{ fontSize: '48px', marginBottom: '20px' }}>⏳</div>
            <p>Preparing your session...</p>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="login-container">
      <div className="login-card">
        <div className="login-header">
          <h1>HPC Cluster Portal</h1>
          <p className="subtitle">SAML Single Sign-On Authentication</p>
        </div>

        <div className="login-body">
          <div className="info-section">
            <h3>Welcome to HPC Cluster</h3>
            <p>Access your high-performance computing resources securely through SSO.</p>

            <ul className="features">
              <li>🖥️ Job Management Dashboard</li>
              <li>🔬 CAE Automation System</li>
              <li>💻 GPU-Accelerated VNC Desktop</li>
            </ul>
          </div>

          <button className="login-button" onClick={handleLogin}>
            <span className="button-icon">🔐</span>
            Sign In with SSO
          </button>

          <div className="divider">
            <span>OR</span>
          </div>

          <button
            className="test-login-toggle"
            onClick={() => setShowTestLogin(!showTestLogin)}
          >
            {showTestLogin ? '▲' : '▼'} Developer Test Login
          </button>

          {showTestLogin && (
            <div className="test-login-form">
              <div className="form-group">
                <label>Username:</label>
                <input
                  type="text"
                  value={username}
                  onChange={(e) => setUsername(e.target.value)}
                  placeholder="admin"
                />
              </div>
              <div className="form-group">
                <label>Group:</label>
                <select value={group} onChange={(e) => setGroup(e.target.value)}>
                  <option value="HPC-Admins">HPC-Admins (Full Access - All Menus)</option>
                  <option value="DX-Users">DX-Users (Dashboard, Monitoring, VNC, SSH)</option>
                  <option value="CAEG-Users">CAEG-Users (CAE, Dashboard, VNC, SSH)</option>
                </select>
              </div>
              <button className="test-login-button" onClick={handleTestLogin}>
                🧪 Test Login
              </button>
            </div>
          )}

          <div className="login-footer">
            <p className="help-text">
              Need help? Contact your system administrator
            </p>
          </div>
        </div>
      </div>

      <div className="background-decoration">
        <div className="circle circle-1"></div>
        <div className="circle circle-2"></div>
        <div className="circle circle-3"></div>
      </div>
    </div>
  );
};

export default LoginPage;
