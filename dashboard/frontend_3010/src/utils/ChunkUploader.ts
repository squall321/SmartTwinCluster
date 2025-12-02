/**
 * Chunk Uploader Utility
 * 대용량 파일을 청크 단위로 업로드
 */

import { ChunkUploadOptions, UploadSession } from '../types/upload';

// JWT 토큰 관리 함수
function getJwtToken(): string | null {
  return localStorage.getItem('jwt_token');
}

// Authorization 헤더 생성
function getAuthHeaders(): HeadersInit {
  const token = getJwtToken();
  return token ? { 'Authorization': `Bearer ${token}` } : {};
}

export interface ChunkUploadState {
  uploadId: string;
  filename: string;
  totalChunks: number;
  uploadedChunks: number;
  isUploading: boolean;
  isPaused: boolean;
  error?: Error;
}

class ChunkUploader {
  private uploadStates: Map<string, ChunkUploadState> = new Map();
  private abortControllers: Map<string, AbortController> = new Map();

  /**
   * 파일 업로드 세션 초기화
   */
  async initUpload(
    filename: string,
    fileSize: number,
    userId: string,
    jobId?: string
  ): Promise<UploadSession> {
    const response = await fetch('/api/v2/files/upload/init', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...getAuthHeaders()
      },
      body: JSON.stringify({
        filename,
        file_size: fileSize,
        user_id: userId,
        job_id: jobId
      })
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.error || 'Upload initialization failed');
    }

    return await response.json();
  }

  /**
   * 파일을 청크 단위로 업로드
   */
  async uploadFile(options: ChunkUploadOptions): Promise<void> {
    const { file, uploadId, chunkSize, onProgress, onError, signal } = options;

    const totalChunks = Math.ceil(file.size / chunkSize);

    // 업로드 상태 초기화
    this.uploadStates.set(uploadId, {
      uploadId,
      filename: file.name,
      totalChunks,
      uploadedChunks: 0,
      isUploading: true,
      isPaused: false
    });

    // AbortController 저장
    if (signal) {
      const controller = new AbortController();
      this.abortControllers.set(uploadId, controller);

      signal.addEventListener('abort', () => {
        controller.abort();
      });
    }

    try {
      for (let i = 0; i < totalChunks; i++) {
        // 취소 확인
        if (signal?.aborted) {
          throw new Error('Upload cancelled');
        }

        // 일시정지 확인
        while (this.uploadStates.get(uploadId)?.isPaused) {
          await new Promise(resolve => setTimeout(resolve, 100));
        }

        const start = i * chunkSize;
        const end = Math.min(start + chunkSize, file.size);
        const chunk = file.slice(start, end);

        // 청크 업로드 (최대 3회 재시도)
        await this.uploadChunkWithRetry(uploadId, chunk, i, 3);

        // 진행률 업데이트
        const state = this.uploadStates.get(uploadId);
        if (state) {
          state.uploadedChunks = i + 1;
          onProgress((state.uploadedChunks / state.totalChunks) * 100);
        }
      }

      // 업로드 완료
      await this.completeUpload(uploadId);

      // 상태 정리
      const state = this.uploadStates.get(uploadId);
      if (state) {
        state.isUploading = false;
      }

    } catch (error) {
      const state = this.uploadStates.get(uploadId);
      if (state) {
        state.isUploading = false;
        state.error = error as Error;
      }
      onError(error as Error);
      throw error;
    } finally {
      this.abortControllers.delete(uploadId);
    }
  }

  /**
   * 단일 청크 업로드 (재시도 포함)
   */
  private async uploadChunkWithRetry(
    uploadId: string,
    chunk: Blob,
    index: number,
    maxRetries: number
  ): Promise<void> {
    let lastError: Error | null = null;

    for (let attempt = 0; attempt < maxRetries; attempt++) {
      try {
        await this.uploadChunk(uploadId, chunk, index);
        return; // 성공
      } catch (error) {
        lastError = error as Error;
        console.warn(`Chunk ${index} upload failed (attempt ${attempt + 1}/${maxRetries}):`, error);

        // 마지막 시도가 아니면 대기 후 재시도
        if (attempt < maxRetries - 1) {
          await new Promise(resolve => setTimeout(resolve, 1000 * (attempt + 1)));
        }
      }
    }

    throw lastError || new Error(`Chunk ${index} upload failed after ${maxRetries} attempts`);
  }

  /**
   * 단일 청크 업로드
   */
  private async uploadChunk(
    uploadId: string,
    chunk: Blob,
    index: number
  ): Promise<void> {
    const formData = new FormData();
    formData.append('upload_id', uploadId);
    formData.append('chunk_index', index.toString());
    formData.append('chunk', chunk);

    // MD5 체크섬 계산 (선택적)
    // const checksum = await this.calculateMD5(chunk);
    // formData.append('checksum', checksum);

    const controller = this.abortControllers.get(uploadId);

    const response = await fetch('/api/v2/files/upload/chunk', {
      method: 'POST',
      headers: {
        ...getAuthHeaders()
      },
      body: formData,
      signal: controller?.signal
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.error || `Chunk ${index} upload failed`);
    }
  }

  /**
   * 업로드 완료 처리
   */
  async completeUpload(uploadId: string): Promise<any> {
    const response = await fetch('/api/v2/files/upload/complete', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...getAuthHeaders()
      },
      body: JSON.stringify({
        upload_id: uploadId
      })
    });

    if (!response.ok) {
      const error = await response.json();
      throw new Error(error.error || 'Upload completion failed');
    }

    return await response.json();
  }

  /**
   * 업로드 일시정지
   */
  pauseUpload(uploadId: string): void {
    const state = this.uploadStates.get(uploadId);
    if (state) {
      state.isPaused = true;
    }
  }

  /**
   * 업로드 재개
   */
  resumeUpload(uploadId: string): void {
    const state = this.uploadStates.get(uploadId);
    if (state) {
      state.isPaused = false;
    }
  }

  /**
   * 업로드 취소
   */
  async cancelUpload(uploadId: string): Promise<void> {
    // AbortController로 진행 중인 요청 취소
    const controller = this.abortControllers.get(uploadId);
    if (controller) {
      controller.abort();
    }

    // 서버에 취소 요청
    try {
      await fetch(`/api/v2/files/uploads/${uploadId}`, {
        method: 'DELETE',
        headers: {
          ...getAuthHeaders()
        }
      });
    } catch (error) {
      console.error('Failed to cancel upload on server:', error);
    }

    // 상태 정리
    this.uploadStates.delete(uploadId);
    this.abortControllers.delete(uploadId);
  }

  /**
   * 업로드 상태 조회
   */
  getUploadState(uploadId: string): ChunkUploadState | undefined {
    return this.uploadStates.get(uploadId);
  }

  /**
   * MD5 체크섬 계산 (선택적)
   */
  private async calculateMD5(blob: Blob): Promise<string> {
    // 간단한 구현 (실제로는 crypto-js 등 사용)
    const buffer = await blob.arrayBuffer();
    const hashBuffer = await crypto.subtle.digest('SHA-256', buffer);
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
  }
}

// 싱글톤 인스턴스
export const chunkUploader = new ChunkUploader();

export default ChunkUploader;
