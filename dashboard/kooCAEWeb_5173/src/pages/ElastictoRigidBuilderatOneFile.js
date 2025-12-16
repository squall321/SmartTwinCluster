import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useState } from 'react';
import BaseLayout from '../layouts/BaseLayout';
import { Upload, Typography, AutoComplete, Button, message, Divider, Table } from 'antd';
import { InboxOutlined, DownloadOutlined } from '@ant-design/icons';
import { api } from '../api/axiosClient';
const { Dragger } = Upload;
const { Title, Paragraph } = Typography;
const ElasticToRigidBuilder = () => {
    const [kFileName, setKFileName] = useState('Impact_1_00000001.k');
    const [allPartInfos, setAllPartInfos] = useState([]);
    const [excludePartIds, setExcludePartIds] = useState([]);
    const username = localStorage.getItem('username') || 'default_user';
    const uploadAndParseKFile = async (file) => {
        const formData = new FormData();
        formData.append("file", file);
        formData.append("user", username);
        try {
            const response = await api.post("/api/upload_dyna_file_and_find_pid", formData, {
                headers: {
                    "Content-Type": "multipart/form-data"
                },
                // 필요 시 credentials 포함:
                // withCredentials: true
            });
            const data = response.data;
            console.log(data);
            const filename = data.filename;
            const parts = data.parts;
            // 상태 업데이트 예시
            setKFileName(filename);
            setAllPartInfos(parts);
            setExcludePartIds([]);
            message.success(`${filename} 파일에서 ${parts.length}개 파트 파싱 완료`);
        }
        catch (err) {
            console.error("❌ Axios 업로드 실패:", err);
            if (err.response?.data?.error) {
                message.error(`업로드 실패: ${err.response.data.error}`);
            }
            else {
                message.error("서버와의 연결에 실패했습니다.");
            }
        }
    };
    const handleFileUpload = (info) => {
        const file = info.fileList[0]?.originFileObj;
        if (!file) {
            message.error('파일을 불러올 수 없습니다.');
            return;
        }
        setKFileName(file.name);
        uploadAndParseKFile(file);
    };
    const handlePartSelect = (value) => {
        const found = allPartInfos.find(part => part.id === value || part.name === value);
        if (found && !excludePartIds.find(p => p.id === found.id)) {
            setExcludePartIds(prev => [...prev, found]);
        }
    };
    const exportRigidScript = () => {
        const modeId = 1;
        const excludedIds = excludePartIds.map(p => p.id);
        const allIds = allPartInfos.map(p => p.id);
        const includedIds = allIds.filter(id => !excludedIds.includes(id));
        const lines = [];
        lines.push(`*Inputfile`);
        lines.push(`${kFileName}`);
        lines.push(`*Mode`);
        lines.push(`ELASTIC_TO_RIGID,${modeId}`);
        lines.push(`**ElastictoRigid,${modeId}`);
        lines.push(`*PIDExcept,${excludedIds.join(',')}`);
        lines.push(`**EndElastictoRigid`);
        lines.push(`*End`);
        const blob = new Blob([lines.join('\n')], { type: 'text/plain;charset=utf-8' });
        const link = document.createElement('a');
        link.href = URL.createObjectURL(blob);
        link.download = 'elasticToRigidOption.txt';
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
    };
    return (_jsx(BaseLayout, { isLoggedIn: true, children: _jsxs("div", { style: {
                padding: 24,
                backgroundColor: '#fff',
                minHeight: '100vh',
                borderRadius: '24px',
            }, children: [_jsx(Typography.Title, { level: 3, children: "Elastic to Rigid \uBCC0\uD658 \uC0DD\uC131\uAE30" }), _jsx(Paragraph, { children: "\uC774 \uCEF4\uD3EC\uB10C\uD2B8\uB294 LS-DYNA\uC758 \uD0C4\uC131 \uD30C\uD2B8\uB97C \uAC15\uCCB4\uB85C \uBCC0\uD658\uD558\uB294 \uC635\uC158 \uD30C\uC77C\uC744 \uC27D\uAC8C \uC0DD\uC131\uD560 \uC218 \uC788\uB3C4\uB85D \uB3C4\uC640\uC90D\uB2C8\uB2E4. \uC0AC\uC6A9\uC790\uB294 .k \uD30C\uC77C\uC744 \uC5C5\uB85C\uB4DC\uD558\uACE0, \uAC15\uCCB4\uB85C \uBCC0\uD658\uD558\uC9C0 \uC54A\uC744 \uD30C\uD2B8\uB97C \uC120\uD0DD\uD55C \uB4A4, \uBC84\uD2BC\uC744 \uB20C\uB7EC \uC635\uC158 \uD30C\uC77C\uC744 \uB2E4\uC6B4\uB85C\uB4DC\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4. \uAC04\uD3B8\uD55C UI\uB85C \uBCC0\uD658 \uC124\uC815\uC744 \uBE60\uB974\uAC8C \uAD6C\uC131\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4." }), _jsxs(Dragger, { name: "file", multiple: false, beforeUpload: () => false, onChange: handleFileUpload, style: { marginBottom: 16 }, children: [_jsx("p", { className: "ant-upload-drag-icon", children: _jsx(InboxOutlined, {}) }), _jsx("p", { className: "ant-upload-text", children: "K \uD30C\uC77C\uC744 \uC5EC\uAE30\uC5D0 \uB4DC\uB798\uADF8\uD558\uAC70\uB098 \uD074\uB9AD\uD558\uC5EC \uC120\uD0DD" })] }), _jsx(Typography.Text, { type: "secondary", children: kFileName }), _jsx(Divider, {}), _jsx(Typography.Title, { level: 4, children: "\uC81C\uC678\uD560 PART ID \uB610\uB294 \uC774\uB984 \uC120\uD0DD" }), _jsx(AutoComplete, { style: { width: '100%' }, placeholder: "\uC608: 1001 \uB610\uB294 PI_LAYER", options: allPartInfos.map(part => ({
                        value: part.id,
                        label: `${part.id} - ${part.name}`
                    })), filterOption: (inputValue, option) => option?.label.toLowerCase().includes(inputValue.toLowerCase()) ?? false, onSelect: handlePartSelect }), _jsx(Table, { dataSource: excludePartIds.map((p, i) => ({ ...p, key: i })), columns: [
                        { title: 'ID', dataIndex: 'id', key: 'id' },
                        { title: '이름', dataIndex: 'name', key: 'name' },
                        {
                            title: '작업',
                            render: (_, record) => (_jsx(Button, { danger: true, onClick: () => {
                                    setExcludePartIds(prev => prev.filter(p => p.id !== record.id));
                                }, children: "\uC81C\uAC70" }))
                        }
                    ], pagination: false, style: { marginTop: 24 } }), _jsx("div", { style: { marginTop: 32, textAlign: 'center' }, children: _jsx(Button, { type: "primary", icon: _jsx(DownloadOutlined, {}), onClick: exportRigidScript, children: "\uC635\uC158\uD30C\uC77C \uCD9C\uB825" }) })] }) }));
};
export default ElasticToRigidBuilder;
