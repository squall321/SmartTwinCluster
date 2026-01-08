import React, { useState, useEffect, useRef, useCallback } from 'react';
import {
  X, FileText, Download, RefreshCw, Terminal, AlertCircle,
  CheckCircle, Clock, XCircle, Loader2, File, FolderOpen,
  ChevronDown, ChevronRight, Copy, ExternalLink
} from 'lucide-react';
import { apiGet, getApiUrl } from '../../utils/api';
import toast from 'react-hot-toast';

interface JobInfo {
  jobId: string;
  jobName: string;
  user: string;
  state: string;
  exitCode: string;
  startTime: string;
  endTime: string;
  elapsed: string;
  partition: string;
  nodes: string;
  cpus: string;
  memory: string;
  hasStdout: boolean;
  hasStderr: boolean;
  hasWorkDir: boolean;
}

interface JobFile {
  name: string;
  path: string;
  fullPath?: string;
  size: number;
  modified: string;
  type: 'file' | 'log';
  logType?: 'stdout' | 'stderr';
}

interface JobLogViewerProps {
  jobId: string;
  isOpen: boolean;
  onClose: () => void;
}

const formatBytes = (bytes: number): string => {
  if (bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
};

const getStateIcon = (state: string) => {
  switch (state) {
    case 'COMPLETED':
      return <CheckCircle className="w-5 h-5 text-green-500" />;
    case 'RUNNING':
      return <Loader2 className="w-5 h-5 text-blue-500 animate-spin" />;
    case 'PENDING':
      return <Clock className="w-5 h-5 text-yellow-500" />;
    case 'FAILED':
    case 'CANCELLED':
    case 'TIMEOUT':
      return <XCircle className="w-5 h-5 text-red-500" />;
    default:
      return <AlertCircle className="w-5 h-5 text-gray-500" />;
  }
};

const getStateBadgeColor = (state: string) => {
  switch (state) {
    case 'COMPLETED':
      return 'bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-400';
    case 'RUNNING':
      return 'bg-blue-100 text-blue-800 dark:bg-blue-900/30 dark:text-blue-400';
    case 'PENDING':
      return 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900/30 dark:text-yellow-400';
    case 'FAILED':
    case 'CANCELLED':
    case 'TIMEOUT':
      return 'bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-400';
    default:
      return 'bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-300';
  }
};

export const JobLogViewer: React.FC<JobLogViewerProps> = ({ jobId, isOpen, onClose }) => {
  const [jobInfo, setJobInfo] = useState<JobInfo | null>(null);
  const [logContent, setLogContent] = useState<string>('');
  const [logType, setLogType] = useState<'out' | 'err'>('out');
  const [files, setFiles] = useState<JobFile[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [autoRefresh, setAutoRefresh] = useState(false);
  const [activeTab, setActiveTab] = useState<'logs' | 'files'>('logs');
  const [showFilesPanel, setShowFilesPanel] = useState(true);

  const logContainerRef = useRef<HTMLPreElement>(null);
  const refreshIntervalRef = useRef<NodeJS.Timeout | null>(null);

  // Fetch job info
  const fetchJobInfo = useCallback(async () => {
    try {
      const response = await apiGet<{ success: boolean; job: JobInfo }>(
        `/api/jobs/${jobId}/info`
      );
      if (response.success) {
        setJobInfo(response.job);
      }
    } catch (error) {
      console.error('Failed to fetch job info:', error);
    }
  }, [jobId]);

  // Fetch log content
  const fetchLogs = useCallback(async (type: 'out' | 'err' = logType) => {
    try {
      const response = await apiGet<{
        success: boolean;
        content: string;
        lines: number;
        totalLines: number;
        truncated: boolean;
        state?: string;
      }>(`/api/jobs/${jobId}/logs?type=${type}`);

      if (response.success) {
        setLogContent(response.content);

        // Auto-scroll to bottom
        setTimeout(() => {
          if (logContainerRef.current) {
            logContainerRef.current.scrollTop = logContainerRef.current.scrollHeight;
          }
        }, 100);
      }
    } catch (error) {
      console.error('Failed to fetch logs:', error);
      setLogContent('[Error loading logs]');
    }
  }, [jobId, logType]);

  // Fetch file list
  const fetchFiles = useCallback(async () => {
    try {
      const response = await apiGet<{
        success: boolean;
        files: JobFile[];
        fileCount: number;
      }>(`/api/jobs/${jobId}/files`);

      if (response.success) {
        setFiles(response.files);
      }
    } catch (error) {
      console.error('Failed to fetch files:', error);
    }
  }, [jobId]);

  // Initial load
  useEffect(() => {
    if (isOpen && jobId) {
      setIsLoading(true);
      Promise.all([fetchJobInfo(), fetchLogs(), fetchFiles()])
        .finally(() => setIsLoading(false));
    }
  }, [isOpen, jobId, fetchJobInfo, fetchLogs, fetchFiles]);

  // Auto-refresh for running jobs
  useEffect(() => {
    if (autoRefresh && jobInfo?.state === 'RUNNING') {
      refreshIntervalRef.current = setInterval(() => {
        fetchLogs();
      }, 2000);
    }

    return () => {
      if (refreshIntervalRef.current) {
        clearInterval(refreshIntervalRef.current);
      }
    };
  }, [autoRefresh, jobInfo?.state, fetchLogs]);

  // Handle log type change
  const handleLogTypeChange = (type: 'out' | 'err') => {
    setLogType(type);
    fetchLogs(type);
  };

  // Manual refresh
  const handleRefresh = async () => {
    setIsRefreshing(true);
    await Promise.all([fetchJobInfo(), fetchLogs(), fetchFiles()]);
    setIsRefreshing(false);
    toast.success('Refreshed');
  };

  // Copy log content
  const handleCopyLogs = () => {
    navigator.clipboard.writeText(logContent);
    toast.success('Logs copied to clipboard');
  };

  // Download file
  const handleDownloadFile = (file: JobFile) => {
    const path = file.logType === 'stdout' ? 'stdout' :
                 file.logType === 'stderr' ? 'stderr' :
                 file.path;
    const url = getApiUrl(`/api/jobs/${jobId}/files/download?path=${encodeURIComponent(path)}`);
    window.open(url, '_blank');
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
      <div className="bg-white dark:bg-gray-800 rounded-lg shadow-2xl w-[90vw] h-[85vh] max-w-6xl flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b dark:border-gray-700">
          <div className="flex items-center gap-4">
            <Terminal className="w-6 h-6 text-blue-500" />
            <div>
              <h2 className="text-lg font-semibold text-gray-900 dark:text-white">
                Job #{jobId}
                {jobInfo && (
                  <span className="ml-2 text-gray-500 dark:text-gray-400 font-normal">
                    - {jobInfo.jobName}
                  </span>
                )}
              </h2>
              {jobInfo && (
                <div className="flex items-center gap-3 mt-1 text-sm text-gray-500 dark:text-gray-400">
                  <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${getStateBadgeColor(jobInfo.state)}`}>
                    {jobInfo.state}
                  </span>
                  <span>User: {jobInfo.user}</span>
                  <span>Partition: {jobInfo.partition}</span>
                  <span>Duration: {jobInfo.elapsed}</span>
                </div>
              )}
            </div>
          </div>

          <div className="flex items-center gap-2">
            <button
              onClick={handleRefresh}
              disabled={isRefreshing}
              className="p-2 hover:bg-gray-100 dark:hover:bg-gray-700 rounded-lg transition-colors"
              title="Refresh"
            >
              <RefreshCw className={`w-5 h-5 ${isRefreshing ? 'animate-spin' : ''}`} />
            </button>
            <button
              onClick={onClose}
              className="p-2 hover:bg-gray-100 dark:hover:bg-gray-700 rounded-lg transition-colors"
            >
              <X className="w-5 h-5" />
            </button>
          </div>
        </div>

        {/* Content */}
        <div className="flex-1 flex overflow-hidden">
          {/* Left Panel - Job Info & Files */}
          <div className={`${showFilesPanel ? 'w-64' : 'w-0'} border-r dark:border-gray-700 flex flex-col overflow-hidden transition-all`}>
            {showFilesPanel && (
              <>
                {/* Job Info Summary */}
                {jobInfo && (
                  <div className="p-4 border-b dark:border-gray-700 space-y-2 text-sm">
                    <div className="flex items-center gap-2">
                      {getStateIcon(jobInfo.state)}
                      <span className="font-medium">{jobInfo.state}</span>
                    </div>
                    <div className="grid grid-cols-2 gap-2 text-gray-600 dark:text-gray-400">
                      <div>
                        <span className="text-xs text-gray-400">Exit Code</span>
                        <div className={jobInfo.exitCode === '0:0' ? 'text-green-600' : 'text-red-600'}>
                          {jobInfo.exitCode}
                        </div>
                      </div>
                      <div>
                        <span className="text-xs text-gray-400">Nodes</span>
                        <div>{jobInfo.nodes}</div>
                      </div>
                      <div>
                        <span className="text-xs text-gray-400">CPUs</span>
                        <div>{jobInfo.cpus}</div>
                      </div>
                      <div>
                        <span className="text-xs text-gray-400">Memory</span>
                        <div>{jobInfo.memory}</div>
                      </div>
                    </div>
                    <div className="text-xs text-gray-500">
                      <div>Start: {jobInfo.startTime}</div>
                      <div>End: {jobInfo.endTime || 'N/A'}</div>
                    </div>
                  </div>
                )}

                {/* Files List */}
                <div className="flex-1 overflow-y-auto p-4">
                  <h3 className="text-sm font-medium text-gray-700 dark:text-gray-300 mb-2 flex items-center gap-2">
                    <FolderOpen className="w-4 h-4" />
                    Files ({files.length})
                  </h3>
                  <div className="space-y-1">
                    {files.length === 0 ? (
                      <p className="text-sm text-gray-500 dark:text-gray-400 italic">
                        No files available
                      </p>
                    ) : (
                      files.map((file, idx) => (
                        <div
                          key={idx}
                          className="flex items-center justify-between p-2 hover:bg-gray-100 dark:hover:bg-gray-700 rounded cursor-pointer group"
                          onClick={() => {
                            if (file.logType === 'stdout') {
                              handleLogTypeChange('out');
                              setActiveTab('logs');
                            } else if (file.logType === 'stderr') {
                              handleLogTypeChange('err');
                              setActiveTab('logs');
                            }
                          }}
                        >
                          <div className="flex items-center gap-2 min-w-0">
                            {file.type === 'log' ? (
                              <FileText className="w-4 h-4 text-blue-500 flex-shrink-0" />
                            ) : (
                              <File className="w-4 h-4 text-gray-400 flex-shrink-0" />
                            )}
                            <div className="min-w-0">
                              <div className="text-sm truncate">{file.name}</div>
                              <div className="text-xs text-gray-500">{formatBytes(file.size)}</div>
                            </div>
                          </div>
                          <button
                            onClick={(e) => {
                              e.stopPropagation();
                              handleDownloadFile(file);
                            }}
                            className="opacity-0 group-hover:opacity-100 p-1 hover:bg-gray-200 dark:hover:bg-gray-600 rounded transition-opacity"
                            title="Download"
                          >
                            <Download className="w-4 h-4" />
                          </button>
                        </div>
                      ))
                    )}
                  </div>
                </div>
              </>
            )}
          </div>

          {/* Toggle Files Panel Button */}
          <button
            onClick={() => setShowFilesPanel(!showFilesPanel)}
            className="absolute left-0 top-1/2 -translate-y-1/2 z-10 bg-gray-200 dark:bg-gray-700 p-1 rounded-r-lg hover:bg-gray-300 dark:hover:bg-gray-600"
            style={{ left: showFilesPanel ? '256px' : '0' }}
          >
            {showFilesPanel ? <ChevronLeft className="w-4 h-4" /> : <ChevronRight className="w-4 h-4" />}
          </button>

          {/* Right Panel - Logs */}
          <div className="flex-1 flex flex-col overflow-hidden">
            {/* Log Type Tabs */}
            <div className="flex items-center justify-between px-4 py-2 border-b dark:border-gray-700 bg-gray-50 dark:bg-gray-900">
              <div className="flex gap-2">
                <button
                  onClick={() => handleLogTypeChange('out')}
                  className={`px-3 py-1.5 text-sm rounded-lg transition-colors ${
                    logType === 'out'
                      ? 'bg-blue-500 text-white'
                      : 'text-gray-600 dark:text-gray-400 hover:bg-gray-200 dark:hover:bg-gray-700'
                  }`}
                >
                  stdout
                </button>
                <button
                  onClick={() => handleLogTypeChange('err')}
                  className={`px-3 py-1.5 text-sm rounded-lg transition-colors ${
                    logType === 'err'
                      ? 'bg-red-500 text-white'
                      : 'text-gray-600 dark:text-gray-400 hover:bg-gray-200 dark:hover:bg-gray-700'
                  }`}
                >
                  stderr
                </button>
              </div>

              <div className="flex items-center gap-2">
                {jobInfo?.state === 'RUNNING' && (
                  <label className="flex items-center gap-2 text-sm text-gray-600 dark:text-gray-400">
                    <input
                      type="checkbox"
                      checked={autoRefresh}
                      onChange={(e) => setAutoRefresh(e.target.checked)}
                      className="rounded"
                    />
                    Auto-refresh
                  </label>
                )}
                <button
                  onClick={handleCopyLogs}
                  className="p-1.5 hover:bg-gray-200 dark:hover:bg-gray-700 rounded transition-colors"
                  title="Copy logs"
                >
                  <Copy className="w-4 h-4" />
                </button>
                <button
                  onClick={() => handleDownloadFile({ name: `${jobId}.${logType}`, path: logType === 'out' ? 'stdout' : 'stderr', size: 0, modified: '', type: 'log', logType: logType === 'out' ? 'stdout' : 'stderr' })}
                  className="p-1.5 hover:bg-gray-200 dark:hover:bg-gray-700 rounded transition-colors"
                  title="Download log"
                >
                  <Download className="w-4 h-4" />
                </button>
              </div>
            </div>

            {/* Log Content */}
            <div className="flex-1 overflow-hidden bg-gray-900">
              {isLoading ? (
                <div className="flex items-center justify-center h-full">
                  <Loader2 className="w-8 h-8 text-blue-500 animate-spin" />
                </div>
              ) : (
                <pre
                  ref={logContainerRef}
                  className="h-full overflow-auto p-4 text-sm font-mono text-green-400 whitespace-pre-wrap break-all"
                >
                  {logContent || '[No log content]'}
                </pre>
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

// ChevronLeft icon (not in lucide-react default exports)
const ChevronLeft: React.FC<{ className?: string }> = ({ className }) => (
  <svg className={className} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
    <path d="M15 18l-6-6 6-6" />
  </svg>
);

export default JobLogViewer;
