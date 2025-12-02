import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
/**
 * ApptainerTemplateIntegration Component
 *
 * Unified integration component that wraps ApptainerImageSelector and CommandTemplateModal
 * for easy integration into existing job submission pages.
 *
 * Features:
 * - Single component for complete template selection workflow
 * - Automatic script generation with variable substitution
 * - Integration with existing job configuration structures
 * - Support for both LS-DYNA and general Apptainer workflows
 * - Collapsible panel to save screen space
 */
import React, { useState } from 'react';
import { Box, Button, Card, CardContent, Typography, Collapse, Alert, Divider, Chip, IconButton, } from '@mui/material';
import { ExpandMore as ExpandMoreIcon, ExpandLess as ExpandLessIcon, Code as CodeIcon, CheckCircle as CheckIcon, Assignment as TemplateIcon, } from '@mui/icons-material';
import ApptainerImageSelector from './ApptainerImageSelector';
import CommandTemplateModal from './CommandTemplateModal';
import { generateScript } from '../utils/templateEngine';
const ApptainerTemplateIntegration = ({ onTemplateApply, slurmConfig = {}, inputFiles = {}, partition = null, defaultExpanded = false, applyButtonText = 'Use This Template', showPreview = true, }) => {
    const [expanded, setExpanded] = useState(defaultExpanded);
    const [selectedImage, setSelectedImage] = useState(null);
    const [selectedTemplate, setSelectedTemplate] = useState(null);
    const [modalOpen, setModalOpen] = useState(false);
    const [generatedScript, setGeneratedScript] = useState('');
    const [scriptError, setScriptError] = useState(null);
    // Handle image selection
    const handleImageSelect = (image) => {
        setSelectedImage(image);
        setSelectedTemplate(null);
        setGeneratedScript('');
        setScriptError(null);
        // If image has templates, open modal
        if (image.command_templates && image.command_templates.length > 0) {
            setModalOpen(true);
        }
        else {
            setScriptError('Selected image has no command templates available.');
        }
    };
    // Handle template selection from modal
    const handleTemplateSelect = (template) => {
        setSelectedTemplate(template);
        setModalOpen(false);
        setScriptError(null);
        // Generate script automatically
        generateScriptPreview(template);
    };
    // Generate script preview
    const generateScriptPreview = (template) => {
        if (!selectedImage) {
            setScriptError('No image selected');
            return;
        }
        try {
            const context = {
                slurmConfig: slurmConfig,
                inputFiles: inputFiles,
                apptainerImage: selectedImage.path,
            };
            const script = generateScript(template, context);
            setGeneratedScript(script);
            setScriptError(null);
        }
        catch (error) {
            console.error('Error generating script:', error);
            setScriptError(error instanceof Error ? error.message : String(error));
            setGeneratedScript('');
        }
    };
    // Handle apply template button
    const handleApplyTemplate = () => {
        if (!selectedTemplate || !selectedImage || !generatedScript) {
            setScriptError('Cannot apply template: missing template, image, or script');
            return;
        }
        onTemplateApply(generatedScript, selectedTemplate, selectedImage);
        // Collapse panel after applying
        setExpanded(false);
    };
    // Re-generate script when slurmConfig or inputFiles change
    React.useEffect(() => {
        if (selectedTemplate) {
            generateScriptPreview(selectedTemplate);
        }
    }, [slurmConfig, inputFiles]);
    return (_jsxs(Card, { variant: "outlined", sx: { mb: 3 }, children: [_jsxs(CardContent, { children: [_jsxs(Box, { display: "flex", justifyContent: "space-between", alignItems: "center", sx: { cursor: 'pointer' }, onClick: () => setExpanded(!expanded), children: [_jsxs(Box, { display: "flex", alignItems: "center", gap: 1, children: [_jsx(TemplateIcon, { color: "primary" }), _jsx(Typography, { variant: "h6", children: "Apptainer Command Templates" }), selectedTemplate && (_jsx(Chip, { icon: _jsx(CheckIcon, {}), label: `Template: ${selectedTemplate.display_name}`, color: "success", size: "small" }))] }), _jsx(IconButton, { size: "small", children: expanded ? _jsx(ExpandLessIcon, {}) : _jsx(ExpandMoreIcon, {}) })] }), _jsx(Typography, { variant: "body2", color: "text.secondary", sx: { mt: 1 }, children: "Select an Apptainer image and command template to auto-generate job submission scripts" }), _jsx(Collapse, { in: expanded, children: _jsxs(Box, { mt: 2, children: [_jsx(Divider, { sx: { mb: 2 } }), _jsx(ApptainerImageSelector, { onSelectImage: handleImageSelect, selectedImageId: selectedImage?.id, partition: partition }), selectedTemplate && (_jsxs(Box, { mt: 3, children: [_jsx(Divider, { sx: { mb: 2 } }), _jsx(Typography, { variant: "subtitle2", gutterBottom: true, children: "Selected Template Details" }), _jsx(Card, { variant: "outlined", sx: { bgcolor: 'grey.50', p: 2 }, children: _jsxs(Box, { display: "flex", justifyContent: "space-between", alignItems: "flex-start", children: [_jsxs(Box, { children: [_jsx(Typography, { variant: "body1", fontWeight: "bold", children: selectedTemplate.display_name }), _jsx(Typography, { variant: "body2", color: "text.secondary", paragraph: true, children: selectedTemplate.description }), _jsxs(Box, { display: "flex", gap: 1, mb: 1, children: [_jsx(Chip, { label: selectedTemplate.category, size: "small", color: "primary" }), selectedTemplate.command.requires_mpi && (_jsx(Chip, { label: "MPI Required", size: "small", color: "warning" }))] })] }), _jsx(Button, { variant: "outlined", size: "small", onClick: () => setModalOpen(true), startIcon: _jsx(CodeIcon, {}), children: "Change Template" })] }) }), showPreview && generatedScript && (_jsxs(Box, { mt: 2, children: [_jsx(Typography, { variant: "subtitle2", gutterBottom: true, children: "Generated Script Preview" }), _jsx(Box, { sx: {
                                                        bgcolor: 'grey.100',
                                                        p: 2,
                                                        borderRadius: 1,
                                                        fontFamily: 'monospace',
                                                        fontSize: '0.75rem',
                                                        overflowX: 'auto',
                                                        maxHeight: '300px',
                                                        overflowY: 'auto',
                                                        border: '1px solid',
                                                        borderColor: 'grey.300',
                                                    }, children: _jsx("pre", { style: { margin: 0 }, children: generatedScript }) })] })), scriptError && (_jsxs(Alert, { severity: "error", sx: { mt: 2 }, children: [_jsx("strong", { children: "Script Generation Error:" }), " ", scriptError] })), _jsx(Box, { mt: 2, display: "flex", justifyContent: "flex-end", children: _jsx(Button, { variant: "contained", color: "primary", onClick: handleApplyTemplate, disabled: !generatedScript || !!scriptError, startIcon: _jsx(CheckIcon, {}), children: applyButtonText }) })] })), !selectedTemplate && selectedImage && (_jsx(Alert, { severity: "info", sx: { mt: 2 }, children: "Click on an image with command templates to browse available templates." }))] }) })] }), selectedImage && (_jsx(CommandTemplateModal, { open: modalOpen, onClose: () => setModalOpen(false), image: selectedImage, onSelectTemplate: handleTemplateSelect }))] }));
};
export default ApptainerTemplateIntegration;
