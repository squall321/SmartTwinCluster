import React, { useState, useEffect } from 'react';
import { LineChart, Line, AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';
import { TrendingUp, Calendar, AlertCircle } from 'lucide-react';
import { apiGet } from '../../utils/api';

/**
 * MetricChart 컴포넌트
 * 시계열 메트릭 차트 시각화
 */

interface MetricChartProps {
  queryResults: any;
  mode?: 'mock' | 'production';
  originalQuery?: string;  // 원래 실행한 쿼리
}

type TimeRange = '1h' | '6h' | '24h' | '7d';
type ChartType = 'line' | 'area';

const TIME_RANGES: Record<TimeRange, { label: string; seconds: number; step: string }> = {
  '1h': { label: '1 Hour', seconds: 3600, step: '15s' },
  '6h': { label: '6 Hours', seconds: 21600, step: '60s' },
  '24h': { label: '24 Hours', seconds: 86400, step: '300s' },
  '7d': { label: '7 Days', seconds: 604800, step: '3600s' }
};

const MetricChart: React.FC<MetricChartProps> = ({ queryResults, mode, originalQuery }) => {
  const [timeRange, setTimeRange] = useState<TimeRange>('1h');
  const [chartType, setChartType] = useState<ChartType>('line');
  const [chartData, setChartData] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [currentQuery, setCurrentQuery] = useState<string>('');  // 현재 차트의 쿼리 저장

  useEffect(() => {
    if (queryResults && queryResults.data?.result?.length > 0 && originalQuery) {
      setCurrentQuery(originalQuery);  // 쿼리 저장
      fetchRangeData(originalQuery);
    }
  }, [queryResults, timeRange, originalQuery]);

  const fetchRangeData = async (query: string) => {
    if (!query || !queryResults?.data?.result?.[0]) {
      return;
    }

    setIsLoading(true);
    setError(null);

    try {
      console.log('[MetricChart] Fetching range data for query:', query);
      
      // Calculate time range
      const end = new Date();
      const start = new Date(end.getTime() - TIME_RANGES[timeRange].seconds * 1000);
      
      const response = await apiGet('/api/prometheus/query_range', {
        query,
        start: start.toISOString(),
        end: end.toISOString(),
        step: TIME_RANGES[timeRange].step
      });

      if (response.data?.result?.length > 0) {
        const processedData = processChartData(response.data.result);
        setChartData(processedData);
      } else {
        setChartData([]);
      }
    } catch (err: any) {
      console.error('❌ Range query error:', err);
      setError(err.message || 'Failed to fetch range data');
      setChartData([]);
    } finally {
      setIsLoading(false);
    }
  };

  const processChartData = (results: any[]): any[] => {
    if (!results || results.length === 0) return [];

    console.log('[MetricChart] Processing', results.length, 'time series');
    
    // 여러 메트릭이 있는지 확인
    const uniqueMetrics = new Set(results.map(r => r.metric.__name__));
    const hasMultipleMetricTypes = uniqueMetrics.size > 1;
    
    console.log('[MetricChart] Unique metrics:', Array.from(uniqueMetrics));
    console.log('[MetricChart] Has multiple metric types:', hasMultipleMetricTypes);

    // Get all unique timestamps
    const timestamps = new Set<number>();
    results.forEach(result => {
      result.values?.forEach(([timestamp]: [number, string]) => {
        timestamps.add(timestamp);
      });
    });

    const sortedTimestamps = Array.from(timestamps).sort((a, b) => a - b);

    // Build chart data
    return sortedTimestamps.map(timestamp => {
      const dataPoint: any = {
        timestamp,
        time: new Date(timestamp * 1000).toLocaleTimeString([], { 
          hour: '2-digit', 
          minute: '2-digit' 
        })
      };

      results.forEach((result, index) => {
        const metricLabel = getMetricLabel(result.metric, index, hasMultipleMetricTypes);
        const value = result.values?.find(([ts]: [number, string]) => ts === timestamp)?.[1];
        dataPoint[metricLabel] = value ? parseFloat(value) : null;
      });

      return dataPoint;
    });
  };

  const getMetricLabel = (metric: Record<string, string>, index: number, hasMultipleMetricTypes: boolean): string => {
    // 1. 메트릭 이름 추출
    const metricName = metric.__name__ || 'unknown';
    
    // 2. 주요 레이블들 수집
    const labels: string[] = [];
    
    // instance 또는 node (짧게 축약)
    if (metric.instance) {
      // localhost:9100 -> localhost
      const instance = metric.instance.split(':')[0];
      labels.push(instance);
    } else if (metric.node) {
      labels.push(metric.node);
    }
    
    // CPU core, GPU index 등
    if (metric.cpu) labels.push(`cpu${metric.cpu}`);
    if (metric.gpu) labels.push(`gpu${metric.gpu}`);
    if (metric.device) labels.push(metric.device);
    if (metric.mountpoint) labels.push(metric.mountpoint);
    if (metric.mode) labels.push(metric.mode);
    if (metric.job) labels.push(metric.job);
    
    // 3. 레이블 조합
    if (labels.length > 0) {
      // 여러 메트릭 타입이 있으면 메트릭 이름 포함
      if (hasMultipleMetricTypes) {
        // 메트릭 이름 축약
        const shortName = metricName.replace('node_', '').replace('_total', '').replace('_bytes', '');
        return `${shortName}[${labels.join('-')}]`;
      } else {
        return labels.join('-');
      }
    }
    
    // 4. 레이블이 없으면 메트릭 이름 + 인덱스
    return `${metricName}-${index + 1}`;
  };

  const getSeriesKeys = (): string[] => {
    if (chartData.length === 0) return [];
    const keys = Object.keys(chartData[0]).filter(key => key !== 'timestamp' && key !== 'time');
    return keys;
  };

  const COLORS = ['#3b82f6', '#10b981', '#f59e0b', '#ef4444', '#8b5cf6', '#ec4899', '#06b6d4', '#84cc16'];

  if (!queryResults || queryResults.data?.result?.length === 0) {
    return (
      <div className="bg-white rounded-xl shadow-sm border border-gray-200 h-full flex items-center justify-center">
        <div className="text-center py-12 text-gray-500">
          <TrendingUp className="w-12 h-12 mx-auto mb-3 text-gray-400" />
          <p className="text-sm">No data to display</p>
          <p className="text-xs mt-2">Execute a query in Query Browser to see charts</p>
        </div>
      </div>
    );
  }

  if (!originalQuery) {
    return (
      <div className="bg-white rounded-xl shadow-sm border border-gray-200 h-full flex items-center justify-center">
        <div className="text-center py-12 text-gray-500">
          <TrendingUp className="w-12 h-12 mx-auto mb-3 text-gray-400" />
          <p className="text-sm">No query executed yet</p>
          <p className="text-xs mt-2">Execute a query in Query Browser first</p>
        </div>
      </div>
    );
  }

  return (
    <div className="bg-white rounded-xl shadow-sm border border-gray-200 h-full flex flex-col">
      {/* Header */}
      <div className="p-4 border-b border-gray-200">
        <div className="flex items-center justify-between mb-3">
          <div className="flex-1">
            <h3 className="text-lg font-semibold text-gray-900">Metric Chart</h3>
            {currentQuery && (
              <p className="text-xs text-gray-500 mt-1 font-mono bg-gray-50 px-2 py-1 rounded border border-gray-200 max-w-2xl overflow-hidden text-ellipsis whitespace-nowrap">
                {currentQuery}
              </p>
            )}
          </div>
          
          {/* Chart Type Toggle */}
          <div className="flex gap-1 bg-gray-100 p-1 rounded-lg">
            <button
              onClick={() => setChartType('line')}
              className={`px-3 py-1.5 text-xs font-medium rounded transition-colors ${
                chartType === 'line'
                  ? 'bg-white text-gray-900 shadow-sm'
                  : 'text-gray-600 hover:text-gray-900'
              }`}
            >
              Line
            </button>
            <button
              onClick={() => setChartType('area')}
              className={`px-3 py-1.5 text-xs font-medium rounded transition-colors ${
                chartType === 'area'
                  ? 'bg-white text-gray-900 shadow-sm'
                  : 'text-gray-600 hover:text-gray-900'
              }`}
            >
              Area
            </button>
          </div>
        </div>

        {/* Time Range Selector */}
        <div className="flex items-center gap-2">
          <Calendar className="w-4 h-4 text-gray-400" />
          <div className="flex gap-1">
            {(Object.keys(TIME_RANGES) as TimeRange[]).map(range => (
              <button
                key={range}
                onClick={() => setTimeRange(range)}
                className={`px-3 py-1.5 text-xs font-medium rounded-lg transition-colors ${
                  timeRange === range
                    ? 'bg-indigo-100 text-indigo-700'
                    : 'text-gray-600 hover:bg-gray-100'
                }`}
              >
                {TIME_RANGES[range].label}
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* Chart */}
      <div className="flex-1 p-4">
        {error && (
          <div className="flex items-start gap-3 p-4 bg-red-50 border border-red-200 rounded-lg mb-4">
            <AlertCircle className="w-5 h-5 text-red-600 flex-shrink-0 mt-0.5" />
            <div>
              <div className="font-medium text-red-900">Chart Error</div>
              <div className="text-sm text-red-700 mt-1">{error}</div>
            </div>
          </div>
        )}

        {isLoading ? (
          <div className="h-full flex items-center justify-center">
            <div className="text-center">
              <div className="w-8 h-8 border-4 border-indigo-600 border-t-transparent rounded-full animate-spin mx-auto mb-3"></div>
              <p className="text-sm text-gray-600">Loading chart data...</p>
            </div>
          </div>
        ) : chartData.length === 0 ? (
          <div className="h-full flex items-center justify-center">
            <div className="text-center text-gray-500">
              <AlertCircle className="w-12 h-12 mx-auto mb-3 text-gray-400" />
              <p className="text-sm">No chart data available</p>
              <p className="text-xs mt-2">Try adjusting the time range</p>
            </div>
          </div>
        ) : (
          <ResponsiveContainer width="100%" height="100%">
            {chartType === 'line' ? (
              <LineChart data={chartData}>
                <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
                <XAxis 
                  dataKey="time" 
                  stroke="#6b7280"
                  style={{ fontSize: '12px' }}
                />
                <YAxis 
                  stroke="#6b7280"
                  style={{ fontSize: '12px' }}
                />
                <Tooltip 
                  contentStyle={{ 
                    backgroundColor: 'white',
                    border: '1px solid #e5e7eb',
                    borderRadius: '8px',
                    fontSize: '12px'
                  }}
                />
                <Legend 
                  wrapperStyle={{ fontSize: '12px' }}
                />
                {getSeriesKeys().map((key, index) => (
                  <Line
                    key={key}
                    type="monotone"
                    dataKey={key}
                    stroke={COLORS[index % COLORS.length]}
                    strokeWidth={2}
                    dot={false}
                    activeDot={{ r: 4 }}
                  />
                ))}
              </LineChart>
            ) : (
              <AreaChart data={chartData}>
                <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
                <XAxis 
                  dataKey="time" 
                  stroke="#6b7280"
                  style={{ fontSize: '12px' }}
                />
                <YAxis 
                  stroke="#6b7280"
                  style={{ fontSize: '12px' }}
                />
                <Tooltip 
                  contentStyle={{ 
                    backgroundColor: 'white',
                    border: '1px solid #e5e7eb',
                    borderRadius: '8px',
                    fontSize: '12px'
                  }}
                />
                <Legend 
                  wrapperStyle={{ fontSize: '12px' }}
                />
                {getSeriesKeys().map((key, index) => (
                  <Area
                    key={key}
                    type="monotone"
                    dataKey={key}
                    stroke={COLORS[index % COLORS.length]}
                    fill={COLORS[index % COLORS.length]}
                    fillOpacity={0.3}
                    strokeWidth={2}
                  />
                ))}
              </AreaChart>
            )}
          </ResponsiveContainer>
        )}
      </div>
    </div>
  );
};

export default MetricChart;
