// FileTreeExplorer.tsx (axios 적용 및 개선 반영)
import React, { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Tree, Button, Typography, Space, message, Modal, Spin, Input, Upload
} from 'antd';
import type { DataNode, TreeProps } from 'antd/es/tree';
import {
  FolderOpenOutlined,
  FolderOutlined,
  FileOutlined,
  DeleteOutlined,
  ReloadOutlined,
  FolderAddOutlined,
  UploadOutlined,
} from '@ant-design/icons';
import { api } from '../../api/axiosClient';

const { Text, Title } = Typography;

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

interface TreeNode extends DataNode {
  key: string;
  entry: FileEntry;
  children?: TreeNode[];
}

const FileTreeExplorer: React.FC<Props> = ({ username, prefix, allowDeleteDir = true }) => {
  const [rootEntry, setRootEntry] = useState<FileEntry | null>(null);
  const [treeData, setTreeData] = useState<TreeNode[]>([]);
  const [expandedKeys, setExpandedKeys] = useState<React.Key[]>([]);
  const [selectedKeys, setSelectedKeys] = useState<React.Key[]>([]);
  const [checkedKeys, setCheckedKeys] = useState<React.Key[]>([]);
  const [loading, setLoading] = useState(false);
  const [mkdirModalOpen, setMkdirModalOpen] = useState(false);
  const [newDirName, setNewDirName] = useState('');

  // Use the shared axios instance with JWT interceptor
  const baseUrl = useMemo(() => `/api/files/${username}`, [username]);

  const buildUrl = useCallback((relpath: string) => {
    const safe = relpath.split('/').map(encodeURIComponent).join('/');
    return `${baseUrl}/${safe}`;
  }, [baseUrl]);

  const fetchRoot = useCallback(async () => {
    setLoading(true);
    try {
      const res = await api.get(baseUrl);
      setRootEntry(res.data);
    } catch (err: any) {
      console.error(err);
      message.error(`파일 트리 불러오기 실패: ${err?.message || err}`);
    } finally {
      setLoading(false);
    }
  }, [baseUrl]);

  useEffect(() => { fetchRoot(); }, [fetchRoot]);

  const filterByPrefix = useCallback((entry: FileEntry): FileEntry | null => {
    if (!prefix) return entry;
    if (entry.type === 'file') return entry.name.startsWith(prefix) ? entry : null;
    const children = entry.children?.map(filterByPrefix).filter((c): c is FileEntry => c !== null);
    return { ...entry, children };
  }, [prefix]);

  const toTreeData = useCallback((entry: FileEntry): TreeNode => ({
    key: entry.relpath,
    entry,
    title: <NodeTitle entry={entry} onDelete={async () => await handleDelete(entry)} />,
    icon: entry.type === 'dir' ? (
      expandedKeys.includes(entry.relpath) ? <FolderOpenOutlined /> : <FolderOutlined />
    ) : <FileOutlined />,
    isLeaf: entry.type === 'file',
    children: entry.children?.map(toTreeData),
  }), [expandedKeys]);

  useEffect(() => {
    if (!rootEntry) return;
    const filtered = filterByPrefix(rootEntry);
    if (!filtered) return setTreeData([]);
    setTreeData([toTreeData(filtered)]);
  }, [rootEntry, filterByPrefix, toTreeData]);

  const onExpand: TreeProps['onExpand'] = (keys) => setExpandedKeys(keys);
  const onSelect: TreeProps['onSelect'] = (keys) => setSelectedKeys(keys);
  const onCheck: TreeProps['onCheck'] = (checkedKeysValue) => {
    const keys = Array.isArray(checkedKeysValue) ? checkedKeysValue : (checkedKeysValue as any).checked;
    setCheckedKeys(keys);
  };

  const findEntryByRelpath = useCallback((entry: FileEntry, relpath: string): FileEntry | null => {
    if (entry.relpath === relpath) return entry;
    if (!entry.children) return null;
    for (const child of entry.children) {
      const found = findEntryByRelpath(child, relpath);
      if (found) return found;
    }
    return null;
  }, []);

  const handleDelete = useCallback(async (entry: FileEntry) => {
    if (entry.type === 'dir' && !allowDeleteDir) {
      message.warning('디렉토리 삭제는 허용되어 있지 않습니다.');
      return;
    }
    Modal.confirm({
      title: `${entry.type === 'dir' ? '폴더' : '파일'} 삭제`,
      content: <span>정말로 <Text code>{entry.name}</Text> 를 삭제하시겠습니까?
        {entry.type === 'dir' && allowDeleteDir && <><br /><Text type="secondary">(하위 모든 파일/폴더가 같이 삭제됩니다)</Text></>}
      </span>,
      okType: 'danger', okText: '삭제', cancelText: '취소',
      onOk: async () => {
        try {
          await api.delete(buildUrl(entry.relpath), { params: { recursive: entry.type === 'dir' } });
          message.success('삭제되었습니다.');
          await fetchRoot();
        } catch (e: any) {
          console.error(e);
          message.error(`삭제 실패: ${e?.message || e}`);
        }
      },
    });
  }, [allowDeleteDir, buildUrl, fetchRoot]);

  const currentSelectedDir = useMemo(() => {
    if (!selectedKeys.length || !rootEntry) return '';
    const rel = String(selectedKeys[0]);
    const entry = findEntryByRelpath(rootEntry, rel);
    if (!entry) return '';
    return entry.type === 'dir' ? entry.relpath : rel.split('/').slice(0, -1).join('/');
  }, [selectedKeys, rootEntry, findEntryByRelpath]);

  const submitMkdir = async () => {
    if (!newDirName) return;
    const target = currentSelectedDir || '';
    const url = `${baseUrl}/${encodeURIComponent(target + '/' + newDirName)}`;
    try {
      await api.post(url, null, { params: { mkdir: true } });
      message.success('폴더가 생성되었습니다.');
      setMkdirModalOpen(false);
      setNewDirName('');
      await fetchRoot();
    } catch (e: any) {
      message.error(`폴더 생성 실패: ${e?.message || e}`);
    }
  };

  const uploadProps = {
    name: 'file',
    multiple: true,
    customRequest: async (options: any) => {
      const { file, onSuccess, onError, onProgress } = options;
      try {
        const dir = currentSelectedDir || '.';
        const url = `${baseUrl}/${encodeURIComponent(dir)}`;
        const formData = new FormData();
        formData.append('file', file as File);
        await api.post(url, formData, {
          headers: { 'Content-Type': 'multipart/form-data' },
          onUploadProgress: ({ loaded, total }) => {
            if (total) onProgress?.({ percent: (loaded / total) * 100 }, file);
          }
        });
        onSuccess?.({}, file);
        await fetchRoot();
      } catch (err: any) {
        onError?.(err);
      }
    }
  };

  return (
    <div>
      <Space style={{ marginBottom: 8 }} wrap>
        <Title level={4} style={{ margin: 0 }}>📂 파일 탐색기</Title>
        <Button icon={<ReloadOutlined />} onClick={fetchRoot}>새로고침</Button>
        <Button icon={<FolderAddOutlined />} onClick={() => setMkdirModalOpen(true)}>폴더 생성</Button>
        <Button danger icon={<DeleteOutlined />} onClick={async () => {
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
            await Promise.all(
              targets.map(k => api.delete(buildUrl(String(k)), {
                params: { recursive: true },
              }))
            );
            message.success('일괄 삭제 완료');
            setCheckedKeys([]);
            await fetchRoot();
          } catch (e: any) {
            message.error(`삭제 중 오류: ${e?.message || e}`);
          }
        }}>선택 항목 삭제 ({checkedKeys.length}개)</Button>
      </Space>

      <Upload.Dragger {...uploadProps} style={{ marginBottom: 12 }}>
        <p className="ant-upload-drag-icon">
          <UploadOutlined />
        </p>
        <p className="ant-upload-text">파일을 드래그하거나 클릭해서 업로드</p>
        <p className="ant-upload-hint">선택된(또는 상위) 디렉토리로 업로드됩니다.</p>
      </Upload.Dragger>

      {loading && <div style={{ padding: '2rem 0', textAlign: 'center' }}><Spin /></div>}
      {!loading && treeData.length === 0 && <Text type="secondary">표시할 파일이 없습니다.</Text>}
      {!loading && treeData.length > 0 && (
        <Tree
          showIcon
          checkable
          multiple
          selectable
          expandedKeys={expandedKeys}
          onExpand={onExpand}
          selectedKeys={selectedKeys}
          onSelect={onSelect}
          checkedKeys={checkedKeys}
          onCheck={onCheck}
          treeData={treeData}
        />
      )}

      <Modal
        title="폴더 생성"
        open={mkdirModalOpen}
        onOk={submitMkdir}
        onCancel={() => setMkdirModalOpen(false)}
      >
        <Input
          placeholder="새 폴더 이름"
          value={newDirName}
          onChange={(e) => setNewDirName(e.target.value)}
        />
      </Modal>
    </div>
  );
};

export default FileTreeExplorer;

const NodeTitle: React.FC<{
  entry: FileEntry;
  onDelete: () => Promise<void> | void;
}> = ({ entry, onDelete }) => (
  <Space size={4}>
    <span>{entry.name}</span>
    <Button
      size="small"
      type="text"
      danger
      icon={<DeleteOutlined />}
      onClick={(e) => {
        e.stopPropagation();
        onDelete();
      }}
    />
  </Space>
);
