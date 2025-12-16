import { jsx as _jsx, Fragment as _Fragment, jsxs as _jsxs } from "react/jsx-runtime";
// FileTreeExplorer.tsx (axios 적용 및 개선 반영)
import { useCallback, useEffect, useMemo, useState } from 'react';
import { Tree, Button, Typography, Space, message, Modal, Spin, Input, Upload } from 'antd';
import { FolderOpenOutlined, FolderOutlined, FileOutlined, DeleteOutlined, ReloadOutlined, FolderAddOutlined, UploadOutlined, } from '@ant-design/icons';
import { api } from '../../api/axiosClient';
const { Text, Title } = Typography;
const FileTreeExplorer = ({ username, prefix, allowDeleteDir = true }) => {
    const [rootEntry, setRootEntry] = useState(null);
    const [treeData, setTreeData] = useState([]);
    const [expandedKeys, setExpandedKeys] = useState([]);
    const [selectedKeys, setSelectedKeys] = useState([]);
    const [checkedKeys, setCheckedKeys] = useState([]);
    const [loading, setLoading] = useState(false);
    const [mkdirModalOpen, setMkdirModalOpen] = useState(false);
    const [newDirName, setNewDirName] = useState('');
    // Use the shared axios instance with JWT interceptor
    const baseUrl = useMemo(() => `/api/files/${username}`, [username]);
    const buildUrl = useCallback((relpath) => {
        const safe = relpath.split('/').map(encodeURIComponent).join('/');
        return `${baseUrl}/${safe}`;
    }, [baseUrl]);
    const fetchRoot = useCallback(async () => {
        setLoading(true);
        try {
            const res = await api.get(baseUrl);
            setRootEntry(res.data);
        }
        catch (err) {
            console.error(err);
            message.error(`파일 트리 불러오기 실패: ${err?.message || err}`);
        }
        finally {
            setLoading(false);
        }
    }, [baseUrl]);
    useEffect(() => { fetchRoot(); }, [fetchRoot]);
    const filterByPrefix = useCallback((entry) => {
        if (!prefix)
            return entry;
        if (entry.type === 'file')
            return entry.name.startsWith(prefix) ? entry : null;
        const children = entry.children?.map(filterByPrefix).filter((c) => c !== null);
        return { ...entry, children };
    }, [prefix]);
    const toTreeData = useCallback((entry) => ({
        key: entry.relpath,
        entry,
        title: _jsx(NodeTitle, { entry: entry, onDelete: async () => await handleDelete(entry) }),
        icon: entry.type === 'dir' ? (expandedKeys.includes(entry.relpath) ? _jsx(FolderOpenOutlined, {}) : _jsx(FolderOutlined, {})) : _jsx(FileOutlined, {}),
        isLeaf: entry.type === 'file',
        children: entry.children?.map(toTreeData),
    }), [expandedKeys]);
    useEffect(() => {
        if (!rootEntry)
            return;
        const filtered = filterByPrefix(rootEntry);
        if (!filtered)
            return setTreeData([]);
        setTreeData([toTreeData(filtered)]);
    }, [rootEntry, filterByPrefix, toTreeData]);
    const onExpand = (keys) => setExpandedKeys(keys);
    const onSelect = (keys) => setSelectedKeys(keys);
    const onCheck = (checkedKeysValue) => {
        const keys = Array.isArray(checkedKeysValue) ? checkedKeysValue : checkedKeysValue.checked;
        setCheckedKeys(keys);
    };
    const findEntryByRelpath = useCallback((entry, relpath) => {
        if (entry.relpath === relpath)
            return entry;
        if (!entry.children)
            return null;
        for (const child of entry.children) {
            const found = findEntryByRelpath(child, relpath);
            if (found)
                return found;
        }
        return null;
    }, []);
    const handleDelete = useCallback(async (entry) => {
        if (entry.type === 'dir' && !allowDeleteDir) {
            message.warning('디렉토리 삭제는 허용되어 있지 않습니다.');
            return;
        }
        Modal.confirm({
            title: `${entry.type === 'dir' ? '폴더' : '파일'} 삭제`,
            content: _jsxs("span", { children: ["\uC815\uB9D0\uB85C ", _jsx(Text, { code: true, children: entry.name }), " \uB97C \uC0AD\uC81C\uD558\uC2DC\uACA0\uC2B5\uB2C8\uAE4C?", entry.type === 'dir' && allowDeleteDir && _jsxs(_Fragment, { children: [_jsx("br", {}), _jsx(Text, { type: "secondary", children: "(\uD558\uC704 \uBAA8\uB4E0 \uD30C\uC77C/\uD3F4\uB354\uAC00 \uAC19\uC774 \uC0AD\uC81C\uB429\uB2C8\uB2E4)" })] })] }),
            okType: 'danger', okText: '삭제', cancelText: '취소',
            onOk: async () => {
                try {
                    await api.delete(buildUrl(entry.relpath), { params: { recursive: entry.type === 'dir' } });
                    message.success('삭제되었습니다.');
                    await fetchRoot();
                }
                catch (e) {
                    console.error(e);
                    message.error(`삭제 실패: ${e?.message || e}`);
                }
            },
        });
    }, [allowDeleteDir, buildUrl, fetchRoot]);
    const currentSelectedDir = useMemo(() => {
        if (!selectedKeys.length || !rootEntry)
            return '';
        const rel = String(selectedKeys[0]);
        const entry = findEntryByRelpath(rootEntry, rel);
        if (!entry)
            return '';
        return entry.type === 'dir' ? entry.relpath : rel.split('/').slice(0, -1).join('/');
    }, [selectedKeys, rootEntry, findEntryByRelpath]);
    const submitMkdir = async () => {
        if (!newDirName)
            return;
        const target = currentSelectedDir || '';
        const url = `${baseUrl}/${encodeURIComponent(target + '/' + newDirName)}`;
        try {
            await api.post(url, null, { params: { mkdir: true } });
            message.success('폴더가 생성되었습니다.');
            setMkdirModalOpen(false);
            setNewDirName('');
            await fetchRoot();
        }
        catch (e) {
            message.error(`폴더 생성 실패: ${e?.message || e}`);
        }
    };
    const uploadProps = {
        name: 'file',
        multiple: true,
        customRequest: async (options) => {
            const { file, onSuccess, onError, onProgress } = options;
            try {
                const dir = currentSelectedDir || '.';
                const url = `${baseUrl}/${encodeURIComponent(dir)}`;
                const formData = new FormData();
                formData.append('file', file);
                await api.post(url, formData, {
                    headers: { 'Content-Type': 'multipart/form-data' },
                    onUploadProgress: ({ loaded, total }) => {
                        if (total)
                            onProgress?.({ percent: (loaded / total) * 100 }, file);
                    }
                });
                onSuccess?.({}, file);
                await fetchRoot();
            }
            catch (err) {
                onError?.(err);
            }
        }
    };
    return (_jsxs("div", { children: [_jsxs(Space, { style: { marginBottom: 8 }, wrap: true, children: [_jsx(Title, { level: 4, style: { margin: 0 }, children: "\uD83D\uDCC2 \uD30C\uC77C \uD0D0\uC0C9\uAE30" }), _jsx(Button, { icon: _jsx(ReloadOutlined, {}), onClick: fetchRoot, children: "\uC0C8\uB85C\uACE0\uCE68" }), _jsx(Button, { icon: _jsx(FolderAddOutlined, {}), onClick: () => setMkdirModalOpen(true), children: "\uD3F4\uB354 \uC0DD\uC131" }), _jsxs(Button, { danger: true, icon: _jsx(DeleteOutlined, {}), onClick: async () => {
                            const targets = checkedKeys;
                            if (!rootEntry || targets.length === 0) {
                                message.warning('선택된 파일/폴더가 없습니다.');
                                return;
                            }
                            const confirm = await Modal.confirm({
                                title: '선택 항목 일괄 삭제',
                                content: `총 ${targets.length}개가 삭제됩니다. 계속하시겠습니까?`,
                            });
                            try {
                                await Promise.all(targets.map(k => api.delete(buildUrl(String(k)), {
                                    params: { recursive: true },
                                })));
                                message.success('일괄 삭제 완료');
                                setCheckedKeys([]);
                                await fetchRoot();
                            }
                            catch (e) {
                                message.error(`삭제 중 오류: ${e?.message || e}`);
                            }
                        }, children: ["\uC120\uD0DD \uD56D\uBAA9 \uC0AD\uC81C (", checkedKeys.length, "\uAC1C)"] })] }), _jsxs(Upload.Dragger, { ...uploadProps, style: { marginBottom: 12 }, children: [_jsx("p", { className: "ant-upload-drag-icon", children: _jsx(UploadOutlined, {}) }), _jsx("p", { className: "ant-upload-text", children: "\uD30C\uC77C\uC744 \uB4DC\uB798\uADF8\uD558\uAC70\uB098 \uD074\uB9AD\uD574\uC11C \uC5C5\uB85C\uB4DC" }), _jsx("p", { className: "ant-upload-hint", children: "\uC120\uD0DD\uB41C(\uB610\uB294 \uC0C1\uC704) \uB514\uB809\uD1A0\uB9AC\uB85C \uC5C5\uB85C\uB4DC\uB429\uB2C8\uB2E4." })] }), loading && _jsx("div", { style: { padding: '2rem 0', textAlign: 'center' }, children: _jsx(Spin, {}) }), !loading && treeData.length === 0 && _jsx(Text, { type: "secondary", children: "\uD45C\uC2DC\uD560 \uD30C\uC77C\uC774 \uC5C6\uC2B5\uB2C8\uB2E4." }), !loading && treeData.length > 0 && (_jsx(Tree, { showIcon: true, checkable: true, multiple: true, selectable: true, expandedKeys: expandedKeys, onExpand: onExpand, selectedKeys: selectedKeys, onSelect: onSelect, checkedKeys: checkedKeys, onCheck: onCheck, treeData: treeData })), _jsx(Modal, { title: "\uD3F4\uB354 \uC0DD\uC131", open: mkdirModalOpen, onOk: submitMkdir, onCancel: () => setMkdirModalOpen(false), children: _jsx(Input, { placeholder: "\uC0C8 \uD3F4\uB354 \uC774\uB984", value: newDirName, onChange: (e) => setNewDirName(e.target.value) }) })] }));
};
export default FileTreeExplorer;
const NodeTitle = ({ entry, onDelete }) => (_jsxs(Space, { size: 4, children: [_jsx("span", { children: entry.name }), _jsx(Button, { size: "small", type: "text", danger: true, icon: _jsx(DeleteOutlined, {}), onClick: (e) => {
                e.stopPropagation();
                onDelete();
            } })] }));
