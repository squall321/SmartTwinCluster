/**
 * Template Catalog Page (Enhanced v2.0)
 * Phase 2 Frontend - Template Management
 *
 * Features:
 * - 템플릿 목록 표시 (카드 및 테이블 뷰)
 * - 카테고리/소스 필터링
 * - 검색 기능
 * - 템플릿 상세 모달
 * - YAML 미리보기 및 다운로드
 * - 📤 템플릿 업로드 (YAML 파일)
 * - 🔄 실시간 스캔 및 동기화
 * - 📊 통계 대시보드
 */

import React, { useState, useMemo, useRef } from 'react';
import { useTemplates } from '../hooks/useTemplates';
import { Template, TemplateSource } from '../types/template';
import {
  Search,
  FileText,
  Tag,
  User,
  Calendar,
  Package,
  RefreshCw,
  Upload,
  Download,
  Grid,
  List,
  Plus,
  X,
  CheckCircle,
  AlertCircle,
  Edit2,
  Trash2,
} from 'lucide-react';
import { API_CONFIG } from '../config/api.config';
import { TemplateEditor } from '../components/TemplateManagement/TemplateEditor';
import { useAuth } from '../contexts/AuthContext';

type ViewMode = 'grid' | 'table';

export const TemplateCatalog: React.FC = () => {
  const { isAdmin } = useAuth(); // Admin 권한 확인
  const [selectedSource, setSelectedSource] = useState<TemplateSource>('all');
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedTemplate, setSelectedTemplate] = useState<Template | null>(null);
  const [showDetailModal, setShowDetailModal] = useState(false);
  const [showUploadModal, setShowUploadModal] = useState(false);
  const [viewMode, setViewMode] = useState<ViewMode>('grid');
  const [uploadFile, setUploadFile] = useState<File | null>(null);
  const [uploadLoading, setUploadLoading] = useState(false);
  const [uploadError, setUploadError] = useState<string | null>(null);
  const [uploadSuccess, setUploadSuccess] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);

  // Template Editor state
  const [showEditor, setShowEditor] = useState(false);
  const [editingTemplate, setEditingTemplate] = useState<Template | null>(null);

  // Template Deletion state
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [templateToDelete, setTemplateToDelete] = useState<Template | null>(null);
  const [deleteLoading, setDeleteLoading] = useState(false);
  const [deleteError, setDeleteError] = useState<string | null>(null);

  const { templates, loading, error, refreshTemplates, scanTemplates } = useTemplates({
    source: selectedSource,
  });

  // 검색 필터링
  const filteredTemplates = useMemo(() => {
    if (!searchQuery) return templates;

    const query = searchQuery.toLowerCase();
    return templates.filter(
      (template) =>
        template.template.name.toLowerCase().includes(query) ||
        template.template.description.toLowerCase().includes(query) ||
        template.category.toLowerCase().includes(query) ||
        template.template.tags.some((tag) => tag.toLowerCase().includes(query))
    );
  }, [templates, searchQuery]);

  // 카테고리별 그룹화
  const templatesByCategory = useMemo(() => {
    const groups: Record<string, Template[]> = {};
    filteredTemplates.forEach((template) => {
      if (!groups[template.category]) {
        groups[template.category] = [];
      }
      groups[template.category].push(template);
    });
    return groups;
  }, [filteredTemplates]);

  const handleSelectTemplate = (template: Template) => {
    setSelectedTemplate(template);
    setShowDetailModal(true);
  };

  const handleCloseModal = () => {
    setShowDetailModal(false);
  };

  const handleScanTemplates = async () => {
    await scanTemplates();
  };

  const handleOpenUploadModal = () => {
    setShowUploadModal(true);
    setUploadError(null);
    setUploadSuccess(false);
    setUploadFile(null);
  };

  const handleCloseUploadModal = () => {
    setShowUploadModal(false);
    setUploadError(null);
    setUploadSuccess(false);
    setUploadFile(null);
  };

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) {
      // Validate file type
      if (!file.name.endsWith('.yaml') && !file.name.endsWith('.yml')) {
        setUploadError('Only YAML files (.yaml, .yml) are allowed');
        setUploadFile(null);
        return;
      }
      setUploadFile(file);
      setUploadError(null);
    }
  };

  const handleUploadTemplate = async () => {
    if (!uploadFile) {
      setUploadError('Please select a file');
      return;
    }

    setUploadLoading(true);
    setUploadError(null);

    try {
      const formData = new FormData();
      formData.append('file', uploadFile);
      formData.append('is_public', 'false'); // Private by default
      formData.append('user_id', localStorage.getItem('user_id') || 'anonymous');

      // Get JWT token for authentication
      const token = localStorage.getItem('jwt_token');
      const headers: HeadersInit = {};
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }
      // Don't set Content-Type for FormData - browser will set it automatically with boundary

      const response = await fetch(`${API_CONFIG.API_BASE_URL}/api/v2/templates/import`, {
        method: 'POST',
        headers,
        body: formData,
      });

      if (!response.ok) {
        const error = await response.json();
        throw new Error(error.error || 'Failed to upload template');
      }

      const result = await response.json();
      setUploadSuccess(true);

      // Refresh template list
      await refreshTemplates();

      // Close modal after 2 seconds
      setTimeout(() => {
        handleCloseUploadModal();
      }, 2000);
    } catch (error) {
      setUploadError(error instanceof Error ? error.message : 'Upload failed');
    } finally {
      setUploadLoading(false);
    }
  };

  // Template Editor handlers
  const handleCreateNew = () => {
    setEditingTemplate(null);
    setShowEditor(true);
  };

  const handleEditTemplate = (template: Template) => {
    console.log('🖊️ Edit button clicked for template:', template.template_id);
    console.log('📄 Full template object:', template);
    setEditingTemplate(template);
    setShowEditor(true);
  };

  const handleSaveTemplate = async (template: Template) => {
    await refreshTemplates();
    setShowEditor(false);
    setEditingTemplate(null);
  };

  const handleDownloadTemplate = async (template: Template) => {
    try {
      // Get JWT token for authentication
      const token = localStorage.getItem('jwt_token');
      const headers: HeadersInit = {};
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }

      const response = await fetch(
        `${API_CONFIG.API_BASE_URL}/api/v2/templates/export/${template.template_id}`,
        {
          headers,
        }
      );

      if (!response.ok) {
        throw new Error('Failed to download template');
      }

      const blob = await response.blob();
      const url = window.URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `${template.template_id}.yaml`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      window.URL.revokeObjectURL(url);
    } catch (error) {
      console.error('Download failed:', error);
      alert('Failed to download template');
    }
  };

  const handleDeleteTemplate = (template: Template) => {
    console.log('🗑️ Delete button clicked for template:', template);
    console.log('📋 Template ID:', template.template_id);
    console.log('📋 Template full object:', JSON.stringify(template, null, 2));
    setTemplateToDelete(template);
    setShowDeleteConfirm(true);
    setDeleteError(null);
  };

  const handleConfirmDelete = async () => {
    if (!templateToDelete) return;

    setDeleteLoading(true);
    setDeleteError(null);

    try {
      // Get JWT token for authentication
      const token = localStorage.getItem('jwt_token');

      const headers: HeadersInit = {};
      if (token) {
        headers['Authorization'] = `Bearer ${token}`;
      }

      // Use template.id from nested template object if template_id is not available
      const templateId = templateToDelete.template_id || templateToDelete.template?.id || templateToDelete.id;
      console.log('🔍 Attempting to delete template with ID:', templateId);
      console.log('🔍 Template object:', templateToDelete);

      if (!templateId) {
        throw new Error('Template ID not found');
      }

      const response = await fetch(
        `${API_CONFIG.API_BASE_URL}/api/v2/templates/${templateId}`,
        {
          method: 'DELETE',
          headers,
        }
      );

      if (!response.ok) {
        const error = await response.json();
        throw new Error(error.error || error.message || 'Failed to delete template');
      }

      // Refresh template list
      await refreshTemplates();

      // Close dialog
      setShowDeleteConfirm(false);
      setTemplateToDelete(null);
    } catch (error) {
      setDeleteError(error instanceof Error ? error.message : 'Delete failed');
    } finally {
      setDeleteLoading(false);
    }
  };

  const handleCancelDelete = () => {
    setShowDeleteConfirm(false);
    setTemplateToDelete(null);
    setDeleteError(null);
  };

  // 소스별 통계
  const stats = useMemo(() => {
    const official = templates.filter((t) => t.source === 'official').length;
    const community = templates.filter((t) => t.source === 'community').length;
    const privateCount = templates.filter((t) => t.source === 'private').length;
    return { official, community, private: privateCount, total: templates.length };
  }, [templates]);

  return (
    <div className="min-h-screen bg-gray-50 dark:bg-gray-900">
      {/* Header */}
      <div className="bg-white dark:bg-gray-800 shadow">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
          <div className="flex items-center justify-between">
            <div>
              <h1 className="text-3xl font-bold text-gray-900 dark:text-gray-100">
                Job Templates
              </h1>
              <p className="mt-2 text-sm text-gray-600 dark:text-gray-400">
                클러스터에서 사용 가능한 작업 템플릿 관리
              </p>
            </div>
            <div className="flex items-center space-x-3">
              <span className="inline-flex items-center px-3 py-1 rounded-full text-sm font-medium bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200">
                Phase 2
              </span>
              <button
                onClick={handleCreateNew}
                className="inline-flex items-center px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-green-600 hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500"
              >
                <Plus className="w-4 h-4 mr-2" />
                Create Template
              </button>
              <button
                onClick={handleOpenUploadModal}
                className="inline-flex items-center px-4 py-2 border border-gray-300 dark:border-gray-600 rounded-md shadow-sm text-sm font-medium text-gray-700 dark:text-gray-300 bg-white dark:bg-gray-700 hover:bg-gray-50 dark:hover:bg-gray-600 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
              >
                <Upload className="w-4 h-4 mr-2" />
                Upload YAML
              </button>
              <button
                onClick={handleScanTemplates}
                disabled={loading}
                className="inline-flex items-center px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:opacity-50"
              >
                <RefreshCw className={`w-4 h-4 mr-2 ${loading ? 'animate-spin' : ''}`} />
                Scan & Sync
              </button>
            </div>
          </div>
        </div>
      </div>

      {/* Main Content */}
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        {/* Filters and View Controls */}
        <div className="bg-white dark:bg-gray-800 rounded-lg shadow-lg p-6 mb-6">
          <div className="flex flex-col md:flex-row md:items-center md:justify-between space-y-4 md:space-y-0">
            {/* Search */}
            <div className="flex-1 max-w-lg">
              <div className="relative">
                <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-gray-400 w-5 h-5" />
                <input
                  type="text"
                  placeholder="Search templates, categories, or tags..."
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  className="w-full pl-10 pr-4 py-2 border border-gray-300 dark:border-gray-600 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent dark:bg-gray-700 dark:text-gray-100"
                />
              </div>
            </div>

            {/* View Mode Toggle */}
            <div className="flex items-center space-x-2">
              <button
                onClick={() => setViewMode('grid')}
                className={`p-2 rounded-md ${
                  viewMode === 'grid'
                    ? 'bg-blue-100 text-blue-600 dark:bg-blue-900 dark:text-blue-200'
                    : 'text-gray-400 hover:text-gray-600 dark:hover:text-gray-300'
                }`}
              >
                <Grid className="w-5 h-5" />
              </button>
              <button
                onClick={() => setViewMode('table')}
                className={`p-2 rounded-md ${
                  viewMode === 'table'
                    ? 'bg-blue-100 text-blue-600 dark:bg-blue-900 dark:text-blue-200'
                    : 'text-gray-400 hover:text-gray-600 dark:hover:text-gray-300'
                }`}
              >
                <List className="w-5 h-5" />
              </button>
            </div>
          </div>

          {/* Source Filter */}
          <div className="flex space-x-2 mt-4">
            {(['all', 'official', 'community', 'private'] as TemplateSource[]).map((source) => (
              <button
                key={source}
                onClick={() => setSelectedSource(source)}
                className={`px-4 py-2 rounded-lg text-sm font-medium transition-colors ${
                  selectedSource === source
                    ? 'bg-blue-600 text-white'
                    : 'bg-gray-200 text-gray-700 hover:bg-gray-300 dark:bg-gray-700 dark:text-gray-300 dark:hover:bg-gray-600'
                }`}
              >
                {source.charAt(0).toUpperCase() + source.slice(1)}
                {source !== 'all' && (
                  <span className="ml-2 px-2 py-0.5 text-xs rounded-full bg-white/20">
                    {source === 'official' && stats.official}
                    {source === 'community' && stats.community}
                    {source === 'private' && stats.private}
                  </span>
                )}
              </button>
            ))}
          </div>
        </div>

        {/* Statistics Cards */}
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
          <StatCard label="Official" value={stats.official} icon="📘" color="blue" />
          <StatCard label="Community" value={stats.community} icon="👥" color="green" />
          <StatCard label="Private" value={stats.private} icon="🔒" color="purple" />
          <StatCard label="Total" value={stats.total} icon="📦" color="gray" />
        </div>

        {/* Error State */}
        {error && (
          <div className="bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg p-4 mb-6">
            <div className="flex items-center">
              <AlertCircle className="w-5 h-5 text-red-600 dark:text-red-400 mr-2" />
              <p className="text-sm text-red-800 dark:text-red-200">{error}</p>
            </div>
          </div>
        )}

        {/* Loading State */}
        {loading && (
          <div className="text-center py-12">
            <div className="inline-block animate-spin rounded-full h-12 w-12 border-b-2 border-blue-600"></div>
            <p className="mt-4 text-gray-600 dark:text-gray-400">Loading templates...</p>
          </div>
        )}

        {/* Templates View */}
        {!loading && Object.keys(templatesByCategory).length === 0 && (
          <div className="text-center py-12 bg-white dark:bg-gray-800 rounded-lg shadow">
            <Package className="mx-auto h-12 w-12 text-gray-400" />
            <h3 className="mt-2 text-sm font-medium text-gray-900 dark:text-gray-100">No templates found</h3>
            <p className="mt-1 text-sm text-gray-500 dark:text-gray-400">
              {searchQuery ? 'Try different search terms' : 'Upload a template to get started'}
            </p>
            <button
              onClick={handleOpenUploadModal}
              className="mt-4 inline-flex items-center px-4 py-2 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-blue-600 hover:bg-blue-700"
            >
              <Plus className="w-4 h-4 mr-2" />
              Upload Template
            </button>
          </div>
        )}

        {/* Grid View */}
        {!loading &&
          viewMode === 'grid' &&
          Object.entries(templatesByCategory).map(([category, categoryTemplates]) => (
            <div key={category} className="mb-8">
              <h2 className="text-xl font-semibold text-gray-900 dark:text-gray-100 mb-4 capitalize flex items-center">
                <span className="w-1 h-6 bg-blue-500 mr-3 rounded"></span>
                {category} ({categoryTemplates.length})
              </h2>
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                {categoryTemplates.map((template) => (
                  <TemplateCard
                    key={template.id}
                    template={template}
                    onClick={() => handleSelectTemplate(template)}
                    onDownload={() => handleDownloadTemplate(template)}
                    onEdit={template.source !== 'official' || isAdmin ? () => handleEditTemplate(template) : undefined}
                    onDelete={template.source !== 'official' || isAdmin ? () => handleDeleteTemplate(template) : undefined}
                  />
                ))}
              </div>
            </div>
          ))}

        {/* Table View */}
        {!loading && viewMode === 'table' && (
          <div className="bg-white dark:bg-gray-800 rounded-lg shadow overflow-hidden">
            <table className="min-w-full divide-y divide-gray-200 dark:divide-gray-700">
              <thead className="bg-gray-50 dark:bg-gray-700">
                <tr>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider">
                    Name
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider">
                    Category
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider">
                    Source
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider">
                    Author
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider">
                    Version
                  </th>
                  <th className="px-6 py-3 text-right text-xs font-medium text-gray-500 dark:text-gray-300 uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody className="bg-white dark:bg-gray-800 divide-y divide-gray-200 dark:divide-gray-700">
                {filteredTemplates.map((template) => (
                  <tr
                    key={template.id}
                    className="hover:bg-gray-50 dark:hover:bg-gray-700 cursor-pointer"
                    onClick={() => handleSelectTemplate(template)}
                  >
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="text-sm font-medium text-gray-900 dark:text-gray-100">
                        {template.template.name}
                      </div>
                      <div className="text-sm text-gray-500 dark:text-gray-400 line-clamp-1">
                        {template.template.description}
                      </div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <span className="px-2 py-1 text-xs font-medium rounded-full bg-gray-100 dark:bg-gray-700 text-gray-800 dark:text-gray-200 capitalize">
                        {template.category}
                      </span>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <span
                        className={`px-2 py-1 text-xs font-medium rounded-full ${
                          template.source === 'official'
                            ? 'bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200'
                            : template.source === 'community'
                            ? 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200'
                            : 'bg-purple-100 text-purple-800 dark:bg-purple-900 dark:text-purple-200'
                        }`}
                      >
                        {template.source}
                      </span>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500 dark:text-gray-400">
                      {template.template.author}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500 dark:text-gray-400">
                      v{template.template.version}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                      {(template.source !== 'official' || isAdmin) && (
                        <button
                          onClick={(e) => {
                            e.stopPropagation();
                            handleEditTemplate(template);
                          }}
                          className="text-green-600 hover:text-green-900 dark:text-green-400 dark:hover:text-green-300 mr-4"
                          title="Edit Template"
                        >
                          <Edit2 className="w-4 h-4 inline" />
                        </button>
                      )}
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          handleDownloadTemplate(template);
                        }}
                        className="text-blue-600 hover:text-blue-900 dark:text-blue-400 dark:hover:text-blue-300 mr-4"
                        title="Download YAML"
                      >
                        <Download className="w-4 h-4 inline" />
                      </button>
                      {(template.source !== 'official' || isAdmin) && (
                        <button
                          onClick={(e) => {
                            e.stopPropagation();
                            handleDeleteTemplate(template);
                          }}
                          className="text-red-600 hover:text-red-900 dark:text-red-400 dark:hover:text-red-300 mr-4"
                          title="Delete Template"
                        >
                          <Trash2 className="w-4 h-4 inline" />
                        </button>
                      )}
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          handleSelectTemplate(template);
                        }}
                        className="text-gray-600 hover:text-gray-900 dark:text-gray-400 dark:hover:text-gray-300"
                      >
                        View
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {/* Usage Guide */}
        <div className="mt-8 bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-800 rounded-lg p-6">
          <h3 className="text-lg font-semibold text-blue-900 dark:text-blue-200 mb-3">
            💡 사용 방법
          </h3>
          <ul className="space-y-2 text-sm text-blue-700 dark:text-blue-300">
            <li className="flex items-start">
              <span className="mr-2">📤</span>
              <span>
                <strong>템플릿 업로드:</strong> Upload Template 버튼으로 YAML 파일을 업로드하세요
              </span>
            </li>
            <li className="flex items-start">
              <span className="mr-2">🔍</span>
              <span>
                <strong>템플릿 검색:</strong> 검색창에서 이름, 카테고리, 태그로 템플릿을 찾을 수 있습니다
              </span>
            </li>
            <li className="flex items-start">
              <span className="mr-2">📋</span>
              <span>
                <strong>템플릿 상세:</strong> 템플릿 카드를 클릭하여 파라미터, 필요 파일, YAML을 확인하세요
              </span>
            </li>
            <li className="flex items-start">
              <span className="mr-2">🔄</span>
              <span>
                <strong>실시간 동기화:</strong> Scan & Sync 버튼으로 /shared/templates/ 디렉토리와 동기화하세요
              </span>
            </li>
          </ul>
        </div>
      </div>

      {/* Detail Modal */}
      {showDetailModal && selectedTemplate && (
        <TemplateDetailModal
          template={selectedTemplate}
          onClose={handleCloseModal}
          onDownload={() => handleDownloadTemplate(selectedTemplate)}
        />
      )}

      {/* Upload Modal */}
      {showUploadModal && (
        <div className="fixed inset-0 z-50 overflow-y-auto">
          <div className="flex items-end justify-center min-h-screen pt-4 px-4 pb-20 text-center sm:block sm:p-0">
            {/* Backdrop */}
            <div className="fixed inset-0 bg-gray-500 bg-opacity-75 transition-opacity" onClick={handleCloseUploadModal} />

            {/* Modal */}
            <div className="inline-block align-bottom bg-white dark:bg-gray-800 rounded-lg text-left overflow-hidden shadow-xl transform transition-all sm:my-8 sm:align-middle sm:max-w-lg sm:w-full">
              <div className="bg-white dark:bg-gray-800 px-4 pt-5 pb-4 sm:p-6 sm:pb-4">
                <div className="flex items-start justify-between mb-4">
                  <h3 className="text-xl font-medium text-gray-900 dark:text-gray-100">
                    Upload Template
                  </h3>
                  <button
                    onClick={handleCloseUploadModal}
                    className="text-gray-400 hover:text-gray-500 dark:hover:text-gray-300"
                  >
                    <X className="w-6 h-6" />
                  </button>
                </div>

                {uploadSuccess ? (
                  <div className="py-8 text-center">
                    <CheckCircle className="mx-auto h-16 w-16 text-green-500" />
                    <h3 className="mt-4 text-lg font-medium text-gray-900 dark:text-gray-100">
                      Template uploaded successfully!
                    </h3>
                    <p className="mt-2 text-sm text-gray-600 dark:text-gray-400">
                      The template has been added to your private templates.
                    </p>
                  </div>
                ) : (
                  <>
                    <div className="space-y-4">
                      {/* File Input */}
                      <div>
                        <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                          Select YAML File
                        </label>
                        <input
                          ref={fileInputRef}
                          type="file"
                          accept=".yaml,.yml"
                          onChange={handleFileChange}
                          className="hidden"
                        />
                        <button
                          onClick={() => fileInputRef.current?.click()}
                          className="w-full flex items-center justify-center px-4 py-8 border-2 border-dashed border-gray-300 dark:border-gray-600 rounded-lg hover:border-blue-500 dark:hover:border-blue-400 transition-colors"
                        >
                          <div className="text-center">
                            <Upload className="mx-auto h-12 w-12 text-gray-400" />
                            <p className="mt-2 text-sm text-gray-600 dark:text-gray-400">
                              {uploadFile ? uploadFile.name : 'Click to select a YAML file'}
                            </p>
                            <p className="mt-1 text-xs text-gray-500 dark:text-gray-500">
                              Supports .yaml and .yml files
                            </p>
                          </div>
                        </button>
                      </div>

                      {/* Info Box */}
                      <div className="bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-800 rounded-lg p-4">
                        <p className="text-sm text-blue-700 dark:text-blue-300">
                          <strong>Note:</strong> Uploaded templates will be saved as private templates and stored in{' '}
                          <code className="bg-blue-100 dark:bg-blue-800 px-1 rounded">
                            /shared/templates/private/&lt;user&gt;/
                          </code>
                        </p>
                      </div>

                      {/* Error Message */}
                      {uploadError && (
                        <div className="bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg p-4">
                          <div className="flex items-center">
                            <AlertCircle className="w-5 h-5 text-red-600 dark:text-red-400 mr-2" />
                            <p className="text-sm text-red-800 dark:text-red-200">{uploadError}</p>
                          </div>
                        </div>
                      )}
                    </div>

                    <div className="mt-6 flex justify-end space-x-3">
                      <button
                        onClick={handleCloseUploadModal}
                        disabled={uploadLoading}
                        className="px-4 py-2 text-sm font-medium text-gray-700 dark:text-gray-300 bg-white dark:bg-gray-700 border border-gray-300 dark:border-gray-600 rounded-md hover:bg-gray-50 dark:hover:bg-gray-600 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:opacity-50"
                      >
                        Cancel
                      </button>
                      <button
                        onClick={handleUploadTemplate}
                        disabled={!uploadFile || uploadLoading}
                        className="px-4 py-2 text-sm font-medium text-white bg-blue-600 border border-transparent rounded-md hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:opacity-50 disabled:cursor-not-allowed"
                      >
                        {uploadLoading ? (
                          <>
                            <RefreshCw className="w-4 h-4 mr-2 inline animate-spin" />
                            Uploading...
                          </>
                        ) : (
                          <>
                            <Upload className="w-4 h-4 mr-2 inline" />
                            Upload
                          </>
                        )}
                      </button>
                    </div>
                  </>
                )}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Template Editor Modal */}
      {showEditor && (
        <TemplateEditor
          key={editingTemplate?.id || 'new'}
          template={editingTemplate}
          onClose={() => {
            setShowEditor(false);
            setEditingTemplate(null);
          }}
          onSave={handleSaveTemplate}
        />
      )}

      {/* Delete Confirmation Modal */}
      {showDeleteConfirm && templateToDelete && (
        <div className="fixed inset-0 z-50 overflow-y-auto">
          <div className="flex items-end justify-center min-h-screen pt-4 px-4 pb-20 text-center sm:block sm:p-0">
            {/* Backdrop */}
            <div className="fixed inset-0 bg-gray-500 bg-opacity-75 transition-opacity" onClick={handleCancelDelete} />

            {/* Modal */}
            <div className="inline-block align-bottom bg-white dark:bg-gray-800 rounded-lg text-left overflow-hidden shadow-xl transform transition-all sm:my-8 sm:align-middle sm:max-w-lg sm:w-full">
              <div className="bg-white dark:bg-gray-800 px-4 pt-5 pb-4 sm:p-6 sm:pb-4">
                <div className="sm:flex sm:items-start">
                  <div className="mx-auto flex-shrink-0 flex items-center justify-center h-12 w-12 rounded-full bg-red-100 dark:bg-red-900/20 sm:mx-0 sm:h-10 sm:w-10">
                    <AlertCircle className="h-6 w-6 text-red-600 dark:text-red-400" />
                  </div>
                  <div className="mt-3 text-center sm:mt-0 sm:ml-4 sm:text-left flex-1">
                    <h3 className="text-lg leading-6 font-medium text-gray-900 dark:text-gray-100">
                      Delete Template
                    </h3>
                    <div className="mt-2">
                      <p className="text-sm text-gray-500 dark:text-gray-400">
                        Are you sure you want to delete the template{' '}
                        <span className="font-semibold text-gray-900 dark:text-gray-100">
                          "{templateToDelete.template.name}"
                        </span>
                        ?
                      </p>
                      <p className="mt-2 text-sm text-gray-500 dark:text-gray-400">
                        This action will move the template to the archive. This action cannot be easily undone.
                      </p>
                    </div>

                    {/* Error Message */}
                    {deleteError && (
                      <div className="mt-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg p-3">
                        <div className="flex items-center">
                          <AlertCircle className="w-5 h-5 text-red-600 dark:text-red-400 mr-2 flex-shrink-0" />
                          <p className="text-sm text-red-800 dark:text-red-200">{deleteError}</p>
                        </div>
                      </div>
                    )}
                  </div>
                </div>
              </div>
              <div className="bg-gray-50 dark:bg-gray-700 px-4 py-3 sm:px-6 sm:flex sm:flex-row-reverse">
                <button
                  onClick={handleConfirmDelete}
                  disabled={deleteLoading}
                  className="w-full inline-flex justify-center items-center rounded-md border border-transparent shadow-sm px-4 py-2 bg-red-600 text-base font-medium text-white hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-500 sm:ml-3 sm:w-auto sm:text-sm disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  {deleteLoading ? (
                    <>
                      <RefreshCw className="w-4 h-4 mr-2 animate-spin" />
                      Deleting...
                    </>
                  ) : (
                    <>
                      <Trash2 className="w-4 h-4 mr-2" />
                      Delete
                    </>
                  )}
                </button>
                <button
                  onClick={handleCancelDelete}
                  disabled={deleteLoading}
                  className="mt-3 w-full inline-flex justify-center rounded-md border border-gray-300 dark:border-gray-600 shadow-sm px-4 py-2 bg-white dark:bg-gray-800 text-base font-medium text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 sm:mt-0 sm:ml-3 sm:w-auto sm:text-sm disabled:opacity-50"
                >
                  Cancel
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

// Stat Card Component
const StatCard: React.FC<{ label: string; value: number; icon: string; color: string }> = ({
  label,
  value,
  icon,
  color,
}) => {
  const colorClasses = {
    blue: 'bg-blue-100 dark:bg-blue-900',
    green: 'bg-green-100 dark:bg-green-900',
    purple: 'bg-purple-100 dark:bg-purple-900',
    gray: 'bg-gray-100 dark:bg-gray-800',
  };

  return (
    <div className="bg-white dark:bg-gray-800 rounded-lg shadow-md hover:shadow-lg transition-shadow p-6">
      <div className="flex items-center">
        <div
          className={`flex-shrink-0 w-14 h-14 ${
            colorClasses[color as keyof typeof colorClasses] || colorClasses.gray
          } rounded-lg flex items-center justify-center`}
        >
          <span className="text-3xl">{icon}</span>
        </div>
        <div className="ml-4">
          <p className="text-sm font-medium text-gray-600 dark:text-gray-400">{label}</p>
          <p className="text-3xl font-bold text-gray-900 dark:text-gray-100">{value}</p>
        </div>
      </div>
    </div>
  );
};

// Template Card Component (Enhanced)
const TemplateCard: React.FC<{
  template: Template;
  onClick: () => void;
  onDownload: () => void;
  onEdit?: () => void;
  onDelete?: () => void;
}> = ({ template, onClick, onDownload, onEdit, onDelete }) => {
  const sourceColors = {
    official: 'bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200',
    community: 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200',
    private: 'bg-purple-100 text-purple-800 dark:bg-purple-900 dark:text-purple-200',
  };

  return (
    <div
      onClick={onClick}
      className="bg-white dark:bg-gray-800 rounded-lg shadow-md hover:shadow-xl transition-all cursor-pointer p-6 border border-gray-200 dark:border-gray-700 hover:border-blue-300 dark:hover:border-blue-500"
    >
      <div className="flex items-start justify-between mb-3">
        <h3 className="text-lg font-semibold text-gray-900 dark:text-gray-100 flex-1 pr-2">
          {template.template.name}
        </h3>
        <span className={`px-2 py-1 rounded text-xs font-medium flex-shrink-0 ${sourceColors[template.source]}`}>
          {template.source}
        </span>
      </div>

      <p className="text-sm text-gray-600 dark:text-gray-400 mb-4 line-clamp-2 min-h-[2.5rem]">
        {template.template.description}
      </p>

      <div className="space-y-2 text-xs text-gray-500 dark:text-gray-400 mb-4">
        <div className="flex items-center">
          <User className="w-4 h-4 mr-2 flex-shrink-0" />
          <span className="truncate">{template.template.author}</span>
        </div>
        <div className="flex items-center">
          <FileText className="w-4 h-4 mr-2 flex-shrink-0" />
          <span>v{template.template.version}</span>
        </div>
        {template.template.tags.length > 0 && (
          <div className="flex items-start">
            <Tag className="w-4 h-4 mr-2 mt-0.5 flex-shrink-0" />
            <div className="flex flex-wrap gap-1">
              {template.template.tags.slice(0, 3).map((tag, idx) => (
                <span key={idx} className="px-2 py-0.5 bg-gray-100 dark:bg-gray-700 rounded text-xs">
                  {tag}
                </span>
              ))}
              {template.template.tags.length > 3 && (
                <span className="text-gray-400 text-xs">+{template.template.tags.length - 3}</span>
              )}
            </div>
          </div>
        )}
      </div>

      {/* Action Buttons */}
      <div className="flex items-center justify-between pt-4 border-t border-gray-200 dark:border-gray-700">
        <div className="flex items-center gap-2">
          {onEdit && (
            <button
              onClick={(e) => {
                e.stopPropagation();
                onEdit();
              }}
              className="inline-flex items-center px-3 py-1.5 text-xs font-medium text-green-600 dark:text-green-400 hover:text-green-800 dark:hover:text-green-300 hover:bg-green-50 dark:hover:bg-green-900/20 rounded transition-colors"
            >
              <Edit2 className="w-3.5 h-3.5 mr-1" />
              Edit
            </button>
          )}
          <button
            onClick={(e) => {
              e.stopPropagation();
              onDownload();
            }}
            className="inline-flex items-center px-3 py-1.5 text-xs font-medium text-blue-600 dark:text-blue-400 hover:text-blue-800 dark:hover:text-blue-300 hover:bg-blue-50 dark:hover:bg-blue-900/20 rounded transition-colors"
          >
            <Download className="w-3.5 h-3.5 mr-1" />
            Download
          </button>
          {onDelete && (
            <button
              onClick={(e) => {
                e.stopPropagation();
                onDelete();
              }}
              className="inline-flex items-center px-3 py-1.5 text-xs font-medium text-red-600 dark:text-red-400 hover:text-red-800 dark:hover:text-red-300 hover:bg-red-50 dark:hover:bg-red-900/20 rounded transition-colors"
            >
              <Trash2 className="w-3.5 h-3.5 mr-1" />
              Delete
            </button>
          )}
        </div>
        <span className="text-xs text-gray-400">Click for details</span>
      </div>
    </div>
  );
};

// Template Detail Modal (Enhanced)
const TemplateDetailModal: React.FC<{
  template: Template;
  onClose: () => void;
  onDownload: () => void;
}> = ({ template, onClose, onDownload }) => {
  return (
    <div className="fixed inset-0 z-50 overflow-y-auto">
      <div className="flex items-end justify-center min-h-screen pt-4 px-4 pb-20 text-center sm:block sm:p-0">
        {/* Backdrop */}
        <div className="fixed inset-0 bg-gray-500 bg-opacity-75 transition-opacity" onClick={onClose} />

        {/* Modal */}
        <div className="inline-block align-bottom bg-white dark:bg-gray-800 rounded-lg text-left overflow-hidden shadow-xl transform transition-all sm:my-8 sm:align-middle sm:max-w-4xl sm:w-full">
          <div className="bg-white dark:bg-gray-800 px-4 pt-5 pb-4 sm:p-6 sm:pb-4">
            <div className="flex items-start justify-between mb-4">
              <h3 className="text-2xl font-medium text-gray-900 dark:text-gray-100">
                {template.template.name}
              </h3>
              <button
                onClick={onClose}
                className="text-gray-400 hover:text-gray-500 dark:hover:text-gray-300"
              >
                <X className="w-6 h-6" />
              </button>
            </div>

            <div className="space-y-6">
              {/* Basic Info */}
              <div>
                <h4 className="text-base font-semibold text-gray-700 dark:text-gray-300 mb-2">Description</h4>
                <p className="text-sm text-gray-600 dark:text-gray-400">{template.template.description}</p>
              </div>

              {/* Metadata Grid */}
              <div className="grid grid-cols-2 gap-4">
                <div className="bg-gray-50 dark:bg-gray-700 rounded-lg p-4">
                  <span className="text-xs text-gray-500 dark:text-gray-400">Author</span>
                  <p className="text-sm font-medium text-gray-900 dark:text-gray-100 mt-1">
                    {template.template.author}
                  </p>
                </div>
                <div className="bg-gray-50 dark:bg-gray-700 rounded-lg p-4">
                  <span className="text-xs text-gray-500 dark:text-gray-400">Version</span>
                  <p className="text-sm font-medium text-gray-900 dark:text-gray-100 mt-1">
                    {template.template.version}
                  </p>
                </div>
                <div className="bg-gray-50 dark:bg-gray-700 rounded-lg p-4">
                  <span className="text-xs text-gray-500 dark:text-gray-400">Category</span>
                  <p className="text-sm font-medium text-gray-900 dark:text-gray-100 mt-1 capitalize">
                    {template.category}
                  </p>
                </div>
                <div className="bg-gray-50 dark:bg-gray-700 rounded-lg p-4">
                  <span className="text-xs text-gray-500 dark:text-gray-400">Source</span>
                  <p className="text-sm font-medium text-gray-900 dark:text-gray-100 mt-1 capitalize">
                    {template.source}
                  </p>
                </div>
              </div>

              {/* Tags */}
              {template.template.tags.length > 0 && (
                <div>
                  <h5 className="text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">Tags</h5>
                  <div className="flex flex-wrap gap-2">
                    {template.template.tags.map((tag, idx) => (
                      <span
                        key={idx}
                        className="px-3 py-1 text-xs bg-blue-100 dark:bg-blue-900 text-blue-800 dark:text-blue-200 rounded-full"
                      >
                        {tag}
                      </span>
                    ))}
                  </div>
                </div>
              )}

              {/* Apptainer Config */}
              {template.apptainer && (
                <div>
                  <h5 className="text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">
                    Apptainer Configuration
                  </h5>
                  <div className="bg-gray-50 dark:bg-gray-700 rounded-lg p-4 space-y-2 text-sm">
                    <div className="flex items-center justify-between">
                      <span className="text-gray-500 dark:text-gray-400">Image:</span>
                      <span className="text-gray-900 dark:text-gray-100 font-mono font-medium">
                        {template.apptainer.image_name}
                      </span>
                    </div>
                    {template.apptainer.app && (
                      <div className="flex items-center justify-between">
                        <span className="text-gray-500 dark:text-gray-400">App:</span>
                        <span className="text-gray-900 dark:text-gray-100 font-mono">
                          {template.apptainer.app}
                        </span>
                      </div>
                    )}
                  </div>
                </div>
              )}

              {/* Required Files */}
              {template.files?.input_schema?.required && template.files.input_schema.required.length > 0 && (
                <div>
                  <h5 className="text-sm font-medium text-gray-700 dark:text-gray-300 mb-2">Required Files</h5>
                  <ul className="space-y-2 bg-gray-50 dark:bg-gray-700 rounded-lg p-4">
                    {template.files.input_schema.required.map((file, idx) => (
                      <li key={idx} className="text-sm text-gray-600 dark:text-gray-400 flex items-start">
                        <span className="text-blue-500 mr-2">•</span>
                        <span>{file.description}</span>
                      </li>
                    ))}
                  </ul>
                </div>
              )}
            </div>
          </div>

          <div className="bg-gray-50 dark:bg-gray-700 px-4 py-3 sm:px-6 sm:flex sm:flex-row-reverse">
            <button
              onClick={onDownload}
              className="w-full inline-flex justify-center items-center rounded-md border border-transparent shadow-sm px-4 py-2 bg-blue-600 text-base font-medium text-white hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 sm:ml-3 sm:w-auto sm:text-sm"
            >
              <Download className="w-4 h-4 mr-2" />
              Download YAML
            </button>
            <button
              onClick={onClose}
              className="mt-3 w-full inline-flex justify-center rounded-md border border-gray-300 dark:border-gray-600 shadow-sm px-4 py-2 bg-white dark:bg-gray-800 text-base font-medium text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 sm:mt-0 sm:ml-3 sm:w-auto sm:text-sm"
            >
              Close
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};

export default TemplateCatalog;
