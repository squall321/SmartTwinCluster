import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useEffect, useRef, useState } from 'react';
import * as BABYLON from '@babylonjs/core';
import '@babylonjs/loaders';
import { Button, Space } from 'antd';
const MultipleStlViewerComponent = ({ models, viewDirection = 'front' }) => {
    const canvasRef = useRef(null);
    const cameraRef = useRef(null);
    const [loading, setLoading] = useState(true);
    const [meshBounds, setMeshBounds] = useState({});
    useEffect(() => {
        if (!models || models.length === 0)
            return;
        setLoading(true);
        const canvas = canvasRef.current;
        const engine = new BABYLON.Engine(canvas, true, { preserveDrawingBuffer: true });
        const scene = new BABYLON.Scene(engine);
        scene.clearColor = new BABYLON.Color4(1, 1, 1, 1);
        const camera = new BABYLON.ArcRotateCamera('camera', -Math.PI / 4, Math.PI / 4, 100, BABYLON.Vector3.Zero(), scene);
        camera.mode = BABYLON.Camera.ORTHOGRAPHIC_CAMERA;
        camera.attachControl(canvas, true);
        camera.panningSensibility = 1000;
        cameraRef.current = camera;
        new BABYLON.HemisphericLight('light1', new BABYLON.Vector3(0, 1, 0), scene).intensity = 0.6;
        new BABYLON.HemisphericLight('light2', new BABYLON.Vector3(0, -1, 0), scene).intensity = 0.4;
        const allMeshes = [];
        const loadAndCloneMeshes = async () => {
            const meshCache = {};
            for (const { url, positions } of models) {
                let baseMesh;
                if (meshCache[url]) {
                    baseMesh = meshCache[url];
                }
                else {
                    try {
                        const result = await BABYLON.SceneLoader.ImportMeshAsync(null, '', url, scene, undefined, '.stl');
                        if (result.meshes.length === 0)
                            continue;
                        baseMesh = result.meshes[0];
                        baseMesh.setEnabled(false);
                        baseMesh.forceSharedVertices();
                        baseMesh.convertToFlatShadedMesh();
                        baseMesh.refreshBoundingInfo();
                        const mat = new BABYLON.PBRMetallicRoughnessMaterial(`mat_${url}`, scene);
                        mat.baseColor = new BABYLON.Color3(0.3, 0.7, 0.9);
                        mat.metallic = 0.6;
                        mat.roughness = 0.4;
                        baseMesh.material = mat;
                        const bounds = baseMesh.getBoundingInfo().boundingBox;
                        const center = bounds.centerWorld.clone();
                        setMeshBounds(prev => ({ ...prev, [url]: { min: bounds.minimumWorld.clone(), max: bounds.maximumWorld.clone(), center } }));
                        meshCache[url] = baseMesh;
                    }
                    catch (err) {
                        console.error(`❌ ${url} 불러오기 실패:`, err);
                        continue;
                    }
                }
                const bounds = meshBounds[url];
                const center = bounds?.center || baseMesh.getBoundingInfo().boundingBox.centerWorld;
                positions.forEach((absPos, i) => {
                    const correctedPos = absPos.clone();
                    const clone = meshCache[url].clone(`${url}_clone_${i}`, null);
                    clone.position = correctedPos.subtract(center);
                    clone.setEnabled(true);
                    allMeshes.push(clone);
                    const debugSphere = BABYLON.MeshBuilder.CreateSphere(`debug_${url}_${i}`, { diameter: 0.001 }, scene);
                    debugSphere.position = absPos.clone();
                    const m = new BABYLON.StandardMaterial(`dbgMat_${i}`, scene);
                    m.diffuseColor = BABYLON.Color3.Red();
                    debugSphere.material = m;
                });
            }
            if (allMeshes.length > 0) {
                const boxes = allMeshes.map(m => m.getBoundingInfo().boundingBox);
                const min = boxes.reduce((a, b) => BABYLON.Vector3.Minimize(a, b.minimumWorld), boxes[0].minimumWorld.clone());
                const max = boxes.reduce((a, b) => BABYLON.Vector3.Maximize(a, b.maximumWorld), boxes[0].maximumWorld.clone());
                const center = min.add(max).scale(0.5);
                const size = max.subtract(min);
                const maxExtent = Math.max(size.x, size.y, size.z) * 1.2;
                if (viewDirection) {
                    switch (viewDirection) {
                        case 'top':
                            camera.alpha = 0;
                            camera.beta = 0.01; // ✅ 버튼 클릭과 동일하게
                            break;
                        case 'bottom':
                            camera.alpha = 0;
                            camera.beta = Math.PI - 0.01;
                            break;
                        case 'left':
                            camera.alpha = -Math.PI / 2;
                            camera.beta = Math.PI / 2;
                            break;
                        case 'right':
                            camera.alpha = Math.PI / 2;
                            camera.beta = Math.PI / 2;
                            break;
                        case 'front':
                            camera.alpha = 0;
                            camera.beta = Math.PI / 2;
                            break;
                        case 'back':
                            camera.alpha = Math.PI;
                            camera.beta = Math.PI / 2;
                            break;
                    }
                }
                else {
                    // 기본 등각 뷰
                    camera.alpha = -Math.PI / 4;
                    camera.beta = Math.PI / 4;
                }
                camera.setTarget(center);
                camera.orthoLeft = -maxExtent;
                camera.orthoRight = maxExtent;
                camera.orthoTop = maxExtent;
                camera.orthoBottom = -maxExtent;
                camera.radius = maxExtent * 4;
                camera.rebuildAnglesAndRadius(); // optional
            }
            setLoading(false);
            camera.rebuildAnglesAndRadius(); // optional
        };
        loadAndCloneMeshes();
        engine.runRenderLoop(() => scene.render());
        const resize = () => engine.resize();
        window.addEventListener('resize', resize);
        return () => {
            engine.dispose();
            window.removeEventListener('resize', resize);
        };
    }, [models]);
    const setCameraView = (view) => {
        const cam = cameraRef.current;
        if (!cam)
            return;
        const meshes = cam.getScene().meshes.filter(m => m.isVisible && m.getTotalVertices() > 0);
        if (meshes.length === 0)
            return;
        const boxes = meshes.map(m => m.getBoundingInfo().boundingBox);
        const min = boxes.reduce((a, b) => BABYLON.Vector3.Minimize(a, b.minimumWorld), boxes[0].minimumWorld.clone());
        const max = boxes.reduce((a, b) => BABYLON.Vector3.Maximize(a, b.maximumWorld), boxes[0].maximumWorld.clone());
        const center = min.add(max).scale(0.5);
        const extent = max.subtract(min);
        const maxExtent = Math.max(extent.x, extent.y, extent.z) * 1.2;
        switch (view) {
            case 'top':
                cam.alpha = 0;
                cam.beta = 0.01;
                break;
            case 'bottom':
                cam.alpha = 0;
                cam.beta = Math.PI - 0.01;
                break;
            case 'left':
                cam.alpha = -Math.PI / 2;
                cam.beta = Math.PI / 2;
                break;
            case 'right':
                cam.alpha = Math.PI / 2;
                cam.beta = Math.PI / 2;
                break;
            case 'front':
                cam.alpha = 0;
                cam.beta = Math.PI / 2;
                break;
            case 'back':
                cam.alpha = Math.PI;
                cam.beta = Math.PI / 2;
                break;
        }
        cam.orthoLeft = -maxExtent;
        cam.orthoRight = maxExtent;
        cam.orthoTop = maxExtent;
        cam.orthoBottom = -maxExtent;
        cam.radius = maxExtent * 4;
        cam.setTarget(center);
    };
    return (_jsxs("div", { style: { position: 'relative', width: '100%', height: '650px' }, children: [loading && (_jsx("div", { style: { position: 'absolute', top: '50%', left: '50%', transform: 'translate(-50%, -50%)', fontSize: 20, color: '#555', zIndex: 1, background: 'rgba(255, 255, 255, 0.8)', padding: '1rem 2rem', borderRadius: 8, boxShadow: '0 0 10px rgba(0,0,0,0.1)' }, children: "Loading STL models..." })), _jsx("div", { style: { position: 'absolute', top: 10, right: 10, zIndex: 2, background: '#fff', padding: 8, borderRadius: 8, boxShadow: '0 0 5px rgba(0,0,0,0.2)' }, children: _jsxs(Space, { direction: "vertical", children: [_jsx(Button, { onClick: () => setCameraView('top'), children: "Top" }), _jsx(Button, { onClick: () => setCameraView('bottom'), children: "Bottom" }), _jsx(Button, { onClick: () => setCameraView('left'), children: "Left" }), _jsx(Button, { onClick: () => setCameraView('right'), children: "Right" }), _jsx(Button, { onClick: () => setCameraView('front'), children: "Front" }), _jsx(Button, { onClick: () => setCameraView('back'), children: "Back" })] }) }), _jsx("canvas", { ref: canvasRef, style: { width: '100%', height: '100%', display: 'block' } })] }));
};
export default MultipleStlViewerComponent;
