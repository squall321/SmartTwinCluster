/**
 * ResourceUsageChart.tsx
 * Resource usage chart (CPU/GPU/Memory)
 * v3.4.0
 */

import React from 'react';
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
} from 'recharts';
import { CpuChipIcon } from '@heroicons/react/24/outline';

interface ResourceUsageChartProps {
  data: {
    timestamps: string[];
    cpu_usage: number[];
    gpu_usage: number[];
    memory_usage: number[];
  };
  loading?: boolean;
  error?: string | null;
}

const ResourceUsageChart: React.FC<ResourceUsageChartProps> = ({
  data,
  loading = false,
  error = null,
}) => {
  // 데이터 변환 (Recharts 형식)
  const chartData = data.timestamps.map((timestamp, index) => ({
    time: new Date(timestamp).toLocaleTimeString('ko-KR', {
      hour: '2-digit',
      minute: '2-digit',
    }),
    CPU: data.cpu_usage[index],
    GPU: data.gpu_usage[index],
    Memory: data.memory_usage[index],
  }));

  if (loading) {
    return (
      <div className="bg-white dark:bg-gray-800 rounded-lg shadow-lg p-6">
        <div className="flex items-center gap-2 mb-4">
          <CpuChipIcon className="w-6 h-6 text-blue-600" />
          <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
            Resource Usage
          </h3>
        </div>
        <div className="h-80 flex items-center justify-center">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600"></div>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="bg-white dark:bg-gray-800 rounded-lg shadow-lg p-6">
        <div className="flex items-center gap-2 mb-4">
          <CpuChipIcon className="w-6 h-6 text-blue-600" />
          <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
            리소스 사용률
          </h3>
        </div>
        <div className="h-80 flex items-center justify-center">
          <div className="text-center">
            <p className="text-red-500 mb-2">❌ {error}</p>
            <p className="text-gray-500 dark:text-gray-400 text-sm">
              Unable to load data
            </p>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="bg-white dark:bg-gray-800 rounded-lg shadow-lg p-6">
      {/* 헤더 */}
      <div className="flex items-center gap-2 mb-4">
        <CpuChipIcon className="w-6 h-6 text-blue-600" />
        <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
          Resource Usage (24h)
        </h3>
      </div>

      {/* 차트 */}
      <ResponsiveContainer width="100%" height={320}>
        <LineChart data={chartData}>
          <CartesianGrid
            strokeDasharray="3 3"
            stroke="#374151"
            opacity={0.1}
          />
          <XAxis
            dataKey="time"
            stroke="#9CA3AF"
            style={{ fontSize: '12px' }}
            interval="preserveStartEnd"
          />
          <YAxis
            stroke="#9CA3AF"
            style={{ fontSize: '12px' }}
            domain={[0, 100]}
            ticks={[0, 25, 50, 75, 100]}
            label={{
              value: 'Usage (%)',
              angle: -90,
              position: 'insideLeft',
              style: { fill: '#9CA3AF', fontSize: '12px' },
            }}
          />
          <Tooltip
            contentStyle={{
              backgroundColor: '#1F2937',
              border: '1px solid #374151',
              borderRadius: '8px',
              color: '#F9FAFB',
            }}
            labelStyle={{ color: '#F9FAFB' }}
            formatter={(value: number) => [`${value.toFixed(1)}%`, '']}
          />
          <Legend
            wrapperStyle={{ paddingTop: '20px' }}
            iconType="line"
          />
          
          {/* CPU 라인 */}
          <Line
            type="monotone"
            dataKey="CPU"
            stroke="#3B82F6"
            strokeWidth={2}
            dot={false}
            activeDot={{ r: 4 }}
            name="CPU"
          />
          
          {/* GPU 라인 */}
          <Line
            type="monotone"
            dataKey="GPU"
            stroke="#10B981"
            strokeWidth={2}
            dot={false}
            activeDot={{ r: 4 }}
            name="GPU"
          />
          
          {/* Memory 라인 */}
          <Line
            type="monotone"
            dataKey="Memory"
            stroke="#F59E0B"
            strokeWidth={2}
            dot={false}
            activeDot={{ r: 4 }}
            name="Memory"
          />
        </LineChart>
      </ResponsiveContainer>

      {/* 현재 값 표시 */}
      <div className="mt-4 grid grid-cols-3 gap-4">
        <div className="text-center p-3 bg-blue-50 dark:bg-blue-900/20 rounded-lg">
          <div className="text-sm text-gray-600 dark:text-gray-400">Current CPU</div>
          <div className="text-2xl font-bold text-blue-600">
            {data.cpu_usage[data.cpu_usage.length - 1]?.toFixed(1)}%
          </div>
        </div>
        <div className="text-center p-3 bg-green-50 dark:bg-green-900/20 rounded-lg">
          <div className="text-sm text-gray-600 dark:text-gray-400">Current GPU</div>
          <div className="text-2xl font-bold text-green-600">
            {data.gpu_usage[data.gpu_usage.length - 1]?.toFixed(1)}%
          </div>
        </div>
        <div className="text-center p-3 bg-orange-50 dark:bg-orange-900/20 rounded-lg">
          <div className="text-sm text-gray-600 dark:text-gray-400">Current Memory</div>
          <div className="text-2xl font-bold text-orange-600">
            {data.memory_usage[data.memory_usage.length - 1]?.toFixed(1)}%
          </div>
        </div>
      </div>
    </div>
  );
};

export default ResourceUsageChart;
