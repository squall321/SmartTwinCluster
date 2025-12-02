/**
 * useFileUpload Hook
 * 파일 업로드 상태 관리 및 API 호출
 */

import { useState, useCallback, useRef } from 'react';
import { chunkUploader } from '../utils/ChunkUploader';
import { UploadedFile, UploadSession } from '../types/upload';

export interface FileUploadOptions {
  userId: string;
  jobId?: string;
  chunkSize?: number;
  onFileComplete?: (file: UploadedFile) => void;
  onAllComplete?: (files: UploadedFile[]) => void;
  onError?: (error: Error, filename: string) => void;
}

export interface FileUploadState {
  uploadId: string;
  filename: string;
  progress: number;
  status: 'pending' | 'uploading' | 'completed' | 'error' | 'cancelled';
  error?: string;
  session?: UploadSession;
  result?: UploadedFile;
}

export interface UseFileUploadResult {
  uploadFiles: (files: File[]) => Promise<void>;
  uploadStates: Map<string, FileUploadState>;
  isUploading: boolean;
  cancelUpload: (filename: string) => void;
  pauseUpload: (filename: string) => void;
  resumeUpload: (filename: string) => void;
  clearCompleted: () => void;
  error: Error | null;
}

export const useFileUpload = (options: FileUploadOptions): UseFileUploadResult => {
  const { userId, jobId, chunkSize = 5 * 1024 * 1024, onFileComplete, onAllComplete, onError } = options;

  const [uploadStates, setUploadStates] = useState<Map<string, FileUploadState>>(new Map());
  const [error, setError] = useState<Error | null>(null);
  const abortControllersRef = useRef<Map<string, AbortController>>(new Map());

  /**
   * 업로드 상태 업데이트
   */
  const updateUploadState = useCallback((filename: string, updates: Partial<FileUploadState>) => {
    setUploadStates(prev => {
      const newStates = new Map(prev);
      const currentState = newStates.get(filename);

      if (currentState) {
        newStates.set(filename, { ...currentState, ...updates });
      }

      return newStates;
    });
  }, []);

  /**
   * 단일 파일 업로드
   */
  const uploadSingleFile = useCallback(async (file: File): Promise<UploadedFile | null> => {
    try {
      // 1. 업로드 세션 초기화
      const session = await chunkUploader.initUpload(
        file.name,
        file.size,
        userId,
        jobId
      );

      // 업로드 상태 초기화
      setUploadStates(prev => {
        const newStates = new Map(prev);
        newStates.set(file.name, {
          uploadId: session.upload_id,
          filename: file.name,
          progress: 0,
          status: 'uploading',
          session
        });
        return newStates;
      });

      // 2. AbortController 생성
      const controller = new AbortController();
      abortControllersRef.current.set(file.name, controller);

      // 3. 청크 업로드 시작
      await chunkUploader.uploadFile({
        file,
        uploadId: session.upload_id,
        chunkSize: session.chunk_size,
        onProgress: (progress) => {
          updateUploadState(file.name, { progress });
        },
        onError: (error) => {
          updateUploadState(file.name, {
            status: 'error',
            error: error.message
          });
          onError?.(error, file.name);
        },
        signal: controller.signal
      });

      // 4. 업로드 완료된 파일 정보 조회
      const response = await fetch(`/api/v2/files/uploads/${session.upload_id}`);
      if (!response.ok) {
        throw new Error('Failed to get upload info');
      }

      const uploadedFile: UploadedFile = await response.json();

      // 완료 상태 업데이트
      updateUploadState(file.name, {
        status: 'completed',
        progress: 100,
        result: uploadedFile
      });

      // 콜백 호출
      onFileComplete?.(uploadedFile);

      // AbortController 정리
      abortControllersRef.current.delete(file.name);

      return uploadedFile;

    } catch (error) {
      const err = error as Error;

      if (err.message !== 'Upload cancelled') {
        updateUploadState(file.name, {
          status: 'error',
          error: err.message
        });
        onError?.(err, file.name);
        setError(err);
      }

      return null;
    }
  }, [userId, jobId, chunkSize, onFileComplete, onError, updateUploadState]);

  /**
   * 여러 파일 업로드
   */
  const uploadFiles = useCallback(async (files: File[]): Promise<void> => {
    setError(null);

    const results: UploadedFile[] = [];

    // 순차적으로 업로드 (병렬 업로드도 가능하지만 서버 부하 고려)
    for (const file of files) {
      const result = await uploadSingleFile(file);
      if (result) {
        results.push(result);
      }
    }

    // 모든 파일 완료 콜백
    if (results.length > 0) {
      onAllComplete?.(results);
    }
  }, [uploadSingleFile, onAllComplete]);

  /**
   * 업로드 취소
   */
  const cancelUpload = useCallback((filename: string) => {
    const state = uploadStates.get(filename);

    if (state && state.uploadId) {
      // AbortController로 취소
      const controller = abortControllersRef.current.get(filename);
      if (controller) {
        controller.abort();
      }

      // 서버에 취소 요청
      chunkUploader.cancelUpload(state.uploadId);

      // 상태 업데이트
      updateUploadState(filename, {
        status: 'cancelled'
      });

      // 정리
      abortControllersRef.current.delete(filename);
    }
  }, [uploadStates, updateUploadState]);

  /**
   * 업로드 일시정지
   */
  const pauseUpload = useCallback((filename: string) => {
    const state = uploadStates.get(filename);

    if (state && state.uploadId) {
      chunkUploader.pauseUpload(state.uploadId);
      updateUploadState(filename, { status: 'pending' });
    }
  }, [uploadStates, updateUploadState]);

  /**
   * 업로드 재개
   */
  const resumeUpload = useCallback((filename: string) => {
    const state = uploadStates.get(filename);

    if (state && state.uploadId) {
      chunkUploader.resumeUpload(state.uploadId);
      updateUploadState(filename, { status: 'uploading' });
    }
  }, [uploadStates, updateUploadState]);

  /**
   * 완료된 업로드 상태 정리
   */
  const clearCompleted = useCallback(() => {
    setUploadStates(prev => {
      const newStates = new Map(prev);

      for (const [filename, state] of newStates.entries()) {
        if (state.status === 'completed' || state.status === 'cancelled') {
          newStates.delete(filename);
        }
      }

      return newStates;
    });
  }, []);

  /**
   * 업로드 중인지 확인
   */
  const isUploading = Array.from(uploadStates.values()).some(
    state => state.status === 'uploading'
  );

  return {
    uploadFiles,
    uploadStates,
    isUploading,
    cancelUpload,
    pauseUpload,
    resumeUpload,
    clearCompleted,
    error
  };
};

export default useFileUpload;
