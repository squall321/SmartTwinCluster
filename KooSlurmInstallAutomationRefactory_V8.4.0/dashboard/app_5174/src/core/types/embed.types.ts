/**
 * Embedding Types
 * - iframe, Web Component 임베딩 관련 타입
 */

/**
 * Embedding 모드
 */
export type EmbedMode = 'iframe' | 'webcomponent' | 'react';

/**
 * Embedding 설정
 */
export interface EmbedConfig {
  mode: EmbedMode;
  width?: string | number;
  height?: string | number;
  autoStart?: boolean;
  showToolbar?: boolean;
  showStatusBar?: boolean;
}

/**
 * PostMessage 통신 (iframe용)
 */
export interface EmbedMessage {
  type: EmbedMessageType;
  payload?: any;
}

export type EmbedMessageType =
  | 'ready'
  | 'start'
  | 'stop'
  | 'status'
  | 'error'
  | 'resize';

/**
 * Web Component 속성
 */
export interface AppFrameworkElement extends HTMLElement {
  appId?: string;
  config?: string; // JSON string
  onStatusChange?: (status: string) => void;
  onError?: (error: any) => void;
}
