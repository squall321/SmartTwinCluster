import React, { useEffect, useRef, useState } from 'react';
import * as BABYLON from '@babylonjs/core';
import '@babylonjs/loaders';
import { Button, Space } from 'antd';

interface StlWithPositions {
  url: string;
  positions: BABYLON.Vector3[];
}

interface MultipleStlViewerProps {
    models: StlWithPositions[];
    viewDirection?: 'top' | 'bottom' | 'left' | 'right' | 'front' | 'back';
  }

const MultipleStlViewerComponent: React.FC<MultipleStlViewerProps> = ({ models, viewDirection = 'front' }) => {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const cameraRef = useRef<BABYLON.ArcRotateCamera | null>(null);
  const [loading, setLoading] = useState(true);
  const [meshBounds, setMeshBounds] = useState<Record<string, { min: BABYLON.Vector3; max: BABYLON.Vector3; center: BABYLON.Vector3 }>>({});

  useEffect(() => {
    if (!models || models.length === 0) return;

    setLoading(true);
    const canvas = canvasRef.current!;
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

    const allMeshes: BABYLON.AbstractMesh[] = [];

    const loadAndCloneMeshes = async () => {
      const meshCache: Record<string, BABYLON.Mesh> = {};

      for (const { url, positions } of models) {
        let baseMesh: BABYLON.Mesh;

        if (meshCache[url]) {
          baseMesh = meshCache[url];
        } else {
          try {
            const result = await BABYLON.SceneLoader.ImportMeshAsync(null, '', url, scene, undefined, '.stl');
            if (result.meshes.length === 0) continue;

            baseMesh = result.meshes[0] as BABYLON.Mesh;
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
          } catch (err) {
            console.error(`❌ ${url} 불러오기 실패:`, err);
            continue;
          }
        }

        const bounds = meshBounds[url];
        const center = bounds?.center || baseMesh.getBoundingInfo().boundingBox.centerWorld;

        positions.forEach((absPos, i) => {
          const correctedPos = absPos.clone();
          const clone = meshCache[url].clone(`${url}_clone_${i}`, null)!;
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
          } else {
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

  const setCameraView = (view: 'top' | 'bottom' | 'left' | 'right' | 'front' | 'back') => {
    const cam = cameraRef.current;
    if (!cam) return;

    const meshes = cam.getScene().meshes.filter(m => m.isVisible && m.getTotalVertices() > 0);
    if (meshes.length === 0) return;

    const boxes = meshes.map(m => m.getBoundingInfo().boundingBox);
    const min = boxes.reduce((a, b) => BABYLON.Vector3.Minimize(a, b.minimumWorld), boxes[0].minimumWorld.clone());
    const max = boxes.reduce((a, b) => BABYLON.Vector3.Maximize(a, b.maximumWorld), boxes[0].maximumWorld.clone());
    const center = min.add(max).scale(0.5);
    const extent = max.subtract(min);
    const maxExtent = Math.max(extent.x, extent.y, extent.z) * 1.2;

    switch (view) {
      case 'top': cam.alpha = 0; cam.beta = 0.01; break;
      case 'bottom': cam.alpha = 0; cam.beta = Math.PI - 0.01; break;
      case 'left': cam.alpha = -Math.PI / 2; cam.beta = Math.PI / 2; break;
      case 'right': cam.alpha = Math.PI / 2; cam.beta = Math.PI / 2; break;
      case 'front': cam.alpha = 0; cam.beta = Math.PI / 2; break;
      case 'back': cam.alpha = Math.PI; cam.beta = Math.PI / 2; break;
    }

    
    cam.orthoLeft = -maxExtent;
    cam.orthoRight = maxExtent;
    cam.orthoTop = maxExtent;
    cam.orthoBottom = -maxExtent;
    cam.radius = maxExtent * 4;
    cam.setTarget(center);
  };

  return (
    <div style={{ position: 'relative', width: '100%', height: '650px' }}>
      {loading && (
        <div style={{ position: 'absolute', top: '50%', left: '50%', transform: 'translate(-50%, -50%)', fontSize: 20, color: '#555', zIndex: 1, background: 'rgba(255, 255, 255, 0.8)', padding: '1rem 2rem', borderRadius: 8, boxShadow: '0 0 10px rgba(0,0,0,0.1)' }}>
          Loading STL models...
        </div>
      )}

      <div style={{ position: 'absolute', top: 10, right: 10, zIndex: 2, background: '#fff', padding: 8, borderRadius: 8, boxShadow: '0 0 5px rgba(0,0,0,0.2)' }}>
        <Space direction="vertical">
          <Button onClick={() => setCameraView('top')}>Top</Button>
          <Button onClick={() => setCameraView('bottom')}>Bottom</Button>
          <Button onClick={() => setCameraView('left')}>Left</Button>
          <Button onClick={() => setCameraView('right')}>Right</Button>
          <Button onClick={() => setCameraView('front')}>Front</Button>
          <Button onClick={() => setCameraView('back')}>Back</Button>
        </Space>
      </div>

      <canvas ref={canvasRef} style={{ width: '100%', height: '100%', display: 'block' }} />

      {/*
      
      <div style={{ padding: '1rem', fontSize: '12px', background: '#f9f9f9' }}>
        <h3>📦 STL 모델 요약 정보</h3>
        {models.map((model, index) => (
          <div key={index} style={{ marginBottom: '1.5rem' }}>
            <strong>{model.url}</strong>
            <div style={{ marginTop: '0.5rem' }}>
              <em>Positions & Bounding Boxes:</em>
              {model.positions.map((pos, i) => {
                const bounds = meshBounds[model.url];
                if (!bounds) return null;
                const worldMin = bounds.min.add(pos);
                const worldMax = bounds.max.add(pos);
                const worldCenter = worldMin.add(worldMax).scale(0.5);
                return (
                  <div key={i} style={{ paddingLeft: '1rem', marginBottom: '0.5rem' }}>
                    <div>[{i}] x: {pos.x.toFixed(4)}, y: {pos.y.toFixed(4)}, z: {pos.z.toFixed(4)}</div>
                    <div style={{ color: 'orange' }}>📏 위치별 Bounding Box:</div>
                    <div>Min: {[worldMin.x.toFixed(5), worldMin.y.toFixed(5), worldMin.z.toFixed(5)].join(', ')}</div>
                    <div>Max: {[worldMax.x.toFixed(5), worldMax.y.toFixed(5), worldMax.z.toFixed(5)].join(', ')}</div>
                    <div>Center: {[worldCenter.x.toFixed(5), worldCenter.y.toFixed(5), worldCenter.z.toFixed(5)].join(', ')}</div>
                  </div>
                );
              })}
            </div>
            {meshBounds[model.url] && (
              <div style={{ marginTop: '0.5rem', paddingLeft: '1rem' }}>
                <div style={{ color: 'green' }}>🟩 Base STL Bounding Box:</div>
                <div>
                  Min: {[meshBounds[model.url].min.x.toFixed(5), meshBounds[model.url].min.y.toFixed(5), meshBounds[model.url].min.z.toFixed(5)].join(', ')}
                </div>
                <div>
                  Max: {[meshBounds[model.url].max.x.toFixed(5), meshBounds[model.url].max.y.toFixed(5), meshBounds[model.url].max.z.toFixed(5)].join(', ')}
                </div>
                <div>
                  Center: {[meshBounds[model.url].center.x.toFixed(5), meshBounds[model.url].center.y.toFixed(5), meshBounds[model.url].center.z.toFixed(5)].join(', ')}
                </div>
              </div>
            )}
          </div>
        ))}
      </div>
      
      */}
    </div>
  );
};

export default MultipleStlViewerComponent;
