import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
/**
 * CommandTemplateModal Component
 *
 * Displays available command templates for a selected Apptainer image
 * and allows users to select one to insert into their job script.
 *
 * Features:
 * - List all command templates for the selected image
 * - Display template details (description, variables, I/O requirements)
 * - Preview generated command
 * - "Insert into Script" functionality
 * - Handle required vs optional variables
 * - Show MPI requirements
 */
import { useState } from 'react';
import { Dialog, DialogTitle, DialogContent, DialogActions, Button, Box, Typography, Card, CardContent, Chip, Divider, List, IconButton, Collapse, } from '@mui/material';
import { Close as CloseIcon, ExpandMore as ExpandMoreIcon, Code as CodeIcon, Input as InputIcon, Output as OutputIcon, Settings as SettingsIcon, PlayArrow as PlayIcon, CheckCircle as CheckIcon, } from '@mui/icons-material';
const CommandTemplateModal = ({ open, onClose, image, onSelectTemplate, }) => {
    const [selectedTemplate, setSelectedTemplate] = useState(null);
    const [expandedSections, setExpandedSections] = useState({});
    const [customValues, setCustomValues] = useState({});
    // Reset state when modal closes
    const handleClose = () => {
        setSelectedTemplate(null);
        setExpandedSections({});
        setCustomValues({});
        onClose();
    };
    // Toggle section expansion
    const toggleSection = (section) => {
        setExpandedSections((prev) => ({
            ...prev,
            [section]: !prev[section],
        }));
    };
    // Handle template selection
    const handleSelectTemplate = (template) => {
        setSelectedTemplate(template);
        setExpandedSections({
            variables: true,
            command: false,
            pre: false,
            post: false,
        });
    };
    // Handle insert button click
    const handleInsert = () => {
        if (selectedTemplate) {
            onSelectTemplate(selectedTemplate, customValues);
            handleClose();
        }
    };
    // Get category color
    const getCategoryColor = (category) => {
        switch (category) {
            case 'solver':
                return 'primary';
            case 'post-processing':
                return 'secondary';
            case 'preprocessing':
                return 'info';
            default:
                return 'default';
        }
    };
    // Count required variables
    const countRequiredVariables = (template) => {
        let count = 0;
        if (template.variables?.dynamic) {
            count += Object.values(template.variables?.dynamic).filter((v) => v.required).length;
        }
        if (template.variables?.input_files) {
            count += Object.values(template.variables?.input_files).filter((v) => v.required).length;
        }
        return count;
    };
    if (!image) {
        return null;
    }
    return (_jsxs(Dialog, { open: open, onClose: handleClose, maxWidth: "md", fullWidth: true, children: [_jsx(DialogTitle, { children: _jsxs(Box, { display: "flex", justifyContent: "space-between", alignItems: "center", children: [_jsxs(Box, { children: [_jsx(Typography, { variant: "h6", children: "Command Templates" }), _jsxs(Typography, { variant: "caption", color: "text.secondary", children: [image.name, " \u2022 ", image.command_templates.length, " template(s) available"] })] }), _jsx(IconButton, { onClick: handleClose, size: "small", children: _jsx(CloseIcon, {}) })] }) }), _jsx(DialogContent, { dividers: true, children: _jsxs(Box, { display: "flex", gap: 2, height: "500px", children: [_jsxs(Box, { flex: "0 0 250px", sx: { overflowY: 'auto' }, children: [_jsx(Typography, { variant: "subtitle2", gutterBottom: true, children: "Available Templates" }), _jsx(List, { dense: true, children: image.command_templates.map((template) => (_jsx(Card, { sx: {
                                            mb: 1,
                                            cursor: 'pointer',
                                            border: selectedTemplate?.template_id === template.template_id ? 2 : 1,
                                            borderColor: selectedTemplate?.template_id === template.template_id
                                                ? 'primary.main'
                                                : 'divider',
                                            '&:hover': {
                                                boxShadow: 2,
                                            },
                                        }, onClick: () => handleSelectTemplate(template), children: _jsxs(CardContent, { sx: { p: 1.5, '&:last-child': { pb: 1.5 } }, children: [_jsxs(Box, { display: "flex", alignItems: "center", gap: 0.5, mb: 0.5, children: [_jsx(CodeIcon, { fontSize: "small", color: "action" }), _jsx(Typography, { variant: "body2", fontWeight: "medium", noWrap: true, children: template.display_name })] }), _jsxs(Box, { display: "flex", gap: 0.5, mb: 0.5, children: [_jsx(Chip, { label: template.category, size: "small", color: getCategoryColor(template.category), sx: { fontSize: '0.65rem', height: '18px' } }), template.command.requires_mpi && (_jsx(Chip, { label: "MPI", size: "small", variant: "outlined", sx: { fontSize: '0.65rem', height: '18px' } }))] }), _jsxs(Typography, { variant: "caption", color: "text.secondary", sx: { display: 'block' }, children: [countRequiredVariables(template), " required variable(s)"] })] }) }, template.template_id))) })] }), _jsx(Box, { flex: 1, sx: { overflowY: 'auto' }, children: !selectedTemplate ? (_jsx(Box, { display: "flex", justifyContent: "center", alignItems: "center", height: "100%", textAlign: "center", children: _jsx(Typography, { variant: "body2", color: "text.secondary", children: "Select a template from the list to view details" }) })) : (_jsxs(Box, { children: [_jsxs(Box, { mb: 2, children: [_jsx(Typography, { variant: "h6", children: selectedTemplate.display_name }), _jsx(Typography, { variant: "body2", color: "text.secondary", paragraph: true, children: selectedTemplate.description }), _jsxs(Box, { display: "flex", gap: 1, children: [_jsx(Chip, { label: selectedTemplate.category, color: getCategoryColor(selectedTemplate.category), size: "small" }), selectedTemplate.command.requires_mpi && (_jsx(Chip, { label: "Requires MPI", color: "warning", size: "small" }))] })] }), _jsx(Divider, { sx: { mb: 2 } }), _jsx(Card, { variant: "outlined", sx: { mb: 2 }, children: _jsxs(CardContent, { children: [_jsxs(Box, { display: "flex", justifyContent: "space-between", alignItems: "center", sx: { cursor: 'pointer' }, onClick: () => toggleSection('variables'), children: [_jsxs(Box, { display: "flex", alignItems: "center", gap: 1, children: [_jsx(SettingsIcon, { fontSize: "small" }), _jsx(Typography, { variant: "subtitle2", children: "Variables" })] }), _jsx(ExpandMoreIcon, { sx: {
                                                                transform: expandedSections.variables ? 'rotate(180deg)' : 'rotate(0deg)',
                                                                transition: '0.3s',
                                                            } })] }), _jsx(Collapse, { in: expandedSections.variables, children: _jsxs(Box, { mt: 2, children: [selectedTemplate.variables?.dynamic && Object.keys(selectedTemplate.variables?.dynamic).length > 0 && (_jsxs(Box, { mb: 2, children: [_jsx(Typography, { variant: "caption", color: "primary", fontWeight: "bold", gutterBottom: true, children: "Dynamic Variables (from Slurm)" }), Object.entries(selectedTemplate.variables?.dynamic).map(([key, value]) => (_jsxs(Box, { mb: 1, children: [_jsxs(Typography, { variant: "body2", children: [_jsx("strong", { children: key }), value.required && _jsx(Chip, { label: "Required", size: "small", color: "error", sx: { ml: 1, height: '16px', fontSize: '0.65rem' } })] }), _jsxs(Typography, { variant: "caption", color: "text.secondary", children: [value.description, _jsx("br", {}), "Source: ", _jsx("code", { children: value.source }), value.transform && ` • Transform: ${value.transform}`] })] }, key)))] })), selectedTemplate.variables?.input_files && Object.keys(selectedTemplate.variables?.input_files).length > 0 && (_jsxs(Box, { mb: 2, children: [_jsx(Typography, { variant: "caption", color: "primary", fontWeight: "bold", gutterBottom: true, children: "Input Files" }), Object.entries(selectedTemplate.variables?.input_files).map(([key, value]) => (_jsxs(Box, { mb: 1, children: [_jsxs(Box, { display: "flex", alignItems: "center", gap: 1, children: [_jsx(InputIcon, { fontSize: "small", color: "action" }), _jsxs(Typography, { variant: "body2", children: [_jsx("strong", { children: key }), value.required && _jsx(Chip, { label: "Required", size: "small", color: "error", sx: { ml: 1, height: '16px', fontSize: '0.65rem' } })] })] }), _jsxs(Typography, { variant: "caption", color: "text.secondary", children: [value.description, _jsx("br", {}), "Pattern: ", _jsx("code", { children: value.pattern })] })] }, key)))] })), selectedTemplate.variables?.output_files && Object.keys(selectedTemplate.variables?.output_files).length > 0 && (_jsxs(Box, { mb: 2, children: [_jsx(Typography, { variant: "caption", color: "primary", fontWeight: "bold", gutterBottom: true, children: "Output Files" }), Object.entries(selectedTemplate.variables?.output_files).map(([key, value]) => (_jsxs(Box, { mb: 1, children: [_jsxs(Box, { display: "flex", alignItems: "center", gap: 1, children: [_jsx(OutputIcon, { fontSize: "small", color: "action" }), _jsxs(Typography, { variant: "body2", children: [_jsx("strong", { children: key }), value.collect && _jsx(CheckIcon, { fontSize: "small", color: "success", sx: { ml: 0.5 } })] })] }), _jsxs(Typography, { variant: "caption", color: "text.secondary", children: [value.description, _jsx("br", {}), "Pattern: ", _jsx("code", { children: value.pattern })] })] }, key)))] }))] }) })] }) }), _jsx(Card, { variant: "outlined", sx: { mb: 2 }, children: _jsxs(CardContent, { children: [_jsxs(Box, { display: "flex", justifyContent: "space-between", alignItems: "center", sx: { cursor: 'pointer' }, onClick: () => toggleSection('command'), children: [_jsxs(Box, { display: "flex", alignItems: "center", gap: 1, children: [_jsx(PlayIcon, { fontSize: "small" }), _jsx(Typography, { variant: "subtitle2", children: "Command Format" })] }), _jsx(ExpandMoreIcon, { sx: {
                                                                transform: expandedSections.command ? 'rotate(180deg)' : 'rotate(0deg)',
                                                                transition: '0.3s',
                                                            } })] }), _jsx(Collapse, { in: expandedSections.command, children: _jsxs(Box, { mt: 2, children: [_jsxs(Typography, { variant: "caption", color: "text.secondary", gutterBottom: true, children: ["Executable: ", _jsx("strong", { children: selectedTemplate.command.executable })] }), _jsx(Box, { sx: {
                                                                    bgcolor: 'grey.100',
                                                                    p: 1,
                                                                    borderRadius: 1,
                                                                    fontFamily: 'monospace',
                                                                    fontSize: '0.75rem',
                                                                    overflowX: 'auto',
                                                                    mt: 1,
                                                                }, children: selectedTemplate.command.format })] }) })] }) }), selectedTemplate.pre_commands && selectedTemplate.pre_commands.length > 0 && (_jsx(Card, { variant: "outlined", sx: { mb: 2 }, children: _jsxs(CardContent, { children: [_jsxs(Box, { display: "flex", justifyContent: "space-between", alignItems: "center", sx: { cursor: 'pointer' }, onClick: () => toggleSection('pre'), children: [_jsxs(Typography, { variant: "subtitle2", children: ["Pre-Commands (", selectedTemplate.pre_commands.length, ")"] }), _jsx(ExpandMoreIcon, { sx: {
                                                                transform: expandedSections.pre ? 'rotate(180deg)' : 'rotate(0deg)',
                                                                transition: '0.3s',
                                                            } })] }), _jsx(Collapse, { in: expandedSections.pre, children: _jsx(Box, { sx: {
                                                            bgcolor: 'grey.100',
                                                            p: 1,
                                                            borderRadius: 1,
                                                            fontFamily: 'monospace',
                                                            fontSize: '0.7rem',
                                                            overflowX: 'auto',
                                                            mt: 1,
                                                        }, children: selectedTemplate.pre_commands.map((cmd, idx) => (_jsx("div", { children: cmd }, idx))) }) })] }) })), selectedTemplate.post_commands && selectedTemplate.post_commands.length > 0 && (_jsx(Card, { variant: "outlined", children: _jsxs(CardContent, { children: [_jsxs(Box, { display: "flex", justifyContent: "space-between", alignItems: "center", sx: { cursor: 'pointer' }, onClick: () => toggleSection('post'), children: [_jsxs(Typography, { variant: "subtitle2", children: ["Post-Commands (", selectedTemplate.post_commands.length, ")"] }), _jsx(ExpandMoreIcon, { sx: {
                                                                transform: expandedSections.post ? 'rotate(180deg)' : 'rotate(0deg)',
                                                                transition: '0.3s',
                                                            } })] }), _jsx(Collapse, { in: expandedSections.post, children: _jsx(Box, { sx: {
                                                            bgcolor: 'grey.100',
                                                            p: 1,
                                                            borderRadius: 1,
                                                            fontFamily: 'monospace',
                                                            fontSize: '0.7rem',
                                                            overflowX: 'auto',
                                                            mt: 1,
                                                        }, children: selectedTemplate.post_commands.map((cmd, idx) => (_jsx("div", { children: cmd }, idx))) }) })] }) }))] })) })] }) }), _jsxs(DialogActions, { children: [_jsx(Button, { onClick: handleClose, children: "Cancel" }), _jsx(Button, { variant: "contained", onClick: handleInsert, disabled: !selectedTemplate, startIcon: _jsx(CodeIcon, {}), children: "Insert Template" })] })] }));
};
export default CommandTemplateModal;
