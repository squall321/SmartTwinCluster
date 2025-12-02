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
import React from 'react';
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
declare const FileBrowser: React.FC<FileBrowserProps>;
export default FileBrowser;
