import React, { useState } from 'react';
import {
  Download,
  Trash2,
  MoveRight,
  Copy,
  RefreshCw,
  Upload,
  Search,
  Filter,
  CheckSquare,
  Square
} from 'lucide-react';
import { FileItem } from '../../types';

interface FileToolbarProps {
  selectedCount: number;
  currentPath: string;
  storageType: 'shared' | 'scratch';
  onRefresh: () => void;
  onSelectAll: () => void;
  selectedFiles: FileItem[];
}

const FileToolbar: React.FC<FileToolbarProps> = ({
  selectedCount,
  currentPath,
  storageType,
  onRefresh,
  onSelectAll,
  selectedFiles
}) => {
  const [searchQuery, setSearchQuery] = useState('');
  const [showMoveModal, setShowMoveModal] = useState(false);
  const [showDeleteModal, setShowDeleteModal] = useState(false);

  const handleMove = () => {
    console.log('Moving files:', selectedFiles);
    setShowMoveModal(true);
  };

  const handleCopy = () => {
    console.log('Copying files:', selectedFiles);
  };

  const handleDelete = () => {
    console.log('Deleting files:', selectedFiles);
    setShowDeleteModal(true);
  };

  const handleDownload = () => {
    console.log('Downloading files:', selectedFiles);
  };

  const canMoveToData = storageType === 'scratch' && selectedCount > 0;

  return (
    <>
      <div className="bg-gray-800 rounded-lg border border-gray-600 p-4">
        <div className="flex items-center justify-between gap-4">
          {/* Left: Search */}
          <div className="flex-1 max-w-md relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
            <input
              type="text"
              placeholder="Search files..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-full pl-10 pr-4 py-2 bg-gray-700 border border-gray-500 rounded-lg text-gray-50 placeholder-gray-400 focus:outline-none focus:border-purple-400 focus:ring-1 focus:ring-purple-400 text-sm"
            />
          </div>

          {/* Middle: Selection info */}
          {selectedCount > 0 && (
            <div className="flex items-center gap-2 text-sm text-gray-300">
              <CheckSquare className="w-4 h-4 text-purple-400" />
              <span className="font-medium">{selectedCount} selected</span>
            </div>
          )}

          {/* Right: Actions */}
          <div className="flex items-center gap-2">
            {selectedCount > 0 ? (
              <>
                {canMoveToData && (
                  <button
                    onClick={handleMove}
                    className="flex items-center gap-2 px-3 py-2 bg-blue-500/20 hover:bg-blue-500/30 text-blue-300 rounded-lg transition text-sm font-medium"
                  >
                    <MoveRight className="w-4 h-4" />
                    Move to /data
                  </button>
                )}
                <button
                  onClick={handleCopy}
                  className="flex items-center gap-2 px-3 py-2 bg-gray-700 hover:bg-gray-600 border border-gray-500 rounded-lg text-gray-50 transition text-sm"
                >
                  <Copy className="w-4 h-4" />
                  Copy
                </button>
                <button
                  onClick={handleDownload}
                  className="flex items-center gap-2 px-3 py-2 bg-gray-700 hover:bg-gray-600 border border-gray-500 rounded-lg text-gray-50 transition text-sm"
                >
                  <Download className="w-4 h-4" />
                  Download
                </button>
                <button
                  onClick={handleDelete}
                  className="flex items-center gap-2 px-3 py-2 bg-red-500/20 hover:bg-red-500/30 text-red-300 rounded-lg transition text-sm"
                >
                  <Trash2 className="w-4 h-4" />
                  Delete
                </button>
              </>
            ) : (
              <>
                <button className="flex items-center gap-2 px-3 py-2 bg-gray-700 hover:bg-gray-600 border border-gray-500 rounded-lg text-gray-50 transition text-sm">
                  <Upload className="w-4 h-4" />
                  Upload
                </button>
                <button className="flex items-center gap-2 px-3 py-2 bg-gray-700 hover:bg-gray-600 border border-gray-500 rounded-lg text-gray-50 transition text-sm">
                  <Filter className="w-4 h-4" />
                  Filter
                </button>
              </>
            )}
            <button
              onClick={onRefresh}
              className="p-2 bg-gray-700 hover:bg-gray-600 border border-gray-500 rounded-lg text-gray-50 transition"
              title="Refresh"
            >
              <RefreshCw className="w-4 h-4" />
            </button>
          </div>
        </div>
      </div>

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
              Move {selectedCount} selected {selectedCount === 1 ? 'item' : 'items'} to shared storage?
            </p>

            <div className="bg-blue-900/30 border border-blue-400/30 rounded-lg p-3 mb-4">
              <p className="text-sm text-blue-200">
                ℹ️ Files will be moved to /data and accessible from all nodes. 
                Original files will be removed from /scratch after successful transfer.
              </p>
            </div>

            <div className="mb-4">
              <label className="block text-sm text-gray-200 font-medium mb-2">
                Destination Path
              </label>
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
                onClick={() => {
                  console.log('Confirmed move');
                  setShowMoveModal(false);
                }}
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
              <h3 className="text-xl font-bold text-gray-50">Delete Files</h3>
            </div>

            <p className="text-gray-200 mb-4">
              Permanently delete {selectedCount} selected {selectedCount === 1 ? 'item' : 'items'}?
            </p>

            <div className="bg-red-900/30 border border-red-400/30 rounded-lg p-3 mb-4">
              <p className="text-sm text-red-200">
                ⚠️ This action cannot be undone. All selected files and directories will be permanently removed.
              </p>
            </div>

            <div className="flex gap-3">
              <button
                onClick={() => setShowDeleteModal(false)}
                className="flex-1 px-4 py-2 border border-gray-500 rounded-lg text-gray-50 hover:bg-gray-700 transition font-medium"
              >
                Cancel
              </button>
              <button
                onClick={() => {
                  console.log('Confirmed delete');
                  setShowDeleteModal(false);
                }}
                className="flex-1 px-4 py-2 bg-red-500 hover:bg-red-600 text-white rounded-lg transition font-medium"
              >
                Delete
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
};

export default FileToolbar;
