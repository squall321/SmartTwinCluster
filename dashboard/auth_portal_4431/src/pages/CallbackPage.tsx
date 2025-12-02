import React, { useEffect, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import '../styles/CallbackPage.css';

const CallbackPage: React.FC = () => {
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();
  const [status, setStatus] = useState<'processing' | 'success' | 'error'>('processing');
  const [error, setError] = useState<string>('');

  useEffect(() => {
    const token = searchParams.get('token');

    if (!token) {
      setStatus('error');
      setError('No authentication token received');
      return;
    }

    // Store token in localStorage
    localStorage.setItem('jwt_token', token);

    // Verify token with backend
    fetch('/auth/verify', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`
      }
    })
      .then(response => {
        if (!response.ok) {
          throw new Error('Token verification failed');
        }
        return response.json();
      })
      .then(data => {
        setStatus('success');
        localStorage.setItem('user_info', JSON.stringify(data.user));

        // Redirect to service menu after brief delay
        setTimeout(() => {
          navigate('/services');
        }, 1500);
      })
      .catch(err => {
        setStatus('error');
        setError(err.message || 'Authentication failed');
        localStorage.removeItem('jwt_token');
      });
  }, [searchParams, navigate]);

  return (
    <div className="callback-container">
      <div className="callback-card">
        {status === 'processing' && (
          <>
            <div className="spinner"></div>
            <h2>Authenticating...</h2>
            <p>Please wait while we verify your credentials</p>
          </>
        )}

        {status === 'success' && (
          <>
            <div className="success-icon">✓</div>
            <h2>Authentication Successful!</h2>
            <p>Redirecting to services...</p>
          </>
        )}

        {status === 'error' && (
          <>
            <div className="error-icon">✗</div>
            <h2>Authentication Failed</h2>
            <p className="error-message">{error}</p>
            <button className="retry-button" onClick={() => navigate('/')}>
              Return to Login
            </button>
          </>
        )}
      </div>
    </div>
  );
};

export default CallbackPage;
