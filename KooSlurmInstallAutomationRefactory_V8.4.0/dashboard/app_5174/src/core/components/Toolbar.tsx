/**
 * Toolbar Component
 *
 * 앱 상단 툴바 (컨트롤 버튼, 앱 정보 등)
 */

import type { AppMetadata, AppSession } from '@core/types';

export interface ToolbarProps {
  /** 앱 메타데이터 */
  metadata: AppMetadata;

  /** 세션 정보 */
  session: AppSession | null;

  /** 로딩 상태 */
  loading?: boolean;

  /** 앱 시작 */
  onStart?: () => void;

  /** 앱 종료 */
  onStop?: () => void;

  /** 앱 재시작 */
  onRestart?: () => void;

  /** 추가 버튼 */
  children?: React.ReactNode;

  /** 스타일 */
  style?: React.CSSProperties;
}

/**
 * Toolbar Component
 */
export function Toolbar(props: ToolbarProps) {
  const {
    metadata,
    session,
    loading = false,
    onStart,
    onStop,
    onRestart,
    children,
    style,
  } = props;

  const isRunning = session?.status === 'running';
  const canStart = !session && !loading;
  const canStop = session && !loading;
  const canRestart = isRunning && !loading;

  return (
    <div
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: '1rem',
        padding: '0.75rem 1rem',
        background: '#1e1e1e',
        color: '#e0e0e0',
        borderBottom: '1px solid #444',
        ...style,
      }}
    >
      {/* 앱 정보 */}
      <div style={{ display: 'flex', alignItems: 'center', gap: '0.75rem' }}>
        {metadata.icon && (
          <img
            src={metadata.icon}
            alt={metadata.name}
            style={{
              width: '24px',
              height: '24px',
              objectFit: 'contain',
            }}
          />
        )}
        <div>
          <div style={{ fontWeight: 600 }}>{metadata.name}</div>
          {metadata.version && (
            <div style={{ fontSize: '0.75rem', opacity: 0.7 }}>
              v{metadata.version}
            </div>
          )}
        </div>
      </div>

      {/* 구분선 */}
      <div
        style={{
          width: '1px',
          height: '32px',
          background: '#444',
        }}
      />

      {/* 컨트롤 버튼 */}
      <div style={{ display: 'flex', gap: '0.5rem' }}>
        {/* 시작 버튼 */}
        {canStart && onStart && (
          <button
            onClick={onStart}
            disabled={loading}
            style={{
              padding: '0.5rem 1rem',
              background: '#4caf50',
              color: 'white',
              border: 'none',
              borderRadius: '4px',
              cursor: loading ? 'wait' : 'pointer',
              fontSize: '0.875rem',
              fontWeight: 500,
            }}
          >
            ▶ Start
          </button>
        )}

        {/* 재시작 버튼 */}
        {canRestart && onRestart && (
          <button
            onClick={onRestart}
            disabled={loading}
            style={{
              padding: '0.5rem 1rem',
              background: '#ff9800',
              color: 'white',
              border: 'none',
              borderRadius: '4px',
              cursor: loading ? 'wait' : 'pointer',
              fontSize: '0.875rem',
              fontWeight: 500,
            }}
          >
            🔄 Restart
          </button>
        )}

        {/* 종료 버튼 */}
        {canStop && onStop && (
          <button
            onClick={onStop}
            disabled={loading}
            style={{
              padding: '0.5rem 1rem',
              background: '#f44336',
              color: 'white',
              border: 'none',
              borderRadius: '4px',
              cursor: loading ? 'wait' : 'pointer',
              fontSize: '0.875rem',
              fontWeight: 500,
            }}
          >
            ⏹ Stop
          </button>
        )}

        {/* 로딩 표시 */}
        {loading && (
          <div
            style={{
              display: 'flex',
              alignItems: 'center',
              padding: '0.5rem 1rem',
              color: '#ff9800',
              fontSize: '0.875rem',
            }}
          >
            ⏳ Processing...
          </div>
        )}
      </div>

      {/* 사용자 정의 버튼 */}
      {children && (
        <>
          <div
            style={{
              width: '1px',
              height: '32px',
              background: '#444',
            }}
          />
          <div style={{ display: 'flex', gap: '0.5rem' }}>
            {children}
          </div>
        </>
      )}
    </div>
  );
}
