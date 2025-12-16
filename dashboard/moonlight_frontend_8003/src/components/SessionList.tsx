/**
 * SessionList Component
 * 현재 세션 목록 표시
 */

import {
  Paper,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Chip,
  IconButton,
  Tooltip,
  Box,
  Typography,
} from '@mui/material';
import {
  Stop,
  PlayArrow,
  Error,
  CheckCircle,
  Schedule,
} from '@mui/icons-material';
import type { MoonlightSession } from '../api/moonlight';

interface SessionListProps {
  sessions: MoonlightSession[];
  onStopSession: (sessionId: string) => void;
  onConnectSession: (session: MoonlightSession) => void;
  loading?: boolean;
}

const getStatusIcon = (status: string) => {
  switch (status) {
    case 'running':
      return <CheckCircle color="success" />;
    case 'pending':
      return <Schedule color="warning" />;
    case 'failed':
      return <Error color="error" />;
    case 'stopped':
      return <Stop color="disabled" />;
    default:
      return <Schedule />;
  }
};

const getStatusColor = (
  status: string
): 'success' | 'warning' | 'error' | 'default' => {
  switch (status) {
    case 'running':
      return 'success';
    case 'pending':
      return 'warning';
    case 'failed':
      return 'error';
    case 'stopped':
      return 'default';
    default:
      return 'default';
  }
};

export const SessionList: React.FC<SessionListProps> = ({
  sessions,
  onStopSession,
  onConnectSession,
  loading = false,
}) => {
  if (sessions.length === 0) {
    return (
      <Box textAlign="center" py={8}>
        <Typography variant="h6" color="text.secondary">
          No active sessions
        </Typography>
        <Typography variant="body2" color="text.secondary">
          Start a new session by selecting an image above
        </Typography>
      </Box>
    );
  }

  return (
    <TableContainer component={Paper}>
      <Table>
        <TableHead>
          <TableRow>
            <TableCell>Session ID</TableCell>
            <TableCell>Image</TableCell>
            <TableCell>Status</TableCell>
            <TableCell>Display</TableCell>
            <TableCell>Port</TableCell>
            <TableCell>Node</TableCell>
            <TableCell>Job ID</TableCell>
            <TableCell>Created</TableCell>
            <TableCell align="right">Actions</TableCell>
          </TableRow>
        </TableHead>
        <TableBody>
          {sessions.map((session) => (
            <TableRow key={session.session_id} hover>
              <TableCell>
                <Typography variant="body2" fontFamily="monospace">
                  {session.session_id.substring(0, 8)}...
                </Typography>
              </TableCell>

              <TableCell>{session.image_name}</TableCell>

              <TableCell>
                <Chip
                  icon={getStatusIcon(session.status)}
                  label={session.status.toUpperCase()}
                  size="small"
                  color={getStatusColor(session.status)}
                />
              </TableCell>

              <TableCell>
                <Typography variant="body2" fontFamily="monospace">
                  :{session.display_num}
                </Typography>
              </TableCell>

              <TableCell>
                <Typography variant="body2" fontFamily="monospace">
                  {session.sunshine_port}
                </Typography>
              </TableCell>

              <TableCell>
                <Typography variant="body2" fontFamily="monospace">
                  {session.slurm_node || '-'}
                </Typography>
              </TableCell>

              <TableCell>
                <Typography variant="body2" fontFamily="monospace">
                  {session.job_id || '-'}
                </Typography>
              </TableCell>

              <TableCell>
                <Typography variant="body2">
                  {new Date(session.created_at).toLocaleString()}
                </Typography>
              </TableCell>

              <TableCell align="right">
                <Box display="flex" gap={1} justifyContent="flex-end">
                  {session.status === 'running' && (
                    <Tooltip title="Connect">
                      <IconButton
                        size="small"
                        color="primary"
                        onClick={() => onConnectSession(session)}
                      >
                        <PlayArrow />
                      </IconButton>
                    </Tooltip>
                  )}

                  {(session.status === 'running' || session.status === 'pending') && (
                    <Tooltip title="Stop Session">
                      <IconButton
                        size="small"
                        color="error"
                        onClick={() => onStopSession(session.session_id)}
                        disabled={loading}
                      >
                        <Stop />
                      </IconButton>
                    </Tooltip>
                  )}

                  {session.status === 'failed' && session.error && (
                    <Tooltip title={session.error}>
                      <IconButton size="small" color="error">
                        <Error />
                      </IconButton>
                    </Tooltip>
                  )}
                </Box>
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </TableContainer>
  );
};
