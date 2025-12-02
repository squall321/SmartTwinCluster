import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
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
import { useState, useEffect } from 'react';
import { Box, Card, CardContent, Typography, Chip, TextField, Select, MenuItem, FormControl, InputLabel, Grid, Badge, IconButton, Tooltip, CircularProgress, Alert, } from '@mui/material';
import { Computer as ComputeIcon, Visibility as VizIcon, Extension as CustomIcon, Search as SearchIcon, Info as InfoIcon, Code as CodeIcon, } from '@mui/icons-material';
const ApptainerImageSelector = ({ onSelectImage, onSelectTemplate, selectedImageId, partition: initialPartition = null, }) => {
    const [images, setImages] = useState([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);
    const [searchQuery, setSearchQuery] = useState('');
    const [partitionFilter, setPartitionFilter] = useState(initialPartition || 'all');
    const [typeFilter, setTypeFilter] = useState('all');
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
        }
        catch (err) {
            console.error('Error fetching Apptainer images:', err);
            setError(err instanceof Error ? err.message : 'Failed to load images');
        }
        finally {
            setLoading(false);
        }
    };
    // Filter images based on search query and type
    const filteredImages = images.filter((image) => {
        // Search filter
        const matchesSearch = searchQuery === '' ||
            image.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
            image.description.toLowerCase().includes(searchQuery.toLowerCase());
        // Type filter
        const matchesType = typeFilter === 'all' || image.type === typeFilter;
        return matchesSearch && matchesType;
    });
    // Get icon based on image type
    const getTypeIcon = (type) => {
        switch (type) {
            case 'compute':
                return _jsx(ComputeIcon, {});
            case 'viz':
                return _jsx(VizIcon, {});
            default:
                return _jsx(CustomIcon, {});
        }
    };
    // Get color based on partition
    const getPartitionColor = (partition) => {
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
    const formatSize = (bytes) => {
        if (bytes === 0)
            return '0 B';
        const k = 1024;
        const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return `${(bytes / Math.pow(k, i)).toFixed(2)} ${sizes[i]}`;
    };
    // Handle image selection
    const handleImageClick = (image) => {
        onSelectImage(image);
    };
    if (loading) {
        return (_jsx(Box, { display: "flex", justifyContent: "center", alignItems: "center", minHeight: "300px", children: _jsx(CircularProgress, {}) }));
    }
    if (error) {
        return (_jsx(Alert, { severity: "error", onClose: () => setError(null), children: error }));
    }
    return (_jsxs(Box, { children: [_jsxs(Box, { mb: 3, children: [_jsx(Typography, { variant: "h6", gutterBottom: true, children: "Select Apptainer Image" }), _jsxs(Grid, { container: true, spacing: 2, alignItems: "center", children: [_jsx(Grid, { item: true, xs: 12, sm: 6, children: _jsx(TextField, { fullWidth: true, size: "small", placeholder: "Search images...", value: searchQuery, onChange: (e) => setSearchQuery(e.target.value), InputProps: {
                                        startAdornment: _jsx(SearchIcon, { color: "action", sx: { mr: 1 } }),
                                    } }) }), _jsx(Grid, { item: true, xs: 12, sm: 3, children: _jsxs(FormControl, { fullWidth: true, size: "small", children: [_jsx(InputLabel, { children: "Partition" }), _jsxs(Select, { value: partitionFilter, label: "Partition", onChange: (e) => setPartitionFilter(e.target.value), children: [_jsx(MenuItem, { value: "all", children: "All Partitions" }), _jsx(MenuItem, { value: "compute", children: "Compute" }), _jsx(MenuItem, { value: "viz", children: "Visualization" }), _jsx(MenuItem, { value: "shared", children: "Shared" })] })] }) }), _jsx(Grid, { item: true, xs: 12, sm: 3, children: _jsxs(FormControl, { fullWidth: true, size: "small", children: [_jsx(InputLabel, { children: "Type" }), _jsxs(Select, { value: typeFilter, label: "Type", onChange: (e) => setTypeFilter(e.target.value), children: [_jsx(MenuItem, { value: "all", children: "All Types" }), _jsx(MenuItem, { value: "compute", children: "Compute" }), _jsx(MenuItem, { value: "viz", children: "Visualization" }), _jsx(MenuItem, { value: "custom", children: "Custom" })] })] }) })] })] }), filteredImages.length === 0 ? (_jsx(Alert, { severity: "info", children: "No images found matching your criteria. Try adjusting the filters." })) : (_jsx(Grid, { container: true, spacing: 2, children: filteredImages.map((image) => (_jsx(Grid, { item: true, xs: 12, sm: 6, md: 4, children: _jsx(Card, { sx: {
                            cursor: 'pointer',
                            transition: 'all 0.2s',
                            border: selectedImageId === image.id ? 2 : 1,
                            borderColor: selectedImageId === image.id ? 'primary.main' : 'divider',
                            '&:hover': {
                                boxShadow: 3,
                                transform: 'translateY(-2px)',
                            },
                        }, onClick: () => handleImageClick(image), children: _jsxs(CardContent, { children: [_jsxs(Box, { display: "flex", justifyContent: "space-between", alignItems: "flex-start", mb: 2, children: [_jsxs(Box, { display: "flex", alignItems: "center", gap: 1, children: [getTypeIcon(image.type), _jsx(Typography, { variant: "subtitle2", fontWeight: "bold", noWrap: true, children: image.name })] }), image.command_templates && image.command_templates.length > 0 && (_jsx(Tooltip, { title: `${image.command_templates.length} command template(s)`, children: _jsx(Badge, { badgeContent: image.command_templates.length, color: "success", children: _jsx(CodeIcon, { fontSize: "small" }) }) }))] }), _jsxs(Box, { display: "flex", gap: 1, mb: 1, children: [_jsx(Chip, { label: image.partition, size: "small", color: getPartitionColor(image.partition) }), _jsx(Chip, { label: `v${image.version}`, size: "small", variant: "outlined" })] }), _jsx(Typography, { variant: "body2", color: "text.secondary", sx: {
                                        overflow: 'hidden',
                                        textOverflow: 'ellipsis',
                                        display: '-webkit-box',
                                        WebkitLineClamp: 2,
                                        WebkitBoxOrient: 'vertical',
                                        minHeight: '40px',
                                        mb: 1,
                                    }, children: image.description || 'No description available' }), _jsxs(Box, { display: "flex", justifyContent: "space-between", alignItems: "center", mt: 2, children: [_jsx(Typography, { variant: "caption", color: "text.secondary", children: formatSize(image.size) }), _jsx(Tooltip, { title: "View details", children: _jsx(IconButton, { size: "small", onClick: (e) => {
                                                    e.stopPropagation();
                                                    // TODO: Open image details modal
                                                }, children: _jsx(InfoIcon, { fontSize: "small" }) }) })] })] }) }) }, image.id))) })), _jsx(Box, { mt: 2, children: _jsxs(Typography, { variant: "caption", color: "text.secondary", children: ["Showing ", filteredImages.length, " of ", images.length, " image(s)"] }) })] }));
};
export default ApptainerImageSelector;
