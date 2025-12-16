import React from 'react';
import { ExternalLink } from 'lucide-react';

/**
 * Moonlight Streaming Embedded View
 * Shows Moonlight frontend in an iframe within the Dashboard
 */
export const MoonlightEmbedded: React.FC = () => {
  return (
    <div className="h-full flex flex-col bg-white dark:bg-gray-900 rounded-lg shadow-lg">
      {/* Header */}
      <div className="flex items-center justify-between p-4 border-b border-gray-200 dark:border-gray-700 bg-gradient-to-r from-purple-50 to-blue-50 dark:from-gray-800 dark:to-gray-850">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 bg-gradient-to-br from-purple-500 to-blue-600 rounded-lg flex items-center justify-center">
            <span className="text-white text-xl">🎮</span>
          </div>
          <div>
            <h2 className="text-lg font-bold text-gray-800 dark:text-white">
              Moonlight Streaming
            </h2>
            <p className="text-xs text-gray-600 dark:text-gray-400">
              Ultra-Low Latency Desktop Visualization (5-20ms)
            </p>
          </div>
        </div>

        <a
          href="/moonlight/"
          target="_blank"
          rel="noopener noreferrer"
          className="flex items-center gap-2 px-3 py-1.5 text-sm bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition"
        >
          <ExternalLink size={16} />
          <span>Open in New Tab</span>
        </a>
      </div>

      {/* Embedded Moonlight Frontend */}
      <div className="flex-1 relative">
        <iframe
          src="/moonlight/"
          title="Moonlight Streaming Interface"
          className="absolute inset-0 w-full h-full border-0"
          style={{ minHeight: '600px' }}
          sandbox="allow-same-origin allow-scripts allow-forms allow-popups"
        />
      </div>

      {/* Footer Info */}
      <div className="p-3 border-t border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-800">
        <div className="flex items-center justify-between text-xs text-gray-600 dark:text-gray-400">
          <div className="flex items-center gap-4">
            <span>🚀 GPU-accelerated streaming with NVIDIA GameStream</span>
            <span>⚡ 5-20ms latency</span>
          </div>
          <div className="flex items-center gap-2">
            <span className="px-2 py-1 bg-green-100 dark:bg-green-900/30 text-green-800 dark:text-green-400 rounded">
              Backend: 8004
            </span>
            <span className="px-2 py-1 bg-blue-100 dark:bg-blue-900/30 text-blue-800 dark:text-blue-400 rounded">
              Frontend: 8003
            </span>
          </div>
        </div>
      </div>
    </div>
  );
};

export default MoonlightEmbedded;
