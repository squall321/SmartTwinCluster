import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useEffect, useRef, useState } from 'react';
import * as BABYLON from '@babylonjs/core';
import '@babylonjs/loaders';
import { Button, Typography } from 'antd';
const { Title, Paragraph } = Typography;
const HeroSection = () => {
    const canvasRef = useRef(null);
    const [loading, setLoading] = useState(true);
    useEffect(() => {
        const canvas = canvasRef.current;
        if (!canvas)
            return;
        const engine = new BABYLON.Engine(canvas, true);
        const scene = new BABYLON.Scene(engine);
        const camera = new BABYLON.ArcRotateCamera('camera', -Math.PI / 2, Math.PI / 2.5, 5, BABYLON.Vector3.Zero(), scene);
        camera.attachControl(canvas, true);
        const light = new BABYLON.HemisphericLight('light', new BABYLON.Vector3(0, 1, 0), scene);
        light.intensity = 1;
        BABYLON.SceneLoader.Append('/models/', 'smartphone.glb', scene, () => {
            const meshes = scene.meshes.filter((m) => m.name !== '__root__');
            if (meshes.length > 0) {
                const bounds = meshes.map((m) => m.getBoundingInfo().boundingBox);
                const min = bounds.map((b) => b.minimumWorld).reduce((a, b) => BABYLON.Vector3.Minimize(a, b));
                const max = bounds.map((b) => b.maximumWorld).reduce((a, b) => BABYLON.Vector3.Maximize(a, b));
                const center = min.add(max).scale(0.5);
                const size = max.subtract(min);
                const maxExtent = Math.max(size.x, size.y, size.z);
                // 모델 중심 이동 및 스케일 조정
                const desiredSize = 1.0;
                const scaleFactor = maxExtent < 1e-6 ? 1.0 : desiredSize / maxExtent;
                meshes.forEach((mesh) => {
                    mesh.position.subtractInPlace(center);
                    mesh.scaling.scaleInPlace(scaleFactor);
                });
                camera.setTarget(BABYLON.Vector3.Zero());
                camera.radius = desiredSize * 2;
            }
            scene.animationGroups.forEach((group) => group.start(true));
            setLoading(false);
        });
        engine.runRenderLoop(() => scene.render());
        const handleResize = () => engine.resize();
        window.addEventListener('resize', handleResize);
        return () => {
            scene.dispose();
            engine.dispose();
            window.removeEventListener('resize', handleResize);
        };
    }, []);
    return (_jsxs("div", { style: { position: 'relative', height: '100vh', overflow: 'hidden' }, children: [loading && (_jsx("div", { style: {
                    position: 'absolute', top: '50%', left: '50%', transform: 'translate(-50%, -50%)',
                    background: 'rgba(255,255,255,0.8)', padding: 20, borderRadius: 8, zIndex: 10
                }, children: "Loading..." })), _jsx("canvas", { ref: canvasRef, style: { width: '100%', height: '100%' } }), _jsxs("div", { style: {
                    position: 'absolute',
                    top: '30%',
                    left: '10%',
                    zIndex: 2,
                    color: 'white',
                    maxWidth: '600px'
                }, children: [_jsx(Title, { level: 1, style: { color: 'white' }, children: "\uB514\uC9C0\uD138 \uD2B8\uC708\uC73C\uB85C \uBBF8\uB798\uB97C \uC124\uACC4\uD558\uB2E4" }), _jsx(Paragraph, { style: { color: 'white', fontSize: '18px' }, children: "\uC2A4\uB9C8\uD2B8\uD3F0\uC758 \uB099\uD558, \uCDA9\uACA9, \uC5F4\uD658\uACBD\uC744 \uAC00\uC0C1 \uC2DC\uBBAC\uB808\uC774\uC158\uC73C\uB85C \uC608\uCE21\uD569\uB2C8\uB2E4." }), _jsxs("div", { style: { marginTop: 20 }, children: [_jsx(Button, { type: "primary", size: "large", style: { marginRight: 10 }, children: "\uC2DC\uBBAC\uB808\uC774\uC158 \uCCB4\uD5D8\uD558\uAE30" }), _jsx(Button, { ghost: true, size: "large", children: "\uC790\uC138\uD788 \uBCF4\uAE30" })] })] })] }));
};
export default HeroSection;
