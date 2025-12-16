import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useState } from 'react';
import BaseLayout from '../layouts/BaseLayout';
import { Typography, Upload, message, Table, Select, InputNumber, Button, Space, Radio } from 'antd';
import { InboxOutlined, DownloadOutlined } from '@ant-design/icons';
import ColoredScatter3DComponent from '../components/ColoredScatter3DComponent';
import Papa from 'papaparse';
import ObjViewerComponent from '../components/ObjViewerComponent';
const { Title, Paragraph } = Typography;
const { Dragger } = Upload;
const { Option } = Select;
const DEFAULT_HEADERS = [
    'Height', 'EulerX', 'EulerY', 'EulerZ',
    'Restitution', 'Stiffness', 'Damping',
    'VelX', 'VelY', 'VelZ',
    'PosX', 'PosY'
];
// 샘플 개수
const DEFAULT_NUM_SAMPLES = 32;
// 간단 LHS (0~1 사이)
function lhsSample(dim, n) {
    const result = Array.from({ length: n }, () => Array(dim).fill(0));
    for (let d = 0; d < dim; d++) {
        const cut = Array.from({ length: n }, (_, i) => (i + Math.random()) / n); // stratified
        // shuffle
        for (let i = cut.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            [cut[i], cut[j]] = [cut[j], cut[i]];
        }
        for (let i = 0; i < n; i++) {
            result[i][d] = cut[i];
        }
    }
    return result;
}
// Box-Muller 표준정규
function randn() {
    let u = 0, v = 0;
    while (u === 0)
        u = Math.random();
    while (v === 0)
        v = Math.random();
    return Math.sqrt(-2.0 * Math.log(u)) * Math.cos(2.0 * Math.PI * v);
}
// 0.4 간격 그리드 배치
function placeOnGrid(n, step = 0.4) {
    const cols = Math.ceil(Math.sqrt(n));
    const coords = [];
    for (let i = 0; i < n; i++) {
        const x = (i % cols) * step;
        const y = Math.floor(i / cols) * step;
        coords.push([x, y]);
    }
    return coords;
}
const makeDefaultParamRows = () => ([
    { key: 'Height', name: 'Height', mode: 'fixed', fixed: 1.5 },
    { key: 'EulerX', name: 'EulerX', mode: 'range', min: -180, max: 180 },
    { key: 'EulerY', name: 'EulerY', mode: 'range', min: -90, max: 90 },
    { key: 'EulerZ', name: 'EulerZ', mode: 'range', min: -180, max: 180 },
    { key: 'Restitution', name: 'Restitution', mode: 'fixed', fixed: 1e-5 },
    { key: 'Stiffness', name: 'Stiffness', mode: 'fixed', fixed: 1e9 },
    { key: 'Damping', name: 'Damping', mode: 'fixed', fixed: 10 },
    { key: 'VelX', name: 'VelX', mode: 'fixed', fixed: 0 },
    { key: 'VelY', name: 'VelY', mode: 'fixed', fixed: 0 },
    { key: 'VelZ', name: 'VelZ', mode: 'fixed', fixed: 0 },
    { key: 'PosX', name: 'PosX', mode: 'fixed', fixed: 0 }, // 실제 생성 시 grid로 덮어씀
    { key: 'PosY', name: 'PosY', mode: 'fixed', fixed: 0 }, // 실제 생성 시 grid로 덮어씀
]);
const FullAngleDropsMBDPage = () => {
    const [data, setData] = useState(null);
    const [rows, setRows] = useState(makeDefaultParamRows);
    const [numSamples, setNumSamples] = useState(DEFAULT_NUM_SAMPLES);
    const [globalSampler, setGlobalSampler] = useState('lhs');
    const [objUrl, setObjUrl] = useState(null);
    // CSV 업로드 파서
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
                try {
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
                    setData(parsed);
                    message.success('CSV 로드 성공!');
                }
                catch (e) {
                    console.error(e);
                    message.error('CSV 파싱 중 오류가 발생했습니다.');
                }
            },
        });
        return false;
    };
    // 파라미터 테이블 변경 핸들러
    const changeRow = (name, patch) => {
        setRows(prev => prev.map(r => r.name === name ? { ...r, ...patch } : r));
    };
    const columns = [
        {
            title: 'Name',
            dataIndex: 'name',
            width: 130,
            render: (v) => _jsx("b", { children: v }),
        },
        {
            title: 'Mode',
            dataIndex: 'mode',
            width: 120,
            render: (_, record) => (_jsxs(Select, { value: record.mode, style: { width: '100%' }, onChange: (val) => changeRow(record.name, { mode: val }), children: [_jsx(Option, { value: "fixed", children: "fixed" }), _jsx(Option, { value: "range", children: "range (LHS/Random)" }), _jsx(Option, { value: "normal", children: "normal(\u03BC, \u03C3)" })] })),
        },
        {
            title: 'Fixed',
            dataIndex: 'fixed',
            width: 120,
            render: (_, record) => (_jsx(InputNumber, { value: record.fixed, onChange: (val) => changeRow(record.name, { fixed: val ?? undefined }), disabled: record.mode !== 'fixed', style: { width: '100%' } })),
        },
        {
            title: 'Min',
            dataIndex: 'min',
            width: 120,
            render: (_, record) => (_jsx(InputNumber, { value: record.min, onChange: (val) => changeRow(record.name, { min: val ?? undefined }), disabled: record.mode !== 'range', style: { width: '100%' } })),
        },
        {
            title: 'Max',
            dataIndex: 'max',
            width: 120,
            render: (_, record) => (_jsx(InputNumber, { value: record.max, onChange: (val) => changeRow(record.name, { max: val ?? undefined }), disabled: record.mode !== 'range', style: { width: '100%' } })),
        },
        {
            title: 'Mean',
            dataIndex: 'mean',
            width: 120,
            render: (_, record) => (_jsx(InputNumber, { value: record.mean, onChange: (val) => changeRow(record.name, { mean: val ?? undefined }), disabled: record.mode !== 'normal', style: { width: '100%' } })),
        },
        {
            title: 'Std',
            dataIndex: 'std',
            width: 120,
            render: (_, record) => (_jsx(InputNumber, { value: record.std, onChange: (val) => changeRow(record.name, { std: val ?? undefined }), disabled: record.mode !== 'normal', style: { width: '100%' } })),
        },
    ];
    const generate = () => {
        // 1) LHS용으로 'range' 모드인 파라미터들만 차원에 포함
        const rangeParams = rows.filter(r => r.mode === 'range');
        const dim = rangeParams.length;
        let lhs = [];
        if (globalSampler === 'lhs' && dim > 0) {
            lhs = lhsSample(dim, numSamples); // 0~1
        }
        // Pos grid
        const grid = placeOnGrid(numSamples, 0.4);
        // 2) 한 샘플당 값 생성
        const records = [];
        for (let i = 0; i < numSamples; i++) {
            const rec = {};
            // 먼저 기본/고정값/정규/범위값 채움
            let rangeIdx = 0;
            for (const r of rows) {
                if (r.name === 'PosX' || r.name === 'PosY')
                    continue; // 나중에 grid로 덮어씀
                if (r.mode === 'fixed') {
                    rec[r.name] = r.fixed ?? 0;
                }
                else if (r.mode === 'range') {
                    const lo = r.min ?? 0;
                    const hi = r.max ?? 1;
                    const u = (globalSampler === 'lhs' && dim > 0)
                        ? lhs[i][rangeIdx++] // stratified
                        : Math.random(); // random
                    rec[r.name] = lo + (hi - lo) * u;
                }
                else { // normal
                    const mean = r.mean ?? 0;
                    const std = r.std ?? 1;
                    rec[r.name] = mean + std * randn();
                }
            }
            // PosX/PosY는 0.4 간격 그리드
            const [px, py] = grid[i];
            rec.PosX = px;
            rec.PosY = py;
            records.push(rec);
        }
        // 3) CSV/ColoredScatter3DComponent용 2D 배열 구성
        const headers = DEFAULT_HEADERS;
        const parsed = [headers];
        for (const r of records) {
            parsed.push(headers.map(h => r[h]));
        }
        setData(parsed);
        message.success(`샘플 ${numSamples}개 생성 완료!`);
    };
    const downloadCSV = () => {
        if (!data)
            return;
        const csv = Papa.unparse({
            fields: data[0],
            data: data.slice(1),
        });
        const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
        const a = document.createElement('a');
        a.href = URL.createObjectURL(blob);
        a.download = `FullAngleDrops_${new Date().toISOString().replace(/[:.]/g, '-')}.csv`;
        a.click();
        URL.revokeObjectURL(a.href);
    };
    return (_jsx(BaseLayout, { isLoggedIn: true, children: _jsxs("div", { style: {
                padding: 24,
                backgroundColor: '#fff',
                minHeight: '100vh',
                borderRadius: '24px',
            }, children: [_jsx(Title, { level: 3, children: "\uC804\uAC01\uB3C4 \uB2E4\uBB3C\uCCB4 \uB3D9\uC5ED\uD559 \uB099\uD558 \uC2DC\uBBAC\uB808\uC774\uC158" }), _jsxs(Paragraph, { children: ["\u2022 CSV\uB97C \uB4DC\uB798\uADF8-\uB4DC\uB86D\uD558\uC5EC \uBC14\uB85C \uC2DC\uAC01\uD654\uD558\uAC70\uB098", _jsx("br", {}), "\u2022 \uC544\uB798 \uD30C\uB77C\uBBF8\uD130 \uD14C\uC774\uBE14\uC5D0\uC11C ", _jsx("b", { children: "\uACE0\uC815\uAC12 / \uBC94\uC704(LHS/Random) / \uC815\uADDC\uBD84\uD3EC(\u03BC,\u03C3)" }), "\uB97C \uC9C0\uC815\uD574 \uC0D8\uD50C\uC744 \uC0DD\uC131\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4.", _jsx("br", {}), "\u2022 ", _jsx("b", { children: "PosX, PosY" }), "\uB294 \uD56D\uC0C1 ", _jsx("code", { children: "0.4" }), " \uAC04\uACA9\uC73C\uB85C \uACB9\uCE58\uC9C0 \uC54A\uB3C4\uB85D \uC790\uB3D9 \uBC30\uCE58\uB429\uB2C8\uB2E4."] }), _jsxs(Dragger, { name: "file", multiple: false, accept: ".csv", beforeUpload: handleCSV, showUploadList: false, style: { marginBottom: 30 }, children: [_jsx("p", { className: "ant-upload-drag-icon", children: _jsx(InboxOutlined, {}) }), _jsx("p", { className: "ant-upload-text", children: "CSV \uD30C\uC77C\uC744 \uC774\uACF3\uC5D0 \uB4DC\uB798\uADF8\uD558\uAC70\uB098 \uD074\uB9AD\uD558\uC5EC \uC5C5\uB85C\uB4DC\uD558\uC138\uC694" })] }), _jsxs(Space, { direction: "vertical", style: { width: '100%', marginTop: 24 }, children: [_jsx(Title, { level: 4, children: "\uD30C\uB77C\uBBF8\uD130 \uAE30\uBC18 \uC0D8\uD50C \uC0DD\uC131" }), _jsxs(Space, { align: "center", wrap: true, children: [_jsx("span", { children: "\uC0D8\uD50C \uAC1C\uC218:" }), _jsx(InputNumber, { min: 1, value: numSamples, onChange: (v) => setNumSamples(v ?? 1) }), _jsx("span", { children: "range \uBAA8\uB4DC \uC804\uC5ED \uC0D8\uD50C\uB7EC:" }), _jsx(Radio.Group, { value: globalSampler, onChange: (e) => setGlobalSampler(e.target.value), optionType: "button", options: [
                                        { label: 'LHS', value: 'lhs' },
                                        { label: 'Random', value: 'random' },
                                    ] }), _jsx(Button, { type: "primary", onClick: generate, children: "\uC0D8\uD50C \uC0DD\uC131" }), _jsx(Button, { icon: _jsx(DownloadOutlined, {}), onClick: downloadCSV, disabled: !data, children: "CSV \uB2E4\uC6B4\uB85C\uB4DC" })] }), _jsx(Table, { bordered: true, size: "small", dataSource: rows, columns: columns, pagination: false, style: { marginTop: 12 } })] }), _jsx("div", { style: { marginTop: 32 }, children: data && (_jsx(ColoredScatter3DComponent, { title: "Colored Scatter 3D", data: data })) }), _jsx(Title, { level: 4, style: { marginTop: 48 }, children: "\uD83D\uDCE6 OBJ \uD30C\uC77C \uC5C5\uB85C\uB4DC" }), _jsx(Paragraph, { children: "\uC2DC\uBBAC\uB808\uC774\uC158 \uACB0\uACFC\uC640 \uD568\uAED8 \uC0AC\uC6A9\uD560 3D \uBAA8\uB378(.obj)\uC744 \uC5C5\uB85C\uB4DC\uD558\uC138\uC694." }), _jsxs(Dragger, { name: "objFile", multiple: false, accept: ".obj", beforeUpload: (file) => {
                        const isObj = file.name.endsWith('.obj');
                        if (!isObj) {
                            message.error('OBJ 파일만 업로드할 수 있습니다.');
                            return Upload.LIST_IGNORE;
                        }
                        setObjUrl(URL.createObjectURL(file));
                        const reader = new FileReader();
                        reader.onload = (e) => {
                            const content = e.target?.result;
                            // TODO: content 처리
                            console.log('[OBJ 업로드됨]', file.name, content.slice(0, 100));
                            message.success(`OBJ 파일 "${file.name}" 로드 완료`);
                        };
                        reader.readAsText(file);
                        return false; // 자동 업로드 방지
                    }, showUploadList: false, children: [_jsx("p", { className: "ant-upload-drag-icon", children: _jsx(InboxOutlined, {}) }), _jsx("p", { className: "ant-upload-text", children: "OBJ \uD30C\uC77C\uC744 \uC774\uACF3\uC5D0 \uB4DC\uB798\uADF8\uD558\uAC70\uB098 \uD074\uB9AD\uD558\uC5EC \uC5C5\uB85C\uB4DC\uD558\uC138\uC694" })] }), objUrl && (_jsx(ObjViewerComponent, { url: objUrl }))] }) }));
};
export default FullAngleDropsMBDPage;
