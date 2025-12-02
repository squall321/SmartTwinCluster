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
import {
  Box,
  Button,
  Card,
  CardContent,
  Typography,
  Collapse,
  Alert,
  Divider,
  Chip,
  IconButton,
} from '@mui/material';
import {
  ExpandMore as ExpandMoreIcon,
  ExpandLess as ExpandLessIcon,
  Code as CodeIcon,
  CheckCircle as CheckIcon,
  Assignment as TemplateIcon,
} from '@mui/icons-material';
import ApptainerImageSelector from './ApptainerImageSelector';
import CommandTemplateModal from './CommandTemplateModal';
import { generateScript } from '../utils/templateEngine';

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

interface SlurmJobConfig {
  partition?: string;
  nodes?: number;
  ntasks?: number;
  'ntasks-per-node'?: number;
  cpus?: number;
  'cpus-per-task'?: number;
  mem?: string;
  'mem-per-cpu'?: string;
  time?: string;
  qos?: string;
  [key: string]: any;
}

interface ApptainerTemplateIntegrationProps {
  /**
   * Callback when template is selected and script is generated
   * @param script - Generated Slurm script
   * @param template - Selected command template
   * @param image - Selected Apptainer image
   */
  onTemplateApply: (script: string, template: CommandTemplate, image: ApptainerImage) => void;

  /**
   * Current Slurm job configuration (will be used for variable substitution)
   */
  slurmConfig?: SlurmJobConfig;

  /**
   * Input files for variable substitution
   * Key should match the file_key in template definition
   */
  inputFiles?: Record<string, string>;

  /**
   * Filter images by partition
   */
  partition?: 'compute' | 'viz' | 'shared' | null;

  /**
   * Whether to show the panel expanded by default
   */
  defaultExpanded?: boolean;

  /**
   * Custom button text for applying template
   */
  applyButtonText?: string;

  /**
   * Show script preview before applying
   */
  showPreview?: boolean;
}

const ApptainerTemplateIntegration: React.FC<ApptainerTemplateIntegrationProps> = ({
  onTemplateApply,
  slurmConfig = {},
  inputFiles = {},
  partition = null,
  defaultExpanded = false,
  applyButtonText = 'Use This Template',
  showPreview = true,
}) => {
  const [expanded, setExpanded] = useState(defaultExpanded);
  const [selectedImage, setSelectedImage] = useState<ApptainerImage | null>(null);
  const [selectedTemplate, setSelectedTemplate] = useState<CommandTemplate | null>(null);
  const [modalOpen, setModalOpen] = useState(false);
  const [generatedScript, setGeneratedScript] = useState<string>('');
  const [scriptError, setScriptError] = useState<string | null>(null);

  // Handle image selection
  const handleImageSelect = (image: ApptainerImage) => {
    setSelectedImage(image);
    setSelectedTemplate(null);
    setGeneratedScript('');
    setScriptError(null);

    // If image has templates, open modal
    if (image.command_templates && image.command_templates.length > 0) {
      setModalOpen(true);
    } else {
      setScriptError('Selected image has no command templates available.');
    }
  };

  // Handle template selection from modal
  const handleTemplateSelect = (template: CommandTemplate) => {
    setSelectedTemplate(template);
    setModalOpen(false);
    setScriptError(null);

    // Generate script automatically
    generateScriptPreview(template);
  };

  // Generate script preview
  const generateScriptPreview = (template: CommandTemplate) => {
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
    } catch (error) {
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

  return (
    <Card variant="outlined" sx={{ mb: 3 }}>
      <CardContent>
        {/* Header with expand/collapse */}
        <Box
          display="flex"
          justifyContent="space-between"
          alignItems="center"
          sx={{ cursor: 'pointer' }}
          onClick={() => setExpanded(!expanded)}
        >
          <Box display="flex" alignItems="center" gap={1}>
            <TemplateIcon color="primary" />
            <Typography variant="h6">
              Apptainer Command Templates
            </Typography>
            {selectedTemplate && (
              <Chip
                icon={<CheckIcon />}
                label={`Template: ${selectedTemplate.display_name}`}
                color="success"
                size="small"
              />
            )}
          </Box>

          <IconButton size="small">
            {expanded ? <ExpandLessIcon /> : <ExpandMoreIcon />}
          </IconButton>
        </Box>

        <Typography variant="body2" color="text.secondary" sx={{ mt: 1 }}>
          Select an Apptainer image and command template to auto-generate job submission scripts
        </Typography>

        {/* Collapsible content */}
        <Collapse in={expanded}>
          <Box mt={2}>
            <Divider sx={{ mb: 2 }} />

            {/* Image Selector */}
            <ApptainerImageSelector
              onSelectImage={handleImageSelect}
              selectedImageId={selectedImage?.id}
              partition={partition}
            />

            {/* Template Summary */}
            {selectedTemplate && (
              <Box mt={3}>
                <Divider sx={{ mb: 2 }} />

                <Typography variant="subtitle2" gutterBottom>
                  Selected Template Details
                </Typography>

                <Card variant="outlined" sx={{ bgcolor: 'grey.50', p: 2 }}>
                  <Box display="flex" justifyContent="space-between" alignItems="flex-start">
                    <Box>
                      <Typography variant="body1" fontWeight="bold">
                        {selectedTemplate.display_name}
                      </Typography>
                      <Typography variant="body2" color="text.secondary" paragraph>
                        {selectedTemplate.description}
                      </Typography>

                      <Box display="flex" gap={1} mb={1}>
                        <Chip label={selectedTemplate.category} size="small" color="primary" />
                        {selectedTemplate.command.requires_mpi && (
                          <Chip label="MPI Required" size="small" color="warning" />
                        )}
                      </Box>
                    </Box>

                    <Button
                      variant="outlined"
                      size="small"
                      onClick={() => setModalOpen(true)}
                      startIcon={<CodeIcon />}
                    >
                      Change Template
                    </Button>
                  </Box>
                </Card>

                {/* Script Preview */}
                {showPreview && generatedScript && (
                  <Box mt={2}>
                    <Typography variant="subtitle2" gutterBottom>
                      Generated Script Preview
                    </Typography>
                    <Box
                      sx={{
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
                      }}
                    >
                      <pre style={{ margin: 0 }}>{generatedScript}</pre>
                    </Box>
                  </Box>
                )}

                {/* Error Display */}
                {scriptError && (
                  <Alert severity="error" sx={{ mt: 2 }}>
                    <strong>Script Generation Error:</strong> {scriptError}
                  </Alert>
                )}

                {/* Apply Button */}
                <Box mt={2} display="flex" justifyContent="flex-end">
                  <Button
                    variant="contained"
                    color="primary"
                    onClick={handleApplyTemplate}
                    disabled={!generatedScript || !!scriptError}
                    startIcon={<CheckIcon />}
                  >
                    {applyButtonText}
                  </Button>
                </Box>
              </Box>
            )}

            {/* Info when no template selected */}
            {!selectedTemplate && selectedImage && (
              <Alert severity="info" sx={{ mt: 2 }}>
                Click on an image with command templates to browse available templates.
              </Alert>
            )}
          </Box>
        </Collapse>
      </CardContent>

      {/* Command Template Modal */}
      {selectedImage && (
        <CommandTemplateModal
          open={modalOpen}
          onClose={() => setModalOpen(false)}
          image={selectedImage}
          onSelectTemplate={handleTemplateSelect}
        />
      )}
    </Card>
  );
};

export default ApptainerTemplateIntegration;
