import React, { useState, useEffect } from 'react';
import { Play, Loader2, AlertCircle, Clock, CheckCircle } from 'lucide-react';
import { apiGet } from '../../utils/api';

/**
 * QueryBrowser 컴포넌트
 * PromQL 쿼리 실행 및 결과 표시
 */

interface QueryResult {
  status: string;
  data: {
    resultType: string;
    result: Array<{
      metric: Record<string, string>;
      value?: [number, string];
      values?: Array<[number, string]>;
    }>;
  };
}

interface QueryBrowserProps {
  selectedQuery: string;
  onQueryResults: (results: any, query: string) => void;  // 쿼리도 함께 전달
  mode?: 'mock' | 'production';
}

const QueryBrowser: React.FC<QueryBrowserProps> = ({ selectedQuery, onQueryResults, mode }) => {
  const [query, setQuery] = useState(selectedQuery);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [results, setResults] = useState<QueryResult | null>(null);
  const [executionTime, setExecutionTime] = useState<number>(0);

  // Update query when selectedQuery changes
  useEffect(() => {
    if (selectedQuery) {
      setQuery(selectedQuery);
    }
  }, [selectedQuery]);

  const executeQuery = async () => {
    if (!query.trim()) {
      setError('Please enter a query');
      return;
    }

    setIsLoading(true);
    setError(null);
    const startTime = Date.now();

    try {
      const response = await apiGet<QueryResult>('/api/prometheus/query', {
        query: query.trim()
      });

      const endTime = Date.now();
      setExecutionTime(endTime - startTime);
      
      setResults(response);
      onQueryResults(response, query.trim());  // 쿼리도 함께 전달
      
      console.log('✅ Query executed:', query.trim(), response);
    } catch (err: any) {
      console.error('❌ Query error:', err);
      setError(err.message || 'Failed to execute query');
      setResults(null);
    } finally {
      setIsLoading(false);
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) {
      executeQuery();
    }
  };

  const formatValue = (value: string | number): string => {
    const num = typeof value === 'string' ? parseFloat(value) : value;
    if (isNaN(num)) return String(value);
    
    // Format large numbers
    if (Math.abs(num) >= 1e9) return `${(num / 1e9).toFixed(2)}B`;
    if (Math.abs(num) >= 1e6) return `${(num / 1e6).toFixed(2)}M`;
    if (Math.abs(num) >= 1e3) return `${(num / 1e3).toFixed(2)}K`;
    
    // Format decimals
    if (num % 1 !== 0) return num.toFixed(2);
    
    return String(num);
  };

  return (
    <div className="bg-white rounded-xl shadow-sm border border-gray-200 h-full flex flex-col">
      {/* Query Input */}
      <div className="p-4 border-b border-gray-200">
        <label className="block text-sm font-medium text-gray-700 mb-2">
          PromQL Query
        </label>
        <div className="flex gap-2">
          <textarea
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder="Enter PromQL query... (Ctrl/Cmd + Enter to execute)"
            rows={3}
            className="flex-1 px-3 py-2 border border-gray-300 rounded-lg text-sm font-mono focus:ring-2 focus:ring-indigo-500 focus:border-transparent resize-none"
          />
          <button
            onClick={executeQuery}
            disabled={isLoading || !query.trim()}
            className="px-4 py-2 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors flex items-center gap-2 self-start"
          >
            {isLoading ? (
              <>
                <Loader2 className="w-4 h-4 animate-spin" />
                <span className="hidden sm:inline">Running...</span>
              </>
            ) : (
              <>
                <Play className="w-4 h-4" />
                <span className="hidden sm:inline">Execute</span>
              </>
            )}
          </button>
        </div>
        <p className="text-xs text-gray-500 mt-2">
          Tip: Press <kbd className="px-1.5 py-0.5 bg-gray-100 border border-gray-300 rounded">Ctrl/Cmd + Enter</kbd> to execute
        </p>
      </div>

      {/* Results */}
      <div className="flex-1 overflow-y-auto p-4">
        {error && (
          <div className="flex items-start gap-3 p-4 bg-red-50 border border-red-200 rounded-lg">
            <AlertCircle className="w-5 h-5 text-red-600 flex-shrink-0 mt-0.5" />
            <div>
              <div className="font-medium text-red-900">Query Error</div>
              <div className="text-sm text-red-700 mt-1">{error}</div>
            </div>
          </div>
        )}

        {!error && !results && !isLoading && (
          <div className="text-center py-12 text-gray-500">
            <Play className="w-12 h-12 mx-auto mb-3 text-gray-400" />
            <p className="text-sm">Enter a PromQL query and click Execute</p>
            <p className="text-xs mt-2">Or select a template from the left panel</p>
          </div>
        )}

        {isLoading && (
          <div className="text-center py-12">
            <Loader2 className="w-12 h-12 mx-auto mb-3 text-indigo-600 animate-spin" />
            <p className="text-sm text-gray-600">Executing query...</p>
          </div>
        )}

        {results && results.data.result.length === 0 && (
          <div className="text-center py-12 text-gray-500">
            <AlertCircle className="w-12 h-12 mx-auto mb-3 text-gray-400" />
            <p className="text-sm">No results found</p>
            <p className="text-xs mt-2">Try a different query or check your Prometheus setup</p>
          </div>
        )}

        {results && results.data.result.length > 0 && (
          <div>
            {/* Result Info */}
            <div className="flex items-center justify-between mb-4 pb-3 border-b border-gray-200">
              <div className="flex items-center gap-3">
                <div className="flex items-center gap-2 text-sm text-green-700 bg-green-50 px-3 py-1.5 rounded-lg">
                  <CheckCircle className="w-4 h-4" />
                  <span>{results.data.result.length} result{results.data.result.length !== 1 ? 's' : ''}</span>
                </div>
                <div className="flex items-center gap-2 text-sm text-gray-600">
                  <Clock className="w-4 h-4" />
                  <span>{executionTime}ms</span>
                </div>
              </div>
              <div className="text-xs text-gray-500 font-mono">
                {results.data.resultType}
              </div>
            </div>

            {/* Results Table */}
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="bg-gray-50 border-b border-gray-200">
                    <th className="px-4 py-3 text-left font-semibold text-gray-700">Metric</th>
                    <th className="px-4 py-3 text-right font-semibold text-gray-700">Value</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-200">
                  {results.data.result.map((item, index) => {
                    const metricName = item.metric.__name__ || 'N/A';
                    const metricLabels = Object.entries(item.metric)
                      .filter(([key]) => key !== '__name__')
                      .map(([key, value]) => `${key}="${value}"`)
                      .join(', ');
                    
                    const value = item.value ? item.value[1] : 'N/A';
                    
                    return (
                      <tr key={index} className="hover:bg-gray-50 transition-colors">
                        <td className="px-4 py-3">
                          <div className="font-mono text-xs">
                            <span className="font-semibold text-indigo-600">{metricName}</span>
                            {metricLabels && (
                              <span className="text-gray-600">{`{${metricLabels}}`}</span>
                            )}
                          </div>
                        </td>
                        <td className="px-4 py-3 text-right">
                          <span className="font-mono font-semibold text-gray-900">
                            {formatValue(value)}
                          </span>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

export default QueryBrowser;
