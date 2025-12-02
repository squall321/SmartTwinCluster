# 📋 Dashboard 잔여 Phase 개선 계획 (v4.3 → v5.0)

> **프로젝트:** Slurm Cluster Management Dashboard
> **현재 버전:** v4.3.0 (Phase 3 완료)
> **목표 버전:** v5.0
> **작성일:** 2025-11-05
> **Phase 1-3 완료:** Apptainer Discovery, Template Management, File Upload API

---

## ⚠️ 개발 규칙 및 가이드라인

### 🔒 핵심 원칙 (MUST FOLLOW)

#### 1. 시스템 안정성 보장
- ✅ **기존 시스템 보호**: 현재 잘 동작하는 시스템에 영향을 주지 않도록 최대한 주의
- ✅ **점진적 개선**: 한 번에 하나의 기능만 수정하고 철저히 테스트
- ✅ **롤백 가능성**: 모든 변경사항은 롤백 가능하도록 백업 유지
- ✅ **의존성 최소화**: 새로운 기능이 기존 기능에 의존하지 않도록 독립적으로 설계

#### 2. 근본 원인 분석 및 해결
- ❌ **임시방편 금지**: "빨리 돌아가게" 하는 임시 해법 금지
- ✅ **근본 원인 분석**: 문제의 근본 원인을 파악하고 근본적으로 해결
- ✅ **문서화**: 문제 발생 원인과 해결 방법을 상세히 문서화
- ✅ **재발 방지**: 동일한 문제가 다시 발생하지 않도록 구조적 개선

#### 3. 소스 코드 기반 수정
- ❌ **운영 서버 직접 수정 금지**: 배포된 서버의 파일을 직접 수정하지 말것
- ✅ **소스 코드 수정**: 빌드 전 소스 코드 수정 (frontend_3010, backend_5010, websocket_5011)
- ✅ **Setup 스크립트 수정**: 배포 과정 변경은 setup 스크립트 수정 (phase*.sh)
- ✅ **버전 관리**: 모든 변경사항은 Git으로 관리

#### 4. 자동 배포 시스템 통합
- ✅ **setup_cluster_full_multihead.sh 통합**: 모든 변경사항이 자동 배포 스크립트에 반영
- ✅ **멱등성 보장**: 스크립트를 여러 번 실행해도 동일한 결과 보장
- ✅ **에러 핸들링**: 각 Phase에서 실패 시 적절한 exit code 반환 및 롤백
- ✅ **의존성 검증**: 스크립트 실행 전 필수 의존성 검증

#### 5. 신규 서버 배포 대응
- ✅ **헤드노드 독립성**: 헤드노드 설정도 setup 파일에 포함하여 자동화
- ✅ **환경 설정 파일화**: 하드코딩된 경로/포트/IP 대신 환경 변수 또는 설정 파일 사용
- ✅ **의존성 자동 설치**: 필요한 패키지, 라이브러리 자동 설치
- ✅ **초기 데이터 생성**: DB 초기화, 샘플 데이터, 기본 템플릿 자동 생성

#### 6. Job Submit 개선 우선순위
- ⚠️ **현재 상태**: Job submit을 제외한 대부분의 기능은 정상 동작
- ✅ **영향 범위 파악**: 수정이 다른 시스템에 미칠 영향 사전 분석
- ✅ **단계적 검증**: 각 단계마다 Job submit 기능이 제대로 동작하는지 검증
- ✅ **통합 테스트**: Template → File Upload → Job Submit → Monitoring 전체 플로우 테스트

---

## 📊 Phase 1-3 완료 현황

### ✅ Phase 1: Apptainer Discovery & Integration
**완료일:** 2025-11-05
**주요 성과:**
- ✅ `apptainer_service.py` - SSH 기반 이미지 스캔 서비스
- ✅ `apptainer_api.py` - REST API 엔드포인트
- ✅ DB 마이그레이션 v4.1.0 - apptainer_images 테이블
- ✅ `ApptainerSelector.tsx` - Frontend 이미지 선택 컴포넌트
- ✅ 배포 완료 및 API 테스트 성공

### ✅ Phase 2: Template Management System
**완료일:** 2025-11-05
**주요 성과:**
- ✅ `/shared/templates/` - 외부 YAML 템플릿 저장소 구조
- ✅ `template_loader.py` - 템플릿 로딩 및 DB 동기화
- ✅ `template_watcher.py` - 파일 시스템 감시 (Hot Reload)
- ✅ `templates_api_v2.py` - Template Management REST API
- ✅ DB 마이그레이션 v4.2.0 - job_templates_v2 테이블
- ✅ 배포 완료 및 API 테스트 성공

### ✅ Phase 3: Unified File Upload API (Backend)
**완료일:** 2025-11-05
**주요 성과:**
- ✅ `file_classifier.py` - 파일 타입 자동 분류 (7가지 타입)
- ✅ `file_upload_api.py` - 청크 기반 업로드 REST API
- ✅ WebSocket `broadcast_message()` - 진행률 브로드캐스트
- ✅ DB 마이그레이션 v4.3.0 - file_uploads 테이블
- ✅ `/shared/uploads/` 저장소 구조 생성
- ✅ 배포 완료 및 API 테스트 성공 (4가지 파일 타입 검증)

**⚠️ Phase 3 잔여 작업:**
- ❌ Frontend 업로드 컴포넌트 (UnifiedUploader.tsx)
- ❌ 청크 업로드 UI 및 진행률 표시
- ❌ WebSocket 연동 실시간 업데이트
- ❌ 템플릿 스키마 기반 파일 검증 UI

---

## 🚀 Phase 3 완성: Frontend File Upload (우선순위 1)

**목표:** Backend API와 연동되는 통합 파일 업로드 UI 구현
**예상 기간:** 3-4일
**의존성:** Phase 3 Backend 완료 ✅

### 3.4 Frontend Upload Component 구현

#### 파일 구조
```
frontend_3010/src/
├── components/
│   └── FileUpload/
│       ├── UnifiedUploader.tsx          # 메인 업로드 컴포넌트
│       ├── ChunkUploader.ts             # 청크 업로드 유틸리티
│       ├── FileClassifier.tsx           # 파일 분류 UI
│       ├── UploadProgress.tsx           # 진행률 표시
│       └── FilePreview.tsx              # 파일 미리보기
├── hooks/
│   ├── useFileUpload.ts                 # 파일 업로드 훅
│   └── useUploadProgress.ts             # 진행률 WebSocket 훅
└── types/
    └── upload.ts                        # 업로드 타입 정의
```

#### 구현 내용

**1. UnifiedUploader.tsx - 메인 컴포넌트**
```typescript
interface UnifiedUploaderProps {
  templateId?: string;                   // 템플릿 ID (검증용)
  jobId?: string;                        // Job ID (저장 경로 결정)
  userId: string;                        // 사용자 ID
  onComplete: (files: UploadedFile[]) => void;
  onError?: (error: Error) => void;
  maxFileSize?: number;                  // 기본 50GB
  maxFiles?: number;                     // 최대 파일 수
  acceptedTypes?: string[];              // 허용 파일 타입
  enableChunking?: boolean;              // 청크 업로드 활성화
  chunkSize?: number;                    // 청크 크기 (기본 5MB)
}

export const UnifiedUploader: React.FC<UnifiedUploaderProps> = ({
  templateId,
  jobId,
  userId,
  onComplete,
  onError,
  maxFileSize = 50 * 1024 * 1024 * 1024, // 50GB
  maxFiles = 20,
  acceptedTypes,
  enableChunking = true,
  chunkSize = 5 * 1024 * 1024
}) => {
  // Features:
  // - Drag & Drop 지원
  // - 다중 파일 선택
  // - 파일 타입 자동 분류 표시
  // - 실시간 진행률 (WebSocket)
  // - 대용량 파일 청크 업로드
  // - 업로드 일시정지/재개/취소
  // - 파일 미리보기
  // - 중복 파일 감지
  // - 에러 핸들링 및 재시도
};
```

**2. ChunkUploader.ts - 청크 업로드 유틸**
```typescript
interface ChunkUploadOptions {
  file: File;
  uploadId: string;
  chunkSize: number;
  onProgress: (progress: number) => void;
  onError: (error: Error) => void;
  signal?: AbortSignal;                  // 취소 지원
}

class ChunkUploader {
  private uploadQueue: Map<string, ChunkUploadState> = new Map();

  async uploadFile(options: ChunkUploadOptions): Promise<void> {
    const { file, uploadId, chunkSize, onProgress, onError, signal } = options;

    const totalChunks = Math.ceil(file.size / chunkSize);
    let uploadedChunks = 0;

    for (let i = 0; i < totalChunks; i++) {
      // 취소 체크
      if (signal?.aborted) {
        throw new Error('Upload cancelled');
      }

      const chunk = file.slice(i * chunkSize, (i + 1) * chunkSize);

      try {
        await this.uploadChunk(uploadId, chunk, i);
        uploadedChunks++;
        onProgress((uploadedChunks / totalChunks) * 100);
      } catch (error) {
        // 재시도 로직 (3회)
        await this.retryChunk(uploadId, chunk, i, 3);
      }
    }

    // 업로드 완료 요청
    await this.completeUpload(uploadId);
  }

  async uploadChunk(uploadId: string, chunk: Blob, index: number): Promise<void> {
    const formData = new FormData();
    formData.append('upload_id', uploadId);
    formData.append('chunk_index', index.toString());
    formData.append('chunk', chunk);

    const response = await fetch('/api/v2/files/upload/chunk', {
      method: 'POST',
      body: formData
    });

    if (!response.ok) {
      throw new Error(`Chunk ${index} upload failed`);
    }
  }

  async pauseUpload(uploadId: string): Promise<void> {
    // 업로드 일시정지
  }

  async resumeUpload(uploadId: string): Promise<void> {
    // 업로드 재개
  }

  async cancelUpload(uploadId: string): Promise<void> {
    // 업로드 취소 및 정리
    await fetch(`/api/v2/files/uploads/${uploadId}`, {
      method: 'DELETE'
    });
  }
}
```

**3. useFileUpload.ts - 업로드 훅**
```typescript
interface UseFileUploadResult {
  uploadFiles: (files: File[]) => Promise<void>;
  uploadProgress: Record<string, number>;
  uploadStatus: Record<string, 'pending' | 'uploading' | 'completed' | 'error'>;
  cancelUpload: (fileId: string) => void;
  pauseUpload: (fileId: string) => void;
  resumeUpload: (fileId: string) => void;
  isUploading: boolean;
  error: Error | null;
}

export const useFileUpload = (options: FileUploadOptions): UseFileUploadResult => {
  const [uploadProgress, setUploadProgress] = useState<Record<string, number>>({});
  const [uploadStatus, setUploadStatus] = useState<Record<string, string>>({});
  const [error, setError] = useState<Error | null>(null);

  const uploadFiles = async (files: File[]) => {
    // 1. 각 파일에 대해 업로드 세션 초기화
    for (const file of files) {
      const response = await fetch('/api/v2/files/upload/init', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          filename: file.name,
          file_size: file.size,
          user_id: options.userId,
          job_id: options.jobId
        })
      });

      const { upload_id, chunk_size, total_chunks } = await response.json();

      // 2. 청크 업로드 시작
      const uploader = new ChunkUploader();
      await uploader.uploadFile({
        file,
        uploadId: upload_id,
        chunkSize: chunk_size,
        onProgress: (progress) => {
          setUploadProgress(prev => ({ ...prev, [upload_id]: progress }));
        },
        onError: setError
      });
    }
  };

  return {
    uploadFiles,
    uploadProgress,
    uploadStatus,
    cancelUpload,
    pauseUpload,
    resumeUpload,
    isUploading: Object.values(uploadStatus).some(s => s === 'uploading'),
    error
  };
};
```

**4. useUploadProgress.ts - WebSocket 진행률 훅**
```typescript
interface UploadProgressEvent {
  upload_id: string;
  uploaded_chunks: number;
  total_chunks: number;
  progress: number;
  status: string;
}

export const useUploadProgress = (uploadId: string) => {
  const [progress, setProgress] = useState(0);
  const [status, setStatus] = useState<string>('pending');

  useEffect(() => {
    const ws = new WebSocket('ws://localhost:5011/ws');

    ws.onmessage = (event) => {
      const data = JSON.parse(event.data);

      if (data.type === 'upload_progress' && data.data.upload_id === uploadId) {
        setProgress(data.data.progress);
        setStatus(data.data.status || 'uploading');
      }
    };

    return () => ws.close();
  }, [uploadId]);

  return { progress, status };
};
```

**5. FileClassifier.tsx - 파일 분류 표시**
```typescript
interface FileClassifierProps {
  files: File[];
  onClassified: (classified: Record<string, File[]>) => void;
}

export const FileClassifier: React.FC<FileClassifierProps> = ({
  files,
  onClassified
}) => {
  const [classified, setClassified] = useState<Record<string, File[]>>({});

  useEffect(() => {
    // 파일 분류 (확장자 기반)
    const groups: Record<string, File[]> = {
      data: [],
      config: [],
      script: [],
      model: [],
      mesh: [],
      result: [],
      other: []
    };

    files.forEach(file => {
      const ext = file.name.split('.').pop()?.toLowerCase();
      const type = detectFileType(ext);
      groups[type].push(file);
    });

    setClassified(groups);
    onClassified(groups);
  }, [files]);

  return (
    <div className="file-classifier">
      {Object.entries(classified).map(([type, typeFiles]) => (
        typeFiles.length > 0 && (
          <div key={type} className="file-group">
            <h3>{type.toUpperCase()} Files ({typeFiles.length})</h3>
            <ul>
              {typeFiles.map(file => (
                <li key={file.name}>
                  {file.name} ({formatSize(file.size)})
                </li>
              ))}
            </ul>
          </div>
        )
      ))}
    </div>
  );
};
```

### 3.5 통합 테스트

**시나리오 1: 단일 작은 파일 업로드**
```typescript
// Test: 1MB 파일 업로드
const smallFile = new File(['test data'], 'config.yaml', { type: 'text/yaml' });
await uploadFiles([smallFile]);
// Expected: 단일 청크, 즉시 완료
```

**시나리오 2: 대용량 파일 청크 업로드**
```typescript
// Test: 10GB 파일 업로드
const largeFile = new File([/* 10GB data */], 'dataset.tar.gz');
await uploadFiles([largeFile]);
// Expected: 2000개 청크, 진행률 표시
```

**시나리오 3: 다중 파일 업로드**
```typescript
// Test: 여러 타입의 파일 동시 업로드
const files = [
  new File(['data'], 'input.dat'),
  new File(['config'], 'config.json'),
  new File(['script'], 'run.sh')
];
await uploadFiles(files);
// Expected: 3개 파일 분류 및 각각 업로드
```

**시나리오 4: 업로드 취소 및 재개**
```typescript
// Test: 업로드 도중 일시정지 후 재개
await pauseUpload(uploadId);
// ... 시간 경과
await resumeUpload(uploadId);
// Expected: 이전 청크부터 재개
```

### 3.6 배포 체크리스트

- [ ] `UnifiedUploader.tsx` 구현 완료
- [ ] `ChunkUploader.ts` 구현 및 테스트
- [ ] WebSocket 연동 테스트
- [ ] 파일 분류 UI 테스트
- [ ] 진행률 표시 테스트
- [ ] 대용량 파일 (5GB+) 업로드 테스트
- [ ] 에러 핸들링 테스트
- [ ] Job Submit 플로우와 통합 테스트
- [ ] Frontend 빌드 및 배포
- [ ] 사용자 시나리오 E2E 테스트

---

## 🔐 Phase 4: Security & Infrastructure (우선순위 2)

**목표:** 보안 강화 및 인프라 최적화
**예상 기간:** 2주
**의존성:** 없음 (독립적 구현 가능)

### 4.1 JWT Refresh Token System

**목적:** Access Token 짧은 TTL + Refresh Token 장기 TTL로 보안 강화

**새 파일:** `auth_portal_4430/token_service.py`

```python
import redis
from datetime import datetime, timedelta
import jwt
from typing import List, Dict

class TokenService:
    def __init__(self):
        self.redis_client = redis.Redis(
            host='localhost',
            port=6379,
            db=0,
            decode_responses=True
        )
        self.secret_key = os.getenv('JWT_SECRET_KEY')
        self.access_token_ttl = 15 * 60  # 15분
        self.refresh_token_ttl = 7 * 24 * 3600  # 7일

    def generate_access_token(self, user_id: str, permissions: List[str]) -> str:
        """
        Access Token 생성 (15분 유효)

        Args:
            user_id: 사용자 ID
            permissions: 권한 목록

        Returns:
            JWT Access Token
        """
        payload = {
            'user_id': user_id,
            'permissions': permissions,
            'type': 'access',
            'exp': datetime.utcnow() + timedelta(seconds=self.access_token_ttl),
            'iat': datetime.utcnow()
        }

        return jwt.encode(payload, self.secret_key, algorithm='HS256')

    def generate_refresh_token(self, user_id: str) -> str:
        """
        Refresh Token 생성 및 Redis 저장 (7일 유효)

        Args:
            user_id: 사용자 ID

        Returns:
            JWT Refresh Token
        """
        token_id = self._generate_token_id()

        payload = {
            'user_id': user_id,
            'token_id': token_id,
            'type': 'refresh',
            'exp': datetime.utcnow() + timedelta(seconds=self.refresh_token_ttl),
            'iat': datetime.utcnow()
        }

        token = jwt.encode(payload, self.secret_key, algorithm='HS256')

        # Redis에 저장 (Token Revocation 지원)
        redis_key = f"refresh_token:{user_id}:{token_id}"
        self.redis_client.setex(redis_key, self.refresh_token_ttl, token)

        return token

    def refresh_access_token(self, refresh_token: str) -> Dict[str, str]:
        """
        Refresh Token으로 새 Access Token 발급

        Args:
            refresh_token: Refresh Token

        Returns:
            { "access_token": "...", "expires_in": 900 }

        Raises:
            InvalidTokenError: 토큰이 유효하지 않거나 무효화됨
        """
        try:
            # Refresh Token 검증
            payload = jwt.decode(refresh_token, self.secret_key, algorithms=['HS256'])

            if payload.get('type') != 'refresh':
                raise InvalidTokenError("Not a refresh token")

            user_id = payload['user_id']
            token_id = payload['token_id']

            # Redis에서 토큰 존재 확인 (Revocation 체크)
            redis_key = f"refresh_token:{user_id}:{token_id}"
            stored_token = self.redis_client.get(redis_key)

            if not stored_token or stored_token != refresh_token:
                raise InvalidTokenError("Token revoked or invalid")

            # 새 Access Token 발급
            permissions = self._get_user_permissions(user_id)
            access_token = self.generate_access_token(user_id, permissions)

            return {
                'access_token': access_token,
                'expires_in': self.access_token_ttl
            }

        except jwt.ExpiredSignatureError:
            raise InvalidTokenError("Refresh token expired")
        except jwt.InvalidTokenError as e:
            raise InvalidTokenError(f"Invalid token: {str(e)}")

    def revoke_refresh_token(self, user_id: str, token_id: str = None):
        """
        Refresh Token 무효화 (로그아웃)

        Args:
            user_id: 사용자 ID
            token_id: 특정 토큰 ID (None이면 모든 토큰)
        """
        if token_id:
            # 특정 토큰만 무효화
            redis_key = f"refresh_token:{user_id}:{token_id}"
            self.redis_client.delete(redis_key)
        else:
            # 해당 사용자의 모든 Refresh Token 무효화
            pattern = f"refresh_token:{user_id}:*"
            keys = self.redis_client.keys(pattern)
            if keys:
                self.redis_client.delete(*keys)

    def revoke_all_tokens(self, user_id: str):
        """모든 토큰 무효화 (보안 이벤트 시)"""
        self.revoke_refresh_token(user_id)

        # Access Token Blacklist 추가 (만료될 때까지)
        # 실제 구현 시 Access Token도 Redis blacklist에 추가

    def _generate_token_id(self) -> str:
        """고유 Token ID 생성"""
        import uuid
        return str(uuid.uuid4())

    def _get_user_permissions(self, user_id: str) -> List[str]:
        """사용자 권한 조회 (DB에서)"""
        # 실제 구현 시 DB 조회
        return ['job:submit', 'node:view', 'data:read']


class InvalidTokenError(Exception):
    """토큰 검증 실패"""
    pass
```

**새 API 엔드포인트:** `auth_portal_4430/auth_api.py`

```python
from flask import Blueprint, request, jsonify
from token_service import TokenService, InvalidTokenError

auth_bp = Blueprint('auth', __name__)
token_service = TokenService()

@auth_bp.route('/api/auth/login', methods=['POST'])
def login():
    """
    로그인 및 토큰 발급

    Request Body:
        { "username": "...", "password": "..." }

    Returns:
        {
            "access_token": "...",
            "refresh_token": "...",
            "expires_in": 900
        }
    """
    data = request.get_json()
    username = data.get('username')
    password = data.get('password')

    # 사용자 인증 (기존 로직)
    user = authenticate_user(username, password)

    if not user:
        return jsonify({'error': 'Invalid credentials'}), 401

    # 토큰 발급
    access_token = token_service.generate_access_token(
        user['id'],
        user['permissions']
    )
    refresh_token = token_service.generate_refresh_token(user['id'])

    return jsonify({
        'access_token': access_token,
        'refresh_token': refresh_token,
        'expires_in': 900,  # 15분
        'user': {
            'id': user['id'],
            'username': user['username'],
            'permissions': user['permissions']
        }
    }), 200


@auth_bp.route('/api/auth/refresh', methods=['POST'])
def refresh():
    """
    Access Token 갱신

    Request Body:
        { "refresh_token": "..." }

    Returns:
        {
            "access_token": "...",
            "expires_in": 900
        }
    """
    data = request.get_json()
    refresh_token = data.get('refresh_token')

    if not refresh_token:
        return jsonify({'error': 'Refresh token required'}), 400

    try:
        result = token_service.refresh_access_token(refresh_token)
        return jsonify(result), 200

    except InvalidTokenError as e:
        return jsonify({'error': str(e)}), 401


@auth_bp.route('/api/auth/logout', methods=['POST'])
def logout():
    """
    로그아웃 (Refresh Token 무효화)

    Headers:
        Authorization: Bearer <access_token>

    Request Body:
        { "refresh_token": "..." }  (선택)

    Returns:
        { "message": "Logged out successfully" }
    """
    # Access Token에서 user_id 추출
    auth_header = request.headers.get('Authorization')
    if not auth_header:
        return jsonify({'error': 'Authorization required'}), 401

    try:
        token = auth_header.split(' ')[1]
        payload = jwt.decode(token, token_service.secret_key, algorithms=['HS256'])
        user_id = payload['user_id']

        # Refresh Token 무효화
        data = request.get_json() or {}
        refresh_token = data.get('refresh_token')

        if refresh_token:
            # 특정 토큰만 무효화
            refresh_payload = jwt.decode(refresh_token, token_service.secret_key, algorithms=['HS256'])
            token_id = refresh_payload.get('token_id')
            token_service.revoke_refresh_token(user_id, token_id)
        else:
            # 모든 Refresh Token 무효화
            token_service.revoke_refresh_token(user_id)

        return jsonify({'message': 'Logged out successfully'}), 200

    except Exception as e:
        return jsonify({'error': str(e)}), 401
```

### 4.2 CORS Configuration (Production)

**수정:** `backend_5010/app.py`

```python
from flask_cors import CORS
import os

# 환경 변수로 CORS 설정 제어
FLASK_ENV = os.getenv('FLASK_ENV', 'development')
ALLOWED_ORIGINS = os.getenv('ALLOWED_ORIGINS', '').split(',')

if FLASK_ENV == 'development':
    # 개발 환경 - 모든 origin 허용
    CORS(app, origins='*', supports_credentials=True)
else:
    # 프로덕션 - 특정 origin만 허용
    if not ALLOWED_ORIGINS or ALLOWED_ORIGINS == ['']:
        raise ValueError("ALLOWED_ORIGINS must be set in production")

    CORS(app,
         origins=ALLOWED_ORIGINS,
         supports_credentials=True,
         allow_headers=['Content-Type', 'Authorization', 'X-Requested-With'],
         expose_headers=['X-Total-Count', 'X-Page-Count', 'Content-Disposition'],
         methods=['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS', 'PATCH'],
         max_age=3600)  # Preflight cache 1시간
```

**환경 변수 설정:** `.env.production`

```bash
FLASK_ENV=production
ALLOWED_ORIGINS=https://dashboard.example.com,https://cae.example.com,https://auth.example.com
JWT_SECRET_KEY=<강력한-시크릿-키>
REDIS_HOST=localhost
REDIS_PORT=6379
```

### 4.3 Rate Limiting

**새 파일:** `backend_5010/middleware/rate_limiter.py`

```python
from flask import request, jsonify
from functools import wraps
import redis
import time

class RateLimiter:
    def __init__(self, redis_client):
        self.redis = redis_client

    def limit(self, max_requests: int, window: int):
        """
        Rate Limiting 데코레이터

        Args:
            max_requests: 최대 요청 수
            window: 시간 윈도우 (초)

        Example:
            @rate_limiter.limit(max_requests=100, window=60)  # 분당 100회
            def my_endpoint():
                ...
        """
        def decorator(f):
            @wraps(f)
            def wrapped(*args, **kwargs):
                # 클라이언트 식별 (IP 또는 User ID)
                client_id = self._get_client_id()
                key = f"rate_limit:{f.__name__}:{client_id}"

                # 현재 요청 수 확인
                current = self.redis.get(key)

                if current and int(current) >= max_requests:
                    return jsonify({
                        'error': 'Rate limit exceeded',
                        'retry_after': self.redis.ttl(key)
                    }), 429

                # 카운터 증가
                pipe = self.redis.pipeline()
                pipe.incr(key)
                pipe.expire(key, window)
                pipe.execute()

                return f(*args, **kwargs)

            return wrapped
        return decorator

    def _get_client_id(self) -> str:
        """클라이언트 식별자 추출"""
        # JWT에서 user_id 추출 (인증된 사용자)
        auth_header = request.headers.get('Authorization')
        if auth_header:
            try:
                token = auth_header.split(' ')[1]
                payload = jwt.decode(token, JWT_SECRET, algorithms=['HS256'])
                return f"user:{payload['user_id']}"
            except:
                pass

        # IP 주소로 fallback
        return f"ip:{request.remote_addr}"


# 사용 예제
redis_client = redis.Redis(host='localhost', port=6379, db=0)
rate_limiter = RateLimiter(redis_client)

@app.route('/api/jobs/submit', methods=['POST'])
@jwt_required
@rate_limiter.limit(max_requests=10, window=60)  # 분당 10회
def submit_job():
    # Job 제출 로직
    pass

@app.route('/api/apptainer/scan', methods=['POST'])
@jwt_required
@rate_limiter.limit(max_requests=5, window=300)  # 5분당 5회 (무거운 작업)
def scan_apptainer():
    # 이미지 스캔 로직
    pass
```

### 4.4 API Key Management

**새 파일:** `backend_5010/api_key_service.py`

```python
import secrets
import hashlib
from datetime import datetime, timedelta
from typing import Optional, List

class APIKeyService:
    """
    외부 프론트엔드용 API Key 관리
    """

    def __init__(self, db_connection):
        self.db = db_connection

    def create_api_key(
        self,
        user_id: str,
        name: str,
        permissions: List[str],
        expires_in_days: int = 90
    ) -> dict:
        """
        API Key 생성

        Args:
            user_id: 사용자 ID
            name: API Key 이름 (용도 식별)
            permissions: 권한 목록
            expires_in_days: 유효 기간 (일)

        Returns:
            {
                "api_key": "sk_live_...",  # 한 번만 표시
                "key_id": "...",
                "created_at": "...",
                "expires_at": "..."
            }
        """
        # API Key 생성 (32바이트 랜덤)
        api_key = f"sk_live_{secrets.token_urlsafe(32)}"

        # 해시 저장 (원본은 저장하지 않음)
        key_hash = hashlib.sha256(api_key.encode()).hexdigest()

        # DB 저장
        cursor = self.db.cursor()
        expires_at = datetime.utcnow() + timedelta(days=expires_in_days)

        cursor.execute('''
            INSERT INTO api_keys (
                user_id, name, key_hash, permissions,
                created_at, expires_at, is_active
            ) VALUES (?, ?, ?, ?, datetime('now'), ?, 1)
        ''', (user_id, name, key_hash, ','.join(permissions), expires_at))

        key_id = cursor.lastrowid
        self.db.commit()

        return {
            'api_key': api_key,  # ⚠️ 한 번만 표시, 다시 조회 불가
            'key_id': key_id,
            'created_at': datetime.utcnow().isoformat(),
            'expires_at': expires_at.isoformat()
        }

    def validate_api_key(self, api_key: str) -> Optional[dict]:
        """
        API Key 검증

        Args:
            api_key: API Key

        Returns:
            { "user_id": "...", "permissions": [...] } 또는 None
        """
        key_hash = hashlib.sha256(api_key.encode()).hexdigest()

        cursor = self.db.cursor()
        cursor.execute('''
            SELECT user_id, permissions, expires_at, is_active
            FROM api_keys
            WHERE key_hash = ?
        ''', (key_hash,))

        row = cursor.fetchone()

        if not row:
            return None

        # 만료 확인
        expires_at = datetime.fromisoformat(row['expires_at'])
        if datetime.utcnow() > expires_at:
            return None

        # 활성화 확인
        if not row['is_active']:
            return None

        # 마지막 사용 시간 업데이트
        cursor.execute('''
            UPDATE api_keys
            SET last_used_at = datetime('now')
            WHERE key_hash = ?
        ''', (key_hash,))
        self.db.commit()

        return {
            'user_id': row['user_id'],
            'permissions': row['permissions'].split(',')
        }

    def revoke_api_key(self, key_id: int, user_id: str) -> bool:
        """API Key 무효화"""
        cursor = self.db.cursor()
        cursor.execute('''
            UPDATE api_keys
            SET is_active = 0, revoked_at = datetime('now')
            WHERE id = ? AND user_id = ?
        ''', (key_id, user_id))
        self.db.commit()
        return cursor.rowcount > 0

    def list_api_keys(self, user_id: str) -> List[dict]:
        """사용자의 API Key 목록 조회"""
        cursor = self.db.cursor()
        cursor.execute('''
            SELECT id, name, created_at, expires_at, last_used_at, is_active
            FROM api_keys
            WHERE user_id = ?
            ORDER BY created_at DESC
        ''', (user_id,))

        return [dict(row) for row in cursor.fetchall()]
```

**API 엔드포인트:** `backend_5010/api_key_api.py`

```python
from flask import Blueprint, request, jsonify

api_key_bp = Blueprint('api_keys', __name__)

@api_key_bp.route('/api/v2/api-keys', methods=['POST'])
@jwt_required
def create_api_key():
    """
    API Key 생성

    Request Body:
        {
            "name": "External CAE App",
            "permissions": ["job:submit", "job:view"],
            "expires_in_days": 90
        }
    """
    data = request.get_json()
    user_id = g.user_id

    result = api_key_service.create_api_key(
        user_id=user_id,
        name=data['name'],
        permissions=data['permissions'],
        expires_in_days=data.get('expires_in_days', 90)
    )

    return jsonify(result), 201


@api_key_bp.route('/api/v2/api-keys', methods=['GET'])
@jwt_required
def list_api_keys():
    """API Key 목록 조회"""
    user_id = g.user_id
    keys = api_key_service.list_api_keys(user_id)
    return jsonify({'api_keys': keys}), 200


@api_key_bp.route('/api/v2/api-keys/<int:key_id>', methods=['DELETE'])
@jwt_required
def revoke_api_key(key_id: int):
    """API Key 무효화"""
    user_id = g.user_id
    success = api_key_service.revoke_api_key(key_id, user_id)

    if success:
        return jsonify({'message': 'API key revoked'}), 200
    else:
        return jsonify({'error': 'API key not found'}), 404
```

**Middleware:** API Key 인증 지원

```python
from functools import wraps

def api_key_required(f):
    """API Key 인증 데코레이터"""
    @wraps(f)
    def decorated(*args, **kwargs):
        # Header에서 API Key 추출
        api_key = request.headers.get('X-API-Key')

        if not api_key:
            return jsonify({'error': 'API Key required'}), 401

        # API Key 검증
        auth_info = api_key_service.validate_api_key(api_key)

        if not auth_info:
            return jsonify({'error': 'Invalid or expired API Key'}), 401

        # Request context에 사용자 정보 저장
        g.user_id = auth_info['user_id']
        g.permissions = auth_info['permissions']
        g.auth_method = 'api_key'

        return f(*args, **kwargs)

    return decorated


# 사용 예제
@app.route('/api/v2/upload/external', methods=['POST'])
@api_key_required
@permission_required(['job:submit'])
def external_upload():
    """외부 프론트엔드에서 API Key로 접근"""
    # 파일 업로드 로직
    pass
```

### 4.5 DB 마이그레이션

**새 파일:** `backend_5010/migrations/v4.4.0_security.sql`

```sql
-- ============================================
-- v4.4.0: Security & Infrastructure
-- 작성일: 2025-11-05
-- 설명: API Key 관리 및 보안 강화
-- ============================================

-- API Keys 테이블
CREATE TABLE IF NOT EXISTS api_keys (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id TEXT NOT NULL,
    name TEXT NOT NULL,                    -- API Key 이름
    key_hash TEXT NOT NULL UNIQUE,         -- SHA-256 해시
    permissions TEXT NOT NULL,             -- 쉼표로 구분된 권한

    created_at TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    last_used_at TEXT,
    revoked_at TEXT,

    is_active INTEGER DEFAULT 1,           -- 0: 비활성, 1: 활성

    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_api_keys_user_id ON api_keys(user_id);
CREATE INDEX IF NOT EXISTS idx_api_keys_key_hash ON api_keys(key_hash);
CREATE INDEX IF NOT EXISTS idx_api_keys_active ON api_keys(is_active, expires_at);

-- Audit Log 테이블 (보안 이벤트 추적)
CREATE TABLE IF NOT EXISTS audit_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id TEXT,
    action TEXT NOT NULL,                  -- login, logout, api_call, etc.
    resource TEXT,                         -- 접근한 리소스
    method TEXT,                           -- HTTP method
    ip_address TEXT,
    user_agent TEXT,

    status_code INTEGER,                   -- HTTP status
    error_message TEXT,

    timestamp TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_user_id ON audit_logs(user_id, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON audit_logs(action, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_timestamp ON audit_logs(timestamp DESC);

-- Security Events 테이블 (의심스러운 활동)
CREATE TABLE IF NOT EXISTS security_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id TEXT,
    event_type TEXT NOT NULL,              -- failed_login, rate_limit, invalid_token
    severity TEXT NOT NULL,                -- low, medium, high, critical
    description TEXT,
    ip_address TEXT,

    detected_at TEXT NOT NULL DEFAULT (datetime('now')),
    resolved_at TEXT,
    is_resolved INTEGER DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_security_events_user_id ON security_events(user_id, detected_at DESC);
CREATE INDEX IF NOT EXISTS idx_security_events_severity ON security_events(severity, is_resolved);
```

### 4.6 Redis 설치 및 설정

**Setup 스크립트:** `cluster/setup/phase4_security.sh`

```bash
#!/bin/bash

# ============================================
# Phase 4: Security & Infrastructure Setup
# ============================================

set -euo pipefail

log_info() { echo "[INFO] $1"; }
log_success() { echo "[SUCCESS] ✅ $1"; }
log_error() { echo "[ERROR] ❌ $1" >&2; }

log_info "Phase 4: Security & Infrastructure Setup"

# 1. Redis 설치
log_info "Installing Redis..."
sudo apt-get update
sudo apt-get install -y redis-server

# Redis 설정
sudo systemctl enable redis-server
sudo systemctl start redis-server

# Redis 비밀번호 설정
REDIS_PASSWORD=$(openssl rand -base64 32)
sudo sed -i "s/# requirepass foobared/requirepass $REDIS_PASSWORD/" /etc/redis/redis.conf
sudo systemctl restart redis-server

log_success "Redis installed and configured"

# 2. JWT Secret Key 생성
log_info "Generating JWT Secret Key..."
JWT_SECRET=$(openssl rand -base64 64)

# 환경 변수 저장
cat > /home/koopark/web_services/backend/.env.security <<EOF
JWT_SECRET_KEY=$JWT_SECRET
JWT_ACCESS_TOKEN_TTL=900
JWT_REFRESH_TOKEN_TTL=604800
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=$REDIS_PASSWORD
FLASK_ENV=production
ALLOWED_ORIGINS=https://dashboard.example.com,https://cae.example.com
EOF

log_success "Security environment variables configured"

# 3. DB 마이그레이션
log_info "Running security migrations..."
cd /home/koopark/web_services/backend
python3 run_migrations.py

log_success "Security migrations completed"

# 4. 서비스 재시작
log_info "Restarting services..."
sudo systemctl restart dashboard_backend
sudo systemctl restart auth_backend

log_success "Phase 4 completed!"
```

### 4.7 배포 체크리스트

- [ ] Redis 설치 및 설정
- [ ] `token_service.py` 구현 및 테스트
- [ ] `auth_api.py` 엔드포인트 구현
- [ ] JWT Refresh Token 플로우 테스트
- [ ] Rate Limiting 구현 및 테스트
- [ ] API Key 관리 시스템 구현
- [ ] CORS 설정 업데이트
- [ ] Audit Log 시스템 구현
- [ ] DB 마이그레이션 v4.4.0 실행
- [ ] 보안 테스트 (침투 테스트 시뮬레이션)
- [ ] Frontend 로그인/로그아웃 플로우 업데이트
- [ ] 문서화 (API Key 사용 가이드)

---

## ⚡ Phase 5: Performance Optimization (우선순위 3)

**목표:** 백엔드/프론트엔드 성능 최적화
**예상 기간:** 1.5주
**의존성:** 없음 (독립적 구현 가능)

### 5.1 Backend Async Processing

**목적:** SSH 기반 노드 조회를 병렬 처리하여 응답 속도 향상

**수정:** `backend_5010/slurm_utils_async.py`

```python
import asyncio
import asyncssh
from typing import List, Dict, Optional
import logging

logger = logging.getLogger(__name__)

class AsyncSlurmClient:
    """
    비동기 Slurm 클라이언트

    SSH 연결을 병렬로 처리하여 다수의 노드 정보를
    빠르게 조회합니다.
    """

    def __init__(self, ssh_username: str = 'slurm'):
        self.ssh_username = ssh_username
        self.connection_pool = {}

    async def get_node_info_async(self, nodes: List[str]) -> Dict[str, dict]:
        """
        병렬 노드 정보 조회

        Args:
            nodes: 노드 리스트

        Returns:
            { "node001": {...}, "node002": {...}, ... }
        """
        tasks = [self._query_node(node) for node in nodes]
        results = await asyncio.gather(*tasks, return_exceptions=True)

        return {
            node: result if not isinstance(result, Exception) else None
            for node, result in zip(nodes, results)
        }

    async def _query_node(self, node: str) -> dict:
        """
        단일 노드 정보 조회

        Args:
            node: 노드 이름

        Returns:
            노드 정보 딕셔너리
        """
        try:
            async with asyncssh.connect(
                node,
                username=self.ssh_username,
                known_hosts=None,
                client_keys=['/home/slurm/.ssh/id_rsa']
            ) as conn:
                # sinfo 실행
                result = await conn.run(
                    f'sinfo -n {node} -o "%C,%m,%t,%O,%E"',
                    check=True
                )

                return self._parse_sinfo(result.stdout)

        except asyncssh.Error as e:
            logger.error(f"SSH connection failed for {node}: {e}")
            return None
        except Exception as e:
            logger.error(f"Error querying node {node}: {e}")
            return None

    def _parse_sinfo(self, output: str) -> dict:
        """sinfo 출력 파싱"""
        # CPUs, Memory, State, CPUsLoad, Reason 파싱
        parts = output.strip().split(',')

        if len(parts) < 3:
            return {}

        cpus = parts[0]  # "4/0/0/4" (allocated/idle/other/total)
        memory = parts[1]
        state = parts[2]

        return {
            'cpus': cpus,
            'memory': int(memory) if memory.isdigit() else 0,
            'state': state,
            'load': parts[3] if len(parts) > 3 else 'N/A',
            'reason': parts[4] if len(parts) > 4 else ''
        }

    async def submit_multiple_jobs(self, jobs: List[dict]) -> List[str]:
        """
        병렬 작업 제출

        Args:
            jobs: Job 설정 리스트

        Returns:
            Job ID 리스트
        """
        tasks = [self._submit_job(job) for job in jobs]
        job_ids = await asyncio.gather(*tasks, return_exceptions=True)

        return [
            job_id if not isinstance(job_id, Exception) else None
            for job_id in job_ids
        ]

    async def _submit_job(self, job: dict) -> str:
        """
        단일 작업 제출

        Args:
            job: Job 설정

        Returns:
            Job ID
        """
        try:
            script = self._generate_job_script(job)

            async with asyncssh.connect(
                'slurmctld',
                username=self.ssh_username,
                known_hosts=None
            ) as conn:
                result = await conn.run('sbatch', input=script, check=True)
                return self._extract_job_id(result.stdout)

        except Exception as e:
            logger.error(f"Job submission failed: {e}")
            raise

    def _generate_job_script(self, job: dict) -> str:
        """Job 스크립트 생성"""
        return f"""#!/bin/bash
#SBATCH --job-name={job['name']}
#SBATCH --partition={job['partition']}
#SBATCH --nodes={job['nodes']}
#SBATCH --ntasks={job['tasks']}
#SBATCH --time={job['time']}

{job['command']}
"""

    def _extract_job_id(self, output: str) -> str:
        """sbatch 출력에서 Job ID 추출"""
        # "Submitted batch job 12345" -> "12345"
        import re
        match = re.search(r'Submitted batch job (\d+)', output)
        return match.group(1) if match else None


# Flask에서 사용
async_slurm = AsyncSlurmClient()

@app.route('/api/nodes/status', methods=['GET'])
async def get_nodes_status():
    """
    모든 노드 상태 조회 (비동기)

    기존 동기 방식 (4 nodes × 2s = 8s)
    → 비동기 방식 (max 2s)
    """
    nodes = ['node001', 'node002', 'viz-node001', 'viz-node002']

    results = await async_slurm.get_node_info_async(nodes)

    return jsonify({
        'nodes': results,
        'total': len(nodes),
        'online': sum(1 for v in results.values() if v and v.get('state') != 'down')
    }), 200
```

### 5.2 Database Query Optimization

**목적:** 자주 조회되는 쿼리 최적화 및 인덱스 추가

**새 마이그레이션:** `backend_5010/migrations/v4.5.0_performance.sql`

```sql
-- ============================================
-- v4.5.0: Performance Optimization
-- 작성일: 2025-11-05
-- 설명: DB 인덱스 최적화 및 쿼리 성능 개선
-- ============================================

-- 복합 인덱스 추가

-- 알림 조회 최적화 (사용자별 미읽은 알림)
CREATE INDEX IF NOT EXISTS idx_notifications_user_read_time
ON notifications(created_by, read, timestamp DESC);

-- 템플릿 조회 최적화 (카테고리별 공개 템플릿)
CREATE INDEX IF NOT EXISTS idx_templates_category_public
ON job_templates_v2(category, is_public, created_at DESC);

-- Job 히스토리 조회 최적화 (사용자별 상태별 정렬)
CREATE INDEX IF NOT EXISTS idx_jobs_user_status_time
ON job_history(user_id, status, submit_time DESC);

-- 업로드 세션 조회 최적화
CREATE INDEX IF NOT EXISTS idx_uploads_user_status_time
ON file_uploads(user_id, status, created_at DESC);

-- Apptainer 이미지 조회 최적화 (파티션별)
CREATE INDEX IF NOT EXISTS idx_apptainer_partition_type
ON apptainer_images(partition, type, name);

-- Audit Log 조회 최적화
CREATE INDEX IF NOT EXISTS idx_audit_user_time
ON audit_logs(user_id, timestamp DESC);

CREATE INDEX IF NOT EXISTS idx_audit_action_time
ON audit_logs(action, timestamp DESC);

-- 쿼리 성능 분석 (실행 계획 확인)
-- EXPLAIN QUERY PLAN SELECT * FROM notifications WHERE created_by = 'user123' AND read = 0 ORDER BY timestamp DESC LIMIT 20;

-- 통계 정보 업데이트
ANALYZE;
```

**쿼리 최적화 예제:**

```python
# ❌ 비효율적 쿼리 (N+1 문제)
def get_jobs_with_templates():
    jobs = db.execute("SELECT * FROM job_history").fetchall()
    for job in jobs:
        template = db.execute(
            "SELECT * FROM job_templates_v2 WHERE template_id = ?",
            (job['template_id'],)
        ).fetchone()
        job['template'] = template
    return jobs

# ✅ 최적화된 쿼리 (JOIN 사용)
def get_jobs_with_templates_optimized():
    return db.execute("""
        SELECT
            j.*,
            t.name as template_name,
            t.category as template_category
        FROM job_history j
        LEFT JOIN job_templates_v2 t ON j.template_id = t.template_id
        ORDER BY j.submit_time DESC
        LIMIT 50
    """).fetchall()
```

### 5.3 Frontend Code Splitting

**목적:** 번들 크기 최적화로 초기 로딩 속도 개선

**수정:** `frontend_3010/vite.config.ts`

```typescript
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { visualizer } from 'rollup-plugin-visualizer';

export default defineConfig({
  plugins: [
    react(),
    visualizer({
      filename: './dist/stats.html',
      open: false,
      gzipSize: true,
      brotliSize: true
    })
  ],
  build: {
    rollupOptions: {
      output: {
        manualChunks: {
          // Vendor chunks (라이브러리 분리)
          'react-vendor': ['react', 'react-dom', 'react-router-dom'],
          'ui-vendor': ['lucide-react', '@heroicons/react', 'clsx'],
          'state-vendor': ['zustand'],
          'chart-vendor': ['recharts'],
          '3d-vendor': ['three', '@react-three/fiber', '@react-three/drei'],

          // Feature chunks (페이지별 분리)
          'job-management': [
            './src/pages/JobManagement.tsx',
            './src/components/JobSubmit',
            './src/components/JobTemplates'
          ],
          'node-management': [
            './src/pages/NodeManagement.tsx',
            './src/components/NodeStatus'
          ],
          'ssh-vnc': [
            './src/components/SSHSessionManager.tsx',
            './src/components/VNCSessionManager.tsx'
          ],
          'data-management': [
            './src/pages/DataManagement.tsx',
            './src/components/FileUpload'
          ],
          'monitoring': [
            './src/pages/Dashboard.tsx',
            './src/components/Monitoring'
          ]
        }
      }
    },
    chunkSizeWarningLimit: 1000,  // 1MB
    minify: 'esbuild',
    target: 'es2020',
    sourcemap: false  // Production에서는 sourcemap 비활성화
  },
  optimizeDeps: {
    include: ['react', 'react-dom', 'react-router-dom']
  }
});
```

**Lazy Loading 적용:**

```typescript
// ❌ 모든 컴포넌트를 한 번에 로드
import JobManagement from './pages/JobManagement';
import NodeManagement from './pages/NodeManagement';
import DataManagement from './pages/DataManagement';

// ✅ 필요할 때만 로드 (Lazy Loading)
import { lazy, Suspense } from 'react';

const JobManagement = lazy(() => import('./pages/JobManagement'));
const NodeManagement = lazy(() => import('./pages/NodeManagement'));
const DataManagement = lazy(() => import('./pages/DataManagement'));
const SSHManager = lazy(() => import('./components/SSHSessionManager'));
const VNCManager = lazy(() => import('./components/VNCSessionManager'));

function App() {
  return (
    <Suspense fallback={<LoadingSpinner />}>
      <Routes>
        <Route path="/jobs" element={<JobManagement />} />
        <Route path="/nodes" element={<NodeManagement />} />
        <Route path="/data" element={<DataManagement />} />
        <Route path="/ssh" element={<SSHManager />} />
        <Route path="/vnc" element={<VNCManager />} />
      </Routes>
    </Suspense>
  );
}
```

### 5.4 Caching Strategy

**Backend 캐싱:**

```python
from functools import lru_cache
import time

class CacheManager:
    def __init__(self):
        self.cache = {}
        self.ttl = {}

    def get(self, key: str) -> Optional[any]:
        """캐시에서 데이터 조회"""
        if key not in self.cache:
            return None

        # TTL 확인
        if time.time() > self.ttl.get(key, 0):
            del self.cache[key]
            del self.ttl[key]
            return None

        return self.cache[key]

    def set(self, key: str, value: any, ttl: int = 60):
        """캐시에 데이터 저장"""
        self.cache[key] = value
        self.ttl[key] = time.time() + ttl

    def delete(self, key: str):
        """캐시 삭제"""
        self.cache.pop(key, None)
        self.ttl.pop(key, None)

cache = CacheManager()

@app.route('/api/nodes/status', methods=['GET'])
def get_nodes_status_cached():
    """노드 상태 조회 (30초 캐싱)"""
    cache_key = 'nodes:status'

    # 캐시 확인
    cached_data = cache.get(cache_key)
    if cached_data:
        return jsonify(cached_data), 200

    # 데이터 조회
    nodes = get_all_nodes_status()

    # 캐시 저장 (30초)
    cache.set(cache_key, nodes, ttl=30)

    return jsonify(nodes), 200
```

### 5.5 WebSocket Connection Pooling

**수정:** `websocket_5011/websocket_server.py`

```python
# 연결 풀 관리
class ConnectionPool:
    def __init__(self, max_connections: int = 1000):
        self.connections: Dict[str, web.WebSocketResponse] = {}
        self.max_connections = max_connections
        self.topics: Dict[str, Set[str]] = {}  # topic -> client_ids

    def add(self, client_id: str, ws: web.WebSocketResponse):
        """클라이언트 추가"""
        if len(self.connections) >= self.max_connections:
            raise ConnectionError("Max connections reached")

        self.connections[client_id] = ws

    def remove(self, client_id: str):
        """클라이언트 제거"""
        self.connections.pop(client_id, None)

        # 모든 topic에서 제거
        for topic_clients in self.topics.values():
            topic_clients.discard(client_id)

    def subscribe(self, client_id: str, topic: str):
        """Topic 구독"""
        if topic not in self.topics:
            self.topics[topic] = set()

        self.topics[topic].add(client_id)

    def unsubscribe(self, client_id: str, topic: str):
        """Topic 구독 해제"""
        if topic in self.topics:
            self.topics[topic].discard(client_id)

    async def broadcast_to_topic(self, topic: str, message: dict):
        """특정 topic 구독자에게만 브로드캐스트"""
        if topic not in self.topics:
            return

        client_ids = self.topics[topic].copy()

        for client_id in client_ids:
            ws = self.connections.get(client_id)
            if ws:
                try:
                    await ws.send_json(message)
                except Exception:
                    self.remove(client_id)


pool = ConnectionPool()

async def websocket_handler(request):
    """WebSocket 연결 핸들러"""
    ws = web.WebSocketResponse()
    await ws.prepare(request)

    client_id = str(uuid.uuid4())
    pool.add(client_id, ws)

    try:
        async for msg in ws:
            if msg.type == web.WSMsgType.TEXT:
                data = json.loads(msg.data)

                # Topic 구독
                if data.get('action') == 'subscribe':
                    pool.subscribe(client_id, data['topic'])

                # Topic 구독 해제
                elif data.get('action') == 'unsubscribe':
                    pool.unsubscribe(client_id, data['topic'])
    finally:
        pool.remove(client_id)

    return ws


# 사용 예제: 업로드 진행률을 upload topic 구독자에게만 전송
async def broadcast_upload_progress(upload_id: str, progress: int):
    await pool.broadcast_to_topic('upload', {
        'type': 'upload_progress',
        'upload_id': upload_id,
        'progress': progress
    })
```

### 5.6 배포 체크리스트

- [ ] Backend 비동기 처리 구현 (`slurm_utils_async.py`)
- [ ] DB 인덱스 최적화 (v4.5.0 마이그레이션)
- [ ] 쿼리 성능 분석 및 개선
- [ ] Frontend Code Splitting 적용
- [ ] Lazy Loading 구현
- [ ] 캐싱 전략 구현 (Backend/Frontend)
- [ ] WebSocket Connection Pooling
- [ ] 번들 크기 분석 (`stats.html` 확인)
- [ ] Lighthouse 성능 테스트 (목표: 90+ 점)
- [ ] Load Testing (목표: 100 concurrent users)
- [ ] 배포 및 성능 모니터링

---

## 🧪 Phase 6: Testing & Documentation (최종 단계)

**목표:** 테스트 코드 작성 및 문서화
**예상 기간:** 1주
**의존성:** Phase 1-5 완료 후

### 6.1 Backend Unit Tests

**새 디렉토리:** `backend_5010/tests/`

```bash
backend_5010/tests/
├── __init__.py
├── conftest.py                    # pytest fixtures
├── test_apptainer_service.py
├── test_template_manager.py
├── test_file_upload.py
├── test_auth_service.py
├── test_api_keys.py
└── test_async_slurm.py
```

**conftest.py - Test Fixtures**

```python
import pytest
import sqlite3
import tempfile
import os

@pytest.fixture
def test_db():
    """테스트용 임시 DB"""
    fd, path = tempfile.mkstemp(suffix='.db')
    conn = sqlite3.connect(path)
    conn.row_factory = sqlite3.Row

    # 테이블 생성 (마이그레이션 적용)
    with open('migrations/v4.1.0_apptainer_images.sql') as f:
        conn.executescript(f.read())

    yield conn

    conn.close()
    os.close(fd)
    os.unlink(path)


@pytest.fixture
def test_user():
    """테스트 사용자"""
    return {
        'id': 'test_user_001',
        'username': 'testuser',
        'permissions': ['job:submit', 'job:view']
    }
```

**test_file_upload.py**

```python
import pytest
from file_upload_api import file_upload_bp
from file_classifier import get_file_classifier

def test_file_classification():
    """파일 분류 테스트"""
    classifier = get_file_classifier()

    # Data 파일
    info = classifier.classify_file('dataset.tar.gz')
    assert info['type'] == 'data'
    assert info['is_compressed'] == True

    # Config 파일
    info = classifier.classify_file('config.yaml')
    assert info['type'] == 'config'
    assert info['is_binary'] == False

    # Model 파일
    info = classifier.classify_file('model_weights.pth')
    assert info['type'] == 'model'


def test_upload_init(client, test_user):
    """업로드 초기화 테스트"""
    response = client.post('/api/v2/files/upload/init', json={
        'filename': 'test.dat',
        'file_size': 1024000,
        'user_id': test_user['id']
    })

    assert response.status_code == 201
    data = response.get_json()
    assert 'upload_id' in data
    assert 'chunk_size' in data
    assert data['total_chunks'] > 0


def test_upload_large_file(client, test_user):
    """대용량 파일 업로드 테스트"""
    # 10GB 파일
    file_size = 10 * 1024 * 1024 * 1024

    response = client.post('/api/v2/files/upload/init', json={
        'filename': 'large_dataset.tar.gz',
        'file_size': file_size,
        'user_id': test_user['id']
    })

    assert response.status_code == 201
    data = response.get_json()

    # 5MB 청크 = 2000 청크
    assert data['total_chunks'] == 2000
    assert data['chunk_size'] == 5 * 1024 * 1024
```

### 6.2 Frontend Tests

**새 디렉토리:** `frontend_3010/src/__tests__/`

```bash
frontend_3010/src/__tests__/
├── components/
│   ├── ApptainerSelector.test.tsx
│   ├── UnifiedUploader.test.tsx
│   └── FileClassifier.test.tsx
├── hooks/
│   ├── useApptainerImages.test.ts
│   └── useFileUpload.test.ts
└── utils/
    └── ChunkUploader.test.ts
```

**UnifiedUploader.test.tsx**

```typescript
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { UnifiedUploader } from '../components/FileUpload/UnifiedUploader';

describe('UnifiedUploader', () => {
  it('renders upload interface', () => {
    render(
      <UnifiedUploader
        userId="test_user"
        onComplete={jest.fn()}
      />
    );

    expect(screen.getByText(/drag.*drop/i)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /select files/i })).toBeInTheDocument();
  });

  it('accepts file drag and drop', async () => {
    const onComplete = jest.fn();

    render(
      <UnifiedUploader
        userId="test_user"
        onComplete={onComplete}
      />
    );

    const dropzone = screen.getByTestId('dropzone');
    const file = new File(['test'], 'test.dat', { type: 'application/octet-stream' });

    fireEvent.drop(dropzone, {
      dataTransfer: {
        files: [file]
      }
    });

    await waitFor(() => {
      expect(screen.getByText('test.dat')).toBeInTheDocument();
    });
  });

  it('shows file classification', async () => {
    render(
      <UnifiedUploader
        userId="test_user"
        onComplete={jest.fn()}
      />
    );

    const files = [
      new File(['data'], 'input.dat'),
      new File(['config'], 'config.yaml'),
      new File(['script'], 'run.sh')
    ];

    // 파일 추가
    const input = screen.getByLabelText(/select files/i);
    fireEvent.change(input, { target: { files } });

    await waitFor(() => {
      expect(screen.getByText(/DATA Files \(1\)/i)).toBeInTheDocument();
      expect(screen.getByText(/CONFIG Files \(1\)/i)).toBeInTheDocument();
      expect(screen.getByText(/SCRIPT Files \(1\)/i)).toBeInTheDocument();
    });
  });

  it('shows upload progress', async () => {
    render(
      <UnifiedUploader
        userId="test_user"
        onComplete={jest.fn()}
      />
    );

    // 파일 업로드 시작
    const file = new File(['x'.repeat(10000000)], 'large.dat');
    const input = screen.getByLabelText(/select files/i);
    fireEvent.change(input, { target: { files: [file] } });

    const uploadButton = screen.getByRole('button', { name: /start upload/i });
    fireEvent.click(uploadButton);

    await waitFor(() => {
      expect(screen.getByRole('progressbar')).toBeInTheDocument();
    });
  });
});
```

### 6.3 E2E Tests (Playwright)

**새 디렉토리:** `tests/e2e/`

```bash
tests/e2e/
├── playwright.config.ts
├── auth.setup.ts
├── job-submit-flow.spec.ts
├── file-upload-flow.spec.ts
└── template-management.spec.ts
```

**job-submit-flow.spec.ts**

```typescript
import { test, expect } from '@playwright/test';

test.describe('Job Submit Flow', () => {
  test.beforeEach(async ({ page }) => {
    // 로그인
    await page.goto('http://localhost:3010/login');
    await page.fill('input[name="username"]', 'testuser');
    await page.fill('input[name="password"]', 'testpass');
    await page.click('button[type="submit"]');

    await expect(page).toHaveURL('http://localhost:3010/dashboard');
  });

  test('complete job submission with file upload', async ({ page }) => {
    // 1. Job Management 페이지로 이동
    await page.click('a[href="/jobs"]');
    await expect(page).toHaveURL('http://localhost:3010/jobs');

    // 2. 새 Job 생성
    await page.click('button:has-text("New Job")');

    // 3. 템플릿 선택
    await page.click('text=PyTorch Training');
    await page.click('button:has-text("Next")');

    // 4. 파일 업로드
    await page.setInputFiles('input[type="file"]', [
      'tests/fixtures/training_data.tar.gz',
      'tests/fixtures/config.yaml'
    ]);

    // 파일 분류 확인
    await expect(page.locator('text=DATA Files (1)')).toBeVisible();
    await expect(page.locator('text=CONFIG Files (1)')).toBeVisible();

    // 업로드 시작
    await page.click('button:has-text("Upload")');

    // 진행률 확인
    await expect(page.locator('role=progressbar')).toBeVisible();

    // 완료 대기
    await expect(page.locator('text=Upload completed')).toBeVisible({
      timeout: 60000
    });

    // 5. Job 설정
    await page.fill('input[name="job_name"]', 'Test Training Job');
    await page.selectOption('select[name="partition"]', 'compute');
    await page.fill('input[name="nodes"]', '2');

    // 6. Job 제출
    await page.click('button:has-text("Submit Job")');

    // 7. 제출 확인
    await expect(page.locator('text=Job submitted successfully')).toBeVisible();
    await expect(page).toHaveURL(/\/jobs\/\d+/);
  });

  test('handles upload errors gracefully', async ({ page }) => {
    await page.goto('http://localhost:3010/jobs/new');

    // 너무 큰 파일 업로드 시도 (60GB)
    await page.evaluate(() => {
      const input = document.querySelector('input[type="file"]');
      const file = new File(['x'.repeat(60 * 1024 * 1024 * 1024)], 'huge.dat');

      const dataTransfer = new DataTransfer();
      dataTransfer.items.add(file);
      input.files = dataTransfer.files;
    });

    // 에러 메시지 확인
    await expect(page.locator('text=File size exceeds maximum')).toBeVisible();
  });
});
```

### 6.4 API Documentation (OpenAPI/Swagger)

**새 파일:** `backend_5010/openapi.yaml`

```yaml
openapi: 3.0.0
info:
  title: Slurm Cluster Dashboard API
  version: 5.0.0
  description: |
    Dashboard API for Slurm cluster management

    ## Features
    - Apptainer image discovery
    - Template management
    - File upload with chunking
    - Job submission and monitoring
    - Authentication with JWT
  contact:
    name: Cluster Admin
    email: admin@example.com

servers:
  - url: http://localhost:5010
    description: Development
  - url: https://api.cluster.example.com
    description: Production

components:
  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer
      bearerFormat: JWT
    apiKeyAuth:
      type: apiKey
      in: header
      name: X-API-Key

  schemas:
    FileUploadInit:
      type: object
      required:
        - filename
        - file_size
        - user_id
      properties:
        filename:
          type: string
          example: "dataset.tar.gz"
        file_size:
          type: integer
          format: int64
          example: 10485760
        user_id:
          type: string
          example: "user_123"
        job_id:
          type: string
          nullable: true
          example: "job_456"
        chunk_size:
          type: integer
          default: 5242880
          example: 5242880

    FileUploadSession:
      type: object
      properties:
        upload_id:
          type: string
          example: "1652cdf37e4feb12"
        chunk_size:
          type: integer
          example: 5242880
        total_chunks:
          type: integer
          example: 2
        storage_path:
          type: string
          example: "/shared/uploads/jobs/job_456/data"
        file_info:
          $ref: '#/components/schemas/FileInfo'

    FileInfo:
      type: object
      properties:
        type:
          type: string
          enum: [data, config, script, model, mesh, result, document]
          example: "data"
        extension:
          type: string
          example: ".tar.gz"
        mime_type:
          type: string
          example: "application/x-tar"
        size:
          type: integer
          format: int64
          example: 10485760
        is_binary:
          type: boolean
          example: true
        is_compressed:
          type: boolean
          example: true

paths:
  /api/v2/files/upload/init:
    post:
      summary: Initialize file upload session
      tags:
        - File Upload
      security:
        - bearerAuth: []
        - apiKeyAuth: []
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/FileUploadInit'
      responses:
        '201':
          description: Upload session created
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/FileUploadSession'
        '400':
          description: Bad request
        '401':
          description: Unauthorized

  /api/v2/files/upload/chunk:
    post:
      summary: Upload file chunk
      tags:
        - File Upload
      security:
        - bearerAuth: []
        - apiKeyAuth: []
      requestBody:
        required: true
        content:
          multipart/form-data:
            schema:
              type: object
              required:
                - upload_id
                - chunk_index
                - chunk
              properties:
                upload_id:
                  type: string
                chunk_index:
                  type: integer
                chunk:
                  type: string
                  format: binary
                checksum:
                  type: string
                  description: MD5 checksum (optional)
      responses:
        '200':
          description: Chunk uploaded
          content:
            application/json:
              schema:
                type: object
                properties:
                  message:
                    type: string
                  uploaded_chunks:
                    type: integer
                  total_chunks:
                    type: integer
                  progress:
                    type: number
                    format: float

  /api/v2/files/upload/complete:
    post:
      summary: Complete file upload
      tags:
        - File Upload
      security:
        - bearerAuth: []
        - apiKeyAuth: []
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required:
                - upload_id
              properties:
                upload_id:
                  type: string
                verify_checksum:
                  type: boolean
                  default: false
      responses:
        '200':
          description: Upload completed
          content:
            application/json:
              schema:
                type: object
                properties:
                  message:
                    type: string
                  file_path:
                    type: string
                  file_info:
                    $ref: '#/components/schemas/FileInfo'
```

**Swagger UI 설정:**

```python
from flask_swagger_ui import get_swaggerui_blueprint

SWAGGER_URL = '/api/docs'
API_URL = '/static/openapi.yaml'

swaggerui_blueprint = get_swaggerui_blueprint(
    SWAGGER_URL,
    API_URL,
    config={
        'app_name': "Slurm Dashboard API"
    }
)

app.register_blueprint(swaggerui_blueprint, url_prefix=SWAGGER_URL)
```

### 6.5 User Documentation

**새 파일:** `docs/USER_GUIDE.md`

```markdown
# Slurm Dashboard User Guide

## 목차
1. [시작하기](#시작하기)
2. [Job 제출](#job-제출)
3. [파일 업로드](#파일-업로드)
4. [템플릿 관리](#템플릿-관리)
5. [API 사용법](#api-사용법)

## 시작하기

### 로그인
1. 브라우저에서 `http://dashboard.example.com` 접속
2. 사용자명과 비밀번호 입력
3. 로그인 성공 후 대시보드로 이동

### 대시보드 개요
- **왼쪽 메뉴**: 주요 기능 탐색
- **상단 바**: 알림, 프로필 설정
- **메인 영역**: 현재 페이지 컨텐츠

## Job 제출

### 기본 Job 제출
1. 왼쪽 메뉴에서 **"Job Management"** 클릭
2. **"New Job"** 버튼 클릭
3. 템플릿 선택 또는 **"Custom Job"** 선택
4. 필요한 파일 업로드
5. Job 설정 입력:
   - Job Name
   - Partition (compute/viz)
   - Nodes
   - Tasks per node
   - Time limit
6. **"Submit Job"** 클릭

### 템플릿 사용
템플릿을 사용하면 미리 정의된 설정으로 빠르게 Job을 제출할 수 있습니다.

1. Job 생성 시 **"Use Template"** 선택
2. 카테고리별 템플릿 탐색:
   - ML (Machine Learning)
   - CFD (Computational Fluid Dynamics)
   - Structural Analysis
3. 템플릿 선택 후 **"Next"** 클릭
4. 필요한 파일 업로드 (템플릿이 요구하는 파일 타입 확인)
5. Job 설정 확인 및 수정
6. **"Submit"** 클릭

## 파일 업로드

### 지원 파일 타입
- **Data**: .dat, .csv, .tar.gz, .hdf5, etc.
- **Config**: .yaml, .json, .toml, .ini
- **Script**: .py, .sh, .sbatch
- **Model**: .pth, .ckpt, .h5
- **Mesh**: .msh, .stl, .vtk

### 단일 파일 업로드
1. **"Select Files"** 버튼 클릭 또는 Drag & Drop
2. 파일 선택
3. 자동으로 파일 타입 분류됨
4. **"Start Upload"** 클릭

### 대용량 파일 업로드
- 최대 파일 크기: **50GB**
- 자동 청크 업로드 (5MB 단위)
- 실시간 진행률 표시
- 업로드 일시정지/재개 가능

### 다중 파일 업로드
1. 여러 파일을 동시에 선택 또는 드래그
2. 파일 타입별로 자동 분류
3. 각 파일의 업로드 진행률 개별 표시
4. 모든 파일 업로드 완료 후 Job 제출 가능

## 템플릿 관리

### 템플릿 생성
1. **"Templates"** 메뉴 클릭
2. **"Create Template"** 버튼 클릭
3. 템플릿 정보 입력:
   - Name
   - Category
   - Description
   - Required files
   - Slurm settings
4. **"Save"** 클릭

### 템플릿 공유
- **Private**: 본인만 사용 가능
- **Public**: 모든 사용자가 사용 가능

### YAML 템플릿 가져오기
1. 외부에서 작성한 YAML 파일 준비
2. **"Import Template"** 클릭
3. YAML 파일 선택
4. 자동으로 DB에 저장 및 Hot Reload

## API 사용법

### API Key 생성
1. 프로필 설정 → **"API Keys"** 클릭
2. **"Create New Key"** 클릭
3. Key 이름 및 권한 설정
4. 생성된 Key 복사 (⚠️ 한 번만 표시됨)

### API 호출 예제

**파일 업로드 (cURL):**
```bash
# 1. 업로드 세션 초기화
curl -X POST https://api.example.com/api/v2/files/upload/init \
  -H "X-API-Key: sk_live_YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "filename": "dataset.tar.gz",
    "file_size": 10485760,
    "user_id": "your_user_id"
  }'

# 2. 파일 업로드 (단일 청크)
curl -X POST https://api.example.com/api/v2/files/upload/chunk \
  -H "X-API-Key: sk_live_YOUR_API_KEY" \
  -F "upload_id=YOUR_UPLOAD_ID" \
  -F "chunk_index=0" \
  -F "chunk=@file.dat"

# 3. 업로드 완료
curl -X POST https://api.example.com/api/v2/files/upload/complete \
  -H "X-API-Key: sk_live_YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "upload_id": "YOUR_UPLOAD_ID"
  }'
```

**Python 예제:**
```python
import requests

API_KEY = "sk_live_YOUR_API_KEY"
BASE_URL = "https://api.example.com"

headers = {
    "X-API-Key": API_KEY,
    "Content-Type": "application/json"
}

# 업로드 초기화
response = requests.post(
    f"{BASE_URL}/api/v2/files/upload/init",
    headers=headers,
    json={
        "filename": "dataset.tar.gz",
        "file_size": 1024000,
        "user_id": "user_123"
    }
)

upload_id = response.json()["upload_id"]
print(f"Upload ID: {upload_id}")
```

## 문제 해결

### 업로드가 느린 경우
- 네트워크 상태 확인
- 파일을 압축하여 크기 줄이기
- 청크 크기 조정 (기본 5MB)

### Job이 제출되지 않는 경우
- 필수 파일이 모두 업로드되었는지 확인
- Partition 설정 확인 (compute/viz)
- 할당량(Quota) 확인

### 템플릿을 찾을 수 없는 경우
- 카테고리 필터 확인
- Private/Public 설정 확인
- 검색 키워드 변경

## 지원

문제가 계속되면 관리자에게 문의하세요:
- Email: support@example.com
- Slack: #cluster-support
```

### 6.6 배포 체크리스트

- [ ] Backend 단위 테스트 작성 (커버리지 80%+)
- [ ] Frontend 컴포넌트 테스트 작성
- [ ] E2E 테스트 시나리오 작성
- [ ] Playwright E2E 테스트 실행
- [ ] OpenAPI 스펙 작성
- [ ] Swagger UI 배포
- [ ] User Guide 작성
- [ ] API Documentation 작성
- [ ] Deployment Guide 작성
- [ ] Troubleshooting Guide 작성
- [ ] 모든 Phase 통합 테스트
- [ ] Production 배포 준비

---

## 📅 전체 일정 요약

| Phase | 목표 | 예상 기간 | 우선순위 | 상태 |
|-------|------|-----------|----------|------|
| Phase 1 | Apptainer Discovery | 2주 | ✅ 완료 | 2025-11-05 |
| Phase 2 | Template Management | 2주 | ✅ 완료 | 2025-11-05 |
| Phase 3 | File Upload (Backend) | 1.5주 | ✅ 완료 | 2025-11-05 |
| **Phase 3+** | **File Upload (Frontend)** | **3-4일** | **🔥 최우선** | ❌ 대기 |
| Phase 4 | Security & Infrastructure | 2주 | 2 | ❌ 대기 |
| Phase 5 | Performance Optimization | 1.5주 | 3 | ❌ 대기 |
| Phase 6 | Testing & Documentation | 1주 | 최종 | ❌ 대기 |

**총 예상 기간 (Phase 3+~6):** 약 4-5주

---

## 🎯 즉시 시작 가능한 작업

### 1순위: Phase 3 Frontend (3-4일)
Backend API가 완성되어 바로 Frontend 개발 시작 가능
- UnifiedUploader 컴포넌트
- 청크 업로드 UI
- WebSocket 진행률 표시

### 2순위: Phase 4 Security (2주)
독립적으로 구현 가능, 기존 시스템과 병렬 작업 가능
- JWT Refresh Token
- Redis 연동
- API Key 시스템

### 3순위: Phase 5 Performance (1.5주)
최적화는 기능 완성 후 진행 권장
- Backend 비동기 처리
- DB 쿼리 최적화
- Frontend Code Splitting

---

## 📝 개발 시작 전 체크리스트

### 환경 준비
- [ ] Git 최신 버전으로 체크아웃
- [ ] 현재 시스템 백업 (`git commit`)
- [ ] 개발 브랜치 생성 (`git checkout -b phase-X`)
- [ ] Node.js 및 Python 의존성 확인

### Phase 3 Frontend 시작 전
- [ ] Backend API 테스트 완료 확인
- [ ] WebSocket 서버 정상 동작 확인
- [ ] `/shared/uploads/` 디렉토리 권한 확인
- [ ] Frontend 개발 환경 설정

### Phase 4 Security 시작 전
- [ ] Redis 설치 계획 수립
- [ ] JWT Secret Key 생성 방법 결정
- [ ] 기존 인증 시스템 분석
- [ ] API Key 저장 방식 설계

---

## 🚨 주의사항

1. **Job Submit 기능 검증**: 각 Phase 완료 후 반드시 Job Submit이 정상 동작하는지 확인
2. **롤백 계획**: 각 Phase마다 Git 커밋으로 롤백 포인트 생성
3. **점진적 배포**: 한 번에 여러 Phase를 배포하지 말 것
4. **사용자 피드백**: Phase 3 Frontend 완료 후 실사용자 피드백 수집
5. **성능 모니터링**: Phase 5 이전에 현재 성능 기준치(Baseline) 측정

---

**다음 단계:** Phase 3 Frontend 구현 시작

```bash
# Phase 3 Frontend 개발 시작
cd /home/koopark/claude/KooSlurmInstallAutomationRefactory
git checkout -b phase-3-frontend
cd dashboard/frontend_3010
npm install
npm run dev
```
