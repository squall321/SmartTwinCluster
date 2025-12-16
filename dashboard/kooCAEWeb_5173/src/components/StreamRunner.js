import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useState, useEffect, useRef } from 'react';
import { api } from '../api/axiosClient';
import { Spin, Button, message, Divider, Typography, Upload } from 'antd';
import { DownloadOutlined } from '@ant-design/icons';
import { useLocation } from 'react-router-dom';
const { Dragger } = Upload;
const { Title, Paragraph } = Typography;
const StreamRunner = (props) => {
    const location = useLocation();
    const state = location.state;
    // 📌 props > location.state > default
    const solver = props.solver ?? state?.solver ?? null;
    const mode = props.mode ?? state?.mode ?? null;
    const autoSubmit = props.autoSubmit ?? state?.autoSubmit ?? false;
    const [txtFiles, setTxtFiles] = useState(props.txtFiles ?? state?.txtFiles ?? []);
    const [optFiles, setOptFiles] = useState(props.optFiles ?? state?.optFiles ?? []);
    const [logs, setLogs] = useState('');
    const [loading, setLoading] = useState(false);
    const [downloadUrl, setDownloadUrl] = useState(null);
    const [isSubmitted, setIsSubmitted] = useState(false);
    const hasSubmittedRef = useRef(false);
    const username = localStorage.getItem('username') || 'default_user';
    const handleSubmit = async () => {
        if (txtFiles.length === 0) {
            message.warning('TXT 파일을 업로드해주세요.');
            return;
        }
        setDownloadUrl(null);
        const formData = new FormData();
        formData.append("user", username);
        formData.append("cmd_line", txtFiles.map(file => file.name).join(","));
        if (mode)
            formData.append("mode", mode);
        txtFiles.forEach(file => formData.append("files_txt", file));
        optFiles.forEach(file => formData.append("files_opt", file));
        let url = "/api/proxy/automation/app/meshmodifier/stream";
        if (solver === "AutomatedModeller") {
            url = "/api/proxy/automation/app/automatedmodeller/stream";
        }
        setLogs("▶️ 실행 시작...\n");
        setLoading(true);
        try {
            const response = await api.post(url, formData, {
                responseType: "text",
                headers: { 'Content-Type': 'multipart/form-data' },
            });
            const parsed = JSON.parse(response.data);
            const allOutput = parsed.results.map((res) => {
                const output = (res.stderr && res.stderr.trim() !== "" ? res.stderr : res.stdout).replace(/\r\n/g, "\n");
                return `📄 ${res.file}\n${output}`;
            }).join("\n\n");
            setLogs(prev => prev + allOutput + "\n✅ 실행 완료");
            const firstResult = parsed.results[0];
            if (firstResult?.download_url) {
                setDownloadUrl(`${api.defaults.baseURL}${firstResult.download_url}`);
            }
        }
        catch (err) {
            console.error(err);
            setLogs(`❌ 오류 발생: ${err.message}`);
            message.error("실행 중 오류가 발생했습니다.");
        }
        finally {
            setLoading(false);
        }
    };
    const handleDownload = async () => {
        if (!downloadUrl) {
            message.error("다운로드 URL이 없습니다.");
            return;
        }
        try {
            const response = await api.get(downloadUrl, { responseType: 'blob' });
            const blob = new Blob([response.data], { type: 'application/zip' });
            const url = URL.createObjectURL(blob);
            const link = document.createElement('a');
            link.href = url;
            link.download = 'results.zip';
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
            URL.revokeObjectURL(url);
        }
        catch (error) {
            console.error(error);
            message.error('다운로드 실패');
        }
    };
    // ✅ autoSubmit 트리거
    useEffect(() => {
        if (autoSubmit &&
            txtFiles.length > 0 &&
            !hasSubmittedRef.current) {
            hasSubmittedRef.current = true;
            console.log("💥 handleSubmit 실행");
            handleSubmit();
        }
    }, [autoSubmit, txtFiles, optFiles]);
    return (_jsx(Spin, { spinning: loading, tip: "\uC5C5\uB85C\uB4DC \uBC0F \uC2E4\uD589 \uC911\uC785\uB2C8\uB2E4...", children: _jsxs("div", { style: { padding: '20px' }, children: [_jsx(Title, { level: 3, children: "Stream Runner" }), _jsx(Paragraph, { children: "TXT \uD30C\uC77C\uACFC \uC635\uC158 \uD30C\uC77C\uC744 \uC5C5\uB85C\uB4DC\uD558\uACE0 \uD574\uC11D\uC744 \uC2E4\uD589\uD55C \uD6C4 \uACB0\uACFC\uB97C \uD655\uC778\uD558\uC138\uC694." }), _jsx("h4", { children: "\uD83D\uDCC4 TXT \uD30C\uC77C \uB4DC\uB798\uADF8" }), _jsxs(Dragger, { name: "files_txt", multiple: true, fileList: txtFiles.map(file => ({
                        uid: file.name,
                        name: file.name,
                        status: 'done',
                    })), beforeUpload: () => false, customRequest: () => { }, onChange: (info) => {
                        const fileList = info.fileList.map(f => f.originFileObj).filter(Boolean);
                        setTxtFiles(fileList);
                    }, onRemove: (file) => {
                        setTxtFiles(prev => prev.filter(f => f.name !== file.name));
                        return true;
                    }, style: { marginBottom: '20px' }, children: [_jsx("p", { className: "ant-upload-drag-icon", children: "\uD83D\uDCC4" }), _jsx("p", { className: "ant-upload-text", children: "\uC5EC\uAE30\uB85C TXT \uD30C\uC77C\uC744 \uB4DC\uB798\uADF8 \uD558\uC138\uC694" }), _jsx("p", { className: "ant-upload-hint", children: "\uC5EC\uB7EC \uD30C\uC77C\uC744 \uB3D9\uC2DC\uC5D0 \uC5C5\uB85C\uB4DC\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4." })] }), _jsx("h4", { children: "\u2699\uFE0F \uC635\uC158 \uD30C\uC77C \uB4DC\uB798\uADF8" }), _jsxs(Dragger, { name: "files_opt", multiple: true, fileList: optFiles.map(file => ({
                        uid: file.name,
                        name: file.name,
                        status: 'done',
                    })), beforeUpload: () => false, customRequest: () => { }, onChange: (info) => {
                        const fileList = info.fileList.map(f => f.originFileObj).filter(Boolean);
                        setOptFiles(fileList);
                    }, onRemove: (file) => {
                        setOptFiles(prev => prev.filter(f => f.name !== file.name));
                        return true;
                    }, style: { marginBottom: '20px' }, children: [_jsx("p", { className: "ant-upload-drag-icon", children: "\u2699\uFE0F" }), _jsx("p", { className: "ant-upload-text", children: "\uC5EC\uAE30\uB85C \uC635\uC158 \uD30C\uC77C\uC744 \uB4DC\uB798\uADF8 \uD558\uC138\uC694" }), _jsx("p", { className: "ant-upload-hint", children: "\uC5EC\uB7EC \uC635\uC158 \uD30C\uC77C\uC744 \uB3D9\uC2DC\uC5D0 \uC5C5\uB85C\uB4DC\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4." })] }), _jsx(Button, { type: "primary", onClick: handleSubmit, style: { marginBottom: '20px' }, children: "\uD83D\uDE80 Submit" }), _jsx(Divider, {}), _jsx(Title, { level: 4, children: "\uD83D\uDCE1 \uC2E4\uD589 \uACB0\uACFC" }), _jsx("pre", { style: {
                        backgroundColor: '#111',
                        color: '#0f0',
                        padding: '10px',
                        height: '300px',
                        overflow: 'auto',
                        borderRadius: '5px',
                        whiteSpace: 'pre-wrap'
                    }, children: logs }), downloadUrl && (_jsx(Button, { type: "primary", icon: _jsx(DownloadOutlined, {}), onClick: handleDownload, children: "\uC0DD\uC131\uB41C \uD30C\uC77C ZIP \uB2E4\uC6B4\uB85C\uB4DC" }))] }) }));
};
export default StreamRunner;
