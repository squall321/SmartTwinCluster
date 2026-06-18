/**
 * Template Editor - YAML 기반 Template 편집/생성
 *
 * 기능:
 * - Template 생성
 * - Template 편집 (YAML)
 * - 실시간 검증
 * - Slurm Script 편집
 * - 파일 스키마 편집
 * - Apptainer 설정 편집
 */

import React, { useState, useEffect, useMemo } from 'react';
import { Save, X, FileText, Settings, Upload, Code, AlertCircle, CheckCircle, RefreshCw, Sparkles } from 'lucide-react';
import toast from 'react-hot-toast';
import { Template } from '../../types/template';
import { apiPost, apiPut } from '../../utils/api';
import { ApptainerImage } from '../../types/apptainer';
import { ImageSelector } from '../CommandTemplates/ImageSelector';
import { CommandTemplateInserter } from '../CommandTemplates/CommandTemplateInserter';
import { ScriptEditor } from '../ScriptEditor';
import { generateAllCompletionItems } from '../../utils/scriptCompletionItems';

interface TemplateEditorProps {
  template?: Template | null;  // null이면 새로 생성
  onClose: () => void;
  onSave: (template: Template) => void;
}

interface ValidationError {
  field: string;
  message: string;
}

export const TemplateEditor: React.FC<TemplateEditorProps> = ({
  template,
  onClose,
  onSave
}) => {
  const isNew = !template;
  const [activeTab, setActiveTab] = useState<'basic' | 'slurm' | 'apptainer' | 'files' | 'script' | 'yaml'>('basic');

  // 기본 샘플 데이터
  const defaultTemplateId = 'my-simulation-v1';
  const defaultDisplayName = '나만의 시뮬레이션';
  const defaultDescription = '새로운 시뮬레이션 템플릿입니다. 이 설명을 수정하세요.';
  const defaultTags = ['simulation', 'custom'];

  // 기본 파일 스키마 예제
  const defaultRequiredFiles = [
    {
      name: "입력 파일",
      file_key: "input_file",
      pattern: "*.dat",
      description: "시뮬레이션 입력 데이터 파일",
      type: "file",
      max_size: "100MB"
    }
  ];

  const defaultMainScript = `#!/bin/bash
# 작업 디렉토리 설정
echo "=== 시뮬레이션 시작 ==="
echo "작업 ID: $SLURM_JOB_ID"
echo "작업 이름: $SLURM_JOB_NAME"
echo "노드: $SLURM_NODELIST"
echo "시작 시간: $(date)"

# 작업 디렉토리로 이동
cd $SLURM_SUBMIT_DIR
echo "작업 디렉토리: $(pwd)"

# 사용 가능한 변수들:
# - Slurm 설정: $JOB_PARTITION, $JOB_NODES, $JOB_NTASKS, $JOB_CPUS_PER_TASK, $JOB_MEMORY, $JOB_TIME
# - 파일 경로: $FILE_INPUT_FILE (Files 탭에서 정의한 file_key 기반)
# - 작업 디렉토리: $WORK_DIR, $RESULT_DIR

# 예제: 업로드된 파일 사용
if [ -n "$FILE_INPUT_FILE" ]; then
    echo "입력 파일: $FILE_INPUT_FILE"
    # python3 simulation.py --input "$FILE_INPUT_FILE" --cores $JOB_NTASKS
fi

echo "시뮬레이션 완료"
echo "종료 시간: $(date)"`;

  // Basic Info
  const [templateId, setTemplateId] = useState(template?.template_id || template?.template?.id || defaultTemplateId);
  const [displayName, setDisplayName] = useState(template?.template?.display_name || template?.template?.name || defaultDisplayName);
  const [description, setDescription] = useState(template?.template?.description || defaultDescription);
  const [category, setCategory] = useState(template?.template?.category || template?.category || 'compute');
  const [source, setSource] = useState<'official' | 'community' | 'private'>((template?.source as 'official' | 'community' | 'private') || 'private');
  const [version, setVersion] = useState(template?.template?.version || '1.0.0');
  const [tags, setTags] = useState<string[]>(template?.template?.tags || defaultTags);
  const [isPublic, setIsPublic] = useState(template?.template?.is_public !== false);

  // Slurm Config
  const [partition, setPartition] = useState(template?.slurm?.partition || 'compute');
  const [nodes, setNodes] = useState(template?.slurm?.nodes || 1);
  const [ntasks, setNtasks] = useState(template?.slurm?.ntasks || 4);
  const [cpusPerTask, setCpusPerTask] = useState(template?.slurm?.cpus_per_task || 1);
  const [memory, setMemory] = useState(template?.slurm?.mem || '16G');
  const [time, setTime] = useState(template?.slurm?.time || '01:00:00');

  // Apptainer Config
  const [apptainerMode, setApptainerMode] = useState<'fixed' | 'partition' | 'specific' | 'any'>(
    template?.apptainer_normalized?.mode || 'partition'
  );
  const [fixedImageName, setFixedImageName] = useState(template?.apptainer?.image_name || '');
  const [apptainerPartition, setApptainerPartition] = useState(
    template?.apptainer_normalized?.partition || 'compute'
  );
  const [defaultImage, setDefaultImage] = useState(
    template?.apptainer_normalized?.default_image || ''
  );
  const [bindMounts, setBindMounts] = useState<string[]>(template?.apptainer?.bind || []);
  const [envVars, setEnvVars] = useState<Record<string, string>>(template?.apptainer?.env || {});

  // File Schema
  const [requiredFiles, setRequiredFiles] = useState<any[]>(
    template?.files?.input_schema?.required || defaultRequiredFiles
  );
  const [optionalFiles, setOptionalFiles] = useState<any[]>(
    template?.files?.input_schema?.optional || []
  );

  // Script
  const [preExecScript, setPreExecScript] = useState(template?.script?.pre_exec || '');
  const [mainExecScript, setMainExecScript] = useState(template?.script?.main_exec || defaultMainScript);
  const [postExecScript, setPostExecScript] = useState(template?.script?.post_exec || '');

  // YAML (전체)
  const [yamlContent, setYamlContent] = useState('');

  // Validation
  const [validationErrors, setValidationErrors] = useState<ValidationError[]>([]);
  const [isSaving, setIsSaving] = useState(false);

  // Command Template System
  const [selectedApptainerImage, setSelectedApptainerImage] = useState<ApptainerImage | null>(null);
  const [showTemplateInserter, setShowTemplateInserter] = useState(false);

  // Generate dynamic autocomplete items for Monaco Editor
  const completionItems = useMemo(() => {
    return generateAllCompletionItems(
      {
        partition,
        nodes,
        ntasks,
        cpus_per_task: cpusPerTask,
        mem: memory,
        time,
      },
      requiredFiles,
      optionalFiles
    );
  }, [partition, nodes, ntasks, cpusPerTask, memory, time, requiredFiles, optionalFiles]);

  // Template prop이 변경될 때 state 업데이트
  useEffect(() => {
    console.log('🔄 Template prop changed:', template);
    if (template) {
      console.log('📝 template_id:', template.template_id);
      console.log('📝 template.template.id:', template.template?.id);
      console.log('📝 template.template:', template.template);
      console.log('📝 template.script:', template.script);
      console.log('📝 main_exec:', template.script?.main_exec);

      setTemplateId(template.template_id || template.template?.id || '');
      setDisplayName(template.template?.display_name || template.template?.name || '');
      setDescription(template.template?.description || '');
      setCategory(template.template?.category || template.category || 'compute');
      setSource((template.source as 'official' | 'community' | 'private') || 'private');
      setVersion(template.template?.version || '1.0.0');
      setTags(template.template?.tags || []);
      setIsPublic(template.template?.is_public !== false);

      setPartition(template.slurm?.partition || 'compute');
      setNodes(template.slurm?.nodes || 1);
      setNtasks(template.slurm?.ntasks || 1);
      setCpusPerTask(template.slurm?.cpus_per_task || 1);
      setMemory(template.slurm?.mem || '16G');
      setTime(template.slurm?.time || '01:00:00');

      setApptainerMode(template.apptainer_normalized?.mode || 'partition');
      setFixedImageName(template.apptainer?.image_name || '');
      setApptainerPartition(template.apptainer_normalized?.partition || 'compute');
      setDefaultImage(template.apptainer_normalized?.default_image || '');
      setBindMounts(template.apptainer?.bind || []);
      setEnvVars(template.apptainer?.env || {});

      setRequiredFiles(template.files?.input_schema?.required || []);
      setOptionalFiles(template.files?.input_schema?.optional || []);

      setPreExecScript(template.script?.pre_exec || '');
      setMainExecScript(template.script?.main_exec || '');
      setPostExecScript(template.script?.post_exec || '');

      console.log('✅ State updated');
    } else {
      console.log('⚠️ Template is null or undefined - using default values');
      // 새 템플릿 생성 시 기본값 유지 (이미 useState 초기값으로 설정됨)
    }
  }, [template]);

  // YAML 생성
  useEffect(() => {
    const yaml = generateYAML();
    setYamlContent(yaml);
  }, [
    templateId, displayName, description, category, source, version, tags, isPublic,
    partition, nodes, ntasks, cpusPerTask, memory, time,
    apptainerMode, fixedImageName, apptainerPartition, defaultImage, bindMounts, envVars,
    requiredFiles, optionalFiles,
    preExecScript, mainExecScript, postExecScript
  ]);

  // Pre-exec 스크립트 자동 생성 (변수 가이드 포함)
  const generatePreExecWithVariables = (): string => {
    const lines: string[] = [];

    lines.push('#!/bin/bash');
    lines.push('# =============================================================================');
    lines.push('# 자동 생성된 환경 변수 - Job Submit 시 실제 값으로 치환됩니다');
    lines.push('# =============================================================================');
    lines.push('');

    // Slurm 설정 변수
    lines.push('# --- Slurm 설정 변수 ---');
    lines.push(`export JOB_PARTITION="${partition}"`);
    lines.push(`export JOB_NODES=${nodes}`);
    lines.push(`export JOB_NTASKS=${ntasks}`);
    lines.push(`export JOB_CPUS_PER_TASK=${cpusPerTask}`);
    lines.push(`export JOB_MEMORY="${memory}"`);
    lines.push(`export JOB_TIME="${time}"`);
    lines.push('');

    // 파일 변수 (file_key 기반)
    if (requiredFiles.length > 0 || optionalFiles.length > 0) {
      lines.push('# --- 업로드된 파일 경로 변수 (file_key 기반) ---');
      lines.push('# 단일 파일: FILE_<FILE_KEY>="/path/to/file"');
      lines.push('# 복수 파일: FILE_<FILE_KEY>="/path/to/file1 /path/to/file2" (공백으로 구분)');
      lines.push('#            FILE_<FILE_KEY>_COUNT=2 (파일 개수)');
      lines.push('');

      [...requiredFiles, ...optionalFiles].forEach(file => {
        const varName = file.file_key?.toUpperCase() || 'UNKNOWN';
        const filePattern = file.pattern || file.validation?.extensions?.join(', ') || '*.*';
        lines.push(`# ${file.name || 'File'} (${filePattern})`);
        lines.push(`# export FILE_${varName}="/path/to/uploaded/file"`);

        // 복수 파일 가능성 체크 (pattern에 *가 있거나 설명에 복수 언급)
        if (file.pattern?.includes('*') || file.description?.includes('들') || file.description?.includes('파일들')) {
          lines.push(`# export FILE_${varName}_COUNT=1  # 업로드된 파일 개수`);
        }
        lines.push('');
      });
    }

    // 작업 디렉토리 변수
    lines.push('# --- 작업 디렉토리 ---');
    lines.push('export WORK_DIR="$SLURM_SUBMIT_DIR"');
    lines.push('export RESULT_DIR="$WORK_DIR/results"');
    lines.push('mkdir -p "$RESULT_DIR"');
    lines.push('');

    lines.push('# =============================================================================');
    lines.push('# 여기에 추가 초기화 스크립트를 작성하세요');
    lines.push('# =============================================================================');
    lines.push('');

    // 사용자 정의 pre-exec이 있으면 추가
    if (preExecScript && preExecScript.trim() && !preExecScript.includes('자동 생성된 환경 변수')) {
      lines.push(preExecScript);
    }

    return lines.join('\n');
  };

  const generateYAML = (): string => {
    const yaml: string[] = [];

    // Template Info
    yaml.push('# Template Configuration');
    yaml.push('template:');
    yaml.push(`  id: "${templateId}"`);
    yaml.push(`  name: ${templateId.replace(/-/g, '_')}`);
    yaml.push(`  display_name: "${displayName}"`);
    yaml.push(`  description: "${description}"`);
    yaml.push(`  category: ${category}`);
    yaml.push(`  source: ${source}`);
    yaml.push(`  tags: [${tags.map(t => `"${t}"`).join(', ')}]`);
    yaml.push(`  version: "${version}"`);
    yaml.push(`  author: admin`);
    yaml.push(`  is_public: ${isPublic}`);
    yaml.push('');

    // Slurm Config
    yaml.push('slurm:');
    yaml.push(`  partition: ${partition}`);
    yaml.push(`  nodes: ${nodes}`);
    yaml.push(`  ntasks: ${ntasks}`);
    yaml.push(`  cpus_per_task: ${cpusPerTask}`);
    yaml.push(`  mem: ${memory}`);
    yaml.push(`  time: "${time}"`);
    yaml.push('');

    // Apptainer Config
    yaml.push('apptainer:');
    if (apptainerMode === 'fixed') {
      yaml.push(`  image_name: "${fixedImageName}"`);
    } else {
      yaml.push('  image_selection:');
      yaml.push(`    mode: "${apptainerMode}"`);
      if (apptainerMode === 'partition') {
        yaml.push(`    partition: "${apptainerPartition}"`);
      }
      if (defaultImage) {
        yaml.push(`    default_image: "${defaultImage}"`);
      }
      yaml.push('    required: true');
    }

    if (bindMounts.length > 0) {
      yaml.push('  bind:');
      bindMounts.forEach(mount => {
        yaml.push(`    - ${mount}`);
      });
    }

    if (Object.keys(envVars).length > 0) {
      yaml.push('  env:');
      Object.entries(envVars).forEach(([key, value]) => {
        yaml.push(`    ${key}: "${value}"`);
      });
    }
    yaml.push('');

    // File Schema
    if (requiredFiles.length > 0 || optionalFiles.length > 0) {
      yaml.push('files:');
      yaml.push('  input_schema:');

      if (requiredFiles.length > 0) {
        yaml.push('    required:');
        requiredFiles.forEach(file => {
          yaml.push(`      - name: "${file.name}"`);
          yaml.push(`        file_key: "${file.file_key}"`);
          yaml.push(`        pattern: "${file.pattern}"`);
          yaml.push(`        description: "${file.description}"`);
          yaml.push(`        type: "${file.type}"`);
          yaml.push(`        max_size: "${file.max_size}"`);
          if (file.validation) {
            yaml.push('        validation:');
            if (file.validation.extensions) {
              yaml.push(`          extensions: [${file.validation.extensions.map((e: string) => `"${e}"`).join(', ')}]`);
            }
            if (file.validation.mime_types) {
              yaml.push(`          mime_types: [${file.validation.mime_types.map((m: string) => `"${m}"`).join(', ')}]`);
            }
          }
        });
      }

      if (optionalFiles.length > 0) {
        yaml.push('    optional:');
        optionalFiles.forEach(file => {
          yaml.push(`      - name: "${file.name}"`);
          yaml.push(`        file_key: "${file.file_key}"`);
          yaml.push(`        pattern: "${file.pattern}"`);
        });
      }

      yaml.push('  output_pattern: "results/**/*"');
      yaml.push('');
    }

    // Script
    yaml.push('script:');
    yaml.push('  pre_exec: |');
    const generatedPreExec = generatePreExecWithVariables();
    generatedPreExec.split('\n').forEach(line => {
      yaml.push(`    ${line}`);
    });
    yaml.push('');

    yaml.push('  main_exec: |');
    mainExecScript.split('\n').forEach(line => {
      yaml.push(`    ${line}`);
    });
    yaml.push('');

    yaml.push('  post_exec: |');
    postExecScript.split('\n').forEach(line => {
      yaml.push(`    ${line}`);
    });

    return yaml.join('\n');
  };

  const validateTemplate = (): ValidationError[] => {
    const errors: ValidationError[] = [];

    console.log('🔍 Validating template...');
    console.log('  templateId:', templateId, '(empty:', !templateId, ')');
    console.log('  displayName:', displayName, '(empty:', !displayName, ')');
    console.log('  mainExecScript:', mainExecScript?.substring(0, 50), '(empty:', !mainExecScript, ')');

    if (!templateId) {
      errors.push({ field: 'templateId', message: 'Template ID is required' });
    }
    if (!displayName) {
      errors.push({ field: 'displayName', message: 'Display name is required' });
    }
    if (apptainerMode === 'fixed' && !fixedImageName) {
      errors.push({ field: 'fixedImageName', message: 'Image name is required for fixed mode' });
    }
    if (!mainExecScript) {
      errors.push({ field: 'mainExecScript', message: 'Main execution script is required' });
    }

    // file_key 중복 체크
    const allFiles = [...requiredFiles, ...optionalFiles];
    const fileKeys = allFiles.map(f => f.file_key).filter(Boolean);
    const duplicates = fileKeys.filter((key, index) => fileKeys.indexOf(key) !== index);

    if (duplicates.length > 0) {
      errors.push({
        field: 'file_key',
        message: `Duplicate file_key found: ${[...new Set(duplicates)].join(', ')}`
      });
    }

    // file_key 형식 검증 (영문자, 숫자, 언더스코어만 허용)
    const invalidKeys = allFiles.filter(f =>
      f.file_key && !/^[a-z0-9_]+$/i.test(f.file_key)
    );
    if (invalidKeys.length > 0) {
      errors.push({
        field: 'file_key',
        message: `Invalid file_key format (use only letters, numbers, and underscores): ${invalidKeys.map(f => f.file_key).join(', ')}`
      });
    }

    // file_key 비어있는지 체크
    const emptyKeys = allFiles.filter(f => !f.file_key || f.file_key.trim() === '');
    if (emptyKeys.length > 0) {
      errors.push({
        field: 'file_key',
        message: 'All files must have a file_key'
      });
    }

    console.log('  Validation errors:', errors);
    return errors;
  };

  const handleSave = async () => {
    // 검증
    const errors = validateTemplate();
    if (errors.length > 0) {
      setValidationErrors(errors);
      console.error('Validation errors:', errors);
      const errorMessages = errors.map(e => `${e.field}: ${e.message}`).join(', ');
      toast.error(`Validation failed: ${errorMessages}`);
      return;
    }

    setIsSaving(true);
    try {
      // Backend API 호출
      const actualTemplateId = template?.template_id || template?.template?.id || templateId;
      console.log('💾 Saving template...');
      console.log('  Template ID:', actualTemplateId);
      console.log('  Is New:', isNew);
      console.log('  YAML Content Length:', yamlContent.length);
      console.log('  YAML Preview:', yamlContent.substring(0, 200));

      const endpoint = isNew
        ? '/api/jobs/templates'
        : `/api/jobs/templates/${actualTemplateId}`;

      console.log('  Endpoint:', endpoint);

      // source에 따라 is_public 결정
      // - private: is_public=false (개인 템플릿)
      // - community: is_public=true (커뮤니티 공유)
      // - official: is_public=true + source=official (관리자 전용, Backend에서 처리)
      const requestData = {
        yaml: yamlContent,
        source: source,
        is_public: source !== 'private'
      };

      const response: any = isNew
        ? await apiPost(endpoint, requestData)
        : await apiPut(endpoint, requestData);

      console.log('✅ Save response:', response);

      // 백엔드는 { message, file_path, template_id }를 반환
      if (response.template_id || response.message) {
        toast.success(response.message || `Template ${isNew ? 'created' : 'updated'} successfully`);
        // 템플릿 목록 새로고침을 위해 빈 객체라도 전달
        onSave(response as any);
        onClose();
      } else if (response.error) {
        toast.error(response.error);
      } else {
        toast.error('Failed to save template');
      }
    } catch (error: any) {
      console.error('❌ Failed to save template:', error);
      console.error('  Error type:', typeof error);
      console.error('  Error message:', error?.message);
      console.error('  Error response:', error?.response);
      console.error('  Full error:', JSON.stringify(error, null, 2));

      const errorMsg = error?.message || error?.error || 'Failed to save template';
      toast.error(errorMsg);
    } finally {
      setIsSaving(false);
    }
  };

  const addRequiredFile = () => {
    // 기존 file_key 개수 기반으로 유니크한 키 자동 생성
    const existingKeys = [...requiredFiles, ...optionalFiles]
      .map(f => f.file_key)
      .filter(Boolean);

    let newKey = 'input_file';
    let counter = 1;
    while (existingKeys.includes(newKey)) {
      counter++;
      newKey = `input_file_${counter}`;
    }

    setRequiredFiles([...requiredFiles, {
      name: '',
      file_key: newKey,  // 자동 생성된 유니크한 키
      pattern: '*.*',
      description: '',
      type: 'file',
      max_size: '100MB',
      validation: {
        extensions: [],
        mime_types: []
      }
    }]);
  };

  const removeRequiredFile = (index: number) => {
    setRequiredFiles(requiredFiles.filter((_, i) => i !== index));
  };

  const updateRequiredFile = (index: number, field: string, value: any) => {
    const updated = [...requiredFiles];
    if (field.startsWith('validation.')) {
      const validationField = field.split('.')[1];
      updated[index].validation[validationField] = value;
    } else {
      updated[index][field] = value;
    }
    setRequiredFiles(updated);
  };

  const addBindMount = () => {
    setBindMounts([...bindMounts, '/shared:/shared:ro']);
  };

  const removeBindMount = (index: number) => {
    setBindMounts(bindMounts.filter((_, i) => i !== index));
  };

  const updateBindMount = (index: number, value: string) => {
    const updated = [...bindMounts];
    updated[index] = value;
    setBindMounts(updated);
  };

  const addEnvVar = () => {
    const key = prompt('Environment variable name:');
    if (key) {
      setEnvVars({ ...envVars, [key]: '' });
    }
  };

  const removeEnvVar = (key: string) => {
    const updated = { ...envVars };
    delete updated[key];
    setEnvVars(updated);
  };

  const updateEnvVar = (key: string, value: string) => {
    setEnvVars({ ...envVars, [key]: value });
  };

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
      <div className="bg-white rounded-lg max-w-7xl w-full h-[95vh] flex flex-col">
        {/* Header */}
        <div className="p-6 border-b flex items-center justify-between">
          <div>
            <h2 className="text-2xl font-bold">
              {isNew ? 'Create New Template' : `Edit Template: ${displayName}`}
            </h2>
            {validationErrors.length > 0 && (
              <div className="mt-2 flex items-center gap-2 text-red-600 text-sm">
                <AlertCircle className="w-4 h-4" />
                <span>{validationErrors.length} validation error(s)</span>
              </div>
            )}
          </div>
          <button
            onClick={onClose}
            className="text-gray-400 hover:text-gray-600"
          >
            <X className="w-6 h-6" />
          </button>
        </div>

        {/* Tabs */}
        <div className="flex border-b px-6 overflow-x-auto">
          {[
            { id: 'basic', label: 'Basic Info', icon: FileText },
            { id: 'slurm', label: 'Slurm Config', icon: Settings },
            { id: 'apptainer', label: 'Apptainer', icon: Settings },
            { id: 'files', label: 'File Schema', icon: Upload },
            { id: 'script', label: 'Scripts', icon: Code },
            { id: 'yaml', label: 'YAML Preview', icon: FileText },
          ].map(tab => {
            const Icon = tab.icon;
            return (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id as any)}
                className={`px-4 py-3 flex items-center gap-2 border-b-2 transition-colors whitespace-nowrap ${
                  activeTab === tab.id
                    ? 'border-blue-600 text-blue-600 font-medium'
                    : 'border-transparent text-gray-600 hover:text-gray-900'
                }`}
              >
                <Icon className="w-4 h-4" />
                {tab.label}
              </button>
            );
          })}
        </div>

        {/* Content */}
        <div className="flex-1 overflow-y-auto p-6">
          {/* Basic Info Tab */}
          {activeTab === 'basic' && (
            <div className="space-y-4 max-w-2xl">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Template ID * <span className="text-xs text-gray-500">(kebab-case)</span>
                </label>
                <input
                  type="text"
                  value={templateId}
                  onChange={(e) => setTemplateId(e.target.value)}
                  disabled={!isNew}
                  placeholder="my-simulation-template"
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 disabled:bg-gray-100"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Display Name *
                </label>
                <input
                  type="text"
                  value={displayName}
                  onChange={(e) => setDisplayName(e.target.value)}
                  placeholder="My Simulation Template"
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Description
                </label>
                <textarea
                  value={description}
                  onChange={(e) => setDescription(e.target.value)}
                  rows={3}
                  placeholder="Brief description of this template..."
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
                />
              </div>

              <div className="grid grid-cols-3 gap-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Category
                  </label>
                  <select
                    value={category}
                    onChange={(e) => setCategory(e.target.value)}
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
                  >
                    <option value="compute">Compute</option>
                    <option value="structural">Structural</option>
                    <option value="simulation">Simulation</option>
                    <option value="ml">Machine Learning</option>
                    <option value="viz">Visualization</option>
                  </select>
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Source
                  </label>
                  <select
                    value={source}
                    onChange={(e) => setSource(e.target.value as 'official' | 'community' | 'private')}
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
                  >
                    <option value="private">Private</option>
                    <option value="community">Community</option>
                    <option value="official">Official</option>
                  </select>
                  <p className="mt-1 text-xs text-gray-500">
                    Private: 개인용 / Community: 공개 공유 / Official: 관리자 전용
                  </p>
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Version
                  </label>
                  <input
                    type="text"
                    value={version}
                    onChange={(e) => setVersion(e.target.value)}
                    placeholder="1.0.0"
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
                  />
                </div>
              </div>

              <div>
                <label className="flex items-center gap-2">
                  <input
                    type="checkbox"
                    checked={isPublic}
                    onChange={(e) => setIsPublic(e.target.checked)}
                    className="w-4 h-4 text-blue-600 rounded"
                  />
                  <span className="text-sm text-gray-700">Public Template</span>
                </label>
              </div>
            </div>
          )}

          {/* Slurm Config Tab */}
          {activeTab === 'slurm' && (
            <div className="space-y-4 max-w-2xl">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Partition
                </label>
                <select
                  value={partition}
                  onChange={(e) => setPartition(e.target.value)}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
                >
                  <option value="compute">Compute</option>
                  <option value="viz">Visualization</option>
                  <option value="gpu">GPU</option>
                </select>
              </div>

              <div className="grid grid-cols-3 gap-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Nodes
                  </label>
                  <input
                    type="number"
                    value={nodes}
                    onChange={(e) => setNodes(parseInt(e.target.value))}
                    min="1"
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Tasks
                  </label>
                  <input
                    type="number"
                    value={ntasks}
                    onChange={(e) => setNtasks(parseInt(e.target.value))}
                    min="1"
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    CPUs/Task
                  </label>
                  <input
                    type="number"
                    value={cpusPerTask}
                    onChange={(e) => setCpusPerTask(parseInt(e.target.value))}
                    min="1"
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
                  />
                </div>
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Memory (e.g., 16G, 64G)
                  </label>
                  <input
                    type="text"
                    value={memory}
                    onChange={(e) => setMemory(e.target.value)}
                    placeholder="16G"
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Time Limit (HH:MM:SS)
                  </label>
                  <input
                    type="text"
                    value={time}
                    onChange={(e) => setTime(e.target.value)}
                    placeholder="01:00:00"
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
                  />
                </div>
              </div>
            </div>
          )}

          {/* Apptainer Config Tab */}
          {activeTab === 'apptainer' && (
            <div className="space-y-4 max-w-2xl">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Image Selection Mode
                </label>
                <select
                  value={apptainerMode}
                  onChange={(e) => setApptainerMode(e.target.value as any)}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
                >
                  <option value="fixed">Fixed (하나의 이미지만 사용)</option>
                  <option value="partition">Partition (파티션별 필터링)</option>
                  <option value="specific">Specific (특정 이미지만)</option>
                  <option value="any">Any (모든 이미지)</option>
                </select>
              </div>

              {apptainerMode === 'fixed' && (
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Image Name *
                  </label>
                  <input
                    type="text"
                    value={fixedImageName}
                    onChange={(e) => setFixedImageName(e.target.value)}
                    placeholder="KooSimulationPython313.sif"
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
                  />
                </div>
              )}

              {apptainerMode === 'partition' && (
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Partition Filter
                  </label>
                  <select
                    value={apptainerPartition}
                    onChange={(e) => setApptainerPartition(e.target.value)}
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
                  >
                    <option value="compute">Compute</option>
                    <option value="viz">Visualization</option>
                  </select>
                </div>
              )}

              {apptainerMode !== 'fixed' && (
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Default Image (Optional)
                  </label>
                  <input
                    type="text"
                    value={defaultImage}
                    onChange={(e) => setDefaultImage(e.target.value)}
                    placeholder="KooSimulationPython313.sif"
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
                  />
                </div>
              )}

              {/* Image Selector - Command Template System */}
              {apptainerMode === 'partition' && (
                <div className="mt-6">
                  <div className="mb-3 p-3 bg-blue-50 border border-blue-200 rounded-lg">
                    <div className="flex items-center gap-2 text-blue-900 text-sm font-medium mb-1">
                      <Sparkles className="w-4 h-4" />
                      Command Template System
                    </div>
                    <p className="text-xs text-blue-700">
                      Browse available Apptainer images and their pre-configured command templates
                    </p>
                  </div>

                  <ImageSelector
                    partition={apptainerPartition}
                    selectedImage={selectedApptainerImage}
                    onSelect={(image) => {
                      setSelectedApptainerImage(image);
                      setDefaultImage(image.name);
                      toast.success(`Selected: ${image.name}`);
                    }}
                    className="max-w-full"
                  />
                </div>
              )}

              {/* Bind Mounts */}
              <div>
                <div className="flex items-center justify-between mb-2">
                  <label className="text-sm font-medium text-gray-700">
                    Bind Mounts
                  </label>
                  <button
                    onClick={addBindMount}
                    className="text-sm text-blue-600 hover:text-blue-700"
                  >
                    + Add
                  </button>
                </div>
                {bindMounts.map((mount, index) => (
                  <div key={index} className="flex gap-2 mb-2">
                    <input
                      type="text"
                      value={mount}
                      onChange={(e) => updateBindMount(index, e.target.value)}
                      placeholder="/host:/container:ro"
                      className="flex-1 px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 text-sm"
                    />
                    <button
                      onClick={() => removeBindMount(index)}
                      className="px-3 py-2 text-red-600 hover:bg-red-50 rounded-lg"
                    >
                      <X className="w-4 h-4" />
                    </button>
                  </div>
                ))}
              </div>

              {/* Environment Variables */}
              <div>
                <div className="flex items-center justify-between mb-2">
                  <label className="text-sm font-medium text-gray-700">
                    Environment Variables
                  </label>
                  <button
                    onClick={addEnvVar}
                    className="text-sm text-blue-600 hover:text-blue-700"
                  >
                    + Add
                  </button>
                </div>
                {Object.entries(envVars).map(([key, value]) => (
                  <div key={key} className="flex gap-2 mb-2">
                    <input
                      type="text"
                      value={key}
                      disabled
                      className="w-1/3 px-3 py-2 border border-gray-300 rounded-lg bg-gray-50 text-sm"
                    />
                    <input
                      type="text"
                      value={value}
                      onChange={(e) => updateEnvVar(key, e.target.value)}
                      placeholder="value"
                      className="flex-1 px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 text-sm"
                    />
                    <button
                      onClick={() => removeEnvVar(key)}
                      className="px-3 py-2 text-red-600 hover:bg-red-50 rounded-lg"
                    >
                      <X className="w-4 h-4" />
                    </button>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* File Schema Tab */}
          {activeTab === 'files' && (
            <div className="space-y-6">
              <div>
                <div className="flex items-center justify-between mb-3">
                  <h3 className="text-lg font-semibold">Required Files</h3>
                  <button
                    onClick={addRequiredFile}
                    className="px-3 py-1.5 bg-blue-600 text-white rounded-lg hover:bg-blue-700 text-sm"
                  >
                    + Add File
                  </button>
                </div>

                {requiredFiles.map((file, index) => (
                  <div key={index} className="border border-gray-200 rounded-lg p-4 mb-3">
                    <div className="flex items-start justify-between mb-3">
                      <h4 className="font-medium">File #{index + 1}</h4>
                      <button
                        onClick={() => removeRequiredFile(index)}
                        className="text-red-600 hover:text-red-700"
                      >
                        <X className="w-5 h-5" />
                      </button>
                    </div>

                    <div className="grid grid-cols-2 gap-3">
                      <div>
                        <label className="block text-xs font-medium text-gray-700 mb-1">
                          Display Name *
                        </label>
                        <input
                          type="text"
                          value={file.name}
                          onChange={(e) => updateRequiredFile(index, 'name', e.target.value)}
                          placeholder="형상 파일"
                          className="w-full px-2 py-1.5 border border-gray-300 rounded text-sm"
                        />
                      </div>

                      <div>
                        <label className="block text-xs font-medium text-gray-700 mb-1">
                          File Key * <span className="text-gray-500">(internal)</span>
                        </label>
                        <input
                          type="text"
                          value={file.file_key}
                          onChange={(e) => updateRequiredFile(index, 'file_key', e.target.value)}
                          placeholder="geometry"
                          className="w-full px-2 py-1.5 border border-gray-300 rounded text-sm"
                        />
                        {file.file_key && (
                          <div className="mt-1 text-xs bg-blue-50 dark:bg-blue-900/20 text-blue-700 dark:text-blue-300 p-2 rounded">
                            <div className="font-medium mb-0.5">Will create variables:</div>
                            <code className="text-xs font-mono">
                              $FILE_{file.file_key.toUpperCase()}
                            </code>
                            {(file.pattern?.includes('*') || file.description?.includes('들')) && (
                              <>
                                <br />
                                <code className="text-xs font-mono">
                                  $FILE_{file.file_key.toUpperCase()}_COUNT
                                </code>
                                <span className="ml-1 text-gray-600 dark:text-gray-400">(for multiple files)</span>
                              </>
                            )}
                          </div>
                        )}
                      </div>

                      <div>
                        <label className="block text-xs font-medium text-gray-700 mb-1">
                          Pattern
                        </label>
                        <input
                          type="text"
                          value={file.pattern || ''}
                          onChange={(e) => updateRequiredFile(index, 'pattern', e.target.value)}
                          placeholder="*.stl"
                          className="w-full px-2 py-1.5 border border-gray-300 rounded text-sm"
                        />
                      </div>

                      <div>
                        <label className="block text-xs font-medium text-gray-700 mb-1">
                          Max Size
                        </label>
                        <input
                          type="text"
                          value={file.max_size || file.validation?.max_size || ''}
                          onChange={(e) => updateRequiredFile(index, 'max_size', e.target.value)}
                          placeholder="500MB"
                          className="w-full px-2 py-1.5 border border-gray-300 rounded text-sm"
                        />
                      </div>

                      <div className="col-span-2">
                        <label className="block text-xs font-medium text-gray-700 mb-1">
                          Description
                        </label>
                        <input
                          type="text"
                          value={file.description}
                          onChange={(e) => updateRequiredFile(index, 'description', e.target.value)}
                          placeholder="입력 형상 파일 (STL)"
                          className="w-full px-2 py-1.5 border border-gray-300 rounded text-sm"
                        />
                      </div>

                      <div>
                        <label className="block text-xs font-medium text-gray-700 mb-1">
                          Extensions (comma-separated)
                        </label>
                        <input
                          type="text"
                          value={file.validation?.extensions?.join(', ') || ''}
                          onChange={(e) => updateRequiredFile(
                            index,
                            'validation.extensions',
                            e.target.value.split(',').map((s: string) => s.trim()).filter(Boolean)
                          )}
                          placeholder=".stl, .STL"
                          className="w-full px-2 py-1.5 border border-gray-300 rounded text-sm"
                        />
                      </div>

                      <div>
                        <label className="block text-xs font-medium text-gray-700 mb-1">
                          MIME Types (comma-separated)
                        </label>
                        <input
                          type="text"
                          value={file.validation?.mime_types?.join(', ') || ''}
                          onChange={(e) => updateRequiredFile(
                            index,
                            'validation.mime_types',
                            e.target.value.split(',').map((s: string) => s.trim()).filter(Boolean)
                          )}
                          placeholder="model/stl, application/octet-stream"
                          className="w-full px-2 py-1.5 border border-gray-300 rounded text-sm"
                        />
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Script Tab */}
          {activeTab === 'script' && (
            <div className="space-y-4">
              {/* Variable Guide Panel */}
              <div className="bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-800 rounded-lg p-4">
                <h4 className="text-sm font-semibold text-blue-900 dark:text-blue-200 mb-3">
                  📋 Available Variables (auto-injected at runtime)
                </h4>

                <div className="grid grid-cols-1 md:grid-cols-2 gap-4 text-xs">
                  {/* Slurm Variables */}
                  <div>
                    <h5 className="font-medium text-blue-800 dark:text-blue-300 mb-2">Slurm Configuration:</h5>
                    <ul className="space-y-1 font-mono text-gray-700 dark:text-gray-300">
                      <li><code className="bg-white dark:bg-gray-800 px-1 rounded">$JOB_PARTITION</code> = "{partition}"</li>
                      <li><code className="bg-white dark:bg-gray-800 px-1 rounded">$JOB_NODES</code> = {nodes}</li>
                      <li><code className="bg-white dark:bg-gray-800 px-1 rounded">$JOB_NTASKS</code> = {ntasks}</li>
                      <li><code className="bg-white dark:bg-gray-800 px-1 rounded">$JOB_CPUS_PER_TASK</code> = {cpusPerTask}</li>
                      <li><code className="bg-white dark:bg-gray-800 px-1 rounded">$JOB_MEMORY</code> = "{memory}"</li>
                      <li><code className="bg-white dark:bg-gray-800 px-1 rounded">$JOB_TIME</code> = "{time}"</li>
                    </ul>
                  </div>

                  {/* File Variables */}
                  <div>
                    <h5 className="font-medium text-blue-800 dark:text-blue-300 mb-2">Uploaded Files:</h5>
                    {[...requiredFiles, ...optionalFiles].length > 0 ? (
                      <ul className="space-y-1 font-mono text-gray-700 dark:text-gray-300">
                        {[...requiredFiles, ...optionalFiles].map((file, idx) => (
                          <li key={idx}>
                            <code className="bg-white dark:bg-gray-800 px-1 rounded">
                              $FILE_{file.file_key?.toUpperCase() || 'UNKNOWN'}
                            </code>
                            <span className="text-gray-600 dark:text-gray-400 ml-1">- {file.name || file.pattern || 'File'}</span>
                            {(file.pattern?.includes('*') || file.description?.includes('들')) && (
                              <div className="ml-4 text-gray-500">
                                <code className="bg-white dark:bg-gray-800 px-1 rounded">
                                  $FILE_{file.file_key?.toUpperCase() || 'UNKNOWN'}_COUNT
                                </code>
                              </div>
                            )}
                          </li>
                        ))}
                      </ul>
                    ) : (
                      <p className="text-gray-500 dark:text-gray-400 italic">No files defined yet</p>
                    )}
                  </div>

                  {/* Directory Variables */}
                  <div>
                    <h5 className="font-medium text-blue-800 dark:text-blue-300 mb-2">Directories:</h5>
                    <ul className="space-y-1 font-mono text-gray-700 dark:text-gray-300">
                      <li><code className="bg-white dark:bg-gray-800 px-1 rounded">$WORK_DIR</code> - Working directory</li>
                      <li><code className="bg-white dark:bg-gray-800 px-1 rounded">$RESULT_DIR</code> - Results directory</li>
                    </ul>
                  </div>
                </div>
              </div>

              <div>
                <div className="flex items-center justify-between mb-1">
                  <label className="block text-sm font-medium text-gray-700">
                    Pre-execution Script
                    <span className="text-xs text-gray-500 ml-2">(Setup, create directories, etc.)</span>
                  </label>
                  <button
                    type="button"
                    onClick={() => setPreExecScript(generatePreExecWithVariables())}
                    className="text-xs px-2 py-1 bg-blue-100 text-blue-700 hover:bg-blue-200 rounded flex items-center gap-1"
                    title="Regenerate variable guide based on current configuration"
                  >
                    <RefreshCw className="w-3 h-3" />
                    Refresh Variables
                  </button>
                </div>
                <ScriptEditor
                  value={preExecScript}
                  onChange={setPreExecScript}
                  height="300px"
                  language="shell"
                  theme="vs-dark"
                  completionItems={completionItems}
                  placeholder="#!/bin/bash&#10;echo 'Starting job...'&#10;mkdir -p output"
                />
              </div>

              <div>
                <div className="flex items-center justify-between mb-1">
                  <label className="block text-sm font-medium text-gray-700">
                    Main Execution Script *
                    <span className="text-xs text-gray-500 ml-2">(Core computation)</span>
                  </label>

                  {/* Command Template Inserter Button */}
                  {selectedApptainerImage && selectedApptainerImage.command_templates && selectedApptainerImage.command_templates.length > 0 && (
                    <button
                      type="button"
                      onClick={() => setShowTemplateInserter(true)}
                      className="text-xs px-3 py-1.5 bg-gradient-to-r from-purple-600 to-blue-600 text-white hover:from-purple-700 hover:to-blue-700 rounded flex items-center gap-1.5 shadow-sm"
                      title="Insert command template from selected Apptainer image"
                    >
                      <Sparkles className="w-3.5 h-3.5" />
                      Insert Command Template
                    </button>
                  )}
                </div>

                {/* Info message when image is selected */}
                {selectedApptainerImage && selectedApptainerImage.command_templates && selectedApptainerImage.command_templates.length > 0 && (
                  <div className="mb-2 p-2 bg-purple-50 border border-purple-200 rounded text-xs text-purple-700">
                    <strong>{selectedApptainerImage.command_templates.length}</strong> command template{selectedApptainerImage.command_templates.length !== 1 ? 's' : ''} available from <strong>{selectedApptainerImage.name}</strong>. Click "Insert Command Template" to use them.
                  </div>
                )}

                <ScriptEditor
                  value={mainExecScript}
                  onChange={setMainExecScript}
                  height="500px"
                  language="shell"
                  theme="vs-dark"
                  completionItems={completionItems}
                  placeholder="#!/bin/bash&#10;apptainer exec $APPTAINER_IMAGE python3 simulation.py"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Post-execution Script
                  <span className="text-xs text-gray-500 ml-2">(Cleanup, collect results, etc.)</span>
                </label>
                <ScriptEditor
                  value={postExecScript}
                  onChange={setPostExecScript}
                  height="300px"
                  language="shell"
                  theme="vs-dark"
                  completionItems={completionItems}
                  placeholder="#!/bin/bash&#10;echo 'Job completed'&#10;cp output/* /shared/results/"
                />
              </div>

              <div className="p-4 bg-blue-50 border border-blue-200 rounded-lg">
                <h4 className="text-sm font-semibold text-blue-900 mb-2">💡 Available Variables</h4>
                <div className="text-xs text-blue-700 space-y-1">
                  <div><code className="bg-white px-1 py-0.5 rounded">$APPTAINER_IMAGE</code> - Apptainer 이미지 경로</div>
                  <div><code className="bg-white px-1 py-0.5 rounded">$SLURM_SUBMIT_DIR</code> - 작업 디렉토리</div>
                  <div><code className="bg-white px-1 py-0.5 rounded">$SLURM_JOB_ID</code> - Job ID</div>
                  <div><code className="bg-white px-1 py-0.5 rounded">${'${FILE_KEY}'}_FILE</code> - 업로드된 파일 경로 (예: $GEOMETRY_FILE)</div>
                </div>
              </div>
            </div>
          )}

          {/* YAML Preview Tab */}
          {activeTab === 'yaml' && (
            <div>
              <div className="flex items-center justify-between mb-3">
                <h3 className="text-lg font-semibold">Generated YAML</h3>
                <button
                  onClick={() => {
                    navigator.clipboard.writeText(yamlContent);
                    toast.success('YAML copied to clipboard');
                  }}
                  className="px-3 py-1.5 text-sm bg-gray-100 hover:bg-gray-200 rounded-lg"
                >
                  Copy
                </button>
              </div>
              <pre className="p-4 bg-gray-900 text-gray-100 rounded-lg overflow-x-auto text-sm font-mono">
                {yamlContent}
              </pre>
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="p-6 border-t flex items-center justify-between">
          <div className="text-sm text-gray-600">
            {validationErrors.length === 0 ? (
              <span className="flex items-center gap-2 text-green-600">
                <CheckCircle className="w-4 h-4" />
                Ready to save
              </span>
            ) : (
              <span className="flex items-center gap-2 text-red-600">
                <AlertCircle className="w-4 h-4" />
                {validationErrors.length} error(s)
              </span>
            )}
          </div>
          <div className="flex gap-3">
            <button
              onClick={onClose}
              className="px-4 py-2 border border-gray-300 rounded-lg hover:bg-gray-50"
            >
              Cancel
            </button>
            <button
              onClick={handleSave}
              disabled={isSaving || validationErrors.length > 0}
              className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-2"
            >
              <Save className="w-4 h-4" />
              {isSaving ? 'Saving...' : isNew ? 'Create Template' : 'Save Changes'}
            </button>
          </div>
        </div>
      </div>

      {/* Command Template Inserter Modal */}
      {showTemplateInserter && selectedApptainerImage && (
        <CommandTemplateInserter
          image={selectedApptainerImage}
          slurmConfig={{
            partition,
            nodes,
            ntasks,
            cpus_per_task: cpusPerTask,
            mem: memory,
            time,
          }}
          onInsert={(script) => {
            setMainExecScript(script);
            setShowTemplateInserter(false);
            toast.success('Command template inserted successfully!');
          }}
          onClose={() => setShowTemplateInserter(false)}
        />
      )}
    </div>
  );
};
