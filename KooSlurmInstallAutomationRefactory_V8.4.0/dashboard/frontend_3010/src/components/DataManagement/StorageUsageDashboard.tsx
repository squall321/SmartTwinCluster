import React, { useState, useEffect } from 'react';
import { LineChart, Line, BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ResponsiveContainer } from 'recharts';
import { TrendingUp, HardDrive, Database, Activity } from 'lucide-react';

interface UsageData {
  timestamp: string;
  data_usage: number;
  scratch_usage: number;
}

const StorageUsageDashboard: React.FC = () => {
  const [timeRange, setTimeRange] = useState<'1h' | '24h' | '7d' | '30d'>('24h');
  const [usageData, setUsageData] = useState<UsageData[]>([]);
  const [currentStats, setCurrentStats] = useState<any>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    loadUsageData();
    // 5분마다 갱신
    const interval = setInterval(loadUsageData, 5 * 60 * 1000);
    return () => clearInterval(interval);
  }, [timeRange]);

  const loadUsageData = async () => {
    setLoading(true);
    
    try {
      // Mock 데이터 (실제로는 API 호출)
      const mockData: UsageData[] = [];
      const now = Date.now();
      const points = timeRange === '1h' ? 12 : timeRange === '24h' ? 24 : timeRange === '7d' ? 7 : 30;
      const interval = timeRange === '1h' ? 5 * 60 * 1000 : timeRange === '24h' ? 60 * 60 * 1000 : 24 * 60 * 60 * 1000;
      
      for (let i = points; i >= 0; i--) {
        const timestamp = new Date(now - i * interval);
        mockData.push({
          timestamp: timestamp.toISOString(),
          data_usage: 65 + Math.random() * 10,
          scratch_usage: 45 + Math.random() * 15
        });
      }
      
      setUsageData(mockData);
      setCurrentStats({
        data: { usage: 68.5, total: '10 TB', used: '6.85 TB', trend: '+2.3%' },
        scratch: { usage: 52.3, total: '5 TB', used: '2.62 TB', trend: '+5.1%' }
      });
    } catch (error) {
      console.error('Failed to load usage data:', error);
    } finally {
      setLoading(false);
    }
  };

  const formatTimestamp = (timestamp: string) => {
    const date = new Date(timestamp);
    if (timeRange === '1h') {
      return date.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' });
    } else if (timeRange === '24h') {
      return date.toLocaleTimeString('en-US', { hour: '2-digit' });
    } else {
      return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
    }
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className="p-2 bg-blue-500/20 rounded-lg">
            <Activity className="w-6 h-6 text-blue-400" />
          </div>
          <div>
            <h2 className="text-xl font-bold text-gray-50">Storage Usage Dashboard</h2>
            <p className="text-sm text-gray-400">Real-time monitoring and trends</p>
          </div>
        </div>

        {/* Time Range Selector */}
        <div className="flex gap-2">
          {(['1h', '24h', '7d', '30d'] as const).map(range => (
            <button
              key={range}
              onClick={() => setTimeRange(range)}
              className={`px-3 py-1.5 text-sm rounded transition ${
                timeRange === range
                  ? 'bg-blue-500 text-white'
                  : 'bg-gray-700 text-gray-300 hover:bg-gray-600'
              }`}
            >
              {range}
            </button>
          ))}
        </div>
      </div>

      {/* Current Stats Cards */}
      {currentStats && (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {/* Data Storage Card */}
          <div className="bg-gradient-to-br from-purple-900/30 to-purple-800/20 border border-purple-500/30 rounded-lg p-6">
            <div className="flex items-center justify-between mb-4">
              <div className="flex items-center gap-3">
                <Database className="w-8 h-8 text-purple-400" />
                <div>
                  <h3 className="text-sm font-medium text-gray-300">Shared Storage (/data)</h3>
                  <p className="text-2xl font-bold text-gray-50">{currentStats.data.usage}%</p>
                </div>
              </div>
              <div className="text-right">
                <div className="text-xs text-gray-400">Trend</div>
                <div className="text-sm font-bold text-green-400">{currentStats.data.trend}</div>
              </div>
            </div>
            
            <div className="w-full bg-gray-700 rounded-full h-3 mb-3">
              <div 
                className="bg-gradient-to-r from-purple-500 to-pink-500 h-3 rounded-full transition-all"
                style={{ width: `${currentStats.data.usage}%` }}
              />
            </div>
            
            <div className="flex justify-between text-sm text-gray-400">
              <span>{currentStats.data.used} used</span>
              <span>{currentStats.data.total} total</span>
            </div>
          </div>

          {/* Scratch Storage Card */}
          <div className="bg-gradient-to-br from-blue-900/30 to-blue-800/20 border border-blue-500/30 rounded-lg p-6">
            <div className="flex items-center justify-between mb-4">
              <div className="flex items-center gap-3">
                <HardDrive className="w-8 h-8 text-blue-400" />
                <div>
                  <h3 className="text-sm font-medium text-gray-300">Scratch Storage (avg)</h3>
                  <p className="text-2xl font-bold text-gray-50">{currentStats.scratch.usage}%</p>
                </div>
              </div>
              <div className="text-right">
                <div className="text-xs text-gray-400">Trend</div>
                <div className="text-sm font-bold text-yellow-400">{currentStats.scratch.trend}</div>
              </div>
            </div>
            
            <div className="w-full bg-gray-700 rounded-full h-3 mb-3">
              <div 
                className="bg-gradient-to-r from-blue-500 to-cyan-500 h-3 rounded-full transition-all"
                style={{ width: `${currentStats.scratch.usage}%` }}
              />
            </div>
            
            <div className="flex justify-between text-sm text-gray-400">
              <span>{currentStats.scratch.used} used</span>
              <span>{currentStats.scratch.total} total</span>
            </div>
          </div>
        </div>
      )}

      {/* Usage Trend Chart */}
      <div className="bg-gray-800 border border-gray-700 rounded-lg p-6">
        <h3 className="text-lg font-bold text-gray-50 mb-4 flex items-center gap-2">
          <TrendingUp className="w-5 h-5 text-blue-400" />
          Usage Trend
        </h3>
        
        {loading ? (
          <div className="h-80 flex items-center justify-center">
            <div className="text-gray-400">Loading chart...</div>
          </div>
        ) : (
          <ResponsiveContainer width="100%" height={300}>
            <LineChart data={usageData}>
              <CartesianGrid strokeDasharray="3 3" stroke="#374151" />
              <XAxis 
                dataKey="timestamp" 
                tickFormatter={formatTimestamp}
                stroke="#9CA3AF"
                style={{ fontSize: '12px' }}
              />
              <YAxis 
                domain={[0, 100]}
                stroke="#9CA3AF"
                style={{ fontSize: '12px' }}
                label={{ value: 'Usage (%)', angle: -90, position: 'insideLeft', fill: '#9CA3AF' }}
              />
              <Tooltip 
                contentStyle={{ backgroundColor: '#1F2937', border: '1px solid #374151', borderRadius: '8px' }}
                labelStyle={{ color: '#F3F4F6' }}
                formatter={(value: number) => `${value.toFixed(1)}%`}
                labelFormatter={(label) => new Date(label).toLocaleString()}
              />
              <Legend />
              <Line 
                type="monotone" 
                dataKey="data_usage" 
                stroke="#A855F7" 
                strokeWidth={2}
                name="Shared Storage"
                dot={false}
              />
              <Line 
                type="monotone" 
                dataKey="scratch_usage" 
                stroke="#3B82F6" 
                strokeWidth={2}
                name="Scratch Storage"
                dot={false}
              />
            </LineChart>
          </ResponsiveContainer>
        )}
      </div>

      {/* Storage Comparison Bar Chart */}
      <div className="bg-gray-800 border border-gray-700 rounded-lg p-6">
        <h3 className="text-lg font-bold text-gray-50 mb-4">Storage Comparison</h3>
        
        <ResponsiveContainer width="100%" height={200}>
          <BarChart data={[
            { name: 'Shared (/data)', usage: currentStats?.data.usage || 0 },
            { name: 'Scratch (avg)', usage: currentStats?.scratch.usage || 0 }
          ]}>
            <CartesianGrid strokeDasharray="3 3" stroke="#374151" />
            <XAxis dataKey="name" stroke="#9CA3AF" />
            <YAxis domain={[0, 100]} stroke="#9CA3AF" />
            <Tooltip 
              contentStyle={{ backgroundColor: '#1F2937', border: '1px solid #374151', borderRadius: '8px' }}
              formatter={(value: number) => `${value.toFixed(1)}%`}
            />
            <Bar dataKey="usage" fill="#8B5CF6" />
          </BarChart>
        </ResponsiveContainer>
      </div>

      {/* Stats Summary */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div className="bg-gray-800 border border-gray-700 rounded-lg p-4">
          <div className="text-sm text-gray-400 mb-1">Total Capacity</div>
          <div className="text-xl font-bold text-gray-50">15 TB</div>
          <div className="text-xs text-gray-500 mt-1">Combined storage</div>
        </div>
        
        <div className="bg-gray-800 border border-gray-700 rounded-lg p-4">
          <div className="text-sm text-gray-400 mb-1">Total Used</div>
          <div className="text-xl font-bold text-gray-50">9.47 TB</div>
          <div className="text-xs text-gray-500 mt-1">63.1% utilized</div>
        </div>
        
        <div className="bg-gray-800 border border-gray-700 rounded-lg p-4">
          <div className="text-sm text-gray-400 mb-1">Available</div>
          <div className="text-xl font-bold text-gray-50">5.53 TB</div>
          <div className="text-xs text-gray-500 mt-1">Remaining capacity</div>
        </div>
      </div>
    </div>
  );
};

export default StorageUsageDashboard;
