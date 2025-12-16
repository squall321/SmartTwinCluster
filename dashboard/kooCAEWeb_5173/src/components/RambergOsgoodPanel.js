import { jsx as _jsx, jsxs as _jsxs, Fragment as _Fragment } from "react/jsx-runtime";
import { useState, useEffect } from "react";
import { Form, InputNumber, Button, Descriptions, Divider, Typography, Row, Col, Card, } from "antd";
import Plot from "react-plotly.js";
import { BlockMath, InlineMath } from "react-katex";
import "katex/dist/katex.min.css";
const { Title, Paragraph } = Typography;
const RambergOsgoodPanel = () => {
    // -----------------------------
    // 상태
    // -----------------------------
    // Material props
    const [E, setE] = useState(200); // GPa
    const [density, setDensity] = useState(7.85); // g/cm³
    // Ramberg-Osgood params
    const [sigma0, setSigma0] = useState(250); // MPa
    const [K, setK] = useState(0.02);
    const [n, setN] = useState(2.0);
    const [offsetStrainPct, setOffsetStrainPct] = useState(0.2);
    // Fracture strain
    const [fractureStrain, setFractureStrain] = useState(null);
    // Fatigue parameters
    const [sigmaFPrime, setSigmaFPrime] = useState(null);
    const [b, setB] = useState(null);
    const [epsilonFPrime, setEpsilonFPrime] = useState(null);
    const [c, setC] = useState(null);
    // Computed curve
    const [strainData, setStrainData] = useState([]);
    const [stressData, setStressData] = useState([]);
    // Fatigue curves
    const [snData, setSnData] = useState([]);
    const [enData, setEnData] = useState([]);
    const [sigma02, setSigma02] = useState(null);
    const [sigmaMax, setSigmaMax] = useState(null);
    // -----------------------------
    // 계산 함수들
    // -----------------------------
    const calcStrain = (sigma) => {
        const elastic = sigma / (E * 1e3);
        const plastic = K * Math.pow(sigma / sigma0, n);
        return elastic + plastic;
    };
    const calcSigma02 = () => {
        const epsOffset = offsetStrainPct / 100;
        const f = (sigma) => {
            return calcStrain(sigma) - (epsOffset + sigma / (E * 1e3));
        };
        let lower = 0;
        let upper = sigma0 * 5;
        let mid;
        for (let i = 0; i < 50; i++) {
            mid = (lower + upper) / 2;
            const val = f(mid);
            if (Math.abs(val) < 1e-6)
                break;
            if (val > 0)
                upper = mid;
            else
                lower = mid;
        }
        return mid;
    };
    const generateCurve = () => {
        const stressArr = [];
        const strainArr = [];
        for (let sigma = 0; sigma <= sigma0 * 5; sigma += sigma0 * 5 / 500) {
            const eps = calcStrain(sigma);
            if (fractureStrain !== null && eps > fractureStrain)
                break;
            stressArr.push(sigma);
            strainArr.push(eps);
        }
        setStressData(stressArr);
        setStrainData(strainArr);
        setSigmaMax(Math.max(...stressArr));
    };
    const generateFatigueCurves = () => {
        if (sigmaFPrime === null ||
            b === null ||
            epsilonFPrime === null ||
            c === null) {
            setSnData([]);
            setEnData([]);
            return;
        }
        const Ncycles = [];
        const stressAmplitude = [];
        const strainAmplitude = [];
        for (let logN = 3; logN <= 6; logN += 0.1) {
            const N = Math.pow(10, logN) / 2; // 2N_f
            const sa = sigmaFPrime * Math.pow(N, b);
            const ea = epsilonFPrime * Math.pow(N, c);
            Ncycles.push(N * 2);
            stressAmplitude.push(sa);
            strainAmplitude.push(ea);
        }
        setSnData([
            {
                x: Ncycles,
                y: stressAmplitude,
                mode: "lines+markers",
                name: "SN Curve",
            },
        ]);
        setEnData([
            {
                x: Ncycles,
                y: strainAmplitude,
                mode: "lines+markers",
                name: "ε-N Curve",
            },
        ]);
    };
    // -----------------------------
    // Hooks
    // -----------------------------
    useEffect(() => {
        const s02 = calcSigma02();
        setSigma02(s02);
        generateCurve();
    }, [E, sigma0, K, n, offsetStrainPct, fractureStrain]);
    useEffect(() => {
        generateFatigueCurves();
    }, [sigmaFPrime, b, epsilonFPrime, c]);
    // -----------------------------
    // Graph Click
    // -----------------------------
    const handleGraphClick = (e) => {
        const x = e.points?.[0]?.x;
        if (x !== undefined) {
            setFractureStrain(x / 100);
            const newSigmaFPrime = sigma0 * 1.5;
            const newB = -0.08;
            const newEpsilonFPrime = 0.5 * x;
            const newC = -0.5;
            setSigmaFPrime(newSigmaFPrime);
            setB(newB);
            setEpsilonFPrime(newEpsilonFPrime);
            setC(newC);
        }
    };
    const resetFractureStrain = () => {
        setFractureStrain(null);
        setSigmaFPrime(null);
        setB(null);
        setEpsilonFPrime(null);
        setC(null);
    };
    const generateTotalStrainLifeCurve = () => {
        if (sigmaFPrime === null ||
            b === null ||
            epsilonFPrime === null ||
            c === null) {
            return [];
        }
        const Ncycles = [];
        const totalStrainAmplitude = [];
        for (let logN = 3; logN <= 6; logN += 0.1) {
            const N = Math.pow(10, logN) / 2; // 2N_f
            const elasticStrain = (sigmaFPrime / (E * 1e3)) * Math.pow(N, b);
            const plasticStrain = epsilonFPrime * Math.pow(N, c);
            const total = elasticStrain + plasticStrain;
            Ncycles.push(N * 2);
            totalStrainAmplitude.push(total);
        }
        return [{
                x: Ncycles,
                y: totalStrainAmplitude,
                mode: "lines+markers",
                name: "Total Strain-Life Curve"
            }];
    };
    // -----------------------------
    // Render
    // -----------------------------
    return (_jsxs(_Fragment, { children: [_jsx(Title, { level: 3, children: "Ramberg-Osgood Material Model" }), _jsxs(Paragraph, { children: ["Ramberg-Osgood \uBAA8\uB378\uC740 \uAE08\uC18D \uC7AC\uB8CC\uC758 \uD0C4\uC131-\uC18C\uC131 \uAC70\uB3D9\uC744 \uD45C\uD604\uD558\uAE30 \uC704\uD574 \uC0AC\uC6A9\uB418\uBA70, \uC751\uB825(", _jsx(InlineMath, { math: "\\sigma" }), ")\uACFC \uBCC0\uD615\uB960(", _jsx(InlineMath, { math: "\\varepsilon" }), ") \uC0AC\uC774\uC758 \uBE44\uC120\uD615 \uAD00\uACC4\uB97C \uB098\uD0C0\uB0C5\uB2C8\uB2E4."] }), _jsx(BlockMath, { math: String.raw `\varepsilon = \frac{\sigma}{E} + K \cdot \left(\frac{\sigma}{\sigma_0}\right)^n` }), _jsxs(Row, { gutter: 16, children: [_jsx(Col, { xs: 24, md: 12, children: _jsx(Card, { title: "Material Properties", size: "small", children: _jsxs(Form, { layout: "vertical", children: [_jsx(Form.Item, { label: "Young's Modulus E (GPa)", children: _jsx(InputNumber, { min: 1, value: E, onChange: (value) => setE(value || 0), style: { width: "100%" } }) }), _jsx(Form.Item, { label: "Density (g/cm\u00B3)", children: _jsx(InputNumber, { min: 0.1, value: density, onChange: (value) => setDensity(value || 0), style: { width: "100%" } }) }), _jsx(Form.Item, { label: "Offset Yield Stress \u03C3\u2080 (MPa)", children: _jsx(InputNumber, { min: 1, value: sigma0, onChange: (value) => setSigma0(value || 0), style: { width: "100%" } }) })] }) }) }), _jsx(Col, { xs: 24, md: 12, children: _jsx(Card, { title: "Ramberg-Osgood Parameters", size: "small", children: _jsxs(Form, { layout: "vertical", children: [_jsx(Form.Item, { label: "Strength Coefficient K", children: _jsx(InputNumber, { min: 0.0001, step: 0.0001, value: K, onChange: (value) => setK(value || 0.0001), style: { width: "100%" } }) }), _jsx(Form.Item, { label: "Strain Hardening Exponent n", children: _jsx(InputNumber, { min: 1, step: 0.01, value: n, onChange: (value) => setN(value || 1), style: { width: "100%" } }) }), _jsx(Form.Item, { label: "Offset Strain (%)", children: _jsx(InputNumber, { min: 0.01, max: 1, step: 0.01, value: offsetStrainPct, onChange: (value) => setOffsetStrainPct(value || 0), style: { width: "100%" } }) })] }) }) })] }), _jsx(Divider, {}), _jsxs(Card, { title: "Stress-Strain Curve", size: "small", style: { marginBottom: "24px" }, children: [_jsx(Plot, { data: [
                            {
                                x: strainData.map((v) => v * 100),
                                y: stressData,
                                mode: "lines+markers",
                                marker: { size: 4 },
                                name: "Stress-Strain Curve",
                            },
                            ...(fractureStrain !== null
                                ? [
                                    {
                                        x: [fractureStrain * 100, fractureStrain * 100],
                                        y: [0, Math.max(...stressData)],
                                        type: "scatter",
                                        mode: "lines",
                                        line: { color: "red", dash: "dot" },
                                        name: "Fracture Strain",
                                    },
                                ]
                                : []),
                        ], layout: {
                            height: 500,
                            autosize: true,
                            title: "Stress-Strain Curve",
                            margin: { l: 40, r: 20, t: 40, b: 40 },
                            xaxis: { title: "Strain (%)", type: "linear" },
                            yaxis: { title: "Stress (MPa)" },
                        }, config: {
                            responsive: true,
                        }, useResizeHandler: true, style: { width: "100%", height: "100%" }, onClick: handleGraphClick }), _jsx(Button, { danger: true, onClick: resetFractureStrain, style: { marginTop: "10px", marginBottom: "10px" }, children: "Fracture Strain \uCD08\uAE30\uD654" })] }), _jsx(Divider, {}), _jsx(Card, { title: "Calculated Properties", size: "small", children: _jsxs(Descriptions, { bordered: true, column: 1, children: [_jsxs(Descriptions.Item, { label: "Offset Yield Strength \u03C3\u2080.\u2082", children: [sigma02?.toFixed(2), " MPa"] }), _jsxs(Descriptions.Item, { label: "Ultimate Strength", children: [sigmaMax?.toFixed(2), " MPa"] }), _jsx(Descriptions.Item, { label: "Fracture Strain", children: fractureStrain !== null
                                ? `${(fractureStrain * 100).toFixed(4)} %`
                                : "미지정" })] }) }), fractureStrain !== null && (_jsxs(_Fragment, { children: [_jsx(Divider, {}), _jsxs(Card, { title: "Fatigue Parameters", size: "small", children: [_jsx(Paragraph, { children: "\uD53C\uB85C \uD574\uC11D\uC5D0 \uC0AC\uC6A9\uB418\uB294 Basquin \uBC95\uCE59\uACFC Coffin-Manson \uBC95\uCE59\uC740 \uC7AC\uB8CC\uC758 \uACE0\uC8FC\uAE30 \uBC0F \uC800\uC8FC\uAE30 \uD53C\uB85C \uC218\uBA85\uC744 \uC608\uCE21\uD569\uB2C8\uB2E4." }), _jsx(Paragraph, { strong: true, children: "Basquin" }), _jsx(BlockMath, { math: String.raw `\sigma_a = \sigma'_f \cdot \left(2N_f\right)^b` }), _jsxs(Paragraph, { children: ["Basquin \uC2DD\uC740 \uC751\uB825 \uC9C4\uD3ED(", _jsx(InlineMath, { math: "\\sigma_a" }), ")\uACFC \uD53C\uB85C \uC218\uBA85(", _jsx(InlineMath, { math: "N_f" }), ")\uC758 \uAD00\uACC4\uB97C \uB098\uD0C0\uB0C5\uB2C8\uB2E4."] }), _jsx(Paragraph, { strong: true, children: "Coffin-Manson" }), _jsx(BlockMath, { math: String.raw `\varepsilon_a = \varepsilon'_f \cdot \left(2N_f\right)^c` }), _jsxs(Paragraph, { children: ["Coffin-Manson \uC2DD\uC740 \uC18C\uC131 \uBCC0\uD615\uB960 \uC9C4\uD3ED(", _jsx(InlineMath, { math: "\\varepsilon_a" }), ")\uACFC \uC218\uBA85\uC758 \uAD00\uACC4\uB97C \uC124\uBA85\uD558\uBA70 \uC800\uC8FC\uAE30 \uD53C\uB85C \uD574\uC11D\uC5D0 \uC4F0\uC785\uB2C8\uB2E4."] }), _jsx(Paragraph, { strong: true, children: "Total Strain-Life (Manson\u2013Coffin\u2013Basquin)" }), _jsx(BlockMath, { math: String.raw `\varepsilon_a 
                = \frac{\sigma'_f}{E} \cdot \left(2N_f\right)^b 
                + \varepsilon'_f \cdot \left(2N_f\right)^c` }), _jsx(Paragraph, { children: "\u2022 \uCCAB \uD56D\uC740 \uD0C4\uC131 \uBCC0\uD615\uB960, \uB450 \uBC88\uC9F8 \uD56D\uC740 \uC18C\uC131 \uBCC0\uD615\uB960\uB85C, \uACE0\uC8FC\uAE30/\uC800\uC8FC\uAE30 \uD53C\uB85C \uC218\uBA85\uC744 \uBAA8\uB450 \uC124\uBA85\uD569\uB2C8\uB2E4." }), _jsxs(Row, { gutter: 16, children: [_jsx(Col, { xs: 24, md: 12, children: _jsx(Form.Item, { label: "Basquin Coefficient \u03C3\u2032f (MPa)", children: _jsx(InputNumber, { min: 1, value: sigmaFPrime ?? undefined, onChange: setSigmaFPrime, style: { width: "100%" } }) }) }), _jsx(Col, { xs: 24, md: 12, children: _jsx(Form.Item, { label: "Basquin Exponent b", children: _jsx(InputNumber, { step: 0.01, value: b ?? undefined, onChange: setB, style: { width: "100%" } }) }) }), _jsx(Col, { xs: 24, md: 12, children: _jsx(Form.Item, { label: "Coffin-Manson Coefficient \u03B5\u2032f", children: _jsx(InputNumber, { min: 0, step: 0.0001, value: epsilonFPrime ?? undefined, onChange: setEpsilonFPrime, style: { width: "100%" } }) }) }), _jsx(Col, { xs: 24, md: 12, children: _jsx(Form.Item, { label: "Coffin-Manson Exponent c", children: _jsx(InputNumber, { step: 0.01, value: c ?? undefined, onChange: setC, style: { width: "100%" } }) }) })] })] })] })), snData.length > 0 && (_jsxs(_Fragment, { children: [_jsx(Divider, {}), _jsx(Card, { title: "SN Curve", size: "small", style: { marginBottom: "24px" }, styles: { body: { padding: 0, height: "100%" } }, children: _jsx(Plot, { data: snData, layout: {
                                autosize: true,
                                height: 400,
                                margin: { l: 50, r: 30, t: 40, b: 50 },
                                title: "SN Curve",
                                xaxis: { title: "Cycles to failure (N)", type: "log" },
                                yaxis: { title: "Stress Amplitude (MPa)", type: "log" },
                            }, config: { responsive: true }, useResizeHandler: true, style: { width: "100%", height: "100%" } }) })] })), enData.length > 0 && (_jsxs(_Fragment, { children: [_jsx(Divider, {}), _jsx(Card, { title: "\u03B5-N Curve", size: "small", style: { marginBottom: "24px" }, styles: { body: { padding: 0, height: "100%" } }, children: _jsx(Plot, { data: enData, layout: {
                                autosize: true,
                                height: 400,
                                margin: { l: 50, r: 30, t: 40, b: 50 },
                                title: "ε-N Curve",
                                xaxis: { title: "Cycles to failure (N)", type: "log" },
                                yaxis: { title: "Strain Amplitude", type: "log" },
                            }, config: { responsive: true }, useResizeHandler: true, style: { width: "100%", height: "100%" } }) })] })), fractureStrain !== null && (_jsxs(_Fragment, { children: [_jsx(Divider, {}), _jsx(Card, { title: "Total Strain-Life Curve", size: "small", style: { marginBottom: "24px" }, bodyStyle: { padding: 0 }, children: _jsx(Plot, { data: generateTotalStrainLifeCurve(), layout: {
                                autosize: true,
                                height: 400,
                                margin: { l: 50, r: 30, t: 40, b: 50 },
                                title: "Total Strain-Life Curve",
                                xaxis: { title: "Cycles to failure (N)", type: "log" },
                                yaxis: { title: "Strain Amplitude", type: "log" },
                            }, config: { responsive: true }, useResizeHandler: true, style: { width: "100%", height: "100%" } }) })] }))] }));
};
export default RambergOsgoodPanel;
