import React, { useState, useEffect } from 'react';
import { DndProvider } from 'react-dnd';
import { HTML5Backend } from 'react-dnd-html5-backend';
import { useClusterStore } from '../store/clusterStore';
import { Sidebar, TabType } from './Sidebar';
import { GroupPanel } from './GroupPanel';
import { ClusterStats } from './ClusterStats';
import { ModeBadge } from './ModeBadge';
import { RealtimeMonitoring } from './RealtimeMonitoring';
import { JobManagement } from './JobManagement';
import { ConfigurationManager } from './ConfigurationManager';
import DataManagement from './DataManagement';
import NotificationBell from './NotificationBell';
import PrometheusMetrics from './PrometheusMetrics';
import GlobalSearch from './GlobalSearch';
import JobTemplates from './JobTemplates';
import CustomDashboard from './CustomDashboard';
import Reports from './Reports';
import ThemeToggle from './ThemeToggle';
import HealthCheck from './HealthCheck';
import NodeManagement from './NodeManagement';
import VNCSessionManager from './VNCSessionManager';
import SSHSessionManager from './SSHSessionManager';
import ApptainerCatalog from '../pages/ApptainerCatalog';
import TemplateCatalog from '../pages/TemplateCatalog';
import FileUploadPage from '../pages/FileUploadPage';
import { ErrorBoundary } from './ErrorBoundary';
import { useApiMode } from '../hooks/useApiMode';
import { useAuth } from '../contexts/AuthContext';
import { apiPost } from '../utils/api';
import {
  Save, RotateCcw, AlertCircle, FolderOpen, Plus, User, LogOut
} from 'lucide-react';
import toast, { Toaster } from 'react-hot-toast';

export const Dashboard: React.FC = () => {
  const {
    groups,
    totalNodes,
    totalCores,
    clusterName,
    hasUnsavedChanges,
    isApplying,
    applyConfiguration,
    resetChanges,
    addGroup,
    loadConfiguration,
  } = useClusterStore();

  const { mode: apiMode } = useApiMode();
  const { user, isAuthenticated, logout } = useAuth();
  const [showConfirmModal, setShowConfirmModal] = useState(false);
  const [showConfigManager, setShowConfigManager] = useState(false);
  const [showGlobalSearch, setShowGlobalSearch] = useState(false);
  const [showUserMenu, setShowUserMenu] = useState(false);
  const [activeTab, setActiveTab] = useState<TabType>('customdash');
  const [isInitialSync, setIsInitialSync] = useState(false);

  // Job template integration
  const [selectedTemplate, setSelectedTemplate] = useState<any>(null);
  const [showJobSubmitModal, setShowJobSubmitModal] = useState(false);

  const handleApply = async () => {
    setShowConfirmModal(false);
    
    const loadingToast = toast.loading('Applying configuration to Slurm...');
    
    try {
      await applyConfiguration();
      
      if (apiMode === 'mock') {
        toast.success('Configuration applied successfully (Mock Mode - No real changes)', {
          id: loadingToast,
          duration: 4000,
        });
      } else {
        toast.success('Configuration applied successfully to Slurm!', {
          id: loadingToast,
        });
      }
    } catch (error) {
      toast.error('Failed to apply configuration', {
        id: loadingToast,
      });
    }
  };

  const handleReset = () => {
    if (window.confirm('Are you sure you want to reset all changes?')) {
      resetChanges();
      toast.success('Changes reset successfully');
    }
  };

  // Auto-sync with Slurm on initial load in production mode
  useEffect(() => {
    const autoSync = async () => {
      if (apiMode === 'production' && !isInitialSync) {
        setIsInitialSync(true);
        
        try {
          const data = await apiPost<{
            success: boolean;
            mode: string;
            message: string;
            data?: any;
          }>('/api/slurm/sync-nodes');
          
          if (data.success && data.data) {
            loadConfiguration(data.data);
            console.log('✅ Auto-synced with Slurm:', data.data.totalNodes, 'nodes');
            toast.success(`Synced ${data.data.totalNodes} nodes from Slurm`, { duration: 3000 });
          } else {
            console.warn('⚠️ Auto-sync failed:', data.message);
          }
        } catch (error) {
          console.error('❌ Auto-sync error:', error);
          toast.error('Failed to auto-sync with Slurm. Using default configuration.', { duration: 3000 });
        }
      }
    };

    autoSync();
  }, [apiMode, isInitialSync, loadConfiguration]);

  // Global keyboard shortcuts
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      // Cmd/Ctrl + K: Open Global Search
      if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
        e.preventDefault();
        setShowGlobalSearch(true);
      }
    };

    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, []);

  // Get current tab title
  const getTabTitle = () => {
    const titles: Record<TabType, string> = {
      customdash: 'Custom Dashboard',
      cluster: 'Cluster Management',
      monitoring: 'Real-time Monitoring',
      prometheus: 'Prometheus Metrics',
      health: 'Health Check',
      reports: 'Reports',
      jobs: 'Job Management',
      templates: 'Job Templates',
      nodes: 'Node Management',
      data: 'Data Management',
      vnc: 'VNC Sessions',
      ssh: 'SSH Sessions',
    };
    return titles[activeTab];
  };

  return (
    <DndProvider backend={HTML5Backend}>
      <div className="flex h-screen bg-gray-100 dark:bg-gray-900 transition-colors overflow-hidden">
        <Toaster position="top-right" />
        
        {/* Sidebar */}
        <Sidebar activeTab={activeTab} onTabChange={setActiveTab} />

        {/* Main Content Area */}
        <div className="flex-1 flex flex-col overflow-hidden">
          {/* Header */}
          <header className="bg-white dark:bg-gray-800 shadow-sm transition-colors border-b border-gray-200 dark:border-gray-700">
            <div className="px-6 py-4">
              <div className="flex items-center justify-between mb-3">
                <div>
                  <h1 className="text-2xl font-bold text-gray-900 dark:text-white">{clusterName}</h1>
                  <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">
                    {totalNodes} Nodes • {totalCores.toLocaleString()} Total Cores
                  </p>
                </div>
                
                <div className="flex items-center gap-3">
                  {/* Theme Toggle */}
                  <ThemeToggle />

                  {/* Notification Bell */}
                  <NotificationBell />

                  {/* User Info with Dropdown */}
                  {isAuthenticated && user && (
                    <div className="relative">
                      <button
                        onClick={() => setShowUserMenu(!showUserMenu)}
                        className="flex items-center gap-2 px-3 py-2 border border-gray-300 dark:border-gray-600 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-700 transition"
                        title="User Menu"
                      >
                        <User size={18} className="text-gray-700 dark:text-gray-300" />
                        <div className="hidden md:flex flex-col items-start">
                          <span className="text-sm font-medium text-gray-900 dark:text-white">
                            {user.username}
                          </span>
                          <span className="text-xs text-gray-500 dark:text-gray-400">
                            {user.groups.join(', ')}
                          </span>
                        </div>
                      </button>

                      {/* User Dropdown Menu */}
                      {showUserMenu && (
                        <>
                          <div
                            className="fixed inset-0 z-10"
                            onClick={() => setShowUserMenu(false)}
                          />
                          <div className="absolute right-0 mt-2 w-64 bg-white dark:bg-gray-800 rounded-lg shadow-lg border border-gray-200 dark:border-gray-700 z-20">
                            <div className="p-4 border-b border-gray-200 dark:border-gray-700">
                              <p className="text-sm font-semibold text-gray-900 dark:text-white">
                                {user.username}
                              </p>
                              {user.email && (
                                <p className="text-xs text-gray-500 dark:text-gray-400 mt-1">
                                  {user.email}
                                </p>
                              )}
                              <div className="mt-2 flex flex-wrap gap-1">
                                {user.groups.map(group => (
                                  <span
                                    key={group}
                                    className="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-blue-100 text-blue-800 dark:bg-blue-900/30 dark:text-blue-400"
                                  >
                                    {group}
                                  </span>
                                ))}
                              </div>
                            </div>
                            <button
                              onClick={() => {
                                setShowUserMenu(false);
                                logout();
                              }}
                              className="w-full flex items-center gap-2 px-4 py-3 text-sm text-red-600 dark:text-red-400 hover:bg-gray-50 dark:hover:bg-gray-700 transition"
                            >
                              <LogOut size={16} />
                              <span>Logout</span>
                            </button>
                          </div>
                        </>
                      )}
                    </div>
                  )}

                  {/* Save/Load Button */}
                  <button
                    onClick={() => setShowConfigManager(true)}
                    className="flex items-center gap-2 px-4 py-2 border border-gray-300 dark:border-gray-600 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-700 dark:text-gray-200 transition"
                    title="Save/Load Configuration"
                  >
                    <FolderOpen size={18} />
                    <span className="hidden md:inline">Config</span>
                  </button>
                  
                  {/* Add Group Button (only in cluster tab) */}
                  {activeTab === 'cluster' && (
                    <button
                      onClick={addGroup}
                      className="flex items-center gap-2 px-4 py-2 bg-green-600 text-white rounded-lg hover:bg-green-700 transition"
                      title="Add New Group"
                    >
                      <Plus size={18} />
                      <span className="hidden md:inline">Add Group</span>
                    </button>
                  )}
                  
                  {/* Unsaved Changes Badge */}
                  {hasUnsavedChanges && activeTab === 'cluster' && (
                    <div className="flex items-center gap-2 text-amber-600 dark:text-amber-400 bg-amber-50 dark:bg-amber-900/30 px-3 py-2 rounded-lg">
                      <AlertCircle size={18} />
                      <span className="text-sm font-medium">Unsaved</span>
                    </div>
                  )}
                  
                  {/* Reset and Apply Buttons (only in cluster tab) */}
                  {activeTab === 'cluster' && (
                    <>
                      <button
                        onClick={handleReset}
                        disabled={!hasUnsavedChanges || isApplying}
                        className="flex items-center gap-2 px-4 py-2 border border-gray-300 dark:border-gray-600 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-700 dark:text-gray-200 disabled:opacity-50 disabled:cursor-not-allowed transition"
                      >
                        <RotateCcw size={18} />
                        <span className="hidden md:inline">Reset</span>
                      </button>
                      
                      <button
                        onClick={() => setShowConfirmModal(true)}
                        disabled={!hasUnsavedChanges || isApplying}
                        className="flex items-center gap-2 px-6 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed transition"
                      >
                        <Save size={18} />
                        {isApplying ? 'Applying...' : 'Apply'}
                      </button>
                    </>
                  )}
                </div>
              </div>
              
              {/* API Mode Badge */}
              <div className="flex items-center justify-between">
                <h2 className="text-lg font-semibold text-gray-700 dark:text-gray-300">
                  {getTabTitle()}
                </h2>
                <ModeBadge mode={apiMode} />
              </div>
            </div>
          </header>

          {/* Content Area */}
          <main className="flex-1 overflow-y-auto p-6">
            {/* Custom Dashboard */}
            {activeTab === 'customdash' && apiMode !== 'unknown' && (
              <CustomDashboard mode={apiMode} />
            )}

            {/* Cluster Management */}
            {activeTab === 'cluster' && (
              <>
                <ClusterStats groups={groups} />
                
                <div className="mt-6">
                  <div className="mb-4">
                    <h3 className="text-xl font-semibold text-gray-800 dark:text-gray-200">
                      Resource Groups
                    </h3>
                    <p className="text-sm text-gray-600 dark:text-gray-400">
                      Drag and drop nodes between groups to reorganize your cluster
                    </p>
                  </div>
                  
                  <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                    {groups.map((group) => (
                      <GroupPanel key={group.id} group={group} />
                    ))}
                  </div>
                </div>
              </>
            )}

            {/* Real-time Monitoring */}
            {activeTab === 'monitoring' && apiMode !== 'unknown' && (
              <RealtimeMonitoring apiMode={apiMode} />
            )}

            {/* Prometheus Metrics */}
            {activeTab === 'prometheus' && apiMode !== 'unknown' && (
              <PrometheusMetrics mode={apiMode} />
            )}

            {/* Health Check */}
            {activeTab === 'health' && (
              <HealthCheck />
            )}

            {/* Reports */}
            {activeTab === 'reports' && (
              <Reports />
            )}

            {/* Job Management */}
            {activeTab === 'jobs' && apiMode !== 'unknown' && (
              <ErrorBoundary>
                <JobManagement
                  apiMode={apiMode}
                  selectedTemplate={selectedTemplate}
                  showSubmitModal={showJobSubmitModal}
                  onCloseSubmitModal={() => {
                    setShowJobSubmitModal(false);
                    setSelectedTemplate(null);
                  }}
                />
              </ErrorBoundary>
            )}

            {/* Job Templates */}
            {activeTab === 'templates' && (
              <TemplateCatalog />
            )}

            {/* Node Management */}
            {activeTab === 'nodes' && (
              <NodeManagement />
            )}

            {/* Data Management */}
            {activeTab === 'data' && (
              <DataManagement />
            )}

            {/* VNC Sessions */}
            {activeTab === 'vnc' && (
              <VNCSessionManager />
            )}

            {/* SSH Sessions */}
            {activeTab === 'ssh' && (
              <SSHSessionManager />
            )}

            {/* Apptainer Images */}
            {activeTab === 'apptainer' && (
              <ApptainerCatalog />
            )}

            {/* File Upload */}
            {activeTab === 'upload' && (
              <FileUploadPage />
            )}
          </main>
        </div>

        {/* Configuration Manager Modal */}
        {showConfigManager && (
          <ConfigurationManager onClose={() => setShowConfigManager(false)} />  
        )}

        {/* Global Search */}
        <GlobalSearch
          isOpen={showGlobalSearch}
          onClose={() => setShowGlobalSearch(false)}
        />

        {/* Apply Confirmation Modal */}
        {showConfirmModal && (
          <div className="fixed inset-0 bg-black bg-opacity-50 dark:bg-opacity-70 flex items-center justify-center z-50">
            <div className="bg-white dark:bg-gray-800 rounded-lg p-6 max-w-md w-full mx-4">
              <h3 className="text-xl font-bold mb-4 text-gray-900 dark:text-white">Apply Configuration?</h3>
              
              {apiMode === 'mock' && (
                <div className="mb-4 p-3 bg-amber-50 dark:bg-amber-900/30 border border-amber-200 dark:border-amber-700 rounded">
                  <p className="text-sm text-amber-800 dark:text-amber-300">
                    🎭 <strong>Mock Mode:</strong> Configuration will be simulated. 
                    No actual Slurm commands will be executed.
                  </p>
                </div>
              )}
              
              <p className="text-gray-600 dark:text-gray-300 mb-6">
                {apiMode === 'production' 
                  ? 'This will apply the current configuration to your Slurm cluster. The following actions will be performed:'
                  : 'This will simulate applying the configuration:'}
              </p>
              
              <ul className="list-disc list-inside text-sm text-gray-600 dark:text-gray-400 mb-6 space-y-1">
                <li>{apiMode === 'production' ? 'Update' : 'Simulate updating'} partition configurations</li>
                <li>{apiMode === 'production' ? 'Modify' : 'Simulate modifying'} QoS settings</li>
                <li>{apiMode === 'production' ? 'Reassign' : 'Simulate reassigning'} nodes to new groups</li>
                {apiMode === 'production' && <li>Restart affected Slurm services</li>}
              </ul>
              
              <div className="flex gap-3">
                <button
                  onClick={() => setShowConfirmModal(false)}
                  className="flex-1 px-4 py-2 border border-gray-300 dark:border-gray-600 rounded hover:bg-gray-50 dark:hover:bg-gray-700 dark:text-gray-200"
                >
                  Cancel
                </button>
                <button
                  onClick={handleApply}
                  className="flex-1 px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 dark:bg-blue-500 dark:hover:bg-blue-600"
                >
                  {apiMode === 'production' ? 'Apply Configuration' : 'Simulate Apply'}
                </button>
              </div>
            </div>
          </div>
        )}
      </div>
    </DndProvider>
  );
};
