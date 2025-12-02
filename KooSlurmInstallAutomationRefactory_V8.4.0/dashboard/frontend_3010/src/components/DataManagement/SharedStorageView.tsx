import React, { useState, useEffect } from 'react';
import { 
  Folder, TrendingUp, Clock, Search, Filter,
  BarChart3, Database, ExternalLink, FileText,
  Eye, FolderOpen, Loader, AlertCircle
} from 'lucide-react';
import { Dataset } from '../../types';
import { mockStorageStats, mockDatasets } from '../../data/mockStorageData';
import FileBrowser from './FileBrowser';
import EnhancedStorageControls from './EnhancedStorageControls';
import storageApi from '../../utils/storageApi';

const SharedStorageView: React.FC = () => {
  const [stats, setStats] = useState(mockStorageStats);
  const [datasets, setDatasets] = useState<Dataset[]>(mockDatasets);
  const [searchQuery, setSearchQuery] = useState('');
  const [filterStatus, setFilterStatus] = useState<'all' | 'active' | 'archived' | 'processing'>('all');
  const [viewMode, setViewMode] = useState<'table' | 'browser'>('table');
  const [selectedDataset, setSelectedDataset] = useState<Dataset | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [isProduction, setIsProduction] = useState(false);

  // Load data from backend
  useEffect(() => {
    loadData();
  }, []);

  const loadData = async () => {
    setLoading(true);
    setError(null);
    
    try {
      // Load storage stats
      const statsResponse = await storageApi.getSharedStorageStats();
      if (statsResponse.success && statsResponse.data) {
        setStats(statsResponse.data as any);
        setIsProduction(statsResponse.mode === 'production');
      }

      // Load datasets
      const datasetsResponse = await storageApi.getDatasets();
      if (datasetsResponse.success) {
        // Production 모드에서 데이터가 있으면 사용, 없으면 mock 데이터 유지
        if (datasetsResponse.mode === 'production' && datasetsResponse.data) {
          const apiDatasets = datasetsResponse.data as any[];
          if (apiDatasets.length > 0) {
            setDatasets(apiDatasets as Dataset[]);
          }
        }
        setIsProduction(datasetsResponse.mode === 'production');
      }
    } catch (err) {
      console.error('Failed to load storage data:', err);
      setError('Failed to load storage data. Using mock data.');
      // Keep using mock data on error
    } finally {
      setLoading(false);
    }
  };

  const filteredDatasets = datasets.filter(ds => {
    const matchesSearch = ds.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
                         ds.path.toLowerCase().includes(searchQuery.toLowerCase()) ||
                         ds.owner.toLowerCase().includes(searchQuery.toLowerCase());
    const matchesFilter = filterStatus === 'all' || ds.status === filterStatus;
    return matchesSearch && matchesFilter;
  });

  const getStatusColor = (status: Dataset['status']) => {
    switch (status) {
      case 'active': return 'text-green-400 bg-green-400/10 border-green-400/30';
      case 'archived': return 'text-gray-400 bg-gray-400/10 border-gray-400/30';
      case 'processing': return 'text-blue-400 bg-blue-400/10 border-blue-400/30';
    }
  };

  const handleBrowseDataset = (dataset: Dataset) => {
    setSelectedDataset(dataset);
    setViewMode('browser');
  };

  if (viewMode === 'browser' && selectedDataset) {
    return (
      <div className="space-y-4">
        {/* Back button */}
        <button
          onClick={() => {
            setViewMode('table');
            setSelectedDataset(null);
          }}
          className="flex items-center gap-2 text-sm text-gray-300 hover:text-gray-50 transition"
        >
          <FolderOpen className="w-4 h-4" />
          Back to Datasets
        </button>

        {/* Dataset info */}
        <div className="bg-gradient-to-r from-purple-900/40 to-pink-900/40 border border-purple-400/40 rounded-lg p-4">
          <div className="flex items-start justify-between">
            <div className="flex items-start gap-3">
              <Folder className="w-5 h-5 text-purple-300 mt-0.5" />
              <div>
                <h4 className="text-sm font-semibold text-gray-50 mb-1">{selectedDataset.name}</h4>
                <p className="text-xs text-gray-200 font-mono mb-2">{selectedDataset.path}</p>
                <div className="flex items-center gap-4 text-xs text-gray-300">
                  <span>{selectedDataset.size}</span>
                  <span>•</span>
                  <span>{selectedDataset.fileCount.toLocaleString()} files</span>
                  <span>•</span>
                  <span>Owner: {selectedDataset.owner}</span>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Enhanced Storage Controls */}
        <EnhancedStorageControls
          storageType="data"
          selectedFiles={[]}
          onUploadComplete={loadData}
          onDownloadComplete={() => console.log('Download complete')}
        />

        {/* File browser */}
        <FileBrowser 
          rootPath={selectedDataset.path} 
          rootLabel={selectedDataset.name}
          storageType="shared"
        />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Loading State */}
      {loading && (
        <div className="bg-blue-900/30 border border-blue-400/30 rounded-lg p-3 flex items-center gap-3">
          <Loader className="w-5 h-5 text-blue-400 animate-spin" />
          <span className="text-sm text-blue-200">Loading storage data...</span>
        </div>
      )}

      {/* Error State */}
      {error && (
        <div className="bg-yellow-900/30 border border-yellow-400/30 rounded-lg p-3 flex items-center gap-3">
          <AlertCircle className="w-5 h-5 text-yellow-400" />
          <span className="text-sm text-yellow-200">{error}</span>
        </div>
      )}

      {/* Mode Indicator */}
      {isProduction && (
        <div className="bg-green-900/30 border border-green-400/30 rounded-lg p-3 flex items-center gap-3">
          <div className="w-2 h-2 bg-green-400 rounded-full animate-pulse" />
          <span className="text-sm text-green-200 font-medium">
            Production Mode - Live Data
          </span>
        </div>
      )}

      {/* Enhanced Storage Controls */}
      <EnhancedStorageControls
        storageType="data"
        selectedFiles={[]}
        onUploadComplete={loadData}
        onDownloadComplete={() => console.log('Download complete')}
      />

      {/* Storage Overview */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        <div className="bg-gray-700 rounded-lg p-4 border border-gray-500">
          <div className="flex items-center gap-3 mb-2">
            <Database className="w-5 h-5 text-purple-400" />
            <span className="text-sm text-gray-300">Total Capacity</span>
          </div>
          <p className="text-2xl font-bold text-gray-50">{stats.totalCapacity}</p>
        </div>

        <div className="bg-gray-700 rounded-lg p-4 border border-gray-500">
          <div className="flex items-center gap-3 mb-2">
            <TrendingUp className="w-5 h-5 text-blue-400" />
            <span className="text-sm text-gray-300">Used Space</span>
          </div>
          <p className="text-2xl font-bold text-gray-50">{stats.usedSpace}</p>
          <div className="mt-2 bg-gray-600 rounded-full h-2">
            <div 
              className="bg-blue-500 rounded-full h-2 transition-all"
              style={{ width: `${stats.usagePercent}%` }}
            />
          </div>
        </div>

        <div className="bg-gray-700/30 rounded-lg p-4 border border-gray-600">
          <div className="flex items-center gap-3 mb-2">
            <Folder className="w-5 h-5 text-green-400" />
            <span className="text-sm text-gray-300">Datasets</span>
          </div>
          <p className="text-2xl font-bold text-gray-50">{stats.datasetCount}</p>
        </div>

        <div className="bg-gray-700/30 rounded-lg p-4 border border-gray-600">
          <div className="flex items-center gap-3 mb-2">
            <FileText className="w-5 h-5 text-orange-400" />
            <span className="text-sm text-gray-300">Total Files</span>
          </div>
          <p className="text-2xl font-bold text-gray-50">{stats.fileCount.toLocaleString()}</p>
        </div>
      </div>

      {/* Analysis Integration Banner */}
      <div className="bg-gradient-to-r from-purple-900/50 to-pink-900/50 border border-purple-400/50 rounded-lg p-4">
        <div className="flex items-start justify-between">
          <div className="flex items-start gap-3">
            <BarChart3 className="w-5 h-5 text-purple-300 mt-0.5" />
            <div>
              <h4 className="text-sm font-semibold text-gray-50 mb-1">Analysis Automation Integration</h4>
              <p className="text-xs text-gray-200">
                Connected to automated analysis pipeline. Last scan: {stats.lastAnalysis}
              </p>
            </div>
          </div>
          <button className="flex items-center gap-2 px-3 py-1.5 bg-purple-500/30 hover:bg-purple-500/40 text-purple-200 rounded text-xs transition font-medium">
            <ExternalLink className="w-3.5 h-3.5" />
            Open Dashboard
          </button>
        </div>
      </div>

      {/* Search and Filter */}
      <div className="flex gap-3">
        <div className="flex-1 relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
          <input
            type="text"
            placeholder="Search datasets by name, path, or owner..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full pl-10 pr-4 py-2 bg-gray-700 border border-gray-500 rounded-lg text-gray-50 placeholder-gray-300 focus:outline-none focus:border-purple-400 focus:ring-1 focus:ring-purple-400"
          />
        </div>
        
        <div className="flex items-center gap-2 px-3 py-2 bg-gray-700 border border-gray-500 rounded-lg">
          <Filter className="w-4 h-4 text-gray-400" />
          <select
            value={filterStatus}
            onChange={(e) => setFilterStatus(e.target.value as any)}
            className="bg-transparent text-gray-50 text-sm focus:outline-none"
          >
            <option value="all">All Status</option>
            <option value="active">Active</option>
            <option value="archived">Archived</option>
            <option value="processing">Processing</option>
          </select>
        </div>
      </div>

      {/* Datasets Table */}
      <div className="bg-gray-800 rounded-lg border border-gray-600 overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead className="bg-gray-700 border-b border-gray-500">
              <tr>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-300 uppercase tracking-wider">Dataset</th>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase">Path</th>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase">Size</th>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase">Files</th>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase">Owner</th>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase">Status</th>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase">Last Accessed</th>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-400 uppercase">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-600">
              {filteredDatasets.map((dataset) => (
                <tr key={dataset.id} className="hover:bg-gray-700/70 transition">
                  <td className="px-4 py-3">
                    <div className="flex items-center gap-2">
                      <Folder className="w-4 h-4 text-purple-400" />
                      <span className="text-sm text-gray-50 font-medium">{dataset.name}</span>
                    </div>
                  </td>
                  <td className="px-4 py-3">
                    <span className="text-xs text-gray-300 font-mono">{dataset.path}</span>
                  </td>
                  <td className="px-4 py-3">
                    <span className="text-sm text-gray-50">{dataset.size}</span>
                  </td>
                  <td className="px-4 py-3">
                    <span className="text-sm text-gray-200">{dataset.fileCount.toLocaleString()}</span>
                  </td>
                  <td className="px-4 py-3">
                    <div>
                      <div className="text-sm text-gray-200">{dataset.owner}</div>
                      {dataset.group && (
                        <div className="text-xs text-gray-400">{dataset.group}</div>
                      )}
                    </div>
                  </td>
                  <td className="px-4 py-3">
                    <span className={`inline-flex items-center px-2 py-1 rounded text-xs font-medium border ${getStatusColor(dataset.status)}`}>
                      {dataset.status}
                    </span>
                  </td>
                  <td className="px-4 py-3">
                    <div className="flex items-center gap-1 text-xs text-gray-400">
                      <Clock className="w-3 h-3" />
                      {dataset.lastAccessed}
                    </div>
                  </td>
                  <td className="px-4 py-3">
                    <button
                      onClick={() => handleBrowseDataset(dataset)}
                      className="flex items-center gap-1 px-2 py-1 text-xs bg-purple-500/20 hover:bg-purple-500/30 text-purple-300 rounded transition"
                    >
                      <Eye className="w-3 h-3" />
                      Browse
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        {filteredDatasets.length === 0 && (
          <div className="text-center py-12">
            <Folder className="w-12 h-12 text-gray-500 mx-auto mb-3" />
            <p className="text-gray-400">No datasets found</p>
          </div>
        )}
      </div>

      {/* Footer Info */}
      <div className="flex items-center justify-between text-xs text-gray-300">
        <span>Showing {filteredDatasets.length} of {datasets.length} datasets</span>
        <span>Mounted on all nodes (management + compute)</span>
      </div>
    </div>
  );
};

export default SharedStorageView;
