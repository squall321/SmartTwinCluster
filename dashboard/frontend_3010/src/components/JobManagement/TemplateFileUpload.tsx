/**
 * Template 기반 파일 업로드 컴포넌트
 * Template의 file schema에 따라 동적으로 업로드 UI 생성
 */

import React, { useState, useCallback } from 'react';
import { Upload, File, CheckCircle, XCircle, AlertCircle } from 'lucide-react';
import toast from 'react-hot-toast';

export interface FileSchema {
  name: string;  // 사용자에게 표시되는 이름
  file_key: string;  // 내부 키 (스크립트에서 사용)
  pattern: string;  // 파일 패턴 (*.stl, *.json 등)
  description: string;
  type: 'file' | 'directory';
  max_size: string;  // "500MB", "1GB" 등
  validation?: {
    extensions?: string[];
    mime_types?: string[];
    schema?: any;  // JSON 스키마
  };
}

export interface UploadedFileInfo {
  file_key: string;
  file: File;
  preview?: string;  // 파일 미리보기 (작은 파일의 경우)
}

interface TemplateFileUploadProps {
  schema: {
    required?: FileSchema[];
    optional?: FileSchema[];
  };
  onFilesChange: (files: UploadedFileInfo[]) => void;
  uploadedFiles: UploadedFileInfo[];
  className?: string;
}

export const TemplateFileUpload: React.FC<TemplateFileUploadProps> = ({
  schema,
  onFilesChange,
  uploadedFiles,
  className = ''
}) => {
  const [validationErrors, setValidationErrors] = useState<Record<string, string>>({});

  // 파일 크기 파싱
  const parseSize = (sizeStr: string): number => {
    const match = sizeStr.match(/^(\d+(\.\d+)?)\s*(B|KB|MB|GB)$/i);
    if (!match) return 1024 * 1024 * 1024; // 기본 1GB

    const value = parseFloat(match[1]);
    const unit = match[3].toUpperCase();

    const units: Record<string, number> = {
      'B': 1,
      'KB': 1024,
      'MB': 1024 * 1024,
      'GB': 1024 * 1024 * 1024
    };

    return value * units[unit];
  };

  // 파일 검증
  const validateFile = useCallback((fileSchema: FileSchema, file: File): string | null => {
    // 크기 검증
    const maxSize = parseSize(fileSchema.max_size);
    if (file.size > maxSize) {
      return `File size (${formatBytes(file.size)}) exceeds maximum (${fileSchema.max_size})`;
    }

    // 확장자 검증
    if (fileSchema.validation?.extensions) {
      const ext = '.' + file.name.split('.').pop()?.toLowerCase();
      const allowed = fileSchema.validation.extensions.map(e => e.toLowerCase());

      if (!allowed.includes(ext)) {
        return `Invalid file extension. Allowed: ${fileSchema.validation.extensions.join(', ')}`;
      }
    }

    // MIME 타입 검증
    if (fileSchema.validation?.mime_types) {
      if (!fileSchema.validation.mime_types.includes(file.type)) {
        return `Invalid file type: ${file.type}`;
      }
    }

    return null;
  }, []);

  // 파일 선택 핸들러
  const handleFileSelect = useCallback(async (fileSchema: FileSchema, event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (!file) return;

    // 검증
    const error = validateFile(fileSchema, file);
    if (error) {
      setValidationErrors(prev => ({ ...prev, [fileSchema.file_key]: error }));
      toast.error(error);
      return;
    }

    // 검증 성공
    setValidationErrors(prev => {
      const newErrors = { ...prev };
      delete newErrors[fileSchema.file_key];
      return newErrors;
    });

    // 파일 미리보기 (JSON 파일의 경우)
    let preview: string | undefined;
    if (file.type === 'application/json' && file.size < 10000) {
      try {
        const text = await file.text();
        preview = text;
      } catch (err) {
        console.error('Failed to preview file:', err);
      }
    }

    // 업로드된 파일 목록 업데이트
    const newFile: UploadedFileInfo = {
      file_key: fileSchema.file_key,
      file,
      preview
    };

    const updatedFiles = uploadedFiles.filter(f => f.file_key !== fileSchema.file_key);
    updatedFiles.push(newFile);
    onFilesChange(updatedFiles);

    toast.success(`File uploaded: ${file.name}`);
  }, [validateFile, uploadedFiles, onFilesChange]);

  // 파일 제거 핸들러
  const handleFileRemove = useCallback((file_key: string) => {
    const updatedFiles = uploadedFiles.filter(f => f.file_key !== file_key);
    onFilesChange(updatedFiles);

    setValidationErrors(prev => {
      const newErrors = { ...prev };
      delete newErrors[file_key];
      return newErrors;
    });

    toast.success('File removed');
  }, [uploadedFiles, onFilesChange]);

  // 파일 렌더링
  const renderFileInput = (fileSchema: FileSchema, isRequired: boolean) => {
    const uploadedFile = uploadedFiles.find(f => f.file_key === fileSchema.file_key);
    const error = validationErrors[fileSchema.file_key];

    return (
      <div key={fileSchema.file_key} className="border border-gray-200 rounded-lg p-4">
        <div className="flex items-start justify-between mb-2">
          <div>
            <label className="block text-sm font-medium text-gray-700">
              {fileSchema.name}
              {isRequired && <span className="text-red-500 ml-1">*</span>}
            </label>
            <p className="text-xs text-gray-500 mt-1">{fileSchema.description}</p>
            <div className="flex gap-2 mt-1">
              <span className="text-xs text-gray-400">Pattern: {fileSchema.pattern}</span>
              <span className="text-xs text-gray-400">Max: {fileSchema.max_size}</span>
            </div>
          </div>

          {uploadedFile && (
            <button
              type="button"
              onClick={() => handleFileRemove(fileSchema.file_key)}
              className="text-red-600 hover:text-red-800 text-sm"
            >
              <XCircle className="w-5 h-5" />
            </button>
          )}
        </div>

        {uploadedFile ? (
          <div className="mt-3 p-3 bg-green-50 border border-green-200 rounded-lg">
            <div className="flex items-center gap-2">
              <CheckCircle className="w-4 h-4 text-green-600" />
              <div className="flex-1">
                <p className="text-sm font-medium text-green-900">{uploadedFile.file.name}</p>
                <p className="text-xs text-green-700">
                  {formatBytes(uploadedFile.file.size)} • {uploadedFile.file.type || 'unknown type'}
                </p>
              </div>
            </div>

            {/* JSON 미리보기 */}
            {uploadedFile.preview && (
              <details className="mt-2">
                <summary className="text-xs text-green-700 cursor-pointer">Preview</summary>
                <pre className="mt-2 p-2 bg-white rounded text-xs overflow-x-auto">
                  {uploadedFile.preview}
                </pre>
              </details>
            )}
          </div>
        ) : (
          <div className="mt-3">
            <label className={`
              flex flex-col items-center gap-2 p-6 border-2 border-dashed rounded-lg cursor-pointer
              transition-colors
              ${error
                ? 'border-red-300 bg-red-50 hover:bg-red-100'
                : 'border-gray-300 hover:border-blue-400 hover:bg-blue-50'
              }
            `}>
              <Upload className={`w-8 h-8 ${error ? 'text-red-400' : 'text-gray-400'}`} />
              <span className="text-sm text-gray-600">
                Click to upload or drag and drop
              </span>
              <input
                type="file"
                className="hidden"
                accept={fileSchema.validation?.extensions?.join(',')}
                onChange={(e) => handleFileSelect(fileSchema, e)}
              />
            </label>
          </div>
        )}

        {/* 에러 메시지 */}
        {error && (
          <div className="mt-2 flex items-center gap-2 text-sm text-red-600">
            <AlertCircle className="w-4 h-4" />
            <span>{error}</span>
          </div>
        )}
      </div>
    );
  };

  // 스키마 없음
  if (!schema.required && !schema.optional) {
    return (
      <div className={`bg-gray-50 p-4 rounded-lg ${className}`}>
        <p className="text-sm text-gray-600">No file upload required for this template</p>
      </div>
    );
  }

  return (
    <div className={className}>
      {/* 필수 파일 */}
      {schema.required && schema.required.length > 0 && (
        <div className="mb-6">
          <h3 className="text-sm font-semibold text-gray-700 mb-3 flex items-center gap-2">
            <File className="w-4 h-4" />
            Required Files
          </h3>
          <div className="space-y-4">
            {schema.required.map(fileSchema => renderFileInput(fileSchema, true))}
          </div>
        </div>
      )}

      {/* 선택적 파일 */}
      {schema.optional && schema.optional.length > 0 && (
        <div>
          <h3 className="text-sm font-semibold text-gray-700 mb-3 flex items-center gap-2">
            <File className="w-4 h-4" />
            Optional Files
          </h3>
          <div className="space-y-4">
            {schema.optional.map(fileSchema => renderFileInput(fileSchema, false))}
          </div>
        </div>
      )}

      {/* 업로드 요약 */}
      <div className="mt-4 p-3 bg-blue-50 border border-blue-200 rounded-lg">
        <div className="text-sm text-blue-900">
          <span className="font-medium">Files uploaded:</span> {uploadedFiles.length}
          {schema.required && (
            <span className="ml-2 text-blue-700">
              (Required: {schema.required.length})
            </span>
          )}
        </div>
      </div>
    </div>
  );
};

// 파일 크기 포맷팅
function formatBytes(bytes: number): string {
  if (bytes === 0) return '0 Bytes';

  const k = 1024;
  const sizes = ['Bytes', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));

  return Math.round((bytes / Math.pow(k, i)) * 100) / 100 + ' ' + sizes[i];
}
