import React, { useState, useEffect } from 'react';
import {
  Folder,
  FolderOpen,
  File,
  ChevronRight,
  Home,
  Database,
  HardDrive,
  Loader,
  Download,
  Upload,
  Trash2,
  Copy,
  Move
} from 'lucide-react';
import { FileItem, BreadcrumbItem } from '../../types';
import { generateMockFiles } from '../../data/mockStorageData';
import FileList from './FileList';
import FileToolbar from './FileToolbar';
import FileDownload from './FileDownload';
import FileUpload from './FileUpload';
import storageApi from '../../utils/storageApi';

interface FileBrowserProps {
  rootPath: string;
  rootLabel: string;
  storageType: 'shared' | 'scratch';
  selectedNode?: string;
}

const FileBrowser: React.FC<FileBrowserProps> = ({ 
  rootPath, 
  rootLabel, 
  storageType,
  selectedNode 
}) => {
  const [currentPath, setCurrentPath] = useState(rootPath);
  const [files, setFiles] = useState<FileItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [selectedFiles, setSelectedFiles] = useState<Set<string>>(new Set());
  const [breadcrumbs, setBreadcrumbs] = useState<BreadcrumbItem[]>([
    { name: rootLabel, path: rootPath }
  ]);
  const [showUpload, setShowUpload] = useState(false);
  const [showDownloadModal, setShowDownloadModal] = useState(false);
  const [downloadTarget, setDownloadTarget] = useState<FileItem | null>(null);

  // Load files for current path
  useEffect(() => {
    loadFiles(currentPath);
  }, [currentPath]);

  const loadFiles = async (path: string) => {
    setLoading(true);
    try {
      const response = await storageApi.listFiles(path, storageType);
      
      if (response.success) {
        if (response.mode === 'production' && response.data) {
          const apiFiles = response.data as any[];
          if (apiFiles.length > 0) {
            setFiles(apiFiles);
          } else {
            const mockFiles = generateMockFiles(path);
            setFiles(mockFiles);
          }
        } else {
          const mockFiles = generateMockFiles(path);
          setFiles(mockFiles);
        }
      } else {
        console.warn('API call failed, using mock data:', response.error);
        const mockFiles = generateMockFiles(path);
        setFiles(mockFiles);
      }
    } catch (error) {
      console.error('Failed to load files:', error);
      const mockFiles = generateMockFiles(path);
      setFiles(mockFiles);
    } finally {
      setLoading(false);
    }
  };

  const navigateToPath = (path: string) => {
    setCurrentPath(path);
    setSelectedFiles(new Set());
    
    const parts = path.replace(rootPath, '').split('/').filter(Boolean);
    const newBreadcrumbs: BreadcrumbItem[] = [
      { name: rootLabel, path: rootPath }
    ];
    
    let accPath = rootPath;
    parts.forEach(part => {
      accPath += `/${part}`;
      newBreadcrumbs.push({ name: part, path: accPath });
    });
    
    setBreadcrumbs(newBreadcrumbs);
  };

  const handleFileClick = (file: FileItem) => {
    if (file.type === 'directory') {
      navigateToPath(file.path);
    } else {
      // 파일 클릭 시 다운로드 모달 표시
      setDownloadTarget(file);
      setShowDownloadModal(true);
    }
  };

  const handleFileSelect = (fileId: string) => {
    const newSelected = new Set(selectedFiles);
    if (newSelected.has(fileId)) {
      newSelected.delete(fileId);
    } else {
      newSelected.add(fileId);
    }
    setSelectedFiles(newSelected);
  };

  const handleSelectAll = () => {
    if (selectedFiles.size === files.length) {
      setSelectedFiles(new Set());
    } else {
      setSelectedFiles(new Set(files.map(f => f.id)));
    }
  };

  const handleRefresh = () => {
    loadFiles(currentPath);
    setSelectedFiles(new Set());
  };

  const handleBulkDownload = () => {
    if (selectedFiles.size === 0) return;
    
    const filesToDownload = files.filter(f => selectedFiles.has(f.id));
    // 첫 번째 파일 다운로드 (실제로는 일괄 다운로드 API 호출)
    if (filesToDownload.length > 0) {
      setDownloadTarget(filesToDownload[0]);
      setShowDownloadModal(true);
    }
  };

  const handleDelete = async () => {
    if (selectedFiles.size === 0) return;
    
    if (!confirm(`Delete ${selectedFiles.size} selected item(s)?`)) return;
    
    try {
      // API 호출하여 삭제
      const filesToDelete = files.filter(f => selectedFiles.has(f.id));
      
      // Mock: 선택된 파일 제거
      setFiles(files.filter(f => !selectedFiles.has(f.id)));
      setSelectedFiles(new Set());
      
      alert(`${filesToDelete.length} item(s) deleted successfully`);
    } catch (error) {
      console.error('Delete failed:', error);
      alert('Failed to delete files');
    }
  };

  const getIcon = () => {
    if (storageType === 'shared') {
      return <Database className="w-5 h-5 text-purple-400" />;
    }
    return <HardDrive className="w-5 h-5 text-blue-400" />;
  };

  const selectedFilesData = files.filter(f => selectedFiles.has(f.id));

  return (
    <div className="space-y-4">
      {/* Header with breadcrumbs */}
      <div className="bg-gray-800 rounded-lg border border-gray-600 p-4">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2 text-sm">
            {getIcon()}
            {breadcrumbs.map((crumb, index) => (
              <React.Fragment key={crumb.path}>
                {index > 0 && <ChevronRight className="w-4 h-4 text-gray-500" />}
                <button
                  onClick={() => navigateToPath(crumb.path)}
                  className={`hover:text-gray-50 transition ${
                    index === breadcrumbs.length - 1
                      ? 'text-gray-50 font-semibold'
                      : 'text-gray-300'
                  }`}
                >
                  {index === 0 && <Home className="w-4 h-4 inline mr-1" />}
                  {crumb.name}
                </button>
              </React.Fragment>
            ))}
          </div>
          
          {/* 경로 표시 */}
          <span className="text-xs text-gray-400 font-mono">
            {currentPath}
          </span>
        </div>
      </div>

      {/* Toolbar */}
      <div className="bg-gray-800 rounded-lg border border-gray-600 p-3">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            {selectedFiles.size > 0 && (
              <>
                <span className="text-sm text-gray-300 font-medium">
                  {selectedFiles.size} selected
                </span>
                <div className="w-px h-6 bg-gray-600" />
              </>
            )}
            
            <button
              onClick={handleSelectAll}
              className="px-3 py-1.5 text-sm text-gray-300 hover:text-gray-50 hover:bg-gray-700 rounded transition"
            >
              {selectedFiles.size === files.length && files.length > 0 ? 'Deselect All' : 'Select All'}
            </button>
            
            {selectedFiles.size > 0 && (
              <>
                <button
                  onClick={handleBulkDownload}
                  className="flex items-center gap-1 px-3 py-1.5 text-sm bg-blue-500/20 hover:bg-blue-500/30 text-blue-300 rounded transition"
                >
                  <Download className="w-4 h-4" />
                  Download
                </button>
                
                <button
                  onClick={handleDelete}
                  className="flex items-center gap-1 px-3 py-1.5 text-sm bg-red-500/20 hover:bg-red-500/30 text-red-300 rounded transition"
                >
                  <Trash2 className="w-4 h-4" />
                  Delete
                </button>
              </>
            )}
          </div>

          <div className="flex items-center gap-2">
            <button
              onClick={() => setShowUpload(!showUpload)}
              className="flex items-center gap-2 px-3 py-1.5 text-sm bg-green-500/20 hover:bg-green-500/30 text-green-300 rounded transition"
            >
              <Upload className="w-4 h-4" />
              {showUpload ? 'Hide Upload' : 'Upload'}
            </button>
            
            <button
              onClick={handleRefresh}
              disabled={loading}
              className="px-3 py-1.5 text-sm text-gray-300 hover:text-gray-50 hover:bg-gray-700 rounded transition disabled:opacity-50"
            >
              {loading ? <Loader className="w-4 h-4 animate-spin" /> : 'Refresh'}
            </button>
          </div>
        </div>
      </div>

      {/* Upload Panel */}
      {showUpload && (
        <div className="bg-gray-800 rounded-lg border border-gray-600 p-4">
          <h4 className="text-sm font-semibold text-gray-50 mb-3">
            Upload to {currentPath}
          </h4>
          <FileUpload
            destination={currentPath}
            targetNodes={selectedNode ? [selectedNode] : []}
            storageType={storageType === 'shared' ? 'data' : 'scratch'}
            onUploadComplete={() => {
              setShowUpload(false);
              handleRefresh();
            }}
          />
        </div>
      )}

      {/* File List */}
      <div className="bg-gray-800 rounded-lg border border-gray-600 overflow-hidden">
        {loading ? (
          <div className="flex items-center justify-center py-12">
            <Loader className="w-8 h-8 text-blue-400 animate-spin" />
            <span className="ml-3 text-gray-300">Loading files...</span>
          </div>
        ) : files.length === 0 ? (
          <div className="text-center py-12">
            <Folder className="w-12 h-12 text-gray-500 mx-auto mb-3" />
            <p className="text-gray-400">This directory is empty</p>
            <button
              onClick={() => setShowUpload(true)}
              className="mt-4 px-4 py-2 text-sm bg-blue-500/20 hover:bg-blue-500/30 text-blue-300 rounded transition"
            >
              Upload Files
            </button>
          </div>
        ) : (
          <FileList
            files={files}
            selectedFiles={selectedFiles}
            onFileClick={handleFileClick}
            onFileSelect={handleFileSelect}
          />
        )}
      </div>

      {/* Download Modal */}
      {showDownloadModal && downloadTarget && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <div className="bg-gray-800 rounded-lg p-6 max-w-md w-full mx-4 border border-gray-700">
            <h3 className="text-lg font-bold text-gray-50 mb-4">Download File</h3>
            
            <div className="bg-gray-700/50 rounded p-3 mb-4">
              <div className="flex items-center gap-2 mb-2">
                {downloadTarget.type === 'directory' ? (
                  <Folder className="w-5 h-5 text-blue-400" />
                ) : (
                  <File className="w-5 h-5 text-gray-400" />
                )}
                <span className="text-gray-50 font-medium">{downloadTarget.name}</span>
              </div>
              <div className="text-xs text-gray-300 space-y-1">
                <div>Size: {downloadTarget.size}</div>
                <div>Path: {downloadTarget.path}</div>
              </div>
            </div>

            <div className="flex gap-3">
              <button
                onClick={() => {
                  setShowDownloadModal(false);
                  setDownloadTarget(null);
                }}
                className="flex-1 px-4 py-2 border border-gray-600 rounded text-gray-50 hover:bg-gray-700 transition"
              >
                Cancel
              </button>
              
              <FileDownload
                filePath={downloadTarget.path}
                filename={downloadTarget.name}
                storageType={storageType === 'shared' ? 'data' : 'scratch'}
                node={selectedNode}
                isDirectory={downloadTarget.type === 'directory'}
                onDownloadStart={() => {
                  console.log('Download started');
                }}
                onDownloadComplete={() => {
                  setShowDownloadModal(false);
                  setDownloadTarget(null);
                }}
                onDownloadError={(error) => {
                  alert(`Download failed: ${error}`);
                  setShowDownloadModal(false);
                  setDownloadTarget(null);
                }}
              />
            </div>
          </div>
        </div>
      )}

      {/* Footer */}
      <div className="flex items-center justify-between text-xs text-gray-400">
        <span>{files.length} item{files.length !== 1 ? 's' : ''}</span>
        {selectedFiles.size > 0 && (
          <span>{selectedFiles.size} selected</span>
        )}
      </div>
    </div>
  );
};

export default FileBrowser;
