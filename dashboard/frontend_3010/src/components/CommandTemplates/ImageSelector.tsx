/**
 * ImageSelector Component
 *
 * Partition별 Apptainer 이미지 목록을 표시하고 선택
 * 각 이미지의 command_templates 미리보기 제공
 */

import React, { useState, useEffect } from 'react';
import { Package, Layers, FileCode, ChevronDown, ChevronUp, Info } from 'lucide-react';
import { ApptainerImage, CommandTemplate } from '../../types/apptainer';
import { apiGet } from '../../utils/api';

interface ImageSelectorProps {
  partition: string;
  selectedImage?: ApptainerImage | null;
  onSelect: (image: ApptainerImage) => void;
  className?: string;
}

export const ImageSelector: React.FC<ImageSelectorProps> = ({
  partition,
  selectedImage,
  onSelect,
  className = '',
}) => {
  const [images, setImages] = useState<ApptainerImage[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [expandedImageId, setExpandedImageId] = useState<string | null>(null);

  // Partition 변경 시 이미지 목록 로드
  useEffect(() => {
    loadImages();
  }, [partition]);

  const loadImages = async () => {
    if (!partition) {
      setImages([]);
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const response = await apiGet(`/api/apptainer/images?partition=${partition}`);

      if (response.images) {
        setImages(response.images);
      } else {
        setError('No images found');
      }
    } catch (err: any) {
      setError(err.message || 'Failed to load images');
      setImages([]);
    } finally {
      setLoading(false);
    }
  };

  const toggleExpand = (imageId: string) => {
    setExpandedImageId(expandedImageId === imageId ? null : imageId);
  };

  const handleSelectImage = (image: ApptainerImage) => {
    onSelect(image);
  };

  if (loading) {
    return (
      <div className={`p-4 border border-gray-200 rounded-lg bg-gray-50 ${className}`}>
        <div className="flex items-center gap-2 text-gray-600">
          <div className="animate-spin rounded-full h-4 w-4 border-2 border-gray-600 border-t-transparent"></div>
          <span>Loading images for {partition}...</span>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className={`p-4 border border-red-200 rounded-lg bg-red-50 ${className}`}>
        <div className="text-red-600 text-sm">
          <strong>Error:</strong> {error}
        </div>
      </div>
    );
  }

  if (images.length === 0) {
    return (
      <div className={`p-4 border border-gray-200 rounded-lg bg-gray-50 ${className}`}>
        <div className="text-gray-600 text-sm text-center">
          No Apptainer images available for partition: <strong>{partition}</strong>
        </div>
      </div>
    );
  }

  return (
    <div className={`space-y-2 ${className}`}>
      <div className="flex items-center justify-between mb-2">
        <label className="text-sm font-medium text-gray-700">
          Select Apptainer Image
        </label>
        <span className="text-xs text-gray-500">
          {images.length} image{images.length !== 1 ? 's' : ''} available
        </span>
      </div>

      <div className="space-y-2 max-h-96 overflow-y-auto">
        {images.map((image) => {
          const isSelected = selectedImage?.id === image.id;
          const isExpanded = expandedImageId === image.id;
          const hasTemplates = image.command_templates && image.command_templates.length > 0;

          return (
            <div
              key={image.id}
              className={`border rounded-lg transition-all ${
                isSelected
                  ? 'border-blue-500 bg-blue-50 shadow-sm'
                  : 'border-gray-200 bg-white hover:border-gray-300'
              }`}
            >
              {/* Image Header */}
              <div
                className="p-3 cursor-pointer"
                onClick={() => handleSelectImage(image)}
              >
                <div className="flex items-start justify-between">
                  <div className="flex items-start gap-3 flex-1">
                    <div className={`mt-0.5 ${isSelected ? 'text-blue-600' : 'text-gray-400'}`}>
                      <Package className="w-5 h-5" />
                    </div>

                    <div className="flex-1 min-w-0">
                      <div className="font-medium text-gray-900 truncate">
                        {image.name}
                      </div>

                      {image.description && (
                        <div className="text-xs text-gray-600 mt-0.5 line-clamp-2">
                          {image.description}
                        </div>
                      )}

                      <div className="flex items-center gap-3 mt-2 text-xs text-gray-500">
                        <span className="flex items-center gap-1">
                          <Layers className="w-3 h-3" />
                          {image.version || 'N/A'}
                        </span>

                        {hasTemplates && (
                          <span className="flex items-center gap-1 text-green-600">
                            <FileCode className="w-3 h-3" />
                            {image.command_templates.length} template{image.command_templates.length !== 1 ? 's' : ''}
                          </span>
                        )}
                      </div>
                    </div>
                  </div>

                  {hasTemplates && (
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        toggleExpand(image.id);
                      }}
                      className={`ml-2 p-1 rounded hover:bg-gray-100 transition-colors ${
                        isSelected ? 'hover:bg-blue-100' : ''
                      }`}
                      title="Show command templates"
                    >
                      {isExpanded ? (
                        <ChevronUp className="w-4 h-4 text-gray-600" />
                      ) : (
                        <ChevronDown className="w-4 h-4 text-gray-600" />
                      )}
                    </button>
                  )}

                  {isSelected && (
                    <div className="ml-2 px-2 py-1 bg-blue-600 text-white text-xs font-semibold rounded">
                      Selected
                    </div>
                  )}
                </div>
              </div>

              {/* Command Templates (Expandable) */}
              {isExpanded && hasTemplates && (
                <div className="border-t border-gray-200 bg-gray-50 p-3">
                  <div className="text-xs font-semibold text-gray-700 mb-2 flex items-center gap-1">
                    <Info className="w-3 h-3" />
                    Available Command Templates:
                  </div>

                  <div className="space-y-2">
                    {image.command_templates!.map((template: CommandTemplate) => (
                      <div
                        key={template.template_id}
                        className="bg-white border border-gray-200 rounded p-2 text-xs"
                      >
                        <div className="font-medium text-gray-900">
                          {template.display_name}
                        </div>
                        <div className="text-gray-600 mt-0.5">
                          {template.description}
                        </div>

                        <div className="flex items-center gap-2 mt-1.5">
                          <span className="px-1.5 py-0.5 bg-purple-100 text-purple-700 rounded text-xs">
                            {template.category}
                          </span>

                          {template.command.requires_mpi && (
                            <span className="px-1.5 py-0.5 bg-blue-100 text-blue-700 rounded text-xs">
                              MPI
                            </span>
                          )}

                          <span className="text-gray-500">
                            {Object.keys(template.variables.input_files).length} input{Object.keys(template.variables.input_files).length !== 1 ? 's' : ''}
                          </span>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
};

export default ImageSelector;
