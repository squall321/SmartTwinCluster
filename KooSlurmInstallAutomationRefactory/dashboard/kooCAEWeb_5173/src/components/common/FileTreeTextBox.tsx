// FileTreeTextBox.tsx
import React, { useEffect, useState } from 'react';
import { List, Spin, Typography, Checkbox, Button, message } from 'antd';
import { DownloadOutlined } from '@ant-design/icons';
import { api } from '../../api/axiosClient';

const { Title } = Typography;

type FileEntry = {
  name: string;
  relpath: string;
  type: 'file' | 'dir';
  size?: number;
  mtime?: number;
  children?: FileEntry[];
};

interface Props {
  username: string;
  date?: string;
  mode?: string;
  prefix?: string;
}

const FileTreeTextBox: React.FC<Props> = ({ username, date, mode, prefix }) => {
  const [fileList, setFileList] = useState<FileEntry[]>([]);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [loading, setLoading] = useState(false);

  const baseUrl = `/api/files/${username}`;

  // segment 단위 인코딩
  const buildUrl = (relpath: string) => {
    const safe = relpath.split('/').map(encodeURIComponent).join('/');
    return `${baseUrl}/${safe}`;
  };

  // 특정 디렉토리까지 이동
  const navigatePath = (root: FileEntry, pathParts: string[]): FileEntry | null => {
    let current = root;
    for (const part of pathParts) {
      const next = current.children?.find(c => c.type === 'dir' && c.name === part);
      if (!next) return null;
      current = next;
    }
    return current;
  };

  const collectFiles = (entry: FileEntry): FileEntry[] => {
    if (entry.type === 'file') {
      if (prefix && !entry.name.startsWith(prefix)) return [];
      return [entry];
    }
    if (entry.type === 'dir' && entry.children) {
      return entry.children.flatMap(collectFiles);
    }
    return [];
  };

  /** ✅ 단일 파일 다운로드: blob 방식 */
  const handleDownload = async (relpath: string, filename?: string) => {
    const url = buildUrl(relpath);
    try {
      const res = await api.get(url, { responseType: 'blob' });
      const blob = new Blob([res.data]);
      const a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = filename || relpath.split('/').pop() || 'download';
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(a.href);
    } catch (e: any) {
      console.error(e);
      message.error(`다운로드 실패: ${e.message}`);
    }
  };

  /** ✅ 선택 파일 일괄 다운로드 (개별로 순차 다운로드) */
  const handleBulkDownload = async () => {
    if (selected.size === 0) {
      message.warning('선택된 파일이 없습니다.');
      return;
    }

    message.loading({ content: '개별 파일 다운로드 중...', key: 'bulk', duration: 0 });

    for (const relpath of selected) {
      const filename = relpath.split('/').pop() || 'download';
      await handleDownload(relpath, filename);
    }

    message.success({ content: '다운로드 완료', key: 'bulk' });
  };

  const toggleSelect = (relpath: string) => {
    setSelected(prev => {
      const copy = new Set(prev);
      copy.has(relpath) ? copy.delete(relpath) : copy.add(relpath);
      return copy;
    });
  };

  useEffect(() => {
    setLoading(true);
    api.get(baseUrl)
      .then(res => res.data)
      .then((root: FileEntry) => {
        const pathParts = [date, mode].filter(Boolean) as string[];
        const target = pathParts.length ? navigatePath(root, pathParts) : root;

        if (!target) {
          message.error(`경로를 찾을 수 없습니다: ${pathParts.join('/')}`);
          return;
        }

        const filtered = collectFiles(target);
        setFileList(filtered);
      })
      .catch(err => {
        console.error(err);
        message.error(`불러오기 실패: ${err.message}`);
      })
      .finally(() => setLoading(false));
  }, [username, date, mode, prefix]);

  return (
    <div>
      <Title level={4}>📂 파일 리스트</Title>
      {loading ? <Spin /> : (
        <>
          <List
            bordered
            dataSource={fileList}
            renderItem={item => (
              <List.Item
                actions={[
                  <Button
                    icon={<DownloadOutlined />}
                    onClick={() => handleDownload(item.relpath, item.name)}
                  >
                    다운로드
                  </Button>
                ]}
              >
                <Checkbox
                  checked={selected.has(item.relpath)}
                  onChange={() => toggleSelect(item.relpath)}
                  style={{ marginRight: '1rem' }}
                />
                {item.name}
              </List.Item>
            )}
          />
          {fileList.length > 0 && (
            <Button
              type="primary"
              icon={<DownloadOutlined />}
              style={{ marginTop: '1rem' }}
              onClick={handleBulkDownload}
            >
              선택된 파일 일괄 다운로드
            </Button>
          )}
        </>
      )}
    </div>
  );
};

export default FileTreeTextBox;
