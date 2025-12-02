/**
 * GEdit Example App
 *
 * BaseApp을 상속받는 실제 앱 예제
 */

import { Component } from 'react';
import type { ReactNode } from 'react';
import { BaseApp, BaseAppProps, BaseAppState } from '@apps/base';
import { AppContainer } from '@core/components';
import type { AppConfig, DisplayConfig, AppMetadata } from '@core/types';
import type { AppSession } from '@core/types/app.types';

/**
 * GEdit App Component
 */
export class GEditApp extends BaseApp {
  /**
   * 기본 설정 제공
   */
  protected getDefaultConfig(): AppConfig {
    return {
      resources: {
        cpus: 2,
        memory: '4Gi',
        gpu: false,
      },
      display: {
        type: 'novnc',
        width: 1280,
        height: 720,
      },
      container: {
        image: 'gedit-vnc',
        command: '/start-gedit.sh',
      },
    };
  }

  /**
   * Display 설정
   */
  protected getDisplayConfig(): DisplayConfig {
    return {
      type: 'novnc',
      width: 1280,
      height: 720,
      quality: 6,
      compression: 2,
      viewOnly: false,
      showControls: true,
    };
  }

  /**
   * 앱 메타데이터
   */
  private getMetadata(): AppMetadata {
    return {
      id: 'gedit',
      name: 'GEdit Text Editor',
      version: '1.0.0',
      description: 'Simple GNOME text editor for Linux',
      category: 'editor',
      tags: ['text', 'editor', 'document'],
    };
  }

  /**
   * 커스텀 툴바 버튼
   */
  protected renderToolbar(): ReactNode {
    return (
      <>
        <button
          onClick={() => this.handleNewDocument()}
          style={{
            padding: '0.5rem 1rem',
            background: '#4caf50',
            color: 'white',
            border: 'none',
            borderRadius: '4px',
            cursor: 'pointer',
            fontSize: '0.875rem',
            fontWeight: 500,
          }}
        >
          📄 New
        </button>

        <button
          onClick={() => this.handleSaveDocument()}
          style={{
            padding: '0.5rem 1rem',
            background: '#2196f3',
            color: 'white',
            border: 'none',
            borderRadius: '4px',
            cursor: 'pointer',
            fontSize: '0.875rem',
            fontWeight: 500,
          }}
        >
          💾 Save
        </button>
      </>
    );
  }

  /**
   * 새 문서 생성
   */
  private handleNewDocument() {
    console.log('[GEditApp] Creating new document...');
    // TODO: WebSocket으로 명령 전송
    // this.sendCommand('new-document');
  }

  /**
   * 문서 저장
   */
  private handleSaveDocument() {
    console.log('[GEditApp] Saving document...');
    // TODO: WebSocket으로 명령 전송
    // this.sendCommand('save-document');
  }

  /**
   * 상태바 커스터마이징
   */
  protected renderStatusBar(): ReactNode {
    return (
      <div style={{ fontSize: '0.875rem', color: '#999' }}>
        GEdit v1.0.0 | Ready
      </div>
    );
  }

  /**
   * 컴포넌트 렌더링
   */
  render(): ReactNode {
    const metadata = this.getMetadata();
    const config = this.getDefaultConfig();
    const displayConfig = this.getDisplayConfig();

    return (
      <AppContainer
        metadata={metadata}
        config={config}
        displayConfig={displayConfig}
        sessionId={this.props.sessionId}
        autoStart={false}
        showControls={true}
        showToolbar={true}
        showStatusBar={true}
        toolbarChildren={this.renderToolbar()}
        statusChildren={this.renderStatusBar()}
        onReady={() => this.props.onSessionReady?.({} as any as AppSession)}
        onError={(error) => this.props.onSessionError?.(error)}
        onClosed={() => this.props.onSessionClosed?.() || undefined}
      />
    );
  }
}

export default GEditApp;
