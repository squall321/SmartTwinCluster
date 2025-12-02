import React from 'react';
import BaseLayout from '../layouts/BaseLayout';
import { Typography } from 'antd';
import StreamRunner from '../components/StreamRunner';


const { Title, Paragraph } = Typography;

const MeshModifier = () => {
  let solver = "MeshModifier";
  return (
    <BaseLayout isLoggedIn={true}>
      <div style={{ 
      padding: 24,
      backgroundColor: '#fff',
       minHeight: '100vh',
       borderRadius: '24px',
       }}>
        {solver == "MeshModifier" && <Title level={3}>📦 Mesh Modifier</Title>}
        {solver == "AutomatedModeller" && <Title level={3}>📦 Automated Modeller</Title>}        
        <Paragraph>
          시뮬레이션 모델에 대한 격자 수정을 위한 자동화 코드를 수행합니다. 
        </Paragraph>

        <StreamRunner solver={null} mode={null} />
      </div>
    </BaseLayout>
  );
};

export default MeshModifier;
