import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useMemo, useRef, useState } from "react";
import { Button, Card, Divider, Flex, Input, InputNumber, Modal, Radio, Select, Space, Switch, Table, Tag, Typography, Upload, message } from "antd";
import { DeleteOutlined, InboxOutlined, PlayCircleOutlined, PlusOutlined, SaveOutlined, UploadOutlined } from "@ant-design/icons";
const { Dragger } = Upload;
const { Title, Text } = Typography;
// Helper for ids (no external dep)
let idCounter = 0;
const uid = (prefix = "row") => `${prefix}_${Date.now()}_${idCounter++}`;
const ANALYSIS_OPTIONS = [
    { label: "전각도 다물체동역학 낙하", value: "fullAngleMBD", hint: "PyBullet/Chrono 등 MBD 기반" },
    { label: "전각도 낙하", value: "fullAngle", hint: "Explicit FE 단발/배치" },
    { label: "전각도 누적 낙하", value: "fullAngleCumulative", hint: "DOE(행) × 회수(열) 매트릭스" },
    { label: "전위치 부분 충격", value: "partialImpact", hint: "배면 XY 격자 포인트 충격" },
];
// Direction option sets
const FACE_DIRS = Array.from({ length: 6 }, (_, i) => `F${i + 1}`);
const EDGE_DIRS = Array.from({ length: 12 }, (_, i) => `E${i + 1}`);
const CORNER_DIRS = Array.from({ length: 8 }, (_, i) => `C${i + 1}`);
const ALL_DIRS = [...FACE_DIRS, ...EDGE_DIRS, ...CORNER_DIRS]; // 26개
const SURFACE_OPTIONS = [
    { label: "철판(steel plate)", value: "steelPlate" },
    { label: "보도블럭(paving block)", value: "pavingBlock" },
    { label: "콘크리트(concrete)", value: "concrete" },
    { label: "목재(wood)", value: "wood" },
];
const dirLabel = (d) => d.startsWith("F") ? `면 ${d.substring(1)}` : d.startsWith("E") ? `엣지 ${d.substring(1)}` : `코너 ${d.substring(1)}`;
const analysisLabel = (row) => {
    if (row.analysisType === "fullAngle") {
        if (row.params?.angleSource === "usePrevResult")
            return "전각도 누적 낙하";
        return "전각도 낙하";
    }
    if (row.analysisType === "fullAngleCumulative")
        return "전각도 누적 낙하";
    if (row.analysisType === "fullAngleMBD")
        return "전각도 다물체동역학 낙하";
    return "전위치 부분 충격";
};
// Predefined counts
const MBD_COUNTS = [1000, 5000, 10000, 50000, 100000, 200000, 500000, 1000000, 2000000, 5000000];
const FULL_ANGLE_COUNTS = [10, 50, 100, 200, 300, 400, 500, 600, 800, 1000];
const DOE_COUNTS = [1, 2, 3, 5, 10, 20, 30, 50, 100, 200, 300, 500, 1000];
const bytesToString = async (f) => new Promise((res, rej) => {
    const reader = new FileReader();
    reader.onload = () => res(String(reader.result || ""));
    reader.onerror = rej;
    reader.readAsText(f);
});
// LHS sampling for angle variations
const generateLHSVariations = (count, maxTolerance) => {
    if (maxTolerance <= 0)
        return new Array(count).fill(0);
    const variations = [];
    for (let i = 0; i < count; i++) {
        // LHS sampling: divide range into equal intervals and sample randomly within each
        const interval = (2 * maxTolerance) / count; // -maxTolerance to +maxTolerance
        const base = -maxTolerance + i * interval;
        const random = Math.random() * interval;
        variations.push(base + random);
    }
    // Shuffle to avoid correlation with order
    for (let i = variations.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [variations[i], variations[j]] = [variations[j], variations[i]];
    }
    return variations;
};
// 다양한 각도 조합 기본값 생성 (repeatCount 길이에 맞춰 최대 다양성). 행 내 중복 허용.
const diverseDefaultDirs = (n) => {
    if (n <= 0)
        return [];
    const seq = [];
    const pools = [FACE_DIRS, EDGE_DIRS, CORNER_DIRS];
    let pi = 0, idx = 0;
    while (seq.length < n) {
        const pool = pools[pi % pools.length];
        seq.push(pool[idx % pool.length]);
        pi++;
        if (pi % pools.length === 0)
            idx++;
    }
    return seq;
};
const rotate = (arr, k) => arr.map((_, i) => arr[(i + k) % arr.length]);
const rowsEqual = (a, b) => a.length === b.length && a.every((v, i) => v === b[i]);
const nextDir = (d, step = 1) => ALL_DIRS[(ALL_DIRS.indexOf(d) + step) % ALL_DIRS.length];
// 한 행이 기존 행들과 완전히 동일하지 않도록 보정 (행 내 중복은 허용)
const ensureRowUnique = (row, existing) => {
    let candidate = row.slice();
    const repeat = candidate.length;
    if (!existing.some(ex => rowsEqual(ex, candidate)))
        return candidate;
    const maxAttempts = ALL_DIRS.length * Math.max(1, repeat);
    for (let t = 0; t < maxAttempts; t++) {
        const pos = t % repeat;
        const shift = Math.floor(t / repeat) + 1;
        candidate[pos] = nextDir(candidate[pos], shift);
        if (!existing.some(ex => rowsEqual(ex, candidate)))
            return candidate;
    }
    return row.slice();
};
const dedupGrid = (grid) => {
    const out = [];
    for (const r of grid)
        out.push(ensureRowUnique(r, out));
    return out;
};
const warnIfDOEExceedsCapacity = (repeat, doe) => {
    const maxUnique = Math.pow(ALL_DIRS.length, repeat);
    if (doe > maxUnique) {
        message.warning(`DOE 수(${doe})가 가능한 고유 조합 수(${maxUnique.toLocaleString()})를 초과하여 일부 행이 동일할 수 있습니다.`);
    }
};
// DOE×회수 기본 매트릭스: 회전 기반 + 유니크 보정
const diverseDefaultGrid = (repeat, doe) => {
    warnIfDOEExceedsCapacity(repeat, doe);
    const base = diverseDefaultDirs(repeat);
    const grid = [];
    for (let r = 0; r < doe; r++) {
        const proposal = rotate(base, r % repeat);
        grid.push(ensureRowUnique(proposal, grid));
    }
    return grid;
};
const normalizeCum = (row) => {
    const repeat = (row.params?.cumRepeatCount ?? 3);
    const doe = (row.params?.cumDOECount ?? 5);
    let grid = row.params?.cumDirectionsGrid;
    if (!grid || !Array.isArray(grid) || grid.length !== doe || grid[0]?.length !== repeat) {
        const oneD = row.params?.cumDirections && row.params.cumDirections.length === repeat ? row.params.cumDirections : undefined;
        grid = diverseDefaultGrid(repeat, doe);
        if (oneD) {
            grid[0] = oneD;
            grid = dedupGrid(grid);
        }
    }
    return { repeat, doe, grid };
};
// ---- Tolerance controls ----
const renderToleranceControls = (row, setScenarios) => {
    const tolerance = row.params?.tolerance || { mode: "disabled" };
    const isEnabled = tolerance.mode === "enabled";
    return (_jsx(Card, { size: "small", style: { marginTop: 8 }, children: _jsxs(Flex, { vertical: true, gap: 8, children: [_jsxs(Flex, { align: "center", gap: 8, children: [_jsx(Text, { strong: true, children: "\uAC01\uB3C4 \uBCC0\uB3D9 \uD5C8\uC6A9" }), _jsx(Switch, { size: "small", checked: isEnabled, onChange: (checked) => setScenarios(prev => prev.map(r => r.id === row.id ? {
                                ...r,
                                params: {
                                    ...(r.params || {}),
                                    tolerance: {
                                        ...tolerance,
                                        mode: checked ? "enabled" : "disabled"
                                    }
                                }
                            } : r)) }), isEnabled && _jsx(Tag, { color: "blue", children: "\uD65C\uC131\uD654\uB428" })] }), isEnabled && (_jsxs(Space, { wrap: true, size: 16, children: [_jsxs(Space, { size: 8, children: [_jsx(Text, { children: "\uBA74 (6\uAC1C)" }), _jsx(InputNumber, { size: "small", min: 0, max: 180, step: 1, value: tolerance.faceTolerance || 0, addonAfter: "\u00B0", style: { width: 80 }, onChange: (v) => setScenarios(prev => prev.map(r => r.id === row.id ? {
                                        ...r,
                                        params: {
                                            ...(r.params || {}),
                                            tolerance: {
                                                ...tolerance,
                                                faceTolerance: Number(v || 0)
                                            }
                                        }
                                    } : r)) })] }), _jsxs(Space, { size: 8, children: [_jsx(Text, { children: "\uC5E3\uC9C0 (12\uAC1C)" }), _jsx(InputNumber, { size: "small", min: 0, max: 180, step: 1, value: tolerance.edgeTolerance || 0, addonAfter: "\u00B0", style: { width: 80 }, onChange: (v) => setScenarios(prev => prev.map(r => r.id === row.id ? {
                                        ...r,
                                        params: {
                                            ...(r.params || {}),
                                            tolerance: {
                                                ...tolerance,
                                                edgeTolerance: Number(v || 0)
                                            }
                                        }
                                    } : r)) })] }), _jsxs(Space, { size: 8, children: [_jsx(Text, { children: "\uCF54\uB108 (8\uAC1C)" }), _jsx(InputNumber, { size: "small", min: 0, max: 180, step: 1, value: tolerance.cornerTolerance || 0, addonAfter: "\u00B0", style: { width: 80 }, onChange: (v) => setScenarios(prev => prev.map(r => r.id === row.id ? {
                                        ...r,
                                        params: {
                                            ...(r.params || {}),
                                            tolerance: {
                                                ...tolerance,
                                                cornerTolerance: Number(v || 0)
                                            }
                                        }
                                    } : r)) })] })] })), isEnabled && (_jsx(Text, { type: "secondary", style: { fontSize: 12 }, children: "\u2022 \uAC01 \uBC29\uD5A5\uBCC4\uB85C \uCD5C\uB300 \uBCC0\uB3D9\uB7C9(\uB3C4)\uC744 \uC124\uC815\uD558\uBA74 LHS \uC0D8\uD50C\uB9C1\uC73C\uB85C \uC2E4\uC81C \uAC01\uB3C4\uAC00 \uC0DD\uC131\uB429\uB2C8\uB2E4 \u2022 \uBCC0\uB3D9 \uBC94\uC704: -\uCD5C\uB300\uAC12 ~ +\uCD5C\uB300\uAC12 (\uC608: 5\u00B0 \uC124\uC815 \uC2DC -5\u00B0 ~ +5\u00B0)" }))] }) }));
};
// ---- Shared controls (Height & Surface) ----
const renderCommonDropControls = (row, setScenarios) => {
    const p = row.params || {};
    const heightMode = p.heightMode ?? "const";
    const heightConst = p.heightConst ?? 1.0;
    const heightMin = p.heightMin ?? 0.5;
    const heightMax = p.heightMax ?? 1.5;
    const surface = p.surface ?? "steelPlate";
    return (_jsxs(Space, { size: 8, wrap: true, children: [_jsx(Text, { children: "\uB192\uC774" }), _jsxs(Radio.Group, { size: "small", value: heightMode, onChange: (e) => setScenarios(prev => prev.map(r => r.id === row.id ? { ...r, params: { ...(r.params || {}), heightMode: e.target.value } } : r)), children: [_jsx(Radio, { value: "const", children: "\uACE0\uC815\uAC12" }), _jsx(Radio, { value: "lhs", children: "LHS" })] }), heightMode === "const" ? (_jsx(Space, { size: 4, children: _jsx(InputNumber, { size: "small", min: 0.01, step: 0.05, value: heightConst, addonAfter: "m", onChange: (v) => setScenarios(prev => prev.map(r => r.id === row.id ? { ...r, params: { ...(r.params || {}), heightConst: Number(v ?? 1.0) } } : r)) }) })) : (_jsxs(Space, { size: 4, children: [_jsx(Text, { type: "secondary", children: "min" }), _jsx(InputNumber, { size: "small", min: 0.01, step: 0.05, value: heightMin, addonAfter: "m", onChange: (v) => setScenarios(prev => prev.map(r => r.id === row.id ? { ...r, params: { ...(r.params || {}), heightMin: Number(v ?? 0.5) } } : r)) }), _jsx(Text, { type: "secondary", children: "max" }), _jsx(InputNumber, { size: "small", min: 0.01, step: 0.05, value: heightMax, addonAfter: "m", onChange: (v) => setScenarios(prev => prev.map(r => r.id === row.id ? { ...r, params: { ...(r.params || {}), heightMax: Number(v ?? 1.5) } } : r)) })] })), _jsx(Divider, { type: "vertical" }), _jsx(Text, { children: "\uD45C\uBA74" }), _jsx(Select, { size: "small", style: { width: 180 }, value: surface, options: SURFACE_OPTIONS, onChange: (v) => setScenarios(prev => prev.map(r => r.id === row.id ? { ...r, params: { ...(r.params || {}), surface: v } } : r)) })] }));
};
// ---- Component ----
const SimulationAutomationComponent = () => {
    const [scenarios, setScenarios] = useState([]);
    const [selectedRowKeys, setSelectedRowKeys] = useState([]);
    const [bulkType, setBulkType] = useState();
    const kFileBufferRef = useRef([]);
    const objFileBufferRef = useRef([]);
    const selectedSingleRow = () => {
        if (selectedRowKeys.length === 1) {
            return scenarios.find(s => s.id === selectedRowKeys[0]);
        }
        return undefined;
    };
    // OBJ uploader (MBD용)
    const uploadPropsOBJ = {
        name: "obj",
        multiple: true,
        accept: ".obj",
        beforeUpload: (file) => { objFileBufferRef.current.push(file); return false; },
        onChange: () => {
            const sel = selectedSingleRow();
            if (objFileBufferRef.current.length === 0)
                return;
            if (sel) {
                const f = objFileBufferRef.current[objFileBufferRef.current.length - 1];
                setScenarios(prev => prev.map(r => r.id === sel.id ? { ...r, objFileName: f.name, objFile: f, analysisType: r.analysisType === "partialImpact" ? "fullAngleMBD" : r.analysisType } : r));
                message.success(`선택한 시나리오에 OBJ(${f.name})를 연결했습니다.`);
            }
            else {
                const newRows = objFileBufferRef.current.map((f) => ({
                    id: uid("scn"),
                    name: f.name.replace(/\.obj$/i, ""),
                    objFileName: f.name,
                    objFile: f,
                    analysisType: "fullAngleMBD",
                    params: { mbdCount: 1000, angleSource: "lhs", heightMode: "const", heightConst: 1.0, heightMin: 0.5, heightMax: 1.5, surface: "steelPlate", tolerance: { mode: "disabled" } },
                }));
                setScenarios(prev => [...prev, ...newRows]);
                message.success(`${newRows.length}개 OBJ 파일을 시나리오로 추가했습니다.`);
            }
            objFileBufferRef.current = [];
        },
        itemRender: () => null,
    };
    // K uploader — 선택된 1개 행이 있으면 그 행에 붙이고, 없으면 새 시나리오 생성
    const uploadPropsK = {
        name: "file",
        multiple: true,
        accept: ".k,.key,.dyn,k",
        beforeUpload: (file) => { kFileBufferRef.current.push(file); return false; },
        onChange: () => {
            if (kFileBufferRef.current.length === 0)
                return;
            const sel = selectedSingleRow();
            if (sel) {
                const f = kFileBufferRef.current[kFileBufferRef.current.length - 1];
                setScenarios(prev => prev.map(r => r.id === sel.id ? { ...r, fileName: f.name, file: f, analysisType: r.analysisType === "partialImpact" ? "fullAngle" : r.analysisType } : r));
                message.success(`선택한 시나리오에 K(${f.name})를 연결했습니다.`);
            }
            else {
                const newRows = kFileBufferRef.current.map((f) => ({
                    id: uid("scn"),
                    name: f.name.replace(/\.(k|key|dyn)$/i, ""),
                    fileName: f.name,
                    file: f,
                    analysisType: "fullAngle",
                    params: { faTotal: 100, includeFace6: true, includeEdge12: true, includeCorner8: true, angleSource: "lhs", heightMode: "const", heightConst: 1.0, heightMin: 0.5, heightMax: 1.5, surface: "steelPlate", tolerance: { mode: "disabled" } },
                }));
                setScenarios(prev => [...prev, ...newRows]);
                message.success(`${newRows.length}개 K 파일을 시나리오로 추가했습니다.`);
            }
            kFileBufferRef.current = [];
        },
        itemRender: () => null,
    };
    const makeAnglesUploadProps = (row) => ({
        name: "angles",
        multiple: false,
        accept: ".json,.csv",
        beforeUpload: async (file) => {
            try {
                const content = await bytesToString(file);
                if (!content.trim()) {
                    message.error("빈 파일입니다.");
                    return Upload.LIST_IGNORE;
                }
                setScenarios(prev => prev.map(r => r.id === row.id ? {
                    ...r,
                    params: { ...(r.params || {}), angleSource: "usePrevResult", angleSourceFileName: file.name, angleSourceFile: file },
                } : r));
                message.success(`${file.name} 각도 소스로 설정됨`);
            }
            catch {
                message.error("파일 읽기 실패");
                return Upload.LIST_IGNORE;
            }
            return false;
        },
        itemRender: () => null,
    });
    // Build dropdown options using scenarios above current row
    const priorMbdOptions = (row) => {
        const idx = scenarios.findIndex(s => s.id === row.id);
        const prior = scenarios.slice(0, idx).filter(s => s.analysisType === "fullAngleMBD");
        return prior.map(s => ({ label: `[MBD] ${s.name} • ${s.params?.mbdCount?.toLocaleString?.() ?? "?"}개`, value: s.id }));
    };
    const priorFaOptions = (row) => {
        const idx = scenarios.findIndex(s => s.id === row.id);
        const prior = scenarios.slice(0, idx).filter(s => s.analysisType === "fullAngle" || s.analysisType === "fullAngleCumulative");
        return prior.map(s => ({ label: `[FA] ${s.name} • ${s.params?.faTotal ?? s.params?.cumRepeatCount ?? "?"}`, value: s.id }));
    };
    // ---- 누적 낙하 전용 컨트롤: DOE(행) x 회수(열) 매트릭스 ----
    const renderCumControls = (row) => {
        const { repeat, doe, grid } = normalizeCum(row);
        const dirOptions = ALL_DIRS.map(d => ({ label: `${dirLabel(d)} (${d})`, value: d }));
        const setRepeat = (v) => {
            setScenarios(prev => prev.map(r => {
                if (r.id !== row.id)
                    return r;
                const old = normalizeCum(r);
                const newGrid = old.grid.map(rw => {
                    const base = rw.length ? rw : diverseDefaultDirs(old.repeat);
                    const resized = v <= base.length ? base.slice(0, v) : [...base, ...diverseDefaultDirs(v - base.length)];
                    return resized;
                });
                const deduped = dedupGrid(newGrid);
                warnIfDOEExceedsCapacity(v, old.doe);
                return { ...r, params: { ...(r.params || {}), cumRepeatCount: v, cumDOECount: old.doe, cumDirectionsGrid: deduped } };
            }));
        };
        const setDOE = (v) => {
            setScenarios(prev => prev.map(r => {
                if (r.id !== row.id)
                    return r;
                const old = normalizeCum(r);
                warnIfDOEExceedsCapacity(old.repeat, v);
                let newGrid = old.grid.slice(0, v);
                if (v > old.grid.length) {
                    const toAdd = v - old.grid.length;
                    for (let i = 0; i < toAdd; i++) {
                        const proposal = rotate(old.grid[0], (old.grid.length + i) % old.repeat);
                        newGrid.push(ensureRowUnique(proposal, newGrid));
                    }
                }
                newGrid = dedupGrid(newGrid);
                return { ...r, params: { ...(r.params || {}), cumRepeatCount: old.repeat, cumDOECount: v, cumDirectionsGrid: newGrid } };
            }));
        };
        const setCell = (ri, ci, val) => {
            setScenarios(prev => prev.map(r => {
                if (r.id !== row.id)
                    return r;
                const old = normalizeCum(r);
                const newGrid = old.grid.map((rw, i) => i === ri ? rw.map((cv, j) => j === ci ? val : cv) : rw);
                const deduped = dedupGrid(newGrid);
                return { ...r, params: { ...(r.params || {}), cumRepeatCount: old.repeat, cumDOECount: old.doe, cumDirectionsGrid: deduped } };
            }));
        };
        const handleAuto = () => {
            warnIfDOEExceedsCapacity(repeat, doe);
            const auto = diverseDefaultGrid(repeat, doe);
            setScenarios(prev => prev.map(r => r.id === row.id ? { ...r, params: { ...(r.params || {}), cumRepeatCount: repeat, cumDOECount: doe, cumDirectionsGrid: auto } } : r));
            message.success("DOE×회수 매트릭스를 다양한 조합(행 유니크)으로 자동 채움");
        };
        // Build matrix table — 상단 정렬 + 타이트 패딩 + 고정 폭 레이아웃
        const vtopCell = { style: { verticalAlign: "top", padding: "4px 6px" } };
        const matrixColumns = [
            { title: "DOE #", dataIndex: "__idx", width: 64, onCell: () => vtopCell },
            ...Array.from({ length: repeat }).map((_, c) => ({
                title: `낙하 #${c + 1}`,
                dataIndex: `c${c}`,
                width: 140,
                onCell: () => vtopCell,
                render: (_, rec) => (_jsx(Select, { size: "small", style: { width: 120 }, dropdownMatchSelectWidth: false, value: rec[`c${c}`], options: dirOptions, onChange: (v) => setCell(rec.__rowIndex, c, v), showSearch: true, optionFilterProp: "label" }))
            }))
        ];
        const matrixData = Array.from({ length: doe }).map((_, rIdx) => {
            const rowObj = { key: rIdx, __idx: `#${rIdx + 1}`, __rowIndex: rIdx };
            for (let c = 0; c < repeat; c++)
                rowObj[`c${c}`] = grid[rIdx][c];
            return rowObj;
        });
        return (_jsxs(Flex, { vertical: true, gap: 10, children: [renderCommonDropControls(row, setScenarios), renderToleranceControls(row, setScenarios), _jsx("style", { children: `
          .doe-matrix .ant-table-tbody > tr > td { vertical-align: top; padding: 4px 6px; }
          .doe-matrix .ant-select-selector { padding: 0 6px !important; }
        ` }), _jsxs(Space, { wrap: true, align: "center", children: [_jsx(Text, { children: "\uD68C\uC218(\uC5F4)" }), _jsx(Select, { style: { width: 120 }, value: repeat, options: [2, 3, 4, 5].map(v => ({ label: `${v}회`, value: v })), onChange: (v) => setRepeat(v) }), _jsx(Divider, { type: "vertical" }), _jsx(Text, { children: "DOE \uC218(\uD589)" }), _jsx(Select, { style: { width: 160 }, value: doe, options: DOE_COUNTS.map(v => ({ label: `${v}`, value: v })), onChange: (v) => setDOE(v) }), _jsx(Button, { size: "small", onClick: handleAuto, children: "\uC790\uB3D9 \uBD84\uD3EC" }), _jsx(Tag, { color: "geekblue", children: analysisLabel(row) })] }), _jsx("div", { className: "doe-matrix", style: { overflowX: "hidden" }, children: _jsx(Table, { size: "small", pagination: false, columns: matrixColumns, dataSource: matrixData, rowClassName: () => "tight-vtop", style: { tableLayout: "fixed" } }) })] }));
    };
    const renderOptionControls = (row) => {
        // ---- fullAngleCumulative ----
        if (row.analysisType === "fullAngleCumulative") {
            return renderCumControls(row);
        }
        // ---- fullAngleMBD ----
        if (row.analysisType === "fullAngleMBD") {
            const value = row.params?.mbdCount ?? 1000;
            const angleSource = row.params?.angleSource ?? "lhs";
            const angleSourceId = row.params?.angleSourceId ?? "";
            const angleSourceFileName = row.params?.angleSourceFileName;
            return (_jsxs(Flex, { vertical: true, gap: 10, children: [_jsxs(Flex, { gap: 10, align: "center", wrap: true, style: { alignItems: "flex-start" }, children: [renderCommonDropControls(row, setScenarios), _jsx(Divider, { type: "vertical" }), _jsx(Text, { children: "\uC0D8\uD50C" }), _jsx(Select, { style: { width: 160 }, value: value, options: MBD_COUNTS.map(v => ({ label: v.toLocaleString(), value: v })), onChange: (v) => setScenarios(prev => prev.map(r => r.id === row.id ? { ...r, params: { ...(r.params || {}), mbdCount: v } } : r)), size: "small" }), _jsx(Divider, { type: "vertical" }), _jsx(Text, { children: "\uAC01\uB3C4 \uC120\uD0DD" }), _jsxs(Radio.Group, { size: "small", value: angleSource, onChange: (e) => setScenarios(prev => prev.map(r => r.id === row.id ? { ...r, params: { ...(r.params || {}), angleSource: e.target.value } } : r)), children: [_jsx(Radio, { value: "lhs", children: "LHS(\uAE30\uBCF8)" }), _jsx(Radio, { value: "fromMBD", children: "\uAE30\uC874 MBD \uACB0\uACFC \uC0AC\uC6A9" })] }), angleSource === "fromMBD" && (_jsxs(Space, { wrap: true, size: 8, children: [_jsx(Select, { style: { width: 260 }, placeholder: "\uC704(\uC774\uC804) MBD \uC2DC\uB098\uB9AC\uC624 \uC120\uD0DD", value: angleSourceId || undefined, options: priorMbdOptions(row), onChange: (v) => setScenarios(prev => prev.map(r => r.id === row.id ? { ...r, params: { ...(r.params || {}), angleSourceId: v } } : r)), disabled: priorMbdOptions(row).length === 0, size: "small", dropdownMatchSelectWidth: false }), _jsx(Upload, { ...makeAnglesUploadProps(row), children: _jsx(Button, { size: "small", icon: _jsx(UploadOutlined, {}), children: "\uAC01\uB3C4 \uD30C\uC77C(.json/.csv)" }) }), angleSourceFileName && _jsx(Tag, { color: "geekblue", children: angleSourceFileName })] })), _jsx(Tag, { children: analysisLabel(row) })] }), renderToleranceControls(row, setScenarios)] }));
        }
        // ---- fullAngle ----
        if (row.analysisType === "fullAngle") {
            const total = row.params?.faTotal ?? 100;
            const face = !!row.params?.includeFace6;
            const edge = !!row.params?.includeEdge12;
            const corner = !!row.params?.includeCorner8;
            const fixedShots = (face ? 6 : 0) + (edge ? 12 : 0) + (corner ? 8 : 0);
            const remaining = total - fixedShots;
            const angleSource = row.params?.angleSource ?? "lhs";
            const angleSourceId = row.params?.angleSourceId ?? "";
            const angleSourceFileName = row.params?.angleSourceFileName;
            const remainingTag = (_jsxs(Tag, { color: remaining < 0 ? "error" : remaining === 0 ? "warning" : undefined, children: ["\uB098\uBA38\uC9C0 \uC790\uB3D9 \uBC30\uCE58: ", remaining] }));
            return (_jsxs(Flex, { vertical: true, gap: 10, children: [_jsxs(Flex, { gap: 10, align: "center", wrap: true, style: { alignItems: "flex-start" }, children: [renderCommonDropControls(row, setScenarios), _jsx(Divider, { type: "vertical" }), _jsx(Text, { children: "\uCD1D \uAC1C\uC218" }), _jsx(Select, { style: { width: 120 }, value: total, options: FULL_ANGLE_COUNTS.map(v => ({ label: v.toString(), value: v })), onChange: (v) => setScenarios(prev => prev.map(r => r.id === row.id ? { ...r, params: { ...(r.params || {}), faTotal: v } } : r)), size: "small" }), _jsx(Divider, { type: "vertical" }), _jsxs(Space, { size: 8, wrap: true, children: [_jsxs("span", { children: [_jsx(Switch, { size: "small", checked: face, onChange: (val) => setScenarios(prev => prev.map(r => r.id === row.id ? { ...r, params: { ...(r.params || {}), includeFace6: val } } : r)) }), " \uBA74(+6)"] }), _jsxs("span", { children: [_jsx(Switch, { size: "small", checked: edge, onChange: (val) => setScenarios(prev => prev.map(r => r.id === row.id ? { ...r, params: { ...(r.params || {}), includeEdge12: val } } : r)) }), " \uC5E3\uC9C0(+12)"] }), _jsxs("span", { children: [_jsx(Switch, { size: "small", checked: corner, onChange: (val) => setScenarios(prev => prev.map(r => r.id === row.id ? { ...r, params: { ...(r.params || {}), includeCorner8: val } } : r)) }), " \uCF54\uB108(+8)"] })] }), remainingTag, _jsx(Divider, { type: "vertical" }), _jsx(Text, { children: "\uAC01\uB3C4 \uC120\uD0DD" }), _jsxs(Radio.Group, { size: "small", value: angleSource, onChange: (e) => setScenarios(prev => prev.map(r => r.id === row.id ? { ...r, params: { ...(r.params || {}), angleSource: e.target.value } } : r)), children: [_jsx(Radio, { value: "lhs", children: "LHS(\uAE30\uBCF8)" }), _jsx(Radio, { value: "fromMBD", children: "\uC774\uC804 MBD \uACB0\uACFC \uC0AC\uC6A9" }), _jsx(Radio, { value: "usePrevResult", children: "\uC774\uC804 \uB2E8\uACC4 \uD574\uC11D \uC0AC\uC6A9" })] }), (angleSource === "fromMBD" || angleSource === "usePrevResult") && (_jsxs(Space, { wrap: true, size: 8, children: [angleSource === "fromMBD" ? (_jsx(Select, { style: { width: 260 }, placeholder: "\uC704(\uC774\uC804) MBD \uC2DC\uB098\uB9AC\uC624 \uC120\uD0DD", value: angleSourceId || undefined, options: priorMbdOptions(row), onChange: (v) => setScenarios(prev => prev.map(r => r.id === row.id ? { ...r, params: { ...(r.params || {}), angleSourceId: v } } : r)), disabled: priorMbdOptions(row).length === 0, size: "small", dropdownMatchSelectWidth: false })) : (_jsx(Select, { style: { width: 260 }, placeholder: "\uC704(\uC774\uC804) \uC2DC\uB098\uB9AC\uC624 \uC120\uD0DD", value: angleSourceId || undefined, options: priorFaOptions(row), onChange: (v) => setScenarios(prev => prev.map(r => r.id === row.id ? { ...r, params: { ...(r.params || {}), angleSourceId: v } } : r)), disabled: priorFaOptions(row).length === 0, size: "small", dropdownMatchSelectWidth: false })), _jsx(Upload, { ...makeAnglesUploadProps(row), children: _jsx(Button, { size: "small", icon: _jsx(UploadOutlined, {}), children: "\uAC01\uB3C4 \uD30C\uC77C(.json/.csv)" }) }), angleSourceFileName && _jsx(Tag, { color: "geekblue", children: angleSourceFileName }), angleSource === "usePrevResult" && (_jsx(Tag, { color: "purple", children: "\uD45C\uC2DC\uBA85: \uC804\uAC01\uB3C4 \uB204\uC801 \uB099\uD558" }))] })), _jsx(Tag, { children: analysisLabel(row) })] }), renderToleranceControls(row, setScenarios)] }));
        }
        // ---- partialImpact ----
        const mode = row.params?.piMode ?? "default";
        const fileName = row.params?.piTxtName;
        const uploadPropsPI = {
            name: "txt",
            multiple: false,
            accept: ".txt",
            beforeUpload: async (file) => {
                try {
                    const content = await bytesToString(file);
                    if (!content.trim()) {
                        message.error("빈 txt 파일입니다.");
                        return Upload.LIST_IGNORE;
                    }
                    setScenarios(prev => prev.map(r => r.id === row.id ? { ...r, params: { ...(r.params || {}), piMode: "txt", piTxtName: file.name, piTxtFile: file } } : r));
                    message.success(`${file.name} 업로드됨`);
                }
                catch {
                    message.error("txt 읽기 실패");
                    return Upload.LIST_IGNORE;
                }
                return false;
            },
            itemRender: () => null,
        };
        return (_jsxs(Flex, { vertical: true, gap: 10, children: [_jsxs(Flex, { gap: 12, align: "center", wrap: true, style: { alignItems: "flex-start" }, children: [_jsxs(Radio.Group, { size: "small", value: mode, onChange: (e) => setScenarios(prev => prev.map(r => r.id === row.id ? { ...r, params: { ...(r.params || {}), piMode: e.target.value } } : r)), children: [_jsx(Radio, { value: "default", children: "default (\uC790\uB3D9 \uC120\uD0DD)" }), _jsx(Radio, { value: "txt", children: "txt \uC5C5\uB85C\uB4DC (\uD328\uD0A4\uC9C0 \uC774\uB984)" })] }), fileName && _jsx(Tag, { color: "geekblue", children: fileName })] }), renderToleranceControls(row, setScenarios)] }));
    };
    // Table columns (상단 정렬 적용)
    const topCell = { style: { verticalAlign: "top" } };
    const columns = useMemo(() => [
        {
            title: "시나리오",
            dataIndex: "name",
            key: "name",
            width: 320,
            onCell: () => topCell,
            render: (value, row) => (_jsxs(Flex, { vertical: true, children: [_jsx(Input, { size: "small", value: row.name, onChange: (e) => setScenarios(prev => prev.map(r => r.id === row.id ? { ...r, name: e.target.value } : r)), placeholder: "\uC2DC\uB098\uB9AC\uC624 \uC774\uB984", style: { maxWidth: 420 } }), _jsxs(Space, { size: 4, wrap: true, children: [_jsxs(Tag, { children: ["id: ", row.id] }), row.fileName && _jsxs(Tag, { color: "geekblue", children: ["K: ", row.fileName] }), row.objFileName && _jsxs(Tag, { color: "purple", children: ["OBJ: ", row.objFileName] })] })] })),
        },
        {
            title: "해석 항목",
            dataIndex: "analysisType",
            key: "analysisType",
            width: 260,
            onCell: () => topCell,
            render: (_, row) => (_jsx(Select, { style: { width: "100%" }, size: "small", value: row.analysisType, onChange: (v) => {
                    setScenarios((prev) => prev.map((r) => (r.id === row.id ? {
                        ...r,
                        analysisType: v,
                        params: v === "fullAngleMBD" ? { mbdCount: 1000, angleSource: "lhs", heightMode: "const", heightConst: 1.0, heightMin: 0.5, heightMax: 1.5, surface: "steelPlate", tolerance: { mode: "disabled" } } :
                            v === "fullAngle" ? { faTotal: 100, includeFace6: true, includeEdge12: true, includeCorner8: true, angleSource: "lhs", heightMode: "const", heightConst: 1.0, heightMin: 0.5, heightMax: 1.5, surface: "steelPlate", tolerance: { mode: "disabled" } } :
                                v === "fullAngleCumulative" ? { cumRepeatCount: 3, cumDOECount: 5, cumDirectionsGrid: diverseDefaultGrid(3, 5), heightMode: "const", heightConst: 1.0, heightMin: 0.5, heightMax: 1.5, surface: "steelPlate", tolerance: { mode: "disabled" } } :
                                    { piMode: "default", tolerance: { mode: "disabled" } },
                    } : r)));
                }, options: ANALYSIS_OPTIONS.map((o) => ({ label: (_jsxs(Flex, { justify: "space-between", gap: 8, children: [_jsx("span", { children: o.label }), _jsx(Text, { type: "secondary", style: { fontSize: 12 }, children: o.hint })] })), value: o.value })) })),
        },
        {
            title: "옵션",
            key: "options",
            onCell: () => topCell,
            render: (_, row) => renderOptionControls(row),
        },
        {
            title: "액션",
            key: "actions",
            fixed: "right",
            width: 120,
            onCell: () => topCell,
            render: (_, row) => (_jsxs(Space, { children: [_jsx(Button, { size: "small", icon: _jsx(PlayCircleOutlined, {}), type: "primary", onClick: () => handleRun([row.id]), children: "\uC2E4\uD589" }), _jsx(Button, { size: "small", icon: _jsx(DeleteOutlined, {}), danger: true, onClick: () => handleDelete(row.id) })] })),
        },
    ], [scenarios]);
    const rowSelection = { selectedRowKeys, onChange: (keys) => setSelectedRowKeys(keys) };
    // Actions
    const handleAddEmpty = () => {
        setScenarios((prev) => ([
            ...prev,
            { id: uid("scn"), name: "새 시나리오", analysisType: "fullAngleMBD", params: { mbdCount: 1000, angleSource: "lhs", heightMode: "const", heightConst: 1.0, heightMin: 0.5, heightMax: 1.5, surface: "steelPlate", tolerance: { mode: "disabled" } } },
        ]));
    };
    const handleDelete = (id) => {
        setScenarios((prev) => prev.filter((r) => r.id !== id));
        setSelectedRowKeys((prev) => prev.filter((k) => k !== id));
    };
    const handleBulkSetType = () => {
        if (!bulkType)
            return message.warning("먼저 상단 드롭다운에서 해석 항목을 선택하세요.");
        if (!selectedRowKeys.length)
            return message.warning("변경할 시나리오를 선택하세요.");
        setScenarios((prev) => prev.map((r) => selectedRowKeys.includes(r.id) ? ({
            ...r,
            analysisType: bulkType,
            params: bulkType === "fullAngleMBD" ? { mbdCount: 1000, angleSource: "lhs", heightMode: "const", heightConst: 1.0, heightMin: 0.5, heightMax: 1.5, surface: "steelPlate", tolerance: { mode: "disabled" } } :
                bulkType === "fullAngle" ? { faTotal: 100, includeFace6: true, includeEdge12: true, includeCorner8: true, angleSource: "lhs", heightMode: "const", heightConst: 1.0, heightMin: 0.5, heightMax: 1.5, surface: "steelPlate", tolerance: { mode: "disabled" } } :
                    bulkType === "fullAngleCumulative" ? { cumRepeatCount: 3, cumDOECount: 5, cumDirectionsGrid: diverseDefaultGrid(3, 5), heightMode: "const", heightConst: 1.0, heightMin: 0.5, heightMax: 1.5, surface: "steelPlate", tolerance: { mode: "disabled" } } :
                        { piMode: "default", tolerance: { mode: "disabled" } },
        }) : r));
        message.success(`선택한 ${selectedRowKeys.length}개 시나리오에 적용했습니다.`);
    };
    const handleRun = (ids) => {
        const runIds = (ids && ids.length ? ids : selectedRowKeys);
        if (!runIds.length)
            return message.info("실행할 시나리오를 선택하세요.");
        const payload = scenarios.filter((s) => runIds.includes(s.id)).map((s) => ({
            id: s.id,
            name: s.name,
            analysisType: s.analysisType,
            analysisLabel: analysisLabel(s),
            fileName: s.fileName,
            objFileName: s.objFileName,
            params: s.params ?? {},
        }));
        Modal.confirm({
            title: "시뮬레이션 실행",
            content: (_jsxs("div", { children: [_jsx("p", { children: `${payload.length}개 시나리오를 실행합니다.` }), _jsx("pre", { style: { maxHeight: 240, overflow: "auto", background: "#0b1021", color: "#e6e6e6", padding: 12, borderRadius: 8 }, children: JSON.stringify(payload, null, 2) })] })),
            onOk: async () => {
                // await api.post("/api/submit/dyna/jobs", payload)
                await new Promise((r) => setTimeout(r, 600));
                message.success("작업 큐에 제출했습니다.");
            },
        });
    };
    const handleExport = () => {
        const blob = new Blob([JSON.stringify(scenarios, null, 2)], { type: "application/json" });
        const url = URL.createObjectURL(blob);
        const a = document.createElement("a");
        a.href = url;
        a.download = `scenarios_${new Date().toISOString().replace(/[:.]/g, "-")}.json`;
        a.click();
        URL.revokeObjectURL(url);
    };
    const handleImport = async (e) => {
        const file = e.target.files?.[0];
        if (!file)
            return;
        try {
            const text = await file.text();
            const data = JSON.parse(text);
            if (!Array.isArray(data))
                throw new Error("Invalid format");
            const safe = data.map((d) => ({
                id: d.id || uid("scn"),
                name: d.name || "Imported",
                fileName: d.fileName,
                analysisType: (ANALYSIS_OPTIONS.some(o => o.value === d.analysisType) ? d.analysisType : "fullAngleMBD"),
                params: d.params ?? {},
            }));
            setScenarios(safe);
            message.success("시나리오를 불러왔습니다.");
        }
        catch (err) {
            console.error(err);
            message.error("불러오기 실패: JSON 형식을 확인하세요.");
        }
        finally {
            e.currentTarget.value = "";
        }
    };
    return (_jsxs(Flex, { vertical: true, gap: 16, className: "p-4", children: [_jsx(Title, { level: 3, style: { margin: 0 }, children: "Simulation Automation" }), _jsx(Text, { type: "secondary", children: "TypeScript + Vite + React + Ant Design \u00B7 OBJ/K \uB4DC\uB798\uADF8&\uB4DC\uB86D \u00B7 \uC0C1\uB2E8\uC815\uB82C UI \u00B7 \uB192\uC774/\uD45C\uBA74 \uACF5\uD1B5 \uC635\uC158 \u00B7 \uB204\uC801 \uB099\uD558 DOE\u00D7\uD68C\uC218 \uB9E4\uD2B8\uB9AD\uC2A4 \u00B7 \uAC01\uB3C4 \uBCC0\uB3D9 \uD5C8\uC6A9 (\uBA74/\uC5E3\uC9C0/\uCF54\uB108)" }), _jsxs(Card, { bodyStyle: { padding: 0 }, children: [_jsxs(Dragger, { ...uploadPropsOBJ, style: { padding: 20 }, children: [_jsx("p", { className: "ant-upload-drag-icon", children: _jsx(InboxOutlined, {}) }), _jsxs("p", { className: "ant-upload-text", children: ["\uC5EC\uAE30\uB85C ", _jsx("b", { children: ".obj" }), " \uD30C\uC77C\uC744 \uB04C\uC5B4\uC624\uAC70\uB098 \uD074\uB9AD\uD558\uC5EC \uC120\uD0DD (MBD)"] }), _jsx("p", { className: "ant-upload-hint", children: "\uC120\uD0DD\uD55C 1\uAC1C \uD589\uC774 \uC788\uC73C\uBA74 \uADF8 \uD589\uC5D0 \uC5F0\uACB0, \uC5C6\uC73C\uBA74 \uC0C8 \uC2DC\uB098\uB9AC\uC624 \uC0DD\uC131" })] }), _jsx(Divider, { style: { margin: 0 } }), _jsxs(Dragger, { ...uploadPropsK, style: { padding: 20 }, children: [_jsx("p", { className: "ant-upload-drag-icon", children: _jsx(InboxOutlined, {}) }), _jsxs("p", { className: "ant-upload-text", children: ["\uC5EC\uAE30\uB85C ", _jsx("b", { children: ".k/.key/.dyn" }), " \uD30C\uC77C\uC744 \uB04C\uC5B4\uC624\uAC70\uB098 \uD074\uB9AD\uD558\uC5EC \uC120\uD0DD (FE)"] }), _jsx("p", { className: "ant-upload-hint", children: "\uC120\uD0DD\uD55C 1\uAC1C \uD589\uC774 \uC788\uC73C\uBA74 \uADF8 \uD589\uC5D0 \uC5F0\uACB0, \uC5C6\uC73C\uBA74 \uC0C8 \uC2DC\uB098\uB9AC\uC624 \uC0DD\uC131" })] })] }), _jsxs(Card, { children: [_jsxs(Flex, { gap: 8, wrap: true, align: "center", justify: "space-between", style: { marginBottom: 12 }, children: [_jsxs(Space, { wrap: true, children: [_jsx(Button, { type: "dashed", icon: _jsx(PlusOutlined, {}), onClick: handleAddEmpty, children: "\uBE48 \uC2DC\uB098\uB9AC\uC624 \uCD94\uAC00" }), _jsx(Select, { style: { width: 300 }, placeholder: "\uC120\uD0DD\uD55C \uC2DC\uB098\uB9AC\uC624\uC5D0 \uC77C\uAD04 \uC801\uC6A9\uD560 \uD574\uC11D \uD56D\uBAA9", value: bulkType, onChange: setBulkType, options: ANALYSIS_OPTIONS.map(o => ({ label: o.label, value: o.value })), size: "small" }), _jsx(Button, { size: "small", onClick: handleBulkSetType, children: "\uC77C\uAD04 \uC801\uC6A9" }), _jsx(Divider, { type: "vertical" }), _jsx(Button, { size: "small", icon: _jsx(PlayCircleOutlined, {}), type: "primary", onClick: () => handleRun(), children: "\uC120\uD0DD \uC2E4\uD589" })] }), _jsxs(Space, { wrap: true, children: [_jsxs("label", { children: [_jsx("input", { type: "file", accept: "application/json", onChange: handleImport, style: { display: "none" }, id: "scenario-import" }), _jsx(Button, { size: "small", icon: _jsx(UploadOutlined, {}), onClick: () => document.getElementById("scenario-import")?.click(), children: "\uBD88\uB7EC\uC624\uAE30" })] }), _jsx(Button, { size: "small", icon: _jsx(SaveOutlined, {}), onClick: handleExport, children: "\uB0B4\uBCF4\uB0B4\uAE30" })] })] }), _jsx(Table, { rowKey: "id", size: "small", rowSelection: rowSelection, columns: columns, dataSource: scenarios, pagination: { pageSize: 10, showSizeChanger: true }, locale: { emptyText: "상단 드래거로 OBJ 또는 K 파일을 추가하세요." }, style: { tableLayout: "fixed" } })] }), _jsx(Card, { size: "small", children: _jsxs(Text, { type: "secondary", children: ["\u2022 \uBAA8\uB4E0 \uC804\uAC01\uB3C4 \uD574\uC11D(MBD/FA/\uB204\uC801)\uC5D0\uC11C \uACF5\uD1B5\uC73C\uB85C ", _jsx("b", { children: "\uB099\uD558 \uB192\uC774(\uACE0\uC815\uAC12 \uB610\uB294 LHS \uBC94\uC704)" }), "\uC640 ", _jsx("b", { children: "\uB099\uD558 \uD45C\uBA74(\uCCA0\uD310/\uBCF4\uB3C4\uBE14\uB7ED/\uCF58\uD06C\uB9AC\uD2B8/\uBAA9\uC7AC)" }), "\uC744 \uC815\uC758\uD569\uB2C8\uB2E4.", _jsx("br", {}), "\u2022 \uB192\uC774 \uBAA8\uB4DC\uAC00 LHS\uC77C \uB54C\uB294 ", _jsx("b", { children: "min/max" }), "\uB97C \uC9C0\uC815\uD569\uB2C8\uB2E4(\uB2E8\uC704: m).", _jsx("br", {}), "\u2022 \uB204\uC801 \uB9E4\uD2B8\uB9AD\uC2A4\uB294 ", _jsx("b", { children: "\uD0C0\uC774\uD2B8 \uD328\uB529 + \uACE0\uC815 \uD3ED" }), "\uC73C\uB85C \uD45C\uC2DC\uD558\uBA70, \uD589 \uAC04 \uC644\uC804 \uB3D9\uC77C \uC870\uD569\uC744 \uBC29\uC9C0\uD569\uB2C8\uB2E4(\uD589 \uB0B4 \uC911\uBCF5 \uD5C8\uC6A9).", _jsx("br", {}), "\u2022 \"\uAE30\uC874 \uACB0\uACFC \uC0AC\uC6A9\"\uC740 \uD604\uC7AC \uD589 ", _jsx("b", { children: "\uC704\uCABD" }), " \uC2DC\uB098\uB9AC\uC624\uB9CC \uB4DC\uB86D\uB2E4\uC6B4\uC73C\uB85C \uD45C\uC2DC\uD569\uB2C8\uB2E4.", _jsx("br", {}), "\u2022 ", _jsx("b", { children: "\uAC01\uB3C4 \uBCC0\uB3D9 \uD5C8\uC6A9" }), "\uC744 \uD65C\uC131\uD654\uD558\uBA74 \uBA74(6\uAC1C), \uC5E3\uC9C0(12\uAC1C), \uCF54\uB108(8\uAC1C)\uBCC4\uB85C \uCD5C\uB300 \uBCC0\uB3D9\uB7C9\uC744 \uC124\uC815\uD560 \uC218 \uC788\uC73C\uBA70, LHS \uC0D8\uD50C\uB9C1\uC73C\uB85C \uC2E4\uC81C \uAC01\uB3C4\uAC00 \uC0DD\uC131\uB429\uB2C8\uB2E4."] }) })] }));
};
export default SimulationAutomationComponent;
