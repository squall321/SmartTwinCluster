/**
 * App Framework Core Types
 * - 앱 메타데이터, 설정, 세션 관련 타입 정의
 */

/**
 * 앱 메타데이터
 */
export interface AppMetadata {
  id: string;
  name: string;
  description: string;
  version: string;
  author?: string;
  icon?: string;
  category?: string;
  tags?: string[];
}

/**
 * 앱 설정
 */
export interface AppConfig {
  // 리소스 설정
  resources?: {
    cpus?: number;
    cpu?: number;
    memory?: string;
    gpu?: boolean | number;
  };

  // Display 설정
  display?: {
    type: 'novnc' | 'broadway' | 'webrtc';
    width?: number;
    height?: number;
    quality?: number;
  };

  // Apptainer 설정
  container?: {
    image: string;
    command?: string;
    sandbox?: boolean;
    writable?: boolean;
    bind?: string[];
  };

  // 앱별 커스텀 설정
  custom?: Record<string, any>;
}

/**
 * 세션 정보
 */
export interface AppSession {
  sessionId: string;
  appId: string;
  userId: string;
  status: SessionStatus;
  displayUrl?: string;
  websocketUrl?: string;
  config: AppConfig;
  createdAt: string;
  updatedAt: string;
  expiresAt?: string;
}

/**
 * 세션 상태
 */
export type SessionStatus =
  | 'creating'
  | 'starting'
  | 'running'
  | 'stopping'
  | 'stopped'
  | 'error';

/**
 * 세션 생성 요청
 */
export interface CreateSessionRequest {
  appId: string;
  config?: Partial<AppConfig>;
}

/**
 * 세션 생성 응답
 */
export interface CreateSessionResponse {
  session: AppSession;
}

/**
 * 세션 목록 응답
 */
export interface ListSessionsResponse {
  sessions: AppSession[];
  total: number;
}

/**
 * 앱 등록 정보
 */
export interface AppRegistration {
  metadata: AppMetadata;
  defaultConfig?: AppConfig;
  component: () => Promise<{ default: React.ComponentType<any> } | React.ComponentType<any>>;
  configComponent?: React.ComponentType<AppConfigProps>;
}

/**
 * 앱 컴포넌트 Props
 */
export interface AppComponentProps {
  session: AppSession;
  onStatusChange?: (status: SessionStatus) => void;
  onError?: (error: AppError) => void;
}

/**
 * 앱 설정 컴포넌트 Props
 */
export interface AppConfigProps {
  config: AppConfig;
  onChange: (config: AppConfig) => void;
}

/**
 * 앱 에러
 */
export interface AppError {
  code: string;
  message: string;
  details?: any;
}
