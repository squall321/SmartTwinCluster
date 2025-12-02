import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
/**
 * FileBrowser Component
 *
 * Simple file browser for selecting input files from the server.
 * Supports directory navigation and file selection.
 *
 * Features:
 * - Browse server directories
 * - Filter by file pattern (e.g., *.k, *.py)
 * - Select single or multiple files
 * - Display file metadata (size, modified date)
 * - Breadcrumb navigation
 */
import { useState, useEffect } from 'react';
import { Box, Dialog, DialogTitle, DialogContent, DialogActions, Button, List, ListItem, ListItemIcon, ListItemText, IconButton, Breadcrumbs, Link, Typography, CircularProgress, Alert, Chip, } from '@mui/material';
import { Folder as FolderIcon, InsertDriveFile as FileIcon, ArrowUpward as UpIcon, Home as HomeIcon, CheckCircle as CheckIcon, Close as CloseIcon, } from '@mui/icons-material';
const FileBrowser = ({ open, onClose, onSelect, filePattern = '*', multiSelect = false, initialPath = '/home', title = 'Select File', }) => {
    const [currentPath, setCurrentPath] = useState(initialPath);
    const [entries, setEntries] = useState([]);
    const [selectedFiles, setSelectedFiles] = useState([]);
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState(null);
    // Fetch directory contents
    useEffect(() => {
        if (open) {
            fetchDirectory(currentPath);
        }
    }, [currentPath, open]);
    const fetchDirectory = async (path) => {
        setLoading(true);
        setError(null);
        try {
            // TODO: Replace with actual API call to list directory contents
            // For now, this is a mock implementation
            const response = await fetch(`/api/files/list?path=${encodeURIComponent(path)}&pattern=${filePattern}`);
            if (!response.ok) {
                throw new Error(`Failed to fetch directory: ${response.statusText}`);
            }
            const data = await response.json();
            setEntries(data.entries || []);
        }
        catch (err) {
            console.error('Error fetching directory:', err);
            setError(err instanceof Error ? err.message : 'Failed to load directory');
            // Mock data for demonstration
            setEntries([
                { name: '..', path: path.split('/').slice(0, -1).join('/') || '/', type: 'directory' },
                { name: 'simulations', path: `${path}/simulations`, type: 'directory' },
                { name: 'input_files', path: `${path}/input_files`, type: 'directory' },
                { name: 'example.k', path: `${path}/example.k`, type: 'file', size: 1024000 },
                { name: 'simulation.py', path: `${path}/simulation.py`, type: 'file', size: 5120 },
            ]);
        }
        finally {
            setLoading(false);
        }
    };
    // Handle directory navigation
    const handleNavigate = (path) => {
        setCurrentPath(path);
        setSelectedFiles([]);
    };
    // Handle file selection
    const handleFileClick = (entry) => {
        if (entry.type === 'directory') {
            handleNavigate(entry.path);
        }
        else {
            if (multiSelect) {
                setSelectedFiles((prev) => {
                    if (prev.includes(entry.path)) {
                        return prev.filter((p) => p !== entry.path);
                    }
                    else {
                        return [...prev, entry.path];
                    }
                });
            }
            else {
                setSelectedFiles([entry.path]);
            }
        }
    };
    // Handle selection confirmation
    const handleConfirm = () => {
        onSelect(selectedFiles);
        onClose();
        setSelectedFiles([]);
    };
    // Format file size
    const formatSize = (bytes) => {
        if (!bytes)
            return '';
        const k = 1024;
        const sizes = ['B', 'KB', 'MB', 'GB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return `${(bytes / Math.pow(k, i)).toFixed(1)} ${sizes[i]}`;
    };
    // Get breadcrumb parts
    const getBreadcrumbs = () => {
        const parts = currentPath.split('/').filter((p) => p);
        return parts.map((part, index) => ({
            name: part,
            path: '/' + parts.slice(0, index + 1).join('/'),
        }));
    };
    return (_jsxs(Dialog, { open: open, onClose: onClose, maxWidth: "md", fullWidth: true, children: [_jsx(DialogTitle, { children: _jsxs(Box, { display: "flex", justifyContent: "space-between", alignItems: "center", children: [_jsx(Typography, { variant: "h6", children: title }), _jsx(IconButton, { onClick: onClose, size: "small", children: _jsx(CloseIcon, {}) })] }) }), _jsxs(DialogContent, { dividers: true, children: [_jsx(Box, { mb: 2, children: _jsxs(Breadcrumbs, { children: [_jsxs(Link, { component: "button", variant: "body2", onClick: () => handleNavigate('/'), sx: { display: 'flex', alignItems: 'center', cursor: 'pointer' }, children: [_jsx(HomeIcon, { sx: { mr: 0.5 }, fontSize: "small" }), "Root"] }), getBreadcrumbs().map((crumb, index) => (_jsx(Link, { component: "button", variant: "body2", onClick: () => handleNavigate(crumb.path), sx: { cursor: 'pointer' }, children: crumb.name }, index)))] }) }), filePattern !== '*' && (_jsx(Box, { mb: 2, children: _jsx(Chip, { label: `Filter: ${filePattern}`, size: "small", color: "primary" }) })), loading && (_jsx(Box, { display: "flex", justifyContent: "center", alignItems: "center", minHeight: "300px", children: _jsx(CircularProgress, {}) })), error && (_jsxs(Alert, { severity: "warning", sx: { mb: 2 }, children: [error, _jsx("br", {}), _jsx("small", { children: "Showing mock data for demonstration" })] })), !loading && (_jsxs(List, { sx: { minHeight: '400px', maxHeight: '400px', overflowY: 'auto' }, children: [entries.map((entry, index) => (_jsxs(ListItem, { button: true, onClick: () => handleFileClick(entry), selected: selectedFiles.includes(entry.path), sx: {
                                    '&:hover': {
                                        backgroundColor: 'action.hover',
                                    },
                                }, children: [_jsx(ListItemIcon, { children: entry.type === 'directory' ? (entry.name === '..' ? (_jsx(UpIcon, {})) : (_jsx(FolderIcon, { color: "primary" }))) : (_jsx(FileIcon, {})) }), _jsx(ListItemText, { primary: entry.name, secondary: entry.type === 'file' && entry.size
                                            ? formatSize(entry.size)
                                            : entry.type === 'directory'
                                                ? 'Directory'
                                                : '' }), selectedFiles.includes(entry.path) && (_jsx(CheckIcon, { color: "success" }))] }, index))), entries.length === 0 && !loading && (_jsx(Box, { display: "flex", justifyContent: "center", alignItems: "center", minHeight: "200px", children: _jsx(Typography, { variant: "body2", color: "text.secondary", children: "No files found in this directory" }) }))] })), selectedFiles.length > 0 && (_jsxs(Box, { mt: 2, children: [_jsxs(Typography, { variant: "subtitle2", gutterBottom: true, children: ["Selected (", selectedFiles.length, "):"] }), _jsx(Box, { display: "flex", flexWrap: "wrap", gap: 1, children: selectedFiles.map((file, index) => (_jsx(Chip, { label: file.split('/').pop(), size: "small", onDelete: () => setSelectedFiles((prev) => prev.filter((f) => f !== file)) }, index))) })] }))] }), _jsxs(DialogActions, { children: [_jsx(Button, { onClick: onClose, children: "Cancel" }), _jsxs(Button, { variant: "contained", onClick: handleConfirm, disabled: selectedFiles.length === 0, startIcon: _jsx(CheckIcon, {}), children: ["Select ", selectedFiles.length > 0 && `(${selectedFiles.length})`] })] })] }));
};
export default FileBrowser;
