import React from 'react';
import { FileText, Server, Briefcase, FileCode, ArrowRight, Cpu, HardDrive } from 'lucide-react';

/**
 * SearchResults 컴포넌트
 * 검색 결과 목록 표시
 */

interface SearchResult {
  type: 'job' | 'node' | 'file' | 'template';
  id: string;
  title: string;
  subtitle: string;
  metadata: string;
  data: any;
}

interface SearchResultsProps {
  results: SearchResult[];
  selectedIndex: number;
  onResultClick: (result: SearchResult) => void;
  onHoverIndex: (index: number) => void;
}

const RESULT_ICONS = {
  job: Briefcase,
  node: Server,
  file: FileText,
  template: FileCode
};

const RESULT_COLORS = {
  job: 'text-blue-600 bg-blue-100',
  node: 'text-green-600 bg-green-100',
  file: 'text-purple-600 bg-purple-100',
  template: 'text-orange-600 bg-orange-100'
};

const SearchResults: React.FC<SearchResultsProps> = ({
  results,
  selectedIndex,
  onResultClick,
  onHoverIndex
}) => {
  if (results.length === 0) return null;

  // Group results by type
  const groupedResults: Record<string, SearchResult[]> = {
    jobs: [],
    nodes: [],
    files: [],
    templates: []
  };

  results.forEach(result => {
    const key = result.type + 's';
    if (!groupedResults[key]) {
      groupedResults[key] = [];
    }
    groupedResults[key].push(result);
  });

  let globalIndex = 0;

  return (
    <div className="divide-y divide-gray-100">
      {Object.entries(groupedResults).map(([type, items]) => {
        if (items.length === 0) return null;

        const typeLabel = type.charAt(0).toUpperCase() + type.slice(1);
        const startIndex = globalIndex;

        return (
          <div key={type} className="py-2">
            {/* Section Header */}
            <div className="px-4 py-2 text-xs font-semibold text-gray-500 uppercase tracking-wide">
              {typeLabel} ({items.length})
            </div>

            {/* Results */}
            <div>
              {items.map((result, index) => {
                const currentIndex = startIndex + index;
                globalIndex++;
                const isSelected = currentIndex === selectedIndex;
                const Icon = RESULT_ICONS[result.type];
                const colorClasses = RESULT_COLORS[result.type];

                return (
                  <button
                    key={result.id}
                    onClick={() => onResultClick(result)}
                    onMouseEnter={() => onHoverIndex(currentIndex)}
                    className={`w-full px-4 py-3 flex items-center gap-3 transition-colors text-left ${
                      isSelected
                        ? 'bg-indigo-50 border-l-2 border-indigo-600'
                        : 'hover:bg-gray-50 border-l-2 border-transparent'
                    }`}
                  >
                    {/* Icon */}
                    <div className={`p-2 rounded-lg ${colorClasses} flex-shrink-0`}>
                      <Icon className="w-4 h-4" />
                    </div>

                    {/* Content */}
                    <div className="flex-1 min-w-0">
                      <div className="font-medium text-gray-900 truncate">
                        {result.title}
                      </div>
                      <div className="text-sm text-gray-500 truncate">
                        {result.subtitle}
                      </div>
                      <div className="text-xs text-gray-400 mt-1">
                        {result.metadata}
                      </div>
                    </div>

                    {/* Arrow */}
                    {isSelected && (
                      <ArrowRight className="w-4 h-4 text-indigo-600 flex-shrink-0" />
                    )}
                  </button>
                );
              })}
            </div>
          </div>
        );
      })}
    </div>
  );
};

export default SearchResults;
