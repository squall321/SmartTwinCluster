/**
 * ControlPanel Component
 *
 * Display 품질, 압축 등 컨트롤 패널
 */

import { useState } from 'react';
import type { DisplayConfig } from '@core/types';

export interface ControlPanelProps {
  /** Display 설정 */
  config: DisplayConfig;

  /** 품질 변경 */
  onQualityChange?: (quality: number) => void;

  /** 압축 변경 */
  onCompressionChange?: (compression: number) => void;

  /** View Only 토글 */
  onViewOnlyToggle?: (viewOnly: boolean) => void;

  /** 추가 컨트롤 */
  children?: React.ReactNode;

  /** 펼침 상태 */
  defaultExpanded?: boolean;

  /** 스타일 */
  style?: React.CSSProperties;
}

/**
 * ControlPanel Component
 */
export function ControlPanel(props: ControlPanelProps) {
  const {
    config,
    onQualityChange,
    onCompressionChange,
    onViewOnlyToggle,
    children,
    defaultExpanded = false,
    style,
  } = props;

  const [expanded, setExpanded] = useState(defaultExpanded);
  const [quality, setQuality] = useState(config.quality || 6);
  const [compression, setCompression] = useState(config.compression || 2);
  const [viewOnly, setViewOnly] = useState(config.viewOnly || false);

  const handleQualityChange = (value: number) => {
    setQuality(value);
    onQualityChange?.(value);
  };

  const handleCompressionChange = (value: number) => {
    setCompression(value);
    onCompressionChange?.(value);
  };

  const handleViewOnlyToggle = () => {
    const newValue = !viewOnly;
    setViewOnly(newValue);
    onViewOnlyToggle?.(newValue);
  };

  return (
    <div
      style={{
        background: '#2a2a2a',
        borderBottom: '1px solid #444',
        ...style,
      }}
    >
      {/* 헤더 */}
      <button
        onClick={() => setExpanded(!expanded)}
        style={{
          width: '100%',
          padding: '0.75rem 1rem',
          background: 'transparent',
          color: '#e0e0e0',
          border: 'none',
          textAlign: 'left',
          cursor: 'pointer',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          fontSize: '0.875rem',
          fontWeight: 500,
        }}
      >
        <span>Display Controls</span>
        <span>{expanded ? '▼' : '▶'}</span>
      </button>

      {/* 컨트롤 내용 */}
      {expanded && (
        <div
          style={{
            padding: '1rem',
            display: 'flex',
            flexDirection: 'column',
            gap: '1rem',
            borderTop: '1px solid #444',
          }}
        >
          {/* 품질 조절 */}
          <div>
            <label
              style={{
                display: 'block',
                marginBottom: '0.5rem',
                color: '#e0e0e0',
                fontSize: '0.875rem',
              }}
            >
              Quality: {quality}
            </label>
            <input
              type="range"
              min="0"
              max="9"
              value={quality}
              onChange={(e) => handleQualityChange(parseInt(e.target.value))}
              style={{
                width: '100%',
              }}
            />
            <div
              style={{
                display: 'flex',
                justifyContent: 'space-between',
                fontSize: '0.75rem',
                color: '#999',
                marginTop: '0.25rem',
              }}
            >
              <span>Low (Fast)</span>
              <span>High (Slow)</span>
            </div>
          </div>

          {/* 압축 조절 */}
          <div>
            <label
              style={{
                display: 'block',
                marginBottom: '0.5rem',
                color: '#e0e0e0',
                fontSize: '0.875rem',
              }}
            >
              Compression: {compression}
            </label>
            <input
              type="range"
              min="0"
              max="9"
              value={compression}
              onChange={(e) => handleCompressionChange(parseInt(e.target.value))}
              style={{
                width: '100%',
              }}
            />
            <div
              style={{
                display: 'flex',
                justifyContent: 'space-between',
                fontSize: '0.75rem',
                color: '#999',
                marginTop: '0.25rem',
              }}
            >
              <span>None</span>
              <span>Maximum</span>
            </div>
          </div>

          {/* View Only */}
          <div
            style={{
              display: 'flex',
              alignItems: 'center',
              gap: '0.5rem',
            }}
          >
            <input
              type="checkbox"
              id="viewOnly"
              checked={viewOnly}
              onChange={handleViewOnlyToggle}
            />
            <label
              htmlFor="viewOnly"
              style={{
                color: '#e0e0e0',
                fontSize: '0.875rem',
                cursor: 'pointer',
              }}
            >
              View Only (Read-only mode)
            </label>
          </div>

          {/* 사용자 정의 컨트롤 */}
          {children}
        </div>
      )}
    </div>
  );
}
