/**
 * CommandTemplateInserter Component
 *
 * Command Template 선택 및 스크립트 생성 모달
 * - Template 선택
 * - 변수 매핑 설정
 * - 스크립트 미리보기
 * - 생성된 스크립트 삽입
 */

import React, { useState, useEffect } from 'react';
import { X, FileCode, Play, AlertCircle, CheckCircle, Copy, Eye } from 'lucide-react';
import { ApptainerImage, CommandTemplate } from '../../types/apptainer';
import { SlurmConfig, UploadedFiles } from '../../utils/variableResolver';
import {
  generateSlurmScript,
  generateMainExecScript,
  generateScriptPreview,
  ScriptPreview,
} from '../../utils/commandTemplateGenerator';
import { generateVariablePreview, VariablePreview } from '../../utils/variableResolver';

interface CommandTemplateInserterProps {
  image: ApptainerImage;
  slurmConfig: SlurmConfig;
  onInsert: (scriptContent: string) => void;
  onClose: () => void;
}

export const CommandTemplateInserter: React.FC<CommandTemplateInserterProps> = ({
  image,
  slurmConfig,
  onInsert,
  onClose,
}) => {
  const [selectedTemplate, setSelectedTemplate] = useState<CommandTemplate | null>(null);
  const [uploadedFiles, setUploadedFiles] = useState<UploadedFiles>({});
  const [activeTab, setActiveTab] = useState<'select' | 'configure' | 'preview'>('select');
  const [scriptPreview, setScriptPreview] = useState<ScriptPreview | null>(null);
  const [variablePreview, setVariablePreview] = useState<VariablePreview[]>([]);

  const templates = image.command_templates || [];

  // Template 선택 시 자동으로 configure 탭으로 이동
  useEffect(() => {
    if (selectedTemplate) {
      setActiveTab('configure');
      updatePreviews();
    }
  }, [selectedTemplate]);

  // 파일 또는 설정 변경 시 미리보기 업데이트
  useEffect(() => {
    if (selectedTemplate) {
      updatePreviews();
    }
  }, [uploadedFiles, slurmConfig]);

  const updatePreviews = () => {
    if (!selectedTemplate) return;

    // Variable preview
    const varPreview = generateVariablePreview(selectedTemplate, slurmConfig, uploadedFiles);
    setVariablePreview(varPreview);

    // Script preview
    const preview = generateScriptPreview({
      template: selectedTemplate,
      slurmConfig,
      uploadedFiles,
      apptainerImagePath: image.path,
      jobName: `${selectedTemplate.template_id}_job`,
    });
    setScriptPreview(preview);
  };

  const handleFileInput = (fileKey: string, value: string) => {
    setUploadedFiles({
      ...uploadedFiles,
      [fileKey]: value,
    });
  };

  const handleInsertFullScript = () => {
    if (!scriptPreview || !scriptPreview.valid) {
      alert('Cannot insert: script has errors');
      return;
    }

    onInsert(scriptPreview.script);
    onClose();
  };

  const handleInsertMainExec = () => {
    if (!selectedTemplate) return;

    const mainExec = generateMainExecScript(selectedTemplate, image.path);
    onInsert(mainExec);
    onClose();
  };

  const copyToClipboard = (text: string) => {
    navigator.clipboard.writeText(text);
    alert('Copied to clipboard!');
  };

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
      <div className="bg-white rounded-lg max-w-6xl w-full h-[95vh] flex flex-col">
        {/* Header */}
        <div className="p-6 border-b flex items-center justify-between">
          <div>
            <h2 className="text-2xl font-bold flex items-center gap-2">
              <FileCode className="w-6 h-6 text-blue-600" />
              Insert Command Template
            </h2>
            <p className="text-sm text-gray-600 mt-1">
              Image: <span className="font-medium">{image.name}</span>
            </p>
          </div>
          <button
            onClick={onClose}
            className="text-gray-400 hover:text-gray-600"
          >
            <X className="w-6 h-6" />
          </button>
        </div>

        {/* Tabs */}
        <div className="flex border-b px-6">
          {[
            { id: 'select', label: 'Select Template', disabled: false },
            { id: 'configure', label: 'Configure Variables', disabled: !selectedTemplate },
            { id: 'preview', label: 'Preview & Insert', disabled: !selectedTemplate },
          ].map((tab) => (
            <button
              key={tab.id}
              onClick={() => !tab.disabled && setActiveTab(tab.id as any)}
              disabled={tab.disabled}
              className={`px-4 py-3 border-b-2 transition-colors ${
                activeTab === tab.id
                  ? 'border-blue-600 text-blue-600 font-medium'
                  : tab.disabled
                  ? 'border-transparent text-gray-400 cursor-not-allowed'
                  : 'border-transparent text-gray-600 hover:text-gray-900'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>

        {/* Content */}
        <div className="flex-1 overflow-y-auto p-6">
          {/* Tab 1: Select Template */}
          {activeTab === 'select' && (
            <div className="space-y-3">
              <h3 className="text-lg font-semibold mb-4">
                Available Templates ({templates.length})
              </h3>

              {templates.length === 0 ? (
                <div className="p-8 text-center text-gray-500 bg-gray-50 rounded-lg">
                  <FileCode className="w-12 h-12 mx-auto mb-3 text-gray-400" />
                  <p>No command templates available for this image</p>
                </div>
              ) : (
                templates.map((template) => (
                  <div
                    key={template.template_id}
                    onClick={() => setSelectedTemplate(template)}
                    className={`border rounded-lg p-4 cursor-pointer transition-all ${
                      selectedTemplate?.template_id === template.template_id
                        ? 'border-blue-500 bg-blue-50 shadow-md'
                        : 'border-gray-200 hover:border-blue-300 hover:shadow-sm'
                    }`}
                  >
                    <div className="flex items-start justify-between">
                      <div className="flex-1">
                        <div className="font-semibold text-lg text-gray-900">
                          {template.display_name}
                        </div>
                        <div className="text-sm text-gray-600 mt-1">
                          {template.description}
                        </div>

                        <div className="flex items-center gap-2 mt-3">
                          <span className="px-2 py-1 bg-purple-100 text-purple-700 rounded text-xs font-medium">
                            {template.category}
                          </span>

                          {template.command.requires_mpi && (
                            <span className="px-2 py-1 bg-blue-100 text-blue-700 rounded text-xs font-medium">
                              MPI Required
                            </span>
                          )}

                          <span className="text-xs text-gray-600">
                            {Object.keys(template.variables.input_files).length} input file{Object.keys(template.variables.input_files).length !== 1 ? 's' : ''}
                          </span>

                          {Object.keys(template.variables.dynamic).length > 0 && (
                            <span className="text-xs text-gray-600">
                              {Object.keys(template.variables.dynamic).length} dynamic var{Object.keys(template.variables.dynamic).length !== 1 ? 's' : ''}
                            </span>
                          )}
                        </div>

                        <div className="mt-3 p-2 bg-gray-100 rounded text-xs font-mono text-gray-700">
                          {template.command.format}
                        </div>
                      </div>

                      {selectedTemplate?.template_id === template.template_id && (
                        <CheckCircle className="w-6 h-6 text-blue-600 ml-3" />
                      )}
                    </div>
                  </div>
                ))
              )}
            </div>
          )}

          {/* Tab 2: Configure Variables */}
          {activeTab === 'configure' && selectedTemplate && (
            <div className="space-y-6">
              <h3 className="text-lg font-semibold">Configure Variables</h3>

              {/* Input Files */}
              {Object.keys(selectedTemplate.variables.input_files).length > 0 && (
                <div>
                  <h4 className="font-medium text-gray-900 mb-3">Input Files</h4>

                  <div className="space-y-3">
                    {Object.entries(selectedTemplate.variables.input_files).map(([varName, varDef]) => (
                      <div key={varName} className="border border-gray-200 rounded-lg p-3">
                        <label className="block text-sm font-medium text-gray-700 mb-1">
                          {varDef.description}
                          {varDef.required && <span className="text-red-500 ml-1">*</span>}
                        </label>

                        <input
                          type="text"
                          value={uploadedFiles[varDef.file_key] as string || ''}
                          onChange={(e) => handleFileInput(varDef.file_key, e.target.value)}
                          placeholder={`File path (${varDef.pattern})`}
                          className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
                        />

                        <div className="mt-1 text-xs text-gray-500">
                          file_key: <code className="bg-gray-100 px-1 py-0.5 rounded">{varDef.file_key}</code>
                          → <code className="bg-gray-100 px-1 py-0.5 rounded">$FILE_{varDef.file_key.toUpperCase()}</code>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {/* Dynamic Variables Preview */}
              {Object.keys(selectedTemplate.variables.dynamic).length > 0 && (
                <div>
                  <h4 className="font-medium text-gray-900 mb-3">Dynamic Variables (Auto-mapped)</h4>

                  <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
                    <div className="text-sm text-blue-900 space-y-2">
                      {Object.entries(selectedTemplate.variables.dynamic).map(([varName, varDef]) => {
                        const preview = variablePreview.find((v) => v.name === varName);

                        return (
                          <div key={varName} className="flex items-center justify-between">
                            <div>
                              <span className="font-medium">{varName}</span>
                              <span className="text-xs text-blue-700 ml-2">
                                from {varDef.source}
                                {varDef.transform && ` → ${varDef.transform}`}
                              </span>
                            </div>
                            <code className="bg-white px-2 py-1 rounded text-blue-900">
                              {preview?.value}
                            </code>
                          </div>
                        );
                      })}
                    </div>
                  </div>
                </div>
              )}

              {/* Variable Preview Table */}
              {variablePreview.length > 0 && (
                <div>
                  <h4 className="font-medium text-gray-900 mb-3">All Variables Preview</h4>

                  <div className="border border-gray-200 rounded-lg overflow-hidden">
                    <table className="w-full text-sm">
                      <thead className="bg-gray-50">
                        <tr>
                          <th className="px-4 py-2 text-left font-medium text-gray-700">Variable</th>
                          <th className="px-4 py-2 text-left font-medium text-gray-700">Value</th>
                          <th className="px-4 py-2 text-left font-medium text-gray-700">Type</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-gray-200">
                        {variablePreview.map((variable, idx) => (
                          <tr key={idx} className="hover:bg-gray-50">
                            <td className="px-4 py-2 font-mono text-xs">{variable.name}</td>
                            <td className="px-4 py-2 font-mono text-xs text-gray-700">
                              {String(variable.value)}
                            </td>
                            <td className="px-4 py-2">
                              <span
                                className={`px-2 py-0.5 rounded text-xs ${
                                  variable.type === 'dynamic'
                                    ? 'bg-blue-100 text-blue-700'
                                    : variable.type === 'file'
                                    ? 'bg-green-100 text-green-700'
                                    : 'bg-gray-100 text-gray-700'
                                }`}
                              >
                                {variable.type}
                              </span>
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                </div>
              )}
            </div>
          )}

          {/* Tab 3: Preview & Insert */}
          {activeTab === 'preview' && selectedTemplate && scriptPreview && (
            <div className="space-y-6">
              <h3 className="text-lg font-semibold">Script Preview</h3>

              {/* Validation Status */}
              <div
                className={`p-4 rounded-lg border ${
                  scriptPreview.valid
                    ? 'bg-green-50 border-green-200'
                    : 'bg-red-50 border-red-200'
                }`}
              >
                <div className="flex items-center gap-2">
                  {scriptPreview.valid ? (
                    <>
                      <CheckCircle className="w-5 h-5 text-green-600" />
                      <span className="font-medium text-green-900">Script ready to insert</span>
                    </>
                  ) : (
                    <>
                      <AlertCircle className="w-5 h-5 text-red-600" />
                      <span className="font-medium text-red-900">Script has errors</span>
                    </>
                  )}
                </div>

                {scriptPreview.errors.length > 0 && (
                  <ul className="mt-2 ml-7 text-sm text-red-700 space-y-1">
                    {scriptPreview.errors.map((error, idx) => (
                      <li key={idx}>• {error}</li>
                    ))}
                  </ul>
                )}

                {scriptPreview.warnings.length > 0 && (
                  <ul className="mt-2 ml-7 text-sm text-yellow-700 space-y-1">
                    {scriptPreview.warnings.map((warning, idx) => (
                      <li key={idx}>⚠ {warning}</li>
                    ))}
                  </ul>
                )}
              </div>

              {/* Resource Summary */}
              <div className="grid grid-cols-4 gap-4">
                <div className="p-3 bg-gray-50 rounded-lg">
                  <div className="text-xs text-gray-600">Total Cores</div>
                  <div className="text-lg font-semibold text-gray-900">
                    {scriptPreview.resourceSummary.cores}
                  </div>
                </div>
                <div className="p-3 bg-gray-50 rounded-lg">
                  <div className="text-xs text-gray-600">Nodes</div>
                  <div className="text-lg font-semibold text-gray-900">
                    {scriptPreview.resourceSummary.nodes}
                  </div>
                </div>
                <div className="p-3 bg-gray-50 rounded-lg">
                  <div className="text-xs text-gray-600">Memory</div>
                  <div className="text-lg font-semibold text-gray-900">
                    {scriptPreview.resourceSummary.memory}
                  </div>
                </div>
                <div className="p-3 bg-gray-50 rounded-lg">
                  <div className="text-xs text-gray-600">Time Limit</div>
                  <div className="text-lg font-semibold text-gray-900">
                    {scriptPreview.resourceSummary.time}
                  </div>
                </div>
              </div>

              {/* Script Content */}
              <div>
                <div className="flex items-center justify-between mb-2">
                  <h4 className="font-medium text-gray-900">Generated Script</h4>
                  <button
                    onClick={() => copyToClipboard(scriptPreview.script)}
                    className="text-sm text-blue-600 hover:text-blue-700 flex items-center gap-1"
                  >
                    <Copy className="w-4 h-4" />
                    Copy
                  </button>
                </div>

                <pre className="p-4 bg-gray-900 text-gray-100 rounded-lg overflow-x-auto text-xs font-mono max-h-96">
                  {scriptPreview.script}
                </pre>
              </div>
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="p-6 border-t flex items-center justify-between">
          <button
            onClick={onClose}
            className="px-4 py-2 border border-gray-300 rounded-lg hover:bg-gray-50"
          >
            Cancel
          </button>

          <div className="flex gap-3">
            {activeTab === 'select' && selectedTemplate && (
              <button
                onClick={() => setActiveTab('configure')}
                className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700"
              >
                Next: Configure →
              </button>
            )}

            {activeTab === 'configure' && (
              <button
                onClick={() => setActiveTab('preview')}
                className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 flex items-center gap-2"
              >
                <Eye className="w-4 h-4" />
                Preview Script
              </button>
            )}

            {activeTab === 'preview' && (
              <>
                <button
                  onClick={handleInsertMainExec}
                  className="px-4 py-2 border border-blue-600 text-blue-600 rounded-lg hover:bg-blue-50"
                >
                  Insert Template Only
                </button>
                <button
                  onClick={handleInsertFullScript}
                  disabled={!scriptPreview.valid}
                  className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-2"
                >
                  <Play className="w-4 h-4" />
                  Insert Full Script
                </button>
              </>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};

export default CommandTemplateInserter;
