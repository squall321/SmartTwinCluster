import { useState, useEffect, useRef } from 'react'
import './App.css'

interface VNCSession {
  session_id: string
  job_id: number
  status: string
  node?: string
  novnc_url?: string
  vnc_port: number
  novnc_port: number
  geometry: string
  image_id?: string
  image_name?: string
  created_at: string
}

interface VNCImage {
  id: string
  name: string
  description: string
  icon: string
  default: boolean
  available: boolean
}

interface SessionReadiness {
  [key: string]: {
    ready: boolean
    checking: boolean
  }
}

function App() {
  const [sessions, setSessions] = useState<VNCSession[]>([])
  const [images, setImages] = useState<VNCImage[]>([])
  const [selectedImageId, setSelectedImageId] = useState<string>('xfce4')
  const [error, setError] = useState('')
  const [creating, setCreating] = useState(false)
  const [resetDialogSession, setResetDialogSession] = useState<string | null>(null)
  const [readiness, setReadiness] = useState<SessionReadiness>({})
  const readinessCheckTimers = useRef<{[key: string]: number}>({})

  // URL에서 토큰 가져오기 및 저장
  useEffect(() => {
    const params = new URLSearchParams(window.location.search)
    const token = params.get('token')
    if (token) {
      localStorage.setItem('jwt_token', token)
      // URL에서 토큰 제거 (보안)
      window.history.replaceState({}, document.title, window.location.pathname)
    }
  }, [])

  // 이미지 목록 조회
  const fetchImages = async () => {
    try {
      const token = localStorage.getItem('jwt_token')
      if (!token) {
        console.warn('JWT token not found - skipping image fetch')
        return
      }

      const response = await fetch('/dashboardapi/vnc/images', {
        headers: { 'Authorization': `Bearer ${token}` }
      })

      if (response.status === 401) {
        console.error('JWT token expired or invalid')
        setError('인증이 만료되었습니다. 다시 로그인해주세요.')
        return
      }

      if (!response.ok) {
        throw new Error('Failed to fetch images')
      }

      const data = await response.json()
      const fetchedImages = data.images || []

      // 이미지 목록이 변경된 경우에만 업데이트 (불필요한 리렌더링 방지)
      if (JSON.stringify(fetchedImages) !== JSON.stringify(images)) {
        setImages(fetchedImages)

        // 기본 이미지 선택 (초기 로드 시에만)
        if (images.length === 0) {
          const defaultImage = fetchedImages.find((img: VNCImage) => img.default)
          if (defaultImage) {
            setSelectedImageId(defaultImage.id)
          }
        }
      }
    } catch (err: any) {
      console.error('Error fetching images:', err)
      // 에러 발생 시에도 기존 이미지는 유지 (빈 배열로 덮어쓰지 않음)
    }
  }

  // VNC 세션 readiness 체크
  const checkSessionReadiness = async (sessionId: string) => {
    const token = localStorage.getItem('jwt_token')

    try {
      const response = await fetch(`/dashboardapi/vnc/sessions/${sessionId}/ready`, {
        headers: { 'Authorization': `Bearer ${token}` }
      })

      if (response.ok) {
        const data = await response.json()
        setReadiness(prev => ({
          ...prev,
          [sessionId]: {
            ready: data.ready === true,
            checking: false
          }
        }))

        // 아직 준비 안됐으면 2초 후 재시도 (빠른 감지)
        if (!data.ready) {
          readinessCheckTimers.current[sessionId] = setTimeout(() => {
            checkSessionReadiness(sessionId)
          }, 2000)
        }
      }
    } catch (err) {
      console.error(`Readiness check failed for ${sessionId}:`, err)
      setReadiness(prev => ({
        ...prev,
        [sessionId]: { ready: false, checking: false }
      }))
    }
  }

  // 세션 목록 조회
  const fetchSessions = async () => {
    try {
      const token = localStorage.getItem('jwt_token')
      const response = await fetch('/dashboardapi/vnc/sessions', {
        headers: { 'Authorization': `Bearer ${token}` }
      })

      if (!response.ok) throw new Error('Failed to fetch sessions')

      const data = await response.json()
      setSessions(data.sessions || [])

      // Running 상태 세션에 대해 readiness 체크 시작
      data.sessions.forEach((session: VNCSession) => {
        if (session.status === 'running') {
          // 기존 타이머 정리
          if (readinessCheckTimers.current[session.session_id]) {
            clearTimeout(readinessCheckTimers.current[session.session_id])
          }

          // readiness 확인 상태가 아직 없거나 ready가 아닌 경우에만 체크
          if (!readiness[session.session_id] || !readiness[session.session_id].ready) {
            setReadiness(prev => ({
              ...prev,
              [session.session_id]: { ready: false, checking: true }
            }))
            checkSessionReadiness(session.session_id)
          }
        }
      })
    } catch (err: any) {
      setError(err.message)
    }
  }

  // 세션 생성
  const createSession = async () => {
    try {
      setCreating(true)
      setError('')

      const token = localStorage.getItem('jwt_token')

      // 기존 세션이 다른 이미지인 경우 경고
      const existingSession = sessions.find(s => s.status === 'running' || s.status === 'pending')
      if (existingSession && existingSession.image_id && existingSession.image_id !== selectedImageId) {
        const selectedImage = images.find(img => img.id === selectedImageId)
        const confirmed = confirm(
          `⚠️ 이미지 변경 감지!\n\n` +
          `현재 세션: ${existingSession.image_name || existingSession.image_id}\n` +
          `새 이미지: ${selectedImage?.name}\n\n` +
          `이미지를 변경하면 기존 세션 데이터가 초기화됩니다.\n` +
          `계속하시겠습니까?`
        )

        if (!confirmed) {
          setCreating(false)
          return
        }

        // 기존 세션 초기화
        await resetSession(existingSession.session_id)
        await new Promise(resolve => setTimeout(resolve, 2000)) // 초기화 대기
      }

      const response = await fetch('/dashboardapi/vnc/sessions', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          image_id: selectedImageId,
          geometry: '1920x1080',
          duration_hours: 4,
          gpu_count: 1
        })
      })

      if (!response.ok) {
        const errorData = await response.json()
        throw new Error(errorData.error || 'Failed to create session')
      }

      await fetchSessions()
    } catch (err: any) {
      setError(err.message)
    } finally {
      setCreating(false)
    }
  }

  // 세션 삭제
  const deleteSession = async (sessionId: string) => {
    try {
      const token = localStorage.getItem('jwt_token')
      const response = await fetch(`/dashboardapi/vnc/sessions/${sessionId}`, {
        method: 'DELETE',
        headers: { 'Authorization': `Bearer ${token}` }
      })

      if (!response.ok) throw new Error('Failed to delete session')

      // 타이머 정리
      if (readinessCheckTimers.current[sessionId]) {
        clearTimeout(readinessCheckTimers.current[sessionId])
        delete readinessCheckTimers.current[sessionId]
      }

      // Readiness 상태 제거
      setReadiness(prev => {
        const newReadiness = { ...prev }
        delete newReadiness[sessionId]
        return newReadiness
      })

      await fetchSessions()
    } catch (err: any) {
      setError(err.message)
    }
  }

  // 세션 초기화
  const resetSession = async (sessionId: string) => {
    try {
      const token = localStorage.getItem('jwt_token')
      const response = await fetch(`/dashboardapi/vnc/sessions/${sessionId}/reset`, {
        method: 'POST',
        headers: { 'Authorization': `Bearer ${token}` }
      })

      if (!response.ok) throw new Error('Failed to reset session')

      // 타이머 정리
      if (readinessCheckTimers.current[sessionId]) {
        clearTimeout(readinessCheckTimers.current[sessionId])
        delete readinessCheckTimers.current[sessionId]
      }

      // Readiness 상태 제거
      setReadiness(prev => {
        const newReadiness = { ...prev }
        delete newReadiness[sessionId]
        return newReadiness
      })

      await fetchSessions()
      setResetDialogSession(null)
    } catch (err: any) {
      setError(err.message)
    }
  }

  const handleResetClick = (sessionId: string) => {
    setResetDialogSession(sessionId)
  }

  const confirmReset = () => {
    if (resetDialogSession) {
      resetSession(resetDialogSession)
    }
  }

  // 초기 로드 및 자동 갱신
  useEffect(() => {
    fetchImages()
    fetchSessions()

    // 세션은 5초마다 갱신 (실시간 모니터링)
    const sessionInterval = setInterval(fetchSessions, 5000)

    // 이미지는 30초마다 갱신 (새 이미지 감지용)
    const imageInterval = setInterval(fetchImages, 30000)

    return () => {
      clearInterval(sessionInterval)
      clearInterval(imageInterval)
      // 모든 타이머 정리
      Object.values(readinessCheckTimers.current).forEach(timer => clearTimeout(timer))
    }
  }, [])

  const getStatusColor = (status: string) => {
    switch (status.toLowerCase()) {
      case 'running': return '#10b981'
      case 'pending': return '#f59e0b'
      case 'completed': return '#6b7280'
      default: return '#ef4444'
    }
  }

  const getStatusText = (status: string) => {
    switch (status.toLowerCase()) {
      case 'running': return '실행 중'
      case 'pending': return '대기 중'
      case 'completed': return '완료됨'
      default: return status
    }
  }

  // 세션이 연결 가능한지 확인
  const isSessionConnectable = (session: VNCSession) => {
    if (session.status !== 'running') return false
    if (!session.novnc_url) return false

    const sessionReadiness = readiness[session.session_id]
    if (!sessionReadiness) return false

    return sessionReadiness.ready === true
  }

  // 연결 버튼 텍스트
  const getConnectButtonText = (session: VNCSession) => {
    if (session.status !== 'running') return '대기 중...'
    if (!session.novnc_url) return '준비 중...'

    const sessionReadiness = readiness[session.session_id]
    if (!sessionReadiness) return '확인 중...'
    if (sessionReadiness.checking) return '확인 중...'
    if (!sessionReadiness.ready) return '준비 중...'

    return '🚀 연결하기'
  }

  return (
    <div className="app">
      <header className="header">
        <div className="header-content">
          <h1>🖥️ VNC Visualization Service</h1>
          <p>GPU 가속 원격 데스크톱</p>
        </div>
        <div className="header-actions">
          <div className="image-selector">
            <label htmlFor="image-select">데스크톱 환경:</label>
            <select
              id="image-select"
              value={selectedImageId}
              onChange={(e) => setSelectedImageId(e.target.value)}
              className="image-select"
            >
              {images.filter(img => img.available).map(image => (
                <option key={image.id} value={image.id}>
                  {image.icon} {image.name}
                </option>
              ))}
            </select>
          </div>
          <button
            className="btn-primary"
            onClick={createSession}
            disabled={creating}
          >
            {creating ? '생성 중...' : '+ 새 세션'}
          </button>
        </div>
      </header>

      {error && (
        <div className="error-banner">
          ❌ {error}
        </div>
      )}

      <main className="main">
        {sessions.length === 0 ? (
          <div className="empty-state">
            <div className="empty-icon">🖥️</div>
            <h2>활성 세션이 없습니다</h2>
            <p>새 VNC 세션을 생성하여 GPU 가속 원격 데스크톱을 시작하세요</p>
          </div>
        ) : (
          <div className="sessions-grid">
            {sessions.map((session) => (
              <div key={session.session_id} className="session-card">
                <div className="session-header">
                  <div className="session-title">
                    <h3>{session.image_name || session.image_id || 'VNC Session'}</h3>
                    <span
                      className="session-status"
                      style={{ backgroundColor: getStatusColor(session.status) }}
                    >
                      {getStatusText(session.status)}
                    </span>
                  </div>
                  <div className="session-actions-header">
                    <button
                      className="btn-reset"
                      onClick={() => handleResetClick(session.session_id)}
                      title="세션 데이터 초기화"
                    >
                      🔄 초기화
                    </button>
                    <button
                      className="btn-danger"
                      onClick={() => deleteSession(session.session_id)}
                    >
                      종료
                    </button>
                  </div>
                </div>

                <div className="session-info">
                  <div className="info-row">
                    <span className="info-label">Job ID:</span>
                    <span className="info-value">{session.job_id}</span>
                  </div>
                  {session.node && (
                    <div className="info-row">
                      <span className="info-label">Node:</span>
                      <span className="info-value">{session.node}</span>
                    </div>
                  )}
                  <div className="info-row">
                    <span className="info-label">Geometry:</span>
                    <span className="info-value">{session.geometry}</span>
                  </div>
                  <div className="info-row">
                    <span className="info-label">Ports:</span>
                    <span className="info-value">
                      VNC: {session.vnc_port} | noVNC: {session.novnc_port}
                    </span>
                  </div>
                </div>

                {session.novnc_url && (
                  <div className="session-actions">
                    <button
                      className="btn-connect"
                      onClick={() => window.open(session.novnc_url, '_blank')}
                      disabled={!isSessionConnectable(session)}
                    >
                      {getConnectButtonText(session)}
                    </button>
                  </div>
                )}
              </div>
            ))}
          </div>
        )}
      </main>

      {/* 초기화 확인 다이얼로그 */}
      {resetDialogSession && (
        <div className="dialog-overlay" onClick={() => setResetDialogSession(null)}>
          <div className="dialog" onClick={(e) => e.stopPropagation()}>
            <h2>⚠️ 세션 데이터 초기화</h2>
            <p>
              현재 세션의 모든 데이터가 삭제됩니다.<br />
              세션이 종료되고 샌드박스가 완전히 초기화됩니다.<br />
              <br />
              <strong>이 작업은 되돌릴 수 없습니다.</strong>
            </p>
            <div className="dialog-actions">
              <button
                className="btn-secondary"
                onClick={() => setResetDialogSession(null)}
              >
                취소
              </button>
              <button
                className="btn-danger"
                onClick={confirmReset}
              >
                초기화
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

export default App
