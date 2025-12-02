import React, { useState } from 'react';
import { Database, HardDrive, Server } from 'lucide-react';
import SharedStorageView from './SharedStorageView';
import ScratchStorageView from './ScratchStorageView';

type ViewType = 'shared' | 'scratch';

const DataManagement: React.FC = () => {
  const [activeView, setActiveView] = useState<ViewType>('shared');

  return (
    <div className="space-y-6 bg-gray-900 p-6 rounded-lg">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className="p-2 bg-purple-500/10 rounded-lg">
            <Database className="w-6 h-6 text-purple-500" />
          </div>
          <div>
            <h2 className="text-2xl font-bold text-gray-50">Data Management</h2>
            <p className="text-gray-300 text-sm">Manage cluster storage and datasets</p>
          </div>
        </div>
      </div>

      {/* Storage Type Tabs */}
      <div className="bg-gray-800 rounded-lg border border-gray-600">
        <div className="flex border-b border-gray-600">
          <button
            onClick={() => setActiveView('shared')}
            className={`flex items-center gap-2 px-6 py-3 border-b-2 transition ${
              activeView === 'shared'
                ? 'border-purple-400 text-purple-300 bg-purple-500/20 font-semibold'
                : 'border-transparent text-gray-300 hover:text-gray-100 hover:bg-gray-700/50'
            }`}
          >
            <Server className="w-5 h-5" />
            <span className="font-medium">Shared Storage (/data)</span>
          </button>
          
          <button
            onClick={() => setActiveView('scratch')}
            className={`flex items-center gap-2 px-6 py-3 border-b-2 transition ${
              activeView === 'scratch'
                ? 'border-blue-400 text-blue-300 bg-blue-500/20 font-semibold'
                : 'border-transparent text-gray-300 hover:text-gray-100 hover:bg-gray-700/50'
            }`}
          >
            <HardDrive className="w-5 h-5" />
            <span className="font-medium">Local Scratch (/scratch)</span>
          </button>
        </div>

        <div className="p-6">
          {activeView === 'shared' && <SharedStorageView />}
          {activeView === 'scratch' && <ScratchStorageView />}
        </div>
      </div>

      {/* Info Banner */}
      <div className="bg-gradient-to-r from-purple-900/40 to-blue-900/40 border border-purple-400/40 rounded-lg p-4">
        <div className="flex items-start gap-3">
          <Database className="w-5 h-5 text-purple-300 mt-0.5 flex-shrink-0" />
          <div className="flex-1">
            <h4 className="text-sm font-semibold text-gray-50 mb-1">Storage Architecture</h4>
            <p className="text-xs text-gray-200">
              <strong className="text-purple-300 font-bold">/data:</strong> Shared storage mounted on all nodes (management + compute). 
              Integrated with analysis automation SW for long-term dataset management.
            </p>
            <p className="text-xs text-gray-200 mt-1">
              <strong className="text-blue-300 font-bold">/scratch:</strong> Local high-speed storage on each compute node. 
              For temporary job data - move to /data for persistence or delete to free space.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
};

export default DataManagement;
