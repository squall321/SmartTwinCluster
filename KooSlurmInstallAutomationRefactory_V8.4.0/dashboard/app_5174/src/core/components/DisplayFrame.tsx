/**
 * DisplayFrame Component
 *
 * noVNC/Broadway Display를 렌더링하는 컴포넌트
 */

import { useEffect } from 'react';
import { useDisplay, UseDisplayOptions } from '@core/hooks';
import type { DisplayConfig, DisplayStats } from '@core/types';

export interface DisplayFrameProps {
  /** Display URL */
  displayUrl?: string;

  /** Display 설정 */
  config: DisplayConfig;

  /** 자동 연결 여부 */
  autoConnect?: boolean;

  /** 전체화면 버튼 표시 */
  showFullscreenButton?: boolean;

  /** 컨테이너 스타일 */
  style?: React.CSSProperties;

  /** 외부 containerRef (optional, useAppLifecycle 사용 시) */
  containerRef?: React.RefObject<HTMLDivElement>;

  /** 연결 콜백 */
  onConnected?: () => void;
  onDisconnected?: () => void;
  onError?: (error: Error) => void;

  /** 통계 업데이트 콜백 */
  onStatsUpdate?: (stats: DisplayStats) => void;
}

/**
 * DisplayFrame Component
 */
export function DisplayFrame(props: DisplayFrameProps) {
  const {
    displayUrl,
    config,
    autoConnect = true,
    showFullscreenButton = true,
    style,
    containerRef: externalContainerRef,
    onConnected,
    onDisconnected,
    onError,
    onStatsUpdate,
  } = props;

  const display = useDisplay({
    displayUrl,
    config,
    autoConnect,
    onConnected,
    onDisconnected,
    onError,
  });

  // 외부에서 containerRef를 전달받은 경우 사용, 아니면 내부 것 사용
  const containerRefToUse = externalContainerRef || display.containerRef;

  /**
   * 통계 업데이트 전달
   */
  useEffect(() => {
    if (display.stats) {
      onStatsUpdate?.(display.stats);
    }
  }, [display.stats, onStatsUpdate]);

  return (
    <div
      style={{
        position: 'relative',
        width: '100%',
        height: '100%',
        background: '#000',
        ...style,
      }}
    >
      {/* Display 컨테이너 - noVNC iframe */}
      <div
        ref={containerRefToUse}
        style={{
          width: '100%',
          height: '100%',
          overflow: 'hidden',
        }}
      >
        {/* noVNC iframe */}
        <iframe
          ref={display.iframeRef}
          src="about:blank"
          style={{
            width: '100%',
            height: '100%',
            border: 'none',
          }}
          title="noVNC Display"
        />
      </div>

      {/* 연결 상태 오버레이 */}
      {display.status !== 'connected' && (
        <div
          style={{
            position: 'absolute',
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            background: 'rgba(0, 0, 0, 0.8)',
            color: 'white',
            fontSize: '1.25rem',
          }}
        >
          {display.status === 'connecting' && (
            <div>
              <div>🔄 Connecting to display...</div>
              {displayUrl && (
                <div style={{ fontSize: '0.875rem', marginTop: '0.5rem', opacity: 0.7 }}>
                  {displayUrl}
                </div>
              )}
            </div>
          )}

          {display.status === 'disconnected' && (
            <div>
              <div>⚪ Disconnected</div>
              {!displayUrl && (
                <div style={{ fontSize: '0.875rem', marginTop: '0.5rem', opacity: 0.7 }}>
                  Waiting for session...
                </div>
              )}
            </div>
          )}

          {display.status === 'error' && (
            <div>
              <div>❌ Connection Error</div>
              <button
                onClick={display.connect}
                style={{
                  marginTop: '1rem',
                  padding: '0.5rem 1rem',
                  background: '#646cff',
                  color: 'white',
                  border: 'none',
                  borderRadius: '4px',
                  cursor: 'pointer',
                }}
              >
                Retry
              </button>
            </div>
          )}
        </div>
      )}

      {/* 전체화면 버튼 */}
      {showFullscreenButton && display.status === 'connected' && (
        <button
          onClick={display.toggleFullscreen}
          style={{
            position: 'absolute',
            top: '1rem',
            right: '1rem',
            padding: '0.5rem 1rem',
            background: 'rgba(0, 0, 0, 0.6)',
            color: 'white',
            border: '1px solid rgba(255, 255, 255, 0.3)',
            borderRadius: '4px',
            cursor: 'pointer',
            fontSize: '0.875rem',
            backdropFilter: 'blur(4px)',
          }}
          title="Toggle Fullscreen"
        >
          ⛶
        </button>
      )}

      {/* 통계 오버레이 (개발 모드) */}
      {import.meta.env.DEV && display.stats && (
        <div
          style={{
            position: 'absolute',
            bottom: '1rem',
            left: '1rem',
            padding: '0.5rem 1rem',
            background: 'rgba(0, 0, 0, 0.6)',
            color: 'white',
            border: '1px solid rgba(255, 255, 255, 0.3)',
            borderRadius: '4px',
            fontSize: '0.75rem',
            fontFamily: 'monospace',
            backdropFilter: 'blur(4px)',
          }}
        >
          <div>Latency: {display.stats.latency}ms</div>
          <div>FPS: {display.stats.fps}</div>
          <div>
            Bandwidth: {(display.stats.bandwidth / 1024 / 1024).toFixed(2)} MB/s
          </div>
        </div>
      )}
    </div>
  );
}
