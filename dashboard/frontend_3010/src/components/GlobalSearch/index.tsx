import React, { useState, useEffect, useRef, useCallback } from 'react';
import { Search, X, Loader2, FileText, Server, Briefcase, FileCode, ArrowRight } from 'lucide-react';
import { apiGet } from '../../utils/api';
import SearchResults from './SearchResults';

/**
 * GlobalSearch 컴포넌트
 * Cmd/Ctrl + K로 열리는 통합 검색 (Command Palette)
 */

interface GlobalSearchProps {
  isOpen: boolean;
  onClose: () => void;
}

interface SearchResult {
  type: 'job' | 'node' | 'file' | 'template';
  id: string;
  title: string;
  subtitle: string;
  metadata: string;
  data: any;
}

const GlobalSearch: React.FC<GlobalSearchProps> = ({ isOpen, onClose }) => {
  const [query, setQuery] = useState('');
  const [isSearching, setIsSearching] = useState(false);
  const [results, setResults] = useState<{
    jobs: any[];
    nodes: any[];
    files: any[];
    templates: any[];
  }>({ jobs: [], nodes: [], files: [], templates: [] });
  const [selectedIndex, setSelectedIndex] = useState(0);
  const [searchType, setSearchType] = useState<'all' | 'jobs' | 'nodes' | 'files' | 'templates'>('all');
  
  const inputRef = useRef<HTMLInputElement>(null);
  const searchTimeoutRef = useRef<NodeJS.Timeout | null>(null);

  // Focus input when opened
  useEffect(() => {
    if (isOpen && inputRef.current) {
      inputRef.current.focus();
    }
  }, [isOpen]);

  // Clear results when closed
  useEffect(() => {
    if (!isOpen) {
      setQuery('');
      setResults({ jobs: [], nodes: [], files: [], templates: [] });
      setSelectedIndex(0);
      setSearchType('all');
    }
  }, [isOpen]);

  // Debounced search
  const performSearch = useCallback(async (searchQuery: string) => {
    if (!searchQuery.trim()) {
      setResults({ jobs: [], nodes: [], files: [], templates: [] });
      return;
    }

    setIsSearching(true);

    try {
      const response = await apiGet<{
        success: boolean;
        results: {
          jobs: any[];
          nodes: any[];
          files: any[];
          templates: any[];
        };
      }>('/api/search/global', {
        q: searchQuery,
        type: searchType,
        limit: 50
      });

      if (response.success) {
        setResults(response.results);
        setSelectedIndex(0); // Reset selection
      }
    } catch (error) {
      console.error('Search error:', error);
    } finally {
      setIsSearching(false);
    }
  }, [searchType]);

  useEffect(() => {
    if (searchTimeoutRef.current) {
      clearTimeout(searchTimeoutRef.current);
    }

    searchTimeoutRef.current = setTimeout(() => {
      performSearch(query);
    }, 300); // 300ms debounce

    return () => {
      if (searchTimeoutRef.current) {
        clearTimeout(searchTimeoutRef.current);
      }
    };
  }, [query, performSearch]);

  // Get flattened results for keyboard navigation
  const getAllResults = (): SearchResult[] => {
    const allResults: SearchResult[] = [];

    results.jobs.forEach(job => {
      allResults.push({
        type: 'job',
        id: job.id,
        title: job.name,
        subtitle: `Job #${job.id}`,
        metadata: `${job.state} • ${job.partition} • ${job.nodes} nodes`,
        data: job
      });
    });

    results.nodes.forEach(node => {
      allResults.push({
        type: 'node',
        id: node.hostname,
        title: node.hostname,
        subtitle: 'Node',
        metadata: `${node.state} • ${node.cpus} cores • ${node.memory}`,
        data: node
      });
    });

    results.files.forEach(file => {
      allResults.push({
        type: 'file',
        id: file.path,
        title: file.name,
        subtitle: file.path,
        metadata: `${file.size} • ${file.modified}`,
        data: file
      });
    });

    results.templates.forEach(template => {
      allResults.push({
        type: 'template',
        id: template.id,
        title: template.name,
        subtitle: 'Job Template',
        metadata: `${template.category} • Used ${template.usage_count} times`,
        data: template
      });
    });

    return allResults;
  };

  const allResults = getAllResults();
  const totalResults = allResults.length;

  // Keyboard navigation
  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Escape') {
      onClose();
    } else if (e.key === 'ArrowDown') {
      e.preventDefault();
      setSelectedIndex(prev => (prev + 1) % totalResults);
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      setSelectedIndex(prev => (prev - 1 + totalResults) % totalResults);
    } else if (e.key === 'Enter' && allResults[selectedIndex]) {
      e.preventDefault();
      handleResultClick(allResults[selectedIndex]);
    }
  };

  const handleResultClick = (result: SearchResult) => {
    console.log('Selected:', result);
    
    // TODO: Navigate to appropriate page based on type
    switch (result.type) {
      case 'job':
        // Navigate to job details
        console.log('Navigate to job:', result.data);
        break;
      case 'node':
        // Navigate to node details
        console.log('Navigate to node:', result.data);
        break;
      case 'file':
        // Open file or navigate to file browser
        console.log('Navigate to file:', result.data);
        break;
      case 'template':
        // Open template editor or job submission
        console.log('Use template:', result.data);
        break;
    }

    onClose();
  };

  if (!isOpen) return null;

  return (
    <>
      {/* Backdrop */}
      <div
        className="fixed inset-0 bg-black bg-opacity-50 z-50 transition-opacity"
        onClick={onClose}
      />

      {/* Search Modal */}
      <div className="fixed inset-0 z-50 flex items-start justify-center pt-[10vh] pointer-events-none">
        <div className="w-full max-w-2xl mx-4 pointer-events-auto">
          <div className="bg-white rounded-xl shadow-2xl border border-gray-200 overflow-hidden">
            {/* Search Input */}
            <div className="flex items-center gap-3 p-4 border-b border-gray-200">
              <Search className="w-5 h-5 text-gray-400 flex-shrink-0" />
              <input
                ref={inputRef}
                type="text"
                placeholder="Search jobs, nodes, files, templates..."
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                onKeyDown={handleKeyDown}
                className="flex-1 text-lg outline-none"
              />
              {isSearching && (
                <Loader2 className="w-5 h-5 text-indigo-600 animate-spin flex-shrink-0" />
              )}
              <button
                onClick={onClose}
                className="p-1.5 hover:bg-gray-100 rounded transition-colors flex-shrink-0"
                title="Close (Esc)"
              >
                <X className="w-5 h-5 text-gray-500" />
              </button>
            </div>

            {/* Filter Tabs */}
            <div className="flex gap-2 px-4 py-3 bg-gray-50 border-b border-gray-200 overflow-x-auto">
              {[
                { value: 'all', label: 'All', count: totalResults },
                { value: 'jobs', label: 'Jobs', count: results.jobs.length },
                { value: 'nodes', label: 'Nodes', count: results.nodes.length },
                { value: 'files', label: 'Files', count: results.files.length },
                { value: 'templates', label: 'Templates', count: results.templates.length }
              ].map(filter => (
                <button
                  key={filter.value}
                  onClick={() => setSearchType(filter.value as any)}
                  className={`px-3 py-1.5 rounded-lg text-sm font-medium whitespace-nowrap transition-colors ${
                    searchType === filter.value
                      ? 'bg-indigo-100 text-indigo-700'
                      : 'text-gray-600 hover:bg-gray-100'
                  }`}
                >
                  {filter.label}
                  {filter.count > 0 && (
                    <span className="ml-1.5 text-xs opacity-75">({filter.count})</span>
                  )}
                </button>
              ))}
            </div>

            {/* Results */}
            <div className="max-h-[60vh] overflow-y-auto">
              {!query.trim() ? (
                <div className="py-12 text-center text-gray-500">
                  <Search className="w-12 h-12 mx-auto mb-3 text-gray-400" />
                  <p className="text-sm">Start typing to search...</p>
                  <p className="text-xs mt-2 text-gray-400">
                    Search across jobs, nodes, files, and templates
                  </p>
                </div>
              ) : totalResults === 0 && !isSearching ? (
                <div className="py-12 text-center text-gray-500">
                  <Search className="w-12 h-12 mx-auto mb-3 text-gray-400" />
                  <p className="text-sm">No results found</p>
                  <p className="text-xs mt-2 text-gray-400">
                    Try different keywords or filters
                  </p>
                </div>
              ) : (
                <SearchResults
                  results={allResults}
                  selectedIndex={selectedIndex}
                  onResultClick={handleResultClick}
                  onHoverIndex={setSelectedIndex}
                />
              )}
            </div>

            {/* Footer */}
            <div className="px-4 py-3 bg-gray-50 border-t border-gray-200 flex items-center justify-between text-xs text-gray-500">
              <div className="flex items-center gap-4">
                <div className="flex items-center gap-1">
                  <kbd className="px-2 py-1 bg-white border border-gray-300 rounded shadow-sm">↑↓</kbd>
                  <span>Navigate</span>
                </div>
                <div className="flex items-center gap-1">
                  <kbd className="px-2 py-1 bg-white border border-gray-300 rounded shadow-sm">Enter</kbd>
                  <span>Select</span>
                </div>
                <div className="flex items-center gap-1">
                  <kbd className="px-2 py-1 bg-white border border-gray-300 rounded shadow-sm">Esc</kbd>
                  <span>Close</span>
                </div>
              </div>
              {totalResults > 0 && (
                <div>
                  {totalResults} result{totalResults !== 1 ? 's' : ''}
                </div>
              )}
            </div>
          </div>
        </div>
      </div>
    </>
  );
};

export default GlobalSearch;
