import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
/**
 * Command Template Example Page
 *
 * Demonstrates how to use the Apptainer Command Template System
 * in a job submission workflow.
 *
 * This page shows:
 * 1. Selecting an Apptainer image
 * 2. Browsing available command templates
 * 3. Selecting a template
 * 4. Generating a Slurm script with variable substitution
 * 5. Previewing and submitting the job
 */
import { useState } from 'react';
import { Box, Container, Typography, Paper, Stepper, Step, StepLabel, Button, TextField, Grid, Alert, Card, CardContent, Divider, } from '@mui/material';
import { ArrowForward as NextIcon, ArrowBack as BackIcon, Send as SubmitIcon, } from '@mui/icons-material';
import ApptainerImageSelector from '../components/ApptainerImageSelector';
import CommandTemplateModal from '../components/CommandTemplateModal';
import { generateScript } from '../utils/templateEngine';
const steps = [
    'Select Apptainer Image',
    'Choose Command Template',
    'Configure Job Parameters',
    'Review & Submit',
];
const CommandTemplateExample = () => {
    const [activeStep, setActiveStep] = useState(0);
    const [selectedImage, setSelectedImage] = useState(null);
    const [selectedTemplate, setSelectedTemplate] = useState(null);
    const [modalOpen, setModalOpen] = useState(false);
    const [generatedScript, setGeneratedScript] = useState('');
    // Job configuration
    const [jobConfig, setJobConfig] = useState({
        partition: 'group6',
        nodes: 1,
        ntasks: 16,
        'cpus-per-task': 1,
        mem: '32G',
        time: '12:00:00',
        qos: 'group6_qos',
    });
    // Input files
    const [inputFiles, setInputFiles] = useState({
        python_script: '/path/to/simulation.py',
        k_file: '/path/to/input.k',
    });
    // Handle image selection
    const handleImageSelect = (image) => {
        setSelectedImage(image);
        setSelectedTemplate(null);
        setGeneratedScript('');
        // If image has templates, open modal
        if (image.command_templates && image.command_templates.length > 0) {
            setModalOpen(true);
        }
    };
    // Handle template selection from modal
    const handleTemplateSelect = (template) => {
        setSelectedTemplate(template);
        setModalOpen(false);
        // Auto-generate script
        generateScriptPreview(template);
        // Move to next step
        if (activeStep === 0) {
            setActiveStep(1);
        }
    };
    // Generate script preview
    const generateScriptPreview = (template = selectedTemplate) => {
        if (!template || !selectedImage)
            return;
        try {
            const context = {
                slurmConfig: jobConfig,
                inputFiles: inputFiles,
                apptainerImage: selectedImage.path,
            };
            const script = generateScript(template, context);
            setGeneratedScript(script);
        }
        catch (error) {
            console.error('Error generating script:', error);
            setGeneratedScript(`# Error generating script:\n# ${error instanceof Error ? error.message : String(error)}`);
        }
    };
    // Handle next step
    const handleNext = () => {
        if (activeStep === 0 && selectedImage && !selectedTemplate) {
            // Open modal to select template
            setModalOpen(true);
            return;
        }
        if (activeStep === 2) {
            // Regenerate script with updated config
            generateScriptPreview();
        }
        setActiveStep((prev) => prev + 1);
    };
    // Handle back step
    const handleBack = () => {
        setActiveStep((prev) => prev - 1);
    };
    // Handle submit
    const handleSubmit = async () => {
        if (!generatedScript) {
            alert('No script generated!');
            return;
        }
        // TODO: Implement actual job submission
        console.log('Submitting job with script:', generatedScript);
        alert('Job submitted successfully! (This is a demo)');
    };
    // Render step content
    const renderStepContent = () => {
        switch (activeStep) {
            case 0:
                return (_jsxs(Box, { children: [_jsx(Typography, { variant: "h6", gutterBottom: true, children: "Step 1: Select an Apptainer Image" }), _jsx(Typography, { variant: "body2", color: "text.secondary", paragraph: true, children: "Choose a container image from the available Apptainer images. Images with command templates will show a badge indicating the number of templates available." }), _jsx(ApptainerImageSelector, { onSelectImage: handleImageSelect, selectedImageId: selectedImage?.id }), selectedImage && (_jsxs(Alert, { severity: "success", sx: { mt: 2 }, children: ["Selected: ", _jsx("strong", { children: selectedImage.name }), selectedImage.command_templates.length > 0 && (_jsxs("span", { children: [" (", selectedImage.command_templates.length, " command template(s) available)"] }))] }))] }));
            case 1:
                return (_jsxs(Box, { children: [_jsx(Typography, { variant: "h6", gutterBottom: true, children: "Step 2: Command Template Selected" }), selectedTemplate ? (_jsx(Card, { children: _jsxs(CardContent, { children: [_jsx(Typography, { variant: "h6", gutterBottom: true, children: selectedTemplate.display_name }), _jsx(Typography, { variant: "body2", color: "text.secondary", paragraph: true, children: selectedTemplate.description }), _jsx(Divider, { sx: { my: 2 } }), _jsxs(Grid, { container: true, spacing: 2, children: [_jsxs(Grid, { item: true, xs: 6, children: [_jsx(Typography, { variant: "body2", color: "text.secondary", children: "Category" }), _jsx(Typography, { variant: "body1", children: selectedTemplate.category })] }), _jsxs(Grid, { item: true, xs: 6, children: [_jsx(Typography, { variant: "body2", color: "text.secondary", children: "Requires MPI" }), _jsx(Typography, { variant: "body1", children: selectedTemplate.command.requires_mpi ? 'Yes' : 'No' })] })] }), _jsx(Box, { mt: 2, children: _jsx(Button, { variant: "outlined", size: "small", onClick: () => setModalOpen(true), children: "Change Template" }) })] }) })) : (_jsxs(Alert, { severity: "warning", children: ["No template selected. Please select a template.", _jsx(Button, { variant: "outlined", size: "small", sx: { ml: 2 }, onClick: () => setModalOpen(true), children: "Select Template" })] }))] }));
            case 2:
                return (_jsxs(Box, { children: [_jsx(Typography, { variant: "h6", gutterBottom: true, children: "Step 3: Configure Job Parameters" }), _jsx(Typography, { variant: "body2", color: "text.secondary", paragraph: true, children: "Adjust the Slurm job configuration and input file paths. These values will be substituted into the command template." }), _jsxs(Grid, { container: true, spacing: 2, children: [_jsx(Grid, { item: true, xs: 12, sm: 6, children: _jsx(TextField, { fullWidth: true, label: "Partition", value: jobConfig.partition, onChange: (e) => setJobConfig({ ...jobConfig, partition: e.target.value }) }) }), _jsx(Grid, { item: true, xs: 12, sm: 6, children: _jsx(TextField, { fullWidth: true, label: "QoS", value: jobConfig.qos, onChange: (e) => setJobConfig({ ...jobConfig, qos: e.target.value }) }) }), _jsx(Grid, { item: true, xs: 12, sm: 4, children: _jsx(TextField, { fullWidth: true, label: "Nodes", type: "number", value: jobConfig.nodes, onChange: (e) => setJobConfig({ ...jobConfig, nodes: parseInt(e.target.value) }) }) }), _jsx(Grid, { item: true, xs: 12, sm: 4, children: _jsx(TextField, { fullWidth: true, label: "Tasks (ntasks)", type: "number", value: jobConfig.ntasks, onChange: (e) => setJobConfig({ ...jobConfig, ntasks: parseInt(e.target.value) }) }) }), _jsx(Grid, { item: true, xs: 12, sm: 4, children: _jsx(TextField, { fullWidth: true, label: "CPUs per Task", type: "number", value: jobConfig['cpus-per-task'], onChange: (e) => setJobConfig({ ...jobConfig, 'cpus-per-task': parseInt(e.target.value) }) }) }), _jsx(Grid, { item: true, xs: 12, sm: 6, children: _jsx(TextField, { fullWidth: true, label: "Memory", value: jobConfig.mem, onChange: (e) => setJobConfig({ ...jobConfig, mem: e.target.value }), helperText: "e.g., 32G, 512M" }) }), _jsx(Grid, { item: true, xs: 12, sm: 6, children: _jsx(TextField, { fullWidth: true, label: "Time Limit", value: jobConfig.time, onChange: (e) => setJobConfig({ ...jobConfig, time: e.target.value }), helperText: "Format: HH:MM:SS" }) }), _jsxs(Grid, { item: true, xs: 12, children: [_jsx(Divider, { sx: { my: 2 } }), _jsx(Typography, { variant: "subtitle2", gutterBottom: true, children: "Input Files" })] }), _jsx(Grid, { item: true, xs: 12, children: _jsx(TextField, { fullWidth: true, label: "Python Script", value: inputFiles.python_script, onChange: (e) => setInputFiles({ ...inputFiles, python_script: e.target.value }), helperText: "Path to your Python simulation script" }) })] })] }));
            case 3:
                return (_jsxs(Box, { children: [_jsx(Typography, { variant: "h6", gutterBottom: true, children: "Step 4: Review & Submit" }), _jsx(Typography, { variant: "body2", color: "text.secondary", paragraph: true, children: "Review the generated Slurm script below. Make any final adjustments if needed, then submit the job." }), _jsx(Paper, { elevation: 0, sx: {
                                bgcolor: 'grey.100',
                                p: 2,
                                fontFamily: 'monospace',
                                fontSize: '0.875rem',
                                overflowX: 'auto',
                                maxHeight: '400px',
                                overflowY: 'auto',
                                mb: 2,
                            }, children: _jsx("pre", { style: { margin: 0 }, children: generatedScript || '# No script generated yet' }) }), _jsx(Alert, { severity: "info", children: "This is a demonstration. Clicking Submit will show an alert instead of actually submitting the job." })] }));
            default:
                return null;
        }
    };
    return (_jsxs(Container, { maxWidth: "lg", sx: { py: 4 }, children: [_jsxs(Box, { mb: 4, children: [_jsx(Typography, { variant: "h4", gutterBottom: true, children: "Command Template Example" }), _jsx(Typography, { variant: "body1", color: "text.secondary", children: "This page demonstrates how to use the Apptainer Command Template System to generate Slurm job scripts with pre-configured commands and variable substitution." })] }), _jsx(Paper, { sx: { p: 3, mb: 3 }, children: _jsx(Stepper, { activeStep: activeStep, alternativeLabel: true, children: steps.map((label) => (_jsx(Step, { children: _jsx(StepLabel, { children: label }) }, label))) }) }), _jsx(Paper, { sx: { p: 3, mb: 3, minHeight: '400px' }, children: renderStepContent() }), _jsxs(Box, { display: "flex", justifyContent: "space-between", children: [_jsx(Button, { disabled: activeStep === 0, onClick: handleBack, startIcon: _jsx(BackIcon, {}), children: "Back" }), _jsx(Box, { display: "flex", gap: 2, children: activeStep === steps.length - 1 ? (_jsx(Button, { variant: "contained", color: "primary", onClick: handleSubmit, startIcon: _jsx(SubmitIcon, {}), disabled: !generatedScript, children: "Submit Job" })) : (_jsx(Button, { variant: "contained", onClick: handleNext, endIcon: _jsx(NextIcon, {}), disabled: (activeStep === 0 && !selectedImage) ||
                                (activeStep === 1 && !selectedTemplate), children: "Next" })) })] }), selectedImage && (_jsx(CommandTemplateModal, { open: modalOpen, onClose: () => setModalOpen(false), image: selectedImage, onSelectTemplate: handleTemplateSelect }))] }));
};
export default CommandTemplateExample;
