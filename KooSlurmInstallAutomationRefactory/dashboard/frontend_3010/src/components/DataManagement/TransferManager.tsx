import React, { useState } from 'react';
import {
  Activity,
  CheckCircle,
  XCircle,
  Clock,
  Loader,
  Download,
  Upload,
  MoveRight,
  Copy,
  Trash2,
  ChevronDown,
  ChevronUp,
  X
} from 'lucide-react';
import { TransferTask } from '../../types';
import { mockTransferTasks } from '../../data/mockStorageData';

const TransferManager: React.FC = () => {
  const [isExpanded, setIsExpanded] = useState(false);
  const [tasks, setTasks] = useState<TransferTask[]>(mockTransferTasks);

  const activeTasks = tasks.filter(t => t.status === 'running' || t.status === 'pending');
  const completedTasks = tasks.filter(t => t.status === 'completed');
  const failedTasks = tasks.filter(t => t.status === 'failed');

  const getTaskIcon = (type: TransferTask['type']) => {
    switch (type) {
      case 'move':
        return <MoveRight className="w-4 h-4 text-blue-400" />;
      case 'copy':
        return <Copy className="w-4 h-4 text-green-400" />;
      case 'delete':
        return <Trash2 className="w-4 h-4 text-red-400" />;
      case 'upload':
        return <Upload className="w-4 h-4 text-purple-400" />;
      case 'download':
        return <Download className="w-4 h-4 text-orange-400" />;
    }
  };

  const getStatusIcon = (status: TransferTask['status']) => {
    switch (status) {
      case 'running':
        return <Loader className="w-4 h-4 text-blue-400 animate-spin" />;
      case 'pending':
        return <Clock className="w-4 h-4 text-yellow-400" />;
      case 'completed':
        return <CheckCircle className="w-4 h-4 text-green-400" />;
      case 'failed':
        return <XCircle className="w-4 h-4 text-red-400" />;
      case 'cancelled':
        return <X className="w-4 h-4 text-gray-400" />;
    }
  };

  const getStatusColor = (status: TransferTask['status']) => {
    switch (status) {
      case 'running':
        return 'text-blue-300 bg-blue-500/10';
      case 'pending':
        return 'text-yellow-300 bg-yellow-500/10';
      case 'completed':
        return 'text-green-300 bg-green-500/10';
      case 'failed':
        return 'text-red-300 bg-red-500/10';
      case 'cancelled':
        return 'text-gray-300 bg-gray-500/10';
    }
  };

  const handleCancelTask = (taskId: string) => {
    setTasks(tasks.map(t => 
      t.id === taskId ? { ...t, status: 'cancelled' as const } : t
    ));
  };

  const handleRetryTask = (taskId: string) => {
    setTasks(tasks.map(t => 
      t.id === taskId ? { ...t, status: 'pending' as const, progress: 0, error: undefined } : t
    ));
  };

  const handleRemoveTask = (taskId: string) => {
    setTasks(tasks.filter(t => t.id !== taskId));
  };

  if (tasks.length === 0) return null;

  return (
    <div className="bg-gray-800 rounded-lg border border-gray-600 overflow-hidden">
      {/* Header */}
      <div 
        className="flex items-center justify-between p-4 cursor-pointer hover:bg-gray-700/50 transition"
        onClick={() => setIsExpanded(!isExpanded)}
      >
        <div className="flex items-center gap-3">
          <Activity className="w-5 h-5 text-purple-400" />
          <div>
            <h3 className="text-sm font-semibold text-gray-50">Transfer Manager</h3>
            <p className="text-xs text-gray-400">
              {activeTasks.length} active · {completedTasks.length} completed · {failedTasks.length} failed
            </p>
          </div>
        </div>

        <div className="flex items-center gap-3">
          {activeTasks.length > 0 && (
            <div className="flex items-center gap-2">
              <Loader className="w-4 h-4 text-blue-400 animate-spin" />
              <span className="text-sm text-blue-300">
                {activeTasks.length} in progress
              </span>
            </div>
          )}
          {isExpanded ? (
            <ChevronUp className="w-5 h-5 text-gray-400" />
          ) : (
            <ChevronDown className="w-5 h-5 text-gray-400" />
          )}
        </div>
      </div>

      {/* Task List */}
      {isExpanded && (
        <div className="border-t border-gray-600">
          <div className="max-h-96 overflow-y-auto">
            {tasks.map((task) => (
              <div
                key={task.id}
                className="p-4 border-b border-gray-600/50 last:border-b-0 hover:bg-gray-700/30 transition"
              >
                <div className="flex items-start justify-between gap-4">
                  <div className="flex items-start gap-3 flex-1 min-w-0">
                    {getTaskIcon(task.type)}
                    
                    <div className="flex-1 min-w-0">
                      {/* Task info */}
                      <div className="flex items-center gap-2 mb-1">
                        <span className="text-sm font-medium text-gray-50 capitalize">
                          {task.type}
                        </span>
                        <span className={`text-xs px-2 py-0.5 rounded font-medium ${getStatusColor(task.status)}`}>
                          {task.status}
                        </span>
                      </div>

                      {/* Paths */}
                      <div className="space-y-1 mb-2">
                        <div className="flex items-center gap-2 text-xs text-gray-300">
                          <span className="text-gray-400">From:</span>
                          <span className="font-mono truncate">{task.source}</span>
                        </div>
                        {task.destination && (
                          <div className="flex items-center gap-2 text-xs text-gray-300">
                            <span className="text-gray-400">To:</span>
                            <span className="font-mono truncate">{task.destination}</span>
                          </div>
                        )}
                      </div>

                      {/* Progress bar */}
                      {(task.status === 'running' || task.status === 'pending') && (
                        <div className="mb-2">
                          <div className="flex items-center justify-between text-xs text-gray-400 mb-1">
                            <span>{task.progress}%</span>
                            <div className="flex items-center gap-3">
                              {task.speed && <span>{task.speed}</span>}
                              {task.eta && <span>ETA: {task.eta}</span>}
                            </div>
                          </div>
                          <div className="bg-gray-700 rounded-full h-1.5">
                            <div
                              className="bg-blue-500 rounded-full h-1.5 transition-all"
                              style={{ width: `${task.progress}%` }}
                            />
                          </div>
                        </div>
                      )}

                      {/* Stats */}
                      <div className="flex items-center gap-4 text-xs text-gray-400">
                        {task.fileCount && <span>{task.fileCount.toLocaleString()} files</span>}
                        {task.totalSize && <span>{task.totalSize}</span>}
                        {task.startTime && task.status === 'running' && (
                          <span>Started {new Date(task.startTime).toLocaleTimeString()}</span>
                        )}
                        {task.endTime && task.status === 'completed' && (
                          <span>Completed {new Date(task.endTime).toLocaleTimeString()}</span>
                        )}
                      </div>

                      {/* Error message */}
                      {task.error && (
                        <div className="mt-2 text-xs text-red-300 bg-red-900/20 border border-red-500/30 rounded px-2 py-1">
                          {task.error}
                        </div>
                      )}
                    </div>
                  </div>

                  {/* Actions */}
                  <div className="flex items-center gap-2">
                    {getStatusIcon(task.status)}
                    
                    {task.status === 'running' && (
                      <button
                        onClick={() => handleCancelTask(task.id)}
                        className="p-1 hover:bg-gray-600 rounded transition"
                        title="Cancel"
                      >
                        <X className="w-4 h-4 text-gray-400" />
                      </button>
                    )}
                    
                    {task.status === 'failed' && (
                      <button
                        onClick={() => handleRetryTask(task.id)}
                        className="px-2 py-1 text-xs bg-blue-500/20 hover:bg-blue-500/30 text-blue-300 rounded transition"
                      >
                        Retry
                      </button>
                    )}
                    
                    {(task.status === 'completed' || task.status === 'failed' || task.status === 'cancelled') && (
                      <button
                        onClick={() => handleRemoveTask(task.id)}
                        className="p-1 hover:bg-gray-600 rounded transition"
                        title="Remove"
                      >
                        <X className="w-4 h-4 text-gray-400" />
                      </button>
                    )}
                  </div>
                </div>
              </div>
            ))}
          </div>

          {/* Footer */}
          <div className="bg-gray-700/50 p-3 flex items-center justify-between">
            <span className="text-xs text-gray-400">
              {tasks.length} total tasks
            </span>
            <button
              onClick={() => setTasks(tasks.filter(t => t.status !== 'completed' && t.status !== 'failed'))}
              className="text-xs text-gray-400 hover:text-gray-200 transition"
            >
              Clear completed
            </button>
          </div>
        </div>
      )}
    </div>
  );
};

export default TransferManager;
