import React from 'react';
import BaseLayout from '../layouts/BaseLayout';
import RambergOsgoodPanel from '../components/RambergOsgoodPanel';
import { Typography } from 'antd';

const { Title, Paragraph } = Typography;

const RambergOsgoodPage: React.FC = () => {
  return (
    <BaseLayout isLoggedIn={false}>
      <div style={{ 
      padding: 24,
      backgroundColor: '#fff',
       minHeight: '100vh',
       borderRadius: '24px',
       }}>
        <Title level={3}>Ramberg-Osgood 비선형 재료 모델</Title>
        <Paragraph>
          본 페이지에서는 금속 재료의 탄소-소성 거동을 표현하는 Ramberg-Osgood 모델을 실시간으로
          시뮬레이션할 수 있습니다. 영률, 항복강도, 비선형 파라미터 등을 조정하여 Stress-Strain 곡선과
          피로 수명 곡선을 확인할 수 있으며, Fracture Strain 선택 시 피로 파라미터가 자동 계산됩니다.
        </Paragraph>
        <RambergOsgoodPanel />
      </div>
    </BaseLayout>
  );
};

export default RambergOsgoodPage;
