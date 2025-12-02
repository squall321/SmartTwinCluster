/**
 * Template Management Page
 * YAML 기반 신규 Template 시스템 관리
 *
 * 기능:
 * - Template 목록 조회
 * - Template 생성/편집/삭제
 * - Template 미리보기
 * - Template 검증
 */

import React, { useState } from 'react';
import { Plus, Search, FileText, Edit2, Trash2, Eye, Download } from 'lucide-react';
import { useTemplates } from '../../hooks/useTemplates';
import { Template } from '../../types/template';
import { TemplateEditor } from './TemplateEditor';
import { apiDelete } from '../../utils/api';
import { useAuth } from '../../contexts/AuthContext';
import toast from 'react-hot-toast';

interface TemplateManagementProps {
  mode?: 'mock' | 'production';
}

export const TemplateManagement: React.FC<TemplateManagementProps> = ({
  mode = 'production'
}) => {
  const { templates, loading, error, refetch } = useTemplates();
  const { user, isAdmin } = useAuth();
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedCategory, setSelectedCategory] = useState<string>('all');
  const [showEditor, setShowEditor] = useState(false);
  const [editingTemplate, setEditingTemplate] = useState<Template | null>(null);
  const [selectedTemplate, setSelectedTemplate] = useState<Template | null>(null);

  // Filter templates
  const filteredTemplates = templates.filter(t => {
    const matchesSearch = !searchQuery ||
      t.template_id.toLowerCase().includes(searchQuery.toLowerCase()) ||
      t.template?.name?.toLowerCase().includes(searchQuery.toLowerCase()) ||
      t.template?.description?.toLowerCase().includes(searchQuery.toLowerCase());

    const matchesCategory = selectedCategory === 'all' || t.category === selectedCategory;

    return matchesSearch && matchesCategory;
  });

  // Get unique categories
  const categories = ['all', ...Array.from(new Set(templates.map(t => t.category).filter(Boolean)))];

  // 템플릿 편집 권한 확인
  const canEdit = (template: Template): boolean => {
    if (template.source === 'official') {
      return isAdmin; // Official: admin만 편집 가능
    }
    if (template.source === 'community') {
      return true; // Community: 모든 사용자 편집 가능
    }
    if (template.source?.startsWith('private:')) {
      // Private: 본인 것만 편집 가능
      const owner = template.source.split(':')[1];
      return user?.username === owner;
    }
    return false;
  };

  // 템플릿 삭제 권한 확인
  const canDelete = (template: Template): boolean => {
    if (template.source === 'official') {
      return isAdmin; // Official: admin만 삭제 가능
    }
    if (template.source === 'community') {
      return isAdmin; // Community: admin만 삭제 가능
    }
    if (template.source?.startsWith('private:')) {
      // Private: 본인 또는 admin 삭제 가능
      const owner = template.source.split(':')[1];
      return user?.username === owner || isAdmin;
    }
    return false;
  };

  const handleCreateNew = () => {
    setEditingTemplate(null);
    setShowEditor(true);
  };

  const handleEdit = (template: Template) => {
    setEditingTemplate(template);
    setShowEditor(true);
  };

  const handleDelete = async (template: Template) => {
    if (!window.confirm(`Delete template "${template.template?.display_name || template.template_id}"?`)) {
      return;
    }

    try {
      const response = await apiDelete(`/api/v2/templates/${template.template_id}`);
      if (response.success) {
        toast.success('Template deleted successfully');
        refetch();
      } else {
        toast.error(response.error || 'Failed to delete template');
      }
    } catch (error) {
      console.error('Failed to delete template:', error);
      toast.error('Failed to delete template');
    }
  };

  const handleSave = (template: Template) => {
    refetch();
    setShowEditor(false);
    setEditingTemplate(null);
  };

  const handleDownload = (template: Template) => {
    // Download as YAML file
    const yaml = `# Generated from Template Manager
# Template ID: ${template.template_id}

template:
  id: "${template.template_id}"
  name: ${template.template?.name}
  display_name: "${template.template?.display_name}"
  description: "${template.template?.description}"
  category: ${template.category}
  version: "${template.template?.version}"

slurm:
  partition: ${template.slurm?.partition}
  nodes: ${template.slurm?.nodes}
  ntasks: ${template.slurm?.ntasks}
  mem: ${template.slurm?.mem}
  time: "${template.slurm?.time}"

# ... (rest of template)
`;

    const blob = new Blob([yaml], { type: 'text/yaml' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${template.template_id}.yaml`;
    a.click();
    URL.revokeObjectURL(url);

    toast.success('Template downloaded');
  };

  return (
    <div className="p-6 space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold text-gray-900">Template Management</h1>
          <p className="mt-1 text-sm text-gray-600">
            Create and manage job templates with YAML configuration
          </p>
        </div>
        <button
          onClick={handleCreateNew}
          className="flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition"
        >
          <Plus className="w-5 h-5" />
          Create Template
        </button>
      </div>

      {/* Search and Filter */}
      <div className="bg-white rounded-lg shadow p-4">
        <div className="flex gap-4">
          <div className="flex-1 relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-5 h-5 text-gray-400" />
            <input
              type="text"
              placeholder="Search templates by ID, name, or description..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-full pl-10 pr-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            />
          </div>

          <select
            value={selectedCategory}
            onChange={(e) => setSelectedCategory(e.target.value)}
            className="px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
          >
            {categories.map(cat => (
              <option key={cat} value={cat}>
                {cat === 'all' ? 'All Categories' : cat.charAt(0).toUpperCase() + cat.slice(1)}
              </option>
            ))}
          </select>
        </div>
      </div>

      {/* Template List */}
      <div className="bg-white rounded-lg shadow">
        {loading ? (
          <div className="flex items-center justify-center py-12">
            <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
            <span className="ml-3 text-gray-600">Loading templates...</span>
          </div>
        ) : error ? (
          <div className="text-center py-12 text-red-600">{error}</div>
        ) : filteredTemplates.length === 0 ? (
          <div className="text-center py-12 text-gray-500">
            <FileText className="w-12 h-12 mx-auto mb-3 text-gray-400" />
            <p>No templates found</p>
            {searchQuery && (
              <button
                onClick={() => setSearchQuery('')}
                className="mt-2 text-blue-600 hover:text-blue-700 text-sm"
              >
                Clear search
              </button>
            )}
          </div>
        ) : (
          <div className="divide-y divide-gray-200">
            {filteredTemplates.map(template => (
              <div
                key={template.id}
                className="p-6 hover:bg-gray-50 transition-colors"
              >
                <div className="flex items-start justify-between">
                  <div className="flex-1">
                    <div className="flex items-center gap-3 mb-2">
                      <h3 className="text-lg font-semibold text-gray-900">
                        {template.template?.display_name || template.template_id}
                      </h3>
                      <span className="px-2 py-1 text-xs font-medium bg-blue-100 text-blue-800 rounded">
                        {template.source}
                      </span>
                      {template.template?.version && (
                        <span className="px-2 py-1 text-xs bg-gray-100 text-gray-700 rounded">
                          v{template.template.version}
                        </span>
                      )}
                    </div>

                    <p className="text-sm text-gray-600 mb-3">
                      {template.template?.description || 'No description'}
                    </p>

                    <div className="flex flex-wrap gap-3 text-xs text-gray-500">
                      <span className="flex items-center gap-1">
                        <strong>ID:</strong> {template.template_id}
                      </span>
                      <span className="flex items-center gap-1">
                        <strong>Category:</strong> {template.category}
                      </span>
                      {template.template?.author && (
                        <span className="flex items-center gap-1">
                          <strong>Author:</strong> {template.template.author}
                        </span>
                      )}
                      <span className="flex items-center gap-1">
                        <strong>Partition:</strong> {template.slurm?.partition}
                      </span>
                      {template.apptainer_normalized && (
                        <span className="flex items-center gap-1">
                          <strong>Apptainer:</strong>{' '}
                          {template.apptainer_normalized.user_selectable
                            ? `${template.apptainer_normalized.mode} (selectable)`
                            : 'fixed'}
                        </span>
                      )}
                    </div>
                  </div>

                  <div className="flex items-center gap-2 ml-4">
                    <button
                      onClick={() => setSelectedTemplate(template)}
                      className="p-2 text-gray-600 hover:bg-gray-100 rounded-lg"
                      title="Preview"
                    >
                      <Eye className="w-5 h-5" />
                    </button>
                    <button
                      onClick={() => handleDownload(template)}
                      className="p-2 text-gray-600 hover:bg-gray-100 rounded-lg"
                      title="Download YAML"
                    >
                      <Download className="w-5 h-5" />
                    </button>
                    {canEdit(template) && (
                      <button
                        onClick={() => handleEdit(template)}
                        className="p-2 text-blue-600 hover:bg-blue-50 rounded-lg"
                        title="Edit"
                      >
                        <Edit2 className="w-5 h-5" />
                      </button>
                    )}
                    {canDelete(template) && (
                      <button
                        onClick={() => handleDelete(template)}
                        className="p-2 text-red-600 hover:bg-red-50 rounded-lg"
                        title="Delete"
                      >
                        <Trash2 className="w-5 h-5" />
                      </button>
                    )}
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Summary */}
      <div className="grid grid-cols-4 gap-4">
        <div className="bg-white rounded-lg shadow p-4">
          <div className="text-sm font-medium text-gray-500">Total Templates</div>
          <div className="mt-1 text-2xl font-bold text-gray-900">{templates.length}</div>
        </div>
        <div className="bg-white rounded-lg shadow p-4">
          <div className="text-sm font-medium text-gray-500">Official</div>
          <div className="mt-1 text-2xl font-bold text-blue-600">
            {templates.filter(t => t.source === 'official').length}
          </div>
        </div>
        <div className="bg-white rounded-lg shadow p-4">
          <div className="text-sm font-medium text-gray-500">Community</div>
          <div className="mt-1 text-2xl font-bold text-green-600">
            {templates.filter(t => t.source === 'community').length}
          </div>
        </div>
        <div className="bg-white rounded-lg shadow p-4">
          <div className="text-sm font-medium text-gray-500">Private</div>
          <div className="mt-1 text-2xl font-bold text-purple-600">
            {templates.filter(t => t.source?.startsWith('private')).length}
          </div>
        </div>
      </div>

      {/* Template Editor Modal */}
      {showEditor && (
        <TemplateEditor
          template={editingTemplate}
          onClose={() => {
            setShowEditor(false);
            setEditingTemplate(null);
          }}
          onSave={handleSave}
        />
      )}

      {/* Template Preview Modal */}
      {selectedTemplate && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-lg max-w-4xl w-full max-h-[90vh] overflow-y-auto">
            <div className="p-6 border-b flex items-center justify-between">
              <h2 className="text-2xl font-bold">
                {selectedTemplate.template?.display_name || selectedTemplate.template_id}
              </h2>
              <button
                onClick={() => setSelectedTemplate(null)}
                className="text-gray-400 hover:text-gray-600"
              >
                <span className="text-2xl">×</span>
              </button>
            </div>

            <div className="p-6 space-y-4">
              <div>
                <h3 className="text-sm font-semibold text-gray-700 mb-2">Description</h3>
                <p className="text-sm text-gray-600">
                  {selectedTemplate.template?.description || 'No description'}
                </p>
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div>
                  <h3 className="text-sm font-semibold text-gray-700 mb-2">Template Info</h3>
                  <dl className="text-sm space-y-1">
                    <div className="flex justify-between">
                      <dt className="text-gray-500">ID:</dt>
                      <dd className="font-medium">{selectedTemplate.template_id}</dd>
                    </div>
                    <div className="flex justify-between">
                      <dt className="text-gray-500">Version:</dt>
                      <dd className="font-medium">{selectedTemplate.template?.version}</dd>
                    </div>
                    <div className="flex justify-between">
                      <dt className="text-gray-500">Category:</dt>
                      <dd className="font-medium">{selectedTemplate.category}</dd>
                    </div>
                    <div className="flex justify-between">
                      <dt className="text-gray-500">Author:</dt>
                      <dd className="font-medium">{selectedTemplate.template?.author}</dd>
                    </div>
                  </dl>
                </div>

                <div>
                  <h3 className="text-sm font-semibold text-gray-700 mb-2">Slurm Config</h3>
                  <dl className="text-sm space-y-1">
                    <div className="flex justify-between">
                      <dt className="text-gray-500">Partition:</dt>
                      <dd className="font-medium">{selectedTemplate.slurm?.partition}</dd>
                    </div>
                    <div className="flex justify-between">
                      <dt className="text-gray-500">Nodes:</dt>
                      <dd className="font-medium">{selectedTemplate.slurm?.nodes}</dd>
                    </div>
                    <div className="flex justify-between">
                      <dt className="text-gray-500">Tasks:</dt>
                      <dd className="font-medium">{selectedTemplate.slurm?.ntasks}</dd>
                    </div>
                    <div className="flex justify-between">
                      <dt className="text-gray-500">Memory:</dt>
                      <dd className="font-medium">{selectedTemplate.slurm?.mem}</dd>
                    </div>
                  </dl>
                </div>
              </div>

              {selectedTemplate.apptainer_normalized && (
                <div>
                  <h3 className="text-sm font-semibold text-gray-700 mb-2">Apptainer Config</h3>
                  <dl className="text-sm space-y-1">
                    <div className="flex justify-between">
                      <dt className="text-gray-500">Mode:</dt>
                      <dd className="font-medium">{selectedTemplate.apptainer_normalized.mode}</dd>
                    </div>
                    <div className="flex justify-between">
                      <dt className="text-gray-500">User Selectable:</dt>
                      <dd className="font-medium">
                        {selectedTemplate.apptainer_normalized.user_selectable ? 'Yes' : 'No'}
                      </dd>
                    </div>
                    {selectedTemplate.apptainer_normalized.image_name && (
                      <div className="flex justify-between">
                        <dt className="text-gray-500">Fixed Image:</dt>
                        <dd className="font-medium font-mono text-xs">
                          {selectedTemplate.apptainer_normalized.image_name}
                        </dd>
                      </div>
                    )}
                  </dl>
                </div>
              )}

              {selectedTemplate.files?.input_schema && (
                <div>
                  <h3 className="text-sm font-semibold text-gray-700 mb-2">File Schema</h3>
                  {selectedTemplate.files.input_schema.required && (
                    <div className="mb-2">
                      <div className="text-xs font-medium text-gray-600 mb-1">Required Files:</div>
                      <ul className="text-sm space-y-1">
                        {selectedTemplate.files.input_schema.required.map((file: any, i: number) => (
                          <li key={i} className="text-gray-700">
                            • {file.name} <span className="text-gray-500">({file.pattern})</span>
                          </li>
                        ))}
                      </ul>
                    </div>
                  )}
                </div>
              )}
            </div>

            <div className="p-6 border-t flex justify-end gap-3">
              <button
                onClick={() => setSelectedTemplate(null)}
                className="px-4 py-2 border border-gray-300 rounded-lg hover:bg-gray-50"
              >
                Close
              </button>
              <button
                onClick={() => {
                  handleEdit(selectedTemplate);
                  setSelectedTemplate(null);
                }}
                className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700"
              >
                Edit Template
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default TemplateManagement;
