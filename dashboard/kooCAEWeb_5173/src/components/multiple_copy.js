import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useEffect, useRef, useState } from 'react';
import * as BABYLON from '@babylonjs/core';
import '@babylonjs/loaders';
import { Button, Space } from 'antd';
const MultipleStlViewerComponent = ({ models }) => {
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
                        const result = await BABYLON.SceneLoader.ImportMeshAsync(null, // meshNames
                        '', // rootUrl
                        url, // sceneFilename (여기에 실제 URL)
                        scene, // scene
                        undefined, // onProgress
                        '.stl' // pluginExtension (중요!)
                        );
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
                        baseMesh.refreshBoundingInfo();
                        const bounds = baseMesh.getBoundingInfo().boundingBox;
                        setMeshBounds(prev => ({
                            ...prev,
                            [url]: {
                                min: bounds.minimumWorld.clone(),
                                max: bounds.maximumWorld.clone(),
                            }
                        }));
                        meshCache[url] = baseMesh;
                    }
                    catch (err) {
                        console.error(`❌ ${url} 불러오기 실패:`, err);
                        continue;
                    }
                }
                for (let i = 0; i < positions.length; i++) {
                    const clone = meshCache[url].clone(`${url}_clone_${i}`, null);
                    clone.position = positions[i].clone();
                    clone.setEnabled(true);
                    allMeshes.push(clone);
                }
                for (let i = 0; i < positions.length; i++) {
                    const position = positions[i].clone();
                    const clone = baseMesh.clone(`${url}_clone_${i}`, null);
                    clone.position = position;
                    clone.setEnabled(true);
                    allMeshes.push(clone);
                    // ✅ 디버그용 위치 마커 추가
                    const debugSphere = BABYLON.MeshBuilder.CreateSphere(`debug_marker_${url}_${i}`, {
                        diameter: 0.001, // 매우 작은 마커 (단위 맞춰서 조절)
                    }, scene);
                    debugSphere.position = position;
                    const markerMat = new BABYLON.StandardMaterial(`debug_marker_mat_${i}`, scene);
                    markerMat.diffuseColor = BABYLON.Color3.Red();
                    debugSphere.material = markerMat;
                }
            }
            // 자동 카메라 보정
            if (allMeshes.length > 0) {
                const bounds = allMeshes.map(m => m.getBoundingInfo().boundingBox);
                const min = bounds.reduce((a, b) => BABYLON.Vector3.Minimize(a, b.minimumWorld), bounds[0].minimumWorld.clone());
                const max = bounds.reduce((a, b) => BABYLON.Vector3.Maximize(a, b.maximumWorld), bounds[0].maximumWorld.clone());
                const center = min.add(max).scale(0.5);
                const extent = max.subtract(min);
                const maxExtent = Math.max(extent.x, extent.y, extent.z) * 1.2;
                camera.setTarget(center);
                camera.orthoLeft = -maxExtent;
                camera.orthoRight = maxExtent;
                camera.orthoTop = maxExtent;
                camera.orthoBottom = -maxExtent;
                camera.radius = maxExtent * 4;
            }
            setLoading(false);
        };
        loadAndCloneMeshes();
        engine.runRenderLoop(() => scene.render());
        const handleResize = () => engine.resize();
        window.addEventListener('resize', handleResize);
        return () => {
            engine.dispose();
            window.removeEventListener('resize', handleResize);
        };
    }, [models]);
    const setCameraView = (view) => {
        const cam = cameraRef.current;
        if (!cam)
            return;
        // ✅ 전체 scene 기준 bounding box 계산
        const meshes = cam.getScene().meshes.filter(m => m.isVisible && m.getTotalVertices() > 0);
        if (meshes.length === 0)
            return;
        const boxes = meshes.map(m => m.getBoundingInfo().boundingBox);
        const min = boxes.reduce((a, b) => BABYLON.Vector3.Minimize(a, b.minimumWorld), boxes[0].minimumWorld.clone());
        const max = boxes.reduce((a, b) => BABYLON.Vector3.Maximize(a, b.maximumWorld), boxes[0].maximumWorld.clone());
        const center = min.add(max).scale(0.5);
        const extent = max.subtract(min);
        const maxExtent = Math.max(extent.x, extent.y, extent.z) * 1.2;
        // ✅ 방향 전환
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
        // ✅ 카메라 위치와 보기 범위 업데이트
        cam.setTarget(center);
        cam.orthoLeft = -maxExtent;
        cam.orthoRight = maxExtent;
        cam.orthoTop = maxExtent;
        cam.orthoBottom = -maxExtent;
        cam.radius = maxExtent * 4; // padding 여유
    };
    return (_jsxs("div", { style: { position: 'relative', width: '100%', height: '650px' }, children: [loading && (_jsx("div", { style: {
                    position: 'absolute', top: '50%', left: '50%',
                    transform: 'translate(-50%, -50%)',
                    fontSize: 20, color: '#555', zIndex: 1,
                    background: 'rgba(255, 255, 255, 0.8)',
                    padding: '1rem 2rem', borderRadius: 8,
                    boxShadow: '0 0 10px rgba(0,0,0,0.1)'
                }, children: "Loading STL models..." })), _jsx("div", { style: {
                    position: 'absolute', top: 10, right: 10,
                    zIndex: 2, background: 'white',
                    padding: '0.5rem', borderRadius: 8,
                    boxShadow: '0 0 5px rgba(0,0,0,0.2)'
                }, children: _jsxs(Space, { direction: "vertical", children: [_jsx(Button, { onClick: () => setCameraView('top'), children: "Top" }), _jsx(Button, { onClick: () => setCameraView('bottom'), children: "Bottom" }), _jsx(Button, { onClick: () => setCameraView('left'), children: "Left" }), _jsx(Button, { onClick: () => setCameraView('right'), children: "Right" }), _jsx(Button, { onClick: () => setCameraView('front'), children: "Front" }), _jsx(Button, { onClick: () => setCameraView('back'), children: "Back" })] }) }), _jsx("canvas", { ref: canvasRef, style: { width: '100%', height: '100%', display: 'block' } }), _jsxs("div", { style: { padding: '1rem', fontSize: '12px', background: '#f9f9f9' }, children: [_jsx("h3", { children: "\uD83D\uDCE6 STL \uBAA8\uB378 \uC694\uC57D \uC815\uBCF4" }), models.map((model, index) => (_jsxs("div", { style: { marginBottom: '1.5rem' }, children: [_jsx("strong", { children: model.url }), _jsxs("div", { style: { marginTop: '0.5rem' }, children: [_jsx("em", { children: "Positions & Bounding Boxes:" }), model.positions.map((pos, i) => {
                                        const bounds = meshBounds[model.url];
                                        if (!bounds)
                                            return null;
                                        const worldMin = bounds.min.add(pos);
                                        const worldMax = bounds.max.add(pos);
                                        return (_jsxs("div", { style: { paddingLeft: '1rem', marginBottom: '0.5rem' }, children: [_jsxs("div", { children: ["[", i, "] x: ", pos.x.toFixed(4), ", y: ", pos.y.toFixed(4), ", z: ", pos.z.toFixed(4)] }), _jsx("div", { style: { color: 'orange' }, children: "\uD83D\uDCCF \uC704\uCE58\uBCC4 Bounding Box:" }), _jsxs("div", { children: ["Min: ", [worldMin.x.toFixed(5), worldMin.y.toFixed(5), worldMin.z.toFixed(5)].join(', ')] }), _jsxs("div", { children: ["Max: ", [worldMax.x.toFixed(5), worldMax.y.toFixed(5), worldMax.z.toFixed(5)].join(', ')] })] }, i));
                                    })] }), meshBounds[model.url] && (_jsxs("div", { style: { marginTop: '0.5rem', paddingLeft: '1rem' }, children: [_jsx("div", { style: { color: 'green' }, children: "\uD83D\uDFE9 Base STL Bounding Box:" }), _jsxs("div", { children: ["Min: ", [meshBounds[model.url].min.x.toFixed(5), meshBounds[model.url].min.y.toFixed(5), meshBounds[model.url].min.z.toFixed(5)].join(', ')] }), _jsxs("div", { children: ["Max: ", [meshBounds[model.url].max.x.toFixed(5), meshBounds[model.url].max.y.toFixed(5), meshBounds[model.url].max.z.toFixed(5)].join(', ')] })] }))] }, index)))] })] }));
};
export default MultipleStlViewerComponent;
