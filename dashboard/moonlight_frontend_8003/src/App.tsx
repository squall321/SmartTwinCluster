/**
 * Moonlight Frontend Main App
 * Ultra-Low Latency Streaming for HPC
 */

import { useState, useEffect } from 'react';
import {
  Container,
  Box,
  Typography,
  AppBar,
  Toolbar,
  Button,
  Alert,
  CircularProgress,
  Divider,
  Paper,
} from '@mui/material';
import { Refresh, Videocam } from '@mui/icons-material';
import { ImageSelector } from './components/ImageSelector';
import { SessionList } from './components/SessionList';
import {
  getImages,
  getSessions,
  createSession,
  stopSession,
  healthCheck,
} from './api/moonlight';
import type { MoonlightImage, MoonlightSession } from './api/moonlight';

function App() {
  const [images, setImages] = useState<MoonlightImage[]>([]);
  const [sessions, setSessions] = useState<MoonlightSession[]>([]);
  const [selectedImage, setSelectedImage] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [backendHealth, setBackendHealth] = useState<boolean>(false);

  // 초기 데이터 로드
  useEffect(() => {
    loadData();
    checkBackendHealth();

    // 5초마다 세션 상태 업데이트
    const interval = setInterval(() => {
      loadSessions();
    }, 5000);

    return () => clearInterval(interval);
  }, []);

  const checkBackendHealth = async () => {
    try {
      await healthCheck();
      setBackendHealth(true);
    } catch (err) {
      setBackendHealth(false);
      console.error('Backend health check failed:', err);
    }
  };

  const loadData = async () => {
    await Promise.all([loadImages(), loadSessions()]);
  };

  const loadImages = async () => {
    try {
      const data = await getImages();
      setImages(data);

      // 기본 이미지 자동 선택
      const defaultImage = data.find((img) => img.default);
      if (defaultImage) {
        setSelectedImage(defaultImage.id);
      }
    } catch (err: any) {
      setError(`Failed to load images: ${err.message}`);
      console.error(err);
    }
  };

  const loadSessions = async () => {
    try {
      const data = await getSessions();
      setSessions(data);
    } catch (err: any) {
      console.error('Failed to load sessions:', err);
    }
  };

  const handleCreateSession = async (imageId: string) => {
    setLoading(true);
    setError(null);

    try {
      const newSession = await createSession({ image_id: imageId });
      setSessions([newSession, ...sessions]);

      alert(
        `Session created successfully!\n\n` +
          `Session ID: ${newSession.session_id}\n` +
          `Display: :${newSession.display_num}\n` +
          `Port: ${newSession.sunshine_port}\n\n` +
          `Status: ${newSession.status}\n\n` +
          `Please wait for the session to start (status: running)`
      );

      // 세션 목록 새로고침
      setTimeout(() => {
        loadSessions();
      }, 2000);
    } catch (err: any) {
      setError(`Failed to create session: ${err.response?.data?.error || err.message}`);
    } finally {
      setLoading(false);
    }
  };

  const handleStopSession = async (sessionId: string) => {
    if (!confirm('Are you sure you want to stop this session?')) {
      return;
    }

    setLoading(true);
    setError(null);

    try {
      await stopSession(sessionId);
      setSessions(sessions.filter((s) => s.session_id !== sessionId));

      alert('Session stopped successfully');

      // 세션 목록 새로고침
      setTimeout(() => {
        loadSessions();
      }, 1000);
    } catch (err: any) {
      setError(`Failed to stop session: ${err.response?.data?.error || err.message}`);
    } finally {
      setLoading(false);
    }
  };

  const handleConnectSession = (session: MoonlightSession) => {
    alert(
      `Connect to session:\n\n` +
        `Session ID: ${session.session_id}\n` +
        `Node: ${session.slurm_node}\n` +
        `Display: :${session.display_num}\n` +
        `Port: ${session.sunshine_port}\n\n` +
        `Note: Moonlight Web Client integration is coming soon!\n` +
        `For now, use native Moonlight client with the connection details above.`
    );
  };

  return (
    <Box sx={{ flexGrow: 1, minHeight: '100vh', bgcolor: '#f5f5f5' }}>
      {/* Header */}
      <AppBar position="static">
        <Toolbar>
          <Videocam sx={{ mr: 2 }} />
          <Typography variant="h6" component="div" sx={{ flexGrow: 1 }}>
            Moonlight/Sunshine - Ultra-Low Latency Streaming
          </Typography>

          <Button
            color="inherit"
            startIcon={<Refresh />}
            onClick={loadData}
            disabled={loading}
          >
            Refresh
          </Button>
        </Toolbar>
      </AppBar>

      <Container maxWidth="xl" sx={{ mt: 4, mb: 4 }}>
        {/* Backend Status */}
        {!backendHealth && (
          <Alert severity="error" sx={{ mb: 3 }}>
            Backend is not responding. Please check if the Moonlight Backend is running on port
            8004.
          </Alert>
        )}

        {/* Error Alert */}
        {error && (
          <Alert severity="error" onClose={() => setError(null)} sx={{ mb: 3 }}>
            {error}
          </Alert>
        )}

        {/* Loading Indicator */}
        {loading && (
          <Box display="flex" justifyContent="center" my={2}>
            <CircularProgress />
          </Box>
        )}

        {/* Image Selector Section */}
        <Paper elevation={2} sx={{ p: 3, mb: 4 }}>
          <Typography variant="h5" gutterBottom>
            Select Desktop Environment
          </Typography>
          <Typography variant="body2" color="text.secondary" paragraph>
            Choose a desktop environment to start a new streaming session
          </Typography>

          {images.length === 0 ? (
            <Box textAlign="center" py={4}>
              <CircularProgress />
              <Typography variant="body2" color="text.secondary" mt={2}>
                Loading images...
              </Typography>
            </Box>
          ) : (
            <ImageSelector
              images={images}
              selectedImage={selectedImage}
              onSelect={setSelectedImage}
              onCreateSession={handleCreateSession}
              loading={loading}
            />
          )}
        </Paper>

        <Divider sx={{ my: 4 }} />

        {/* Session List Section */}
        <Paper elevation={2} sx={{ p: 3 }}>
          <Box display="flex" justifyContent="space-between" alignItems="center" mb={2}>
            <Typography variant="h5">Active Sessions</Typography>
            <Typography variant="body2" color="text.secondary">
              {sessions.length} session{sessions.length !== 1 ? 's' : ''}
            </Typography>
          </Box>

          <SessionList
            sessions={sessions}
            onStopSession={handleStopSession}
            onConnectSession={handleConnectSession}
            loading={loading}
          />
        </Paper>

        {/* Footer */}
        <Box textAlign="center" mt={4} py={2}>
          <Typography variant="body2" color="text.secondary">
            Moonlight/Sunshine Frontend v1.0.0 | Backend Port: 8004 | Signaling Port: 8005
            (Coming Soon)
          </Typography>
        </Box>
      </Container>
    </Box>
  );
}

export default App;
