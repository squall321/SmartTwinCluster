// src/pages/PWMGeneratorPage.tsx

import React from "react";
import BaseLayout from "../layouts/BaseLayout";
import PWMGenerator from "../components/PWMGenerator";
import { Typography } from "antd";

const { Title, Paragraph } = Typography;

const PWMGeneratorPage: React.FC = () => {
  return (
    <BaseLayout isLoggedIn={true}>
    <div style={{ 
      padding: 24,
      backgroundColor: '#fff',
       minHeight: '100vh',
       borderRadius: '24px',
       }}>
    <Title level={3}>PWM Generator</Title>
        <Paragraph>
          PWM 신호를 생성하는 도구입니다.  
          원하는 채널 개수와 파라미터를 직접 설정하고  
          그래프로 시각화하며 CSV로 내보낼 수 있습니다.
        </Paragraph>
        
        <PWMGenerator />
      </div>
    </BaseLayout>
  );
};

export default PWMGeneratorPage;
