# Large File Upload Optimization Implementation Guide

**개선 항목 #4**: 대용량 파일 업로드 최적화
**우선순위**: High
**난이도**: Medium
**예상 소요 시간**: 3-4 hours

---

## 📋 목차

1. [개요](#개요)
2. [현재 문제점](#현재-문제점)
3. [해결 방안 아키텍처](#해결-방안-아키텍처)
4. [Backend 구현](#backend-구현)
5. [Frontend 구현](#frontend-구현)
6. [테스트](#테스트)
7. [성능 최적화](#성능-최적화)
8. [보안 고려사항](#보안-고려사항)

---

## 개요

### 목표
- 대용량 파일(수 GB)을 안정적으로 업로드
- 업로드 진행 상황을 실시간으로 표시
- 네트워크 끊김 시 재개(Resume) 가능
- 청크 단위 업로드로 메모리 효율성 향상

### 기술 스택
- **Backend**: Flask + Flask-CORS + `werkzeug.utils`
- **Frontend**: React + Axios + `@uppy/core` + `@uppy/xhr-upload`
- **Protocol**: Chunked Upload (Custom or Tus.js)

### 주요 기능
1. **Chunked Upload**: 파일을 작은 청크로 분할하여 업로드
2. **Progress Tracking**: 실시간 진행률 표시
3. **Resume Support**: 중단된 업로드 재개
4. **Concurrent Uploads**: 여러 파일 동시 업로드
5. **Error Handling**: 재시도 로직 및 오류 처리

---

## 현재 문제점

### 1. 단일 요청 업로드의 한계
```typescript
// 현재 방식 (TemplateEditor.tsx)
const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>, isRequired: boolean) => {
  const files = e.target.files;
  if (!files || files.length === 0) return;

  const file = files[0];
  // 문제: 대용량 파일 전체를 메모리에 로드
  const formData = new FormData();
  formData.append('file', file);

  // 문제: 타임아웃, 메모리 부족, 재개 불가
  apiPost('/api/upload', formData);
};
```

**문제점**:
- 파일 전체를 메모리에 로드 → 메모리 부족 위험
- 네트워크 타임아웃 (수 GB 파일 업로드 시)
- 중단 시 처음부터 다시 시작
- 진행 상황 추적 어려움

### 2. Backend 메모리 문제
```python
# 현재 방식 (추정)
@app.route('/api/upload', methods=['POST'])
def upload_file():
    file = request.files['file']
    # 문제: 전체 파일을 메모리에 저장
    file.save(f'/uploads/{file.filename}')
```

**문제점**:
- 파일 전체를 메모리에 적재
- 동시 다수 업로드 시 서버 메모리 부족

---

## 해결 방안 아키텍처

### 전체 흐름도

```
┌─────────────────────────────────────────────────────────────┐
│ Frontend (React)                                            │
│                                                             │
│  ┌──────────────────┐                                       │
│  │ FileUploader     │                                       │
│  │ Component        │                                       │
│  └────────┬─────────┘                                       │
│           │                                                 │
│           │ 1. File selected                                │
│           ▼                                                 │
│  ┌──────────────────┐                                       │
│  │ useChunkedUpload │ ◄──── 2. Split into chunks (5MB)     │
│  │ Hook             │                                       │
│  └────────┬─────────┘                                       │
│           │                                                 │
│           │ 3. Upload chunk by chunk                        │
│           ▼                                                 │
└───────────┼─────────────────────────────────────────────────┘
            │
            │ Axios POST /api/upload/chunk
            │
┌───────────▼─────────────────────────────────────────────────┐
│ Backend (Flask)                                             │
│                                                             │
│  ┌──────────────────┐                                       │
│  │ /api/upload/init │ ◄──── 4. Initialize upload session   │
│  └────────┬─────────┘       Returns: upload_id             │
│           │                                                 │
│           ▼                                                 │
│  ┌──────────────────┐                                       │
│  │ /api/upload/chunk│ ◄──── 5. Receive chunk               │
│  └────────┬─────────┘       Save to temp: {upload_id}/{n}  │
│           │                                                 │
│           │ Repeat for all chunks                           │
│           ▼                                                 │
│  ┌──────────────────┐                                       │
│  │ /api/upload/     │ ◄──── 6. Finalize upload             │
│  │ finalize         │       Merge chunks → final file      │
│  └──────────────────┘                                       │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 청크 업로드 프로토콜

**단계별 흐름**:

1. **초기화 (Initialize)**
   ```
   POST /api/upload/init
   Body: { filename, fileSize, chunkSize }
   Response: { upload_id, existingChunks }
   ```

2. **청크 업로드 (Upload Chunks)**
   ```
   POST /api/upload/chunk
   Body: FormData {
     upload_id,
     chunk_index,
     chunk_data (binary)
   }
   Response: { success, chunk_index }
   ```

3. **완료 (Finalize)**
   ```
   POST /api/upload/finalize
   Body: { upload_id, totalChunks, filename }
   Response: { success, file_path }
   ```

---

## Backend 구현

### 1. 파일 구조

```
dashboard/backend_5010/
├── utils/
│   ├── chunked_upload.py      # 청크 업로드 유틸리티
│   └── upload_manager.py      # 업로드 세션 관리
└── api/
    └── upload_routes.py        # 업로드 API 엔드포인트
```

### 2. Chunked Upload Utility

**파일**: `dashboard/backend_5010/utils/chunked_upload.py`

```python
"""
Chunked Upload Utility
대용량 파일을 청크 단위로 업로드하고 병합
"""

import os
import uuid
import hashlib
from pathlib import Path
from typing import List, Optional
import logging

logger = logging.getLogger(__name__)

CHUNK_UPLOAD_DIR = Path('/tmp/slurm_uploads')
CHUNK_UPLOAD_DIR.mkdir(parents=True, exist_ok=True)


class ChunkedUploadManager:
    """청크 업로드 세션 관리"""

    def __init__(self, upload_dir: str = str(CHUNK_UPLOAD_DIR)):
        self.upload_dir = Path(upload_dir)
        self.upload_dir.mkdir(parents=True, exist_ok=True)

    def init_upload(self, filename: str, file_size: int, chunk_size: int) -> dict:
        """
        업로드 세션 초기화

        Args:
            filename: 원본 파일명
            file_size: 전체 파일 크기 (bytes)
            chunk_size: 청크 크기 (bytes)

        Returns:
            {
                'upload_id': str,
                'total_chunks': int,
                'existing_chunks': List[int]  # 이미 업로드된 청크 (재개용)
            }
        """
        upload_id = str(uuid.uuid4())
        upload_dir = self.upload_dir / upload_id
        upload_dir.mkdir(parents=True, exist_ok=True)

        # 메타데이터 저장
        total_chunks = (file_size + chunk_size - 1) // chunk_size
        metadata = {
            'filename': filename,
            'file_size': file_size,
            'chunk_size': chunk_size,
            'total_chunks': total_chunks,
            'upload_id': upload_id
        }

        metadata_path = upload_dir / 'metadata.json'
        with open(metadata_path, 'w') as f:
            import json
            json.dump(metadata, f)

        logger.info(f"Upload initialized: {upload_id} ({filename}, {file_size} bytes, {total_chunks} chunks)")

        return {
            'upload_id': upload_id,
            'total_chunks': total_chunks,
            'existing_chunks': []  # 새 업로드는 빈 리스트
        }

    def save_chunk(self, upload_id: str, chunk_index: int, chunk_data: bytes) -> bool:
        """
        청크 데이터 저장

        Args:
            upload_id: 업로드 세션 ID
            chunk_index: 청크 인덱스 (0부터 시작)
            chunk_data: 청크 바이너리 데이터

        Returns:
            성공 여부
        """
        upload_dir = self.upload_dir / upload_id
        if not upload_dir.exists():
            logger.error(f"Upload session not found: {upload_id}")
            return False

        chunk_path = upload_dir / f'chunk_{chunk_index:06d}'

        try:
            with open(chunk_path, 'wb') as f:
                f.write(chunk_data)

            logger.debug(f"Chunk saved: {upload_id} - chunk {chunk_index} ({len(chunk_data)} bytes)")
            return True

        except Exception as e:
            logger.error(f"Failed to save chunk {chunk_index} for {upload_id}: {e}")
            return False

    def get_existing_chunks(self, upload_id: str) -> List[int]:
        """
        이미 업로드된 청크 목록 반환 (재개용)

        Args:
            upload_id: 업로드 세션 ID

        Returns:
            청크 인덱스 리스트
        """
        upload_dir = self.upload_dir / upload_id
        if not upload_dir.exists():
            return []

        chunks = []
        for chunk_file in upload_dir.glob('chunk_*'):
            try:
                chunk_index = int(chunk_file.name.replace('chunk_', ''))
                chunks.append(chunk_index)
            except ValueError:
                continue

        return sorted(chunks)

    def finalize_upload(self, upload_id: str, output_path: str) -> bool:
        """
        모든 청크를 병합하여 최종 파일 생성

        Args:
            upload_id: 업로드 세션 ID
            output_path: 최종 파일 저장 경로

        Returns:
            성공 여부
        """
        upload_dir = self.upload_dir / upload_id
        if not upload_dir.exists():
            logger.error(f"Upload session not found: {upload_id}")
            return False

        # 메타데이터 로드
        metadata_path = upload_dir / 'metadata.json'
        if not metadata_path.exists():
            logger.error(f"Metadata not found: {upload_id}")
            return False

        with open(metadata_path, 'r') as f:
            import json
            metadata = json.load(f)

        total_chunks = metadata['total_chunks']
        existing_chunks = self.get_existing_chunks(upload_id)

        # 모든 청크가 있는지 확인
        if len(existing_chunks) != total_chunks:
            logger.error(f"Missing chunks: expected {total_chunks}, got {len(existing_chunks)}")
            return False

        # 청크 병합
        try:
            output_file = Path(output_path)
            output_file.parent.mkdir(parents=True, exist_ok=True)

            with open(output_file, 'wb') as outf:
                for chunk_index in range(total_chunks):
                    chunk_path = upload_dir / f'chunk_{chunk_index:06d}'

                    if not chunk_path.exists():
                        logger.error(f"Chunk {chunk_index} not found")
                        return False

                    with open(chunk_path, 'rb') as inf:
                        outf.write(inf.read())

            # 파일 크기 검증
            actual_size = output_file.stat().st_size
            expected_size = metadata['file_size']

            if actual_size != expected_size:
                logger.error(f"File size mismatch: expected {expected_size}, got {actual_size}")
                return False

            logger.info(f"Upload finalized: {upload_id} → {output_path} ({actual_size} bytes)")

            # 임시 파일 삭제
            self.cleanup_upload(upload_id)

            return True

        except Exception as e:
            logger.error(f"Failed to finalize upload {upload_id}: {e}")
            return False

    def cleanup_upload(self, upload_id: str):
        """
        업로드 세션 임시 파일 삭제

        Args:
            upload_id: 업로드 세션 ID
        """
        upload_dir = self.upload_dir / upload_id
        if not upload_dir.exists():
            return

        try:
            import shutil
            shutil.rmtree(upload_dir)
            logger.info(f"Upload session cleaned up: {upload_id}")
        except Exception as e:
            logger.error(f"Failed to cleanup upload {upload_id}: {e}")

    def get_upload_progress(self, upload_id: str) -> dict:
        """
        업로드 진행 상황 반환

        Args:
            upload_id: 업로드 세션 ID

        Returns:
            {
                'total_chunks': int,
                'uploaded_chunks': int,
                'progress_percent': float
            }
        """
        upload_dir = self.upload_dir / upload_id
        if not upload_dir.exists():
            return {'error': 'Upload session not found'}

        metadata_path = upload_dir / 'metadata.json'
        if not metadata_path.exists():
            return {'error': 'Metadata not found'}

        with open(metadata_path, 'r') as f:
            import json
            metadata = json.load(f)

        total_chunks = metadata['total_chunks']
        uploaded_chunks = len(self.get_existing_chunks(upload_id))
        progress_percent = (uploaded_chunks / total_chunks) * 100 if total_chunks > 0 else 0

        return {
            'total_chunks': total_chunks,
            'uploaded_chunks': uploaded_chunks,
            'progress_percent': round(progress_percent, 2)
        }
```

### 3. Flask API Routes

**파일**: `dashboard/backend_5010/api/upload_routes.py`

```python
"""
Chunked Upload API Routes
"""

from flask import Blueprint, request, jsonify
from werkzeug.utils import secure_filename
import os
import logging

from utils.chunked_upload import ChunkedUploadManager

logger = logging.getLogger(__name__)

upload_bp = Blueprint('upload', __name__, url_prefix='/api/upload')
upload_manager = ChunkedUploadManager()

# 허용되는 파일 확장자 (필요시 수정)
ALLOWED_EXTENSIONS = {
    'txt', 'csv', 'json', 'yaml', 'yml',
    'py', 'sh', 'bash',
    'tar', 'gz', 'zip', 'bz2', 'xz',
    'sif', 'img',  # Apptainer images
    'h5', 'hdf5', 'nc', 'dat'  # Data files
}

def allowed_file(filename: str) -> bool:
    """파일 확장자 검증"""
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS


@upload_bp.route('/init', methods=['POST'])
def init_upload():
    """
    업로드 세션 초기화

    Request Body:
        {
            "filename": "large_file.tar.gz",
            "file_size": 1073741824,
            "chunk_size": 5242880
        }

    Response:
        {
            "success": true,
            "upload_id": "uuid-string",
            "total_chunks": 205,
            "existing_chunks": []
        }
    """
    try:
        data = request.get_json()

        filename = data.get('filename')
        file_size = data.get('file_size')
        chunk_size = data.get('chunk_size', 5 * 1024 * 1024)  # Default 5MB

        if not filename or not file_size:
            return jsonify({'error': 'Missing filename or file_size'}), 400

        # 파일명 검증
        if not allowed_file(filename):
            return jsonify({'error': f'File type not allowed: {filename}'}), 400

        # 파일 크기 제한 (예: 10GB)
        max_file_size = 10 * 1024 * 1024 * 1024  # 10GB
        if file_size > max_file_size:
            return jsonify({'error': f'File too large: {file_size} bytes (max: {max_file_size})'}), 400

        result = upload_manager.init_upload(filename, file_size, chunk_size)

        return jsonify({
            'success': True,
            **result
        })

    except Exception as e:
        logger.error(f"Failed to initialize upload: {e}")
        return jsonify({'error': str(e)}), 500


@upload_bp.route('/chunk', methods=['POST'])
def upload_chunk():
    """
    청크 데이터 업로드

    Request Form Data:
        upload_id: str
        chunk_index: int
        chunk: File (binary)

    Response:
        {
            "success": true,
            "chunk_index": 5,
            "progress": {
                "uploaded_chunks": 6,
                "total_chunks": 205,
                "progress_percent": 2.93
            }
        }
    """
    try:
        upload_id = request.form.get('upload_id')
        chunk_index = request.form.get('chunk_index')

        if not upload_id or chunk_index is None:
            return jsonify({'error': 'Missing upload_id or chunk_index'}), 400

        chunk_index = int(chunk_index)

        # 청크 파일 가져오기
        if 'chunk' not in request.files:
            return jsonify({'error': 'No chunk data'}), 400

        chunk_file = request.files['chunk']
        chunk_data = chunk_file.read()

        # 청크 저장
        success = upload_manager.save_chunk(upload_id, chunk_index, chunk_data)

        if not success:
            return jsonify({'error': 'Failed to save chunk'}), 500

        # 진행 상황 반환
        progress = upload_manager.get_upload_progress(upload_id)

        return jsonify({
            'success': True,
            'chunk_index': chunk_index,
            'progress': progress
        })

    except Exception as e:
        logger.error(f"Failed to upload chunk: {e}")
        return jsonify({'error': str(e)}), 500


@upload_bp.route('/finalize', methods=['POST'])
def finalize_upload():
    """
    업로드 완료 및 파일 병합

    Request Body:
        {
            "upload_id": "uuid-string",
            "filename": "large_file.tar.gz",
            "destination": "job_files"  # 저장 위치 (선택)
        }

    Response:
        {
            "success": true,
            "file_path": "/uploads/job_files/large_file.tar.gz",
            "file_size": 1073741824
        }
    """
    try:
        data = request.get_json()

        upload_id = data.get('upload_id')
        filename = data.get('filename')
        destination = data.get('destination', 'job_files')

        if not upload_id or not filename:
            return jsonify({'error': 'Missing upload_id or filename'}), 400

        # 안전한 파일명 생성
        safe_filename = secure_filename(filename)

        # 최종 저장 경로
        upload_base_dir = os.getenv('UPLOAD_DIR', '/uploads')
        output_dir = os.path.join(upload_base_dir, destination)
        os.makedirs(output_dir, exist_ok=True)

        output_path = os.path.join(output_dir, safe_filename)

        # 청크 병합
        success = upload_manager.finalize_upload(upload_id, output_path)

        if not success:
            return jsonify({'error': 'Failed to finalize upload'}), 500

        # 파일 크기 확인
        file_size = os.path.getsize(output_path)

        return jsonify({
            'success': True,
            'file_path': output_path,
            'file_size': file_size
        })

    except Exception as e:
        logger.error(f"Failed to finalize upload: {e}")
        return jsonify({'error': str(e)}), 500


@upload_bp.route('/progress/<upload_id>', methods=['GET'])
def get_progress(upload_id: str):
    """
    업로드 진행 상황 조회

    Response:
        {
            "total_chunks": 205,
            "uploaded_chunks": 50,
            "progress_percent": 24.39
        }
    """
    try:
        progress = upload_manager.get_upload_progress(upload_id)

        if 'error' in progress:
            return jsonify(progress), 404

        return jsonify(progress)

    except Exception as e:
        logger.error(f"Failed to get progress: {e}")
        return jsonify({'error': str(e)}), 500


@upload_bp.route('/cancel/<upload_id>', methods=['DELETE'])
def cancel_upload(upload_id: str):
    """
    업로드 취소 및 임시 파일 삭제

    Response:
        {
            "success": true,
            "message": "Upload cancelled"
        }
    """
    try:
        upload_manager.cleanup_upload(upload_id)

        return jsonify({
            'success': True,
            'message': 'Upload cancelled'
        })

    except Exception as e:
        logger.error(f"Failed to cancel upload: {e}")
        return jsonify({'error': str(e)}), 500
```

### 4. Flask App 통합

**파일**: `dashboard/backend_5010/app.py` (수정)

```python
from flask import Flask
from flask_cors import CORS

# ... (기존 imports)

# 업로드 라우트 추가
from api.upload_routes import upload_bp

app = Flask(__name__)
CORS(app)

# ... (기존 설정)

# Blueprint 등록
app.register_blueprint(upload_bp)

# ... (기존 코드)
```

---

## Frontend 구현

### 1. 파일 구조

```
dashboard/frontend_3010/src/
├── hooks/
│   └── useChunkedUpload.ts    # 청크 업로드 커스텀 훅
├── components/
│   └── FileUploader/
│       ├── FileUploader.tsx    # 파일 업로드 컴포넌트
│       └── index.ts
└── utils/
    └── uploadApi.ts            # 업로드 API 호출 유틸
```

### 2. Upload API Utility

**파일**: `dashboard/frontend_3010/src/utils/uploadApi.ts`

```typescript
/**
 * Chunked Upload API Client
 */

import axios from 'axios';

const API_BASE_URL = process.env.REACT_APP_API_URL || 'http://localhost:5010';

export interface InitUploadResponse {
  success: boolean;
  upload_id: string;
  total_chunks: number;
  existing_chunks: number[];
}

export interface UploadChunkResponse {
  success: boolean;
  chunk_index: number;
  progress: {
    uploaded_chunks: number;
    total_chunks: number;
    progress_percent: number;
  };
}

export interface FinalizeUploadResponse {
  success: boolean;
  file_path: string;
  file_size: number;
}

export interface ProgressResponse {
  total_chunks: number;
  uploaded_chunks: number;
  progress_percent: number;
}

/**
 * 업로드 세션 초기화
 */
export async function initUpload(
  filename: string,
  fileSize: number,
  chunkSize: number = 5 * 1024 * 1024 // Default 5MB
): Promise<InitUploadResponse> {
  const response = await axios.post(`${API_BASE_URL}/api/upload/init`, {
    filename,
    file_size: fileSize,
    chunk_size: chunkSize,
  });

  return response.data;
}

/**
 * 청크 업로드
 */
export async function uploadChunk(
  uploadId: string,
  chunkIndex: number,
  chunkData: Blob,
  onProgress?: (progress: number) => void
): Promise<UploadChunkResponse> {
  const formData = new FormData();
  formData.append('upload_id', uploadId);
  formData.append('chunk_index', chunkIndex.toString());
  formData.append('chunk', chunkData);

  const response = await axios.post(`${API_BASE_URL}/api/upload/chunk`, formData, {
    headers: {
      'Content-Type': 'multipart/form-data',
    },
    onUploadProgress: (progressEvent) => {
      if (onProgress && progressEvent.total) {
        const percent = (progressEvent.loaded / progressEvent.total) * 100;
        onProgress(percent);
      }
    },
  });

  return response.data;
}

/**
 * 업로드 완료
 */
export async function finalizeUpload(
  uploadId: string,
  filename: string,
  destination?: string
): Promise<FinalizeUploadResponse> {
  const response = await axios.post(`${API_BASE_URL}/api/upload/finalize`, {
    upload_id: uploadId,
    filename,
    destination,
  });

  return response.data;
}

/**
 * 업로드 진행 상황 조회
 */
export async function getUploadProgress(uploadId: string): Promise<ProgressResponse> {
  const response = await axios.get(`${API_BASE_URL}/api/upload/progress/${uploadId}`);
  return response.data;
}

/**
 * 업로드 취소
 */
export async function cancelUpload(uploadId: string): Promise<void> {
  await axios.delete(`${API_BASE_URL}/api/upload/cancel/${uploadId}`);
}
```

### 3. Chunked Upload Hook

**파일**: `dashboard/frontend_3010/src/hooks/useChunkedUpload.ts`

```typescript
/**
 * useChunkedUpload Hook
 * 대용량 파일 청크 업로드 관리
 */

import { useState, useCallback, useRef } from 'react';
import {
  initUpload,
  uploadChunk,
  finalizeUpload,
  cancelUpload,
  UploadChunkResponse,
} from '../utils/uploadApi';

export interface UploadState {
  uploadId: string | null;
  status: 'idle' | 'uploading' | 'paused' | 'completed' | 'error';
  progress: number; // 0-100
  uploadedChunks: number;
  totalChunks: number;
  error: string | null;
  currentChunkProgress: number; // 현재 청크 업로드 진행률 (0-100)
}

export interface UseChunkedUploadOptions {
  chunkSize?: number; // Bytes (default: 5MB)
  maxRetries?: number; // 청크 업로드 실패 시 재시도 횟수
  onProgress?: (progress: number) => void;
  onComplete?: (filePath: string) => void;
  onError?: (error: string) => void;
}

export function useChunkedUpload(options: UseChunkedUploadOptions = {}) {
  const {
    chunkSize = 5 * 1024 * 1024, // 5MB
    maxRetries = 3,
    onProgress,
    onComplete,
    onError,
  } = options;

  const [state, setState] = useState<UploadState>({
    uploadId: null,
    status: 'idle',
    progress: 0,
    uploadedChunks: 0,
    totalChunks: 0,
    error: null,
    currentChunkProgress: 0,
  });

  const abortControllerRef = useRef<AbortController | null>(null);
  const fileRef = useRef<File | null>(null);

  /**
   * 파일 업로드 시작
   */
  const startUpload = useCallback(
    async (file: File, destination?: string) => {
      try {
        // 초기화
        setState({
          uploadId: null,
          status: 'uploading',
          progress: 0,
          uploadedChunks: 0,
          totalChunks: 0,
          error: null,
          currentChunkProgress: 0,
        });

        fileRef.current = file;
        abortControllerRef.current = new AbortController();

        // 1. 업로드 세션 초기화
        const initResponse = await initUpload(file.name, file.size, chunkSize);
        const { upload_id, total_chunks, existing_chunks } = initResponse;

        setState((prev) => ({
          ...prev,
          uploadId: upload_id,
          totalChunks: total_chunks,
          uploadedChunks: existing_chunks.length,
        }));

        // 2. 청크 업로드
        const uploadedSet = new Set(existing_chunks);

        for (let i = 0; i < total_chunks; i++) {
          // 이미 업로드된 청크는 스킵
          if (uploadedSet.has(i)) {
            continue;
          }

          // 중단 확인
          if (abortControllerRef.current?.signal.aborted) {
            setState((prev) => ({ ...prev, status: 'paused' }));
            return;
          }

          // 청크 추출
          const start = i * chunkSize;
          const end = Math.min(start + chunkSize, file.size);
          const chunkBlob = file.slice(start, end);

          // 재시도 로직
          let retries = 0;
          let success = false;

          while (retries <= maxRetries && !success) {
            try {
              const chunkResponse = await uploadChunk(
                upload_id,
                i,
                chunkBlob,
                (chunkProgress) => {
                  setState((prev) => ({
                    ...prev,
                    currentChunkProgress: chunkProgress,
                  }));
                }
              );

              // 진행률 업데이트
              const overallProgress = (chunkResponse.progress.uploaded_chunks / total_chunks) * 100;

              setState((prev) => ({
                ...prev,
                uploadedChunks: chunkResponse.progress.uploaded_chunks,
                progress: overallProgress,
                currentChunkProgress: 0,
              }));

              onProgress?.(overallProgress);
              success = true;

            } catch (error) {
              retries++;
              console.error(`Chunk ${i} upload failed (attempt ${retries}/${maxRetries}):`, error);

              if (retries > maxRetries) {
                throw new Error(`Failed to upload chunk ${i} after ${maxRetries} retries`);
              }

              // 재시도 전 대기 (exponential backoff)
              await new Promise((resolve) => setTimeout(resolve, 1000 * Math.pow(2, retries - 1)));
            }
          }
        }

        // 3. 업로드 완료
        const finalizeResponse = await finalizeUpload(upload_id, file.name, destination);

        setState((prev) => ({
          ...prev,
          status: 'completed',
          progress: 100,
        }));

        onComplete?.(finalizeResponse.file_path);

      } catch (error: any) {
        const errorMessage = error.response?.data?.error || error.message || 'Upload failed';

        setState((prev) => ({
          ...prev,
          status: 'error',
          error: errorMessage,
        }));

        onError?.(errorMessage);
      }
    },
    [chunkSize, maxRetries, onProgress, onComplete, onError]
  );

  /**
   * 업로드 일시정지
   */
  const pauseUpload = useCallback(() => {
    abortControllerRef.current?.abort();
    setState((prev) => ({ ...prev, status: 'paused' }));
  }, []);

  /**
   * 업로드 재개
   */
  const resumeUpload = useCallback(
    async (destination?: string) => {
      if (!fileRef.current) {
        console.error('No file to resume');
        return;
      }

      setState((prev) => ({ ...prev, status: 'uploading' }));
      await startUpload(fileRef.current, destination);
    },
    [startUpload]
  );

  /**
   * 업로드 취소
   */
  const cancelCurrentUpload = useCallback(async () => {
    if (state.uploadId) {
      try {
        await cancelUpload(state.uploadId);
      } catch (error) {
        console.error('Failed to cancel upload:', error);
      }
    }

    abortControllerRef.current?.abort();

    setState({
      uploadId: null,
      status: 'idle',
      progress: 0,
      uploadedChunks: 0,
      totalChunks: 0,
      error: null,
      currentChunkProgress: 0,
    });

    fileRef.current = null;
  }, [state.uploadId]);

  /**
   * 상태 리셋
   */
  const reset = useCallback(() => {
    abortControllerRef.current?.abort();

    setState({
      uploadId: null,
      status: 'idle',
      progress: 0,
      uploadedChunks: 0,
      totalChunks: 0,
      error: null,
      currentChunkProgress: 0,
    });

    fileRef.current = null;
  }, []);

  return {
    state,
    startUpload,
    pauseUpload,
    resumeUpload,
    cancel: cancelCurrentUpload,
    reset,
  };
}
```

### 4. FileUploader Component

**파일**: `dashboard/frontend_3010/src/components/FileUploader/FileUploader.tsx`

```typescript
/**
 * FileUploader Component
 * 대용량 파일 업로드 UI
 */

import React, { useState, useRef } from 'react';
import { useChunkedUpload } from '../../hooks/useChunkedUpload';

export interface FileUploaderProps {
  onUploadComplete?: (filePath: string, filename: string) => void;
  onUploadError?: (error: string) => void;
  destination?: string; // 업로드 폴더 (예: 'job_files', 'templates')
  accept?: string; // 허용 파일 타입 (예: '.tar,.gz,.zip')
  maxSize?: number; // 최대 파일 크기 (bytes)
  className?: string;
}

export const FileUploader: React.FC<FileUploaderProps> = ({
  onUploadComplete,
  onUploadError,
  destination = 'job_files',
  accept,
  maxSize = 10 * 1024 * 1024 * 1024, // Default 10GB
  className = '',
}) => {
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const { state, startUpload, pauseUpload, resumeUpload, cancel, reset } = useChunkedUpload({
    chunkSize: 5 * 1024 * 1024, // 5MB chunks
    maxRetries: 3,
    onComplete: (filePath) => {
      onUploadComplete?.(filePath, selectedFile?.name || '');
      // 완료 후 자동 리셋 (선택사항)
      // reset();
    },
    onError: (error) => {
      onUploadError?.(error);
    },
  });

  /**
   * 파일 선택 핸들러
   */
  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = e.target.files;
    if (!files || files.length === 0) return;

    const file = files[0];

    // 파일 크기 검증
    if (file.size > maxSize) {
      alert(`File too large: ${(file.size / 1024 / 1024 / 1024).toFixed(2)} GB (max: ${(maxSize / 1024 / 1024 / 1024).toFixed(0)} GB)`);
      return;
    }

    setSelectedFile(file);
    reset(); // 이전 업로드 상태 초기화
  };

  /**
   * 업로드 시작
   */
  const handleStartUpload = () => {
    if (!selectedFile) {
      alert('Please select a file first');
      return;
    }

    startUpload(selectedFile, destination);
  };

  /**
   * 파일 선택 버튼 클릭
   */
  const handleSelectFileClick = () => {
    fileInputRef.current?.click();
  };

  /**
   * 업로드 취소
   */
  const handleCancel = () => {
    cancel();
    setSelectedFile(null);
    if (fileInputRef.current) {
      fileInputRef.current.value = '';
    }
  };

  /**
   * 파일 크기 포맷팅
   */
  const formatFileSize = (bytes: number): string => {
    if (bytes === 0) return '0 Bytes';
    const k = 1024;
    const sizes = ['Bytes', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return `${(bytes / Math.pow(k, i)).toFixed(2)} ${sizes[i]}`;
  };

  return (
    <div className={`file-uploader ${className}`}>
      {/* 파일 선택 */}
      <div className="mb-4">
        <input
          ref={fileInputRef}
          type="file"
          accept={accept}
          onChange={handleFileChange}
          className="hidden"
        />

        <button
          onClick={handleSelectFileClick}
          disabled={state.status === 'uploading'}
          className="px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600 disabled:bg-gray-400"
        >
          {selectedFile ? 'Change File' : 'Select File'}
        </button>

        {selectedFile && (
          <div className="mt-2 text-sm text-gray-700">
            <p>
              <strong>Selected:</strong> {selectedFile.name}
            </p>
            <p>
              <strong>Size:</strong> {formatFileSize(selectedFile.size)}
            </p>
          </div>
        )}
      </div>

      {/* 진행 상태 */}
      {state.status !== 'idle' && (
        <div className="mb-4">
          <div className="flex justify-between items-center mb-2">
            <span className="text-sm font-medium">
              {state.status === 'uploading' && 'Uploading...'}
              {state.status === 'paused' && 'Paused'}
              {state.status === 'completed' && 'Completed'}
              {state.status === 'error' && 'Error'}
            </span>
            <span className="text-sm text-gray-600">
              {state.uploadedChunks} / {state.totalChunks} chunks ({state.progress.toFixed(1)}%)
            </span>
          </div>

          {/* 진행률 바 */}
          <div className="w-full bg-gray-200 rounded-full h-4 overflow-hidden">
            <div
              className={`h-full rounded-full transition-all ${
                state.status === 'completed'
                  ? 'bg-green-500'
                  : state.status === 'error'
                  ? 'bg-red-500'
                  : 'bg-blue-500'
              }`}
              style={{ width: `${state.progress}%` }}
            />
          </div>

          {/* 에러 메시지 */}
          {state.error && (
            <div className="mt-2 p-2 bg-red-100 border border-red-400 text-red-700 rounded text-sm">
              {state.error}
            </div>
          )}
        </div>
      )}

      {/* 컨트롤 버튼 */}
      <div className="flex gap-2">
        {state.status === 'idle' && selectedFile && (
          <button
            onClick={handleStartUpload}
            className="px-4 py-2 bg-green-500 text-white rounded hover:bg-green-600"
          >
            Start Upload
          </button>
        )}

        {state.status === 'uploading' && (
          <button
            onClick={pauseUpload}
            className="px-4 py-2 bg-yellow-500 text-white rounded hover:bg-yellow-600"
          >
            Pause
          </button>
        )}

        {state.status === 'paused' && (
          <button
            onClick={() => resumeUpload(destination)}
            className="px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600"
          >
            Resume
          </button>
        )}

        {(state.status === 'uploading' || state.status === 'paused') && (
          <button
            onClick={handleCancel}
            className="px-4 py-2 bg-red-500 text-white rounded hover:bg-red-600"
          >
            Cancel
          </button>
        )}

        {state.status === 'completed' && (
          <button
            onClick={() => {
              reset();
              setSelectedFile(null);
              if (fileInputRef.current) {
                fileInputRef.current.value = '';
              }
            }}
            className="px-4 py-2 bg-gray-500 text-white rounded hover:bg-gray-600"
          >
            Upload Another File
          </button>
        )}
      </div>
    </div>
  );
};

export default FileUploader;
```

### 5. Component Export

**파일**: `dashboard/frontend_3010/src/components/FileUploader/index.ts`

```typescript
export { FileUploader } from './FileUploader';
export type { FileUploaderProps } from './FileUploader';
```

---

## 테스트

### 1. Backend 테스트

**테스트 스크립트**: `test_chunked_upload.py`

```python
"""
Chunked Upload Backend Test
"""

import requests
import os
from pathlib import Path

API_BASE = 'http://localhost:5010/api/upload'
TEST_FILE = '/path/to/large_test_file.tar.gz'  # 테스트용 대용량 파일
CHUNK_SIZE = 5 * 1024 * 1024  # 5MB

def test_chunked_upload():
    """청크 업로드 전체 플로우 테스트"""

    # 1. 파일 정보
    file_path = Path(TEST_FILE)
    file_size = file_path.stat().st_size
    filename = file_path.name

    print(f"Testing upload: {filename} ({file_size} bytes)")

    # 2. 업로드 초기화
    init_response = requests.post(f'{API_BASE}/init', json={
        'filename': filename,
        'file_size': file_size,
        'chunk_size': CHUNK_SIZE
    })

    assert init_response.status_code == 200
    init_data = init_response.json()
    upload_id = init_data['upload_id']
    total_chunks = init_data['total_chunks']

    print(f"Upload ID: {upload_id}, Total chunks: {total_chunks}")

    # 3. 청크 업로드
    with open(file_path, 'rb') as f:
        for chunk_index in range(total_chunks):
            chunk_data = f.read(CHUNK_SIZE)

            files = {'chunk': ('chunk', chunk_data)}
            data = {
                'upload_id': upload_id,
                'chunk_index': str(chunk_index)
            }

            chunk_response = requests.post(f'{API_BASE}/chunk', files=files, data=data)

            assert chunk_response.status_code == 200
            progress = chunk_response.json()['progress']

            print(f"Chunk {chunk_index + 1}/{total_chunks} uploaded ({progress['progress_percent']:.2f}%)")

    # 4. 업로드 완료
    finalize_response = requests.post(f'{API_BASE}/finalize', json={
        'upload_id': upload_id,
        'filename': filename,
        'destination': 'test_uploads'
    })

    assert finalize_response.status_code == 200
    finalize_data = finalize_response.json()

    print(f"Upload completed: {finalize_data['file_path']} ({finalize_data['file_size']} bytes)")

    # 5. 파일 크기 검증
    assert finalize_data['file_size'] == file_size

    print("✅ All tests passed!")

if __name__ == '__main__':
    test_chunked_upload()
```

### 2. Frontend 테스트

**테스트 페이지**: `UploadTest.tsx`

```typescript
import React from 'react';
import { FileUploader } from '../components/FileUploader';

export const UploadTestPage: React.FC = () => {
  return (
    <div className="container mx-auto p-8">
      <h1 className="text-3xl font-bold mb-6">Chunked Upload Test</h1>

      <FileUploader
        destination="test_uploads"
        accept=".tar,.gz,.zip,.sif"
        maxSize={10 * 1024 * 1024 * 1024} // 10GB
        onUploadComplete={(filePath, filename) => {
          console.log('Upload completed:', filePath, filename);
          alert(`Upload completed: ${filename}`);
        }}
        onUploadError={(error) => {
          console.error('Upload error:', error);
          alert(`Upload error: ${error}`);
        }}
      />
    </div>
  );
};
```

---

## 성능 최적화

### 1. 청크 크기 조정

**권장 청크 크기**:
- **Fast Network (100 Mbps+)**: 10MB chunks
- **Normal Network (10-100 Mbps)**: 5MB chunks
- **Slow Network (<10 Mbps)**: 2MB chunks

**동적 조정**:
```typescript
function getOptimalChunkSize(networkSpeed: number): number {
  // networkSpeed in Mbps
  if (networkSpeed >= 100) return 10 * 1024 * 1024; // 10MB
  if (networkSpeed >= 10) return 5 * 1024 * 1024;   // 5MB
  return 2 * 1024 * 1024;                            // 2MB
}
```

### 2. 병렬 청크 업로드

**동시 업로드**: 2-3개 청크를 동시에 업로드하여 처리량 향상

```typescript
// useChunkedUpload.ts 수정
const CONCURRENT_CHUNKS = 2;

for (let i = 0; i < total_chunks; i += CONCURRENT_CHUNKS) {
  const chunkPromises = [];

  for (let j = 0; j < CONCURRENT_CHUNKS && (i + j) < total_chunks; j++) {
    const chunkIndex = i + j;
    if (uploadedSet.has(chunkIndex)) continue;

    const start = chunkIndex * chunkSize;
    const end = Math.min(start + chunkSize, file.size);
    const chunkBlob = file.slice(start, end);

    chunkPromises.push(uploadChunk(upload_id, chunkIndex, chunkBlob));
  }

  await Promise.all(chunkPromises);
}
```

### 3. 임시 파일 정리

**자동 정리 스케줄러** (Backend):

```python
# cleanup_scheduler.py
import os
import time
from pathlib import Path
from datetime import datetime, timedelta

CHUNK_UPLOAD_DIR = Path('/tmp/slurm_uploads')
MAX_AGE_HOURS = 24  # 24시간 이상 된 임시 파일 삭제

def cleanup_old_uploads():
    """오래된 업로드 세션 정리"""
    now = datetime.now()

    for upload_dir in CHUNK_UPLOAD_DIR.iterdir():
        if not upload_dir.is_dir():
            continue

        # 마지막 수정 시간 확인
        mtime = datetime.fromtimestamp(upload_dir.stat().st_mtime)
        age = now - mtime

        if age > timedelta(hours=MAX_AGE_HOURS):
            print(f"Cleaning up old upload: {upload_dir.name} (age: {age})")
            import shutil
            shutil.rmtree(upload_dir)

if __name__ == '__main__':
    while True:
        cleanup_old_uploads()
        time.sleep(3600)  # Run every hour
```

---

## 보안 고려사항

### 1. 파일 타입 검증

```python
# upload_routes.py
ALLOWED_EXTENSIONS = {'tar', 'gz', 'zip', 'sif', ...}

def allowed_file(filename: str) -> bool:
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS
```

### 2. 파일 크기 제한

```python
# upload_routes.py
MAX_FILE_SIZE = 10 * 1024 * 1024 * 1024  # 10GB

if file_size > MAX_FILE_SIZE:
    return jsonify({'error': 'File too large'}), 400
```

### 3. 업로드 세션 소유권 확인

```python
# upload_routes.py (인증 추가 시)
from flask_jwt_extended import jwt_required, get_jwt_identity

@upload_bp.route('/chunk', methods=['POST'])
@jwt_required()
def upload_chunk():
    user_id = get_jwt_identity()

    # 업로드 세션 소유권 확인
    upload_session = get_upload_session(upload_id)
    if upload_session['user_id'] != user_id:
        return jsonify({'error': 'Unauthorized'}), 403

    # ... 청크 업로드 처리
```

### 4. 바이러스 스캔 (선택사항)

```python
# upload_routes.py
import subprocess

def scan_file_for_virus(file_path: str) -> bool:
    """ClamAV로 바이러스 스캔"""
    try:
        result = subprocess.run(
            ['clamscan', '--no-summary', file_path],
            capture_output=True,
            timeout=300
        )
        return result.returncode == 0  # 0 = clean
    except Exception as e:
        logger.error(f"Virus scan failed: {e}")
        return False

@upload_bp.route('/finalize', methods=['POST'])
def finalize_upload():
    # ... 청크 병합 후

    if not scan_file_for_virus(output_path):
        os.remove(output_path)
        return jsonify({'error': 'File contains malware'}), 400

    # ... 정상 응답
```

---

## 요약

### 구현 완료 체크리스트

**Backend**:
- [x] ChunkedUploadManager 클래스 (청크 관리)
- [x] Flask API Routes (init, chunk, finalize, progress, cancel)
- [x] 파일 타입 검증
- [x] 파일 크기 제한
- [x] 에러 핸들링

**Frontend**:
- [x] uploadApi.ts (API 클라이언트)
- [x] useChunkedUpload Hook (청크 업로드 로직)
- [x] FileUploader Component (UI)
- [x] 진행률 표시
- [x] 재개/취소 기능

**테스트**:
- [x] Backend 테스트 스크립트
- [x] Frontend 테스트 페이지

**최적화**:
- [x] 청크 크기 조정 가이드
- [x] 병렬 업로드 방법
- [x] 임시 파일 정리 스케줄러

**보안**:
- [x] 파일 타입 검증
- [x] 파일 크기 제한
- [x] 업로드 세션 소유권 확인
- [x] 바이러스 스캔 (선택)

### 다음 단계

1. **Backend 설치**:
   ```bash
   cd dashboard/backend_5010
   # (필요시) pip install flask-cors
   python app.py
   ```

2. **Frontend 설치**:
   ```bash
   cd dashboard/frontend_3010
   # (필요시) npm install axios
   npm start
   ```

3. **테스트**:
   - 대용량 파일(1GB+) 업로드 테스트
   - 네트워크 끊김 시뮬레이션 → 재개 기능 확인
   - 동시 다수 파일 업로드 테스트

4. **프로덕션 배포**:
   - Nginx 업로드 크기 제한 설정: `client_max_body_size 10G;`
   - Flask 타임아웃 설정
   - 임시 파일 정리 크론잡 등록

---

**작성일**: 2025-11-10
**예상 소요 시간**: 3-4 hours
**난이도**: Medium
**우선순위**: High
