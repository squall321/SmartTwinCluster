import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
/**
 * Enhanced SubmitLsdynaPanel with Apptainer Template Integration v2
 *
 * 새로운 기능:
 * - 템플릿으로 저장 기능
 * - 저장된 템플릿 불러오기
 * - 템플릿 기반 제출 시 template_id와 image_path 전송
 */
import { useEffect, useState } from 'react';
import { Button, message, Tabs } from 'antd';
import { CodeOutlined, UploadOutlined, SaveOutlined } from '@ant-design/icons';
import LsdynaFileUploader from '../uploader/LsdynaFileUploader';
import ApptainerTemplateIntegration from '../ApptainerTemplateIntegration';
import SaveTemplateModal from '../SaveTemplateModal';
import { api } from '../../api/axiosClient';
const { TabPane } = Tabs;
const SubmitLsdynaPanelWithTemplates = ({ initialConfigs, autoSubmit = false, onSubmitSuccess, }) => {
    const [configs, setConfigs] = useState([]);
    const [activeTab, setActiveTab] = useState('upload');
    // Template-related state
    const [selectedTemplate, setSelectedTemplate] = useState(null);
    const [selectedImage, setSelectedImage] = useState(null);
    const [generatedScript, setGeneratedScript] = useState('');
    // Save template modal
    const [saveModalOpen, setSaveModalOpen] = useState(false);
    // Initialize with initial configs
    useEffect(() => {
        if (initialConfigs && configs.length === 0) {
            setConfigs(initialConfigs);
        }
    }, [initialConfigs, configs.length]);
    // Handle file uploader data updates
    const handleDataUpdate = (updated) => {
        setConfigs(updated);
    };
    // Handle template application
    const handleTemplateApply = (script, template, image) => {
        setSelectedTemplate(template);
        setSelectedImage(image);
        setGeneratedScript(script);
        message.success(`템플릿 "${template.display_name}"이(가) 적용되었습니다!`);
        // Auto-populate job configs based on template
        autoPopulateFromTemplate(template, image);
    };
    // Auto-populate job configurations from template
    const autoPopulateFromTemplate = (template, image) => {
        const defaultCores = template.variables?.dynamic?.SLURM_NTASKS?.source === 'slurm.ntasks' ? 16 : 16;
        const requiresMPI = template.command.requires_mpi;
        if (configs.length > 0) {
            const updated = configs.map((cfg) => ({
                ...cfg,
                cores: defaultCores,
                mode: requiresMPI ? 'MPP' : 'SMP',
            }));
            setConfigs(updated);
            message.info(`${configs.length}개 작업에 템플릿 기본값이 적용되었습니다`);
        }
        else {
            message.info('템플릿이 적용되었습니다. K 파일을 업로드하여 이 설정으로 작업을 생성하세요.');
        }
    };
    // Build Slurm config from first job config for template preview
    const getSlurmConfigFromJobConfig = (config) => {
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
        if (configs.length === 0)
            return undefined;
        const firstConfig = configs[0];
        if (!firstConfig.filename)
            return undefined;
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
            const metaData = {
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
            const res = await api.post("/api/slurm/submit-lsdyna-jobs", formData, {
                headers: { 'Content-Type': 'multipart/form-data' },
            });
            if (Array.isArray(res.data.submitted)) {
                message.success(`총 ${res.data.submitted.length}개의 작업이 제출되었습니다`);
                // Log template usage
                const templatesUsed = res.data.submitted.filter((job) => job.used_template).length;
                if (templatesUsed > 0) {
                    console.log(`📋 ${templatesUsed}개 작업이 템플릿을 사용했습니다`);
                }
                setConfigs([]);
                setSelectedTemplate(null);
                setSelectedImage(null);
                setGeneratedScript('');
                onSubmitSuccess?.(res.data.submitted);
            }
            else {
                message.error(res.data.error || '제출 실패: submitted 정보가 없습니다.');
            }
        }
        catch (err) {
            message.error(err?.response?.data?.error || err?.message || '제출 중 서버 오류 발생');
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
    const handleSaveTemplate = async (templateData) => {
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
            }
            else {
                throw new Error(res.data.error || '템플릿 저장 실패');
            }
        }
        catch (err) {
            throw new Error(err?.response?.data?.error || err?.message || '템플릿 저장 중 오류 발생');
        }
    };
    // Auto-submit functionality
    useEffect(() => {
        if (autoSubmit && configs.length > 0) {
            handleSubmit();
        }
    }, [configs, autoSubmit]);
    return (_jsxs("div", { children: [_jsxs(Tabs, { activeKey: activeTab, onChange: setActiveTab, style: { marginBottom: 16 }, children: [_jsxs(TabPane, { tab: _jsxs("span", { children: [_jsx(UploadOutlined, {}), "\uAE30\uC874 \uBC29\uC2DD \uC5C5\uB85C\uB4DC"] }), children: [_jsx(LsdynaFileUploader, { onDataUpdate: handleDataUpdate, initialData: configs }), configs.length > 0 && !autoSubmit && (_jsxs("div", { style: { textAlign: 'right', marginTop: '1rem', display: 'flex', gap: '8px', justifyContent: 'flex-end' }, children: [selectedTemplate && (_jsx(Button, { icon: _jsx(SaveOutlined, {}), onClick: () => setSaveModalOpen(true), children: "\uD15C\uD50C\uB9BF\uC73C\uB85C \uC800\uC7A5" })), _jsx(Button, { type: "primary", onClick: handleSubmit, children: "\uC791\uC5C5 \uC81C\uCD9C" })] }))] }, "upload"), _jsxs(TabPane, { tab: _jsxs("span", { children: [_jsx(CodeOutlined, {}), "\uD15C\uD50C\uB9BF \uAE30\uBC18 \uC81C\uCD9C"] }), children: [_jsx(ApptainerTemplateIntegration, { onTemplateApply: handleTemplateApply, slurmConfig: getSlurmConfigFromJobConfig(configs[0]), inputFiles: getInputFilesFromConfigs(), partition: "compute", defaultExpanded: true, applyButtonText: "\uC791\uC5C5\uC5D0 \uD15C\uD50C\uB9BF \uC801\uC6A9", showPreview: true }), selectedTemplate && (_jsxs("div", { style: { marginTop: 24 }, children: [_jsx("h3", { children: "\uD15C\uD50C\uB9BF \uAE30\uBC18 \uC81C\uCD9C\uC744 \uC704\uD55C K \uD30C\uC77C \uC5C5\uB85C\uB4DC" }), _jsxs("p", { style: { color: '#666', marginBottom: 16 }, children: ["\uD15C\uD50C\uB9BF: ", _jsx("strong", { children: selectedTemplate.display_name }), ' ', "| \uC774\uBBF8\uC9C0: ", _jsx("strong", { children: selectedImage?.name })] }), _jsx(LsdynaFileUploader, { onDataUpdate: handleDataUpdate, initialData: configs }), configs.length > 0 && (_jsxs("div", { style: { textAlign: 'right', marginTop: '1rem', display: 'flex', gap: '8px', justifyContent: 'flex-end' }, children: [_jsx(Button, { icon: _jsx(SaveOutlined, {}), onClick: () => setSaveModalOpen(true), children: "\uD15C\uD50C\uB9BF\uC73C\uB85C \uC800\uC7A5" }), _jsx(Button, { type: "primary", onClick: handleTemplateSubmit, children: "\uD15C\uD50C\uB9BF\uC73C\uB85C \uC81C\uCD9C" })] }))] }))] }, "template")] }), selectedTemplate && activeTab === 'upload' && (_jsxs("div", { style: {
                    marginTop: 16,
                    padding: 12,
                    background: '#e6f7ff',
                    border: '1px solid #91d5ff',
                    borderRadius: 4,
                }, children: [_jsx("strong", { children: "\uD65C\uC131 \uD15C\uD50C\uB9BF:" }), " ", selectedTemplate.display_name, _jsxs("span", { style: { marginLeft: 8, color: '#666' }, children: ["(", selectedImage?.name, ")"] }), _jsx(Button, { size: "small", type: "link", onClick: () => setActiveTab('template'), children: "\uD15C\uD50C\uB9BF \uBCF4\uAE30/\uBCC0\uACBD" })] })), _jsx(SaveTemplateModal, { open: saveModalOpen, onClose: () => setSaveModalOpen(false), onSave: handleSaveTemplate, defaultName: selectedTemplate?.display_name || '' })] }));
};
export default SubmitLsdynaPanelWithTemplates;
