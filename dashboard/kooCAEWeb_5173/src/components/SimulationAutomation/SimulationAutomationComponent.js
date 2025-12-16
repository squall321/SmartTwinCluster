import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useMemo, useRef, useState } from "react";
import { Button, Card, Divider, Flex, Input, InputNumber, Modal, Radio, Select, Space, Switch, Table, Tag, Typography, Upload, message } from "antd";
import { DeleteOutlined, InboxOutlined, PlayCircleOutlined, PlusOutlined, SaveOutlined, UploadOutlined } from "@ant-design/icons";
import StandardScenarioModal from "./StandardScenarioModal";
const { Dragger } = Upload;
const { Title, Text } = Typography;
// Helper for ids (no external dep)
let idCounter = 0;
const uid = (prefix = "row") => `${prefix}_${Date.now()}_${idCounter++}`;
const ANALYSIS_OPTIONS = [
    { label: "전각도 다물체동역학 낙하", value: "fullAngleMBD", hint: "PyBullet/Chrono 등 MBD 기반" },
    { label: "전각도 낙하", value: "fullAngle", hint: "Explicit FE 단발/배치" },
    { label: "전각도 누적 낙하", value: "fullAngleCumulative", hint: "DOE(행) × 회수(열) 매트릭스" },
    { label: "다회 누적 낙하", value: "multiRepeatCumulative", hint: "DOE 없이 회수만 지정" },
    { label: "낙하 중량 충격", value: "dropWeightImpact", hint: "패키지 위치별 Ball/Cylinder 충격" },
    { label: "사전 정의 낙하 자세", value: "predefinedAttitudes", hint: "6면/12엣지/8코너 조합" },
    { label: "엣지 축 회전", value: "edgeAxisRotation", hint: "엣지 기준 회전 각도 분할" },
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
const DEFAULT_DESCRIPTIONS = {
    "fullAngleMBD": "다물체 동역학을 고려한 전각도 낙하 시험. 다양한 각도에서의 충격 시뮬레이션을 수행합니다.",
    "fullAngle": "전각도 낙하 시험. 주요 각도에서의 충격 특성을 평가합니다.",
    "fullAngleCumulative": "전각도 누적 낙하 시험. 반복 충격에 대한 내구성을 평가합니다.",
    "multiRepeatCumulative": "여러 방향에서의 다회 누적 낙하 시험. 다양한 각도에서의 반복 충격 내구성을 종합 평가합니다.",
    "dropWeightImpact": "낙하 중량 충격 시험. 다양한 중량의 낙하물에 대한 충격 저항성을 평가합니다.",
    "predefinedAttitudes": "사전 정의 낙하 자세 시험. 실제 사고 시나리오를 반영한 다양한 자세에서의 충격 특성을 평가합니다.",
    "edgeAxisRotation": "엣지 축 회전 충격 시험. 회전 충격에 대한 저항성과 안정성을 평가합니다.",
};
const dirLabel = (d) => d.startsWith("F") ? `면 ${d.substring(1)}` : d.startsWith("E") ? `엣지 ${d.substring(1)}` : `코너 ${d.substring(1)}`;
const analysisLabel = (row) => {
    if (row.analysisType === "fullAngle") {
        if (row.params?.angleSource === "usePrevResult")
            return "전각도 누적 낙하";
        return "전각도 낙하";
    }
    if (row.analysisType === "fullAngleCumulative")
        return "전각도 누적 낙하";
    if (row.analysisType === "multiRepeatCumulative")
        return "다회 누적 낙하";
    if (row.analysisType === "fullAngleMBD")
        return "전각도 다물체동역학 낙하";
    if (row.analysisType === "dropWeightImpact")
        return "낙하 중량 충격";
    if (row.analysisType === "predefinedAttitudes")
        return "사전 정의 낙하 자세";
    if (row.analysisType === "edgeAxisRotation")
        return "엣지 축 회전";
    return "알 수 없는 해석 타입";
};
// Predefined counts
const MBD_COUNTS = [1000, 5000, 10000, 50000, 100000, 200000, 500000, 1000000, 2000000, 5000000];
const FULL_ANGLE_COUNTS = [10, 50, 100, 200, 300, 400, 500, 600, 800, 1000];
const DOE_COUNTS = [1, 2, 3, 5, 10, 20, 30, 50, 100, 200, 300, 500, 1000];
// Generate evenly spaced grid coordinates
const generateGridLocations = (rows, cols, applyEdgeMargin = false) => {
    const locations = [];
    for (let r = 0; r < rows; r++) {
        for (let c = 0; c < cols; c++) {
            let x, y;
            if (applyEdgeMargin) {
                // Apply edge margin: spacing/2 from edges
                const xSpacing = cols === 1 ? 0 : 100 / (cols - 1);
                const ySpacing = rows === 1 ? 0 : 100 / (rows - 1);
                const xMargin = xSpacing / 2;
                const yMargin = ySpacing / 2;
                if (cols === 1) {
                    x = 50; // Center if only one column
                }
                else {
                    // Map [0, cols-1] to [xMargin, 100-xMargin]
                    x = xMargin + (c / (cols - 1)) * (100 - 2 * xMargin);
                }
                if (rows === 1) {
                    y = 50; // Center if only one row
                }
                else {
                    // Map [0, rows-1] to [yMargin, 100-yMargin]
                    y = yMargin + (r / (rows - 1)) * (100 - 2 * yMargin);
                }
            }
            else {
                // Original behavior: 0% to 100%
                x = cols === 1 ? 50 : (c / (cols - 1)) * 100;
                y = rows === 1 ? 50 : (r / (rows - 1)) * 100;
            }
            locations.push({ x: Math.round(x * 10) / 10, y: Math.round(y * 10) / 10 });
        }
    }
    return locations;
};
// Calculate grid dimensions from sample count
const calculateGridDimensions = (sampleCount) => {
    const cols = Math.floor(Math.sqrt(sampleCount));
    const rows = Math.ceil(sampleCount / cols);
    return { rows, cols };
};
// Predefined drop attitudes (Roll, Pitch, Yaw) - based on DropAttitudeGenerator.tsx
// Coordinate system: Display facing +Z, origin at bottom center of device
const FACE_ATTITUDES = [
    [0, 0, 0], // 전면 (Front - display)
    [180, 0, 0], // 배면 (Back)
    [90, 0, 0], // 좌측면 (Left side)
    [-90, 0, 0], // 우측면 (Right side)
    [0, -90, 0], // 상단 (Top)
    [0, 90, 0], // 하단 (Bottom)
];
const EDGE_ATTITUDES = [
    [-45, 0, 0], // 엣지 1
    [45, 0, 0], // 엣지 2
    [0, -45, 0], // 엣지 3
    [0, 45, 0], // 엣지 4
    [0, 0, -45], // 엣지 5
    [0, 0, 45], // 엣지 6
    [45, 45, 0], // 엣지 7
    [-45, -45, 0], // 엣지 8
    [0, 45, 45], // 엣지 9
    [0, -45, -45], // 엣지 10
    [45, 0, 45], // 엣지 11
    [-45, 0, -45], // 엣지 12
];
const CORNER_ATTITUDES = [
    [-35.264, 45, 0], // 코너 1
    [35.264, 45, 0], // 코너 2
    [-35.264, -45, 0], // 코너 3
    [35.264, -45, 0], // 코너 4
    [-35.264, 45, 180], // 코너 5
    [35.264, 45, 180], // 코너 6
    [-35.264, -45, 180], // 코너 7
    [35.264, -45, 180], // 코너 8
];
// Impact grid options
const IMPACT_GRID_OPTIONS = [
    { label: "1×1 (중앙)", value: "1x1" },
    { label: "2×1 (가로 2열)", value: "2x1" },
    { label: "1×2 (세로 2열)", value: "1x2" },
    { label: "3×1 (가로 3열)", value: "3x1" },
    { label: "1×3 (세로 3열)", value: "1x3" },
    { label: "3×3 (9포인트)", value: "3x3" },
];
// Edge axis options
const EDGE_AXIS_OPTIONS = [
    { label: "상단 엣지", value: "top" },
    { label: "하단 엣지", value: "bottom" },
    { label: "좌측 엣지", value: "left" },
    { label: "우측 엣지", value: "right" },
];
// Edge divisions (number of rotation angles)
const EDGE_DIVISION_COUNTS = [4, 6, 8, 12, 16, 24, 36, 48, 72];
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
// ---- Helper functions for new analysis types ----
// Generate attitudes for predefined modes
const generatePredefinedAttitudes = (mode) => {
    switch (mode) {
        case "faces6":
            return FACE_ATTITUDES;
        case "edges12":
            return EDGE_ATTITUDES;
        case "corners8":
            return CORNER_ATTITUDES;
        case "all26":
            return [...FACE_ATTITUDES, ...EDGE_ATTITUDES, ...CORNER_ATTITUDES];
        default:
            return FACE_ATTITUDES;
    }
};
// Generate edge rotation attitudes
const generateEdgeRotationAttitudes = (axis, divisions) => {
    const attitudes = [];
    const angleStep = 360 / divisions;
    for (let i = 0; i < divisions; i++) {
        const angle = i * angleStep;
        // Rotation axis depends on edge selection
        switch (axis) {
            case "top":
                // Rotate around top edge (Y-axis at top)
                attitudes.push([0, -90, angle]);
                break;
            case "bottom":
                // Rotate around bottom edge (Y-axis at bottom)
                attitudes.push([0, 90, angle]);
                break;
            case "left":
                // Rotate around left edge (X-axis at left)
                attitudes.push([90, 0, angle]);
                break;
            case "right":
                // Rotate around right edge (X-axis at right)
                attitudes.push([-90, 0, angle]);
                break;
        }
    }
    return attitudes;
};
// Wildcard pattern matching for package names
const matchesPackagePattern = (packageName, pattern) => {
    // Convert wildcard pattern to regex
    // Escape special regex characters except *
    const regexPattern = pattern
        .split('*')
        .map(part => part.replace(/[.+?^${}()|[\]\\]/g, '\\$&'))
        .join('.*');
    const regex = new RegExp(`^${regexPattern}$`, 'i'); // case-insensitive
    return regex.test(packageName);
};
// Check if package matches any of the patterns
const matchesAnyPattern = (packageName, patterns) => {
    return patterns.some(pattern => matchesPackagePattern(packageName, pattern));
};
// Generate grid coordinates based on mode
const generateGridCoordinates = (mode) => {
    const coords = [];
    // Parse grid mode (e.g., "3x3" -> cols=3, rows=3)
    const [colsStr, rowsStr] = mode.split('x');
    const cols = parseInt(colsStr, 10);
    const rows = parseInt(rowsStr, 10);
    // Generate evenly distributed grid points (percentage: 0-100)
    for (let row = 0; row < rows; row++) {
        for (let col = 0; col < cols; col++) {
            const x = cols === 1 ? 50 : (col / (cols - 1)) * 100;
            const y = rows === 1 ? 50 : (row / (rows - 1)) * 100;
            coords.push({ x, y });
        }
    }
    return coords;
};
// Generate random LHS coordinates
const generateLHSCoordinates = (count) => {
    const coords = [];
    // LHS sampling for X
    const xSamples = generateLHSVariations(count, 50).map(v => v + 50); // -50~50 -> 0~100
    // LHS sampling for Y
    const ySamples = generateLHSVariations(count, 50).map(v => v + 50); // -50~50 -> 0~100
    for (let i = 0; i < count; i++) {
        coords.push({ x: xSamples[i], y: ySamples[i] });
    }
    return coords;
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
// ---- UI Controls for new analysis types ----
// 1. Predefined Attitudes Controls
const renderPredefinedAttitudesControls = (row, setScenarios) => {
    const p = row.params || {};
    const predefinedMode = p.predefinedMode ?? "all26";
    const defaultAttitudes = generatePredefinedAttitudes(predefinedMode);
    // Initialize custom angles if not present
    const customAngles = p.predefinedAngles || defaultAttitudes.map((att, idx) => ({
        name: `자세 ${idx + 1}`,
        phi: att[0],
        theta: att[1],
        psi: att[2]
    }));
    const updateAngle = (index, field, value) => {
        setScenarios(prev => prev.map(r => {
            if (r.id !== row.id)
                return r;
            const newAngles = [...customAngles];
            if (field === 'name') {
                newAngles[index] = { ...newAngles[index], name: value };
            }
            else {
                newAngles[index] = { ...newAngles[index], [field]: Number(value) || 0 };
            }
            return { ...r, params: { ...(r.params || {}), predefinedAngles: newAngles } };
        }));
    };
    const addAngle = () => {
        setScenarios(prev => prev.map(r => {
            if (r.id !== row.id)
                return r;
            const newAngles = [...customAngles, { name: `자세 ${customAngles.length + 1}`, phi: 0, theta: 0, psi: 0 }];
            return { ...r, params: { ...(r.params || {}), predefinedAngles: newAngles } };
        }));
    };
    const removeAngle = (index) => {
        if (customAngles.length <= 1) {
            message.warning('최소 1개의 자세는 필요합니다.');
            return;
        }
        setScenarios(prev => prev.map(r => {
            if (r.id !== row.id)
                return r;
            const newAngles = customAngles.filter((_, i) => i !== index);
            return { ...r, params: { ...(r.params || {}), predefinedAngles: newAngles } };
        }));
    };
    const resetToDefault = () => {
        const resetAngles = defaultAttitudes.map((att, idx) => ({
            name: `자세 ${idx + 1}`,
            phi: att[0],
            theta: att[1],
            psi: att[2]
        }));
        setScenarios(prev => prev.map(r => r.id === row.id ? { ...r, params: { ...(r.params || {}), predefinedAngles: resetAngles } } : r));
    };
    const angleColumns = [
        { title: '#', dataIndex: 'index', width: 50, render: (_, __, idx) => idx + 1 },
        {
            title: '자세 이름',
            dataIndex: 'name',
            width: 180,
            render: (val, _, idx) => (_jsx(Input, { size: "small", value: val, onChange: (e) => updateAngle(idx, 'name', e.target.value), placeholder: "\uC790\uC138 \uC774\uB984" }))
        },
        {
            title: 'φ (Roll, °)',
            dataIndex: 'phi',
            width: 120,
            render: (val, _, idx) => (_jsx(InputNumber, { size: "small", value: val, onChange: (v) => updateAngle(idx, 'phi', v ?? 0), style: { width: '100%' }, step: 1 }))
        },
        {
            title: 'θ (Pitch, °)',
            dataIndex: 'theta',
            width: 120,
            render: (val, _, idx) => (_jsx(InputNumber, { size: "small", value: val, onChange: (v) => updateAngle(idx, 'theta', v ?? 0), style: { width: '100%' }, step: 1 }))
        },
        {
            title: 'ψ (Yaw, °)',
            dataIndex: 'psi',
            width: 120,
            render: (val, _, idx) => (_jsx(InputNumber, { size: "small", value: val, onChange: (v) => updateAngle(idx, 'psi', v ?? 0), style: { width: '100%' }, step: 1 }))
        },
        {
            title: '액션',
            width: 80,
            render: (_, __, idx) => (_jsx(Button, { size: "small", danger: true, icon: _jsx(DeleteOutlined, {}), onClick: () => removeAngle(idx) }))
        }
    ];
    return (_jsxs(Flex, { vertical: true, gap: 10, children: [renderCommonDropControls(row, setScenarios), _jsx(Divider, {}), _jsxs(Space, { size: 8, wrap: true, align: "center", children: [_jsx(Text, { strong: true, children: "\uB099\uD558 \uC790\uC138 \uC120\uD0DD" }), _jsxs(Radio.Group, { size: "small", value: predefinedMode, onChange: (e) => {
                            const newMode = e.target.value;
                            const newAttitudes = generatePredefinedAttitudes(newMode);
                            const resetAngles = newAttitudes.map((att, idx) => ({
                                name: `자세 ${idx + 1}`,
                                phi: att[0],
                                theta: att[1],
                                psi: att[2]
                            }));
                            setScenarios(prev => prev.map(r => r.id === row.id ? { ...r, params: { ...(r.params || {}), predefinedMode: newMode, predefinedAngles: resetAngles } } : r));
                        }, children: [_jsx(Radio, { value: "faces6", children: "6\uBA74 (6\uAC1C)" }), _jsx(Radio, { value: "edges12", children: "12\uC5E3\uC9C0 (12\uAC1C)" }), _jsx(Radio, { value: "corners8", children: "8\uCF54\uB108 (8\uAC1C)" }), _jsx(Radio, { value: "all26", children: "\uC804\uCCB4 (26\uAC1C)" })] }), _jsxs(Tag, { color: "blue", children: ["\uCD1D ", customAngles.length, "\uAC1C \uC790\uC138"] }), _jsx(Button, { size: "small", onClick: resetToDefault, children: "\uAE30\uBCF8\uAC12 \uBCF5\uC6D0" })] }), _jsx(Card, { size: "small", style: { backgroundColor: '#fafafa' }, children: _jsxs(Flex, { vertical: true, gap: 8, children: [_jsxs(Flex, { justify: "space-between", align: "center", children: [_jsx(Text, { strong: true, children: "\uB099\uD558 \uC790\uC138 \uAC01\uB3C4 (\uC624\uC77C\uB7EC \uAC01\uB3C4)" }), _jsx(Button, { size: "small", type: "dashed", icon: _jsx(PlusOutlined, {}), onClick: addAngle, children: "\uC790\uC138 \uCD94\uAC00" })] }), _jsx("div", { style: { overflowX: 'auto', maxHeight: '400px' }, children: _jsx(Table, { size: "small", pagination: false, columns: angleColumns, dataSource: customAngles, rowKey: (_, idx) => idx, bordered: true }) }), _jsx(Text, { type: "secondary", style: { fontSize: 12 }, children: "\u2022 \u03C6 (Roll): X\uCD95 \uD68C\uC804, \u03B8 (Pitch): Y\uCD95 \uD68C\uC804, \u03C8 (Yaw): Z\uCD95 \uD68C\uC804 (\uB2E8\uC704: \uB3C4)" })] }) }), renderToleranceControls(row, setScenarios)] }));
};
// 2. Edge Axis Rotation Controls
const renderEdgeAxisRotationControls = (row, setScenarios) => {
    const p = row.params || {};
    const edgeAxis = p.edgeAxis ?? "top";
    const edgeDivisions = p.edgeDivisions ?? 12;
    const attitudes = generateEdgeRotationAttitudes(edgeAxis, edgeDivisions);
    return (_jsxs(Flex, { vertical: true, gap: 10, children: [renderCommonDropControls(row, setScenarios), _jsx(Divider, {}), _jsxs(Space, { size: 8, wrap: true, align: "center", children: [_jsx(Text, { strong: true, children: "\uD68C\uC804 \uC5E3\uC9C0 \uC120\uD0DD" }), _jsx(Select, { size: "small", style: { width: 140 }, value: edgeAxis, options: EDGE_AXIS_OPTIONS, onChange: (v) => setScenarios(prev => prev.map(r => r.id === row.id ? { ...r, params: { ...(r.params || {}), edgeAxis: v } } : r)) }), _jsx(Divider, { type: "vertical" }), _jsx(Text, { strong: true, children: "\uBD84\uD560 \uC218" }), _jsx(Select, { size: "small", style: { width: 100 }, value: edgeDivisions, options: EDGE_DIVISION_COUNTS.map(v => ({ label: `${v}등분`, value: v })), onChange: (v) => setScenarios(prev => prev.map(r => r.id === row.id ? { ...r, params: { ...(r.params || {}), edgeDivisions: v } } : r)) }), _jsxs(Tag, { color: "blue", children: ["\uCD1D ", attitudes.length, "\uAC1C \uAC01\uB3C4"] })] }), renderToleranceControls(row, setScenarios)] }));
};
// 3. Drop Weight Impact Controls
const renderDropWeightImpactControls = (row, setScenarios) => {
    const p = row.params || {};
    const packagePatterns = p.impactPackagePatterns ?? ["*pkg*"];
    const locationMode = p.impactLocationMode ?? "grid";
    const gridMode = p.impactGridMode ?? "3x3";
    const percentageX = p.impactPercentageX ?? 50;
    const percentageY = p.impactPercentageY ?? 50;
    const randomCount = p.impactRandomCount ?? 10;
    const impactorType = p.impactorType ?? "ball";
    const ballDiameter = p.impactorBallDiameter ?? 6;
    const cylinderDiameter = p.impactorCylinderDiameter ?? 8;
    const cylinderDiameterCustom = p.impactorCylinderDiameterCustom ?? 10;
    const updateParams = (updates) => {
        setScenarios(prev => prev.map(r => r.id === row.id ? { ...r, params: { ...(r.params || {}), ...updates } } : r));
    };
    return (_jsxs(Flex, { vertical: true, gap: 10, children: [_jsx(Card, { size: "small", style: { backgroundColor: '#f5f5f5' }, children: _jsxs(Flex, { vertical: true, gap: 8, children: [_jsx(Text, { strong: true, children: "\uD328\uD0A4\uC9C0 \uD328\uD134 (\uC27C\uD45C\uB85C \uAD6C\uBD84, *\uB294 \uC640\uC77C\uB4DC\uCE74\uB4DC)" }), _jsx(Input, { size: "small", placeholder: "\uC608: *pkg*, display, camera*", value: packagePatterns.join(', '), onChange: (e) => {
                                const patterns = e.target.value.split(',').map(s => s.trim()).filter(s => s.length > 0);
                                updateParams({ impactPackagePatterns: patterns.length > 0 ? patterns : ["*pkg*"] });
                            } }), _jsxs(Text, { type: "secondary", style: { fontSize: 12 }, children: ["\uD604\uC7AC \uD328\uD134: ", packagePatterns.map(p => `"${p}"`).join(', ')] })] }) }), _jsx(Card, { size: "small", style: { backgroundColor: '#f5f5f5' }, children: _jsxs(Flex, { vertical: true, gap: 8, children: [_jsx(Text, { strong: true, children: "\uCDA9\uACA9 \uC704\uCE58 \uBAA8\uB4DC" }), _jsxs(Radio.Group, { size: "small", value: locationMode, onChange: (e) => updateParams({ impactLocationMode: e.target.value }), children: [_jsx(Radio, { value: "grid", children: "\uACA9\uC790 (Grid)" }), _jsx(Radio, { value: "percentage", children: "\uC88C\uD45C \uC9C0\uC815 (%)" }), _jsx(Radio, { value: "random", children: "\uB79C\uB364 (LHS)" })] }), locationMode === "grid" && (_jsxs(Space, { size: 8, children: [_jsx(Text, { children: "\uACA9\uC790 \uBAA8\uB4DC" }), _jsx(Select, { size: "small", style: { width: 160 }, value: gridMode, options: IMPACT_GRID_OPTIONS, onChange: (v) => updateParams({ impactGridMode: v }) }), _jsxs(Tag, { color: "green", children: [generateGridCoordinates(gridMode).length, "\uAC1C \uD3EC\uC778\uD2B8"] })] })), locationMode === "percentage" && (() => {
                            // Initialize locations if not present
                            const locations = p.impactLocations || [];
                            const rows = p.impactGridRows || 3;
                            const cols = p.impactGridCols || 3;
                            const packageWidth = p.impactPackageWidth || 100;
                            const packageHeight = p.impactPackageHeight || 100;
                            const applyEdgeMargin = p.applyEdgeMargin ?? false;
                            const sampleCount = rows * cols;
                            // Auto-generate if empty
                            if (locations.length === 0) {
                                const newLocations = generateGridLocations(rows, cols, applyEdgeMargin);
                                updateParams({
                                    impactLocations: newLocations,
                                    impactGridRows: rows,
                                    impactGridCols: cols,
                                    applyEdgeMargin: applyEdgeMargin,
                                    impactPackageWidth: packageWidth,
                                    impactPackageHeight: packageHeight
                                });
                                return _jsx(Text, { type: "secondary", children: "\uCD08\uAE30\uD654 \uC911..." });
                            }
                            const updateGridCell = (rowIdx, colIdx, field, value) => {
                                const flatIndex = rowIdx * cols + colIdx;
                                const newLocations = [...locations];
                                if (flatIndex < newLocations.length) {
                                    newLocations[flatIndex] = { ...newLocations[flatIndex], [field]: value };
                                    updateParams({ impactLocations: newLocations });
                                }
                            };
                            const regenerateGrid = (newRows, newCols, newApplyEdgeMargin) => {
                                const useMargin = newApplyEdgeMargin ?? applyEdgeMargin;
                                const newLocations = generateGridLocations(newRows, newCols, useMargin);
                                updateParams({ impactLocations: newLocations, impactGridRows: newRows, impactGridCols: newCols, applyEdgeMargin: useMargin });
                            };
                            const updateSampleCount = (count) => {
                                const { rows: newRows, cols: newCols } = calculateGridDimensions(count);
                                regenerateGrid(newRows, newCols);
                            };
                            // SVG visualization settings
                            const svgWidth = 400;
                            const aspectRatio = packageHeight / packageWidth;
                            const svgHeight = svgWidth * aspectRatio;
                            const padding = 20;
                            const rectWidth = svgWidth - 2 * padding;
                            const rectHeight = svgHeight - 2 * padding;
                            return (_jsx(Card, { size: "small", style: { backgroundColor: '#fff', marginTop: 8 }, children: _jsxs(Flex, { vertical: true, gap: 12, children: [_jsxs(Flex, { gap: 8, wrap: true, align: "center", children: [_jsx(Text, { strong: true, children: "\uC0D8\uD50C \uC218" }), _jsx(InputNumber, { size: "small", value: sampleCount, onChange: (v) => updateSampleCount(v ?? 9), min: 1, max: 1000, style: { width: 100 } }), _jsx(Text, { type: "secondary", children: "\u2192" }), _jsx(Text, { strong: true, children: "\uAC00\uB85C" }), _jsx(InputNumber, { size: "small", value: cols, onChange: (v) => regenerateGrid(rows, v ?? 3), min: 1, max: 100, style: { width: 80 } }), _jsx(Text, { strong: true, children: "\uC138\uB85C" }), _jsx(InputNumber, { size: "small", value: rows, onChange: (v) => regenerateGrid(v ?? 3, cols), min: 1, max: 100, style: { width: 80 } }), _jsx(Divider, { type: "vertical" }), _jsxs(Space, { size: "small", children: [_jsx(Switch, { size: "small", checked: applyEdgeMargin, onChange: (checked) => regenerateGrid(rows, cols, checked) }), _jsx(Text, { strong: true, children: "\uC678\uACFD \uB9C8\uC9C4 \uC801\uC6A9" }), _jsx(Text, { type: "secondary", style: { fontSize: 11 }, children: "(\uAC04\uACA9/2)" })] }), _jsx(Divider, { type: "vertical" }), _jsx(Text, { strong: true, children: "\uD328\uD0A4\uC9C0 \uAC00\uB85C(mm)" }), _jsx(InputNumber, { size: "small", value: packageWidth, onChange: (v) => updateParams({ impactPackageWidth: v ?? 100 }), min: 1, max: 10000, style: { width: 100 } }), _jsx(Text, { strong: true, children: "\uC138\uB85C(mm)" }), _jsx(InputNumber, { size: "small", value: packageHeight, onChange: (v) => updateParams({ impactPackageHeight: v ?? 100 }), min: 1, max: 10000, style: { width: 100 } })] }), _jsxs(Flex, { gap: 16, wrap: true, children: [_jsxs("div", { style: { flex: '0 0 auto' }, children: [_jsx(Text, { strong: true, style: { display: 'block', marginBottom: 8 }, children: "\uC88C\uD45C \uC785\uB825 (X%, Y%)" }), _jsx("table", { style: {
                                                                borderCollapse: 'collapse',
                                                                border: '1px solid #d9d9d9',
                                                                fontSize: '12px'
                                                            }, children: _jsx("tbody", { children: Array.from({ length: rows }).map((_, rowIdx) => (_jsx("tr", { children: Array.from({ length: cols }).map((_, colIdx) => {
                                                                        const flatIndex = rowIdx * cols + colIdx;
                                                                        const loc = locations[flatIndex] || { x: 0, y: 0 };
                                                                        return (_jsx("td", { style: {
                                                                                border: '1px solid #d9d9d9',
                                                                                padding: '4px',
                                                                                backgroundColor: '#fafafa'
                                                                            }, children: _jsxs(Flex, { vertical: true, gap: 2, children: [_jsx(InputNumber, { size: "small", value: loc.x, onChange: (v) => updateGridCell(rowIdx, colIdx, 'x', v ?? 0), min: 0, max: 100, step: 0.1, placeholder: "X%", style: { width: 70 } }), _jsx(InputNumber, { size: "small", value: loc.y, onChange: (v) => updateGridCell(rowIdx, colIdx, 'y', v ?? 0), min: 0, max: 100, step: 0.1, placeholder: "Y%", style: { width: 70 } })] }) }, colIdx));
                                                                    }) }, rowIdx))) }) })] }), _jsxs("div", { style: { flex: '1 1 auto' }, children: [_jsxs(Text, { strong: true, style: { display: 'block', marginBottom: 8 }, children: ["\uC2DC\uAC01\uD654 (", packageWidth, "mm \u00D7 ", packageHeight, "mm)"] }), _jsxs("svg", { width: svgWidth, height: svgHeight, style: { border: '1px solid #d9d9d9' }, children: [_jsx("rect", { x: padding, y: padding, width: rectWidth, height: rectHeight, fill: "#f0f0f0", stroke: "#999", strokeWidth: "2" }), Array.from({ length: cols + 1 }).map((_, i) => (_jsx("line", { x1: padding + (i / cols) * rectWidth, y1: padding, x2: padding + (i / cols) * rectWidth, y2: padding + rectHeight, stroke: "#ddd", strokeWidth: "1" }, `v${i}`))), Array.from({ length: rows + 1 }).map((_, i) => (_jsx("line", { x1: padding, y1: padding + (i / rows) * rectHeight, x2: padding + rectWidth, y2: padding + (i / rows) * rectHeight, stroke: "#ddd", strokeWidth: "1" }, `h${i}`))), locations.map((loc, idx) => {
                                                                    const x = padding + (loc.x / 100) * rectWidth;
                                                                    const y = padding + (loc.y / 100) * rectHeight;
                                                                    return (_jsxs("g", { children: [_jsx("circle", { cx: x, cy: y, r: "4", fill: "red", stroke: "darkred", strokeWidth: "1" }), _jsx("text", { x: x, y: y - 8, textAnchor: "middle", fontSize: "10", fill: "#333", children: idx + 1 })] }, idx));
                                                                })] })] })] }), _jsxs(Text, { type: "secondary", style: { fontSize: 11 }, children: ["\u2022 \uADF8\uB9AC\uB4DC \uD14C\uC774\uBE14\uC5D0\uC11C \uAC01 \uC140\uC758 X%, Y% \uC88C\uD45C\uB97C \uC9C1\uC811 \uC785\uB825", _jsx("br", {}), "\u2022 \uC6B0\uCE21 \uC2DC\uAC01\uD654\uC5D0\uC11C \uBE68\uAC04 \uC810\uC73C\uB85C \uCDA9\uACA9 \uC704\uCE58 \uD655\uC778", _jsx("br", {}), "\u2022 \uD328\uD0A4\uC9C0 \uD06C\uAE30\uB97C \uC785\uB825\uD558\uBA74 \uC2DC\uAC01\uD654 \uBE44\uC728\uC774 \uC790\uB3D9 \uC870\uC815\uB428"] })] }) }));
                        })(), locationMode === "random" && (_jsxs(Space, { size: 8, children: [_jsx(Text, { children: "\uC0D8\uD50C \uAC1C\uC218" }), _jsx(InputNumber, { size: "small", min: 1, max: 1000, step: 1, value: randomCount, style: { width: 100 }, onChange: (v) => updateParams({ impactRandomCount: Number(v ?? 10) }) }), _jsxs(Tag, { color: "orange", children: [randomCount, "\uAC1C LHS \uC0D8\uD50C"] })] }))] }) }), _jsx(Card, { size: "small", style: { backgroundColor: '#f5f5f5' }, children: _jsxs(Flex, { vertical: true, gap: 8, children: [_jsx(Text, { strong: true, children: "\uCDA9\uACA9\uCCB4 \uD0C0\uC785" }), _jsxs(Radio.Group, { size: "small", value: impactorType, onChange: (e) => updateParams({ impactorType: e.target.value }), children: [_jsx(Radio, { value: "ball", children: "Ball" }), _jsx(Radio, { value: "cylinder", children: "Cylinder" })] }), impactorType === "ball" && (_jsxs(Space, { size: 8, children: [_jsx(Text, { children: "Ball \uC9C0\uB984" }), _jsx(InputNumber, { size: "small", min: 1, max: 50, step: 0.5, value: ballDiameter, addonAfter: "mm", style: { width: 100 }, onChange: (v) => updateParams({ impactorBallDiameter: Number(v ?? 6) }) }), _jsx(Tag, { color: "blue", children: "\uAE30\uBCF8: 6mm" })] })), impactorType === "cylinder" && (_jsxs(Flex, { vertical: true, gap: 8, children: [_jsxs(Space, { size: 8, children: [_jsx(Text, { children: "Cylinder \uC9C0\uB984" }), _jsxs(Radio.Group, { size: "small", value: typeof cylinderDiameter === 'number' && cylinderDiameter !== 8 && cylinderDiameter !== 15 ? "custom" : cylinderDiameter, onChange: (e) => {
                                                const val = e.target.value;
                                                if (val === "custom") {
                                                    updateParams({ impactorCylinderDiameter: "custom" });
                                                }
                                                else {
                                                    updateParams({ impactorCylinderDiameter: val });
                                                }
                                            }, children: [_jsx(Radio, { value: 8, children: "8mm" }), _jsx(Radio, { value: 15, children: "15mm" }), _jsx(Radio, { value: "custom", children: "\uC0AC\uC6A9\uC790 \uC815\uC758" })] })] }), (cylinderDiameter === "custom" || (typeof cylinderDiameter === 'number' && cylinderDiameter !== 8 && cylinderDiameter !== 15)) && (_jsxs(Space, { size: 8, children: [_jsx(Text, { children: "\uC9C0\uB984 \uC785\uB825" }), _jsx(InputNumber, { size: "small", min: 1, max: 100, step: 0.5, value: cylinderDiameterCustom, addonAfter: "mm", style: { width: 110 }, onChange: (v) => updateParams({ impactorCylinderDiameterCustom: Number(v ?? 10) }) })] }))] }))] }) }), renderToleranceControls(row, setScenarios)] }));
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
    const [standardModalVisible, setStandardModalVisible] = useState(false);
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
                setScenarios(prev => prev.map(r => r.id === sel.id ? { ...r, objFileName: f.name, objFile: f, analysisType: r.analysisType === "dropWeightImpact" ? "fullAngleMBD" : r.analysisType } : r));
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
                setScenarios(prev => prev.map(r => r.id === sel.id ? { ...r, fileName: f.name, file: f, analysisType: r.analysisType === "dropWeightImpact" ? "fullAngle" : r.analysisType } : r));
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
    // ---- 다회 누적 낙하 전용 컨트롤: 회수만 지정 (DOE 없음) ----
    const renderMultiRepeatControls = (row) => {
        const p = row.params || {};
        const repeat = p.multiRepeatCount ?? 24;
        const directions = p.multiRepeatDirections ?? diverseDefaultDirs(repeat);
        // 유효성 검사
        const validDirections = Array.isArray(directions) && directions.length === repeat
            ? directions
            : diverseDefaultDirs(repeat);
        const dirOptions = ALL_DIRS.map(d => ({ label: `${dirLabel(d)} (${d})`, value: d }));
        const setRepeat = (v) => {
            setScenarios(prev => prev.map(r => {
                if (r.id !== row.id)
                    return r;
                const oldDirs = r.params?.multiRepeatDirections ?? diverseDefaultDirs(repeat);
                const newDirs = v <= oldDirs.length
                    ? oldDirs.slice(0, v)
                    : [...oldDirs, ...diverseDefaultDirs(v - oldDirs.length)];
                return {
                    ...r,
                    params: {
                        ...(r.params || {}),
                        multiRepeatCount: v,
                        multiRepeatDirections: newDirs
                    }
                };
            }));
        };
        const setCell = (ci, val) => {
            setScenarios(prev => prev.map(r => {
                if (r.id !== row.id)
                    return r;
                const oldDirs = r.params?.multiRepeatDirections ?? diverseDefaultDirs(repeat);
                const newDirs = oldDirs.map((cv, j) => j === ci ? val : cv);
                return {
                    ...r,
                    params: {
                        ...(r.params || {}),
                        multiRepeatDirections: newDirs
                    }
                };
            }));
        };
        const handleAuto = () => {
            const auto = diverseDefaultDirs(repeat);
            setScenarios(prev => prev.map(r => r.id === row.id ? {
                ...r,
                params: {
                    ...(r.params || {}),
                    multiRepeatCount: repeat,
                    multiRepeatDirections: auto
                }
            } : r));
            message.success(`${repeat}회 시나리오를 다양한 조합으로 자동 채움`);
        };
        // 6개씩 끊어서 여러 행으로 표시
        const COLS_PER_ROW = 6;
        const numRows = Math.ceil(repeat / COLS_PER_ROW);
        const vtopCell = { style: { verticalAlign: "top", padding: "4px 6px" } };
        const matrixColumns = [
            { title: "낙하 순서", dataIndex: "__idx", width: 90, onCell: () => vtopCell, fixed: "left" },
            ...Array.from({ length: COLS_PER_ROW }).map((_, c) => ({
                title: `시나리오`,
                dataIndex: `c${c}`,
                width: 140,
                onCell: () => vtopCell,
                render: (_, rec) => {
                    const actualIndex = rec.__rowIndex * COLS_PER_ROW + c;
                    if (actualIndex >= repeat)
                        return null;
                    return (_jsxs(Flex, { vertical: true, gap: 4, children: [_jsxs(Text, { type: "secondary", style: { fontSize: 11 }, children: ["#", actualIndex + 1] }), _jsx(Select, { size: "small", style: { width: 120 }, dropdownMatchSelectWidth: false, value: rec[`c${c}`], options: dirOptions, onChange: (v) => setCell(actualIndex, v), showSearch: true, optionFilterProp: "label" })] }));
                }
            }))
        ];
        const matrixData = Array.from({ length: numRows }).map((_, rowIdx) => {
            const rowObj = {
                key: rowIdx,
                __idx: `${rowIdx * COLS_PER_ROW + 1}-${Math.min((rowIdx + 1) * COLS_PER_ROW, repeat)}`,
                __rowIndex: rowIdx
            };
            for (let c = 0; c < COLS_PER_ROW; c++) {
                const actualIndex = rowIdx * COLS_PER_ROW + c;
                rowObj[`c${c}`] = actualIndex < repeat ? validDirections[actualIndex] : null;
            }
            return rowObj;
        });
        return (_jsxs(Flex, { vertical: true, gap: 10, children: [renderCommonDropControls(row, setScenarios), renderToleranceControls(row, setScenarios), _jsx("style", { children: `
          .multi-repeat-matrix .ant-table-tbody > tr > td { vertical-align: top; padding: 4px 6px; }
          .multi-repeat-matrix .ant-select-selector { padding: 0 6px !important; }
        ` }), _jsxs(Space, { wrap: true, align: "center", children: [_jsx(Text, { children: "\uD68C\uC218" }), _jsx(InputNumber, { style: { width: 100 }, value: repeat, min: 1, max: 100, onChange: (v) => setRepeat(Number(v ?? 24)) }), _jsx(Button, { size: "small", onClick: handleAuto, children: "\uC790\uB3D9 \uBD84\uD3EC" }), _jsx(Tag, { color: "geekblue", children: analysisLabel(row) }), _jsxs(Text, { type: "secondary", style: { fontSize: 12 }, children: ["(", COLS_PER_ROW, "\uAC1C\uC529 ", numRows, "\uD589\uC73C\uB85C \uD45C\uC2DC)"] })] }), _jsx("div", { className: "multi-repeat-matrix", style: { overflowX: "auto" }, children: _jsx(Table, { size: "small", pagination: false, columns: matrixColumns, dataSource: matrixData, rowClassName: () => "tight-vtop", bordered: true }) })] }));
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
        // ---- NEW: predefinedAttitudes ----
        if (row.analysisType === "predefinedAttitudes") {
            return renderPredefinedAttitudesControls(row, setScenarios);
        }
        // ---- NEW: edgeAxisRotation ----
        if (row.analysisType === "edgeAxisRotation") {
            return renderEdgeAxisRotationControls(row, setScenarios);
        }
        // ---- NEW: dropWeightImpact ----
        if (row.analysisType === "dropWeightImpact") {
            return renderDropWeightImpactControls(row, setScenarios);
        }
        // ---- multiRepeatCumulative ----
        if (row.analysisType === "multiRepeatCumulative") {
            return renderMultiRepeatControls(row);
        }
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
            title: "시나리오 / 해석 항목",
            dataIndex: "name",
            key: "name",
            width: 340,
            onCell: () => topCell,
            render: (value, row) => (_jsxs(Flex, { vertical: true, gap: 8, children: [_jsxs(Flex, { vertical: true, gap: 4, children: [_jsx(Text, { strong: true, style: { fontSize: 12, color: '#666' }, children: "\uC2DC\uB098\uB9AC\uC624 \uC774\uB984" }), _jsx(Input, { size: "small", value: row.name, onChange: (e) => setScenarios(prev => prev.map(r => r.id === row.id ? { ...r, name: e.target.value } : r)), placeholder: "\uC2DC\uB098\uB9AC\uC624 \uC774\uB984" })] }), _jsxs(Flex, { vertical: true, gap: 4, children: [_jsx(Text, { strong: true, style: { fontSize: 12, color: '#666' }, children: "\uD574\uC11D \uD56D\uBAA9" }), _jsx(Select, { style: { width: "100%" }, size: "small", value: row.analysisType, onChange: (v) => {
                                    setScenarios((prev) => prev.map((r) => (r.id === row.id ? {
                                        ...r,
                                        analysisType: v,
                                        description: DEFAULT_DESCRIPTIONS[v],
                                        params: v === "fullAngleMBD" ? { mbdCount: 1000, angleSource: "lhs", heightMode: "const", heightConst: 1.0, heightMin: 0.5, heightMax: 1.5, surface: "steelPlate", tolerance: { mode: "disabled" } } :
                                            v === "fullAngle" ? { faTotal: 100, includeFace6: true, includeEdge12: true, includeCorner8: true, angleSource: "lhs", heightMode: "const", heightConst: 1.0, heightMin: 0.5, heightMax: 1.5, surface: "steelPlate", tolerance: { mode: "disabled" } } :
                                                v === "fullAngleCumulative" ? { cumRepeatCount: 3, cumDOECount: 5, cumDirectionsGrid: diverseDefaultGrid(3, 5), heightMode: "const", heightConst: 1.0, heightMin: 0.5, heightMax: 1.5, surface: "steelPlate", tolerance: { mode: "disabled" } } :
                                                    v === "multiRepeatCumulative" ? { multiRepeatCount: 24, multiRepeatDirections: diverseDefaultDirs(24), heightMode: "const", heightConst: 1.0, heightMin: 0.5, heightMax: 1.5, surface: "steelPlate", tolerance: { mode: "disabled" } } :
                                                        v === "predefinedAttitudes" ? { predefinedMode: "all26", heightMode: "const", heightConst: 1.0, heightMin: 0.5, heightMax: 1.5, surface: "steelPlate", tolerance: { mode: "disabled" } } :
                                                            v === "edgeAxisRotation" ? { edgeAxis: "top", edgeDivisions: 12, heightMode: "const", heightConst: 1.0, heightMin: 0.5, heightMax: 1.5, surface: "steelPlate", tolerance: { mode: "disabled" } } :
                                                                v === "dropWeightImpact" ? { impactPackagePatterns: ["*pkg*"], impactLocationMode: "grid", impactGridMode: "3x3", impactPercentageX: 50, impactPercentageY: 50, impactRandomCount: 10, impactorType: "ball", impactorBallDiameter: 6, impactorCylinderDiameter: 8, impactorCylinderDiameterCustom: 10, tolerance: { mode: "disabled" } } :
                                                                    { piMode: "default", tolerance: { mode: "disabled" } },
                                    } : r)));
                                }, options: ANALYSIS_OPTIONS.map((o) => ({ label: o.label, value: o.value })) })] }), row.description && (_jsx(Text, { type: "secondary", style: { fontSize: 11, fontStyle: 'italic', lineHeight: '1.4' }, children: row.description })), _jsxs(Space, { size: 4, wrap: true, children: [_jsxs(Tag, { style: { fontSize: 11 }, children: ["ID: ", row.id] }), row.fileName && _jsxs(Tag, { color: "geekblue", style: { fontSize: 11 }, children: ["K: ", row.fileName] }), row.objFileName && _jsxs(Tag, { color: "purple", style: { fontSize: 11 }, children: ["OBJ: ", row.objFileName] })] })] })),
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
            {
                id: uid("scn"),
                name: "새 시나리오",
                description: DEFAULT_DESCRIPTIONS["fullAngleMBD"],
                analysisType: "fullAngleMBD",
                params: { mbdCount: 1000, angleSource: "lhs", heightMode: "const", heightConst: 1.0, heightMin: 0.5, heightMax: 1.5, surface: "steelPlate", tolerance: { mode: "disabled" } }
            },
        ]));
    };
    const handleStandardScenarioSelect = (scenario) => {
        // Map standard scenario to internal format
        const analysisTypeMap = {
            "multibody": "fullAngleMBD",
            "fall": "fullAngle",
            "cumulative": "fullAngleCumulative",
            "multiCumulative": "multiRepeatCumulative",
            "weightImpact": "dropWeightImpact",
            "predefined": "predefinedAttitudes",
            "edgeRotation": "edgeAxisRotation",
        };
        const analysisType = analysisTypeMap[scenario.parameters.analysisType] || "fullAngleMBD";
        // Build params based on analysis type
        let params = {
            heightMode: "const",
            heightConst: scenario.parameters.dropHeight || 1.0,
            surface: scenario.parameters.impactSurface || "steelPlate",
            tolerance: { mode: "disabled" },
        };
        // Add type-specific parameters
        if (analysisType === "fullAngleMBD") {
            params.mbdCount = scenario.angles.length;
            params.angleSource = "lhs";
        }
        else if (analysisType === "fullAngle") {
            params.faTotal = scenario.angles.length;
            params.includeFace6 = true;
            params.includeEdge12 = true;
            params.includeCorner8 = true;
            params.angleSource = "lhs";
        }
        else if (analysisType === "fullAngleCumulative") {
            // DOE x repeat matrix - use angles as DOE rows
            const repeatCount = scenario.parameters.repeatCount || 3;
            params.cumRepeatCount = (repeatCount >= 2 && repeatCount <= 5 ? repeatCount : 3);
            params.cumDOECount = scenario.angles.length;
            // Initialize with default grid (will be customizable by user)
            params.cumDirectionsGrid = diverseDefaultGrid(params.cumRepeatCount, params.cumDOECount);
        }
        else if (analysisType === "multiRepeatCumulative") {
            // Multiple repeats without DOE - use angles as repeat sequence
            const repeatCount = scenario.parameters.repeatCount || scenario.angles.length;
            params.multiRepeatCount = repeatCount;
            params.multiRepeatDirections = diverseDefaultDirs(repeatCount);
        }
        else if (analysisType === "predefinedAttitudes") {
            // Determine mode from angle count
            const count = scenario.angles.length;
            params.predefinedMode = count === 6 ? "faces6" : count === 12 ? "edges12" : count === 8 ? "corners8" : "all26";
            // Initialize with scenario angles
            params.predefinedAngles = scenario.angles.map((angle) => ({
                name: angle.name,
                phi: angle.phi,
                theta: angle.theta,
                psi: angle.psi
            }));
        }
        else if (analysisType === "edgeAxisRotation") {
            params.edgeAxis = "top";
            params.edgeDivisions = scenario.angles.length;
        }
        else if (analysisType === "dropWeightImpact") {
            params.impactPackagePatterns = ["*pkg*"];
            params.impactLocationMode = "grid";
            params.impactGridMode = "3x3";
            params.impactPercentageX = 50;
            params.impactPercentageY = 50;
            params.impactRandomCount = 10;
            params.impactorType = "ball";
            params.impactorBallDiameter = 6;
            params.impactorCylinderDiameter = 8;
            params.impactorCylinderDiameterCustom = 10;
        }
        const newScenario = {
            id: uid("scn"),
            name: scenario.name,
            description: scenario.description,
            analysisType,
            params,
        };
        setScenarios((prev) => [...prev, newScenario]);
        setStandardModalVisible(false);
        message.success(`규격 시나리오 "${scenario.name}"를 추가했습니다.`);
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
                        bulkType === "multiRepeatCumulative" ? { multiRepeatCount: 24, multiRepeatDirections: diverseDefaultDirs(24), heightMode: "const", heightConst: 1.0, heightMin: 0.5, heightMax: 1.5, surface: "steelPlate", tolerance: { mode: "disabled" } } :
                            bulkType === "predefinedAttitudes" ? { predefinedMode: "all26", heightMode: "const", heightConst: 1.0, heightMin: 0.5, heightMax: 1.5, surface: "steelPlate", tolerance: { mode: "disabled" } } :
                                bulkType === "edgeAxisRotation" ? { edgeAxis: "top", edgeDivisions: 12, heightMode: "const", heightConst: 1.0, heightMin: 0.5, heightMax: 1.5, surface: "steelPlate", tolerance: { mode: "disabled" } } :
                                    bulkType === "dropWeightImpact" ? { impactPackagePatterns: ["*pkg*"], impactLocationMode: "grid", impactGridMode: "3x3", impactPercentageX: 50, impactPercentageY: 50, impactRandomCount: 10, impactorType: "ball", impactorBallDiameter: 6, impactorCylinderDiameter: 8, impactorCylinderDiameterCustom: 10, tolerance: { mode: "disabled" } } :
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
    return (_jsxs(Flex, { vertical: true, gap: 16, className: "p-4", children: [_jsx(Title, { level: 3, style: { margin: 0 }, children: "Simulation Automation" }), _jsx(Text, { type: "secondary", children: "TypeScript + Vite + React + Ant Design \u00B7 OBJ/K \uB4DC\uB798\uADF8&\uB4DC\uB86D \u00B7 \uC0C1\uB2E8\uC815\uB82C UI \u00B7 \uB192\uC774/\uD45C\uBA74 \uACF5\uD1B5 \uC635\uC158 \u00B7 \uB204\uC801 \uB099\uD558 DOE\u00D7\uD68C\uC218 \uB9E4\uD2B8\uB9AD\uC2A4 \u00B7 \uAC01\uB3C4 \uBCC0\uB3D9 \uD5C8\uC6A9 (\uBA74/\uC5E3\uC9C0/\uCF54\uB108)" }), _jsxs(Card, { bodyStyle: { padding: 0 }, children: [_jsxs(Dragger, { ...uploadPropsOBJ, style: { padding: 20 }, children: [_jsx("p", { className: "ant-upload-drag-icon", children: _jsx(InboxOutlined, {}) }), _jsxs("p", { className: "ant-upload-text", children: ["\uC5EC\uAE30\uB85C ", _jsx("b", { children: ".obj" }), " \uD30C\uC77C\uC744 \uB04C\uC5B4\uC624\uAC70\uB098 \uD074\uB9AD\uD558\uC5EC \uC120\uD0DD (MBD)"] }), _jsx("p", { className: "ant-upload-hint", children: "\uC120\uD0DD\uD55C 1\uAC1C \uD589\uC774 \uC788\uC73C\uBA74 \uADF8 \uD589\uC5D0 \uC5F0\uACB0, \uC5C6\uC73C\uBA74 \uC0C8 \uC2DC\uB098\uB9AC\uC624 \uC0DD\uC131" })] }), _jsx(Divider, { style: { margin: 0 } }), _jsxs(Dragger, { ...uploadPropsK, style: { padding: 20 }, children: [_jsx("p", { className: "ant-upload-drag-icon", children: _jsx(InboxOutlined, {}) }), _jsxs("p", { className: "ant-upload-text", children: ["\uC5EC\uAE30\uB85C ", _jsx("b", { children: ".k/.key/.dyn" }), " \uD30C\uC77C\uC744 \uB04C\uC5B4\uC624\uAC70\uB098 \uD074\uB9AD\uD558\uC5EC \uC120\uD0DD (FE)"] }), _jsx("p", { className: "ant-upload-hint", children: "\uC120\uD0DD\uD55C 1\uAC1C \uD589\uC774 \uC788\uC73C\uBA74 \uADF8 \uD589\uC5D0 \uC5F0\uACB0, \uC5C6\uC73C\uBA74 \uC0C8 \uC2DC\uB098\uB9AC\uC624 \uC0DD\uC131" })] })] }), _jsxs(Card, { children: [_jsxs(Flex, { gap: 8, wrap: true, align: "center", justify: "space-between", style: { marginBottom: 12 }, children: [_jsxs(Space, { wrap: true, children: [_jsx(Button, { type: "dashed", icon: _jsx(PlusOutlined, {}), onClick: handleAddEmpty, children: "\uBE48 \uC2DC\uB098\uB9AC\uC624 \uCD94\uAC00" }), _jsx(Button, { type: "primary", icon: _jsx(PlusOutlined, {}), onClick: () => setStandardModalVisible(true), children: "\uADDC\uACA9 \uC2DC\uB098\uB9AC\uC624 \uCD94\uAC00" }), _jsx(Select, { style: { width: 300 }, placeholder: "\uC120\uD0DD\uD55C \uC2DC\uB098\uB9AC\uC624\uC5D0 \uC77C\uAD04 \uC801\uC6A9\uD560 \uD574\uC11D \uD56D\uBAA9", value: bulkType, onChange: setBulkType, options: ANALYSIS_OPTIONS.map(o => ({ label: o.label, value: o.value })), size: "small" }), _jsx(Button, { size: "small", onClick: handleBulkSetType, children: "\uC77C\uAD04 \uC801\uC6A9" }), _jsx(Divider, { type: "vertical" }), _jsx(Button, { size: "small", icon: _jsx(PlayCircleOutlined, {}), type: "primary", onClick: () => handleRun(), children: "\uC120\uD0DD \uC2E4\uD589" })] }), _jsxs(Space, { wrap: true, children: [_jsxs("label", { children: [_jsx("input", { type: "file", accept: "application/json", onChange: handleImport, style: { display: "none" }, id: "scenario-import" }), _jsx(Button, { size: "small", icon: _jsx(UploadOutlined, {}), onClick: () => document.getElementById("scenario-import")?.click(), children: "\uBD88\uB7EC\uC624\uAE30" })] }), _jsx(Button, { size: "small", icon: _jsx(SaveOutlined, {}), onClick: handleExport, children: "\uB0B4\uBCF4\uB0B4\uAE30" })] })] }), _jsx(Table, { rowKey: "id", size: "small", rowSelection: rowSelection, columns: columns, dataSource: scenarios, pagination: { pageSize: 10, showSizeChanger: true }, locale: { emptyText: "상단 드래거로 OBJ 또는 K 파일을 추가하세요." }, style: { tableLayout: "fixed" } })] }), _jsx(Card, { size: "small", children: _jsxs(Text, { type: "secondary", children: ["\u2022 \uBAA8\uB4E0 \uC804\uAC01\uB3C4 \uD574\uC11D(MBD/FA/\uB204\uC801)\uC5D0\uC11C \uACF5\uD1B5\uC73C\uB85C ", _jsx("b", { children: "\uB099\uD558 \uB192\uC774(\uACE0\uC815\uAC12 \uB610\uB294 LHS \uBC94\uC704)" }), "\uC640 ", _jsx("b", { children: "\uB099\uD558 \uD45C\uBA74(\uCCA0\uD310/\uBCF4\uB3C4\uBE14\uB7ED/\uCF58\uD06C\uB9AC\uD2B8/\uBAA9\uC7AC)" }), "\uC744 \uC815\uC758\uD569\uB2C8\uB2E4.", _jsx("br", {}), "\u2022 \uB192\uC774 \uBAA8\uB4DC\uAC00 LHS\uC77C \uB54C\uB294 ", _jsx("b", { children: "min/max" }), "\uB97C \uC9C0\uC815\uD569\uB2C8\uB2E4(\uB2E8\uC704: m).", _jsx("br", {}), "\u2022 \uB204\uC801 \uB9E4\uD2B8\uB9AD\uC2A4\uB294 ", _jsx("b", { children: "\uD0C0\uC774\uD2B8 \uD328\uB529 + \uACE0\uC815 \uD3ED" }), "\uC73C\uB85C \uD45C\uC2DC\uD558\uBA70, \uD589 \uAC04 \uC644\uC804 \uB3D9\uC77C \uC870\uD569\uC744 \uBC29\uC9C0\uD569\uB2C8\uB2E4(\uD589 \uB0B4 \uC911\uBCF5 \uD5C8\uC6A9).", _jsx("br", {}), "\u2022 \"\uAE30\uC874 \uACB0\uACFC \uC0AC\uC6A9\"\uC740 \uD604\uC7AC \uD589 ", _jsx("b", { children: "\uC704\uCABD" }), " \uC2DC\uB098\uB9AC\uC624\uB9CC \uB4DC\uB86D\uB2E4\uC6B4\uC73C\uB85C \uD45C\uC2DC\uD569\uB2C8\uB2E4.", _jsx("br", {}), "\u2022 ", _jsx("b", { children: "\uAC01\uB3C4 \uBCC0\uB3D9 \uD5C8\uC6A9" }), "\uC744 \uD65C\uC131\uD654\uD558\uBA74 \uBA74(6\uAC1C), \uC5E3\uC9C0(12\uAC1C), \uCF54\uB108(8\uAC1C)\uBCC4\uB85C \uCD5C\uB300 \uBCC0\uB3D9\uB7C9\uC744 \uC124\uC815\uD560 \uC218 \uC788\uC73C\uBA70, LHS \uC0D8\uD50C\uB9C1\uC73C\uB85C \uC2E4\uC81C \uAC01\uB3C4\uAC00 \uC0DD\uC131\uB429\uB2C8\uB2E4."] }) }), _jsx(StandardScenarioModal, { visible: standardModalVisible, onClose: () => setStandardModalVisible(false), onSelect: handleStandardScenarioSelect })] }));
};
export default SimulationAutomationComponent;
