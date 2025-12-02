import React, { useEffect, useState } from 'react';
import { Card, Row, Col, Tooltip, Progress, Typography, Divider } from 'antd';
import { api } from '../api/axiosClient';
import BarChartComponent from '../components/BarChartComponent'; // 경로는 실제 위치에 따라 조정 필요

const { Title } = Typography;

interface NodeStatus {
  name: string;
  rack: string;
  total: number;
  load: number;
}

interface UserUsage {
  user: string;
  cores: number;
}


const getUsageInfo = (load: number, total: number) => {
  const usage = load / total;
  if (usage < 0.3) return { color: '#52c41a', label: '낮음' };
  if (usage < 0.7) return { color: '#faad14', label: '중간' };
  return { color: '#f5222d', label: '높음' };
};

const RackViewerComponent: React.FC = () => {
  const [rackData, setRackData] = useState<Record<string, NodeStatus[]>>({});
  const [userUsage, setUserUsage] = useState<UserUsage[]>([]);

  const fetchRackData = async () => {
    try {
      const res = await api.get(`/api/rack-status`);
      setRackData({ ...res.data });
    } catch (error) {
      console.error('⚠️ 랙 데이터 요청 실패:', error);
    }
  };

  const fetchUserUsage = async () => {
    try {
      const res = await api.get(`/api/slurm/user-core-usage`);
      const sorted = res.data.sort((a: UserUsage, b: UserUsage) => b.cores - a.cores);
      setUserUsage(sorted);
    } catch (error) {
      console.error('⚠️ 유저 사용량 요청 실패:', error);
    }
  };

  useEffect(() => {
    fetchRackData();
    fetchUserUsage();
    const interval = setInterval(() => {
      fetchRackData();
      fetchUserUsage();
    }, 1000);
    return () => clearInterval(interval);
  }, []);

  return (
    <div style={{ padding: '40px 24px 24px', background: '#f0f2f5' }}>
      <div style={{ display: 'flex', justifyContent: 'left', marginBottom: 24 }}>
        <Typography.Title level={3} style={{ margin: 0 }}>
          📡 클러스터 랙 상태 모니터링
        </Typography.Title>
      </div>

      <Row gutter={[24, 24]} wrap justify="start">
        {Object.entries(rackData).map(([rack, nodes]) => (
          <Col key={rack}>
            <Card
              title={<span style={{ fontWeight: 600 }}>🗄️ {rack}</span>}
              bordered={false}
              style={{
                width: 280,
                background: '#e6f7ff',
                border: '2px solid #1890ff',
                borderRadius: 12,
                boxShadow: '0 4px 12px rgba(0,0,0,0.08)',
              }}
              bodyStyle={{ padding: '12px 16px' }}
            >
              {nodes.map((node) => {
                const { color, label } = getUsageInfo(node.load, node.total);
                const usagePercent = Math.round((node.load / node.total) * 100);

                return (
                  <Tooltip
                    key={node.name}
                    title={
                      <>
                        <div>
                          <strong>{node.name}</strong>
                        </div>
                        <div>총 코어: {node.total}</div>
                        <div>사용 중: {node.load.toFixed(1)}</div>
                        <div>
                          사용률: {usagePercent}% ({label})
                        </div>
                      </>
                    }
                  >
                    <div
                      style={{
                        background: '#ffffff',
                        border: `1px solid ${color}`,
                        margin: '8px 0',
                        padding: '6px 10px',
                        borderRadius: 6,
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'space-between',
                        height: 38,
                        boxShadow: `0 1px 3px ${color}44`,
                        transition: 'all 0.3s',
                      }}
                    >
                      <div
                        style={{
                          fontSize: 13,
                          fontWeight: 500,
                          whiteSpace: 'nowrap',
                          overflow: 'hidden',
                          textOverflow: 'ellipsis',
                          marginRight: 10,
                          flex: 1,
                        }}
                      >
                        {node.name}
                      </div>
                      <Progress
                        percent={usagePercent}
                        size="small"
                        status="active"
                        strokeColor={color}
                        showInfo={false}
                        style={{ width: 120 }}
                      />
                    </div>
                  </Tooltip>
                );
              })}
              <Divider style={{ margin: '12px 0' }} />
              <div style={{ textAlign: 'right', fontSize: 12, color: '#888' }}>
                총 노드: {nodes.length}
              </div>
            </Card>
          </Col>
        ))}
      </Row>

      {userUsage.length > 0 && (
        <div style={{ marginTop: 48 }}>
          <Typography.Title level={4}>🧑‍💻 유저별 코어 사용량</Typography.Title>
          <div style={{ width: '100%', height: 800 }}>
            <BarChartComponent
              data={userUsage.map((u) => ({ name: u.user, number: u.cores }))}
              title="유저별 사용량"
              unitLabel="코어"
            />
          </div>
        </div>
      )}
    </div>
  );
};

export default RackViewerComponent;
