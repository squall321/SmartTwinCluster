/**
 * CostTrendsChart.tsx
 * Cost trends chart (Area Chart)
 * v3.4.0
 */

import React from 'react';
import {
  AreaChart,
  Area,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
} from 'recharts';
import { CurrencyDollarIcon } from '@heroicons/react/24/outline';

interface CostTrendsChartProps {
  data: {
    period: 'week' | 'month' | 'year';
    dates: string[];
    daily_costs: number[];
    cumulative_costs: number[];
    total_cost: number;
    average_daily_cost: number;
  };
  loading?: boolean;
  error?: string | null;
  onPeriodChange?: (period: 'week' | 'month' | 'year') => void;
}

const CostTrendsChart: React.FC<CostTrendsChartProps> = ({
  data,
  loading = false,
  error = null,
  onPeriodChange,
}) => {
  // 차트 데이터 변환
  const chartData = data.dates.map((date, index) => ({
    date: new Date(date).toLocaleDateString('ko-KR', {
      month: 'short',
      day: 'numeric',
    }),
    dailyCost: data.daily_costs[index],
    cumulativeCost: data.cumulative_costs[index],
  }));

  if (loading) {
    return (
      <div className="bg-white dark:bg-gray-800 rounded-lg shadow-lg p-6">
        <div className="flex items-center gap-2 mb-4">
          <CurrencyDollarIcon className="w-6 h-6 text-emerald-600" />
          <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
            Cost Trends
          </h3>
        </div>
        <div className="h-96 flex items-center justify-center">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-emerald-600"></div>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="bg-white dark:bg-gray-800 rounded-lg shadow-lg p-6">
        <div className="flex items-center gap-2 mb-4">
          <CurrencyDollarIcon className="w-6 h-6 text-emerald-600" />
          <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
            Cost Trends
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

  return (
    <div className="bg-white dark:bg-gray-800 rounded-lg shadow-lg p-6">
      {/* 헤더 */}
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-2">
          <CurrencyDollarIcon className="w-6 h-6 text-emerald-600" />
          <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
            Cost Trends
          </h3>
        </div>

        {/* 기간 선택 버튼 */}
        {onPeriodChange && (
          <div className="flex gap-2">
            <button
              onClick={() => onPeriodChange('week')}
              className={`px-3 py-1 rounded-lg text-sm font-medium transition-colors ${
                data.period === 'week'
                  ? 'bg-emerald-600 text-white'
                  : 'bg-gray-100 dark:bg-gray-700 text-gray-600 dark:text-gray-400 hover:bg-gray-200 dark:hover:bg-gray-600'
              }`}
            >
              Weekly
            </button>
            <button
              onClick={() => onPeriodChange('month')}
              className={`px-3 py-1 rounded-lg text-sm font-medium transition-colors ${
                data.period === 'month'
                  ? 'bg-emerald-600 text-white'
                  : 'bg-gray-100 dark:bg-gray-700 text-gray-600 dark:text-gray-400 hover:bg-gray-200 dark:hover:bg-gray-600'
              }`}
            >
              Monthly
            </button>
            <button
              onClick={() => onPeriodChange('year')}
              className={`px-3 py-1 rounded-lg text-sm font-medium transition-colors ${
                data.period === 'year'
                  ? 'bg-emerald-600 text-white'
                  : 'bg-gray-100 dark:bg-gray-700 text-gray-600 dark:text-gray-400 hover:bg-gray-200 dark:hover:bg-gray-600'
              }`}
            >
              Yearly
            </button>
          </div>
        )}
      </div>

      {/* 차트 */}
      <ResponsiveContainer width="100%" height={280}>
        <AreaChart data={chartData}>
          <defs>
            <linearGradient id="colorDaily" x1="0" y1="0" x2="0" y2="1">
              <stop offset="5%" stopColor="#3B82F6" stopOpacity={0.8} />
              <stop offset="95%" stopColor="#3B82F6" stopOpacity={0.1} />
            </linearGradient>
            <linearGradient id="colorCumulative" x1="0" y1="0" x2="0" y2="1">
              <stop offset="5%" stopColor="#10B981" stopOpacity={0.8} />
              <stop offset="95%" stopColor="#10B981" stopOpacity={0.1} />
            </linearGradient>
          </defs>
          <CartesianGrid strokeDasharray="3 3" stroke="#374151" opacity={0.1} />
          <XAxis
            dataKey="date"
            stroke="#9CA3AF"
            style={{ fontSize: '12px' }}
          />
          <YAxis
            stroke="#9CA3AF"
            style={{ fontSize: '12px' }}
            label={{
              value: 'Cost ($)',
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
            formatter={(value: number) => [`$${value.toFixed(2)}`, '']}
          />
          <Legend wrapperStyle={{ paddingTop: '20px' }} />
          
          {/* 일별 비용 */}
          <Area
            type="monotone"
            dataKey="dailyCost"
            stroke="#3B82F6"
            strokeWidth={2}
            fillOpacity={1}
            fill="url(#colorDaily)"
            name="Daily Cost"
          />
          
          {/* 누적 비용 */}
          <Area
            type="monotone"
            dataKey="cumulativeCost"
            stroke="#10B981"
            strokeWidth={2}
            fillOpacity={1}
            fill="url(#colorCumulative)"
            name="Cumulative Cost"
          />
        </AreaChart>
      </ResponsiveContainer>

      {/* 통계 요약 */}
      <div className="mt-4 grid grid-cols-2 gap-4">
        <div className="p-3 bg-emerald-50 dark:bg-emerald-900/20 rounded-lg">
          <div className="text-sm text-gray-600 dark:text-gray-400 mb-1">
            Total Cost
          </div>
          <div className="text-2xl font-bold text-emerald-600">
            ${data.total_cost.toFixed(2)}
          </div>
        </div>
        <div className="p-3 bg-blue-50 dark:bg-blue-900/20 rounded-lg">
          <div className="text-sm text-gray-600 dark:text-gray-400 mb-1">
            Daily Average
          </div>
          <div className="text-2xl font-bold text-blue-600">
            ${data.average_daily_cost.toFixed(2)}
          </div>
        </div>
      </div>
    </div>
  );
};

export default CostTrendsChart;
