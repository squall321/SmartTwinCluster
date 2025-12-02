import React from 'react';
import BaseLayout from '../layouts/BaseLayout';
import ViscoElasticVisualizer from '../components/ViscoElasticVisualizer';
import { Typography } from 'antd';

const { Title, Paragraph } = Typography;

const ViscoelasticVisualizerPage: React.FC = () => {
  return (
    <BaseLayout isLoggedIn={false}>
      <div style={{ 
      padding: 24,
      backgroundColor: '#fff',
       minHeight: '100vh',
       borderRadius: '24px',
       }}>
        <Title level={3}>Viscoelastic Visualizer</Title>
        <Paragraph>
          본 페이지에서는 비선형 재료의 비선형 거동을 시뮬레이션할 수 있습니다.
        </Paragraph>
        <ViscoElasticVisualizer />
      </div>
    </BaseLayout>
  );
};

export default ViscoelasticVisualizerPage;