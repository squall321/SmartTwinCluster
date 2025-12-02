/**
 * Display Types
 * - Display 연결 및 렌더링 관련 타입
 */

/**
 * Display 타입
 */
export type DisplayType = 'novnc' | 'broadway' | 'webrtc' | 'x11';

/**
 * Display 설정
 */
export interface DisplayConfig {
  type: DisplayType;
  url?: string;
  width?: number;
  height?: number;
  quality?: number;
  compression?: number;
  scaling?: boolean;
  viewOnly?: boolean;
  showControls?: boolean;
}

/**
 * Display 상태
 */
export type DisplayStatus =
  | 'disconnected'
  | 'connecting'
  | 'connected'
  | 'error';

/**
 * Display 연결 정보
 */
export interface DisplayConnection {
  config: DisplayConfig;
  status: DisplayStatus;
  error?: string;
  latency?: number;
  fps?: number;
}

/**
 * Display 이벤트
 */
export interface DisplayEvent {
  type: 'connect' | 'disconnect' | 'error' | 'stats';
  timestamp: string;
  data?: any;
}

/**
 * Display 통계
 */
export interface DisplayStats {
  latency: number;
  fps: number;
  bandwidth: number;
  dropped_frames: number;
}
