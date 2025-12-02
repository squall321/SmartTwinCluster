import { jsx as _jsx, jsxs as _jsxs, Fragment as _Fragment } from "react/jsx-runtime";
import { useRef, useState, useEffect } from 'react';
import { Canvas, useFrame } from '@react-three/fiber';
import { OrbitControls } from '@react-three/drei';
import { Slider, Typography, Row, Col, Card, Button, Space, Progress } from 'antd';
import { Line } from '@ant-design/plots';
const { Title, Paragraph } = Typography;
const gravity = 9.81;
const floorY = 0;
const Ball = ({ contactStiffness, mass, initialVelocity, dt, initialHeight, running, onRecord, }) => {
    const meshRef = useRef(null);
    const [positionY, setPositionY] = useState(initialHeight);
    const [velocity, setVelocity] = useState(initialVelocity);
    const [time, setTime] = useState(0);
    const physicsStepTarget = 1 / 60;
    let accumulatedTime = 0;
    useEffect(() => {
        setPositionY(initialHeight);
        setVelocity(initialVelocity);
        setTime(0);
    }, [initialHeight, running, initialVelocity]);
    useFrame((_, delta) => {
        if (!running)
            return;
        accumulatedTime += delta;
        let posY = positionY;
        let vel = velocity;
        let t = time;
        while (accumulatedTime >= physicsStepTarget) {
            const numSteps = Math.floor(physicsStepTarget / dt);
            for (let i = 0; i < numSteps; i++) {
                let penetrationDepth = 0;
                let force = 0;
                if (posY <= floorY) {
                    penetrationDepth = floorY - posY;
                    force = contactStiffness * penetrationDepth;
                    const acc = (force / mass) - gravity;
                    vel += acc * dt;
                }
                else {
                    vel += -gravity * dt;
                }
                posY += vel * dt;
                t += dt;
            }
            accumulatedTime -= physicsStepTarget;
        }
        onRecord(t, posY);
        setPositionY(posY);
        setVelocity(vel);
        setTime(t);
        if (meshRef.current) {
            meshRef.current.position.y = posY;
        }
    });
    return (_jsxs(_Fragment, { children: [_jsxs("mesh", { ref: meshRef, children: [_jsx("sphereGeometry", { args: [0.5, 32, 32] }), _jsx("meshStandardMaterial", { color: positionY < floorY ? 'red' : 'orange', opacity: 0.8, transparent: true })] }), _jsxs("mesh", { rotation: [-Math.PI / 2, 0, 0], position: [0, 0, 0], children: [_jsx("planeGeometry", { args: [10, 10] }), _jsx("meshStandardMaterial", { color: "lightgray" })] })] }));
};
const ContactStiffnessDemoComponent = () => {
    const [contactStiffness, setContactStiffness] = useState(1e4);
    const [mass, setMass] = useState(1);
    const [dt, setDt] = useState(0.001);
    const [initialHeight, setInitialHeight] = useState(5);
    const [running, setRunning] = useState(false);
    // 추가된 state
    const [youngsModulus, setYoungsModulus] = useState(210000); // MPa
    const [hMin, setHMin] = useState(1); // mm
    const [contactArea, setContactArea] = useState(100); // mm²
    const [alphaFactor, setAlphaFactor] = useState(0.5);
    // System dt 관련 state
    const [hSys, setHSys] = useState(0.1); // mm
    const [eSys, setESys] = useState(210000); // MPa
    const [rhoSys, setRhoSys] = useState(7800); // kg/m³
    const [data, setData] = useState([]);
    // Δt 안정 조건
    const omegaMax = Math.sqrt(contactStiffness / mass);
    const stableDt = 2 / omegaMax;
    // Mesh stiffness 계산
    const meshStiffness = (youngsModulus * contactArea) / hMin * 1e6; // N/m
    const ratio = contactStiffness / meshStiffness;
    // dt 기반 stiffness 한도
    const kMaxByDt = (4 * mass) / (dt * dt);
    // System wave speed
    const cSys = Math.sqrt((eSys * 1e6) / rhoSys); // m/s
    const dtSystem = (hSys * 1e-3) / cSys; // s
    const kMaxBySystemDt = (4 * mass) / (dtSystem * dtSystem);
    const effectiveContactStiffness = Math.min(contactStiffness, kMaxByDt, kMaxBySystemDt);
    const handleStart = () => {
        setData([]);
        setRunning(true);
    };
    const handleStop = () => {
        setRunning(false);
    };
    const handleReset = () => {
        setRunning(false);
        setData([]);
    };
    const handleRecord = (time, y) => {
        if (Math.floor(time * 30) % 30 === 0) {
            setData((prev) => [...prev, { time, y }]);
        }
    };
    const handleApplyRecommended = () => {
        const kContact = (alphaFactor * youngsModulus * contactArea) / hMin * 1e6;
        setContactStiffness(kContact);
    };
    const config = {
        data,
        xField: 'time',
        yField: 'y',
        height: 300,
        smooth: true,
        lineStyle: { stroke: '#ff7300', lineWidth: 2 },
        yAxis: {
            min: -1,
            title: { text: 'Height (m)' },
        },
        xAxis: {
            title: { text: 'Time (s)' },
        },
    };
    return (_jsxs(Row, { gutter: 16, children: [_jsx(Col, { span: 12, children: _jsxs(Canvas, { camera: { position: [0, 5, 10], fov: 50 }, children: [_jsx("ambientLight", {}), _jsx("pointLight", { position: [10, 10, 10] }), _jsx(Ball, { contactStiffness: effectiveContactStiffness, mass: mass, initialVelocity: 0, dt: dt, initialHeight: initialHeight, running: running, onRecord: handleRecord }), _jsx(OrbitControls, {})] }) }), _jsx(Col, { span: 12, children: _jsxs(Card, { children: [_jsx(Title, { level: 4, children: "Contact Stiffness Demo" }), _jsxs(Space, { direction: "vertical", style: { width: '100%' }, children: [_jsxs(Paragraph, { children: [_jsx("b", { children: "Initial Height:" }), " ", initialHeight.toFixed(2), " m"] }), _jsx(Slider, { min: 0.5, max: 10, step: 0.1, value: initialHeight, onChange: setInitialHeight }), _jsxs(Paragraph, { children: [_jsx("b", { children: "Young\u2019s Modulus:" }), " ", youngsModulus.toExponential(2), " MPa"] }), _jsx(Slider, { min: 100, max: 500000, step: 100, value: youngsModulus, onChange: setYoungsModulus }), _jsxs(Paragraph, { children: [_jsx("b", { children: "h_min (Element Size):" }), " ", hMin.toFixed(2), " mm"] }), _jsx(Slider, { min: 0.1, max: 10, step: 0.1, value: hMin, onChange: setHMin }), _jsxs(Paragraph, { children: [_jsx("b", { children: "Contact Area:" }), " ", contactArea.toFixed(2), " mm\u00B2"] }), _jsx(Slider, { min: 1, max: 1000, step: 1, value: contactArea, onChange: setContactArea }), _jsxs(Paragraph, { children: [_jsx("b", { children: "Alpha Factor:" }), " ", alphaFactor.toFixed(2)] }), _jsx(Slider, { min: 0.1, max: 1, step: 0.1, value: alphaFactor, onChange: setAlphaFactor }), _jsx(Button, { onClick: handleApplyRecommended, children: "Apply Recommended Stiffness" }), _jsxs(Paragraph, { children: [_jsx("b", { children: "Recommended Contact Stiffness:" }), " ", ((alphaFactor * youngsModulus * contactArea) /
                                            hMin *
                                            1e6).toExponential(2), " N/m"] }), _jsxs(Paragraph, { children: [_jsx("b", { children: "Contact Stiffness:" }), " ", contactStiffness.toExponential(2), " N/m"] }), _jsx(Slider, { min: 100, max: 1e15, step: 100, value: contactStiffness, onChange: setContactStiffness, tooltip: { formatter: (v) => v?.toExponential(2) } }), _jsxs(Paragraph, { children: [_jsx("b", { children: "Mesh Stiffness:" }), " ", meshStiffness.toExponential(2), " N/m"] }), _jsxs(Paragraph, { children: [_jsx("b", { children: "Contact / Mesh Stiffness Ratio:" }), " ", ratio.toFixed(2)] }), _jsx(Progress, { percent: Math.min(ratio * 10, 100), status: ratio < 2
                                        ? "success"
                                        : ratio < 10
                                            ? "active"
                                            : "exception" }), ratio > 10 && (_jsx(Paragraph, { type: "danger", children: "\u26A0\uFE0F Contact stiffness may be excessive vs mesh stiffness!" })), _jsxs(Paragraph, { children: [_jsx("b", { children: "System Min Element Size:" }), " ", hSys.toFixed(3), " mm"] }), _jsx(Slider, { min: 0.01, max: 10, step: 0.01, value: hSys, onChange: setHSys }), _jsxs(Paragraph, { children: [_jsx("b", { children: "System Young\u2019s Modulus:" }), " ", eSys.toExponential(2), " MPa"] }), _jsx(Slider, { min: 100, max: 500000, step: 100, value: eSys, onChange: setESys }), _jsxs(Paragraph, { children: [_jsx("b", { children: "System Density:" }), " ", rhoSys.toFixed(1), " kg/m\u00B3"] }), _jsx(Slider, { min: 1000, max: 9000, step: 100, value: rhoSys, onChange: setRhoSys }), _jsxs(Paragraph, { children: [_jsx("b", { children: "Calculated System \u0394t:" }), " ", dtSystem.toExponential(2), " s"] }), _jsxs(Paragraph, { children: [_jsx("b", { children: "Max Contact Stiffness allowed by System \u0394t:" }), " ", kMaxBySystemDt.toExponential(2), " N/m"] }), _jsxs(Paragraph, { children: [_jsx("b", { children: "Time Step (dt):" }), " ", dt.toExponential(2), " s"] }), _jsx(Slider, { min: 1e-9, max: 1e-2, step: 1e-5, value: dt, onChange: setDt, tooltip: { formatter: (v) => v?.toExponential(2) } }), _jsxs(Paragraph, { children: [_jsx("b", { children: "\u0394t Stability Limit:" }), " ", stableDt.toExponential(2), " s"] }), _jsxs(Paragraph, { children: [_jsx("b", { children: "Max Contact Stiffness allowed by dt:" }), " ", kMaxByDt.toExponential(2), " N/m"] }), _jsxs(Paragraph, { children: [_jsx("b", { children: "Effective Contact Stiffness used:" }), " ", effectiveContactStiffness.toExponential(2), " N/m"] }), _jsx(Paragraph, { type: contactStiffness > kMaxBySystemDt ? 'danger' : undefined, children: contactStiffness > kMaxBySystemDt
                                        ? '⚠️ Contact stiffness exceeds system dt limit! Auto-reduced.'
                                        : '✔️ Contact stiffness is OK for system dt.' }), _jsxs(Space, { children: [_jsx(Button, { type: "primary", onClick: handleStart, disabled: running, children: "\u25B6\uFE0F Start" }), _jsx(Button, { onClick: handleStop, disabled: !running, children: "\u23F8\uFE0F Stop" }), _jsx(Button, { onClick: handleReset, children: "\uD83D\uDD04 Reset" })] }), _jsx(Title, { level: 5, children: "Height vs Time" }), _jsx(Line, { ...config })] })] }) })] }));
};
export default ContactStiffnessDemoComponent;
