/**
 * JobFileUpload Component
 * Job Submit을 위한 UnifiedUploader 어댑터
 *
 * 기존 FileUploadSection의 인터페이스를 유지하면서
 * 내부적으로 새로운 UnifiedUploader를 사용
 */

import React, { useCallback, useMemo, useState, useEffect } from 'react';
import { UnifiedUploader } from '../FileUpload';
import { UploadedFile as NewUploadedFile, ClassifiedFiles } from '../../types/upload';
import { UploadedFile as LegacyUploadedFile } from './types';
import { useTemplateSchema } from '../../hooks/useTemplateSchema';
import { FileValidationStatus, TemplateRequirements } from '../FileUpload/FileValidationStatus';
import { validateFilesAgainstTemplate } from '../../utils/templateFileValidation';

interface JobFileUploadProps {
  files: LegacyUploadedFile[];
  jobId: string;
  userId: string;
  onFilesChange: React.Dispatch<React.SetStateAction<LegacyUploadedFile[]>>;
  onValidationChange?: (validation: { valid: boolean } | null) => void;
  disabled?: boolean;
  templateId?: string;
  maxFileSize?: number;
  maxFiles?: number;
}

/**
 * 파일명에서 변수명 생성
 * data.csv → DATA_CSV
 */
const generateVariableName = (filename: string): string => {
  return filename
    .replace(/\.[^.]+$/, '') // 확장자 제거
    .replace(/[^a-zA-Z0-9]/g, '_') // 특수문자 → _
    .toUpperCase();
};

/**
 * 새로운 UploadedFile을 레거시 포맷으로 변환
 */
const convertToLegacyFormat = (newFile: NewUploadedFile): LegacyUploadedFile => {
  return {
    id: newFile.upload_id,
    name: newFile.filename,
    size: newFile.file_size,
    path: newFile.file_path || newFile.storage_path,
    uploadTime: newFile.created_at,
    status: newFile.status === 'completed' ? 'uploaded' :
            newFile.status === 'failed' ? 'failed' :
            'uploading',
    progress: 100, // 완료된 파일만 콜백으로 오므로
    variableName: generateVariableName(newFile.filename),
    metadata: {
      file_type: newFile.file_type,
      upload_id: newFile.upload_id,
      storage_path: newFile.storage_path
    }
  };
};

export const JobFileUpload: React.FC<JobFileUploadProps> = ({
  files,
  jobId,
  userId,
  onFilesChange,
  onValidationChange,
  disabled = false,
  templateId,
  maxFileSize = 50 * 1024 * 1024 * 1024, // 50GB
  maxFiles = 20
}) => {
  // Template 스키마 로드
  const { schema, template, loading: schemaLoading } = useTemplateSchema(templateId);

  // 파일 분류 상태 (검증용)
  const [classifiedFiles, setClassifiedFiles] = useState<ClassifiedFiles | null>(null);

  // 파일 검증 결과 계산
  const validation = useMemo(() => {
    if (!schema || !classifiedFiles) return null;
    return validateFilesAgainstTemplate(classifiedFiles, schema);
  }, [schema, classifiedFiles]);

  // 검증 결과를 부모 컴포넌트로 전달
  useEffect(() => {
    if (onValidationChange) {
      onValidationChange(validation);
    }
  }, [validation, onValidationChange]);

  /**
   * 업로드 완료 핸들러
   */
  const handleComplete = useCallback((uploadedFiles: NewUploadedFile[]) => {
    console.log('Files uploaded:', uploadedFiles);

    // 새로운 파일들을 레거시 포맷으로 변환
    const legacyFiles = uploadedFiles.map(convertToLegacyFormat);

    // 기존 파일 목록에 추가
    onFilesChange(prevFiles => {
      // 중복 제거 (upload_id 기준)
      const existingIds = new Set(prevFiles.map(f => f.id));
      const newFiles = legacyFiles.filter(f => !existingIds.has(f.id));

      return [...prevFiles, ...newFiles];
    });
  }, [onFilesChange]);

  /**
   * 에러 핸들러
   */
  const handleError = useCallback((error: Error) => {
    console.error('Upload error:', error);
    // 토스트 메시지는 UnifiedUploader 내부에서도 표시되지만
    // 추가 처리가 필요하면 여기서 수행
  }, []);

  /**
   * 현재 업로드된 파일 목록 표시
   */
  const uploadedFilesList = useMemo(() => {
    if (files.length === 0) {
      return null;
    }

    return (
      <div className="mt-4 space-y-2">
        <h4 className="text-sm font-medium text-gray-700">
          업로드된 파일 ({files.length}개)
        </h4>

        <div className="border rounded-lg divide-y max-h-48 overflow-y-auto">
          {files.map((file) => (
            <div
              key={file.id}
              className="flex items-center justify-between p-3 hover:bg-gray-50"
            >
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                  <span className="text-sm font-medium text-gray-800 truncate">
                    {file.name}
                  </span>
                  {file.metadata?.file_type && (
                    <span className="px-2 py-0.5 bg-blue-100 text-blue-800 text-xs font-medium rounded">
                      {file.metadata.file_type}
                    </span>
                  )}
                </div>

                <div className="flex items-center gap-4 mt-1 text-xs text-gray-500">
                  <span>
                    {(file.size / (1024 * 1024)).toFixed(2)} MB
                  </span>

                  {file.variableName && (
                    <span className="font-mono">
                      ${file.variableName}
                    </span>
                  )}

                  {file.status === 'uploaded' && (
                    <span className="text-green-600">✓ 업로드 완료</span>
                  )}
                </div>
              </div>

              <button
                onClick={() => {
                  onFilesChange(prevFiles =>
                    prevFiles.filter(f => f.id !== file.id)
                  );
                }}
                className="ml-2 p-1 hover:bg-gray-200 rounded transition-colors"
                title="제거"
                disabled={disabled}
              >
                <span className="text-gray-600">×</span>
              </button>
            </div>
          ))}
        </div>

        {/* 파일 경로 정보 */}
        <div className="text-xs text-gray-500 bg-gray-50 p-2 rounded">
          <strong>저장 위치:</strong> Job별 디렉토리 (/shared/uploads/jobs/{jobId}/)
        </div>
      </div>
    );
  }, [files, jobId, onFilesChange, disabled]);

  // disabled 상태면 업로드된 파일 목록만 표시
  if (disabled && files.length > 0) {
    return uploadedFilesList;
  }

  if (disabled) {
    return (
      <div className="text-center py-8 text-gray-500 border-2 border-dashed border-gray-300 rounded-lg">
        파일 업로드가 비활성화되었습니다.
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {/* Template 파일 요구사항 */}
      {templateId && schema && (
        <TemplateRequirements
          schema={schema}
          className="mb-4"
        />
      )}

      {/* UnifiedUploader */}
      <UnifiedUploader
        userId={userId}
        jobId={jobId}
        templateId={templateId}
        onComplete={handleComplete}
        onError={handleError}
        onClassified={setClassifiedFiles}
        maxFileSize={maxFileSize}
        maxFiles={maxFiles}
        enableChunking={true}
        chunkSize={5 * 1024 * 1024}
      />

      {/* 파일 검증 결과 */}
      {validation && (
        <FileValidationStatus
          validation={validation}
          loading={schemaLoading}
          className="mt-4"
        />
      )}

      {/* 업로드된 파일 목록 */}
      {uploadedFilesList}
    </div>
  );
};

export default JobFileUpload;
