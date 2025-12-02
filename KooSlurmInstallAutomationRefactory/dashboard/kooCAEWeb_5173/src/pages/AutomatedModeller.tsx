import React, { useState } from 'react';
import BaseLayout from '../layouts/BaseLayout';
import { Typography, Select, Space } from 'antd';
import StreamRunner from '../components/StreamRunner';

const { Title, Paragraph } = Typography;
const { Option } = Select;

const AutomatedModeller = () => {
    let solver = "AutomatedModeller";
    const [mode, setMode] = useState<string | null>(null);

    const handleModeChange = (value: string) => {
        setMode(value);
    };

    return (
        <BaseLayout isLoggedIn={true}>
            <div style={{ 
                padding: 24,
                backgroundColor: '#fff',
                minHeight: '100vh',
                borderRadius: '24px',
            }}>
                {solver === "AutomatedModeller" && <Title level={3}>📦 Automated Modeller</Title>}
                <Paragraph>시뮬레이션 모델을 자동으로 생성합니다.</Paragraph>

                <Space direction="vertical" style={{ marginBottom: 16 }}>
                    <Select
                        placeholder="모드를 선택하세요"
                        style={{ width: 200 }}
                        onChange={handleModeChange}
                        value={mode}
                    >
                        <Option value="PKG">PKG</Option>
                        <Option value="PBA">PBA</Option>
                        <Option value="ArrayPCB">ArrayPCB</Option>
                        <Option value="CAP">CAP</Option>
                    </Select>
                </Space>

                <StreamRunner solver={solver} mode={mode} />
            </div>
        </BaseLayout>
    );
};

export default AutomatedModeller;
