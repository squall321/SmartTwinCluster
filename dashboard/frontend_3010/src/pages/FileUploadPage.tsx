/**
 * File Upload Page
 * Phase 3 Frontend - Unified File Upload
 *
 * Features:
 * - 드래그 앤 드롭 파일 업로드
 * - 청크 기반 대용량 파일 업로드
 * - 실시간 진행률 표시
 * - 파일 타입 자동 분류
 * - 업로드 이력 관리
 */

import React, { useState } from 'react';
import { UnifiedUploader } from '../components/FileUpload/UnifiedUploader';
import { UploadedFile, ClassifiedFiles } from '../types/upload';
import { useAuth } from '../contexts/AuthContext';
import { FileText, Upload, CheckCircle, Clock, AlertCircle } from 'lucide-react';

export const FileUploadPage: React.FC = () => {
  const { user } = useAuth();
  const [completedUploads, setCompletedUploads] = useState<UploadedFile[]>([]);
  const [classifiedFiles, setClassifiedFiles] = useState<ClassifiedFiles | null>(null);
  const [showHistory, setShowHistory] = useState(false);

  const handleComplete = (files: UploadedFile[]) => {
    console.log('Upload completed:', files);
    setCompletedUploads(prev => [...prev, ...files]);
  };

  const handleError = (error: Error) => {
    console.error('Upload error:', error);
  };

  const handleClassified = (files: ClassifiedFiles) => {
    setClassifiedFiles(files);
  };

  // 파일 타입별 통계
  const fileTypeStats = classifiedFiles
    ? Object.entries(classifiedFiles).map(([type, files]) => ({
        type,
        count: files.length,
        size: files.reduce((sum, f) => sum + f.size, 0),
      }))
    : [];

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-900">
      {/* Header */}
      <div className="bg-white dark:bg-gray-800 shadow">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
          <div className="flex items-center justify-between">
            <div>
              <h1 className="text-3xl font-bold text-gray-900 dark:text-gray-100">
                File Upload
              </h1>
              <p className="mt-2 text-sm text-gray-600 dark:text-gray-400">
                대용량 파일을 안전하게 업로드하세요 (최대 50GB)
              </p>
            </div>
            <div className="flex items-center space-x-3">
              <span className="inline-flex items-center px-3 py-1 rounded-full text-sm font-medium bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200">
                Phase 3
              </span>
              <button
                onClick={() => setShowHistory(!showHistory)}
                className="inline-flex items-center px-4 py-2 border border-gray-300 dark:border-gray-600 rounded-md shadow-sm text-sm font-medium text-gray-700 dark:text-gray-300 bg-white dark:bg-gray-700 hover:bg-gray-50 dark:hover:bg-gray-600"
              >
                <Clock className="w-4 h-4 mr-2" />
                Upload History ({completedUploads.length})
              </button>
            </div>
          </div>
        </div>
      </div>

      {/* Main Content */}
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {/* Uploader */}
        <div className="bg-white dark:bg-gray-800 rounded-lg shadow-lg p-6 mb-6">
          <UnifiedUploader
            userId={user?.username || 'anonymous'}
            onComplete={handleComplete}
            onError={handleError}
            onClassified={handleClassified}
            maxFileSize={50 * 1024 * 1024 * 1024} // 50GB
            maxFiles={20}
            enableChunking={true}
            chunkSize={5 * 1024 * 1024} // 5MB
          />
        </div>

        {/* File Type Statistics */}
        {classifiedFiles && fileTypeStats.some(s => s.count > 0) && (
          <div className="bg-white dark:bg-gray-800 rounded-lg shadow-lg p-6 mb-6">
            <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-4">
              파일 분류 통계
            </h2>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              {fileTypeStats
                .filter(stat => stat.count > 0)
                .map(stat => (
                  <div
                    key={stat.type}
                    className="bg-gray-50 dark:bg-gray-700 rounded-lg p-4"
                  >
                    <div className="flex items-center justify-between mb-2">
                      <span className="text-sm font-medium text-gray-600 dark:text-gray-400 capitalize">
                        {stat.type}
                      </span>
                      <FileText className="w-4 h-4 text-gray-400" />
                    </div>
                    <div className="text-2xl font-bold text-gray-900 dark:text-gray-100">
                      {stat.count}
                    </div>
                    <div className="text-xs text-gray-500 dark:text-gray-400 mt-1">
                      {formatBytes(stat.size)}
                    </div>
                  </div>
                ))}
            </div>
          </div>
        )}

        {/* Upload History */}
        {showHistory && completedUploads.length > 0 && (
          <div className="bg-white dark:bg-gray-800 rounded-lg shadow-lg p-6 mb-6">
            <div className="flex items-center justify-between mb-4">
              <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100">
                업로드 이력 ({completedUploads.length})
              </h2>
              <button
                onClick={() => setCompletedUploads([])}
                className="text-sm text-red-600 hover:text-red-700 dark:text-red-400"
              >
                Clear History
              </button>
            </div>
            <div className="space-y-3">
              {completedUploads.map((file, idx) => (
                <div
                  key={idx}
                  className="flex items-center justify-between p-4 bg-gray-50 dark:bg-gray-700 rounded-lg"
                >
                  <div className="flex items-center space-x-3 flex-1">
                    <CheckCircle className="w-5 h-5 text-green-600 dark:text-green-400 flex-shrink-0" />
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-medium text-gray-900 dark:text-gray-100 truncate">
                        {file.filename}
                      </p>
                      <p className="text-xs text-gray-500 dark:text-gray-400">
                        {formatBytes(file.file_size)} • {file.file_type} • {new Date(file.created_at).toLocaleString()}
                      </p>
                    </div>
                  </div>
                  <div className="ml-4">
                    <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200">
                      Completed
                    </span>
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Usage Guide */}
        <div className="bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-800 rounded-lg p-6">
          <h3 className="text-lg font-semibold text-blue-900 dark:text-blue-200 mb-3 flex items-center">
            <Upload className="w-5 h-5 mr-2" />
            사용 방법
          </h3>
          <ul className="space-y-2 text-sm text-blue-700 dark:text-blue-300">
            <li className="flex items-start">
              <span className="mr-2">1️⃣</span>
              <span>파일을 드래그 앤 드롭하거나 "Browse Files" 버튼을 클릭하세요</span>
            </li>
            <li className="flex items-start">
              <span className="mr-2">2️⃣</span>
              <span>최대 50GB 크기의 파일을 업로드할 수 있습니다</span>
            </li>
            <li className="flex items-start">
              <span className="mr-2">3️⃣</span>
              <span>대용량 파일은 자동으로 5MB 청크로 분할되어 안전하게 업로드됩니다</span>
            </li>
            <li className="flex items-start">
              <span className="mr-2">4️⃣</span>
              <span>업로드 중 일시정지, 재개, 취소가 가능합니다</span>
            </li>
            <li className="flex items-start">
              <span className="mr-2">5️⃣</span>
              <span>업로드된 파일은 자동으로 타입별로 분류됩니다 (Mesh, Script, Config 등)</span>
            </li>
          </ul>
        </div>

        {/* Features */}
        <div className="mt-6 grid grid-cols-1 md:grid-cols-3 gap-4">
          <div className="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
            <div className="flex items-center mb-3">
              <div className="w-10 h-10 bg-blue-100 dark:bg-blue-900 rounded-lg flex items-center justify-center mr-3">
                <Upload className="w-5 h-5 text-blue-600 dark:text-blue-400" />
              </div>
              <h4 className="text-base font-semibold text-gray-900 dark:text-gray-100">
                청크 업로드
              </h4>
            </div>
            <p className="text-sm text-gray-600 dark:text-gray-400">
              대용량 파일을 5MB 청크로 분할하여 안정적으로 업로드
            </p>
          </div>

          <div className="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
            <div className="flex items-center mb-3">
              <div className="w-10 h-10 bg-green-100 dark:bg-green-900 rounded-lg flex items-center justify-center mr-3">
                <CheckCircle className="w-5 h-5 text-green-600 dark:text-green-400" />
              </div>
              <h4 className="text-base font-semibold text-gray-900 dark:text-gray-100">
                자동 분류
              </h4>
            </div>
            <p className="text-sm text-gray-600 dark:text-gray-400">
              파일 확장자를 기반으로 7가지 타입으로 자동 분류
            </p>
          </div>

          <div className="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
            <div className="flex items-center mb-3">
              <div className="w-10 h-10 bg-purple-100 dark:bg-purple-900 rounded-lg flex items-center justify-center mr-3">
                <AlertCircle className="w-5 h-5 text-purple-600 dark:text-purple-400" />
              </div>
              <h4 className="text-base font-semibold text-gray-900 dark:text-gray-100">
                에러 복구
              </h4>
            </div>
            <p className="text-sm text-gray-600 dark:text-gray-400">
              업로드 실패 시 자동 재시도 및 일시정지/재개 기능
            </p>
          </div>
        </div>
      </div>
    </div>
  );
};

// Helper function
function formatBytes(bytes: number): string {
  if (bytes === 0) return '0 Bytes';
  const k = 1024;
  const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}

export default FileUploadPage;
