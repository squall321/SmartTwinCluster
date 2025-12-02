import React from "react";
import BaseLayout from "../layouts/BaseLayout";
import ThreePointBendingApp from "../components/threepointbending/ThreePointBendingApp";
import { Typography } from "antd";

const { Title, Paragraph } = Typography;

const ThreePointBendingPage: React.FC = () => {
  return (
    <BaseLayout isLoggedIn={true}>
      <div style={{ 
      padding: 24,
      backgroundColor: '#fff',
       minHeight: '100vh',
       borderRadius: '24px',
       }}>
        <ThreePointBendingApp />
      </div>
    </BaseLayout>
  );
};

export default ThreePointBendingPage;   
