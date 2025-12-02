import React from 'react';
import { X, Cpu, MemoryStick, Monitor, Clock, List, Zap, Server, HardDrive, Bell, Star } from 'lucide-react';
import { WidgetType } from './widgetRegistry';

interface WidgetInfo {
  type: WidgetType;
  name: string;
  description: string;
  icon: React.ReactNode;
  category: 'system' | 'jobs' | 'actions';
  colorClasses: {
    bg: string;
    text: string;
  };
}

const widgetCatalog: WidgetInfo[] = [
  {
    type: 'cpu',
    name: 'CPU Usage',
    description: 'Monitor cluster CPU usage',
    icon: <Cpu className="w-6 h-6" />,
    category: 'system',
    colorClasses: { bg: 'bg-blue-100 dark:bg-blue-900', text: 'text-blue-600 dark:text-blue-400' }
  },
  {
    type: 'memory',
    name: 'Memory Usage',
    description: 'Cluster memory status',
    icon: <MemoryStick className="w-6 h-6" />,
    category: 'system',
    colorClasses: { bg: 'bg-blue-100 dark:bg-blue-900', text: 'text-blue-600 dark:text-blue-400' }
  },
  {
    type: 'gpu',
    name: 'GPU Status',
    description: 'GPU utilization and status',
    icon: <Monitor className="w-6 h-6" />,
    category: 'system',
    colorClasses: { bg: 'bg-blue-100 dark:bg-blue-900', text: 'text-blue-600 dark:text-blue-400' }
  },
  {
    type: 'jobQueue',
    name: 'Job Queue',
    description: 'Number of pending jobs',
    icon: <Clock className="w-6 h-6" />,
    category: 'jobs',
    colorClasses: { bg: 'bg-green-100 dark:bg-green-900', text: 'text-green-600 dark:text-green-400' }
  },
  {
    type: 'recentJobs',
    name: 'Recent Jobs',
    description: 'Recently submitted jobs',
    icon: <List className="w-6 h-6" />,
    category: 'jobs',
    colorClasses: { bg: 'bg-green-100 dark:bg-green-900', text: 'text-green-600 dark:text-green-400' }
  },
  {
    type: 'quickActions',
    name: 'Quick Actions',
    description: 'Frequently used action buttons',
    icon: <Zap className="w-6 h-6" />,
    category: 'actions',
    colorClasses: { bg: 'bg-purple-100 dark:bg-purple-900', text: 'text-purple-600 dark:text-purple-400' }
  },
  {
    type: 'nodeStatus',
    name: 'Node Status',
    description: 'Cluster node status summary',
    icon: <Server className="w-6 h-6" />,
    category: 'system',
    colorClasses: { bg: 'bg-blue-100 dark:bg-blue-900', text: 'text-blue-600 dark:text-blue-400' }
  },
  {
    type: 'storage',
    name: 'Storage',
    description: 'Disk usage status',
    icon: <HardDrive className="w-6 h-6" />,
    category: 'system',
    colorClasses: { bg: 'bg-blue-100 dark:bg-blue-900', text: 'text-blue-600 dark:text-blue-400' }
  },
  {
    type: 'alerts',
    name: 'Alerts',
    description: 'Recent notifications',
    icon: <Bell className="w-6 h-6" />,
    category: 'system',
    colorClasses: { bg: 'bg-blue-100 dark:bg-blue-900', text: 'text-blue-600 dark:text-blue-400' }
  },
  {
    type: 'favorites',
    name: 'Favorites',
    description: 'Frequently used features',
    icon: <Star className="w-6 h-6" />,
    category: 'actions',
    colorClasses: { bg: 'bg-purple-100 dark:bg-purple-900', text: 'text-purple-600 dark:text-purple-400' }
  }
];

interface WidgetLibraryProps {
  onClose: () => void;
  onAddWidget: (type: WidgetType) => void;
}

const WidgetLibrary: React.FC<WidgetLibraryProps> = ({ onClose, onAddWidget }) => {
  const categories = {
    system: { name: 'System', textColor: 'text-blue-600 dark:text-blue-400' },
    jobs: { name: 'Job Management', textColor: 'text-green-600 dark:text-green-400' },
    actions: { name: 'Quick Actions', textColor: 'text-purple-600 dark:text-purple-400' }
  };

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
      <div className="bg-white dark:bg-gray-800 rounded-lg shadow-2xl max-w-4xl w-full max-h-[80vh] overflow-hidden">
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-gray-200 dark:border-gray-700">
          <div>
            <h2 className="text-2xl font-bold text-gray-900 dark:text-white">Widget Library</h2>
            <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">
              Select a widget to add to your dashboard
            </p>
          </div>
          <button
            onClick={onClose}
            className="p-2 hover:bg-gray-100 dark:hover:bg-gray-700 rounded-lg transition-colors"
          >
            <X className="w-5 h-5 text-gray-500 dark:text-gray-400" />
          </button>
        </div>

        {/* Content */}
        <div className="p-6 overflow-y-auto max-h-[calc(80vh-80px)]">
          {Object.entries(categories).map(([key, { name, textColor }]) => {
            const categoryWidgets = widgetCatalog.filter(w => w.category === key);
            
            return (
              <div key={key} className="mb-8 last:mb-0">
                <h3 className={`text-lg font-semibold mb-4 ${textColor}`}>
                  {name}
                </h3>
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                  {categoryWidgets.map(widget => (
                    <button
                      key={widget.type}
                      onClick={() => onAddWidget(widget.type)}
                      className="flex flex-col items-start p-4 bg-gray-50 dark:bg-gray-700 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-600 transition-colors text-left group"
                    >
                      <div className={`p-3 rounded-lg ${widget.colorClasses.bg} ${widget.colorClasses.text} mb-3 group-hover:scale-110 transition-transform`}>
                        {widget.icon}
                      </div>
                      <h4 className="font-semibold text-gray-900 dark:text-white mb-1">
                        {widget.name}
                      </h4>
                      <p className="text-sm text-gray-500 dark:text-gray-400">
                        {widget.description}
                      </p>
                    </button>
                  ))}
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
};

export default WidgetLibrary;
