import React, { useState, useEffect } from 'react';
import { Cpu, GripVertical, X, TrendingUp, TrendingDown } from 'lucide-react';
import { WidgetProps } from '../widgetRegistry';
import { apiGet } from '../../../utils/api';

const CPUWidget: React.FC<WidgetProps> = ({ id, onRemove, isEditMode, mode }) => {
  const [cpuUsage, setCpuUsage] = useState<number>(0);
  const [trend, setTrend] = useState<'up' | 'down' | 'stable'>('stable');
  const [prevUsage, setPrevUsage] = useState<number>(0);
  const [loading, setLoading] = useState(true);
  const [usingMockData, setUsingMockData] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetchCPUData();
    const interval = setInterval(fetchCPUData, 5000);
    return () => clearInterval(interval);
  }, [mode]);

  const fetchCPUData = async () => {
    setError(null);
    
    // Production mode: try real API
    if (mode === 'production') {
      try {
        const response = await apiGet('/api/prometheus/query', {
          query: '100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)'
        });
        
        if (response?.data?.result?.[0]?.value) {
          const usage = parseFloat(response.data.result[0].value[1]);
          setCpuUsage(usage);
          setUsingMockData(false);
          setError(null);
          setLoading(false);
          return;
        } else {
          // No data - not an error
          setCpuUsage(0);
          setUsingMockData(false);
          setError(null);
          setLoading(false);
          return;
        }
      } catch (error) {
        // API error
        console.error('[CPUWidget] Production API error:', error);
        const errorMessage = error instanceof Error ? error.message : 'Failed to fetch CPU data';
        setError(errorMessage);
        setCpuUsage(0);
        setUsingMockData(false);
        setLoading(false);
        return;
      }
    }
    
    // Mock mode: use mock data
    const mockUsage = 45 + Math.random() * 30;
    setCpuUsage(mockUsage);
    setUsingMockData(true);
    setError(null);
    setLoading(false);
  };

  // Trend calculation
  useEffect(() => {
    if (cpuUsage !== prevUsage) {
      const diff = cpuUsage - prevUsage;
      if (Math.abs(diff) < 1) {
        setTrend('stable');
      } else {
        setTrend(diff > 0 ? 'up' : 'down');
      }
      setPrevUsage(cpuUsage);
    }
  }, [cpuUsage, prevUsage]);

  const getStatusColor = (usage: number) => {
    if (usage < 50) return 'text-green-500';
    if (usage < 80) return 'text-yellow-500';
    return 'text-red-500';
  };

  const getStatusBg = (usage: number) => {
    if (usage < 50) return 'bg-green-50 dark:bg-green-900/20';
    if (usage < 80) return 'bg-yellow-50 dark:bg-yellow-900/20';
    return 'bg-red-50 dark:bg-red-900/20';
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
          <Cpu className="w-5 h-5 text-blue-500" />
          <h3 className="font-semibold text-gray-900 dark:text-white">CPU Usage</h3>
          {mode === 'mock' && usingMockData && (
            <span className="text-xs bg-amber-100 dark:bg-amber-900/30 text-amber-700 dark:text-amber-400 px-2 py-0.5 rounded">
              Mock
            </span>
          )}
          {mode === 'production' && !usingMockData && !loading && !error && cpuUsage > 0 && (
            <span className="text-xs bg-gray-100 dark:bg-gray-700 text-gray-600 dark:text-gray-400 px-2 py-0.5 rounded">
              Production
            </span>
          )}
        </div>
        {isEditMode && (
          <button
            onClick={onRemove}
            className="p-1 hover:bg-gray-100 dark:hover:bg-gray-700 rounded transition-colors"
            title="Remove widget"
          >
            <X className="w-4 h-4 text-gray-500" />
          </button>
        )}
      </div>

      {/* Content */}
      <div className="flex-1 flex items-center justify-center p-6">
        {loading ? (
          <div className="text-center">
            <div className="w-8 h-8 border-4 border-blue-600 border-t-transparent rounded-full animate-spin mx-auto mb-2"></div>
            <p className="text-sm text-gray-500 dark:text-gray-400">Loading...</p>
          </div>
        ) : error ? (
          <div className="text-center text-red-500 dark:text-red-400">
            <Cpu className="w-12 h-12 mx-auto mb-3 opacity-50" />
            <p className="font-medium">{error}</p>
            <p className="text-sm text-gray-500 dark:text-gray-400 mt-2">
              Check Prometheus or node_exporter
            </p>
          </div>
        ) : cpuUsage === 0 && !usingMockData ? (
          <div className="text-center text-gray-500 dark:text-gray-400">
            <Cpu className="w-12 h-12 mx-auto mb-3 opacity-50" />
            <p className="font-medium">No data available</p>
            <p className="text-sm text-gray-500 dark:text-gray-400 mt-2">
              {mode === 'production' ? 'Check Prometheus setup' : 'Try mock mode'}
            </p>
          </div>
        ) : (
          <div className="text-center w-full">
            {/* CPU Usage Circle */}
            <div className={`relative inline-flex items-center justify-center w-32 h-32 rounded-full ${getStatusBg(cpuUsage)}`}>
              <div className="text-center">
                <div className={`text-4xl font-bold ${getStatusColor(cpuUsage)}`}>
                  {cpuUsage.toFixed(1)}%
                </div>
                <div className="text-xs text-gray-500 dark:text-gray-400 mt-1">CPU</div>
              </div>
            </div>

            {/* Trend Indicator */}
            <div className="mt-4 flex items-center justify-center gap-2">
              {trend === 'up' && (
                <>
                  <TrendingUp className="w-4 h-4 text-red-500" />
                  <span className="text-sm text-red-500">Increasing</span>
                </>
              )}
              {trend === 'down' && (
                <>
                  <TrendingDown className="w-4 h-4 text-green-500" />
                  <span className="text-sm text-green-500">Decreasing</span>
                </>
              )}
              {trend === 'stable' && (
                <span className="text-sm text-gray-500 dark:text-gray-400">Stable</span>
              )}
            </div>

            {/* Status Text */}
            <div className="mt-2 text-sm text-gray-600 dark:text-gray-400">
              {cpuUsage < 50 && 'Low Usage'}
              {cpuUsage >= 50 && cpuUsage < 80 && 'Moderate Usage'}
              {cpuUsage >= 80 && 'High Usage'}
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

export default CPUWidget;
