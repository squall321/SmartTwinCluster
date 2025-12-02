import React from 'react';
import BaseLayout from '../layouts/BaseLayout';
import ContactStiffnessDemoComponent from '../components/ContactStiffnessDemoComponent';
import { Typography } from 'antd';

const { Title, Paragraph } = Typography;

const ContactStiffnessDemoPage: React.FC = () => {
  return (
    <BaseLayout isLoggedIn={false}>
      <div style={{ 
      padding: 24,
      backgroundColor: '#fff',
       minHeight: '100vh',
       borderRadius: '24px',
       }}>
        <Title level={3}>Contact Stiffness Demo</Title>
        <Paragraph>
          이 페이지에서는 충돌 강성을 시뮬레이션할 수 있습니다.
          현재 사용하는 요소 크기와 시간 간격을 조정하여 충돌 강성을 시뮬레이션할 수 있습니다.
        </Paragraph>
        <ContactStiffnessDemoComponent />
      </div>
    </BaseLayout>
  );
};

export default ContactStiffnessDemoPage;

