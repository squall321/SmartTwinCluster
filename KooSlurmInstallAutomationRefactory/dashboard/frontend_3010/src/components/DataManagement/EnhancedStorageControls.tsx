import React, { useState } from 'react';
import { Upload as UploadIcon, Download, Zap, Activity } from 'lucide-react';
import FileUpload from './FileUpload';
import FileDownload from './FileDownload';
import { API_CONFIG } from "../../config/api.config";

interface EnhancedStorageControlsProps {
  storageType: 'data' | 'scratch';
  selectedNode?: string;
  selectedFiles?: Array<{ path: string; name: string; isDirectory?: boolean }>;
  onUploadComplete?: () => void;
  onDownloadComplete?: () => void;
}

const EnhancedStorageControls: React.FC<EnhancedStorageControlsProps> = ({
  storageType,
  selectedNode,
  selectedFiles = [],
  onUploadComplete,
  onDownloadComplete
}) => {
  const [showUpload, setShowUpload] = useState(false);
  const [cacheStats, setCacheStats] = useState<any>(null);
  const [loadingStats, setLoadingStats] = useState(false);

  const fetchCacheStats = async () => {
    setLoadingStats(true);
    try {
      const response = await fetch(`${API_CONFIG.API_BASE_URL}/api/cache/stats`);
      if (!response.ok) {
        // API가 없으면 Mock 데이터 사용
        setCacheStats({
          enabled: false,
          message: 'Cache API not available'
        });
        return;
      }
      const data = await response.json();
      if (data.success) {
        setCacheStats(data.data);
      }
    } catch (error) {
      console.error('Failed to fetch cache stats:', error);
      // 에러 발생 시 Mock 데이터
      setCacheStats({
        enabled: false,
        message: 'Cache API not available'
      });
    } finally {
      setLoadingStats(false);
    }
  };

  const invalidateCache = async () => {
    try {
      const response = await fetch(`${API_CONFIG.API_BASE_URL}/api/cache/invalidate`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ pattern: 'storage:*' })
      });
      
      if (!response.ok) {
        alert('Cache API not available');
        return;
      }
      
      const data = await response.json();
      if (data.success) {
        alert('Cache invalidated successfully');
        fetchCacheStats();
      }
    } catch (error) {
      console.error('Failed to invalidate cache:', error);
      alert('Cache API not available');
    }
  };

  React.useEffect(() => {
    fetchCacheStats();
    // 30초마다 갱신
    const interval = setInterval(fetchCacheStats, 30000);
    return () => clearInterval(interval);
  }, []);

  return (
    <div className="space-y-4">
      {/* 컨트롤 패널 */}
      <div className="bg-white rounded-lg border border-gray-200 p-4">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-lg font-semibold text-gray-900">
            Storage Controls
          </h3>
          
          {/* 캐시 통계 */}
          {cacheStats && cacheStats.enabled && (
            <div className="flex items-center gap-3 text-sm">
              <div className="flex items-center gap-1">
                <Activity className="w-4 h-4 text-green-500" />
                <span className="text-gray-600">
                  Hit Rate: <span className="font-medium text-gray-900">
                    {cacheStats.hit_rate?.toFixed(1)}%
                  </span>
                </span>
              </div>
              <div className="text-gray-600">
                Keys: <span className="font-medium text-gray-900">
                  {cacheStats.total_keys || 0}
                </span>
              </div>
            </div>
          )}
        </div>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
          {/* 업로드 버튼 */}
          <button
            onClick={() => setShowUpload(!showUpload)}
            className="flex items-center justify-center gap-2 px-4 py-2 bg-blue-500 text-white rounded-md hover:bg-blue-600 transition-colors"
          >
            <UploadIcon className="w-4 h-4" />
            <span>{showUpload ? 'Hide Upload' : 'Upload Files'}</span>
          </button>

          {/* 다운로드 버튼 (파일 선택 시) */}
          {selectedFiles.length > 0 && (
            <div className="flex flex-col gap-2">
              {selectedFiles.map((file, idx) => (
                <FileDownload
                  key={idx}
                  filePath={file.path}
                  filename={file.name}
                  storageType={storageType}
                  node={selectedNode}
                  isDirectory={file.isDirectory}
                  onDownloadComplete={() => {
                    if (onDownloadComplete) onDownloadComplete();
                  }}
                  onDownloadError={(error) => {
                    alert(`Download failed: ${error}`);
                  }}
                />
              ))}
            </div>
          )}

          {/* 캐시 무효화 버튼 */}
          <button
            onClick={invalidateCache}
            disabled={loadingStats}
            className="flex items-center justify-center gap-2 px-4 py-2 bg-gray-500 text-white rounded-md hover:bg-gray-600 transition-colors disabled:opacity-50"
          >
            <Zap className="w-4 h-4" />
            <span>Clear Cache</span>
          </button>
        </div>
      </div>

      {/* 업로드 영역 */}
      {showUpload && (
        <div className="bg-white rounded-lg border border-gray-200 p-4">
          <h4 className="text-md font-semibold text-gray-900 mb-4">
            Upload to {storageType === 'data' ? '/data' : '/scratch'}
          </h4>
          
          <FileUpload
            destination={storageType === 'data' ? '/data/uploads/' : '/scratch/'}
            targetNodes={selectedNode ? [selectedNode] : []}
            storageType={storageType}
            onUploadComplete={(result) => {
              console.log('Upload complete:', result);
              setShowUpload(false);
              if (onUploadComplete) onUploadComplete();
            }}
          />
        </div>
      )}

      {/* 성능 정보 */}
      {cacheStats && (
        <div className="bg-gradient-to-r from-blue-50 to-indigo-50 rounded-lg border border-blue-200 p-4">
          <div className="flex items-start gap-3">
            <Zap className="w-5 h-5 text-blue-600 mt-0.5" />
            <div className="flex-1">
              <h4 className="text-sm font-semibold text-gray-900 mb-2">
                Performance Optimization Active
              </h4>
              
              <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
                <div>
                  <p className="text-gray-600">Cache Status</p>
                  <p className="font-medium text-gray-900">
                    {cacheStats.enabled && cacheStats.connected ? 
                      <span className="text-green-600">✓ Active</span> : 
                      <span className="text-gray-500">✗ Disabled</span>
                    }
                  </p>
                </div>
                
                <div>
                  <p className="text-gray-600">Total Keys</p>
                  <p className="font-medium text-gray-900">
                    {cacheStats.total_keys || 0}
                  </p>
                </div>
                
                <div>
                  <p className="text-gray-600">Cache Hits</p>
                  <p className="font-medium text-gray-900">
                    {cacheStats.hits || 0}
                  </p>
                </div>
                
                <div>
                  <p className="text-gray-600">Hit Rate</p>
                  <p className="font-medium text-gray-900">
                    {cacheStats.hit_rate?.toFixed(1) || 0}%
                  </p>
                </div>
              </div>

              <p className="text-xs text-gray-600 mt-3">
                💡 <strong>Performance:</strong> First request ~2-3s (SSH), 
                cached requests ~100ms. Cache TTL: 3-5 minutes.
              </p>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default EnhancedStorageControls;
