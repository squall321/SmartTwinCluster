// 잡 관리 파일 업로드 섹션
import React, { useCallback, useState } from 'react';
import { Upload, X, File, CheckCircle, AlertCircle, Copy, Loader } from 'lucide-react';
import { UploadedFile } from './types';
import toast from 'react-hot-toast';
import { API_CONFIG } from '../../config/api.config';

interface FileUploadSectionProps {
  files: UploadedFile[];
  jobId: string;
  onFilesChange: React.Dispatch<React.SetStateAction<UploadedFile[]>>;
  disabled?: boolean;
  templateId?: string;  // Template ID for smart behavior
}

/**
 * 파일명에서 변수명 생성
 * data.csv → DATA_CSV
 * my-model.pt → MY_MODEL_PT
 */
const generateVariableName = (filename: string): string => {
  return filename
    .replace(/\.[^.]+$/, '') // 확장자 제거
    .replace(/[^a-zA-Z0-9]/g, '_') // 특수문자 → _
    .toUpperCase();
};

/**
 * 파일 크기를 읽기 쉬운 형식으로 변환
 */
const formatFileSize = (bytes: number): string => {
  if (bytes === 0) return '0 Bytes';
  const k = 1024;
  const sizes = ['Bytes', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return Math.round((bytes / Math.pow(k, i)) * 100) / 100 + ' ' + sizes[i];
};

/**
 * 파일 아이콘 선택
 */
const getFileIcon = (filename: string): string => {
  const ext = filename.split('.').pop()?.toLowerCase();
  
  const iconMap: Record<string, string> = {
    'csv': '📊',
    'txt': '📄',
    'py': '🐍',
    'sh': '🔧',
    'json': '📋',
    'yaml': '⚙️',
    'yml': '⚙️',
    'pt': '🧠',
    'pth': '🧠',
    'h5': '🧠',
    'pkl': '📦',
    'zip': '🗜️',
    'tar': '🗜️',
    'gz': '🗜️',
    'pdf': '📕',
    'png': '🖼️',
    'jpg': '🖼️',
    'jpeg': '🖼️',
  };
  
  return iconMap[ext || ''] || '📄';
};

export const FileUploadSection: React.FC<FileUploadSectionProps> = ({
  files,
  jobId,
  onFilesChange,
  disabled = false,
  templateId,
}) => {
  const [isDragging, setIsDragging] = useState(false);

  // 파일 업로드 처리
  const handleFileUpload = useCallback(async (fileList: FileList) => {
    if (disabled) return;

    const newFiles: UploadedFile[] = [];

    for (let i = 0; i < fileList.length; i++) {
      const file = fileList[i];
      
      // 중복 파일명 체크
      if (files.some(f => f.name === file.name)) {
        toast.error(`File "${file.name}" already exists`);
        continue;
      }

      // 파일 크기 제한 (10GB)
      if (file.size > 10 * 1024 * 1024 * 1024) {
        toast.error(`File "${file.name}" is too large (max 10GB)`);
        continue;
      }

      const uploadedFile: UploadedFile = {
        id: `file-${Date.now()}-${i}`,
        name: file.name,
        size: file.size,
        path: `/data/results/${jobId}/${file.name}`,
        uploadTime: new Date().toISOString(),
        status: 'uploading',
        progress: 0,
        variableName: generateVariableName(file.name),
      };

      newFiles.push(uploadedFile);
    }

    if (newFiles.length === 0) return;

    // 파일 목록에 추가 (업로딩 상태)
    onFilesChange([...files, ...newFiles]);

    // 실제 파일 업로드
    for (let i = 0; i < fileList.length; i++) {
      const file = fileList[i];
      const uploadedFile = newFiles[i];
      
      if (!uploadedFile) continue;
      
      try {
        // 백엔드로 파일 업로드
        await uploadFileToBackend(file, uploadedFile, (progress) => {
          onFilesChange(prevFiles => 
            prevFiles.map(f => 
              f.id === uploadedFile.id 
                ? { ...f, progress } 
                : f
            )
          );
        });

        // 업로드 완료
        onFilesChange(prevFiles => 
          prevFiles.map(f => 
            f.id === uploadedFile.id 
              ? { ...f, status: 'uploaded', progress: 100 } 
              : f
          )
        );

        toast.success(`Uploaded: ${uploadedFile.name}`);
      } catch (error) {
        // 업로드 실패
        onFilesChange(prevFiles => 
          prevFiles.map(f => 
            f.id === uploadedFile.id 
              ? { ...f, status: 'error', progress: 0 } 
              : f
          )
        );
        toast.error(`Failed to upload: ${uploadedFile.name}`);
        console.error('Upload error:', error);
      }
    }
  }, [files, jobId, onFilesChange, disabled]);

  // 실제 파일 업로드 (백엔드 API 호출)
  const uploadFileToBackend = async (
    file: File,
    uploadedFile: UploadedFile,
    onProgress: (progress: number) => void
  ): Promise<void> => {
    return new Promise((resolve, reject) => {
      const formData = new FormData();
      formData.append('file', file);
      formData.append('jobId', jobId);

      const xhr = new XMLHttpRequest();

      // 진행률 추적
      xhr.upload.addEventListener('progress', (e) => {
        if (e.lengthComputable) {
          const progress = (e.loaded / e.total) * 100;
          onProgress(progress);
        }
      });

      // 완료
      xhr.addEventListener('load', () => {
        if (xhr.status === 200) {
          resolve();
        } else {
          reject(new Error(`Upload failed: ${xhr.status}`));
        }
      });

      // 에러
      xhr.addEventListener('error', () => {
        reject(new Error('Upload failed'));
      });

      // 요청 전송
      xhr.open('POST', `${API_CONFIG.API_BASE_URL}/api/jobs/upload-file`);
      xhr.send(formData);
    });
  };

  // 파일 삭제
  const handleRemoveFile = (fileId: string) => {
    if (disabled) return;
    onFilesChange(files.filter(f => f.id !== fileId));
    toast.success('File removed');
  };

  // 변수명 복사
  const handleCopyVariable = (variableName: string) => {
    navigator.clipboard.writeText(`$${variableName}`);
    toast.success('Variable name copied!', { duration: 1500 });
  };

  // 드래그 앤 드롭 핸들러
  const handleDragEnter = (e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    if (!disabled) setIsDragging(true);
  };

  const handleDragLeave = (e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragging(false);
  };

  const handleDragOver = (e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
  };

  const handleDrop = (e: React.DragEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragging(false);
    
    if (disabled) return;
    
    const droppedFiles = e.dataTransfer.files;
    if (droppedFiles.length > 0) {
      handleFileUpload(droppedFiles);
    }
  };

  // 파일 선택 핸들러
  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files && e.target.files.length > 0) {
      handleFileUpload(e.target.files);
      e.target.value = ''; // Reset input
    }
  };

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <label className="block text-sm font-medium text-gray-700">
          Input Files
        </label>
        <span className="text-xs text-gray-500">
          Job Directory: /data/results/{jobId}
        </span>
      </div>

      {/* 드래그 앤 드롭 영역 */}
      <div
        onDragEnter={handleDragEnter}
        onDragLeave={handleDragLeave}
        onDragOver={handleDragOver}
        onDrop={handleDrop}
        className={`
          relative border-2 border-dashed rounded-lg p-6 text-center transition-colors
          ${disabled ? 'opacity-50 cursor-not-allowed' : 'cursor-pointer'}
          ${isDragging 
            ? 'border-blue-500 bg-blue-50' 
            : 'border-gray-300 hover:border-gray-400 bg-gray-50'
          }
        `}
      >
        <input
          type="file"
          multiple
          disabled={disabled}
          onChange={handleFileSelect}
          className="absolute inset-0 w-full h-full opacity-0 cursor-pointer disabled:cursor-not-allowed"
          accept="*/*"
        />
        
        <Upload className={`w-10 h-10 mx-auto mb-2 ${isDragging ? 'text-blue-500' : 'text-gray-400'}`} />
        <p className="text-sm text-gray-600 mb-1">
          {isDragging ? 'Drop files here' : 'Drag & drop files or click to browse'}
        </p>
        <p className="text-xs text-gray-500">
          Maximum file size: 10GB
        </p>
      </div>

      {/* 파일 목록 */}
      {files.length > 0 && (
        <div className="border border-gray-200 rounded-lg overflow-hidden">
          <div className="bg-gray-50 px-4 py-2 border-b border-gray-200">
            <div className="flex items-center justify-between">
              <span className="text-sm font-medium text-gray-700">
                Files ({files.length})
              </span>
              <span className="text-xs text-gray-500">
                Total: {formatFileSize(files.reduce((acc, f) => acc + f.size, 0))}
              </span>
            </div>
          </div>

          <div className="divide-y divide-gray-200 max-h-80 overflow-y-auto">
            {files.map((file) => (
              <div
                key={file.id}
                className="px-4 py-3 hover:bg-gray-50 transition-colors"
              >
                <div className="flex items-start gap-3">
                  {/* 파일 아이콘 & 상태 */}
                  <div className="flex-shrink-0 mt-0.5">
                    {file.status === 'uploading' ? (
                      <Loader className="w-5 h-5 text-blue-500 animate-spin" />
                    ) : file.status === 'uploaded' ? (
                      <CheckCircle className="w-5 h-5 text-green-500" />
                    ) : (
                      <AlertCircle className="w-5 h-5 text-red-500" />
                    )}
                  </div>

                  {/* 파일 정보 */}
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 mb-1">
                      <span className="text-lg">{getFileIcon(file.name)}</span>
                      <span className="text-sm font-medium text-gray-900 truncate">
                        {file.name}
                      </span>
                      <span className="text-xs text-gray-500">
                        {formatFileSize(file.size)}
                      </span>
                    </div>

                    {/* 변수명 */}
                    <div className="flex items-center gap-2 mb-1">
                      <code className="text-xs bg-gray-100 px-2 py-0.5 rounded text-gray-700">
                        ${file.variableName}="{file.path}"
                      </code>
                      <button
                        onClick={() => handleCopyVariable(file.variableName || '')}
                        className="text-gray-400 hover:text-gray-600 transition-colors"
                        title="Copy variable name"
                      >
                        <Copy className="w-3 h-3" />
                      </button>
                    </div>

                    {/* 업로드 진행률 */}
                    {file.status === 'uploading' && file.progress !== undefined && (
                      <div className="mt-2">
                        <div className="flex items-center justify-between text-xs text-gray-600 mb-1">
                          <span>Uploading...</span>
                          <span>{Math.round(file.progress)}%</span>
                        </div>
                        <div className="w-full bg-gray-200 rounded-full h-1.5">
                          <div
                            className="bg-blue-500 h-1.5 rounded-full transition-all"
                            style={{ width: `${file.progress}%` }}
                          />
                        </div>
                      </div>
                    )}

                    {/* 에러 메시지 */}
                    {file.status === 'error' && (
                      <p className="text-xs text-red-600 mt-1">
                        Upload failed. Please try again.
                      </p>
                    )}
                  </div>

                  {/* 삭제 버튼 */}
                  <button
                    onClick={() => handleRemoveFile(file.id)}
                    disabled={disabled || file.status === 'uploading'}
                    className="flex-shrink-0 p-1 text-gray-400 hover:text-red-600 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
                    title="Remove file"
                  >
                    <X className="w-4 h-4" />
                  </button>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* 도움말 */}
      {files.length > 0 && (
        <div className="bg-blue-50 border border-blue-200 rounded-lg p-3">
          <p className="text-xs text-blue-800">
            💡 <strong>Tip:</strong> Files are automatically referenced in your script. 
            Click the copy icon to copy variable names.
          </p>
        </div>
      )}
      
      {/* LS-DYNA 특별 안내 */}
      {templateId === 'template-lsdyna-single' && files.length === 0 && (
        <div className="bg-purple-50 border border-purple-200 rounded-lg p-3">
          <p className="text-xs text-purple-800">
            📦 <strong>LS-DYNA Single Job:</strong> Upload one K file. 
            It will be automatically configured in the script as <code className="bg-purple-100 px-1 rounded">K_FILE</code>.
          </p>
        </div>
      )}
      
      {templateId === 'template-lsdyna-single' && files.length > 1 && (
        <div className="bg-amber-50 border border-amber-200 rounded-lg p-3">
          <p className="text-xs text-amber-800">
            ⚠️ <strong>Notice:</strong> Only the first K file will be used for Single Job. 
            Remove extra files or use the Array Job template for multiple files.
          </p>
        </div>
      )}
      
      {templateId === 'template-lsdyna-array' && files.length === 0 && (
        <div className="bg-purple-50 border border-purple-200 rounded-lg p-3">
          <p className="text-xs text-purple-800">
            📦 <strong>LS-DYNA Array Job:</strong> Upload multiple K files. 
            Each file will be submitted as a separate job with its own resources and output directory.
          </p>
        </div>
      )}
      
      {templateId === 'template-lsdyna-array' && files.length > 0 && (
        <div className="bg-green-50 border border-green-200 rounded-lg p-3">
          <p className="text-xs text-green-800">
            ✅ <strong>Ready:</strong> {files.filter(f => f.name.endsWith('.k')).length} K file(s) will be submitted. 
            Each job will run with {files.length > 0 ? '16 cores' : 'configured resources'}.
          </p>
        </div>
      )}
    </div>
  );
};

export default FileUploadSection;
