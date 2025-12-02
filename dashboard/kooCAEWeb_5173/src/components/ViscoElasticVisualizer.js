import { jsx as _jsx, jsxs as _jsxs, Fragment as _Fragment } from "react/jsx-runtime";
import React, { useState, useMemo } from 'react';
import { Form, InputNumber, Button, Select, Table, Typography, Card, Row, Col, Divider, Space, } from 'antd';
import Plot from 'react-plotly.js';
import { MathJax, MathJaxContext } from 'better-react-mathjax';
import { Canvas, useFrame } from '@react-three/fiber';
import { OrbitControls } from '@react-three/drei';
import { extend } from '@react-three/fiber';
import * as THREE from 'three';
extend(THREE);
const { Title, Paragraph, Text } = Typography;
const ViscoCube = ({ scaleVector, shearStrain, position = [0, 0, 0], color = 'orange', }) => {
    const ref = React.useRef(null);
    useFrame(() => {
        if (ref.current) {
            const magnify = 50;
            const γ = shearStrain * magnify;
            const matrix = new THREE.Matrix4();
            matrix.set(1, γ, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1);
            const scaleMatrix = new THREE.Matrix4().makeScale(scaleVector[0], scaleVector[1], scaleVector[2]);
            matrix.multiply(scaleMatrix);
            ref.current.matrixAutoUpdate = false;
            ref.current.matrix.copy(matrix);
        }
    });
    return React.createElement('mesh', { ref, position }, React.createElement('boxGeometry', { args: [1, 1, 1] }), React.createElement('meshStandardMaterial', { color, wireframe: true }));
};
const ViscoElasticVisualizer = () => {
    const [model, setModel] = useState('prony');
    const [bulkModulus, setBulkModulus] = useState(1000);
    const [strainRate, setStrainRate] = useState(0.1);
    const [compareStress, setCompareStress] = useState(5);
    const [pronyTerms, setPronyTerms] = useState([
        { tau: 0.01, g: 500 },
        { tau: 0.1, g: 300 },
        { tau: 1, g: 200 },
    ]);
    const [simpleParams, setSimpleParams] = useState({
        g0: 1000,
        gInf: 100,
        tau: 0.5,
    });
    const [G_inf, setGInf] = useState(100);
    const omegaRange = useMemo(() => {
        return Array.from({ length: 100 }, (_, i) => 10 ** (-1 + i * 4 / 99));
    }, []);
    const calcModuli = () => {
        const Gp = [];
        const Gpp = [];
        const Gabs = [];
        const tanDelta = [];
        omegaRange.forEach((omega) => {
            let Gstar = new mathComplex(0, 0);
            if (model === 'prony') {
                Gstar = Gstar.addScalar(G_inf);
                pronyTerms.forEach(({ tau, g }) => {
                    const jwTau = new mathComplex(0, omega * tau);
                    const term = jwTau.div(new mathComplex(1, omega * tau));
                    Gstar = Gstar.add(term.mulScalar(g));
                });
            }
            else {
                const { g0, gInf, tau } = simpleParams;
                const jwTau = new mathComplex(0, omega * tau);
                const term = jwTau.div(new mathComplex(1, omega * tau));
                Gstar = term.mulScalar(g0 - gInf).addScalar(gInf);
            }
            Gp.push(Gstar.re);
            Gpp.push(Gstar.im);
            Gabs.push(Math.sqrt(Gstar.re ** 2 + Gstar.im ** 2));
            tanDelta.push(Gstar.im / (Gstar.re || 1e-6));
        });
        return { Gp, Gpp, Gabs, tanDelta };
    };
    const { Gp, Gpp, Gabs, tanDelta } = useMemo(calcModuli, [
        model,
        pronyTerms,
        simpleParams,
        omegaRange,
    ]);
    const relaxationData = useMemo(() => {
        const times = Array.from({ length: 100 }, (_, i) => 10 ** (-3 + i * 5 / 99));
        const Gt = [];
        const Jt = [];
        times.forEach((t) => {
            let G = 0;
            let J = 0;
            if (model === 'prony') {
                G = G_inf + pronyTerms.reduce((acc, { tau, g }) => acc + g * Math.exp(-t / tau), 0);
                J = (1 / G_inf) + pronyTerms.reduce((acc, { tau, g }) => acc + (g / G_inf) * (1 - Math.exp(-t / tau)), 0);
            }
            else {
                const { g0, gInf, tau } = simpleParams;
                G = gInf + (g0 - gInf) * Math.exp(-t / tau);
                J = (1 / gInf) + ((g0 - gInf) / gInf) * (1 - Math.exp(-t / tau));
            }
            Gt.push(G);
            Jt.push(J);
        });
        return { times, Gt, Jt };
    }, [model, pronyTerms, simpleParams, G_inf]);
    const omegaIndex = 50;
    const GstarMid = Gabs[omegaIndex] || G_inf || 1;
    const poissonRatio = useMemo(() => {
        const G = GstarMid;
        const K = bulkModulus;
        return (3 * K - 2 * G) / (2 * (3 * K + G));
    }, [GstarMid, bulkModulus]);
    const elasticModulus = useMemo(() => {
        const G = GstarMid;
        const K = bulkModulus;
        return (9 * K * G) / (3 * K + G);
    }, [GstarMid, bulkModulus]);
    const compressiveStrain = useMemo(() => {
        return -compareStress / elasticModulus;
    }, [compareStress, elasticModulus]);
    const lateralStrain = useMemo(() => {
        return -compressiveStrain * poissonRatio;
    }, [compressiveStrain, poissonRatio]);
    const compressionScale = useMemo(() => {
        return [
            1 + compressiveStrain,
            1 + lateralStrain,
            1 + lateralStrain,
        ];
    }, [compressiveStrain, lateralStrain]);
    const omegaStrainRate = strainRate; // rad/s 로 가정
    const GstarForStrainRate = useMemo(() => {
        let Gstar = new mathComplex(0, 0);
        if (model === 'prony') {
            Gstar = Gstar.addScalar(G_inf);
            pronyTerms.forEach(({ tau, g }) => {
                const jwTau = new mathComplex(0, omegaStrainRate * tau);
                const term = jwTau.div(new mathComplex(1, omegaStrainRate * tau));
                Gstar = Gstar.add(term.mulScalar(g));
            });
        }
        else {
            const { g0, gInf, tau } = simpleParams;
            const jwTau = new mathComplex(0, omegaStrainRate * tau);
            const term = jwTau.div(new mathComplex(1, omegaStrainRate * tau));
            Gstar = term.mulScalar(g0 - gInf).addScalar(gInf);
        }
        return Math.sqrt(Gstar.re ** 2 + Gstar.im ** 2);
    }, [model, pronyTerms, simpleParams, G_inf, omegaStrainRate]);
    const shearStrainCompare = useMemo(() => {
        return compareStress / (GstarForStrainRate || 1);
    }, [compareStress, GstarForStrainRate]);
    return (_jsx(MathJaxContext, { children: _jsxs("div", { style: { padding: 24 }, children: [_jsx(Title, { children: "Viscoelastic Visualizer" }), _jsx(Divider, {}), _jsxs(Row, { gutter: 24, children: [_jsxs(Col, { span: 8, children: [_jsx(Card, { title: "Material Parameters", bordered: false, children: _jsxs(Form, { layout: "vertical", children: [_jsx(Form.Item, { label: "Model", children: _jsxs(Select, { value: model, onChange: (val) => setModel(val), children: [_jsx(Select.Option, { value: "prony", children: "Prony Series" }), _jsx(Select.Option, { value: "simple", children: "Simple Viscoelasticity" })] }) }), model === 'simple' && (_jsxs(_Fragment, { children: [_jsx(Form.Item, { label: "G0 (MPa)", children: _jsx(InputNumber, { style: { width: '100%' }, value: simpleParams.g0, onChange: (v) => setSimpleParams({ ...simpleParams, g0: v }) }) }), _jsx(Form.Item, { label: "G_inf (MPa)", children: _jsx(InputNumber, { style: { width: '100%' }, value: simpleParams.gInf, onChange: (v) => setSimpleParams({ ...simpleParams, gInf: v }) }) }), _jsx(Form.Item, { label: "Tau (s)", children: _jsx(InputNumber, { style: { width: '100%' }, value: simpleParams.tau, onChange: (v) => setSimpleParams({ ...simpleParams, tau: v }) }) })] })), model === 'prony' && (_jsxs(_Fragment, { children: [_jsx(Form.Item, { label: "G_inf (MPa)", children: _jsx(InputNumber, { style: { width: '100%' }, value: G_inf, onChange: (v) => setGInf(v) }) }), _jsxs(Form.Item, { label: "Prony Terms", children: [_jsx(Table, { size: "small", bordered: true, dataSource: pronyTerms.map((t, i) => ({
                                                                    ...t,
                                                                    key: i,
                                                                })), columns: [
                                                                    {
                                                                        title: 'Tau (s)',
                                                                        dataIndex: 'tau',
                                                                        render: (_, record, index) => (_jsx(InputNumber, { value: record.tau, onChange: (v) => {
                                                                                const updated = [...pronyTerms];
                                                                                updated[index].tau = v;
                                                                                setPronyTerms(updated);
                                                                            } })),
                                                                    },
                                                                    {
                                                                        title: 'g (MPa)',
                                                                        dataIndex: 'g',
                                                                        render: (_, record, index) => (_jsx(InputNumber, { value: record.g, onChange: (v) => {
                                                                                const updated = [...pronyTerms];
                                                                                updated[index].g = v;
                                                                                setPronyTerms(updated);
                                                                            } })),
                                                                    },
                                                                ], pagination: false }), _jsx(Button, { style: { marginTop: 8 }, block: true, onClick: () => setPronyTerms([...pronyTerms, { tau: 0.1, g: 100 }]), children: "Add Prony Term" })] })] })), _jsx(Form.Item, { label: "Bulk Modulus (MPa)", children: _jsx(InputNumber, { style: { width: '100%' }, value: bulkModulus, onChange: (v) => setBulkModulus(v) }) })] }) }), _jsx(Divider, {}), _jsx(Card, { title: "Equations", size: "small", bordered: false, children: _jsxs(Space, { direction: "vertical", style: { width: '100%' }, children: [_jsxs(Paragraph, { children: [_jsx(MathJax, { children: `\\[
                        G^*(\\omega) = G_{\\infty} + \\sum_{i=1}^{n}
                        \\frac{ g_i j \\omega \\tau_i }
                        { 1 + j \\omega \\tau_i }
                        \\]` }), "\uBCF5\uC18C \uC804\uB2E8 \uD0C4\uC131\uB960"] }), _jsxs(Paragraph, { children: [_jsx(MathJax, { children: `\\[
                      G'(\\omega) = \\Re\\left( G^*(\\omega) \\right)
                      \\]` }), "\uC800\uC7A5 \uD0C4\uC131\uB960"] }), _jsxs(Paragraph, { children: [_jsx(MathJax, { children: `\\[
                      G''(\\omega) = \\Im\\left( G^*(\\omega) \\right)
                      \\]` }), "\uC190\uC2E4 \uD0C4\uC131\uB960"] }), _jsxs(Paragraph, { children: [_jsx(MathJax, { children: `\\[
                      |G^*(\\omega)| = \\sqrt{ G'^2 + G''^2 }
                      \\]` }), "\uBCF5\uC18C \uD0C4\uC131\uB960\uC758 \uD06C\uAE30"] }), _jsxs(Paragraph, { children: [_jsx(MathJax, { children: `\\[
                      \\tan \\delta = \\frac{ G'' }{ G' }
                      \\]` }), "\uC190\uC2E4 \uD0C4\uC820\uD2B8"] }), _jsxs(Paragraph, { children: [_jsx(MathJax, { children: `\\[
                      G(t) = G_{\\infty} + \\sum_{i=1}^{n}
                      g_i e^{- t / \\tau_i }
                      \\]` }), "\uC751\uB825 \uC774\uC644"] }), _jsxs(Paragraph, { children: [_jsx(MathJax, { children: `\\[
                      J(t) = \\frac{1}{G_{\\infty}} +
                      \\sum_{i=1}^{n} \\frac{g_i}{G_{\\infty}}
                      (1 - e^{-t/\\tau_i})
                      \\]` }), "\uD06C\uB9AC\uD504 \uCEF4\uD50C\uB77C\uC774\uC5B8\uC2A4"] }), _jsxs(Paragraph, { children: [_jsx(MathJax, { children: `\\[
                      \\nu = \\frac{3K - 2G}{2(3K + G)}
                      \\]` }), "\uD478\uC544\uC1A1\uBE44"] }), _jsxs(Paragraph, { children: [_jsx(MathJax, { children: `\\[
                      \\varepsilon_{xx} = -\\frac{\\sigma}{E}
                      \\]` }), "\uB2E8\uCD95 \uC555\uCD95 \uBCC0\uD615\uB960"] }), _jsxs(Paragraph, { children: [_jsx(MathJax, { children: `\\[
                      \\varepsilon_{yy} = \\varepsilon_{zz} = \\nu \\cdot \\frac{\\sigma}{E}
                      \\]` }), "\uCE21\uBCC0 \uC778\uC7A5 \uBCC0\uD615\uB960"] }), _jsxs(Paragraph, { children: [_jsx(MathJax, { children: `\\[
                      \\gamma = \\frac{\\tau}{|G^*(\\omega)|}
                      \\]` }), "\uC804\uB2E8 \uBCC0\uD615\uB960"] })] }) })] }), _jsxs(Col, { span: 16, children: [_jsx(Card, { title: "Frequency Domain (Storage/Loss/Complex Moduli)", bordered: false, children: _jsx(Plot, { data: [
                                            { x: omegaRange, y: Gp, name: 'G′ (Storage Modulus)', type: 'scatter', mode: 'lines' },
                                            { x: omegaRange, y: Gpp, name: 'G″ (Loss Modulus)', type: 'scatter', mode: 'lines' },
                                            { x: omegaRange, y: Gabs, name: '|G*| (Complex Modulus)', type: 'scatter', mode: 'lines' },
                                        ], layout: {
                                            xaxis: {
                                                type: 'log',
                                                title: { text: 'Angular Frequency ω [rad/s]', font: { size: 16 } },
                                            },
                                            yaxis: {
                                                title: { text: 'Modulus [MPa]', font: { size: 16 } },
                                            },
                                            height: 400,
                                            legend: {
                                                orientation: 'h',
                                                y: 1.15,
                                            },
                                            margin: { t: 50, b: 70, l: 60, r: 30 },
                                        }, useResizeHandler: true, style: { width: '100%', height: '100%' } }) }), _jsx(Divider, {}), _jsx(Card, { title: "Loss Tangent", bordered: false, children: _jsx(Plot, { data: [
                                            { x: omegaRange, y: tanDelta, name: 'tanδ', type: 'scatter', mode: 'lines' },
                                        ], layout: {
                                            xaxis: {
                                                type: 'log',
                                                title: { text: 'Angular Frequency ω [rad/s]', font: { size: 16 } },
                                            },
                                            yaxis: {
                                                title: { text: 'tanδ [unitless]', font: { size: 16 } },
                                                type: 'log',
                                            },
                                            height: 400,
                                            legend: { orientation: 'h' },
                                            margin: { t: 30, b: 50, l: 60, r: 30 },
                                        }, useResizeHandler: true, style: { width: '100%', height: '100%' } }) }), _jsx(Divider, {}), _jsx(Card, { title: "Time Domain (Relaxation & Creep)", bordered: false, children: _jsx(Plot, { data: [
                                            {
                                                x: relaxationData.times,
                                                y: relaxationData.Gt,
                                                name: 'G(t) (Relaxation Modulus)',
                                                type: 'scatter',
                                                mode: 'lines'
                                            },
                                            {
                                                x: relaxationData.times,
                                                y: relaxationData.Jt,
                                                name: 'J(t) (Creep Compliance)',
                                                type: 'scatter',
                                                mode: 'lines'
                                            },
                                        ], layout: {
                                            xaxis: {
                                                type: 'log',
                                                title: { text: 'Time [s]', font: { size: 16 } },
                                            },
                                            yaxis: {
                                                title: { text: 'Modulus [MPa] / Compliance [1/MPa]', font: { size: 16 } },
                                            },
                                            height: 400,
                                            legend: {
                                                orientation: 'h',
                                                y: 1.15,
                                            },
                                            margin: { t: 50, b: 70, l: 60, r: 30 },
                                        }, useResizeHandler: true, style: { width: '100%', height: '100%' } }) }), _jsx(Divider, {}), _jsx(Card, { title: "Cube Controls", bordered: false, children: _jsxs(Form, { layout: "vertical", children: [_jsx(Form.Item, { label: "Stress (MPa)", children: _jsx(InputNumber, { style: { width: '100%' }, value: compareStress, onChange: (v) => setCompareStress(v) }) }), _jsx(Form.Item, { label: "Strain Rate (1/s)", children: _jsx(InputNumber, { style: { width: '100%' }, value: strainRate, onChange: (v) => setStrainRate(v) }) })] }) }), _jsx(Divider, {}), _jsxs(Card, { title: "3D Cube Visualization", bordered: false, children: [_jsx("div", { style: { height: 400 }, children: _jsxs(Canvas, { camera: { position: [5, 3, 5] }, children: [_jsx("ambientLight", {}), _jsx("directionalLight", { position: [5, 5, 5] }), _jsx(OrbitControls, {}), _jsx("axesHelper", { args: [2] }), _jsx(ViscoCube, { position: [-2, 0, 0], scaleVector: compressionScale, shearStrain: 0, color: "blue" }), _jsx(ViscoCube, { position: [2, 0, 0], scaleVector: [1, 1, 1], shearStrain: shearStrainCompare, color: "red" })] }) }), _jsxs(Paragraph, { children: [_jsx(Text, { strong: true, children: "Compression strain x:" }), " ", compressiveStrain.toExponential(3), _jsx("br", {}), _jsx(Text, { strong: true, children: "Lateral strain y/z:" }), " ", lateralStrain.toExponential(3), _jsx("br", {}), _jsx(Text, { strong: true, children: "Shear strain:" }), " ", shearStrainCompare.toExponential(3)] })] })] })] })] }) }));
};
export default ViscoElasticVisualizer;
/** ---- Math Complex Class ---- **/
class mathComplex {
    re;
    im;
    constructor(re, im) {
        this.re = re;
        this.im = im;
    }
    add(other) {
        return new mathComplex(this.re + other.re, this.im + other.im);
    }
    addScalar(s) {
        return new mathComplex(this.re + s, this.im);
    }
    mulScalar(s) {
        return new mathComplex(this.re * s, this.im * s);
    }
    div(other) {
        const denom = other.re ** 2 + other.im ** 2;
        return new mathComplex((this.re * other.re + this.im * other.im) / denom, (this.im * other.re - this.re * other.im) / denom);
    }
}
