import React, { useState, useEffect } from 'react';
import { HardDrive, GripVertical, X, AlertTriangle } from 'lucide-react';
import { WidgetProps } from '../widgetRegistry';
import { apiGet } from '../../../utils/api';

interface StorageInfo {
  name: string;
  used: number;
  total: number;
  percentage: number;
}

const StorageWidget: React.FC<WidgetProps> = ({ id, onRemove, isEditMode, mode }) => {
  const [storages, setStorages] = useState<StorageInfo[]>([]);
  const [loading, setLoading] = useState(true);
  const [usingMockData, setUsingMockData] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetchStorageData();
    const interval = setInterval(fetchStorageData, 30000);
    return () => clearInterval(interval);
  }, [mode]);

  const fetchStorageData = async () => {
    setError(null);
    
    // Production 모드: 실제 API 시도
    if (mode === 'production') {
      try {
        const response = await apiGet('/api/storage/usage');
        if (response?.storages && Array.isArray(response.storages)) {
          // API 응답을 위젯 형식으로 변환
          const formatted = response.storages.map((s: any) => ({
            name: s.path || s.name || 'Unknown',
            used: parseFloat(s.used_gb || s.used || 0),
            total: parseFloat(s.total_gb || s.total || 1),
            percentage: parseFloat(s.usage_percent || s.percentage || 0)
          }));
          setStorages(formatted);
          setUsingMockData(false);
          setLoading(false);
          console.log('[StorageWidget] Successfully loaded', formatted.length, 'storage info');
          return;
        } else {
          setError('Storage information not found');
          setStorages([]);
          setUsingMockData(false);
          setLoading(false);
          return;
        }
      } catch (error) {
        console.error('[StorageWidget] Production API error:', error);
        setError('Failed to fetch storage data');
        setStorages([]);
        setUsingMockData(false);
        setLoading(false);
        return;
      }
    }
    
    // Mock 모드: Mock 데이터 사용
    setStorages([
      { name: '/home', used: 850, total: 1000, percentage: 85 },
      { name: '/scratch', used: 4500, total: 10000, percentage: 45 },
      { name: '/data', used: 1800, total: 5000, percentage: 36 }
    ]);
    setUsingMockData(true);
    setLoading(false);
    console.log('[StorageWidget] Using mock storage data');
  };

  const getStorageColor = (percentage: number) => {
    if (percentage < 70) return 'bg-green-500';
    if (percentage < 85) return 'bg-yellow-500';
    return 'bg-red-500';
  };

  const formatSize = (gb: number) => {
    if (gb >= 1000) return `${(gb / 1000).toFixed(1)} TB`;
    return `${gb.toFixed(0)} GB`;
  };

  return (
    <div className="h-full flex flex-col">
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-3 border-b border-gray-200 dark:border-gray-700">
        <div className="flex items-center gap-2">
          {isEditMode && (
            <div className="drag-handle cursor-move">
              <GripVertical className="w-4 h-4 text-gray-400" />
            </div>
          )}
          <HardDrive className="w-5 h-5 text-pink-500" />
          <h3 className="font-semibold text-gray-900 dark:text-white">Storage</h3>
          {mode === 'mock' && usingMockData && (
            <span className="text-xs bg-amber-100 dark:bg-amber-900/30 text-amber-700 dark:text-amber-400 px-2 py-0.5 rounded">
              Mock
            </span>
          )}
          {mode === 'production' && !usingMockData && !loading && !error && (
            <span className="text-xs bg-gray-100 dark:bg-gray-700 text-gray-600 dark:text-gray-400 px-2 py-0.5 rounded">
              Production
            </span>
          )}
        </div>
        {isEditMode && (
          <button
            onClick={onRemove}
            className="p-1 hover:bg-gray-100 dark:hover:bg-gray-700 rounded transition-colors"
          >
            <X className="w-4 h-4 text-gray-400" />
          </button>
        )}
      </div>

      {/* Content */}
      <div className="flex-1 overflow-y-auto p-4">
        {loading ? (
          <div className="text-center py-8">
            <div className="w-8 h-8 border-4 border-pink-600 border-t-transparent rounded-full animate-spin mx-auto mb-2"></div>
            <p className="text-sm text-gray-500 dark:text-gray-400">Loading...</p>
          </div>
        ) : error ? (
          <div className="text-center text-red-500 dark:text-red-400 py-8">
            <HardDrive className="w-12 h-12 mx-auto mb-3 opacity-50" />
            <p className="font-medium">{error}</p>
            <p className="text-sm text-gray-500 dark:text-gray-400 mt-2">
              Check Storage API
            </p>
          </div>
        ) : storages.length === 0 ? (
          <div className="text-center text-gray-500 dark:text-gray-400 py-8">
            <HardDrive className="w-12 h-12 mx-auto mb-3 opacity-50" />
            <p className="font-medium">No Storage Information</p>
            {mode === 'production' && (
              <p className="text-sm mt-2">
                No mounted storage or unable to fetch information
              </p>
            )}
          </div>
        ) : (
          <div className="space-y-4">
            {storages.map((storage, index) => (
              <div key={index} className="bg-gray-50 dark:bg-gray-700/50 rounded-lg p-4">
                <div className="flex items-center justify-between mb-3">
                  <div className="flex items-center gap-2">
                    <HardDrive className="w-5 h-5 text-gray-500 dark:text-gray-400" />
                    <span className="font-semibold text-gray-900 dark:text-white">
                      {storage.name}
                    </span>
                  </div>
                  {storage.percentage > 85 && (
                    <AlertTriangle className="w-5 h-5 text-red-500" />
                  )}
                </div>

                <div className="mb-2">
                  <div className="flex items-center justify-between text-sm text-gray-600 dark:text-gray-400 mb-1">
                    <span>{formatSize(storage.used)} / {formatSize(storage.total)}</span>
                    <span className="font-semibold">{storage.percentage.toFixed(1)}%</span>
                  </div>
                  
                  <div className="w-full bg-gray-200 dark:bg-gray-600 rounded-full h-3 overflow-hidden">
                    <div
                      className={`h-full ${getStorageColor(storage.percentage)} transition-all duration-500`}
                      style={{ width: `${storage.percentage}%` }}
                    />
                  </div>
                </div>

                {storage.percentage > 85 && (
                  <div className="text-xs text-red-600 dark:text-red-400 mt-2">
                    ⚠️ Low storage space
                  </div>
                )}
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
};

export default StorageWidget;
