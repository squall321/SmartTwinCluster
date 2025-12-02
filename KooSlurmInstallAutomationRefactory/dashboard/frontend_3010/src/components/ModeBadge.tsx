import React from 'react';
import { ApiMode } from '../hooks/useApiMode';
import { AlertCircle, Zap, HelpCircle } from 'lucide-react';

interface ModeBadgeProps {
  mode: ApiMode;
}

export const ModeBadge: React.FC<ModeBadgeProps> = ({ mode }) => {
  if (mode === 'mock') {
    return (
      <div className="flex items-center gap-2 bg-amber-100 text-amber-800 px-4 py-2 rounded-lg border border-amber-300">
        <AlertCircle size={18} />
        <div>
          <div className="font-semibold">🎭 Mock Mode</div>
          <div className="text-xs">Demo Environment - No real Slurm commands executed</div>
        </div>
      </div>
    );
  }

  if (mode === 'production') {
    return (
      <div className="flex items-center gap-2 bg-green-100 text-green-800 px-4 py-2 rounded-lg border border-green-300">
        <Zap size={18} />
        <div>
          <div className="font-semibold">🚀 Production Mode</div>
          <div className="text-xs">Connected to Real Slurm Cluster</div>
        </div>
      </div>
    );
  }

  return (
    <div className="flex items-center gap-2 bg-gray-100 text-gray-800 px-4 py-2 rounded-lg border border-gray-300">
      <HelpCircle size={18} />
      <div>
        <div className="font-semibold">❓ Unknown Mode</div>
        <div className="text-xs">Checking connection...</div>
      </div>
    </div>
  );
};
