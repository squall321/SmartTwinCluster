import React from 'react';
import { SlurmGroup } from '../types';
import { Server, Cpu, Activity } from 'lucide-react';

interface ClusterStatsProps {
  groups: SlurmGroup[];
}

export const ClusterStats: React.FC<ClusterStatsProps> = ({ groups }) => {
  const totalNodes = groups.reduce((sum, g) => sum + g.nodeCount, 0);
  const totalCores = groups.reduce((sum, g) => sum + g.totalCores, 0);
  
  return (
    <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
      <div className="bg-white rounded-lg shadow p-6">
        <div className="flex items-center justify-between">
          <div>
            <p className="text-sm text-gray-500">Total Nodes</p>
            <p className="text-3xl font-bold text-gray-900">{totalNodes}</p>
          </div>
          <div className="p-3 bg-blue-100 rounded-lg">
            <Server size={24} className="text-blue-600" />
          </div>
        </div>
      </div>
      
      <div className="bg-white rounded-lg shadow p-6">
        <div className="flex items-center justify-between">
          <div>
            <p className="text-sm text-gray-500">Total Cores</p>
            <p className="text-3xl font-bold text-gray-900">{totalCores.toLocaleString()}</p>
          </div>
          <div className="p-3 bg-green-100 rounded-lg">
            <Cpu size={24} className="text-green-600" />
          </div>
        </div>
      </div>
      
      <div className="bg-white rounded-lg shadow p-6">
        <div className="flex items-center justify-between">
          <div>
            <p className="text-sm text-gray-500">Active Groups</p>
            <p className="text-3xl font-bold text-gray-900">{groups.length}</p>
          </div>
          <div className="p-3 bg-purple-100 rounded-lg">
            <Activity size={24} className="text-purple-600" />
          </div>
        </div>
      </div>
    </div>
  );
};
