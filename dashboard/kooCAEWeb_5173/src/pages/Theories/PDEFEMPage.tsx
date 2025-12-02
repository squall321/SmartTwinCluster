import React from "react";
import BaseLayout from "../../layouts/BaseLayout";
import PDEFEMMainRouter from "../../components/Theories/FiniteElementMethod/PDEFEMMainRouter";
import { Typography } from "antd";

const { Title, Paragraph } = Typography;

const PDEFEMPage: React.FC = () => {
    return (
        <BaseLayout isLoggedIn={true}>
            <div style={{ 
      padding: 24,
      backgroundColor: '#fff',
       minHeight: '100vh',
       borderRadius: '24px',
       }}>
                <Title level={3}>Partial Differential Equation</Title>
                <Paragraph>
                    편미분방정식의 유한요소법 이론 자료입니다.
                </Paragraph>
                <PDEFEMMainRouter />
            </div>
        </BaseLayout>
    );
};  

export default PDEFEMPage;