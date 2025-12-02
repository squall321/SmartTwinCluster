import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useEffect, useRef, useState } from 'react';
import * as BABYLON from '@babylonjs/core';
import '@babylonjs/loaders';
import { Slider } from 'antd';
import { GridMaterial } from '@babylonjs/materials';
const GLBDynamicViewerComponent = ({ file, autoScale = true, // 🔹 기본값은 true
 }) => {
    const canvasRef = useRef(null);
    const [loading, setLoading] = useState(true);
    const [morphTargets, setMorphTargets] = useState([]);
    const [morphWeights, setMorphWeights] = useState([]);
    useEffect(() => {
        if (!file || !canvasRef.current)
            return;
        const blobUrl = URL.createObjectURL(file);
        const canvas = canvasRef.current;
        const engine = new BABYLON.Engine(canvas, true);
        const scene = new BABYLON.Scene(engine);
        scene.clearColor = new BABYLON.Color4(0.92, 0.92, 0.92, 1.0);
        const camera = new BABYLON.ArcRotateCamera('camera', -Math.PI / 2, Math.PI / 2.5, 5, BABYLON.Vector3.Zero(), scene);
        camera.attachControl(canvas, true);
        setupSceneHelpers(scene);
        loadGLBModel(blobUrl, scene, camera);
        const resizeHandler = () => engine.resize();
        window.addEventListener('resize', resizeHandler);
        engine.runRenderLoop(() => {
            scene.render();
        });
        return () => {
            scene.dispose();
            engine.dispose();
            window.removeEventListener('resize', resizeHandler);
            URL.revokeObjectURL(blobUrl);
        };
    }, [file, autoScale]);
    const setupSceneHelpers = (scene) => {
        const hemiLight = new BABYLON.HemisphericLight('hemi', new BABYLON.Vector3(0, 1, 0), scene);
        hemiLight.intensity = 0.6;
        const dirLight = new BABYLON.DirectionalLight('dir', new BABYLON.Vector3(-1, -2, -1), scene);
        dirLight.position = new BABYLON.Vector3(5, 10, 5);
        dirLight.intensity = 0.5;
        const ground = BABYLON.MeshBuilder.CreateGround('ground', { width: 10, height: 10, subdivisions: 20 }, scene);
        const grid = new GridMaterial('grid', scene);
        grid.gridRatio = 1;
        grid.majorUnitFrequency = 5;
        grid.minorUnitVisibility = 0.45;
        grid.lineColor = new BABYLON.Color3(0.75, 0.75, 0.75);
        ground.material = grid;
        ground.position.y = -0.5;
        grid.opacity = 0.7;
        const showAxis = (size) => {
            const makeAxis = (name, color, dir) => {
                const axis = BABYLON.MeshBuilder.CreateLines(name, { points: [BABYLON.Vector3.Zero(), dir.scale(size)], colors: [color.toColor4(), color.toColor4()] }, scene);
                axis.isPickable = false;
            };
            makeAxis('X', BABYLON.Color3.Red(), new BABYLON.Vector3(1, 0, 0));
            makeAxis('Y', BABYLON.Color3.Green(), new BABYLON.Vector3(0, 1, 0));
            makeAxis('Z', BABYLON.Color3.Blue(), new BABYLON.Vector3(0, 0, 1));
        };
        showAxis(1.5);
    };
    const loadGLBModel = async (url, scene, camera) => {
        try {
            setLoading(true);
            await BABYLON.SceneLoader.AppendAsync('', url, scene, undefined, '.glb');
            scene.meshes.forEach((m, i) => {
                console.log(`Mesh[${i}] name="${m.name}" vertices=${m.getTotalVertices()}`);
            });
            const renderMeshes = scene.meshes.filter((m) => m.getTotalVertices() > 0 && !['ground', 'X', 'Y', 'Z'].includes(m.name));
            if (renderMeshes.length === 0) {
                console.warn('🚫 No valid renderable meshes found in the scene.');
                return;
            }
            // 계산
            const bounds = renderMeshes.map((m) => m.getBoundingInfo().boundingBox);
            const min = bounds.map((b) => b.minimumWorld).reduce(BABYLON.Vector3.Minimize);
            const max = bounds.map((b) => b.maximumWorld).reduce(BABYLON.Vector3.Maximize);
            const center = min.add(max).scale(0.5);
            const size = max.subtract(min);
            const maxExtent = Math.max(size.x, size.y, size.z);
            const scaleFactor = maxExtent < 1e-6 ? 1.0 : 1.0 / maxExtent;
            // 공통 parent 노드
            const parentNode = new BABYLON.TransformNode('modelRoot', scene);
            renderMeshes.forEach((mesh) => mesh.setParent(parentNode));
            // 중심 이동
            parentNode.position = center.scale(-1);
            // 자동 스케일 조정 (옵션)
            if (autoScale) {
                parentNode.scaling.scaleInPlace(scaleFactor);
            }
            // 카메라 설정
            const finalSize = autoScale ? 1.0 : maxExtent;
            camera.setTarget(BABYLON.Vector3.Zero());
            camera.radius = finalSize * 1.5;
            camera.lowerRadiusLimit = finalSize * 0.1;
            camera.upperRadiusLimit = finalSize * 10;
            // Morph Targets
            const foundTargets = [];
            renderMeshes.forEach((mesh) => {
                const mManager = mesh.morphTargetManager;
                if (mManager) {
                    for (let i = 0; i < mManager.numTargets; i++) {
                        const target = mManager.getTarget(i);
                        foundTargets.push(target);
                    }
                }
            });
            setMorphTargets(foundTargets);
            setMorphWeights(foundTargets.map((t) => t.influence));
            scene.animationGroups.forEach((group) => group.start(true));
            setLoading(false);
        }
        catch (err) {
            console.error('❌ GLB Load error:', err);
            setLoading(false);
        }
    };
    const handleSliderChange = (value, index) => {
        setMorphWeights((prev) => {
            const next = [...prev];
            next[index] = value;
            if (morphTargets[index])
                morphTargets[index].influence = value;
            return next;
        });
    };
    return (_jsxs("div", { style: { width: '100%', height: '600px', position: 'relative' }, children: [loading && (_jsx("div", { style: {
                    position: 'absolute',
                    top: '50%',
                    left: '50%',
                    transform: 'translate(-50%, -50%)',
                    background: 'rgba(255,255,255,0.8)',
                    padding: 20,
                    borderRadius: 8,
                    boxShadow: '0 0 10px rgba(0,0,0,0.2)',
                }, children: "Loading..." })), _jsx("canvas", { ref: canvasRef, style: { width: '100%', height: '100%' } }), !loading && morphTargets.length > 0 && (_jsxs("div", { style: {
                    position: 'absolute',
                    top: 10,
                    right: 10,
                    background: 'rgba(255,255,255,0.9)',
                    padding: 10,
                    borderRadius: 8,
                    maxHeight: '90%',
                    overflowY: 'auto',
                }, children: [_jsx("h4", { style: { marginBottom: 8 }, children: "Morph Targets" }), morphTargets.map((target, i) => (_jsxs("div", { style: { marginBottom: 12 }, children: [_jsx("div", { style: { fontSize: 12, marginBottom: 4 }, children: target.name || `Target ${i}` }), _jsx(Slider, { min: 0, max: 1, step: 0.01, value: morphWeights[i], onChange: (v) => handleSliderChange(v, i) })] }, target.name || i)))] }))] }));
};
export default GLBDynamicViewerComponent;
