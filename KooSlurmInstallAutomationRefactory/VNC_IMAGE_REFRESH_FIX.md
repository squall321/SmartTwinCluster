# VNC 이미지 목록 자동 갱신 기능 추가

## 📋 개요

날짜: 2025-10-21
작업자: Claude Code
목적: VNC Service 프론트엔드에서 이미지 목록을 주기적으로 갱신하여 새 이미지가 자동으로 표시되도록 개선

## 🎯 문제점

### 이전 동작 (Before)
```typescript
// 이미지는 한 번만 조회
useEffect(() => {
  fetchImages()  // ❌ 초기 로드 시 1회만 실행
  fetchSessions()
  const interval = setInterval(fetchSessions, 5000) // 세션만 5초마다 갱신
  return () => clearInterval(interval)
}, [])
```

**문제:**
1. `fetchImages()`가 초기 로드 시 한 번만 실행
2. 백엔드에 새 이미지(gnome_lsprepost) 추가해도 프론트엔드에 나타나지 않음
3. JWT 토큰 만료 시 에러가 조용히 무시됨 (console.error만)
4. 사용자는 브라우저를 새로고침해야만 새 이미지를 볼 수 있음

## ✅ 해결 방법

### 1. 이미지 목록 주기적 갱신

```typescript
// 초기 로드 및 자동 갱신
useEffect(() => {
  fetchImages()
  fetchSessions()

  // 세션은 5초마다 갱신 (실시간 모니터링)
  const sessionInterval = setInterval(fetchSessions, 5000)

  // 이미지는 30초마다 갱신 (새 이미지 감지용) ✅
  const imageInterval = setInterval(fetchImages, 30000)

  return () => {
    clearInterval(sessionInterval)
    clearInterval(imageInterval)  // ✅ 정리
    Object.values(readinessCheckTimers.current).forEach(timer => clearTimeout(timer))
  }
}, [])
```

### 2. 개선된 에러 처리

```typescript
const fetchImages = async () => {
  try {
    const token = localStorage.getItem('jwt_token')

    // ✅ JWT 토큰 없으면 스킵
    if (!token) {
      console.warn('JWT token not found - skipping image fetch')
      return
    }

    const response = await fetch('/dashboardapi/vnc/images', {
      headers: { 'Authorization': `Bearer ${token}` }
    })

    // ✅ 401 에러 명시적 처리
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

    // ✅ 이미지 목록이 변경된 경우에만 업데이트 (불필요한 리렌더링 방지)
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
    // ✅ 에러 발생 시에도 기존 이미지는 유지 (빈 배열로 덮어쓰지 않음)
  }
}
```

## 📊 개선 사항

| 항목 | 이전 | 개선 후 |
|------|------|---------|
| 이미지 갱신 주기 | 1회 (초기 로드만) | 30초마다 자동 갱신 |
| JWT 만료 처리 | 무시됨 (console.error) | 사용자에게 에러 메시지 표시 |
| 새 이미지 감지 | 브라우저 새로고침 필요 | 최대 30초 내 자동 감지 |
| 불필요한 리렌더링 | 매번 setState | 변경 시에만 업데이트 |
| 에러 복구력 | 에러 시 빈 배열로 덮어씀 | 기존 이미지 유지 |

## 🔧 변경된 파일

### [dashboard/vnc_service_8002/src/App.tsx](dashboard/vnc_service_8002/src/App.tsx)

**주요 변경:**
1. `fetchImages()` 함수 개선 (줄 57-98)
   - JWT 토큰 확인 추가
   - 401 에러 명시적 처리
   - 이미지 목록 변경 감지
   - 에러 시 기존 데이터 보존

2. `useEffect` 수정 (줄 300-316)
   - `imageInterval` 추가 (30초)
   - 타이머 정리 개선

## 🧪 테스트 시나리오

### 시나리오 1: 새 이미지 배포
1. 백엔드에 새 VNC 이미지 추가
2. 백엔드 재시작
3. **기대 결과**: 30초 이내 프론트엔드 드롭다운에 새 이미지 자동 표시

### 시나리오 2: JWT 만료
1. 오래된 페이지에서 JWT 만료
2. 30초 후 이미지 갱신 시도
3. **기대 결과**: "인증이 만료되었습니다" 에러 메시지 표시

### 시나리오 3: 네트워크 장애
1. 백엔드 API 일시적 장애
2. 이미지 갱신 실패
3. **기대 결과**: 기존 이미지 목록 유지 (빈 목록으로 변경되지 않음)

## 📈 성능 고려사항

### 왜 30초인가?

- **세션**: 5초마다 갱신 (실시간 상태 모니터링 필요)
- **이미지**: 30초마다 갱신 (자주 바뀌지 않음, API 부하 최소화)

30초는 다음을 고려한 균형점:
- 충분히 빠른 새 이미지 감지 (사용자 경험)
- 불필요한 API 호출 최소화 (서버 부하)
- 이미지 목록은 자주 변하지 않음 (일반적으로 하루 1-2회 정도)

### 최적화 기법

1. **JSON 비교로 불필요한 업데이트 방지**
   ```typescript
   if (JSON.stringify(fetchedImages) !== JSON.stringify(images)) {
     setImages(fetchedImages)  // 변경 시에만 업데이트
   }
   ```

2. **타이머 정리**
   ```typescript
   return () => {
     clearInterval(sessionInterval)
     clearInterval(imageInterval)  // 메모리 누수 방지
   }
   ```

## 🚀 배포

### 빌드
```bash
cd dashboard/vnc_service_8002
npx vite build
```

### 배포 확인
- 빌드 성공: `dist/assets/index-ChcH4pn6.js` (202.36 kB)
- 30초 interval 포함 확인: minified code에 `3e4` (30000ms) 포함

### Nginx 재시작 불필요
Nginx는 `dist/` 디렉토리를 직접 제공하므로 빌드 후 즉시 반영됨.

## 💡 향후 개선 가능성

1. **실시간 업데이트 (WebSocket)**
   - 백엔드에서 이미지 변경 시 WebSocket으로 즉시 알림
   - 30초 대기 없이 즉시 반영

2. **로컬 캐싱**
   - 이미지 목록을 localStorage에 캐싱
   - 페이지 로드 속도 개선

3. **Progressive Loading**
   - 첫 로드는 캐시된 데이터 사용
   - 백그라운드에서 최신 데이터 가져오기

## 📝 관련 문서

- [APPTAINER_RESTRUCTURE.md](APPTAINER_RESTRUCTURE.md) - Apptainer 구조 재편성
- [USAGE.md](USAGE.md) - 전체 시스템 사용 가이드
- [dashboard/vnc_service_8002/src/App.tsx](dashboard/vnc_service_8002/src/App.tsx) - 수정된 소스 코드

## ✨ 요약

VNC Service 프론트엔드에 주기적 이미지 목록 갱신 기능을 추가했습니다. 이제 새 VNC 이미지를 백엔드에 추가하면 30초 이내에 자동으로 프론트엔드 드롭다운에 나타나며, JWT 만료와 같은 에러 상황도 적절히 처리됩니다.

**사용자는 더 이상 브라우저를 새로고침하지 않아도 됩니다! 🚀**
