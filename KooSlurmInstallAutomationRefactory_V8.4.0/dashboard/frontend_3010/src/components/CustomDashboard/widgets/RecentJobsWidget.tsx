import React, { useState, useEffect } from 'react';
import { List, GripVertical, X, CheckCircle, XCircle, Clock, Play } from 'lucide-react';
import { WidgetProps } from '../widgetRegistry';
import { apiGet } from '../../../utils/api';

interface Job {
  id: string;
  name: string;
  state: string;
  user: string;
  submitTime: string;
}

const RecentJobsWidget: React.FC<WidgetProps> = ({ id, onRemove, isEditMode, mode }) => {
  const [jobs, setJobs] = useState<Job[]>([]);
  const [loading, setLoading] = useState(true);
  const [usingMockData, setUsingMockData] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetchRecentJobs();
    const interval = setInterval(fetchRecentJobs, 10000);
    return () => clearInterval(interval);
  }, [mode]);

  const fetchRecentJobs = async () => {
    setError(null);
    
    // Production 모드: 실제 API 시도
    if (mode === 'production') {
      try {
        const response = await apiGet('/api/jobs?limit=5');
        if (response?.jobs && Array.isArray(response.jobs)) {
          // 실제 API 응답을 위젯 형식으로 변환
          const formattedJobs = response.jobs.slice(0, 5).map((job: any) => ({
            id: job.job_id || job.id || 'N/A',
            name: job.job_name || job.name || 'Unknown',
            state: job.job_state || job.state || 'UNKNOWN',
            user: job.user_name || job.user || 'unknown',
            submitTime: job.submit_time || job.submitTime || 'N/A'
          }));
          setJobs(formattedJobs);
          setUsingMockData(false);
          setLoading(false);
          console.log('[RecentJobsWidget] Successfully loaded', formattedJobs.length, 'jobs');
          return;
        } else {
          setError('Recent jobs information not found');
          setJobs([]);
          setUsingMockData(false);
          setLoading(false);
          return;
        }
      } catch (error) {
        console.error('[RecentJobsWidget] Production API error:', error);
        setError('Failed to fetch recent jobs data');
        setJobs([]);
        setUsingMockData(false);
        setLoading(false);
        return;
      }
    }
    
    // Mock 모드: Mock 데이터 사용
    const mockJobs: Job[] = [
      { id: '12345', name: 'training_model_v2', state: 'RUNNING', user: 'user1', submitTime: '2분 전' },
      { id: '12346', name: 'data_preprocessing', state: 'COMPLETED', user: 'user2', submitTime: '5분 전' },
      { id: '12347', name: 'simulation_run', state: 'PENDING', user: 'user3', submitTime: '8분 전' },
      { id: '12348', name: 'analysis_job', state: 'RUNNING', user: 'user1', submitTime: '12분 전' },
      { id: '12349', name: 'backup_task', state: 'FAILED', user: 'user4', submitTime: '15분 전' },
    ];
    setJobs(mockJobs);
    setUsingMockData(true);
    setLoading(false);
    console.log('[RecentJobsWidget] Using mock job data');
  };

  const getStateIcon = (state: string) => {
    switch (state.toUpperCase()) {
      case 'RUNNING':
        return <Play className="w-4 h-4 text-blue-500" />;
      case 'COMPLETED':
        return <CheckCircle className="w-4 h-4 text-green-500" />;
      case 'FAILED':
        return <XCircle className="w-4 h-4 text-red-500" />;
      case 'PENDING':
        return <Clock className="w-4 h-4 text-yellow-500" />;
      default:
        return <Clock className="w-4 h-4 text-gray-500" />;
    }
  };

  const getStateBadge = (state: string) => {
    const upperState = state.toUpperCase();
    const styles = {
      RUNNING: 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400',
      COMPLETED: 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400',
      FAILED: 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400',
      PENDING: 'bg-yellow-100 text-yellow-700 dark:bg-yellow-900/30 dark:text-yellow-400',
    };
    return styles[upperState as keyof typeof styles] || 'bg-gray-100 text-gray-700 dark:bg-gray-700 dark:text-gray-400';
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
          <List className="w-5 h-5 text-indigo-500" />
          <h3 className="font-semibold text-gray-900 dark:text-white">Recent Jobs</h3>
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
      <div className="flex-1 overflow-y-auto p-4">
        {loading ? (
          <div className="text-center py-8">
            <div className="w-8 h-8 border-4 border-indigo-600 border-t-transparent rounded-full animate-spin mx-auto mb-2"></div>
            <p className="text-sm text-gray-500 dark:text-gray-400">Loading...</p>
          </div>
        ) : error ? (
          <div className="text-center text-red-500 dark:text-red-400 py-8">
            <List className="w-12 h-12 mx-auto mb-3 opacity-50" />
            <p className="font-medium">{error}</p>
            <p className="text-sm text-gray-500 dark:text-gray-400 mt-2">
              Check Slurm Jobs API
            </p>
          </div>
        ) : jobs.length === 0 ? (
          <div className="text-center text-gray-500 dark:text-gray-400 py-8">
            <List className="w-12 h-12 mx-auto mb-3 opacity-50" />
            <p className="font-medium">No Recent Jobs</p>
            {mode === 'production' && (
              <p className="text-sm mt-2">
                No submitted jobs or job history not found
              </p>
            )}
          </div>
        ) : (
          <div className="space-y-2">
            {jobs.map(job => (
              <div
                key={job.id}
                className="bg-gray-50 dark:bg-gray-700/50 rounded-lg p-3 hover:bg-gray-100 dark:hover:bg-gray-700 transition-colors cursor-pointer"
              >
                <div className="flex items-start justify-between mb-2">
                  <div className="flex items-center gap-2 flex-1 min-w-0">
                    {getStateIcon(job.state)}
                    <div className="flex-1 min-w-0">
                      <h4 className="font-medium text-gray-900 dark:text-white truncate">
                        {job.name}
                      </h4>
                      <p className="text-xs text-gray-500 dark:text-gray-400">
                        Job ID: {job.id}
                      </p>
                    </div>
                  </div>
                  <span className={`px-2 py-1 rounded text-xs font-medium whitespace-nowrap ${getStateBadge(job.state)}`}>
                    {job.state}
                  </span>
                </div>
                
                <div className="flex items-center justify-between text-xs text-gray-500 dark:text-gray-400">
                  <span>{job.user}</span>
                  <span>{job.submitTime}</span>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
};

export default RecentJobsWidget;
