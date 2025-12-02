import React from 'react';
import { Play, Edit2, Trash2, Copy, TrendingUp, Clock, User, Cpu, HardDrive, Download, FileText } from 'lucide-react';

/**
 * TemplateCard 컴포넌트
 * 템플릿 카드 표시
 */

interface Template {
  id: string;
  name: string;
  description: string;
  category: 'ml' | 'simulation' | 'data' | 'custom' | 'compute' | 'container';
  shared: boolean;
  config: {
    partition: string;
    nodes: number;
    cpus: number;
    memory: string;
    time: string;
    gpu?: number;
    script: string;
  };
  created_by: string;
  created_at: string;
  updated_at: string;
  usage_count: number;
  tags?: string[];
}

interface TemplateCardProps {
  template: Template;
  onUse: (template: Template) => void;
  onEdit: (template: Template) => void;
  onDelete: (templateId: string) => void;
  onExport?: (template: Template) => void;
  onDuplicate?: (template: Template) => void;
}

const CATEGORY_COLORS = {
  ml: 'bg-blue-100 text-blue-700 border-blue-200',
  data: 'bg-green-100 text-green-700 border-green-200',
  simulation: 'bg-purple-100 text-purple-700 border-purple-200',
  compute: 'bg-yellow-100 text-yellow-700 border-yellow-200',
  container: 'bg-indigo-100 text-indigo-700 border-indigo-200',
  custom: 'bg-gray-100 text-gray-700 border-gray-200'
};

const CATEGORY_LABELS = {
  ml: '🤖 ML',
  data: '📊 Data',
  simulation: '🧪 Simulation',
  compute: '⚡ HPC',
  container: '📦 Container',
  custom: '⚙️ Custom'
};

const TemplateCard: React.FC<TemplateCardProps> = (
  {
    template,
    onUse,
    onEdit,
    onDelete,
    onExport,
    onDuplicate
  }
) => {
  const formatDate = (dateStr: string) => {
    const date = new Date(dateStr);
    return date.toLocaleDateString();
  };

  return (
    <div className="bg-white rounded-lg border border-gray-200 hover:shadow-lg transition-all overflow-hidden group">
      {/* Header */}
      <div className="p-4 border-b border-gray-100">
        <div className="flex items-start justify-between mb-2">
          <div className="flex-1 min-w-0">
            <h3 className="text-lg font-semibold text-gray-900 truncate">
              {template.name}
            </h3>
            <p className="text-sm text-gray-500 line-clamp-2 mt-1">
              {template.description}
            </p>
          </div>
          
          {/* Category Badge */}
          <span className={`ml-2 px-2 py-1 text-xs font-medium rounded border flex-shrink-0 ${
            CATEGORY_COLORS[template.category]
          }`}>
            {CATEGORY_LABELS[template.category]}
          </span>
        </div>

        {/* Stats */}
        <div className="flex items-center gap-3 text-xs text-gray-500 mt-3">
          <div className="flex items-center gap-1">
            <TrendingUp className="w-3 h-3" />
            <span>{template.usage_count} uses</span>
          </div>
          <div className="flex items-center gap-1">
            <User className="w-3 h-3" />
            <span>{template.created_by}</span>
          </div>
          <div className="flex items-center gap-1">
            <Clock className="w-3 h-3" />
            <span>{formatDate(template.created_at)}</span>
          </div>
        </div>
      </div>

      {/* Config Preview */}
      <div className="p-4 bg-gray-50">
        <div className="grid grid-cols-2 gap-3 text-sm">
          <div>
            <div className="text-xs text-gray-500 mb-1">Partition</div>
            <div className="font-medium text-gray-900">{template.config.partition}</div>
          </div>
          <div>
            <div className="text-xs text-gray-500 mb-1">Time Limit</div>
            <div className="font-medium text-gray-900">{template.config.time}</div>
          </div>
          <div>
            <div className="text-xs text-gray-500 mb-1">Resources</div>
            <div className="font-medium text-gray-900 flex items-center gap-1">
              <Cpu className="w-3 h-3" />
              {template.config.nodes}N × {template.config.cpus}C
              {template.config.gpu && ` × ${template.config.gpu}G`}
            </div>
          </div>
          <div>
            <div className="text-xs text-gray-500 mb-1">Memory</div>
            <div className="font-medium text-gray-900 flex items-center gap-1">
              <HardDrive className="w-3 h-3" />
              {template.config.memory}
            </div>
          </div>
        </div>
      </div>

      {/* Actions */}
      <div className="p-4 flex items-center gap-2 border-t border-gray-100 bg-white">
        <button
          onClick={() => onUse(template)}
          className="flex-1 flex items-center justify-center gap-2 px-3 py-2 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700 transition-colors text-sm font-medium"
        >
          <Play className="w-4 h-4" />
          Use
        </button>
        
        <button
          onClick={() => onEdit(template)}
          className="p-2 text-gray-600 hover:bg-gray-100 rounded-lg transition-colors"
          title="Edit template"
        >
          <Edit2 className="w-4 h-4" />
        </button>

        {onExport && (
          <button
            onClick={() => onExport(template)}
            className="p-2 text-gray-600 hover:bg-gray-100 rounded-lg transition-colors"
            title="Export template as JSON"
          >
            <Download className="w-4 h-4" />
          </button>
        )}

        {onDuplicate && (
          <button
            onClick={() => onDuplicate(template)}
            className="p-2 text-gray-600 hover:bg-gray-100 rounded-lg transition-colors"
            title="Duplicate template"
          >
            <Copy className="w-4 h-4" />
          </button>
        )}
        
        <button
          onClick={() => {
            navigator.clipboard.writeText(template.config.script);
            // 사용자에게 피드백
            const btn = event?.currentTarget;
            if (btn) {
              const originalTitle = btn.title;
              btn.title = 'Copied!';
              setTimeout(() => { btn.title = originalTitle; }, 2000);
            }
          }}
          className="p-2 text-gray-600 hover:bg-gray-100 rounded-lg transition-colors"
          title="Copy script to clipboard"
        >
          <FileText className="w-4 h-4" />
        </button>
        
        <button
          onClick={() => onDelete(template.id)}
          className="p-2 text-red-600 hover:bg-red-50 rounded-lg transition-colors"
          title="Delete template"
        >
          <Trash2 className="w-4 h-4" />
        </button>
      </div>

      {/* Shared/Public Badge */}
      {template.shared && (
        <div className="absolute top-3 right-3 flex items-center gap-1.5 px-2.5 py-1 bg-green-500 text-white text-xs font-medium rounded-full shadow-sm">
          <svg className="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
          </svg>
          <span>Public</span>
        </div>
      )}

      {/* Tags (if available) */}
      {template.tags && template.tags.length > 0 && (
        <div className="px-4 pb-4 flex flex-wrap gap-2">
          {template.tags.slice(0, 3).map((tag, index) => (
            <span
              key={index}
              className="px-2 py-0.5 text-xs font-medium bg-gray-100 text-gray-600 rounded"
            >
              #{tag}
            </span>
          ))}
          {template.tags.length > 3 && (
            <span className="px-2 py-0.5 text-xs text-gray-400">
              +{template.tags.length - 3} more
            </span>
          )}
        </div>
      )}
    </div>
  );
};

export default TemplateCard;
