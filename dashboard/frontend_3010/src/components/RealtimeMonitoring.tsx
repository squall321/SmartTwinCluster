import React, { useState, useEffect } from 'react';
import { 
  LineChart, Line, AreaChart, Area, XAxis, YAxis, CartesianGrid, 
  Tooltip, Legend, ResponsiveContainer, PieChart, Pie, Cell 
} from 'recharts';
import { Activity, Cpu, HardDrive, Zap, TrendingUp, Server } from 'lucide-react';
import { RealtimeMetrics, TimeSeriesData } from '../types';
import { apiGet, API_ENDPOINTS } from '../utils/api';
import toast from 'react-hot-toast';

interface RealtimeMonitoringProps {
  apiMode: 'mock' | 'production';
}

export const RealtimeMonitoring: React.FC<RealtimeMonitoringProps> = ({ apiMode }) => {
  const [metrics, setMetrics] = useState<RealtimeMetrics | null>(null);
  const [cpuHistory, setCpuHistory] = useState<TimeSeriesData[]>([]);
  const [memoryHistory, setMemoryHistory] = useState<TimeSeriesData[]>([]);
  const [jobHistory, setJobHistory] = useState<TimeSeriesData[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  // 실시간 데이터 업데이트
  useEffect(() => {
    const fetchMetrics = async () => {
      try {
        const response = await apiGet<{
          success: boolean;
          mode: string;
          data: RealtimeMetrics;
          error?: string;
        }>(API_ENDPOINTS.metrics);

        if (response.success && response.data) {
          const newMetrics = response.data;
          setMetrics(newMetrics);
          setError(null);
          setIsLoading(false);
          
          // 히스토리 업데이트 (최근 20개만 유지)
          const timestamp = new Date().toLocaleTimeString();
          
          setCpuHistory(prev => [...prev.slice(-19), {
            timestamp,
            value: newMetrics.cpuUsage,
          }]);
          
          setMemoryHistory(prev => [...prev.slice(-19), {
            timestamp,
            value: newMetrics.memoryUsage,
          }]);
          
          setJobHistory(prev => [...prev.slice(-19), {
            timestamp,
            value: newMetrics.activeJobs,
          }]);
        } else {
          throw new Error(response.error || 'Failed to fetch metrics');
        }
      } catch (err) {
        const errorMessage = err instanceof Error ? err.message : 'Failed to fetch metrics';
        console.error('Metrics fetch error:', errorMessage);
        setError(errorMessage);
        setIsLoading(false);
        
        // Production 모드에서만 에러 토스트 표시 (한 번만)
        if (apiMode === 'production' && !error) {
          toast.error(`Metrics Error: ${errorMessage}`, { duration: 3000 });
        }
      }
    };

    // 초기 로드
    fetchMetrics();
    
    // 3초마다 업데이트
    const interval = setInterval(fetchMetrics, 3000);

    return () => clearInterval(interval);
  }, [apiMode]);

  if (isLoading) {
    return (
      <div className="p-6 text-center">
        <div className="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
        <p className="mt-2 text-gray-600">Loading metrics...</p>
      </div>
    );
  }

  if (error) {
    return (
      <div className="p-6">
        <div className="bg-red-50 border border-red-200 rounded-lg p-4">
          <div className="flex items-center gap-2 text-red-800 mb-2">
            <Server className="w-5 h-5" />
            <h3 className="font-semibold">Metrics Unavailable</h3>
          </div>
          <p className="text-red-600 text-sm">{error}</p>
          <p className="text-red-500 text-xs mt-2">
            {apiMode === 'production' 
              ? 'Make sure Slurm is running and accessible (sinfo, squeue commands)'
              : 'Check if backend is running on port 5010'
            }
          </p>
        </div>
      </div>
    );
  }

  if (!metrics) {
    return <div className="p-6 text-center text-gray-500">No metrics data available</div>;
  }

  const nodeStateData = [
    { name: 'Idle', value: metrics.idleNodes, color: '#10b981' },
    { name: 'Allocated', value: metrics.allocatedNodes, color: '#3b82f6' },
    { name: 'Down', value: metrics.downNodes, color: '#ef4444' },
  ];

  return (
    <div className="space-y-6">
      {/* 상단 메트릭 카드 */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <MetricCard
          title="CPU Usage"
          value={`${metrics.cpuUsage.toFixed(1)}%`}
          icon={<Cpu className="w-6 h-6" />}
          color="blue"
          trend={metrics.cpuUsage > 70 ? 'up' : 'normal'}
        />
        <MetricCard
          title="Memory Usage"
          value={`${metrics.memoryUsage.toFixed(1)}%`}
          icon={<HardDrive className="w-6 h-6" />}
          color="green"
          trend={metrics.memoryUsage > 80 ? 'up' : 'normal'}
        />
        <MetricCard
          title="Active Jobs"
          value={metrics.activeJobs.toString()}
          icon={<Activity className="w-6 h-6" />}
          color="purple"
          subtitle={`${metrics.pendingJobs} pending`}
        />
        <MetricCard
          title="GPU Usage"
          value={`${(metrics.gpuUsage || 0).toFixed(1)}%`}
          icon={<Zap className="w-6 h-6" />}
          color="amber"
        />
      </div>

      {/* 차트 그리드 */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* CPU 사용률 추이 */}
        <div className="bg-white rounded-lg shadow p-6">
          <h3 className="text-lg font-semibold mb-4 flex items-center gap-2">
            <TrendingUp className="w-5 h-5 text-blue-600" />
            CPU Usage Trend
          </h3>
          <ResponsiveContainer width="100%" height={250}>
            <AreaChart data={cpuHistory}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis 
                dataKey="timestamp" 
                tick={{ fontSize: 12 }}
                interval="preserveStartEnd"
              />
              <YAxis domain={[0, 100]} />
              <Tooltip />
              <Area 
                type="monotone" 
                dataKey="value" 
                stroke="#3b82f6" 
                fill="#3b82f6" 
                fillOpacity={0.3}
                name="CPU %"
              />
            </AreaChart>
          </ResponsiveContainer>
        </div>

        {/* 메모리 사용률 추이 */}
        <div className="bg-white rounded-lg shadow p-6">
          <h3 className="text-lg font-semibold mb-4 flex items-center gap-2">
            <HardDrive className="w-5 h-5 text-green-600" />
            Memory Usage Trend
          </h3>
          <ResponsiveContainer width="100%" height={250}>
            <AreaChart data={memoryHistory}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis 
                dataKey="timestamp" 
                tick={{ fontSize: 12 }}
                interval="preserveStartEnd"
              />
              <YAxis domain={[0, 100]} />
              <Tooltip />
              <Area 
                type="monotone" 
                dataKey="value" 
                stroke="#10b981" 
                fill="#10b981" 
                fillOpacity={0.3}
                name="Memory %"
              />
            </AreaChart>
          </ResponsiveContainer>
        </div>

        {/* 작업 수 추이 */}
        <div className="bg-white rounded-lg shadow p-6">
          <h3 className="text-lg font-semibold mb-4 flex items-center gap-2">
            <Activity className="w-5 h-5 text-purple-600" />
            Active Jobs Trend
          </h3>
          <ResponsiveContainer width="100%" height={250}>
            <LineChart data={jobHistory}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis 
                dataKey="timestamp" 
                tick={{ fontSize: 12 }}
                interval="preserveStartEnd"
              />
              <YAxis />
              <Tooltip />
              <Legend />
              <Line 
                type="monotone" 
                dataKey="value" 
                stroke="#8b5cf6" 
                strokeWidth={2}
                name="Jobs"
                dot={{ r: 3 }}
              />
            </LineChart>
          </ResponsiveContainer>
        </div>

        {/* 노드 상태 분포 */}
        <div className="bg-white rounded-lg shadow p-6">
          <h3 className="text-lg font-semibold mb-4 flex items-center gap-2">
            <Server className="w-5 h-5 text-gray-600" />
            Node State Distribution
          </h3>
          <ResponsiveContainer width="100%" height={250}>
            <PieChart>
              <Pie
                data={nodeStateData}
                cx="50%"
                cy="50%"
                labelLine={false}
                label={({ name, value }) => `${name}: ${value}`}
                outerRadius={80}
                fill="#8884d8"
                dataKey="value"
              >
                {nodeStateData.map((entry, index) => (
                  <Cell key={`cell-${index}`} fill={entry.color} />
                ))}
              </Pie>
              <Tooltip />
            </PieChart>
          </ResponsiveContainer>
          <div className="mt-4 grid grid-cols-3 gap-2 text-sm">
            {nodeStateData.map((state) => (
              <div key={state.name} className="text-center">
                <div 
                  className="w-4 h-4 rounded mx-auto mb-1" 
                  style={{ backgroundColor: state.color }}
                />
                <div className="font-medium">{state.value}</div>
                <div className="text-gray-500 text-xs">{state.name}</div>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* 노드 상태 상세 */}
      <div className="bg-white rounded-lg shadow p-6">
        <h3 className="text-lg font-semibold mb-4">Node Statistics</h3>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <StatItem label="Total Nodes" value={metrics.totalNodes} />
          <StatItem label="Idle Nodes" value={metrics.idleNodes} color="green" />
          <StatItem label="Allocated Nodes" value={metrics.allocatedNodes} color="blue" />
          <StatItem label="Down Nodes" value={metrics.downNodes} color="red" />
        </div>
      </div>
    </div>
  );
};

// 메트릭 카드 컴포넌트
interface MetricCardProps {
  title: string;
  value: string;
  icon: React.ReactNode;
  color: 'blue' | 'green' | 'purple' | 'amber';
  subtitle?: string;
  trend?: 'up' | 'down' | 'normal';
}

const MetricCard: React.FC<MetricCardProps> = ({ 
  title, value, icon, color, subtitle, trend = 'normal' 
}) => {
  const colorClasses = {
    blue: 'bg-blue-100 text-blue-600',
    green: 'bg-green-100 text-green-600',
    purple: 'bg-purple-100 text-purple-600',
    amber: 'bg-amber-100 text-amber-600',
  };

  const trendColors = {
    up: 'text-red-600',
    down: 'text-green-600',
    normal: 'text-gray-600',
  };

  return (
    <div className="bg-white rounded-lg shadow p-6">
      <div className="flex items-center justify-between mb-2">
        <div className={`p-3 rounded-lg ${colorClasses[color]}`}>
          {icon}
        </div>
        {trend !== 'normal' && (
          <TrendingUp 
            className={`w-5 h-5 ${trendColors[trend]} ${trend === 'down' ? 'rotate-180' : ''}`} 
          />
        )}
      </div>
      <div className="text-sm text-gray-500 mb-1">{title}</div>
      <div className="text-2xl font-bold text-gray-900">{value}</div>
      {subtitle && <div className="text-xs text-gray-500 mt-1">{subtitle}</div>}
    </div>
  );
};

// 통계 아이템 컴포넌트
interface StatItemProps {
  label: string;
  value: number;
  color?: 'green' | 'blue' | 'red';
}

const StatItem: React.FC<StatItemProps> = ({ label, value, color }) => {
  const colorClasses = {
    green: 'text-green-600',
    blue: 'text-blue-600',
    red: 'text-red-600',
  };

  return (
    <div className="text-center p-3 bg-gray-50 rounded">
      <div className={`text-2xl font-bold ${color ? colorClasses[color] : 'text-gray-900'}`}>
        {value}
      </div>
      <div className="text-sm text-gray-600 mt-1">{label}</div>
    </div>
  );
};
