import React, { useState, useEffect } from 'react';
import { Clock, GripVertical, X, Users, AlertCircle } from 'lucide-react';
import { WidgetProps } from '../widgetRegistry';
import { apiGet } from '../../../utils/api';

const JobQueueWidget: React.FC<WidgetProps> = ({ id, onRemove, isEditMode, mode }) => {
  const [queueData, setQueueData] = useState({
    pending: 0,
    running: 0,
    avgWaitTime: 0
  });
  const [loading, setLoading] = useState(true);
  const [usingMockData, setUsingMockData] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetchQueueData();
    const interval = setInterval(fetchQueueData, 10000);
    return () => clearInterval(interval);
  }, [mode]);

  const fetchQueueData = async () => {
    setError(null);
    
    // Production 모드: 실제 API 시도
    if (mode === 'production') {
      try {
        const [pendingRes, runningRes] = await Promise.all([
          apiGet('/api/jobs', { state: 'PENDING' }),
          apiGet('/api/jobs', { state: 'RUNNING' })
        ]);

        // Handle direct array response or jobs property
        const pendingJobs = Array.isArray(pendingRes) ? pendingRes : pendingRes?.jobs;
        const runningJobs = Array.isArray(runningRes) ? runningRes : runningRes?.jobs;

        if (pendingJobs !== undefined && runningJobs !== undefined) {
          const pending = Array.isArray(pendingJobs) ? pendingJobs.length : 0;
          const running = Array.isArray(runningJobs) ? runningJobs.length : 0;
          
          // 평균 대기 시간 계산
          const avgWaitTime = pending > 0 ? Math.floor(pending / Math.max(running, 1) * 5) : 0;
          
          setQueueData({ pending, running, avgWaitTime });
          setUsingMockData(false);
          setLoading(false);
          console.log('[JobQueueWidget] Successfully loaded job queue data');
          return;
        } else {
          throw new Error('Job queue information not found');
        }
      } catch (error) {
        console.error('[JobQueueWidget] Production API error:', error);
        const errorMessage = error instanceof Error ? error.message : 'Failed to fetch job queue data';
        setError(errorMessage);
        setQueueData({ pending: 0, running: 0, avgWaitTime: 0 });
        setUsingMockData(false);
        setLoading(false);
        return;
      }
    }
    
    // Mock 모드: Mock 데이터 사용
    setQueueData({
      pending: Math.floor(Math.random() * 20) + 5,
      running: Math.floor(Math.random() * 15) + 10,
      avgWaitTime: Math.floor(Math.random() * 30) + 5
    });
    setUsingMockData(true);
    setLoading(false);
    console.log('[JobQueueWidget] Using mock job queue data');
  };

  const getQueueStatus = (pending: number) => {
    if (pending < 10) return { color: 'text-green-500', bg: 'bg-green-50 dark:bg-green-900/20', label: 'Smooth' };
    if (pending < 20) return { color: 'text-yellow-500', bg: 'bg-yellow-50 dark:bg-yellow-900/20', label: 'Moderate' };
    return { color: 'text-red-500', bg: 'bg-red-50 dark:bg-red-900/20', label: 'Busy' };
  };

  const status = getQueueStatus(queueData.pending);

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
          <Clock className="w-5 h-5 text-orange-500" />
          <h3 className="font-semibold text-gray-900 dark:text-white">Job Queue</h3>
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
            <div className="w-8 h-8 border-4 border-orange-600 border-t-transparent rounded-full animate-spin mx-auto mb-2"></div>
            <p className="text-sm text-gray-500 dark:text-gray-400">Loading...</p>
          </div>
        ) : error ? (
          <div className="text-center text-red-500 dark:text-red-400 py-8">
            <Clock className="w-12 h-12 mx-auto mb-3 opacity-50" />
            <p className="font-medium">{error}</p>
            <p className="text-sm text-gray-500 dark:text-gray-400 mt-2">
              Check Slurm Jobs API
            </p>
          </div>
        ) : queueData.pending === 0 && queueData.running === 0 ? (
          <div className="text-center text-gray-500 dark:text-gray-400 py-8">
            <Clock className="w-12 h-12 mx-auto mb-3 opacity-50" />
            <p className="font-medium">No jobs found</p>
            <p className="text-sm text-gray-500 dark:text-gray-400 mt-2">
              {mode === 'production' ? 'Queue is currently empty' : 'Try mock mode'}
            </p>
          </div>
        ) : (
          <div>
            {/* Main Stats */}
            <div className="grid grid-cols-2 gap-4 mb-6">
              <div className={`${status.bg} rounded-lg p-4 text-center`}>
                <Clock className={`w-8 h-8 ${status.color} mx-auto mb-2`} />
                <div className={`text-3xl font-bold ${status.color}`}>
                  {queueData.pending}
                </div>
                <div className="text-sm text-gray-600 dark:text-gray-400 mt-1">Pending</div>
              </div>

              <div className="bg-blue-50 dark:bg-blue-900/20 rounded-lg p-4 text-center">
                <Users className="w-8 h-8 text-blue-500 mx-auto mb-2" />
                <div className="text-3xl font-bold text-blue-500">
                  {queueData.running}
                </div>
                <div className="text-sm text-gray-600 dark:text-gray-400 mt-1">Running</div>
              </div>
            </div>

            {/* Status Info */}
            <div className="space-y-3">
              <div className="flex items-center justify-between p-3 bg-gray-50 dark:bg-gray-700/50 rounded-lg">
                <span className="text-sm text-gray-600 dark:text-gray-400">Queue Status</span>
                <span className={`font-semibold ${status.color}`}>{status.label}</span>
              </div>

              <div className="flex items-center justify-between p-3 bg-gray-50 dark:bg-gray-700/50 rounded-lg">
                <span className="text-sm text-gray-600 dark:text-gray-400">Avg Wait Time</span>
                <span className="font-semibold text-gray-900 dark:text-white">
                  {queueData.avgWaitTime} min
                </span>
              </div>

              {queueData.pending > 15 && (
                <div className="flex items-start gap-2 p-3 bg-yellow-50 dark:bg-yellow-900/20 rounded-lg">
                  <AlertCircle className="w-5 h-5 text-yellow-600 dark:text-yellow-400 flex-shrink-0 mt-0.5" />
                  <div className="text-sm text-yellow-700 dark:text-yellow-300">
                    High number of pending jobs. Please check resources.
                  </div>
                </div>
              )}
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

export default JobQueueWidget;
