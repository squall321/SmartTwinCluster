import React, { useState } from 'react';
import '../styles/LoginPage.css';

const LoginPage: React.FC = () => {
  const [showTestLogin, setShowTestLogin] = useState(false);
  const [username, setUsername] = useState('koopark');
  const [group, setGroup] = useState('HPC-Admins');

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
        window.location.href = '/services';
      } else {
        alert('Test login failed');
      }
    } catch (error) {
      console.error('Test login error:', error);
      alert('Test login error');
    }
  };

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
