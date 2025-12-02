import React, { useState } from 'react';
import { Search, Server, Cpu, HardDrive, Network, Zap, BarChart3, TrendingUp } from 'lucide-react';

/**
 * QueryTemplates 컴포넌트
 * 사전 정의된 PromQL 쿼리 템플릿
 */

interface QueryTemplate {
  id: string;
  name: string;
  description: string;
  query: string;
  category: 'node' | 'slurm' | 'gpu' | 'network' | 'comparison' | 'advanced';
  isAdvanced?: boolean;
}

interface QueryTemplatesProps {
  onSelectQuery: (query: string) => void;
  mode?: 'mock' | 'production';
}

const QUERY_TEMPLATES: QueryTemplate[] = [
  // Node Metrics - Basic
  {
    id: 'node-cpu-usage',
    name: 'CPU Usage',
    description: 'Current CPU usage per node',
    query: '100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)',
    category: 'node'
  },
  {
    id: 'node-cpu-cores',
    name: 'CPU Usage by Core',
    description: 'CPU usage for each core across all nodes',
    query: '100 - (avg by (instance, cpu) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)',
    category: 'node',
    isAdvanced: true
  },
  {
    id: 'node-cpu-modes',
    name: 'CPU Time by Mode',
    description: 'CPU time spent in different modes (user, system, idle)',
    query: 'rate(node_cpu_seconds_total[5m])',
    category: 'node',
    isAdvanced: true
  },
  {
    id: 'node-memory-usage',
    name: 'Memory Usage',
    description: 'Memory usage percentage',
    query: '(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100',
    category: 'node'
  },
  {
    id: 'node-memory-breakdown',
    name: 'Memory Usage Breakdown',
    description: 'Memory breakdown (used, cached, buffers, free)',
    query: 'node_memory_MemTotal_bytes - node_memory_MemFree_bytes - node_memory_Cached_bytes - node_memory_Buffers_bytes',
    category: 'node',
    isAdvanced: true
  },
  {
    id: 'node-disk-usage',
    name: 'Disk Usage',
    description: 'Disk space usage percentage',
    query: '(1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})) * 100',
    category: 'node'
  },
  {
    id: 'node-disk-all',
    name: 'All Filesystem Usage',
    description: 'Disk usage for all mounted filesystems',
    query: '(1 - (node_filesystem_avail_bytes / node_filesystem_size_bytes)) * 100',
    category: 'node',
    isAdvanced: true
  },
  {
    id: 'node-disk-io',
    name: 'Disk I/O Rate',
    description: 'Disk read/write operations per second',
    query: 'rate(node_disk_io_time_seconds_total[5m])',
    category: 'node',
    isAdvanced: true
  },
  {
    id: 'node-load',
    name: 'Load Average',
    description: '1-minute load average',
    query: 'node_load1',
    category: 'node'
  },
  {
    id: 'node-load-all',
    name: 'Load Average (1m, 5m, 15m)',
    description: 'Load average for 1, 5, and 15 minutes',
    query: 'node_load1 or node_load5 or node_load15',
    category: 'node',
    isAdvanced: true
  },
  
  // Network Metrics
  {
    id: 'node-network-rx',
    name: 'Network Receive',
    description: 'Network bytes received per second',
    query: 'rate(node_network_receive_bytes_total[5m])',
    category: 'network'
  },
  {
    id: 'node-network-tx',
    name: 'Network Transmit',
    description: 'Network bytes transmitted per second',
    query: 'rate(node_network_transmit_bytes_total[5m])',
    category: 'network'
  },
  {
    id: 'node-network-all',
    name: 'Network Traffic (All Interfaces)',
    description: 'Network receive + transmit for all interfaces',
    query: 'rate(node_network_receive_bytes_total[5m]) + rate(node_network_transmit_bytes_total[5m])',
    category: 'network',
    isAdvanced: true
  },
  {
    id: 'network-errors',
    name: 'Network Errors',
    description: 'Network errors per second',
    query: 'rate(node_network_receive_errs_total[5m]) + rate(node_network_transmit_errs_total[5m])',
    category: 'network'
  },
  
  // Slurm Metrics
  {
    id: 'slurm-queue-jobs',
    name: 'Queue Length',
    description: 'Number of jobs in queue',
    query: 'slurm_queue_jobs',
    category: 'slurm'
  },
  {
    id: 'slurm-running-jobs',
    name: 'Running Jobs',
    description: 'Number of running jobs',
    query: 'slurm_running_jobs',
    category: 'slurm'
  },
  {
    id: 'slurm-pending-jobs',
    name: 'Pending Jobs',
    description: 'Number of pending jobs',
    query: 'slurm_pending_jobs',
    category: 'slurm'
  },
  {
    id: 'slurm-all-jobs',
    name: 'All Job States',
    description: 'Running, pending, and completed jobs',
    query: 'slurm_running_jobs or slurm_pending_jobs or slurm_queue_jobs',
    category: 'slurm',
    isAdvanced: true
  },
  {
    id: 'slurm-allocated-cores',
    name: 'Allocated Cores',
    description: 'Total allocated CPU cores',
    query: 'slurm_allocated_cores',
    category: 'slurm'
  },
  
  // GPU Metrics
  {
    id: 'gpu-utilization',
    name: 'GPU Utilization',
    description: 'GPU utilization percentage',
    query: 'nvidia_gpu_utilization_gpu',
    category: 'gpu'
  },
  {
    id: 'gpu-all-metrics',
    name: 'All GPU Metrics',
    description: 'GPU utilization, memory, temperature, power',
    query: 'nvidia_gpu_utilization_gpu or nvidia_gpu_memory_used_bytes or nvidia_gpu_temperature_celsius or nvidia_gpu_power_usage_watts',
    category: 'gpu',
    isAdvanced: true
  },
  {
    id: 'gpu-memory-usage',
    name: 'GPU Memory Usage',
    description: 'GPU memory usage percentage',
    query: '(nvidia_gpu_memory_used_bytes / nvidia_gpu_memory_total_bytes) * 100',
    category: 'gpu'
  },
  {
    id: 'gpu-temperature',
    name: 'GPU Temperature',
    description: 'GPU temperature in Celsius',
    query: 'nvidia_gpu_temperature_celsius',
    category: 'gpu'
  },
  {
    id: 'gpu-power',
    name: 'GPU Power Usage',
    description: 'GPU power consumption in watts',
    query: 'nvidia_gpu_power_usage_watts',
    category: 'gpu'
  },
  {
    id: 'gpu-comparison',
    name: 'GPU Utilization vs Temperature',
    description: 'Compare GPU utilization and temperature',
    query: 'nvidia_gpu_utilization_gpu or nvidia_gpu_temperature_celsius',
    category: 'gpu',
    isAdvanced: true
  },
  
  // Comparison Queries (여러 메트릭 비교)
  {
    id: 'compare-cpu-memory',
    name: 'CPU vs Memory Usage',
    description: 'Compare CPU and memory usage across nodes',
    query: '100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) or (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100',
    category: 'comparison',
    isAdvanced: true
  },
  {
    id: 'compare-all-nodes',
    name: 'Node Resource Overview',
    description: 'CPU, Memory, Disk usage for all nodes',
    query: 'node_load1 or (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 or (1 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})) * 100',
    category: 'comparison',
    isAdvanced: true
  },
  {
    id: 'compare-network-io',
    name: 'Network vs Disk I/O',
    description: 'Compare network and disk I/O rates',
    query: 'rate(node_network_receive_bytes_total[5m]) or rate(node_disk_read_bytes_total[5m])',
    category: 'comparison',
    isAdvanced: true
  },
  
  // Advanced Analysis Queries
  {
    id: 'advanced-top-cpu',
    name: 'Top CPU Consumers',
    description: 'Top 5 nodes by CPU usage',
    query: 'topk(5, 100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100))',
    category: 'advanced',
    isAdvanced: true
  },
  {
    id: 'advanced-top-memory',
    name: 'Top Memory Consumers',
    description: 'Top 5 nodes by memory usage',
    query: 'topk(5, (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100)',
    category: 'advanced',
    isAdvanced: true
  },
  {
    id: 'advanced-resource-efficiency',
    name: 'Resource Efficiency',
    description: 'CPU efficiency (usage vs load)',
    query: '(100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)) / node_load1',
    category: 'advanced',
    isAdvanced: true
  },
  {
    id: 'advanced-saturation',
    name: 'System Saturation',
    description: 'Identify overloaded nodes (load > CPU count)',
    query: 'node_load1 > count by (instance) (node_cpu_seconds_total{mode="idle"})',
    category: 'advanced',
    isAdvanced: true
  },
  {
    id: 'advanced-memory-pressure',
    name: 'Memory Pressure',
    description: 'Nodes with high memory usage (>80%)',
    query: '(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 80',
    category: 'advanced',
    isAdvanced: true
  },
  {
    id: 'advanced-network-bandwidth',
    name: 'Total Network Bandwidth',
    description: 'Sum of all network traffic across cluster',
    query: 'sum(rate(node_network_receive_bytes_total[5m])) + sum(rate(node_network_transmit_bytes_total[5m]))',
    category: 'advanced',
    isAdvanced: true
  }
];

const CATEGORY_INFO = {
  node: { icon: Server, color: 'blue', label: 'Node Metrics' },
  slurm: { icon: Cpu, color: 'green', label: 'Slurm Metrics' },
  gpu: { icon: Zap, color: 'yellow', label: 'GPU Metrics' },
  network: { icon: Network, color: 'purple', label: 'Network Metrics' },
  comparison: { icon: BarChart3, color: 'orange', label: 'Comparison' },
  advanced: { icon: TrendingUp, color: 'red', label: 'Advanced Analysis' }
};

const QueryTemplates: React.FC<QueryTemplatesProps> = ({ onSelectQuery, mode }) => {
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedCategory, setSelectedCategory] = useState<string>('all');

  // Filter templates
  const filteredTemplates = QUERY_TEMPLATES.filter(template => {
    const matchesSearch = template.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
                         template.description.toLowerCase().includes(searchQuery.toLowerCase());
    const matchesCategory = selectedCategory === 'all' || template.category === selectedCategory;
    return matchesSearch && matchesCategory;
  });

  // Get unique categories
  const categories = ['all', ...Array.from(new Set(QUERY_TEMPLATES.map(t => t.category)))];

  return (
    <div className="bg-white rounded-xl shadow-sm border border-gray-200 h-full flex flex-col">
      {/* Header */}
      <div className="p-4 border-b border-gray-200">
        <h3 className="text-lg font-semibold text-gray-900 mb-3">Query Templates</h3>
        
        {/* Search */}
        <div className="relative">
          <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 w-4 h-4 text-gray-400" />
          <input
            type="text"
            placeholder="Search templates..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full pl-9 pr-4 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-indigo-500 focus:border-transparent"
          />
        </div>
        
        {/* Category Tabs */}
        <div className="flex gap-1 mt-3 overflow-x-auto">
          {categories.map(category => (
            <button
              key={category}
              onClick={() => setSelectedCategory(category)}
              className={`px-3 py-1.5 text-xs font-medium rounded-lg whitespace-nowrap transition-colors ${
                selectedCategory === category
                  ? 'bg-indigo-100 text-indigo-700'
                  : 'text-gray-600 hover:bg-gray-100'
              }`}
            >
              {category === 'all' ? 'All' : CATEGORY_INFO[category as keyof typeof CATEGORY_INFO]?.label}
            </button>
          ))}
        </div>
      </div>

      {/* Template List */}
      <div className="flex-1 overflow-y-auto p-4 space-y-2" style={{ maxHeight: 'calc(100vh - 400px)' }}>
        {filteredTemplates.length === 0 ? (
          <div className="text-center py-8 text-gray-500">
            <Search className="w-8 h-8 mx-auto mb-2 text-gray-400" />
            <p className="text-sm">No templates found</p>
          </div>
        ) : (
          filteredTemplates.map(template => {
            const categoryInfo = CATEGORY_INFO[template.category];
            const Icon = categoryInfo.icon;
            
            return (
              <button
                key={template.id}
                onClick={() => onSelectQuery(template.query)}
                className="w-full text-left p-3 rounded-lg border border-gray-200 hover:border-indigo-300 hover:bg-indigo-50 transition-all group"
              >
                <div className="flex items-start gap-3">
                  <div className={`p-2 rounded-lg bg-${categoryInfo.color}-100 text-${categoryInfo.color}-600 group-hover:bg-${categoryInfo.color}-200`}>
                    <Icon className="w-4 h-4" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2">
                      <div className="font-medium text-gray-900 text-sm group-hover:text-indigo-700">
                        {template.name}
                      </div>
                      {template.isAdvanced && (
                        <span className="px-1.5 py-0.5 bg-orange-100 text-orange-700 text-[10px] font-medium rounded">
                          Advanced
                        </span>
                      )}
                    </div>
                    <div className="text-xs text-gray-500 mb-2">
                      {template.description}
                    </div>
                    <div className="text-xs font-mono text-gray-400 bg-gray-50 p-2 rounded border border-gray-200 overflow-hidden text-ellipsis whitespace-nowrap">
                      {template.query}
                    </div>
                  </div>
                </div>
              </button>
            );
          })
        )}
      </div>

      {/* Footer */}
      <div className="p-4 border-t border-gray-200 bg-gray-50">
        <div className="text-xs text-gray-500 text-center">
          {filteredTemplates.length} of {QUERY_TEMPLATES.length} templates
          {selectedCategory !== 'all' && ` in ${CATEGORY_INFO[selectedCategory as keyof typeof CATEGORY_INFO]?.label}`}
        </div>
      </div>
    </div>
  );
};

export default QueryTemplates;
