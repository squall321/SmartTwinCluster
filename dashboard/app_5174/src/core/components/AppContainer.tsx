/**
 * AppContainer Component
 *
 * 모든 앱을 감싸는 최상위 컨테이너
 * Toolbar, DisplayFrame, ControlPanel, StatusBar를 조합
 */

import { useState } from 'react';
import { useAppLifecycle } from '@core/hooks';
import { Toolbar } from './Toolbar';
import { DisplayFrame } from './DisplayFrame';
import { ControlPanel } from './ControlPanel';
import { StatusBar } from './StatusBar';
import type { AppMetadata, AppConfig, DisplayConfig } from '@core/types';

export interface AppContainerProps {
  /** 앱 메타데이터 */
  metadata: AppMetadata;

  /** 앱 설정 */
  config: AppConfig;

  /** Display 설정 */
  displayConfig: DisplayConfig;

  /** 기존 세션 ID (재연결용) */
  sessionId?: string;

  /** 자동 시작 여부 */
  autoStart?: boolean;

  /** 컨트롤 패널 표시 */
  showControls?: boolean;

  /** 툴바 표시 */
  showToolbar?: boolean;

  /** 상태바 표시 */
  showStatusBar?: boolean;

  /** 툴바 추가 버튼 */
  toolbarChildren?: React.ReactNode;

  /** 컨트롤 패널 추가 컨트롤 */
  controlChildren?: React.ReactNode;

  /** 상태바 추가 정보 */
  statusChildren?: React.ReactNode;

  /** 컨테이너 스타일 */
  style?: React.CSSProperties;

  /** 생명주기 콜백 */
  onReady?: () => void;
  onError?: (error: Error) => void;
  onClosed?: () => void;
}

/**
 * AppContainer Component
 */
export function AppContainer(props: AppContainerProps) {
  const {
    metadata,
    config,
    displayConfig,
    sessionId,
    autoStart = false,
    showControls = true,
    showToolbar = true,
    showStatusBar = true,
    toolbarChildren,
    controlChildren,
    statusChildren,
    style,
    onReady,
    onError,
    onClosed,
  } = props;

  const [displayStats, setDisplayStats] = useState<any>(null);

  // 앱 생명주기 관리
  const lifecycle = useAppLifecycle({
    appId: metadata.id,
    config,
    displayConfig,
    sessionId,
    autoStart,
    onReady,
    onError,
    onClosed,
  });

  return (
    <div
      style={{
        display: 'flex',
        flexDirection: 'column',
        width: '100%',
        height: '100%',
        background: '#1e1e1e',
        overflow: 'hidden',
        ...style,
      }}
    >
      {/* Toolbar */}
      {showToolbar && (
        <Toolbar
          metadata={metadata}
          session={lifecycle.session.session}
          loading={lifecycle.session.loading}
          onStart={lifecycle.start}
          onStop={lifecycle.stop}
          onRestart={lifecycle.session.restartSession}
        >
          {toolbarChildren}
        </Toolbar>
      )}

      {/* Control Panel */}
      {showControls && (
        <ControlPanel
          config={displayConfig}
          onQualityChange={lifecycle.display.setQuality}
          onCompressionChange={lifecycle.display.setCompression}
        >
          {controlChildren}
        </ControlPanel>
      )}

      {/* Display Frame */}
      <div style={{ flex: 1, position: 'relative', overflow: 'hidden' }}>
        <DisplayFrame
          displayUrl={lifecycle.session.session?.displayUrl}
          config={displayConfig}
          autoConnect={false} // lifecycle에서 제어
          containerRef={lifecycle.display.containerRef}
          onStatsUpdate={setDisplayStats}
        />
      </div>

      {/* Status Bar */}
      {showStatusBar && (
        <StatusBar
          session={lifecycle.session.session}
          displayStatus={lifecycle.display.status}
          displayStats={displayStats}
          websocketConnected={lifecycle.websocket.connected}
        >
          {statusChildren}
        </StatusBar>
      )}

      {/* 에러 오버레이 */}
      {lifecycle.session.error && (
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
            background: 'rgba(0, 0, 0, 0.9)',
            color: 'white',
            zIndex: 1000,
          }}
        >
          <div style={{ textAlign: 'center', padding: '2rem' }}>
            <div style={{ fontSize: '3rem', marginBottom: '1rem' }}>❌</div>
            <div style={{ fontSize: '1.5rem', marginBottom: '1rem' }}>
              Error
            </div>
            <div
              style={{
                fontSize: '1rem',
                opacity: 0.8,
                marginBottom: '2rem',
                maxWidth: '500px',
              }}
            >
              {lifecycle.session.error.message}
            </div>
            <button
              onClick={() => window.location.reload()}
              style={{
                padding: '0.75rem 1.5rem',
                background: '#646cff',
                color: 'white',
                border: 'none',
                borderRadius: '4px',
                cursor: 'pointer',
                fontSize: '1rem',
              }}
            >
              Reload
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
