/**
 * UploadProgress Component
 * 개별 파일 업로드 진행률 표시
 */

import React from 'react';
import { FileUploadState } from '../../hooks/useFileUpload';
import {
  CheckCircle,
  XCircle,
  Loader,
  Pause,
  Play,
  X,
  FileIcon
} from 'lucide-react';

interface UploadProgressProps {
  state: FileUploadState;
  onCancel?: () => void;
  onPause?: () => void;
  onResume?: () => void;
  className?: string;
}

/**
 * 파일 크기 포맷
 */
const formatFileSize = (bytes: number): string => {
  if (bytes === 0) return '0 B';

  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));

  return `${(bytes / Math.pow(k, i)).toFixed(1)} ${sizes[i]}`;
};

/**
 * 상태별 아이콘 및 색상
 */
const getStatusDisplay = (status: FileUploadState['status']) => {
  switch (status) {
    case 'completed':
      return {
        icon: CheckCircle,
        color: 'text-green-600',
        bgColor: 'bg-green-50',
        text: '완료'
      };
    case 'error':
      return {
        icon: XCircle,
        color: 'text-red-600',
        bgColor: 'bg-red-50',
        text: '실패'
      };
    case 'cancelled':
      return {
        icon: XCircle,
        color: 'text-gray-600',
        bgColor: 'bg-gray-50',
        text: '취소됨'
      };
    case 'uploading':
      return {
        icon: Loader,
        color: 'text-blue-600',
        bgColor: 'bg-blue-50',
        text: '업로드 중'
      };
    case 'pending':
      return {
        icon: Pause,
        color: 'text-yellow-600',
        bgColor: 'bg-yellow-50',
        text: '일시정지'
      };
    default:
      return {
        icon: FileIcon,
        color: 'text-gray-600',
        bgColor: 'bg-gray-50',
        text: '대기 중'
      };
  }
};

export const UploadProgress: React.FC<UploadProgressProps> = ({
  state,
  onCancel,
  onPause,
  onResume,
  className = ''
}) => {
  const { icon: StatusIcon, color, bgColor, text: statusText } = getStatusDisplay(state.status);

  return (
    <div className={`border rounded-lg p-4 ${className}`}>
      {/* 파일 정보 헤더 */}
      <div className="flex items-start justify-between mb-3">
        <div className="flex items-center gap-3 flex-1 min-w-0">
          <div className={`p-2 rounded-lg ${bgColor}`}>
            <StatusIcon
              className={`w-5 h-5 ${color} ${state.status === 'uploading' ? 'animate-spin' : ''}`}
            />
          </div>

          <div className="flex-1 min-w-0">
            <h4 className="font-medium text-gray-800 truncate">
              {state.filename}
            </h4>
            <p className="text-sm text-gray-500">
              {state.session && formatFileSize(state.session.file_info.size)}
              {' · '}
              {statusText}
            </p>
          </div>
        </div>

        {/* 액션 버튼 */}
        <div className="flex items-center gap-2 ml-2">
          {state.status === 'uploading' && onPause && (
            <button
              onClick={onPause}
              className="p-1 hover:bg-gray-100 rounded transition-colors"
              title="일시정지"
            >
              <Pause className="w-4 h-4 text-gray-600" />
            </button>
          )}

          {state.status === 'pending' && onResume && (
            <button
              onClick={onResume}
              className="p-1 hover:bg-gray-100 rounded transition-colors"
              title="재개"
            >
              <Play className="w-4 h-4 text-gray-600" />
            </button>
          )}

          {(state.status === 'uploading' || state.status === 'pending') && onCancel && (
            <button
              onClick={onCancel}
              className="p-1 hover:bg-gray-100 rounded transition-colors"
              title="취소"
            >
              <X className="w-4 h-4 text-gray-600" />
            </button>
          )}
        </div>
      </div>

      {/* 진행률 바 */}
      {(state.status === 'uploading' || state.status === 'pending') && (
        <div className="space-y-2">
          <div className="w-full bg-gray-200 rounded-full h-2 overflow-hidden">
            <div
              className="bg-blue-600 h-full transition-all duration-300 ease-out"
              style={{ width: `${state.progress}%` }}
            />
          </div>

          <div className="flex justify-between text-xs text-gray-600">
            <span>
              {state.session && (
                <>
                  {state.session.total_chunks > 0
                    ? `${Math.floor((state.progress / 100) * state.session.total_chunks)} / ${state.session.total_chunks} 청크`
                    : `${state.progress.toFixed(1)}%`
                  }
                </>
              )}
            </span>
            <span>{state.progress.toFixed(1)}%</span>
          </div>
        </div>
      )}

      {/* 에러 메시지 */}
      {state.status === 'error' && state.error && (
        <div className="mt-2 p-2 bg-red-50 border border-red-200 rounded text-sm text-red-700">
          {state.error}
        </div>
      )}

      {/* 완료 정보 */}
      {state.status === 'completed' && state.result && (
        <div className="mt-2 p-2 bg-green-50 border border-green-200 rounded text-sm text-green-700">
          <div className="flex justify-between">
            <span>파일 타입:</span>
            <span className="font-medium">{state.result.file_type}</span>
          </div>
          <div className="flex justify-between mt-1">
            <span>저장 위치:</span>
            <span className="font-mono text-xs truncate max-w-xs" title={state.result.storage_path}>
              {state.result.storage_path}
            </span>
          </div>
        </div>
      )}
    </div>
  );
};

export default UploadProgress;
