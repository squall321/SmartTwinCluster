/**
 * Reports Main Page
 * v3.4.0 - Real-time dashboard charts added
 */

import React, { useState, useEffect } from 'react';
import { 
  getOverviewReport, 
  getReportDownloadUrl,
  getDashboardResources,
  getDashboardTopUsers,
  getDashboardJobStatus,
  getDashboardCostTrends,
  ReportPeriod 
} from '../../utils/api';

// Dashboard 차트 컴포넌트
import {
  ResourceUsageChart,
  TopUsersTable,
  JobStatusPieChart,
  CostTrendsChart,
} from './Dashboard';

// Icons
import { 
  ChartBarIcon, 
  DocumentArrowDownIcon,
  CalendarIcon,
  CurrencyDollarIcon,
  CpuChipIcon,
  ClockIcon,
  ArrowPathIcon,
  DocumentTextIcon,
  TableCellsIcon
} from '@heroicons/react/24/outline';

interface OverviewData {
  status: string;
  summary: {
    total_users: number;
    active_users: number;
    total_jobs_today: number;
    running_jobs: number;
    pending_jobs: number;
  };
  resources: {
    cpu_utilization: number;
    gpu_utilization: number;
    memory_utilization: number;
  };
  costs_today: number;
  costs_this_month: number;
  generated_at: string;
}

const Reports: React.FC = () => {
  const [period, setPeriod] = useState<ReportPeriod>('week');
  const [loading, setLoading] = useState(true);
  const [overviewData, setOverviewData] = useState<OverviewData | null>(null);
  const [error, setError] = useState<string | null>(null);

  // Dashboard 데이터 상태
  const [resourceData, setResourceData] = useState<any>(null);
  const [topUsersData, setTopUsersData] = useState<any[]>([]);
  const [jobStatusData, setJobStatusData] = useState<any>(null);
  const [costTrendsData, setCostTrendsData] = useState<any>(null);
  const [costPeriod, setCostPeriod] = useState<'week' | 'month' | 'year'>('week');
  
  const [dashboardLoading, setDashboardLoading] = useState(true);
  const [dashboardError, setDashboardError] = useState<string | null>(null);

  // Overview 데이터 로드
  useEffect(() => {
    loadOverviewData();
    loadDashboardData();
    
    // 자동 새로고침 (30초마다)
    const interval = setInterval(() => {
      loadDashboardData();
    }, 30000);
    
    return () => clearInterval(interval);
  }, []);

  // Cost Period 변경 시 데이터 로드
  useEffect(() => {
    loadCostTrendsData();
  }, [costPeriod]);

  const loadOverviewData = async () => {
    try {
      setLoading(true);
      setError(null);
      const data = await getOverviewReport();
      setOverviewData(data);
    } catch (err) {
      console.error('Failed to load overview:', err);
      setError('Unable to load report');
    } finally {
      setLoading(false);
    }
  };

  const loadDashboardData = async () => {
    try {
      setDashboardLoading(true);
      setDashboardError(null);
      
      // 병렬로 모든 데이터 로드
      const [resources, topUsers, jobStatus, costTrends] = await Promise.all([
        getDashboardResources(),
        getDashboardTopUsers(10),
        getDashboardJobStatus(),
        getDashboardCostTrends(costPeriod),
      ]);
      
      setResourceData(resources);
      setTopUsersData(topUsers.users || []);
      setJobStatusData(jobStatus);
      setCostTrendsData(costTrends);
    } catch (err) {
      console.error('Failed to load dashboard data:', err);
      setDashboardError('Unable to load dashboard data');
    } finally {
      setDashboardLoading(false);
    }
  };

  const loadCostTrendsData = async () => {
    try {
      const data = await getDashboardCostTrends(costPeriod);
      setCostTrendsData(data);
    } catch (err) {
      console.error('Failed to load cost trends:', err);
    }
  };

  const handleCostPeriodChange = (newPeriod: 'week' | 'month' | 'year') => {
    setCostPeriod(newPeriod);
  };

  // 다운로드 핸들러
  const handleDownload = (reportType: 'usage' | 'costs', format: 'pdf' | 'excel') => {
    const url = getReportDownloadUrl(reportType, format, period);
    window.open(url, '_blank');
  };

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-900 p-6">
      {/* 헤더 */}
      <div className="mb-8">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-3xl font-bold text-gray-900 dark:text-white flex items-center gap-3">
              <ChartBarIcon className="w-8 h-8 text-blue-600" />
              Reports
            </h1>
            <p className="mt-2 text-gray-600 dark:text-gray-400">
              System usage and cost analysis reports
            </p>
          </div>

          {/* 새로고침 버튼 */}
          <button
            onClick={() => {
              loadOverviewData();
              loadDashboardData();
            }}
            disabled={loading || dashboardLoading}
            className="flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors disabled:opacity-50"
          >
            <ArrowPathIcon className={`w-5 h-5 ${(loading || dashboardLoading) ? 'animate-spin' : ''}`} />
            Refresh
          </button>
        </div>
      </div>

      {/* 에러 메시지 */}
      {error && (
        <div className="mb-6 p-4 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg">
          <p className="text-red-800 dark:text-red-200">{error}</p>
        </div>
      )}

      {/* 로딩 상태 */}
      {loading && !overviewData ? (
        <div className="flex items-center justify-center py-12">
          <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600"></div>
        </div>
      ) : (
        <>
          {/* 빠른 통계 */}
          {overviewData && (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-5 gap-6 mb-8">
              {/* 총 사용자 */}
              <div className="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm text-gray-600 dark:text-gray-400">Total Users</p>
                    <p className="text-2xl font-bold text-gray-900 dark:text-white mt-1">
                      {overviewData.summary.total_users}
                    </p>
                  </div>
                  <div className="p-3 bg-blue-100 dark:bg-blue-900/30 rounded-lg">
                    <CpuChipIcon className="w-6 h-6 text-blue-600 dark:text-blue-400" />
                  </div>
                </div>
              </div>

              {/* 활성 사용자 */}
              <div className="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm text-gray-600 dark:text-gray-400">Active Users</p>
                    <p className="text-2xl font-bold text-gray-900 dark:text-white mt-1">
                      {overviewData.summary.active_users}
                    </p>
                  </div>
                  <div className="p-3 bg-green-100 dark:bg-green-900/30 rounded-lg">
                    <ChartBarIcon className="w-6 h-6 text-green-600 dark:text-green-400" />
                  </div>
                </div>
              </div>

              {/* 실행 중 작업 */}
              <div className="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm text-gray-600 dark:text-gray-400">Running</p>
                    <p className="text-2xl font-bold text-gray-900 dark:text-white mt-1">
                      {overviewData.summary.running_jobs}
                    </p>
                  </div>
                  <div className="p-3 bg-purple-100 dark:bg-purple-900/30 rounded-lg">
                    <ClockIcon className="w-6 h-6 text-purple-600 dark:text-purple-400" />
                  </div>
                </div>
              </div>

              {/* 오늘 비용 */}
              <div className="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm text-gray-600 dark:text-gray-400">Today</p>
                    <p className="text-2xl font-bold text-gray-900 dark:text-white mt-1">
                      ${overviewData.costs_today.toFixed(2)}
                    </p>
                  </div>
                  <div className="p-3 bg-yellow-100 dark:bg-yellow-900/30 rounded-lg">
                    <CurrencyDollarIcon className="w-6 h-6 text-yellow-600 dark:text-yellow-400" />
                  </div>
                </div>
              </div>

              {/* 이번 달 비용 */}
              <div className="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm text-gray-600 dark:text-gray-400">This Month</p>
                    <p className="text-2xl font-bold text-gray-900 dark:text-white mt-1">
                      ${overviewData.costs_this_month.toFixed(2)}
                    </p>
                  </div>
                  <div className="p-3 bg-red-100 dark:bg-red-900/30 rounded-lg">
                    <CurrencyDollarIcon className="w-6 h-6 text-red-600 dark:text-red-400" />
                  </div>
                </div>
              </div>
            </div>
          )}

          {/* ========== v3.4.0: 실시간 대시보드 차트 ========== */}
          <div className="mb-8">
            <h2 className="text-2xl font-bold text-gray-900 dark:text-white mb-6">
              📊 Real-time Dashboard
            </h2>
            
            {dashboardError && (
              <div className="mb-6 p-4 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg">
                <p className="text-red-800 dark:text-red-200">{dashboardError}</p>
              </div>
            )}

            {/* 차트 그리드 */}
            <div className="grid grid-cols-1 gap-6">
              {/* 리소스 사용률 차트 (전체 너비) */}
              <div className="col-span-1">
                <ResourceUsageChart 
                  data={resourceData || { timestamps: [], cpu_usage: [], gpu_usage: [], memory_usage: [] }} 
                  loading={dashboardLoading}
                  error={dashboardError}
                />
              </div>

              {/* 2열 그리드 */}
              <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                {/* Top 사용자 테이블 */}
                <div>
                  <TopUsersTable 
                    users={topUsersData}
                    loading={dashboardLoading}
                    error={dashboardError}
                  />
                </div>

                {/* 작업 상태 파이 차트 */}
                <div>
                  <JobStatusPieChart 
                    data={jobStatusData || { running: 0, pending: 0, completed: 0, failed: 0, cancelled: 0, total: 0 }}
                    loading={dashboardLoading}
                    error={dashboardError}
                  />
                </div>
              </div>

              {/* 비용 추이 차트 (전체 너비) */}
              <div className="col-span-1">
                <CostTrendsChart 
                  data={costTrendsData || { period: 'week', dates: [], daily_costs: [], cumulative_costs: [], total_cost: 0, average_daily_cost: 0 }}
                  loading={dashboardLoading}
                  error={dashboardError}
                  onPeriodChange={handleCostPeriodChange}
                />
              </div>
            </div>
          </div>

          {/* ========== 기존 리포트 다운로드 섹션 ========== */}
          <div className="mb-8">
            <h2 className="text-2xl font-bold text-gray-900 dark:text-white mb-6">
              📥 Report Download
            </h2>

            {/* 기간 선택 */}
            <div className="bg-white dark:bg-gray-800 rounded-lg shadow p-6 mb-6">
              <div className="flex items-center gap-4">
                <CalendarIcon className="w-5 h-5 text-gray-600 dark:text-gray-400" />
                <span className="text-gray-700 dark:text-gray-300 font-medium">Period:</span>
                <div className="flex gap-2">
                  {(['today', 'week', 'month', 'year'] as ReportPeriod[]).map((p) => (
                    <button
                      key={p}
                      onClick={() => setPeriod(p)}
                      className={`px-4 py-2 rounded-lg font-medium transition-colors ${
                        period === p
                          ? 'bg-blue-600 text-white'
                          : 'bg-gray-100 dark:bg-gray-700 text-gray-700 dark:text-gray-300 hover:bg-gray-200 dark:hover:bg-gray-600'
                      }`}
                    >
                      {p === 'today' && 'Today'}
                      {p === 'week' && 'This Week'}
                      {p === 'month' && 'This Month'}
                      {p === 'year' && 'This Year'}
                    </button>
                  ))}
                </div>
              </div>
            </div>

            {/* 리포트 다운로드 카드 */}
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
              {/* Usage Report */}
              <div className="bg-white dark:bg-gray-800 rounded-lg shadow-lg overflow-hidden">
                <div className="bg-gradient-to-r from-blue-600 to-blue-700 p-6">
                  <h3 className="text-2xl font-bold text-white flex items-center gap-3">
                    <ChartBarIcon className="w-7 h-7" />
                    Usage Report
                  </h3>
                  <p className="text-blue-100 mt-2">
                    Resource usage and job statistics
                  </p>
                </div>
                
                <div className="p-6">
                  <div className="space-y-4">
                    <div>
                      <h4 className="text-sm font-semibold text-gray-700 dark:text-gray-300 mb-2">
                        Contents:
                      </h4>
                      <ul className="text-sm text-gray-600 dark:text-gray-400 space-y-1">
                        <li className="flex items-center gap-2">
                          <span className="w-1.5 h-1.5 bg-blue-600 rounded-full"></span>
                          CPU, GPU, Memory usage time
                        </li>
                        <li className="flex items-center gap-2">
                          <span className="w-1.5 h-1.5 bg-blue-600 rounded-full"></span>
                          Job submission/completion/failure stats
                        </li>
                        <li className="flex items-center gap-2">
                          <span className="w-1.5 h-1.5 bg-blue-600 rounded-full"></span>
                          Cost analysis (by resource)
                        </li>
                        <li className="flex items-center gap-2">
                          <span className="w-1.5 h-1.5 bg-blue-600 rounded-full"></span>
                          Daily detailed data
                        </li>
                      </ul>
                    </div>

                    <div className="pt-4 border-t border-gray-200 dark:border-gray-700">
                      <p className="text-xs text-gray-500 dark:text-gray-400 mb-4">
                        Selected period: <span className="font-semibold">{period}</span>
                      </p>
                      
                      <div className="grid grid-cols-2 gap-3">
                        <button
                          onClick={() => handleDownload('usage', 'pdf')}
                          className="flex items-center justify-center gap-2 px-4 py-3 bg-red-600 text-white rounded-lg hover:bg-red-700 transition-colors font-medium"
                        >
                          <DocumentTextIcon className="w-5 h-5" />
                          PDF
                        </button>
                        
                        <button
                          onClick={() => handleDownload('usage', 'excel')}
                          className="flex items-center justify-center gap-2 px-4 py-3 bg-green-600 text-white rounded-lg hover:bg-green-700 transition-colors font-medium"
                        >
                          <TableCellsIcon className="w-5 h-5" />
                          Excel
                        </button>
                      </div>
                    </div>
                  </div>
                </div>
              </div>

              {/* Costs Report */}
              <div className="bg-white dark:bg-gray-800 rounded-lg shadow-lg overflow-hidden">
                <div className="bg-gradient-to-r from-green-600 to-green-700 p-6">
                  <h3 className="text-2xl font-bold text-white flex items-center gap-3">
                    <CurrencyDollarIcon className="w-7 h-7" />
                    Cost Report
                  </h3>
                  <p className="text-green-100 mt-2">
                    Detailed cost analysis and trends
                  </p>
                </div>
                
                <div className="p-6">
                  <div className="space-y-4">
                    <div>
                      <h4 className="text-sm font-semibold text-gray-700 dark:text-gray-300 mb-2">
                        Contents:
                      </h4>
                      <ul className="text-sm text-gray-600 dark:text-gray-400 space-y-1">
                        <li className="flex items-center gap-2">
                          <span className="w-1.5 h-1.5 bg-green-600 rounded-full"></span>
                          Cost by resource (CPU, GPU, Memory)
                        </li>
                        <li className="flex items-center gap-2">
                          <span className="w-1.5 h-1.5 bg-green-600 rounded-full"></span>
                          Cost distribution and ratios
                        </li>
                        <li className="flex items-center gap-2">
                          <span className="w-1.5 h-1.5 bg-green-600 rounded-full"></span>
                          Rate information (unit price)
                        </li>
                        <li className="flex items-center gap-2">
                          <span className="w-1.5 h-1.5 bg-green-600 rounded-full"></span>
                          Daily cost trends
                        </li>
                      </ul>
                    </div>

                    <div className="pt-4 border-t border-gray-200 dark:border-gray-700">
                      <p className="text-xs text-gray-500 dark:text-gray-400 mb-4">
                        Selected period: <span className="font-semibold">{period}</span>
                      </p>
                      
                      <div className="grid grid-cols-2 gap-3">
                        <button
                          onClick={() => handleDownload('costs', 'pdf')}
                          className="flex items-center justify-center gap-2 px-4 py-3 bg-red-600 text-white rounded-lg hover:bg-red-700 transition-colors font-medium"
                        >
                          <DocumentTextIcon className="w-5 h-5" />
                          PDF
                        </button>
                        
                        <button
                          onClick={() => handleDownload('costs', 'excel')}
                          className="flex items-center justify-center gap-2 px-4 py-3 bg-green-600 text-white rounded-lg hover:bg-green-700 transition-colors font-medium"
                        >
                          <TableCellsIcon className="w-5 h-5" />
                          Excel
                        </button>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            {/* 안내 메시지 */}
            <div className="mt-6 bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-800 rounded-lg p-6">
              <div className="flex items-start gap-3">
                <DocumentArrowDownIcon className="w-6 h-6 text-blue-600 dark:text-blue-400 flex-shrink-0 mt-0.5" />
                <div>
                  <h3 className="font-semibold text-blue-900 dark:text-blue-100 mb-2">
                    Report Download Guide
                  </h3>
                  <ul className="text-sm text-blue-800 dark:text-blue-200 space-y-1">
                    <li>• PDF: Professional format suitable for printing and sharing</li>
                    <li>• Excel: Format suitable for data analysis and processing (includes charts)</li>
                    <li>• Reports include data for the selected period</li>
                    <li>• Auto-refresh: Real-time data updates every 30 seconds</li>
                  </ul>
                </div>
              </div>
            </div>
          </div>
        </>
      )}
    </div>
  );
};

export default Reports;
