/**
 * ApptainerImageSelector Component
 *
 * Allows users to browse and select Apptainer container images
 * with their associated command templates.
 *
 * Features:
 * - Display available Apptainer images from the cluster
 * - Show command template count badges
 * - Filter by partition (compute/viz) and type
 * - Search by image name or description
 * - Click to select image and view command templates
 */

import React, { useState, useEffect } from 'react';
import {
  Box,
  Card,
  CardContent,
  Typography,
  Chip,
  TextField,
  Select,
  MenuItem,
  FormControl,
  InputLabel,
  Grid,
  Badge,
  IconButton,
  Tooltip,
  CircularProgress,
  Alert,
} from '@mui/material';
import {
  Computer as ComputeIcon,
  Visibility as VizIcon,
  Extension as CustomIcon,
  Search as SearchIcon,
  Info as InfoIcon,
  Code as CodeIcon,
} from '@mui/icons-material';

import { CommandTemplate, ApptainerImage } from '../types/apptainer';

interface ApptainerImageSelectorProps {
  onSelectImage: (image: ApptainerImage) => void;
  onSelectTemplate?: (image: ApptainerImage, template: CommandTemplate) => void;
  selectedImageId?: string;
  partition?: 'compute' | 'viz' | 'shared' | null;
}

const ApptainerImageSelector: React.FC<ApptainerImageSelectorProps> = ({
  onSelectImage,
  onSelectTemplate,
  selectedImageId,
  partition: initialPartition = null,
}) => {
  const [images, setImages] = useState<ApptainerImage[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState('');
  const [partitionFilter, setPartitionFilter] = useState<string>(initialPartition || 'all');
  const [typeFilter, setTypeFilter] = useState<string>('all');

  // Fetch Apptainer images from API
  useEffect(() => {
    fetchImages();
  }, [partitionFilter]);

  const fetchImages = async () => {
    setLoading(true);
    setError(null);

    try {
      const params = new URLSearchParams();
      if (partitionFilter && partitionFilter !== 'all') {
        params.append('partition', partitionFilter);
      }

      const response = await fetch(`/api/apptainer/images?${params.toString()}`);

      if (!response.ok) {
        throw new Error(`Failed to fetch images: ${response.statusText}`);
      }

      const data = await response.json();
      setImages(data.images || []);
    } catch (err) {
      console.error('Error fetching Apptainer images:', err);
      setError(err instanceof Error ? err.message : 'Failed to load images');
    } finally {
      setLoading(false);
    }
  };

  // Filter images based on search query and type
  const filteredImages = images.filter((image) => {
    // Search filter
    const matchesSearch =
      searchQuery === '' ||
      image.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
      (image.description ?? "").toLowerCase().includes(searchQuery.toLowerCase());

    // Type filter
    const matchesType = typeFilter === 'all' || image.type === typeFilter;

    return matchesSearch && matchesType;
  });

  // Get icon based on image type
  const getTypeIcon = (type?: string) => {
    switch (type) {
      case 'compute':
        return <ComputeIcon />;
      case 'viz':
        return <VizIcon />;
      default:
        return <CustomIcon />;
    }
  };

  // Get color based on partition
  const getPartitionColor = (partition: string) => {
    switch (partition) {
      case 'compute':
        return 'primary';
      case 'viz':
        return 'secondary';
      default:
        return 'default';
    }
  };

  // Format file size
  const formatSize = (bytes: number): string => {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return `${(bytes / Math.pow(k, i)).toFixed(2)} ${sizes[i]}`;
  };

  // Handle image selection
  const handleImageClick = (image: ApptainerImage) => {
    onSelectImage(image);
  };

  if (loading) {
    return (
      <Box display="flex" justifyContent="center" alignItems="center" minHeight="300px">
        <CircularProgress />
      </Box>
    );
  }

  if (error) {
    return (
      <Alert severity="error" onClose={() => setError(null)}>
        {error}
      </Alert>
    );
  }

  return (
    <Box>
      {/* Header and Filters */}
      <Box mb={3}>
        <Typography variant="h6" gutterBottom>
          Select Apptainer Image
        </Typography>

        <Grid container spacing={2} alignItems="center">
          {/* Search */}
          <Grid item xs={12} sm={6}>
            <TextField
              fullWidth
              size="small"
              placeholder="Search images..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              InputProps={{
                startAdornment: <SearchIcon color="action" sx={{ mr: 1 }} />,
              }}
            />
          </Grid>

          {/* Partition Filter */}
          <Grid item xs={12} sm={3}>
            <FormControl fullWidth size="small">
              <InputLabel>Partition</InputLabel>
              <Select
                value={partitionFilter}
                label="Partition"
                onChange={(e) => setPartitionFilter(e.target.value)}
              >
                <MenuItem value="all">All Partitions</MenuItem>
                <MenuItem value="compute">Compute</MenuItem>
                <MenuItem value="viz">Visualization</MenuItem>
                <MenuItem value="shared">Shared</MenuItem>
              </Select>
            </FormControl>
          </Grid>

          {/* Type Filter */}
          <Grid item xs={12} sm={3}>
            <FormControl fullWidth size="small">
              <InputLabel>Type</InputLabel>
              <Select
                value={typeFilter}
                label="Type"
                onChange={(e) => setTypeFilter(e.target.value)}
              >
                <MenuItem value="all">All Types</MenuItem>
                <MenuItem value="compute">Compute</MenuItem>
                <MenuItem value="viz">Visualization</MenuItem>
                <MenuItem value="custom">Custom</MenuItem>
              </Select>
            </FormControl>
          </Grid>
        </Grid>
      </Box>

      {/* Image Grid */}
      {filteredImages.length === 0 ? (
        <Alert severity="info">
          No images found matching your criteria. Try adjusting the filters.
        </Alert>
      ) : (
        <Grid container spacing={2}>
          {filteredImages.map((image) => (
            <Grid item xs={12} sm={6} md={4} key={image.id}>
              <Card
                sx={{
                  cursor: 'pointer',
                  transition: 'all 0.2s',
                  border: selectedImageId === image.id ? 2 : 1,
                  borderColor: selectedImageId === image.id ? 'primary.main' : 'divider',
                  '&:hover': {
                    boxShadow: 3,
                    transform: 'translateY(-2px)',
                  },
                }}
                onClick={() => handleImageClick(image)}
              >
                <CardContent>
                  {/* Header with icon and badges */}
                  <Box display="flex" justifyContent="space-between" alignItems="flex-start" mb={2}>
                    <Box display="flex" alignItems="center" gap={1}>
                      {getTypeIcon(image.type)}
                      <Typography variant="subtitle2" fontWeight="bold" noWrap>
                        {image.name}
                      </Typography>
                    </Box>

                    {/* Command template badge */}
                    {image.command_templates && image.command_templates.length > 0 && (
                      <Tooltip title={`${image.command_templates.length} command template(s)`}>
                        <Badge badgeContent={image.command_templates.length} color="success">
                          <CodeIcon fontSize="small" />
                        </Badge>
                      </Tooltip>
                    )}
                  </Box>

                  {/* Partition and Version */}
                  <Box display="flex" gap={1} mb={1}>
                    <Chip
                      label={image.partition}
                      size="small"
                      color={getPartitionColor(image.partition) as any}
                    />
                    <Chip label={`v${image.version}`} size="small" variant="outlined" />
                  </Box>

                  {/* Description */}
                  <Typography
                    variant="body2"
                    color="text.secondary"
                    sx={{
                      overflow: 'hidden',
                      textOverflow: 'ellipsis',
                      display: '-webkit-box',
                      WebkitLineClamp: 2,
                      WebkitBoxOrient: 'vertical',
                      minHeight: '40px',
                      mb: 1,
                    }}
                  >
                    {image.description || 'No description available'}
                  </Typography>

                  {/* Footer */}
                  <Box display="flex" justifyContent="space-between" alignItems="center" mt={2}>
                    <Typography variant="caption" color="text.secondary">
                      {formatSize(image.size ?? 0)}
                    </Typography>

                    {/* Info button */}
                    <Tooltip title="View details">
                      <IconButton size="small" onClick={(e) => {
                        e.stopPropagation();
                        // TODO: Open image details modal
                      }}>
                        <InfoIcon fontSize="small" />
                      </IconButton>
                    </Tooltip>
                  </Box>
                </CardContent>
              </Card>
            </Grid>
          ))}
        </Grid>
      )}

      {/* Summary */}
      <Box mt={2}>
        <Typography variant="caption" color="text.secondary">
          Showing {filteredImages.length} of {images.length} image(s)
        </Typography>
      </Box>
    </Box>
  );
};

export default ApptainerImageSelector;
