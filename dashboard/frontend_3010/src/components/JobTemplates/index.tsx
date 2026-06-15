import React, { useState, useEffect } from 'react';
import { FileCode, Plus, Search, Trash2, Edit2, Copy, TrendingUp, Download, Upload, Star, Clock } from 'lucide-react';
import { apiGet, apiPost, apiDelete } from '../../utils/api';
import TemplateCard from './TemplateCard';
import TemplateEditor from './TemplateEditor';
import { PREDEFINED_TEMPLATES, TEMPLATE_CATEGORIES, Template, Category, searchTemplates, sortTemplatesByPopularity, sortTemplatesByRecent } from './predefinedTemplates';

/**
 * JobTemplates 컴포넌트
 * 작업 템플릿 라이브러리
 */

interface JobTemplatesProps {
  mode: 'mock' | 'production';
  onUseTemplate?: (template: Template) => void;
}

// v2 로더 응답(nested {template:{...}})을 이 화면의 flat Template 으로 매핑.
// 카탈로그 표시/필터/정렬에 필요한 필드만 채우고 나머지는 안전한 기본값.
const V2_CATEGORIES = ['ml', 'simulation', 'data', 'custom', 'compute', 'container'];
const mapV2Template = (item: any): Template => {
  const t = (item && item.template) ? item.template : (item || {});
  const cat = V2_CATEGORIES.includes(t.category) ? t.category : 'custom';
  return {
    id: t.id || '',
    name: t.display_name || t.name || t.id || '(이름 없음)',
    description: t.description || '',
    category: cat,
    shared: t.is_public ?? true,
    config: ({} as Template['config']),
    created_by: t.source || 'official',
    created_at: item?.last_modified || '',
    updated_at: item?.last_modified || '',
    usage_count: t.usage_count || 0,
    tags: Array.isArray(t.tags) ? t.tags : [],
  };
};

// 카테고리 count 계산
const calculateCategoryCounts = (templates: Template[]) => {
  return TEMPLATE_CATEGORIES.map(cat => ({
    ...cat,
    count: templates.filter(t => t.category === cat.name).length
  }));
};

const JobTemplates: React.FC<JobTemplatesProps> = ({ mode, onUseTemplate }) => {
  const [templates, setTemplates] = useState<Template[]>([]);
  const [categories, setCategories] = useState<Category[]>([]);
  const [selectedCategory, setSelectedCategory] = useState<string>('all');
  const [searchQuery, setSearchQuery] = useState('');
  const [sortBy, setSortBy] = useState<'name' | 'popular' | 'recent'>('name');
  const [isLoading, setIsLoading] = useState(true);
  const [showEditor, setShowEditor] = useState(false);
  const [editingTemplate, setEditingTemplate] = useState<Template | null>(null);

  // 템플릿 로드
  useEffect(() => {
    loadTemplates();
  }, [mode]);

  const loadTemplates = async () => {
    setIsLoading(true);
    try {
      if (mode === 'mock') {
        // Mock 모드: 사전 정의된 템플릿 사용
        setTemplates(PREDEFINED_TEMPLATES);
        setCategories(calculateCategoryCounts(PREDEFINED_TEMPLATES));
      } else {
        // Production 모드: 파일 기반 official 템플릿 로더(v2)에서 가져오기.
        // /api/jobs/templates(templates_api_v2)가 /shared/templates 의 official yaml 을 서빙한다.
        // (구 /api/templates 는 별도 DB 만 봐서 official 파일템플릿이 안 보였음)
        try {
          const data = await apiGet<{ templates: any[] }>('/api/jobs/templates');
          const mapped = (data.templates || []).map(mapV2Template);
          setTemplates(mapped);
          setCategories(calculateCategoryCounts(mapped));
        } catch (apiError) {
          // API가 없으면 Mock 데이터로 Fallback
          console.warn('API /api/jobs/templates not available, using predefined templates');
          setTemplates(PREDEFINED_TEMPLATES);
          setCategories(calculateCategoryCounts(PREDEFINED_TEMPLATES));
        }
      }
    } catch (error) {
      console.error('Failed to load templates:', error);
      // Fallback to mock data
      setTemplates(PREDEFINED_TEMPLATES);
      setCategories(calculateCategoryCounts(PREDEFINED_TEMPLATES));
    } finally {
      setIsLoading(false);
    }
  };

  // 필터링 및 정렬
  const filteredTemplates = React.useMemo(() => {
    let result = templates;

    // 카테고리 필터
    if (selectedCategory !== 'all') {
      result = result.filter(t => t.category === selectedCategory);
    }

    // 검색 필터
    if (searchQuery) {
      result = searchTemplates(result, searchQuery);
    }

    // 정렬
    switch (sortBy) {
      case 'popular':
        result = sortTemplatesByPopularity(result);
        break;
      case 'recent':
        result = sortTemplatesByRecent(result);
        break;
      case 'name':
      default:
        result = [...result].sort((a, b) => a.name.localeCompare(b.name));
    }

    return result;
  }, [templates, selectedCategory, searchQuery, sortBy]);

  // 템플릿 사용
  const handleUseTemplate = (template: Template) => {
    if (onUseTemplate) {
      onUseTemplate(template);
    }
    // Usage count 증가 (Production 모드에서만)
    if (mode === 'production') {
      // API 호출하여 usage_count 업데이트
      // TODO: Implement usage tracking API
    }
  };

  // 템플릿 편집
  const handleEditTemplate = (template: Template) => {
    setEditingTemplate(template);
    setShowEditor(true);
  };

  // 템플릿 삭제
  const handleDeleteTemplate = async (templateId: string) => {
    if (!window.confirm('Are you sure you want to delete this template?')) {
      return;
    }

    try {
      if (mode === 'production') {
        await apiDelete(`/api/templates/${templateId}`);
      }
      setTemplates(templates.filter(t => t.id !== templateId));
      setCategories(calculateCategoryCounts(templates.filter(t => t.id !== templateId)));
    } catch (error) {
      console.error('Failed to delete template:', error);
      alert('Failed to delete template');
    }
  };

  // 템플릿 저장
  const handleSaveTemplate = async (template: Template) => {
    try {
      if (mode === 'production') {
        if (editingTemplate) {
          // Update existing
          await apiPost(`/api/templates/${template.id}`, template);
        } else {
          // Create new
          await apiPost('/api/templates', template);
        }
      }

      // Update local state
      if (editingTemplate) {
        setTemplates(templates.map(t => (t.id === template.id ? template : t)));
      } else {
        setTemplates([...templates, template]);
      }

      setCategories(calculateCategoryCounts([...templates, template]));
      setShowEditor(false);
      setEditingTemplate(null);
    } catch (error) {
      console.error('Failed to save template:', error);
      alert('Failed to save template');
    }
  };

  // 템플릿 Export
  const handleExportTemplate = (template: Template) => {
    const dataStr = JSON.stringify(template, null, 2);
    const dataUri = 'data:application/json;charset=utf-8,' + encodeURIComponent(dataStr);
    const exportFileDefaultName = `template_${template.name.replace(/\s+/g, '_')}.json`;

    const linkElement = document.createElement('a');
    linkElement.setAttribute('href', dataUri);
    linkElement.setAttribute('download', exportFileDefaultName);
    linkElement.click();
  };

  // 전체 템플릿 Export
  const handleExportAll = () => {
    const dataStr = JSON.stringify(templates, null, 2);
    const dataUri = 'data:application/json;charset=utf-8,' + encodeURIComponent(dataStr);
    const exportFileDefaultName = `templates_all_${new Date().toISOString().split('T')[0]}.json`;

    const linkElement = document.createElement('a');
    linkElement.setAttribute('href', dataUri);
    linkElement.setAttribute('download', exportFileDefaultName);
    linkElement.click();
  };

  // 템플릿 Import
  const handleImport = () => {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = '.json';
    input.onchange = async (e: any) => {
      const file = e.target.files[0];
      if (!file) return;

      try {
        const text = await file.text();
        const imported = JSON.parse(text);

        // 배열인지 단일 객체인지 확인
        const newTemplates = Array.isArray(imported) ? imported : [imported];

        // ID 중복 방지
        const uniqueTemplates = newTemplates.map(t => ({
          ...t,
          id: `imported-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
        }));

        setTemplates([...templates, ...uniqueTemplates]);
        setCategories(calculateCategoryCounts([...templates, ...uniqueTemplates]));

        alert(`Successfully imported ${uniqueTemplates.length} template(s)`);
      } catch (error) {
        console.error('Failed to import template:', error);
        alert('Failed to import template. Please check the file format.');
      }
    };
    input.click();
  };

  // 템플릿 복제
  const handleDuplicateTemplate = (template: Template) => {
    const duplicated: Template = {
      ...template,
      id: `dup-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
      name: `${template.name} (Copy)`,
      usage_count: 0,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    };

    setTemplates([...templates, duplicated]);
    setCategories(calculateCategoryCounts([...templates, duplicated]));
  };

  return (
    <div className="h-full flex flex-col bg-white">
      {/* Header */}
      <div className="border-b border-gray-200 bg-white px-6 py-4">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-3">
            <FileCode className="w-6 h-6 text-indigo-600" />
            <h1 className="text-2xl font-bold text-gray-900">Job Templates</h1>
            <span className="px-2 py-1 text-xs font-medium bg-indigo-100 text-indigo-700 rounded">
              {templates.length} templates
            </span>
          </div>

          <div className="flex items-center gap-2">
            {/* Export All Button */}
            <button
              onClick={handleExportAll}
              className="inline-flex items-center gap-2 px-3 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-lg hover:bg-gray-50"
              title="Export all templates"
            >
              <Download className="w-4 h-4" />
              Export
            </button>

            {/* Import Button */}
            <button
              onClick={handleImport}
              className="inline-flex items-center gap-2 px-3 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-lg hover:bg-gray-50"
              title="Import templates"
            >
              <Upload className="w-4 h-4" />
              Import
            </button>

            {/* Create Button */}
            <button
              onClick={() => {
                setEditingTemplate(null);
                setShowEditor(true);
              }}
              className="inline-flex items-center gap-2 px-4 py-2 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700"
            >
              <Plus className="w-4 h-4" />
              New Template
            </button>
          </div>
        </div>

        {/* Search and Filters */}
        <div className="flex items-center gap-4">
          {/* Search */}
          <div className="flex-1 relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-5 h-5 text-gray-400" />
            <input
              type="text"
              placeholder="Search templates..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-full pl-10 pr-4 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-indigo-500"
            />
          </div>

          {/* Sort */}
          <div className="flex items-center gap-2">
            <span className="text-sm text-gray-600">Sort by:</span>
            <select
              value={sortBy}
              onChange={(e) => setSortBy(e.target.value as any)}
              className="px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-indigo-500"
            >
              <option value="name">Name</option>
              <option value="popular">Most Popular</option>
              <option value="recent">Most Recent</option>
            </select>
          </div>
        </div>

        {/* Categories */}
        <div className="mt-4">
          <div className="flex items-center gap-2 flex-wrap">
            <button
              onClick={() => setSelectedCategory('all')}
              className={`px-4 py-2 rounded-lg text-sm font-medium transition-colors ${
                selectedCategory === 'all'
                  ? 'bg-indigo-100 text-indigo-700'
                  : 'text-gray-600 hover:bg-gray-100'
              }`}
            >
              All ({templates.length})
            </button>
            {categories.map(category => (
              <button
                key={category.name}
                onClick={() => setSelectedCategory(category.name)}
                className={`px-4 py-2 rounded-lg text-sm font-medium transition-colors ${
                  selectedCategory === category.name
                    ? 'bg-indigo-100 text-indigo-700'
                    : 'text-gray-600 hover:bg-gray-100'
                }`}
              >
                {category.icon} {category.label} ({category.count})
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* Templates Grid */}
      <div className="flex-1 overflow-y-auto p-6">
        {isLoading ? (
          <div className="flex items-center justify-center py-12">
            <div className="text-center">
              <div className="w-8 h-8 border-4 border-indigo-600 border-t-transparent rounded-full animate-spin mx-auto mb-3"></div>
              <p className="text-sm text-gray-600">Loading templates...</p>
            </div>
          </div>
        ) : filteredTemplates.length === 0 ? (
          <div className="flex items-center justify-center py-12">
            <div className="text-center">
              <FileCode className="w-16 h-16 mx-auto mb-4 text-gray-400" />
              <p className="text-gray-600 mb-2">No templates found</p>
              <p className="text-sm text-gray-500 mb-4">
                {searchQuery
                  ? 'Try a different search term'
                  : 'Create your first template to get started'}
              </p>
              <button
                onClick={() => {
                  setEditingTemplate(null);
                  setShowEditor(true);
                }}
                className="inline-flex items-center gap-2 px-4 py-2 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700"
              >
                <Plus className="w-4 h-4" />
                Create Template
              </button>
            </div>
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {filteredTemplates.map(template => (
              <TemplateCard
                key={template.id}
                template={template}
                onUse={handleUseTemplate}
                onEdit={handleEditTemplate}
                onDelete={handleDeleteTemplate}
                onExport={handleExportTemplate}
                onDuplicate={handleDuplicateTemplate}
              />
            ))}
          </div>
        )}
      </div>

      {/* Template Editor Modal */}
      {showEditor && (
        <TemplateEditor
          template={editingTemplate}
          onClose={() => {
            setShowEditor(false);
            setEditingTemplate(null);
          }}
          onSave={handleSaveTemplate}
          mode={mode}
        />
      )}

      {/* Mode Badge */}
      {mode === 'mock' && (
        <div className="border-t border-gray-200 bg-yellow-50 px-6 py-3">
          <div className="flex items-center gap-2 text-sm text-yellow-800">
            <span className="font-medium">🎭 Mock Mode:</span>
            <span>Templates are simulated. Changes won't persist after refresh.</span>
          </div>
        </div>
      )}
    </div>
  );
};

export default JobTemplates;
