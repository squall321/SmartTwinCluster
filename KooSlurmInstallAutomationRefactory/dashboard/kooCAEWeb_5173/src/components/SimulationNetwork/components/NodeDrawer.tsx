// components/simulationnetwork/NodeDrawer.tsx
import React, { useEffect, useState } from 'react';
import { Drawer, Tabs, Space, Tag, Spin } from 'antd';
import { useSimulationNetworkStore } from '../store/simulationnetworkStore';
import StatusTags from './StatusTags';
import { api } from '../../../api/axiosClient'; // ← alias 없으면 상대경로로 변경

const NodeDrawer: React.FC = () => {
  const selectedNode = useSimulationNetworkStore(s => s.selectedNode);
  const nodeDetails = useSimulationNetworkStore(s => s.nodeDetails);
  const nodeLogs = useSimulationNetworkStore(s => s.nodeLogs);
  const nodeArtifacts = useSimulationNetworkStore(s => s.nodeArtifacts);
  const setSelectedNode = useSimulationNetworkStore(s => s.setSelectedNode);
  const setNodeDetails = useSimulationNetworkStore(s => s.setNodeDetails);
  const setNodeLogs = useSimulationNetworkStore(s => s.setNodeLogs);
  const setNodeArtifacts = useSimulationNetworkStore(s => s.setNodeArtifacts);

  const [activeKey, setActiveKey] = useState('details');

  useEffect(() => {
    setActiveKey('details');
  }, [selectedNode]);

  // Details: 선택 시 즉시 로드 (axios)
  useEffect(() => {
    if (!selectedNode) return;
    const fetchDetails = async () => {
      try {
        const detailPath = `case/${selectedNode.id}/${
          selectedNode.kind === 'DropSet' ? 'DropSet.json' : 'DropImpactor.json'
        }`;
        // 프록시 base는 axiosClient에서 주입되므로 상대 경로만!
        const { data } = await api.post(`/${detailPath}`);
        setNodeDetails(data ?? {});
      } catch (e) {
        console.error(e);
        setNodeDetails({});
      }
    };
    fetchDetails();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedNode]);

  const onTabsChange = async (key: string) => {
    setActiveKey(key);
    if (!selectedNode) return;

    try {
      if (key === 'logs' && nodeLogs === null) {
        // text 응답
        const { data } = await api.post<string>(`/case/${selectedNode.id}/logs`, undefined, {
          responseType: 'text',
        });
        setNodeLogs(typeof data === 'string' ? data : '');
      } else if (key === 'artifacts' && nodeArtifacts === null) {
        const { data } = await api.post<string[]>(`/case/${selectedNode.id}/artifacts`);
        setNodeArtifacts(Array.isArray(data) ? data : []);
      }
    } catch (e) {
      console.error(e);
      if (key === 'logs') setNodeLogs('');
      if (key === 'artifacts') setNodeArtifacts([]);
    }
  };

  const items = [
    {
      key: 'details',
      label: 'Details',
      children: nodeDetails ? (
        <pre style={{ maxHeight: '60vh', overflow: 'auto' }}>
          {JSON.stringify(nodeDetails, null, 2)}
        </pre>
      ) : (
        <Spin tip="Loading details..." />
      ),
    },
    {
      key: 'logs',
      label: 'Logs',
      children:
        nodeLogs !== null ? (
          <pre style={{ maxHeight: '60vh', overflow: 'auto' }}>{nodeLogs || 'No logs available.'}</pre>
        ) : (
          <Spin tip="Loading logs..." />
        ),
    },
    {
      key: 'artifacts',
      label: 'Artifacts',
      children:
        nodeArtifacts !== null ? (
          nodeArtifacts.length ? (
            <ul style={{ maxHeight: '60vh', overflow: 'auto' }}>
              {nodeArtifacts.map((f: string) => (
                <li key={f}>{f}</li>
              ))}
            </ul>
          ) : (
            <p>No artifacts available.</p>
          )
        ) : (
          <Spin tip="Loading artifacts..." />
        ),
    },
  ];

  return (
    <Drawer
      title={selectedNode ? `Case ${selectedNode.id}` : ''}
      open={!!selectedNode}
      onClose={() => setSelectedNode(null)}
      width={520}
      destroyOnClose
    >
      {selectedNode && (
        <>
          <Space style={{ marginBottom: 16 }}>
            <StatusTags statuses={[selectedNode.status]} />
            <Tag>{selectedNode.kind}</Tag>
          </Space>
          <Tabs items={items} activeKey={activeKey} onChange={onTabsChange} />
        </>
      )}
    </Drawer>
  );
};

export default NodeDrawer;
