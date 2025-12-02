import React, { useState, useEffect } from 'react';
import { API_CONFIG } from '../../config/api.config';
import {
  Activity,
  Server,
  Database,
  Wifi,
  HardDrive,
  AlertCircle,
  CheckCircle,
  XCircle,
  RefreshCw,
  Wrench
} from 'lucide-react';

interface ServiceStatus {
  status: 'healthy' | 'warning' | 'critical' | 'down';
  uptime?: string;
  uptime_percentage?: number;
  last_check: string;
  [key: string]: any;
}

interface HealthData {
  success: boolean;
  overall_status: 'healthy' | 'warning' | 'critical';
  timestamp: string;
  services: {
    backend: ServiceStatus;
    websocket: ServiceStatus;
    prometheus: ServiceStatus;
    node_exporter: ServiceStatus;
    slurm: ServiceStatus;
    database: ServiceStatus;
    storage: ServiceStatus;
  };
  mode: 'mock' | 'production';
}

const HealthCheck: React.FC = () => {
  const [healthData, setHealthData] = useState<HealthData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [autoRefresh, setAutoRefresh] = useState(true);
  const [healing, setHealing] = useState<string | null>(null);

  const fetchHealthStatus = async () => {
    try {
      const response = await fetch(`${API_CONFIG.API_BASE_URL}/api/health/status`);
      const data = await response.json();
      
      if (data.success) {
        setHealthData(data);
        setError(null);
      } else {
        setError(data.error || 'Failed to fetch health status');
      }
    } catch (err) {
      setError('Failed to connect to backend');
      console.error('Health check error:', err);
    } finally {
      setLoading(false);
    }
  };

  const handleAutoHeal = async (serviceName: string) => {
    if (!confirm(`Do you want to restart ${serviceName}?`)) {
      return;
    }

    setHealing(serviceName);
    try {
      const response = await fetch(`${API_CONFIG.API_BASE_URL}/api/health/auto-heal`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ service: serviceName })
      });

      const data = await response.json();
      
      if (data.success) {
        alert(`${serviceName} restarted successfully!`);
        // 재시작 후 5초 뒤에 상태 다시 확인
        setTimeout(fetchHealthStatus, 5000);
      } else {
        alert(`Failed to restart ${serviceName}: ${data.error}`);
      }
    } catch (err) {
      alert(`Failed to restart ${serviceName}`);
      console.error('Auto-heal error:', err);
    } finally {
      setHealing(null);
    }
  };

  useEffect(() => {
    fetchHealthStatus();

    if (autoRefresh) {
      const interval = setInterval(fetchHealthStatus, 30000); // 30초마다 갱신
      return () => clearInterval(interval);
    }
  }, [autoRefresh]);

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'healthy':
        return 'text-green-600 dark:text-green-400 bg-green-100 dark:bg-green-900/30';
      case 'warning':
        return 'text-yellow-600 dark:text-yellow-400 bg-yellow-100 dark:bg-yellow-900/30';
      case 'critical':
      case 'down':
        return 'text-red-600 dark:text-red-400 bg-red-100 dark:bg-red-900/30';
      default:
        return 'text-gray-600 dark:text-gray-400 bg-gray-100 dark:bg-gray-700';
    }
  };

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'healthy':
        return <CheckCircle className="text-green-600 dark:text-green-400" size={20} />;
      case 'warning':
        return <AlertCircle className="text-yellow-600 dark:text-yellow-400" size={20} />;
      case 'critical':
      case 'down':
        return <XCircle className="text-red-600 dark:text-red-400" size={20} />;
      default:
        return <AlertCircle className="text-gray-600 dark:text-gray-400" size={20} />;
    }
  };

  const getServiceIcon = (serviceName: string) => {
    const iconProps = { size: 24 };
    switch (serviceName) {
      case 'backend':
        return <Server {...iconProps} />;
      case 'websocket':
        return <Wifi {...iconProps} />;
      case 'prometheus':
      case 'node_exporter':
        return <Activity {...iconProps} />;
      case 'database':
        return <Database {...iconProps} />;
      case 'storage':
        return <HardDrive {...iconProps} />;
      case 'slurm':
        return <Server {...iconProps} />;
      default:
        return <Server {...iconProps} />;
    }
  };

  const getServiceDisplayName = (serviceName: string) => {
    const names: { [key: string]: string } = {
      backend: 'Backend API',
      websocket: 'WebSocket Server',
      prometheus: 'Prometheus',
      node_exporter: 'Node Exporter',
      slurm: 'Slurm Controller',
      database: 'Database',
      storage: 'Storage'
    };
    return names[serviceName] || serviceName;
  };

  const canAutoHeal = (serviceName: string) => {
    return ['websocket', 'prometheus', 'node_exporter'].includes(serviceName);
  };

  if (loading && !healthData) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-center">
          <RefreshCw className="animate-spin mx-auto mb-4 text-blue-600 dark:text-blue-400" size={48} />
          <p className="text-gray-600 dark:text-gray-400">Loading health status...</p>
        </div>
      </div>
    );
  }

  if (error && !healthData) {
    return (
      <div className="bg-red-50 dark:bg-red-900/30 border border-red-200 dark:border-red-700 rounded-lg p-6">
        <div className="flex items-center gap-3">
          <XCircle className="text-red-600 dark:text-red-400" size={24} />
          <div>
            <h3 className="font-semibold text-red-900 dark:text-red-200">
              Health Check Failed
            </h3>
            <p className="text-sm text-red-700 dark:text-red-300 mt-1">{error}</p>
          </div>
        </div>
        <button
          onClick={fetchHealthStatus}
          className="mt-4 px-4 py-2 bg-red-600 text-white rounded hover:bg-red-700 transition"
        >
          Retry
        </button>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* 헤더 */}
      <div className="bg-white dark:bg-gray-800 rounded-lg shadow p-6">
        <div className="flex items-center justify-between">
          <div>
            <h2 className="text-2xl font-bold text-gray-900 dark:text-white">
              System Health Check
            </h2>
            <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">
              Monitor all system services and components
            </p>
          </div>
          <div className="flex items-center gap-3">
            <label className="flex items-center gap-2 text-sm text-gray-600 dark:text-gray-400">
              <input
                type="checkbox"
                checked={autoRefresh}
                onChange={(e) => setAutoRefresh(e.target.checked)}
                className="rounded"
              />
              Auto-refresh (30s)
            </label>
            <button
              onClick={fetchHealthStatus}
              disabled={loading}
              className="flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 disabled:opacity-50 transition"
            >
              <RefreshCw size={18} className={loading ? 'animate-spin' : ''} />
              Refresh
            </button>
          </div>
        </div>

        {/* 전체 상태 배지 */}
        {healthData && (
          <div className="mt-4">
            <div className={`inline-flex items-center gap-2 px-4 py-2 rounded-full ${getStatusColor(healthData.overall_status)}`}>
              {getStatusIcon(healthData.overall_status)}
              <span className="font-semibold capitalize">
                Overall Status: {healthData.overall_status}
              </span>
            </div>
            {healthData.mode === 'mock' && (
              <span className="ml-3 text-sm text-amber-600 dark:text-amber-400">
                (Mock Mode)
              </span>
            )}
          </div>
        )}
      </div>

      {/* 서비스 상태 카드 그리드 */}
      {healthData && (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
          {Object.entries(healthData.services).map(([serviceName, serviceData]) => (
            <div
              key={serviceName}
              className="bg-white dark:bg-gray-800 rounded-lg shadow p-6 hover:shadow-lg transition-shadow"
            >
              <div className="flex items-start justify-between mb-4">
                <div className="flex items-center gap-3">
                  <div className={`p-2 rounded-lg ${getStatusColor(serviceData.status)}`}>
                    {getServiceIcon(serviceName)}
                  </div>
                  <div>
                    <h3 className="font-semibold text-gray-900 dark:text-white">
                      {getServiceDisplayName(serviceName)}
                    </h3>
                    <div className="flex items-center gap-2 mt-1">
                      {getStatusIcon(serviceData.status)}
                      <span className={`text-sm font-medium capitalize ${getStatusColor(serviceData.status)}`}>
                        {serviceData.status}
                      </span>
                    </div>
                  </div>
                </div>
              </div>

              {/* 상세 정보 */}
              <div className="space-y-2 text-sm">
                {serviceData.uptime && (
                  <div className="flex justify-between text-gray-600 dark:text-gray-400">
                    <span>Uptime:</span>
                    <span className="font-mono">{serviceData.uptime}</span>
                  </div>
                )}
                
                {serviceData.uptime_percentage !== undefined && (
                  <div className="flex justify-between text-gray-600 dark:text-gray-400">
                    <span>Availability:</span>
                    <span className="font-semibold">{serviceData.uptime_percentage}%</span>
                  </div>
                )}

                {serviceName === 'backend' && (
                  <>
                    <div className="flex justify-between text-gray-600 dark:text-gray-400">
                      <span>Memory:</span>
                      <span>{serviceData.memory_mb} MB</span>
                    </div>
                    <div className="flex justify-between text-gray-600 dark:text-gray-400">
                      <span>CPU:</span>
                      <span>{serviceData.cpu_percent}%</span>
                    </div>
                  </>
                )}

                {serviceName === 'websocket' && serviceData.clients !== undefined && (
                  <div className="flex justify-between text-gray-600 dark:text-gray-400">
                    <span>Clients:</span>
                    <span>{serviceData.clients}</span>
                  </div>
                )}

                {serviceName === 'prometheus' && (
                  <>
                    <div className="flex justify-between text-gray-600 dark:text-gray-400">
                      <span>Targets:</span>
                      <span>{serviceData.up_targets}/{serviceData.total_targets}</span>
                    </div>
                    {serviceData.down_targets > 0 && (
                      <div className="text-red-600 dark:text-red-400 text-xs mt-2">
                        ⚠️ {serviceData.down_targets} target(s) down
                      </div>
                    )}
                  </>
                )}

                {serviceName === 'database' && (
                  <>
                    <div className="flex justify-between text-gray-600 dark:text-gray-400">
                      <span>Tables:</span>
                      <span>{serviceData.table_count}</span>
                    </div>
                    <div className="flex justify-between text-gray-600 dark:text-gray-400">
                      <span>Size:</span>
                      <span>{serviceData.size_mb} MB</span>
                    </div>
                  </>
                )}

                {serviceName === 'storage' && (
                  <>
                    <div className="flex justify-between text-gray-600 dark:text-gray-400">
                      <span>Usage:</span>
                      <span>{serviceData.usage_percent}%</span>
                    </div>
                    <div className="w-full bg-gray-200 dark:bg-gray-700 rounded-full h-2 mt-1">
                      <div
                        className={`h-2 rounded-full ${
                          serviceData.usage_percent >= 95
                            ? 'bg-red-500'
                            : serviceData.usage_percent >= 85
                            ? 'bg-yellow-500'
                            : 'bg-green-500'
                        }`}
                        style={{ width: `${serviceData.usage_percent}%` }}
                      />
                    </div>
                    <div className="flex justify-between text-gray-600 dark:text-gray-400 mt-1">
                      <span>Free:</span>
                      <span>{serviceData.free_gb} GB</span>
                    </div>
                  </>
                )}

                {serviceData.error && (
                  <div className="text-red-600 dark:text-red-400 text-xs mt-2">
                    ⚠️ {serviceData.error}
                  </div>
                )}
              </div>

              {/* Auto-heal 버튼 */}
              {canAutoHeal(serviceName) && serviceData.status !== 'healthy' && (
                <button
                  onClick={() => handleAutoHeal(serviceName)}
                  disabled={healing === serviceName}
                  className="w-full mt-4 flex items-center justify-center gap-2 px-3 py-2 bg-amber-600 text-white rounded hover:bg-amber-700 disabled:opacity-50 transition text-sm"
                >
                  <Wrench size={16} />
                  {healing === serviceName ? 'Restarting...' : 'Auto-heal'}
                </button>
              )}
            </div>
          ))}
        </div>
      )}

      {/* 마지막 업데이트 시간 */}
      {healthData && (
        <div className="text-center text-sm text-gray-500 dark:text-gray-400">
          Last updated: {new Date(healthData.timestamp).toLocaleString()}
        </div>
      )}
    </div>
  );
};

export default HealthCheck;
