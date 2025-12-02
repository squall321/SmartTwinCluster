import React, { useEffect } from 'react';
import { Dashboard } from './components/Dashboard';
import { ThemeProvider } from './contexts/ThemeContext';
import { AuthProvider } from './contexts/AuthContext';
import { setJwtToken } from './utils/api';
import './index.css';

function App() {
  useEffect(() => {
    // Extract JWT token from URL query parameters (from Auth Portal)
    const urlParams = new URLSearchParams(window.location.search);
    const token = urlParams.get('token');

    if (token) {
      console.log('[Auth] JWT token received from URL, storing in localStorage');
      setJwtToken(token);

      // Remove token from URL for security (prevent token exposure in browser history)
      window.history.replaceState({}, document.title, window.location.pathname);

      // Reload to apply authentication
      window.location.reload();
    }
  }, []);

  return (
    <ThemeProvider>
      <AuthProvider>
        <Dashboard />
      </AuthProvider>
    </ThemeProvider>
  );
}

export default App;
