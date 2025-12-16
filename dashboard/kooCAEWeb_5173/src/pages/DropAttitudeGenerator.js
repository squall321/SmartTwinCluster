import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useState } from 'react';
import BaseLayout from '../layouts/BaseLayout';
import { Typography, Upload, Button, Table, InputNumber, Space, Form, message, Popconfirm, Spin } from 'antd';
import { InboxOutlined, PlusOutlined, DeleteOutlined } from '@ant-design/icons';
import Plot from 'react-plotly.js';
import { generateDropAttitudeOptionFile } from '../components/shared/utils';
import ExportMeshModifierButton from '../components/shared/ExportMeshModifierButtonProps';
const { Title } = Typography;
const defaultOptions = {
    OffsetDistance: 0.1,
    Density: 2700,
    YoungsModulus: 70e9,
    PoissonRatio: 0.3,
    tFinal: 1.0e-3,
    dt: 1.0e-6,
};
const optionLabels = {
    OffsetDistance: '벽면까지 초기 거리 (m)',
    Density: '밀도 (kg/m³)',
    YoungsModulus: '탄성계수(GPa)',
    PoissonRatio: '푸아송비(비율)',
    tFinal: '종료 시간(Tfinal, s)',
    dt: '시간 간격(dt, s)',
};
const initialRow = {
    EulerRolling: 0,
    EulerPitching: 0,
    EulerYawing: 0,
    Height: 1220,
    InitialVelocityX: 0,
    InitialVelocityY: 0,
    InitialVelocityZ: 0,
    InitialAngularVelocityX: 0,
    InitialAngularVelocityY: 0,
    InitialAngularVelocityZ: 0,
};
const DropAttitudeGenerator = () => {
    const [kFile, setKFile] = useState(null);
    const [tableData, setTableData] = useState([initialRow]);
    const [options, setOptions] = useState(defaultOptions);
    const [randomCount, setRandomCount] = useState(5);
    const [loading, setLoading] = useState(false);
    const fullPlotBoxStyle = { width: '100%', height: 500, minWidth: 0 };
    const fullPlotStyle = { width: '100%', height: '100%' };
    const handleAddRow = () => {
        setTableData([...tableData, { ...initialRow }]);
    };
    const handleDeleteRow = (indexToRemove) => {
        const newData = tableData.filter((_, idx) => idx !== indexToRemove);
        setTableData(newData);
    };
    const handleClearAllRows = () => {
        setTableData([]);
    };
    const handleAddPredefinedRows = (angles) => {
        const newRows = angles.map(([roll, pitch, yaw]) => ({
            ...initialRow,
            Height: 1500,
            EulerRolling: roll,
            EulerPitching: pitch,
            EulerYawing: yaw,
        }));
        setTableData([...tableData, ...newRows]);
    };
    const handleOptionChange = (key, value) => {
        setOptions({ ...options, [key]: value });
    };
    /*
    const handleExport = () => {
      const fields = Object.keys(initialRow);
      let content = '*Inputfile\n';
      content += `${kFile?.name || 'UNKNOWN.k'}\n`;
      content += '*Mode\n';
      content += 'DROP_ATTITUDE,1\n';
      content += '**DropAttitude,1\n';
  
      fields.forEach(field => {
        content += field + ',' + tableData.map(row => row[field]).join(',') + '\n';
      });
  
      Object.entries(options).forEach(([key, value]) => {
        content += `${key},${value}\n`;
      });
  
      content += '**EndDropAttitude\n*End';
  
      const blob = new Blob([content], { type: 'text/plain;charset=utf-8' });
      const link = document.createElement('a');
      link.href = URL.createObjectURL(blob);
      link.download = 'drop_attitude.txt';
      link.click();
    };*/
    const columnNameMap = {
        EulerRolling: _jsxs("div", { style: { textAlign: 'center' }, children: ["Roll", _jsx("br", {}), "(\uB864)"] }),
        EulerPitching: _jsxs("div", { style: { textAlign: 'center' }, children: ["Pitch", _jsx("br", {}), "(\uD53C\uCE58)"] }),
        EulerYawing: _jsxs("div", { style: { textAlign: 'center' }, children: ["Yaw", _jsx("br", {}), "(\uC694)"] }),
        Height: _jsxs("div", { style: { textAlign: 'center' }, children: ["\uB192\uC774", _jsx("br", {}), "(mm)"] }),
        InitialVelocityX: _jsxs("div", { style: { textAlign: 'center' }, children: ["Vx", _jsx("br", {}), "(mm/s)"] }),
        InitialVelocityY: _jsxs("div", { style: { textAlign: 'center' }, children: ["Vy", _jsx("br", {}), "(mm/s)"] }),
        InitialVelocityZ: _jsxs("div", { style: { textAlign: 'center' }, children: ["Vz", _jsx("br", {}), "(mm/s)"] }),
        InitialAngularVelocityX: _jsxs("div", { style: { textAlign: 'center' }, children: ["\u03C9x", _jsx("br", {}), "(rad/s)"] }),
        InitialAngularVelocityY: _jsxs("div", { style: { textAlign: 'center' }, children: ["\u03C9y", _jsx("br", {}), "(rad/s)"] }),
        InitialAngularVelocityZ: _jsxs("div", { style: { textAlign: 'center' }, children: ["\u03C9z", _jsx("br", {}), "(rad/s)"] }),
    };
    const columns = [
        ...Object.keys(initialRow).map((key) => ({
            title: columnNameMap[key] || key,
            dataIndex: key,
            align: 'center',
            width: 50,
            render: (_, record, index) => (_jsx(InputNumber, { size: "small", style: { width: '80px', textAlign: 'center' }, value: record[key], onChange: (value) => {
                    const newData = [...tableData];
                    newData[index][key] = value;
                    setTableData(newData);
                } })),
        })),
        {
            title: '삭제',
            dataIndex: 'delete',
            align: 'center',
            width: 60,
            render: (_, __, index) => (_jsx(Popconfirm, { title: "\uC774 \uD589\uC744 \uC0AD\uC81C\uD558\uC2DC\uACA0\uC2B5\uB2C8\uAE4C?", onConfirm: () => handleDeleteRow(index), children: _jsx(Button, { icon: _jsx(DeleteOutlined, {}), size: "small", danger: true }) })),
        },
    ];
    const plotData = [{
            x: tableData.map(d => d.EulerRolling),
            y: tableData.map(d => d.EulerPitching),
            z: tableData.map(d => d.EulerYawing),
            mode: 'markers',
            type: 'scatter3d',
            marker: { size: 4, color: tableData.map(d => d.Height), colorscale: 'Viridis' },
        }];
    const plotLayout = {
        margin: { l: 0, r: 0, b: 0, t: 0 },
        autosize: true,
        scene: {
            xaxis: { title: 'Roll (°)' },
            yaxis: { title: 'Pitch (°)' },
            zaxis: { title: 'Yaw (°)' },
        },
    };
    // boxLayout도 동일 처리
    const boxLayout = {
        margin: { l: 0, r: 0, b: 0, t: 0 },
        autosize: true,
        scene: {
            xaxis: { title: 'X', scaleanchor: 'y' },
            yaxis: { title: 'Y', scaleanchor: 'z' },
            zaxis: { title: 'Z' },
            aspectmode: 'data',
        },
    };
    const boxData = tableData.flatMap((row, index) => {
        const angleToRad = (angle) => angle * Math.PI / 180;
        const rx = angleToRad(row.EulerRolling);
        const ry = angleToRad(row.EulerPitching);
        const rz = angleToRad(row.EulerYawing);
        const size = { x: 70, y: 150, z: 8 };
        // ✅ 정방형 그리드 좌표 계산
        const total = tableData.length;
        const cols = Math.ceil(Math.sqrt(total));
        const spacingX = 250.0;
        const spacingY = 250.0;
        const rowIdx = Math.floor(index / cols);
        const colIdx = index % cols;
        const offsetX = colIdx * spacingX;
        const offsetY = -rowIdx * spacingY;
        const offsetZ = row.Height;
        const corners = [
            [-size.x / 2, -size.y / 2, -size.z / 2],
            [size.x / 2, -size.y / 2, -size.z / 2],
            [size.x / 2, size.y / 2, -size.z / 2],
            [-size.x / 2, size.y / 2, -size.z / 2],
            [-size.x / 2, -size.y / 2, size.z / 2],
            [size.x / 2, -size.y / 2, size.z / 2],
            [size.x / 2, size.y / 2, size.z / 2],
            [-size.x / 2, size.y / 2, size.z / 2],
        ];
        const rotate = (v) => {
            let [x, y, z] = v;
            [y, z] = [y * Math.cos(rx) - z * Math.sin(rx), y * Math.sin(rx) + z * Math.cos(rx)];
            [x, z] = [x * Math.cos(ry) + z * Math.sin(ry), -x * Math.sin(ry) + z * Math.cos(ry)];
            [x, y] = [x * Math.cos(rz) - y * Math.sin(rz), x * Math.sin(rz) + y * Math.cos(rz)];
            return [x + offsetX, y + offsetY, z + offsetZ];
        };
        const vertices = corners.map(rotate);
        const frontFace = [[0, 1, 2], [0, 2, 3]];
        const topFace = [[2, 3, 7], [2, 7, 6]];
        const otherFaces = [
            [4, 5, 6], [4, 6, 7],
            [0, 1, 5], [0, 5, 4],
            [1, 2, 6], [1, 6, 5],
            [3, 0, 4], [3, 4, 7],
        ];
        const meshFront = {
            type: 'mesh3d',
            x: vertices.map(v => v[0]),
            y: vertices.map(v => v[1]),
            z: vertices.map(v => v[2]),
            i: frontFace.map(f => f[0]),
            j: frontFace.map(f => f[1]),
            k: frontFace.map(f => f[2]),
            color: 'red',
            opacity: 1.0,
            name: `Front ${index}`,
            showscale: false,
        };
        const meshTop = {
            type: 'mesh3d',
            x: vertices.map(v => v[0]),
            y: vertices.map(v => v[1]),
            z: vertices.map(v => v[2]),
            i: topFace.map(f => f[0]),
            j: topFace.map(f => f[1]),
            k: topFace.map(f => f[2]),
            color: 'blue',
            opacity: 1.0,
            name: `Top ${index}`,
            showscale: false,
        };
        const meshOthers = {
            type: 'mesh3d',
            x: vertices.map(v => v[0]),
            y: vertices.map(v => v[1]),
            z: vertices.map(v => v[2]),
            i: otherFaces.map(f => f[0]),
            j: otherFaces.map(f => f[1]),
            k: otherFaces.map(f => f[2]),
            color: 'gray',
            opacity: 1.0,
            name: `Body ${index}`,
            showscale: false,
        };
        return [meshOthers, meshFront, meshTop];
    });
    const parseDropAttitudeFile = (text) => {
        try {
            const lines = text
                .split(/\r?\n/)
                .map(line => line.trim())
                .filter(line => line.length > 0);
            const tableFields = {};
            const optionsData = {};
            let inDropAttitude = false;
            for (const line of lines) {
                if (line.startsWith("**DropAttitude")) {
                    inDropAttitude = true;
                    continue;
                }
                if (line.startsWith("**EndDropAttitude")) {
                    inDropAttitude = false;
                    continue;
                }
                if (inDropAttitude) {
                    const [key, ...values] = line.split(",").map(s => s.trim());
                    tableFields[key] = values.map(v => parseFloat(v));
                }
                else {
                    if (line.includes(",")) {
                        const [key, value] = line.split(",").map(s => s.trim());
                        if (key in defaultOptions) {
                            optionsData[key] = parseFloat(value);
                        }
                    }
                }
            }
            const numRows = Object.values(tableFields)[0]?.length || 0;
            const rows = Array.from({ length: numRows }, (_, i) => {
                const row = {};
                for (const key of Object.keys(initialRow)) {
                    row[key] = tableFields[key] ? tableFields[key][i] : 0;
                }
                return row;
            });
            setTableData(rows);
            setOptions({ ...defaultOptions, ...optionsData });
            message.success("옵션 파일을 불러왔습니다!");
        }
        catch (error) {
            console.error(error);
            message.error("옵션 파일 파싱 중 오류가 발생했습니다.");
        }
        finally {
            setLoading(false);
        }
    };
    return (_jsx(BaseLayout, { isLoggedIn: true, children: _jsx(Spin, { spinning: loading, tip: "\uC635\uC158 \uD30C\uC77C \uBD88\uB7EC\uC624\uB294 \uC911...", children: _jsxs("div", { style: {
                    padding: 24,
                    backgroundColor: '#fff',
                    minHeight: '100vh',
                    borderRadius: '24px',
                }, children: [_jsx(Title, { level: 3, children: "\uD83E\uDDED \uB099\uD558 \uC790\uC138 \uC0DD\uC131\uAE30" }), _jsxs(Upload.Dragger, { multiple: false, accept: ".k", beforeUpload: (file) => {
                            setLoading(true);
                            setTimeout(() => {
                                setKFile(file);
                                message.success(`${file.name} 선택됨`);
                                setLoading(false);
                            }, 0);
                            return false;
                        }, style: { marginBottom: '2rem' }, children: [_jsx("p", { className: "ant-upload-drag-icon", children: _jsx(InboxOutlined, {}) }), _jsx("p", { className: "ant-upload-text", children: "\uAE30\uBCF8 \uD574\uC11D\uC6A9 .k \uD30C\uC77C\uC744 \uC5C5\uB85C\uB4DC\uD558\uC138\uC694" })] }), _jsxs(Upload.Dragger, { multiple: false, accept: ".txt", beforeUpload: (file) => {
                            setLoading(true);
                            setTimeout(() => {
                                const reader = new FileReader();
                                reader.onload = (e) => {
                                    const content = e.target?.result;
                                    parseDropAttitudeFile(content);
                                    setLoading(false);
                                };
                                reader.onerror = () => {
                                    message.error("파일 읽기에 실패했습니다.");
                                    setLoading(false);
                                };
                                reader.readAsText(file);
                            }, 0);
                            return false;
                        }, style: { marginBottom: '2rem' }, children: [_jsx("p", { className: "ant-upload-drag-icon", children: _jsx(InboxOutlined, {}) }), _jsx("p", { className: "ant-upload-text", children: "\uC635\uC158 \uD30C\uC77C(.txt)\uC744 \uC5C5\uB85C\uB4DC\uD558\uC5EC \uC790\uC138\uC640 \uC635\uC158\uC744 \uBD88\uB7EC\uC624\uC138\uC694" })] }), _jsx(Title, { level: 5, children: "DOE \uD30C\uB77C\uBBF8\uD130" }), _jsxs(Space, { wrap: true, style: { marginBottom: '1rem' }, children: [_jsx(Button, { icon: _jsx(PlusOutlined, {}), onClick: handleAddRow, children: "\uC9C1\uC811 \uCD94\uAC00" }), _jsx(Button, { onClick: () => handleAddPredefinedRows([
                                    [0, 0, 0], // 전면
                                    [180, 0, 0], // 배면
                                    [90, 0, 0], // 좌측면 (왼쪽이 바닥으로)
                                    [-90, 0, 0], // 우측면 (오른쪽이 바닥으로)
                                    [0, -90, 0], // 상단 (윗면이 바닥으로)
                                    [0, 90, 0], // 하단 (아랫면이 바닥으로)
                                ]), children: "\uD83D\uDCE6 1.5m 6\uBA74 \uB099\uD558" }), _jsx(Button, { onClick: () => handleAddPredefinedRows([
                                    [-45, 0, 0], [45, 0, 0], [0, -45, 0], [0, 45, 0],
                                    [0, 0, -45], [0, 0, 45], [45, 45, 0], [-45, -45, 0],
                                    [0, 45, 45], [0, -45, -45], [45, 0, 45], [-45, 0, -45]
                                ]), children: "\uD83D\uDCE6 1.5m 12\uC5E3\uC9C0 \uB099\uD558" }), _jsx(Button, { onClick: () => handleAddPredefinedRows([
                                    [-35.264, 45, 0], [35.264, 45, 0],
                                    [-35.264, -45, 0], [35.264, -45, 0],
                                    [-35.264, 45, 180], [35.264, 45, 180],
                                    [-35.264, -45, 180], [35.264, -45, 180]
                                ]), children: "\uD83D\uDCE6 1.5m 8\uCF54\uB108 \uB099\uD558" }), _jsx(InputNumber, { min: 1, max: 100, value: randomCount, onChange: (v) => setRandomCount(v || 1), style: { width: '80px' } }), _jsx(Button, { onClick: () => {
                                    const rows = Array.from({ length: randomCount }, () => ({
                                        ...initialRow,
                                        Height: 1500,
                                        EulerRolling: Math.random() * 360 - 180,
                                        EulerPitching: Math.random() * 360 - 180,
                                        EulerYawing: Math.random() * 360 - 180,
                                    }));
                                    setTableData([...tableData, ...rows]);
                                }, children: "\uD83D\uDCE6 1.5m \uB79C\uB364 \uB099\uD558" }), _jsx(Button, { onClick: () => {
                                    const rows = Array.from({ length: randomCount }, () => ({
                                        ...initialRow,
                                        Height: Math.floor(Math.random() * 1800) + 300,
                                        EulerRolling: Math.random() * 360 - 180,
                                        EulerPitching: Math.random() * 360 - 180,
                                        EulerYawing: Math.random() * 360 - 180,
                                    }));
                                    setTableData([...tableData, ...rows]);
                                }, children: "\uD83D\uDCE6 \uB79C\uB364 \uB192\uC774 \uB099\uD558" }), _jsx(Button, { danger: true, onClick: handleClearAllRows, children: "\uC804\uCCB4 \uC0AD\uC81C" })] }), _jsx(Table, { columns: columns, dataSource: tableData, rowKey: (record, index) => index?.toString() ?? '', pagination: false, scroll: { x: true } }), _jsx(Title, { level: 5, style: { marginTop: '2rem' }, children: "\uC2DC\uBBAC\uB808\uC774\uC158 \uC804\uC5ED \uC635\uC158" }), _jsx(Form, { layout: "vertical", children: _jsx(Space, { wrap: true, children: Object.entries(defaultOptions).map(([key, defaultValue]) => (_jsx(Form.Item, { label: optionLabels[key] || key, children: _jsx(InputNumber, { value: options[key], onChange: (value) => handleOptionChange(key, value || 0) }) }, key))) }) }), _jsx(Title, { level: 5, style: { marginTop: '2rem' }, children: " Roll\u2013Pitch\u2013Yaw \uBD84\uD3EC (3D)" }), _jsx("div", { style: fullPlotBoxStyle, children: _jsx(Plot, { data: plotData, layout: plotLayout, useResizeHandler: true, style: fullPlotStyle, config: { responsive: true } }) }), _jsx(Title, { level: 5, style: { marginTop: '2rem' }, children: " \uC790\uC138\uBCC4 \uC2A4\uB9C8\uD2B8\uD3F0 \uBC15\uC2A4 \uC2DC\uAC01\uD654 (3D)" }), _jsx("div", { style: fullPlotBoxStyle, children: _jsx(Plot, { data: boxData, layout: boxLayout, useResizeHandler: true, style: fullPlotStyle, config: { responsive: true } }) }), _jsx("div", { style: { marginTop: '2rem', textAlign: 'center' }, children: _jsx(ExportMeshModifierButton, { kFile: kFile, kFileName: kFile?.name || 'UNKNOWN.k', optionFileGenerator: () => generateDropAttitudeOptionFile(kFile?.name || 'UNKNOWN.k', tableData, options), optionFileName: "drop_attitude.txt", solver: "MeshModifier", mode: "DropAttitude", buttonLabel: "\uD83D\uDD01 \uD574\uC11D \uC2E4\uD589 (Mesh Modifier)" }) })] }) }) }));
};
export default DropAttitudeGenerator;
