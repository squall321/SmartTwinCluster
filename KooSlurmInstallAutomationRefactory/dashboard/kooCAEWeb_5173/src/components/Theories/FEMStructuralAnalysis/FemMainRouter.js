import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
// FemMainRouter.tsx
import { useState } from "react";
import { Layout, Menu, Typography } from "antd";
import { BulbOutlined, BookOutlined, ReadOutlined, } from "@ant-design/icons";
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
const chapterTitles = {
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
const FemMainRouter = () => {
    const [selectedKey, setSelectedKey] = useState("1");
    const renderContent = () => {
        switch (selectedKey) {
            case "1":
                return _jsx(Chapter1, {});
            case "2":
                return _jsx(Chapter2, {});
            case "3":
                return _jsx(Chapter3, {});
            case "4":
                return _jsx(Chapter4, {});
            case "5":
                return _jsx(Chapter5, {});
            case "6":
                return _jsx(Chapter6, {});
            case "7":
                return _jsx(Chapter7, {});
            case "8":
                return _jsx(Chapter8, {});
            case "9":
                return _jsx(Chapter9, {});
            case "10":
                return _jsx(Chapter10, {});
            case "11":
                return _jsx(Chapter11, {});
            case "12":
                return _jsx(Chapter12, {});
            case "13":
                return _jsx(Chapter13, {});
            case "14":
                return _jsx(Chapter14, {});
            case "15":
                return _jsx(Chapter15, {});
            case "16":
                return _jsx(Chapter16, {});
            case "17":
                return _jsx(Chapter17, {});
            case "18":
                return _jsx(Chapter18, {});
            case "19":
                return _jsx(Chapter19, {});
            case "20":
                return _jsx(Chapter20, {});
            case "21":
                return _jsx(Chapter21, {});
            case "22":
                return _jsx(Chapter22, {});
            case "23":
                return _jsx(Chapter23, {});
            case "24":
                return _jsx(Chapter24, {});
            default:
                return _jsx(Chapter1, {});
        }
    };
    return (_jsxs(Layout, { style: { minHeight: "100vh" }, children: [_jsx(Sider, { width: 260, theme: "light", children: _jsxs(Menu, { mode: "inline", selectedKeys: [selectedKey], onClick: (e) => setSelectedKey(e.key), style: { height: "100%", borderRight: 0 }, children: [_jsxs(Menu.Item, { icon: _jsx(BulbOutlined, {}), children: ["Chapter 1: ", chapterTitles["1"]] }, "1"), _jsxs(Menu.Item, { icon: _jsx(BookOutlined, {}), children: ["Chapter 2: ", chapterTitles["2"]] }, "2"), _jsxs(Menu.Item, { icon: _jsx(ReadOutlined, {}), children: ["Chapter 3: ", chapterTitles["3"]] }, "3"), _jsxs(Menu.Item, { icon: _jsx(ReadOutlined, {}), children: ["Chapter 4: ", chapterTitles["4"]] }, "4"), _jsxs(Menu.Item, { icon: _jsx(ReadOutlined, {}), children: ["Chapter 5: ", chapterTitles["5"]] }, "5"), _jsxs(Menu.Item, { icon: _jsx(ReadOutlined, {}), children: ["Chapter 6: ", chapterTitles["6"]] }, "6"), _jsxs(Menu.Item, { icon: _jsx(ReadOutlined, {}), children: ["Chapter 7: ", chapterTitles["7"]] }, "7"), _jsxs(Menu.Item, { icon: _jsx(ReadOutlined, {}), children: ["Chapter 8: ", chapterTitles["8"]] }, "8"), _jsxs(Menu.Item, { icon: _jsx(ReadOutlined, {}), children: ["Chapter 9: ", chapterTitles["9"]] }, "9"), _jsxs(Menu.Item, { icon: _jsx(ReadOutlined, {}), children: ["Chapter 10: ", chapterTitles["10"]] }, "10"), _jsxs(Menu.Item, { icon: _jsx(ReadOutlined, {}), children: ["Chapter 11: ", chapterTitles["11"]] }, "11"), _jsxs(Menu.Item, { icon: _jsx(ReadOutlined, {}), children: ["Chapter 12: ", chapterTitles["12"]] }, "12"), _jsxs(Menu.Item, { icon: _jsx(ReadOutlined, {}), children: ["Chapter 13: ", chapterTitles["13"]] }, "13"), _jsxs(Menu.Item, { icon: _jsx(ReadOutlined, {}), children: ["Chapter 14: ", chapterTitles["14"]] }, "14"), _jsxs(Menu.Item, { icon: _jsx(ReadOutlined, {}), children: ["Chapter 15: ", chapterTitles["15"]] }, "15"), _jsxs(Menu.Item, { icon: _jsx(ReadOutlined, {}), children: ["Chapter 16: ", chapterTitles["16"]] }, "16"), _jsxs(Menu.Item, { icon: _jsx(ReadOutlined, {}), children: ["Chapter 17: ", chapterTitles["17"]] }, "17"), _jsxs(Menu.Item, { icon: _jsx(ReadOutlined, {}), children: ["Chapter 18: ", chapterTitles["18"]] }, "18"), _jsxs(Menu.Item, { icon: _jsx(ReadOutlined, {}), children: ["Chapter 19: ", chapterTitles["19"]] }, "19"), _jsxs(Menu.Item, { icon: _jsx(ReadOutlined, {}), children: ["Chapter 20: ", chapterTitles["20"]] }, "20"), _jsxs(Menu.Item, { icon: _jsx(ReadOutlined, {}), children: ["Chapter 21: ", chapterTitles["21"]] }, "21"), _jsxs(Menu.Item, { icon: _jsx(ReadOutlined, {}), children: ["Chapter 22: ", chapterTitles["22"]] }, "22"), _jsxs(Menu.Item, { icon: _jsx(ReadOutlined, {}), children: ["Chapter 23: ", chapterTitles["23"]] }, "23"), _jsxs(Menu.Item, { icon: _jsx(ReadOutlined, {}), children: ["Chapter 24: ", chapterTitles["24"]] }, "24")] }) }), _jsxs(Layout, { children: [_jsx(Header, { style: { background: "#fff", paddingLeft: 24 }, children: _jsxs(Title, { level: 3, children: ["Chapter ", selectedKey, ": ", chapterTitles[selectedKey]] }) }), _jsx(Content, { style: { margin: "24px", background: "#fff", padding: 24 }, children: renderContent() })] })] }));
};
export default FemMainRouter;
