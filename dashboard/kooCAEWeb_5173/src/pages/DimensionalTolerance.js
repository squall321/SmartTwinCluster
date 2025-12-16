import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useState, useEffect, useMemo } from 'react';
import BaseLayout from '../layouts/BaseLayout';
import { Typography, Divider, Input, Select, Button, Space, InputNumber, Table, Tag, Popconfirm, message } from "antd";
import { useNavigate } from 'react-router-dom';
import PartIdFinderUploader from '../components/uploader/PartIDFindUploader';
import PartSelector from '../components/shared/PartSelector';
import ColoredScatter3DComponent from '../components/ColoredScatter3DComponent';
import { generateDimensionalToleranceOptionFile } from '../components/shared/utils';
import ExportMeshModifierButton from '@components/shared/ExportMeshModifierButtonProps';
const { Title, Paragraph, Text } = Typography;
const variationOptions = [
    "fixed",
    "최대/최소 등간격",
    "평균/표준편차",
    "최대 최소 LHS",
    "랜덤",
];
const ALL_DIRS = ['x', 'y', 'z'];
const METHOD_USES_MINMAX = ['최대/최소 등간격', '최대 최소 LHS', '랜덤'];
const toStr = (v) => (v === null || v === undefined) ? '' : String(v);
const makeKey = (partId, dir) => `${partId}::${dir}`;
// ---- Normal utilities (no deps) ----
function normInv(p, mu = 0, sigma = 1) {
    // Peter J. Acklam's approximation
    if (p <= 0 || p >= 1)
        return p === 0 ? -Infinity : Infinity;
    const a1 = -39.69683028665376, a2 = 220.9460984245205, a3 = -275.9285104469687;
    const a4 = 138.3577518672690, a5 = -30.66479806614716, a6 = 2.506628277459239;
    const b1 = -54.47609879822406, b2 = 161.5858368580409, b3 = -155.6989798598866;
    const b4 = 66.80131188771972, b5 = -13.28068155288572;
    const c1 = -0.007784894002430293, c2 = -0.3223964580411365, c3 = -2.400758277161838;
    const c4 = -2.549732539343734, c5 = 4.374664141464968, c6 = 2.938163982698783;
    const d1 = 0.007784695709041462, d2 = 0.3224671290700398, d3 = 2.445134137142996, d4 = 3.754408661907416;
    const plow = 0.02425, phigh = 1 - plow;
    let q, r, x;
    if (p < plow) {
        q = Math.sqrt(-2 * Math.log(p));
        x = (((((c1 * q + c2) * q + c3) * q + c4) * q + c5) * q + c6) /
            ((((d1 * q + d2) * q + d3) * q + d4) * q + 1);
    }
    else if (p <= phigh) {
        q = p - 0.5;
        r = q * q;
        x = (((((a1 * r + a2) * r + a3) * r + a4) * r + a5) * r + a6) * q /
            (((((b1 * r + b2) * r + b3) * r + b4) * r + b5) * r + 1);
    }
    else {
        q = Math.sqrt(-2 * Math.log(1 - p));
        x = -(((((c1 * q + c2) * q + c3) * q + c4) * q + c5) * q + c6) /
            ((((d1 * q + d2) * q + d3) * q + d4) * q + 1);
    }
    // one step Halley correction
    const e = 0.5 * (1 + erf(x / Math.SQRT2)) - p;
    const u = e * Math.sqrt(2 * Math.PI) * Math.exp(x * x / 2);
    x = x - u / (1 + x * u / 2);
    return mu + sigma * x;
}
function erf(x) {
    // Abramowitz-Stegun approximation
    const sign = Math.sign(x);
    x = Math.abs(x);
    const a1 = 0.254829592, a2 = -0.284496736, a3 = 1.421413741, a4 = -1.453152027, a5 = 1.061405429;
    const p = 0.3275911;
    const t = 1 / (1 + p * x);
    const y = 1 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * Math.exp(-x * x);
    return sign * y;
}
function normCdf(x, mu = 0, sigma = 1) {
    return 0.5 * (1 + erf((x - mu) / (sigma * Math.SQRT2)));
}
function shuffleInPlace(arr) {
    for (let i = arr.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [arr[i], arr[j]] = [arr[j], arr[i]];
    }
}
// LHS for Normal(μ,σ)
function lhsNormal(n, mu = 0, sigma = 1) {
    const step = 1 / n;
    const u = Array.from({ length: n }, (_, i) => (i + Math.random()) * step);
    const z = u.map(p => normInv(p, mu, sigma));
    shuffleInPlace(z);
    return z;
}
// LHS for Truncated Normal within [a,b]
function lhsTruncNormal(n, mu = 0, sigma = 1, a = -Infinity, b = Infinity) {
    const Fa = Number.isFinite(a) ? normCdf(a, mu, sigma) : 0;
    const Fb = Number.isFinite(b) ? normCdf(b, mu, sigma) : 1;
    const step = 1 / n;
    const u = Array.from({ length: n }, (_, i) => (i + Math.random()) * step);
    const uT = u.map(v => Fa + v * (Fb - Fa));
    const z = uT.map(p => normInv(p, mu, sigma));
    shuffleInPlace(z);
    return z;
}
// ---------- 샘플링 유틸 ----------
function randn() {
    let u = 0, v = 0;
    while (u === 0)
        u = Math.random();
    while (v === 0)
        v = Math.random();
    return Math.sqrt(-2.0 * Math.log(u)) * Math.cos(2.0 * Math.PI * v);
}
function lhs1D(n, min, max) {
    const step = 1 / n;
    const arr = Array.from({ length: n }, (_, i) => (i + Math.random()) * step);
    // shuffle
    for (let i = arr.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [arr[i], arr[j]] = [arr[j], arr[i]];
    }
    return arr.map(u => min + (max - min) * u);
}
function linspace(min, max, count) {
    if (count <= 1)
        return [(min + max) / 2];
    const out = [];
    const step = (max - min) / (count - 1);
    for (let i = 0; i < count; i++)
        out.push(min + step * i);
    return out;
}
const DimensionalTolerance = () => {
    const navigate = useNavigate();
    const [kFileName, setKFileName] = useState('uploaded_file.k');
    const [allPartInfos, setAllPartInfos] = useState([]);
    const [selectedParts, setSelectedParts] = useState([]);
    const [uploadedKFile, setUploadedKFile] = useState(null);
    // bulk 입력값
    const [bulkKeyword, setBulkKeyword] = useState('');
    const [minToleranceValue, setMinToleranceValue] = useState(-1);
    const [maxToleranceValue, setMaxToleranceValue] = useState(1);
    const [meanToleranceValue, setMeanToleranceValue] = useState(0);
    const [stdDevToleranceValue, setStdDevToleranceValue] = useState(1);
    const [lhsMinToleranceValue, setLhsMinToleranceValue] = useState(-1);
    const [lhsMaxToleranceValue, setLhsMaxToleranceValue] = useState(1);
    const [randomMinToleranceValue, setRandomMinToleranceValue] = useState(-1);
    const [randomMaxToleranceValue, setRandomMaxToleranceValue] = useState(1);
    const [bulkDirection, setBulkDirection] = useState('z');
    const [variationMethod, setVariationMethod] = useState(variationOptions[0]);
    // 테이블 행
    const [partRows, setPartRows] = useState([]);
    // 샘플 생성용 입력
    const [baseSamples, setBaseSamples] = useState(32); // 등간격 제외 샘플 수
    const [intervalCount, setIntervalCount] = useState(10); // 등간격 interval 개수
    // 생성된 데이터 (ColoredScatter3DComponent 용)
    const [generatedData, setGeneratedData] = useState(null);
    // 1) helper: generatedData -> {partIDs, directions, variableMatrix}
    function buildDimTolArgsFromGeneratedData(generatedData) {
        if (!generatedData || generatedData.length < 2) {
            return { partIDs: [], directions: [], variableMatrix: [] };
        }
        const headers = generatedData[0]; // ['sample', ...vars, 'sweepVarIndex', 'sweepLevel']
        const rows = generatedData.slice(1);
        // 변수 컬럼만 추출 (sample=0번째, 마지막 두 개는 sweep 메타)
        const varHeaders = headers.slice(1, Math.max(1, headers.length - 2));
        // partIDs, directions 추출
        const partIDs = [];
        const directions = [];
        for (const vh of varHeaders) {
            // 형식: "<partId>_<dir>"
            const [pidStr, dirStr] = String(vh).split('_');
            partIDs.push(Number(pidStr));
            // 안전하게 캐스팅
            const d = dirStr || 'z';
            directions.push(d);
        }
        // variableMatrix[i] = 모든 행의 i번째 변수값(숫자)을 모은 컬럼
        const variableMatrix = varHeaders.map((_, i) => rows.map(r => {
            const v = r[1 + i]; // 0은 sample, 변수는 1부터
            const num = typeof v === 'number' ? v : Number(v);
            return Number.isFinite(num) ? num : 0; // 숫자 아님/빈 값은 0으로
        }));
        return { partIDs, directions, variableMatrix };
    }
    // 새로 선택된 파트는 기본 z 방향 1행 추가 (이미 있으면 이름만 갱신)
    useEffect(() => {
        setPartRows(prev => {
            const next = [...prev];
            for (const p of selectedParts) {
                const pid = toStr(p.id);
                const pname = toStr(p.name);
                const hasAny = next.some(r => r.partId === pid);
                if (!hasAny) {
                    const key = makeKey(pid, 'z');
                    next.push({
                        key,
                        partId: pid,
                        partName: pname,
                        direction: 'z',
                        method: 'fixed',
                        fixedValue: 1,
                    });
                }
                else {
                    next.forEach(r => { if (r.partId === pid)
                        r.partName = pname; });
                }
            }
            return next;
        });
    }, [selectedParts]);
    // 표시용 매칭 카운트
    const matchedParts = useMemo(() => {
        const kw = bulkKeyword.trim().toLowerCase();
        if (!kw)
            return [];
        return allPartInfos.filter(p => {
            const name = toStr(p.name).toLowerCase();
            const id = toStr(p.id).toLowerCase();
            return name.includes(kw) || id.includes(kw);
        });
    }, [bulkKeyword, allPartInfos]);
    // 셀 패치
    const patchRow = (rowKey, patch) => {
        setPartRows(prev => prev.map(r => r.key === rowKey ? { ...r, ...patch } : r));
    };
    // 행 삭제
    const deleteRow = (rowKey) => {
        setPartRows(prev => prev.filter(r => r.key !== rowKey));
    };
    // 방향 추가 (최대 3행/파트, 중복 방향 불가)
    const addDirectionRow = (partId) => {
        setPartRows(prev => {
            const rowsOfPart = prev.filter(r => r.partId === partId);
            if (rowsOfPart.length >= 3) {
                message.warning('해당 파트는 최대 3개 방향까지만 설정할 수 있어요.');
                return prev;
            }
            const used = new Set(rowsOfPart.map(r => r.direction));
            const available = ALL_DIRS.find(d => !used.has(d));
            if (!available) {
                message.warning('사용 가능한 방향이 없습니다.');
                return prev;
            }
            const partName = rowsOfPart[0]?.partName ?? '';
            const key = makeKey(partId, available);
            return [
                ...prev,
                {
                    key,
                    partId,
                    partName,
                    direction: available,
                    method: 'fixed',
                    fixedValue: 1,
                },
            ];
        });
    };
    // 방향 변경: 같은 파트 내 중복 방지 + key 갱신
    const changeDirection = (row, newDir) => {
        setPartRows(prev => {
            if (prev.some(r => r.partId === row.partId && r.direction === newDir && r.key !== row.key)) {
                message.error('같은 파트에서 방향이 중복될 수 없어요.');
                return prev;
            }
            const newKey = makeKey(row.partId, newDir);
            return prev.map(r => r.key === row.key ? { ...r, direction: newDir, key: newKey } : r);
        });
    };
    // 일괄 적용
    const handleBulkApply = () => {
        const kw = bulkKeyword.trim().toLowerCase();
        const matches = (kw
            ? allPartInfos.filter(p => {
                const name = toStr(p.name).toLowerCase();
                const id = toStr(p.id).toLowerCase();
                return name.includes(kw) || id.includes(kw);
            })
            : allPartInfos);
        if (matches.length === 0) {
            message.info('매칭된 파트가 없습니다.');
            return;
        }
        setPartRows(prev => {
            const next = [...prev];
            const byPart = new Map();
            for (const r of next) {
                const list = byPart.get(r.partId) ?? [];
                list.push(r);
                byPart.set(r.partId, list);
            }
            for (const p of matches) {
                const pid = toStr(p.id);
                const pname = toStr(p.name);
                const rows = byPart.get(pid) ?? [];
                // 없으면 기본 z행 추가
                if (rows.length === 0) {
                    const baseKey = makeKey(pid, 'z');
                    const baseRow = {
                        key: baseKey, partId: pid, partName: pname,
                        direction: 'z', method: 'fixed', fixedValue: 1,
                    };
                    next.push(baseRow);
                    byPart.set(pid, [baseRow]);
                }
                else {
                    rows.forEach(r => (r.partName = pname));
                }
                // bulkDirection 찾기
                let target = (byPart.get(pid) ?? []).find(r => r.direction === bulkDirection);
                if (!target) {
                    const rowsNow = byPart.get(pid);
                    if (rowsNow.length >= 3)
                        continue; // 3행 제한
                    const key = makeKey(pid, bulkDirection);
                    target = { key, partId: pid, partName: pname, direction: bulkDirection, method: 'fixed', fixedValue: 1 };
                    next.push(target);
                    rowsNow.push(target);
                }
                // 메서드/값 적용
                switch (variationMethod) {
                    case "fixed":
                        target.method = "fixed";
                        target.fixedValue = target.fixedValue ?? 1;
                        target.min = undefined;
                        target.max = undefined;
                        target.mean = undefined;
                        target.std = undefined;
                        break;
                    case "최대/최소 등간격":
                        target.method = "최대/최소 등간격";
                        target.min = minToleranceValue;
                        target.max = maxToleranceValue;
                        target.fixedValue = undefined;
                        target.mean = undefined;
                        target.std = undefined;
                        break;
                    case "평균/표준편차":
                        target.method = "평균/표준편차";
                        target.mean = meanToleranceValue;
                        target.std = stdDevToleranceValue;
                        target.fixedValue = undefined;
                        target.min = undefined;
                        target.max = undefined;
                        break;
                    case "최대 최소 LHS":
                        target.method = "최대 최소 LHS";
                        target.min = lhsMinToleranceValue;
                        target.max = lhsMaxToleranceValue;
                        target.fixedValue = undefined;
                        target.mean = undefined;
                        target.std = undefined;
                        break;
                    case "랜덤":
                        target.method = "랜덤";
                        target.min = randomMinToleranceValue;
                        target.max = randomMaxToleranceValue;
                        target.fixedValue = undefined;
                        target.mean = undefined;
                        target.std = undefined;
                        break;
                }
            }
            return next;
        });
    };
    // 일괄 삭제
    const handleBulkClear = () => {
        const kw = bulkKeyword.trim().toLowerCase();
        setPartRows(prev => prev.filter(row => kw &&
            !(row.partName.toLowerCase().includes(kw) || row.partId.toLowerCase().includes(kw))));
        if (!kw) {
            setPartRows([]);
        }
    };
    // ---------- 전체 샘플 수 계산 ----------
    const totalSamplesPreview = useMemo(() => {
        const eqRows = partRows.filter(r => r.method === '최대/최소 등간격');
        if (eqRows.length > 0) {
            return baseSamples * Math.max(1, intervalCount) * eqRows.length;
        }
        return baseSamples;
    }, [partRows, baseSamples, intervalCount]);
    // ---------- 산포 생성 ----------
    const generateSamples = () => {
        if (partRows.length === 0) {
            message.warning('표에 행이 없습니다. 파트를 선택하거나 행을 추가하세요.');
            return;
        }
        const N = Math.max(1, Math.floor(baseSamples));
        const M = Math.max(1, Math.floor(intervalCount));
        // 컬럼 헤더: sample, 각 변수(파트ID_방향), sweepVarIndex, sweepLevel
        const varKeys = partRows.map(r => `${r.partId}_${r.direction}`);
        const headers = ['sample', ...varKeys, 'sweepVarIndex', 'sweepLevel'];
        const out = [headers];
        // 등간격 행 & 그 외
        const eqRows = partRows.filter(r => r.method === '최대/최소 등간격');
        const otherRows = partRows.filter(r => r.method !== '최대/최소 등간격');
        // LHS 사전계산 (변수 단위 1D)
        // LHS 캐시 (Uniform 범위와 Normal 시퀀스를 분리)
        const lhsUniformCache = new Map();
        const lhsNormalCache = new Map();
        const lhsTruncNormCache = new Map();
        const ensureLHSUniform = (key, min, max) => {
            if (!lhsUniformCache.has(key))
                lhsUniformCache.set(key, lhs1D(N, min, max));
            return lhsUniformCache.get(key);
        };
        const ensureLHSNormal = (key, mean, std) => {
            if (!lhsNormalCache.has(key))
                lhsNormalCache.set(key, lhsNormal(N, mean, std));
            return lhsNormalCache.get(key);
        };
        const ensureLHSTruncNormal = (key, mean, std, a, b) => {
            if (!lhsTruncNormCache.has(key))
                lhsTruncNormCache.set(key, lhsTruncNormal(N, mean, std, a, b));
            return lhsTruncNormCache.get(key);
        };
        let sampleIndex = 0;
        // 등간격 행이 없으면 그냥 N개 생성
        if (eqRows.length === 0) {
            // 등간격 행이 없는 경우
            for (let i = 0; i < N; i++) {
                const row = [sampleIndex++];
                for (const r of partRows) {
                    const vKey = `${r.partId}_${r.direction}`;
                    const rmin = r.min ?? -Infinity;
                    const rmax = r.max ?? Infinity;
                    switch (r.method) {
                        case 'fixed':
                            row.push(r.fixedValue ?? 1);
                            break;
                        case '랜덤': {
                            const min = Number.isFinite(rmin) ? rmin : -1;
                            const max = Number.isFinite(rmax) ? rmax : 1;
                            row.push(min + (max - min) * Math.random());
                            break;
                        }
                        case '최대 최소 LHS': {
                            const min = Number.isFinite(rmin) ? rmin : -1;
                            const max = Number.isFinite(rmax) ? rmax : 1;
                            const series = ensureLHSUniform(vKey, min, max);
                            row.push(series[i % series.length]);
                            break;
                        }
                        case '평균/표준편차': {
                            const mu = r.mean ?? 0;
                            const sd = r.std ?? 1;
                            // 절단 경계가 지정되어 있으면 절단 정규로, 아니면 일반 정규 LHS
                            if (Number.isFinite(rmin) || Number.isFinite(rmax)) {
                                const series = ensureLHSTruncNormal(vKey, mu, sd, rmin, rmax);
                                row.push(series[i % series.length]);
                            }
                            else {
                                const series = ensureLHSNormal(vKey, mu, sd);
                                row.push(series[i % series.length]);
                            }
                            break;
                        }
                        default:
                            row.push(0); // fallback
                            break;
                    }
                }
                row.push(0, 0);
                out.push(row);
            }
        }
        else {
            // 등간격 행이 있으면 각 등간격 행별로 N*M개 생성하고 이어붙임
            eqRows.forEach((eqRow, eqIdx) => {
                const min = eqRow.min ?? -1;
                const max = eqRow.max ?? 1;
                const levels = linspace(min, max, M);
                for (let lv = 0; lv < levels.length; lv++) {
                    const levelVal = levels[lv];
                    // LHS는 레벨마다 동일 시퀀스를 써도 되고, 섞고 싶다면 캐시를 덮어써도 됨
                    // 여기서는 동일 시퀀스를 재사용
                    for (let i = 0; i < N; i++) {
                        const row = [sampleIndex++];
                        for (const r of partRows) {
                            const vKey = `${r.partId}_${r.direction}`;
                            const rmin = r.min ?? -1;
                            const rmax = r.max ?? 1;
                            if (r.key === eqRow.key) {
                                // 등간격 타겟 변수는 현재 levelVal로 고정
                                row.push(levelVal);
                                continue;
                            }
                            switch (r.method) {
                                case 'fixed':
                                    row.push(r.fixedValue ?? 1);
                                    break;
                                case '랜덤':
                                    row.push(rmin + (rmax - rmin) * Math.random());
                                    break;
                                case '최대 최소 LHS': {
                                    const series = ensureLHSUniform(vKey, rmin, rmax);
                                    row.push(series[i % series.length]);
                                    break;
                                }
                                case '평균/표준편차': {
                                    const mu = r.mean ?? 0;
                                    const sd = r.std ?? 1;
                                    if (Number.isFinite(rmin) || Number.isFinite(rmax)) {
                                        const series = ensureLHSTruncNormal(vKey, mu, sd, rmin, rmax);
                                        row.push(series[i % N]);
                                    }
                                    else {
                                        const series = ensureLHSNormal(vKey, mu, sd);
                                        row.push(series[i % N]);
                                    }
                                    break;
                                }
                                case '최대/최소 등간격':
                                    // 본인이 아닌 다른 등간격 변수는 min 값 고정(간단 정책)
                                    row.push(rmin);
                                    break;
                                default:
                                    row.push(rmin);
                                    break;
                            }
                        }
                        // sweep 메타정보: 어떤 등간격 변수(eqIdx)와 레벨(lv)
                        row.push(eqIdx + 1, lv + 1);
                        out.push(row);
                    }
                }
            });
        }
        setGeneratedData(out);
        message.success(`샘플 생성 완료! 총 ${out.length - 1}개 행`);
    };
    const columns = [
        {
            title: 'Part',
            dataIndex: 'partName',
            width: 200,
            fixed: 'left',
            render: (_, record) => (_jsxs(Space, { size: "small", children: [_jsx("b", { children: record.partName }), _jsx(Tag, { children: record.partId })] })),
        },
        {
            title: '방향',
            dataIndex: 'direction',
            width: 70,
            render: (_, record) => (_jsx(Select, { value: record.direction, onChange: (dir) => changeDirection(record, dir), options: [
                    { label: 'X', value: 'x' },
                    { label: 'Y', value: 'y' },
                    { label: 'Z', value: 'z' },
                ], style: { width: '100%' } })),
        },
        {
            title: '산포 방법',
            dataIndex: 'method',
            width: 140,
            render: (_, record) => (_jsx(Select, { value: record.method, style: { width: '100%' }, onChange: (val) => {
                    if (val === 'fixed') {
                        patchRow(record.key, {
                            method: val,
                            fixedValue: record.fixedValue ?? 1,
                            min: undefined, max: undefined,
                            mean: undefined, std: undefined,
                        });
                    }
                    else if (val === '평균/표준편차') {
                        patchRow(record.key, {
                            method: val,
                            mean: record.mean ?? 0,
                            std: record.std ?? 1,
                            fixedValue: undefined,
                            min: undefined, max: undefined,
                        });
                    }
                    else {
                        patchRow(record.key, {
                            method: val,
                            min: record.min ?? -1,
                            max: record.max ?? 1,
                            fixedValue: undefined,
                            mean: undefined, std: undefined,
                        });
                    }
                }, options: variationOptions.map(v => ({ label: v, value: v })) })),
        },
        {
            title: '두께',
            dataIndex: 'fixedValue',
            width: 70,
            render: (_, record) => (_jsx(InputNumber, { value: record.fixedValue, onChange: v => patchRow(record.key, { fixedValue: v ?? undefined }), disabled: record.method !== 'fixed', style: { width: '100%' } })),
        },
        {
            title: '최소',
            dataIndex: 'min',
            width: 70,
            render: (_, record) => (_jsx(InputNumber, { value: record.min, onChange: v => patchRow(record.key, { min: v ?? undefined }), disabled: !METHOD_USES_MINMAX.includes(record.method), style: { width: '100%' } })),
        },
        {
            title: '최대',
            dataIndex: 'max',
            width: 70,
            render: (_, record) => (_jsx(InputNumber, { value: record.max, onChange: v => patchRow(record.key, { max: v ?? undefined }), disabled: !METHOD_USES_MINMAX.includes(record.method), style: { width: '100%' } })),
        },
        {
            title: '평균',
            dataIndex: 'mean',
            width: 70,
            render: (_, record) => (_jsx(InputNumber, { value: record.mean, onChange: v => patchRow(record.key, { mean: v ?? undefined }), disabled: record.method !== '평균/표준편차', style: { width: '100%' } })),
        },
        {
            title: '표준편차',
            dataIndex: 'std',
            width: 80,
            render: (_, record) => (_jsx(InputNumber, { value: record.std, onChange: v => patchRow(record.key, { std: v ?? undefined }), disabled: record.method !== '평균/표준편차', style: { width: '100%' } })),
        },
        {
            title: '작업',
            dataIndex: 'actions',
            width: 150,
            fixed: 'right',
            render: (_, record) => (_jsxs(Space, { children: [_jsx(Button, { size: "small", onClick: () => addDirectionRow(record.partId), children: "\uBC29\uD5A5 \uCD94\uAC00" }), _jsx(Popconfirm, { title: "\uC774 \uD589\uC744 \uC0AD\uC81C\uD560\uAE4C\uC694?", okText: "\uC0AD\uC81C", cancelText: "\uCDE8\uC18C", onConfirm: () => deleteRow(record.key), children: _jsx(Button, { danger: true, size: "small", children: "\uC0AD\uC81C" }) })] })),
        },
    ];
    function handlePartSelect(part) {
        const pid = toStr(part.id);
        if (selectedParts.some(p => toStr(p.id) === pid))
            return;
        setSelectedParts([...selectedParts, part]);
    }
    return (_jsx(BaseLayout, { isLoggedIn: true, children: _jsxs("div", { style: {
                padding: 24,
                backgroundColor: '#fff',
                minHeight: '100vh',
                borderRadius: '24px',
                overflow: 'hidden', // ✅ 콘텐츠가 좌우로 튀어나오지 않게 클리핑
                position: 'relative', // ✅ 스택 컨텍스트 부여
                isolation: 'isolate', // ✅ 자식 z-index가 밖으로 안 새어나가게
            }, children: [_jsx(Title, { level: 2, children: "\uCE58\uC218 \uC0B0\uD3EC \uACE0\uB3C4\uD654" }), _jsx(Paragraph, { children: "\uD30C\uD2B8\uBCC4\uB85C \uCD5C\uB300 3\uAC1C\uC758 \uC11C\uB85C \uB2E4\uB978 \uCD95(x/y/z) \uBC29\uD5A5 \uC0B0\uD3EC\uB97C \uC124\uC815\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4. \uAC01 \uD589\uC740 (Part, \uBC29\uD5A5) \uC870\uD569\uC73C\uB85C \uAD00\uB9AC\uB429\uB2C8\uB2E4." }), _jsx(PartIdFinderUploader, { onParsed: (filename, parts, file) => {
                        setKFileName(filename);
                        setAllPartInfos(parts);
                        setSelectedParts([]);
                        setUploadedKFile(file ?? null);
                    } }), _jsx(Text, { type: "secondary", children: kFileName }), _jsx(Divider, {}), _jsx(Title, { level: 4, children: "Part \uC120\uD0DD" }), _jsx(PartSelector, { allParts: allPartInfos, onSelect: handlePartSelect }), _jsx(Divider, {}), _jsx(Title, { level: 5, children: "\uD0A4\uC6CC\uB4DC\uB85C \uC77C\uAD04 \uC635\uC158 \uC801\uC6A9" }), _jsxs(Space, { wrap: true, align: "center", children: [_jsx(Input, { placeholder: "\uD0A4\uC6CC\uB4DC (id \uB610\uB294 name)", value: bulkKeyword, onChange: (e) => setBulkKeyword(e.target.value), style: { width: 260 }, allowClear: true }), _jsx(Select, { value: variationMethod, onChange: (value) => setVariationMethod(value), options: variationOptions.map((option) => ({
                                label: option,
                                value: option,
                            })), style: { width: 160 } }), _jsx(Select, { value: bulkDirection, onChange: setBulkDirection, options: [
                                { label: 'X', value: 'x' },
                                { label: 'Y', value: 'y' },
                                { label: 'Z', value: 'z' },
                            ], style: { width: 90 } }), variationMethod === "fixed" && (_jsxs(Space, { children: [_jsx(Text, { children: "\uAC12:" }), _jsx(InputNumber, { value: 1, disabled: true, style: { width: 100 } })] })), variationMethod === "최대/최소 등간격" && (_jsxs(Space, { children: [_jsx(Text, { children: "\uCD5C\uC18C:" }), _jsx(InputNumber, { value: minToleranceValue, onChange: (v) => setMinToleranceValue(v ?? 0), style: { width: 100 } }), _jsx(Text, { children: "\uCD5C\uB300:" }), _jsx(InputNumber, { value: maxToleranceValue, onChange: (v) => setMaxToleranceValue(v ?? 0), style: { width: 100 } })] })), variationMethod === "평균/표준편차" && (_jsxs(Space, { children: [_jsx(Text, { children: "\uD3C9\uADE0:" }), _jsx(InputNumber, { value: meanToleranceValue, onChange: (v) => setMeanToleranceValue(v ?? 0), style: { width: 100 } }), _jsx(Text, { children: "\u03C3:" }), _jsx(InputNumber, { value: stdDevToleranceValue, onChange: (v) => setStdDevToleranceValue(v ?? 0), style: { width: 100 } })] })), variationMethod === "최대 최소 LHS" && (_jsxs(Space, { children: [_jsx(Text, { children: "\uCD5C\uC18C:" }), _jsx(InputNumber, { value: lhsMinToleranceValue, onChange: (v) => setLhsMinToleranceValue(v ?? 0), style: { width: 100 } }), _jsx(Text, { children: "\uCD5C\uB300:" }), _jsx(InputNumber, { value: lhsMaxToleranceValue, onChange: (v) => setLhsMaxToleranceValue(v ?? 0), style: { width: 100 } })] })), variationMethod === "랜덤" && (_jsxs(Space, { children: [_jsx(Text, { children: "\uCD5C\uC18C:" }), _jsx(InputNumber, { value: randomMinToleranceValue, onChange: (v) => setRandomMinToleranceValue(v ?? 0), style: { width: 100 } }), _jsx(Text, { children: "\uCD5C\uB300:" }), _jsx(InputNumber, { value: randomMaxToleranceValue, onChange: (v) => setRandomMaxToleranceValue(v ?? 0), style: { width: 100 } })] })), _jsx(Button, { type: "primary", onClick: handleBulkApply, children: "\uC77C\uAD04 \uC801\uC6A9 (\uD544\uC694 \uC2DC \uD589 \uCD94\uAC00)" }), _jsx(Popconfirm, { title: "\uB9E4\uCE6D\uB41C \uD589(\uB610\uB294 \uC804\uCCB4)\uC744 \uC0AD\uC81C\uD560\uAE4C\uC694?", okText: "\uC0AD\uC81C", cancelText: "\uCDE8\uC18C", onConfirm: handleBulkClear, children: _jsx(Button, { danger: true, children: "\uC77C\uAD04 \uC0AD\uC81C" }) })] }), bulkKeyword && (_jsx("div", { style: { marginTop: 8 }, children: _jsxs(Text, { type: "secondary", children: ["\uD0A4\uC6CC\uB4DC \"", _jsx("b", { children: bulkKeyword }), "\" \uB85C \uB9E4\uCE6D\uB41C \uD30C\uD2B8: ", _jsx(Tag, { color: "blue", children: matchedParts.length }), "\uAC1C"] }) })), _jsx(Divider, {}), _jsx(Title, { level: 4, children: "\uD30C\uD2B8\uBCC4 \uCE58\uC218 \uC0B0\uD3EC \uC124\uC815 (\uCD5C\uB300 3\uD589/\uD30C\uD2B8)" }), _jsx(Table, { bordered: true, size: "small", dataSource: partRows, columns: columns, pagination: false, scroll: { x: 1000 }, rowKey: "key" }), _jsx(Divider, {}), _jsx(Title, { level: 4, children: "\uC0D8\uD50C \uC0DD\uC131" }), _jsxs(Space, { align: "center", wrap: true, children: [_jsx(Text, { children: "\uC0D8\uD50C \uAC1C\uC218 (\uB4F1\uAC04\uACA9 \uC81C\uC678):" }), _jsx(InputNumber, { min: 1, value: baseSamples, onChange: v => setBaseSamples((v ?? 1) | 0) }), _jsx(Text, { children: "\uB4F1\uAC04\uACA9 interval:" }), _jsx(InputNumber, { min: 1, value: intervalCount, onChange: v => setIntervalCount((v ?? 1) | 0) }), _jsx(Button, { type: "primary", onClick: generateSamples, children: "\uC0B0\uD3EC \uC0DD\uC131" }), _jsxs(Text, { type: "secondary", children: ["\uC804\uCCB4 \uC0D8\uD50C \uC218 \uBBF8\uB9AC\uBCF4\uAE30: ", _jsx("b", { children: totalSamplesPreview })] })] }), _jsx(Divider, {}), generatedData && (_jsx(ColoredScatter3DComponent, { data: generatedData, title: "\uCE58\uC218 \uC0B0\uD3EC \uC0D8\uD50C (3D + Color)" })), _jsx(Divider, {}), generatedData && (_jsx(ExportMeshModifierButton, { kFile: uploadedKFile, kFileName: kFileName || 'UNKNOWN.k', optionFileGenerator: () => {
                        if (!generatedData) {
                            message.error('먼저 샘플을 생성하세요.');
                            throw new Error('샘플이 생성되지 않았습니다.');
                        }
                        const { partIDs, directions, variableMatrix } = buildDimTolArgsFromGeneratedData(generatedData);
                        if (partIDs.length === 0) {
                            message.error('변수 컬럼을 찾지 못했습니다.');
                            throw new Error('변수 컬럼을 찾지 못했습니다.');
                        }
                        // generateDimensionalToleranceOptionFile 사용
                        return generateDimensionalToleranceOptionFile(kFileName || 'UNKNOWN.k', partIDs, directions, variableMatrix);
                    }, optionFileName: "dimensional_tolerance.txt" }))] }) }));
};
export default DimensionalTolerance;
