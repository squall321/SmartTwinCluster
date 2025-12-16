import { Fragment as _Fragment, jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useState } from 'react';
import BaseLayout from '../layouts/BaseLayout';
import { Upload, Table, Typography, message, Spin, Button } from 'antd';
import { InboxOutlined } from '@ant-design/icons';
import { useNavigate } from 'react-router-dom';
import { api } from '../api/axiosClient';
const { Dragger } = Upload;
const { Title } = Typography;
const FullAngleDrop = () => {
    const [data, setData] = useState([]);
    const [columns, setColumns] = useState([]);
    const [loading, setLoading] = useState(false);
    const navigate = useNavigate();
    const columnNameMap = {
        filename: _jsx(_Fragment, { children: "\uD30C\uC77C\uBA85" }),
        "Short File Name": _jsx(_Fragment, { children: "\uD30C\uC77C\uBA85" }),
        Number: _jsx(_Fragment, { children: "\uBC88\uD638" }),
        EX: _jsxs(_Fragment, { children: ["Roll", _jsx("br", {}), "(Deg)"] }),
        EY: _jsxs(_Fragment, { children: ["Pitch", _jsx("br", {}), "(Deg)"] }),
        EZ: _jsxs(_Fragment, { children: ["Yaw", _jsx("br", {}), "(Deg)"] }),
        H: _jsxs(_Fragment, { children: ["\uB192\uC774", _jsx("br", {}), "(m)"] }),
        VX: _jsxs(_Fragment, { children: ["\uC18D\uB3C4 X", _jsx("br", {}), "(mm/s)"] }),
        VY: _jsxs(_Fragment, { children: ["\uC18D\uB3C4 Y", _jsx("br", {}), "(mm/s)"] }),
        VZ: _jsxs(_Fragment, { children: ["\uC18D\uB3C4 Z", _jsx("br", {}), "(mm/s)"] }),
        WX: _jsxs(_Fragment, { children: ["\uAC01\uC18D\uB3C4 X", _jsx("br", {}), "(rad/s)"] }),
        WY: _jsxs(_Fragment, { children: ["\uAC01\uC18D\uB3C4 Y", _jsx("br", {}), "(rad/s)"] }),
        WZ: _jsxs(_Fragment, { children: ["\uAC01\uC18D\uB3C4 Z", _jsx("br", {}), "(rad/s)"] }),
    };
    const handleUpload = async (info) => {
        const { fileList } = info;
        const formData = new FormData();
        fileList.forEach((file) => {
            if (file.originFileObj) {
                formData.append('files', file.originFileObj);
            }
        });
        const username = localStorage.getItem('username') || 'default_user';
        formData.append('user', username);
        try {
            setLoading(true);
            const res = await api.post('/api/upload_lsdyna_files', formData, {
                headers: { 'Content-Type': 'multipart/form-data' },
            });
            if (res.data.success) {
                const shortFilename = (full) => {
                    const idx = full.indexOf("DA_");
                    if (idx === -1)
                        return full;
                    return full.substring(0, idx - 1);
                };
                const flatData = res.data.data.map((item, i) => ({
                    "Short File Name": shortFilename(item.filename),
                    Number: item.parameters?.Number,
                    ...item.parameters,
                    __originalFile: fileList[i]?.originFileObj, // 🔑 파일 객체 저장
                }));
                const allKeys = new Set(flatData.flatMap((obj) => Object.keys(obj)));
                const dynamicColumns = Array.from(allKeys).map((key) => ({
                    title: columnNameMap[key] || key,
                    dataIndex: key,
                    key,
                }));
                setColumns(dynamicColumns);
                setData(flatData);
                message.success("업로드 성공!");
            }
        }
        catch (err) {
            console.error(err);
            message.error('업로드 실패');
        }
        finally {
            setLoading(false);
        }
    };
    const handleGoToAutoSubmit = () => {
        if (data.length === 0) {
            message.warning('제출할 파일이 없습니다.');
            return;
        }
        const jobConfigs = data.map((row) => {
            const file = row.__originalFile;
            return {
                file,
                filename: file.name,
                cores: 32,
                precision: 'Double',
                version: 'R15',
                mode: 'MPP',
            };
        });
        navigate('/auto-submit-lsdyna', {
            state: { jobConfigs },
        });
    };
    return (_jsx(BaseLayout, { isLoggedIn: true, children: _jsxs("div", { style: {
                padding: 24,
                backgroundColor: '#fff',
                minHeight: '100vh',
                borderRadius: '24px',
            }, children: [_jsx(Title, { level: 3, children: "\uD83D\uDCF1 \uC804\uAC01\uB3C4 \uB099\uD558 \uC2DC\uBBAC\uB808\uC774\uC158" }), _jsx("p", { children: "\uB2E4\uC591\uD55C \uAC01\uB3C4\uC758 \uB099\uD558 \uC870\uAC74\uC744 \uD3EC\uD568\uD55C LS-DYNA \uCF00\uC774\uC2A4 \uD30C\uC77C(.k)\uC744 \uC5C5\uB85C\uB4DC\uD558\uC138\uC694." }), _jsxs(Spin, { spinning: loading, tip: "\uD30C\uC77C \uC5C5\uB85C\uB4DC \uBC0F \uD30C\uC2F1 \uC911\uC785\uB2C8\uB2E4...", children: [_jsxs(Dragger, { multiple: true, customRequest: () => { }, beforeUpload: () => false, onChange: handleUpload, children: [_jsx("p", { className: "ant-upload-drag-icon", children: _jsx(InboxOutlined, {}) }), _jsx("p", { className: "ant-upload-text", children: ".k \uD30C\uC77C\uC744 \uC774\uACF3\uC5D0 \uB4DC\uB798\uADF8\uD558\uAC70\uB098 \uD074\uB9AD\uD558\uC5EC \uC5C5\uB85C\uB4DC\uD558\uC138\uC694" }), _jsx("p", { className: "ant-upload-hint", children: "\uD30C\uC77C\uBA85\uC740 \uBC18\uB4DC\uC2DC DA_ \uD0A4\uC6CC\uB4DC\uB97C \uD3EC\uD568\uD574\uC57C \uD569\uB2C8\uB2E4." })] }), _jsx(Table, { style: { marginTop: '2rem' }, dataSource: data, columns: columns, rowKey: "Short File Name", scroll: { x: 'max-content' } }), data.length > 0 && (_jsx("div", { style: { textAlign: 'right', marginTop: '1rem' }, children: _jsx(Button, { type: "primary", onClick: handleGoToAutoSubmit, children: "\uC790\uB3D9 \uC81C\uCD9C\uB85C \uC774\uB3D9" }) }))] })] }) }));
};
export default FullAngleDrop;
