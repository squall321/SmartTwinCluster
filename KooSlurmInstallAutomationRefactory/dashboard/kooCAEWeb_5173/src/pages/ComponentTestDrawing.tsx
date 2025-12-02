import React from 'react';
import BaseLayout from '../layouts/BaseLayout';
import { Typography, Divider } from 'antd';
import DrawingCanvaswithModel from '../components/DrawingCanvaswithModel';

const { Title, Paragraph } = Typography;

const ComponentTestDrawing: React.FC = () => {
  return (
    <BaseLayout isLoggedIn={true}>
      <div style={{ 
      padding: 24,
      width: '100%',
      backgroundColor: '#fff',
       minHeight: '100vh',
       borderRadius: '24px',
       }}>
        <Title level={3}>🖊️ Component Test: Drawing Canvas</Title>
        <Paragraph>
          Poly 버튼을 눌러 다각형을, Box 버튼을 눌러 사각형을 그릴 수 있습니다.<br />
          각 점은 드래그로 이동할 수 있으며, grid에 스냅됩니다.<br />
          Grid 간격도 자유롭게 조절해보세요!
        </Paragraph>

        <Divider />

        <DrawingCanvaswithModel />
      </div>
    </BaseLayout>
  );
};

export default ComponentTestDrawing;
