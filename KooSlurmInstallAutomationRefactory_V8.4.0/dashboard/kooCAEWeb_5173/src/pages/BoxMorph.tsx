import React from 'react';
import BaseLayout from '../layouts/BaseLayout';
import { Typography } from 'antd';
import MorphComponent from '../components/MorphComponent';

const { Title, Paragraph } = Typography;

const BoxMorphPage = () => {
  return (
    <BaseLayout isLoggedIn={true}>
      <div style={{ 
      padding: 24,
      backgroundColor: '#fff',
       minHeight: '100vh',
       borderRadius: '24px',
       }}>
        <Title level={3}>📦 박스 모핑 시뮬레이션</Title>
        <Paragraph>
          아래 2D 공간에서 박스를 그려 Morphing 범위를 지정하고, 
          설정값을 통해 LS-DYNA 스크립트를 생성할 수 있습니다.
        </Paragraph>

        <MorphComponent />
      </div>
    </BaseLayout>
  );
};

export default BoxMorphPage;
