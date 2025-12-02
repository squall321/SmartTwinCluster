import React , { useState } from "react";
import {
    BulbOutlined,
    BookOutlined,
    ReadOutlined,
} from "@ant-design/icons";
import PDEFEMChapter1 from "./PDEFEMChapter1";
import PDEFEMChapter2 from "./PDEFEMChapter2";
import PDEFEMChapter3 from "./PDEFEMChapter3";
import { Layout, Menu, Typography } from "antd";
const { Title } = Typography;
const { Header, Sider, Content } = Layout;

const chapterTitles: { [key: string]: string } = {
    "1": "Introduction to the Partial Differential Equation",
    "2": "Continuous Elements for One-Dimensional Problems",
    "3": "Weak Form, Function Spaces, and Galerkin Method"
}
const PDEFEMMainRouter: React.FC = () => {
    const [selectedKey, setSelectedKey] = useState("1");
    const renderContent = () => {
        switch (selectedKey) {
        case "1":
            return <PDEFEMChapter1/>;
        case "2":
            return <PDEFEMChapter2/>;
        case "3":
            return <PDEFEMChapter3/>;
        }
    }
    return (
        <Layout style={{ minHeight: "100vh" }}>
            <Sider width={260} theme="light">
                <Menu
                    mode="inline"
                    selectedKeys={[selectedKey]}
                    onClick={(e) => setSelectedKey(e.key)}
                    style={{ height: "100%", borderRight: 0 }}
                >
                    <Menu.Item key="1" icon={<BulbOutlined />}>
                        Chapter 1: {chapterTitles["1"]}
                    </Menu.Item>
                    <Menu.Item key="2" icon={<BookOutlined />}>
                        Chapter 2: {chapterTitles["2"]}
                    </Menu.Item>
                    <Menu.Item key="3" icon={<ReadOutlined />}>
                        Chapter 3: {chapterTitles["3"]}
                    </Menu.Item>
                </Menu>
            </Sider>
            <Layout>
                <Header style={{ background: "#fff", paddingLeft: 24 }}>
                    <Title level={3}>
                        Chapter {selectedKey}: {chapterTitles[selectedKey]}
                    </Title>
                </Header>
                <Content style={{ padding: 24 }}>
                    {renderContent()}
                </Content>
            </Layout>
        </Layout>
    );
};

export default PDEFEMMainRouter;