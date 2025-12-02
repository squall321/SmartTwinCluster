import React from 'react';
import { Zap, GripVertical, X, Play, Pause, RotateCcw, Trash2, FileText, Download } from 'lucide-react';
import { WidgetProps } from '../widgetRegistry';

const QuickActionsWidget: React.FC<WidgetProps> = ({ id, onRemove, isEditMode, mode }) => {
  const actions = [
    { icon: <Play className="w-5 h-5" />, label: 'Submit Job', color: 'bg-green-500 hover:bg-green-600' },
    { icon: <Pause className="w-5 h-5" />, label: 'Stop Job', color: 'bg-yellow-500 hover:bg-yellow-600' },
    { icon: <RotateCcw className="w-5 h-5" />, label: 'Restart', color: 'bg-blue-500 hover:bg-blue-600' },
    { icon: <Trash2 className="w-5 h-5" />, label: 'Delete', color: 'bg-red-500 hover:bg-red-600' },
    { icon: <FileText className="w-5 h-5" />, label: 'View Logs', color: 'bg-purple-500 hover:bg-purple-600' },
    { icon: <Download className="w-5 h-5" />, label: 'Download Results', color: 'bg-indigo-500 hover:bg-indigo-600' },
  ];

  const handleAction = (label: string) => {
    alert(`${label} feature is under development.`);
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
          <Zap className="w-5 h-5 text-yellow-500" />
          <h3 className="font-semibold text-gray-900 dark:text-white">Quick Actions</h3>
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
      <div className="flex-1 p-4">
        <div className="grid grid-cols-2 gap-3">
          {actions.map((action, index) => (
            <button
              key={index}
              onClick={() => handleAction(action.label)}
              className={`${action.color} text-white rounded-lg p-4 transition-all transform hover:scale-105 active:scale-95 shadow-md`}
            >
              <div className="flex flex-col items-center gap-2">
                {action.icon}
                <span className="text-sm font-medium">{action.label}</span>
              </div>
            </button>
          ))}
        </div>
      </div>
    </div>
  );
};

export default QuickActionsWidget;
