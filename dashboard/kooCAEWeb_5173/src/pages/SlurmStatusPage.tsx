import React from 'react';
import BaseLayout from '../layouts/BaseLayout';
import { Typography, Divider } from 'antd';
import ResourceSummary from '../components/ResourceSummaryComponent';
import RackViewerComponent from '../components/RackViewerComponent';

const { Title, Paragraph } = Typography;

const SlurmStatusPage: React.FC = () => {
  return (
    <BaseLayout isLoggedIn={true}>
      <div style={{ 
      padding: 24,
      backgroundColor: '#fff',
       minHeight: '100vh',
       borderRadius: '24px',
       }}>
        <Title level={3}>🖥️ Slurm 스케줄러 상태 대시보드</Title>
        <Paragraph>
          현재 HPC 클러스터의 노드 자원 사용 상태 및 LSDYNA 작업 코어 사용량을 실시간으로 확인할 수 있습니다.
        </Paragraph>

        <Divider orientation="left">📊 자원 요약</Divider>
        <ResourceSummary />

        <Divider orientation="left">🗄️ 랙별 노드 사용 현황</Divider>
        <RackViewerComponent />
      </div>
    </BaseLayout>
  );
};

export default SlurmStatusPage;
