/**
 * File Upload Test Page
 * UnifiedUploader 컴포넌트 테스트 페이지
 */

import React, { useState } from 'react';
import { UnifiedUploader } from '../components/FileUpload';
import { UploadedFile } from '../types/upload';

export const FileUploadTest: React.FC = () => {
  const [completedUploads, setCompletedUploads] = useState<UploadedFile[]>([]);

  const handleComplete = (files: UploadedFile[]) => {
    console.log('Upload completed:', files);
    setCompletedUploads(prev => [...prev, ...files]);
  };

  const handleError = (error: Error) => {
    console.error('Upload error:', error);
    alert(`업로드 오류: ${error.message}`);
  };

  return (
    <div className="min-h-screen bg-gray-50 p-8">
      <div className="max-w-6xl mx-auto">
        {/* 헤더 */}
        <div className="mb-8">
          <h1 className="text-3xl font-bold text-gray-900 mb-2">
            파일 업로드 테스트
          </h1>
          <p className="text-gray-600">
            Phase 3: Unified File Upload API - Frontend 컴포넌트 테스트
          </p>
        </div>

        {/* 업로더 */}
        <div className="bg-white rounded-lg shadow-md p-6 mb-8">
          <UnifiedUploader
            userId="test_user"
            jobId="test_job_001"
            onComplete={handleComplete}
            onError={handleError}
            maxFileSize={50 * 1024 * 1024 * 1024} // 50GB
            maxFiles={20}
            enableChunking={true}
            chunkSize={5 * 1024 * 1024} // 5MB
          />
        </div>

        {/* 완료된 업로드 목록 */}
        {completedUploads.length > 0 && (
          <div className="bg-white rounded-lg shadow-md p-6">
            <h2 className="text-xl font-semibold text-gray-900 mb-4">
              완료된 업로드 ({completedUploads.length}개)
            </h2>

            <div className="space-y-4">
              {completedUploads.map((file, index) => (
                <div
                  key={index}
                  className="border rounded-lg p-4 hover:bg-gray-50 transition-colors"
                >
                  <div className="flex items-start justify-between mb-2">
                    <div>
                      <h3 className="font-medium text-gray-800">
                        {file.filename}
                      </h3>
                      <p className="text-sm text-gray-500">
                        Upload ID: {file.upload_id}
                      </p>
                    </div>
                    <span className="px-3 py-1 bg-green-100 text-green-800 text-sm font-medium rounded-full">
                      {file.file_type}
                    </span>
                  </div>

                  <div className="grid grid-cols-2 gap-4 text-sm">
                    <div>
                      <span className="text-gray-600">파일 크기:</span>
                      <span className="ml-2 text-gray-800">
                        {(file.file_size / (1024 * 1024)).toFixed(2)} MB
                      </span>
                    </div>

                    <div>
                      <span className="text-gray-600">청크 수:</span>
                      <span className="ml-2 text-gray-800">
                        {file.total_chunks}개
                      </span>
                    </div>

                    <div className="col-span-2">
                      <span className="text-gray-600">저장 경로:</span>
                      <code className="ml-2 text-xs text-gray-800 bg-gray-100 px-2 py-1 rounded">
                        {file.storage_path}
                      </code>
                    </div>

                    {file.file_path && (
                      <div className="col-span-2">
                        <span className="text-gray-600">파일 경로:</span>
                        <code className="ml-2 text-xs text-gray-800 bg-gray-100 px-2 py-1 rounded">
                          {file.file_path}
                        </code>
                      </div>
                    )}

                    <div>
                      <span className="text-gray-600">생성 시각:</span>
                      <span className="ml-2 text-gray-800">
                        {new Date(file.created_at).toLocaleString('ko-KR')}
                      </span>
                    </div>

                    {file.completed_at && (
                      <div>
                        <span className="text-gray-600">완료 시각:</span>
                        <span className="ml-2 text-gray-800">
                          {new Date(file.completed_at).toLocaleString('ko-KR')}
                        </span>
                      </div>
                    )}
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* API 테스트 정보 */}
        <div className="mt-8 p-4 bg-blue-50 border border-blue-200 rounded-lg">
          <h3 className="font-semibold text-blue-900 mb-2">
            API 엔드포인트
          </h3>
          <ul className="text-sm text-blue-800 space-y-1">
            <li>• POST /api/v2/files/upload/init - 업로드 세션 초기화</li>
            <li>• POST /api/v2/files/upload/chunk - 청크 업로드</li>
            <li>• POST /api/v2/files/upload/complete - 업로드 완료</li>
            <li>• GET /api/v2/files/uploads - 업로드 목록 조회</li>
            <li>• DELETE /api/v2/files/uploads/:id - 업로드 취소</li>
          </ul>
        </div>
      </div>
    </div>
  );
};

export default FileUploadTest;
