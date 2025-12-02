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

import React, { useState } from 'react';
import {
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  Button,
  Box,
  Typography,
  Card,
  CardContent,
  Chip,
  Divider,
  List,
  ListItem,
  ListItemText,
  IconButton,
  Collapse,
  Alert,
  TextField,
  Tooltip,
} from '@mui/material';
import {
  Close as CloseIcon,
  ExpandMore as ExpandMoreIcon,
  Code as CodeIcon,
  Input as InputIcon,
  Output as OutputIcon,
  Settings as SettingsIcon,
  PlayArrow as PlayIcon,
  CheckCircle as CheckIcon,
} from '@mui/icons-material';

interface CommandTemplate {
  template_id: string;
  display_name: string;
  description: string;
  category: 'solver' | 'post-processing' | 'preprocessing';
  command: {
    executable: string;
    format: string;
    requires_mpi: boolean;
  };
  variables: {
    dynamic?: Record<string, {
      source: string;
      transform?: string;
      description: string;
      required: boolean;
    }>;
    input_files?: Record<string, {
      description: string;
      pattern: string;
      required: boolean;
      file_key: string;
    }>;
    output_files?: Record<string, {
      pattern: string;
      description: string;
      collect: boolean;
    }>;
    input_dependencies?: Record<string, {
      pattern: string;
      auto_detect?: boolean;
      auto_generate?: boolean;
      source_dir?: string;
      generate_rule?: string;
    }>;
    computed?: Record<string, {
      source: string;
      transform: string;
      description: string;
    }>;
  };
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

interface CommandTemplateModalProps {
  open: boolean;
  onClose: () => void;
  image: ApptainerImage | null;
  onSelectTemplate: (template: CommandTemplate, customValues?: Record<string, string>) => void;
}

const CommandTemplateModal: React.FC<CommandTemplateModalProps> = ({
  open,
  onClose,
  image,
  onSelectTemplate,
}) => {
  const [selectedTemplate, setSelectedTemplate] = useState<CommandTemplate | null>(null);
  const [expandedSections, setExpandedSections] = useState<Record<string, boolean>>({});
  const [customValues, setCustomValues] = useState<Record<string, string>>({});

  // Reset state when modal closes
  const handleClose = () => {
    setSelectedTemplate(null);
    setExpandedSections({});
    setCustomValues({});
    onClose();
  };

  // Toggle section expansion
  const toggleSection = (section: string) => {
    setExpandedSections((prev) => ({
      ...prev,
      [section]: !prev[section],
    }));
  };

  // Handle template selection
  const handleSelectTemplate = (template: CommandTemplate) => {
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
  const getCategoryColor = (category: string) => {
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
  const countRequiredVariables = (template: CommandTemplate): number => {
    let count = 0;
    if (template.variables.dynamic) {
      count += Object.values(template.variables.dynamic).filter((v) => v.required).length;
    }
    if (template.variables.input_files) {
      count += Object.values(template.variables.input_files).filter((v) => v.required).length;
    }
    return count;
  };

  if (!image) {
    return null;
  }

  return (
    <Dialog open={open} onClose={handleClose} maxWidth="md" fullWidth>
      <DialogTitle>
        <Box display="flex" justifyContent="space-between" alignItems="center">
          <Box>
            <Typography variant="h6">Command Templates</Typography>
            <Typography variant="caption" color="text.secondary">
              {image.name} • {image.command_templates.length} template(s) available
            </Typography>
          </Box>
          <IconButton onClick={handleClose} size="small">
            <CloseIcon />
          </IconButton>
        </Box>
      </DialogTitle>

      <DialogContent dividers>
        <Box display="flex" gap={2} height="500px">
          {/* Left Panel: Template List */}
          <Box flex="0 0 250px" sx={{ overflowY: 'auto' }}>
            <Typography variant="subtitle2" gutterBottom>
              Available Templates
            </Typography>

            <List dense>
              {image.command_templates.map((template) => (
                <Card
                  key={template.template_id}
                  sx={{
                    mb: 1,
                    cursor: 'pointer',
                    border: selectedTemplate?.template_id === template.template_id ? 2 : 1,
                    borderColor:
                      selectedTemplate?.template_id === template.template_id
                        ? 'primary.main'
                        : 'divider',
                    '&:hover': {
                      boxShadow: 2,
                    },
                  }}
                  onClick={() => handleSelectTemplate(template)}
                >
                  <CardContent sx={{ p: 1.5, '&:last-child': { pb: 1.5 } }}>
                    <Box display="flex" alignItems="center" gap={0.5} mb={0.5}>
                      <CodeIcon fontSize="small" color="action" />
                      <Typography variant="body2" fontWeight="medium" noWrap>
                        {template.display_name}
                      </Typography>
                    </Box>

                    <Box display="flex" gap={0.5} mb={0.5}>
                      <Chip
                        label={template.category}
                        size="small"
                        color={getCategoryColor(template.category) as any}
                        sx={{ fontSize: '0.65rem', height: '18px' }}
                      />
                      {template.command.requires_mpi && (
                        <Chip
                          label="MPI"
                          size="small"
                          variant="outlined"
                          sx={{ fontSize: '0.65rem', height: '18px' }}
                        />
                      )}
                    </Box>

                    <Typography variant="caption" color="text.secondary" sx={{ display: 'block' }}>
                      {countRequiredVariables(template)} required variable(s)
                    </Typography>
                  </CardContent>
                </Card>
              ))}
            </List>
          </Box>

          {/* Right Panel: Template Details */}
          <Box flex={1} sx={{ overflowY: 'auto' }}>
            {!selectedTemplate ? (
              <Box
                display="flex"
                justifyContent="center"
                alignItems="center"
                height="100%"
                textAlign="center"
              >
                <Typography variant="body2" color="text.secondary">
                  Select a template from the list to view details
                </Typography>
              </Box>
            ) : (
              <Box>
                {/* Template Header */}
                <Box mb={2}>
                  <Typography variant="h6">{selectedTemplate.display_name}</Typography>
                  <Typography variant="body2" color="text.secondary" paragraph>
                    {selectedTemplate.description}
                  </Typography>

                  <Box display="flex" gap={1}>
                    <Chip
                      label={selectedTemplate.category}
                      color={getCategoryColor(selectedTemplate.category) as any}
                      size="small"
                    />
                    {selectedTemplate.command.requires_mpi && (
                      <Chip label="Requires MPI" color="warning" size="small" />
                    )}
                  </Box>
                </Box>

                <Divider sx={{ mb: 2 }} />

                {/* Variables Section */}
                <Card variant="outlined" sx={{ mb: 2 }}>
                  <CardContent>
                    <Box
                      display="flex"
                      justifyContent="space-between"
                      alignItems="center"
                      sx={{ cursor: 'pointer' }}
                      onClick={() => toggleSection('variables')}
                    >
                      <Box display="flex" alignItems="center" gap={1}>
                        <SettingsIcon fontSize="small" />
                        <Typography variant="subtitle2">Variables</Typography>
                      </Box>
                      <ExpandMoreIcon
                        sx={{
                          transform: expandedSections.variables ? 'rotate(180deg)' : 'rotate(0deg)',
                          transition: '0.3s',
                        }}
                      />
                    </Box>

                    <Collapse in={expandedSections.variables}>
                      <Box mt={2}>
                        {/* Dynamic Variables */}
                        {selectedTemplate.variables.dynamic && Object.keys(selectedTemplate.variables.dynamic).length > 0 && (
                          <Box mb={2}>
                            <Typography variant="caption" color="primary" fontWeight="bold" gutterBottom>
                              Dynamic Variables (from Slurm)
                            </Typography>
                            {Object.entries(selectedTemplate.variables.dynamic).map(([key, value]) => (
                              <Box key={key} mb={1}>
                                <Typography variant="body2">
                                  <strong>{key}</strong>
                                  {value.required && <Chip label="Required" size="small" color="error" sx={{ ml: 1, height: '16px', fontSize: '0.65rem' }} />}
                                </Typography>
                                <Typography variant="caption" color="text.secondary">
                                  {value.description}
                                  <br />
                                  Source: <code>{value.source}</code>
                                  {value.transform && ` • Transform: ${value.transform}`}
                                </Typography>
                              </Box>
                            ))}
                          </Box>
                        )}

                        {/* Input Files */}
                        {selectedTemplate.variables.input_files && Object.keys(selectedTemplate.variables.input_files).length > 0 && (
                          <Box mb={2}>
                            <Typography variant="caption" color="primary" fontWeight="bold" gutterBottom>
                              Input Files
                            </Typography>
                            {Object.entries(selectedTemplate.variables.input_files).map(([key, value]) => (
                              <Box key={key} mb={1}>
                                <Box display="flex" alignItems="center" gap={1}>
                                  <InputIcon fontSize="small" color="action" />
                                  <Typography variant="body2">
                                    <strong>{key}</strong>
                                    {value.required && <Chip label="Required" size="small" color="error" sx={{ ml: 1, height: '16px', fontSize: '0.65rem' }} />}
                                  </Typography>
                                </Box>
                                <Typography variant="caption" color="text.secondary">
                                  {value.description}
                                  <br />
                                  Pattern: <code>{value.pattern}</code>
                                </Typography>
                              </Box>
                            ))}
                          </Box>
                        )}

                        {/* Output Files */}
                        {selectedTemplate.variables.output_files && Object.keys(selectedTemplate.variables.output_files).length > 0 && (
                          <Box mb={2}>
                            <Typography variant="caption" color="primary" fontWeight="bold" gutterBottom>
                              Output Files
                            </Typography>
                            {Object.entries(selectedTemplate.variables.output_files).map(([key, value]) => (
                              <Box key={key} mb={1}>
                                <Box display="flex" alignItems="center" gap={1}>
                                  <OutputIcon fontSize="small" color="action" />
                                  <Typography variant="body2">
                                    <strong>{key}</strong>
                                    {value.collect && <CheckIcon fontSize="small" color="success" sx={{ ml: 0.5 }} />}
                                  </Typography>
                                </Box>
                                <Typography variant="caption" color="text.secondary">
                                  {value.description}
                                  <br />
                                  Pattern: <code>{value.pattern}</code>
                                </Typography>
                              </Box>
                            ))}
                          </Box>
                        )}
                      </Box>
                    </Collapse>
                  </CardContent>
                </Card>

                {/* Command Format */}
                <Card variant="outlined" sx={{ mb: 2 }}>
                  <CardContent>
                    <Box
                      display="flex"
                      justifyContent="space-between"
                      alignItems="center"
                      sx={{ cursor: 'pointer' }}
                      onClick={() => toggleSection('command')}
                    >
                      <Box display="flex" alignItems="center" gap={1}>
                        <PlayIcon fontSize="small" />
                        <Typography variant="subtitle2">Command Format</Typography>
                      </Box>
                      <ExpandMoreIcon
                        sx={{
                          transform: expandedSections.command ? 'rotate(180deg)' : 'rotate(0deg)',
                          transition: '0.3s',
                        }}
                      />
                    </Box>

                    <Collapse in={expandedSections.command}>
                      <Box mt={2}>
                        <Typography variant="caption" color="text.secondary" gutterBottom>
                          Executable: <strong>{selectedTemplate.command.executable}</strong>
                        </Typography>
                        <Box
                          sx={{
                            bgcolor: 'grey.100',
                            p: 1,
                            borderRadius: 1,
                            fontFamily: 'monospace',
                            fontSize: '0.75rem',
                            overflowX: 'auto',
                            mt: 1,
                          }}
                        >
                          {selectedTemplate.command.format}
                        </Box>
                      </Box>
                    </Collapse>
                  </CardContent>
                </Card>

                {/* Pre Commands */}
                {selectedTemplate.pre_commands && selectedTemplate.pre_commands.length > 0 && (
                  <Card variant="outlined" sx={{ mb: 2 }}>
                    <CardContent>
                      <Box
                        display="flex"
                        justifyContent="space-between"
                        alignItems="center"
                        sx={{ cursor: 'pointer' }}
                        onClick={() => toggleSection('pre')}
                      >
                        <Typography variant="subtitle2">Pre-Commands ({selectedTemplate.pre_commands.length})</Typography>
                        <ExpandMoreIcon
                          sx={{
                            transform: expandedSections.pre ? 'rotate(180deg)' : 'rotate(0deg)',
                            transition: '0.3s',
                          }}
                        />
                      </Box>

                      <Collapse in={expandedSections.pre}>
                        <Box
                          sx={{
                            bgcolor: 'grey.100',
                            p: 1,
                            borderRadius: 1,
                            fontFamily: 'monospace',
                            fontSize: '0.7rem',
                            overflowX: 'auto',
                            mt: 1,
                          }}
                        >
                          {selectedTemplate.pre_commands.map((cmd, idx) => (
                            <div key={idx}>{cmd}</div>
                          ))}
                        </Box>
                      </Collapse>
                    </CardContent>
                  </Card>
                )}

                {/* Post Commands */}
                {selectedTemplate.post_commands && selectedTemplate.post_commands.length > 0 && (
                  <Card variant="outlined">
                    <CardContent>
                      <Box
                        display="flex"
                        justifyContent="space-between"
                        alignItems="center"
                        sx={{ cursor: 'pointer' }}
                        onClick={() => toggleSection('post')}
                      >
                        <Typography variant="subtitle2">Post-Commands ({selectedTemplate.post_commands.length})</Typography>
                        <ExpandMoreIcon
                          sx={{
                            transform: expandedSections.post ? 'rotate(180deg)' : 'rotate(0deg)',
                            transition: '0.3s',
                          }}
                        />
                      </Box>

                      <Collapse in={expandedSections.post}>
                        <Box
                          sx={{
                            bgcolor: 'grey.100',
                            p: 1,
                            borderRadius: 1,
                            fontFamily: 'monospace',
                            fontSize: '0.7rem',
                            overflowX: 'auto',
                            mt: 1,
                          }}
                        >
                          {selectedTemplate.post_commands.map((cmd, idx) => (
                            <div key={idx}>{cmd}</div>
                          ))}
                        </Box>
                      </Collapse>
                    </CardContent>
                  </Card>
                )}
              </Box>
            )}
          </Box>
        </Box>
      </DialogContent>

      <DialogActions>
        <Button onClick={handleClose}>Cancel</Button>
        <Button
          variant="contained"
          onClick={handleInsert}
          disabled={!selectedTemplate}
          startIcon={<CodeIcon />}
        >
          Insert Template
        </Button>
      </DialogActions>
    </Dialog>
  );
};

export default CommandTemplateModal;
