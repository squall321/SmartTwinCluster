import React from "react";
import BaseLayout from "../../layouts/BaseLayout";
import LayeredModelEditor from "../../ModuleGenerator/LayeredModelEditor";
    import { Typography } from "antd";

const { Title, Paragraph } = Typography;

const PackageGeneratorPage: React.FC = () => {
    return (
        <BaseLayout isLoggedIn={true}>
            <div style={{ 
      padding: 24,
      backgroundColor: '#fff',
       minHeight: '100vh',
       borderRadius: '24px',
       }}>
                <Title level={3}>Package Generator</Title>
                <Paragraph>
                    Package Generator
                </Paragraph>
                <LayeredModelEditor />
            </div>
        </BaseLayout>
    );
};

export default PackageGeneratorPage;