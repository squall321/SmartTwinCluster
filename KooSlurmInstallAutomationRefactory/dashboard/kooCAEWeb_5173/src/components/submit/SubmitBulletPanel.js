import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useMemo, useState } from 'react';
import { Typography, Form, Input, InputNumber, Button, Table, Space, message, Tooltip, Upload, Tag } from 'antd';
import { CopyOutlined, DownloadOutlined, ThunderboltOutlined, InboxOutlined, FileDoneOutlined } from '@ant-design/icons';
import Papa from 'papaparse';
const { Title, Paragraph, Text } = Typography;
const { Dragger } = Upload;
const SubmitBulletPanel = ({ csvData: externalCsvData, csvPath: externalCsvPath, objPath: externalObjPath, defaultTimestep = 1.0e-6, defaultWriteTime = 1.0, defaultThreads = 4, solverEntry = 'python solver.py', }) => {
    const [csvData, setCsvData] = useState(externalCsvData);
    const [csvPath, setCsvPath] = useState(externalCsvPath ?? 'drop.csv');
    const [objPath, setObjPath] = useState(externalObjPath ?? 'smartphone.obj');
    const [csvUploaded, setCsvUploaded] = useState(false);
    const [objUploaded, setObjUploaded] = useState(false);
    const numCases = useMemo(() => {
        if (!csvData || csvData.length <= 1)
            return 0;
        return csvData.length - 1;
    }, [csvData]);
    const [timestep, setTimestep] = useState(defaultTimestep);
    const [writeTime, setWriteTime] = useState(defaultWriteTime);
    const [threads, setThreads] = useState(defaultThreads);
    const [entry, setEntry] = useState(solverEntry);
    const [jobs, setJobs] = useState([]);
    const generateJobs = () => {
        if (numCases <= 0) {
            message.error('CSV 데이터(행 수)를 확인할 수 없습니다. csvData를 props로 전달했는지 확인하세요.');
            return;
        }
        if (threads <= 0) {
            message.error('threads 는 1 이상이어야 합니다.');
            return;
        }
        const chunk = Math.ceil(numCases / threads);
        const newJobs = [];
        for (let k = 0; k < threads; k++) {
            const start = k * chunk;
            const end = Math.min((k + 1) * chunk, numCases);
            if (start >= end)
                break;
            const cmd = `${entry} ` +
                `--start ${start} ` +
                `--end ${end} ` +
                `--batchsize ${chunk} ` +
                `--timestep ${timestep} ` +
                `--csv ${csvPath} ` +
                `--objfile ${objPath} ` +
                `--writetime ${writeTime}`;
            newJobs.push({ key: k, idx: k, start, end, batchsize: chunk, command: cmd });
        }
        setJobs(newJobs);
        message.success(`${newJobs.length}개의 job 커맨드를 생성했습니다.`);
    };
    const copyAll = async () => {
        if (jobs.length === 0)
            return;
        const text = jobs.map(j => j.command).join('\n');
        try {
            await navigator.clipboard.writeText(text);
            message.success('모든 커맨드를 클립보드에 복사했습니다.');
        }
        catch (e) {
            message.error('클립보드 복사에 실패했습니다.');
        }
    };
    const downloadSh = () => {
        if (jobs.length === 0)
            return;
        const body = [
            '#!/usr/bin/env bash',
            'set -e',
            `# total cases: ${numCases}, threads: ${threads}`,
            ...jobs.map(j => j.command + ' &'),
            'wait',
            'echo "all jobs done"',
        ].join('\n');
        const blob = new Blob([body], { type: 'text/x-shellscript;charset=utf-8;' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = 'run_bullet_jobs.sh';
        a.click();
        URL.revokeObjectURL(url);
    };
    const columns = [
        { title: '#', dataIndex: 'idx', width: 60 },
        { title: 'start', dataIndex: 'start', width: 90 },
        { title: 'end', dataIndex: 'end', width: 90 },
        { title: 'batchsize', dataIndex: 'batchsize', width: 110 },
        {
            title: 'command',
            dataIndex: 'command',
            render: (val) => (_jsxs(Space, { children: [_jsx(Text, { code: true, style: { userSelect: 'all' }, children: val }), _jsx(Tooltip, { title: "Copy", children: _jsx(Button, { size: "small", icon: _jsx(CopyOutlined, {}), onClick: async () => {
                                try {
                                    await navigator.clipboard.writeText(val);
                                    message.success('복사됨');
                                }
                                catch {
                                    message.error('복사 실패');
                                }
                            } }) })] })),
        },
    ];
    const handleCSV = (file) => {
        Papa.parse(file, {
            header: true,
            skipEmptyLines: true,
            complete: (results) => {
                const raw = results.data;
                const meta = results.meta.fields || [];
                if (raw.length === 0 || meta.length === 0) {
                    message.error('CSV에 유효한 데이터가 없습니다.');
                    return;
                }
                const headers = meta;
                const parsed = [headers];
                raw.forEach((row) => {
                    const rowArray = headers.map((key) => {
                        const val = row[key];
                        const num = Number(val);
                        return isNaN(num) ? val : num;
                    });
                    parsed.push(rowArray);
                });
                setCsvData(parsed);
                setCsvPath(file.name);
                setCsvUploaded(true);
                message.success(`CSV "${file.name}" 업로드 성공!`);
            },
        });
        return false;
    };
    const handleOBJ = (file) => {
        if (!file.name.endsWith('.obj')) {
            message.error('OBJ 파일만 업로드 가능합니다.');
            return Upload.LIST_IGNORE;
        }
        setObjPath(file.name);
        setObjUploaded(true);
        message.success(`OBJ "${file.name}" 업로드 성공!`);
        return false;
    };
    return (_jsxs("div", { style: { padding: 24 }, children: [_jsx(Title, { level: 3, children: "SubmitBulletPanel" }), _jsxs(Paragraph, { children: [_jsx("b", { children: "CSV" }), " \uBC0F ", _jsx("b", { children: "OBJ" }), " \uD30C\uC77C\uC744 \uC9C1\uC811 \uC5C5\uB85C\uB4DC\uD558\uAC70\uB098, \uC678\uBD80 props\uB85C \uC804\uB2EC\uBC1B\uC744 \uC218 \uC788\uC2B5\uB2C8\uB2E4."] }), _jsx(Title, { level: 4, children: "\uD83D\uDCC2 \uD30C\uC77C \uC5C5\uB85C\uB4DC" }), _jsxs(Paragraph, { children: ["\u2022 CSV \uD30C\uC77C\uC740 \uC2E4\uD5D8 \uCF00\uC774\uC2A4\uB97C \uD3EC\uD568\uD55C \uD30C\uB77C\uBBF8\uD130 \uD14C\uC774\uBE14\uC785\uB2C8\uB2E4. (\uCCAB \uD589\uC740 \uD5E4\uB354)", _jsx("br", {}), "\u2022 OBJ \uD30C\uC77C\uC740 \uC2DC\uBBAC\uB808\uC774\uC158 \uB300\uC0C1 \uD615\uC0C1\uC785\uB2C8\uB2E4."] }), _jsxs(Space, { direction: "vertical", style: { width: '100%' }, children: [_jsxs(Dragger, { name: "csv", multiple: false, accept: ".csv", beforeUpload: handleCSV, showUploadList: false, children: [_jsx("p", { className: "ant-upload-drag-icon", children: _jsx(InboxOutlined, {}) }), _jsx("p", { className: "ant-upload-text", children: "CSV \uD30C\uC77C \uB4DC\uB798\uADF8 \uD639\uC740 \uD074\uB9AD" }), csvUploaded && _jsxs(Tag, { icon: _jsx(FileDoneOutlined, {}), color: "green", children: [csvPath, " \uBD88\uB7EC\uC634"] })] }), _jsxs(Dragger, { name: "obj", multiple: false, accept: ".obj", beforeUpload: handleOBJ, showUploadList: false, children: [_jsx("p", { className: "ant-upload-drag-icon", children: _jsx(InboxOutlined, {}) }), _jsx("p", { className: "ant-upload-text", children: "OBJ \uD30C\uC77C \uB4DC\uB798\uADF8 \uD639\uC740 \uD074\uB9AD" }), objUploaded && _jsxs(Tag, { icon: _jsx(FileDoneOutlined, {}), color: "blue", children: [objPath, " \uBD88\uB7EC\uC634"] })] })] }), _jsxs(Form, { layout: "vertical", onFinish: generateJobs, style: { marginTop: 24 }, children: [_jsx(Form.Item, { label: "solver entry (\uC608: python solver.py)", children: _jsx(Input, { value: entry, onChange: (e) => setEntry(e.target.value) }) }), _jsx(Form.Item, { label: "timestep (s)", children: _jsx(InputNumber, { style: { width: '100%' }, value: timestep, onChange: (v) => setTimestep(v ?? 0) }) }), _jsx(Form.Item, { label: "writeTime (s)", children: _jsx(InputNumber, { style: { width: '100%' }, value: writeTime, onChange: (v) => setWriteTime(v ?? 0) }) }), _jsx(Form.Item, { label: "threads (\uB3D9\uC2DC\uC5D0 \uB3CC\uB9B4 job \uC218)", children: _jsx(InputNumber, { min: 1, style: { width: '100%' }, value: threads, onChange: (v) => setThreads(v ?? 1) }) }), _jsxs(Space, { children: [_jsx(Button, { type: "primary", htmlType: "submit", icon: _jsx(ThunderboltOutlined, {}), children: "Generate Commands" }), _jsx(Button, { icon: _jsx(CopyOutlined, {}), disabled: jobs.length === 0, onClick: copyAll, children: "Copy All" }), _jsx(Button, { icon: _jsx(DownloadOutlined, {}), disabled: jobs.length === 0, onClick: downloadSh, children: "Download .sh" })] })] }), _jsx(Table, { style: { marginTop: 24 }, bordered: true, size: "small", dataSource: jobs, columns: columns, pagination: false, rowKey: "key" })] }));
};
export default SubmitBulletPanel;
