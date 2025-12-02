import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useState } from "react";
import { BulbOutlined, BookOutlined, ReadOutlined, } from "@ant-design/icons";
import PDEFEMChapter1 from "./PDEFEMChapter1";
import PDEFEMChapter2 from "./PDEFEMChapter2";
import PDEFEMChapter3 from "./PDEFEMChapter3";
import { Layout, Menu, Typography } from "antd";
const { Title } = Typography;
const { Header, Sider, Content } = Layout;
const chapterTitles = {
    "1": "Introduction to the Partial Differential Equation",
    "2": "Continuous Elements for One-Dimensional Problems",
    "3": "Weak Form, Function Spaces, and Galerkin Method"
};
const PDEFEMMainRouter = () => {
    const [selectedKey, setSelectedKey] = useState("1");
    const renderContent = () => {
        switch (selectedKey) {
            case "1":
                return _jsx(PDEFEMChapter1, {});
            case "2":
                return _jsx(PDEFEMChapter2, {});
            case "3":
                return _jsx(PDEFEMChapter3, {});
        }
    };
    return (_jsxs(Layout, { style: { minHeight: "100vh" }, children: [_jsx(Sider, { width: 260, theme: "light", children: _jsxs(Menu, { mode: "inline", selectedKeys: [selectedKey], onClick: (e) => setSelectedKey(e.key), style: { height: "100%", borderRight: 0 }, children: [_jsxs(Menu.Item, { icon: _jsx(BulbOutlined, {}), children: ["Chapter 1: ", chapterTitles["1"]] }, "1"), _jsxs(Menu.Item, { icon: _jsx(BookOutlined, {}), children: ["Chapter 2: ", chapterTitles["2"]] }, "2"), _jsxs(Menu.Item, { icon: _jsx(ReadOutlined, {}), children: ["Chapter 3: ", chapterTitles["3"]] }, "3")] }) }), _jsxs(Layout, { children: [_jsx(Header, { style: { background: "#fff", paddingLeft: 24 }, children: _jsxs(Title, { level: 3, children: ["Chapter ", selectedKey, ": ", chapterTitles[selectedKey]] }) }), _jsx(Content, { style: { padding: 24 }, children: renderContent() })] })] }));
};
export default PDEFEMMainRouter;
