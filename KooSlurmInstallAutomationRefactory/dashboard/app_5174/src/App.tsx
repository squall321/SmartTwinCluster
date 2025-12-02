import { useState, useEffect } from 'react'
import './App.css'
import { apiService } from '@core/services/api.service'
import { AppContainer, AppLauncher } from '@core/components'
import { appRegistry } from '@core/services/app.registry'
import { registerExampleApps } from '@apps/example'
import type { AppMetadata, AppConfig, DisplayConfig } from '@core/types'

function App() {
  const [view, setView] = useState<'home' | 'demo' | 'launcher' | 'app'>('launcher')
  const [selectedAppId, setSelectedAppId] = useState<string | null>(null)
  const [AppComponent, setAppComponent] = useState<React.ComponentType<any> | null>(null)
  const [status, setStatus] = useState<'idle' | 'loading' | 'success' | 'error'>('idle')
  const [message, setMessage] = useState('')
  const [backendStatus, setBackendStatus] = useState<string>('checking...')

  // URL에서 토큰 처리 (Auth Portal에서 전달)
  useEffect(() => {
    const urlParams = new URLSearchParams(window.location.search)
    const token = urlParams.get('token')

    if (token) {
      console.log('[Auth] JWT token received from URL, storing in localStorage')
      localStorage.setItem('jwt_token', token)

      // Try to decode JWT and save user info
      try {
        const base64Url = token.split('.')[1]
        const base64 = base64Url.replace(/-/g, '+').replace(/_/g, '/')
        const jsonPayload = decodeURIComponent(
          atob(base64)
            .split('')
            .map(c => '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2))
            .join('')
        )
        const payload = JSON.parse(jsonPayload)
        if (payload.sub) {
          localStorage.setItem('username', payload.sub)
        }
        console.log('[Auth] User info saved:', payload.sub)
      } catch (e) {
        console.error('[Auth] Failed to decode JWT:', e)
      }

      // Remove token from URL for security (prevent token exposure in browser history)
      window.history.replaceState({}, document.title, window.location.pathname)
    }
  }, [])

  // 앱 등록 (초기화)
  useEffect(() => {
    registerExampleApps()
    console.log('[App] Example apps registered')
  }, [])

  // 백엔드 연결 테스트
  useEffect(() => {
    const checkBackend = async () => {
      try {
        const response = await fetch('/api/app/health')
        if (response.ok) {
          setBackendStatus('✅ Connected to kooCAEWebServer_5000')
        } else {
          setBackendStatus('⚠️ Backend responded but not healthy')
        }
      } catch (error) {
        setBackendStatus('❌ Cannot connect to backend')
      }
    }
    checkBackend()
  }, [])

  const handleTest = async () => {
    setStatus('loading')
    setMessage('Testing API...')

    try {
      // API 테스트 (앱 목록 조회)
      await apiService.listApps()
      setStatus('success')
      setMessage('✅ API Service is working!')
    } catch (error) {
      setStatus('error')
      setMessage(`❌ Error: ${error instanceof Error ? error.message : 'Unknown error'}`)
    }
  }

  // Demo 앱 메타데이터
  const demoMetadata: AppMetadata = {
    id: 'demo-app',
    name: 'Demo Application',
    version: '1.0.0',
    description: 'Phase 2 Framework Demo',
    category: 'demo',
  }

  // Demo 앱 설정
  const demoConfig: AppConfig = {
    resources: {
      cpus: 2,
      memory: '4Gi',
      gpu: false,
    },
    display: {
      type: 'novnc',
      width: 1920,
      height: 1080,
    },
    container: {
      image: 'demo-image',
      command: '/bin/bash',
    },
  }

  // Display 설정
  const displayConfig: DisplayConfig = {
    type: 'novnc',
    width: 1920,
    height: 1080,
    quality: 6,
    compression: 2,
    viewOnly: false,
    showControls: true,
  }

  /**
   * 앱 실행
   */
  const handleLaunchApp = async (appId: string) => {
    console.log('[App] Launching app:', appId)
    setSelectedAppId(appId)

    try {
      const component = await appRegistry.loadComponent(appId)
      if (component) {
        setAppComponent(() => component)
        setView('app')
      } else {
        alert('Failed to load app component')
      }
    } catch (error) {
      console.error('[App] Failed to load app:', error)
      alert('Error loading app: ' + (error instanceof Error ? error.message : 'Unknown error'))
    }
  }

  // App Launcher View
  if (view === 'launcher') {
    return (
      <AppLauncher
        onLaunch={handleLaunchApp}
        onBack={() => setView('home')}
      />
    )
  }

  // App View
  if (view === 'app' && AppComponent && selectedAppId) {
    return (
      <div style={{ width: '100vw', height: '100vh', display: 'flex', flexDirection: 'column' }}>
        <div style={{
          padding: '0.5rem 1rem',
          background: '#646cff',
          color: 'white',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between'
        }}>
          <div style={{ fontWeight: 600 }}>Running: {selectedAppId}</div>
          <button
            onClick={() => {
              setView('launcher')
              setAppComponent(null)
              setSelectedAppId(null)
            }}
            style={{
              padding: '0.5rem 1rem',
              background: 'white',
              color: '#646cff',
              border: 'none',
              borderRadius: '4px',
              cursor: 'pointer',
              fontWeight: 500,
            }}
          >
            ← Back to Launcher
          </button>
        </div>
        <div style={{ flex: 1 }}>
          <AppComponent />
        </div>
      </div>
    )
  }

  // Demo View (Phase 2)
  if (view === 'demo') {
    return (
      <div style={{ width: '100vw', height: '100vh', display: 'flex', flexDirection: 'column' }}>
        <div style={{
          padding: '0.5rem 1rem',
          background: '#646cff',
          color: 'white',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between'
        }}>
          <div style={{ fontWeight: 600 }}>Phase 2 Framework Demo</div>
          <button
            onClick={() => setView('home')}
            style={{
              padding: '0.5rem 1rem',
              background: 'white',
              color: '#646cff',
              border: 'none',
              borderRadius: '4px',
              cursor: 'pointer',
              fontWeight: 500,
            }}
          >
            ← Back to Home
          </button>
        </div>
        <div style={{ flex: 1 }}>
          <AppContainer
            metadata={demoMetadata}
            config={demoConfig}
            displayConfig={displayConfig}
            autoStart={false}
            onReady={() => console.log('App ready!')}
            onError={(error) => console.error('App error:', error)}
          />
        </div>
      </div>
    )
  }

  // Home View
  return (
    <div style={{ padding: '2rem', maxWidth: '800px', margin: '0 auto' }}>
      <h1>🚀 App Framework (app_5174)</h1>

      <div style={{
        background: '#f5f5f5',
        padding: '1rem',
        borderRadius: '8px',
        marginBottom: '2rem'
      }}>
        <h2>Project Status</h2>
        <p><strong>Phase:</strong> 3 - Example App & noVNC ✨ NEW</p>
        <p><strong>Port:</strong> 5174</p>
        <p><strong>Backend:</strong> {backendStatus}</p>
      </div>

      <div style={{ marginBottom: '2rem' }}>
        <h2>Quick Test</h2>

        <div style={{ display: 'flex', gap: '1rem', marginBottom: '1rem', flexWrap: 'wrap' }}>
          <button
            onClick={handleTest}
            disabled={status === 'loading'}
            style={{
              padding: '0.75rem 1.5rem',
              fontSize: '1rem',
              cursor: status === 'loading' ? 'wait' : 'pointer',
              background: '#646cff',
              color: 'white',
              border: 'none',
              borderRadius: '8px'
            }}
          >
            {status === 'loading' ? 'Testing...' : 'Test API Connection'}
          </button>

          <button
            onClick={() => setView('launcher')}
            style={{
              padding: '0.75rem 1.5rem',
              fontSize: '1rem',
              cursor: 'pointer',
              background: '#4caf50',
              color: 'white',
              border: 'none',
              borderRadius: '8px'
            }}
          >
            🚀 Launch Apps
          </button>

          <button
            onClick={() => setView('demo')}
            style={{
              padding: '0.75rem 1.5rem',
              fontSize: '1rem',
              cursor: 'pointer',
              background: '#ff9800',
              color: 'white',
              border: 'none',
              borderRadius: '8px'
            }}
          >
            🎨 Phase 2 Demo
          </button>
        </div>

        {message && (
          <div style={{
            marginTop: '1rem',
            padding: '0.75rem',
            borderRadius: '4px',
            background: status === 'success' ? '#d4edda' :
                        status === 'error' ? '#f8d7da' : '#fff3cd',
            color: status === 'success' ? '#155724' :
                   status === 'error' ? '#721c24' : '#856404',
          }}>
            {message}
          </div>
        )}
      </div>

      <div>
        <h2>Project Structure</h2>
        <ul style={{ textAlign: 'left', lineHeight: '1.8' }}>
          <li>✅ Vite + React + TypeScript</li>
          <li>✅ Directory structure (core, apps, shared, embed)</li>
          <li>✅ Type definitions (app, display, embed)</li>
          <li>✅ API Service client</li>
          <li>✅ Development scripts (dev.sh, test-standalone.sh, test-embed.sh)</li>
          <li>✅ <strong>Core Components (AppContainer, DisplayFrame, Toolbar, StatusBar, ControlPanel)</strong></li>
          <li>✅ <strong>Custom Hooks (useAppSession, useDisplay, useWebSocket, useAppLifecycle)</strong></li>
          <li>✅ <strong>BaseApp abstract class</strong></li>
          <li>✅ <strong>App Registry system</strong></li>
          <li>✅ <strong>noVNC integration</strong></li>
          <li>✅ <strong>App Launcher UI</strong></li>
          <li>✅ <strong>GEdit example app</strong></li>
          <li>⏳ Apptainer containers (Phase 3)</li>
          <li>⏳ Embedding support (Phase 4)</li>
        </ul>
      </div>

      <div style={{ marginTop: '2rem', padding: '1rem', background: '#e3f2fd', borderRadius: '8px' }}>
        <h3 style={{ marginTop: 0 }}>🎉 Phase 3 Progress!</h3>
        <p>App Launcher and GEdit example app are ready!</p>
        <p><strong>Try it:</strong> Click "Launch Apps" to see registered apps</p>
      </div>

      <div style={{ marginTop: '2rem', fontSize: '0.875rem', color: '#666' }}>
        <p>📝 <strong>Next Steps (Phase 3):</strong></p>
        <ul style={{ textAlign: 'left' }}>
          <li>Build Apptainer containers</li>
          <li>Backend API implementation</li>
          <li>End-to-end testing</li>
          <li>Phase 4: Embedding support</li>
        </ul>
      </div>
    </div>
  )
}

export default App
