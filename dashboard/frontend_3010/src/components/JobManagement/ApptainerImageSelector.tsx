/**
 * Apptainer 이미지 선택 컴포넌트
 * Template 설정에 따라 동적으로 이미지 선택 UI 제공
 */

import React, { useState, useEffect } from 'react';
import { apiGet } from '../../utils/api';
import toast from 'react-hot-toast';
import { Package, CheckCircle, AlertCircle } from 'lucide-react';

export interface ApptainerImage {
  id: string;
  name: string;
  path: string;
  partition: string;
  type: string;
  version: string;
  description?: string;
  size?: number;
}

export interface ApptainerConfig {
  mode: 'fixed' | 'partition' | 'specific' | 'any';
  image_name?: string;  // mode='fixed'일 때
  partition?: string;  // mode='partition'일 때
  allowed_images?: string[];  // mode='specific'일 때
  default_image?: string;
  required: boolean;
  user_selectable: boolean;
}

interface ApptainerImageSelectorProps {
  config: ApptainerConfig;
  onSelect: (image: ApptainerImage | null) => void;
  selectedImage?: ApptainerImage | null;
  className?: string;
}

export const ApptainerImageSelector: React.FC<ApptainerImageSelectorProps> = ({
  config,
  onSelect,
  selectedImage,
  className = ''
}) => {
  const [images, setImages] = useState<ApptainerImage[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // 이미지 목록 로드
  useEffect(() => {
    const loadImages = async () => {
      try {
        setLoading(true);
        setError(null);

        // mode에 따라 필터링
        let url = '/api/apptainer/images';

        if (config.mode === 'partition' && config.partition) {
          url += `?partition=${config.partition}`;
        }

        const response = await apiGet<{
          images: ApptainerImage[];
          total: number;
        }>(url);

        let filteredImages = response.images || [];

        // mode='specific'일 때 allowed_images로 필터링
        if (config.mode === 'specific' && config.allowed_images) {
          filteredImages = filteredImages.filter(img =>
            config.allowed_images!.includes(img.name)
          );
        }

        setImages(filteredImages);

        // 기본 이미지 자동 선택
        if (!selectedImage && config.default_image && filteredImages.length > 0) {
          const defaultImg = filteredImages.find(img => img.name === config.default_image);
          if (defaultImg) {
            onSelect(defaultImg);
          }
        }

      } catch (err) {
        console.error('Failed to load Apptainer images:', err);
        setError('Failed to load images');
        toast.error('Failed to load Apptainer images');
      } finally {
        setLoading(false);
      }
    };

    if (config.user_selectable) {
      loadImages();
    }
  }, [config, selectedImage, onSelect]);

  // mode='fixed'일 때는 선택 UI 표시 안 함
  if (!config.user_selectable || config.mode === 'fixed') {
    return (
      <div className={`bg-gray-50 p-4 rounded-lg ${className}`}>
        <div className="flex items-center gap-2 text-sm text-gray-700">
          <Package className="w-4 h-4" />
          <span className="font-medium">Apptainer Image:</span>
          <code className="bg-gray-200 px-2 py-1 rounded text-xs">
            {config.image_name || 'Not specified'}
          </code>
        </div>
      </div>
    );
  }

  // 로딩 상태
  if (loading) {
    return (
      <div className={`bg-gray-50 p-4 rounded-lg ${className}`}>
        <div className="flex items-center gap-2">
          <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-blue-600"></div>
          <span className="text-sm text-gray-600">Loading images...</span>
        </div>
      </div>
    );
  }

  // 에러 상태
  if (error) {
    return (
      <div className={`bg-red-50 p-4 rounded-lg border border-red-200 ${className}`}>
        <div className="flex items-center gap-2 text-sm text-red-700">
          <AlertCircle className="w-4 h-4" />
          <span>{error}</span>
        </div>
      </div>
    );
  }

  // 이미지 없음
  if (images.length === 0) {
    return (
      <div className={`bg-amber-50 p-4 rounded-lg border border-amber-200 ${className}`}>
        <div className="flex items-center gap-2 text-sm text-amber-700">
          <AlertCircle className="w-4 h-4" />
          <span>No Apptainer images available for this partition</span>
        </div>
      </div>
    );
  }

  // 선택 UI
  return (
    <div className={className}>
      <label className="block text-sm font-medium text-gray-700 mb-2">
        Apptainer Image {config.required && <span className="text-red-500">*</span>}
      </label>

      <div className="space-y-2">
        {images.map((image) => (
          <div
            key={image.id}
            onClick={() => onSelect(image)}
            className={`
              relative p-4 rounded-lg border-2 cursor-pointer transition-all
              ${selectedImage?.id === image.id
                ? 'border-blue-500 bg-blue-50'
                : 'border-gray-200 hover:border-gray-300 bg-white'
              }
            `}
          >
            <div className="flex items-start justify-between">
              <div className="flex-1">
                <div className="flex items-center gap-2">
                  <Package className="w-4 h-4 text-gray-600" />
                  <span className="font-medium text-gray-900">{image.name}</span>
                  {selectedImage?.id === image.id && (
                    <CheckCircle className="w-4 h-4 text-blue-500" />
                  )}
                </div>

                {image.description && (
                  <p className="mt-1 text-sm text-gray-600">{image.description}</p>
                )}

                <div className="mt-2 flex flex-wrap gap-3 text-xs text-gray-500">
                  {image.version && image.version !== 'unknown' && (
                    <span className="bg-gray-100 px-2 py-1 rounded">
                      v{image.version}
                    </span>
                  )}
                  {image.partition && (
                    <span className="bg-blue-100 text-blue-700 px-2 py-1 rounded">
                      {image.partition}
                    </span>
                  )}
                  {image.type && (
                    <span className="bg-gray-100 px-2 py-1 rounded">
                      {image.type}
                    </span>
                  )}
                  {image.size && (
                    <span className="bg-gray-100 px-2 py-1 rounded">
                      {formatBytes(image.size)}
                    </span>
                  )}
                </div>

                <div className="mt-2 text-xs text-gray-400 font-mono">
                  {image.path}
                </div>
              </div>
            </div>
          </div>
        ))}
      </div>

      {/* 선택된 이미지 정보 */}
      {selectedImage && (
        <div className="mt-3 p-3 bg-green-50 border border-green-200 rounded-lg">
          <div className="flex items-center gap-2 text-sm text-green-700">
            <CheckCircle className="w-4 h-4" />
            <span className="font-medium">Selected:</span>
            <code className="text-xs">{selectedImage.name}</code>
          </div>
        </div>
      )}
    </div>
  );
};

// 파일 크기 포맷팅
function formatBytes(bytes: number): string {
  if (bytes === 0) return '0 Bytes';

  const k = 1024;
  const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));

  return Math.round((bytes / Math.pow(k, i)) * 100) / 100 + ' ' + sizes[i];
}
