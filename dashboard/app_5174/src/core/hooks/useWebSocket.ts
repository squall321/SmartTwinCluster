/**
 * useWebSocket Hook
 *
 * WebSocket 연결 관리 (앱 통신용)
 */

import { useState, useCallback, useEffect, useRef } from 'react';

export interface UseWebSocketOptions {
  /** WebSocket URL */
  url?: string;

  /** 자동 연결 여부 */
  autoConnect?: boolean;

  /** 재연결 시도 횟수 */
  reconnectAttempts?: number;

  /** 재연결 간격 (ms) */
  reconnectInterval?: number;

  /** 이벤트 콜백 */
  onOpen?: () => void;
  onClose?: () => void;
  onError?: (error: Event) => void;
  onMessage?: (data: any) => void;
}

export interface UseWebSocketReturn {
  /** 연결 상태 */
  connected: boolean;

  /** 메시지 전송 */
  send: (data: any) => void;

  /** 연결 */
  connect: () => void;

  /** 연결 해제 */
  disconnect: () => void;

  /** 마지막 메시지 */
  lastMessage: any;
}

/**
 * useWebSocket Hook
 */
export function useWebSocket(
  options: UseWebSocketOptions
): UseWebSocketReturn {
  const {
    url,
    autoConnect = false,
    reconnectAttempts = 5,
    reconnectInterval = 3000,
    onOpen,
    onClose,
    onError,
    onMessage,
  } = options;

  const [connected, setConnected] = useState(false);
  const [lastMessage, setLastMessage] = useState<any>(null);

  const wsRef = useRef<WebSocket | null>(null);
  const reconnectCountRef = useRef(0);
  const reconnectTimeoutRef = useRef<number | null>(null);

  /**
   * 연결
   */
  const connect = useCallback(() => {
    if (!url) {
      console.warn('[useWebSocket] No URL provided');
      return;
    }

    if (wsRef.current?.readyState === WebSocket.OPEN) {
      console.warn('[useWebSocket] Already connected');
      return;
    }

    console.log('[useWebSocket] Connecting to:', url);

    try {
      const ws = new WebSocket(url);

      ws.onopen = () => {
        console.log('[useWebSocket] Connected');
        setConnected(true);
        reconnectCountRef.current = 0;
        onOpen?.();
      };

      ws.onclose = () => {
        console.log('[useWebSocket] Disconnected');
        setConnected(false);
        wsRef.current = null;
        onClose?.();

        // 재연결 시도
        if (reconnectCountRef.current < reconnectAttempts) {
          reconnectCountRef.current++;
          console.log(
            `[useWebSocket] Reconnecting... (${reconnectCountRef.current}/${reconnectAttempts})`
          );

          reconnectTimeoutRef.current = setTimeout(() => {
            connect();
          }, reconnectInterval);
        }
      };

      ws.onerror = (error) => {
        console.error('[useWebSocket] Error:', error);
        onError?.(error);
      };

      ws.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data);
          setLastMessage(data);
          onMessage?.(data);
        } catch (error) {
          console.error('[useWebSocket] Failed to parse message:', error);
        }
      };

      wsRef.current = ws;
    } catch (error) {
      console.error('[useWebSocket] Connection failed:', error);
    }
  }, [url, reconnectAttempts, reconnectInterval, onOpen, onClose, onError, onMessage]);

  /**
   * 연결 해제
   */
  const disconnect = useCallback(() => {
    if (reconnectTimeoutRef.current) {
      clearTimeout(reconnectTimeoutRef.current);
      reconnectTimeoutRef.current = null;
    }

    if (wsRef.current) {
      wsRef.current.close();
      wsRef.current = null;
    }

    setConnected(false);
    reconnectCountRef.current = 0;
  }, []);

  /**
   * 메시지 전송
   */
  const send = useCallback((data: any) => {
    if (!wsRef.current || wsRef.current.readyState !== WebSocket.OPEN) {
      console.warn('[useWebSocket] Not connected, cannot send message');
      return;
    }

    try {
      const message = typeof data === 'string' ? data : JSON.stringify(data);
      wsRef.current.send(message);
    } catch (error) {
      console.error('[useWebSocket] Failed to send message:', error);
    }
  }, []);

  /**
   * 자동 연결
   */
  useEffect(() => {
    if (autoConnect && url) {
      connect();
    }

    return () => {
      disconnect();
    };
  }, [autoConnect, url]);

  return {
    connected,
    send,
    connect,
    disconnect,
    lastMessage,
  };
}
