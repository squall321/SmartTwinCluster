import React, { useState, useEffect } from 'react';
import { Server, GripVertical, X, CheckCircle, AlertCircle, XCircle } from 'lucide-react';
import { WidgetProps } from '../widgetRegistry';
import { apiGet } from '../../../utils/api';

interface NodeStats {
  total: number;
  allocated: number;
  idle: number;
  down: number;
}

const NodeStatusWidget: React.FC<WidgetProps> = ({ id, onRemove, isEditMode, mode }) => {
  const [stats, setStats] = useState<NodeStats>({
    total: 0,
    allocated: 0,
    idle: 0,
    down: 0
  });
  const [loading, setLoading] = useState(true);
  const [usingMockData, setUsingMockData] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetchNodeStats();
    const interval = setInterval(fetchNodeStats, 10000);
    return () => clearInterval(interval);
  }, [mode]);

  const fetchNodeStats = async () => {
    setError(null);
    
    // Production mode: try real API
    if (mode === 'production') {
      try {
        const response = await apiGet('/api/nodes');
        if (response?.nodes && Array.isArray(response.nodes)) {
          const nodes = response.nodes;
          
          // Aggregate by node state
          const allocated = nodes.filter((n: any) => 
            n.state?.toLowerCase().includes('alloc') || 
            n.state?.toLowerCase().includes('mix')
          ).length;
          
          const idle = nodes.filter((n: any) => 
            n.state?.toLowerCase().includes('idle')
          ).length;
          
          const down = nodes.filter((n: any) => 
            n.state?.toLowerCase().includes('down') ||
            n.state?.toLowerCase().includes('drain') ||
            n.state?.toLowerCase().includes('fail')
          ).length;
          
          setStats({
            total: nodes.length,
            allocated,
            idle,
            down
          });
          setUsingMockData(false);
          setLoading(false);
          console.log('[NodeStatusWidget] Successfully loaded node stats:', nodes.length, 'nodes');
          return;
        } else {
          throw new Error('Node information not found');
        }
      } catch (error) {
        console.error('[NodeStatusWidget] Production API error:', error);
        const errorMessage = error instanceof Error ? error.message : 'Failed to fetch node data';
        setError(errorMessage);
        setStats({ total: 0, allocated: 0, idle: 0, down: 0 });
        setUsingMockData(false);
        setLoading(false);
        return;
      }
    }
    
    // Mock mode: use mock data
    setStats({
      total: 20,
      allocated: 12,
      idle: 6,
      down: 2
    });
    setUsingMockData(true);
    setLoading(false);
    console.log('[NodeStatusWidget] Using mock node data');
  };

  const getHealthPercentage = () => {
    if (stats.total === 0) return 0;
    return ((stats.total - stats.down) / stats.total) * 100;
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
          <Server className="w-5 h-5 text-cyan-500" />
          <h3 className="font-semibold text-gray-900 dark:text-white">Node Status</h3>
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
            <div className="w-8 h-8 border-4 border-cyan-600 border-t-transparent rounded-full animate-spin mx-auto mb-2"></div>
            <p className="text-sm text-gray-500 dark:text-gray-400">Loading...</p>
          </div>
        ) : error ? (
          <div className="text-center text-red-500 dark:text-red-400 py-8">
            <Server className="w-12 h-12 mx-auto mb-3 opacity-50" />
            <p className="font-medium">{error}</p>
            <p className="text-sm text-gray-500 dark:text-gray-400 mt-2">
              Check Slurm Nodes API
            </p>
          </div>
        ) : stats.total === 0 ? (
          <div className="text-center text-gray-500 dark:text-gray-400 py-8">
            <Server className="w-12 h-12 mx-auto mb-3 opacity-50" />
            <p className="font-medium">No nodes found</p>
            <p className="text-sm text-gray-500 dark:text-gray-400 mt-2">
              {mode === 'production' ? 'Check cluster configuration' : 'Try mock mode'}
            </p>
          </div>
        ) : (
          <div>
            {/* Health Status */}
            <div className="text-center mb-6">
              <div className="text-5xl font-bold text-gray-900 dark:text-white mb-2">
                {stats.total}
              </div>
              <div className="text-sm text-gray-500 dark:text-gray-400 mb-4">Total Nodes</div>
              
              <div className="w-full bg-gray-200 dark:bg-gray-700 rounded-full h-3 overflow-hidden">
                <div
                  className={`h-full transition-all duration-500 ${
                    getHealthPercentage() > 90 ? 'bg-green-500' :
                    getHealthPercentage() > 70 ? 'bg-yellow-500' : 'bg-red-500'
                  }`}
                  style={{ width: `${getHealthPercentage()}%` }}
                />
              </div>
              <div className="text-xs text-gray-500 dark:text-gray-400 mt-1">
                Cluster Health: {getHealthPercentage().toFixed(0)}%
              </div>
            </div>

            {/* Stats Grid */}
            <div className="grid grid-cols-3 gap-3">
              <div className="bg-blue-50 dark:bg-blue-900/20 rounded-lg p-3 text-center">
                <CheckCircle className="w-6 h-6 text-blue-500 mx-auto mb-1" />
                <div className="text-2xl font-bold text-blue-600 dark:text-blue-400">
                  {stats.allocated}
                </div>
                <div className="text-xs text-gray-600 dark:text-gray-400">Allocated</div>
              </div>

              <div className="bg-green-50 dark:bg-green-900/20 rounded-lg p-3 text-center">
                <AlertCircle className="w-6 h-6 text-green-500 mx-auto mb-1" />
                <div className="text-2xl font-bold text-green-600 dark:text-green-400">
                  {stats.idle}
                </div>
                <div className="text-xs text-gray-600 dark:text-gray-400">Idle</div>
              </div>

              <div className="bg-red-50 dark:bg-red-900/20 rounded-lg p-3 text-center">
                <XCircle className="w-6 h-6 text-red-500 mx-auto mb-1" />
                <div className="text-2xl font-bold text-red-600 dark:text-red-400">
                  {stats.down}
                </div>
                <div className="text-xs text-gray-600 dark:text-gray-400">Down</div>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

export default NodeStatusWidget;
