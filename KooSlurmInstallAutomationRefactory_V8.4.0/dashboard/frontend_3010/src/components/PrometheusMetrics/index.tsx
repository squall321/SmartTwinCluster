import React, { useState } from 'react';
import { Activity, TrendingUp, AlertCircle, Database } from 'lucide-react';
import QueryBrowser from './QueryBrowser';
import QueryTemplates from './QueryTemplates';
import MetricChart from './MetricChart';

/**
 * PrometheusMetrics 컴포넌트
 * Prometheus 메트릭 조회 및 시각화
 */

interface PrometheusMetricsProps {
  mode?: 'mock' | 'production';
}

const PrometheusMetrics: React.FC<PrometheusMetricsProps> = ({ mode = 'mock' }) => {
  const [activeTab, setActiveTab] = useState<'browser' | 'charts'>('browser');
  const [selectedQuery, setSelectedQuery] = useState<string>('');
  const [queryResults, setQueryResults] = useState<any>(null);
  const [executedQuery, setExecutedQuery] = useState<string>('');  // 실제 실행된 쿼리 저장
  const [timeRange, setTimeRange] = useState<string>('1h');
  const [autoRefresh, setAutoRefresh] = useState<boolean>(false);
  const [refreshInterval, setRefreshInterval] = useState<number>(30);

  const handleTemplateSelect = (query: string) => {
    setSelectedQuery(query);
  };

  const handleQueryResults = (results: any, query: string) => {
    setQueryResults(results);
    setExecutedQuery(query);  // 실행된 쿼리 저장
    console.log('[PrometheusMetrics] Query executed:', query);
  };

  return (
    <div className="h-full flex flex-col bg-gray-50">
      {/* Header */}
      <div className="bg-white border-b border-gray-200 px-6 py-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-gradient-to-br from-purple-500 to-indigo-600 rounded-lg">
              <Activity className="w-6 h-6 text-white" />
            </div>
            <div>
              <h2 className="text-2xl font-bold text-gray-900">Prometheus Metrics</h2>
              <p className="text-sm text-gray-500">Query and visualize cluster metrics</p>
            </div>
          </div>
          
          <div className="flex items-center gap-3">
            {/* Time Range Selector */}
            <select
              value={timeRange}
              onChange={(e) => setTimeRange(e.target.value)}
              className="px-3 py-1.5 border border-gray-300 rounded-lg text-sm font-medium text-gray-700 hover:border-gray-400 focus:outline-none focus:ring-2 focus:ring-indigo-500"
            >
              <option value="5m">Last 5 minutes</option>
              <option value="15m">Last 15 minutes</option>
              <option value="30m">Last 30 minutes</option>
              <option value="1h">Last 1 hour</option>
              <option value="6h">Last 6 hours</option>
              <option value="24h">Last 24 hours</option>
              <option value="7d">Last 7 days</option>
            </select>

            {/* Auto Refresh Toggle */}
            <button
              onClick={() => setAutoRefresh(!autoRefresh)}
              className={`px-3 py-1.5 rounded-lg text-sm font-medium transition-colors ${
                autoRefresh
                  ? 'bg-indigo-100 text-indigo-700 border border-indigo-300'
                  : 'bg-gray-100 text-gray-700 border border-gray-300 hover:bg-gray-200'
              }`}
            >
              Auto Refresh {autoRefresh ? 'ON' : 'OFF'}
            </button>

            {/* Status Badge */}
            <div className="flex items-center gap-2 px-3 py-1.5 bg-green-50 border border-green-200 rounded-lg">
              <div className="w-2 h-2 bg-green-500 rounded-full animate-pulse"></div>
              <span className="text-sm font-medium text-green-700">
                {mode === 'mock' ? 'Mock Mode' : 'Connected'}
              </span>
            </div>
          </div>
        </div>

        {/* Tab Navigation */}
        <div className="flex gap-2 mt-4">
          <button
            onClick={() => setActiveTab('browser')}
            className={`flex items-center gap-2 px-4 py-2 rounded-lg font-medium transition-colors ${
              activeTab === 'browser'
                ? 'bg-indigo-100 text-indigo-700'
                : 'text-gray-600 hover:bg-gray-100'
            }`}
          >
            <Database className="w-4 h-4" />
            Query Browser
          </button>
          <button
            onClick={() => setActiveTab('charts')}
            className={`flex items-center gap-2 px-4 py-2 rounded-lg font-medium transition-colors ${
              activeTab === 'charts'
                ? 'bg-indigo-100 text-indigo-700'
                : 'text-gray-600 hover:bg-gray-100'
            }`}
          >
            <TrendingUp className="w-4 h-4" />
            Charts
          </button>
        </div>
      </div>

      {/* Content */}
      <div className="flex-1 overflow-hidden">
        <div className="h-full grid grid-cols-1 lg:grid-cols-3 gap-6 p-6">
          {/* Left Side: Query Templates */}
          <div className="lg:col-span-1 h-full overflow-hidden">
            <QueryTemplates
              onSelectQuery={handleTemplateSelect}
              mode={mode}
            />
          </div>

          {/* Right Side: Query Browser or Charts */}
          <div className="lg:col-span-2 h-full overflow-hidden">
            {activeTab === 'browser' ? (
              <QueryBrowser
                selectedQuery={selectedQuery}
                onQueryResults={handleQueryResults}
                mode={mode}
              />
            ) : (
              <MetricChart
                queryResults={queryResults}
                originalQuery={executedQuery}  // 실행된 쿼리 전달
                mode={mode}
              />
            )}
          </div>
        </div>
      </div>

      {/* Info Banner */}
      {mode === 'mock' && (
        <div className="border-t border-gray-200 bg-yellow-50 px-6 py-3">
          <div className="flex items-center gap-2 text-sm text-yellow-800">
            <AlertCircle className="w-4 h-4" />
            <span>
              Running in <strong>Mock Mode</strong>. Metrics are simulated for demonstration.
              Set <code className="px-1.5 py-0.5 bg-yellow-100 rounded">MOCK_MODE=false</code> for real data.
            </span>
          </div>
        </div>
      )}
    </div>
  );
};

export default PrometheusMetrics;
