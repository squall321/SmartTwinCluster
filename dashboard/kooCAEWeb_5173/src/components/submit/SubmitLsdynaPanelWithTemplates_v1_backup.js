import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
/**
 * Enhanced SubmitLsdynaPanel with Apptainer Template Integration
 *
 * This version includes:
 * - Original file upload and configuration functionality
 * - Apptainer command template selection
 * - Automatic script generation from templates
 * - Template-based job parameter population
 */
import { useEffect, useState } from 'react';
import { Button, message, Tabs } from 'antd';
import { CodeOutlined, UploadOutlined } from '@ant-design/icons';
import LsdynaFileUploader from '../uploader/LsdynaFileUploader';
import ApptainerTemplateIntegration from '../ApptainerTemplateIntegration';
import { api } from '../../api/axiosClient';
const { TabPane } = Tabs;
const SubmitLsdynaPanelWithTemplates = ({ initialConfigs, autoSubmit = false, onSubmitSuccess, }) => {
    const [configs, setConfigs] = useState([]);
    const [activeTab, setActiveTab] = useState('upload');
    // Template-related state
    const [selectedTemplate, setSelectedTemplate] = useState(null);
    const [selectedImage, setSelectedImage] = useState(null);
    const [generatedScript, setGeneratedScript] = useState('');
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
        message.success(`Template "${template.display_name}" applied successfully!`);
        // Optionally auto-populate job configs based on template
        // This would extract parameters from the template and create configs
        autoPopulateFromTemplate(template, image);
    };
    // Auto-populate job configurations from template
    const autoPopulateFromTemplate = (template, image) => {
        // Extract default values from template
        // This is a simplified version - you may need to customize based on your template structure
        const defaultCores = template.variables?.dynamic?.SLURM_NTASKS?.source === 'slurm.ntasks' ? 16 : 16;
        const requiresMPI = template.command.requires_mpi;
        // If we have existing configs, update them with template defaults
        if (configs.length > 0) {
            const updated = configs.map((cfg) => ({
                ...cfg,
                cores: defaultCores,
                mode: requiresMPI ? 'MPP' : 'SMP',
            }));
            setConfigs(updated);
            message.info(`Updated ${configs.length} job(s) with template defaults`);
        }
        else {
            message.info('Template applied. Upload K files to create jobs with these settings.');
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
            mem: `${Math.ceil(config.cores * 2)}G`, // 2GB per core
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
            // Add more file mappings as needed
        };
    };
    // Handle traditional job submission (existing functionality)
    const handleSubmit = async () => {
        if (configs.length === 0) {
            message.warning('업로드된 파일이 없습니다.');
            return;
        }
        const formData = new FormData();
        configs.forEach((cfg, i) => {
            formData.append('files', cfg.file);
            formData.append(`meta[${i}]`, JSON.stringify({
                filename: cfg.filename,
                cores: cfg.cores,
                precision: cfg.precision,
                version: cfg.version,
                mode: cfg.mode,
                // Include template info if available
                template_id: selectedTemplate?.template_id,
                image_path: selectedImage?.path,
            }));
        });
        try {
            const res = await api.post("/api/slurm/submit-lsdyna-jobs", formData, {
                headers: { 'Content-Type': 'multipart/form-data' },
            });
            if (Array.isArray(res.data.submitted)) {
                message.success(`총 ${res.data.submitted.length}개의 Job 제출 성공`);
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
        // TODO: Implement template-based submission endpoint
        // This would send the generated script to a new endpoint that handles template-based submissions
        message.info('템플릿 기반 제출 기능은 아직 구현 중입니다. 기존 제출 방식을 사용해주세요.');
        // For now, fallback to traditional submission
        await handleSubmit();
    };
    // Auto-submit functionality
    useEffect(() => {
        if (autoSubmit && configs.length > 0) {
            handleSubmit();
        }
    }, [configs, autoSubmit]);
    return (_jsxs("div", { children: [_jsxs(Tabs, { activeKey: activeTab, onChange: setActiveTab, style: { marginBottom: 16 }, children: [_jsxs(TabPane, { tab: _jsxs("span", { children: [_jsx(UploadOutlined, {}), "Traditional Upload"] }), children: [_jsx(LsdynaFileUploader, { onDataUpdate: handleDataUpdate, initialData: configs }), configs.length > 0 && !autoSubmit && (_jsx("div", { style: { textAlign: 'right', marginTop: '1rem' }, children: _jsx(Button, { type: "primary", onClick: handleSubmit, children: "Submit Jobs" }) }))] }, "upload"), _jsxs(TabPane, { tab: _jsxs("span", { children: [_jsx(CodeOutlined, {}), "Template-Based Submission"] }), children: [_jsx(ApptainerTemplateIntegration, { onTemplateApply: handleTemplateApply, slurmConfig: getSlurmConfigFromJobConfig(configs[0]), inputFiles: getInputFilesFromConfigs(), partition: "compute", defaultExpanded: true, applyButtonText: "Apply Template to Jobs", showPreview: true }), selectedTemplate && (_jsxs("div", { style: { marginTop: 24 }, children: [_jsx("h3", { children: "Upload K Files for Template-Based Submission" }), _jsxs("p", { style: { color: '#666', marginBottom: 16 }, children: ["Template: ", _jsx("strong", { children: selectedTemplate.display_name }), ' ', "| Image: ", _jsx("strong", { children: selectedImage?.name })] }), _jsx(LsdynaFileUploader, { onDataUpdate: handleDataUpdate, initialData: configs }), configs.length > 0 && (_jsx("div", { style: { textAlign: 'right', marginTop: '1rem' }, children: _jsx(Button, { type: "primary", onClick: handleTemplateSubmit, children: "Submit with Template" }) }))] }))] }, "template")] }), selectedTemplate && activeTab === 'upload' && (_jsxs("div", { style: {
                    marginTop: 16,
                    padding: 12,
                    background: '#e6f7ff',
                    border: '1px solid #91d5ff',
                    borderRadius: 4,
                }, children: [_jsx("strong", { children: "Active Template:" }), " ", selectedTemplate.display_name, _jsxs("span", { style: { marginLeft: 8, color: '#666' }, children: ["(", selectedImage?.name, ")"] }), _jsx(Button, { size: "small", type: "link", onClick: () => setActiveTab('template'), children: "View/Change Template" })] }))] }));
};
export default SubmitLsdynaPanelWithTemplates;
