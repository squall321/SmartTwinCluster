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

import React, { useState, useEffect } from 'react';
import {
  Box,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  Button,
  List,
  ListItem,
  ListItemIcon,
  ListItemText,
  IconButton,
  TextField,
  Breadcrumbs,
  Link,
  Typography,
  CircularProgress,
  Alert,
  Chip,
} from '@mui/material';
import {
  Folder as FolderIcon,
  InsertDriveFile as FileIcon,
  ArrowUpward as UpIcon,
  Home as HomeIcon,
  CheckCircle as CheckIcon,
  Close as CloseIcon,
} from '@mui/icons-material';

interface FileEntry {
  name: string;
  path: string;
  type: 'file' | 'directory';
  size?: number;
  modified?: string;
}

interface FileBrowserProps {
  /**
   * Whether the dialog is open
   */
  open: boolean;

  /**
   * Callback when dialog is closed
   */
  onClose: () => void;

  /**
   * Callback when file(s) are selected
   * @param files - Selected file paths
   */
  onSelect: (files: string[]) => void;

  /**
   * File pattern to filter (e.g., "*.k", "*.py")
   */
  filePattern?: string;

  /**
   * Allow multiple file selection
   */
  multiSelect?: boolean;

  /**
   * Initial directory to browse
   */
  initialPath?: string;

  /**
   * Dialog title
   */
  title?: string;
}

const FileBrowser: React.FC<FileBrowserProps> = ({
  open,
  onClose,
  onSelect,
  filePattern = '*',
  multiSelect = false,
  initialPath = '/home',
  title = 'Select File',
}) => {
  const [currentPath, setCurrentPath] = useState(initialPath);
  const [entries, setEntries] = useState<FileEntry[]>([]);
  const [selectedFiles, setSelectedFiles] = useState<string[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Fetch directory contents
  useEffect(() => {
    if (open) {
      fetchDirectory(currentPath);
    }
  }, [currentPath, open]);

  const fetchDirectory = async (path: string) => {
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
    } catch (err) {
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
    } finally {
      setLoading(false);
    }
  };

  // Handle directory navigation
  const handleNavigate = (path: string) => {
    setCurrentPath(path);
    setSelectedFiles([]);
  };

  // Handle file selection
  const handleFileClick = (entry: FileEntry) => {
    if (entry.type === 'directory') {
      handleNavigate(entry.path);
    } else {
      if (multiSelect) {
        setSelectedFiles((prev) => {
          if (prev.includes(entry.path)) {
            return prev.filter((p) => p !== entry.path);
          } else {
            return [...prev, entry.path];
          }
        });
      } else {
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
  const formatSize = (bytes?: number): string => {
    if (!bytes) return '';
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

  return (
    <Dialog open={open} onClose={onClose} maxWidth="md" fullWidth>
      <DialogTitle>
        <Box display="flex" justifyContent="space-between" alignItems="center">
          <Typography variant="h6">{title}</Typography>
          <IconButton onClick={onClose} size="small">
            <CloseIcon />
          </IconButton>
        </Box>
      </DialogTitle>

      <DialogContent dividers>
        {/* Breadcrumb Navigation */}
        <Box mb={2}>
          <Breadcrumbs>
            <Link
              component="button"
              variant="body2"
              onClick={() => handleNavigate('/')}
              sx={{ display: 'flex', alignItems: 'center', cursor: 'pointer' }}
            >
              <HomeIcon sx={{ mr: 0.5 }} fontSize="small" />
              Root
            </Link>
            {getBreadcrumbs().map((crumb, index) => (
              <Link
                key={index}
                component="button"
                variant="body2"
                onClick={() => handleNavigate(crumb.path)}
                sx={{ cursor: 'pointer' }}
              >
                {crumb.name}
              </Link>
            ))}
          </Breadcrumbs>
        </Box>

        {/* File Pattern Info */}
        {filePattern !== '*' && (
          <Box mb={2}>
            <Chip label={`Filter: ${filePattern}`} size="small" color="primary" />
          </Box>
        )}

        {/* Loading State */}
        {loading && (
          <Box display="flex" justifyContent="center" alignItems="center" minHeight="300px">
            <CircularProgress />
          </Box>
        )}

        {/* Error Display */}
        {error && (
          <Alert severity="warning" sx={{ mb: 2 }}>
            {error}
            <br />
            <small>Showing mock data for demonstration</small>
          </Alert>
        )}

        {/* File List */}
        {!loading && (
          <List sx={{ minHeight: '400px', maxHeight: '400px', overflowY: 'auto' }}>
            {entries.map((entry, index) => (
              <ListItem
                key={index}
                button
                onClick={() => handleFileClick(entry)}
                selected={selectedFiles.includes(entry.path)}
                sx={{
                  '&:hover': {
                    backgroundColor: 'action.hover',
                  },
                }}
              >
                <ListItemIcon>
                  {entry.type === 'directory' ? (
                    entry.name === '..' ? (
                      <UpIcon />
                    ) : (
                      <FolderIcon color="primary" />
                    )
                  ) : (
                    <FileIcon />
                  )}
                </ListItemIcon>

                <ListItemText
                  primary={entry.name}
                  secondary={
                    entry.type === 'file' && entry.size
                      ? formatSize(entry.size)
                      : entry.type === 'directory'
                      ? 'Directory'
                      : ''
                  }
                />

                {selectedFiles.includes(entry.path) && (
                  <CheckIcon color="success" />
                )}
              </ListItem>
            ))}

            {entries.length === 0 && !loading && (
              <Box
                display="flex"
                justifyContent="center"
                alignItems="center"
                minHeight="200px"
              >
                <Typography variant="body2" color="text.secondary">
                  No files found in this directory
                </Typography>
              </Box>
            )}
          </List>
        )}

        {/* Selected Files Summary */}
        {selectedFiles.length > 0 && (
          <Box mt={2}>
            <Typography variant="subtitle2" gutterBottom>
              Selected ({selectedFiles.length}):
            </Typography>
            <Box display="flex" flexWrap="wrap" gap={1}>
              {selectedFiles.map((file, index) => (
                <Chip
                  key={index}
                  label={file.split('/').pop()}
                  size="small"
                  onDelete={() =>
                    setSelectedFiles((prev) => prev.filter((f) => f !== file))
                  }
                />
              ))}
            </Box>
          </Box>
        )}
      </DialogContent>

      <DialogActions>
        <Button onClick={onClose}>Cancel</Button>
        <Button
          variant="contained"
          onClick={handleConfirm}
          disabled={selectedFiles.length === 0}
          startIcon={<CheckIcon />}
        >
          Select {selectedFiles.length > 0 && `(${selectedFiles.length})`}
        </Button>
      </DialogActions>
    </Dialog>
  );
};

export default FileBrowser;
