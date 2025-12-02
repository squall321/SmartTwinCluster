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

import React, { useState } from 'react';
import {
  Box,
  Container,
  Typography,
  Paper,
  Stepper,
  Step,
  StepLabel,
  Button,
  TextField,
  Grid,
  Alert,
  Card,
  CardContent,
  Divider,
} from '@mui/material';
import {
  ArrowForward as NextIcon,
  ArrowBack as BackIcon,
  Send as SubmitIcon,
  Code as CodeIcon,
} from '@mui/icons-material';
import ApptainerImageSelector from '../components/ApptainerImageSelector';
import CommandTemplateModal from '../components/CommandTemplateModal';
import { generateScript, validateTemplate } from '../utils/templateEngine';

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

const steps = [
  'Select Apptainer Image',
  'Choose Command Template',
  'Configure Job Parameters',
  'Review & Submit',
];

const CommandTemplateExample: React.FC = () => {
  const [activeStep, setActiveStep] = useState(0);
  const [selectedImage, setSelectedImage] = useState<ApptainerImage | null>(null);
  const [selectedTemplate, setSelectedTemplate] = useState<CommandTemplate | null>(null);
  const [modalOpen, setModalOpen] = useState(false);
  const [generatedScript, setGeneratedScript] = useState<string>('');

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
  const [inputFiles, setInputFiles] = useState<Record<string, string>>({
    python_script: '/path/to/simulation.py',
    k_file: '/path/to/input.k',
  });

  // Handle image selection
  const handleImageSelect = (image: ApptainerImage) => {
    setSelectedImage(image);
    setSelectedTemplate(null);
    setGeneratedScript('');

    // If image has templates, open modal
    if (image.command_templates && image.command_templates.length > 0) {
      setModalOpen(true);
    }
  };

  // Handle template selection from modal
  const handleTemplateSelect = (template: CommandTemplate) => {
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
  const generateScriptPreview = (template: CommandTemplate = selectedTemplate!) => {
    if (!template || !selectedImage) return;

    try {
      const context = {
        slurmConfig: jobConfig,
        inputFiles: inputFiles,
        apptainerImage: selectedImage.path,
      };

      const script = generateScript(template, context);
      setGeneratedScript(script);
    } catch (error) {
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
        return (
          <Box>
            <Typography variant="h6" gutterBottom>
              Step 1: Select an Apptainer Image
            </Typography>
            <Typography variant="body2" color="text.secondary" paragraph>
              Choose a container image from the available Apptainer images.
              Images with command templates will show a badge indicating the number of templates available.
            </Typography>

            <ApptainerImageSelector
              onSelectImage={handleImageSelect}
              selectedImageId={selectedImage?.id}
            />

            {selectedImage && (
              <Alert severity="success" sx={{ mt: 2 }}>
                Selected: <strong>{selectedImage.name}</strong>
                {selectedImage.command_templates.length > 0 && (
                  <span> ({selectedImage.command_templates.length} command template(s) available)</span>
                )}
              </Alert>
            )}
          </Box>
        );

      case 1:
        return (
          <Box>
            <Typography variant="h6" gutterBottom>
              Step 2: Command Template Selected
            </Typography>

            {selectedTemplate ? (
              <Card>
                <CardContent>
                  <Typography variant="h6" gutterBottom>
                    {selectedTemplate.display_name}
                  </Typography>
                  <Typography variant="body2" color="text.secondary" paragraph>
                    {selectedTemplate.description}
                  </Typography>

                  <Divider sx={{ my: 2 }} />

                  <Grid container spacing={2}>
                    <Grid item xs={6}>
                      <Typography variant="body2" color="text.secondary">
                        Category
                      </Typography>
                      <Typography variant="body1">{selectedTemplate.category}</Typography>
                    </Grid>
                    <Grid item xs={6}>
                      <Typography variant="body2" color="text.secondary">
                        Requires MPI
                      </Typography>
                      <Typography variant="body1">
                        {selectedTemplate.command.requires_mpi ? 'Yes' : 'No'}
                      </Typography>
                    </Grid>
                  </Grid>

                  <Box mt={2}>
                    <Button variant="outlined" size="small" onClick={() => setModalOpen(true)}>
                      Change Template
                    </Button>
                  </Box>
                </CardContent>
              </Card>
            ) : (
              <Alert severity="warning">
                No template selected. Please select a template.
                <Button variant="outlined" size="small" sx={{ ml: 2 }} onClick={() => setModalOpen(true)}>
                  Select Template
                </Button>
              </Alert>
            )}
          </Box>
        );

      case 2:
        return (
          <Box>
            <Typography variant="h6" gutterBottom>
              Step 3: Configure Job Parameters
            </Typography>
            <Typography variant="body2" color="text.secondary" paragraph>
              Adjust the Slurm job configuration and input file paths.
              These values will be substituted into the command template.
            </Typography>

            <Grid container spacing={2}>
              <Grid item xs={12} sm={6}>
                <TextField
                  fullWidth
                  label="Partition"
                  value={jobConfig.partition}
                  onChange={(e) => setJobConfig({ ...jobConfig, partition: e.target.value })}
                />
              </Grid>
              <Grid item xs={12} sm={6}>
                <TextField
                  fullWidth
                  label="QoS"
                  value={jobConfig.qos}
                  onChange={(e) => setJobConfig({ ...jobConfig, qos: e.target.value })}
                />
              </Grid>
              <Grid item xs={12} sm={4}>
                <TextField
                  fullWidth
                  label="Nodes"
                  type="number"
                  value={jobConfig.nodes}
                  onChange={(e) => setJobConfig({ ...jobConfig, nodes: parseInt(e.target.value) })}
                />
              </Grid>
              <Grid item xs={12} sm={4}>
                <TextField
                  fullWidth
                  label="Tasks (ntasks)"
                  type="number"
                  value={jobConfig.ntasks}
                  onChange={(e) => setJobConfig({ ...jobConfig, ntasks: parseInt(e.target.value) })}
                />
              </Grid>
              <Grid item xs={12} sm={4}>
                <TextField
                  fullWidth
                  label="CPUs per Task"
                  type="number"
                  value={jobConfig['cpus-per-task']}
                  onChange={(e) => setJobConfig({ ...jobConfig, 'cpus-per-task': parseInt(e.target.value) })}
                />
              </Grid>
              <Grid item xs={12} sm={6}>
                <TextField
                  fullWidth
                  label="Memory"
                  value={jobConfig.mem}
                  onChange={(e) => setJobConfig({ ...jobConfig, mem: e.target.value })}
                  helperText="e.g., 32G, 512M"
                />
              </Grid>
              <Grid item xs={12} sm={6}>
                <TextField
                  fullWidth
                  label="Time Limit"
                  value={jobConfig.time}
                  onChange={(e) => setJobConfig({ ...jobConfig, time: e.target.value })}
                  helperText="Format: HH:MM:SS"
                />
              </Grid>

              <Grid item xs={12}>
                <Divider sx={{ my: 2 }} />
                <Typography variant="subtitle2" gutterBottom>
                  Input Files
                </Typography>
              </Grid>

              <Grid item xs={12}>
                <TextField
                  fullWidth
                  label="Python Script"
                  value={inputFiles.python_script}
                  onChange={(e) => setInputFiles({ ...inputFiles, python_script: e.target.value })}
                  helperText="Path to your Python simulation script"
                />
              </Grid>
            </Grid>
          </Box>
        );

      case 3:
        return (
          <Box>
            <Typography variant="h6" gutterBottom>
              Step 4: Review & Submit
            </Typography>
            <Typography variant="body2" color="text.secondary" paragraph>
              Review the generated Slurm script below. Make any final adjustments if needed,
              then submit the job.
            </Typography>

            <Paper
              elevation={0}
              sx={{
                bgcolor: 'grey.100',
                p: 2,
                fontFamily: 'monospace',
                fontSize: '0.875rem',
                overflowX: 'auto',
                maxHeight: '400px',
                overflowY: 'auto',
                mb: 2,
              }}
            >
              <pre style={{ margin: 0 }}>{generatedScript || '# No script generated yet'}</pre>
            </Paper>

            <Alert severity="info">
              This is a demonstration. Clicking Submit will show an alert instead of actually submitting the job.
            </Alert>
          </Box>
        );

      default:
        return null;
    }
  };

  return (
    <Container maxWidth="lg" sx={{ py: 4 }}>
      <Box mb={4}>
        <Typography variant="h4" gutterBottom>
          Command Template Example
        </Typography>
        <Typography variant="body1" color="text.secondary">
          This page demonstrates how to use the Apptainer Command Template System
          to generate Slurm job scripts with pre-configured commands and variable substitution.
        </Typography>
      </Box>

      {/* Stepper */}
      <Paper sx={{ p: 3, mb: 3 }}>
        <Stepper activeStep={activeStep} alternativeLabel>
          {steps.map((label) => (
            <Step key={label}>
              <StepLabel>{label}</StepLabel>
            </Step>
          ))}
        </Stepper>
      </Paper>

      {/* Step Content */}
      <Paper sx={{ p: 3, mb: 3, minHeight: '400px' }}>
        {renderStepContent()}
      </Paper>

      {/* Navigation */}
      <Box display="flex" justifyContent="space-between">
        <Button
          disabled={activeStep === 0}
          onClick={handleBack}
          startIcon={<BackIcon />}
        >
          Back
        </Button>

        <Box display="flex" gap={2}>
          {activeStep === steps.length - 1 ? (
            <Button
              variant="contained"
              color="primary"
              onClick={handleSubmit}
              startIcon={<SubmitIcon />}
              disabled={!generatedScript}
            >
              Submit Job
            </Button>
          ) : (
            <Button
              variant="contained"
              onClick={handleNext}
              endIcon={<NextIcon />}
              disabled={
                (activeStep === 0 && !selectedImage) ||
                (activeStep === 1 && !selectedTemplate)
              }
            >
              Next
            </Button>
          )}
        </Box>
      </Box>

      {/* Command Template Modal */}
      {selectedImage && (
        <CommandTemplateModal
          open={modalOpen}
          onClose={() => setModalOpen(false)}
          image={selectedImage}
          onSelectTemplate={handleTemplateSelect}
        />
      )}
    </Container>
  );
};

export default CommandTemplateExample;
