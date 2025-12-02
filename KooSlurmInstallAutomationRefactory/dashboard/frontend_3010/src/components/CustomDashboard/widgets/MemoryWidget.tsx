import React, { useState, useEffect } from 'react';
import { MemoryStick, GripVertical, X } from 'lucide-react';
import { WidgetProps } from '../widgetRegistry';
import { apiGet } from '../../../utils/api';

const MemoryWidget: React.FC<WidgetProps> = ({ id, onRemove, isEditMode, mode }) => {
  const [memoryData, setMemoryData] = useState({
    used: 0,
    total: 0,
    percentage: 0
  });
  const [loading, setLoading] = useState(true);
  const [usingMockData, setUsingMockData] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetchMemoryData();
    const interval = setInterval(fetchMemoryData, 5000);
    return () => clearInterval(interval);
  }, [mode]);

  const fetchMemoryData = async () => {
    setError(null);
    
    // Production mode: try real API
    if (mode === 'production') {
      try {
        // Memory usage query
        const usageResponse = await apiGet('/api/prometheus/query', {
          query: '(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100'
        });
        
        // Total memory query
        const totalResponse = await apiGet('/api/prometheus/query', {
          query: 'node_memory_MemTotal_bytes / (1024^3)'
        });
        
        if (usageResponse?.data?.result?.[0]?.value && totalResponse?.data?.result?.[0]?.value) {
          const percentage = parseFloat(usageResponse.data.result[0].value[1]);
          const total = parseFloat(totalResponse.data.result[0].value[1]);
          const used = (total * percentage) / 100;
          
          setMemoryData({ 
            used: Math.max(0, used), 
            total: Math.max(0, total), 
            percentage: Math.min(100, Math.max(0, percentage)) 
          });
          setUsingMockData(false);
          setLoading(false);
          console.log('[MemoryWidget] Successfully loaded real memory data:', percentage.toFixed(1) + '%');
          return;
        } else {
          // No data in production mode - this is NOT an error, just empty data
          console.log('[MemoryWidget] No memory data found in production mode');
          setMemoryData({ used: 0, total: 0, percentage: 0 });
          setError(null);  // NOT an error
          setUsingMockData(false);
          setLoading(false);
          return;
        }
      } catch (error) {
        // API error in production mode (network error, 500, etc)
        console.error('[MemoryWidget] Production API error:', error);
        
        // Extract error message - ApiError already contains the right message
        const errorMessage = error instanceof Error 
          ? error.message 
          : 'Failed to fetch memory data';
        
        setError(errorMessage);
        setMemoryData({ used: 0, total: 0, percentage: 0 });
        setUsingMockData(false);
        setLoading(false);
        return;
      }
    }
    
    // Mock mode: use mock data
    const percentage = 60 + Math.random() * 20;
    const total = 256;
    const used = (total * percentage) / 100;
    
    setMemoryData({ used, total, percentage });
    setUsingMockData(true);
    setLoading(false);
    console.log('[MemoryWidget] Using mock memory data:', percentage.toFixed(1) + '%');
  };

  const getStatusColor = (percentage: number) => {
    if (percentage < 70) return 'bg-green-500';
    if (percentage < 85) return 'bg-yellow-500';
    return 'bg-red-500';
  };

  const getStatusText = (percentage: number) => {
    if (percentage < 70) return 'text-green-500';
    if (percentage < 85) return 'text-yellow-500';
    return 'text-red-500';
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
          <MemoryStick className="w-5 h-5 text-purple-500" />
          <h3 className="font-semibold text-gray-900 dark:text-white">Memory Usage</h3>
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
      <div className="flex-1 flex flex-col justify-center p-6">
        {loading ? (
          <div className="text-center py-8">
            <div className="w-8 h-8 border-4 border-purple-600 border-t-transparent rounded-full animate-spin mx-auto mb-2"></div>
            <p className="text-sm text-gray-500 dark:text-gray-400">Loading...</p>
          </div>
        ) : error ? (
          <div className="text-center text-red-500 dark:text-red-400 py-8">
            <MemoryStick className="w-12 h-12 mx-auto mb-3 opacity-50" />
            <p className="font-medium">{error}</p>
            <p className="text-sm text-gray-500 dark:text-gray-400 mt-2">
              Check Prometheus or node_exporter
            </p>
          </div>
        ) : memoryData.total === 0 ? (
          <div className="text-center text-gray-500 dark:text-gray-400 py-8">
            <MemoryStick className="w-12 h-12 mx-auto mb-3 opacity-50" />
            <p className="font-medium">No data available</p>
            <p className="text-sm text-gray-500 dark:text-gray-400 mt-2">
              {mode === 'production' ? 'Check Prometheus setup' : 'Try mock mode'}
            </p>
          </div>
        ) : (
          <div>
            {/* Progress Bar */}
            <div className="mb-4">
              <div className="flex items-center justify-between mb-2">
                <span className={`text-2xl font-bold ${getStatusText(memoryData.percentage)}`}>
                  {memoryData.percentage.toFixed(1)}%
                </span>
                <span className="text-sm text-gray-500 dark:text-gray-400">
                  {memoryData.used.toFixed(1)} / {memoryData.total.toFixed(1)} GB
                </span>
              </div>
              
              <div className="w-full bg-gray-200 dark:bg-gray-700 rounded-full h-4 overflow-hidden">
                <div
                  className={`h-full ${getStatusColor(memoryData.percentage)} transition-all duration-500 rounded-full`}
                  style={{ width: `${memoryData.percentage}%` }}
                />
              </div>
            </div>

            {/* Stats */}
            <div className="grid grid-cols-2 gap-3 mt-4">
              <div className="bg-gray-50 dark:bg-gray-700/50 rounded-lg p-3">
                <div className="text-xs text-gray-500 dark:text-gray-400 mb-1">In Use</div>
                <div className="text-lg font-semibold text-gray-900 dark:text-white">
                  {memoryData.used.toFixed(1)} GB
                </div>
              </div>
              
              <div className="bg-gray-50 dark:bg-gray-700/50 rounded-lg p-3">
                <div className="text-xs text-gray-500 dark:text-gray-400 mb-1">Available</div>
                <div className="text-lg font-semibold text-gray-900 dark:text-white">
                  {(memoryData.total - memoryData.used).toFixed(1)} GB
                </div>
              </div>
            </div>

            {/* Status Text */}
            <div className="mt-3 text-center text-sm text-gray-600 dark:text-gray-400">
              {memoryData.percentage < 70 && 'Healthy'}
              {memoryData.percentage >= 70 && memoryData.percentage < 85 && 'Warning'}
              {memoryData.percentage >= 85 && 'High Usage'}
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

export default MemoryWidget;
