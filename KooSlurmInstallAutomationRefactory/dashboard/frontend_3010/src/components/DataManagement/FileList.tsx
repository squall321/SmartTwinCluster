import React, { useState } from 'react';
import {
  File,
  Folder,
  FolderOpen,
  Image,
  FileText,
  FileCode,
  Database,
  Archive,
  Music,
  Video,
  ChevronDown,
  ChevronRight,
  MoreVertical
} from 'lucide-react';
import { FileItem, SortField, SortDirection } from '../../types';

interface FileListProps {
  files: FileItem[];
  selectedFiles: Set<string>;
  onFileClick: (file: FileItem) => void;
  onFileSelect: (fileId: string) => void;
  onSelectAll: () => void;
}

const FileList: React.FC<FileListProps> = ({
  files,
  selectedFiles,
  onFileClick,
  onFileSelect,
  onSelectAll
}) => {
  const [sortField, setSortField] = useState<SortField>('name');
  const [sortDirection, setSortDirection] = useState<SortDirection>('asc');

  const getFileIcon = (file: FileItem) => {
    if (file.type === 'directory') {
      return <Folder className="w-5 h-5 text-blue-400" />;
    }

    const ext = file.extension?.toLowerCase();
    switch (ext) {
      case '.png':
      case '.jpg':
      case '.jpeg':
      case '.gif':
      case '.svg':
        return <Image className="w-5 h-5 text-green-400" />;
      case '.txt':
      case '.md':
      case '.log':
        return <FileText className="w-5 h-5 text-gray-400" />;
      case '.py':
      case '.js':
      case '.jsx':
      case '.ts':
      case '.tsx':
      case '.cpp':
      case '.c':
      case '.java':
        return <FileCode className="w-5 h-5 text-purple-400" />;
      case '.csv':
      case '.json':
      case '.xml':
      case '.yaml':
        return <Database className="w-5 h-5 text-yellow-400" />;
      case '.zip':
      case '.tar':
      case '.gz':
      case '.rar':
        return <Archive className="w-5 h-5 text-orange-400" />;
      case '.mp3':
      case '.wav':
      case '.flac':
        return <Music className="w-5 h-5 text-pink-400" />;
      case '.mp4':
      case '.avi':
      case '.mkv':
      case '.mov':
        return <Video className="w-5 h-5 text-red-400" />;
      default:
        return <File className="w-5 h-5 text-gray-400" />;
    }
  };

  const handleSort = (field: SortField) => {
    if (sortField === field) {
      setSortDirection(sortDirection === 'asc' ? 'desc' : 'asc');
    } else {
      setSortField(field);
      setSortDirection('asc');
    }
  };

  const sortedFiles = [...files].sort((a, b) => {
    // Always show directories first
    if (a.type === 'directory' && b.type !== 'directory') return -1;
    if (a.type !== 'directory' && b.type === 'directory') return 1;

    let comparison = 0;
    switch (sortField) {
      case 'name':
        comparison = a.name.localeCompare(b.name);
        break;
      case 'size':
        comparison = a.sizeBytes - b.sizeBytes;
        break;
      case 'modified':
        comparison = new Date(a.modifiedAt).getTime() - new Date(b.modifiedAt).getTime();
        break;
      case 'owner':
        comparison = a.owner.localeCompare(b.owner);
        break;
      case 'type':
        comparison = (a.extension || '').localeCompare(b.extension || '');
        break;
    }

    return sortDirection === 'asc' ? comparison : -comparison;
  });

  const formatDate = (dateStr: string) => {
    const date = new Date(dateStr);
    const now = new Date();
    const diffMs = now.getTime() - date.getTime();
    const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));

    if (diffDays === 0) return 'Today';
    if (diffDays === 1) return 'Yesterday';
    if (diffDays < 7) return `${diffDays} days ago`;
    
    return date.toLocaleDateString('en-US', { 
      month: 'short', 
      day: 'numeric',
      year: date.getFullYear() !== now.getFullYear() ? 'numeric' : undefined
    });
  };

  const SortHeader: React.FC<{ field: SortField; children: React.ReactNode }> = ({ field, children }) => (
    <th 
      className="px-4 py-3 text-left cursor-pointer hover:bg-gray-600/50 transition"
      onClick={() => handleSort(field)}
    >
      <div className="flex items-center gap-2">
        <span className="text-xs font-medium text-gray-300 uppercase tracking-wider">
          {children}
        </span>
        {sortField === field && (
          sortDirection === 'asc' 
            ? <ChevronDown className="w-4 h-4 text-purple-400" />
            : <ChevronRight className="w-4 h-4 text-purple-400 rotate-180" />
        )}
      </div>
    </th>
  );

  return (
    <div className="bg-gray-800 rounded-lg border border-gray-600 overflow-hidden">
      <div className="overflow-x-auto">
        <table className="w-full">
          <thead className="bg-gray-700 border-b border-gray-600">
            <tr>
              <th className="px-4 py-3 w-12">
                <input
                  type="checkbox"
                  checked={selectedFiles.size === files.length && files.length > 0}
                  onChange={onSelectAll}
                  className="w-4 h-4 rounded border-gray-500 text-purple-500 focus:ring-purple-500 focus:ring-offset-0"
                />
              </th>
              <SortHeader field="name">Name</SortHeader>
              <SortHeader field="size">Size</SortHeader>
              <SortHeader field="owner">Owner</SortHeader>
              <SortHeader field="type">Type</SortHeader>
              <th className="px-4 py-3 text-left">
                <span className="text-xs font-medium text-gray-300 uppercase tracking-wider">
                  Permissions
                </span>
              </th>
              <SortHeader field="modified">Modified</SortHeader>
              <th className="px-4 py-3 w-12"></th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-600">
            {sortedFiles.map((file) => (
              <tr
                key={file.id}
                className={`hover:bg-gray-700/50 transition ${
                  selectedFiles.has(file.id) ? 'bg-gray-700/30' : ''
                }`}
              >
                <td className="px-4 py-3">
                  <input
                    type="checkbox"
                    checked={selectedFiles.has(file.id)}
                    onChange={() => onFileSelect(file.id)}
                    className="w-4 h-4 rounded border-gray-500 text-purple-500 focus:ring-purple-500 focus:ring-offset-0"
                    onClick={(e) => e.stopPropagation()}
                  />
                </td>
                <td 
                  className="px-4 py-3 cursor-pointer"
                  onClick={() => onFileClick(file)}
                >
                  <div className="flex items-center gap-3">
                    {getFileIcon(file)}
                    <div>
                      <div className="text-sm text-gray-50 font-medium hover:text-purple-300 transition">
                        {file.name}
                      </div>
                      {file.type === 'directory' && (
                        <div className="text-xs text-gray-400">
                          Directory
                        </div>
                      )}
                    </div>
                  </div>
                </td>
                <td className="px-4 py-3">
                  <span className="text-sm text-gray-200">
                    {file.type === 'directory' ? '-' : file.size}
                  </span>
                </td>
                <td className="px-4 py-3">
                  <div>
                    <div className="text-sm text-gray-200">{file.owner}</div>
                    <div className="text-xs text-gray-400">{file.group}</div>
                  </div>
                </td>
                <td className="px-4 py-3">
                  <span className="text-sm text-gray-300">
                    {file.type === 'directory' ? 'Folder' : (file.extension || 'File')}
                  </span>
                </td>
                <td className="px-4 py-3">
                  <span className="text-xs text-gray-400 font-mono">
                    {file.permissions}
                  </span>
                </td>
                <td className="px-4 py-3">
                  <span className="text-sm text-gray-300">
                    {formatDate(file.modifiedAt)}
                  </span>
                </td>
                <td className="px-4 py-3">
                  <button className="p-1 hover:bg-gray-600 rounded transition">
                    <MoreVertical className="w-4 h-4 text-gray-400" />
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {files.length === 0 && (
        <div className="text-center py-12">
          <Folder className="w-12 h-12 text-gray-500 mx-auto mb-3" />
          <p className="text-gray-400">This directory is empty</p>
        </div>
      )}

      {/* Footer */}
      <div className="bg-gray-700/50 border-t border-gray-600 px-4 py-3">
        <div className="flex items-center justify-between text-xs text-gray-300">
          <span>
            {files.length} items
            {selectedFiles.size > 0 && ` · ${selectedFiles.size} selected`}
          </span>
          <span>
            {files.filter(f => f.type === 'directory').length} folders · {' '}
            {files.filter(f => f.type === 'file').length} files
          </span>
        </div>
      </div>
    </div>
  );
};

export default FileList;
