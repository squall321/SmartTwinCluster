import React, { useState, useEffect } from 'react';
import { 
  HardDrive, Server, Trash2, MoveRight, AlertTriangle, 
  Search, ChevronDown, ChevronRight, Folder, RefreshCw,
  CheckCircle, Eye, Loader, AlertCircle
} from 'lucide-react';
import { NodeScratchData, ScratchDirectory } from '../../types';
import { mockScratchNodes } from '../../data/mockStorageData';
import FileBrowser from './FileBrowser';
import EnhancedStorageControls from './EnhancedStorageControls';
import MultiNodeTransfer from './MultiNodeTransfer';
import storageApi from '../../utils/storageApi';

const ScratchStorageView: React.FC = () => {
  const [nodes, setNodes] = useState<NodeScratchData[]>([]);
  const [expandedNodes, setExpandedNodes] = useState<Set<string>>(new Set());
  const [selectedItems, setSelectedItems] = useState<Set<string>>(new Set());
  const [searchQuery, setSearchQuery] = useState('');
  const [showMoveModal, setShowMoveModal] = useState(false);
  const [showDeleteModal, setShowDeleteModal] = useState(false);
  const [browsingNode, setBrowsingNode] = useState<NodeScratchData | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [isProduction, setIsProduction] = useState(false);
  const [showMultiTransfer, setShowMultiTransfer] = useState(false);
  const [transferSource, setTransferSource] = useState<{ path: string; node: string } | null>(null);

  // Load data from backend
  useEffect(() => {
    loadData();
  }, []);

  const loadData = async () => {
    setLoading(true);
    setError(null);
    
    try {
      const response = await storageApi.getScratchNodes();
      
      if (response.success) {
        const mode = response.mode || 'mock';
        setIsProduction(mode === 'production');
        
        if (mode === 'production') {
          // Production 모드: 실제 API 데이터 사용
          const apiNodes = (response.data as any[]) || [];
          setNodes(apiNodes as NodeScratchData[]);
          
          console.log(`✅ Production Mode: Loaded ${apiNodes.length} nodes from API`);
          
          if (apiNodes.length === 0) {
            setError('No compute nodes found. Check: 1) Slurm is running (sinfo), 2) SSH keys are configured.');
          }
        } else {
          // Mock 모드: mock 데이터 사용
          console.log('🎭 Mock Mode: Using mock scratch nodes');
          setNodes(mockScratchNodes);
        }
      } else {
        // API 실패
        setError(response.error || 'Failed to load scratch data. Check backend logs.');
        console.error('API Error:', response.error);
        
        // Mock 데이터로 폴백
        setNodes(mockScratchNodes);
        setIsProduction(false);
      }
    } catch (err) {
      console.error('Failed to load scratch nodes:', err);
      setError('Failed to connect to backend. Using mock data.');
      
      // Mock 데이터로 폴백
      setNodes(mockScratchNodes);
      setIsProduction(false);
    } finally {
      setLoading(false);
    }
  };

  const handleRefresh = () => {
    loadData();
  };

  const toggleNodeExpansion = (nodeId: string) => {
    const newExpanded = new Set(expandedNodes);
    if (newExpanded.has(nodeId)) {
      newExpanded.delete(nodeId);
    } else {
      newExpanded.add(nodeId);
    }
    setExpandedNodes(newExpanded);
  };

  const toggleSelection = (id: string) => {
    const newSelected = new Set(selectedItems);
    if (newSelected.has(id)) {
      newSelected.delete(id);
    } else {
      newSelected.add(id);
    }
    setSelectedItems(newSelected);
  };

  const handleMoveToData = () => {
    setShowMoveModal(true);
  };

  const handleMultiNodeTransfer = () => {
    // 선택된 첫 번째 디렉토리를 전송 소스로 사용
    const firstSelectedId = Array.from(selectedItems)[0];
    const sourceDir = nodes
      .flatMap(n => n.directories)
      .find(d => d.id === firstSelectedId);
    
    if (sourceDir) {
      const sourceNode = nodes.find(n => 
        n.directories.some(d => d.id === firstSelectedId)
      );
      
      if (sourceNode) {
        setTransferSource({
          path: sourceDir.path,
          node: sourceNode.nodeName
        });
        setShowMultiTransfer(true);
      }
    }
  };

  const handleDelete = () => {
    setShowDeleteModal(true);
  };

  const confirmMove = async () => {
    console.log('Moving to /data:', Array.from(selectedItems));
    
    try {
      const response = await storageApi.moveScratchToData({
        directoryIds: Array.from(selectedItems),
        destination: '/data/from_scratch/'
      });
      
      if (response.success) {
        console.log('Move initiated:', response.message);
        // Refresh data
        loadData();
      } else {
        setError(response.error || 'Failed to move directories');
      }
    } catch (err) {
      console.error('Move error:', err);
      setError('Failed to move directories');
    } finally {
      setSelectedItems(new Set());
      setShowMoveModal(false);
    }
  };

  const confirmDelete = async () => {
    console.log('Deleting:', Array.from(selectedItems));
    
    try {
      const response = await storageApi.deleteScratchDirectories(Array.from(selectedItems));
      
      if (response.success) {
        console.log('Delete initiated:', response.message);
        // Remove deleted directories from state
        setNodes(nodes.map(node => ({
          ...node,
          directories: node.directories.filter(dir => !selectedItems.has(dir.id))
        })));
      } else {
        setError(response.error || 'Failed to delete directories');
      }
    } catch (err) {
      console.error('Delete error:', err);
      setError('Failed to delete directories');
    } finally {
      setSelectedItems(new Set());
      setShowDeleteModal(false);
    }
  };

  const getStatusColor = (status: NodeScratchData['status']) => {
    switch (status) {
      case 'online': return 'text-green-400 bg-green-400/10';
      case 'offline': return 'text-red-400 bg-red-400/10';
      case 'maintenance': return 'text-yellow-400 bg-yellow-400/10';
    }
  };

  const getUsageColor = (percent: number) => {
    if (percent >= 90) return 'bg-red-500';
    if (percent >= 75) return 'bg-orange-500';
    if (percent >= 50) return 'bg-yellow-500';
    return 'bg-green-500';
  };

  const filteredNodes = nodes.filter(node => 
    node.nodeName.toLowerCase().includes(searchQuery.toLowerCase()) ||
    node.directories.some(dir => 
      dir.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
      dir.owner.toLowerCase().includes(searchQuery.toLowerCase())
    )
  );

  const totalSelected = selectedItems.size;
  const totalUsagePercent = nodes.length > 0 
    ? nodes.reduce((sum, node) => sum + node.usagePercent, 0) / nodes.length 
    : 0;
  const highUsageNodes = nodes.filter(n => n.usagePercent > 75).length;

  if (browsingNode) {
    return (
      <div className="space-y-4">
        {/* Back button */}
        <button
          onClick={() => setBrowsingNode(null)}
          className="flex items-center gap-2 text-sm text-gray-300 hover:text-gray-50 transition"
        >
          <Server className="w-4 h-4" />
          Back to Nodes
        </button>

        {/* Node info */}
        <div className="bg-gradient-to-r from-blue-900/40 to-cyan-900/40 border border-blue-400/40 rounded-lg p-4">
          <div className="flex items-start justify-between">
            <div className="flex items-start gap-3">
              <HardDrive className="w-5 h-5 text-blue-300 mt-0.5" />
              <div>
                <h4 className="text-sm font-semibold text-gray-50 mb-1">{browsingNode.nodeName}</h4>
                <p className="text-xs text-gray-200 font-mono mb-2">/scratch</p>
                <div className="flex items-center gap-4 text-xs text-gray-300">
                  <span>{browsingNode.usedSpace} / {browsingNode.totalSpace}</span>
                  <span>•</span>
                  <span>{browsingNode.usagePercent}% used</span>
                  <span>•</span>
                  <span>{browsingNode.directories.length} directories</span>
                </div>
              </div>
            </div>
            <span className={`text-xs px-2 py-1 rounded font-medium ${getStatusColor(browsingNode.status)}`}>
              {browsingNode.status}
            </span>
          </div>
        </div>

        {/* Enhanced Storage Controls */}
        <EnhancedStorageControls
          storageType="scratch"
          selectedNode={browsingNode.nodeName}
          selectedFiles={[]}
          onUploadComplete={loadData}
          onDownloadComplete={() => console.log('Download complete')}
        />

        {/* File browser */}
        <FileBrowser 
          rootPath="/scratch" 
          rootLabel={`${browsingNode.nodeName} /scratch`}
          storageType="scratch"
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
          <span className="text-sm text-blue-200">Loading scratch data from compute nodes...</span>
        </div>
      )}

      {/* Error State */}
      {error && (
        <div className="bg-yellow-900/30 border border-yellow-400/30 rounded-lg p-3 flex items-center gap-3">
          <AlertCircle className="w-5 h-5 text-yellow-400" />
          <div className="flex-1">
            <span className="text-sm text-yellow-200 block">{error}</span>
            {isProduction && nodes.length === 0 && (
              <div className="text-xs text-yellow-300 mt-2 space-y-1">
                <div>Troubleshooting:</div>
                <div>• Check Slurm: <code className="bg-yellow-900/30 px-1 rounded">sinfo -N</code></div>
                <div>• Check SSH: <code className="bg-yellow-900/30 px-1 rounded">ssh node-01 "echo test"</code></div>
                <div>• Setup SSH keys: <code className="bg-yellow-900/30 px-1 rounded">ssh-copy-id node-01</code></div>
              </div>
            )}
          </div>
          <button 
            onClick={() => setError(null)}
            className="text-yellow-200 hover:text-yellow-100"
          >
            ×
          </button>
        </div>
      )}

      {/* Mode Indicator */}
      {isProduction && (
        <div className="bg-green-900/30 border border-green-400/30 rounded-lg p-3 flex items-center gap-3">
          <div className="w-2 h-2 bg-green-400 rounded-full animate-pulse" />
          <div className="flex-1">
            <span className="text-sm text-green-200 font-medium">
              Production Mode - Live Data from {nodes.length} Compute Node{nodes.length !== 1 ? 's' : ''}
            </span>
          </div>
        </div>
      )}

      {/* Mock Mode Warning */}
      {!isProduction && !loading && (
        <div className="bg-blue-900/30 border border-blue-400/30 rounded-lg p-3 flex items-center gap-3">
          <AlertCircle className="w-5 h-5 text-blue-400" />
          <div className="flex-1">
            <span className="text-sm text-blue-200 font-medium">Mock Mode - Using Demo Data</span>
            <div className="text-xs text-blue-300 mt-1">
              Start in production mode: <code className="bg-blue-900/30 px-1 rounded">./start_production.sh</code>
            </div>
          </div>
        </div>
      )}

      {/* Overall Stats */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        <div className="bg-gray-700 rounded-lg p-4 border border-gray-500">
          <div className="flex items-center gap-3 mb-2">
            <Server className="w-5 h-5 text-blue-400" />
            <span className="text-sm text-gray-300">Total Nodes</span>
          </div>
          <p className="text-2xl font-bold text-gray-50">{nodes.length}</p>
          {isProduction && (
            <p className="text-xs text-gray-300 mt-1">From Slurm cluster</p>
          )}
        </div>

        <div className="bg-gray-700/30 rounded-lg p-4 border border-gray-600">
          <div className="flex items-center gap-3 mb-2">
            <HardDrive className="w-5 h-5 text-green-400" />
            <span className="text-sm text-gray-300">Avg Usage</span>
          </div>
          <p className="text-2xl font-bold text-gray-50">{totalUsagePercent.toFixed(1)}%</p>
        </div>

        <div className="bg-gray-700/30 rounded-lg p-4 border border-gray-600">
          <div className="flex items-center gap-3 mb-2">
            <Folder className="w-5 h-5 text-purple-400" />
            <span className="text-sm text-gray-300">Total Directories</span>
          </div>
          <p className="text-2xl font-bold text-gray-50">
            {nodes.reduce((sum, node) => sum + node.directories.length, 0)}
          </p>
        </div>

        <div className="bg-gray-700/30 rounded-lg p-4 border border-gray-600">
          <div className="flex items-center gap-3 mb-2">
            <AlertTriangle className="w-5 h-5 text-orange-400" />
            <span className="text-sm text-gray-300">High Usage</span>
          </div>
          <p className="text-2xl font-bold text-gray-50">{highUsageNodes}</p>
          <p className="text-xs text-gray-300 mt-1">&gt; 75% used</p>
        </div>
      </div>

      {/* Enhanced Storage Controls */}
      <EnhancedStorageControls
        storageType="scratch"
        selectedFiles={[]}
        onUploadComplete={loadData}
        onDownloadComplete={() => console.log('Download complete')}
      />

      {/* Action Bar */}
      <div className="flex items-center justify-between gap-3">
        <div className="flex-1 relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
          <input
            type="text"
            placeholder="Search by node, directory, or owner..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full pl-10 pr-4 py-2 bg-gray-700 border border-gray-500 rounded-lg text-gray-50 placeholder-gray-300 focus:outline-none focus:border-blue-400 focus:ring-1 focus:ring-blue-400"
          />
        </div>

        {totalSelected > 0 && (
          <div className="flex items-center gap-2">
            <span className="text-sm text-gray-300 font-medium">{totalSelected} selected</span>
            <button
              onClick={handleMultiNodeTransfer}
              className="flex items-center gap-2 px-4 py-2 bg-purple-500/20 hover:bg-purple-500/30 text-purple-200 rounded-lg transition font-medium"
              title="Transfer to multiple nodes in parallel"
            >
              <Server className="w-4 h-4" />
              Multi-Node Transfer
            </button>
            <button
              onClick={handleMoveToData}
              className="flex items-center gap-2 px-4 py-2 bg-blue-500/20 hover:bg-blue-500/30 text-blue-200 rounded-lg transition font-medium"
            >
              <MoveRight className="w-4 h-4" />
              Move to /data
            </button>
            <button
              onClick={handleDelete}
              className="flex items-center gap-2 px-4 py-2 bg-red-500/20 hover:bg-red-500/30 text-red-200 rounded-lg transition font-medium"
            >
              <Trash2 className="w-4 h-4" />
              Delete
            </button>
          </div>
        )}

        <button 
          className="flex items-center gap-2 px-4 py-2 bg-gray-700 hover:bg-gray-600 border border-gray-500 rounded-lg text-gray-50 transition font-medium"
          onClick={handleRefresh}
          disabled={loading}
        >
          <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
          Refresh
        </button>
      </div>

      {/* Empty State */}
      {!loading && nodes.length === 0 && (
        <div className="bg-gray-800 rounded-lg border border-gray-600 p-12 text-center">
          <Server className="w-16 h-16 text-gray-500 mx-auto mb-4" />
          <h3 className="text-xl font-bold text-gray-50 mb-2">No Compute Nodes Found</h3>
          <p className="text-gray-300 mb-4">
            {isProduction 
              ? 'Unable to find any compute nodes. This could be due to:'
              : 'Start in production mode to see real nodes.'
            }
          </p>
          {isProduction && (
            <div className="bg-gray-700/50 rounded-lg p-4 text-left max-w-md mx-auto space-y-2 text-sm text-gray-300">
              <div>1. Slurm is not running or configured</div>
              <div className="pl-4 text-xs">
                → Check: <code className="bg-gray-600 px-1 rounded">sinfo -N</code>
              </div>
              <div>2. SSH keys not configured for nodes</div>
              <div className="pl-4 text-xs">
                → Setup: <code className="bg-gray-600 px-1 rounded">ssh-copy-id node-01</code>
              </div>
              <div>3. Backend unable to reach nodes</div>
              <div className="pl-4 text-xs">
                → Check: <code className="bg-gray-600 px-1 rounded">tail -f backend.log</code>
              </div>
            </div>
          )}
        </div>
      )}

      {/* Nodes List */}
      {nodes.length > 0 && (
        <div className="space-y-3">
          {filteredNodes.map((node) => (
            <div key={node.nodeId} className="bg-gray-800 rounded-lg border border-gray-600 overflow-hidden">
              {/* Node Header */}
              <div className="flex items-center justify-between p-4">
                <div 
                  className="flex items-center gap-3 flex-1 cursor-pointer hover:opacity-80 transition"
                  onClick={() => toggleNodeExpansion(node.nodeId)}
                >
                  {expandedNodes.has(node.nodeId) ? (
                    <ChevronDown className="w-5 h-5 text-gray-400" />
                  ) : (
                    <ChevronRight className="w-5 h-5 text-gray-400" />
                  )}
                  <Server className={`w-5 h-5 ${node.status === 'online' ? 'text-green-400' : 'text-red-400'}`} />
                  <div>
                    <div className="flex items-center gap-2">
                      <span className="text-gray-50 font-semibold">{node.nodeName}</span>
                      <span className={`text-xs px-2 py-0.5 rounded font-medium ${getStatusColor(node.status)}`}>
                        {node.status}
                      </span>
                    </div>
                    <span className="text-xs text-gray-300">
                      {node.directories.length} directories · {node.fileCount.toLocaleString()} files
                    </span>
                  </div>
                </div>

                <div className="flex items-center gap-4">
                  <button
                    onClick={() => setBrowsingNode(node)}
                    className="flex items-center gap-1 px-3 py-1.5 text-xs bg-blue-500/20 hover:bg-blue-500/30 text-blue-300 rounded transition"
                  >
                    <Eye className="w-3 h-3" />
                    Browse
                  </button>

                  <div className="text-right">
                    <p className="text-sm text-gray-50 font-medium">{node.usedSpace} / {node.totalSpace}</p>
                    <p className="text-xs text-gray-300">{node.availableSpace} available</p>
                  </div>
                  <div className="w-32">
                    <div className="flex items-center justify-between text-xs text-gray-400 mb-1">
                      <span>{node.usagePercent}%</span>
                    </div>
                    <div className="bg-gray-600 rounded-full h-2">
                      <div 
                        className={`${getUsageColor(node.usagePercent)} rounded-full h-2 transition-all`}
                        style={{ width: `${node.usagePercent}%` }}
                      />
                    </div>
                  </div>
                </div>
              </div>

              {/* Directories */}
              {expandedNodes.has(node.nodeId) && node.directories.length > 0 && (
                <div className="border-t border-gray-600">
                  {node.directories.map((dir) => (
                    <div 
                      key={dir.id}
                      className="flex items-center justify-between p-4 hover:bg-gray-700 transition border-b border-gray-600/50 last:border-b-0"
                    >
                      <div className="flex items-center gap-3 flex-1">
                        <input
                          type="checkbox"
                          checked={selectedItems.has(dir.id)}
                          onChange={() => toggleSelection(dir.id)}
                          className="w-4 h-4 rounded border-gray-500 text-blue-500 focus:ring-blue-500 focus:ring-offset-0"
                        />
                        <Folder className="w-4 h-4 text-blue-400" />
                        <div className="flex-1">
                          <div className="flex items-center gap-2">
                            <span className="text-sm text-gray-50 font-medium">{dir.name}</span>
                            {dir.jobId && (
                              <span className="text-xs px-2 py-0.5 bg-purple-500/30 text-purple-200 rounded font-medium">
                                Job #{dir.jobId}
                              </span>
                            )}
                          </div>
                          <div className="flex items-center gap-3 mt-1">
                            <span className="text-xs text-gray-300 font-mono">{dir.path}</span>
                            <span className="text-xs text-gray-400">•</span>
                            <span className="text-xs text-gray-300">Owner: {dir.owner}</span>
                            {dir.group && (
                              <>
                                <span className="text-xs text-gray-400">•</span>
                                <span className="text-xs text-gray-300">Group: {dir.group}</span>
                              </>
                            )}
                            <span className="text-xs text-gray-400">•</span>
                            <span className="text-xs text-gray-300">{dir.createdAt}</span>
                          </div>
                        </div>
                      </div>

                      <div className="flex items-center gap-4">
                        <div className="text-right">
                          <p className="text-sm text-gray-50 font-medium">{dir.size}</p>
                          <p className="text-xs text-gray-300">{dir.fileCount.toLocaleString()} files</p>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              )}

              {/* Empty directories message */}
              {expandedNodes.has(node.nodeId) && node.directories.length === 0 && (
                <div className="border-t border-gray-600 p-4 text-center text-sm text-gray-400">
                  No directories found in /scratch
                </div>
              )}
            </div>
          ))}
        </div>
      )}

      {/* Move to /data Modal */}
      {showMoveModal && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <div className="bg-gray-800 rounded-lg p-6 max-w-md w-full mx-4 border border-gray-700">
            <div className="flex items-center gap-3 mb-4">
              <div className="p-2 bg-blue-500/20 rounded-lg">
                <MoveRight className="w-6 h-6 text-blue-400" />
              </div>
              <h3 className="text-xl font-bold text-gray-50">Move to /data</h3>
            </div>
            
            <p className="text-gray-200 mb-4">
              Move {totalSelected} selected {totalSelected === 1 ? 'directory' : 'directories'} to shared storage (/data)?
            </p>

            <div className="bg-blue-900/40 border border-blue-400/50 rounded-lg p-3 mb-4">
              <p className="text-sm text-blue-200">
                ℹ️ Files will be transferred to /data and remain accessible from all nodes. 
                Original files in /scratch will be removed after successful transfer.
              </p>
            </div>

            <div className="mb-4">
              <label className="block text-sm text-gray-200 font-medium mb-2">Destination Path</label>
              <input
                type="text"
                defaultValue="/data/from_scratch/"
                className="w-full px-3 py-2 bg-gray-700 border border-gray-500 rounded-lg text-gray-50 focus:outline-none focus:border-blue-400 focus:ring-1 focus:ring-blue-400"
              />
            </div>

            <div className="flex gap-3">
              <button
                onClick={() => setShowMoveModal(false)}
                className="flex-1 px-4 py-2 border border-gray-500 rounded-lg text-gray-50 hover:bg-gray-700 transition font-medium"
              >
                Cancel
              </button>
              <button
                onClick={confirmMove}
                className="flex-1 px-4 py-2 bg-blue-500 hover:bg-blue-600 text-white rounded-lg transition font-medium"
              >
                Move Files
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Delete Confirmation Modal */}
      {showDeleteModal && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <div className="bg-gray-800 rounded-lg p-6 max-w-md w-full mx-4 border border-gray-700">
            <div className="flex items-center gap-3 mb-4">
              <div className="p-2 bg-red-500/20 rounded-lg">
                <Trash2 className="w-6 h-6 text-red-400" />
              </div>
              <h3 className="text-xl font-bold text-gray-50">Delete Directories</h3>
            </div>
            
            <p className="text-gray-400 mb-4">
              Permanently delete {totalSelected} selected {totalSelected === 1 ? 'directory' : 'directories'}?
            </p>

            <div className="bg-red-900/40 border border-red-400/50 rounded-lg p-3 mb-4">
              <p className="text-sm text-red-200">
                ⚠️ This action cannot be undone. All files in the selected directories will be permanently removed from /scratch storage.
              </p>
            </div>

            <div className="flex gap-3">
              <button
                onClick={() => setShowDeleteModal(false)}
                className="flex-1 px-4 py-2 border border-gray-600 rounded-lg text-white hover:bg-gray-700 transition"
              >
                Cancel
              </button>
              <button
                onClick={confirmDelete}
                className="flex-1 px-4 py-2 bg-red-500 hover:bg-red-600 text-white rounded-lg transition font-medium"
              >
                Delete
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Multi-Node Transfer Modal */}
      {showMultiTransfer && transferSource && (
        <MultiNodeTransfer
          sourcePath={transferSource.path}
          sourceNode={transferSource.node}
          availableNodes={nodes.map(n => n.nodeName).filter(n => n !== transferSource.node)}
          onTransferComplete={(results) => {
            console.log('Multi-node transfer complete:', results);
            loadData();
          }}
          onClose={() => {
            setShowMultiTransfer(false);
            setTransferSource(null);
          }}
        />
      )}

      {/* Footer Info */}
      <div className="flex items-center justify-between text-xs text-gray-300">
        <span>
          {filteredNodes.length > 0 
            ? `Showing ${filteredNodes.length} of ${nodes.length} nodes`
            : 'No nodes to display'
          }
        </span>
        <span>Local storage on each compute node</span>
      </div>
    </div>
  );
};

export default ScratchStorageView;
