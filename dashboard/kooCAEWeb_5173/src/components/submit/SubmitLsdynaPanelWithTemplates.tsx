/**
 * Enhanced SubmitLsdynaPanel with Apptainer Template Integration v2
 *
 * 새로운 기능:
 * - 템플릿으로 저장 기능
 * - 저장된 템플릿 불러오기
 * - 템플릿 기반 제출 시 template_id와 image_path 전송
 */

import React, { useEffect, useState } from 'react';
import { Button, message, Tabs, Modal } from 'antd';
import { CodeOutlined, UploadOutlined, SaveOutlined, FolderOpenOutlined } from '@ant-design/icons';
import LsdynaFileUploader from '../uploader/LsdynaFileUploader';
import type { LsdynaJobConfig } from '../uploader/LsdynaOptionTable';
import ApptainerTemplateIntegration from '../ApptainerTemplateIntegration';
import SaveTemplateModal, { SaveTemplateData } from '../SaveTemplateModal';
import { api } from '../../api/axiosClient';

const { TabPane } = Tabs;

interface CommandTemplate {
  template_id: string;
  display_name: string;
  description: string;
  category: string;
  command: {
    executable: string;
    format: string;
    requires_mpi: boolean;
  };
  variables: any;
  pre_commands?: string[];
  post_commands?: string[];
}

interface ApptainerImage {
  id: string;
  name: string;
  path: string;
  partition: string;
  command_templates: CommandTemplate[];
}

interface SubmitLsdynaPanelWithTemplatesProps {
  initialConfigs?: LsdynaJobConfig[];
  autoSubmit?: boolean;
  onSubmitSuccess?: (submitted: any[]) => void;
}

const SubmitLsdynaPanelWithTemplates: React.FC<SubmitLsdynaPanelWithTemplatesProps> = ({
  initialConfigs,
  autoSubmit = false,
  onSubmitSuccess,
}) => {
  const [configs, setConfigs] = useState<LsdynaJobConfig[]>([]);
  const [activeTab, setActiveTab] = useState<string>('upload');

  // Template-related state
  const [selectedTemplate, setSelectedTemplate] = useState<CommandTemplate | null>(null);
  const [selectedImage, setSelectedImage] = useState<ApptainerImage | null>(null);
  const [generatedScript, setGeneratedScript] = useState<string>('');

  // Save template modal
  const [saveModalOpen, setSaveModalOpen] = useState(false);

  // Initialize with initial configs
  useEffect(() => {
    if (initialConfigs && configs.length === 0) {
      setConfigs(initialConfigs);
    }
  }, [initialConfigs, configs.length]);

  // Handle file uploader data updates
  const handleDataUpdate = (updated: LsdynaJobConfig[]) => {
    setConfigs(updated);
  };

  // Handle template application
  const handleTemplateApply = (
    script: string,
    template: CommandTemplate,
    image: ApptainerImage
  ) => {
    setSelectedTemplate(template);
    setSelectedImage(image);
    setGeneratedScript(script);

    message.success(`템플릿 "${template.display_name}"이(가) 적용되었습니다!`);

    // Auto-populate job configs based on template
    autoPopulateFromTemplate(template, image);
  };

  // Auto-populate job configurations from template
  const autoPopulateFromTemplate = (template: CommandTemplate, image: ApptainerImage) => {
    const defaultCores = template.variables?.dynamic?.SLURM_NTASKS?.source === 'slurm.ntasks' ? 16 : 16;
    const requiresMPI = template.command.requires_mpi;

    if (configs.length > 0) {
      const updated = configs.map((cfg) => ({
        ...cfg,
        cores: defaultCores,
        mode: requiresMPI ? 'MPP' as const : 'SMP' as const,
      }));
      setConfigs(updated);
      message.info(`${configs.length}개 작업에 템플릿 기본값이 적용되었습니다`);
    } else {
      message.info('템플릿이 적용되었습니다. K 파일을 업로드하여 이 설정으로 작업을 생성하세요.');
    }
  };

  // Build Slurm config from first job config for template preview
  const getSlurmConfigFromJobConfig = (config?: LsdynaJobConfig) => {
    if (!config) {
      return {
        partition: 'compute',
        nodes: 1,
        ntasks: 16,
        'cpus-per-task': 1,
        mem: '32G',
        time: '12:00:00',
      };
    }

    return {
      partition: 'compute',
      nodes: 1,
      ntasks: config.cores,
      'cpus-per-task': 1,
      mem: `${Math.ceil(config.cores * 2)}G`,
      time: '12:00:00',
    };
  };

  // Build input files mapping from configs
  const getInputFilesFromConfigs = () => {
    if (configs.length === 0) return {};

    const firstConfig = configs[0];
    return {
      k_file: firstConfig.filename,
    };
  };

  // Handle traditional job submission
  const handleSubmit = async () => {
    if (configs.length === 0) {
      message.warning('업로드된 파일이 없습니다.');
      return;
    }

    const formData = new FormData();
    configs.forEach((cfg, i) => {
      formData.append('files', cfg.file);

      const metaData: any = {
        filename: cfg.filename,
        cores: cfg.cores,
        precision: cfg.precision,
        version: cfg.version,
        mode: cfg.mode,
      };

      // Include template info if available
      if (selectedTemplate && selectedImage) {
        metaData.template_id = selectedTemplate.template_id;
        metaData.image_path = selectedImage.path;
      }

      formData.append(`meta[${i}]`, JSON.stringify(metaData));
    });

    try {
      const res = await api.post(
        "/api/slurm/submit-lsdyna-jobs",
        formData,
        {
          headers: { 'Content-Type': 'multipart/form-data' },
        }
      );

      if (Array.isArray(res.data.submitted)) {
        message.success(`총 ${res.data.submitted.length}개의 작업이 제출되었습니다`);

        // Log template usage
        const templatesUsed = res.data.submitted.filter((job: any) => job.used_template).length;
        if (templatesUsed > 0) {
          console.log(`📋 ${templatesUsed}개 작업이 템플릿을 사용했습니다`);
        }

        setConfigs([]);
        setSelectedTemplate(null);
        setSelectedImage(null);
        setGeneratedScript('');
        onSubmitSuccess?.(res.data.submitted);
      } else {
        message.error(res.data.error || '제출 실패: submitted 정보가 없습니다.');
      }
    } catch (err: any) {
      message.error(
        err?.response?.data?.error || err?.message || '제출 중 서버 오류 발생'
      );
    }
  };

  // Handle template-based job submission
  const handleTemplateSubmit = async () => {
    if (!selectedTemplate || !selectedImage || !generatedScript) {
      message.warning('템플릿이 선택되지 않았거나 스크립트가 생성되지 않았습니다.');
      return;
    }

    if (configs.length === 0) {
      message.warning('최소 하나의 K 파일을 업로드해야 합니다.');
      return;
    }

    // Use same submission as traditional, but with template info
    await handleSubmit();
  };

  // Handle save as template
  const handleSaveTemplate = async (templateData: SaveTemplateData) => {
    if (!selectedTemplate || !selectedImage) {
      throw new Error('템플릿과 이미지를 먼저 선택해주세요');
    }

    if (configs.length === 0) {
      throw new Error('작업 구성이 없습니다. K 파일을 업로드해주세요');
    }

    // Build job config from first config
    const firstConfig = configs[0];
    const jobConfig = {
      partition: 'group6',
      nodes: 1,
      ntasks: firstConfig.cores,
      cpus_per_task: 1,
      mem: `${Math.ceil(firstConfig.cores * 2)}G`,
      time: '24:00:00',
      qos: 'group6_qos',
      precision: firstConfig.precision,
      version: firstConfig.version,
      mode: firstConfig.mode,
    };

    // Create template data
    const templatePayload = {
      name: templateData.name,
      description: templateData.description,
      category: templateData.category,
      shared: templateData.shared,
      config: jobConfig,
      apptainer_template_id: selectedTemplate.template_id,
      apptainer_image_id: selectedImage.id,
      custom_values: {},
      created_by: 'current_user', // TODO: Get from auth context
    };

    try {
      const res = await api.post('/api/templates/', templatePayload);

      if (res.data.success) {
        message.success(`템플릿 "${templateData.name}"이(가) 저장되었습니다!`);
        console.log('Saved template ID:', res.data.template_id);
      } else {
        throw new Error(res.data.error || '템플릿 저장 실패');
      }
    } catch (err: any) {
      throw new Error(err?.response?.data?.error || err?.message || '템플릿 저장 중 오류 발생');
    }
  };

  // Auto-submit functionality
  useEffect(() => {
    if (autoSubmit && configs.length > 0) {
      handleSubmit();
    }
  }, [configs, autoSubmit]);

  return (
    <div>
      {/* Tab Navigation */}
      <Tabs
        activeKey={activeTab}
        onChange={setActiveTab}
        style={{ marginBottom: 16 }}
      >
        <TabPane
          tab={
            <span>
              <UploadOutlined />
              기존 방식 업로드
            </span>
          }
          key="upload"
        >
          {/* Original file upload interface */}
          <LsdynaFileUploader
            onDataUpdate={handleDataUpdate}
            initialData={configs}
          />

          {configs.length > 0 && !autoSubmit && (
            <div style={{ textAlign: 'right', marginTop: '1rem', display: 'flex', gap: '8px', justifyContent: 'flex-end' }}>
              {selectedTemplate && (
                <Button
                  icon={<SaveOutlined />}
                  onClick={() => setSaveModalOpen(true)}
                >
                  템플릿으로 저장
                </Button>
              )}
              <Button type="primary" onClick={handleSubmit}>
                작업 제출
              </Button>
            </div>
          )}
        </TabPane>

        <TabPane
          tab={
            <span>
              <CodeOutlined />
              템플릿 기반 제출
            </span>
          }
          key="template"
        >
          {/* Apptainer Template Integration */}
          <ApptainerTemplateIntegration
            onTemplateApply={handleTemplateApply}
            slurmConfig={getSlurmConfigFromJobConfig(configs[0])}
            inputFiles={getInputFilesFromConfigs()}
            partition="compute"
            defaultExpanded={true}
            applyButtonText="작업에 템플릿 적용"
            showPreview={true}
          />

          {/* Show upload section if template is selected */}
          {selectedTemplate && (
            <div style={{ marginTop: 24 }}>
              <h3>템플릿 기반 제출을 위한 K 파일 업로드</h3>
              <p style={{ color: '#666', marginBottom: 16 }}>
                템플릿: <strong>{selectedTemplate.display_name}</strong>
                {' '}| 이미지: <strong>{selectedImage?.name}</strong>
              </p>

              <LsdynaFileUploader
                onDataUpdate={handleDataUpdate}
                initialData={configs}
              />

              {configs.length > 0 && (
                <div style={{ textAlign: 'right', marginTop: '1rem', display: 'flex', gap: '8px', justifyContent: 'flex-end' }}>
                  <Button
                    icon={<SaveOutlined />}
                    onClick={() => setSaveModalOpen(true)}
                  >
                    템플릿으로 저장
                  </Button>
                  <Button type="primary" onClick={handleTemplateSubmit}>
                    템플릿으로 제출
                  </Button>
                </div>
              )}
            </div>
          )}
        </TabPane>
      </Tabs>

      {/* Template info display */}
      {selectedTemplate && activeTab === 'upload' && (
        <div style={{
          marginTop: 16,
          padding: 12,
          background: '#e6f7ff',
          border: '1px solid #91d5ff',
          borderRadius: 4,
        }}>
          <strong>활성 템플릿:</strong> {selectedTemplate.display_name}
          <span style={{ marginLeft: 8, color: '#666' }}>
            ({selectedImage?.name})
          </span>
          <Button
            size="small"
            type="link"
            onClick={() => setActiveTab('template')}
          >
            템플릿 보기/변경
          </Button>
        </div>
      )}

      {/* Save Template Modal */}
      <SaveTemplateModal
        open={saveModalOpen}
        onClose={() => setSaveModalOpen(false)}
        onSave={handleSaveTemplate}
        defaultName={selectedTemplate?.display_name || ''}
      />
    </div>
  );
};

export default SubmitLsdynaPanelWithTemplates;
