import React from 'react';
export type FileEntry = {
    name: string;
    relpath: string;
    type: 'file' | 'dir';
    size?: number;
    mtime?: number;
    children?: FileEntry[];
};
interface Props {
    username: string;
    prefix?: string;
    allowDeleteDir?: boolean;
}
declare const FileTreeExplorer: React.FC<Props>;
export default FileTreeExplorer;
