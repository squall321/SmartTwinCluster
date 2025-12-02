// FemMainRouter.tsx
import React, { useState } from "react";
import { Layout, Menu, Typography } from "antd";
import {
  BulbOutlined,
  BookOutlined,
  ReadOutlined,
} from "@ant-design/icons";
import Chapter1 from "./Chapter1";
import Chapter2 from "./Chapter2";
import Chapter3 from "./Chapter3";
import Chapter4 from "./Chapter4";
import Chapter5 from "./Chapter5";
import Chapter6 from "./Chapter6";
import Chapter7 from "./Chapter7";
import Chapter8 from "./Chapter8";
import Chapter9 from "./Chapter9";
import Chapter10 from "./Chapter10";
import Chapter11 from "./Chapter11";
import Chapter12 from "./Chapter12";
import Chapter13 from "./Chapter13";
import Chapter14 from "./Chapter14";
import Chapter15 from "./Chapter15";
import Chapter16 from "./Chapter16";
import Chapter17 from "./Chapter17";  
import Chapter18 from "./Chapter18";
import Chapter19 from "./Chapter19";
import Chapter20 from "./Chapter20";
import Chapter21 from "./Chapter21";
import Chapter22 from "./Chapter22";
import Chapter23 from "./Chapter23";
import Chapter24 from "./Chapter24";
const { Header, Sider, Content } = Layout;
const { Title } = Typography;

// ✅ 챕터 번호에 따른 제목 매핑
const chapterTitles: { [key: string]: string } = {
  "1": "Introduction to the Finite Element Method",
  "2": "One-Dimensional Linear Finite Elements",
  "3": "Two-Dimensional Finite Elements",
  "4": "Isoparametric Mapping",
  "5": "Numerical Integration in Finite Elements",
  "6": "Time-Dependent Problems",
  "7": "Eigenvalue Problems",
  "8": "Dynamic Analysis",
  "9": "Nonlinear Finite Element Analysis",
  "10": "Explicit Finite Element Analysis",
  "11": "Contact and Friction in Finite Element Analysis",
  "12": "Multiphysics Applications - Thermo-Mechanical, Fluid-Structure, and More",
  "13": "Stabilization Techniques and Mixed Methods",
  "14": "Reduced-Order Modeling and Model Reduction",
  "15": "Parallel Finite Element Methods",
  "16": "Multi-Scale and Homogenization Techniques",
  "17": "Error Estimation and Adaptive Mesh Refinement",
  "18": "Mesh Quality and Improvement",
  "19": "Geometric Nonlinearity and Large Deformation Mechanics",
  "20": "Plate and Shell Finite Elements",
  "21": "Curved Surfaces and Finite Element Methods",
  "22": "Plasticity and Damage Mechanics",
  "23": "Uncertainty Quantification in Finite Elements",
  "24": "Meshfree Methods and Extended Finite Element Methods",
};

const FemMainRouter: React.FC = () => {
  const [selectedKey, setSelectedKey] = useState("1");

  const renderContent = () => {
    switch (selectedKey) {
      case "1":
        return <Chapter1 />;
      case "2":
        return <Chapter2 />;
      case "3":
        return <Chapter3 />;
      case "4":
        return <Chapter4 />;
      case "5":
        return <Chapter5 />;
      case "6":
        return <Chapter6 />;
      case "7":
        return <Chapter7 />;
      case "8":
        return <Chapter8 />;
      case "9":
        return <Chapter9 />;
      case "10":
        return <Chapter10 />;
      case "11":
        return <Chapter11 />;
      case "12":
        return <Chapter12 />;
      case "13":
        return <Chapter13 />;
      case "14":
        return <Chapter14 />;
      case "15":
        return <Chapter15 />;
      case "16":
        return <Chapter16 />;
      case "17":
        return <Chapter17 />;
      case "18":
        return <Chapter18 />;
      case "19":
        return <Chapter19 />;
      case "20":
        return <Chapter20 />;
      case "21":
        return <Chapter21 />;
      case "22":
        return <Chapter22 />;
      case "23":
        return <Chapter23 />;
      case "24":
        return <Chapter24 />;
      default:
        return <Chapter1 />;
    }
  };

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
          <Menu.Item key="4" icon={<ReadOutlined />}>
            Chapter 4: {chapterTitles["4"]}
          </Menu.Item>
          <Menu.Item key="5" icon={<ReadOutlined />}>
            Chapter 5: {chapterTitles["5"]}
          </Menu.Item>
          <Menu.Item key="6" icon={<ReadOutlined />}>
            Chapter 6: {chapterTitles["6"]}
          </Menu.Item>
          <Menu.Item key="7" icon={<ReadOutlined />}>
            Chapter 7: {chapterTitles["7"]}
          </Menu.Item>
          <Menu.Item key="8" icon={<ReadOutlined />}>
            Chapter 8: {chapterTitles["8"]}
          </Menu.Item>
          <Menu.Item key="9" icon={<ReadOutlined />}>
            Chapter 9: {chapterTitles["9"]}
          </Menu.Item>
          <Menu.Item key="10" icon={<ReadOutlined />}>
            Chapter 10: {chapterTitles["10"]}
          </Menu.Item>
          <Menu.Item key="11" icon={<ReadOutlined />}>
            Chapter 11: {chapterTitles["11"]}
          </Menu.Item>
          <Menu.Item key="12" icon={<ReadOutlined />}>
            Chapter 12: {chapterTitles["12"]}
          </Menu.Item>
          <Menu.Item key="13" icon={<ReadOutlined />}>
            Chapter 13: {chapterTitles["13"]}
          </Menu.Item>
          <Menu.Item key="14" icon={<ReadOutlined />}>
            Chapter 14: {chapterTitles["14"]}
          </Menu.Item>
          <Menu.Item key="15" icon={<ReadOutlined />}>
            Chapter 15: {chapterTitles["15"]}
          </Menu.Item>
          <Menu.Item key="16" icon={<ReadOutlined />}>
            Chapter 16: {chapterTitles["16"]}
          </Menu.Item>
          <Menu.Item key="17" icon={<ReadOutlined />}>
            Chapter 17: {chapterTitles["17"]}
          </Menu.Item>
          <Menu.Item key="18" icon={<ReadOutlined />}>
            Chapter 18: {chapterTitles["18"]}
          </Menu.Item>
          <Menu.Item key="19" icon={<ReadOutlined />}>
            Chapter 19: {chapterTitles["19"]}
          </Menu.Item>
          <Menu.Item key="20" icon={<ReadOutlined />}>
            Chapter 20: {chapterTitles["20"]}
          </Menu.Item>
          <Menu.Item key="21" icon={<ReadOutlined />}>
            Chapter 21: {chapterTitles["21"]}
          </Menu.Item>
          <Menu.Item key="22" icon={<ReadOutlined />}>
            Chapter 22: {chapterTitles["22"]}
          </Menu.Item>
          <Menu.Item key="23" icon={<ReadOutlined />}>
            Chapter 23: {chapterTitles["23"]}
          </Menu.Item>
          <Menu.Item key="24" icon={<ReadOutlined />}>
            Chapter 24: {chapterTitles["24"]}
          </Menu.Item>
            </Menu>
      </Sider>
      <Layout>
        <Header style={{ background: "#fff", paddingLeft: 24 }}>
          <Title level={3}>
            Chapter {selectedKey}: {chapterTitles[selectedKey]}
          </Title>
        </Header>
        <Content style={{ margin: "24px", background: "#fff", padding: 24 }}>
          {renderContent()}
        </Content>
      </Layout>
    </Layout>
  );
};

export default FemMainRouter;
