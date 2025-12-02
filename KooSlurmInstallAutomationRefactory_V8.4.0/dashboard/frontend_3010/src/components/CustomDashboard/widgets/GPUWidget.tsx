import React, { useState, useEffect } from 'react';
import { Monitor, GripVertical, X, Activity } from 'lucide-react';
import { WidgetProps } from '../widgetRegistry';
import { apiGet } from '../../../utils/api';

interface GPUInfo {
  id: number;
  utilization: number;
  memory: number;
  temperature: number;
}

const GPUWidget: React.FC<WidgetProps> = ({ id, onRemove, isEditMode, mode }) => {
  const [gpus, setGpus] = useState<GPUInfo[]>([]);
  const [loading, setLoading] = useState(true);
  const [usingMockData, setUsingMockData] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetchGPUData();
    const interval = setInterval(fetchGPUData, 5000);
    return () => clearInterval(interval);
  }, [mode]);

  const fetchGPUData = async () => {
    setError(null);
    
    // Production 모드: 실제 API 시도
    if (mode === 'production') {
      try {
        // GPU 사용률 쿼리
        const utilizationResponse = await apiGet('/api/prometheus/query', {
          query: 'nvidia_smi_utilization_gpu_ratio'
        });
        
        // GPU 메모리 쿼리
        const memoryResponse = await apiGet('/api/prometheus/query', {
          query: 'nvidia_smi_memory_used_bytes / nvidia_smi_memory_total_bytes * 100'
        });
        
        // GPU 온도 쿼리
        const tempResponse = await apiGet('/api/prometheus/query', {
          query: 'nvidia_smi_temperature_gpu'
        });
        
        // 응답 검증
        if (utilizationResponse?.data?.result?.length > 0) {
          const gpuData = utilizationResponse.data.result.map((item: any, index: number) => {
            // GPU ID 추출
            const gpuId = parseInt(item.metric?.gpu || item.metric?.minor_number || index);
            
            // 사용률 (0-100%)
            const utilization = parseFloat(item.value[1]) * 100 || 0;
            
            // 메모리 사용률 찾기
            const memoryItem = memoryResponse?.data?.result?.find(
              (m: any) => (m.metric?.gpu || m.metric?.minor_number) === String(gpuId)
            );
            const memory = memoryItem ? parseFloat(memoryItem.value[1]) : 0;
            
            // 온도 찾기
            const tempItem = tempResponse?.data?.result?.find(
              (t: any) => (t.metric?.gpu || t.metric?.minor_number) === String(gpuId)
            );
            const temperature = tempItem ? parseFloat(tempItem.value[1]) : 0;
            
            return {
              id: gpuId,
              utilization: Math.min(100, Math.max(0, utilization)),
              memory: Math.min(100, Math.max(0, memory)),
              temperature: Math.min(100, Math.max(0, temperature))
            };
          });
          
          setGpus(gpuData);
          setUsingMockData(false);
          setLoading(false);
          console.log('[GPUWidget] Successfully loaded real GPU data:', gpuData.length, 'GPUs');
          return;
        } else {
          // Production 모드에서 GPU 데이터가 없으면 빈 배열로 설정
          console.log('[GPUWidget] No GPU data found in production mode');
          setGpus([]);
          setUsingMockData(false);
          setLoading(false);
          return;
        }
      } catch (error) {
        // Production 모드에서 API 에러 발생 시
        console.error('[GPUWidget] Production API error:', error);
        setError('Failed to fetch GPU data');
        setGpus([]);
        setUsingMockData(false);
        setLoading(false);
        return;
      }
    }
    
    // Mock 모드: Mock 데이터 사용
    const mockGpus = [
      { id: 0, utilization: 75 + Math.random() * 20, memory: 80 + Math.random() * 10, temperature: 65 + Math.random() * 5 },
      { id: 1, utilization: 45 + Math.random() * 20, memory: 55 + Math.random() * 10, temperature: 58 + Math.random() * 5 },
      { id: 2, utilization: 90 + Math.random() * 10, memory: 95 + Math.random() * 5, temperature: 72 + Math.random() * 5 },
      { id: 3, utilization: 20 + Math.random() * 20, memory: 30 + Math.random() * 10, temperature: 48 + Math.random() * 5 }
    ];
    setGpus(mockGpus);
    setUsingMockData(true);
    setLoading(false);
    console.log('[GPUWidget] Using mock GPU data:', mockGpus.length, 'GPUs');
  };

  const getUtilizationColor = (util: number) => {
    if (util < 50) return 'bg-green-500';
    if (util < 80) return 'bg-yellow-500';
    return 'bg-red-500';
  };

  const getTempColor = (temp: number) => {
    if (temp < 60) return 'text-green-500';
    if (temp < 75) return 'text-yellow-500';
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
          <Monitor className="w-5 h-5 text-green-500" />
          <h3 className="font-semibold text-gray-900 dark:text-white">GPU Status</h3>
          {gpus.length > 0 && (
            <span className="text-xs bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-400 px-2 py-1 rounded">
              {gpus.length} Active
            </span>
          )}
          {mode === 'mock' && usingMockData && (
            <span className="text-xs bg-amber-100 dark:bg-amber-900/30 text-amber-700 dark:text-amber-400 px-2 py-0.5 rounded">
              Mock
            </span>
          )}
          {mode === 'production' && !usingMockData && gpus.length === 0 && !loading && (
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
            <div className="w-8 h-8 border-4 border-blue-600 border-t-transparent rounded-full animate-spin mx-auto mb-2"></div>
            <p className="text-sm text-gray-500 dark:text-gray-400">Loading...</p>
          </div>
        ) : error ? (
          <div className="text-center text-red-500 dark:text-red-400 py-8">
            <Monitor className="w-12 h-12 mx-auto mb-3 opacity-50" />
            <p className="font-medium">{error}</p>
            <p className="text-sm text-gray-500 dark:text-gray-400 mt-2">
              Check Prometheus or nvidia_exporter
            </p>
          </div>
        ) : gpus.length === 0 ? (
          <div className="text-center text-gray-500 dark:text-gray-400 py-8">
            <Monitor className="w-12 h-12 mx-auto mb-3 opacity-50" />
            <p className="font-medium">No GPUs found</p>
            <p className="text-sm text-gray-500 dark:text-gray-400 mt-2">
              {mode === 'production' ? 'Check nvidia_exporter' : 'Try mock mode'}
            </p>
          </div>
        ) : (
          <div className="space-y-3">
            {gpus.map(gpu => (
              <div
                key={gpu.id}
                className="bg-gray-50 dark:bg-gray-700/50 rounded-lg p-3 hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors"
              >
                <div className="flex items-center justify-between mb-2">
                  <div className="flex items-center gap-2">
                    <Activity className="w-4 h-4 text-gray-500" />
                    <span className="font-medium text-gray-900 dark:text-white">
                      GPU {gpu.id}
                    </span>
                  </div>
                  <div className="flex items-center gap-2">
                    <span className={`text-sm font-semibold ${getTempColor(gpu.temperature)}`}>
                      {gpu.temperature.toFixed(0)}°C
                    </span>
                  </div>
                </div>

                {/* Utilization Bar */}
                <div className="mb-2">
                  <div className="flex items-center justify-between text-xs text-gray-500 dark:text-gray-400 mb-1">
                    <span>Utilization</span>
                    <span>{gpu.utilization.toFixed(1)}%</span>
                  </div>
                  <div className="w-full bg-gray-200 dark:bg-gray-600 rounded-full h-2 overflow-hidden">
                    <div
                      className={`h-full ${getUtilizationColor(gpu.utilization)} transition-all duration-500`}
                      style={{ width: `${gpu.utilization}%` }}
                    />
                  </div>
                </div>

                {/* Memory Bar */}
                <div>
                  <div className="flex items-center justify-between text-xs text-gray-500 dark:text-gray-400 mb-1">
                    <span>Memory</span>
                    <span>{gpu.memory.toFixed(1)}%</span>
                  </div>
                  <div className="w-full bg-gray-200 dark:bg-gray-600 rounded-full h-2 overflow-hidden">
                    <div
                      className="h-full bg-blue-500 transition-all duration-500"
                      style={{ width: `${gpu.memory}%` }}
                    />
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
};

export default GPUWidget;
