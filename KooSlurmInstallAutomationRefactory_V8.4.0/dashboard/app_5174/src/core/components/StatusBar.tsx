/**
 * StatusBar Component
 *
 * 앱 하단 상태바 (세션 정보, 연결 상태 등)
 */

import type { AppSession, DisplayStatus, DisplayStats } from '@core/types';

export interface StatusBarProps {
  /** 세션 정보 */
  session: AppSession | null;

  /** Display 연결 상태 */
  displayStatus: DisplayStatus;

  /** Display 통계 */
  displayStats: DisplayStats | null;

  /** WebSocket 연결 상태 */
  websocketConnected: boolean;

  /** 추가 정보 렌더링 */
  children?: React.ReactNode;

  /** 스타일 */
  style?: React.CSSProperties;
}

/**
 * StatusBar Component
 */
export function StatusBar(props: StatusBarProps) {
  const {
    session,
    displayStatus,
    displayStats,
    websocketConnected,
    children,
    style,
  } = props;

  const getSessionStatusColor = () => {
    if (!session) return '#666';
    switch (session.status) {
      case 'running':
        return '#4caf50';
      case 'creating':
      case 'starting':
        return '#ff9800';
      case 'error':
        return '#f44336';
      default:
        return '#666';
    }
  };

  const getDisplayStatusIcon = () => {
    switch (displayStatus) {
      case 'connected':
        return '🟢';
      case 'connecting':
        return '🟡';
      case 'error':
        return '🔴';
      default:
        return '⚪';
    }
  };

  return (
    <div
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: '1.5rem',
        padding: '0.5rem 1rem',
        background: '#2a2a2a',
        color: '#e0e0e0',
        fontSize: '0.875rem',
        borderTop: '1px solid #444',
        ...style,
      }}
    >
      {/* 세션 상태 */}
      <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
        <div
          style={{
            width: '8px',
            height: '8px',
            borderRadius: '50%',
            background: getSessionStatusColor(),
          }}
        />
        <span>
          Session: {session ? session.status : 'none'}
        </span>
        {session && (
          <span style={{ opacity: 0.7, fontSize: '0.75rem' }}>
            ({session.sessionId.slice(0, 8)})
          </span>
        )}
      </div>

      {/* Display 상태 */}
      <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
        <span>{getDisplayStatusIcon()}</span>
        <span>Display: {displayStatus}</span>
      </div>

      {/* WebSocket 상태 */}
      <div style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
        <span>{websocketConnected ? '🟢' : '⚪'}</span>
        <span>WS: {websocketConnected ? 'connected' : 'disconnected'}</span>
      </div>

      {/* Display 통계 */}
      {displayStats && (
        <>
          <div style={{ opacity: 0.7 }}>
            Latency: {displayStats.latency}ms
          </div>
          <div style={{ opacity: 0.7 }}>
            FPS: {displayStats.fps}
          </div>
        </>
      )}

      {/* 사용자 정의 컨텐츠 */}
      {children && (
        <div style={{ marginLeft: 'auto' }}>
          {children}
        </div>
      )}
    </div>
  );
}
