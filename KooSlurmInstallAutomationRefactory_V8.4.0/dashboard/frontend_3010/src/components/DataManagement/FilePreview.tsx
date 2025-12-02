import React, { useState, useEffect } from 'react';
import { X, FileText, Image as ImageIcon, Download, RefreshCw, Maximize2 } from 'lucide-react';
import { API_CONFIG } from "../../config/api.config";

interface FilePreviewProps {
  filePath: string;
  fileName: string;
  onClose: () => void;
}

const FilePreview: React.FC<FilePreviewProps> = ({ filePath, fileName, onClose }) => {
  const [fileType, setFileType] = useState<'text' | 'image' | 'unsupported' | null>(null);
  const [content, setContent] = useState<string>('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [fileInfo, setFileInfo] = useState<any>(null);
  const [showFullscreen, setShowFullscreen] = useState(false);

  useEffect(() => {
    checkFileType();
  }, [filePath]);

  const checkFileType = async () => {
    setLoading(true);
    setError(null);

    try {
      const response = await fetch(`${API_CONFIG.API_BASE_URL}/api/preview/type`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ path: filePath })
      });

      const data = await response.json();

      if (data.success) {
        setFileInfo(data);
        setFileType(data.type);

        if (data.previewable) {
          if (data.type === 'text') {
            loadTextContent();
          } else if (data.type === 'image') {
            // 이미지는 URL로 로드
            setContent(`${API_CONFIG.API_BASE_URL}/api/preview/image?path=${encodeURIComponent(filePath)}`);
            setLoading(false);
          }
        } else {
          setError(data.too_large ? 'File too large for preview (max 10MB)' : 'File type not supported for preview');
          setLoading(false);
        }
      } else {
        setError(data.error || 'Failed to check file type');
        setLoading(false);
      }
    } catch (err) {
      setError('Failed to load file preview');
      setLoading(false);
    }
  };

  const loadTextContent = async () => {
    try {
      const response = await fetch(`${API_CONFIG.API_BASE_URL}/api/preview/text`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ 
          path: filePath,
          lines: 500  // 처음 500줄만
        })
      });

      const data = await response.json();

      if (data.success) {
        setContent(data.content);
      } else {
        setError(data.error || 'Failed to load text content');
      }
    } catch (err) {
      setError('Failed to load text content');
    } finally {
      setLoading(false);
    }
  };

  const loadTail = async () => {
    setLoading(true);
    try {
      const response = await fetch(`${API_CONFIG.API_BASE_URL}/api/preview/tail`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ 
          path: filePath,
          lines: 500
        })
      });

      const data = await response.json();

      if (data.success) {
        setContent(data.content);
      } else {
        setError(data.error || 'Failed to load tail');
      }
    } catch (err) {
      setError('Failed to load tail');
    } finally {
      setLoading(false);
    }
  };

  const formatFileSize = (bytes: number) => {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(2)} KB`;
    return `${(bytes / 1024 / 1024).toFixed(2)} MB`;
  };

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
      <div className={`bg-gray-800 rounded-lg border border-gray-700 overflow-hidden ${
        showFullscreen ? 'w-full h-full' : 'max-w-4xl w-full max-h-[90vh]'
      }`}>
        {/* Header */}
        <div className="bg-gradient-to-r from-blue-900/40 to-purple-900/40 border-b border-gray-700 px-4 py-3">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3 flex-1 min-w-0">
              {fileType === 'text' ? (
                <FileText className="w-5 h-5 text-blue-400 flex-shrink-0" />
              ) : fileType === 'image' ? (
                <ImageIcon className="w-5 h-5 text-purple-400 flex-shrink-0" />
              ) : (
                <FileText className="w-5 h-5 text-gray-400 flex-shrink-0" />
              )}
              <div className="flex-1 min-w-0">
                <h3 className="text-sm font-bold text-gray-50 truncate">{fileName}</h3>
                {fileInfo && (
                  <p className="text-xs text-gray-400 truncate">
                    {formatFileSize(fileInfo.size)} • {fileInfo.mime_type || 'Unknown type'}
                  </p>
                )}
              </div>
            </div>

            <div className="flex items-center gap-2 ml-4">
              {fileType === 'text' && (
                <>
                  <button
                    onClick={loadTail}
                    disabled={loading}
                    className="p-1.5 text-gray-400 hover:text-gray-200 transition disabled:opacity-50"
                    title="Show last 500 lines"
                  >
                    <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
                  </button>
                  <button
                    onClick={() => setShowFullscreen(!showFullscreen)}
                    className="p-1.5 text-gray-400 hover:text-gray-200 transition"
                    title="Toggle fullscreen"
                  >
                    <Maximize2 className="w-4 h-4" />
                  </button>
                </>
              )}
              <button
                onClick={onClose}
                className="p-1.5 text-gray-400 hover:text-gray-200 transition"
              >
                <X className="w-4 h-4" />
              </button>
            </div>
          </div>
        </div>

        {/* Content */}
        <div className={`overflow-auto ${showFullscreen ? 'h-[calc(100vh-120px)]' : 'max-h-[calc(90vh-120px)]'}`}>
          {loading ? (
            <div className="flex items-center justify-center py-12">
              <RefreshCw className="w-8 h-8 text-blue-400 animate-spin" />
              <span className="ml-3 text-gray-300">Loading preview...</span>
            </div>
          ) : error ? (
            <div className="flex flex-col items-center justify-center py-12 px-4">
              <FileText className="w-12 h-12 text-gray-500 mb-3" />
              <p className="text-gray-400 text-center">{error}</p>
            </div>
          ) : fileType === 'text' ? (
            <pre className="p-4 text-xs text-gray-200 font-mono whitespace-pre-wrap break-words bg-gray-900">
              {content}
            </pre>
          ) : fileType === 'image' ? (
            <div className="p-4 flex items-center justify-center bg-gray-900">
              <img 
                src={content} 
                alt={fileName}
                className="max-w-full max-h-full object-contain"
                style={{ maxHeight: showFullscreen ? 'calc(100vh - 200px)' : '70vh' }}
              />
            </div>
          ) : (
            <div className="flex flex-col items-center justify-center py-12 px-4">
              <FileText className="w-12 h-12 text-gray-500 mb-3" />
              <p className="text-gray-400 text-center">Preview not available for this file type</p>
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="border-t border-gray-700 px-4 py-3 bg-gray-800/50">
          <div className="flex items-center justify-between text-xs text-gray-400">
            <span>
              {fileType === 'text' && content && (
                <>Lines: {content.split('\n').length}</>
              )}
            </span>
            <span className="font-mono">{filePath}</span>
          </div>
        </div>
      </div>
    </div>
  );
};

export default FilePreview;
