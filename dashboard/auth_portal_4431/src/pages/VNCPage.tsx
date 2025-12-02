import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import '../styles/VNCPage.css';
import { API_CONFIG } from '../config/api.config';

interface VNCSession {
  session_id: string;
  job_id: number;
  username: string;
  email: string;
  status: 'pending' | 'running' | 'completed' | 'failed';
  vnc_port: number;
  novnc_port: number;
  novnc_url: string | null;
  node: string | null;
  geometry: string;
  duration_hours: number;
  gpu_count: number;
  created_at: string;
}

const VNCPage: React.FC = () => {
  const [sessions, setSessions] = useState<VNCSession[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [retryCount, setRetryCount] = useState(0);
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [isCreating, setIsCreating] = useState(false);
  const navigate = useNavigate();

  // Form state
  const [geometry, setGeometry] = useState('1920x1080');
  const [durationHours, setDurationHours] = useState(2);
  const [imageId, setImageId] = useState('xfce4');

  const getToken = () => localStorage.getItem('jwt_token');
  // Nginx routes /dashboardapi to backend 5010 /api
  const API_URL = `${API_CONFIG.VNC_API_BASE_URL}/vnc`;
  const FETCH_TIMEOUT = 10000; // 10 seconds timeout
  const MAX_RETRIES = 3;

  // Fetch VNC sessions with timeout and retry
  const fetchSessions = async (isRetry = false) => {
    // Clear previous error
    setError(null);
    setLoading(true);

    try {
      const token = getToken();
      if (!token) {
        console.warn('No JWT token found, redirecting to login');
        navigate('/');
        return;
      }

      // Debug logging
      const requestURL = `${API_URL}/sessions`;
      console.log('🔍 VNC API Request:', {
        API_CONFIG_VNC_BASE: API_CONFIG.VNC_API_BASE_URL,
        API_URL: API_URL,
        fullURL: requestURL,
        isDev: import.meta.env.DEV
      });

      // Create timeout promise
      const timeoutPromise = new Promise<never>((_, reject) => {
        setTimeout(() => reject(new Error('Request timeout')), FETCH_TIMEOUT);
      });

      // Create fetch promise
      const fetchPromise = fetch(requestURL, {
        headers: {
          'Authorization': `Bearer ${token}`,
        },
      });

      // Race between fetch and timeout
      const response = await Promise.race([fetchPromise, timeoutPromise]) as Response;

      if (response.ok) {
        const data = await response.json();
        setSessions(data.sessions || []);
        setRetryCount(0); // Reset retry count on success
        setError(null);
      } else if (response.status === 401) {
        setError('Session expired. Please log in again');
        setTimeout(() => {
          localStorage.removeItem('jwt_token');
          navigate('/');
        }, 2000);
      } else if (response.status === 404) {
        setError('VNC API endpoint not found. Backend may not be running');
      } else {
        const errorData = await response.json().catch(() => ({ error: 'Unknown error' }));
        setError(errorData.error || `Server error: ${response.status}`);
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error';
      console.error('Error fetching VNC sessions:', errorMessage);

      if (errorMessage.includes('timeout')) {
        setError('Request timed out. Backend may be slow or not responding');
      } else if (errorMessage.includes('Failed to fetch')) {
        setError('Cannot connect to backend. Please check if services are running');
      } else {
        setError(`Network error: ${errorMessage}`);
      }

      // Auto-retry logic
      if (!isRetry && retryCount < MAX_RETRIES) {
        const nextRetry = retryCount + 1;
        setRetryCount(nextRetry);
        console.log(`Retrying fetch (${nextRetry}/${MAX_RETRIES})...`);
        setTimeout(() => {
          fetchSessions(true);
        }, 2000 * nextRetry); // Exponential backoff: 2s, 4s, 6s
      }
    } finally {
      setLoading(false);
    }
  };

  // Create VNC session
  const createSession = async () => {
    setIsCreating(true);
    try {
      const token = getToken();
      if (!token) {
        navigate('/');
        return;
      }

      const response = await fetch(`${API_URL}/sessions`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          geometry,
          duration_hours: durationHours,
          image_id: imageId,
        }),
      });

      if (response.ok) {
        const session = await response.json();
        alert(`VNC session created! Job ID: ${session.job_id}`);
        setShowCreateModal(false);
        fetchSessions();
      } else {
        const error = await response.json();
        alert(error.error || 'Failed to create session');
      }
    } catch (error) {
      console.error('Error creating VNC session:', error);
      alert('Network error. Please try again');
    } finally {
      setIsCreating(false);
    }
  };

  // Delete VNC session
  const deleteSession = async (sessionId: string) => {
    if (!window.confirm('Are you sure you want to terminate this VNC session?')) {
      return;
    }

    try {
      const token = getToken();
      const response = await fetch(`${API_URL}/sessions/${sessionId}`, {
        method: 'DELETE',
        headers: {
          'Authorization': `Bearer ${token}`,
        },
      });

      if (response.ok) {
        alert('VNC session terminated');
        fetchSessions();
      } else {
        const error = await response.json();
        alert(error.error || 'Failed to delete session');
      }
    } catch (error) {
      console.error('Error deleting VNC session:', error);
    }
  };

  // Open noVNC viewer
  const openVNCViewer = (session: VNCSession) => {
    if (session.status !== 'running' || !session.novnc_url) {
      alert('VNC session is not running yet');
      return;
    }

    window.open(session.novnc_url, '_blank', 'width=1920,height=1080');
  };

  // Auto-refresh
  useEffect(() => {
    fetchSessions();
    const interval = setInterval(fetchSessions, 15000);
    return () => clearInterval(interval);
  }, []);

  // Check token
  useEffect(() => {
    const token = getToken();
    if (!token) {
      navigate('/');
    }
  }, [navigate]);

  const handleBack = () => {
    navigate('/services');
  };

  return (
    <div className="vnc-page">
      <header className="vnc-header">
        <div className="header-content">
          <button className="back-button" onClick={handleBack}>
            ← Back to Services
          </button>
          <div className="header-title">
            <h1>🖥️ Smart Twin Desktop</h1>
            <p>GPU-Accelerated Remote Desktop Sessions</p>
          </div>
          <button className="create-button" onClick={() => setShowCreateModal(true)}>
            + New Session
          </button>
        </div>
      </header>

      <main className="vnc-main">
        {error ? (
          <div className="error-state">
            <div className="error-icon">⚠️</div>
            <h2>Error Loading Sessions</h2>
            <p className="error-message">{error}</p>
            {retryCount > 0 && retryCount < MAX_RETRIES && (
              <p className="retry-info">Retrying... ({retryCount}/{MAX_RETRIES})</p>
            )}
            <button className="retry-button" onClick={() => {
              setRetryCount(0);
              fetchSessions();
            }}>
              Retry Now
            </button>
          </div>
        ) : loading && sessions.length === 0 ? (
          <div className="loading">
            <div className="spinner"></div>
            <p>Loading sessions...</p>
            {retryCount > 0 && (
              <p className="retry-info">Attempt {retryCount + 1}...</p>
            )}
          </div>
        ) : sessions.length === 0 ? (
          <div className="empty-state">
            <div className="empty-icon">🖥️</div>
            <h2>No VNC Sessions</h2>
            <p>Create a new session to get started with GPU-accelerated remote desktop</p>
            <button className="create-button-large" onClick={() => setShowCreateModal(true)}>
              Create Your First Session
            </button>
          </div>
        ) : (
          <div className="sessions-list">
            {sessions.map((session) => (
              <div key={session.session_id} className={`session-card status-${session.status}`}>
                <div className="session-header">
                  <div className="session-status">
                    <span className={`status-badge status-${session.status}`}>
                      {session.status.toUpperCase()}
                    </span>
                    <span className="job-id">Job #{session.job_id}</span>
                  </div>
                  {session.node && (
                    <span className="node-info">📡 {session.node}</span>
                  )}
                </div>

                <div className="session-details">
                  <div className="detail-item">
                    <span className="label">Resolution:</span>
                    <span className="value">{session.geometry}</span>
                  </div>
                  <div className="detail-item">
                    <span className="label">Duration:</span>
                    <span className="value">{session.duration_hours}h</span>
                  </div>
                  <div className="detail-item">
                    <span className="label">VNC Port:</span>
                    <span className="value">{session.vnc_port}</span>
                  </div>
                  <div className="detail-item">
                    <span className="label">noVNC Port:</span>
                    <span className="value">{session.novnc_port}</span>
                  </div>
                </div>

                <div className="session-footer">
                  <span className="created-time">
                    Created: {new Date(session.created_at).toLocaleString()}
                  </span>
                  <div className="session-actions">
                    {session.status === 'running' && session.novnc_url && (
                      <button
                        className="btn-open"
                        onClick={() => openVNCViewer(session)}
                      >
                        Open Desktop →
                      </button>
                    )}
                    <button
                      className="btn-delete"
                      onClick={() => deleteSession(session.session_id)}
                    >
                      Terminate
                    </button>
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </main>

      {/* Create Modal */}
      {showCreateModal && (
        <div className="modal-overlay" onClick={() => setShowCreateModal(false)}>
          <div className="modal-content" onClick={(e) => e.stopPropagation()}>
            <h2>Create VNC Session</h2>

            <div className="form-group">
              <label>Resolution</label>
              <select value={geometry} onChange={(e) => setGeometry(e.target.value)}>
                <option value="1280x720">1280x720 (HD)</option>
                <option value="1920x1080">1920x1080 (Full HD)</option>
                <option value="2560x1440">2560x1440 (QHD)</option>
                <option value="3840x2160">3840x2160 (4K)</option>
              </select>
            </div>

            <div className="form-group">
              <label>Duration (hours)</label>
              <input
                type="number"
                min="1"
                max="48"
                value={durationHours}
                onChange={(e) => setDurationHours(parseInt(e.target.value))}
              />
            </div>

            <div className="form-group">
              <label>Desktop Environment</label>
              <select value={imageId} onChange={(e) => setImageId(e.target.value)}>
                <option value="xfce4">XFCE4 Desktop (Lightweight)</option>
                <option value="gnome">GNOME Desktop (Full-featured)</option>
              </select>
            </div>

            <div className="modal-info">
              A Slurm job will be submitted with GPU access for your remote desktop session.
            </div>

            <div className="modal-actions">
              <button
                className="btn-cancel"
                onClick={() => setShowCreateModal(false)}
                disabled={isCreating}
              >
                Cancel
              </button>
              <button
                className="btn-submit"
                onClick={createSession}
                disabled={isCreating}
              >
                {isCreating ? 'Creating...' : 'Create Session'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default VNCPage;
