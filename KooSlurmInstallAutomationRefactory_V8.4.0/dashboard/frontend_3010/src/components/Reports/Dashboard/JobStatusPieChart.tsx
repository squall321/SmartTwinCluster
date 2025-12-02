/**
 * JobStatusPieChart.tsx
 * Job status distribution pie chart
 * v3.4.0
 */

import React from 'react';
import {
  PieChart,
  Pie,
  Cell,
  ResponsiveContainer,
  Legend,
  Tooltip,
} from 'recharts';
import { ChartPieIcon } from '@heroicons/react/24/outline';

interface JobStatusPieChartProps {
  data: {
    running: number;
    pending: number;
    completed: number;
    failed: number;
    cancelled: number;
    total: number;
  };
  loading?: boolean;
  error?: string | null;
}

const JobStatusPieChart: React.FC<JobStatusPieChartProps> = ({
  data,
  loading = false,
  error = null,
}) => {
  // 차트 데이터 구성
  const chartData = [
    { name: 'Running', value: data.running, color: '#3B82F6' },
    { name: 'Pending', value: data.pending, color: '#F59E0B' },
    { name: 'Completed', value: data.completed, color: '#10B981' },
    { name: 'Failed', value: data.failed, color: '#EF4444' },
    { name: 'Cancelled', value: data.cancelled, color: '#6B7280' },
  ].filter(item => item.value > 0); // 0인 항목 제외

  if (loading) {
    return (
      <div className="bg-white dark:bg-gray-800 rounded-lg shadow-lg p-6">
        <div className="flex items-center gap-2 mb-4">
          <ChartPieIcon className="w-6 h-6 text-green-600" />
          <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
            Job Status Distribution
          </h3>
        </div>
        <div className="h-96 flex items-center justify-center">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-green-600"></div>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="bg-white dark:bg-gray-800 rounded-lg shadow-lg p-6">
        <div className="flex items-center gap-2 mb-4">
          <ChartPieIcon className="w-6 h-6 text-green-600" />
          <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
            Job Status Distribution
          </h3>
        </div>
        <div className="h-96 flex items-center justify-center">
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

  // 커스텀 라벨
  const renderCustomLabel = ({ cx, cy, midAngle, innerRadius, outerRadius, percent }: any) => {
    const radius = innerRadius + (outerRadius - innerRadius) * 0.5;
    const x = cx + radius * Math.cos(-midAngle * Math.PI / 180);
    const y = cy + radius * Math.sin(-midAngle * Math.PI / 180);

    if (percent < 0.05) return null; // 5% 미만은 라벨 생략

    return (
      <text
        x={x}
        y={y}
        fill="white"
        textAnchor={x > cx ? 'start' : 'end'}
        dominantBaseline="central"
        className="text-sm font-semibold"
      >
        {`${(percent * 100).toFixed(0)}%`}
      </text>
    );
  };

  return (
    <div className="bg-white dark:bg-gray-800 rounded-lg shadow-lg p-6">
      {/* 헤더 */}
      <div className="flex items-center gap-2 mb-4">
        <ChartPieIcon className="w-6 h-6 text-green-600" />
        <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
          Job Status Distribution
        </h3>
      </div>

      {/* 차트 */}
      <ResponsiveContainer width="100%" height={280}>
        <PieChart>
          <Pie
            data={chartData}
            cx="50%"
            cy="50%"
            labelLine={false}
            label={renderCustomLabel}
            outerRadius={100}
            fill="#8884d8"
            dataKey="value"
            animationBegin={0}
            animationDuration={800}
          >
            {chartData.map((entry, index) => (
              <Cell key={`cell-${index}`} fill={entry.color} />
            ))}
          </Pie>
          <Tooltip
            contentStyle={{
              backgroundColor: '#1F2937',
              border: '1px solid #374151',
              borderRadius: '8px',
              color: '#F9FAFB',
            }}
            formatter={(value: number) => [value, '']}
          />
          <Legend
            verticalAlign="bottom"
            height={36}
            iconType="circle"
          />
        </PieChart>
      </ResponsiveContainer>

      {/* 통계 카드 */}
      <div className="mt-4 grid grid-cols-2 gap-3">
        <div className="p-3 bg-blue-50 dark:bg-blue-900/20 rounded-lg">
          <div className="flex items-center justify-between">
            <span className="text-sm text-gray-600 dark:text-gray-400">Running</span>
            <span className="text-xl font-bold text-blue-600">{data.running}</span>
          </div>
        </div>
        <div className="p-3 bg-orange-50 dark:bg-orange-900/20 rounded-lg">
          <div className="flex items-center justify-between">
            <span className="text-sm text-gray-600 dark:text-gray-400">Pending</span>
            <span className="text-xl font-bold text-orange-600">{data.pending}</span>
          </div>
        </div>
        <div className="p-3 bg-green-50 dark:bg-green-900/20 rounded-lg">
          <div className="flex items-center justify-between">
            <span className="text-sm text-gray-600 dark:text-gray-400">Completed</span>
            <span className="text-xl font-bold text-green-600">{data.completed}</span>
          </div>
        </div>
        <div className="p-3 bg-red-50 dark:bg-red-900/20 rounded-lg">
          <div className="flex items-center justify-between">
            <span className="text-sm text-gray-600 dark:text-gray-400">Failed</span>
            <span className="text-xl font-bold text-red-600">{data.failed}</span>
          </div>
        </div>
      </div>

      {/* 총 작업 수 */}
      <div className="mt-4 pt-4 border-t border-gray-200 dark:border-gray-700">
        <div className="flex items-center justify-between">
          <span className="text-sm font-medium text-gray-600 dark:text-gray-400">
            Total Jobs
          </span>
          <span className="text-2xl font-bold text-gray-900 dark:text-white">
            {data.total}
          </span>
        </div>
      </div>
    </div>
  );
};

export default JobStatusPieChart;
