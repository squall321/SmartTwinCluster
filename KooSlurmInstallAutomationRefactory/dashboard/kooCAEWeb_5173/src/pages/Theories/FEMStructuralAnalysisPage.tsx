import React from "react";
import BaseLayout from "../../layouts/BaseLayout";
import FemMainRouter from "../../components/Theories/FEMStructuralAnalysis/FemMainRouter";
import { Typography } from "antd";

const { Title, Paragraph } = Typography;

const FEMStructuralAnalysisPage: React.FC = () => {
    return (
        <BaseLayout isLoggedIn={true}>
            <div style={{ 
      padding: 24,
      backgroundColor: '#fff',
       minHeight: '100vh',
       borderRadius: '24px',
       }}>
                <Title level={3}>Computational Statics and Dynamics</Title>
                <Paragraph>
                    유한요소법을 이용한 구조해석 이론 자료입니다.
                </Paragraph>
                <FemMainRouter />
            </div>
        </BaseLayout>
    );
};

export default FEMStructuralAnalysisPage;