import { jsx as _jsx, jsxs as _jsxs } from "react/jsx-runtime";
import { useEffect, useRef, useState } from 'react';
import * as BABYLON from '@babylonjs/core';
import '@babylonjs/loaders/glTF';
import { Slider, Button, Select } from 'antd';
const GltfViewerWithScalars = ({ glbFile, binFile }) => {
    const canvasRef = useRef(null);
    const sceneRef = useRef(null);
    const engineRef = useRef(null);
    const meshRef = useRef(null);
    const morphRef = useRef(null);
    const cameraRef = useRef(null);
    const maxExtentRef = useRef(1);
    const [loading, setLoading] = useState(true);
    const [scalarData, setScalarData] = useState(null);
    const [currentFrame, setCurrentFrame] = useState(0);
    const [frameRange, setFrameRange] = useState([0, 0]);
    const [currentScalar, setCurrentScalar] = useState(null);
    const [isPlaying, setIsPlaying] = useState(false);
    useEffect(() => {
        const run = async () => {
            setLoading(true);
            const canvas = canvasRef.current;
            const engine = new BABYLON.Engine(canvas, true, { preserveDrawingBuffer: true });
            engineRef.current = engine;
            const scene = new BABYLON.Scene(engine);
            sceneRef.current = scene;
            scene.clearColor = new BABYLON.Color4(1, 1, 1, 1);
            const camera = new BABYLON.ArcRotateCamera('camera', -Math.PI / 2, Math.PI / 2.5, 5, BABYLON.Vector3.Zero(), scene);
            camera.attachControl(canvas, true);
            cameraRef.current = camera;
            new BABYLON.HemisphericLight('light', new BABYLON.Vector3(0, 1, 0), scene).intensity = 1;
            // GLB 파일 → Blob URL 생성
            const arrayBuffer = await glbFile.arrayBuffer();
            const blob = new Blob([arrayBuffer], {
                type: "model/gltf-binary"
            });
            const objectUrl = URL.createObjectURL(blob);
            await BABYLON.SceneLoader.ImportMeshAsync(null, '', objectUrl, scene, undefined, ".glb").then((result) => {
                const mesh = result.meshes.find(m => m instanceof BABYLON.Mesh);
                if (!mesh) {
                    console.error("Mesh not found in GLB!");
                    return;
                }
                meshRef.current = mesh;
                morphRef.current = mesh.morphTargetManager || null;
                const bbox = mesh.getBoundingInfo().boundingBox;
                const center = bbox.minimumWorld.add(bbox.maximumWorld).scale(0.5);
                const size = bbox.maximumWorld.subtract(bbox.minimumWorld);
                const maxExtent = Math.max(size.x, size.y, size.z);
                maxExtentRef.current = maxExtent;
                camera.setTarget(center);
                // ✅ 작은 모델 대응 로직
                let radius = maxExtent * 2;
                if (radius < 0.1)
                    radius = 0.1;
                camera.radius = radius;
                camera.lowerRadiusLimit = radius * 0.3;
                camera.upperRadiusLimit = radius * 10;
                camera.inertia = 0.5;
                camera.panningInertia = 0.5;
                camera.wheelPrecision = 50;
                camera.minZ = radius / 1000;
                camera.maxZ = radius * 50;
                // bin 파일 있으면 파싱
                if (binFile) {
                    loadScalarBin(binFile).then((data) => {
                        setScalarData(data);
                        setCurrentScalar(data.names[0]);
                        setFrameRange([0, data.frames.length - 1]);
                        setLoading(false);
                    });
                }
                else {
                    setLoading(false);
                }
            }).catch(err => {
                console.error("GLB Load failed:", err);
            });
            engine.runRenderLoop(() => {
                if (scene) {
                    scene.render();
                }
            });
            const resize = () => engine.resize();
            window.addEventListener("resize", resize);
            return () => {
                engine.dispose();
                window.removeEventListener("resize", resize);
            };
        };
        run();
    }, [glbFile, binFile]);
    useEffect(() => {
        let interval;
        if (isPlaying) {
            interval = window.setInterval(() => {
                setCurrentFrame((prev) => {
                    const next = prev + 1;
                    if (scalarData && next > scalarData.frames.length - 1) {
                        setIsPlaying(false);
                        return 0;
                    }
                    updateVisualization(next, currentScalar);
                    return next;
                });
            }, 200);
        }
        return () => {
            if (interval)
                clearInterval(interval);
        };
    }, [isPlaying, scalarData, currentScalar]);
    const onFrameChange = (value) => {
        setCurrentFrame(value);
        updateVisualization(value, currentScalar);
        setIsPlaying(false);
    };
    const togglePlay = () => {
        setIsPlaying(!isPlaying);
    };
    const updateVisualization = (frame, scalarName) => {
        if (!scalarData || !meshRef.current)
            return;
        const mesh = meshRef.current;
        if (morphRef.current) {
            for (let i = 0; i < morphRef.current.numTargets; i++) {
                morphRef.current.getTarget(i).influence = (i === frame - 1) ? 1.0 : 0.0;
            }
        }
        if (!scalarName)
            return;
        const scalarIndex = scalarData.names.indexOf(scalarName);
        if (scalarIndex === -1)
            return;
        const scalars = scalarData.frames[frame][scalarIndex];
        const colors = new Float32Array(scalars.length * 4);
        const min = Math.min(...scalars);
        const max = Math.max(...scalars);
        const range = max - min || 1;
        for (let i = 0; i < scalars.length; i++) {
            const norm = (scalars[i] - min) / range;
            const [r, g, b] = computeColorFromScalar(norm);
            colors.set([r, g, b, 1.0], i * 4);
        }
        mesh.setVerticesData(BABYLON.VertexBuffer.ColorKind, colors, true);
    };
    const onScalarChange = (value) => {
        setCurrentScalar(value);
        updateVisualization(currentFrame, value);
    };
    const setView = (view) => {
        if (!cameraRef.current)
            return;
        const camera = cameraRef.current;
        const radius = maxExtentRef.current * 2 || 2;
        switch (view) {
            case "Front":
                camera.alpha = 0;
                camera.beta = Math.PI / 2;
                break;
            case "Back":
                camera.alpha = Math.PI;
                camera.beta = Math.PI / 2;
                break;
            case "Left":
                camera.alpha = -Math.PI / 2;
                camera.beta = Math.PI / 2;
                break;
            case "Right":
                camera.alpha = Math.PI / 2;
                camera.beta = Math.PI / 2;
                break;
            case "Top":
                camera.alpha = 0;
                camera.beta = 0.01;
                break;
            case "Bottom":
                camera.alpha = 0;
                camera.beta = Math.PI - 0.01;
                break;
        }
        camera.radius = radius;
    };
    return (_jsxs("div", { style: { width: '100%', height: '700px', position: 'relative' }, children: [loading && (_jsx("div", { style: {
                    position: 'absolute', top: '50%', left: '50%',
                    transform: 'translate(-50%, -50%)', fontSize: 20, zIndex: 1,
                    background: 'rgba(255,255,255,0.8)', padding: '1rem 2rem', borderRadius: 8
                }, children: "Loading..." })), _jsx("canvas", { ref: canvasRef, style: { width: '100%', height: '600px', display: 'block' } }), !loading && scalarData && (_jsxs("div", { style: { padding: '12px 24px' }, children: [_jsx(Select, { style: { width: 200, marginRight: 16 }, value: currentScalar, onChange: onScalarChange, children: scalarData?.names.map(name => (_jsx(Select.Option, { value: name, children: name }, name))) }), _jsx(Slider, { min: frameRange[0], max: frameRange[1], value: currentFrame, onChange: onFrameChange }), _jsx(Button, { onClick: togglePlay, style: { marginTop: 12 }, children: isPlaying ? '⏸ Pause' : '▶ Play' }), _jsx("div", { style: { marginTop: 12 }, children: ["Front", "Back", "Left", "Right", "Top", "Bottom"].map((dir) => (_jsx(Button, { onClick: () => setView(dir), style: { marginRight: 8, marginTop: 8 }, children: dir }, dir))) })] }))] }));
};
export default GltfViewerWithScalars;
function computeColorFromScalar(value) {
    return [value, 0.5 * (1 - value), 1 - value];
}
async function loadScalarBin(file) {
    const buf = await file.arrayBuffer();
    const view = new DataView(buf);
    let offset = 0;
    const scalarCount = view.getUint32(offset, true);
    offset += 4;
    const names = [];
    for (let i = 0; i < scalarCount; i++) {
        const len = view.getUint32(offset, true);
        offset += 4;
        let name = "";
        for (let j = 0; j < len; j++) {
            name += String.fromCharCode(view.getUint8(offset++));
        }
        names.push(name);
    }
    const frameCount = view.getUint32(offset, true);
    offset += 4;
    const vertCount = view.getUint32(offset, true);
    offset += 4;
    const frames = [];
    for (let t = 0; t < frameCount; t++) {
        const frame = [];
        for (let s = 0; s < scalarCount; s++) {
            const arr = new Float32Array(buf, offset, vertCount);
            frame.push(arr);
            offset += vertCount * 4;
        }
        frames.push(frame);
    }
    return { names, frames };
}
