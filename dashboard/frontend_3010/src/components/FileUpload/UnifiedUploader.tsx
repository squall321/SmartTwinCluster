/**
 * UnifiedUploader Component
 * 통합 파일 업로드 인터페이스
 *
 * Features:
 * - Drag & Drop 지원
 * - 다중 파일 선택
 * - 파일 타입 자동 분류
 * - 실시간 진행률 표시
 * - 대용량 파일 청크 업로드
 * - 업로드 일시정지/재개/취소
 */

import React, { useState, useCallback, useRef, useEffect } from 'react';
import { UnifiedUploaderProps, ClassifiedFiles } from '../../types/upload';
import { useFileUpload } from '../../hooks/useFileUpload';
import { useUploadProgress } from '../../hooks/useUploadProgress';
import { FileClassifier } from './FileClassifier';
import { UploadProgress } from './UploadProgress';
import {
  Upload,
  X,
  FileUp,
  CheckCircle,
  AlertCircle
} from 'lucide-react';

export const UnifiedUploader: React.FC<UnifiedUploaderProps> = ({
  templateId,
  jobId,
  userId,
  onComplete,
  onError,
  onClassified,
  maxFileSize = 50 * 1024 * 1024 * 1024, // 50GB
  maxFiles = 20,
  acceptedTypes,
  enableChunking = true,
  chunkSize = 5 * 1024 * 1024 // 5MB
}) => {
  const [selectedFiles, setSelectedFiles] = useState<File[]>([]);
  const [isDragging, setIsDragging] = useState(false);
  const [classifiedFiles, setClassifiedFiles] = useState<ClassifiedFiles | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  // 파일 업로드 훅
  const {
    uploadFiles,
    uploadStates,
    isUploading,
    cancelUpload,
    pauseUpload,
    resumeUpload,
    clearCompleted,
    error: uploadError
  } = useFileUpload({
    userId,
    jobId,
    chunkSize,
    onAllComplete: (files) => {
      onComplete(files);
      // 업로드 완료 후 상태 정리
      setTimeout(() => {
        clearCompleted();
        setSelectedFiles([]);
      }, 2000);
    },
    onError: (error, filename) => {
      console.error(`Upload error for ${filename}:`, error);
      onError?.(error);
    }
  });

  // WebSocket 진행률 추적 (선택적)
  const { progressMap } = useUploadProgress({
    uploadIds: Array.from(uploadStates.values())
      .map(state => state.uploadId)
      .filter(Boolean) as string[]
  });

  // 파일 분류 변경 시 콜백 호출
  useEffect(() => {
    if (classifiedFiles && onClassified) {
      onClassified(classifiedFiles);
    }
  }, [classifiedFiles, onClassified]);

  /**
   * 파일 검증
   */
  const validateFile = useCallback((file: File): { valid: boolean; error?: string } => {
    // 파일 크기 검증
    if (file.size > maxFileSize) {
      return {
        valid: false,
        error: `파일 크기가 최대 크기(${(maxFileSize / (1024 * 1024 * 1024)).toFixed(1)}GB)를 초과합니다.`
      };
    }

    // 파일 타입 검증 (선택적)
    if (acceptedTypes && acceptedTypes.length > 0) {
      const ext = file.name.split('.').pop()?.toLowerCase();
      if (!ext || !acceptedTypes.includes(`.${ext}`)) {
        return {
          valid: false,
          error: `허용되지 않는 파일 형식입니다. (허용: ${acceptedTypes.join(', ')})`
        };
      }
    }

    return { valid: true };
  }, [maxFileSize, acceptedTypes]);

  /**
   * 파일 추가
   */
  const addFiles = useCallback((newFiles: FileList | File[]) => {
    const filesArray = Array.from(newFiles);

    // 파일 수 제한 확인
    if (selectedFiles.length + filesArray.length > maxFiles) {
      alert(`최대 ${maxFiles}개의 파일만 업로드할 수 있습니다.`);
      return;
    }

    // 각 파일 검증
    const validFiles: File[] = [];
    const errors: string[] = [];

    filesArray.forEach(file => {
      const { valid, error } = validateFile(file);

      if (valid) {
        // 중복 파일 확인
        const isDuplicate = selectedFiles.some(f => f.name === file.name && f.size === file.size);

        if (!isDuplicate) {
          validFiles.push(file);
        }
      } else {
        errors.push(`${file.name}: ${error}`);
      }
    });

    // 에러가 있으면 표시
    if (errors.length > 0) {
      alert(errors.join('\n'));
    }

    // 유효한 파일 추가
    if (validFiles.length > 0) {
      setSelectedFiles(prev => [...prev, ...validFiles]);
    }
  }, [selectedFiles, maxFiles, validateFile]);

  /**
   * 파일 제거
   */
  const removeFile = useCallback((filename: string) => {
    setSelectedFiles(prev => prev.filter(f => f.name !== filename));
  }, []);

  /**
   * 파일 선택 핸들러
   */
  const handleFileSelect = useCallback((event: React.ChangeEvent<HTMLInputElement>) => {
    const files = event.target.files;
    if (files) {
      addFiles(files);
    }

    // input 초기화 (같은 파일 다시 선택 가능)
    if (fileInputRef.current) {
      fileInputRef.current.value = '';
    }
  }, [addFiles]);

  /**
   * Drag & Drop 핸들러
   */
  const handleDragEnter = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragging(true);
  }, []);

  const handleDragLeave = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragging(false);
  }, []);

  const handleDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
  }, []);

  const handleDrop = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragging(false);

    const files = e.dataTransfer.files;
    if (files) {
      addFiles(files);
    }
  }, [addFiles]);

  /**
   * 업로드 시작
   */
  const handleStartUpload = useCallback(async () => {
    if (selectedFiles.length === 0) {
      alert('업로드할 파일을 선택해주세요.');
      return;
    }

    try {
      await uploadFiles(selectedFiles);
    } catch (error) {
      console.error('Upload failed:', error);
    }
  }, [selectedFiles, uploadFiles]);

  /**
   * 모든 완료된 업로드 정리
   */
  const handleClearCompleted = useCallback(() => {
    clearCompleted();
    setSelectedFiles([]);
    setClassifiedFiles(null);
  }, [clearCompleted]);

  // 업로드 상태 통계
  const uploadStats = {
    total: uploadStates.size,
    uploading: Array.from(uploadStates.values()).filter(s => s.status === 'uploading').length,
    completed: Array.from(uploadStates.values()).filter(s => s.status === 'completed').length,
    failed: Array.from(uploadStates.values()).filter(s => s.status === 'error').length
  };

  return (
    <div className="space-y-6">
      {/* 업로드 영역 */}
      {!isUploading && selectedFiles.length === 0 && (
        <div
          className={`
            border-2 border-dashed rounded-lg p-8 text-center
            transition-colors cursor-pointer
            ${isDragging
              ? 'border-blue-500 bg-blue-50'
              : 'border-gray-300 hover:border-gray-400 hover:bg-gray-50'
            }
          `}
          onDragEnter={handleDragEnter}
          onDragLeave={handleDragLeave}
          onDragOver={handleDragOver}
          onDrop={handleDrop}
          onClick={() => fileInputRef.current?.click()}
        >
          <Upload className="w-12 h-12 mx-auto mb-4 text-gray-400" />

          <h3 className="text-lg font-medium text-gray-700 mb-2">
            파일을 드래그하거나 클릭하여 선택
          </h3>

          <p className="text-sm text-gray-500 mb-4">
            최대 {maxFiles}개 파일, 개별 파일 최대 {(maxFileSize / (1024 * 1024 * 1024)).toFixed(0)}GB
          </p>

          {acceptedTypes && acceptedTypes.length > 0 && (
            <p className="text-xs text-gray-400">
              허용 형식: {acceptedTypes.join(', ')}
            </p>
          )}

          <input
            ref={fileInputRef}
            type="file"
            multiple
            onChange={handleFileSelect}
            className="hidden"
            accept={acceptedTypes?.join(',')}
          />
        </div>
      )}

      {/* 선택된 파일 목록 (업로드 전) */}
      {selectedFiles.length > 0 && !isUploading && (
        <div className="space-y-4">
          <div className="flex items-center justify-between">
            <h3 className="text-lg font-semibold text-gray-800">
              선택된 파일 ({selectedFiles.length}개)
            </h3>

            <div className="flex gap-2">
              <button
                onClick={() => fileInputRef.current?.click()}
                className="px-4 py-2 text-sm border border-gray-300 rounded-lg hover:bg-gray-50 transition-colors"
              >
                <FileUp className="w-4 h-4 inline mr-2" />
                파일 추가
              </button>

              <button
                onClick={handleStartUpload}
                className="px-4 py-2 text-sm bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
              >
                업로드 시작
              </button>
            </div>
          </div>

          {/* 파일 분류 */}
          <FileClassifier
            files={selectedFiles}
            onClassified={setClassifiedFiles}
          />

          {/* 선택된 파일 상세 목록 */}
          <div className="border rounded-lg divide-y">
            {selectedFiles.map((file, index) => (
              <div
                key={index}
                className="flex items-center justify-between p-3 hover:bg-gray-50"
              >
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium text-gray-800 truncate">
                    {file.name}
                  </p>
                  <p className="text-xs text-gray-500">
                    {(file.size / (1024 * 1024)).toFixed(2)} MB
                  </p>
                </div>

                <button
                  onClick={() => removeFile(file.name)}
                  className="ml-2 p-1 hover:bg-gray-200 rounded transition-colors"
                  title="제거"
                >
                  <X className="w-4 h-4 text-gray-600" />
                </button>
              </div>
            ))}
          </div>

          <input
            ref={fileInputRef}
            type="file"
            multiple
            onChange={handleFileSelect}
            className="hidden"
            accept={acceptedTypes?.join(',')}
          />
        </div>
      )}

      {/* 업로드 진행 상태 */}
      {uploadStates.size > 0 && (
        <div className="space-y-4">
          {/* 통계 */}
          <div className="flex items-center justify-between p-4 bg-gray-50 rounded-lg">
            <h3 className="text-lg font-semibold text-gray-800">
              업로드 진행 상황
            </h3>

            <div className="flex items-center gap-4 text-sm">
              {uploadStats.uploading > 0 && (
                <span className="text-blue-600">
                  업로드 중: {uploadStats.uploading}
                </span>
              )}
              {uploadStats.completed > 0 && (
                <span className="text-green-600 flex items-center gap-1">
                  <CheckCircle className="w-4 h-4" />
                  완료: {uploadStats.completed}
                </span>
              )}
              {uploadStats.failed > 0 && (
                <span className="text-red-600 flex items-center gap-1">
                  <AlertCircle className="w-4 h-4" />
                  실패: {uploadStats.failed}
                </span>
              )}

              {uploadStats.completed === uploadStats.total && uploadStats.total > 0 && (
                <button
                  onClick={handleClearCompleted}
                  className="px-3 py-1 text-sm border border-gray-300 rounded hover:bg-gray-100"
                >
                  정리
                </button>
              )}
            </div>
          </div>

          {/* 개별 파일 진행률 */}
          <div className="space-y-3">
            {Array.from(uploadStates.entries()).map(([filename, state]) => (
              <UploadProgress
                key={filename}
                state={state}
                onCancel={() => cancelUpload(filename)}
                onPause={() => pauseUpload(filename)}
                onResume={() => resumeUpload(filename)}
              />
            ))}
          </div>
        </div>
      )}

      {/* 에러 표시 */}
      {uploadError && (
        <div className="p-4 bg-red-50 border border-red-200 rounded-lg">
          <div className="flex items-start gap-2">
            <AlertCircle className="w-5 h-5 text-red-600 flex-shrink-0 mt-0.5" />
            <div className="flex-1">
              <h4 className="text-sm font-medium text-red-800 mb-1">
                업로드 오류
              </h4>
              <p className="text-sm text-red-700">
                {uploadError.message}
              </p>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default UnifiedUploader;
