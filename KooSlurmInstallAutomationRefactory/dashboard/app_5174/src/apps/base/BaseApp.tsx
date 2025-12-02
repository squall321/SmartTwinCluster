/**
 * BaseApp - Abstract Base Class for All Apps
 *
 * 모든 앱이 상속받아야 하는 추상 클래스
 * 생명주기 관리, 세션 관리, Display 관리를 제공
 */

import { Component } from 'react';
import type { ReactNode } from 'react';
import type { AppMetadata, AppConfig, AppSession, DisplayConfig } from '@core/types';

/**
 * BaseApp Props
 */
export interface BaseAppProps {
  /** 앱 메타데이터 */
  metadata: AppMetadata;

  /** 앱 설정 */
  config?: Partial<AppConfig>;

  /** 기존 세션 ID (재연결용) */
  sessionId?: string;

  /** 임베딩 모드 여부 */
  embedded?: boolean;

  /** 컨테이너 스타일 오버라이드 */
  containerStyle?: React.CSSProperties;

  /** 생명주기 이벤트 콜백 */
  onSessionCreated?: (session: AppSession) => void;
  onSessionReady?: (session: AppSession) => void;
  onSessionError?: (error: Error) => void;
  onSessionClosed?: () => void;
}

/**
 * BaseApp State
 */
export interface BaseAppState {
  /** 현재 세션 */
  session: AppSession | null;

  /** 로딩 상태 */
  loading: boolean;

  /** 에러 */
  error: Error | null;

  /** Display 연결 상태 */
  displayConnected: boolean;

  /** WebSocket 연결 상태 */
  websocketConnected: boolean;
}

/**
 * BaseApp Abstract Class
 */
export abstract class BaseApp<
  P extends BaseAppProps = BaseAppProps,
  S extends BaseAppState = BaseAppState
> extends Component<P, S> {

  /**
   * 앱별 기본 설정 (오버라이드 필수)
   */
  protected abstract getDefaultConfig(): AppConfig;

  /**
   * Display 설정 (오버라이드 가능)
   */
  protected getDisplayConfig(): DisplayConfig {
    return {
      type: 'novnc',
      width: 1920,
      height: 1080,
      quality: 6,
      compression: 2,
      viewOnly: false,
      showControls: true,
    };
  }

  /**
   * Toolbar 렌더링 (오버라이드 가능)
   */
  protected renderToolbar(): ReactNode {
    return null;
  }

  /**
   * 추가 컨트롤 패널 (오버라이드 가능)
   */
  protected renderControls(): ReactNode {
    return null;
  }

  /**
   * 상태 바 커스터마이징 (오버라이드 가능)
   */
  protected renderStatusBar(): ReactNode {
    return null;
  }

  /**
   * 생명주기: 세션 생성 완료
   */
  protected onSessionCreated(session: AppSession): void {
    this.props.onSessionCreated?.(session);
  }

  /**
   * 생명주기: Display 준비 완료
   */
  protected onSessionReady(session: AppSession): void {
    this.props.onSessionReady?.(session);
  }

  /**
   * 생명주기: 에러 발생
   */
  protected onSessionError(error: Error): void {
    this.props.onSessionError?.(error);
  }

  /**
   * 생명주기: 세션 종료
   */
  protected onSessionClosed(): void {
    this.props.onSessionClosed?.();
  }

  /**
   * 세션 생성 요청
   */
  protected async createSession(): Promise<void> {
    // AppContainer에서 구현 (useAppSession hook 사용)
    throw new Error('createSession must be implemented by AppContainer');
  }

  /**
   * 세션 종료
   */
  protected async destroySession(): Promise<void> {
    // AppContainer에서 구현
    throw new Error('destroySession must be implemented by AppContainer');
  }

  /**
   * 세션 재시작
   */
  protected async restartSession(): Promise<void> {
    // AppContainer에서 구현
    throw new Error('restartSession must be implemented by AppContainer');
  }

  /**
   * 렌더링 (하위 클래스에서 오버라이드 가능)
   * 기본적으로 AppContainer가 감싸서 렌더링
   */
  abstract render(): ReactNode;
}
