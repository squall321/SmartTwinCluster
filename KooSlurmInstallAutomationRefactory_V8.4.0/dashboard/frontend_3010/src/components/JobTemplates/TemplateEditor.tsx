import React, { useState, useEffect } from 'react';
import { X, Save } from 'lucide-react';
import { apiGet, apiPost, apiPatch } from '../../utils/api';

/**
 * TemplateEditor 컴포넌트
 * 템플릿 생성/수정 모달
 * v4: 기존 템플릿 편집 시에도 파티션 정책 기반 UI 적용
 */

interface Template {
  id: string;
  name: string;
  description: string;
  category: 'ml' | 'simulation' | 'data' | 'custom';
  shared: boolean;
  config: {
    partition: string;
    nodes: number;
    cpus: number;
    memory: string;
    time: string;
    gpu?: number;
    script: string;
  };
  created_by?: string;
  created_at?: string;
  updated_at?: string;
  usage_count?: number;
}

interface NodeConfig {
  total_cores: number;
  nodes: number;
  cpus_per_node: number;
}

interface Partition {
  name: string;
  label: string;
  allowedCoreSizes: number[];
  allowedConfigs: NodeConfig[];
  description: string;
}

interface TemplateEditorProps {
  template: Template | null;
  onClose: () => void;
  onSave: () => void;
  mode?: 'mock' | 'production';
}

const TemplateEditor: React.FC<TemplateEditorProps> = ({
  template,
  onClose,
  onSave,
  mode = 'mock'
}) => {
  const [formData, setFormData] = useState({
    name: template?.name || '',
    description: template?.description || '',
    category: template?.category || 'custom' as 'ml' | 'simulation' | 'data' | 'custom',
    shared: template?.shared || false,
    partition: template?.config.partition || '',
    nodes: template?.config.nodes || 1,
    cpus: template?.config.cpus || 128,
    memory: template?.config.memory || '32G',
    time: template?.config.time || '12:00:00',
    gpu: template?.config.gpu || 0,
    script: template?.config.script || '#!/bin/bash\n\n# Your job script here\n'
  });

  const [isSaving, setIsSaving] = useState(false);
  const [partitions, setPartitions] = useState<Partition[]>([]);
  const [loadingPartitions, setLoadingPartitions] = useState(true);
  const [allowedConfigs, setAllowedConfigs] = useState<NodeConfig[]>([]);
  const [selectedConfigIndex, setSelectedConfigIndex] = useState(0);
  const [cpusPerNode, setCpusPerNode] = useState(128);

  // 기존 템플릿의 구성과 일치하는 인덱스 찾기
  const findMatchingConfigIndex = (configs: NodeConfig[], nodes: number, cpus: number): number => {
    const totalCores = nodes * cpus;
    const index = configs.findIndex(
      config => config.total_cores === totalCores || 
               (config.nodes === nodes && config.cpus_per_node === cpus)
    );
    return index >= 0 ? index : 0;
  };

  // 파티션 목록 로드
  useEffect(() => {
    const loadPartitions = async () => {
      try {
        setLoadingPartitions(true);
        const response = await apiGet('/api/groups/partitions');
        if (response.success) {
          setPartitions(response.partitions);
          setCpusPerNode(response.cpus_per_node || 128);
          
          if (template) {
            // 기존 템플릿 편집: 현재 파티션의 구성 로드
            const currentPartition = response.partitions.find(
              (p: Partition) => p.name === template.config.partition
            );
            
            if (currentPartition) {
              setAllowedConfigs(currentPartition.allowedConfigs);
              
              // 기존 템플릿의 nodes/cpus와 일치하는 구성 찾기
              const matchingIndex = findMatchingConfigIndex(
                currentPartition.allowedConfigs,
                template.config.nodes,
                template.config.cpus
              );
              setSelectedConfigIndex(matchingIndex);
              
              // 일치하는 구성이 없으면 첫 번째 구성으로 업데이트
              if (matchingIndex === 0 && currentPartition.allowedConfigs.length > 0) {
                const firstConfig = currentPartition.allowedConfigs[0];
                setFormData(prev => ({
                  ...prev,
                  nodes: firstConfig.nodes,
                  cpus: firstConfig.cpus_per_node
                }));
              }
            }
          } else {
            // 새 템플릿 생성: 첫 번째 파티션을 기본값으로
            if (response.partitions.length > 0) {
              const firstPartition = response.partitions[0];
              const firstConfig = firstPartition.allowedConfigs[0];
              
              setFormData(prev => ({
                ...prev,
                partition: firstPartition.name,
                nodes: firstConfig.nodes,
                cpus: firstConfig.cpus_per_node
              }));
              setAllowedConfigs(firstPartition.allowedConfigs);
              setSelectedConfigIndex(0);
            }
          }
        }
      } catch (error) {
        console.error('Failed to load partitions:', error);
      } finally {
        setLoadingPartitions(false);
      }
    };

    loadPartitions();
  }, [template]);

  // Partition 변경 시 허용된 구성 목록 업데이트
  useEffect(() => {
    const selectedPartition = partitions.find(p => p.name === formData.partition);
    if (selectedPartition) {
      setAllowedConfigs(selectedPartition.allowedConfigs);
      
      // 파티션이 변경되면 첫 번째 구성을 기본값으로 설정
      if (selectedPartition.allowedConfigs.length > 0) {
        const firstConfig = selectedPartition.allowedConfigs[0];
        setFormData(prev => ({
          ...prev,
          nodes: firstConfig.nodes,
          cpus: firstConfig.cpus_per_node
        }));
        setSelectedConfigIndex(0);
      }
    }
  }, [formData.partition, partitions]);

  // 구성 선택 변경 시 nodes와 cpus 업데이트
  const handleConfigChange = (index: number) => {
    const config = allowedConfigs[index];
    setSelectedConfigIndex(index);
    setFormData(prev => ({
      ...prev,
      nodes: config.nodes,
      cpus: config.cpus_per_node
    }));
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsSaving(true);

    try {
      const data = {
        name: formData.name,
        description: formData.description,
        category: formData.category,
        shared: formData.shared,
        config: {
          partition: formData.partition,
          nodes: formData.nodes,
          cpus: formData.cpus,
          memory: formData.memory,
          time: formData.time,
          gpu: formData.gpu || undefined,
          script: formData.script
        }
      };

      if (template) {
        // Update
        await apiPatch(`/api/jobs/templates/${template.id}`, data);
      } else {
        // Create
        await apiPost('/api/jobs/templates', data);
      }

      onSave();
    } catch (error) {
      console.error('Failed to save template:', error);
      alert('Failed to save template');
    } finally {
      setIsSaving(false);
    }
  };

  return (
    <>
      {/* Backdrop */}
      <div
        className="fixed inset-0 bg-black bg-opacity-50 z-50"
        onClick={onClose}
      />

      {/* Modal */}
      <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
        <div className="bg-white rounded-xl shadow-2xl max-w-3xl w-full max-h-[90vh] overflow-hidden">
          {/* Header */}
          <div className="px-6 py-4 border-b border-gray-200 flex items-center justify-between">
            <h2 className="text-xl font-bold text-gray-900">
              {template ? 'Edit Template' : 'New Template'}
            </h2>
            <button
              onClick={onClose}
              className="p-2 hover:bg-gray-100 rounded-lg transition-colors"
            >
              <X className="w-5 h-5" />
            </button>
          </div>

          {/* Form */}
          <form onSubmit={handleSubmit} className="p-6 overflow-y-auto max-h-[calc(90vh-140px)]">
            <div className="space-y-4">
              {/* Name */}
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Template Name *
                </label>
                <input
                  type="text"
                  required
                  value={formData.name}
                  onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-indigo-500"
                  placeholder="e.g., PyTorch Training"
                />
              </div>

              {/* Description */}
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Description
                </label>
                <textarea
                  value={formData.description}
                  onChange={(e) => setFormData({ ...formData, description: e.target.value })}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-indigo-500"
                  rows={2}
                  placeholder="Brief description of this template"
                />
              </div>

              {/* Category & Shared */}
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Category
                  </label>
                  <select
                    value={formData.category}
                    onChange={(e) => setFormData({ ...formData, category: e.target.value as any })}
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-indigo-500"
                  >
                    <option value="ml">🤖 Machine Learning</option>
                    <option value="simulation">🔬 Simulation</option>
                    <option value="data">📊 Data Processing</option>
                    <option value="custom">⚙️ Custom</option>
                  </select>
                </div>

                <div className="flex items-end">
                  <label className="flex items-center gap-2 cursor-pointer">
                    <input
                      type="checkbox"
                      checked={formData.shared}
                      onChange={(e) => setFormData({ ...formData, shared: e.target.checked })}
                      className="w-4 h-4 text-indigo-600 rounded focus:ring-2 focus:ring-indigo-500"
                    />
                    <span className="text-sm font-medium text-gray-700">Shared Template</span>
                  </label>
                </div>
              </div>

              {/* Partition Selection */}
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Partition * 
                  <span className="text-xs text-gray-500 ml-1">(Group)</span>
                </label>
                {loadingPartitions ? (
                  <div className="w-full px-3 py-2 border border-gray-300 rounded-lg bg-gray-50 text-gray-500 text-sm">
                    Loading...
                  </div>
                ) : partitions.length === 0 ? (
                  <div className="w-full px-3 py-2 border border-red-300 rounded-lg bg-red-50 text-red-600 text-xs">
                    No partitions available
                  </div>
                ) : (
                  <select
                    required
                    value={formData.partition}
                    onChange={(e) => setFormData({ ...formData, partition: e.target.value })}
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-indigo-500"
                  >
                    {partitions.map((p) => (
                      <option key={p.name} value={p.name}>
                        {p.label} ({p.name})
                      </option>
                    ))}
                  </select>
                )}
              </div>

              {/* Resource Configuration Selection */}
              {allowedConfigs.length > 0 && (
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    Resource Configuration *
                    <span className="text-xs text-gray-500 ml-1">(Based on Partition Policy)</span>
                  </label>
                  <div className="grid grid-cols-1 gap-2">
                    {allowedConfigs.map((config, index) => (
                      <div
                        key={index}
                        onClick={() => handleConfigChange(index)}
                        className={`p-3 border-2 rounded-lg cursor-pointer transition-all ${
                          selectedConfigIndex === index
                            ? 'border-indigo-500 bg-indigo-50'
                            : 'border-gray-200 hover:border-gray-300 bg-white'
                        }`}
                      >
                        <div className="flex items-center justify-between">
                          <div className="flex items-center gap-3">
                            <input
                              type="radio"
                              checked={selectedConfigIndex === index}
                              onChange={() => handleConfigChange(index)}
                              className="w-4 h-4 text-indigo-600"
                            />
                            <div>
                              <div className="font-semibold text-gray-900">
                                {config.total_cores} Total Cores
                              </div>
                              <div className="text-sm text-gray-600">
                                {config.nodes} node{config.nodes > 1 ? 's' : ''} × {config.cpus_per_node} CPUs/node
                              </div>
                            </div>
                          </div>
                          {selectedConfigIndex === index && (
                            <div className="text-indigo-600 font-semibold text-sm">
                              ✓ Selected
                            </div>
                          )}
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {/* Display Selected Configuration */}
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Nodes
                    <span className="text-xs text-gray-500 ml-1">(Auto-calculated)</span>
                  </label>
                  <input
                    type="number"
                    value={formData.nodes}
                    disabled
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg bg-gray-100 text-gray-600 cursor-not-allowed"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    CPUs per Node
                    <span className="text-xs text-gray-500 ml-1">(Auto-calculated)</span>
                  </label>
                  <input
                    type="number"
                    value={formData.cpus}
                    disabled
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg bg-gray-100 text-gray-600 cursor-not-allowed"
                  />
                </div>
              </div>

              {/* Other Resources */}
              <div className="grid grid-cols-3 gap-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Memory
                  </label>
                  <input
                    type="text"
                    value={formData.memory}
                    onChange={(e) => setFormData({ ...formData, memory: e.target.value })}
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-indigo-500"
                    placeholder="e.g., 32G"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Time Limit
                  </label>
                  <input
                    type="text"
                    value={formData.time}
                    onChange={(e) => setFormData({ ...formData, time: e.target.value })}
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-indigo-500"
                    placeholder="HH:MM:SS"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    GPUs
                  </label>
                  <input
                    type="number"
                    min="0"
                    value={formData.gpu}
                    onChange={(e) => setFormData({ ...formData, gpu: parseInt(e.target.value) })}
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-indigo-500"
                  />
                </div>
              </div>

              {/* Info Box */}
              {allowedConfigs.length > 0 && (
                <div className="p-4 bg-blue-50 border border-blue-200 rounded-lg">
                  <div className="text-sm font-semibold text-blue-900 mb-2">
                    ℹ️ Resource Policy for "{formData.partition}"
                  </div>
                  <div className="text-xs text-blue-700 space-y-1">
                    <div>• Each node has {cpusPerNode} CPU cores</div>
                    <div>• Partition allows {allowedConfigs.length} configuration{allowedConfigs.length > 1 ? 's' : ''}</div>
                    <div>• Total cores selected: <span className="font-semibold">{formData.nodes * formData.cpus}</span></div>
                  </div>
                </div>
              )}

              {/* Script */}
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Job Script *
                </label>
                <textarea
                  required
                  value={formData.script}
                  onChange={(e) => setFormData({ ...formData, script: e.target.value })}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-indigo-500 font-mono text-sm"
                  rows={10}
                  placeholder="#!/bin/bash&#10;&#10;# Your job script here"
                />
              </div>
            </div>
          </form>

          {/* Footer */}
          <div className="px-6 py-4 border-t border-gray-200 flex items-center justify-end gap-3">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 border border-gray-300 text-gray-700 rounded-lg hover:bg-gray-50 transition-colors"
            >
              Cancel
            </button>
            <button
              onClick={handleSubmit}
              disabled={isSaving || loadingPartitions}
              className="flex items-center gap-2 px-4 py-2 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700 disabled:opacity-50 transition-colors"
            >
              <Save className="w-4 h-4" />
              {isSaving ? 'Saving...' : 'Save Template'}
            </button>
          </div>
        </div>
      </div>
    </>
  );
};

export default TemplateEditor;
