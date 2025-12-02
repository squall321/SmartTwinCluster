/**
 * ApptainerSelector Component
 *
 * Apptainer 이미지 선택 컴포넌트
 * Job Submit 시 사용 가능한 .sif 이미지를 선택할 수 있습니다.
 *
 * Features:
 * - 파티션별 이미지 필터링 (compute, viz)
 * - 이미지 타입별 구분 (viz, compute, custom)
 * - 검색 기능
 * - 이미지 메타데이터 표시 (크기, 버전, 설명)
 * - 앱 목록 표시
 */

import React, { useState, useEffect, useMemo } from 'react';
import { useApptainerImages } from '../hooks/useApptainerImages';

export interface ApptainerImage {
  id: string;
  name: string;
  path: string;
  node: string;
  partition: string;
  type: 'viz' | 'compute' | 'custom';
  size: number;
  version: string;
  description: string;
  labels: Record<string, string>;
  apps: string[];
  runscript: string;
  env_vars: Record<string, string>;
  created_at: string;
  updated_at: string;
  last_scanned: string;
  is_active: boolean;
}

export interface ApptainerSelectorProps {
  partition?: 'compute' | 'viz' | null;
  selectedImageId?: string;
  onSelect: (image: ApptainerImage | null) => void;
  disabled?: boolean;
}

export const ApptainerSelector: React.FC<ApptainerSelectorProps> = ({
  partition = null,
  selectedImageId,
  onSelect,
  disabled = false
}) => {
  const { images, loading, error, refreshImages } = useApptainerImages(partition);
  const [searchQuery, setSearchQuery] = useState('');
  const [filterType, setFilterType] = useState<string>('all');
  const [expandedImageId, setExpandedImageId] = useState<string | null>(null);

  // 검색 및 필터링된 이미지 목록
  const filteredImages = useMemo(() => {
    let filtered = images;

    // 타입 필터
    if (filterType !== 'all') {
      filtered = filtered.filter(img => img.type === filterType);
    }

    // 검색 필터
    if (searchQuery) {
      const query = searchQuery.toLowerCase();
      filtered = filtered.filter(img =>
        img.name.toLowerCase().includes(query) ||
        img.description.toLowerCase().includes(query) ||
        img.apps.some(app => app.toLowerCase().includes(query))
      );
    }

    return filtered;
  }, [images, filterType, searchQuery]);

  // 선택된 이미지
  const selectedImage = useMemo(() => {
    return images.find(img => img.id === selectedImageId) || null;
  }, [images, selectedImageId]);

  // 이미지 선택 핸들러
  const handleSelectImage = (image: ApptainerImage) => {
    if (disabled) return;

    if (selectedImageId === image.id) {
      onSelect(null); // 토글: 이미 선택된 경우 선택 해제
    } else {
      onSelect(image);
    }
  };

  // 파일 크기 포맷팅
  const formatSize = (bytes: number): string => {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    let size = bytes;
    let unitIndex = 0;

    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }

    return `${size.toFixed(2)} ${units[unitIndex]}`;
  };

  // 이미지 타입 뱃지 색상
  const getTypeBadgeColor = (type: string): string => {
    switch (type) {
      case 'viz':
        return 'bg-purple-100 text-purple-800 dark:bg-purple-900 dark:text-purple-200';
      case 'compute':
        return 'bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200';
      case 'custom':
        return 'bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-200';
      default:
        return 'bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-200';
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center p-8">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
        <span className="ml-3 text-gray-600 dark:text-gray-400">
          Apptainer 이미지 로딩 중...
        </span>
      </div>
    );
  }

  if (error) {
    return (
      <div className="bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg p-4">
        <div className="flex items-start">
          <svg className="h-5 w-5 text-red-600 dark:text-red-400 mt-0.5" fill="currentColor" viewBox="0 0 20 20">
            <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clipRule="evenodd" />
          </svg>
          <div className="ml-3">
            <h3 className="text-sm font-medium text-red-800 dark:text-red-300">
              이미지 로드 실패
            </h3>
            <p className="mt-1 text-sm text-red-700 dark:text-red-400">{error}</p>
            <button
              onClick={refreshImages}
              className="mt-2 text-sm text-red-600 dark:text-red-400 hover:text-red-500 dark:hover:text-red-300 font-medium"
            >
              다시 시도
            </button>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {/* 헤더 */}
      <div className="flex items-center justify-between">
        <h3 className="text-lg font-semibold text-gray-900 dark:text-gray-100">
          Apptainer 이미지 선택
        </h3>
        <button
          onClick={refreshImages}
          disabled={disabled}
          className="text-sm text-blue-600 dark:text-blue-400 hover:text-blue-500 dark:hover:text-blue-300 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          🔄 새로고침
        </button>
      </div>

      {/* 검색 및 필터 */}
      <div className="flex gap-3">
        <input
          type="text"
          placeholder="이미지 검색..."
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          disabled={disabled}
          className="flex-1 px-4 py-2 border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 focus:ring-2 focus:ring-blue-500 focus:border-transparent disabled:opacity-50 disabled:cursor-not-allowed"
        />
        <select
          value={filterType}
          onChange={(e) => setFilterType(e.target.value)}
          disabled={disabled}
          className="px-4 py-2 border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 focus:ring-2 focus:ring-blue-500 focus:border-transparent disabled:opacity-50 disabled:cursor-not-allowed"
        >
          <option value="all">모든 타입</option>
          <option value="viz">Visualization</option>
          <option value="compute">Compute</option>
          <option value="custom">Custom</option>
        </select>
      </div>

      {/* 선택된 이미지 정보 */}
      {selectedImage && (
        <div className="bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-800 rounded-lg p-4">
          <div className="flex items-start justify-between">
            <div>
              <p className="text-sm font-medium text-blue-900 dark:text-blue-200">
                선택된 이미지
              </p>
              <p className="mt-1 text-lg font-semibold text-blue-700 dark:text-blue-300">
                {selectedImage.name}
              </p>
              <p className="mt-1 text-sm text-blue-600 dark:text-blue-400">
                {selectedImage.path}
              </p>
            </div>
            <button
              onClick={() => onSelect(null)}
              disabled={disabled}
              className="text-blue-600 dark:text-blue-400 hover:text-blue-500 dark:hover:text-blue-300 disabled:opacity-50"
            >
              ✕
            </button>
          </div>
        </div>
      )}

      {/* 이미지 목록 */}
      <div className="space-y-2 max-h-96 overflow-y-auto">
        {filteredImages.length === 0 ? (
          <div className="text-center py-8 text-gray-500 dark:text-gray-400">
            {searchQuery ? '검색 결과가 없습니다.' : '사용 가능한 이미지가 없습니다.'}
          </div>
        ) : (
          filteredImages.map((image) => (
            <div
              key={image.id}
              className={`border rounded-lg p-4 cursor-pointer transition-all ${
                selectedImageId === image.id
                  ? 'border-blue-500 bg-blue-50 dark:bg-blue-900/20'
                  : 'border-gray-200 dark:border-gray-700 hover:border-gray-300 dark:hover:border-gray-600'
              } ${disabled ? 'opacity-50 cursor-not-allowed' : ''}`}
              onClick={() => handleSelectImage(image)}
            >
              <div className="flex items-start justify-between">
                <div className="flex-1 min-w-0">
                  {/* 이미지 이름 및 타입 */}
                  <div className="flex items-center gap-2">
                    <h4 className="text-base font-semibold text-gray-900 dark:text-gray-100 truncate">
                      {image.name}
                    </h4>
                    <span className={`px-2 py-0.5 text-xs font-medium rounded-full ${getTypeBadgeColor(image.type)}`}>
                      {image.type}
                    </span>
                  </div>

                  {/* 설명 */}
                  {image.description && (
                    <p className="mt-1 text-sm text-gray-600 dark:text-gray-400 line-clamp-2">
                      {image.description}
                    </p>
                  )}

                  {/* 메타데이터 */}
                  <div className="mt-2 flex flex-wrap gap-3 text-xs text-gray-500 dark:text-gray-400">
                    <span>📦 {formatSize(image.size)}</span>
                    <span>🏷️ v{image.version}</span>
                    <span>💻 {image.node}</span>
                    {image.apps.length > 0 && (
                      <span>📱 {image.apps.length} apps</span>
                    )}
                  </div>

                  {/* 앱 목록 (확장 시) */}
                  {expandedImageId === image.id && image.apps.length > 0 && (
                    <div className="mt-3 pt-3 border-t border-gray-200 dark:border-gray-700">
                      <p className="text-xs font-medium text-gray-700 dark:text-gray-300 mb-2">
                        사용 가능한 앱:
                      </p>
                      <div className="flex flex-wrap gap-1">
                        {image.apps.map((app, idx) => (
                          <span
                            key={idx}
                            className="px-2 py-1 text-xs bg-gray-100 dark:bg-gray-800 text-gray-700 dark:text-gray-300 rounded"
                          >
                            {app}
                          </span>
                        ))}
                      </div>
                    </div>
                  )}
                </div>

                {/* 확장 버튼 */}
                {image.apps.length > 0 && (
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      setExpandedImageId(expandedImageId === image.id ? null : image.id);
                    }}
                    className="ml-2 text-gray-400 hover:text-gray-600 dark:hover:text-gray-300"
                  >
                    {expandedImageId === image.id ? '▲' : '▼'}
                  </button>
                )}
              </div>
            </div>
          ))
        )}
      </div>

      {/* 통계 */}
      <div className="text-sm text-gray-500 dark:text-gray-400">
        {filteredImages.length}개의 이미지
        {partition && ` (${partition} 파티션)`}
      </div>
    </div>
  );
};

export default ApptainerSelector;
