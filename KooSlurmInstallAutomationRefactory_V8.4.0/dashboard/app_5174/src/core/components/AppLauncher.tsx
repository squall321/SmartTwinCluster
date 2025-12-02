/**
 * AppLauncher Component
 *
 * 등록된 앱 목록을 표시하고 선택할 수 있는 런처
 */

import { useState, useEffect } from 'react';
import { appRegistry } from '@core/services/app.registry';
import type { AppMetadata } from '@core/types';

export interface AppLauncherProps {
  /** 앱 실행 콜백 */
  onLaunch?: (appId: string) => void;

  /** 뒤로가기 콜백 */
  onBack?: () => void;

  /** 스타일 */
  style?: React.CSSProperties;
}

/**
 * AppCard Component
 */
function AppCard({ app, onLaunch }: { app: AppMetadata; onLaunch: () => void }) {
  return (
    <div
      onClick={onLaunch}
      style={{
        padding: '1.5rem',
        background: '#2a2a2a',
        borderRadius: '8px',
        cursor: 'pointer',
        transition: 'all 0.2s',
        border: '2px solid #444',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        gap: '0.75rem',
        minWidth: '180px',
      }}
      onMouseEnter={(e) => {
        e.currentTarget.style.background = '#333';
        e.currentTarget.style.borderColor = '#646cff';
        e.currentTarget.style.transform = 'translateY(-2px)';
      }}
      onMouseLeave={(e) => {
        e.currentTarget.style.background = '#2a2a2a';
        e.currentTarget.style.borderColor = '#444';
        e.currentTarget.style.transform = 'translateY(0)';
      }}
    >
      {/* 앱 아이콘 */}
      <div
        style={{
          width: '64px',
          height: '64px',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          fontSize: '3rem',
          background: '#1e1e1e',
          borderRadius: '12px',
        }}
      >
        {app.icon ? (
          <img src={app.icon} alt={app.name} style={{ width: '100%', height: '100%' }} />
        ) : (
          getCategoryIcon(app.category)
        )}
      </div>

      {/* 앱 이름 */}
      <div
        style={{
          fontSize: '1rem',
          fontWeight: 600,
          color: '#e0e0e0',
          textAlign: 'center',
        }}
      >
        {app.name}
      </div>

      {/* 앱 설명 */}
      <div
        style={{
          fontSize: '0.75rem',
          color: '#999',
          textAlign: 'center',
          lineHeight: '1.4',
        }}
      >
        {app.description}
      </div>

      {/* 버전 */}
      {app.version && (
        <div
          style={{
            fontSize: '0.7rem',
            color: '#666',
            background: '#1e1e1e',
            padding: '0.25rem 0.5rem',
            borderRadius: '4px',
          }}
        >
          v{app.version}
        </div>
      )}
    </div>
  );
}

/**
 * 카테고리별 아이콘
 */
function getCategoryIcon(category?: string): string {
  switch (category) {
    case 'editor':
      return '📝';
    case 'graphics':
      return '🎨';
    case 'tools':
      return '🔧';
    case 'terminal':
      return '💻';
    case 'browser':
      return '🌐';
    default:
      return '📦';
  }
}

/**
 * AppLauncher Component
 */
export function AppLauncher(props: AppLauncherProps) {
  const { onLaunch, onBack, style } = props;

  const [apps, setApps] = useState<AppMetadata[]>([]);
  const [search, setSearch] = useState('');
  const [category, setCategory] = useState('all');

  /**
   * 앱 목록 로드
   */
  useEffect(() => {
    const allApps = appRegistry.listMetadata();
    setApps(allApps);
  }, []);

  /**
   * 필터링된 앱 목록
   */
  const filteredApps = apps.filter((app) => {
    const matchSearch =
      search === '' ||
      app.name.toLowerCase().includes(search.toLowerCase()) ||
      app.description?.toLowerCase().includes(search.toLowerCase());

    const matchCategory = category === 'all' || app.category === category;

    return matchSearch && matchCategory;
  });

  /**
   * 카테고리 목록
   */
  const categories = ['all', ...new Set(apps.map((app) => app.category).filter(Boolean))];

  /**
   * 앱 실행
   */
  const handleLaunch = (appId: string) => {
    console.log('[AppLauncher] Launching app:', appId);
    onLaunch?.(appId);
  };

  return (
    <div
      style={{
        width: '100%',
        height: '100%',
        background: '#1e1e1e',
        color: '#e0e0e0',
        display: 'flex',
        flexDirection: 'column',
        overflow: 'hidden',
        ...style,
      }}
    >
      {/* 헤더 */}
      <div
        style={{
          padding: '1rem 1.5rem',
          background: '#2a2a2a',
          borderBottom: '1px solid #444',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
        }}
      >
        <h1 style={{ margin: 0, fontSize: '1.5rem', fontWeight: 600 }}>App Launcher</h1>

        {onBack && (
          <button
            onClick={onBack}
            style={{
              padding: '0.5rem 1rem',
              background: '#646cff',
              color: 'white',
              border: 'none',
              borderRadius: '4px',
              cursor: 'pointer',
              fontSize: '0.875rem',
              fontWeight: 500,
            }}
          >
            ← Back to Home
          </button>
        )}
      </div>

      {/* 검색 및 필터 */}
      <div
        style={{
          padding: '1.5rem',
          background: '#252525',
          borderBottom: '1px solid #444',
        }}
      >
        {/* 검색 바 */}
        <input
          type="text"
          placeholder="🔍 Search apps..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          style={{
            width: '100%',
            padding: '0.75rem 1rem',
            background: '#1e1e1e',
            color: '#e0e0e0',
            border: '2px solid #444',
            borderRadius: '8px',
            fontSize: '1rem',
            outline: 'none',
            marginBottom: '1rem',
          }}
          onFocus={(e) => {
            e.currentTarget.style.borderColor = '#646cff';
          }}
          onBlur={(e) => {
            e.currentTarget.style.borderColor = '#444';
          }}
        />

        {/* 카테고리 필터 */}
        <div style={{ display: 'flex', gap: '0.5rem', flexWrap: 'wrap' }}>
          {categories.map((cat) => (
            <button
              key={cat}
              onClick={() => setCategory(cat || '')}
              style={{
                padding: '0.5rem 1rem',
                background: category === cat ? '#646cff' : '#2a2a2a',
                color: 'white',
                border: 'none',
                borderRadius: '4px',
                cursor: 'pointer',
                fontSize: '0.875rem',
                fontWeight: 500,
                textTransform: 'capitalize',
              }}
            >
              {cat}
            </button>
          ))}
        </div>
      </div>

      {/* 앱 목록 */}
      <div
        style={{
          flex: 1,
          padding: '1.5rem',
          overflowY: 'auto',
        }}
      >
        <div style={{ marginBottom: '1rem', color: '#999', fontSize: '0.875rem' }}>
          {filteredApps.length} app{filteredApps.length !== 1 ? 's' : ''} found
        </div>

        {/* 앱 그리드 */}
        <div
          style={{
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fill, minmax(180px, 1fr))',
            gap: '1.5rem',
          }}
        >
          {filteredApps.map((app) => (
            <AppCard key={app.id} app={app} onLaunch={() => handleLaunch(app.id)} />
          ))}
        </div>

        {/* 앱 없음 */}
        {filteredApps.length === 0 && (
          <div
            style={{
              textAlign: 'center',
              padding: '3rem',
              color: '#666',
            }}
          >
            <div style={{ fontSize: '3rem', marginBottom: '1rem' }}>📦</div>
            <div style={{ fontSize: '1.25rem', marginBottom: '0.5rem' }}>No apps found</div>
            <div style={{ fontSize: '0.875rem' }}>
              Try adjusting your search or category filter
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
